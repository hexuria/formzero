//! Typed filing-period identity shared by the Tax Form Library and editors.
//!
//! A calendar date is not enough to identify a filing.  The same form can
//! have twelve monthly, four quarterly, one annual, or multiple on-demand
//! occurrences in a tax year.  This value object keeps that distinction
//! explicit while the legacy recurring-draft adapter continues to support its
//! existing quarterly keys.

const std = @import("std");
const catalog = @import("generated/catalog.zig");

pub const Error = error{InvalidYear, InvalidMonth, InvalidQuarter, InvalidOccurrence};
pub const key_capacity: usize = 16;

pub const FilingPeriod = union(enum) {
    monthly: struct { tax_year: u16, month: u8 },
    quarterly: struct { tax_year: u16, quarter: u8 },
    annual: struct { tax_year: u16 },
    on_demand: struct { tax_year: u16, occurrence: u32 },

    pub fn taxYear(self: FilingPeriod) u16 {
        return switch (self) {
            .monthly => |value| value.tax_year,
            .quarterly => |value| value.tax_year,
            .annual => |value| value.tax_year,
            .on_demand => |value| value.tax_year,
        };
    }

    pub fn cadence(self: FilingPeriod) catalog.FilingCadence {
        return switch (self) {
            .monthly => .monthly,
            .quarterly => .quarterly,
            .annual => .annual,
            .on_demand => .on_demand,
        };
    }

    pub fn month(self: FilingPeriod) ?u8 {
        return switch (self) {
            .monthly => |value| value.month,
            else => null,
        };
    }

    pub fn quarter(self: FilingPeriod) ?u8 {
        return switch (self) {
            .quarterly => |value| if (value.quarter >= 1 and value.quarter <= 4)
                value.quarter
            else
                null,
            .monthly => |value| if (value.month >= 1 and value.month <= 12)
                @intCast((value.month - 1) / 3 + 1)
            else
                null,
            else => null,
        };
    }

    pub fn validate(self: FilingPeriod) Error!void {
        if (self.taxYear() == 0 or self.taxYear() > 9999) {
            return error.InvalidYear;
        }
        switch (self) {
            .monthly => |value| if (value.month < 1 or value.month > 12)
                return error.InvalidMonth,
            .quarterly => |value| if (value.quarter < 1 or value.quarter > 4)
                return error.InvalidQuarter,
            .annual => {},
            .on_demand => |value| if (value.occurrence == 0)
                return error.InvalidOccurrence,
        }
    }

    /// Canonical key used by new period-aware projections.  Existing
    /// quarterly drafts already use the compatible `YYYY-QN` form.
    pub fn key(self: FilingPeriod, output: []u8) Error![]const u8 {
        try self.validate();
        return switch (self) {
            .monthly => |value| std.fmt.bufPrint(
                output,
                "{d:0>4}-M{d:0>2}",
                .{ value.tax_year, value.month },
            ) catch return error.InvalidMonth,
            .quarterly => |value| std.fmt.bufPrint(
                output,
                "{d:0>4}-Q{d}",
                .{ value.tax_year, value.quarter },
            ) catch return error.InvalidQuarter,
            .annual => |value| std.fmt.bufPrint(
                output,
                "{d:0>4}-A",
                .{value.tax_year},
            ) catch return error.InvalidYear,
            .on_demand => |value| std.fmt.bufPrint(
                output,
                "{d:0>4}-O{d:0>3}",
                .{ value.tax_year, value.occurrence },
            ) catch return error.InvalidOccurrence,
        };
    }

    pub fn label(self: FilingPeriod, output: []u8) Error![]const u8 {
        try self.validate();
        return switch (self) {
            .monthly => |value| std.fmt.bufPrint(
                output,
                "{d} {s}",
                .{ value.tax_year, monthName(value.month) },
            ) catch return error.InvalidMonth,
            .quarterly => |value| std.fmt.bufPrint(
                output,
                "{d} Q{d}",
                .{ value.tax_year, value.quarter },
            ) catch return error.InvalidQuarter,
            .annual => |value| std.fmt.bufPrint(
                output,
                "{d} Annual",
                .{value.tax_year},
            ) catch return error.InvalidYear,
            .on_demand => |value| std.fmt.bufPrint(
                output,
                "{d} On-demand #{d}",
                .{ value.tax_year, value.occurrence },
            ) catch return error.InvalidOccurrence,
        };
    }

    pub fn matchesCadence(self: FilingPeriod, value: catalog.FilingCadence) bool {
        return self.cadence() == value;
    }

    pub fn eql(self: FilingPeriod, other: FilingPeriod) bool {
        return switch (self) {
            .monthly => |left| switch (other) {
                .monthly => |right| left.tax_year == right.tax_year and
                    left.month == right.month,
                else => false,
            },
            .quarterly => |left| switch (other) {
                .quarterly => |right| left.tax_year == right.tax_year and
                    left.quarter == right.quarter,
                else => false,
            },
            .annual => |left| switch (other) {
                .annual => |right| left.tax_year == right.tax_year,
                else => false,
            },
            .on_demand => |left| switch (other) {
                .on_demand => |right| left.tax_year == right.tax_year and
                    left.occurrence == right.occurrence,
                else => false,
            },
        };
    }

    pub fn parseKey(
        form_cadence: catalog.FilingCadence,
        text: []const u8,
    ) Error!FilingPeriod {
        if (text.len < 6 or text[4] != '-') return error.InvalidYear;
        const tax_year = std.fmt.parseInt(u16, text[0..4], 10) catch
            return error.InvalidYear;
        const period = switch (form_cadence) {
            .monthly => blk: {
                if (text.len != 8 or text[5] != 'M') return error.InvalidMonth;
                const parsed_month = std.fmt.parseInt(u8, text[6..8], 10) catch
                    return error.InvalidMonth;
                break :blk FilingPeriod{ .monthly = .{
                    .tax_year = tax_year,
                    .month = parsed_month,
                } };
            },
            .quarterly => blk: {
                if (text.len != 7 or text[5] != 'Q') return error.InvalidQuarter;
                const parsed_quarter = std.fmt.parseInt(u8, text[6..7], 10) catch
                    return error.InvalidQuarter;
                break :blk FilingPeriod{ .quarterly = .{
                    .tax_year = tax_year,
                    .quarter = parsed_quarter,
                } };
            },
            .annual => blk: {
                if (text.len != 6 or text[5] != 'A') return error.InvalidYear;
                break :blk FilingPeriod{ .annual = .{ .tax_year = tax_year } };
            },
            .on_demand => blk: {
                if (text.len != 9 or text[5] != 'O') return error.InvalidOccurrence;
                const occurrence = std.fmt.parseInt(u32, text[6..9], 10) catch
                    return error.InvalidOccurrence;
                break :blk FilingPeriod{ .on_demand = .{
                    .tax_year = tax_year,
                    .occurrence = occurrence,
                } };
            },
        };
        try period.validate();
        return period;
    }
};

