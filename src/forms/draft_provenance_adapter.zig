//! Pure composition boundary for immutable draft provenance.
//!
//! Persistence adapters resolve immutable rows first.  This module then
//! requalifies those rows against one exact generated form revision, filing
//! period, and date-effective Forms Set before `DraftProvenance.capture` owns
//! the result.  It performs no reads or writes and never invents an annual
//! setup row for a generated `no_setup` contract.

const std = @import("std");
const catalog = @import("generated/catalog.zig");
const catalog_projection = @import("catalog_projection.zig");
const ids = @import("id.zig");
const filing_period = @import("filing_period.zig");
const provenance = @import("draft_provenance.zig");
const field = @import("../tax_profile/field.zig");
const forms_set = @import("../tax_profile/forms_set_resolver.zig");
const model = @import("../tax_profile/model.zig");
const annual_profile = @import("../tax_profile/tax_form_profile.zig");
const year_settings = @import("../tax_profile/taxpayer_year_settings.zig");

pub const Error = std.mem.Allocator.Error ||
    catalog_projection.Error ||
    forms_set.Error ||
    provenance.Error ||
    provenance.ParseError ||
    annual_profile.Error ||
    year_settings.Error || error{
    CalendarOnlyForm,
    InactiveExactForm,
    ProfileProjectionRejected,
    UnsupportedProfileRole,
    MissingConfirmedTaxpayerYearRevision,
    UnexpectedTaxpayerYearRevision,
    UnknownTaxpayerYearSetting,
    UnsupportedTaxpayerYearRole,
    TaxFormProfileRequiresReview,
    TaxFormProfileNotEffective,
    WrongTaxFormProfileOwner,
    WrongTaxFormProfileYear,
    MissingTransactionSeed,
    UnexpectedTransactionSeed,
    DuplicateTransactionSeed,
    WrongTransactionSeedOrigin,
    TransactionSeedValueMismatch,
    TooManyCompositionValues,
};

/// One already-resolved immutable Base Tax Profile revision for a named role.
/// Current composition uses direct Base Tax Profile revisions and explicit
/// annual/form values only.
pub const ResolvedProfile = struct {
    role: catalog.Role,
    revision: *const model.ProfileRevision,
};

pub const TransactionSeedOrigin = union(enum) {
    /// Copy the value from the exact annual setup revision supplied in Input.
    tax_form_profile_revision,
    /// Copy a generated/catalog default and bind it to this catalog identity.
    catalog_default: provenance.SnapshotValue,
};

/// Maps one catalog-declared transaction default to the editable filing field
/// it initializes. The annual value remains immutable seed provenance; the
/// returned `FilingOwnedValues` is the only mutable copy.
pub const TransactionSeedInput = struct {
    filing_field: provenance.DraftFieldKey,
    role: catalog.Role,
    semantic_key: catalog.TaxFormProfileSemanticKey,
    origin: TransactionSeedOrigin,
};

pub const Input = struct {
    catalog_binding: provenance.CatalogBinding,
    owner_profile_id: model.ProfileId,
    form: forms_set.FormRegistration,
    period: filing_period.FilingPeriod,
    occurrence_date: ?model.Date = null,
    whole_year: forms_set.WholeYearFormSet,
    intervals: []const forms_set.Interval = &.{},
    profiles: []const ResolvedProfile,
    taxpayer_year_revision: ?*const year_settings.Revision = null,
    tax_form_profile_revision: ?*const annual_profile.Revision = null,
    transaction_seeds: []const TransactionSeedInput = &.{},
};

pub const Composition = struct {
    applicability_date: model.Date,
    availability_source: forms_set.ResolutionSource,
    provenance_snapshot: provenance.DraftProvenance,
    filing_owned_values: provenance.FilingOwnedValues,
};

const Builder = struct {
    taxpayer_revisions: [provenance.max_taxpayer_roles]provenance.TaxpayerRevisionBinding = undefined,
    taxpayer_revision_count: usize = 0,
    sources: [provenance.max_source_snapshots]provenance.SourceSnapshot = undefined,
    source_count: usize = 0,
    seeds: [provenance.max_transaction_seeds]provenance.TransactionDefaultSeed = undefined,
    seed_count: usize = 0,

    fn addTaxpayerRevision(
        self: *Builder,
        value: provenance.TaxpayerRevisionBinding,
    ) Error!void {
        if (self.taxpayer_revision_count == self.taxpayer_revisions.len) {
            return error.TooManyCompositionValues;
        }
        self.taxpayer_revisions[self.taxpayer_revision_count] = value;
        self.taxpayer_revision_count += 1;
    }

    fn addSource(self: *Builder, value: provenance.SourceSnapshot) Error!void {
        for (self.sources[0..self.source_count]) |*existing| {
            if (existing.key.eql(value.key)) return;
        }
        if (self.source_count == self.sources.len) {
            return error.TooManyCompositionValues;
        }
        self.sources[self.source_count] = value;
        self.source_count += 1;
    }

    fn addSeed(
        self: *Builder,
        value: provenance.TransactionDefaultSeed,
    ) Error!void {
        if (self.seed_count == self.seeds.len) {
            return error.TooManyCompositionValues;
        }
        self.seeds[self.seed_count] = value;
        self.seed_count += 1;
    }
};

