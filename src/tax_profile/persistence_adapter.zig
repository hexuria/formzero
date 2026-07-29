//! Lossless boundary between the validated tax-profile domain and SQLite rows.
//!
//! The database layer owns SQL concerns and allocated text. This adapter owns
//! semantic parsing and construction: reads must pass every field parser and
//! the typestate editor before a `model.ProfileRevision` is exposed.

const std = @import("std");
const editor = @import("editor.zig");
const field = @import("field.zig");
const model = @import("model.zig");
const persistence = @import("store.zig");

pub const SerializedValue = struct {
    value_type: []const u8,
    text: []const u8,
};

/// Allocated only for repeated SQL rows. All text slices borrow the immutable,
/// allocation-free domain revision supplied to `toWriteRows`.
pub const WriteRows = struct {
    revision: persistence.RevisionWrite,
    business_activities: []persistence.BusinessActivityWrite,
    registration_facts: []persistence.RegistrationFactWrite,

    pub fn components(self: *const WriteRows) persistence.RevisionComponentsWrite {
        return .{
            .business_activities = self.business_activities,
            .registration_facts = self.registration_facts,
        };
    }

    pub fn deinit(self: *WriteRows, allocator: std.mem.Allocator) void {
        allocator.free(self.business_activities);
        allocator.free(self.registration_facts);
        self.* = undefined;
    }
};

/// Owns the repeated arrays referenced by `revision`. Domain fields themselves
/// are fixed-storage values, so the source SQLite row can be released as soon
/// as this conversion returns.
pub const OwnedDomainRevision = struct {
    revision: model.ProfileRevision,
    business_activities: []model.BusinessActivity,
    registration_facts: []model.RegistrationFact,

    pub fn deinit(
        self: *OwnedDomainRevision,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.business_activities);
        allocator.free(self.registration_facts);
        self.* = undefined;
    }
};

pub fn toWriteRows(
    allocator: std.mem.Allocator,
    revision: *const model.ProfileRevision,
    expected_current_sequence: ?u32,
) !WriteRows {
    try revision.validate();

    const activities = try allocator.alloc(
        persistence.BusinessActivityWrite,
        revision.business_activities.len,
    );
    errdefer allocator.free(activities);
    for (revision.business_activities, 0..) |*activity, index| {
        if (index > std.math.maxInt(u32)) return error.TooManyComponents;
        activities[index] = .{
            .id = activity.id.asSlice(),
            .line_of_business = activity.line_of_business.asSlice(),
            .atc = if (activity.atc) |*atc| atc.asSlice() else null,
            .effective = effectiveToWrite(activity.effective),
            .ordinal = @intCast(index),
        };
    }

    const facts = try allocator.alloc(
        persistence.RegistrationFactWrite,
        revision.registration_facts.len,
    );
    errdefer allocator.free(facts);
    for (revision.registration_facts, 0..) |*fact, index| {
        if (index > std.math.maxInt(u32)) return error.TooManyComponents;
        facts[index] = .{
            .id = fact.id.asSlice(),
            .effective = effectiveToWrite(fact.effective),
            .value = registrationFactToWrite(&fact.value),
            .ordinal = @intCast(index),
        };
    }

    return .{
        .revision = .{
            .id = revision.id.asSlice(),
            .profile_id = revision.profile_id.asSlice(),
            .sequence = revision.sequence,
            .expected_current_sequence = expected_current_sequence,
            .effective = effectiveToWrite(revision.effective),
            .source = sourceToWrite(&revision.source),
            .identity = .{
                .tin = revision.identity.tin.asDigits(),
                .rdo_code = revision.identity.rdo_code.asSlice(),
            },
            .contact = .{
                .registered_address = revision.contact.address.asSlice(),
                .zip_code = if (revision.contact.zip_code) |*zip|
                    zip.asSlice()
                else
                    null,
                .contact_number = if (revision.contact.contact_number) |*number|
                    number.asSlice()
                else
                    null,
                .email_address = if (revision.contact.email_address) |*email|
                    email.asSlice()
                else
                    null,
            },
            .subject = subjectToWrite(&revision.subject),
        },
        .business_activities = activities,
        .registration_facts = facts,
    };
}

