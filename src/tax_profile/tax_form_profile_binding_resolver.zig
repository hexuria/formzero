//! Date-effective validation for saved Tax Form Profile bindings.
//!
//! A confirmed annual revision proves only that its identifiers matched the
//! generated setup contract when it was saved. Filing readiness additionally
//! requires every referenced profile, business activity, and registration
//! obligation to still resolve on the exact activation/filing date. This
//! allocation-free resolver is shared by library cards, the Tax Form Profile
//! page, and form launch so those surfaces cannot disagree about the same
//! saved revision.

const std = @import("std");
const catalog = @import("../forms/generated/catalog.zig");
const model = @import("model.zig");
const tax_form_profile = @import("tax_form_profile.zig");

pub const Status = enum {
    ready,
    needs_setup,
    requires_review,
};

pub const Issue = enum {
    missing_revision,
    named_profile_unresolved,
    named_profile_ineligible,
    named_profile_not_distinct,
    binding_owner_unresolved,
    business_activity_unresolved,
    registration_obligation_unresolved,
    required_activity_unresolved,
};

pub const Result = struct {
    status: Status = .ready,
    issue: ?Issue = null,
    spouse_profile_id: ?model.ProfileId = null,
    filer_activity_id: ?model.BusinessActivityId = null,
    spouse_activity_id: ?model.BusinessActivityId = null,

    fn needsSetup(issue: Issue) Result {
        return .{ .status = .needs_setup, .issue = issue };
    }
};

/// Persistence-independent lookups. The application adapter supplies exact
/// store-backed functions; tests can supply bounded in-memory facts.
pub const Lookup = struct {
    context: *anyopaque,
    profile_subject_kind_fn: *const fn (
        context: *anyopaque,
        profile_id: model.ProfileId,
        on: model.Date,
    ) anyerror!?model.SubjectKind,
    business_activity_fn: *const fn (
        context: *anyopaque,
        owner_profile_id: model.ProfileId,
        anchor_id: []const u8,
        on: model.Date,
    ) anyerror!?model.BusinessActivityId,
    registration_obligation_fn: *const fn (
        context: *anyopaque,
        owner_profile_id: model.ProfileId,
        semantic_key: catalog.TaxFormProfileSemanticKey,
        anchor_id: []const u8,
        on: model.Date,
    ) anyerror!bool,

    fn profileSubjectKind(
        self: Lookup,
        profile_id: model.ProfileId,
        on: model.Date,
    ) !?model.SubjectKind {
        return self.profile_subject_kind_fn(self.context, profile_id, on);
    }

    fn businessActivity(
        self: Lookup,
        owner_profile_id: model.ProfileId,
        anchor_id: []const u8,
        on: model.Date,
    ) !?model.BusinessActivityId {
        return self.business_activity_fn(
            self.context,
            owner_profile_id,
            anchor_id,
            on,
        );
    }

    fn registrationObligation(
        self: Lookup,
        owner_profile_id: model.ProfileId,
        semantic_key: catalog.TaxFormProfileSemanticKey,
        anchor_id: []const u8,
        on: model.Date,
    ) !bool {
        return self.registration_obligation_fn(
            self.context,
            owner_profile_id,
            semantic_key,
            anchor_id,
            on,
        );
    }
};

pub const ResolveArgs = struct {
    form: *const catalog.FormDefinition,
    filer_profile_id: model.ProfileId,
    on: model.Date,
    saved_revision: ?*const tax_form_profile.Revision,
    /// Runtime composition may require a filer activity even when the catalog
    /// correctly marks its persisted selector as conditional.
    activity_selection_required: bool = false,
};

