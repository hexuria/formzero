//! HTA-local Item 1 year and Item 2 quarter gates for BIR Form 1601EQ
//! January 2018 ENCS.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601EQ.hta`
//! - SHA-256:
//!   `cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96`
//! - `var dt = new Date()` line 3140 (script-load snapshot, not per call)
//! - `validateForm` year gate lines 3143-3159
//! - `validateForm` quarter gate lines 3161-3209
//!
//! Clock is injected. `Date.getMonth()` is 0-based: April is 3, July is 6,
//! October is 9. Fourth quarter of the clock year is never accepted — HTA
//! has no month check for Q4. Remaining `validateForm` rules (Items 4, 6-12,
//! Part II ATC) are not implemented. `ready` stays false.

const std = @import("std");
const evidence = @import("evidence.zig");

pub const ready = false;
pub const year_quarter_ready = true;

pub const alert_year_required = "Please enter a valid year on Item 1.";
pub const alert_year_future = "Invalid entry on Item 1. Entry should not be a future Date.";
pub const alert_year_before_2018 = "Invalid entry on Item 1. Entry should not be a previous year from 2018.";
pub const alert_quarter_required = "Please select Quarter on Item 2";
pub const alert_quarter_1 = "Unable to select first Quarter due to the current date. Payment should be made after the Quarter";
pub const alert_quarter_2 = "Unable to select second Quarter due to the current date. Payment should be made after the Quarter";
pub const alert_quarter_3 = "Unable to select third Quarter due to the current date. Payment should be made after the Quarter";
pub const alert_quarter_4 = "Unable to select fourth Quarter due to the current date. Payment should be made after the Quarter";

/// 0-based month from HTA `Date.getMonth()`.
pub const JsMonth = enum(u4) {
    january = 0,
    february = 1,
    march = 2,
    april = 3,
    may = 4,
    june = 5,
    july = 6,
    august = 7,
    september = 8,
    october = 9,
    november = 10,
    december = 11,
};

/// Script-load `dt` from HTA line 3140.
pub const Clock = struct {
    year: i32,
    month: JsMonth,
};

pub const Year = union(enum) {
    empty,
    value: i32,
};

pub const Quarter = enum(u3) {
    none,
    q1,
    q2,
    q3,
    q4,
};

pub const Outcome = struct {
    accepted: bool,
    year: Year,
    quarter: Quarter,
    alert: ?[]const u8,
    focus_year: bool,
};

fn accept(year: Year, quarter: Quarter) Outcome {
    return .{
        .accepted = true,
        .year = year,
        .quarter = quarter,
        .alert = null,
        .focus_year = false,
    };
}

fn rejectYear(year: Year, quarter: Quarter, alert: []const u8) Outcome {
    return .{
        .accepted = false,
        .year = year,
        .quarter = quarter,
        .alert = alert,
        .focus_year = true,
    };
}

fn rejectQuarter(year: Year, alert: []const u8) Outcome {
    return .{
        .accepted = false,
        .year = year,
        .quarter = .none,
        .alert = alert,
        .focus_year = false,
    };
}

fn currentYearQuarterOpen(quarter: Quarter, month: JsMonth) bool {
    const month_index = @intFromEnum(month);
    return switch (quarter) {
        .none => false,
        .q1 => month_index >= 3,
        .q2 => month_index >= 6,
        .q3 => month_index >= 9,
        // HTA Q4 current-year branch has no month check; it always fails.
        .q4 => false,
    };
}

fn quarterClosedAlert(quarter: Quarter) []const u8 {
    return switch (quarter) {
        .none => alert_quarter_required,
        .q1 => alert_quarter_1,
        .q2 => alert_quarter_2,
        .q3 => alert_quarter_3,
        .q4 => alert_quarter_4,
    };
}

/// Year then quarter, in `validateForm` order. Does not run later rules.
pub fn validateYearAndQuarter(year: Year, quarter: Quarter, clock: Clock) Outcome {
    const entered = switch (year) {
        .empty => return rejectYear(.empty, quarter, alert_year_required),
        .value => |value| value,
    };
    if (entered > clock.year) {
        return rejectYear(.{ .value = clock.year }, quarter, alert_year_future);
    }
    if (entered < 2018) {
        return rejectYear(.empty, quarter, alert_year_before_2018);
    }

    const accepted_year: Year = .{ .value = entered };
    if (quarter == .none) {
        return .{
            .accepted = false,
            .year = accepted_year,
            .quarter = .none,
            .alert = alert_quarter_required,
            .focus_year = false,
        };
    }

    const prior_year = entered < clock.year;
    if (prior_year or currentYearQuarterOpen(quarter, clock.month)) {
        return accept(accepted_year, quarter);
    }
    return rejectQuarter(accepted_year, quarterClosedAlert(quarter));
}

