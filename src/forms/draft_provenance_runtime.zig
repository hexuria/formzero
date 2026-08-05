//! SQLite-backed preparation of exact immutable draft provenance.
//!
//! This is the read-only runtime boundary between an accepted coarse form
//! state and the pure `draft_provenance_adapter`. It resolves every mutable
//! source on the filing applicability date, rejects non-authoritative Forms
//! Set decisions, and never appends a draft or invents transaction defaults.

const std = @import("std");
const adapter = @import("draft_provenance_adapter.zig");
const draft_persistence = @import("persistence_adapter.zig");
const provenance = @import("draft_provenance.zig");
const filing_period = @import("filing_period.zig");
const ids = @import("id.zig");
const runtime = @import("runtime.zig");
const ui_state = @import("ui_state.zig");
const catalog = @import("generated/catalog.zig");
const forms_set_history = @import("../tax_profile/forms_set_history.zig");
const forms_set_resolver = @import("../tax_profile/forms_set_resolver.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");
const profile_editor = @import("../tax_profile/editor.zig");
const profile_persistence = @import("../tax_profile/persistence_adapter.zig");
const store_module = @import("../tax_profile/store.zig");
const tax_form_profile = @import("../tax_profile/tax_form_profile.zig");
const taxpayer_year = @import("../tax_profile/taxpayer_year_settings.zig");

pub const Error = error{
    CalendarOnlyForm,
    DefinitionIsNotGeneratedCatalogEntry,
    MissingFormRevision,
    FormStateNotOpen,
    FormStateAlreadyPersisted,
    FormStateProjectionRejected,
    OpenedFormMismatch,
    FilingPeriodMismatch,
    MissingFilerBinding,
    UnsupportedProfileRole,
    MissingProfileRevision,
    ProfileRevisionBindingMismatch,
    MissingFormsSetDecision,
    InactiveFormsSetDecision,
    FormsSetDecisionRequiresReview,
    NonAuthoritativeFormsSetDecision,
    MissingActiveFormsSetSegment,
};

/// Owns the history backing the exact Forms Set decision pointer. `Composition`
/// is fixed-storage and remains valid after other loaded histories are
/// released inside `prepare`.
pub const OwnedComposition = struct {
    composition: adapter.Composition,
    exact_forms_set: profile_persistence.OwnedFormSetDecisionResolution,
    allocator: std.mem.Allocator,

    pub fn formSetDecision(
        self: *const OwnedComposition,
    ) *const forms_set_history.Decision {
        return self.exact_forms_set.resolution.decision.?;
    }

    pub fn deinit(self: *OwnedComposition) void {
        self.exact_forms_set.deinit(self.allocator);
        self.* = undefined;
    }
};

