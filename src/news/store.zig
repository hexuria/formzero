//! SQLite repository for the public Important News cache.
//!
//! This store is intentionally separate from taxpayer/calendar persistence.
//! The runtime should open `news.sqlite3`; it contains public feed content only
//! and can be rebuilt from its configured providers. Writes are transactional,
//! keyed by `(source, external_id)`, and globally pruned to the 25 newest rows.

const std = @import("std");
const domain = @import("domain.zig");

const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

pub const default_filename = "news.sqlite3";
pub const latest_schema_version: u32 = 1;

pub const Error = domain.Error || std.mem.Allocator.Error || error{
    Closed,
    InvalidPath,
    BatchTooLarge,
    SchemaTooNew,
    SqliteBusy,
    SqliteConstraint,
    SqliteFailure,
};

pub const Store = struct {
    db: ?*sqlite.sqlite3,

    /// Opens the separate, disposable public-news cache. The parent directory
    /// must already exist. No taxpayer, filing, credential, or calendar-policy
    /// data belongs in this database.
    pub fn openFile(
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !Store {
        if (domain.trim(path).len == 0) return Error.InvalidPath;
        return openInternal(allocator, path, true);
    }

    /// Opens the disposable public-news cache without making application boot
    /// depend on that cache being readable. A healthy file remains the backing
    /// store. An unopenable file, unsupported schema, failed integrity check,
    /// malformed schema, or invalid cached row falls back to a fresh in-memory
    /// store; the failed file is left untouched for later diagnosis/recovery.
    ///
    /// This recovery boundary is intentionally specific to public feed data.
    /// Taxpayer, filing, calendar-rule, and override stores must not use it.
    pub fn openRecoverableCache(
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !Store {
        var file_store = Store.openFile(allocator, path) catch
            return Store.openMemory(allocator);
        file_store.validateDisposableCache(allocator) catch {
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

    /// Atomically inserts or updates a fetched feed and enforces the global
    /// retention bound. Every item is validated before the transaction starts.
    pub fn upsertBatch(
        self: *Store,
        notices: []const domain.NoticeWrite,
    ) !void {
        if (notices.len > domain.max_feed_entries) return Error.BatchTooLarge;
        for (notices) |notice| try notice.validate();

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        var statement = try self.prepare(upsert_sql);
        defer statement.deinit();
        for (notices) |notice| {
            try bindNotice(&statement, notice);
            try statement.expectDone();
            try statement.reset();
        }
        try self.prune();
        try self.commit();
        committed = true;
    }

    /// Convenience boundary for `feed.parse` results without weakening batch
    /// atomicity or requiring the caller to allocate a second owned model.
    pub fn upsertOwnedBatch(
        self: *Store,
        notices: []const domain.OwnedNotice,
    ) !void {
        if (notices.len > domain.max_feed_entries) return Error.BatchTooLarge;
        for (notices) |*notice| try notice.write().validate();

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        var statement = try self.prepare(upsert_sql);
        defer statement.deinit();
        for (notices) |*notice| {
            try bindNotice(&statement, notice.write());
            try statement.expectDone();
            try statement.reset();
        }
        try self.prune();
        try self.commit();
        committed = true;
    }

    pub fn listNewest(
        self: *Store,
        allocator: std.mem.Allocator,
    ) !domain.NoticeList {
        var statement = try self.prepare(
            \\SELECT source, external_id, title, summary, url,
            \\       published_at_unix, fetched_at_unix
            \\FROM news_notices
            \\ORDER BY published_at_unix DESC, fetched_at_unix DESC,
            \\         source ASC, external_id ASC
            \\LIMIT 25;
        );
        defer statement.deinit();

        var items: std.ArrayList(domain.OwnedNotice) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            try items.append(allocator, try readNotice(allocator, statement.raw));
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    pub fn count(self: *Store) !usize {
        var statement = try self.prepare("SELECT count(*) FROM news_notices;");
        defer statement.deinit();
        if (try statement.step() != .row) return Error.SqliteFailure;
        const value = sqlite.sqlite3_column_int64(statement.raw, 0);
        if (value < 0 or value > domain.max_notices) return Error.SqliteFailure;
        return @intCast(value);
    }

    fn validateDisposableCache(
        self: *Store,
        allocator: std.mem.Allocator,
    ) !void {
        var integrity = try self.prepare("PRAGMA quick_check;");
        defer integrity.deinit();
        if (try integrity.step() != .row) return Error.SqliteFailure;
        const result = columnText(integrity.raw, 0) orelse
            return Error.SqliteFailure;
        if (!std.mem.eql(u8, result, "ok")) return Error.SqliteFailure;
        if (try integrity.step() != .done) return Error.SqliteFailure;

        // Exercise the schema and validate every retained row before handing
        // the file to startup. `listNewest` is bounded to the cache maximum.
        var notices = try self.listNewest(allocator);
        defer notices.deinit(allocator);
        if (try self.count() != notices.items.len) return Error.SqliteFailure;
    }

    fn prune(self: *Store) !void {
        try self.exec(
            \\DELETE FROM news_notices
            \\WHERE id NOT IN (
            \\    SELECT id FROM news_notices
            \\    ORDER BY published_at_unix DESC, fetched_at_unix DESC,
            \\             source ASC, external_id ASC
            \\    LIMIT 25
            \\);
        );
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

    fn bindOptionalText(
        self: *Statement,
        index: c_int,
        value: ?[]const u8,
    ) !void {
        if (value) |text| return self.bindText(index, text);
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }

    fn bindInt64(self: *Statement, index: c_int, value: i64) !void {
        if (sqlite.sqlite3_bind_int64(self.raw, index, value) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
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

    fn reset(self: *Statement) !void {
        if (sqlite.sqlite3_reset(self.raw) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
        if (sqlite.sqlite3_clear_bindings(self.raw) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }
};

fn bindNotice(statement: *Statement, notice: domain.NoticeWrite) !void {
    try statement.bindText(1, domain.trim(notice.source));
    try statement.bindText(2, domain.trim(notice.external_id));
    try statement.bindText(3, domain.trim(notice.title));
    try statement.bindText(4, domain.trim(notice.summary));
    try statement.bindOptionalText(
        5,
        if (notice.url) |url| domain.trim(url) else null,
    );
    try statement.bindInt64(6, notice.published_at_unix);
    try statement.bindInt64(7, notice.fetched_at_unix);
}

fn readNotice(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
) !domain.OwnedNotice {
    return domain.OwnedNotice.init(allocator, .{
        .source = columnText(row, 0) orelse return Error.SqliteFailure,
        .external_id = columnText(row, 1) orelse return Error.SqliteFailure,
        .title = columnText(row, 2) orelse return Error.SqliteFailure,
        .summary = columnText(row, 3) orelse return Error.SqliteFailure,
        .url = if (sqlite.sqlite3_column_type(row, 4) == sqlite.SQLITE_NULL)
            null
        else
            columnText(row, 4) orelse return Error.SqliteFailure,
        .published_at_unix = sqlite.sqlite3_column_int64(row, 5),
        .fetched_at_unix = sqlite.sqlite3_column_int64(row, 6),
    });
}

fn columnText(row: *sqlite.sqlite3_stmt, column: c_int) ?[]const u8 {
    const raw = sqlite.sqlite3_column_text(row, column) orelse return null;
    const length = sqlite.sqlite3_column_bytes(row, column);
    if (length < 0) return null;
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

const schema_v1 =
    \\CREATE TABLE news_notices (
    \\    id INTEGER PRIMARY KEY,
    \\    source TEXT NOT NULL
    \\        CHECK (length(trim(source)) BETWEEN 1 AND 96),
    \\    external_id TEXT NOT NULL
    \\        CHECK (length(trim(external_id)) BETWEEN 1 AND 512),
    \\    title TEXT NOT NULL
    \\        CHECK (length(trim(title)) BETWEEN 1 AND 512),
    \\    summary TEXT NOT NULL
    \\        CHECK (length(summary) <= 4096),
    \\    url TEXT CHECK (
    \\        url IS NULL OR url GLOB 'https://*' OR url GLOB 'http://*'
    \\    ),
    \\    published_at_unix INTEGER NOT NULL
    \\        CHECK (published_at_unix >= 0),
    \\    fetched_at_unix INTEGER NOT NULL
    \\        CHECK (fetched_at_unix >= 0),
    \\    created_at_unix INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at_unix INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    UNIQUE (source, external_id)
    \\);
    \\CREATE INDEX news_notices_newest_idx
    \\    ON news_notices(
    \\        published_at_unix DESC,
    \\        fetched_at_unix DESC,
    \\        source,
    \\        external_id
    \\    );
;

const upsert_sql =
    \\INSERT INTO news_notices (
    \\    source, external_id, title, summary, url,
    \\    published_at_unix, fetched_at_unix
    \\) VALUES (?, ?, ?, ?, ?, ?, ?)
    \\ON CONFLICT(source, external_id) DO UPDATE SET
    \\    title = excluded.title,
    \\    summary = excluded.summary,
    \\    url = excluded.url,
    \\    published_at_unix = excluded.published_at_unix,
    \\    fetched_at_unix = excluded.fetched_at_unix,
    \\    updated_at_unix = unixepoch();
;

test "migration is versioned and rejects a newer schema" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
    try store.migrate();
    try store.exec("PRAGMA user_version = 99;");
    try std.testing.expectError(Error.SchemaTooNew, store.migrate());
}

test "transactional upsert deduplicates stable identity" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const batch = [_]domain.NoticeWrite{
        .{
            .source = "Agency",
            .external_id = "notice-1",
            .title = "Original",
            .published_at_unix = 10,
            .fetched_at_unix = 20,
        },
        .{
            .source = "Agency",
            .external_id = "notice-1",
            .title = "Corrected",
            .summary = "The publisher corrected the title.",
            .published_at_unix = 11,
            .fetched_at_unix = 30,
        },
    };
    try store.upsertBatch(&batch);

    try std.testing.expectEqual(@as(usize, 1), try store.count());
    var notices = try store.listNewest(allocator);
    defer notices.deinit(allocator);
    try std.testing.expectEqualStrings("Corrected", notices.items[0].title);
    try std.testing.expectEqual(@as(i64, 30), notices.items[0].fetched_at_unix);
}

test "owned feed results use the same atomic upsert boundary" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    var owned = [_]domain.OwnedNotice{
        try domain.OwnedNotice.init(allocator, .{
            .source = "Agency",
            .external_id = "owned-1",
            .title = "Owned result",
            .published_at_unix = 10,
            .fetched_at_unix = 20,
        }),
    };
    defer owned[0].deinit(allocator);
    try store.upsertOwnedBatch(&owned);

    var notices = try store.listNewest(allocator);
    defer notices.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), notices.items.len);
    try std.testing.expectEqualStrings("owned-1", notices.items[0].external_id);
}

test "batch validates fully before changing the cache" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    try store.upsertBatch(&.{.{
        .source = "Agency",
        .external_id = "existing",
        .title = "Existing",
        .published_at_unix = 10,
        .fetched_at_unix = 20,
    }});
    try std.testing.expectError(Error.EmptyTitle, store.upsertBatch(&.{
        .{
            .source = "Agency",
            .external_id = "would-have-been-inserted",
            .title = "New",
            .published_at_unix = 30,
            .fetched_at_unix = 40,
        },
        .{
            .source = "Agency",
            .external_id = "invalid",
            .title = " ",
            .published_at_unix = 30,
            .fetched_at_unix = 40,
        },
    }));
    try std.testing.expectEqual(@as(usize, 1), try store.count());
}

test "repository retains only the 25 newest notices" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    var id_buffer: [32]u8 = undefined;
    var title_buffer: [32]u8 = undefined;
    var index: usize = 0;
    while (index < 30) : (index += 1) {
        const id = try std.fmt.bufPrint(&id_buffer, "notice-{d}", .{index});
        const title = try std.fmt.bufPrint(&title_buffer, "Notice {d}", .{index});
        try store.upsertBatch(&.{.{
            .source = "Agency",
            .external_id = id,
            .title = title,
            .published_at_unix = @intCast(index),
            .fetched_at_unix = 100,
        }});
    }

    try std.testing.expectEqual(domain.max_notices, try store.count());
    var notices = try store.listNewest(allocator);
    defer notices.deinit(allocator);
    try std.testing.expectEqual(domain.max_notices, notices.items.len);
    try std.testing.expectEqualStrings("notice-29", notices.items[0].external_id);
    try std.testing.expectEqualStrings("notice-5", notices.items[24].external_id);
}

test "file cache closes and reopens without losing rows" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory_len = try tmp.dir.realPath(
        std.testing.io,
        &directory_buffer,
    );
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const database_path = try std.fmt.bufPrint(
        &path_buffer,
        "{s}/{s}",
        .{ directory_buffer[0..directory_len], default_filename },
    );

    {
        var store = try Store.openFile(allocator, database_path);
        defer store.close();
        try store.upsertBatch(&.{.{
            .source = "Official Gazette",
            .external_id = "reopen-1",
            .title = "Persisted notice",
            .url = "https://example.test/reopen-1",
            .published_at_unix = 100,
            .fetched_at_unix = 200,
        }});
    }

    {
        var reopened = try Store.openFile(allocator, database_path);
        defer reopened.close();
        try std.testing.expectEqual(
            latest_schema_version,
            try reopened.schemaVersion(),
        );
        var notices = try reopened.listNewest(allocator);
        defer notices.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 1), notices.items.len);
        try std.testing.expectEqualStrings("Persisted notice", notices.items[0].title);
    }
}

test "recoverable cache preserves healthy file backing" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory_len = try tmp.dir.realPath(
        std.testing.io,
        &directory_buffer,
    );
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const database_path = try std.fmt.bufPrint(
        &path_buffer,
        "{s}/{s}",
        .{ directory_buffer[0..directory_len], default_filename },
    );

    {
        var initial = try Store.openFile(allocator, database_path);
        defer initial.close();
        try initial.upsertBatch(&.{.{
            .source = "Official Gazette",
            .external_id = "healthy-1",
            .title = "Healthy cached notice",
            .published_at_unix = 100,
            .fetched_at_unix = 200,
        }});
    }

    {
        var recovered = try Store.openRecoverableCache(
            allocator,
            database_path,
        );
        defer recovered.close();
        try std.testing.expectEqual(@as(usize, 1), try recovered.count());
        try recovered.upsertBatch(&.{.{
            .source = "Official Gazette",
            .external_id = "healthy-2",
            .title = "Second cached notice",
            .published_at_unix = 300,
            .fetched_at_unix = 400,
        }});
    }

    var reopened = try Store.openFile(allocator, database_path);
    defer reopened.close();
    try std.testing.expectEqual(@as(usize, 2), try reopened.count());
}

