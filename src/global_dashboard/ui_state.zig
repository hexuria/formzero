//! Session-owned state for the Global Dashboard.
//!
//! The dashboard consumes the same globally resolved calendar rules and
//! SQLite overrides as the rest of the application, but its viewed period,
//! day focus, and form filter are deliberately independent of every taxpayer
//! profile. Form option metadata stays caller-owned; this module only owns a
//! bounded selection set keyed by the caller's stable option indices.

const std = @import("std");

pub const calendar_ui = @import("../calendar/ui_state.zig");
const multi_select = @import("../components/multi_select.zig");

pub const domain = calendar_ui.domain;
pub const FormSelectionChange = multi_select.SelectionChange;

/// Creates the Global Dashboard's bounded session-state type.
///
/// `form_option_count` comes from the caller's canonical form registry. This
/// keeps the module independent of `main.zig` and prevents the global filter
/// from becoming coupled to any taxpayer profile's Forms Set.
pub fn State(
    comptime form_option_count: usize,
    comptime form_query_capacity: usize,
) type {
    const FormSelectionState = multi_select.State(
        form_option_count,
        form_query_capacity,
    );

    return struct {
        const Self = @This();

        pub const Forms = FormSelectionState;
        pub const option_count = form_option_count;

        /// The dashboard owns its viewed calendar period. Calendar rules,
        /// overrides, and persistence remain authoritative in calendar_ui.
        calendar: calendar_ui.State = .{},

        /// Global Dashboard form filtering is session-only and starts with
        /// the complete caller-provided registry selected.
        forms: FormSelectionState = FormSelectionState.allSelected(),

        /// A full date avoids treating the same day number in another month
        /// as selected if a caller changes the viewed calendar directly.
        selected_date: ?domain.Date = null,

        pub fn selectedDate(self: *const Self) ?domain.Date {
            const selected = self.selected_date orelse return null;
            if (selected.year != self.calendar.selected_year or
                selected.month != self.calendar.selected_month)
            {
                return null;
            }
            return selected;
        }

        pub fn selectedDay(self: *const Self) ?u8 {
            return if (self.selectedDate()) |selected| selected.day else null;
        }

        pub fn isDaySelected(self: *const Self, day: u8) bool {
            return self.selectedDay() == day;
        }

        /// Selects a day in the viewed month, or clears it when pressed again.
        /// Invalid and out-of-month dates are ignored without disturbing the
        /// current selection.
        pub fn toggleDay(self: *Self, day: u8) bool {
            const date = domain.Date.init(
                self.calendar.selected_year,
                self.calendar.selected_month,
                day,
            ) catch return false;
            return self.toggleDate(date);
        }

        pub fn toggleDate(self: *Self, date: domain.Date) bool {
            if (date.year != self.calendar.selected_year or
                date.month != self.calendar.selected_month)
            {
                return false;
            }

            if (self.selectedDate()) |selected| {
                if (domain.Date.compare(selected, date) == .eq) {
                    self.selected_date = null;
                    return true;
                }
            }
            self.selected_date = date;
            return true;
        }

        pub fn clearSelectedDay(self: *Self) bool {
            const changed = self.selected_date != null;
            self.selected_date = null;
            return changed;
        }

        /// Clears a stale day after callers legitimately replace or attach
        /// the embedded calendar state without using the navigation wrappers.
        pub fn reconcileSelectedDay(self: *Self) bool {
            if (self.selected_date == null or self.selectedDate() != null) {
                return false;
            }
            self.selected_date = null;
            return true;
        }

        pub fn previousMonth(self: *Self) void {
            const year = self.calendar.selected_year;
            const month = self.calendar.selected_month;
            self.calendar.previousMonth();
            self.clearDayWhenPeriodChanged(year, month);
        }

        pub fn nextMonth(self: *Self) void {
            const year = self.calendar.selected_year;
            const month = self.calendar.selected_month;
            self.calendar.nextMonth();
            self.clearDayWhenPeriodChanged(year, month);
        }

        pub fn previousYear(self: *Self) void {
            const year = self.calendar.selected_year;
            const month = self.calendar.selected_month;
            self.calendar.previousYear();
            self.clearDayWhenPeriodChanged(year, month);
        }

        pub fn nextYear(self: *Self) void {
            const year = self.calendar.selected_year;
            const month = self.calendar.selected_month;
            self.calendar.nextYear();
            self.clearDayWhenPeriodChanged(year, month);
        }

        pub fn selectedFormCount(self: *const Self) usize {
            return self.forms.selectedCount();
        }

        pub fn hasSelectedForms(self: *const Self) bool {
            return self.selectedFormCount() != 0;
        }

        pub fn allFormsSelected(self: *const Self) bool {
            return self.selectedFormCount() == form_option_count;
        }

        pub fn formIsSelected(self: *const Self, index: usize) bool {
            return self.forms.isSelected(index);
        }

        pub fn setForm(
            self: *Self,
            index: usize,
            selected: bool,
        ) ?FormSelectionChange {
            return self.forms.set(index, selected);
        }

        pub fn toggleForm(self: *Self, index: usize) ?FormSelectionChange {
            return self.forms.toggle(index);
        }

        pub fn selectAllForms(self: *Self) bool {
            return self.forms.setAll(true);
        }

        pub fn clearAllForms(self: *Self) bool {
            return self.forms.clear();
        }

        fn clearDayWhenPeriodChanged(
            self: *Self,
            previous_year: i32,
            previous_month: u8,
        ) void {
            if (self.calendar.selected_year != previous_year or
                self.calendar.selected_month != previous_month)
            {
                _ = self.clearSelectedDay();
            }
        }
    };
}