/// Prepares immutable provenance only. The caller remains responsible for
/// assigning a draft identity and atomically persisting the returned snapshot.
pub fn prepare(
    allocator: std.mem.Allocator,
    store: *store_module.Store,
    state: *const ui_state.State,
    definition: *const catalog.FormDefinition,
    period: filing_period.FilingPeriod,
    occurrence_date: ?model.Date,
) anyerror!OwnedComposition {
    const generated = catalog.findForm(definition.code) orelse
        return error.DefinitionIsNotGeneratedCatalogEntry;
    if (generated != definition) {
        return error.DefinitionIsNotGeneratedCatalogEntry;
    }
    if (definition.status != .static_layout or
        definition.tax_form_profile.mode == .calendar_only)
    {
        return error.CalendarOnlyForm;
    }
    const revision = definition.revision orelse
        return error.MissingFormRevision;

    const opened_form = state.formRevision() orelse
        return error.FormStateNotOpen;
    if (!std.mem.eql(u8, opened_form.code.asSlice(), definition.code) or
        !std.mem.eql(u8, opened_form.revision.asSlice(), revision))
    {
        return error.OpenedFormMismatch;
    }
    const opened_period = state.filingPeriod() orelse
        return error.FormStateNotOpen;
    if (!opened_period.eql(period) or state.taxYear() != period.taxYear()) {
        return error.FilingPeriodMismatch;
    }
    if (state.profileSnapshotLocked()) return error.FormStateAlreadyPersisted;
    if (!state.projectionAccepted()) return error.FormStateProjectionRejected;

    const form_registration: forms_set_resolver.FormRegistration = .{
        .form_code = definition.code,
        .form_revision = revision,
    };
    const query: forms_set_resolver.FilingQuery = .{
        .form = form_registration,
        .period = period,
        .occurrence_date = occurrence_date,
    };
    const applicability_date = try forms_set_resolver.applicabilityDate(query);

    const filer_binding = state.roleBinding(.filer) orelse
        return error.MissingFilerBinding;
    const forms_set_stream: forms_set_history.StreamIdentity = .{
        .profile_id = filer_binding.profile_id,
        .tax_year = period.taxYear(),
        .form = .{ .code = definition.code, .revision = revision },
    };
    var exact_forms_set = try profile_persistence.resolveFormSetDecisionOn(
        store,
        allocator,
        forms_set_stream,
        applicability_date,
    );
    errdefer exact_forms_set.deinit(allocator);
    try requireAuthoritativeActiveDecision(&exact_forms_set);
    const exact_decision = exact_forms_set.resolution.decision.?;
    const exact_active_segment = (try exact_forms_set.owned_history.history
        .preferredActiveSegment(forms_set_stream, applicability_date)) orelse
        return error.MissingActiveFormsSetSegment;
    if (!exact_active_segment.effective.contains(applicability_date)) {
        return error.MissingActiveFormsSetSegment;
    }

    var resolved_profiles: [runtime.max_role_bindings]adapter.ResolvedProfile =
        undefined;
    const bindings = state.roleBindings().slice();
    for (bindings, 0..) |*binding, index| {
        const role = catalogRole(binding.role) orelse
            return error.UnsupportedProfileRole;
        const profile_revision = state.profileRevision(binding.role) orelse
            return error.MissingProfileRevision;
        if (!profile_revision.profile_id.eql(&binding.profile_id) or
            !profile_revision.id.eql(&binding.revision_id) or
            profile_revision.sequence != binding.revision_sequence)
        {
            return error.ProfileRevisionBindingMismatch;
        }
        resolved_profiles[index] = .{
            .role = role,
            .revision = profile_revision,
        };
    }

    var owned_taxpayer_year: ?profile_persistence.OwnedTaxpayerYearHistory =
        null;
    defer if (owned_taxpayer_year) |*owned| owned.deinit(allocator);
    const taxpayer_year_revision: ?*const taxpayer_year.Revision =
        if (definition.consumed_taxpayer_year_settings.len == 0)
            null
        else blk: {
            owned_taxpayer_year = try profile_persistence.loadTaxpayerYearHistory(
                store,
                allocator,
                .{
                    .profile_id = filer_binding.profile_id,
                    .tax_year = period.taxYear(),
                },
            );
            break :blk try owned_taxpayer_year.?.history.confirmedEffectiveOn(
                applicability_date,
            );
        };

    var owned_tax_form_profile: ?profile_persistence.OwnedTaxFormProfileHistory = null;
    defer if (owned_tax_form_profile) |*owned| owned.deinit(allocator);
    const tax_form_profile_revision: ?*const tax_form_profile.Revision =
        switch (definition.tax_form_profile.mode) {
            .calendar_only => return error.CalendarOnlyForm,
            .no_setup => null,
            .setup => blk: {
                const stream: tax_form_profile.StreamKey = .{
                    .profile_id = filer_binding.profile_id,
                    .tax_year = period.taxYear(),
                    .form_code = try tax_form_profile.FormCode.parse(
                        definition.code,
                    ),
                    .form_revision = try tax_form_profile.FormRevision.parse(
                        revision,
                    ),
                };
                owned_tax_form_profile =
                    try profile_persistence.loadTaxFormProfileHistory(
                        store,
                        allocator,
                        stream,
                    );
                break :blk try effectiveTaxFormProfileRevision(
                    &owned_tax_form_profile.?.history,
                    definition,
                    applicability_date,
                    exact_active_segment.effective,
                );
            },
        };

    const catalog_binding: provenance.CatalogBinding = .{
        .revision = try provenance.CatalogRevision.parse(
            catalog.catalog_revision,
        ),
        .sha256 = try provenance.Sha256.parse(catalog.catalog_sha256),
    };
    const exact_form_storage = [_]forms_set_resolver.FormRegistration{
        form_registration,
    };
    var exact_interval_storage: [1]forms_set_resolver.Interval = undefined;
    var exact_intervals: []const forms_set_resolver.Interval = &.{};
    var exact_whole_year: forms_set_resolver.WholeYearFormSet = .{
        .tax_year = exact_decision.stream.tax_year,
        // An interval decision says nothing about the baseline. Keep it
        // explicitly unconfigured; only the selected exact interval may
        // authorize composition.
        .form_set = .{ .state = .needs_configuration, .forms = &.{} },
    };
    switch (exact_decision.scope) {
        .whole_year => exact_whole_year.form_set = .{
            .state = .active_nonempty,
            .forms = &exact_form_storage,
        },
        .interval => {
            exact_interval_storage[0] = .{
                .sequence = exact_decision.sequence,
                .tax_year = exact_decision.stream.tax_year,
                .effective = exact_decision.effective,
                .form_set = .{
                    .state = .active_nonempty,
                    .forms = &exact_form_storage,
                },
            };
            exact_intervals = &exact_interval_storage;
        },
    }
    const input: adapter.Input = .{
        .catalog_binding = catalog_binding,
        .owner_profile_id = filer_binding.profile_id,
        .form = form_registration,
        .period = period,
        .occurrence_date = occurrence_date,
        .whole_year = exact_whole_year,
        .intervals = exact_intervals,
        .profiles = resolved_profiles[0..bindings.len],
        .taxpayer_year_revision = taxpayer_year_revision,
        .tax_form_profile_revision = tax_form_profile_revision,
        .transaction_seeds = &.{},
    };
    const composition = try adapter.compose(allocator, &input);
    if (!composition.applicability_date.eql(applicability_date)) {
        return error.FilingPeriodMismatch;
    }
    return .{
        .composition = composition,
        .exact_forms_set = exact_forms_set,
        .allocator = allocator,
    };
}