/// Compose through the checked generated-catalog entry for `input.form`.
pub fn compose(
    allocator: std.mem.Allocator,
    input: *const Input,
) Error!Composition {
    const definition = catalog.findForm(input.form.form_code) orelse
        return error.UnknownForm;
    return composeDefinition(allocator, input, definition);
}

/// The definition parameter keeps the validation core directly testable with
/// a catalog-shaped fixture. Production callers use `compose`, which always
/// obtains this pointer from the generated catalog.
fn composeDefinition(
    allocator: std.mem.Allocator,
    input: *const Input,
    definition: *const catalog.FormDefinition,
) Error!Composition {
    if (definition.status != .static_layout or
        definition.tax_form_profile.mode == .calendar_only)
    {
        return error.CalendarOnlyForm;
    }
    if (!std.mem.eql(u8, definition.code, input.form.form_code)) {
        return error.WrongForm;
    }
    const form_revision = definition.revision orelse
        return error.CalendarOnlyForm;
    if (!std.mem.eql(u8, form_revision, input.form.form_revision)) {
        return error.FormRevisionMismatch;
    }

    const query: forms_set.FilingQuery = .{
        .form = input.form,
        .period = input.period,
        .occurrence_date = input.occurrence_date,
    };
    const availability = try forms_set.resolveAvailability(
        input.whole_year,
        input.intervals,
        query,
    );
    if (!availability.active) return error.InactiveExactForm;

    var builder: Builder = .{};
    try composeProfiles(
        allocator,
        input,
        definition,
        availability.applicability_date,
        &builder,
    );
    const year_binding = try composeTaxpayerYear(
        input,
        definition,
        availability.applicability_date,
        &builder,
    );
    const form_profile_binding = try composeTaxFormProfile(
        input,
        definition,
        availability.applicability_date,
        &builder,
    );

    const identity: provenance.FilingIdentity = .{
        .owner_profile_id = input.owner_profile_id,
        .tax_year = input.period.taxYear(),
        .form_code = try annual_profile.FormCode.parse(definition.code),
        .form_revision = try annual_profile.FormRevision.parse(form_revision),
        .catalog = input.catalog_binding,
        .setup_spec_revision = definition.tax_form_profile.spec_revision orelse
            return error.MissingSetupSpecIdentity,
        .setup_spec_hash = try provenance.Sha256.parse(
            definition.tax_form_profile.spec_hash orelse
                return error.MissingSetupSpecIdentity,
        ),
    };
    const capture_input: provenance.CaptureInput = .{
        .identity = identity,
        .taxpayer_revisions = builder.taxpayer_revisions[0..builder.taxpayer_revision_count],
        .taxpayer_year_revision = year_binding,
        .tax_form_profile_revision = form_profile_binding,
        .source_snapshots = builder.sources[0..builder.source_count],
        .transaction_seeds = builder.seeds[0..builder.seed_count],
    };
    const snapshot = try provenance.DraftProvenance.capture(
        &capture_input,
        definition,
    );
    return .{
        .applicability_date = availability.applicability_date,
        .availability_source = availability.source,
        .provenance_snapshot = snapshot,
        .filing_owned_values = provenance.FilingOwnedValues.fromProvenance(
            &snapshot,
        ),
    };
}

fn composeProfiles(
    allocator: std.mem.Allocator,
    input: *const Input,
    definition: *const catalog.FormDefinition,
    on: model.Date,
    builder: *Builder,
) Error!void {
    var projection_bindings: [provenance.max_taxpayer_roles]catalog_projection.Binding = undefined;
    if (input.profiles.len > projection_bindings.len) {
        return error.TooManyCompositionValues;
    }
    for (input.profiles, 0..) |resolved, index| {
        const role = catalog_projection.domainRole(resolved.role) orelse
            return error.UnsupportedProfileRole;
        projection_bindings[index] = .{
            .role = role,
            .revision = resolved.revision,
            .selection = .{},
        };
        try builder.addTaxpayerRevision(.{
            .role = resolved.role,
            .profile_id = resolved.revision.profile_id,
            .revision_id = resolved.revision.id,
            .revision_sequence = resolved.revision.sequence,
        });
    }

    const typed_form: ids.FormRevision = .{
        .code = try ids.FormCode.parse(definition.code),
        .revision = try ids.RevisionLabel.parse(definition.revision.?),
    };
    var result = try catalog_projection.project(
        allocator,
        typed_form,
        projection_bindings[0..input.profiles.len],
        on,
    );
    defer result.deinit(allocator);
    switch (result) {
        .rejected => return error.ProfileProjectionRejected,
        .accepted => |accepted| for (accepted.entries) |entry| {
            const reusable = reusableFieldForTarget(definition, &entry.target) orelse
                continue;
            const fact_key = taxpayerFactKey(reusable) orelse continue;
            const role = catalogRole(entry.role) orelse
                return error.UnsupportedProfileRole;
            try builder.addSource(.{
                .key = .{ .taxpayer_fact = .{
                    .role = role,
                    .key = fact_key,
                } },
                .copied_value = try profileSnapshotValue(entry.value),
            });
        },
    }
}