pub fn createProfileWithRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    status: persistence.ProfileStatus,
    revision: *const model.ProfileRevision,
) !void {
    var rows = try toWriteRows(allocator, revision, 0);
    defer rows.deinit(allocator);
    try store.createProfileWithRevision(
        .{
            .id = revision.profile_id.asSlice(),
            .status = status,
        },
        rows.revision,
        rows.components(),
    );
}

pub fn appendRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    revision: *const model.ProfileRevision,
    expected_current_sequence: u32,
) !void {
    var rows = try toWriteRows(
        allocator,
        revision,
        expected_current_sequence,
    );
    defer rows.deinit(allocator);
    try store.appendRevision(rows.revision, rows.components());
}

pub fn toDomain(
    allocator: std.mem.Allocator,
    rows: *const persistence.OwnedProfileRevision,
) !OwnedDomainRevision {
    const activities = try allocator.alloc(
        model.BusinessActivity,
        rows.business_activities.len,
    );
    errdefer allocator.free(activities);
    for (rows.business_activities, 0..) |*activity, index| {
        activities[index] = .{
            .id = try model.BusinessActivityId.parse(activity.id),
            .line_of_business = try field.LineOfBusiness.parse(
                activity.line_of_business,
            ),
            .atc = if (activity.atc) |atc|
                try field.Atc.parse(atc)
            else
                null,
            .effective = try parseEffective(
                activity.effective_from,
                activity.effective_until,
            ),
        };
    }

    const facts = try allocator.alloc(
        model.RegistrationFact,
        rows.registration_facts.len,
    );
    errdefer allocator.free(facts);
    for (rows.registration_facts, 0..) |*fact, index| {
        facts[index] = .{
            .id = try model.RegistrationFactId.parse(fact.id),
            .effective = try parseEffective(
                fact.effective_from,
                fact.effective_until,
            ),
            .value = try registrationFactToDomain(&fact.value),
        };
    }

    const base: editor.Base = .{
        .profile_id = try model.ProfileId.parse(rows.profile_id),
        .revision_id = try model.RevisionId.parse(rows.id),
        .sequence = rows.sequence,
        .effective = try parseEffective(
            rows.effective_from,
            rows.effective_until,
        ),
        .source = try sourceToDomain(&rows.source),
        .identity = .{
            .tin = try field.Tin.parse(rows.tin),
            .rdo_code = try field.RdoCode.parse(rows.rdo_code),
        },
        .contact = .{
            // Required: malformed/incomplete legacy rows stop here.
            .address = try field.RegisteredAddress.parse(
                rows.contact.registered_address,
            ),
            .zip_code = if (rows.contact.zip_code) |zip|
                try field.ZipCode.parse(zip)
            else
                null,
            .contact_number = if (rows.contact.contact_number) |number|
                try field.ContactNumber.parse(number)
            else
                null,
            .email_address = if (rows.contact.email_address) |email|
                try field.EmailAddress.parse(email)
            else
                null,
        },
    };
    const subject = try subjectToDomain(&rows.subject);
    const ready = switch (subject) {
        .individual => |person| editor.begin(base).individual(person),
        .sole_proprietor => |proprietor| editor.begin(base).soleProprietor(proprietor),
        .legal_entity => |entity| editor.begin(base).legalEntity(entity),
    };
    const revision = try ready
        .withBusinessActivities(activities)
        .withRegistrationFacts(facts)
        .build();

    return .{
        .revision = revision,
        .business_activities = activities,
        .registration_facts = facts,
    };
}

pub fn loadCurrentRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    profile_id: model.ProfileId,
) !?OwnedDomainRevision {
    var rows = (try store.getCurrentRevision(
        allocator,
        profile_id.asSlice(),
    )) orelse return null;
    defer rows.deinit(allocator);
    return try toDomain(allocator, &rows);
}

pub fn loadRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    profile_id: model.ProfileId,
    revision_id: model.RevisionId,
) !?OwnedDomainRevision {
    var rows = (try store.getRevision(
        allocator,
        profile_id.asSlice(),
        revision_id.asSlice(),
    )) orelse return null;
    defer rows.deinit(allocator);
    return try toDomain(allocator, &rows);
}

