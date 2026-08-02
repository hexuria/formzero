//! Reusable state core for bounded multi-select comboboxes.
//!
//! The view owns option labels and filtering presentation. This type owns the
//! interaction state that every multi-select needs: open/closed state, a
//! mirrored query buffer, and an indexed selection set. Keeping those
//! concerns separate lets callers derive downstream content directly from
//! the selection without coupling the component to a dashboard or form type.

const std = @import("std");
const native_sdk = @import("native_sdk");

const canvas = native_sdk.canvas;

/// Describes the result of setting or toggling one option.
pub const SelectionChange = struct {
    index: usize,
    selected: bool,
    selected_count: usize,
    changed: bool,
};

/// Creates a fixed-capacity multi-select state type.
///
/// Option identity is the stable index supplied by the caller. Labels and
/// other option metadata remain caller-owned, so the same state can back
/// forms, taxpayer profiles, categories, or any other bounded option set.
pub fn State(comptime option_count: usize, comptime query_capacity: usize) type {
    if (option_count == 0) @compileError("multi-select state needs at least one option");
    if (query_capacity == 0) @compileError("multi-select query capacity must be positive");

    return struct {
        const Self = @This();

        open: bool = false,
        selected: [option_count]bool = [_]bool{false} ** option_count,
        query_buffer: canvas.TextBuffer(query_capacity) = .{},

        /// Creates a state with every option selected.
        pub fn allSelected() Self {
            var state = Self{};
            _ = state.setAll(true);
            return state;
        }

        pub fn isOpen(self: *const Self) bool {
            return self.open;
        }

        /// Opens the picker with a fresh search query.
        pub fn openPicker(self: *Self) void {
            self.open = true;
            self.query_buffer.clear();
        }

        /// Closes the picker and restores its summary face.
        pub fn closePicker(self: *Self) void {
            self.open = false;
            self.query_buffer.clear();
        }

        pub fn togglePicker(self: *Self) void {
            if (self.open) {
                self.closePicker();
            } else {
                self.openPicker();
            }
        }

        /// Mirrors one Native SDK text edit into the component query.
        ///
        /// A direct typing action may arrive before an explicit open action,
        /// so editing a closed picker opens it first.
        pub fn applyQuery(self: *Self, edit: canvas.TextInputEvent) void {
            if (!self.open) self.openPicker();
            self.query_buffer.apply(edit);
        }

        pub fn query(self: *const Self) []const u8 {
            return self.query_buffer.text();
        }

        pub fn matches(self: *const Self, candidate: []const u8) bool {
            return containsAsciiInsensitive(candidate, self.query());
        }

        pub fn isSelected(self: *const Self, index: usize) bool {
            return index < option_count and self.selected[index];
        }

        pub fn selectedCount(self: *const Self) usize {
            var count: usize = 0;
            for (self.selected) |selected| {
                if (selected) count += 1;
            }
            return count;
        }

        /// Sets one option and returns a selection snapshot.
        ///
        /// Invalid indices return `null` without mutating state.
        pub fn set(self: *Self, index: usize, selected: bool) ?SelectionChange {
            if (index >= option_count) return null;

            const changed = self.selected[index] != selected;
            self.selected[index] = selected;
            return .{
                .index = index,
                .selected = selected,
                .selected_count = self.selectedCount(),
                .changed = changed,
            };
        }

        pub fn toggle(self: *Self, index: usize) ?SelectionChange {
            if (index >= option_count) return null;
            return self.set(index, !self.selected[index]);
        }

        /// Sets every option and reports whether any value changed.
        pub fn setAll(self: *Self, selected: bool) bool {
            var changed = false;
            for (&self.selected) |*value| {
                changed = changed or value.* != selected;
                value.* = selected;
            }
            return changed;
        }

        pub fn clear(self: *Self) bool {
            return self.setAll(false);
        }

        /// Copies only authoritative selection values. Transient query/open
        /// state stays local to the receiving surface.
        pub fn copySelectionFrom(self: *Self, other: *const Self) void {
            self.selected = other.selected;
        }

        pub fn selectionEql(self: *const Self, other: *const Self) bool {
            return std.mem.eql(bool, &self.selected, &other.selected);
        }

        pub fn resetInteraction(self: *Self) void {
            self.closePicker();
        }
    };
}

/// ASCII case-insensitive substring matching for form codes and labels.
///
/// Non-ASCII bytes compare exactly. This keeps filtering allocation-free and
/// deterministic while still matching the application's current ASCII data.
pub fn containsAsciiInsensitive(candidate: []const u8, query: []const u8) bool {
    if (query.len == 0) return true;
    if (query.len > candidate.len) return false;

    var start: usize = 0;
    while (start + query.len <= candidate.len) : (start += 1) {
        var matches = true;
        for (query, 0..) |query_byte, offset| {
            const candidate_byte = candidate[start + offset];
            if (std.ascii.toLower(candidate_byte) != std.ascii.toLower(query_byte)) {
                matches = false;
                break;
            }
        }
        if (matches) return true;
    }
    return false;
}

test "all-selected state exposes stable selection change metadata" {
    const TestState = State(4, 16);
    var state = TestState.allSelected();

    try std.testing.expectEqual(@as(usize, 4), state.selectedCount());
    const change = state.toggle(1).?;
    try std.testing.expectEqual(@as(usize, 1), change.index);
    try std.testing.expect(!change.selected);
    try std.testing.expectEqual(@as(usize, 3), change.selected_count);
    try std.testing.expect(change.changed);
    try std.testing.expect(state.toggle(9) == null);
}

test "bulk selection and clearing report whether state changed" {
    const TestState = State(3, 16);
    var state = TestState{};

    try std.testing.expect(state.setAll(true));
    try std.testing.expectEqual(@as(usize, 3), state.selectedCount());
    try std.testing.expect(!state.setAll(true));
    try std.testing.expect(state.clear());
    try std.testing.expectEqual(@as(usize, 0), state.selectedCount());
    try std.testing.expect(!state.clear());
}

test "selection snapshots copy without leaking transient interaction" {
    const TestState = State(3, 16);
    var saved = TestState.allSelected();
    var staged = TestState{};
    staged.openPicker();
    staged.copySelectionFrom(&saved);
    try std.testing.expect(staged.selectionEql(&saved));
    try std.testing.expect(staged.isOpen());
    _ = saved.toggle(0);
    try std.testing.expect(!staged.selectionEql(&saved));
    staged.resetInteraction();
    try std.testing.expect(!staged.isOpen());
}

test "query lifecycle is mirrored and matches without allocation" {
    const TestState = State(2, 16);
    var state = TestState{};

    state.openPicker();
    state.applyQuery(.{ .insert_text = "qUaR" });
    try std.testing.expectEqualStrings("qUaR", state.query());
    try std.testing.expect(state.matches("2551 Quarterly Return"));
    try std.testing.expect(!state.matches("0619 Monthly Return"));

    state.closePicker();
    try std.testing.expect(!state.isOpen());
    try std.testing.expectEqualStrings("", state.query());
}