/// Resolves one effective saved annual revision. A missing optional revision
/// remains ready unless runtime composition explicitly requires an activity;
/// once a revision exists, every binding it declares must resolve exactly.
pub fn resolve(args: ResolveArgs, lookup: Lookup) !Result {
    if (args.form.tax_form_profile.mode != .setup) return .{};
    const saved = args.saved_revision orelse return if (args.activity_selection_required)
        Result.needsSetup(.missing_revision)
    else
        .{};

    try saved.validate(args.form);
    if (!saved.effectiveOn(args.on)) return error.NoEffectiveRevision;
    if (saved.review_state != .confirmed) {
        return .{ .status = .requires_review };
    }

    var result: Result = .{};

    // Named roles must be resolved before activity bindings because catalog
    // value order is not an ownership contract.
    for (saved.values) |*value| {
        const value_definition = findValueDefinition(
            &args.form.tax_form_profile,
            value.role,
            value.semantic_key,
        ) orelse return error.UnknownSemanticKey;
        if (value_definition.source_kind != .named_profile_role) continue;
        const profile_id = switch (value.value) {
            .profile_id => |id| id,
            else => return error.WrongValueType,
        };
        const subject_kind = (try lookup.profileSubjectKind(
            profile_id,
            args.on,
        )) orelse return Result.needsSetup(.named_profile_unresolved);
        const role_definition = findProfileRole(args.form, value.role) orelse
            return error.WrongRole;
        if (!roleAllowsSubject(role_definition, subject_kind)) {
            return Result.needsSetup(.named_profile_ineligible);
        }
        for (role_definition.distinct_from) |other_role| {
            const other_id = profileForRole(
                saved.values,
                args.filer_profile_id,
                other_role,
            ) orelse continue;
            if (profile_id.eql(&other_id)) {
                return Result.needsSetup(.named_profile_not_distinct);
            }
        }
        if (value.role == .spouse) result.spouse_profile_id = profile_id;
    }

    for (saved.values) |*value| {
        const value_definition = findValueDefinition(
            &args.form.tax_form_profile,
            value.role,
            value.semantic_key,
        ) orelse return error.UnknownSemanticKey;
        const owner_profile_id = profileForRole(
            saved.values,
            args.filer_profile_id,
            value.role,
        );
        switch (value_definition.source_kind) {
            .business_activity_anchor => {
                const owner = owner_profile_id orelse
                    return Result.needsSetup(.binding_owner_unresolved);
                const anchor = switch (value.value) {
                    .business_activity_anchor_id => |*id| id.asSlice(),
                    else => return error.WrongValueType,
                };
                const activity_id = (try lookup.businessActivity(
                    owner,
                    anchor,
                    args.on,
                )) orelse return Result.needsSetup(
                    .business_activity_unresolved,
                );
                switch (value.role) {
                    .filer => result.filer_activity_id = activity_id,
                    .spouse => result.spouse_activity_id = activity_id,
                    else => {},
                }
            },
            .registration_obligation_anchor => {
                const owner = owner_profile_id orelse
                    return Result.needsSetup(.binding_owner_unresolved);
                const anchor = switch (value.value) {
                    .registration_obligation_anchor_id => |*id| id.asSlice(),
                    else => return error.WrongValueType,
                };
                if (!try lookup.registrationObligation(
                    owner,
                    value.semantic_key,
                    anchor,
                    args.on,
                )) return Result.needsSetup(
                    .registration_obligation_unresolved,
                );
            },
            .named_profile_role, .user_entry, .catalog_default => {},
        }
    }

    if (args.activity_selection_required and
        result.filer_activity_id == null)
    {
        return Result.needsSetup(.required_activity_unresolved);
    }
    return result;
}

fn findValueDefinition(
    spec: *const catalog.TaxFormProfileSpec,
    role: catalog.Role,
    semantic_key: catalog.TaxFormProfileSemanticKey,
) ?*const catalog.TaxFormProfileValueDefinition {
    for (spec.values) |*definition| {
        if (definition.role == role and
            definition.semantic_key == semantic_key)
        {
            return definition;
        }
    }
    return null;
}

fn findProfileRole(
    form: *const catalog.FormDefinition,
    role: catalog.Role,
) ?*const catalog.ProfileRoleDefinition {
    for (form.profile_roles) |*definition| {
        if (definition.role == role) return definition;
    }
    return null;
}

