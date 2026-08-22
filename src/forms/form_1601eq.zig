//! BIR Form 1601EQ, January 2018 (ENCS).
//!
//! The profile projection mirrors the reusable controls that are actually
//! bound in `src/pages/forms/1601-eq.native`. Only the eight Background
//! Information fields carrying a `formFiler…` binding are projected.
//!
//! Item 4 and Item 11 are deliberately absent. The catalog does carry
//! `input.any_taxes_withheld` and `input.withholding_agent_category`, and
//! `field.ReusableField` does carry `government_withholding_agent`, but the
//! Native page leaves both controls unbound. Declaring them here would claim
//! a projection the page does not perform.
//!
//! Filing period, the ATC schedule, remittances, penalties and payment
//! details all remain transaction data.

const ids = @import("id.zig");
const spec = @import("spec.zig");
const model = @import("../tax_profile/model.zig");

pub const revision = ids.FormRevision.initComptime(
    "1601EQ",
    "2018-01-ENCS",
);

pub const filer_requirements = [_]spec.Requirement{
    .{
        .source = .tin,
        .target = ids.FieldId.initComptime(
            "1601EQ.2018-01-ENCS.input.tin",
        ),
    },
    .{
        .source = .rdo_code,
        .target = ids.FieldId.initComptime(
            "1601EQ.2018-01-ENCS.input.rdo_code",
        ),
    },
    .{
        .source = .taxpayer_name,
        .target = ids.FieldId.initComptime(
            "1601EQ.2018-01-ENCS.input.taxpayer_name",
        ),
    },
    .{
        .source = .registered_address,
        .target = ids.FieldId.initComptime(
            "1601EQ.2018-01-ENCS.input.registered_address",
        ),
    },
    .{
        .source = .zip_code,
        .target = ids.FieldId.initComptime(
            "1601EQ.2018-01-ENCS.input.zip_code",
        ),
    },
    .{
        .source = .line_of_business,
        .target = ids.FieldId.initComptime(
            "1601EQ.2018-01-ENCS.input.line_of_business",
        ),
    },
    .{
        .source = .contact_number,
        .target = ids.FieldId.initComptime(
            "1601EQ.2018-01-ENCS.input.contact_number",
        ),
    },
    .{
        .source = .email_address,
        .target = ids.FieldId.initComptime(
            "1601EQ.2018-01-ENCS.input.email_address",
        ),
    },
};

/// A withholding agent may be an individual or a juridical entity, so no
/// subject kind is excluded.
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

test "1601EQ projects exactly the bound background information fields" {
    try std.testing.expectEqual(@as(usize, 8), filer_requirements.len);
    try std.testing.expectEqual(@as(usize, 1), roles.len);
    try std.testing.expectEqual(spec.Cardinality.exactly_one, roles[0].cardinality);
}

test "1601EQ projects no field the Native page leaves unbound" {
    // Item 4 and Item 11 exist in the catalog but carry no profile binding.
    for (filer_requirements) |requirement| {
        const target = requirement.target.asSlice();
        try std.testing.expect(!std.mem.endsWith(u8, target, ".any_taxes_withheld"));
        try std.testing.expect(!std.mem.endsWith(u8, target, ".withholding_agent_category"));
    }
}

test "1601EQ requirement targets are unique and carry the form revision" {
    for (filer_requirements, 0..) |requirement, index| {
        const target = requirement.target.asSlice();
        try std.testing.expect(std.mem.startsWith(u8, target, "1601EQ.2018-01-ENCS.input."));
        for (filer_requirements[index + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, target, other.target.asSlice()));
        }
    }
}
