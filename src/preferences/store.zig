//! SQLite repository for app-owned interface preferences.
//!
//! This store records how a reader has chosen to look at the application and
//! nothing else. No taxpayer, registration, filing, credential, or
//! calendar-policy data belongs in `preferences.sqlite3`: those live in their
//! own databases and carry retention, provenance, and custody obligations a
//! window preference does not.
//!
//! A preference is worth exactly one re-selection, so the runtime opens this
//! file through a recovery boundary. An unopenable, unsupported, or malformed
//! store degrades to defaults instead of blocking startup, and the failed file
//! is left untouched for later diagnosis.

const std = @import("std");

const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

pub const default_filename = "preferences.sqlite3";
pub const latest_schema_version: u32 = 1;

/// Keys are compile-time constants owned by this module, and values are short
/// interface choices. Both bounds exist so reads can answer by value.
pub const max_key_bytes = 96;
pub const max_value_bytes = 64;

/// Canonical Revenue District Office codes are three characters ("039",
/// "17A"). Eight bytes absorbs a revised code without letting a stored
/// preference grow with whatever the caller hands over.
pub const max_rdo_code_bytes = 8;

pub const Error = std.mem.Allocator.Error || error{
    Closed,
    InvalidPath,
    EmptyKey,
    KeyTooLong,
    EmptyRdoCode,
    RdoCodeTooLong,
    ValueTooLong,
    SchemaTooNew,
    SqliteBusy,
    SqliteConstraint,
    SqliteFailure,
};

/// A bounded copy of a stored preference value.
pub const Value = struct {
    storage: [max_value_bytes]u8 = undefined,
    len: usize = 0,

    pub fn text(self: *const Value) []const u8 {
        return self.storage[0..self.len];
    }
};

pub const dashboard_rdo_context_key = "global_dashboard.rdo_context";

/// A recorded Global Dashboard RDO context.
///
/// An empty code is the nationwide schedule the reader deliberately chose,
/// which is not the same as never having chosen: the absence of a record is
/// reported as `null` by `loadDashboardRdoContext`, so clearing a district
/// persists as cleared rather than decaying back into "no preference".
pub const RdoContextPreference = struct {
    storage: [max_rdo_code_bytes]u8 = undefined,
    len: usize = 0,

    pub const nationwide: RdoContextPreference = .{};

    pub fn district(rdo_code: []const u8) Error!RdoContextPreference {
        const candidate = std.mem.trim(u8, rdo_code, " \t\r\n");
        if (candidate.len == 0) return Error.EmptyRdoCode;
        if (candidate.len > max_rdo_code_bytes) return Error.RdoCodeTooLong;
        var preference = RdoContextPreference{};
        @memcpy(preference.storage[0..candidate.len], candidate);
        preference.len = candidate.len;
        return preference;
    }

    pub fn code(self: *const RdoContextPreference) []const u8 {
        return self.storage[0..self.len];
    }

    pub fn isNationwide(self: *const RdoContextPreference) bool {
        return self.len == 0;
    }
};

