//! Tax-profile aggregate and immutable, effective-dated revisions.
//!
//! A revision is a composition of cohesive components rather than a single
//! struct full of nullable form fields. Different subject variants carry only
//! facts that are meaningful for that subject.

const std = @import("std");
const domain_date = @import("../domain/date.zig");
const field = @import("field.zig");

pub const Date = domain_date.Date;
pub const EffectivePeriod = domain_date.EffectivePeriod;

pub const IdError = error{
    Empty,
    TooLong,
    InvalidCharacter,
};

const IdKind = enum {
    profile,
    revision,
};

fn OpaqueId(comptime kind: IdKind) type {
    _ = kind;
    return struct {
        const Self = @This();

        bytes: [64]u8 = undefined,
        len: u8 = 0,

        pub fn parse(raw: []const u8) IdError!Self {
            const value = std.mem.trim(u8, raw, " \t\r\n");
            if (value.len == 0) return error.Empty;
            if (value.len > 64) return error.TooLong;
            for (value) |byte| {
                if (!std.ascii.isAlphanumeric(byte) and
                    byte != '-' and byte != '_' and byte != '.' and
                    byte != ':')
                {
                    return error.InvalidCharacter;
                }
            }
            var result: Self = .{};
            @memcpy(result.bytes[0..value.len], value);
            result.len = @intCast(value.len);
            return result;
        }

        pub fn asSlice(self: *const Self) []const u8 {
            return self.bytes[0..self.len];
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            return std.mem.eql(u8, self.asSlice(), other.asSlice());
        }
    };
}

pub const ProfileId = OpaqueId(.profile);
pub const RevisionId = OpaqueId(.revision);

pub const Identity = struct {
    tin: field.Tin,
    rdo_code: field.RdoCode,
};

pub const RegisteredContact = struct {
    address: field.RegisteredAddress,
    zip_code: ?field.ZipCode = null,
    contact_number: ?field.ContactNumber = null,
    email_address: ?field.EmailAddress = null,
};

/// Accounting-period facts belong to the reusable taxpayer record, not to
/// one form or filing. The containing `ProfileRevision` supplies the
/// effective date.
pub const AccountingPeriodBasis = field.AccountingPeriodBasis;

/// EOPT taxpayer size classification recorded on the effective Base Tax
/// Profile revision. `null` means not recorded; review-only migration states
/// are carried separately and are never exposed as selectable tiers.
pub const EoptTier = enum {
    micro,
    small,
    medium,
    large,

    pub fn label(self: EoptTier) []const u8 {
        return switch (self) {
            .micro => "Micro",
            .small => "Small",
            .medium => "Medium",
            .large => "Large",
        };
    }
};

/// Older normalized Registration streams can be copied into the Base Tax
/// Profile only when their answer is unambiguous. This marker preserves the
/// difference between "not recorded" and "legacy evidence needs review".
pub const ConsolidationReviewState = enum {
    confirmed,
    requires_review,
};

/// Filing classification for a natural-person taxpayer.
///
/// This is deliberately separate from `SubjectKind`: "Individual" answers
/// what legal person owns the profile, while this value records whether that
/// person has compensation, business/professional, or mixed income. Existing
/// records whose old `individual`/`sole_proprietor` tag does not prove the
/// answer migrate to `classification_unknown` and require review rather than
/// being guessed into a filing class.
pub const NaturalPersonClassification = enum {
    classification_unknown,
    pure_compensation,
    self_employed,
    mixed_income,
};

pub const Individual = struct {
    name: field.TaxpayerName,
    classification: NaturalPersonClassification = .classification_unknown,
    /// Optional registered business/trade name for a self-employed or
    /// mixed-income natural person. It is separate from the person's legal
    /// taxpayer name and is inapplicable to pure compensation.
    trade_name: ?field.RegisteredName = null,
    date_of_birth: ?Date = null,
    citizenship: ?field.Citizenship = null,
    foreign_tax_number: ?field.ForeignTaxNumber = null,
};

pub const SoleProprietor = struct {
    person: Individual,
    /// A DTI/registered trade name is not duplicated into the person's name.
    trade_name: ?field.RegisteredName = null,
};

