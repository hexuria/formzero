//! Builder/composer for one-or-more named profile roles.
//!
//! Anonymous profile arrays are never interpreted positionally. Every binding
//! carries its role, and a form spec declares that role's cardinality,
//! requirements, subject kinds, and cross-role constraints.

const std = @import("std");
const ids = @import("id.zig");
const spec = @import("spec.zig");
const model = @import("../tax_profile/model.zig");
const projection = @import("../tax_profile/projection.zig");

pub const max_composition_issues = 64;

pub const Issue = union(enum) {
    missing_required_role: ids.Role,
    duplicate_role_binding: ids.Role,
    unexpected_role: ids.Role,
    same_profile_in_distinct_roles: spec.DistinctProfileRoles,
    qualification: projection.QualificationIssue,
};

pub const Rejection = struct {
    issues: [max_composition_issues]Issue = undefined,
    len: u8 = 0,
    truncated: bool = false,

    pub fn slice(self: *const Rejection) []const Issue {
        return self.issues[0..self.len];
    }

    pub fn isEmpty(self: *const Rejection) bool {
        return self.len == 0 and !self.truncated;
    }

    fn add(self: *Rejection, issue: Issue) void {
        if (self.len == self.issues.len) {
            self.truncated = true;
            return;
        }
        self.issues[self.len] = issue;
        self.len += 1;
    }
};

pub const Result = union(enum) {
    accepted: projection.Snapshot,
    rejected: Rejection,
};

pub const Error = projection.ProjectError;

pub fn compose(
    form_spec: spec.FormSpec,
    bindings: []const projection.Binding,
    effective_on: model.Date,
) Error!Result {
    var rejection: Rejection = .{};

    for (bindings) |binding| {
        if (form_spec.role(binding.role) == null) {
            rejection.add(.{ .unexpected_role = binding.role });
        }
    }

    for (form_spec.roles) |role_spec| {
        var count: usize = 0;
        var selected: ?projection.Binding = null;
        for (bindings) |binding| {
            if (binding.role != role_spec.role) continue;
            count += 1;
            if (selected == null) selected = binding;
        }
        if (count == 0) {
            if (role_spec.cardinality == .exactly_one) {
                rejection.add(.{ .missing_required_role = role_spec.role });
            }
            continue;
        }
        if (count > 1) {
            rejection.add(.{ .duplicate_role_binding = role_spec.role });
            continue;
        }

        const qualification = projection.qualify(
            role_spec,
            selected.?,
            effective_on,
        );
        for (qualification.slice()) |issue| {
            rejection.add(.{ .qualification = issue });
        }
        if (qualification.truncated) rejection.truncated = true;
    }

    for (form_spec.distinct_profile_roles) |pair| {
        const left = firstBinding(bindings, pair.left) orelse continue;
        const right = firstBinding(bindings, pair.right) orelse continue;
        if (left.revision.profile_id.eql(&right.revision.profile_id)) {
            rejection.add(.{ .same_profile_in_distinct_roles = pair });
        }
    }

    if (!rejection.isEmpty()) return .{ .rejected = rejection };

    var snapshot = projection.Snapshot.init(
        form_spec.revision,
        effective_on,
    );
    for (form_spec.roles) |role_spec| {
        const binding = firstBinding(bindings, role_spec.role) orelse continue;
        const role_snapshot = try projection.projectRole(
            form_spec.revision,
            role_spec,
            binding,
            effective_on,
        );
        try snapshot.appendSnapshot(&role_snapshot);
    }
    return .{ .accepted = snapshot };
}

fn firstBinding(
    bindings: []const projection.Binding,
    role: ids.Role,
) ?projection.Binding {
    for (bindings) |binding| {
        if (binding.role == role) return binding;
    }
    return null;
}

fn exampleIndividual(
    profile_name: []const u8,
    revision_name: []const u8,
    tin: []const u8,
    name: []const u8,
) !model.ProfileRevision {
    const field = @import("../tax_profile/field.zig");
    return .{
        .profile_id = try model.ProfileId.parse(profile_name),
        .id = try model.RevisionId.parse(revision_name),
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
            .address = try field.RegisteredAddress.parse("1 Taxpayer Street"),
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse("person@example.ph"),
        },
        .subject = .{ .individual = .{
            .name = try field.TaxpayerName.parse(name),
            .date_of_birth = try model.Date.parseIso("1995-06-01"),
            .citizenship = try field.Citizenship.parse("Filipino"),
        } },
    };
}

test "1701Q composes exact-one filer with optional named spouse" {
    const form_1701q = @import("form_1701q.zig");
    var filer = try exampleIndividual(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
    );
    var spouse = try exampleIndividual(
        "profile-spouse",
        "revision-spouse",
        "987-654-321-000",
        "ANA DELA CRUZ",
    );
    const bindings = [_]projection.Binding{
        .{ .role = .filer, .revision = &filer },
        .{ .role = .spouse, .revision = &spouse },
    };
    const result = try compose(
        form_1701q.profile_spec,
        &bindings,
        try model.Date.parseIso("2026-03-31"),
    );
    const snapshot = result.accepted;
    try std.testing.expectEqual(@as(u8, 10), snapshot.len);

    var filer_count: usize = 0;
    var spouse_count: usize = 0;
    for (snapshot.slice()) |entry| {
        if (entry.role == .filer) filer_count += 1;
        if (entry.role == .spouse) spouse_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 7), filer_count);
    try std.testing.expectEqual(@as(usize, 3), spouse_count);
}

test "1701Q accepts an omitted optional spouse" {
    const form_1701q = @import("form_1701q.zig");
    var filer = try exampleIndividual(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
    );
    const result = try compose(
        form_1701q.profile_spec,
        &.{.{ .role = .filer, .revision = &filer }},
        try model.Date.parseIso("2026-03-31"),
    );
    try std.testing.expectEqual(@as(u8, 7), result.accepted.len);
}

test "named role and distinct-profile constraints reject wrong composition" {
    const form_1701q = @import("form_1701q.zig");
    var filer = try exampleIndividual(
        "profile-filer",
        "revision-filer",
        "123-456-789-000",
        "JUAN DELA CRUZ",
    );
    const same_profile_bindings = [_]projection.Binding{
        .{ .role = .filer, .revision = &filer },
        .{ .role = .spouse, .revision = &filer },
    };
    const same = try compose(
        form_1701q.profile_spec,
        &same_profile_bindings,
        try model.Date.parseIso("2026-03-31"),
    );
    try std.testing.expectEqual(@as(u8, 1), same.rejected.len);
    try std.testing.expectEqual(
        std.meta.activeTag(
            Issue{ .same_profile_in_distinct_roles = .{ .left = .filer, .right = .spouse } },
        ),
        std.meta.activeTag(same.rejected.slice()[0]),
    );

    const missing = try compose(
        form_1701q.profile_spec,
        &.{},
        try model.Date.parseIso("2026-03-31"),
    );
    try std.testing.expectEqual(
        ids.Role.filer,
        missing.rejected.slice()[0].missing_required_role,
    );
}
