//! Form-revision profile requirements.
//!
//! A role spec is Zig's idiomatic equivalent of a Rust requirement
//! supertrait: it names the exact reusable subset and permitted subject kinds
//! for that role. Static specs are validated at compile time; runtime-loaded
//! profile revisions are qualified separately by `projection.zig`.

const std = @import("std");
const ids = @import("id.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");

pub const Cardinality = enum {
    exactly_one,
    zero_or_one,
};

pub const Presence = enum {
    required,
    optional,
};

pub const Requirement = struct {
    source: field.ReusableField,
    target: ids.FieldId,
    presence: Presence = .required,
};

pub const RoleSpec = struct {
    role: ids.Role,
    cardinality: Cardinality,
    allowed_subjects: model.SubjectKindSet,
    requirements: []const Requirement,

    pub fn requiredFields(self: RoleSpec) field.FieldSet {
        var result: field.FieldSet = .empty;
        for (self.requirements) |requirement| {
            if (requirement.presence == .required) {
                result.insert(requirement.source);
            }
        }
        return result;
    }

    pub fn accepts(self: RoleSpec, kind: model.SubjectKind) bool {
        return self.allowed_subjects.contains(kind);
    }
};

pub const DistinctProfileRoles = struct {
    left: ids.Role,
    right: ids.Role,
};

pub const FormSpec = struct {
    revision: ids.FormRevision,
    roles: []const RoleSpec,
    distinct_profile_roles: []const DistinctProfileRoles = &.{},

    pub fn role(self: FormSpec, wanted: ids.Role) ?RoleSpec {
        for (self.roles) |role_spec| {
            if (role_spec.role == wanted) return role_spec;
        }
        return null;
    }
};

pub const ValidationError = error{
    NoRoles,
    EmptyRequirements,
    NoAllowedSubjects,
    DuplicateRole,
    DuplicateSourceWithinRole,
    DuplicateTarget,
    UnknownConstrainedRole,
    SelfDistinctRole,
    DuplicateDistinctConstraint,
};

pub fn validateRuntime(form_spec: FormSpec) ValidationError!void {
    if (form_spec.roles.len == 0) return error.NoRoles;
    for (form_spec.roles, 0..) |role_spec, role_index| {
        if (role_spec.requirements.len == 0) return error.EmptyRequirements;
        if (role_spec.allowed_subjects.count() == 0) {
            return error.NoAllowedSubjects;
        }
        for (form_spec.roles[role_index + 1 ..]) |other_role| {
            if (role_spec.role == other_role.role) return error.DuplicateRole;
        }

        for (role_spec.requirements, 0..) |requirement, requirement_index| {
            for (role_spec.requirements[requirement_index + 1 ..]) |other| {
                if (requirement.source == other.source) {
                    return error.DuplicateSourceWithinRole;
                }
            }
            for (form_spec.roles[role_index..], role_index..) |
                target_role,
                target_role_index,
            | {
                const first_target_index = if (target_role_index == role_index)
                    requirement_index + 1
                else
                    0;
                for (target_role.requirements[first_target_index..]) |other| {
                    if (requirement.target.eql(&other.target)) {
                        return error.DuplicateTarget;
                    }
                }
            }
        }
    }
    for (form_spec.distinct_profile_roles, 0..) |pair, pair_index| {
        if (pair.left == pair.right) return error.SelfDistinctRole;
        if (form_spec.role(pair.left) == null or
            form_spec.role(pair.right) == null)
        {
            return error.UnknownConstrainedRole;
        }
        for (form_spec.distinct_profile_roles[pair_index + 1 ..]) |other| {
            if ((pair.left == other.left and pair.right == other.right) or
                (pair.left == other.right and pair.right == other.left))
            {
                return error.DuplicateDistinctConstraint;
            }
        }
    }
}

/// Invoke from a `comptime` block next to every static form specification.
pub fn validate(comptime form_spec: FormSpec) void {
    validateRuntime(form_spec) catch |err| @compileError(
        "invalid form profile specification: " ++ @errorName(err),
    );
}

test "role requirements expose the compiler-checked reusable subset" {
    const requirements = [_]Requirement{
        .{
            .source = .tin,
            .target = ids.FieldId.initComptime("example.tin"),
        },
        .{
            .source = .foreign_tax_number,
            .target = ids.FieldId.initComptime("example.foreign-tax-number"),
            .presence = .optional,
        },
    };
    const roles = [_]RoleSpec{.{
        .role = .filer,
        .cardinality = .exactly_one,
        .allowed_subjects = model.SubjectKindSet.initMany(&.{
            .individual,
            .sole_proprietor,
        }),
        .requirements = &requirements,
    }};
    const form_spec: FormSpec = .{
        .revision = ids.FormRevision.initComptime("TEST", "2026"),
        .roles = &roles,
    };

    try validateRuntime(form_spec);
    const required = roles[0].requiredFields();
    try std.testing.expect(required.contains(.tin));
    try std.testing.expect(!required.contains(.foreign_tax_number));
}

test "malformed form specs reject duplicate role sources" {
    const requirements = [_]Requirement{
        .{
            .source = .tin,
            .target = ids.FieldId.initComptime("example.tin-one"),
        },
        .{
            .source = .tin,
            .target = ids.FieldId.initComptime("example.tin-two"),
        },
    };
    const roles = [_]RoleSpec{.{
        .role = .filer,
        .cardinality = .exactly_one,
        .allowed_subjects = model.SubjectKindSet.initOne(.individual),
        .requirements = &requirements,
    }};
    try std.testing.expectError(
        error.DuplicateSourceWithinRole,
        validateRuntime(.{
            .revision = ids.FormRevision.initComptime("TEST", "2026"),
            .roles = &roles,
        }),
    );
}