pub const LegalEntityKind = enum {
    corporation,
    partnership,
    cooperative,
    estate,
    trust,
    other,
};

pub const LegalEntity = struct {
    registered_name: field.RegisteredName,
    trade_name: ?field.RegisteredName = null,
    kind: LegalEntityKind,
};

pub const SubjectKind = enum {
    individual,
    sole_proprietor,
    corporation,
    partnership,
    cooperative,
    estate,
    trust,
    other_legal_entity,
};

pub const SubjectKindSet = std.EnumSet(SubjectKind);

pub const Subject = union(enum) {
    individual: Individual,
    sole_proprietor: SoleProprietor,
    legal_entity: LegalEntity,

    pub fn kind(self: *const Subject) SubjectKind {
        return switch (self.*) {
            .individual => .individual,
            .sole_proprietor => .sole_proprietor,
            .legal_entity => |entity| switch (entity.kind) {
                .corporation => .corporation,
                .partnership => .partnership,
                .cooperative => .cooperative,
                .estate => .estate,
                .trust => .trust,
                .other => .other_legal_entity,
            },
        };
    }

    /// The exact combined name displayed by the current Native form editors.
    /// Legal names are converted, never mirrored as sibling stored fields.
    pub fn taxpayerName(self: *const Subject) field.TaxpayerName {
        return switch (self.*) {
            .individual => |person| person.name,
            .sole_proprietor => |proprietor| proprietor.person.name,
            .legal_entity => |entity| field.TaxpayerName.parse(
                entity.registered_name.asSlice(),
            ) catch unreachable,
        };
    }

    pub fn registeredName(self: *const Subject) ?field.RegisteredName {
        return switch (self.*) {
            .individual => |person| person.trade_name,
            .sole_proprietor => |proprietor| proprietor.trade_name,
            .legal_entity => |entity| entity.registered_name,
        };
    }

    pub fn tradeName(self: *const Subject) ?field.RegisteredName {
        return switch (self.*) {
            .individual => |person| person.trade_name,
            .sole_proprietor => |proprietor| proprietor.trade_name,
            .legal_entity => |entity| entity.trade_name,
        };
    }

    pub fn individualDetails(self: *const Subject) ?*const Individual {
        return switch (self.*) {
            .individual => |*person| person,
            .sole_proprietor => |*proprietor| &proprietor.person,
            .legal_entity => null,
        };
    }

    pub fn naturalPersonClassification(
        self: *const Subject,
    ) ?NaturalPersonClassification {
        return switch (self.*) {
            .individual => |person| person.classification,
            // Compatibility-only legacy subject rows carry enough evidence
            // to migrate to Individual + self-employed without guessing.
            .sole_proprietor => .self_employed,
            .legal_entity => null,
        };
    }
};

pub const RevisionSource = union(enum) {
    manual_entry,
    imported: field.SourceReference,
    migrated: field.SourceReference,
};

pub const RevisionError = error{
    InvalidSequence,
    InvalidAccountingPeriod,
};