fn composeTaxpayerYear(
    input: *const Input,
    definition: *const catalog.FormDefinition,
    on: model.Date,
    builder: *Builder,
) Error!?provenance.TaxpayerYearRevisionBinding {
    var required_keys: [std.meta.fields(year_settings.SettingKey).len]year_settings.SettingKey = undefined;
    var required_count: usize = 0;
    for (definition.consumed_taxpayer_year_settings) |catalog_key| {
        if (required_count == required_keys.len) {
            return error.TooManyCompositionValues;
        }
        required_keys[required_count] = switch (catalog_key) {
            .income_tax_rate_election => .income_tax_rate_election,
            .deduction_method => .deduction_method,
        };
        required_count += 1;
    }

    if (required_count == 0) {
        if (input.taxpayer_year_revision != null) {
            return error.UnexpectedTaxpayerYearRevision;
        }
        return null;
    }
    const revision = input.taxpayer_year_revision orelse
        return error.MissingConfirmedTaxpayerYearRevision;
    try revision.validate();
    if (!revision.stream.profile_id.eql(&input.owner_profile_id)) {
        return error.WrongOwner;
    }
    if (revision.stream.tax_year != input.period.taxYear()) {
        return error.WrongTaxpayerYear;
    }
    if (!revision.effectiveOn(on)) return error.NoEffectiveRevision;
    if (revision.review_state != .confirmed) {
        return error.EffectiveRevisionRequiresReview;
    }
    // Resolve the rate first because deduction is a conditional consumer:
    // graduated filers must carry exactly one method, while an eight-percent
    // election must carry none. `Revision.validate` enforces the stored
    // invariant; this pass applies the same rule to the generated consumer
    // contract rather than treating every listed key as unconditionally
    // present.
    var consumed_rate: ?year_settings.IncomeTaxRateElection = null;
    for (required_keys[0..required_count]) |key| {
        if (key != .income_tax_rate_election) continue;
        const value = revision.find(key) orelse return error.MissingSetting;
        consumed_rate = switch (value.*) {
            .income_tax_rate_election => |rate| rate,
            .deduction_method => return error.UnknownTaxpayerYearSetting,
        };
        try builder.addSource(.{
            .key = .{ .taxpayer_year_setting = .{
                .role = .filer,
                .key = key,
            } },
            .copied_value = yearSnapshotValue(value.*),
        });
    }
    for (required_keys[0..required_count]) |key| {
        if (key == .income_tax_rate_election) continue;
        if (key == .deduction_method and
            consumed_rate == .eight_percent)
        {
            continue;
        }
        if (key == .deduction_method and consumed_rate == null) {
            return error.UnknownTaxpayerYearSetting;
        }
        const value = revision.find(key) orelse return error.MissingSetting;
        try builder.addSource(.{
            .key = .{ .taxpayer_year_setting = .{
                .role = .filer,
                .key = key,
            } },
            .copied_value = yearSnapshotValue(value.*),
        });
    }
    return .{
        .stream = revision.stream,
        .revision_id = revision.id,
        .revision_sequence = revision.sequence,
    };
}

fn composeTaxFormProfile(
    input: *const Input,
    definition: *const catalog.FormDefinition,
    on: model.Date,
    builder: *Builder,
) Error!?provenance.TaxFormProfileRevisionBinding {
    switch (definition.tax_form_profile.mode) {
        .calendar_only => return error.CalendarOnlyForm,
        .no_setup => {
            if (input.tax_form_profile_revision != null) {
                return error.UnexpectedTaxFormProfileRevision;
            }
            if (input.transaction_seeds.len != 0) {
                return error.UnexpectedTransactionSeed;
            }
            return null;
        },
        .setup => {},
    }

    const revision = input.tax_form_profile_revision orelse {
        try composeUnambiguousSetupWithoutRevision(
            input,
            definition,
            on,
            builder,
        );
        return null;
    };
    try revision.validate(definition);
    if (!revision.stream.profile_id.eql(&input.owner_profile_id)) {
        return error.WrongTaxFormProfileOwner;
    }
    if (revision.stream.tax_year != input.period.taxYear()) {
        return error.WrongTaxFormProfileYear;
    }
    if (revision.review_state != .confirmed) {
        return error.TaxFormProfileRequiresReview;
    }
    if (!revision.effectiveOn(on)) return error.TaxFormProfileNotEffective;

    try validateSeedInputs(input, definition, revision);
    for (revision.values) |*setup_value| {
        const value_definition = findSetupDefinition(
            definition,
            setup_value.role,
            setup_value.semantic_key,
        ) orelse return error.UnknownSemanticKey;
        if (value_definition.ownership == .transaction_default) {
            const seed_input = findSeedInput(
                input.transaction_seeds,
                setup_value.role,
                setup_value.semantic_key,
            ) orelse return error.MissingTransactionSeed;
            try addTransactionSeed(
                input,
                revision,
                setup_value,
                value_definition,
                seed_input,
                builder,
            );
            continue;
        }
        const copied_value = try setupSnapshotValue(setup_value.value);
        try builder.addSource(.{
            .key = .{ .tax_form_profile_value = .{
                .role = setup_value.role,
                .key = setup_value.semantic_key,
            } },
            .copied_value = copied_value,
        });
    }

    // A catalog default need not be stored as an annual value. Consume any
    // explicit catalog-default mappings that were not represented above.
    for (input.transaction_seeds) |*seed_input| {
        if (findSetupValue(
            revision.values,
            seed_input.role,
            seed_input.semantic_key,
        ) != null) continue;
        const value_definition = findSetupDefinition(
            definition,
            seed_input.role,
            seed_input.semantic_key,
        ) orelse return error.UnexpectedTransactionSeed;
        if (value_definition.ownership != .transaction_default or
            value_definition.source_kind != .catalog_default)
        {
            return error.UnexpectedTransactionSeed;
        }
        const copied_value = switch (seed_input.origin) {
            .catalog_default => |value| value,
            .tax_form_profile_revision => return error.WrongTransactionSeedOrigin,
        };
        try builder.addSeed(.{
            .filing_field = seed_input.filing_field,
            .source_key = .{ .tax_form_profile_value = .{
                .role = seed_input.role,
                .key = seed_input.semantic_key,
            } },
            .source = .{ .catalog_default = input.catalog_binding },
            .copied_seed_value = copied_value,
        });
    }

    return .{
        .stream = revision.stream,
        .revision_id = revision.id,
        .revision_sequence = revision.sequence,
        .spec_revision = revision.spec_revision,
        .spec_hash = revision.spec_hash,
    };
}