fn effectiveTaxFormProfileRevision(
    history: *const tax_form_profile.History,
    definition: *const catalog.FormDefinition,
    on: model.Date,
    activation_period: tax_form_profile.EffectivePeriod,
) anyerror!?*const tax_form_profile.Revision {
    var confirmed: ?*const tax_form_profile.Revision = null;
    for (history.revisions) |*revision| {
        try revision.validate(definition);
        if (!revision.effective.eql(activation_period) or
            !revision.effectiveOn(on)) continue;
        if (revision.review_state != .confirmed) {
            return error.TaxFormProfileRequiresReview;
        }
        if (confirmed == null or revision.sequence > confirmed.?.sequence) {
            confirmed = revision;
        }
    }
    return confirmed;
}

fn requireAuthoritativeActiveDecision(
    exact: *const profile_persistence.OwnedFormSetDecisionResolution,
) Error!void {
    if (exact.resolution.review_required) {
        return error.FormsSetDecisionRequiresReview;
    }
    switch (exact.resolution.availability) {
        .unconfigured => return error.MissingFormsSetDecision,
        .inactive => return error.InactiveFormsSetDecision,
        .active => {},
    }
    const decision = exact.resolution.decision orelse
        return error.MissingFormsSetDecision;
    if (decision.review != .confirmed or decision.state != .active) {
        return error.NonAuthoritativeFormsSetDecision;
    }
}

fn catalogRole(role: ids.Role) ?catalog.Role {
    return switch (role) {
        .filer => .filer,
        .spouse => .spouse,
        .employer => .employer,
        .employee => null,
    };
}