/// Immutable by API: there are no setters. Updating profile facts means
/// appending another revision to a `History`, never changing this value.
pub const ProfileRevision = struct {
    profile_id: ProfileId,
    id: RevisionId,
    sequence: u32,
    effective: EffectivePeriod,
    source: RevisionSource,
    identity: Identity,
    contact: RegisteredContact,
    subject: Subject,
    accounting_period_basis: ?AccountingPeriodBasis = null,
    fiscal_year_end_month: ?u8 = null,
    eopt_tier: ?EoptTier = null,
    primary_line_of_business: ?field.LineOfBusiness = null,
    consolidation_review_state: ConsolidationReviewState = .confirmed,

    pub fn validate(self: *const ProfileRevision) RevisionError!void {
        if (self.sequence == 0) return error.InvalidSequence;
        if (self.accounting_period_basis) |basis| {
            switch (basis) {
                .calendar => if (self.fiscal_year_end_month != null) {
                    return error.InvalidAccountingPeriod;
                },
                .fiscal => {
                    const month = self.fiscal_year_end_month orelse
                        return error.InvalidAccountingPeriod;
                    if (month < 1 or month > 12) {
                        return error.InvalidAccountingPeriod;
                    }
                },
            }
        } else if (self.fiscal_year_end_month != null) {
            return error.InvalidAccountingPeriod;
        }
    }

    pub fn isEffective(self: *const ProfileRevision, on: Date) bool {
        return self.effective.contains(on);
    }

    /// True when two revisions record the same taxpayer facts.
    ///
    /// Identity — which revision this is, and where it sits in the sequence —
    /// is excluded: the question is whether appending would record anything.
    /// Everything a reader of history would call a change is included, the
    /// source among them, because "manual entry" becoming "imported from a
    /// COR" is a real difference in what the record claims.
    ///
    /// Comparison runs on parsed values, so text that differs only in
    /// formatting a field normalizes away is equal here.
    pub fn contentEquals(
        self: *const ProfileRevision,
        other: *const ProfileRevision,
    ) bool {
        if (!self.effective.eql(other.effective)) return false;
        if (!revisionSourceEquals(self.source, other.source)) return false;
        if (!self.identity.tin.eql(&other.identity.tin)) return false;
        if (!self.identity.rdo_code.eql(&other.identity.rdo_code)) return false;
        if (!contactEquals(&self.contact, &other.contact)) return false;
        if (!subjectEquals(&self.subject, &other.subject)) return false;
        if (self.accounting_period_basis != other.accounting_period_basis) {
            return false;
        }
        if (self.fiscal_year_end_month != other.fiscal_year_end_month) {
            return false;
        }
        if (self.eopt_tier != other.eopt_tier) return false;
        if (!optionalFieldEquals(
            self.primary_line_of_business,
            other.primary_line_of_business,
        )) return false;
        return self.consolidation_review_state ==
            other.consolidation_review_state;
    }
};

fn optionalFieldEquals(left: anytype, right: @TypeOf(left)) bool {
    if (left) |*value| {
        const other = &(right orelse return false);
        return value.eql(other);
    }
    return right == null;
}

fn revisionSourceEquals(left: RevisionSource, right: RevisionSource) bool {
    return switch (left) {
        .manual_entry => right == .manual_entry,
        .imported => |reference| switch (right) {
            .imported => |other| reference.eql(&other),
            else => false,
        },
        .migrated => |reference| switch (right) {
            .migrated => |other| reference.eql(&other),
            else => false,
        },
    };
}

fn contactEquals(
    left: *const RegisteredContact,
    right: *const RegisteredContact,
) bool {
    if (!left.address.eql(&right.address)) return false;
    if (!optionalFieldEquals(left.zip_code, right.zip_code)) return false;
    if (!optionalFieldEquals(left.contact_number, right.contact_number)) {
        return false;
    }
    return optionalFieldEquals(left.email_address, right.email_address);
}

fn individualEquals(left: *const Individual, right: *const Individual) bool {
    if (!left.name.eql(&right.name)) return false;
    if (left.classification != right.classification) return false;
    if (!optionalFieldEquals(left.trade_name, right.trade_name)) return false;
    if (left.date_of_birth) |value| {
        const other = right.date_of_birth orelse return false;
        if (!value.eql(other)) return false;
    } else if (right.date_of_birth != null) return false;
    if (!optionalFieldEquals(left.citizenship, right.citizenship)) return false;
    return optionalFieldEquals(
        left.foreign_tax_number,
        right.foreign_tax_number,
    );
}

fn subjectEquals(left: *const Subject, right: *const Subject) bool {
    return switch (left.*) {
        .individual => |*person| switch (right.*) {
            .individual => |*other| individualEquals(person, other),
            else => false,
        },
        .sole_proprietor => |*proprietor| switch (right.*) {
            .sole_proprietor => |*other| individualEquals(
                &proprietor.person,
                &other.person,
            ) and optionalFieldEquals(proprietor.trade_name, other.trade_name),
            else => false,
        },
        .legal_entity => |*entity| switch (right.*) {
            .legal_entity => |*other| entity.kind == other.kind and
                entity.registered_name.eql(&other.registered_name) and
                optionalFieldEquals(entity.trade_name, other.trade_name),
            else => false,
        },
    };
}