/// Filing composition uses this lookup; editing screens generally use
/// `loadCurrentRevision`. Highest effective sequence wins when immutable
/// effective periods overlap because a later revision supersedes an earlier
/// one without rewriting history.
pub fn loadEffectiveRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    profile_id: model.ProfileId,
    on: model.Date,
) !?OwnedDomainRevision {
    var date_buffer: persistence.DateText = undefined;
    const date_text = on.writeIso(&date_buffer);
    var rows = (try store.getEffectiveRevision(
        allocator,
        profile_id.asSlice(),
        date_text,
    )) orelse return null;
    defer rows.deinit(allocator);
    return try toDomain(allocator, &rows);
}

/// Canonical snapshot encoding for every reusable field. Text is always
/// copied into the caller's buffer so the result never borrows a profile.
pub fn serializeValue(
    value: *const field.Value,
    buffer: *[255]u8,
) SerializedValue {
    const text = switch (value.*) {
        .tin => |*item| copyToBuffer(buffer, item.asDigits()),
        .rdo_code => |*item| copyToBuffer(buffer, item.asSlice()),
        .taxpayer_name => |*item| copyToBuffer(buffer, item.asSlice()),
        .registered_name => |*item| copyToBuffer(buffer, item.asSlice()),
        .registered_address => |*item| copyToBuffer(buffer, item.asSlice()),
        .zip_code => |*item| copyToBuffer(buffer, item.asSlice()),
        .contact_number => |*item| copyToBuffer(buffer, item.asSlice()),
        .email_address => |*item| copyToBuffer(buffer, item.asSlice()),
        .date_of_birth => |item| item.writeIso(buffer[0..10]),
        .citizenship => |*item| copyToBuffer(buffer, item.asSlice()),
        .foreign_tax_number => |*item| copyToBuffer(buffer, item.asSlice()),
        .line_of_business => |*item| copyToBuffer(buffer, item.asSlice()),
        .atc => |*item| copyToBuffer(buffer, item.asSlice()),
        .tax_type => |*item| copyToBuffer(buffer, item.asSlice()),
        .government_withholding_agent => |item| copyToBuffer(
            buffer,
            @tagName(item),
        ),
        .special_rate_basis => |*item| copyToBuffer(buffer, item.asSlice()),
    };
    return .{
        .value_type = canonicalValueType(value.field()),
        .text = text,
    };
}

pub fn parseValue(
    reusable_field: field.ReusableField,
    value_type: []const u8,
    text: []const u8,
) !field.Value {
    if (!std.mem.eql(
        u8,
        value_type,
        canonicalValueType(reusable_field),
    )) {
        return error.InvalidValueType;
    }
    return switch (reusable_field) {
        .tin => .{ .tin = try field.Tin.parse(text) },
        .rdo_code => .{ .rdo_code = try field.RdoCode.parse(text) },
        .taxpayer_name => .{
            .taxpayer_name = try field.TaxpayerName.parse(text),
        },
        .registered_name => .{
            .registered_name = try field.RegisteredName.parse(text),
        },
        .registered_address => .{
            .registered_address = try field.RegisteredAddress.parse(text),
        },
        .zip_code => .{ .zip_code = try field.ZipCode.parse(text) },
        .contact_number => .{
            .contact_number = try field.ContactNumber.parse(text),
        },
        .email_address => .{
            .email_address = try field.EmailAddress.parse(text),
        },
        .date_of_birth => .{
            .date_of_birth = try model.Date.parseIso(text),
        },
        .citizenship => .{
            .citizenship = try field.Citizenship.parse(text),
        },
        .foreign_tax_number => .{
            .foreign_tax_number = try field.ForeignTaxNumber.parse(text),
        },
        .line_of_business => .{
            .line_of_business = try field.LineOfBusiness.parse(text),
        },
        .atc => .{ .atc = try field.Atc.parse(text) },
        .tax_type => .{ .tax_type = try field.TaxType.parse(text) },
        .government_withholding_agent => .{
            .government_withholding_agent = parseGovernmentWithholdingAgent(text) orelse
                return error.InvalidGovernmentWithholdingAgent,
        },
        .special_rate_basis => .{
            .special_rate_basis = try field.SpecialRateBasis.parse(text),
        },
    };
}

pub fn canonicalValueType(value: field.ReusableField) []const u8 {
    return switch (value) {
        .tin => "tin_digits",
        .date_of_birth => "iso_date",
        .government_withholding_agent => "yes_no",
        else => "text",
    };
}