pub fn monthName(month: u8) []const u8 {
    return switch (month) {
        1 => "January",
        2 => "February",
        3 => "March",
        4 => "April",
        5 => "May",
        6 => "June",
        7 => "July",
        8 => "August",
        9 => "September",
        10 => "October",
        11 => "November",
        12 => "December",
        else => "Unknown month",
    };
}

pub fn periodFromCadence(
    cadence: catalog.FilingCadence,
    tax_year: u16,
    slot: u8,
) FilingPeriod {
    return switch (cadence) {
        .monthly => .{ .monthly = .{ .tax_year = tax_year, .month = slot } },
        .quarterly => .{ .quarterly = .{ .tax_year = tax_year, .quarter = slot } },
        .annual => .{ .annual = .{ .tax_year = tax_year } },
        .on_demand => .{ .on_demand = .{ .tax_year = tax_year, .occurrence = @max(@as(u32, 1), slot) } },
    };
}

test "filing period keys and labels are canonical" {
    var buffer: [32]u8 = undefined;
    const monthly: FilingPeriod = .{ .monthly = .{ .tax_year = 2026, .month = 1 } };
    try std.testing.expectEqualStrings("2026-M01", try monthly.key(&buffer));
    try std.testing.expectEqualStrings("2026 January", try monthly.label(&buffer));

    const quarterly: FilingPeriod = .{ .quarterly = .{ .tax_year = 2026, .quarter = 3 } };
    try std.testing.expectEqualStrings("2026-Q3", try quarterly.key(&buffer));

    const annual: FilingPeriod = .{ .annual = .{ .tax_year = 2026 } };
    try std.testing.expectEqualStrings("2026-A", try annual.key(&buffer));

    const on_demand: FilingPeriod = .{ .on_demand = .{ .tax_year = 2026, .occurrence = 2 } };
    try std.testing.expectEqualStrings("2026-O002", try on_demand.key(&buffer));
}

test "monthly periods derive their containing quarter" {
    const period: FilingPeriod = .{ .monthly = .{ .tax_year = 2026, .month = 12 } };
    try std.testing.expectEqual(@as(?u8, 4), period.quarter());
}

test "period keys round trip by cadence" {
    var buffer: [key_capacity]u8 = undefined;
    const values = [_]FilingPeriod{
        .{ .monthly = .{ .tax_year = 2026, .month = 12 } },
        .{ .quarterly = .{ .tax_year = 2026, .quarter = 2 } },
        .{ .annual = .{ .tax_year = 2026 } },
        .{ .on_demand = .{ .tax_year = 2026, .occurrence = 7 } },
    };
    for (values) |value| {
        const key = try value.key(&buffer);
        const parsed = try FilingPeriod.parseKey(value.cadence(), key);
        try std.testing.expect(value.eql(parsed));
    }
}
