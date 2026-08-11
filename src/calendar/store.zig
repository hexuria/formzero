//! SQLite persistence for calendar policy, calendar providers, and managed
//! external events.
//!
//! This module deliberately owns persistence-shaped records rather than the
//! calendar domain model. Write records borrow caller-owned slices. Read APIs
//! return owned records/lists and require the same allocator when deinitialized.
//!
//! Deadline overrides carry a provenance: `manual` rows are authored in the
//! app and owned by the user, `synced` rows are projected from the published
//! BIR feed and owned by `syncOverridesFromFeed`. The two never mix — a synced
//! row is addressed by its feed-stable `external_ref`, a manual row never has
//! one, and no sync may read, update, or delete a manual row. Dismissing a
//! synced row tombstones its reference so later syncs cannot resurrect it.

const std = @import("std");
const key_custody = @import("../security/key_custody.zig");
const repository_opening = @import("../security/repository_opening.zig");

const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

pub const latest_schema_version: u32 = 3;
pub const max_scope_text_bytes: usize = 128;
pub const max_external_ref_bytes: usize = 512;
/// One feed document may carry at most this many override records. The
/// publisher's own cap is lower; this bounds a hostile or corrupted feed.
pub const max_sync_records: usize = 128;
pub const storage_classification =
    repository_opening.legacy_plaintext_repository_classification;
pub const production_repository_integration_state =
    repository_opening.current_production_repository_integration_state;
pub const production_repository_scope =
    repository_opening.ProductionRepositoryScope
        .shared_calendar_tax_profile_database;

pub const Error = error{
    Closed,
    InvalidDate,
    InvalidValue,
    SourceRequired,
    AffectedFormRequired,
    ExternalRefRequired,
    BatchTooLarge,
    NotFound,
    SchemaTooNew,
    SqliteBusy,
    SqliteConstraint,
    SqliteFailure,
};

/// Mirrors the `origin` CHECK vocabulary; unknown storage text fails closed
/// rather than degrading a synced row into an editable one.
pub const Origin = enum {
    manual,
    synced,

    pub fn text(self: Origin) []const u8 {
        return switch (self) {
            .manual => "manual",
            .synced => "synced",
        };
    }

    fn parse(value: []const u8) Error!Origin {
        if (std.mem.eql(u8, value, "manual")) return .manual;
        if (std.mem.eql(u8, value, "synced")) return .synced;
        return Error.InvalidValue;
    }
};

pub const OverrideWrite = struct {
    id: ?i64 = null,
    title: []const u8,
    source: []const u8,
    original_deadline: []const u8,
    adjusted_deadline: []const u8,
    effective_from: ?[]const u8 = null,
    effective_until: ?[]const u8 = null,
    expires_at: ?[]const u8 = null,
    affected_form_codes: []const []const u8,
    /// An empty list means the override applies in every region.
    regions: []const []const u8 = &.{},
    /// An empty list means the override applies to every taxpayer type.
    taxpayer_types: []const []const u8 = &.{},
    origin: Origin = .manual,
    /// Feed-stable identity. Required for `.synced`, forbidden for `.manual`.
    external_ref: ?[]const u8 = null,
};

pub const OwnedOverride = struct {
    id: i64,
    title: []u8,
    source: []u8,
    original_deadline: []u8,
    adjusted_deadline: []u8,
    effective_from: ?[]u8,
    effective_until: ?[]u8,
    expires_at: ?[]u8,
    affected_form_codes: [][]u8,
    regions: [][]u8,
    taxpayer_types: [][]u8,
    origin: Origin,
    external_ref: ?[]u8,

    pub fn deinit(self: *OwnedOverride, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.source);
        allocator.free(self.original_deadline);
        allocator.free(self.adjusted_deadline);
        freeOptional(allocator, self.effective_from);
        freeOptional(allocator, self.effective_until);
        freeOptional(allocator, self.expires_at);
        freeStrings(allocator, self.affected_form_codes);
        freeStrings(allocator, self.regions);
        freeStrings(allocator, self.taxpayer_types);
        freeOptional(allocator, self.external_ref);
        self.* = undefined;
    }
};

