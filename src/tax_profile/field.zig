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
pub const TaxType = BoundedText(.tax_type, 80);
pub const SpecialRateBasis = BoundedText(.special_rate_basis, 160);
pub const SourceReference = BoundedText(.source_reference, 160);

pub const GovernmentWithholdingAgent = enum {
    no,
    yes,
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
    InvalidLength,
};

pub const ContactNumber = struct {
    bytes: [16]u8 = undefined,
    len: u8 = 0,

    /// Stores an optional leading `+` followed by 7-15 digits.
    pub fn parse(raw: []const u8) ContactNumberError!ContactNumber {
        var result: ContactNumber = .{};
        for (raw) |byte| {
            if (std.ascii.isDigit(byte)) {
                if (result.len == result.bytes.len) {
                    return error.InvalidLength;
                }
                result.bytes[result.len] = byte;
                result.len += 1;
                continue;
            }
            if (byte == '+' and result.len == 0) {
                result.bytes[0] = '+';
                result.len = 1;
                continue;
            }
            if (byte == ' ' or byte == '-' or byte == '(' or byte == ')') {
                continue;
            }
            return error.InvalidCharacter;
        }
        const digit_count = result.len - @intFromBool(
            result.len > 0 and result.bytes[0] == '+',
        );
        if (digit_count < 7 or digit_count > 15) return error.InvalidLength;
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
        if (at == 0 or at + 1 == text.len) return error.InvalidEmailAddress;
        if (std.mem.indexOfScalarPos(u8, text, at + 1, '@') != null) {
            return error.InvalidEmailAddress;
        }
        const domain = text[at + 1 ..];
        if (std.mem.indexOfScalar(u8, domain, '.') == null) {
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
    line_of_business,
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
    line_of_business: LineOfBusiness,
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
            .line_of_business => |value| value.eql(&other.line_of_business),
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

test "tagged reusable values retain semantic types" {
    const value: Value = .{ .atc = try Atc.parse("PT 010") };
    try std.testing.expectEqual(ReusableField.atc, value.field());
    try std.testing.expectEqualStrings("PT010", value.atc.asSlice());
}