fn copyToBuffer(buffer: *[255]u8, source: []const u8) []const u8 {
    std.debug.assert(source.len <= buffer.len);
    @memcpy(buffer[0..source.len], source);
    return buffer[0..source.len];
}

fn effectiveToWrite(
    value: model.EffectivePeriod,
) persistence.EffectivePeriodWrite {
    var from: persistence.DateText = undefined;
    _ = value.from.writeIso(&from);
    var until: ?persistence.DateText = null;
    if (value.until) |last| {
        var buffer: persistence.DateText = undefined;
        _ = last.writeIso(&buffer);
        until = buffer;
    }
    return .{ .from = from, .until = until };
}

fn sourceToWrite(
    value: *const model.RevisionSource,
) persistence.RevisionSourceWrite {
    return switch (value.*) {
        .manual_entry => .{ .manual_entry = {} },
        .imported => |*reference| .{
            .imported = reference.asSlice(),
        },
        .migrated => |*reference| .{
            .migrated = reference.asSlice(),
        },
    };
}

fn subjectToWrite(value: *const model.Subject) persistence.SubjectWrite {
    return switch (value.*) {
        .individual => |*person| .{
            .individual = individualToWrite(person),
        },
        .sole_proprietor => |*proprietor| .{
            .sole_proprietor = .{
                .person = individualToWrite(&proprietor.person),
                .trade_name = if (proprietor.trade_name) |*name|
                    name.asSlice()
                else
                    null,
            },
        },
        .legal_entity => |*entity| .{
            .legal_entity = .{
                .registered_name = entity.registered_name.asSlice(),
                .kind = switch (entity.kind) {
                    .corporation => .corporation,
                    .partnership => .partnership,
                    .estate => .estate,
                    .trust => .trust,
                    .other => .other,
                },
            },
        },
    };
}

fn individualToWrite(
    value: *const model.Individual,
) persistence.IndividualWrite {
    return .{
        .name = value.name.asSlice(),
        .date_of_birth = if (value.date_of_birth) |date| blk: {
            var buffer: persistence.DateText = undefined;
            _ = date.writeIso(&buffer);
            break :blk buffer;
        } else null,
        .citizenship = if (value.citizenship) |*citizenship|
            citizenship.asSlice()
        else
            null,
        .foreign_tax_number = if (value.foreign_tax_number) |*number|
            number.asSlice()
        else
            null,
    };
}

fn registrationFactToWrite(
    value: *const model.RegistrationFactValue,
) persistence.RegistrationFactValueWrite {
    return switch (value.*) {
        .tax_type => |*tax_type| .{
            .tax_type = tax_type.asSlice(),
        },
        .government_withholding_agent => |answer| .{
            .government_withholding_agent = switch (answer) {
                .no => .no,
                .yes => .yes,
            },
        },
        .special_rate_basis => |*basis| .{
            .special_rate_basis = basis.asSlice(),
        },
    };
}

fn parseEffective(
    from: []const u8,
    until: ?[]const u8,
) !model.EffectivePeriod {
    return try model.EffectivePeriod.init(
        try model.Date.parseIso(from),
        if (until) |last| try model.Date.parseIso(last) else null,
    );
}

fn sourceToDomain(
    value: *const persistence.OwnedRevisionSource,
) !model.RevisionSource {
    return switch (value.*) {
        .manual_entry => .manual_entry,
        .imported => |reference| .{
            .imported = try field.SourceReference.parse(reference),
        },
        .migrated => |reference| .{
            .migrated = try field.SourceReference.parse(reference),
        },
    };
}

fn subjectToDomain(value: *const persistence.OwnedSubject) !model.Subject {
    return switch (value.*) {
        .individual => |*person| .{
            .individual = try individualToDomain(person),
        },
        .sole_proprietor => |*proprietor| .{
            .sole_proprietor = .{
                .person = try individualToDomain(&proprietor.person),
                .trade_name = if (proprietor.trade_name) |name|
                    try field.RegisteredName.parse(name)
                else
                    null,
            },
        },
        .legal_entity => |*entity| .{
            .legal_entity = .{
                .registered_name = try field.RegisteredName.parse(
                    entity.registered_name,
                ),
                .kind = switch (entity.kind) {
                    .corporation => .corporation,
                    .partnership => .partnership,
                    .estate => .estate,
                    .trust => .trust,
                    .other => .other,
                },
            },
        },
    };
}

