//! Generic profile projection for every Native editor in the generated catalog.
//!
//! The TypeScript catalog records concrete form targets while
//! `tax_profile.field.ReusableField` is the canonical reusable vocabulary.
//! This module is the deliberately small bridge between those two layers:
//! it considers only fields whose catalog provenance is `.profile`, resolves
//! each target from an explicitly named profile binding, and copies the value
//! and provenance into an owned result.
//!
//! Catalog order is retained and entries are never deduplicated by reusable
//! source. A form may therefore project the same reusable fact into several
//! distinct concrete targets without losing any of them.

const std = @import("std");
const catalog = @import("generated/catalog.zig");
const ids = @import("id.zig");
const spec = @import("spec.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");
const capability = @import("../tax_profile/capability.zig");
const projection = @import("../tax_profile/projection.zig");

/// A closed, local representation of the generated catalog's string keys.
///
/// Keeping this separate from `ReusableField` makes the conversion explicit:
/// catalog strings are parsed at the boundary and then exhaustively mapped to
/// the domain vocabulary.
pub const CatalogProfileKey = enum {
    tin,
    rdo_code,
    taxpayer_name,
    registered_name,
    registered_address,
    zip_code,
    contact_number,
    email_address,
    date_of_birth,
    citizenship,
    foreign_tax_number,
    line_of_business,
    atc,
    tax_type,
    government_withholding_agent,
    special_rate_basis,
};

comptime {
    if (std.meta.fields(CatalogProfileKey).len !=
        std.meta.fields(field.ReusableField).len)
    {
        @compileError(
            "catalog profile-key bridge no longer covers ReusableField",
        );
    }
    if (std.meta.fields(catalog.ProfileSubjectKind).len !=
        std.meta.fields(model.SubjectKind).len)
    {
        @compileError(
            "catalog subject-kind bridge no longer covers SubjectKind",
        );
    }
}

/// Convert a generated `profile_key` string into the canonical domain field.
/// Unknown strings are rejected; they are never treated as generic text.
pub fn reusableField(raw: []const u8) ?field.ReusableField {
    const key = std.meta.stringToEnum(CatalogProfileKey, raw) orelse
        return null;
    return switch (key) {
        .tin => .tin,
        .rdo_code => .rdo_code,
        .taxpayer_name => .taxpayer_name,
        .registered_name => .registered_name,
        .registered_address => .registered_address,
        .zip_code => .zip_code,
        .contact_number => .contact_number,
        .email_address => .email_address,
        .date_of_birth => .date_of_birth,
        .citizenship => .citizenship,
        .foreign_tax_number => .foreign_tax_number,
        .line_of_business => .line_of_business,
        .atc => .atc,
        .tax_type => .tax_type,
        .government_withholding_agent => .government_withholding_agent,
        .special_rate_basis => .special_rate_basis,
    };
}

/// Map generated roles that have a canonical domain-role counterpart.
///
/// Filing, payment, evidence, and system roles intentionally return `null`:
/// they are not profile bindings. The catalog generator currently permits
/// `.profile` provenance only for filer and spouse targets.
pub fn domainRole(role: catalog.Role) ?ids.Role {
    return switch (role) {
        .filer => .filer,
        .spouse => .spouse,
        .employer => .employer,
        .filing,
        .payment,
        .preparer,
        .withholding_agent,
        .attachment,
        .evidence,
        .system,
        => null,
    };
}

/// Convert generated subject policy into the canonical profile subject kind.
pub fn domainSubjectKind(
    kind: catalog.ProfileSubjectKind,
) model.SubjectKind {
    return switch (kind) {
        .individual => .individual,
        .sole_proprietor => .sole_proprietor,
        .corporation => .corporation,
        .partnership => .partnership,
        .estate => .estate,
        .trust => .trust,
        .other_legal_entity => .other_legal_entity,
    };
}

pub const Binding = projection.Binding;
pub const Entry = projection.SnapshotEntry;

pub const TargetContext = struct {
    role: ids.Role,
    target: ids.FieldId,
    reusable_field: field.ReusableField,
};

/// Projection failures retain the exact role and target whenever the problem
/// is target-specific. No missing or ambiguous value is silently defaulted.
pub const Issue = union(enum) {
    missing_binding: TargetContext,
    duplicate_binding: ids.Role,
    unexpected_binding: ids.Role,
    same_profile_binding: struct {
        left: ids.Role,
        right: ids.Role,
    },
    invalid_revision: struct {
        role: ids.Role,
        reason: model.RevisionError,
    },
    revision_not_effective: struct {
        role: ids.Role,
        revision_id: model.RevisionId,
    },
    subject_not_allowed: struct {
        role: ids.Role,
        subject: model.SubjectKind,
    },
    missing_capability: TargetContext,
    ambiguous_business_activity: TargetContext,
    unknown_business_activity: TargetContext,
    inactive_business_activity: TargetContext,
};

pub const OwnedProjection = struct {
    form: ids.FormRevision,
    effective_on: model.Date,
    entries: []Entry,

    pub fn deinit(self: *OwnedProjection, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
        self.* = undefined;
    }

    pub fn slice(self: *const OwnedProjection) []const Entry {
        return self.entries;
    }
};

