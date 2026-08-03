//! Civil month and quarter display names.
//!
//! Separate from `date.zig`, which owns arithmetic: these are presentation
//! strings and carry no calendar semantics.

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