pub const HistoryError = RevisionError || error{
    EmptyHistory,
    WrongProfile,
    DuplicateRevisionId,
    DuplicateSequence,
    NoEffectiveRevision,
};

/// Append-only revision history.
///
/// Effective periods may overlap intentionally: appending a correction must
/// not rewrite or close an earlier immutable revision. For a requested date,
/// the effective revision with the greatest sequence supersedes all earlier
/// effective revisions. Future starts and explicit expiry still determine
/// whether a revision is eligible at all.
pub const History = struct {
    profile_id: ProfileId,
    revisions: []const ProfileRevision,

    pub fn validate(self: *const History) HistoryError!void {
        if (self.revisions.len == 0) return error.EmptyHistory;
        for (self.revisions, 0..) |*revision, index| {
            try revision.validate();
            if (!revision.profile_id.eql(&self.profile_id)) {
                return error.WrongProfile;
            }
            for (self.revisions[index + 1 ..]) |*other| {
                if (revision.id.eql(&other.id)) {
                    return error.DuplicateRevisionId;
                }
                if (revision.sequence == other.sequence) {
                    return error.DuplicateSequence;
                }
            }
        }
    }

    pub fn resolve(
        self: *const History,
        on: Date,
    ) HistoryError!*const ProfileRevision {
        try self.validate();
        var found: ?*const ProfileRevision = null;
        for (self.revisions) |*revision| {
            if (!revision.isEffective(on)) continue;
            if (found == null or revision.sequence > found.?.sequence) {
                found = revision;
            }
        }
        return found orelse error.NoEffectiveRevision;
    }
};

fn exampleContact() !RegisteredContact {
    return .{
        .address = try field.RegisteredAddress.parse("1 Taxpayer Street"),
        .zip_code = try field.ZipCode.parse("1000"),
        .contact_number = try field.ContactNumber.parse("+639171234567"),
        .email_address = try field.EmailAddress.parse("maria@example.ph"),
    };
}

fn exampleRevision(
    revision_id: []const u8,
    sequence: u32,
    effective: EffectivePeriod,
) !ProfileRevision {
    return .{
        .profile_id = try ProfileId.parse("profile-maria"),
        .id = try RevisionId.parse(revision_id),
        .sequence = sequence,
        .effective = effective,
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = try exampleContact(),
        .subject = .{ .sole_proprietor = .{
            .person = .{
                .name = try field.TaxpayerName.parse("MARIA SANTOS"),
                .date_of_birth = try Date.parseIso("1995-06-01"),
                .citizenship = try field.Citizenship.parse("Filipino"),
            },
            .trade_name = try field.RegisteredName.parse("MARIA'S BAKERY"),
        } },
    };
}

test "subject variants expose truthful derived capabilities" {
    const revision = try exampleRevision(
        "revision-1",
        1,
        try EffectivePeriod.init(try Date.parseIso("2026-01-01"), null),
    );
    try std.testing.expectEqual(
        SubjectKind.sole_proprietor,
        revision.subject.kind(),
    );
    try std.testing.expectEqualStrings(
        "MARIA SANTOS",
        revision.subject.taxpayerName().asSlice(),
    );
    try std.testing.expectEqualStrings(
        "MARIA'S BAKERY",
        revision.subject.registeredName().?.asSlice(),
    );
}

test "cooperative is a first-class legal entity subject" {
    const subject: Subject = .{ .legal_entity = .{
        .registered_name = try field.RegisteredName.parse(
            "EXAMPLE WORKERS COOPERATIVE",
        ),
        .kind = .cooperative,
    } };
    try std.testing.expectEqual(SubjectKind.cooperative, subject.kind());
    try std.testing.expectEqualStrings(
        "EXAMPLE WORKERS COOPERATIVE",
        subject.taxpayerName().asSlice(),
    );
}

