//! Civil month and quarter display names.
//!
//! Separate from `date.zig`, which owns arithmetic: these are presentation
//! strings and carry no calendar semantics.

const std = @import("std");

pub fn fullMonthName(month: u8) []const u8 {
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

pub fn shortMonthName(month: u8) []const u8 {
    return switch (month) {
        1 => "Jan",
        2 => "Feb",
        3 => "Mar",
        4 => "Apr",
        5 => "May",
        6 => "Jun",
        7 => "Jul",
        8 => "Aug",
        9 => "Sep",
        10 => "Oct",
        11 => "Nov",
        12 => "Dec",
        else => "",
    };
}

pub fn shortQuarterName(quarter: u8) []const u8 {
    return switch (quarter) {
        1 => "Q1",
        2 => "Q2",
        3 => "Q3",
        4 => "Q4",
        else => "",
    };
}

test "full month names cover the civil year in order" {
    const expected = [_][]const u8{
        "January",   "February", "March",    "April",
        "May",       "June",     "July",     "August",
        "September", "October",  "November", "December",
    };
    for (expected, 0..) |name, index| {
        try std.testing.expectEqualStrings(name, fullMonthName(@intCast(index + 1)));
    }
    try std.testing.expectEqualStrings("Unknown month", fullMonthName(0));
    try std.testing.expectEqualStrings("Unknown month", fullMonthName(13));
}

test "short month and quarter names stay bounded and empty out of range" {
    const expected = [_][]const u8{
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };
    for (expected, 0..) |name, index| {
        try std.testing.expectEqualStrings(name, shortMonthName(@intCast(index + 1)));
    }
    try std.testing.expectEqualStrings("", shortMonthName(0));
    try std.testing.expectEqualStrings("", shortMonthName(13));

    try std.testing.expectEqualStrings("Q1", shortQuarterName(1));
    try std.testing.expectEqualStrings("Q2", shortQuarterName(2));
    try std.testing.expectEqualStrings("Q3", shortQuarterName(3));
    try std.testing.expectEqualStrings("Q4", shortQuarterName(4));
    try std.testing.expectEqualStrings("", shortQuarterName(0));
    try std.testing.expectEqualStrings("", shortQuarterName(5));
}