fn profileForRole(
    values: []const tax_form_profile.SetupValue,
    filer_profile_id: model.ProfileId,
    role: catalog.Role,
) ?model.ProfileId {
    if (role == .filer) return filer_profile_id;
    for (values) |value| {
        if (value.role != role) continue;
        switch (value.value) {
            .profile_id => |profile_id| return profile_id,
            else => {},
        }
    }
    return null;
}

fn roleAllowsSubject(
    role: *const catalog.ProfileRoleDefinition,
    subject_kind: model.SubjectKind,
) bool {
    const catalog_kind: catalog.ProfileSubjectKind = switch (subject_kind) {
        .individual => .individual,
        .sole_proprietor => .sole_proprietor,
        .corporation => .corporation,
        .partnership => .partnership,
        .cooperative => .cooperative,
        .estate => .estate,
        .trust => .trust,
        .other_legal_entity => .other_legal_entity,
    };
    for (role.allowed_subjects) |allowed| {
        if (allowed == catalog_kind) return true;
    }
    return false;
}

const fixture_profile_roles = [_]catalog.ProfileRoleDefinition{
    .{
        .role = .filer,
        .cardinality = .exactly_one,
        .allowed_subjects = &.{.sole_proprietor},
        .distinct_from = &.{},
    },
    .{
        .role = .spouse,
        .cardinality = .zero_or_one,
        .allowed_subjects = &.{ .individual, .sole_proprietor },
        .distinct_from = &.{.filer},
    },
};

const fixture_values = [_]catalog.TaxFormProfileValueDefinition{
    .{
        .semantic_key = .spouse_profile_id,
        .value_type = .profile_id,
        .role = .spouse,
        .presence = .optional,
        .validation_rule = .distinct_profile_role,
        .ownership = .binding_selection,
        .source_kind = .named_profile_role,
        .availability = .supported,
        .source_evidence = "resolver fixture",
        .evidence_gate = null,
    },
    .{
        .semantic_key = .business_activity_anchor_id,
        .value_type = .business_activity_anchor_id,
        .role = .filer,
        .presence = .conditional,
        .validation_rule = .effective_business_activity,
        .ownership = .binding_selection,
        .source_kind = .business_activity_anchor,
        .availability = .supported,
        .source_evidence = "resolver fixture",
        .evidence_gate = null,
    },
    .{
        .semantic_key = .spouse_business_activity_anchor_id,
        .value_type = .business_activity_anchor_id,
        .role = .spouse,
        .presence = .conditional,
        .validation_rule = .effective_business_activity,
        .ownership = .binding_selection,
        .source_kind = .business_activity_anchor,
        .availability = .supported,
        .source_evidence = "resolver fixture",
        .evidence_gate = null,
    },
    .{
        .semantic_key = .special_rate_obligation_anchor_id,
        .value_type = .registration_obligation_anchor_id,
        .role = .filer,
        .presence = .conditional,
        .validation_rule = .effective_registration_obligation,
        .ownership = .binding_selection,
        .source_kind = .registration_obligation_anchor,
        .availability = .supported,
        .source_evidence = "resolver fixture",
        .evidence_gate = null,
    },
};

const fixture_form: catalog.FormDefinition = .{
    .code = "FIXTURE",
    .display_title = "Binding resolver fixture",
    .tax_category = .income_tax,
    .revision = "2026-TEST",
    .status = .static_layout,
    .cadence = .annual,
    .min_period = null,
    .max_period = null,
    .source_path = null,
    .roles = &.{ .filer, .spouse },
    .profile_roles = &fixture_profile_roles,
    .consumed_taxpayer_year_settings = &.{},
    .tax_form_profile = .{
        .mode = .setup,
        .spec_revision = 1,
        .spec_hash = "fixture-spec-hash",
        .source_evidence = "resolver fixture",
        .values = &fixture_values,
    },
    .fields = &.{},
};