fn individualToDomain(
    value: *const persistence.OwnedIndividual,
) !model.Individual {
    return .{
        .name = try field.TaxpayerName.parse(value.name),
        .date_of_birth = if (value.date_of_birth) |date|
            try model.Date.parseIso(date)
        else
            null,
        .citizenship = if (value.citizenship) |citizenship|
            try field.Citizenship.parse(citizenship)
        else
            null,
        .foreign_tax_number = if (value.foreign_tax_number) |number|
            try field.ForeignTaxNumber.parse(number)
        else
            null,
    };
}

fn registrationFactToDomain(
    value: *const persistence.OwnedRegistrationFactValue,
) !model.RegistrationFactValue {
    return switch (value.*) {
        .tax_type => |tax_type| .{
            .tax_type = try field.TaxType.parse(tax_type),
        },
        .government_withholding_agent => |answer| .{
            .government_withholding_agent = switch (answer) {
                .no => .no,
                .yes => .yes,
            },
        },
        .special_rate_basis => |basis| .{
            .special_rate_basis = try field.SpecialRateBasis.parse(basis),
        },
    };
}

fn parseGovernmentWithholdingAgent(
    value: []const u8,
) ?field.GovernmentWithholdingAgent {
    if (std.mem.eql(u8, value, "no")) return .no;
    if (std.mem.eql(u8, value, "yes")) return .yes;
    return null;
}

test "individual revision round trips through cohesive persistence rows" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const revision = try testIndividualRevision();
    try createProfileWithRevision(&store, allocator, .active, &revision);
    var loaded = (try loadCurrentRevision(
        &store,
        allocator,
        revision.profile_id,
    )).?;
    defer loaded.deinit(allocator);
    try expectRevisionEqual(&revision, &loaded.revision);
}

test "sole proprietor activities facts trade name and source round trip" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

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
            .id = try model.BusinessActivityId.parse("activity-consulting"),
            .line_of_business = try field.LineOfBusiness.parse("Consulting"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-04-01"),
                try model.Date.parseIso("2026-12-31"),
            ),
        },
    };
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
                try model.Date.parseIso("2026-02-01"),
                null,
            ),
            .value = .{ .government_withholding_agent = .yes },
        },
        .{
            .id = try model.RegistrationFactId.parse("fact-special-rate"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-03-01"),
                null,
            ),
            .value = .{
                .special_rate_basis = try field.SpecialRateBasis.parse(
                    "Tax treaty article 7",
                ),
            },
        },
    };
    const base = try testBase(
        "profile-sole-proprietor",
        "revision-sole-proprietor",
        .{ .imported = try field.SourceReference.parse("bir-import-2026") },
    );
    const revision = try editor.begin(base)
        .soleProprietor(.{
            .person = .{
                .name = try field.TaxpayerName.parse("MARIA SANTOS"),
                .date_of_birth = try model.Date.parseIso("1995-06-01"),
                .citizenship = try field.Citizenship.parse("Filipino"),
                .foreign_tax_number = try field.ForeignTaxNumber.parse(
                    "US-12345",
                ),
            },
            .trade_name = try field.RegisteredName.parse("MARIA'S BAKERY"),
        })
        .withBusinessActivities(&activities)
        .withRegistrationFacts(&facts)
        .build();

    try createProfileWithRevision(&store, allocator, .active, &revision);
    var loaded = (try loadCurrentRevision(
        &store,
        allocator,
        revision.profile_id,
    )).?;
    defer loaded.deinit(allocator);
    try expectRevisionEqual(&revision, &loaded.revision);
}

test "every legal entity subject kind round trips exactly" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const kinds = [_]model.LegalEntityKind{
        .corporation,
        .partnership,
        .estate,
        .trust,
        .other,
    };
    for (kinds, 0..) |kind, index| {
        var profile_buffer: [64]u8 = undefined;
        const profile_text = try std.fmt.bufPrint(
            &profile_buffer,
            "profile-legal-{d}",
            .{index},
        );
        var revision_buffer: [64]u8 = undefined;
        const revision_text = try std.fmt.bufPrint(
            &revision_buffer,
            "revision-legal-{d}",
            .{index},
        );
        const base = try testBase(
            profile_text,
            revision_text,
            .{ .migrated = try field.SourceReference.parse(
                "legacy-profile-v1",
            ) },
        );
        const revision = try editor.begin(base).legalEntity(.{
            .registered_name = try field.RegisteredName.parse(
                "EXAMPLE LEGAL ENTITY",
            ),
            .kind = kind,
        }).build();
        try createProfileWithRevision(&store, allocator, .active, &revision);
        var loaded = (try loadCurrentRevision(
            &store,
            allocator,
            revision.profile_id,
        )).?;
        defer loaded.deinit(allocator);
        try expectRevisionEqual(&revision, &loaded.revision);
    }
}