test "history accepts an open-ended append and resolves by date and sequence" {
    const first = try exampleRevision(
        "revision-1",
        1,
        try EffectivePeriod.init(try Date.parseIso("2026-01-01"), null),
    );
    const second = try exampleRevision(
        "revision-2",
        2,
        try EffectivePeriod.init(try Date.parseIso("2026-07-01"), null),
    );
    const revisions = [_]ProfileRevision{ first, second };
    const history: History = .{
        .profile_id = try ProfileId.parse("profile-maria"),
        .revisions = &revisions,
    };

    try history.validate();
    const past = try history.resolve(try Date.parseIso("2026-03-31"));
    try std.testing.expectEqual(@as(u32, 1), past.sequence);
    const later = try history.resolve(try Date.parseIso("2026-08-01"));
    try std.testing.expectEqual(@as(u32, 2), later.sequence);
}

test "retroactive overlap resolves to the highest effective sequence" {
    const first = try exampleRevision(
        "revision-1",
        1,
        try EffectivePeriod.init(try Date.parseIso("2026-01-01"), null),
    );
    const second = try exampleRevision(
        "revision-2",
        2,
        try EffectivePeriod.init(try Date.parseIso("2026-02-01"), null),
    );
    // Deliberately unsorted: selection is based on sequence, not slice order.
    const revisions = [_]ProfileRevision{ second, first };
    const history: History = .{
        .profile_id = try ProfileId.parse("profile-maria"),
        .revisions = &revisions,
    };

    try history.validate();
    const corrected = try history.resolve(try Date.parseIso("2026-02-15"));
    try std.testing.expectEqual(
        @as(u32, 2),
        corrected.sequence,
    );
}

test "content comparison ignores identity and sees every recorded fact" {
    const period = try EffectivePeriod.init(
        try Date.parseIso("2026-01-01"),
        null,
    );
    const first = try exampleRevision("revision-1", 1, period);
    // A different revision id and sequence is not a difference in content:
    // the question is whether appending would record anything.
    var second = try exampleRevision("revision-2", 7, period);
    try std.testing.expect(first.contentEquals(&second));
    try std.testing.expect(second.contentEquals(&first));

    // The same TIN written differently parses to the same canonical value.
    second.identity.tin = try field.Tin.parse("123456789000");
    try std.testing.expect(first.contentEquals(&second));

    second.identity.tin = try field.Tin.parse("987-654-321-000");
    try std.testing.expect(!first.contentEquals(&second));
    second.identity.tin = first.identity.tin;

    second.contact.email_address = null;
    try std.testing.expect(!first.contentEquals(&second));
    second.contact.email_address = first.contact.email_address;
    try std.testing.expect(first.contentEquals(&second));

    // The source is part of the record: where a fact came from is a claim.
    second.source = .{ .imported = try field.SourceReference.parse("COR") };
    try std.testing.expect(!first.contentEquals(&second));
    second.source = first.source;

    second.effective = try EffectivePeriod.init(
        try Date.parseIso("2026-07-01"),
        null,
    );
    try std.testing.expect(!first.contentEquals(&second));
    second.effective = first.effective;

    second.subject = .{ .individual = .{
        .name = try field.TaxpayerName.parse("MARIA SANTOS"),
    } };
    try std.testing.expect(!first.contentEquals(&second));
    second.subject = first.subject;

    second.primary_line_of_business =
        try field.LineOfBusiness.parse("Retail");
    try std.testing.expect(!first.contentEquals(&second));
    second.primary_line_of_business = first.primary_line_of_business;

    second.eopt_tier = .micro;
    try std.testing.expect(!first.contentEquals(&second));
    second.eopt_tier = first.eopt_tier;

    second.accounting_period_basis = .calendar;
    try std.testing.expect(!first.contentEquals(&second));
}

test "an effective period equals only an identical one" {
    const from = try Date.parseIso("2026-01-01");
    const open = try EffectivePeriod.init(from, null);
    const closed = try EffectivePeriod.init(
        from,
        try Date.parseIso("2026-12-31"),
    );
    try std.testing.expect(open.eql(try EffectivePeriod.init(from, null)));
    // An open period never equals a closed one, in either direction.
    try std.testing.expect(!open.eql(closed));
    try std.testing.expect(!closed.eql(open));
    try std.testing.expect(!open.eql(try EffectivePeriod.init(
        try Date.parseIso("2026-02-01"),
        null,
    )));
}