const FakeLookup = struct {
    filer_profile_id: model.ProfileId,
    spouse_profile_id: model.ProfileId,
    filer_activity_active: bool = true,
    spouse_activity_active: bool = true,
    obligation_active: bool = true,
    spouse_profile_active: bool = true,

    fn lookup(self: *FakeLookup) Lookup {
        return .{
            .context = self,
            .profile_subject_kind_fn = profileSubjectKind,
            .business_activity_fn = businessActivity,
            .registration_obligation_fn = registrationObligation,
        };
    }

    fn profileSubjectKind(
        context: *anyopaque,
        profile_id: model.ProfileId,
        on: model.Date,
    ) !?model.SubjectKind {
        _ = on;
        const self: *FakeLookup = @ptrCast(@alignCast(context));
        if (profile_id.eql(&self.filer_profile_id)) return .sole_proprietor;
        if (profile_id.eql(&self.spouse_profile_id) and
            self.spouse_profile_active)
        {
            return .individual;
        }
        return null;
    }

    fn businessActivity(
        context: *anyopaque,
        owner_profile_id: model.ProfileId,
        anchor_id: []const u8,
        on: model.Date,
    ) !?model.BusinessActivityId {
        _ = on;
        const self: *FakeLookup = @ptrCast(@alignCast(context));
        if (owner_profile_id.eql(&self.filer_profile_id) and
            std.mem.eql(u8, anchor_id, "filer-activity") and
            self.filer_activity_active)
        {
            return @as(
                ?model.BusinessActivityId,
                try model.BusinessActivityId.parse(anchor_id),
            );
        }
        if (owner_profile_id.eql(&self.spouse_profile_id) and
            std.mem.eql(u8, anchor_id, "spouse-activity") and
            self.spouse_activity_active)
        {
            return @as(
                ?model.BusinessActivityId,
                try model.BusinessActivityId.parse(anchor_id),
            );
        }
        return null;
    }

    fn registrationObligation(
        context: *anyopaque,
        owner_profile_id: model.ProfileId,
        semantic_key: catalog.TaxFormProfileSemanticKey,
        anchor_id: []const u8,
        on: model.Date,
    ) !bool {
        if (semantic_key != .special_rate_obligation_anchor_id) return false;
        _ = on;
        const self: *FakeLookup = @ptrCast(@alignCast(context));
        return owner_profile_id.eql(&self.filer_profile_id) and
            std.mem.eql(u8, anchor_id, "special-rate") and
            self.obligation_active;
    }
};

fn fixtureRevision(
    filer_profile_id: model.ProfileId,
    values: []const tax_form_profile.SetupValue,
) !tax_form_profile.Revision {
    return .{
        .id = try tax_form_profile.RevisionId.parse("fixture-revision"),
        .stream = .{
            .profile_id = filer_profile_id,
            .tax_year = 2026,
            .form_code = try tax_form_profile.FormCode.parse(
                fixture_form.code,
            ),
            .form_revision = try tax_form_profile.FormRevision.parse(
                fixture_form.revision.?,
            ),
        },
        .sequence = 1,
        .effective = try tax_form_profile.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .spec_revision = fixture_form.tax_form_profile.spec_revision.?,
        .spec_hash = try tax_form_profile.SpecHash.parse(
            fixture_form.tax_form_profile.spec_hash.?,
        ),
        .review_state = .confirmed,
        .confirmed_at_unix = 1,
        .source = .manual_entry,
        .values = values,
    };
}

fn fixtureSetupValues(
    spouse_profile_id: model.ProfileId,
) ![4]tax_form_profile.SetupValue {
    return .{
        .{
            .semantic_key = .spouse_profile_id,
            .role = .spouse,
            .value = .{ .profile_id = spouse_profile_id },
        },
        .{
            .semantic_key = .business_activity_anchor_id,
            .role = .filer,
            .value = .{
                .business_activity_anchor_id = try tax_form_profile
                    .ComponentAnchorId.parse("filer-activity"),
            },
        },
        .{
            .semantic_key = .spouse_business_activity_anchor_id,
            .role = .spouse,
            .value = .{
                .business_activity_anchor_id = try tax_form_profile
                    .ComponentAnchorId.parse("spouse-activity"),
            },
        },
        .{
            .semantic_key = .special_rate_obligation_anchor_id,
            .role = .filer,
            .value = .{
                .registration_obligation_anchor_id = try tax_form_profile
                    .ComponentAnchorId.parse("special-rate"),
            },
        },
    };
}