test "recoverable cache falls back when file schema is unusable" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory_len = try tmp.dir.realPath(
        std.testing.io,
        &directory_buffer,
    );
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const database_path = try std.fmt.bufPrint(
        &path_buffer,
        "{s}/{s}",
        .{ directory_buffer[0..directory_len], default_filename },
    );

    {
        var broken = try Store.openFile(allocator, database_path);
        defer broken.close();
        try broken.exec("DROP TABLE news_notices;");
    }

    {
        var recovered = try Store.openRecoverableCache(
            allocator,
            database_path,
        );
        defer recovered.close();
        try std.testing.expectEqual(
            latest_schema_version,
            try recovered.schemaVersion(),
        );
        try std.testing.expectEqual(@as(usize, 0), try recovered.count());
        try recovered.upsertBatch(&.{.{
            .source = "Official Gazette",
            .external_id = "memory-after-corruption",
            .title = "Usable fallback",
            .published_at_unix = 100,
            .fetched_at_unix = 200,
        }});
        try std.testing.expectEqual(@as(usize, 1), try recovered.count());
    }

    // Recovery is non-destructive: the failed public cache remains available
    // for diagnosis instead of being silently replaced with another file.
    var still_broken = try Store.openFile(allocator, database_path);
    defer still_broken.close();
    try std.testing.expectError(Error.SqliteFailure, still_broken.count());
}

