//! Validated, allocation-free vocabulary shared by profiles and forms.
//!
//! Values are normalized and copied into bounded storage at the input
//! boundary. A `Value` can consequently be copied into a filing snapshot
//! without borrowing profile or UI memory.

const std = @import("std");
const date = @import("../domain/date.zig");

pub const Date = date.Date;

pub const TextError = error{
    Empty,
    TooLong,
    InvalidUtf8,
    ControlCharacter,
};

const TextKind = enum {
    taxpayer_name,
    registered_name,
    registered_address,
    email_address,
    citizenship,
    foreign_tax_number,
    line_of_business,
    eopt_tier,
    tax_type,
    special_rate_basis,
    source_reference,
};

fn BoundedText(comptime kind: TextKind, comptime maximum: usize) type {
    _ = kind;
    return struct {
        const Self = @This();
        const Length = std.math.IntFittingRange(0, maximum);

        bytes: [maximum]u8 = undefined,
        len: Length = 0,

        pub fn parse(raw: []const u8) TextError!Self {
            const value = std.mem.trim(u8, raw, " \t\r\n");
            if (value.len == 0) return error.Empty;
            if (value.len > maximum) return error.TooLong;
            if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
            for (value) |byte| {
                if (byte < 0x20 or byte == 0x7f) {
                    return error.ControlCharacter;
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

pub const TaxpayerName = BoundedText(.taxpayer_name, 160);
pub const RegisteredName = BoundedText(.registered_name, 160);
pub const RegisteredAddress = BoundedText(.registered_address, 255);
pub const Citizenship = BoundedText(.citizenship, 80);
pub const ForeignTaxNumber = BoundedText(.foreign_tax_number, 64);
pub const LineOfBusiness = BoundedText(.line_of_business, 160);
pub const EoptTier = BoundedText(.eopt_tier, 16);
pub const TaxType = BoundedText(.tax_type, 80);
pub const SpecialRateBasis = BoundedText(.special_rate_basis, 160);
pub const SourceReference = BoundedText(.source_reference, 160);

pub const GovernmentWithholdingAgent = enum {
    no,
    yes,
};

/// Reusable accounting-period ownership. Fiscal year-end month remains on
/// the containing effective-dated profile revision because it is meaningful
/// only when this value is `.fiscal`.
pub const AccountingPeriodBasis = enum {
    calendar,
    fiscal,

    pub fn label(self: AccountingPeriodBasis) []const u8 {
        return switch (self) {
            .calendar => "Calendar year",
            .fiscal => "Fiscal year",
        };
    }
};

pub const TinError = error{
    InvalidCharacter,
    InvalidLength,
};

pub const Tin = struct {
    digits: [14]u8 = undefined,
    len: u8 = 0,

    /// Accepts a 9-digit root plus an optional 3-5 digit branch code.
    /// ASCII whitespace and `-` separators are ignored.
    pub fn parse(raw: []const u8) TinError!Tin {
        var result: Tin = .{};
        for (raw) |byte| {
            if (std.ascii.isDigit(byte)) {
                if (result.len == result.digits.len) {
                    return error.InvalidLength;
                }
                result.digits[result.len] = byte;
                result.len += 1;
            } else if (byte != '-' and !std.ascii.isWhitespace(byte)) {
                return error.InvalidCharacter;
            }
        }
        if (result.len != 9 and (result.len < 12 or result.len > 14)) {
            return error.InvalidLength;
        }
        return result;
    }

    pub fn asDigits(self: *const Tin) []const u8 {
        return self.digits[0..self.len];
    }

    pub fn root(self: *const Tin) []const u8 {
        return self.digits[0..9];
    }

    pub fn branch(self: *const Tin) ?[]const u8 {
        if (self.len == 9) return null;
        return self.digits[9..self.len];
    }

    pub fn write(self: *const Tin, buffer: []u8) error{NoSpaceLeft}![]const u8 {
        if (self.branch()) |branch_code| {
            return std.fmt.bufPrint(
                buffer,
                "{s}-{s}-{s}-{s}",
                .{
                    self.digits[0..3],
                    self.digits[3..6],
                    self.digits[6..9],
                    branch_code,
                },
            );
        }
        return std.fmt.bufPrint(
            buffer,
            "{s}-{s}-{s}",
            .{ self.digits[0..3], self.digits[3..6], self.digits[6..9] },
        );
    }

    /// Safe for diagnostics; never emits the full taxpayer identifier.
    pub fn writeMasked(
        self: *const Tin,
        buffer: []u8,
    ) error{NoSpaceLeft}![]const u8 {
        return std.fmt.bufPrint(
            buffer,
            "***-***-{s}{s}",
            .{
                self.digits[6..9],
                if (self.len > 9) "-***" else "",
            },
        );
    }

    pub fn eql(self: *const Tin, other: *const Tin) bool {
        return std.mem.eql(u8, self.asDigits(), other.asDigits());
    }
};

pub const RdoCodeError = error{
    InvalidLength,
    InvalidCharacter,
};

pub const RdoCode = struct {
    bytes: [3]u8 = undefined,
    len: u8 = 0,

    pub fn parse(raw: []const u8) RdoCodeError!RdoCode {
        const value = std.mem.trim(u8, raw, " \t\r\n");
        if (value.len < 2 or value.len > 3) return error.InvalidLength;
        var result: RdoCode = .{};
        for (value, 0..) |byte, index| {
            if (!std.ascii.isAlphanumeric(byte)) {
                return error.InvalidCharacter;
            }
            result.bytes[index] = std.ascii.toUpper(byte);
        }
        result.len = @intCast(value.len);
        return result;
    }

    pub fn asSlice(self: *const RdoCode) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(self: *const RdoCode, other: *const RdoCode) bool {
        return std.mem.eql(u8, self.asSlice(), other.asSlice());
    }
};

pub const AtcError = error{
    InvalidLength,
    InvalidCharacter,
};

pub const Atc = struct {
    bytes: [7]u8 = undefined,
    len: u8 = 0,

    pub fn parse(raw: []const u8) AtcError!Atc {
        var result: Atc = .{};
        for (raw) |byte| {
            if (std.ascii.isWhitespace(byte) or byte == '-') continue;
            if (!std.ascii.isAlphanumeric(byte)) {
                return error.InvalidCharacter;
            }
            if (result.len == result.bytes.len) return error.InvalidLength;
            result.bytes[result.len] = std.ascii.toUpper(byte);
            result.len += 1;
        }
        if (result.len < 3) return error.InvalidLength;
        return result;
    }

    pub fn asSlice(self: *const Atc) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(self: *const Atc, other: *const Atc) bool {
        return std.mem.eql(u8, self.asSlice(), other.asSlice());
    }
};

pub const ZipCodeError = error{InvalidZipCode};

pub const ZipCode = struct {
    digits: [4]u8,

    pub fn parse(raw: []const u8) ZipCodeError!ZipCode {
        const value = std.mem.trim(u8, raw, " \t\r\n");
        if (value.len != 4) return error.InvalidZipCode;
        for (value) |byte| {
            if (!std.ascii.isDigit(byte)) return error.InvalidZipCode;
        }
        return .{ .digits = value[0..4].* };
    }

    pub fn asSlice(self: *const ZipCode) []const u8 {
        return &self.digits;
    }

    pub fn eql(self: *const ZipCode, other: *const ZipCode) bool {
        return std.mem.eql(u8, self.asSlice(), other.asSlice());
    }
};

pub const ContactNumberError = error{
    InvalidCharacter,
    InvalidPhilippineNumber,
};

pub const ContactNumber = struct {
    bytes: [16]u8 = undefined,
    len: u8 = 0,

    /// Accepts a Philippine mobile or geographic number in one of the three
    /// public forms people normally enter: `+63…`, `63…`, or `0…`.
    ///
    /// Formatting punctuation is ignored and every valid representation is
    /// stored in canonical E.164 form (`+63…`). This is deliberately a
    /// format check, not a claim that a particular number is currently
    /// allocated to a subscriber.
    pub fn parse(raw: []const u8) ContactNumberError!ContactNumber {
        var input: [16]u8 = undefined;
        var input_len: usize = 0;
        for (raw) |byte| {
            if (std.ascii.isDigit(byte)) {
                if (input_len == input.len) return error.InvalidPhilippineNumber;
                input[input_len] = byte;
                input_len += 1;
                continue;
            }
            if (byte == '+' and input_len == 0) {
                input[0] = byte;
                input_len = 1;
                continue;
            }
            if (byte == ' ' or byte == '-' or byte == '(' or byte == ')') {
                continue;
            }
            return error.InvalidCharacter;
        }

        const has_plus = input_len > 0 and input[0] == '+';
        const digits = input[@intFromBool(has_plus)..input_len];
        const national = if (std.mem.startsWith(u8, digits, "63"))
            digits[2..]
        else if (!has_plus and std.mem.startsWith(u8, digits, "0"))
            digits[1..]
        else
            return error.InvalidPhilippineNumber;

        const valid_mobile = national.len == 10 and national[0] == '9';
        const valid_geographic = national.len == 9 and
            national[0] >= '2' and national[0] <= '8';
        if (!valid_mobile and !valid_geographic) {
            return error.InvalidPhilippineNumber;
        }

        var result: ContactNumber = .{};
        result.bytes[0] = '+';
        result.bytes[1] = '6';
        result.bytes[2] = '3';
        @memcpy(result.bytes[3 .. 3 + national.len], national);
        result.len = @intCast(3 + national.len);
        return result;
    }

    pub fn asSlice(self: *const ContactNumber) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(self: *const ContactNumber, other: *const ContactNumber) bool {
        return std.mem.eql(u8, self.asSlice(), other.asSlice());
    }
};

pub const EmailAddressError = TextError || error{InvalidEmailAddress};

pub const EmailAddress = struct {
    value: BoundedText(.email_address, 254),

    pub fn parse(raw: []const u8) EmailAddressError!EmailAddress {
        const value = try BoundedText(.email_address, 254).parse(raw);
        const text = value.asSlice();
        const at = std.mem.indexOfScalar(u8, text, '@') orelse
            return error.InvalidEmailAddress;
        if (at == 0 or at + 1 == text.len or at > 64) {
            return error.InvalidEmailAddress;
        }
        if (std.mem.indexOfScalarPos(u8, text, at + 1, '@') != null) {
            return error.InvalidEmailAddress;
        }
        if (!validEmailLocal(text[0..at]) or !validEmailDomain(text[at + 1 ..])) {
            return error.InvalidEmailAddress;
        }
        return .{ .value = value };
    }

    pub fn asSlice(self: *const EmailAddress) []const u8 {
        return self.value.asSlice();
    }

    pub fn eql(self: *const EmailAddress, other: *const EmailAddress) bool {
        return std.ascii.eqlIgnoreCase(self.asSlice(), other.asSlice());
    }
};

fn validEmailLocal(value: []const u8) bool {
    if (value.len == 0 or value[0] == '.' or value[value.len - 1] == '.') {
        return false;
    }
    var previous_dot = false;
    for (value) |byte| {
        const valid = std.ascii.isAlphanumeric(byte) or switch (byte) {
            '!', '#', '$', '%', '&', '\'', '*', '+', '-', '/', '=', '?', '^', '_', '`', '{', '|', '}', '~', '.' => true,
            else => false,
        };
        if (!valid) return false;
        if (byte == '.' and previous_dot) return false;
        previous_dot = byte == '.';
    }
    return true;
}

fn validEmailDomain(value: []const u8) bool {
    if (value.len == 0 or std.mem.indexOfScalar(u8, value, '.') == null) {
        return false;
    }
    var label_start: usize = 0;
    var label_count: usize = 0;
    for (value, 0..) |byte, index| {
        if (byte == '.') {
            if (!validEmailDomainLabel(value[label_start..index])) return false;
            label_count += 1;
            label_start = index + 1;
            continue;
        }
        if (!std.ascii.isAlphanumeric(byte) and byte != '-') return false;
    }
    if (!validEmailDomainLabel(value[label_start..])) return false;
    return label_count >= 1;
}

fn validEmailDomainLabel(value: []const u8) bool {
    return value.len != 0 and value.len <= 63 and value[0] != '-' and
        value[value.len - 1] != '-';
}

pub const BirthDateError = error{InvalidBirthDate};

/// Parses the birth-date entry formats accepted by the profile editor. A
/// two-digit year is resolved against the supplied current year: values up to
/// that year's final two digits are in the 2000s; the remainder are in the
/// 1900s. The caller owns the separate "not in the future" business rule.
pub fn parseBirthDate(raw: []const u8, current_year: u16) BirthDateError!Date {
    const value = std.mem.trim(u8, raw, " \t\r\n");
    if (value.len == 10 and value[4] == '-' and value[7] == '-') {
        return Date.parseIso(value) catch error.InvalidBirthDate;
    }

    const parts = blk: {
        var digits_only = value.len != 0;
        for (value) |byte| {
            if (!std.ascii.isDigit(byte)) {
                digits_only = false;
                break;
            }
        }
        if (digits_only) {
            break :blk switch (value.len) {
                // MDDYY, MMDDYY, MDDYYYY, and MMDDYYYY respectively.
                5 => [_][]const u8{ value[0..1], value[1..3], value[3..5] },
                6 => [_][]const u8{ value[0..2], value[2..4], value[4..6] },
                7 => [_][]const u8{ value[0..1], value[1..3], value[3..7] },
                8 => [_][]const u8{ value[0..2], value[2..4], value[4..8] },
                else => return error.InvalidBirthDate,
            };
        }

        const first_slash = std.mem.indexOfScalar(u8, value, '/') orelse
            return error.InvalidBirthDate;
        const second_slash = std.mem.indexOfScalarPos(
            u8,
            value,
            first_slash + 1,
            '/',
        ) orelse return error.InvalidBirthDate;
        if (std.mem.indexOfScalarPos(u8, value, second_slash + 1, '/') != null) {
            return error.InvalidBirthDate;
        }
        break :blk [_][]const u8{
            value[0..first_slash],
            value[first_slash + 1 .. second_slash],
            value[second_slash + 1 ..],
        };
    };
    const month_text = parts[0];
    const day_text = parts[1];
    const year_text = parts[2];
    if (month_text.len == 0 or month_text.len > 2 or
        day_text.len == 0 or day_text.len > 2 or
        (year_text.len != 2 and year_text.len != 4))
    {
        return error.InvalidBirthDate;
    }
    const month = std.fmt.parseInt(u8, month_text, 10) catch
        return error.InvalidBirthDate;
    const day = std.fmt.parseInt(u8, day_text, 10) catch
        return error.InvalidBirthDate;
    const parsed_year = std.fmt.parseInt(u16, year_text, 10) catch
        return error.InvalidBirthDate;
    const year = if (year_text.len == 2)
        if (parsed_year <= current_year % 100)
            @as(u16, 2000) + parsed_year
        else
            @as(u16, 1900) + parsed_year
    else
        parsed_year;
    return Date.init(year, month, day) catch error.InvalidBirthDate;
}

pub const QuarterError = error{InvalidQuarter};

pub const Quarter = struct {
    year: u16,
    number: u8,

    pub fn init(year: u16, number: u8) QuarterError!Quarter {
        if (year == 0 or number < 1 or number > 4) {
            return error.InvalidQuarter;
        }
        return .{ .year = year, .number = number };
    }
};

/// The reusable vocabulary is deliberately independent from concrete profile
/// variants and concrete forms. Forms select subsets with `FieldSet`.
pub const ReusableField = enum {
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
    accounting_period_basis,
    line_of_business,
    eopt_tier,
    atc,
    tax_type,
    government_withholding_agent,
    special_rate_basis,
};

pub const FieldSet = std.EnumSet(ReusableField);

pub const Value = union(ReusableField) {
    tin: Tin,
    rdo_code: RdoCode,
    taxpayer_name: TaxpayerName,
    registered_name: RegisteredName,
    registered_address: RegisteredAddress,
    zip_code: ZipCode,
    contact_number: ContactNumber,
    email_address: EmailAddress,
    date_of_birth: Date,
    citizenship: Citizenship,
    foreign_tax_number: ForeignTaxNumber,
    accounting_period_basis: AccountingPeriodBasis,
    line_of_business: LineOfBusiness,
    eopt_tier: EoptTier,
    atc: Atc,
    tax_type: TaxType,
    government_withholding_agent: GovernmentWithholdingAgent,
    special_rate_basis: SpecialRateBasis,

    pub fn field(self: Value) ReusableField {
        return self;
    }

    pub fn eql(self: *const Value, other: *const Value) bool {
        if (self.field() != other.field()) return false;
        return switch (self.*) {
            .tin => |value| value.eql(&other.tin),
            .rdo_code => |value| value.eql(&other.rdo_code),
            .taxpayer_name => |value| value.eql(&other.taxpayer_name),
            .registered_name => |value| value.eql(&other.registered_name),
            .registered_address => |value| value.eql(&other.registered_address),
            .zip_code => |value| value.eql(&other.zip_code),
            .contact_number => |value| value.eql(&other.contact_number),
            .email_address => |value| value.eql(&other.email_address),
            .date_of_birth => |value| value.eql(other.date_of_birth),
            .citizenship => |value| value.eql(&other.citizenship),
            .foreign_tax_number => |value| value.eql(&other.foreign_tax_number),
            .accounting_period_basis => |value| value == other.accounting_period_basis,
            .line_of_business => |value| value.eql(&other.line_of_business),
            .eopt_tier => |value| value.eql(&other.eopt_tier),
            .atc => |value| value.eql(&other.atc),
            .tax_type => |value| value.eql(&other.tax_type),
            .government_withholding_agent => |value| value == other.government_withholding_agent,
            .special_rate_basis => |value| value.eql(&other.special_rate_basis),
        };
    }
};

test "TIN normalization preserves root and optional branch" {
    const root = try Tin.parse("123-456-789");
    const branch = try Tin.parse("123-456-789-000");
    try std.testing.expectEqualStrings("123456789", root.asDigits());
    try std.testing.expectEqualStrings("000", branch.branch().?);

    var full_buffer: [24]u8 = undefined;
    try std.testing.expectEqualStrings(
        "123-456-789-000",
        try branch.write(&full_buffer),
    );
    var masked_buffer: [24]u8 = undefined;
    try std.testing.expectEqualStrings(
        "***-***-789-***",
        try branch.writeMasked(&masked_buffer),
    );
}

test "TIN rejects invalid lengths and non-separator characters" {
    try std.testing.expectError(error.InvalidLength, Tin.parse("12345"));
    try std.testing.expectError(
        error.InvalidCharacter,
        Tin.parse("123-ABC-789"),
    );
}

test "semantic text types normalize only boundary whitespace" {
    const name = try TaxpayerName.parse("  MARIA SANTOS  ");
    const address = try RegisteredAddress.parse("1 Taxpayer Street");
    try std.testing.expectEqualStrings("MARIA SANTOS", name.asSlice());
    try std.testing.expectEqualStrings(
        "1 Taxpayer Street",
        address.asSlice(),
    );
}

test "Philippine ZIP code has exactly four digits" {
    const zip = try ZipCode.parse(" 1000 ");
    try std.testing.expectEqualStrings("1000", zip.asSlice());
    try std.testing.expectError(
        error.InvalidZipCode,
        ZipCode.parse("100"),
    );
    try std.testing.expectError(
        error.InvalidZipCode,
        ZipCode.parse("10A0"),
    );
}

test "contact fields reject malformed values" {
    const number = try ContactNumber.parse("+63 (917) 123-4567");
    const email = try EmailAddress.parse("tax@example.ph");
    try std.testing.expectEqualStrings("+639171234567", number.asSlice());
    try std.testing.expectEqualStrings("tax@example.ph", email.asSlice());
    try std.testing.expectError(
        error.InvalidEmailAddress,
        EmailAddress.parse("not-an-email"),
    );
}

test "Philippine contact numbers accept mobile and geographic national formats" {
    const mobile_international = try ContactNumber.parse("+63 917 123 4567");
    try std.testing.expectEqualStrings(
        "+639171234567",
        mobile_international.asSlice(),
    );

    const mobile_country_code = try ContactNumber.parse("63 917 123 4567");
    try std.testing.expectEqualStrings(
        "+639171234567",
        mobile_country_code.asSlice(),
    );

    const mobile_domestic = try ContactNumber.parse("0917 123 4567");
    try std.testing.expectEqualStrings(
        "+639171234567",
        mobile_domestic.asSlice(),
    );

    const metro_manila = try ContactNumber.parse("02 8123 4567");
    try std.testing.expectEqualStrings("+63281234567", metro_manila.asSlice());

    const provincial = try ContactNumber.parse("+63 32 123 4567");
    try std.testing.expectEqualStrings(
        "+63321234567",
        provincial.asSlice(),
    );

    const provincial_domestic = try ContactNumber.parse("063 123 4567");
    try std.testing.expectEqualStrings(
        "+63631234567",
        provincial_domestic.asSlice(),
    );

    try std.testing.expectError(
        error.InvalidPhilippineNumber,
        ContactNumber.parse("+63 900 000 000"),
    );
    try std.testing.expectError(
        error.InvalidPhilippineNumber,
        ContactNumber.parse("0712 123 4567"),
    );
    try std.testing.expectError(
        error.InvalidPhilippineNumber,
        ContactNumber.parse("8123 4567"),
    );
}

test "registered email validation rejects malformed mailbox and domain shapes" {
    _ = try EmailAddress.parse("tax.payer+records@example.com.ph");
    try std.testing.expectError(
        error.InvalidEmailAddress,
        EmailAddress.parse(".taxpayer@example.ph"),
    );
    try std.testing.expectError(
        error.InvalidEmailAddress,
        EmailAddress.parse("taxpayer..records@example.ph"),
    );
    try std.testing.expectError(
        error.InvalidEmailAddress,
        EmailAddress.parse("taxpayer@example-.ph"),
    );
    try std.testing.expectError(
        error.InvalidEmailAddress,
        EmailAddress.parse("taxpayer@example"),
    );
}

test "birth date accepts Filipino entry formats and resolves two digit years" {
    const short = try parseBirthDate("8/17/88", 2026);
    var short_iso: [10]u8 = undefined;
    try std.testing.expectEqualStrings("1988-08-17", short.writeIso(&short_iso));

    const full = try parseBirthDate("08/17/1988", 2026);
    var full_iso: [10]u8 = undefined;
    try std.testing.expectEqualStrings("1988-08-17", full.writeIso(&full_iso));

    const iso = try parseBirthDate("1988-08-17", 2026);
    try std.testing.expect(iso.eql(full));

    const current_century = try parseBirthDate("1/1/26", 2026);
    var current_century_iso: [10]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2026-01-01",
        current_century.writeIso(&current_century_iso),
    );

    const compact_short = try parseBirthDate("81788", 2026);
    var compact_short_iso: [10]u8 = undefined;
    try std.testing.expectEqualStrings(
        "1988-08-17",
        compact_short.writeIso(&compact_short_iso),
    );

    const compact_full = try parseBirthDate("08171988", 2026);
    var compact_full_iso: [10]u8 = undefined;
    try std.testing.expectEqualStrings(
        "1988-08-17",
        compact_full.writeIso(&compact_full_iso),
    );

    const compact_padded_short = try parseBirthDate("081788", 2026);
    var compact_padded_short_iso: [10]u8 = undefined;
    try std.testing.expectEqualStrings(
        "1988-08-17",
        compact_padded_short.writeIso(&compact_padded_short_iso),
    );

    const compact_unpadded_full = try parseBirthDate("8171988", 2026);
    var compact_unpadded_full_iso: [10]u8 = undefined;
    try std.testing.expectEqualStrings(
        "1988-08-17",
        compact_unpadded_full.writeIso(&compact_unpadded_full_iso),
    );

    try std.testing.expectError(
        error.InvalidBirthDate,
        parseBirthDate("2/29/2025", 2026),
    );
    try std.testing.expectError(
        error.InvalidBirthDate,
        parseBirthDate("8/17/8", 2026),
    );
    try std.testing.expectError(
        error.InvalidBirthDate,
        parseBirthDate("1/1/0000", 2026),
    );
}

test "tagged reusable values retain semantic types" {
    const value: Value = .{ .atc = try Atc.parse("PT 010") };
    try std.testing.expectEqual(ReusableField.atc, value.field());
    try std.testing.expectEqualStrings("PT010", value.atc.asSlice());
}