pub const OverrideList = struct {
    items: []OwnedOverride,

    pub fn deinit(self: *OverrideList, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

/// One compiled feed override, borrowed for the duration of a single sync.
/// `rdo_codes` become the row's region scopes verbatim and `source_reference`
/// becomes its source, so the existing scoped resolver applies them unchanged.
pub const FeedOverrideRecord = struct {
    external_ref: []const u8,
    title: []const u8,
    source_reference: []const u8,
    original_deadline: []const u8,
    adjusted_deadline: []const u8,
    form_codes: []const []const u8,
    rdo_codes: []const []const u8,
};

pub const SyncSummary = struct {
    inserted: usize = 0,
    updated: usize = 0,
    skipped_dismissed: usize = 0,
    rejected: usize = 0,
};

pub const NonWorkingDayWrite = struct {
    id: ?i64 = null,
    day: []const u8,
    name: []const u8,
    kind: []const u8,
    source: []const u8,
    /// An empty list means the day applies nationwide.
    regions: []const []const u8 = &.{},
};

pub const OwnedNonWorkingDay = struct {
    id: i64,
    day: []u8,
    name: []u8,
    kind: []u8,
    source: []u8,
    regions: [][]u8,

    pub fn deinit(self: *OwnedNonWorkingDay, allocator: std.mem.Allocator) void {
        allocator.free(self.day);
        allocator.free(self.name);
        allocator.free(self.kind);
        allocator.free(self.source);
        freeStrings(allocator, self.regions);
        self.* = undefined;
    }
};

pub const NonWorkingDayList = struct {
    items: []OwnedNonWorkingDay,

    pub fn deinit(self: *NonWorkingDayList, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const ConnectionWrite = struct {
    provider: []const u8,
    profile_key: []const u8,
    external_calendar_id: []const u8,
    calendar_name: ?[]const u8 = null,
    enabled: bool = true,
    last_synced_at: ?[]const u8 = null,
    last_error: ?[]const u8 = null,
};

pub const OwnedConnection = struct {
    id: i64,
    provider: []u8,
    profile_key: []u8,
    external_calendar_id: []u8,
    calendar_name: ?[]u8,
    enabled: bool,
    last_synced_at: ?[]u8,
    last_error: ?[]u8,

    pub fn deinit(self: *OwnedConnection, allocator: std.mem.Allocator) void {
        allocator.free(self.provider);
        allocator.free(self.profile_key);
        allocator.free(self.external_calendar_id);
        freeOptional(allocator, self.calendar_name);
        freeOptional(allocator, self.last_synced_at);
        freeOptional(allocator, self.last_error);
        self.* = undefined;
    }
};

pub const ConnectionList = struct {
    items: []OwnedConnection,

    pub fn deinit(self: *ConnectionList, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const EventLinkWrite = struct {
    provider: []const u8,
    profile_key: []const u8,
    obligation_key: []const u8,
    external_event_id: []const u8,
    external_ical_uid: ?[]const u8 = null,
    series_id: ?[]const u8 = null,
    occurrence_id: ?[]const u8 = null,
    revision: ?[]const u8 = null,
    fingerprint: []const u8,
    created_by_backend: bool = true,
};

pub const OwnedEventLink = struct {
    provider: []u8,
    profile_key: []u8,
    obligation_key: []u8,
    external_event_id: []u8,
    external_ical_uid: ?[]u8,
    series_id: ?[]u8,
    occurrence_id: ?[]u8,
    revision: ?[]u8,
    fingerprint: []u8,
    created_by_backend: bool,

    pub fn deinit(self: *OwnedEventLink, allocator: std.mem.Allocator) void {
        allocator.free(self.provider);
        allocator.free(self.profile_key);
        allocator.free(self.obligation_key);
        allocator.free(self.external_event_id);
        freeOptional(allocator, self.external_ical_uid);
        freeOptional(allocator, self.series_id);
        freeOptional(allocator, self.occurrence_id);
        freeOptional(allocator, self.revision);
        allocator.free(self.fingerprint);
        self.* = undefined;
    }
};

pub const EventLinkList = struct {
    items: []OwnedEventLink,

    pub fn deinit(self: *EventLinkList, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Store = struct {
    db: ?*sqlite.sqlite3,

    /// Opens the legacy file-backed plaintext repository only after validating
    /// authority minted by the source-selected development-artifact bootstrap.
    /// It is not a production repository factory. The parent directory must
    /// already exist. WAL and a five-second busy timeout are enabled.
    pub fn openDevelopmentPlaintext(
        capability: *const key_custody.DevelopmentPlaintextStorageCapability,
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !Store {
        try key_custody.requireDevelopmentPlaintextStorage(capability);
        if (path.len == 0) return Error.InvalidValue;
        return openInternal(allocator, path, true);
    }

    /// Explicit ephemeral in-memory constructor with the same schema and
    /// foreign-key enforcement as the development plaintext file store.
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
        var flags: c_int = sqlite.SQLITE_OPEN_READWRITE |
            sqlite.SQLITE_OPEN_CREATE |
            sqlite.SQLITE_OPEN_FULLMUTEX;
        if (file_backed) flags |= sqlite.SQLITE_OPEN_NOFOLLOW;
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
        try store.exec("PRAGMA foreign_keys = ON;");
        if (file_backed) try store.exec("PRAGMA journal_mode = WAL;");
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
        if (value < 0 or value > std.math.maxInt(u32)) return Error.SqliteFailure;
        return @intCast(value);
    }

    pub fn foreignKeysEnabled(self: *Store) !bool {
        var statement = try self.prepare("PRAGMA foreign_keys;");
        defer statement.deinit();
        if (try statement.step() != .row) return Error.SqliteFailure;
        return sqlite.sqlite3_column_int(statement.raw, 0) == 1;
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

        // Another process may have completed the migration while this opener
        // was waiting for the write lock. Never replay non-idempotent DDL from
        // the stale pre-lock observation.
        const version = try self.schemaVersion();
        if (version > latest_schema_version) return Error.SchemaTooNew;
        if (version < 1) {
            try self.exec(schema_v1);
            try self.exec("PRAGMA user_version = 1;");
        }
        if (version < 2) {
            try self.exec(migration_v2);
            try self.exec("PRAGMA user_version = 2;");
        }
        if (version < 3) {
            try self.exec(migration_v3);
            try self.exec("PRAGMA user_version = 3;");
        }

        try self.commit();
        committed = true;
    }

    pub fn putOverride(self: *Store, value: OverrideWrite) !i64 {
        try validateOverride(value);

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        const id = try self.writeOverride(value);

        try self.commit();
        committed = true;
        return id;
    }

    /// Writes one validated override inside a transaction the caller owns, so
    /// a whole feed sync commits or rolls back as a unit. Any error leaves the
    /// transaction dirty; the caller must roll back.
    fn writeOverride(self: *Store, value: OverrideWrite) !i64 {
        const id = if (value.id) |existing_id| blk: {
            var update = try self.prepare(
                \\UPDATE calendar_overrides
                \\SET title = ?, source = ?, original_deadline = ?,
                \\    adjusted_deadline = ?, effective_from = ?,
                \\    effective_until = ?, expires_at = ?,
                \\    origin = ?, external_ref = ?,
                \\    updated_at = unixepoch()
                \\WHERE id = ?;
            );
            defer update.deinit();
            try update.bindText(1, value.title);
            try update.bindText(2, value.source);
            try update.bindText(3, value.original_deadline);
            try update.bindText(4, value.adjusted_deadline);
            try update.bindOptionalText(5, value.effective_from);
            try update.bindOptionalText(6, value.effective_until);
            try update.bindOptionalText(7, value.expires_at);
            try update.bindText(8, value.origin.text());
            try update.bindOptionalText(9, value.external_ref);
            try update.bindInt64(10, existing_id);
            try update.expectDone();
            if (sqlite.sqlite3_changes(try self.handle()) == 0) return Error.NotFound;

            var clear = try self.prepare(
                "DELETE FROM calendar_override_forms WHERE override_id = ?;",
            );
            defer clear.deinit();
            try clear.bindInt64(1, existing_id);
            try clear.expectDone();

            var clear_regions = try self.prepare(
                "DELETE FROM calendar_override_regions WHERE override_id = ?;",
            );
            defer clear_regions.deinit();
            try clear_regions.bindInt64(1, existing_id);
            try clear_regions.expectDone();

            var clear_taxpayer_types = try self.prepare(
                \\DELETE FROM calendar_override_taxpayer_types
                \\WHERE override_id = ?;
            );
            defer clear_taxpayer_types.deinit();
            try clear_taxpayer_types.bindInt64(1, existing_id);
            try clear_taxpayer_types.expectDone();
            break :blk existing_id;
        } else blk: {
            var insert = try self.prepare(
                \\INSERT INTO calendar_overrides (
                \\    title, source, original_deadline, adjusted_deadline,
                \\    effective_from, effective_until, expires_at,
                \\    origin, external_ref
                \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            );
            defer insert.deinit();
            try insert.bindText(1, value.title);
            try insert.bindText(2, value.source);
            try insert.bindText(3, value.original_deadline);
            try insert.bindText(4, value.adjusted_deadline);
            try insert.bindOptionalText(5, value.effective_from);
            try insert.bindOptionalText(6, value.effective_until);
            try insert.bindOptionalText(7, value.expires_at);
            try insert.bindText(8, value.origin.text());
            try insert.bindOptionalText(9, value.external_ref);
            try insert.expectDone();
            break :blk sqlite.sqlite3_last_insert_rowid(try self.handle());
        };

        var add_form = try self.prepare(
            \\INSERT INTO calendar_override_forms (override_id, form_code)
            \\VALUES (?, ?);
        );
        defer add_form.deinit();
        for (value.affected_form_codes) |form_code| {
            try add_form.bindInt64(1, id);
            try add_form.bindText(2, form_code);
            try add_form.expectDone();
            try add_form.reset();
        }

        var add_region = try self.prepare(
            \\INSERT INTO calendar_override_regions (override_id, region)
            \\VALUES (?, ?);
        );
        defer add_region.deinit();
        for (value.regions) |region| {
            try add_region.bindInt64(1, id);
            try add_region.bindText(2, region);
            try add_region.expectDone();
            try add_region.reset();
        }

        var add_taxpayer_type = try self.prepare(
            \\INSERT INTO calendar_override_taxpayer_types (
            \\    override_id, taxpayer_type
            \\) VALUES (?, ?);
        );
        defer add_taxpayer_type.deinit();
        for (value.taxpayer_types) |taxpayer_type| {
            try add_taxpayer_type.bindInt64(1, id);
            try add_taxpayer_type.bindText(2, taxpayer_type);
            try add_taxpayer_type.expectDone();
            try add_taxpayer_type.reset();
        }

        return id;
    }

    pub fn getOverride(
        self: *Store,
        allocator: std.mem.Allocator,
        id: i64,
    ) !?OwnedOverride {
        var statement = try self.prepare(
            \\SELECT id, title, source, original_deadline, adjusted_deadline,
            \\       effective_from, effective_until, expires_at,
            \\       origin, external_ref
            \\FROM calendar_overrides
            \\WHERE id = ?;
        );
        defer statement.deinit();
        try statement.bindInt64(1, id);
        return switch (try statement.step()) {
            .done => null,
            .row => try self.readOverride(allocator, statement.raw),
        };
    }

    pub fn listOverrides(
        self: *Store,
        allocator: std.mem.Allocator,
    ) !OverrideList {
        var statement = try self.prepare(
            \\SELECT id, title, source, original_deadline, adjusted_deadline,
            \\       effective_from, effective_until, expires_at,
            \\       origin, external_ref
            \\FROM calendar_overrides
            \\ORDER BY id;
        );
        defer statement.deinit();

        var items: std.ArrayList(OwnedOverride) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const item = try self.readOverride(allocator, statement.raw);
            errdefer {
                var owned = item;
                owned.deinit(allocator);
            }
            try items.append(allocator, item);
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    pub fn deleteOverride(self: *Store, id: i64) !bool {
        var statement = try self.prepare(
            "DELETE FROM calendar_overrides WHERE id = ?;",
        );
        defer statement.deinit();
        try statement.bindInt64(1, id);
        try statement.expectDone();
        return sqlite.sqlite3_changes(try self.handle()) != 0;
    }

    /// Resolves a feed identity to the synced row it owns. Manual rows are
    /// excluded by the `origin` predicate as well as by their null reference,
    /// so a hand-edited database cannot hand a user's row to the sync.
    pub fn getOverrideIdByExternalRef(
        self: *Store,
        external_ref: []const u8,
    ) !?i64 {
        var statement = try self.prepare(
            \\SELECT id FROM calendar_overrides
            \\WHERE external_ref = ? AND origin = 'synced';
        );
        defer statement.deinit();
        try statement.bindText(1, external_ref);
        return switch (try statement.step()) {
            .done => null,
            .row => sqlite.sqlite3_column_int64(statement.raw, 0),
        };
    }

    pub fn isDismissed(self: *Store, external_ref: []const u8) !bool {
        var statement = try self.prepare(
            \\SELECT 1 FROM calendar_override_dismissals
            \\WHERE external_ref = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, external_ref);
        return try statement.step() == .row;
    }

    /// Removes a synced override and tombstones its feed identity in one
    /// transaction, so a later sync cannot resurrect what the user dismissed.
    /// Manual rows are not dismissible — delete them with `deleteOverride`.
    pub fn dismissSyncedOverride(self: *Store, id: i64) !void {
        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        var reference_buffer: [max_external_ref_bytes]u8 = undefined;
        const external_ref = try self.syncedExternalRef(id, &reference_buffer);

        var tombstone = try self.prepare(
            \\INSERT INTO calendar_override_dismissals (external_ref)
            \\VALUES (?)
            \\ON CONFLICT(external_ref) DO NOTHING;
        );
        defer tombstone.deinit();
        try tombstone.bindText(1, external_ref);
        try tombstone.expectDone();

        var delete = try self.prepare(
            "DELETE FROM calendar_overrides WHERE id = ?;",
        );
        defer delete.deinit();
        try delete.bindInt64(1, id);
        try delete.expectDone();
        if (sqlite.sqlite3_changes(try self.handle()) == 0) return Error.NotFound;

        try self.commit();
        committed = true;
    }

    /// Projects the current feed's override records onto the synced rows in one
    /// transaction. Synced rows missing from `records` are kept: a feed rolls
    /// off long before the deadline history it announced stops mattering.
    pub fn syncOverridesFromFeed(
        self: *Store,
        records: []const FeedOverrideRecord,
    ) !SyncSummary {
        if (records.len > max_sync_records) return Error.BatchTooLarge;

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        var summary = SyncSummary{};
        for (records) |record| {
            const write = OverrideWrite{
                .title = record.title,
                .source = record.source_reference,
                .original_deadline = record.original_deadline,
                .adjusted_deadline = record.adjusted_deadline,
                .affected_form_codes = record.form_codes,
                .regions = record.rdo_codes,
                .origin = .synced,
                .external_ref = record.external_ref,
            };
            // One unusable record must not cost the operator the rest of the
            // feed; storage failures still abort, because they leave the
            // transaction dirty.
            validateOverride(write) catch {
                summary.rejected += 1;
                continue;
            };
            if (try self.isDismissed(record.external_ref)) {
                summary.skipped_dismissed += 1;
                continue;
            }
            if (try self.getOverrideIdByExternalRef(record.external_ref)) |id| {
                var update = write;
                update.id = id;
                _ = try self.writeOverride(update);
                summary.updated += 1;
            } else {
                _ = try self.writeOverride(write);
                summary.inserted += 1;
            }
        }

        try self.commit();
        committed = true;
        return summary;
    }

    fn syncedExternalRef(
        self: *Store,
        id: i64,
        buffer: []u8,
    ) ![]const u8 {
        var statement = try self.prepare(
            \\SELECT external_ref FROM calendar_overrides
            \\WHERE id = ? AND origin = 'synced' AND external_ref IS NOT NULL;
        );
        defer statement.deinit();
        try statement.bindInt64(1, id);
        if (try statement.step() != .row) return Error.NotFound;
        const stored = columnText(statement.raw, 0) orelse
            return Error.SqliteFailure;
        if (stored.len > buffer.len) return Error.SqliteFailure;
        @memcpy(buffer[0..stored.len], stored);
        return buffer[0..stored.len];
    }

    pub fn putNonWorkingDay(self: *Store, value: NonWorkingDayWrite) !i64 {
        try validateNonWorkingDay(value);

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        const id = if (value.id) |existing_id| blk: {
            var update = try self.prepare(
                \\UPDATE calendar_non_working_days
                \\SET day = ?, name = ?, kind = ?, source = ?,
                \\    updated_at = unixepoch()
                \\WHERE id = ?;
            );
            defer update.deinit();
            try update.bindText(1, value.day);
            try update.bindText(2, value.name);
            try update.bindText(3, value.kind);
            try update.bindText(4, value.source);
            try update.bindInt64(5, existing_id);
            try update.expectDone();
            if (sqlite.sqlite3_changes(try self.handle()) == 0) return Error.NotFound;

            var clear = try self.prepare(
                \\DELETE FROM calendar_non_working_day_regions
                \\WHERE non_working_day_id = ?;
            );
            defer clear.deinit();
            try clear.bindInt64(1, existing_id);
            try clear.expectDone();
            break :blk existing_id;
        } else blk: {
            var insert = try self.prepare(
                \\INSERT INTO calendar_non_working_days (day, name, kind, source)
                \\VALUES (?, ?, ?, ?);
            );
            defer insert.deinit();
            try insert.bindText(1, value.day);
            try insert.bindText(2, value.name);
            try insert.bindText(3, value.kind);
            try insert.bindText(4, value.source);
            try insert.expectDone();
            break :blk sqlite.sqlite3_last_insert_rowid(try self.handle());
        };

        var add_region = try self.prepare(
            \\INSERT INTO calendar_non_working_day_regions (
            \\    non_working_day_id, region
            \\) VALUES (?, ?);
        );
        defer add_region.deinit();
        for (value.regions) |region| {
            try add_region.bindInt64(1, id);
            try add_region.bindText(2, region);
            try add_region.expectDone();
            try add_region.reset();
        }

        try self.commit();
        committed = true;
        return id;
    }

    pub fn getNonWorkingDay(
        self: *Store,
        allocator: std.mem.Allocator,
        id: i64,
    ) !?OwnedNonWorkingDay {
        var statement = try self.prepare(
            \\SELECT id, day, name, kind, source
            \\FROM calendar_non_working_days
            \\WHERE id = ?;
        );
        defer statement.deinit();
        try statement.bindInt64(1, id);
        return switch (try statement.step()) {
            .done => null,
            .row => try self.readNonWorkingDay(allocator, statement.raw),
        };
    }

    pub fn listNonWorkingDays(
        self: *Store,
        allocator: std.mem.Allocator,
    ) !NonWorkingDayList {
        var statement = try self.prepare(
            \\SELECT id, day, name, kind, source
            \\FROM calendar_non_working_days
            \\ORDER BY day, name COLLATE NOCASE, id;
        );
        defer statement.deinit();

        var items: std.ArrayList(OwnedNonWorkingDay) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const item = try self.readNonWorkingDay(allocator, statement.raw);
            errdefer {
                var owned = item;
                owned.deinit(allocator);
            }
            try items.append(allocator, item);
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    pub fn deleteNonWorkingDay(self: *Store, id: i64) !bool {
        var statement = try self.prepare(
            "DELETE FROM calendar_non_working_days WHERE id = ?;",
        );
        defer statement.deinit();
        try statement.bindInt64(1, id);
        try statement.expectDone();
        return sqlite.sqlite3_changes(try self.handle()) != 0;
    }

    /// Upserts one provider/profile connection and returns its stable row ID.
    pub fn putConnection(self: *Store, value: ConnectionWrite) !i64 {
        try validateConnection(value);
        var statement = try self.prepare(
            \\INSERT INTO calendar_connections (
            \\    provider, profile_key, external_calendar_id, calendar_name,
            \\    enabled, last_synced_at, last_error
            \\) VALUES (?, ?, ?, ?, ?, ?, ?)
            \\ON CONFLICT(provider, profile_key) DO UPDATE SET
            \\    external_calendar_id = excluded.external_calendar_id,
            \\    calendar_name = excluded.calendar_name,
            \\    enabled = excluded.enabled,
            \\    last_synced_at = excluded.last_synced_at,
            \\    last_error = excluded.last_error,
            \\    updated_at = unixepoch()
            \\RETURNING id;
        );
        defer statement.deinit();
        try statement.bindText(1, value.provider);
        try statement.bindText(2, value.profile_key);
        try statement.bindText(3, value.external_calendar_id);
        try statement.bindOptionalText(4, value.calendar_name);
        try statement.bindBool(5, value.enabled);
        try statement.bindOptionalText(6, value.last_synced_at);
        try statement.bindOptionalText(7, value.last_error);
        if (try statement.step() != .row) return Error.SqliteFailure;
        const id = sqlite.sqlite3_column_int64(statement.raw, 0);
        if (try statement.step() != .done) return Error.SqliteFailure;
        return id;
    }

    pub fn getConnection(
        self: *Store,
        allocator: std.mem.Allocator,
        provider: []const u8,
        profile_key: []const u8,
    ) !?OwnedConnection {
        var statement = try self.prepare(
            \\SELECT id, provider, profile_key, external_calendar_id,
            \\       calendar_name, enabled, last_synced_at, last_error
            \\FROM calendar_connections
            \\WHERE provider = ? AND profile_key = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, provider);
        try statement.bindText(2, profile_key);
        return switch (try statement.step()) {
            .done => null,
            .row => try readConnection(allocator, statement.raw),
        };
    }

    pub fn listConnections(
        self: *Store,
        allocator: std.mem.Allocator,
    ) !ConnectionList {
        var statement = try self.prepare(
            \\SELECT id, provider, profile_key, external_calendar_id,
            \\       calendar_name, enabled, last_synced_at, last_error
            \\FROM calendar_connections
            \\ORDER BY provider COLLATE NOCASE, profile_key COLLATE NOCASE, id;
        );
        defer statement.deinit();

        var items: std.ArrayList(OwnedConnection) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const item = try readConnection(allocator, statement.raw);
            errdefer {
                var owned = item;
                owned.deinit(allocator);
            }
            try items.append(allocator, item);
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    pub fn deleteConnection(
        self: *Store,
        provider: []const u8,
        profile_key: []const u8,
    ) !bool {
        var statement = try self.prepare(
            \\DELETE FROM calendar_connections
            \\WHERE provider = ? AND profile_key = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, provider);
        try statement.bindText(2, profile_key);
        try statement.expectDone();
        return sqlite.sqlite3_changes(try self.handle()) != 0;
    }

    /// Upserts a managed external-event mapping. Its provider/profile must
    /// already have a connection, which makes connection deletion cascade.
    pub fn putEventLink(self: *Store, value: EventLinkWrite) !void {
        try validateEventLink(value);
        var statement = try self.prepare(
            \\INSERT INTO calendar_event_links (
            \\    provider, profile_key, obligation_key, external_event_id,
            \\    external_ical_uid, series_id, occurrence_id, revision,
            \\    fingerprint, created_by_backend
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            \\ON CONFLICT(provider, profile_key, obligation_key) DO UPDATE SET
            \\    external_event_id = excluded.external_event_id,
            \\    external_ical_uid = excluded.external_ical_uid,
            \\    series_id = excluded.series_id,
            \\    occurrence_id = excluded.occurrence_id,
            \\    revision = excluded.revision,
            \\    fingerprint = excluded.fingerprint,
            \\    created_by_backend = excluded.created_by_backend,
            \\    updated_at = unixepoch();
        );
        defer statement.deinit();
        try statement.bindText(1, value.provider);
        try statement.bindText(2, value.profile_key);
        try statement.bindText(3, value.obligation_key);
        try statement.bindText(4, value.external_event_id);
        try statement.bindOptionalText(5, value.external_ical_uid);
        try statement.bindOptionalText(6, value.series_id);
        try statement.bindOptionalText(7, value.occurrence_id);
        try statement.bindOptionalText(8, value.revision);
        try statement.bindText(9, value.fingerprint);
        try statement.bindBool(10, value.created_by_backend);
        try statement.expectDone();
    }

    pub fn getEventLink(
        self: *Store,
        allocator: std.mem.Allocator,
        provider: []const u8,
        profile_key: []const u8,
        obligation_key: []const u8,
    ) !?OwnedEventLink {
        var statement = try self.prepare(
            \\SELECT provider, profile_key, obligation_key, external_event_id,
            \\       external_ical_uid, series_id, occurrence_id, revision,
            \\       fingerprint, created_by_backend
            \\FROM calendar_event_links
            \\WHERE provider = ? AND profile_key = ? AND obligation_key = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, provider);
        try statement.bindText(2, profile_key);
        try statement.bindText(3, obligation_key);
        return switch (try statement.step()) {
            .done => null,
            .row => try readEventLink(allocator, statement.raw),
        };
    }

    pub fn listEventLinks(
        self: *Store,
        allocator: std.mem.Allocator,
        provider: []const u8,
        profile_key: []const u8,
    ) !EventLinkList {
        var statement = try self.prepare(
            \\SELECT provider, profile_key, obligation_key, external_event_id,
            \\       external_ical_uid, series_id, occurrence_id, revision,
            \\       fingerprint, created_by_backend
            \\FROM calendar_event_links
            \\WHERE provider = ? AND profile_key = ?
            \\ORDER BY obligation_key;
        );
        defer statement.deinit();
        try statement.bindText(1, provider);
        try statement.bindText(2, profile_key);

        var items: std.ArrayList(OwnedEventLink) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const item = try readEventLink(allocator, statement.raw);
            errdefer {
                var owned = item;
                owned.deinit(allocator);
            }
            try items.append(allocator, item);
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    pub fn deleteEventLink(
        self: *Store,
        provider: []const u8,
        profile_key: []const u8,
        obligation_key: []const u8,
    ) !bool {
        var statement = try self.prepare(
            \\DELETE FROM calendar_event_links
            \\WHERE provider = ? AND profile_key = ? AND obligation_key = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, provider);
        try statement.bindText(2, profile_key);
        try statement.bindText(3, obligation_key);
        try statement.expectDone();
        return sqlite.sqlite3_changes(try self.handle()) != 0;
    }

    fn readOverride(
        self: *Store,
        allocator: std.mem.Allocator,
        row: *sqlite.sqlite3_stmt,
    ) !OwnedOverride {
        const id = sqlite.sqlite3_column_int64(row, 0);
        const title = try dupColumn(allocator, row, 1);
        errdefer allocator.free(title);
        const source = try dupColumn(allocator, row, 2);
        errdefer allocator.free(source);
        const original_deadline = try dupColumn(allocator, row, 3);
        errdefer allocator.free(original_deadline);
        const adjusted_deadline = try dupColumn(allocator, row, 4);
        errdefer allocator.free(adjusted_deadline);
        const effective_from = try dupOptionalColumn(allocator, row, 5);
        errdefer freeOptional(allocator, effective_from);
        const effective_until = try dupOptionalColumn(allocator, row, 6);
        errdefer freeOptional(allocator, effective_until);
        const expires_at = try dupOptionalColumn(allocator, row, 7);
        errdefer freeOptional(allocator, expires_at);
        const origin = try Origin.parse(
            columnText(row, 8) orelse return Error.SqliteFailure,
        );
        const external_ref = try dupOptionalColumn(allocator, row, 9);
        errdefer freeOptional(allocator, external_ref);
        const forms = try self.loadStrings(
            allocator,
            "SELECT form_code FROM calendar_override_forms WHERE override_id = ? ORDER BY form_code COLLATE NOCASE;",
            id,
        );
        errdefer freeStrings(allocator, forms);
        const regions = try self.loadStrings(
            allocator,
            "SELECT region FROM calendar_override_regions WHERE override_id = ? ORDER BY region COLLATE NOCASE;",
            id,
        );
        errdefer freeStrings(allocator, regions);
        const taxpayer_types = try self.loadStrings(
            allocator,
            "SELECT taxpayer_type FROM calendar_override_taxpayer_types WHERE override_id = ? ORDER BY taxpayer_type COLLATE NOCASE;",
            id,
        );
        errdefer freeStrings(allocator, taxpayer_types);

        return .{
            .id = id,
            .title = title,
            .source = source,
            .original_deadline = original_deadline,
            .adjusted_deadline = adjusted_deadline,
            .effective_from = effective_from,
            .effective_until = effective_until,
            .expires_at = expires_at,
            .affected_form_codes = forms,
            .regions = regions,
            .taxpayer_types = taxpayer_types,
            .origin = origin,
            .external_ref = external_ref,
        };
    }

    fn readNonWorkingDay(
        self: *Store,
        allocator: std.mem.Allocator,
        row: *sqlite.sqlite3_stmt,
    ) !OwnedNonWorkingDay {
        const id = sqlite.sqlite3_column_int64(row, 0);
        const day = try dupColumn(allocator, row, 1);
        errdefer allocator.free(day);
        const name = try dupColumn(allocator, row, 2);
        errdefer allocator.free(name);
        const kind = try dupColumn(allocator, row, 3);
        errdefer allocator.free(kind);
        const source = try dupColumn(allocator, row, 4);
        errdefer allocator.free(source);
        const regions = try self.loadStrings(
            allocator,
            "SELECT region FROM calendar_non_working_day_regions WHERE non_working_day_id = ? ORDER BY region COLLATE NOCASE;",
            id,
        );
        errdefer freeStrings(allocator, regions);

        return .{
            .id = id,
            .day = day,
            .name = name,
            .kind = kind,
            .source = source,
            .regions = regions,
        };
    }

    fn loadStrings(
        self: *Store,
        allocator: std.mem.Allocator,
        sql_text: []const u8,
        id: i64,
    ) ![][]u8 {
        var statement = try self.prepare(sql_text);
        defer statement.deinit();
        try statement.bindInt64(1, id);

        var values: std.ArrayList([]u8) = .empty;
        errdefer {
            for (values.items) |value| allocator.free(value);
            values.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const value = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(value);
            try values.append(allocator, value);
        }
        return values.toOwnedSlice(allocator);
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
        return .{ .db = db, .raw = raw.? };
    }

    fn handle(self: *Store) Error!*sqlite.sqlite3 {
        return self.db orelse Error.Closed;
    }
};

const StepResult = enum { row, done };

const Statement = struct {
    db: *sqlite.sqlite3,
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
        const rc = sqlite.sqlite3_bind_null(self.raw, index);
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn bindInt64(self: *Statement, index: c_int, value: i64) !void {
        const rc = sqlite.sqlite3_bind_int64(self.raw, index, value);
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn bindBool(self: *Statement, index: c_int, value: bool) !void {
        const rc = sqlite.sqlite3_bind_int(
            self.raw,
            index,
            @intFromBool(value),
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

    fn reset(self: *Statement) !void {
        const rc = sqlite.sqlite3_reset(self.raw);
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
        if (sqlite.sqlite3_clear_bindings(self.raw) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }
};

fn readConnection(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
) !OwnedConnection {
    const provider = try dupColumn(allocator, row, 1);
    errdefer allocator.free(provider);
    const profile_key = try dupColumn(allocator, row, 2);
    errdefer allocator.free(profile_key);
    const external_calendar_id = try dupColumn(allocator, row, 3);
    errdefer allocator.free(external_calendar_id);
    const calendar_name = try dupOptionalColumn(allocator, row, 4);
    errdefer freeOptional(allocator, calendar_name);
    const last_synced_at = try dupOptionalColumn(allocator, row, 6);
    errdefer freeOptional(allocator, last_synced_at);
    const last_error = try dupOptionalColumn(allocator, row, 7);
    errdefer freeOptional(allocator, last_error);

    return .{
        .id = sqlite.sqlite3_column_int64(row, 0),
        .provider = provider,
        .profile_key = profile_key,
        .external_calendar_id = external_calendar_id,
        .calendar_name = calendar_name,
        .enabled = sqlite.sqlite3_column_int(row, 5) != 0,
        .last_synced_at = last_synced_at,
        .last_error = last_error,
    };
}

fn readEventLink(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
) !OwnedEventLink {
    const provider = try dupColumn(allocator, row, 0);
    errdefer allocator.free(provider);
    const profile_key = try dupColumn(allocator, row, 1);
    errdefer allocator.free(profile_key);
    const obligation_key = try dupColumn(allocator, row, 2);
    errdefer allocator.free(obligation_key);
    const external_event_id = try dupColumn(allocator, row, 3);
    errdefer allocator.free(external_event_id);
    const external_ical_uid = try dupOptionalColumn(allocator, row, 4);
    errdefer freeOptional(allocator, external_ical_uid);
    const series_id = try dupOptionalColumn(allocator, row, 5);
    errdefer freeOptional(allocator, series_id);
    const occurrence_id = try dupOptionalColumn(allocator, row, 6);
    errdefer freeOptional(allocator, occurrence_id);
    const revision = try dupOptionalColumn(allocator, row, 7);
    errdefer freeOptional(allocator, revision);
    const fingerprint = try dupColumn(allocator, row, 8);
    errdefer allocator.free(fingerprint);

    return .{
        .provider = provider,
        .profile_key = profile_key,
        .obligation_key = obligation_key,
        .external_event_id = external_event_id,
        .external_ical_uid = external_ical_uid,
        .series_id = series_id,
        .occurrence_id = occurrence_id,
        .revision = revision,
        .fingerprint = fingerprint,
        .created_by_backend = sqlite.sqlite3_column_int(row, 9) != 0,
    };
}

fn dupColumn(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) ![]u8 {
    const text = columnText(row, column) orelse return Error.SqliteFailure;
    return allocator.dupe(u8, text);
}

fn dupOptionalColumn(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) !?[]u8 {
    if (sqlite.sqlite3_column_type(row, column) == sqlite.SQLITE_NULL) return null;
    return try dupColumn(allocator, row, column);
}

fn columnText(row: *sqlite.sqlite3_stmt, column: c_int) ?[]const u8 {
    const raw = sqlite.sqlite3_column_text(row, column) orelse return null;
    const length = sqlite.sqlite3_column_bytes(row, column);
    if (length < 0) return null;
    const bytes: [*]const u8 = @ptrCast(raw);
    return bytes[0..@intCast(length)];
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]u8) void {
    if (value) |bytes| allocator.free(bytes);
}

fn freeStrings(allocator: std.mem.Allocator, values: [][]u8) void {
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

fn mapResult(rc: c_int) Error {
    const primary = rc & 0xff;
    return switch (primary) {
        sqlite.SQLITE_BUSY, sqlite.SQLITE_LOCKED => Error.SqliteBusy,
        sqlite.SQLITE_CONSTRAINT => Error.SqliteConstraint,
        else => Error.SqliteFailure,
    };
}

fn validateOverride(value: OverrideWrite) Error!void {
    try requireValue(value.title);
    try requireSource(value.source);
    try validateDate(value.original_deadline);
    try validateDate(value.adjusted_deadline);
    if (value.effective_from) |date| try validateDate(date);
    if (value.effective_until) |date| try validateDate(date);
    if (value.expires_at) |date| try validateDate(date);
    if (value.effective_from != null and value.effective_until != null and
        std.mem.order(
            u8,
            value.effective_from.?,
            value.effective_until.?,
        ) == .gt)
    {
        return Error.InvalidDate;
    }
    if (value.effective_from != null and value.expires_at != null and
        std.mem.order(u8, value.effective_from.?, value.expires_at.?) == .gt)
    {
        return Error.InvalidDate;
    }
    if (value.affected_form_codes.len == 0) {
        return Error.AffectedFormRequired;
    }
    for (value.affected_form_codes) |form_code| try requireValue(form_code);
    for (value.regions) |region| try requireScopeValue(region);
    for (value.taxpayer_types) |taxpayer_type| {
        try requireScopeValue(taxpayer_type);
    }
    // Provenance and feed identity travel together. A synced row without a
    // reference could never be re-synced or dismissed, and a manual row
    // carrying one would be captured by the next sync of that identity.
    switch (value.origin) {
        .manual => if (value.external_ref != null) return Error.InvalidValue,
        .synced => try requireExternalRef(
            value.external_ref orelse return Error.ExternalRefRequired,
        ),
    }
}

fn validateNonWorkingDay(value: NonWorkingDayWrite) Error!void {
    try validateDate(value.day);
    try requireValue(value.name);
    try requireValue(value.kind);
    try requireSource(value.source);
    if (value.regions.len == 0 and
        (std.ascii.eqlIgnoreCase(value.kind, "local") or
            std.ascii.eqlIgnoreCase(value.kind, "local_holiday")))
    {
        return Error.InvalidValue;
    }
    for (value.regions) |region| try requireScopeValue(region);
}

fn validateConnection(value: ConnectionWrite) Error!void {
    try requireValue(value.provider);
    try requireValue(value.profile_key);
    try requireValue(value.external_calendar_id);
    if (value.calendar_name) |name| try requireValue(name);
}

fn validateEventLink(value: EventLinkWrite) Error!void {
    try requireValue(value.provider);
    try requireValue(value.profile_key);
    try requireValue(value.obligation_key);
    try requireValue(value.external_event_id);
    try requireValue(value.fingerprint);
    if (value.external_ical_uid) |uid| try requireValue(uid);
    if (value.series_id) |series| try requireValue(series);
    if (value.occurrence_id) |occurrence| try requireValue(occurrence);
    if (value.revision) |revision| try requireValue(revision);
}

fn requireSource(value: []const u8) Error!void {
    if (trimmed(value).len == 0) return Error.SourceRequired;
}

fn requireValue(value: []const u8) Error!void {
    if (trimmed(value).len == 0) return Error.InvalidValue;
}

fn requireExternalRef(value: []const u8) Error!void {
    const text = trimmed(value);
    if (text.len == 0) return Error.ExternalRefRequired;
    if (text.len > max_external_ref_bytes) return Error.InvalidValue;
}

fn requireScopeValue(value: []const u8) Error!void {
    try requireValue(value);
    if (trimmed(value).len > max_scope_text_bytes) {
        return Error.InvalidValue;
    }
}

fn trimmed(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn validateDate(value: []const u8) Error!void {
    if (value.len != 10 or value[4] != '-' or value[7] != '-') {
        return Error.InvalidDate;
    }
    for (value, 0..) |byte, index| {
        if (index == 4 or index == 7) continue;
        if (!std.ascii.isDigit(byte)) return Error.InvalidDate;
    }
    const year = parseDigits(value[0..4]);
    const month = parseDigits(value[5..7]);
    const day = parseDigits(value[8..10]);
    if (year == 0 or month < 1 or month > 12) return Error.InvalidDate;
    const month_days = [_]u8{
        31,
        if (isLeapYear(year)) 29 else 28,
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    };
    if (day < 1 or day > month_days[month - 1]) return Error.InvalidDate;
}

fn parseDigits(value: []const u8) u16 {
    var result: u16 = 0;
    for (value) |byte| result = result * 10 + (byte - '0');
    return result;
}

fn isLeapYear(year: u16) bool {
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
}

const schema_v1 =
    \\CREATE TABLE calendar_overrides (
    \\    id INTEGER PRIMARY KEY,
    \\    title TEXT NOT NULL CHECK (length(trim(title)) > 0),
    \\    source TEXT NOT NULL CHECK (length(trim(source)) > 0),
    \\    original_deadline TEXT NOT NULL,
    \\    adjusted_deadline TEXT NOT NULL,
    \\    effective_from TEXT,
    \\    expires_on TEXT,
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    CHECK (effective_from IS NULL OR expires_on IS NULL OR effective_from <= expires_on)
    \\);
    \\CREATE INDEX calendar_overrides_deadline_idx
    \\    ON calendar_overrides(adjusted_deadline, id);
    \\
    \\CREATE TABLE calendar_override_forms (
    \\    override_id INTEGER NOT NULL
    \\        REFERENCES calendar_overrides(id) ON DELETE CASCADE,
    \\    form_code TEXT NOT NULL COLLATE NOCASE
    \\        CHECK (length(trim(form_code)) > 0),
    \\    PRIMARY KEY (override_id, form_code)
    \\);
    \\CREATE INDEX calendar_override_forms_code_idx
    \\    ON calendar_override_forms(form_code, override_id);
    \\
    \\CREATE TABLE calendar_override_regions (
    \\    override_id INTEGER NOT NULL
    \\        REFERENCES calendar_overrides(id) ON DELETE CASCADE,
    \\    region TEXT NOT NULL COLLATE NOCASE
    \\        CHECK (length(trim(region)) > 0),
    \\    PRIMARY KEY (override_id, region)
    \\);
    \\CREATE INDEX calendar_override_regions_region_idx
    \\    ON calendar_override_regions(region, override_id);
    \\
    \\CREATE TABLE calendar_override_taxpayer_types (
    \\    override_id INTEGER NOT NULL
    \\        REFERENCES calendar_overrides(id) ON DELETE CASCADE,
    \\    taxpayer_type TEXT NOT NULL COLLATE NOCASE
    \\        CHECK (length(trim(taxpayer_type)) > 0),
    \\    PRIMARY KEY (override_id, taxpayer_type)
    \\);
    \\CREATE INDEX calendar_override_taxpayer_types_type_idx
    \\    ON calendar_override_taxpayer_types(taxpayer_type, override_id);
    \\
    \\CREATE TABLE calendar_non_working_days (
    \\    id INTEGER PRIMARY KEY,
    \\    day TEXT NOT NULL,
    \\    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    \\    kind TEXT NOT NULL CHECK (length(trim(kind)) > 0),
    \\    source TEXT NOT NULL CHECK (length(trim(source)) > 0),
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    UNIQUE (day, name, kind)
    \\);
    \\CREATE INDEX calendar_non_working_days_day_idx
    \\    ON calendar_non_working_days(day, id);
    \\
    \\CREATE TABLE calendar_non_working_day_regions (
    \\    non_working_day_id INTEGER NOT NULL
    \\        REFERENCES calendar_non_working_days(id) ON DELETE CASCADE,
    \\    region TEXT NOT NULL COLLATE NOCASE
    \\        CHECK (length(trim(region)) > 0),
    \\    PRIMARY KEY (non_working_day_id, region)
    \\);
    \\
    \\CREATE TABLE calendar_connections (
    \\    id INTEGER PRIMARY KEY,
    \\    provider TEXT NOT NULL CHECK (length(trim(provider)) > 0),
    \\    profile_key TEXT NOT NULL CHECK (length(trim(profile_key)) > 0),
    \\    external_calendar_id TEXT NOT NULL
    \\        CHECK (length(trim(external_calendar_id)) > 0),
    \\    calendar_name TEXT,
    \\    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
    \\    last_synced_at TEXT,
    \\    last_error TEXT,
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    UNIQUE (provider, profile_key)
    \\);
    \\CREATE INDEX calendar_connections_enabled_idx
    \\    ON calendar_connections(provider, enabled, profile_key);
    \\
    \\CREATE TABLE calendar_event_links (
    \\    provider TEXT NOT NULL,
    \\    profile_key TEXT NOT NULL,
    \\    obligation_key TEXT NOT NULL
    \\        CHECK (length(trim(obligation_key)) > 0),
    \\    external_event_id TEXT NOT NULL
    \\        CHECK (length(trim(external_event_id)) > 0),
    \\    external_ical_uid TEXT,
    \\    series_id TEXT,
    \\    occurrence_id TEXT,
    \\    revision TEXT,
    \\    fingerprint TEXT NOT NULL CHECK (length(trim(fingerprint)) > 0),
    \\    created_by_backend INTEGER NOT NULL DEFAULT 1
    \\        CHECK (created_by_backend IN (0, 1)),
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (provider, profile_key, obligation_key),
    \\    UNIQUE (provider, profile_key, external_event_id),
    \\    FOREIGN KEY (provider, profile_key)
    \\        REFERENCES calendar_connections(provider, profile_key)
    \\        ON UPDATE CASCADE ON DELETE CASCADE
    \\);
    \\CREATE INDEX calendar_event_links_fingerprint_idx
    \\    ON calendar_event_links(provider, profile_key, fingerprint);
;

/// v1 exposed this value to users as "Expires on" and mapped it to the
/// reference model's expiry field. Preserve that meaning, then add the
/// previously unrepresentable effective-range end.
const migration_v2 =
    \\ALTER TABLE calendar_overrides
    \\    RENAME COLUMN expires_on TO expires_at;
    \\ALTER TABLE calendar_overrides
    \\    ADD COLUMN effective_until TEXT;
    \\CREATE TRIGGER calendar_overrides_effective_range_insert
    \\BEFORE INSERT ON calendar_overrides
    \\WHEN NEW.effective_from IS NOT NULL
    \\    AND NEW.effective_until IS NOT NULL
    \\    AND NEW.effective_from > NEW.effective_until
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'invalid override effective range');
    \\END;
    \\CREATE TRIGGER calendar_overrides_effective_range_update
    \\BEFORE UPDATE OF effective_from, effective_until ON calendar_overrides
    \\WHEN NEW.effective_from IS NOT NULL
    \\    AND NEW.effective_until IS NOT NULL
    \\    AND NEW.effective_from > NEW.effective_until
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'invalid override effective range');
    \\END;
;

/// v2 rows are all user-authored, so the backfilled provenance is `manual`
/// with no feed identity. The partial unique index is what makes a re-sync an
/// update instead of a duplicate; the tombstone table outlives the row it
/// dismisses, which is the only way a dismissal survives the next feed.
const migration_v3 =
    \\ALTER TABLE calendar_overrides
    \\    ADD COLUMN origin TEXT NOT NULL DEFAULT 'manual'
    \\        CHECK (origin IN ('manual','synced'));
    \\ALTER TABLE calendar_overrides
    \\    ADD COLUMN external_ref TEXT
    \\        CHECK (external_ref IS NULL OR length(trim(external_ref)) > 0);
    \\CREATE UNIQUE INDEX calendar_overrides_external_ref_idx
    \\    ON calendar_overrides(external_ref) WHERE external_ref IS NOT NULL;
    \\CREATE TABLE calendar_override_dismissals (
    \\    external_ref TEXT PRIMARY KEY CHECK (length(trim(external_ref)) > 0),
    \\    dismissed_at INTEGER NOT NULL DEFAULT (unixepoch())
    \\);
;

test "migration is idempotent and enables foreign keys" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
    try std.testing.expect(try store.foreignKeysEnabled());
    try store.migrate();
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
}

test "stale pre-lock migration observation does not replay DDL" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
    // Models a second process that observed v1, then waited while the first
    // process completed v2. The locked re-read must turn this into a no-op.
    try store.migrateFromObservedVersion(1);
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
    try std.testing.expect(try tableHasColumn(&store, "effective_until"));
    try std.testing.expect(try tableHasColumn(&store, "expires_at"));
}

test "v2 migration preserves v1 expiry without rebuilding" {
    const allocator = std.testing.allocator;
    var raw: ?*sqlite.sqlite3 = null;
    const flags = sqlite.SQLITE_OPEN_READWRITE |
        sqlite.SQLITE_OPEN_CREATE |
        sqlite.SQLITE_OPEN_FULLMUTEX;
    const rc = sqlite.sqlite3_open_v2(":memory:", &raw, flags, null);
    if (rc != sqlite.SQLITE_OK or raw == null) {
        if (raw) |db| _ = sqlite.sqlite3_close_v2(db);
        return Error.SqliteFailure;
    }

    var store = Store{ .db = raw.? };
    defer store.close();
    try store.exec("PRAGMA foreign_keys = ON;");
    try store.exec(schema_v1);
    try store.exec("PRAGMA user_version = 1;");
    try store.exec(
        \\INSERT INTO calendar_overrides (
        \\    id, title, source, original_deadline, adjusted_deadline,
        \\    effective_from, expires_on
        \\) VALUES (
        \\    41, 'Migrated extension', 'RMC migration fixture',
        \\    '2026-05-15', '2026-05-22', '2026-05-01', '2026-05-31'
        \\);
    );
    try store.exec(
        \\INSERT INTO calendar_override_forms (override_id, form_code)
        \\VALUES (41, '1701Q');
    );
    try store.exec(
        \\INSERT INTO calendar_override_regions (override_id, region)
        \\VALUES (41, 'NCR');
    );
    try store.exec(
        \\INSERT INTO calendar_override_taxpayer_types (
        \\    override_id, taxpayer_type
        \\) VALUES (41, 'Individual');
    );

    try std.testing.expectEqual(@as(u32, 1), try store.schemaVersion());
    try store.migrate();
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
    try std.testing.expect(!try tableHasColumn(&store, "expires_on"));
    try std.testing.expect(try tableHasColumn(&store, "effective_until"));
    try std.testing.expect(try tableHasColumn(&store, "expires_at"));

    var migrated = (try store.getOverride(allocator, 41)).?;
    defer migrated.deinit(allocator);
    try std.testing.expectEqualStrings("2026-05-01", migrated.effective_from.?);
    try std.testing.expect(migrated.effective_until == null);
    try std.testing.expectEqualStrings("2026-05-31", migrated.expires_at.?);
    try std.testing.expectEqualStrings("1701Q", migrated.affected_form_codes[0]);
    try std.testing.expectEqualStrings("NCR", migrated.regions[0]);
    try std.testing.expectEqualStrings("Individual", migrated.taxpayer_types[0]);

    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\INSERT INTO calendar_overrides (
            \\    title, source, original_deadline, adjusted_deadline,
            \\    effective_from, effective_until
            \\) VALUES (
            \\    'Invalid range', 'Direct SQL fixture',
            \\    '2026-05-15', '2026-05-22',
            \\    '2026-06-01', '2026-05-01'
            \\);
        ),
    );
}

test "override CRUD preserves ordered scopes and cascades normalized rows" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const quarterly = [_][]const u8{ "1701Q", "1702Q" };
    const annual = [_][]const u8{"1701"};
    const regions = [_][]const u8{ "NCR", "CALABARZON" };
    const taxpayer_types = [_][]const u8{ "Individual", "Corporation" };

    try std.testing.expectError(Error.SourceRequired, store.putOverride(.{
        .title = "Unverified extension",
        .source = " \t",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-05-20",
        .affected_form_codes = &quarterly,
    }));
    try std.testing.expectError(Error.AffectedFormRequired, store.putOverride(.{
        .title = "Missing form scope",
        .source = "RMC 1-2026",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-05-20",
        .affected_form_codes = &.{},
    }));
    try std.testing.expectError(Error.InvalidDate, store.putOverride(.{
        .title = "Inverted effective range",
        .source = "RMC 1-2026",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-05-20",
        .effective_from = "2026-06-01",
        .effective_until = "2026-05-01",
        .affected_form_codes = &quarterly,
    }));
    try std.testing.expectError(Error.InvalidDate, store.putOverride(.{
        .title = "Invalid record expiry",
        .source = "RMC 1-2026",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-05-20",
        .expires_at = "2027-02-29",
        .affected_form_codes = &quarterly,
    }));
    try std.testing.expectError(Error.InvalidDate, store.putOverride(.{
        .title = "Expiry predates effectivity",
        .source = "RMC 1-2026",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-05-20",
        .effective_from = "2026-06-01",
        .expires_at = "2026-05-31",
        .affected_form_codes = &quarterly,
    }));

    const later_id = try store.putOverride(.{
        .title = "Quarterly extension",
        .source = "RMC 2-2026",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-05-22",
        .effective_from = "2026-05-01",
        .effective_until = "2026-05-31",
        .expires_at = "2027-05-31",
        .affected_form_codes = &quarterly,
        .regions = &regions,
        .taxpayer_types = &taxpayer_types,
    });
    const earlier_id = try store.putOverride(.{
        .title = "Annual extension",
        .source = "RMC 1-2026",
        .original_deadline = "2026-04-15",
        .adjusted_deadline = "2026-04-20",
        .affected_form_codes = &annual,
    });

    var list = try store.listOverrides(allocator);
    defer list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    // Preserve insertion order because later matching overrides deliberately
    // win when the calendar resolver applies this list.
    try std.testing.expectEqual(later_id, list.items[0].id);
    try std.testing.expectEqualStrings("1701Q", list.items[0].affected_form_codes[0]);
    try std.testing.expectEqualStrings("1702Q", list.items[0].affected_form_codes[1]);
    try std.testing.expectEqualStrings("CALABARZON", list.items[0].regions[0]);
    try std.testing.expectEqualStrings("NCR", list.items[0].regions[1]);
    try std.testing.expectEqualStrings("Corporation", list.items[0].taxpayer_types[0]);
    try std.testing.expectEqualStrings("Individual", list.items[0].taxpayer_types[1]);
    try std.testing.expectEqualStrings(
        "2026-05-31",
        list.items[0].effective_until.?,
    );
    try std.testing.expectEqualStrings("2027-05-31", list.items[0].expires_at.?);
    try std.testing.expectEqual(earlier_id, list.items[1].id);
    try std.testing.expectEqualStrings("1701", list.items[1].affected_form_codes[0]);
    try std.testing.expectEqual(@as(usize, 0), list.items[1].regions.len);
    try std.testing.expectEqual(@as(usize, 0), list.items[1].taxpayer_types.len);

    const replacement_forms = [_][]const u8{"2550Q"};
    const replacement_regions = [_][]const u8{"NCR"};
    const replacement_taxpayer_types = [_][]const u8{"Non-Individual"};
    _ = try store.putOverride(.{
        .id = later_id,
        .title = "VAT extension",
        .source = "RMC 3-2026",
        .original_deadline = "2026-05-25",
        .adjusted_deadline = "2026-05-29",
        .affected_form_codes = &replacement_forms,
        .regions = &replacement_regions,
        .taxpayer_types = &replacement_taxpayer_types,
    });
    var updated = (try store.getOverride(allocator, later_id)).?;
    defer updated.deinit(allocator);
    try std.testing.expectEqualStrings("VAT extension", updated.title);
    try std.testing.expectEqual(@as(usize, 1), updated.affected_form_codes.len);
    try std.testing.expectEqualStrings("2550Q", updated.affected_form_codes[0]);
    try std.testing.expectEqualStrings("NCR", updated.regions[0]);
    try std.testing.expect(updated.effective_from == null);
    try std.testing.expect(updated.effective_until == null);
    try std.testing.expect(updated.expires_at == null);
    try std.testing.expectEqualStrings(
        "Non-Individual",
        updated.taxpayer_types[0],
    );

    try std.testing.expect(try store.deleteOverride(later_id));
    try std.testing.expect(!try store.deleteOverride(later_id));
    try std.testing.expectEqual(@as(i64, 0), try scalarCount(
        &store,
        "SELECT count(*) FROM calendar_override_forms WHERE override_id = ?;",
        later_id,
    ));
    try std.testing.expectEqual(@as(i64, 0), try scalarCount(
        &store,
        "SELECT count(*) FROM calendar_override_regions WHERE override_id = ?;",
        later_id,
    ));
    try std.testing.expectEqual(@as(i64, 0), try scalarCount(
        &store,
        "SELECT count(*) FROM calendar_override_taxpayer_types WHERE override_id = ?;",
        later_id,
    ));
}

test "non-working-day CRUD preserves ordered regions and cascades" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    try std.testing.expectError(Error.SourceRequired, store.putNonWorkingDay(.{
        .day = "2026-08-21",
        .name = "Local holiday",
        .kind = "local",
        .source = "",
    }));
    try std.testing.expectError(Error.InvalidDate, store.putNonWorkingDay(.{
        .day = "2026-02-29",
        .name = "Impossible day",
        .kind = "regular",
        .source = "Official Gazette",
    }));
    try std.testing.expectError(Error.InvalidValue, store.putNonWorkingDay(.{
        .day = "2026-08-21",
        .name = "Unscoped local holiday",
        .kind = "local",
        .source = "Official Gazette",
    }));

    const regions = [_][]const u8{ "NCR", "CALABARZON" };
    const local_id = try store.putNonWorkingDay(.{
        .day = "2026-08-21",
        .name = "Local holiday",
        .kind = "local",
        .source = "Proclamation 100",
        .regions = &regions,
    });
    _ = try store.putNonWorkingDay(.{
        .day = "2026-01-01",
        .name = "New Year's Day",
        .kind = "regular",
        .source = "Official Gazette",
    });

    var list = try store.listNonWorkingDays(allocator);
    defer list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("2026-01-01", list.items[0].day);
    try std.testing.expectEqualStrings("CALABARZON", list.items[1].regions[0]);
    try std.testing.expectEqualStrings("NCR", list.items[1].regions[1]);

    try std.testing.expect(try store.deleteNonWorkingDay(local_id));
    try std.testing.expectEqual(@as(i64, 0), try scalarCount(
        &store,
        "SELECT count(*) FROM calendar_non_working_day_regions WHERE non_working_day_id = ?;",
        local_id,
    ));
}

test "provider connections and full event metadata upsert and cascade" {
    const allocator = std.testing.allocator;
    const profile_key = "tax-profile-018f6f2a";
    var store = try Store.openMemory(allocator);
    defer store.close();

    const connection_id = try store.putConnection(.{
        .provider = "google",
        .profile_key = profile_key,
        .external_calendar_id = "calendar-1",
        .calendar_name = "BIR Deadlines",
    });
    const same_id = try store.putConnection(.{
        .provider = "google",
        .profile_key = profile_key,
        .external_calendar_id = "calendar-2",
        .calendar_name = "Updated deadlines",
        .last_error = "temporary",
    });
    try std.testing.expectEqual(connection_id, same_id);

    try store.putEventLink(.{
        .provider = "google",
        .profile_key = profile_key,
        .obligation_key = "2026:1701Q:q1",
        .external_event_id = "event-1",
        .external_ical_uid = "ical-1@example.test",
        .series_id = "series-1",
        .occurrence_id = "20260515",
        .revision = "etag-1",
        .fingerprint = "sha256-old",
        .created_by_backend = true,
    });
    try store.putEventLink(.{
        .provider = "google",
        .profile_key = profile_key,
        .obligation_key = "2026:1701Q:q1",
        .external_event_id = "event-1",
        .external_ical_uid = "ical-1@example.test",
        .series_id = "series-1",
        .occurrence_id = "20260515",
        .revision = "etag-2",
        .fingerprint = "sha256-new",
        .created_by_backend = false,
    });

    var connection = (try store.getConnection(
        allocator,
        "google",
        profile_key,
    )).?;
    defer connection.deinit(allocator);
    try std.testing.expectEqualStrings("calendar-2", connection.external_calendar_id);

    var link = (try store.getEventLink(
        allocator,
        "google",
        profile_key,
        "2026:1701Q:q1",
    )).?;
    defer link.deinit(allocator);
    try std.testing.expectEqualStrings("etag-2", link.revision.?);
    try std.testing.expectEqualStrings("sha256-new", link.fingerprint);
    try std.testing.expect(!link.created_by_backend);

    try std.testing.expectError(Error.SqliteConstraint, store.putEventLink(.{
        .provider = "native",
        .profile_key = "missing",
        .obligation_key = "2026:1701:annual",
        .external_event_id = "event-x",
        .fingerprint = "sha256-x",
    }));

    try std.testing.expect(try store.deleteConnection("google", profile_key));
    try std.testing.expectEqual(@as(i64, 0), try scalarCount(
        &store,
        "SELECT count(*) FROM calendar_event_links WHERE provider = 'google' AND profile_key = '123-456-789' AND ? IS NOT NULL;",
        1,
    ));
}

test "v3 migration keeps every stored override manual and unreferenced" {
    const allocator = std.testing.allocator;
    var store = try openUnmigrated();
    defer store.close();
    try store.exec("PRAGMA foreign_keys = ON;");
    try store.exec(schema_v1);
    try store.exec(migration_v2);
    try store.exec("PRAGMA user_version = 2;");
    try store.exec(
        \\INSERT INTO calendar_overrides (
        \\    id, title, source, original_deadline, adjusted_deadline
        \\) VALUES
        \\    (7, 'Hand-authored extension', 'RMC 4-2026',
        \\     '2026-03-15', '2026-03-20'),
        \\    (8, 'Second extension', 'RMC 5-2026',
        \\     '2026-04-15', '2026-04-20');
    );
    try store.exec(
        \\INSERT INTO calendar_override_forms (override_id, form_code)
        \\VALUES (7, '2550Q'), (8, '1701Q');
    );
    try store.exec(
        \\INSERT INTO calendar_override_regions (override_id, region)
        \\VALUES (7, 'NCR');
    );

    try std.testing.expectEqual(@as(u32, 2), try store.schemaVersion());
    try store.migrate();
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
    try std.testing.expect(try tableHasColumn(&store, "origin"));
    try std.testing.expect(try tableHasColumn(&store, "external_ref"));

    var list = try store.listOverrides(allocator);
    defer list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    for (list.items) |item| {
        try std.testing.expectEqual(Origin.manual, item.origin);
        try std.testing.expect(item.external_ref == null);
    }
    try std.testing.expectEqualStrings("2550Q", list.items[0].affected_form_codes[0]);
    try std.testing.expectEqualStrings("NCR", list.items[0].regions[0]);
    try std.testing.expect(!try store.isDismissed(feed_reference));
}

test "migration rejects a database written by a newer build" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    try store.exec("PRAGMA user_version = 99;");
    try std.testing.expectError(Error.SchemaTooNew, store.migrate());
}

test "one feed identity may own at most one synced override" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const forms = [_][]const u8{"1601C"};
    _ = try store.putOverride(.{
        .title = "RMC 89-2026 monsoon extension",
        .source = "RMC No. 89-2026",
        .original_deadline = "2026-08-10",
        .adjusted_deadline = "2026-08-17",
        .affected_form_codes = &forms,
        .origin = .synced,
        .external_ref = feed_reference,
    });
    try std.testing.expectError(Error.SqliteConstraint, store.putOverride(.{
        .title = "Duplicate of the same issuance",
        .source = "RMC No. 89-2026",
        .original_deadline = "2026-08-10",
        .adjusted_deadline = "2026-08-17",
        .affected_form_codes = &forms,
        .origin = .synced,
        .external_ref = feed_reference,
    }));
    try std.testing.expectError(Error.ExternalRefRequired, store.putOverride(.{
        .title = "Synced row without an identity",
        .source = "RMC No. 89-2026",
        .original_deadline = "2026-08-10",
        .adjusted_deadline = "2026-08-17",
        .affected_form_codes = &forms,
        .origin = .synced,
    }));
    try std.testing.expectError(Error.InvalidValue, store.putOverride(.{
        .title = "Manual row wearing a feed identity",
        .source = "RMC No. 89-2026",
        .original_deadline = "2026-08-10",
        .adjusted_deadline = "2026-08-17",
        .affected_form_codes = &forms,
        .external_ref = "bir:rmc:2026:090/2026-08-10/nonefps",
    }));

    var list = try store.listOverrides(allocator);
    defer list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
}

test "re-syncing a feed record updates its row instead of duplicating it" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const forms = [_][]const u8{ "1601C", "0619E" };
    const rdo_codes = [_][]const u8{ "039", "113" };
    const first = [_]FeedOverrideRecord{.{
        .external_ref = feed_reference,
        .title = "RMC 89-2026 monsoon extension (due 2026-08-10)",
        .source_reference = "RMC No. 89-2026",
        .original_deadline = "2026-08-10",
        .adjusted_deadline = "2026-08-17",
        .form_codes = &forms,
        .rdo_codes = &rdo_codes,
    }};
    const inserted = try store.syncOverridesFromFeed(&first);
    try std.testing.expectEqual(@as(usize, 1), inserted.inserted);
    try std.testing.expectEqual(@as(usize, 0), inserted.updated);
    try std.testing.expectEqual(@as(usize, 0), inserted.rejected);
    const id = (try store.getOverrideIdByExternalRef(feed_reference)).?;

    // Models a re-extraction after a parser fix: same identity, corrected
    // adjusted date, narrowed scope.
    const revised_forms = [_][]const u8{"1601C"};
    const revised_rdo_codes = [_][]const u8{"039"};
    const second = [_]FeedOverrideRecord{.{
        .external_ref = feed_reference,
        .title = "RMC 89-2026 monsoon extension (due 2026-08-10)",
        .source_reference = "RMC No. 89-2026",
        .original_deadline = "2026-08-10",
        .adjusted_deadline = "2026-08-18",
        .form_codes = &revised_forms,
        .rdo_codes = &revised_rdo_codes,
    }};
    const updated = try store.syncOverridesFromFeed(&second);
    try std.testing.expectEqual(@as(usize, 0), updated.inserted);
    try std.testing.expectEqual(@as(usize, 1), updated.updated);

    var list = try store.listOverrides(allocator);
    defer list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    const row = list.items[0];
    try std.testing.expectEqual(id, row.id);
    try std.testing.expectEqual(Origin.synced, row.origin);
    try std.testing.expectEqualStrings(feed_reference, row.external_ref.?);
    try std.testing.expectEqualStrings("RMC No. 89-2026", row.source);
    try std.testing.expectEqualStrings("2026-08-18", row.adjusted_deadline);
    try std.testing.expectEqual(@as(usize, 1), row.affected_form_codes.len);
    try std.testing.expectEqualStrings("1601C", row.affected_form_codes[0]);
    try std.testing.expectEqual(@as(usize, 1), row.regions.len);
    try std.testing.expectEqualStrings("039", row.regions[0]);
}

test "a dismissed feed identity stays deleted across later syncs" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const forms = [_][]const u8{"1601C"};
    const rdo_codes = [_][]const u8{"039"};
    const records = [_]FeedOverrideRecord{.{
        .external_ref = feed_reference,
        .title = "RMC 89-2026 monsoon extension (due 2026-08-10)",
        .source_reference = "RMC No. 89-2026",
        .original_deadline = "2026-08-10",
        .adjusted_deadline = "2026-08-17",
        .form_codes = &forms,
        .rdo_codes = &rdo_codes,
    }};
    _ = try store.syncOverridesFromFeed(&records);
    const id = (try store.getOverrideIdByExternalRef(feed_reference)).?;

    try store.dismissSyncedOverride(id);
    try std.testing.expect(try store.isDismissed(feed_reference));
    try std.testing.expect(try store.getOverrideIdByExternalRef(feed_reference) == null);
    try std.testing.expectError(Error.NotFound, store.dismissSyncedOverride(id));
    try std.testing.expectEqual(@as(i64, 0), try scalarCount(
        &store,
        "SELECT count(*) FROM calendar_override_forms WHERE override_id = ?;",
        id,
    ));

    const resynced = try store.syncOverridesFromFeed(&records);
    try std.testing.expectEqual(@as(usize, 1), resynced.skipped_dismissed);
    try std.testing.expectEqual(@as(usize, 0), resynced.inserted);
    var list = try store.listOverrides(allocator);
    defer list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}

test "a sync leaves a manual override with the same dates untouched" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const forms = [_][]const u8{"1601C"};
    const rdo_codes = [_][]const u8{"039"};
    const manual_id = try store.putOverride(.{
        .title = "Locally noted extension",
        .source = "Branch advisory",
        .original_deadline = "2026-08-10",
        .adjusted_deadline = "2026-08-17",
        .affected_form_codes = &forms,
        .regions = &rdo_codes,
    });
    const records = [_]FeedOverrideRecord{.{
        .external_ref = feed_reference,
        .title = "RMC 89-2026 monsoon extension (due 2026-08-10)",
        .source_reference = "RMC No. 89-2026",
        .original_deadline = "2026-08-10",
        .adjusted_deadline = "2026-08-17",
        .form_codes = &forms,
        .rdo_codes = &rdo_codes,
    }};
    const summary = try store.syncOverridesFromFeed(&records);
    try std.testing.expectEqual(@as(usize, 1), summary.inserted);
    try std.testing.expectEqual(@as(usize, 0), summary.updated);

    var manual = (try store.getOverride(allocator, manual_id)).?;
    defer manual.deinit(allocator);
    try std.testing.expectEqual(Origin.manual, manual.origin);
    try std.testing.expect(manual.external_ref == null);
    try std.testing.expectEqualStrings("Locally noted extension", manual.title);
    try std.testing.expectEqualStrings("Branch advisory", manual.source);
    // A manual row has no feed identity to tombstone; deletion stays the
    // user's own action through deleteOverride.
    try std.testing.expectError(
        Error.NotFound,
        store.dismissSyncedOverride(manual_id),
    );

    var list = try store.listOverrides(allocator);
    defer list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
}

test "an unusable feed record is rejected without dropping the rest" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const forms = [_][]const u8{"1601C"};
    const rdo_codes = [_][]const u8{"039"};
    const records = [_]FeedOverrideRecord{
        .{
            .external_ref = "bir:rmc:2026:088/2026-08-05/nonefps",
            .title = "Unsourced extension",
            .source_reference = "  ",
            .original_deadline = "2026-08-05",
            .adjusted_deadline = "2026-08-12",
            .form_codes = &forms,
            .rdo_codes = &rdo_codes,
        },
        .{
            .external_ref = "bir:rmc:2026:087/2026-02-29/nonefps",
            .title = "Impossible original deadline",
            .source_reference = "RMC No. 87-2026",
            .original_deadline = "2026-02-29",
            .adjusted_deadline = "2026-03-05",
            .form_codes = &forms,
            .rdo_codes = &rdo_codes,
        },
        .{
            .external_ref = feed_reference,
            .title = "RMC 89-2026 monsoon extension (due 2026-08-10)",
            .source_reference = "RMC No. 89-2026",
            .original_deadline = "2026-08-10",
            .adjusted_deadline = "2026-08-17",
            .form_codes = &forms,
            .rdo_codes = &rdo_codes,
        },
    };

    const summary = try store.syncOverridesFromFeed(&records);
    try std.testing.expectEqual(@as(usize, 2), summary.rejected);
    try std.testing.expectEqual(@as(usize, 1), summary.inserted);

    var list = try store.listOverrides(allocator);
    defer list.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings(feed_reference, list.items[0].external_ref.?);
}

const feed_reference = "bir:rmc:2026:089/2026-08-10/nonefps";

fn openUnmigrated() !Store {
    var raw: ?*sqlite.sqlite3 = null;
    const flags = sqlite.SQLITE_OPEN_READWRITE |
        sqlite.SQLITE_OPEN_CREATE |
        sqlite.SQLITE_OPEN_FULLMUTEX;
    const rc = sqlite.sqlite3_open_v2(":memory:", &raw, flags, null);
    if (rc != sqlite.SQLITE_OK or raw == null) {
        if (raw) |db| _ = sqlite.sqlite3_close_v2(db);
        return Error.SqliteFailure;
    }
    return .{ .db = raw.? };
}

fn scalarCount(store: *Store, sql_text: []const u8, value: i64) !i64 {
    var statement = try store.prepare(sql_text);
    defer statement.deinit();
    try statement.bindInt64(1, value);
    if (try statement.step() != .row) return Error.SqliteFailure;
    return sqlite.sqlite3_column_int64(statement.raw, 0);
}

fn tableHasColumn(store: *Store, wanted: []const u8) !bool {
    var statement = try store.prepare("PRAGMA table_info(calendar_overrides);");
    defer statement.deinit();
    while (try statement.step() == .row) {
        const name = columnText(statement.raw, 1) orelse
            return Error.SqliteFailure;
        if (std.mem.eql(u8, name, wanted)) return true;
    }
    return false;
}