test "canonical value codec round trips all reusable field variants" {
    const values = [_]field.Value{
        .{ .tin = try field.Tin.parse("123-456-789-000") },
        .{ .rdo_code = try field.RdoCode.parse("019") },
        .{ .taxpayer_name = try field.TaxpayerName.parse("MARIA SANTOS") },
        .{ .registered_name = try field.RegisteredName.parse("MARIA BAKERY") },
        .{ .registered_address = try field.RegisteredAddress.parse(
            "1 Taxpayer Street",
        ) },
        .{ .zip_code = try field.ZipCode.parse("1000") },
        .{ .contact_number = try field.ContactNumber.parse("09171234567") },
        .{ .email_address = try field.EmailAddress.parse("tax@example.ph") },
        .{ .date_of_birth = try model.Date.parseIso("1995-06-01") },
        .{ .citizenship = try field.Citizenship.parse("Filipino") },
        .{ .foreign_tax_number = try field.ForeignTaxNumber.parse("US-123") },
        .{ .line_of_business = try field.LineOfBusiness.parse("Retail") },
        .{ .atc = try field.Atc.parse("PT010") },
        .{ .tax_type = try field.TaxType.parse("Percentage Tax") },
        .{ .government_withholding_agent = .yes },
        .{ .special_rate_basis = try field.SpecialRateBasis.parse(
            "Treaty article 7",
        ) },
    };
    for (&values) |*value| {
        var buffer: [255]u8 = undefined;
        const encoded = serializeValue(value, &buffer);
        const decoded = try parseValue(
            value.field(),
            encoded.value_type,
            encoded.text,
        );
        try std.testing.expect(value.eql(&decoded));
    }
}

fn testIndividualRevision() !model.ProfileRevision {
    const base = try testBase(
        "profile-individual",
        "revision-individual",
        .manual_entry,
    );
    return try editor.begin(base).individual(.{
        .name = try field.TaxpayerName.parse("JUAN DELA CRUZ"),
        .date_of_birth = try model.Date.parseIso("1990-01-02"),
        .citizenship = try field.Citizenship.parse("Filipino"),
        .foreign_tax_number = try field.ForeignTaxNumber.parse("JP-98765"),
    }).build();
}

fn testBase(
    profile_id: []const u8,
    revision_id: []const u8,
    source: model.RevisionSource,
) !editor.Base {
    return .{
        .profile_id = try model.ProfileId.parse(profile_id),
        .revision_id = try model.RevisionId.parse(revision_id),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = source,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("1 Taxpayer Street"),
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse("tax@example.ph"),
        },
    };
}