test "confirmed bindings are ready only when every declared source resolves" {
    const filer = try model.ProfileId.parse("resolver-filer");
    const spouse = try model.ProfileId.parse("resolver-spouse");
    const values = try fixtureSetupValues(spouse);
    const revision = try fixtureRevision(filer, &values);
    var facts: FakeLookup = .{
        .filer_profile_id = filer,
        .spouse_profile_id = spouse,
    };

    const resolved = try resolve(.{
        .form = &fixture_form,
        .filer_profile_id = filer,
        .on = try model.Date.parseIso("2026-08-04"),
        .saved_revision = &revision,
        .activity_selection_required = true,
    }, facts.lookup());
    try std.testing.expectEqual(Status.ready, resolved.status);
    try std.testing.expect(resolved.issue == null);
    try std.testing.expect(resolved.spouse_profile_id.?.eql(&spouse));
    try std.testing.expectEqualStrings(
        "filer-activity",
        resolved.filer_activity_id.?.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "spouse-activity",
        resolved.spouse_activity_id.?.asSlice(),
    );
}

test "retired filer or spouse activity makes confirmed setup need repair" {
    const filer = try model.ProfileId.parse("resolver-filer");
    const spouse = try model.ProfileId.parse("resolver-spouse");
    const values = try fixtureSetupValues(spouse);
    const revision = try fixtureRevision(filer, &values);
    var facts: FakeLookup = .{
        .filer_profile_id = filer,
        .spouse_profile_id = spouse,
        .filer_activity_active = false,
    };
    var resolved = try resolve(.{
        .form = &fixture_form,
        .filer_profile_id = filer,
        .on = try model.Date.parseIso("2026-08-04"),
        .saved_revision = &revision,
    }, facts.lookup());
    try std.testing.expectEqual(Status.needs_setup, resolved.status);
    try std.testing.expectEqual(
        @as(?Issue, .business_activity_unresolved),
        resolved.issue,
    );

    facts.filer_activity_active = true;
    facts.spouse_activity_active = false;
    resolved = try resolve(.{
        .form = &fixture_form,
        .filer_profile_id = filer,
        .on = try model.Date.parseIso("2026-08-04"),
        .saved_revision = &revision,
    }, facts.lookup());
    try std.testing.expectEqual(Status.needs_setup, resolved.status);
    try std.testing.expectEqual(
        @as(?Issue, .business_activity_unresolved),
        resolved.issue,
    );
}

test "missing spouse profile or registration obligation cannot stay ready" {
    const filer = try model.ProfileId.parse("resolver-filer");
    const spouse = try model.ProfileId.parse("resolver-spouse");
    const values = try fixtureSetupValues(spouse);
    const revision = try fixtureRevision(filer, &values);
    var facts: FakeLookup = .{
        .filer_profile_id = filer,
        .spouse_profile_id = spouse,
        .spouse_profile_active = false,
    };
    var resolved = try resolve(.{
        .form = &fixture_form,
        .filer_profile_id = filer,
        .on = try model.Date.parseIso("2026-08-04"),
        .saved_revision = &revision,
    }, facts.lookup());
    try std.testing.expectEqual(Status.needs_setup, resolved.status);
    try std.testing.expectEqual(
        @as(?Issue, .named_profile_unresolved),
        resolved.issue,
    );

    facts.spouse_profile_active = true;
    facts.obligation_active = false;
    resolved = try resolve(.{
        .form = &fixture_form,
        .filer_profile_id = filer,
        .on = try model.Date.parseIso("2026-08-04"),
        .saved_revision = &revision,
    }, facts.lookup());
    try std.testing.expectEqual(Status.needs_setup, resolved.status);
    try std.testing.expectEqual(
        @as(?Issue, .registration_obligation_unresolved),
        resolved.issue,
    );
}