fn persistTestProfile(
    allocator: std.mem.Allocator,
    store: *store_module.Store,
    profile_text: []const u8,
) !model.ProfileId {
    const profile_id = try model.ProfileId.parse(profile_text);
    const effective = try model.EffectivePeriod.init(
        try model.Date.parseIso("2020-01-01"),
        null,
    );
    const base: profile_editor.Base = .{
        .profile_id = profile_id,
        .revision_id = try model.RevisionId.parse("profile-revision-1"),
        .sequence = 1,
        .effective = effective,
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("040"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse(
                "1 Taxpayer Street, Quezon City",
            ),
            .zip_code = try field.ZipCode.parse("1100"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse(
                "taxpayer@example.ph",
            ),
        },
    };
    var revision = try profile_editor.begin(base).soleProprietor(.{
        .person = .{
            .name = try field.TaxpayerName.parse("MARIA SANTOS"),
            .date_of_birth = try model.Date.parseIso("1990-01-02"),
            .citizenship = try field.Citizenship.parse("Filipino"),
        },
        .trade_name = try field.RegisteredName.parse("SANTOS CONSULTING"),
    }).build();
    revision.accounting_period_basis = .calendar;
    revision.eopt_tier = .micro;
    revision.primary_line_of_business = try field.LineOfBusiness.parse(
        "Base profile consulting",
    );
    try revision.validate();
    try profile_persistence.createProfileWithRevision(
        store,
        allocator,
        .active,
        &revision,
    );
    return profile_id;
}

fn typedForm(definition: *const catalog.FormDefinition) !ids.FormRevision {
    return .{
        .code = try ids.FormCode.parse(definition.code),
        .revision = try ids.RevisionLabel.parse(definition.revision.?),
    };
}

fn createWholeYearFormsSet(
    store: *store_module.Store,
    profile_id: model.ProfileId,
    definition: *const catalog.FormDefinition,
) !void {
    const forms = [_]store_module.FormRegistrationWrite{.{
        .form_code = definition.code,
        .form_revision = definition.revision.?,
    }};
    try store.createFormSet(profile_id.asSlice(), 2026, &forms);
}

fn persist2551QTaxFormProfile(
    allocator: std.mem.Allocator,
    store: *store_module.Store,
    profile_id: model.ProfileId,
    definition: *const catalog.FormDefinition,
    choice: []const u8,
) !void {
    const values = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .income_tax_rate_election,
        .role = .filer,
        .value = .{ .choice = try tax_form_profile.TextValue.parse(choice) },
    }};
    const revision: tax_form_profile.Revision = .{
        .id = try tax_form_profile.RevisionId.parse("setup-2551q-2026"),
        .stream = .{
            .profile_id = profile_id,
            .tax_year = 2026,
            .form_code = try tax_form_profile.FormCode.parse(definition.code),
            .form_revision = try tax_form_profile.FormRevision.parse(
                definition.revision.?,
            ),
        },
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            try model.Date.parseIso("2026-12-31"),
        ),
        .spec_revision = definition.tax_form_profile.spec_revision.?,
        .spec_hash = try tax_form_profile.SpecHash.parse(
            definition.tax_form_profile.spec_hash.?,
        ),
        .review_state = .confirmed,
        .confirmed_at_unix = 1,
        .source = .manual_entry,
        .values = &values,
    };
    try profile_persistence.appendTaxFormProfileRevision(
        store,
        allocator,
        0,
        &revision,
    );
}