test "recoverable cache falls back for too-new and unopenable files" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory_len = try tmp.dir.realPath(
        std.testing.io,
        &directory_buffer,
    );
    const directory_path = directory_buffer[0..directory_len];
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const database_path = try std.fmt.bufPrint(
        &path_buffer,
        "{s}/{s}",
        .{ directory_path, default_filename },
    );

    {
        var too_new = try Store.openFile(allocator, database_path);
        defer too_new.close();
        try too_new.exec("PRAGMA user_version = 99;");
    }
    {
        var recovered = try Store.openRecoverableCache(
            allocator,
            database_path,
        );
        defer recovered.close();
        try std.testing.expectEqual(
            latest_schema_version,
            try recovered.schemaVersion(),
        );
        try std.testing.expectEqual(@as(usize, 0), try recovered.count());
    }
    try std.testing.expectError(
        Error.SchemaTooNew,
        Store.openFile(allocator, database_path),
    );

    // SQLite cannot use a directory as a database file. The recoverable
    // boundary still returns a migrated, writable in-memory cache.
    var unopenable = try Store.openRecoverableCache(
        allocator,
        directory_path,
    );
    defer unopenable.close();
    try unopenable.upsertBatch(&.{.{
        .source = "Official Gazette",
        .external_id = "memory-after-open-failure",
        .title = "Usable fallback",
        .published_at_unix = 100,
        .fetched_at_unix = 200,
    }});
    try std.testing.expectEqual(@as(usize, 1), try unopenable.count());
}
