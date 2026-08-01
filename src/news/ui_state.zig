//! Allocation-free Important News request state.
//!
//! The state coalesces duplicate refresh presses and accepts a completion only
//! when its generation is still active. Cached notices stay visible while a
//! refresh is loading or after it fails.

const std = @import("std");
const domain = @import("domain.zig");

pub const max_error_bytes: usize = 256;

pub const Error = error{
    GenerationExhausted,
    TooManyNotices,
    ErrorMessageTooLong,
    InvalidUtf8,
};

pub const Phase = enum {
    idle,
    loading,
    loaded,
    empty,
    @"error",
};

pub const StartResult = union(enum) {
    started: u64,
    already_loading: u64,
};

pub const ApplyResult = enum {
    applied,
    stale,
};

pub const State = struct {
    phase: Phase = .idle,
    notice_count: usize = 0,
    request_generation: u64 = 0,
    active_request_generation: ?u64 = null,
    error_buffer: [max_error_bytes]u8 = undefined,
    error_length: usize = 0,

    /// Installs the cache result loaded synchronously during app startup.
    pub fn loadCached(self: *State, count: usize) Error!void {
        try validateCount(count);
        self.notice_count = count;
        self.active_request_generation = null;
        self.phase = if (count == 0) .empty else .loaded;
        self.clearError();
    }

    /// Starts one request. Repeated refresh presses share the active request.
    pub fn beginRefresh(self: *State) Error!StartResult {
        if (self.active_request_generation) |generation| {
            return .{ .already_loading = generation };
        }
        if (self.request_generation == std.math.maxInt(u64)) {
            return Error.GenerationExhausted;
        }
        self.request_generation += 1;
        self.active_request_generation = self.request_generation;
        self.phase = .loading;
        self.clearError();
        return .{ .started = self.request_generation };
    }

    pub fn applySuccess(
        self: *State,
        generation: u64,
        count: usize,
    ) Error!ApplyResult {
        if (self.active_request_generation == null or
            self.active_request_generation.? != generation)
        {
            return .stale;
        }
        try validateCount(count);

        self.active_request_generation = null;
        self.notice_count = count;
        self.phase = if (count == 0) .empty else .loaded;
        self.clearError();
        return .applied;
    }

    pub fn applyFailure(
        self: *State,
        generation: u64,
        message: []const u8,
    ) Error!ApplyResult {
        if (self.active_request_generation == null or
            self.active_request_generation.? != generation)
        {
            return .stale;
        }
        if (!std.unicode.utf8ValidateSlice(message)) return Error.InvalidUtf8;
        const normalized = std.mem.trim(u8, message, " \t\r\n");
        const visible_message = if (normalized.len == 0)
            "Unable to refresh important news."
        else
            normalized;
        if (visible_message.len > max_error_bytes) {
            return Error.ErrorMessageTooLong;
        }

        @memcpy(self.error_buffer[0..visible_message.len], visible_message);
        self.error_length = visible_message.len;
        self.active_request_generation = null;
        self.phase = .@"error";
        return .applied;
    }

    /// Invalidates an in-flight response, for example when the app is closing.
    pub fn cancelRefresh(self: *State) void {
        if (self.active_request_generation == null) return;
        self.active_request_generation = null;
        self.phase = if (self.notice_count == 0) .empty else .loaded;
    }

    pub fn dismissError(self: *State) void {
        if (self.phase != .@"error") return;
        self.clearError();
        self.phase = if (self.notice_count == 0) .empty else .loaded;
    }

    pub fn errorMessage(self: *const State) []const u8 {
        return self.error_buffer[0..self.error_length];
    }

    pub fn isRefreshing(self: *const State) bool {
        return self.active_request_generation != null;
    }

    pub fn hasCachedNotices(self: *const State) bool {
        return self.notice_count != 0;
    }

    fn clearError(self: *State) void {
        self.error_length = 0;
    }
};

fn validateCount(count: usize) Error!void {
    if (count > domain.max_notices) return Error.TooManyNotices;
}

test "cache load exposes loaded and empty phases" {
    var state = State{};
    try state.loadCached(3);
    try std.testing.expectEqual(Phase.loaded, state.phase);
    try std.testing.expect(state.hasCachedNotices());

    try state.loadCached(0);
    try std.testing.expectEqual(Phase.empty, state.phase);
    try std.testing.expect(!state.hasCachedNotices());
}

test "refresh presses coalesce and stale completions are rejected" {
    var state = State{};
    try state.loadCached(2);

    const first = (try state.beginRefresh()).started;
    try std.testing.expectEqual(Phase.loading, state.phase);
    try std.testing.expectEqual(
        first,
        (try state.beginRefresh()).already_loading,
    );
    try std.testing.expectEqual(@as(usize, 2), state.notice_count);

    state.cancelRefresh();
    const second = (try state.beginRefresh()).started;
    try std.testing.expect(second > first);
    try std.testing.expectEqual(
        ApplyResult.stale,
        try state.applySuccess(first, 1),
    );
    try std.testing.expectEqual(Phase.loading, state.phase);
    try std.testing.expectEqual(
        ApplyResult.applied,
        try state.applySuccess(second, 4),
    );
    try std.testing.expectEqual(Phase.loaded, state.phase);
    try std.testing.expectEqual(@as(usize, 4), state.notice_count);
}

test "refresh error retains cached notices and can be dismissed" {
    var state = State{};
    try state.loadCached(2);
    const generation = (try state.beginRefresh()).started;
    try std.testing.expectEqual(
        ApplyResult.applied,
        try state.applyFailure(generation, "  Network unavailable  "),
    );
    try std.testing.expectEqual(Phase.@"error", state.phase);
    try std.testing.expectEqualStrings("Network unavailable", state.errorMessage());
    try std.testing.expectEqual(@as(usize, 2), state.notice_count);

    state.dismissError();
    try std.testing.expectEqual(Phase.loaded, state.phase);
    try std.testing.expectEqualStrings("", state.errorMessage());
}

test "state rejects counts and messages beyond its fixed bounds" {
    var state = State{};
    try std.testing.expectError(
        Error.TooManyNotices,
        state.loadCached(domain.max_notices + 1),
    );

    const generation = (try state.beginRefresh()).started;
    var oversized: [max_error_bytes + 1]u8 = undefined;
    @memset(&oversized, 'x');
    try std.testing.expectError(
        Error.ErrorMessageTooLong,
        state.applyFailure(generation, &oversized),
    );
    // Validation failure does not consume the active request.
    try std.testing.expect(state.isRefreshing());
}
