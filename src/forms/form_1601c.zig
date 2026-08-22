//! BIR Form 1601C, January 2018 (ENCS).
//!
//! The profile projection mirrors the reusable controls that are bound in
//! `src/pages/forms/1601-c.native` and that catalog policy classifies as
//! profile-provided.
//!
//! The page also binds `{formFilerAtc}`, but the catalog records that field
//! with `provenance = .form_policy` and `role = .system`, carrying neither a
//! profile key nor a presence. It is supplied by policy rather than by the
//! taxpayer profile, so declaring it here would both misstate its source and
//! break the count the drift test enforces.
//!
//! ZIP code and email address are optional; catalog policy marks them so.
//!
//! The monthly period, compensation lines, the Schedule 1 adjustment,
//! remittances, penalties and payment details all remain transaction data.

const ids = @import("id.zig");
const spec = @import("spec.zig");
const model = @import("../tax_profile/model.zig");

pub const revision = ids.FormRevision.initComptime(
    "1601C",
    "2018-01-ENCS",
);

pub const filer_requirements = [_]spec.Requirement{
    .{
        .source = .tin,
        .target = ids.FieldId.initComptime(
            "1601C.2018-01-ENCS.input.tin",
        ),
    },
    .{
        .source = .rdo_code,
        .target = ids.FieldId.initComptime(
            "1601C.2018-01-ENCS.input.rdo_code",
        ),
    },
    .{
        .source = .taxpayer_name,
        .target = ids.FieldId.initComptime(
            "1601C.2018-01-ENCS.input.taxpayer_name",
        ),
    },
    .{
        .source = .registered_address,
        .target = ids.FieldId.initComptime(
            "1601C.2018-01-ENCS.input.registered_address",
        ),
    },
    .{
        .source = .zip_code,
        .target = ids.FieldId.initComptime(
            "1601C.2018-01-ENCS.input.zip_code",
        ),
        .presence = .optional,
    },
    .{
        .source = .line_of_business,
        .target = ids.FieldId.initComptime(
            "1601C.2018-01-ENCS.input.line_of_business",
        ),
    },
    .{
        .source = .contact_number,
        .target = ids.FieldId.initComptime(
            "1601C.2018-01-ENCS.input.contact_number",
        ),
    },
    .{
        .source = .email_address,
        .target = ids.FieldId.initComptime(
            "1601C.2018-01-ENCS.input.email_address",
        ),
        .presence = .optional,
    },
};

/// A withholding agent on compensation may be an individual or a juridical
/// entity, so no subject kind is excluded.
pub const roles = [_]spec.RoleSpec{.{
    .role = .filer,
    .cardinality = .exactly_one,
    .allowed_subjects = model.SubjectKindSet.full,
    .requirements = &filer_requirements,
}};

pub const profile_spec: spec.FormSpec = .{
    .revision = revision,
    .roles = &roles,
};

comptime {
    spec.validate(profile_spec);
}

const std = @import("std");

test "1601C projects the eight profile-provided fields" {
    try std.testing.expectEqual(@as(usize, 8), filer_requirements.len);
    try std.testing.expectEqual(@as(usize, 1), roles.len);
    try std.testing.expectEqual(spec.Cardinality.exactly_one, roles[0].cardinality);
}

test "1601C does not project the policy-supplied ATC" {
    // The Native page binds it, but the catalog calls it form policy.
    for (filer_requirements) |requirement| {
        try std.testing.expect(!std.mem.endsWith(
            u8,
            requirement.target.asSlice(),
            ".atc",
        ));
    }
}

test "1601C marks exactly the two fields catalog policy calls optional" {
    var optional_count: usize = 0;
    for (filer_requirements) |requirement| {
        if (requirement.presence != .optional) continue;
        optional_count += 1;
        const target = requirement.target.asSlice();
        try std.testing.expect(std.mem.endsWith(u8, target, ".zip_code") or
            std.mem.endsWith(u8, target, ".email_address"));
    }
    try std.testing.expectEqual(@as(usize, 2), optional_count);
}

test "1601C requirement targets are unique and carry the form revision" {
    for (filer_requirements, 0..) |requirement, index| {
        const target = requirement.target.asSlice();
        try std.testing.expect(std.mem.startsWith(u8, target, "1601C.2018-01-ENCS.input."));
        for (filer_requirements[index + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, target, other.target.asSlice()));
        }
    }
}