fn composeUnambiguousSetupWithoutRevision(
    input: *const Input,
    definition: *const catalog.FormDefinition,
    on: model.Date,
    builder: *Builder,
) Error!void {
    _ = on;
    for (definition.tax_form_profile.values) |value_definition| {
        if (value_definition.availability != .supported) continue;
        if (value_definition.presence == .required) {
            return error.MissingTaxFormProfileRevision;
        }
        if (value_definition.ownership != .binding_selection) continue;

        _ = findResolvedProfile(
            input.profiles,
            value_definition.role,
        ) orelse {
            // An optional named role that is absent needs no annual choice.
            if (value_definition.source_kind == .named_profile_role) continue;
            return error.MissingRequiredProfileRole;
        };

        switch (value_definition.source_kind) {
            .named_profile_role => {},
            .user_entry,
            .catalog_default,
            => return error.MissingTaxFormProfileRevision,
        }
    }

    // Catalog-owned defaults can seed a transaction without inventing an
    // annual revision. Any caller-supplied annual-value origin still requires
    // a saved Tax Form Profile.
    for (input.transaction_seeds, 0..) |*seed_input, index| {
        for (input.transaction_seeds[index + 1 ..]) |*other| {
            if ((seed_input.role == other.role and
                seed_input.semantic_key == other.semantic_key) or
                seed_input.filing_field.eql(&other.filing_field))
            {
                return error.DuplicateTransactionSeed;
            }
        }
        const value_definition = findSetupDefinition(
            definition,
            seed_input.role,
            seed_input.semantic_key,
        ) orelse return error.UnexpectedTransactionSeed;
        if (value_definition.availability != .supported or
            value_definition.ownership != .transaction_default or
            value_definition.source_kind != .catalog_default)
        {
            return error.MissingTaxFormProfileRevision;
        }
        const copied_value = switch (seed_input.origin) {
            .catalog_default => |value| value,
            .tax_form_profile_revision => return error.MissingTaxFormProfileRevision,
        };
        try builder.addSeed(.{
            .filing_field = seed_input.filing_field,
            .source_key = .{ .tax_form_profile_value = .{
                .role = seed_input.role,
                .key = seed_input.semantic_key,
            } },
            .source = .{ .catalog_default = input.catalog_binding },
            .copied_seed_value = copied_value,
        });
    }
}

fn validateSeedInputs(
    input: *const Input,
    definition: *const catalog.FormDefinition,
    revision: *const annual_profile.Revision,
) Error!void {
    _ = revision;
    for (input.transaction_seeds, 0..) |seed, index| {
        for (input.transaction_seeds[index + 1 ..]) |other| {
            if ((seed.role == other.role and
                seed.semantic_key == other.semantic_key) or
                seed.filing_field.eql(&other.filing_field))
            {
                return error.DuplicateTransactionSeed;
            }
        }
        const value_definition = findSetupDefinition(
            definition,
            seed.role,
            seed.semantic_key,
        ) orelse return error.UnexpectedTransactionSeed;
        if (value_definition.ownership != .transaction_default) {
            return error.UnexpectedTransactionSeed;
        }
    }
}

fn addTransactionSeed(
    input: *const Input,
    revision: *const annual_profile.Revision,
    setup_value: *const annual_profile.SetupValue,
    definition: *const catalog.TaxFormProfileValueDefinition,
    seed_input: *const TransactionSeedInput,
    builder: *Builder,
) Error!void {
    const revision_value = try setupSnapshotValue(setup_value.value);
    const copied_value: provenance.SnapshotValue = switch (seed_input.origin) {
        .tax_form_profile_revision => blk: {
            if (definition.source_kind == .catalog_default) {
                return error.WrongTransactionSeedOrigin;
            }
            break :blk revision_value;
        },
        .catalog_default => |value| blk: {
            if (definition.source_kind != .catalog_default) {
                return error.WrongTransactionSeedOrigin;
            }
            if (!snapshotValueEql(value, revision_value)) {
                return error.TransactionSeedValueMismatch;
            }
            break :blk value;
        },
    };
    try builder.addSeed(.{
        .filing_field = seed_input.filing_field,
        .source_key = .{ .tax_form_profile_value = .{
            .role = setup_value.role,
            .key = setup_value.semantic_key,
        } },
        .source = switch (seed_input.origin) {
            .tax_form_profile_revision => .{
                .tax_form_profile_revision = revision.id,
            },
            .catalog_default => .{
                .catalog_default = input.catalog_binding,
            },
        },
        .copied_seed_value = copied_value,
    });
}

