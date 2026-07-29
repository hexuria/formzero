//! Small, allocation-free civil date used by tax-profile effective periods.
//!
//! Construction is deliberately fallible. Domain code can therefore accept a
//! `Date` without repeating calendar validation at every call site.

const std = @import("std");

pub const Error = error{
    InvalidYear,
    InvalidMonth,
    InvalidDay,
    InvalidIsoDate,
};

pub const Order = enum {
    before,
    equal,
    after,
};

pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn init(year: u16, month: u8, day: u8) Error!Date {
        if (year == 0) return error.InvalidYear;
        if (month < 1 or month > 12) return error.InvalidMonth;
        if (day < 1 or day > daysInMonth(year, month)) return error.InvalidDay;
        return .{ .year = year, .month = month, .day = day };
    }

    pub fn parseIso(raw: []const u8) Error!Date {
        if (raw.len != 10 or raw[4] != '-' or raw[7] != '-') {
            return error.InvalidIsoDate;
        }
        const year = std.fmt.parseInt(u16, raw[0..4], 10) catch
            return error.InvalidIsoDate;
        const month = std.fmt.parseInt(u8, raw[5..7], 10) catch
            return error.InvalidIsoDate;
        const day = std.fmt.parseInt(u8, raw[8..10], 10) catch
            return error.InvalidIsoDate;
        return init(year, month, day) catch return error.InvalidIsoDate;
    }

    pub fn writeIso(self: Date, buffer: *[10]u8) []const u8 {
        _ = std.fmt.bufPrint(
            buffer,
            "{d:0>4}-{d:0>2}-{d:0>2}",
            .{ self.year, self.month, self.day },
        ) catch unreachable;
        return buffer;
    }

    pub fn order(self: Date, other: Date) Order {
        const lhs = self.sortKey();
        const rhs = other.sortKey();
        if (lhs < rhs) return .before;
        if (lhs > rhs) return .after;
        return .equal;
    }

    pub fn isBefore(self: Date, other: Date) bool {
        return self.order(other) == .before;
    }

    pub fn isAfter(self: Date, other: Date) bool {
        return self.order(other) == .after;
    }

    pub fn eql(self: Date, other: Date) bool {
        return self.order(other) == .equal;
    }

    fn sortKey(self: Date) u32 {
        return @as(u32, self.year) * 10_000 +
            @as(u32, self.month) * 100 +
            @as(u32, self.day);
    }
};

pub const EffectivePeriod = struct {
    /// Inclusive first day.
    from: Date,
    /// Inclusive final day. `null` means the period remains open.
    until: ?Date = null,

    pub fn init(from: Date, until: ?Date) error{InvalidRange}!EffectivePeriod {
        if (until) |last| {
            if (last.isBefore(from)) return error.InvalidRange;
        }
        return .{ .from = from, .until = until };
    }

    pub fn contains(self: EffectivePeriod, date: Date) bool {
        if (date.isBefore(self.from)) return false;
        if (self.until) |last| return !date.isAfter(last);
        return true;
    }

    pub fn overlaps(self: EffectivePeriod, other: EffectivePeriod) bool {
        if (self.until) |last| {
            if (last.isBefore(other.from)) return false;
        }
        if (other.until) |last| {
            if (last.isBefore(self.from)) return false;
        }
        return true;
    }
};

fn isLeapYear(year: u16) bool {
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
}

fn daysInMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

test "date parses, formats, and rejects impossible dates" {
    const leap = try Date.parseIso("2024-02-29");
    var buffer: [10]u8 = undefined;
    try std.testing.expectEqualStrings("2024-02-29", leap.writeIso(&buffer));
    try std.testing.expectError(error.InvalidIsoDate, Date.parseIso("2026-02-29"));
    try std.testing.expectError(error.InvalidIsoDate, Date.parseIso("2026-2-01"));
}

test "effective periods are inclusive and reject reversed bounds" {
    const first = try Date.init(2026, 1, 1);
    const last = try Date.init(2026, 6, 30);
    const period = try EffectivePeriod.init(first, last);

    try std.testing.expect(period.contains(first));
    try std.testing.expect(period.contains(last));
    try std.testing.expect(!period.contains(try Date.init(2026, 7, 1)));
    try std.testing.expectError(
        error.InvalidRange,
        EffectivePeriod.init(last, first),
    );
}

test "effective period overlap includes a shared boundary day" {
    const left = try EffectivePeriod.init(
        try Date.init(2026, 1, 1),
        try Date.init(2026, 3, 31),
    );
    const touching = try EffectivePeriod.init(
        try Date.init(2026, 3, 31),
        try Date.init(2026, 6, 30),
    );
    const separate = try EffectivePeriod.init(
        try Date.init(2026, 4, 1),
        try Date.init(2026, 6, 30),
    );

    try std.testing.expect(left.overlaps(touching));
    try std.testing.expect(!left.overlaps(separate));
}