fn expectRevisionEqual(
    expected: *const model.ProfileRevision,
    actual: *const model.ProfileRevision,
) !void {
    try std.testing.expect(expected.profile_id.eql(&actual.profile_id));
    try std.testing.expect(expected.id.eql(&actual.id));
    try std.testing.expectEqual(expected.sequence, actual.sequence);
    try expectEffectiveEqual(expected.effective, actual.effective);
    try expectSourceEqual(&expected.source, &actual.source);
    try std.testing.expect(expected.identity.tin.eql(&actual.identity.tin));
    try std.testing.expect(
        expected.identity.rdo_code.eql(&actual.identity.rdo_code),
    );
    try std.testing.expect(
        expected.contact.address.eql(&actual.contact.address),
    );
    try expectOptionalFieldEqual(
        field.ZipCode,
        expected.contact.zip_code,
        actual.contact.zip_code,
    );
    try expectOptionalFieldEqual(
        field.ContactNumber,
        expected.contact.contact_number,
        actual.contact.contact_number,
    );
    try expectOptionalFieldEqual(
        field.EmailAddress,
        expected.contact.email_address,
        actual.contact.email_address,
    );
    try expectSubjectEqual(&expected.subject, &actual.subject);

    try std.testing.expectEqual(
        expected.business_activities.len,
        actual.business_activities.len,
    );
    for (
        expected.business_activities,
        actual.business_activities,
    ) |*left, *right| {
        try std.testing.expect(left.id.eql(&right.id));
        try std.testing.expect(
            left.line_of_business.eql(&right.line_of_business),
        );
        try expectOptionalFieldEqual(field.Atc, left.atc, right.atc);
        try expectEffectiveEqual(left.effective, right.effective);
    }

    try std.testing.expectEqual(
        expected.registration_facts.len,
        actual.registration_facts.len,
    );
    for (
        expected.registration_facts,
        actual.registration_facts,
    ) |*left, *right| {
        try std.testing.expect(left.id.eql(&right.id));
        try expectEffectiveEqual(left.effective, right.effective);
        try std.testing.expectEqual(left.kind(), right.kind());
        switch (left.value) {
            .tax_type => |value| try std.testing.expect(
                value.eql(&right.value.tax_type),
            ),
            .government_withholding_agent => |value| try std.testing.expectEqual(
                value,
                right.value.government_withholding_agent,
            ),
            .special_rate_basis => |value| try std.testing.expect(
                value.eql(&right.value.special_rate_basis),
            ),
        }
    }
}

fn expectEffectiveEqual(
    expected: model.EffectivePeriod,
    actual: model.EffectivePeriod,
) !void {
    try std.testing.expect(expected.from.eql(actual.from));
    if (expected.until) |left| {
        try std.testing.expect(actual.until != null);
        try std.testing.expect(left.eql(actual.until.?));
    } else {
        try std.testing.expect(actual.until == null);
    }
}

fn expectSourceEqual(
    expected: *const model.RevisionSource,
    actual: *const model.RevisionSource,
) !void {
    try std.testing.expectEqual(
        std.meta.activeTag(expected.*),
        std.meta.activeTag(actual.*),
    );
    switch (expected.*) {
        .manual_entry => {},
        .imported => |reference| try std.testing.expect(
            reference.eql(&actual.imported),
        ),
        .migrated => |reference| try std.testing.expect(
            reference.eql(&actual.migrated),
        ),
    }
}

fn expectSubjectEqual(
    expected: *const model.Subject,
    actual: *const model.Subject,
) !void {
    try std.testing.expectEqual(
        std.meta.activeTag(expected.*),
        std.meta.activeTag(actual.*),
    );
    switch (expected.*) {
        .individual => |person| try expectIndividualEqual(
            &person,
            &actual.individual,
        ),
        .sole_proprietor => |proprietor| {
            try expectIndividualEqual(
                &proprietor.person,
                &actual.sole_proprietor.person,
            );
            try expectOptionalFieldEqual(
                field.RegisteredName,
                proprietor.trade_name,
                actual.sole_proprietor.trade_name,
            );
        },
        .legal_entity => |entity| {
            try std.testing.expectEqual(entity.kind, actual.legal_entity.kind);
            try std.testing.expect(
                entity.registered_name.eql(
                    &actual.legal_entity.registered_name,
                ),
            );
        },
    }
}

fn expectIndividualEqual(
    expected: *const model.Individual,
    actual: *const model.Individual,
) !void {
    try std.testing.expect(expected.name.eql(&actual.name));
    if (expected.date_of_birth) |date| {
        try std.testing.expect(actual.date_of_birth != null);
        try std.testing.expect(date.eql(actual.date_of_birth.?));
    } else {
        try std.testing.expect(actual.date_of_birth == null);
    }
    try expectOptionalFieldEqual(
        field.Citizenship,
        expected.citizenship,
        actual.citizenship,
    );
    try expectOptionalFieldEqual(
        field.ForeignTaxNumber,
        expected.foreign_tax_number,
        actual.foreign_tax_number,
    );
}

fn expectOptionalFieldEqual(
    comptime T: type,
    expected: ?T,
    actual: ?T,
) !void {
    if (expected) |left| {
        try std.testing.expect(actual != null);
        try std.testing.expect(left.eql(&actual.?));
    } else {
        try std.testing.expect(actual == null);
    }
}
