//! Session-owned state for the Global Dashboard.
//!
//! The dashboard consumes the same globally resolved calendar rules and
//! SQLite overrides as the rest of the application, but its viewed period,
//! day focus, and form filter are deliberately independent of every taxpayer
//! profile. Form option metadata stays caller-owned; this module only owns a
//! bounded selection set keyed by the caller's stable option indices.
//!
//! The one taxpayer-shaped input the dashboard accepts is an optional RDO
//! context. Without it the page is the honest nationwide schedule, which is
//! what it exists to be; with it the caller re-projects the same loaded
//! policy through one district so RDO-scoped overrides become visible. This
//! module holds the context only for the running session. A caller that
//! carries one across launches owns two obligations with it: the code must
//! still name a district in the caller's canonical reference, and the caption
//! must be restored alongside the projection, or a later reader would mistake
//! a district view for the nationwide schedule.

const std = @import("std");

pub const calendar_ui = @import("../calendar/ui_state.zig");
const multi_select = @import("../components/multi_select.zig");

pub const domain = calendar_ui.domain;
pub const FormSelectionChange = multi_select.SelectionChange;

/// Canonical Revenue District Office codes are three characters ("039",
/// "17A"). Eight bytes absorbs a revised code without letting session state
/// grow with the caller's input.
pub const max_rdo_code_bytes = 8;

pub const RdoContextError = error{
    EmptyRdoCode,
    RdoCodeTooLong,
};

/// A bounded copy of the caller's canonical RDO code. The dashboard stores
/// the code rather than a reference row so this module stays independent of
/// the RDO catalog that feeds the picker.
pub const RdoContext = struct {
    storage: [max_rdo_code_bytes]u8 = undefined,
    len: usize = 0,

    pub fn code(self: *const RdoContext) []const u8 {
        return self.storage[0..self.len];
    }
};

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

        /// `null` is the nationwide projection: the dashboard's default and
        /// the only view that is a complete national schedule.
        rdo_context: ?RdoContext = null,

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

        /// Returns to an absolute month directly, clearing a day selection
        /// left over from the period being abandoned.
        pub fn jumpToMonth(self: *Self, year: i32, month: u8) void {
            const previous_year = self.calendar.selected_year;
            const previous_month = self.calendar.selected_month;
            self.calendar.jumpToMonth(year, month);
            self.clearDayWhenPeriodChanged(previous_year, previous_month);
        }

        /// The canonical code of the active RDO context, or `null` while the
        /// dashboard shows the nationwide schedule.
        pub fn rdoContext(self: *const Self) ?[]const u8 {
            if (self.rdo_context) |*context| return context.code();
            return null;
        }

        pub fn hasRdoContext(self: *const Self) bool {
            return self.rdo_context != null;
        }

        /// Adopts a session RDO context and reports whether the projection
        /// the caller must recompute actually changed. Validating the code
        /// against an RDO catalog stays with the caller that owns the picker;
        /// this refuses only what it cannot store, and a blank code, which
        /// would silently read as the nationwide view.
        pub fn setRdoContext(
            self: *Self,
            code: []const u8,
        ) RdoContextError!bool {
            const candidate = std.mem.trim(u8, code, " \t\r\n");
            if (candidate.len == 0) return RdoContextError.EmptyRdoCode;
            if (candidate.len > max_rdo_code_bytes) {
                return RdoContextError.RdoCodeTooLong;
            }
            if (self.rdoContext()) |active| {
                if (std.mem.eql(u8, active, candidate)) return false;
            }
            var context = RdoContext{};
            @memcpy(context.storage[0..candidate.len], candidate);
            context.len = candidate.len;
            self.rdo_context = context;
            return true;
        }

        /// Restores the nationwide projection.
        pub fn clearRdoContext(self: *Self) bool {
            const changed = self.rdo_context != null;
            self.rdo_context = null;
            return changed;
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

test "jumpToMonth abandons the old period's selected day" {
    const TestState = State(2, 16);
    var state = TestState{};
    state.calendar.selected_year = 2026;
    state.calendar.selected_month = 6;

    try std.testing.expect(state.toggleDay(30));
    state.jumpToMonth(2026, 11);
    try std.testing.expectEqual(@as(u8, 11), state.calendar.selected_month);
    try std.testing.expect(state.selectedDay() == null);

    // Jumping back to the same period is a no-op that keeps the selection.
    try std.testing.expect(state.toggleDay(5));
    state.jumpToMonth(2026, 11);
    try std.testing.expectEqual(@as(?u8, 5), state.selectedDay());
}

test "the dashboard starts nationwide and adopts one session RDO context" {
    const TestState = State(2, 16);
    var state = TestState{};

    try std.testing.expect(!state.hasRdoContext());
    try std.testing.expect(state.rdoContext() == null);
    try std.testing.expect(!state.clearRdoContext());

    try std.testing.expect(try state.setRdoContext("039"));
    try std.testing.expect(state.hasRdoContext());
    try std.testing.expectEqualStrings("039", state.rdoContext().?);

    // Re-selecting the active district must not ask the caller to reproject.
    try std.testing.expect(!try state.setRdoContext("  039  "));
    try std.testing.expect(try state.setRdoContext("17A"));
    try std.testing.expectEqualStrings("17A", state.rdoContext().?);

    try std.testing.expect(state.clearRdoContext());
    try std.testing.expect(state.rdoContext() == null);
}

test "an unusable RDO context code is refused instead of reading as nationwide" {
    const TestState = State(2, 16);
    var state = TestState{};

    try std.testing.expectError(
        error.EmptyRdoCode,
        state.setRdoContext("   "),
    );
    try std.testing.expectError(
        error.RdoCodeTooLong,
        state.setRdoContext("0" ** (max_rdo_code_bytes + 1)),
    );
    try std.testing.expect(!state.hasRdoContext());
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