fn findResolvedProfile(
    profiles: []const ResolvedProfile,
    role: catalog.Role,
) ?*const ResolvedProfile {
    for (profiles) |*profile| {
        if (profile.role == role) return profile;
    }
    return null;
}

fn reusableFieldForTarget(
    definition: *const catalog.FormDefinition,
    target: *const ids.FieldId,
) ?field.ReusableField {
    for (definition.fields) |catalog_field| {
        if (!std.mem.eql(u8, catalog_field.id, target.asSlice())) continue;
        return catalog_projection.reusableField(
            catalog_field.profile_key orelse return null,
        );
    }
    return null;
}

fn taxpayerFactKey(value: field.ReusableField) ?provenance.TaxpayerFactKey {
    return switch (value) {
        .tin => .tin,
        .rdo_code => .rdo_code,
        .taxpayer_name => .taxpayer_name,
        .registered_name => .registered_name,
        .registered_address => .registered_address,
        .zip_code => .zip_code,
        .contact_number => .contact_number,
        .email_address => .email_address,
        .accounting_period_basis,
        .date_of_birth,
        .citizenship,
        .foreign_tax_number,
        .line_of_business,
        .eopt_tier,
        .atc,
        .tax_type,
        .government_withholding_agent,
        .special_rate_basis,
        => null,
    };
}

fn profileSnapshotValue(value: field.Value) provenance.ParseError!provenance.SnapshotValue {
    return switch (value) {
        .tin => |item| .{ .text = try provenance.OwnedText.copy(item.asDigits()) },
        .rdo_code => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .taxpayer_name => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .registered_name => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .registered_address => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .zip_code => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .contact_number => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .email_address => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .accounting_period_basis => |item| .{
            .choice = try provenance.OwnedText.copy(@tagName(item)),
        },
        .date_of_birth => |item| .{ .date = item },
        .citizenship => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .foreign_tax_number => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .line_of_business => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .eopt_tier => |item| .{ .choice = try provenance.OwnedText.copy(item.asSlice()) },
        .atc => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .tax_type => |item| .{ .choice = try provenance.OwnedText.copy(item.asSlice()) },
        .government_withholding_agent => |item| .{ .boolean = item == .yes },
        .special_rate_basis => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
    };
}

fn yearSnapshotValue(value: year_settings.SettingValue) provenance.SnapshotValue {
    return switch (value) {
        .income_tax_rate_election => |item| .{ .income_tax_rate_election = item },
        .deduction_method => |item| .{ .deduction_method = item },
    };
}

fn setupSnapshotValue(
    value: annual_profile.ScalarValue,
) Error!provenance.SnapshotValue {
    return switch (value) {
        .profile_id => |item| .{ .profile_id = item },
        .text => |item| .{ .text = try provenance.OwnedText.copy(item.asSlice()) },
        .boolean => |item| .{ .boolean = item },
        .integer => |item| .{ .integer = item },
        .date => |item| .{ .date = item },
        .year => |item| .{ .year = item },
        .choice => |item| .{ .choice = try provenance.OwnedText.copy(item.asSlice()) },
    };
}

fn findSetupDefinition(
    definition: *const catalog.FormDefinition,
    role: catalog.Role,
    key: catalog.TaxFormProfileSemanticKey,
) ?*const catalog.TaxFormProfileValueDefinition {
    for (definition.tax_form_profile.values) |*value| {
        if (value.role == role and value.semantic_key == key) return value;
    }
    return null;
}

fn findSetupValue(
    values: []const annual_profile.SetupValue,
    role: catalog.Role,
    key: catalog.TaxFormProfileSemanticKey,
) ?*const annual_profile.SetupValue {
    for (values) |*value| {
        if (value.role == role and value.semantic_key == key) return value;
    }
    return null;
}

fn findSeedInput(
    inputs: []const TransactionSeedInput,
    role: catalog.Role,
    key: catalog.TaxFormProfileSemanticKey,
) ?*const TransactionSeedInput {
    for (inputs) |*input| {
        if (input.role == role and input.semantic_key == key) return input;
    }
    return null;
}

fn catalogRole(role: ids.Role) ?catalog.Role {
    return switch (role) {
        .filer => .filer,
        .spouse => .spouse,
        .employer => .employer,
        .employee => null,
    };
}

fn snapshotValueEql(
    left: provenance.SnapshotValue,
    right: provenance.SnapshotValue,
) bool {
    return switch (left) {
        .text => |value| switch (right) {
            .text => |other| std.mem.eql(u8, value.asSlice(), other.asSlice()),
            else => false,
        },
        .choice => |value| switch (right) {
            .choice => |other| std.mem.eql(u8, value.asSlice(), other.asSlice()),
            else => false,
        },
        .boolean => |value| switch (right) {
            .boolean => |other| value == other,
            else => false,
        },
        .integer => |value| switch (right) {
            .integer => |other| value == other,
            else => false,
        },
        .date => |value| switch (right) {
            .date => |other| value.eql(other),
            else => false,
        },
        .year => |value| switch (right) {
            .year => |other| value == other,
            else => false,
        },
        .profile_id => |value| switch (right) {
            .profile_id => |other| value.eql(&other),
            else => false,
        },
        .income_tax_rate_election => |value| switch (right) {
            .income_tax_rate_election => |other| value == other,
            else => false,
        },
        .deduction_method => |value| switch (right) {
            .deduction_method => |other| value == other,
            else => false,
        },
    };
}

