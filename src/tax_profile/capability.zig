//! Capability discovery and typed value resolution for profile revisions.
//!
//! Zig has no need for one trait per field. An exhaustive field enum plus an
//! `EnumSet` expresses the same subset relation while keeping runtime-loaded
//! profile revisions honest.

const std = @import("std");
const field = @import("field.zig");
const model = @import("model.zig");

/// Current profile projection has no activity or obligation selection. Keep an
/// empty value so call sites retain one stable binding shape while historical
/// component identifiers remain confined to persistence/export decoders.
pub const Selection = struct {};

pub const ResolveError = error{};

/// Capabilities the revision can truthfully provide without considering a
/// filing date or disambiguating a repeated business activity.
pub fn provided(revision: *const model.ProfileRevision) field.FieldSet {
    var result = field.FieldSet.initMany(&.{
        .tin,
        .rdo_code,
        .taxpayer_name,
        .registered_address,
    });
    if (revision.contact.zip_code != null) result.insert(.zip_code);
    if (revision.contact.contact_number != null) result.insert(.contact_number);
    if (revision.contact.email_address != null) result.insert(.email_address);

    if (revision.subject.registeredName() != null) {
        result.insert(.registered_name);
    }
    if (revision.subject.individualDetails()) |person| {
        if (person.date_of_birth != null) result.insert(.date_of_birth);
        if (person.citizenship != null) result.insert(.citizenship);
        if (person.foreign_tax_number != null) {
            result.insert(.foreign_tax_number);
        }
    }
    if (revision.accounting_period_basis != null) {
        result.insert(.accounting_period_basis);
    }
    if (revision.primary_line_of_business != null) {
        result.insert(.line_of_business);
    }
    if (revision.eopt_tier != null) result.insert(.eopt_tier);
    return result;
}

pub fn valueFor(
    revision: *const model.ProfileRevision,
    reusable_field: field.ReusableField,
    on: model.Date,
    selection: Selection,
) ResolveError!?field.Value {
    _ = selection;
    _ = on;
    return switch (reusable_field) {
        .tin => .{ .tin = revision.identity.tin },
        .rdo_code => .{ .rdo_code = revision.identity.rdo_code },
        .taxpayer_name => .{
            .taxpayer_name = revision.subject.taxpayerName(),
        },
        .registered_name => if (revision.subject.registeredName()) |name|
            .{ .registered_name = name }
        else
            null,
        .registered_address => .{
            .registered_address = revision.contact.address,
        },
        .zip_code => if (revision.contact.zip_code) |value|
            .{ .zip_code = value }
        else
            null,
        .contact_number => if (revision.contact.contact_number) |value|
            .{ .contact_number = value }
        else
            null,
        .email_address => if (revision.contact.email_address) |value|
            .{ .email_address = value }
        else
            null,
        .date_of_birth => if (revision.subject.individualDetails()) |person|
            if (person.date_of_birth) |value|
                .{ .date_of_birth = value }
            else
                null
        else
            null,
        .citizenship => if (revision.subject.individualDetails()) |person|
            if (person.citizenship) |value|
                .{ .citizenship = value }
            else
                null
        else
            null,
        .foreign_tax_number => if (revision.subject.individualDetails()) |person|
            if (person.foreign_tax_number) |number|
                .{ .foreign_tax_number = number }
            else
                null
        else
            null,
        .accounting_period_basis => if (revision.accounting_period_basis) |basis|
            .{ .accounting_period_basis = basis }
        else
            null,
        .line_of_business => if (revision.primary_line_of_business) |value|
            .{ .line_of_business = value }
        else
            null,
        .eopt_tier => if (revision.eopt_tier) |tier|
            .{ .eopt_tier = field.EoptTier.parse(tier.label()) catch unreachable }
        else
            null,
        // ATC is form policy or filing-transaction data. It is never inferred
        // from a legacy Registration activity.
        .atc => null,
        // These variants remain decodable for historical catalog snapshots,
        // but normal Base projection no longer reads Registration rows.
        .tax_type, .government_withholding_agent, .special_rate_basis => null,
    };
}

test "capability set follows the subject variant rather than nullable answers" {
    const profile_id = try model.ProfileId.parse("profile-corporation");
    const revision: model.ProfileRevision = .{
        .profile_id = profile_id,
        .id = try model.RevisionId.parse("revision-1"),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("1 Corporate Way"),
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("0281234567"),
            .email_address = try field.EmailAddress.parse("tax@corp.example"),
        },
        .subject = .{ .legal_entity = .{
            .registered_name = try field.RegisteredName.parse(
                "EXAMPLE CORPORATION",
            ),
            .kind = .corporation,
        } },
        .eopt_tier = .micro,
    };

    const set = provided(&revision);
    try std.testing.expect(set.contains(.tin));
    try std.testing.expect(set.contains(.registered_name));
    try std.testing.expect(set.contains(.eopt_tier));
    try std.testing.expect(!set.contains(.date_of_birth));
    try std.testing.expect(!set.contains(.atc));
    const tier = (try valueFor(
        &revision,
        .eopt_tier,
        try model.Date.parseIso("2026-01-01"),
        .{},
    )).?;
    try std.testing.expectEqualStrings("Micro", tier.eopt_tier.asSlice());
}

test "Line of Business comes only from the Base Tax Profile" {
    const revision: model.ProfileRevision = .{
        .profile_id = try model.ProfileId.parse("profile-maria"),
        .id = try model.RevisionId.parse("revision-1"),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse("123456789000"),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("1 Taxpayer Street"),
        },
        .subject = .{ .sole_proprietor = .{
            .person = .{
                .name = try field.TaxpayerName.parse("MARIA SANTOS"),
            },
        } },
        .primary_line_of_business = try field.LineOfBusiness.parse("Base consulting"),
    };
    const on = try model.Date.parseIso("2026-02-01");

    const line = (try valueFor(
        &revision,
        .line_of_business,
        on,
        .{},
    )).?;
    try std.testing.expectEqualStrings(
        "Base consulting",
        line.line_of_business.asSlice(),
    );
    try std.testing.expect((try valueFor(&revision, .atc, on, .{})) == null);
}