const april_2026: Clock = .{ .year = 2026, .month = .april };
const december_2026: Clock = .{ .year = 2026, .month = .december };

test "1601EQ year and quarter gates stay unreconciled and skip the rest of validateForm" {
    try std.testing.expect(year_quarter_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!evidence.readiness.identityReady());
    try std.testing.expect(!evidence.readiness.dependency_closure);
}

test "1601EQ empty year fails and keeps the quarter" {
    const result = validateYearAndQuarter(.empty, .q1, april_2026);
    try std.testing.expect(!result.accepted);
    try std.testing.expect(result.year == .empty);
    try std.testing.expectEqual(Quarter.q1, result.quarter);
    try std.testing.expectEqualStrings(alert_year_required, result.alert.?);
    try std.testing.expect(result.focus_year);
}

test "1601EQ future year rewrites to the clock year" {
    const result = validateYearAndQuarter(.{ .value = 2027 }, .q2, april_2026);
    try std.testing.expect(!result.accepted);
    try std.testing.expectEqual(Year{ .value = 2026 }, result.year);
    try std.testing.expectEqual(Quarter.q2, result.quarter);
    try std.testing.expectEqualStrings(alert_year_future, result.alert.?);
    try std.testing.expect(result.focus_year);
}

test "1601EQ year before 2018 clears the year" {
    const result = validateYearAndQuarter(.{ .value = 2017 }, .q4, april_2026);
    try std.testing.expect(!result.accepted);
    try std.testing.expect(result.year == .empty);
    try std.testing.expectEqual(Quarter.q4, result.quarter);
    try std.testing.expectEqualStrings(alert_year_before_2018, result.alert.?);
    try std.testing.expect(result.focus_year);
}

test "1601EQ current-year quarters open only after the HTA month thresholds" {
    const year: Year = .{ .value = 2026 };
    try std.testing.expect(validateYearAndQuarter(year, .q1, april_2026).accepted);
    try std.testing.expect(!validateYearAndQuarter(year, .q1, .{ .year = 2026, .month = .march }).accepted);

    try std.testing.expect(validateYearAndQuarter(year, .q2, .{ .year = 2026, .month = .july }).accepted);
    const june_q2 = validateYearAndQuarter(year, .q2, .{ .year = 2026, .month = .june });
    try std.testing.expect(!june_q2.accepted);
    try std.testing.expectEqual(Quarter.none, june_q2.quarter);
    try std.testing.expectEqualStrings(alert_quarter_2, june_q2.alert.?);

    try std.testing.expect(validateYearAndQuarter(year, .q3, .{ .year = 2026, .month = .october }).accepted);
    try std.testing.expect(!validateYearAndQuarter(year, .q3, .{ .year = 2026, .month = .september }).accepted);
}

test "1601EQ current-year Q4 is never open even in December" {
    const result = validateYearAndQuarter(.{ .value = 2026 }, .q4, december_2026);
    try std.testing.expect(!result.accepted);
    try std.testing.expectEqual(Year{ .value = 2026 }, result.year);
    try std.testing.expectEqual(Quarter.none, result.quarter);
    try std.testing.expectEqualStrings(alert_quarter_4, result.alert.?);
    try std.testing.expect(!result.focus_year);
}

test "1601EQ prior-year Q4 is accepted and a missing quarter is not" {
    const prior = validateYearAndQuarter(.{ .value = 2025 }, .q4, april_2026);
    try std.testing.expect(prior.accepted);
    try std.testing.expectEqual(Quarter.q4, prior.quarter);
    try std.testing.expect(prior.alert == null);

    const missing = validateYearAndQuarter(.{ .value = 2018 }, .none, april_2026);
    try std.testing.expect(!missing.accepted);
    try std.testing.expectEqual(Year{ .value = 2018 }, missing.year);
    try std.testing.expectEqual(Quarter.none, missing.quarter);
    try std.testing.expectEqualStrings(alert_quarter_required, missing.alert.?);
    try std.testing.expect(!missing.focus_year);
}