test "2551Q prepares SQLite-resolved generic Tax Form Profile provenance" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();
    const profile_id = try persistTestProfile(
        allocator,
        &store,
        "runtime-profile-2551q",
    );
    const definition = catalog.findForm("2551Q").?;
    try createWholeYearFormsSet(&store, profile_id, definition);
    try persist2551QTaxFormProfile(
        allocator,
        &store,
        profile_id,
        definition,
        "eight_percent",
    );

    const period: filing_period.FilingPeriod = .{
        .quarterly = .{ .tax_year = 2026, .quarter = 1 },
    };
    var state = ui_state.State.init(allocator, &store);
    defer state.deinit();
    try state.open(.{
        .form = try typedForm(definition),
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 1,
        .filing_period = period,
    });
    try std.testing.expect(state.projectionAccepted());

    var prepared = try prepare(
        allocator,
        &store,
        &state,
        definition,
        period,
        null,
    );
    defer prepared.deinit();
    try std.testing.expect(
        prepared.composition.applicability_date.eql(
            try model.Date.parseIso("2026-03-31"),
        ),
    );
    try std.testing.expectEqual(
        forms_set_history.DecisionScope.whole_year,
        prepared.formSetDecision().scope,
    );
    try std.testing.expectEqual(
        forms_set_history.ReviewState.confirmed,
        prepared.formSetDecision().review,
    );
    const snapshot = &prepared.composition.provenance_snapshot;
    try std.testing.expectEqualStrings(
        catalog.catalog_revision,
        snapshot.identity.catalog.revision.asSlice(),
    );
    try std.testing.expectEqualStrings(
        catalog.catalog_sha256,
        snapshot.identity.catalog.sha256.asSlice(),
    );
    try std.testing.expect(snapshot.taxpayer_year_revision == null);
    try std.testing.expect(snapshot.tax_form_profile_revision != null);
    try std.testing.expectEqual(
        @as(u32, 1),
        snapshot.tax_form_profile_revision.?.revision_sequence,
    );
    try std.testing.expectEqual(@as(usize, 0), snapshot.transactionSeeds().len);

    var found_election = false;
    for (snapshot.sourceSnapshots()) |source| switch (source.key) {
        .tax_form_profile_value => |key| {
            if (key.key != .income_tax_rate_election) continue;
            try std.testing.expectEqualStrings(
                "eight_percent",
                source.copied_value.choice.asSlice(),
            );
            found_election = true;
        },
        else => {},
    };
    try std.testing.expect(found_election);

    const open_input: draft_persistence.OpenInput = .{
        .period = .{
            .form = try typedForm(definition),
            .tax_year = 2026,
            .quarter = 1,
        },
        .filing_period = period,
        .role_bindings = state.roleBindings(),
        .snapshot = state.snapshot().?,
    };
    const exact: draft_persistence.ExactProvenanceInput = .{
        .applicability_date = prepared.composition.applicability_date,
        .forms_set_decision = prepared.formSetDecision(),
        .snapshot = &prepared.composition.provenance_snapshot,
    };
    var created = try draft_persistence.createOrLoadWithProvenance(
        allocator,
        &store,
        open_input,
        exact,
    );
    defer created.deinit(allocator);
    try std.testing.expectEqual(
        draft_persistence.OpenDisposition.created,
        created.disposition,
    );
    try std.testing.expect(created.provenance == .exact);

    var resumed = try draft_persistence.createOrLoadWithProvenance(
        allocator,
        &store,
        open_input,
        exact,
    );
    defer resumed.deinit(allocator);
    try std.testing.expectEqual(
        draft_persistence.OpenDisposition.resumed,
        resumed.disposition,
    );
    try std.testing.expect(resumed.provenance == .exact);

    const legacy_period: filing_period.FilingPeriod = .{
        .quarterly = .{ .tax_year = 2026, .quarter = 2 },
    };
    try state.open(.{
        .form = try typedForm(definition),
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 2,
        .filing_period = legacy_period,
    });
    var legacy_prepared = try prepare(
        allocator,
        &store,
        &state,
        definition,
        legacy_period,
        null,
    );
    defer legacy_prepared.deinit();
    const legacy_input: draft_persistence.OpenInput = .{
        .period = .{
            .form = try typedForm(definition),
            .tax_year = 2026,
            .quarter = 2,
        },
        .filing_period = legacy_period,
        .role_bindings = state.roleBindings(),
        .snapshot = state.snapshot().?,
    };
    var legacy_created = try draft_persistence.createOrLoad(
        allocator,
        &store,
        legacy_input,
    );
    defer legacy_created.deinit(allocator);
    try std.testing.expectEqual(
        draft_persistence.OpenDisposition.created,
        legacy_created.disposition,
    );
    var legacy_resumed = try draft_persistence.createOrLoadWithProvenance(
        allocator,
        &store,
        legacy_input,
        .{
            .applicability_date = legacy_prepared.composition.applicability_date,
            .forms_set_decision = legacy_prepared.formSetDecision(),
            .snapshot = &legacy_prepared.composition.provenance_snapshot,
        },
    );
    defer legacy_resumed.deinit(allocator);
    try std.testing.expectEqual(
        draft_persistence.OpenDisposition.resumed,
        legacy_resumed.disposition,
    );
    try std.testing.expect(
        legacy_resumed.provenance == .provenance_legacy_absent,
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        try store.draftProvenanceSequence(legacy_resumed.draft.id),
    );
}