pub const OwnedRejection = struct {
    issues: []Issue,

    pub fn deinit(self: *OwnedRejection, allocator: std.mem.Allocator) void {
        allocator.free(self.issues);
        self.* = undefined;
    }

    pub fn slice(self: *const OwnedRejection) []const Issue {
        return self.issues;
    }
};

pub const Result = union(enum) {
    accepted: OwnedProjection,
    rejected: OwnedRejection,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .accepted => |*accepted| accepted.deinit(allocator),
            .rejected => |*rejected| rejected.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const Error = std.mem.Allocator.Error || ids.Error || error{
    UnknownForm,
    CalendarOnlyForm,
    RevisionMismatch,
    UnknownCatalogProfileKey,
    UnsupportedCatalogProfileRole,
    MissingCatalogProfileRoleSpec,
    DuplicateCatalogProfileRoleSpec,
    MissingCatalogProfilePresence,
};

const RoleState = struct {
    policy: ?*const catalog.ProfileRoleDefinition = null,
    count: usize = 0,
    binding: ?Binding = null,
    usable: bool = false,
};

/// Project all direct profile targets for one exact editor revision.
///
/// `bindings` is a named map expressed as a slice: position has no meaning.
/// Each binding independently carries the selected business activity. A sole
/// effective activity may be resolved by the domain capability layer; two or
/// more effective activities without a selection produce an explicit issue.
pub fn project(
    allocator: std.mem.Allocator,
    form_revision: ids.FormRevision,
    bindings: []const Binding,
    effective_on: model.Date,
) Error!Result {
    const definition = catalog.findForm(form_revision.code.asSlice()) orelse
        return error.UnknownForm;
    if (definition.status != .static_layout) {
        return error.CalendarOnlyForm;
    }
    const catalog_revision = definition.revision orelse
        return error.CalendarOnlyForm;
    if (!std.mem.eql(
        u8,
        catalog_revision,
        form_revision.revision.asSlice(),
    )) {
        return error.RevisionMismatch;
    }

    const role_count = std.meta.fields(ids.Role).len;
    var states = [_]RoleState{.{}} ** role_count;

    for (definition.profile_roles) |*profile_role| {
        const role = domainRole(profile_role.role) orelse
            return error.UnsupportedCatalogProfileRole;
        const state = &states[@intFromEnum(role)];
        if (state.policy != null) {
            return error.DuplicateCatalogProfileRoleSpec;
        }
        state.policy = profile_role;
    }

    // Validate the generated bridge before consulting any runtime profile.
    for (definition.fields) |catalog_field| {
        if (catalog_field.provenance != .profile) continue;
        const raw_key = catalog_field.profile_key orelse
            return error.UnknownCatalogProfileKey;
        _ = reusableField(raw_key) orelse
            return error.UnknownCatalogProfileKey;
        const role = domainRole(catalog_field.role) orelse
            return error.UnsupportedCatalogProfileRole;
        if (states[@intFromEnum(role)].policy == null) {
            return error.MissingCatalogProfileRoleSpec;
        }
        _ = catalog_field.profile_presence orelse
            return error.MissingCatalogProfilePresence;
        _ = try ids.FieldId.parse(catalog_field.id);
    }

    var issues: std.ArrayList(Issue) = .empty;
    defer issues.deinit(allocator);

    for (bindings) |binding| {
        const index = @intFromEnum(binding.role);
        if (states[index].policy == null) {
            try issues.append(
                allocator,
                .{ .unexpected_binding = binding.role },
            );
            continue;
        }
        states[index].count += 1;
        if (states[index].count == 1) {
            states[index].binding = binding;
        }
    }

    var entries: std.ArrayList(Entry) = .empty;
    defer entries.deinit(allocator);

    for (definition.profile_roles) |*profile_role| {
        const role = domainRole(profile_role.role) orelse
            return error.UnsupportedCatalogProfileRole;
        const state = states[@intFromEnum(role)];
        if (state.count != 1) continue;
        for (profile_role.distinct_from) |other_catalog_role| {
            const other_role = domainRole(other_catalog_role) orelse
                return error.UnsupportedCatalogProfileRole;
            const other_state = states[@intFromEnum(other_role)];
            if (other_state.count != 1) continue;
            if (state.binding.?.revision.profile_id.eql(
                &other_state.binding.?.revision.profile_id,
            )) {
                try issues.append(allocator, .{
                    .same_profile_binding = .{
                        .left = role,
                        .right = other_role,
                    },
                });
            }
        }
    }

    for (std.meta.tags(ids.Role)) |role| {
        const index = @intFromEnum(role);
        if (states[index].policy == null) continue;
        var state = &states[index];
        if (state.count == 0) continue;
        if (state.count > 1) {
            try issues.append(allocator, .{ .duplicate_binding = role });
            continue;
        }

        const binding = state.binding.?;
        binding.revision.validate() catch |reason| {
            try issues.append(allocator, .{ .invalid_revision = .{
                .role = role,
                .reason = reason,
            } });
            continue;
        };
        if (!binding.revision.isEffective(effective_on)) {
            try issues.append(allocator, .{ .revision_not_effective = .{
                .role = role,
                .revision_id = binding.revision.id,
            } });
            continue;
        }
        const subject = binding.revision.subject.kind();
        if (!allowsSubject(state.policy.?, subject)) {
            try issues.append(allocator, .{ .subject_not_allowed = .{
                .role = role,
                .subject = subject,
            } });
            continue;
        }
        state.usable = true;
    }

    for (definition.fields) |catalog_field| {
        // This is the hard provenance boundary. Transaction, derived,
        // filing-context, and external fields never reach the resolver.
        if (catalog_field.provenance != .profile) continue;

        const reusable_field = reusableField(catalog_field.profile_key.?) orelse
            unreachable;
        const role = domainRole(catalog_field.role) orelse unreachable;
        const target = try ids.FieldId.parse(catalog_field.id);
        const context: TargetContext = .{
            .role = role,
            .target = target,
            .reusable_field = reusable_field,
        };
        const state = states[@intFromEnum(role)];

        if (state.count == 0) {
            if (state.policy.?.cardinality == .exactly_one) {
                try issues.append(allocator, .{ .missing_binding = context });
            }
            continue;
        }
        if (state.count > 1 or !state.usable) continue;

        const binding = state.binding.?;
        const value = capability.valueFor(
            binding.revision,
            reusable_field,
            effective_on,
            binding.selection,
        ) catch |reason| {
            try issues.append(allocator, switch (reason) {
                error.BusinessActivitySelectionRequired => .{
                    .ambiguous_business_activity = context,
                },
                error.UnknownBusinessActivity => .{
                    .unknown_business_activity = context,
                },
                error.InactiveBusinessActivity => .{
                    .inactive_business_activity = context,
                },
            });
            continue;
        };
        if (value == null) {
            if (catalog_field.profile_presence == .required) {
                try issues.append(
                    allocator,
                    .{ .missing_capability = context },
                );
            }
            continue;
        }

        // Append once per catalog field, not once per reusable source.
        try entries.append(allocator, .{
            .role = role,
            .target = target,
            .value = value.?,
            .provenance = provenanceFor(
                binding,
                reusable_field,
                effective_on,
            ),
        });
    }

    if (issues.items.len != 0) {
        return .{ .rejected = .{
            .issues = try issues.toOwnedSlice(allocator),
        } };
    }
    return .{ .accepted = .{
        .form = form_revision,
        .effective_on = effective_on,
        .entries = try entries.toOwnedSlice(allocator),
    } };
}

fn allowsSubject(
    policy: *const catalog.ProfileRoleDefinition,
    subject: model.SubjectKind,
) bool {
    for (policy.allowed_subjects) |allowed| {
        if (domainSubjectKind(allowed) == subject) return true;
    }
    return false;
}

fn provenanceFor(
    binding: Binding,
    reusable_field: field.ReusableField,
    effective_on: model.Date,
) projection.Provenance {
    var business_activity_id: ?model.BusinessActivityId = null;
    var registration_fact_id: ?model.RegistrationFactId = null;

    if (reusable_field == .atc or reusable_field == .line_of_business) {
        const activity = capability.resolveBusinessActivity(
            binding.revision,
            effective_on,
            binding.selection,
        ) catch unreachable;
        if (activity) |selected| business_activity_id = selected.id;
    }

    const fact_kind: ?model.RegistrationFactKind = switch (reusable_field) {
        .tax_type => .tax_type,
        .government_withholding_agent => .government_withholding_agent,
        .special_rate_basis => .special_rate_basis,
        else => null,
    };
    if (fact_kind) |kind| {
        if (binding.revision.registrationFact(kind, effective_on)) |fact| {
            registration_fact_id = fact.id;
        }
    }

    return .{
        .profile_id = binding.revision.profile_id,
        .revision_id = binding.revision.id,
        .revision_sequence = binding.revision.sequence,
        .revision_source = binding.revision.source,
        .business_activity_id = business_activity_id,
        .registration_fact_id = registration_fact_id,
    };
}

fn typedRevision(
    definition: *const catalog.FormDefinition,
) ids.Error!ids.FormRevision {
    return .{
        .code = try ids.FormCode.parse(definition.code),
        .revision = try ids.RevisionLabel.parse(definition.revision.?),
    };
}

fn expectTypedSpecMatchesCatalog(
    definition: *const catalog.FormDefinition,
    typed: spec.FormSpec,
) !void {
    try std.testing.expectEqualStrings(
        definition.code,
        typed.revision.code.asSlice(),
    );
    try std.testing.expectEqualStrings(
        definition.revision.?,
        typed.revision.revision.asSlice(),
    );
    try std.testing.expectEqual(
        definition.profile_roles.len,
        typed.roles.len,
    );

    var catalog_distinct_count: usize = 0;
    for (definition.profile_roles) |catalog_role| {
        const left = domainRole(catalog_role.role).?;
        for (catalog_role.distinct_from) |other| {
            const right = domainRole(other).?;
            catalog_distinct_count += 1;
            var matched = false;
            for (typed.distinct_profile_roles) |pair| {
                if ((pair.left == left and pair.right == right) or
                    (pair.left == right and pair.right == left))
                {
                    matched = true;
                    break;
                }
            }
            try std.testing.expect(matched);
        }
    }
    try std.testing.expectEqual(
        catalog_distinct_count,
        typed.distinct_profile_roles.len,
    );

    for (typed.roles) |typed_role| {
        var catalog_role: ?*const catalog.ProfileRoleDefinition = null;
        for (definition.profile_roles) |*candidate| {
            if (domainRole(candidate.role) == typed_role.role) {
                catalog_role = candidate;
                break;
            }
        }
        const role_policy = catalog_role orelse
            return error.TestUnexpectedResult;
        try std.testing.expectEqual(
            switch (role_policy.cardinality) {
                .exactly_one => spec.Cardinality.exactly_one,
                .zero_or_one => spec.Cardinality.zero_or_one,
            },
            typed_role.cardinality,
        );
        inline for (std.meta.tags(model.SubjectKind)) |kind| {
            try std.testing.expectEqual(
                allowsSubject(role_policy, kind),
                typed_role.accepts(kind),
            );
        }

        var catalog_target_count: usize = 0;
        for (definition.fields) |catalog_field| {
            if (catalog_field.provenance == .profile and
                domainRole(catalog_field.role) == typed_role.role)
            {
                catalog_target_count += 1;
            }
        }
        try std.testing.expectEqual(
            catalog_target_count,
            typed_role.requirements.len,
        );

        for (typed_role.requirements) |requirement| {
            var matched: ?*const catalog.FieldDefinition = null;
            for (definition.fields) |*catalog_field| {
                if (catalog_field.provenance != .profile) continue;
                if (!std.mem.eql(
                    u8,
                    catalog_field.id,
                    requirement.target.asSlice(),
                )) continue;
                matched = catalog_field;
                break;
            }
            const catalog_target = matched orelse
                return error.TestUnexpectedResult;
            try std.testing.expectEqual(
                typed_role.role,
                domainRole(catalog_target.role).?,
            );
            try std.testing.expectEqual(
                requirement.source,
                reusableField(catalog_target.profile_key.?).?,
            );
            try std.testing.expectEqual(
                requirement.presence,
                switch (catalog_target.profile_presence.?) {
                    .required => spec.Presence.required,
                    .optional => spec.Presence.optional,
                },
            );
        }
    }
}

fn completeRevision(
    profile_id: []const u8,
    revision_id: []const u8,
    tin: []const u8,
    name: []const u8,
    activities: []const model.BusinessActivity,
    facts: []const model.RegistrationFact,
) !model.ProfileRevision {
    return .{
        .profile_id = try model.ProfileId.parse(profile_id),
        .id = try model.RevisionId.parse(revision_id),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse(tin),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse(
                "1 Taxpayer Street",
            ),
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse(
                "taxpayer@example.ph",
            ),
        },
        .subject = .{ .sole_proprietor = .{
            .person = .{
                .name = try field.TaxpayerName.parse(name),
                .date_of_birth = try model.Date.parseIso("1990-06-15"),
                .citizenship = try field.Citizenship.parse("Filipino"),
                .foreign_tax_number = try field.ForeignTaxNumber.parse(
                    "FOREIGN-123",
                ),
            },
            .trade_name = try field.RegisteredName.parse(
                "EXAMPLE TRADING",
            ),
        } },
        .business_activities = activities,
        .registration_facts = facts,
    };
}

