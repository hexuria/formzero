//! Capability discovery and typed value resolution for profile revisions.
//!
//! Zig has no need for one trait per field. An exhaustive field enum plus an
//! `EnumSet` expresses the same subset relation while keeping runtime-loaded
//! profile revisions honest.

const std = @import("std");
const field = @import("field.zig");
const model = @import("model.zig");

pub const Selection = struct {
    /// Required only when more than one business activity is effective for
    /// the filing period. A sole effective activity is selected implicitly.
    business_activity_id: ?model.BusinessActivityId = null,
};

pub const ResolveError = error{
    BusinessActivitySelectionRequired,
    UnknownBusinessActivity,
    InactiveBusinessActivity,
};

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
    if (revision.business_activities.len > 0) {
        result.insert(.line_of_business);
        for (revision.business_activities) |activity| {
            if (activity.atc != null) {
                result.insert(.atc);
                break;
            }
        }
    }
    for (revision.registration_facts) |*fact| {
        result.insert(switch (fact.kind()) {
            .tax_type => .tax_type,
            .government_withholding_agent => .government_withholding_agent,
            .special_rate_basis => .special_rate_basis,
        });
    }
    return result;
}

pub fn resolveBusinessActivity(
    revision: *const model.ProfileRevision,
    on: model.Date,
    selection: Selection,
) ResolveError!?*const model.BusinessActivity {
    if (selection.business_activity_id) |id| {
        const activity = revision.businessActivity(id) orelse
            return error.UnknownBusinessActivity;
        if (!activity.isEffective(on)) return error.InactiveBusinessActivity;
        return activity;
    }

    return switch (revision.effectiveBusinessActivityCount(on)) {
        0 => null,
        1 => revision.soleEffectiveBusinessActivity(on).?,
        else => error.BusinessActivitySelectionRequired,
    };
}

pub fn valueFor(
    revision: *const model.ProfileRevision,
    reusable_field: field.ReusableField,
    on: model.Date,
    selection: Selection,
) ResolveError!?field.Value {
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
        .line_of_business => if (try resolveBusinessActivity(
            revision,
            on,
            selection,
        )) |activity|
            .{ .line_of_business = activity.line_of_business }
        else
            null,
        .atc => if (try resolveBusinessActivity(
            revision,
            on,
            selection,
        )) |activity|
            if (activity.atc) |value|
                .{ .atc = value }
            else
                null
        else
            null,
        .tax_type => if (revision.registrationFact(.tax_type, on)) |fact|
            .{ .tax_type = fact.value.tax_type }
        else
            null,
        .government_withholding_agent => if (revision.registrationFact(
            .government_withholding_agent,
            on,
        )) |fact|
            .{
                .government_withholding_agent = fact.value.government_withholding_agent,
            }
        else
            null,
        .special_rate_basis => if (revision.registrationFact(
            .special_rate_basis,
            on,
        )) |fact|
            .{ .special_rate_basis = fact.value.special_rate_basis }
        else
            null,
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
            .contact_number = try field.ContactNumber.parse("81234567"),
            .email_address = try field.EmailAddress.parse("tax@corp.example"),
        },
        .subject = .{ .legal_entity = .{
            .registered_name = try field.RegisteredName.parse(
                "EXAMPLE CORPORATION",
            ),
            .kind = .corporation,
        } },
    };

    const set = provided(&revision);
    try std.testing.expect(set.contains(.tin));
    try std.testing.expect(set.contains(.registered_name));
    try std.testing.expect(!set.contains(.date_of_birth));
    try std.testing.expect(!set.contains(.atc));
}

test "business capability requires disambiguation only when necessary" {
    const activity_one: model.BusinessActivity = .{
        .id = try model.BusinessActivityId.parse("activity-1"),
        .line_of_business = try field.LineOfBusiness.parse("Retail"),
        .atc = try field.Atc.parse("PT010"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    };
    const activity_two: model.BusinessActivity = .{
        .id = try model.BusinessActivityId.parse("activity-2"),
        .line_of_business = try field.LineOfBusiness.parse("Services"),
        .atc = try field.Atc.parse("PT040"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    };
    const activities = [_]model.BusinessActivity{ activity_one, activity_two };
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
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse("maria@example.ph"),
        },
        .subject = .{ .sole_proprietor = .{
            .person = .{
                .name = try field.TaxpayerName.parse("MARIA SANTOS"),
                .date_of_birth = try model.Date.parseIso("1995-06-01"),
                .citizenship = try field.Citizenship.parse("Filipino"),
            },
        } },
        .business_activities = &activities,
    };
    const on = try model.Date.parseIso("2026-02-01");

    try std.testing.expectError(
        error.BusinessActivitySelectionRequired,
        valueFor(&revision, .atc, on, .{}),
    );
    const selected = (try valueFor(
        &revision,
        .atc,
        on,
        .{ .business_activity_id = activity_two.id },
    )).?;
    try std.testing.expectEqualStrings("PT040", selected.atc.asSlice());
}

test "effective registration facts extend the reusable union" {
    const facts = [_]model.RegistrationFact{
        .{
            .id = try model.RegistrationFactId.parse("registration-tax-type"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
            .value = .{
                .tax_type = try field.TaxType.parse("Percentage Tax"),
            },
        },
        .{
            .id = try model.RegistrationFactId.parse("registration-gwa"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
            .value = .{ .government_withholding_agent = .yes },
        },
    };
    var revision: model.ProfileRevision = .{
        .profile_id = try model.ProfileId.parse("profile-corporation"),
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
            .contact_number = try field.ContactNumber.parse("81234567"),
            .email_address = try field.EmailAddress.parse("tax@corp.example"),
        },
        .subject = .{ .legal_entity = .{
            .registered_name = try field.RegisteredName.parse(
                "EXAMPLE CORPORATION",
            ),
            .kind = .corporation,
        } },
        .registration_facts = &facts,
    };
    try revision.validate();
    const on = try model.Date.parseIso("2026-03-31");
    const tax_type = (try valueFor(&revision, .tax_type, on, .{})).?;
    const gwa = (try valueFor(
        &revision,
        .government_withholding_agent,
        on,
        .{},
    )).?;
    try std.testing.expectEqualStrings(
        "Percentage Tax",
        tax_type.tax_type.asSlice(),
    );
    try std.testing.expectEqual(
        field.GovernmentWithholdingAgent.yes,
        gwa.government_withholding_agent,
    );
}