fn fixtureCatalogBinding() !provenance.CatalogBinding {
    return .{
        .revision = try provenance.CatalogRevision.parse("catalog-fixture-1"),
        .sha256 = try provenance.Sha256.parse(
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        ),
    };
}

fn fixtureProfile(
    profile_id: []const u8,
    revision_id: []const u8,
    name: []const u8,
    tax_year: u16,
) !model.ProfileRevision {
    return .{
        .profile_id = try model.ProfileId.parse(profile_id),
        .id = try model.RevisionId.parse(revision_id),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.init(tax_year, 1, 1),
            try model.Date.init(tax_year, 12, 31),
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("040"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("1 Taxpayer Street"),
            .zip_code = try field.ZipCode.parse("1100"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse("taxpayer@example.ph"),
        },
        .subject = .{ .individual = .{
            .name = try field.TaxpayerName.parse(name),
            .classification = .self_employed,
            .date_of_birth = try model.Date.parseIso("1990-01-01"),
            .citizenship = try field.Citizenship.parse("Filipino"),
        } },
        .accounting_period_basis = .calendar,
        .eopt_tier = .micro,
        .primary_line_of_business = try field.LineOfBusiness.parse(
            "Software consulting",
        ),
    };
}

fn fixtureYearRevision(
    profile_id: model.ProfileId,
    tax_year: u16,
    values: []const year_settings.SettingValue,
) !year_settings.Revision {
    return .{
        .id = try year_settings.RevisionId.parse("year-settings-1"),
        .stream = .{ .profile_id = profile_id, .tax_year = tax_year },
        .sequence = 1,
        .effective = try year_settings.fullTaxYearPeriod(tax_year),
        .review_state = .confirmed,
        .confirmed_at_unix_seconds = 1,
        .source = .manual_entry,
        .values = values,
    };
}

fn fixtureAnnualRevision(
    definition: *const catalog.FormDefinition,
    profile_id: model.ProfileId,
    tax_year: u16,
    values: []const annual_profile.SetupValue,
) !annual_profile.Revision {
    return .{
        .id = try annual_profile.RevisionId.parse("annual-setup-1"),
        .stream = .{
            .profile_id = profile_id,
            .tax_year = tax_year,
            .form_code = try annual_profile.FormCode.parse(definition.code),
            .form_revision = try annual_profile.FormRevision.parse(
                definition.revision.?,
            ),
        },
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.init(tax_year, 1, 1),
            try model.Date.init(tax_year, 12, 31),
        ),
        .spec_revision = definition.tax_form_profile.spec_revision.?,
        .spec_hash = try annual_profile.SpecHash.parse(
            definition.tax_form_profile.spec_hash.?,
        ),
        .review_state = .confirmed,
        .confirmed_at_unix = 1,
        .source = .manual_entry,
        .values = values,
    };
}

fn fixtureInput(
    definition: *const catalog.FormDefinition,
    profile: *const model.ProfileRevision,
    profiles: []const ResolvedProfile,
    year_revision: ?*const year_settings.Revision,
    annual_revision: ?*const annual_profile.Revision,
    forms: []const forms_set.FormRegistration,
    tax_year: u16,
) !Input {
    return .{
        .catalog_binding = try fixtureCatalogBinding(),
        .owner_profile_id = profile.profile_id,
        .form = .{
            .form_code = definition.code,
            .form_revision = definition.revision.?,
        },
        .period = .{ .quarterly = .{ .tax_year = tax_year, .quarter = 1 } },
        .whole_year = .{
            .tax_year = tax_year,
            .form_set = .{ .state = .active_nonempty, .forms = forms },
        },
        .profiles = profiles,
        .taxpayer_year_revision = year_revision,
        .tax_form_profile_revision = annual_revision,
    };
}

test "2551Q setup captures exact profile and generic Tax Form Profile revision" {
    const definition = catalog.findForm("2551Q").?;
    var filer = try fixtureProfile(
        "profile-filer",
        "profile-revision-1",
        "JUAN DELA CRUZ",
        2026,
    );
    const profiles = [_]ResolvedProfile{.{
        .role = .filer,
        .revision = &filer,
    }};
    const setup_values = [_]annual_profile.SetupValue{.{
        .semantic_key = .income_tax_rate_election,
        .role = .filer,
        .value = .{ .choice = try annual_profile.TextValue.parse(
            "eight_percent",
        ) },
    }};
    var annual_revision = try fixtureAnnualRevision(
        definition,
        filer.profile_id,
        2026,
        &setup_values,
    );
    const forms = [_]forms_set.FormRegistration{.{
        .form_code = definition.code,
        .form_revision = definition.revision.?,
    }};
    var input = try fixtureInput(
        definition,
        &filer,
        &profiles,
        null,
        &annual_revision,
        &forms,
        2026,
    );
    const result = try compose(std.testing.allocator, &input);
    try std.testing.expect(result.provenance_snapshot.tax_form_profile_revision != null);
    try std.testing.expect(result.provenance_snapshot.taxpayer_year_revision == null);

    const setup_definition = catalog.findForm("1701Q").?;
    const spouse_value = [_]annual_profile.SetupValue{.{
        .semantic_key = .spouse_profile_id,
        .role = .spouse,
        .value = .{ .profile_id = try model.ProfileId.parse("profile-spouse") },
    }};
    var fabricated = try fixtureAnnualRevision(
        setup_definition,
        filer.profile_id,
        2026,
        &spouse_value,
    );
    input.tax_form_profile_revision = &fabricated;
    try std.testing.expectError(
        error.WrongForm,
        compose(std.testing.allocator, &input),
    );
}