fn completeLegalRevision(
    profile_id: []const u8,
    revision_id: []const u8,
    tin: []const u8,
    activities: []const model.BusinessActivity,
    facts: []const model.RegistrationFact,
) !model.ProfileRevision {
    var revision = try completeRevision(
        profile_id,
        revision_id,
        tin,
        "EXAMPLE CORPORATION",
        activities,
        facts,
    );
    revision.subject = .{ .legal_entity = .{
        .registered_name = try field.RegisteredName.parse(
            "EXAMPLE CORPORATION",
        ),
        .kind = .corporation,
    } };
    return revision;
}

fn profileTargetCount(definition: *const catalog.FormDefinition) usize {
    var count: usize = 0;
    for (definition.fields) |catalog_field| {
        if (catalog_field.provenance == .profile) count += 1;
    }
    return count;
}

fn spouseTargetCount(definition: *const catalog.FormDefinition) usize {
    var count: usize = 0;
    for (definition.fields) |catalog_field| {
        if (catalog_field.provenance == .profile and
            catalog_field.role == .spouse)
        {
            count += 1;
        }
    }
    return count;
}

test "closed generated key vocabulary maps exhaustively to ReusableField" {
    try std.testing.expectEqual(
        @as(usize, 16),
        std.meta.fields(CatalogProfileKey).len,
    );

    var mapped = field.FieldSet.initEmpty();
    inline for (std.meta.tags(CatalogProfileKey)) |key| {
        const reusable = reusableField(@tagName(key)) orelse
            return error.TestUnexpectedResult;
        mapped.insert(reusable);
        try std.testing.expectEqualStrings(
            @tagName(key),
            @tagName(reusable),
        );
    }
    try std.testing.expectEqual(@as(usize, 16), mapped.count());
    try std.testing.expect(reusableField("not_a_profile_key") == null);

    var observed = field.FieldSet.initEmpty();
    for (catalog.forms) |definition| {
        for (definition.fields) |catalog_field| {
            if (catalog_field.provenance != .profile) continue;
            observed.insert(
                reusableField(catalog_field.profile_key.?) orelse
                    return error.TestUnexpectedResult,
            );
            const role = domainRole(catalog_field.role) orelse
                return error.TestUnexpectedResult;
            try std.testing.expect(
                role == .filer or role == .spouse,
            );
        }
    }
    // The closed reusable vocabulary remains broader than the fields projected
    // by the ten current editors. ATC and tax type are no longer direct profile
    // targets: their former controls are filing data or locked form policy.
    try std.testing.expectEqual(@as(usize, 14), observed.count());
    try std.testing.expect(!observed.contains(.atc));
    try std.testing.expect(!observed.contains(.tax_type));

    inline for (std.meta.tags(catalog.ProfileSubjectKind)) |kind| {
        try std.testing.expectEqualStrings(
            @tagName(kind),
            @tagName(domainSubjectKind(kind)),
        );
    }
    try std.testing.expectEqual(
        @as(usize, 34),
        catalog.optional_profile_target_count,
    );
}