pub const Store = struct {
    db: ?*sqlite.sqlite3,

    /// Opens the interface-preference store. The parent directory must already
    /// exist.
    pub fn openFile(
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !Store {
        if (std.mem.trim(u8, path, " \t\r\n").len == 0) return Error.InvalidPath;
        return openInternal(allocator, path, true);
    }

    /// Opens the preference store without making application boot depend on
    /// that store being readable. A healthy file remains the backing store; an
    /// unopenable file, unsupported schema, failed integrity check, malformed
    /// schema, or unreadable row falls back to a fresh in-memory store, which
    /// starts the session on defaults and records this session's choices.
    ///
    /// This recovery boundary is specific to disposable interface state.
    /// Taxpayer, filing, calendar-rule, and override stores must not use it.
    pub fn openRecoverable(
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !Store {
        var file_store = Store.openFile(allocator, path) catch
            return Store.openMemory(allocator);
        file_store.validateDisposableStore() catch {
            file_store.close();
            return Store.openMemory(allocator);
        };
        return file_store;
    }

    pub fn openMemory(allocator: std.mem.Allocator) !Store {
        return openInternal(allocator, ":memory:", false);
    }

    fn openInternal(
        allocator: std.mem.Allocator,
        path: []const u8,
        file_backed: bool,
    ) !Store {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        var raw: ?*sqlite.sqlite3 = null;
        const flags = sqlite.SQLITE_OPEN_READWRITE |
            sqlite.SQLITE_OPEN_CREATE |
            sqlite.SQLITE_OPEN_FULLMUTEX |
            sqlite.SQLITE_OPEN_NOFOLLOW;
        const rc = sqlite.sqlite3_open_v2(path_z.ptr, &raw, flags, null);
        if (rc != sqlite.SQLITE_OK or raw == null) {
            if (raw) |db| _ = sqlite.sqlite3_close_v2(db);
            return mapResult(rc);
        }

        var store = Store{ .db = raw.? };
        errdefer store.close();
        _ = sqlite.sqlite3_extended_result_codes(store.db.?, 1);
        if (sqlite.sqlite3_busy_timeout(store.db.?, 5_000) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
        if (file_backed) {
            try store.exec("PRAGMA journal_mode = WAL;");
            try store.exec("PRAGMA synchronous = NORMAL;");
        }
        try store.migrate();
        return store;
    }

    pub fn close(self: *Store) void {
        if (self.db) |db| {
            _ = sqlite.sqlite3_close_v2(db);
            self.db = null;
        }
    }

    pub fn schemaVersion(self: *Store) !u32 {
        var statement = try self.prepare("PRAGMA user_version;");
        defer statement.deinit();
        if (try statement.step() != .row) return Error.SqliteFailure;
        const value = sqlite.sqlite3_column_int64(statement.raw, 0);
        if (value < 0 or value > std.math.maxInt(u32)) {
            return Error.SqliteFailure;
        }
        return @intCast(value);
    }

    pub fn migrate(self: *Store) !void {
        const observed_version = try self.schemaVersion();
        return self.migrateFromObservedVersion(observed_version);
    }

    fn migrateFromObservedVersion(
        self: *Store,
        observed_version: u32,
    ) !void {
        if (observed_version > latest_schema_version) return Error.SchemaTooNew;
        if (observed_version == latest_schema_version) return;

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        // Re-read after taking the write lock: a concurrent opener may have
        // completed the migration while this connection was waiting.
        const locked_version = try self.schemaVersion();
        if (locked_version > latest_schema_version) return Error.SchemaTooNew;
        if (locked_version < 1) {
            try self.exec(schema_v1);
            try self.exec("PRAGMA user_version = 1;");
        }

        try self.commit();
        committed = true;
    }

    /// `null` means the preference has never been recorded.
    pub fn get(self: *Store, key: []const u8) !?Value {
        try validateKey(key);
        var statement = try self.prepare(
            "SELECT value FROM app_preferences WHERE key = ?;",
        );
        defer statement.deinit();
        try statement.bindText(1, key);
        if (try statement.step() != .row) return null;

        const stored = columnText(statement.raw, 0) orelse
            return Error.SqliteFailure;
        if (stored.len > max_value_bytes) return Error.ValueTooLong;
        var value = Value{};
        @memcpy(value.storage[0..stored.len], stored);
        value.len = stored.len;
        return value;
    }

    pub fn set(self: *Store, key: []const u8, value: []const u8) !void {
        try validateKey(key);
        if (value.len > max_value_bytes) return Error.ValueTooLong;
        var statement = try self.prepare(upsert_sql);
        defer statement.deinit();
        try statement.bindText(1, key);
        try statement.bindText(2, value);
        try statement.expectDone();
    }

    pub fn count(self: *Store) !usize {
        var statement = try self.prepare("SELECT count(*) FROM app_preferences;");
        defer statement.deinit();
        if (try statement.step() != .row) return Error.SqliteFailure;
        const value = sqlite.sqlite3_column_int64(statement.raw, 0);
        if (value < 0) return Error.SqliteFailure;
        return @intCast(value);
    }

    pub fn loadDashboardRdoContext(self: *Store) !?RdoContextPreference {
        const stored = try self.get(dashboard_rdo_context_key) orelse
            return null;
        const recorded = stored.text();
        if (recorded.len == 0) return RdoContextPreference.nationwide;
        return try RdoContextPreference.district(recorded);
    }

    pub fn saveDashboardRdoContext(
        self: *Store,
        preference: RdoContextPreference,
    ) !void {
        return self.set(dashboard_rdo_context_key, preference.code());
    }

    fn validateDisposableStore(self: *Store) !void {
        var integrity = try self.prepare("PRAGMA quick_check;");
        defer integrity.deinit();
        if (try integrity.step() != .row) return Error.SqliteFailure;
        const result = columnText(integrity.raw, 0) orelse
            return Error.SqliteFailure;
        if (!std.mem.eql(u8, result, "ok")) return Error.SqliteFailure;
        if (try integrity.step() != .done) return Error.SqliteFailure;

        // Exercise the schema and every retained row before startup adopts the
        // file: a row this reader cannot hold is corruption, not a preference.
        var rows = try self.prepare("SELECT key, value FROM app_preferences;");
        defer rows.deinit();
        while (try rows.step() == .row) {
            const key = columnText(rows.raw, 0) orelse
                return Error.SqliteFailure;
            try validateKey(key);
            const value = columnText(rows.raw, 1) orelse
                return Error.SqliteFailure;
            if (value.len > max_value_bytes) return Error.ValueTooLong;
        }
    }

    fn beginImmediate(self: *Store) !void {
        try self.exec("BEGIN IMMEDIATE;");
    }

    fn commit(self: *Store) !void {
        try self.exec("COMMIT;");
    }

    fn rollbackNoFail(self: *Store) void {
        self.exec("ROLLBACK;") catch {};
    }

    fn exec(self: *Store, sql_text: [*:0]const u8) !void {
        const db = try self.handle();
        const rc = sqlite.sqlite3_exec(db, sql_text, null, null, null);
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn prepare(self: *Store, sql_text: []const u8) !Statement {
        const db = try self.handle();
        var raw: ?*sqlite.sqlite3_stmt = null;
        const rc = sqlite.sqlite3_prepare_v2(
            db,
            sql_text.ptr,
            @intCast(sql_text.len),
            &raw,
            null,
        );
        if (rc != sqlite.SQLITE_OK or raw == null) return mapResult(rc);
        return .{ .raw = raw.? };
    }

    fn handle(self: *Store) Error!*sqlite.sqlite3 {
        return self.db orelse Error.Closed;
    }
};

const StepResult = enum { row, done };

const Statement = struct {
    raw: *sqlite.sqlite3_stmt,

    fn deinit(self: *Statement) void {
        _ = sqlite.sqlite3_finalize(self.raw);
        self.* = undefined;
    }

    fn bindText(self: *Statement, index: c_int, value: []const u8) !void {
        const rc = sqlite.sqlite3_bind_text(
            self.raw,
            index,
            value.ptr,
            @intCast(value.len),
            null,
        );
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn step(self: *Statement) !StepResult {
        return switch (sqlite.sqlite3_step(self.raw)) {
            sqlite.SQLITE_ROW => .row,
            sqlite.SQLITE_DONE => .done,
            else => |rc| mapResult(rc),
        };
    }

    fn expectDone(self: *Statement) !void {
        if (try self.step() != .done) return Error.SqliteFailure;
    }
};

fn validateKey(key: []const u8) Error!void {
    if (key.len == 0) return Error.EmptyKey;
    if (key.len > max_key_bytes) return Error.KeyTooLong;
}

/// SQLite reports an empty TEXT column through a pointer that callers must not
/// distinguish from a failed read, so the column type decides emptiness.
fn columnText(row: *sqlite.sqlite3_stmt, column: c_int) ?[]const u8 {
    if (sqlite.sqlite3_column_type(row, column) == sqlite.SQLITE_NULL) {
        return null;
    }
    const length = sqlite.sqlite3_column_bytes(row, column);
    if (length < 0) return null;
    if (length == 0) return "";
    const raw = sqlite.sqlite3_column_text(row, column) orelse return null;
    const bytes: [*]const u8 = @ptrCast(raw);
    return bytes[0..@intCast(length)];
}

fn mapResult(rc: c_int) Error {
    const primary = rc & 0xff;
    return switch (primary) {
        sqlite.SQLITE_BUSY, sqlite.SQLITE_LOCKED => Error.SqliteBusy,
        sqlite.SQLITE_CONSTRAINT => Error.SqliteConstraint,
        else => Error.SqliteFailure,
    };
}

const schema_v1 = std.fmt.comptimePrint(
    \\CREATE TABLE app_preferences (
    \\    key TEXT PRIMARY KEY
    \\        CHECK (length(key) BETWEEN 1 AND {d}),
    \\    value TEXT NOT NULL
    \\        CHECK (length(value) <= {d}),
    \\    created_at_unix INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at_unix INTEGER NOT NULL DEFAULT (unixepoch())
    \\);
, .{ max_key_bytes, max_value_bytes });

const upsert_sql =
    \\INSERT INTO app_preferences (key, value) VALUES (?, ?)
    \\ON CONFLICT(key) DO UPDATE SET
    \\    value = excluded.value,
    \\    updated_at_unix = unixepoch();
;

fn temporaryStorePath(
    directory: *std.testing.TmpDir,
    directory_buffer: []u8,
    path_buffer: []u8,
) ![]const u8 {
    const directory_len = try directory.dir.realPath(
        std.testing.io,
        directory_buffer,
    );
    return std.fmt.bufPrint(
        path_buffer,
        "{s}/{s}",
        .{ directory_buffer[0..directory_len], default_filename },
    );
}

test "migration is versioned and rejects a newer schema" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
    try store.migrate();
    try store.exec("PRAGMA user_version = 99;");
    try std.testing.expectError(Error.SchemaTooNew, store.migrate());
}

test "an unrecorded preference reads as absent rather than as a default" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    try std.testing.expect(try store.get("never.written") == null);
    try std.testing.expect(try store.loadDashboardRdoContext() == null);
    try std.testing.expectEqual(@as(usize, 0), try store.count());
}

test "a recorded dashboard district survives close and reopen" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const store_path = try temporaryStorePath(
        &tmp,
        &directory_buffer,
        &path_buffer,
    );

    {
        var store = try Store.openFile(allocator, store_path);
        defer store.close();
        try store.saveDashboardRdoContext(
            try RdoContextPreference.district("039"),
        );
        // The last choice wins rather than accumulating rows.
        try store.saveDashboardRdoContext(
            try RdoContextPreference.district("17A"),
        );
        try std.testing.expectEqual(@as(usize, 1), try store.count());
    }

    var reopened = try Store.openRecoverable(allocator, store_path);
    defer reopened.close();
    try std.testing.expectEqual(
        latest_schema_version,
        try reopened.schemaVersion(),
    );
    const restored = (try reopened.loadDashboardRdoContext()) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(!restored.isNationwide());
    try std.testing.expectEqualStrings("17A", restored.code());
}

test "a cleared dashboard context reopens as a recorded nationwide choice" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const store_path = try temporaryStorePath(
        &tmp,
        &directory_buffer,
        &path_buffer,
    );

    {
        var store = try Store.openFile(allocator, store_path);
        defer store.close();
        try store.saveDashboardRdoContext(
            try RdoContextPreference.district("039"),
        );
        try store.saveDashboardRdoContext(RdoContextPreference.nationwide);
    }

    var reopened = try Store.openFile(allocator, store_path);
    defer reopened.close();
    const restored = (try reopened.loadDashboardRdoContext()) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(restored.isNationwide());
    try std.testing.expectEqualStrings("", restored.code());
}

test "an unusable RDO code is refused instead of being recorded" {
    try std.testing.expectError(
        Error.EmptyRdoCode,
        RdoContextPreference.district("   "),
    );
    try std.testing.expectError(
        Error.RdoCodeTooLong,
        RdoContextPreference.district("0" ** (max_rdo_code_bytes + 1)),
    );
}

test "an unreadable preference store degrades to defaults, not to a failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const store_path = try temporaryStorePath(
        &tmp,
        &directory_buffer,
        &path_buffer,
    );

    {
        var broken = try Store.openFile(allocator, store_path);
        defer broken.close();
        try broken.saveDashboardRdoContext(
            try RdoContextPreference.district("039"),
        );
        try broken.exec("DROP TABLE app_preferences;");
    }

    {
        var recovered = try Store.openRecoverable(allocator, store_path);
        defer recovered.close();
        try std.testing.expect(try recovered.loadDashboardRdoContext() == null);
        try recovered.saveDashboardRdoContext(
            try RdoContextPreference.district("113"),
        );
        const session = (try recovered.loadDashboardRdoContext()) orelse
            return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings("113", session.code());
    }

    // Recovery is non-destructive: the failed file stays available for
    // diagnosis instead of being silently replaced.
    var still_broken = try Store.openFile(allocator, store_path);
    defer still_broken.close();
    try std.testing.expectError(Error.SqliteFailure, still_broken.count());
}