test "v15 review-required Forms Set proposal blocks otherwise active 2551Q" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();
    const profile_id = try persistTestProfile(
        allocator,
        &store,
        "runtime-profile-review",
    );
    const definition = catalog.findForm("2551Q").?;
    try createWholeYearFormsSet(&store, profile_id, definition);
    try persist2551QTaxFormProfile(
        allocator,
        &store,
        profile_id,
        definition,
        "graduated",
    );
    const stream: forms_set_history.StreamIdentity = .{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form = .{
            .code = definition.code,
            .revision = definition.revision.?,
        },
    };
    const proposal: forms_set_history.DecisionInput = .{
        .id = try model.RevisionId.parse("imported-review-proposal"),
        .stream = stream,
        .state = .inactive,
        .scope = .whole_year,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .imported,
        .evidence_reference = "COR import awaiting review",
        .review = .review_required,
    };
    try profile_persistence.appendFormSetDecision(&store, 1, &proposal);

    const period: filing_period.FilingPeriod = .{
        .quarterly = .{ .tax_year = 2026, .quarter = 1 },
    };
    var state = ui_state.State.init(allocator, &store);
    defer state.deinit();
    try state.open(.{
        .form = try typedForm(definition),
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 1,
        .filing_period = period,
    });
    try std.testing.expectError(
        error.FormsSetDecisionRequiresReview,
        prepare(allocator, &store, &state, definition, period, null),
    );
}

test "1601C composes from the Forms Set and Base Profile without registration" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();
    const profile_id = try persistTestProfile(
        allocator,
        &store,
        "runtime-profile-1601c",
    );
    const definition = catalog.findForm("1601C").?;

    try store.createFormSet(profile_id.asSlice(), 2026, &.{});
    const interval_forms = [_]store_module.FormRegistrationWrite{.{
        .form_code = definition.code,
        .form_revision = definition.revision.?,
    }};
    try store.createFormSetInterval(.{
        .id = "runtime-1601c-interval",
        .profile_id = profile_id.asSlice(),
        .tax_year = 2026,
        .effective_from = "2026-01-01",
        .effective_until = "2026-06-30",
        .forms = &interval_forms,
    });

    const period: filing_period.FilingPeriod = .{
        .monthly = .{ .tax_year = 2026, .month = 1 },
    };
    var state = ui_state.State.init(allocator, &store);
    defer state.deinit();
    try state.open(.{
        .form = try typedForm(definition),
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 1,
        .filing_period = period,
    });
    try std.testing.expect(state.projectionAccepted());

    var prepared = try prepare(
        allocator,
        &store,
        &state,
        definition,
        period,
        null,
    );
    defer prepared.deinit();
    try std.testing.expectEqual(
        forms_set_history.DecisionScope.interval,
        prepared.formSetDecision().scope,
    );
    try std.testing.expectEqual(
        forms_set_resolver.ResolutionSource{ .interval = 2 },
        prepared.composition.availability_source,
    );
    const snapshot = &prepared.composition.provenance_snapshot;
    try std.testing.expect(snapshot.taxpayer_year_revision == null);
    try std.testing.expect(snapshot.tax_form_profile_revision == null);
    try std.testing.expectEqual(@as(usize, 0), snapshot.transactionSeeds().len);
}
