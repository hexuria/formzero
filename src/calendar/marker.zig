//! Deadline marker glyphs and urgency tones for calendar surfaces.
//!
//! The global dashboard and the taxpayer dashboard must agree on what a day
//! looks like, so both read these rather than deriving their own thresholds.

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