test "all ten editor revisions project all ninety-one profile targets" {
    const allocator = std.testing.allocator;
    const on = try model.Date.parseIso("2026-03-31");
    const activities = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("activity-retail"),
        .line_of_business = try field.LineOfBusiness.parse("Retail"),
        .atc = try field.Atc.parse("PT010"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    }};
    const facts = [_]model.RegistrationFact{
        .{
            .id = try model.RegistrationFactId.parse("fact-tax-type"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
            .value = .{
                .tax_type = try field.TaxType.parse("Percentage Tax"),
            },
        },
        .{
            .id = try model.RegistrationFactId.parse("fact-gwa"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
            .value = .{ .government_withholding_agent = .yes },
        },
        .{
            .id = try model.RegistrationFactId.parse("fact-special-rate"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
            .value = .{
                .special_rate_basis = try field.SpecialRateBasis.parse(
                    "Treaty registration",
                ),
            },
        },
    };
    var filer = try completeRevision(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
        &activities,
        &facts,
    );
    var spouse = try completeRevision(
        "profile-spouse",
        "revision-spouse",
        "987-654-321-000",
        "ANA DELA CRUZ",
        &activities,
        &facts,
    );
    var legal_filer = try completeLegalRevision(
        "profile-legal-filer",
        "revision-legal-filer",
        "456-789-123-000",
        &activities,
        &facts,
    );
    const person_bindings = [_]Binding{
        .{ .role = .filer, .revision = &filer },
        .{ .role = .spouse, .revision = &spouse },
    };
    const legal_bindings = [_]Binding{
        .{ .role = .filer, .revision = &legal_filer },
    };

    var editor_count: usize = 0;
    var target_count: usize = 0;
    for (&catalog.forms) |*definition| {
        if (definition.status != .static_layout) continue;
        editor_count += 1;
        const bindings: []const Binding =
            if (std.mem.eql(u8, definition.code, "1702MX") or
            std.mem.eql(u8, definition.code, "1702RT"))
                &legal_bindings
            else if (definition.profile_roles.len == 1)
                person_bindings[0..1]
            else
                &person_bindings;

        var result = try project(
            allocator,
            try typedRevision(definition),
            bindings,
            on,
        );
        defer result.deinit(allocator);
        const accepted = switch (result) {
            .accepted => |accepted| accepted,
            .rejected => return error.TestUnexpectedResult,
        };
        const expected = profileTargetCount(definition);
        try std.testing.expectEqual(expected, accepted.entries.len);
        for (definition.fields) |catalog_field| {
            if (catalog_field.provenance != .profile) continue;
            var matching_targets: usize = 0;
            for (accepted.entries) |entry| {
                if (!std.mem.eql(
                    u8,
                    catalog_field.id,
                    entry.target.asSlice(),
                )) continue;
                matching_targets += 1;
                try std.testing.expectEqual(
                    reusableField(catalog_field.profile_key.?).?,
                    entry.value.field(),
                );
                try std.testing.expectEqual(
                    domainRole(catalog_field.role).?,
                    entry.role,
                );
            }
            try std.testing.expectEqual(@as(usize, 1), matching_targets);
        }
        target_count += accepted.entries.len;
    }

    try std.testing.expectEqual(@as(usize, 10), editor_count);
    try std.testing.expectEqual(catalog.editor_count, editor_count);
    try std.testing.expectEqual(@as(usize, 91), target_count);
    try std.testing.expectEqual(catalog.profile_target_count, target_count);
}

test "corrected ownership source contracts stay outside direct profile projection" {
    const Contract = struct {
        code: []const u8,
        id: []const u8,
        provenance: catalog.Provenance,
        source_key: ?[]const u8 = null,
        fixed_value: ?[]const u8 = null,
        optional_seed_source: ?[]const u8 = null,
    };
    const contracts = [_]Contract{
        .{
            .code = "0605",
            .id = "0605.1999-07-ENCS.input.atc_only_source_proven_pairs",
            .provenance = .transaction,
        },
        .{
            .code = "0605",
            .id = "0605.1999-07-ENCS.input.tax_type_only_source_proven_pairs",
            .provenance = .transaction,
        },
        .{
            .code = "0605",
            .id = "0605.1999-07-ENCS.input.line_of_business_occupation",
            .provenance = .transaction,
            .optional_seed_source = "business_activity.line_of_business",
        },
        .{
            .code = "1601C",
            .id = "1601C.2018-01-ENCS.input.atc",
            .provenance = .form_policy,
            .source_key = "form_policy.atc",
            .fixed_value = "WW010",
        },
        .{
            .code = "0619F",
            .id = "0619F.2018-01-ENCS.input.tax_type_code",
            .provenance = .form_policy,
            .source_key = "form_policy.tax_type",
            .fixed_value = "WB",
        },
        .{
            .code = "0619E",
            .id = "0619E.2018-01-ENCS.input.atc",
            .provenance = .form_policy,
            .source_key = "form_policy.atc",
            .fixed_value = "WME10",
        },
        .{
            .code = "0619E",
            .id = "0619E.2018-01-ENCS.input.tax_type_code",
            .provenance = .form_policy,
            .source_key = "form_policy.tax_type",
            .fixed_value = "WE",
        },
        .{
            .code = "1701Q",
            .id = "1701Q.2018-01-ENCS.input.income_tax_rate_election",
            .provenance = .taxpayer_year,
            .source_key = "income_tax_rate_election",
        },
        .{
            .code = "2551Q",
            .id = "2551Q.2018-01-ENCS.input.income_tax_rate_election",
            .provenance = .taxpayer_year,
            .source_key = "income_tax_rate_election",
        },
    };

    for (contracts) |expected| {
        const definition = catalog.findForm(expected.code).?;
        var matched: ?*const catalog.FieldDefinition = null;
        for (definition.fields) |*catalog_field| {
            if (std.mem.eql(u8, catalog_field.id, expected.id)) {
                matched = catalog_field;
                break;
            }
        }
        const actual = matched orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(expected.provenance, actual.provenance);
        try std.testing.expect(actual.profile_key == null);
        if (expected.source_key) |value| {
            try std.testing.expectEqualStrings(value, actual.source_key.?);
        } else try std.testing.expect(actual.source_key == null);
        if (expected.fixed_value) |value| {
            try std.testing.expectEqualStrings(value, actual.fixed_value.?);
        } else try std.testing.expect(actual.fixed_value == null);
        if (expected.optional_seed_source) |value| {
            try std.testing.expectEqualStrings(
                value,
                actual.optional_seed_source.?,
            );
        } else try std.testing.expect(actual.optional_seed_source == null);
    }

    try std.testing.expectEqual(@as(usize, 2), catalog.taxpayer_year_target_count);
    try std.testing.expectEqual(@as(usize, 4), catalog.form_policy_target_count);
}

test "exact 2551Q and 1701Q typed specs cannot drift from catalog policy" {
    const form_2551q = @import("form_2551q.zig");
    const form_1701q = @import("form_1701q.zig");
    try expectTypedSpecMatchesCatalog(
        catalog.findForm("2551Q").?,
        form_2551q.profile_spec,
    );
    try expectTypedSpecMatchesCatalog(
        catalog.findForm("1701Q").?,
        form_1701q.profile_spec,
    );
}

test "2551Q schedule ATC is transaction data and is never projected" {
    const allocator = std.testing.allocator;
    const definition = catalog.findForm("2551Q").?;
    const on = try model.Date.parseIso("2026-03-31");
    const activities = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("activity-retail"),
        .line_of_business = try field.LineOfBusiness.parse("Retail"),
        .atc = try field.Atc.parse("PT010"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    }};
    var filer = try completeRevision(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
        &activities,
        &.{},
    );

    var result = try project(
        allocator,
        try typedRevision(definition),
        &.{.{ .role = .filer, .revision = &filer }},
        on,
    );
    defer result.deinit(allocator);
    const accepted = switch (result) {
        .accepted => |accepted| accepted,
        .rejected => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(usize, 7), accepted.entries.len);
    try std.testing.expectEqual(@as(usize, 1), definition.profile_roles.len);
    try std.testing.expectEqual(
        catalog.ProfileCardinality.exactly_one,
        definition.profile_roles[0].cardinality,
    );
    try std.testing.expectEqual(
        std.meta.fields(model.SubjectKind).len,
        definition.profile_roles[0].allowed_subjects.len,
    );
    for (definition.fields) |catalog_field| {
        if (catalog_field.provenance == .profile) {
            try std.testing.expectEqual(
                catalog.ProfilePresence.required,
                catalog_field.profile_presence.?,
            );
        }
    }

    const schedule_atc =
        "2551Q.2018-01-ENCS.table.percentage_tax_line.atc";
    for (accepted.entries) |entry| {
        try std.testing.expect(!std.mem.eql(
            u8,
            schedule_atc,
            entry.target.asSlice(),
        ));
        try std.testing.expect(entry.value.field() != .atc);
    }

    var found_schedule_atc = false;
    for (definition.fields) |catalog_field| {
        if (!std.mem.eql(u8, schedule_atc, catalog_field.id)) continue;
        found_schedule_atc = true;
        try std.testing.expectEqual(
            catalog.Provenance.transaction,
            catalog_field.provenance,
        );
        try std.testing.expect(catalog_field.profile_key == null);
    }
    try std.testing.expect(found_schedule_atc);
}

test "1701 and 1701Q omit an unbound optional spouse and add a bound spouse" {
    const allocator = std.testing.allocator;
    const on = try model.Date.parseIso("2026-03-31");
    var filer = try completeRevision(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
        &.{},
        &.{},
    );
    var spouse = try completeRevision(
        "profile-spouse",
        "revision-spouse",
        "987-654-321-000",
        "ANA DELA CRUZ",
        &.{},
        &.{},
    );

    for ([_][]const u8{ "1701", "1701Q" }) |code| {
        const definition = catalog.findForm(code).?;
        const spouse_targets = spouseTargetCount(definition);
        try std.testing.expect(spouse_targets > 0);

        {
            var omitted = try project(
                allocator,
                try typedRevision(definition),
                &.{.{ .role = .filer, .revision = &filer }},
                on,
            );
            defer omitted.deinit(allocator);
            const accepted = switch (omitted) {
                .accepted => |accepted| accepted,
                .rejected => return error.TestUnexpectedResult,
            };
            try std.testing.expectEqual(
                profileTargetCount(definition) - spouse_targets,
                accepted.entries.len,
            );
            for (accepted.entries) |entry| {
                try std.testing.expect(entry.role != .spouse);
            }
        }

        {
            const bindings = [_]Binding{
                .{ .role = .filer, .revision = &filer },
                .{ .role = .spouse, .revision = &spouse },
            };
            var bound = try project(
                allocator,
                try typedRevision(definition),
                &bindings,
                on,
            );
            defer bound.deinit(allocator);
            const accepted = switch (bound) {
                .accepted => |accepted| accepted,
                .rejected => return error.TestUnexpectedResult,
            };
            try std.testing.expectEqual(
                profileTargetCount(definition),
                accepted.entries.len,
            );
            var projected_spouse_targets: usize = 0;
            for (accepted.entries) |entry| {
                if (entry.role == .spouse) projected_spouse_targets += 1;
            }
            try std.testing.expectEqual(
                spouse_targets,
                projected_spouse_targets,
            );
        }
    }
}

test "1701 and 1701Q reject the same stable profile in filer and spouse roles" {
    const allocator = std.testing.allocator;
    const on = try model.Date.parseIso("2026-03-31");
    var filer = try completeRevision(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
        &.{},
        &.{},
    );

    for ([_][]const u8{ "1701", "1701Q" }) |code| {
        const definition = catalog.findForm(code).?;
        const bindings = [_]Binding{
            .{ .role = .filer, .revision = &filer },
            .{ .role = .spouse, .revision = &filer },
        };
        var result = try project(
            allocator,
            try typedRevision(definition),
            &bindings,
            on,
        );
        defer result.deinit(allocator);
        const rejection = switch (result) {
            .accepted => return error.TestUnexpectedResult,
            .rejected => |rejected| rejected,
        };
        var found = false;
        for (rejection.issues) |issue| {
            switch (issue) {
                .same_profile_binding => |roles| {
                    try std.testing.expectEqual(ids.Role.spouse, roles.left);
                    try std.testing.expectEqual(ids.Role.filer, roles.right);
                    found = true;
                },
                else => {},
            }
        }
        try std.testing.expect(found);
    }
}

test "catalog projection rejects bindings for undeclared profile roles" {
    const allocator = std.testing.allocator;
    const definition = catalog.findForm("2551Q").?;
    const on = try model.Date.parseIso("2026-03-31");
    var filer = try completeRevision(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
        &.{},
        &.{},
    );
    var unexpected = try completeRevision(
        "profile-unexpected",
        "revision-unexpected",
        "987-654-321-000",
        "UNEXPECTED PROFILE",
        &.{},
        &.{},
    );
    const bindings = [_]Binding{
        .{ .role = .filer, .revision = &filer },
        .{ .role = .spouse, .revision = &unexpected },
    };
    var result = try project(
        allocator,
        try typedRevision(definition),
        &bindings,
        on,
    );
    defer result.deinit(allocator);
    const rejection = switch (result) {
        .accepted => return error.TestUnexpectedResult,
        .rejected => |rejected| rejected,
    };
    var found = false;
    for (rejection.issues) |issue| {
        switch (issue) {
            .unexpected_binding => |role| {
                try std.testing.expectEqual(ids.Role.spouse, role);
                found = true;
            },
            else => {},
        }
    }
    try std.testing.expect(found);
}

test "missing optional applicability fields are omitted" {
    const allocator = std.testing.allocator;
    const definition = catalog.findForm("1701Q").?;
    const on = try model.Date.parseIso("2026-03-31");
    var filer = try completeRevision(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
        &.{},
        &.{},
    );
    filer.subject.sole_proprietor.person.date_of_birth = null;
    filer.subject.sole_proprietor.person.citizenship = null;
    filer.subject.sole_proprietor.person.foreign_tax_number = null;

    var result = try project(
        allocator,
        try typedRevision(definition),
        &.{.{ .role = .filer, .revision = &filer }},
        on,
    );
    defer result.deinit(allocator);
    const accepted = switch (result) {
        .accepted => |accepted| accepted,
        .rejected => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(
        profileTargetCount(definition) - spouseTargetCount(definition) - 3,
        accepted.entries.len,
    );
    for (accepted.entries) |entry| {
        try std.testing.expect(entry.value.field() != .date_of_birth);
        try std.testing.expect(entry.value.field() != .citizenship);
        try std.testing.expect(entry.value.field() != .foreign_tax_number);
    }
}

test "disallowed subject produces a precise role issue" {
    const allocator = std.testing.allocator;
    const definition = catalog.findForm("1702MX").?;
    const on = try model.Date.parseIso("2026-03-31");
    const activities = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("activity-retail"),
        .line_of_business = try field.LineOfBusiness.parse("Retail"),
        .atc = try field.Atc.parse("PT010"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    }};
    var person = try completeRevision(
        "profile-person",
        "revision-person",
        "123-456-789-000",
        "JUAN DELA CRUZ",
        &activities,
        &.{},
    );

    var result = try project(
        allocator,
        try typedRevision(definition),
        &.{.{ .role = .filer, .revision = &person }},
        on,
    );
    defer result.deinit(allocator);
    const rejected = switch (result) {
        .accepted => return error.TestUnexpectedResult,
        .rejected => |rejected| rejected,
    };
    try std.testing.expectEqual(@as(usize, 1), rejected.issues.len);
    switch (rejected.issues[0]) {
        .subject_not_allowed => |issue| {
            try std.testing.expectEqual(ids.Role.filer, issue.role);
            try std.testing.expectEqual(
                model.SubjectKind.sole_proprietor,
                issue.subject,
            );
        },
        else => return error.TestUnexpectedResult,
    }
}

test "missing capability identifies the exact concrete target" {
    const allocator = std.testing.allocator;
    const definition = catalog.findForm("2551Q").?;
    const on = try model.Date.parseIso("2026-03-31");
    var filer = try completeRevision(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
        &.{},
        &.{},
    );
    filer.contact.email_address = null;

    var result = try project(
        allocator,
        try typedRevision(definition),
        &.{.{ .role = .filer, .revision = &filer }},
        on,
    );
    defer result.deinit(allocator);
    const rejected = switch (result) {
        .accepted => return error.TestUnexpectedResult,
        .rejected => |rejected| rejected,
    };
    try std.testing.expectEqual(@as(usize, 1), rejected.issues.len);
    switch (rejected.issues[0]) {
        .missing_capability => |context| {
            try std.testing.expectEqual(
                field.ReusableField.email_address,
                context.reusable_field,
            );
            try std.testing.expectEqual(ids.Role.filer, context.role);
            try std.testing.expectEqualStrings(
                "2551Q.2018-01-ENCS.input.email_address",
                context.target.asSlice(),
            );
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ambiguous activities are reported only for activity-owned profile targets" {
    const allocator = std.testing.allocator;
    const definition = catalog.findForm("1601C").?;
    const on = try model.Date.parseIso("2026-03-31");
    const activities = [_]model.BusinessActivity{
        .{
            .id = try model.BusinessActivityId.parse("activity-retail"),
            .line_of_business = try field.LineOfBusiness.parse("Retail"),
            .atc = try field.Atc.parse("PT010"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
        },
        .{
            .id = try model.BusinessActivityId.parse("activity-services"),
            .line_of_business = try field.LineOfBusiness.parse("Services"),
            .atc = try field.Atc.parse("PT040"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
        },
    };
    const facts = [_]model.RegistrationFact{.{
        .id = try model.RegistrationFactId.parse("fact-tax-type"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .value = .{ .tax_type = try field.TaxType.parse("Income Tax") },
    }};
    var filer = try completeRevision(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
        &activities,
        &facts,
    );

    var result = try project(
        allocator,
        try typedRevision(definition),
        &.{.{ .role = .filer, .revision = &filer }},
        on,
    );
    defer result.deinit(allocator);
    const rejected = switch (result) {
        .accepted => return error.TestUnexpectedResult,
        .rejected => |rejected| rejected,
    };

    var ambiguous_count: usize = 0;
    for (rejected.issues) |issue| {
        switch (issue) {
            .ambiguous_business_activity => |context| {
                try std.testing.expectEqual(
                    field.ReusableField.line_of_business,
                    context.reusable_field,
                );
                ambiguous_count += 1;
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(usize, 1), ambiguous_count);
}