test "selected day toggles within the viewed global calendar month" {
    const TestState = State(3, 16);
    var state = TestState{};
    state.calendar.selected_year = 2026;
    state.calendar.selected_month = 2;

    try std.testing.expect(state.toggleDay(14));
    try std.testing.expectEqual(@as(?u8, 14), state.selectedDay());
    try std.testing.expect(state.isDaySelected(14));

    try std.testing.expect(state.toggleDay(14));
    try std.testing.expect(state.selectedDay() == null);
    try std.testing.expect(!state.clearSelectedDay());

    try std.testing.expect(!state.toggleDay(0));
    try std.testing.expect(!state.toggleDay(29));
    try std.testing.expect(state.selectedDay() == null);
}

test "calendar navigation clears a selected day after a successful move" {
    const TestState = State(2, 16);
    var state = TestState{};
    state.calendar.selected_year = 2026;
    state.calendar.selected_month = 6;

    try std.testing.expect(state.toggleDay(30));
    state.nextMonth();

    try std.testing.expectEqual(@as(i32, 2026), state.calendar.selected_year);
    try std.testing.expectEqual(@as(u8, 7), state.calendar.selected_month);
    try std.testing.expect(state.selectedDay() == null);
}

test "global form selection defaults to all and supports empty then all" {
    const TestState = State(4, 16);
    var state = TestState{};

    try std.testing.expectEqual(@as(usize, 4), state.selectedFormCount());
    try std.testing.expect(state.hasSelectedForms());
    try std.testing.expect(state.allFormsSelected());
    for (0..TestState.option_count) |index| {
        try std.testing.expect(state.formIsSelected(index));
    }

    try std.testing.expect(state.clearAllForms());
    try std.testing.expectEqual(@as(usize, 0), state.selectedFormCount());
    try std.testing.expect(!state.hasSelectedForms());
    try std.testing.expect(!state.allFormsSelected());
    try std.testing.expect(!state.clearAllForms());

    try std.testing.expect(state.selectAllForms());
    try std.testing.expectEqual(@as(usize, 4), state.selectedFormCount());
    try std.testing.expect(state.allFormsSelected());
    try std.testing.expect(!state.selectAllForms());
}
