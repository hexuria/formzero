//! Date-effective validation for saved Tax Form Profile references.
//!
//! Primitive yearly values are self-contained in the confirmed revision. The
//! only external binding that remains is a named profile role (currently the
//! optional spouse on 1701/1701Q), so readiness never depends on Registration
//! activities or tax-obligation anchors.

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
};

pub const Result = struct {
    status: Status = .ready,
    issue: ?Issue = null,
    spouse_profile_id: ?model.ProfileId = null,

    fn needsSetup(issue: Issue) Result {
        return .{ .status = .needs_setup, .issue = issue };
    }
};

/// Persistence-independent lookup for named profile bindings.
pub const Lookup = struct {
    context: *anyopaque,
    profile_subject_kind_fn: *const fn (
        context: *anyopaque,
        profile_id: model.ProfileId,
        on: model.Date,
    ) anyerror!?model.SubjectKind,

    fn profileSubjectKind(
        self: Lookup,
        profile_id: model.ProfileId,
        on: model.Date,
    ) !?model.SubjectKind {
        return self.profile_subject_kind_fn(self.context, profile_id, on);
    }
};

pub const ResolveArgs = struct {
    form: *const catalog.FormDefinition,
    filer_profile_id: model.ProfileId,
    on: model.Date,
    saved_revision: ?*const tax_form_profile.Revision,
};

/// Resolves one effective saved revision. A missing revision blocks only when
/// the generated setup contract contains a required value.
pub fn resolve(args: ResolveArgs, lookup: Lookup) !Result {
    if (args.form.tax_form_profile.mode != .setup) return .{};
    const saved = args.saved_revision orelse return if (hasRequiredValue(
        &args.form.tax_form_profile,
    )) Result.needsSetup(.missing_revision) else .{};

    try saved.validate(args.form);
    if (!saved.effectiveOn(args.on)) return error.NoEffectiveRevision;
    if (saved.review_state != .confirmed) {
        return .{ .status = .requires_review };
    }

    var result: Result = .{};
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
    return result;
}

fn hasRequiredValue(spec: *const catalog.TaxFormProfileSpec) bool {
    for (spec.values) |value| {
        if (value.availability == .supported and value.presence == .required) {
            return true;
        }
    }
    return false;
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

const fixture_values = [_]catalog.TaxFormProfileValueDefinition{.{
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
}};

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
    spouse_profile_active: bool = true,

    fn lookup(self: *FakeLookup) Lookup {
        return .{
            .context = self,
            .profile_subject_kind_fn = profileSubjectKind,
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
            .form_code = try tax_form_profile.FormCode.parse(fixture_form.code),
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

test "confirmed named profile binding resolves without registration facts" {
    const filer = try model.ProfileId.parse("resolver-filer");
    const spouse = try model.ProfileId.parse("resolver-spouse");
    const values = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .spouse_profile_id,
        .role = .spouse,
        .value = .{ .profile_id = spouse },
    }};
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
    }, facts.lookup());
    try @import("std").testing.expectEqual(Status.ready, resolved.status);
    try @import("std").testing.expect(resolved.spouse_profile_id.?.eql(&spouse));
}

test "missing named profile makes confirmed setup need repair" {
    const filer = try model.ProfileId.parse("resolver-filer");
    const spouse = try model.ProfileId.parse("resolver-spouse");
    const values = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .spouse_profile_id,
        .role = .spouse,
        .value = .{ .profile_id = spouse },
    }};
    const revision = try fixtureRevision(filer, &values);
    var facts: FakeLookup = .{
        .filer_profile_id = filer,
        .spouse_profile_id = spouse,
        .spouse_profile_active = false,
    };

    const resolved = try resolve(.{
        .form = &fixture_form,
        .filer_profile_id = filer,
        .on = try model.Date.parseIso("2026-08-04"),
        .saved_revision = &revision,
    }, facts.lookup());
    try @import("std").testing.expectEqual(Status.needs_setup, resolved.status);
    try @import("std").testing.expectEqual(
        @as(?Issue, .named_profile_unresolved),
        resolved.issue,
    );
}
