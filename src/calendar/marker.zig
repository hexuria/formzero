//! Deadline marker glyphs and urgency tones for calendar surfaces.
//!
//! The global dashboard and the taxpayer dashboard must agree on what a day
//! looks like, so both read these rather than deriving their own thresholds.

const std = @import("std");
const domain = @import("domain.zig");

pub fn deadlineMarker(count: usize) []const u8 {
    return switch (count) {
        0 => "",
        1 => "•",
        2 => "••",
        3 => "•••",
        4 => "••••",
        else => "•••• +",
    };
}

pub const CalendarMarkerTone = enum {
    normal,
    approaching,
    due_soon,
    overdue,
    closed,
};

/// Calendar deadlines currently resolve to a civil date, not a clock time.
/// Treat today and tomorrow as the date-level approximation of "within 24
/// hours", then keep the inclusive seven-day window green.
pub fn calendarMarkerTone(
    deadline: domain.Date,
    today: domain.Date,
) CalendarMarkerTone {
    if (domain.Date.compare(deadline, today) == .lt) {
        return .overdue;
    }
    const due_soon_through = today.addDays(1) catch today;
    if (domain.Date.compare(deadline, due_soon_through) != .gt) {
        return .due_soon;
    }
    const approaching_through = today.addDays(7) catch due_soon_through;
    if (domain.Date.compare(deadline, approaching_through) != .gt) {
        return .approaching;
    }
    return .normal;
}

test "deadline marker glyphs saturate after four deadlines" {
    try std.testing.expectEqualStrings("", deadlineMarker(0));
    try std.testing.expectEqualStrings("•", deadlineMarker(1));
    try std.testing.expectEqualStrings("••", deadlineMarker(2));
    try std.testing.expectEqualStrings("•••", deadlineMarker(3));
    try std.testing.expectEqualStrings("••••", deadlineMarker(4));
    try std.testing.expectEqualStrings("•••• +", deadlineMarker(5));
    try std.testing.expectEqualStrings("•••• +", deadlineMarker(100));
}

test "marker tone crosses month and leap-year boundaries at civil-day distance" {
    // Jan 31 -> Feb 1 is tomorrow, so the deadline is due soon despite the
    // month change; Feb 7 is the inclusive seventh day and still approaching.
    const jan_end = try domain.Date.init(2026, 1, 31);
    try std.testing.expectEqual(
        CalendarMarkerTone.due_soon,
        calendarMarkerTone(try domain.Date.init(2026, 2, 1), jan_end),
    );
    try std.testing.expectEqual(
        CalendarMarkerTone.approaching,
        calendarMarkerTone(try domain.Date.init(2026, 2, 7), jan_end),
    );

    // A leap-day deadline keeps the inclusive +1 day window: the day after
    // is still due soon, and the day after that is approaching.
    const leap_day = try domain.Date.init(2024, 2, 29);
    try std.testing.expectEqual(
        CalendarMarkerTone.due_soon,
        calendarMarkerTone(try domain.Date.init(2024, 3, 1), leap_day),
    );
    try std.testing.expectEqual(
        CalendarMarkerTone.approaching,
        calendarMarkerTone(try domain.Date.init(2024, 3, 2), leap_day),
    );
}
