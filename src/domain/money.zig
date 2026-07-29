//! Signed Philippine-peso money stored as integer centavos.
//!
//! Negative amounts are required for adjustments and overpayments. Arithmetic
//! never saturates silently: callers must handle overflow explicitly.

const std = @import("std");

pub const Error = error{
    Empty,
    InvalidFormat,
    TooManyFractionDigits,
    Overflow,
    DivisionByZero,
};

pub const Money = struct {
    centavos: i64,

    pub const zero: Money = .{ .centavos = 0 };

    pub fn fromCentavos(centavos: i64) Money {
        return .{ .centavos = centavos };
    }

    pub fn parse(raw: []const u8) Error!Money {
        const text = std.mem.trim(u8, raw, " \t\r\n");
        if (text.len == 0) return error.Empty;

        var index: usize = 0;
        var negative = false;
        if (text[index] == '-' or text[index] == '+') {
            negative = text[index] == '-';
            index += 1;
            if (index == text.len) return error.InvalidFormat;
        }

        var whole: i64 = 0;
        var whole_digits: usize = 0;
        var digits_in_group: usize = 0;
        var saw_group_separator = false;
        while (index < text.len and text[index] != '.') : (index += 1) {
            const byte = text[index];
            if (byte == ',') {
                if (digits_in_group == 0) return error.InvalidFormat;
                if ((!saw_group_separator and digits_in_group > 3) or
                    (saw_group_separator and digits_in_group != 3))
                {
                    return error.InvalidFormat;
                }
                saw_group_separator = true;
                digits_in_group = 0;
                continue;
            }
            if (!std.ascii.isDigit(byte)) return error.InvalidFormat;
            whole = std.math.mul(i64, whole, 10) catch return error.Overflow;
            whole = std.math.add(i64, whole, byte - '0') catch
                return error.Overflow;
            whole_digits += 1;
            digits_in_group += 1;
        }
        if (whole_digits == 0) return error.InvalidFormat;
        if (saw_group_separator and digits_in_group != 3) {
            return error.InvalidFormat;
        }

        var fraction: i64 = 0;
        if (index < text.len) {
            index += 1;
            const remaining = text.len - index;
            if (remaining == 0 or remaining > 2) {
                return error.TooManyFractionDigits;
            }
            while (index < text.len) : (index += 1) {
                const byte = text[index];
                if (!std.ascii.isDigit(byte)) return error.InvalidFormat;
                fraction = fraction * 10 + (byte - '0');
            }
            if (remaining == 1) fraction *= 10;
        }

        var centavos = std.math.mul(i64, whole, 100) catch
            return error.Overflow;
        centavos = std.math.add(i64, centavos, fraction) catch
            return error.Overflow;
        if (negative) {
            centavos = std.math.negate(centavos) catch return error.Overflow;
        }
        return .{ .centavos = centavos };
    }

    pub fn checkedAdd(self: Money, other: Money) Error!Money {
        return .{
            .centavos = std.math.add(i64, self.centavos, other.centavos) catch
                return error.Overflow,
        };
    }

    pub fn checkedSub(self: Money, other: Money) Error!Money {
        return .{
            .centavos = std.math.sub(i64, self.centavos, other.centavos) catch
                return error.Overflow,
        };
    }

    /// Multiplies by a caller-supplied rational. No tax rate lives here.
    pub fn checkedRatio(
        self: Money,
        numerator: i64,
        denominator: i64,
    ) Error!Money {
        if (denominator == 0) return error.DivisionByZero;
        const product = std.math.mul(i64, self.centavos, numerator) catch
            return error.Overflow;
        if (product == std.math.minInt(i64) and denominator == -1) {
            return error.Overflow;
        }
        return .{ .centavos = @divTrunc(product, denominator) };
    }

    pub fn write(self: Money, buffer: []u8) error{NoSpaceLeft}![]const u8 {
        const negative = self.centavos < 0;
        const magnitude: u64 = if (self.centavos < 0)
            @as(u64, @intCast(-(self.centavos + 1))) + 1
        else
            @intCast(self.centavos);
        const whole = magnitude / 100;
        const fraction = magnitude % 100;
        return std.fmt.bufPrint(
            buffer,
            "{s}{d}.{d:0>2}",
            .{ if (negative) "-" else "", whole, fraction },
        );
    }
};

test "money parses pesos into signed centavos" {
    try std.testing.expectEqual(
        @as(i64, 123_456_78),
        (try Money.parse("123,456.78")).centavos,
    );
    try std.testing.expectEqual(
        @as(i64, -1_050),
        (try Money.parse("-10.5")).centavos,
    );
    try std.testing.expectError(
        error.TooManyFractionDigits,
        Money.parse("1.234"),
    );
    try std.testing.expectError(error.InvalidFormat, Money.parse("1,23.00"));
    try std.testing.expectError(error.InvalidFormat, Money.parse("12,,000"));
}

test "money arithmetic is checked and rates are supplied by policy" {
    const amount = Money.fromCentavos(45_000_000);
    const result = try amount.checkedRatio(3, 100);
    try std.testing.expectEqual(@as(i64, 1_350_000), result.centavos);
    try std.testing.expectError(
        error.Overflow,
        Money.fromCentavos(std.math.maxInt(i64)).checkedAdd(
            Money.fromCentavos(1),
        ),
    );
    try std.testing.expectError(
        error.Overflow,
        Money.fromCentavos(std.math.minInt(i64)).checkedRatio(1, -1),
    );
}

test "money formats with exactly two fractional digits" {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings(
        "-10.50",
        try Money.fromCentavos(-1_050).write(&buffer),
    );
}