test "a too-new or unopenable preference store still yields a usable session" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const store_path = try temporaryStorePath(
        &tmp,
        &directory_buffer,
        &path_buffer,
    );

    {
        var too_new = try Store.openFile(allocator, store_path);
        defer too_new.close();
        try too_new.exec("PRAGMA user_version = 99;");
    }
    {
        var recovered = try Store.openRecoverable(allocator, store_path);
        defer recovered.close();
        try std.testing.expectEqual(
            latest_schema_version,
            try recovered.schemaVersion(),
        );
        try std.testing.expect(try recovered.loadDashboardRdoContext() == null);
    }
    try std.testing.expectError(
        Error.SchemaTooNew,
        Store.openFile(allocator, store_path),
    );

    // SQLite cannot use a directory as a database file. An absent store and an
    // unopenable one reach the same in-memory defaults.
    const directory_len = try tmp.dir.realPath(
        std.testing.io,
        &directory_buffer,
    );
    var unopenable = try Store.openRecoverable(
        allocator,
        directory_buffer[0..directory_len],
    );
    defer unopenable.close();
    try std.testing.expect(try unopenable.loadDashboardRdoContext() == null);
    try unopenable.saveDashboardRdoContext(RdoContextPreference.nationwide);
    try std.testing.expect(
        (try unopenable.loadDashboardRdoContext()).?.isNationwide(),
    );
}