test "1701Q optional spouse composes without registration component bindings" {
    const definition = catalog.findForm("1701Q").?;
    var filer = try fixtureProfile(
        "profile-filer",
        "filer-revision-1",
        "JUAN DELA CRUZ",
        2026,
    );
    var spouse = try fixtureProfile(
        "profile-spouse",
        "spouse-revision-1",
        "ANA DELA CRUZ",
        2026,
    );
    spouse.identity.tin = try field.Tin.parse("987-654-321-000");
    const profiles = [_]ResolvedProfile{
        .{ .role = .filer, .revision = &filer },
        .{ .role = .spouse, .revision = &spouse },
    };
    const year_values = [_]year_settings.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .itemized_deduction },
    };
    var year_revision = try fixtureYearRevision(
        filer.profile_id,
        2026,
        &year_values,
    );
    const setup_values = [_]annual_profile.SetupValue{.{
        .semantic_key = .spouse_profile_id,
        .role = .spouse,
        .value = .{ .profile_id = spouse.profile_id },
    }};
    var annual_revision = try fixtureAnnualRevision(
        definition,
        filer.profile_id,
        2026,
        &setup_values,
    );
    const forms = [_]forms_set.FormRegistration{.{
        .form_code = definition.code,
        .form_revision = definition.revision.?,
    }};
    var input = try fixtureInput(
        definition,
        &filer,
        &profiles,
        &year_revision,
        &annual_revision,
        &forms,
        2026,
    );
    const result = try compose(std.testing.allocator, &input);
    try std.testing.expectEqual(@as(usize, 2), result.provenance_snapshot.taxpayerRevisions().len);

    const eight_percent_values = [_]year_settings.SettingValue{.{
        .income_tax_rate_election = .eight_percent,
    }};
    year_revision.values = &eight_percent_values;
    const eight_percent_result = try compose(std.testing.allocator, &input);
    var rate_source_count: usize = 0;
    var deduction_source_count: usize = 0;
    for (eight_percent_result.provenance_snapshot.sourceSnapshots()) |source| {
        switch (source.key) {
            .taxpayer_year_setting => |key| switch (key.key) {
                .income_tax_rate_election => rate_source_count += 1,
                .deduction_method => deduction_source_count += 1,
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(usize, 1), rate_source_count);
    try std.testing.expectEqual(@as(usize, 0), deduction_source_count);
    year_revision.values = &year_values;
}

test "taxpayer-year revision is isolated to the filing year" {
    const definition = catalog.findForm("1701Q").?;
    var filer = try fixtureProfile(
        "profile-filer",
        "profile-revision-1",
        "JUAN DELA CRUZ",
        2026,
    );
    const profiles = [_]ResolvedProfile{.{ .role = .filer, .revision = &filer }};
    const year_values = [_]year_settings.SettingValue{.{
        .income_tax_rate_election = .eight_percent,
    }};
    var wrong_year = try fixtureYearRevision(
        filer.profile_id,
        2025,
        &year_values,
    );
    const forms = [_]forms_set.FormRegistration{.{
        .form_code = definition.code,
        .form_revision = definition.revision.?,
    }};
    var input = try fixtureInput(
        definition,
        &filer,
        &profiles,
        &wrong_year,
        null,
        &forms,
        2026,
    );
    try std.testing.expectError(
        error.WrongTaxpayerYear,
        compose(std.testing.allocator, &input),
    );

    input.taxpayer_year_revision = null;
    try std.testing.expectError(
        error.MissingConfirmedTaxpayerYearRevision,
        compose(std.testing.allocator, &input),
    );

    var unconfirmed = try fixtureYearRevision(
        filer.profile_id,
        2026,
        &year_values,
    );
    unconfirmed.review_state = .requires_review;
    unconfirmed.confirmed_at_unix_seconds = null;
    input.taxpayer_year_revision = &unconfirmed;
    try std.testing.expectError(
        error.EffectiveRevisionRequiresReview,
        compose(std.testing.allocator, &input),
    );
}

test "stale form revision and Tax Form Profile spec fail closed" {
    const definition = catalog.findForm("1701Q").?;
    var filer = try fixtureProfile(
        "profile-filer",
        "profile-revision-1",
        "JUAN DELA CRUZ",
        2026,
    );
    var spouse = try fixtureProfile(
        "profile-spouse",
        "spouse-revision-1",
        "ANA DELA CRUZ",
        2026,
    );
    spouse.identity.tin = try field.Tin.parse("987-654-321-000");
    const profiles = [_]ResolvedProfile{
        .{ .role = .filer, .revision = &filer },
        .{ .role = .spouse, .revision = &spouse },
    };
    const year_values = [_]year_settings.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .itemized_deduction },
    };
    var year_revision = try fixtureYearRevision(filer.profile_id, 2026, &year_values);
    const setup_values = [_]annual_profile.SetupValue{.{
        .semantic_key = .spouse_profile_id,
        .role = .spouse,
        .value = .{ .profile_id = spouse.profile_id },
    }};
    var annual_revision = try fixtureAnnualRevision(
        definition,
        filer.profile_id,
        2026,
        &setup_values,
    );
    const forms = [_]forms_set.FormRegistration{.{
        .form_code = definition.code,
        .form_revision = definition.revision.?,
    }};
    var input = try fixtureInput(
        definition,
        &filer,
        &profiles,
        &year_revision,
        &annual_revision,
        &forms,
        2026,
    );
    input.form.form_revision = "stale-revision";
    try std.testing.expectError(
        error.FormRevisionMismatch,
        compose(std.testing.allocator, &input),
    );

    input.form.form_revision = definition.revision.?;
    annual_revision.spec_hash = try annual_profile.SpecHash.parse(
        "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    );
    try std.testing.expectError(
        error.SpecHashMismatch,
        compose(std.testing.allocator, &input),
    );
}

test "date-effective Forms Set interval blocks only inactive filing dates" {
    const definition = catalog.findForm("2551Q").?;
    var filer = try fixtureProfile(
        "profile-filer",
        "profile-revision-1",
        "JUAN DELA CRUZ",
        2026,
    );
    const profiles = [_]ResolvedProfile{.{ .role = .filer, .revision = &filer }};
    const setup_values = [_]annual_profile.SetupValue{.{
        .semantic_key = .income_tax_rate_election,
        .role = .filer,
        .value = .{ .choice = try annual_profile.TextValue.parse(
            "graduated",
        ) },
    }};
    var annual_revision = try fixtureAnnualRevision(
        definition,
        filer.profile_id,
        2026,
        &setup_values,
    );
    const forms = [_]forms_set.FormRegistration{.{
        .form_code = definition.code,
        .form_revision = definition.revision.?,
    }};
    var input = try fixtureInput(
        definition,
        &filer,
        &profiles,
        null,
        &annual_revision,
        &forms,
        2026,
    );
    const inactive_intervals = [_]forms_set.Interval{.{
        .sequence = 1,
        .tax_year = 2026,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-04-01"),
            null,
        ),
        .form_set = .{ .state = .active_empty, .forms = &.{} },
    }};
    input.intervals = &inactive_intervals;
    _ = try compose(std.testing.allocator, &input); // Q1 resolves on March 31.
    input.period = .{ .quarterly = .{ .tax_year = 2026, .quarter = 2 } };
    try std.testing.expectError(
        error.InactiveExactForm,
        compose(std.testing.allocator, &input),
    );
}

test "transaction default is immutable provenance and only its filing copy mutates" {
    const generated = catalog.findForm("1701Q").?;
    const transaction_definition: catalog.TaxFormProfileValueDefinition = .{
        .semantic_key = .special_rate_basis,
        .value_type = .text,
        .role = .filer,
        .presence = .optional,
        .validation_rule = .nonempty_text,
        .ownership = .transaction_default,
        .source_kind = .user_entry,
        .availability = .supported,
        .source_evidence = "adapter transaction-seed fixture",
        .evidence_gate = null,
    };
    const setup_definitions = [_]catalog.TaxFormProfileValueDefinition{
        transaction_definition,
    };
    var definition = generated.*;
    definition.tax_form_profile.values = &setup_definitions;
    definition.tax_form_profile.spec_hash =
        "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd";

    var filer = try fixtureProfile(
        "profile-filer",
        "profile-revision-1",
        "JUAN DELA CRUZ",
        2026,
    );
    const profiles = [_]ResolvedProfile{.{ .role = .filer, .revision = &filer }};
    const year_values = [_]year_settings.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .itemized_deduction },
    };
    var year_revision = try fixtureYearRevision(filer.profile_id, 2026, &year_values);
    const setup_values = [_]annual_profile.SetupValue{.{
        .semantic_key = .special_rate_basis,
        .role = .filer,
        .value = .{ .text = try annual_profile.TextValue.parse("seed-value") },
    }};
    var annual_revision = try fixtureAnnualRevision(
        &definition,
        filer.profile_id,
        2026,
        &setup_values,
    );
    const forms = [_]forms_set.FormRegistration{.{
        .form_code = definition.code,
        .form_revision = definition.revision.?,
    }};
    var input = try fixtureInput(
        &definition,
        &filer,
        &profiles,
        &year_revision,
        &annual_revision,
        &forms,
        2026,
    );
    const filing_field = try provenance.DraftFieldKey.parse(
        "1701Q.transaction.special-rate",
    );
    const seed_inputs = [_]TransactionSeedInput{.{
        .filing_field = filing_field,
        .role = .filer,
        .semantic_key = .special_rate_basis,
        .origin = .tax_form_profile_revision,
    }};
    input.transaction_seeds = &seed_inputs;
    var result = try composeDefinition(
        std.testing.allocator,
        &input,
        &definition,
    );
    try result.filing_owned_values.set(
        &filing_field,
        .{ .text = try provenance.OwnedText.copy("edited-in-filing") },
    );
    try std.testing.expectEqualStrings(
        "seed-value",
        result.provenance_snapshot.transactionSeedForField(
            &filing_field,
        ).?.copied_seed_value.text.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "edited-in-filing",
        result.filing_owned_values.get(&filing_field).?.value.text.asSlice(),
    );
}
