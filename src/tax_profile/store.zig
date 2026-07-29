//! SQLite persistence for versioned tax profiles and form-prefill snapshots.
//!
//! The calendar store already owns `PRAGMA user_version` for its schema. This
//! repository deliberately uses a namespaced migration table instead, so both
//! repositories can share the legacy `calendar.sqlite3` file without making an
//! older calendar-only binary reject the database as too new.

const std = @import("std");

const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

pub const latest_schema_version: u32 = 2;
const migration_component = "tax_profile";

pub const Error = error{
    Closed,
    InvalidDate,
    InvalidAmendment,
    InvalidTransition,
    InvalidValue,
    NotFound,
    RevisionConflict,
    SchemaTooNew,
    SqliteBusy,
    SqliteConstraint,
    SqliteFailure,
};

/// Opaque 128-bit identifiers are serialized as 32 lowercase hexadecimal
/// characters. They deliberately carry no TIN, name, form, sequence, or
/// period meaning. Persistence accepts the domain's broader opaque-ID syntax
/// for imports, but all newly generated identifiers use this representation.
pub const OpaqueId = [32]u8;
pub const DateText = [10]u8;

pub const EffectivePeriodWrite = struct {
    from: DateText,
    until: ?DateText = null,
};

pub const ProfileStatus = enum {
    active,
    archived,

    fn text(self: ProfileStatus) []const u8 {
        return @tagName(self);
    }
};

pub const SubjectKind = enum {
    individual,
    sole_proprietor,
    corporation,
    partnership,
    estate,
    trust,
    other_legal_entity,

    fn text(self: SubjectKind) []const u8 {
        return @tagName(self);
    }
};

pub const LegalEntityKind = enum {
    corporation,
    partnership,
    estate,
    trust,
    other,

    fn text(self: LegalEntityKind) []const u8 {
        return @tagName(self);
    }
};

pub const RevisionSourceTag = enum {
    manual_entry,
    imported,
    migrated,

    fn text(self: RevisionSourceTag) []const u8 {
        return @tagName(self);
    }
};

pub const RevisionSourceWrite = union(RevisionSourceTag) {
    manual_entry: void,
    imported: []const u8,
    migrated: []const u8,
};

pub const IdentityWrite = struct {
    tin: []const u8,
    rdo_code: []const u8,
};

pub const ContactWrite = struct {
    registered_address: []const u8,
    zip_code: ?[]const u8 = null,
    contact_number: ?[]const u8 = null,
    email_address: ?[]const u8 = null,
};

pub const IndividualWrite = struct {
    name: []const u8,
    date_of_birth: ?DateText = null,
    citizenship: ?[]const u8 = null,
    foreign_tax_number: ?[]const u8 = null,
};

pub const SoleProprietorWrite = struct {
    person: IndividualWrite,
    trade_name: ?[]const u8 = null,
};

pub const LegalEntityWrite = struct {
    registered_name: []const u8,
    kind: LegalEntityKind,
};

pub const SubjectWrite = union(enum) {
    individual: IndividualWrite,
    sole_proprietor: SoleProprietorWrite,
    legal_entity: LegalEntityWrite,

    pub fn kind(self: SubjectWrite) SubjectKind {
        return switch (self) {
            .individual => .individual,
            .sole_proprietor => .sole_proprietor,
            .legal_entity => |entity| switch (entity.kind) {
                .corporation => .corporation,
                .partnership => .partnership,
                .estate => .estate,
                .trust => .trust,
                .other => .other_legal_entity,
            },
        };
    }
};

pub const ProfileCreate = struct {
    id: []const u8,
    status: ProfileStatus = .active,
};

/// A cohesive immutable revision row. Repeated components are passed
/// separately through `RevisionComponentsWrite`; no tax-type fact is hidden
/// inside a business activity and no subject is represented by a nullable bag.
pub const RevisionWrite = struct {
    id: []const u8,
    profile_id: []const u8,
    sequence: u32,
    expected_current_sequence: ?u32 = null,
    effective: EffectivePeriodWrite,
    source: RevisionSourceWrite,
    identity: IdentityWrite,
    contact: ContactWrite,
    subject: SubjectWrite,
};

pub const BusinessActivityWrite = struct {
    id: []const u8,
    line_of_business: []const u8,
    atc: ?[]const u8 = null,
    effective: EffectivePeriodWrite,
    ordinal: u32 = 0,
};

pub const RegistrationFactKind = enum {
    tax_type,
    government_withholding_agent,
    special_rate_basis,

    fn text(self: RegistrationFactKind) []const u8 {
        return @tagName(self);
    }
};

pub const GovernmentWithholdingAgent = enum {
    no,
    yes,

    fn text(self: GovernmentWithholdingAgent) []const u8 {
        return @tagName(self);
    }
};

pub const RegistrationFactValueWrite = union(RegistrationFactKind) {
    tax_type: []const u8,
    government_withholding_agent: GovernmentWithholdingAgent,
    special_rate_basis: []const u8,
};

pub const RegistrationFactWrite = struct {
    id: []const u8,
    effective: EffectivePeriodWrite,
    value: RegistrationFactValueWrite,
    ordinal: u32 = 0,
};

pub const RevisionComponentsWrite = struct {
    business_activities: []const BusinessActivityWrite = &.{},
    registration_facts: []const RegistrationFactWrite = &.{},
};

pub const FormRegistrationWrite = struct {
    form_code: []const u8,
    form_revision: []const u8,
};

pub const DraftWrite = struct {
    id: []const u8,
    form_code: []const u8,
    form_revision: []const u8,
    period_key: []const u8,
    profile_as_of: DateText,
    lifecycle: []const u8 = "editing",
    intent: []const u8 = "original",
    mapping_revision: []const u8,
    amendment_of: ?[]const u8 = null,
};

pub const RoleBindingWrite = struct {
    role: []const u8,
    profile_id: []const u8,
    profile_revision_id: []const u8,
    profile_revision_sequence: u32,
    business_activity_id: ?[]const u8 = null,
};

pub const SnapshotFieldWrite = struct {
    role: []const u8,
    field_id: []const u8,
    reusable_field: []const u8,
    value_type: []const u8,
    value_text: []const u8,
    provenance: []const u8,
    profile_revision_id: []const u8,
    profile_revision_sequence: u32,
    revision_source: RevisionSourceWrite,
    business_activity_id: ?[]const u8 = null,
    registration_fact_id: ?[]const u8 = null,
    overridden: bool = false,
};

pub const DraftValueWrite = struct {
    field_id: []const u8,
    value_text: []const u8,
    provenance: []const u8 = "transaction",
};

pub const OwnedProfileSummary = struct {
    id: []u8,
    status: ProfileStatus,
    current_revision_id: []u8,
    current_revision_sequence: u32,
    display_name: []u8,
    tin: []u8,
    subject_kind: SubjectKind,

    pub fn deinit(self: *OwnedProfileSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.current_revision_id);
        allocator.free(self.display_name);
        allocator.free(self.tin);
        self.* = undefined;
    }
};

pub const ProfileSummaryList = struct {
    items: []OwnedProfileSummary,

    pub fn deinit(self: *ProfileSummaryList, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const OwnedRevisionSource = union(RevisionSourceTag) {
    manual_entry: void,
    imported: []u8,
    migrated: []u8,

    pub fn deinit(self: *OwnedRevisionSource, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .manual_entry => {},
            .imported => |reference| allocator.free(reference),
            .migrated => |reference| allocator.free(reference),
        }
        self.* = undefined;
    }
};

pub const OwnedContact = struct {
    registered_address: []u8,
    zip_code: ?[]u8,
    contact_number: ?[]u8,
    email_address: ?[]u8,

    pub fn deinit(self: *OwnedContact, allocator: std.mem.Allocator) void {
        allocator.free(self.registered_address);
        freeOptional(allocator, self.zip_code);
        freeOptional(allocator, self.contact_number);
        freeOptional(allocator, self.email_address);
        self.* = undefined;
    }
};

pub const OwnedIndividual = struct {
    name: []u8,
    date_of_birth: ?[]u8,
    citizenship: ?[]u8,
    foreign_tax_number: ?[]u8,

    pub fn deinit(self: *OwnedIndividual, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        freeOptional(allocator, self.date_of_birth);
        freeOptional(allocator, self.citizenship);
        freeOptional(allocator, self.foreign_tax_number);
        self.* = undefined;
    }
};

pub const OwnedSoleProprietor = struct {
    person: OwnedIndividual,
    trade_name: ?[]u8,

    pub fn deinit(
        self: *OwnedSoleProprietor,
        allocator: std.mem.Allocator,
    ) void {
        self.person.deinit(allocator);
        freeOptional(allocator, self.trade_name);
        self.* = undefined;
    }
};

pub const OwnedLegalEntity = struct {
    registered_name: []u8,
    kind: LegalEntityKind,

    pub fn deinit(self: *OwnedLegalEntity, allocator: std.mem.Allocator) void {
        allocator.free(self.registered_name);
        self.* = undefined;
    }
};

pub const OwnedSubject = union(enum) {
    individual: OwnedIndividual,
    sole_proprietor: OwnedSoleProprietor,
    legal_entity: OwnedLegalEntity,

    pub fn deinit(self: *OwnedSubject, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .individual => |*person| person.deinit(allocator),
            .sole_proprietor => |*proprietor| proprietor.deinit(allocator),
            .legal_entity => |*entity| entity.deinit(allocator),
        }
        self.* = undefined;
    }

    pub fn kind(self: *const OwnedSubject) SubjectKind {
        return switch (self.*) {
            .individual => .individual,
            .sole_proprietor => .sole_proprietor,
            .legal_entity => |entity| switch (entity.kind) {
                .corporation => .corporation,
                .partnership => .partnership,
                .estate => .estate,
                .trust => .trust,
                .other => .other_legal_entity,
            },
        };
    }
};

pub const OwnedBusinessActivity = struct {
    id: []u8,
    line_of_business: []u8,
    atc: ?[]u8,
    effective_from: []u8,
    effective_until: ?[]u8,
    ordinal: u32,

    pub fn deinit(
        self: *OwnedBusinessActivity,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.id);
        allocator.free(self.line_of_business);
        freeOptional(allocator, self.atc);
        allocator.free(self.effective_from);
        freeOptional(allocator, self.effective_until);
        self.* = undefined;
    }
};

pub const OwnedRegistrationFactValue = union(RegistrationFactKind) {
    tax_type: []u8,
    government_withholding_agent: GovernmentWithholdingAgent,
    special_rate_basis: []u8,

    pub fn deinit(
        self: *OwnedRegistrationFactValue,
        allocator: std.mem.Allocator,
    ) void {
        switch (self.*) {
            .tax_type => |value| allocator.free(value),
            .government_withholding_agent => {},
            .special_rate_basis => |value| allocator.free(value),
        }
        self.* = undefined;
    }
};

pub const OwnedRegistrationFact = struct {
    id: []u8,
    effective_from: []u8,
    effective_until: ?[]u8,
    value: OwnedRegistrationFactValue,
    ordinal: u32,

    pub fn deinit(
        self: *OwnedRegistrationFact,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.id);
        allocator.free(self.effective_from);
        freeOptional(allocator, self.effective_until);
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

pub const OwnedProfileRevision = struct {
    id: []u8,
    sequence: u32,
    profile_id: []u8,
    effective_from: []u8,
    effective_until: ?[]u8,
    source: OwnedRevisionSource,
    tin: []u8,
    rdo_code: []u8,
    contact: OwnedContact,
    subject: OwnedSubject,
    business_activities: []OwnedBusinessActivity,
    registration_facts: []OwnedRegistrationFact,

    pub fn deinit(self: *OwnedProfileRevision, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.profile_id);
        allocator.free(self.effective_from);
        freeOptional(allocator, self.effective_until);
        self.source.deinit(allocator);
        allocator.free(self.tin);
        allocator.free(self.rdo_code);
        self.contact.deinit(allocator);
        self.subject.deinit(allocator);
        for (self.business_activities) |*activity| activity.deinit(allocator);
        allocator.free(self.business_activities);
        for (self.registration_facts) |*fact| fact.deinit(allocator);
        allocator.free(self.registration_facts);
        self.* = undefined;
    }
};

pub const OwnedFormRegistration = struct {
    form_code: []u8,
    form_revision: []u8,

    pub fn deinit(self: *OwnedFormRegistration, allocator: std.mem.Allocator) void {
        allocator.free(self.form_code);
        allocator.free(self.form_revision);
        self.* = undefined;
    }
};

pub const FormRegistrationList = struct {
    items: []OwnedFormRegistration,

    pub fn deinit(self: *FormRegistrationList, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const OwnedRoleBinding = struct {
    role: []u8,
    profile_id: []u8,
    profile_revision_id: []u8,
    profile_revision_sequence: u32,
    business_activity_id: ?[]u8,

    pub fn deinit(self: *OwnedRoleBinding, allocator: std.mem.Allocator) void {
        allocator.free(self.role);
        allocator.free(self.profile_id);
        allocator.free(self.profile_revision_id);
        freeOptional(allocator, self.business_activity_id);
        self.* = undefined;
    }
};

pub const OwnedSnapshotField = struct {
    role: []u8,
    field_id: []u8,
    reusable_field: []u8,
    value_type: []u8,
    value_text: []u8,
    provenance: []u8,
    profile_revision_id: []u8,
    profile_revision_sequence: u32,
    revision_source: OwnedRevisionSource,
    business_activity_id: ?[]u8,
    registration_fact_id: ?[]u8,
    overridden: bool,

    pub fn deinit(self: *OwnedSnapshotField, allocator: std.mem.Allocator) void {
        allocator.free(self.role);
        allocator.free(self.field_id);
        allocator.free(self.reusable_field);
        allocator.free(self.value_type);
        allocator.free(self.value_text);
        allocator.free(self.provenance);
        allocator.free(self.profile_revision_id);
        self.revision_source.deinit(allocator);
        freeOptional(allocator, self.business_activity_id);
        freeOptional(allocator, self.registration_fact_id);
        self.* = undefined;
    }
};

pub const OwnedDraftValue = struct {
    field_id: []u8,
    value_text: []u8,
    provenance: []u8,

    pub fn deinit(self: *OwnedDraftValue, allocator: std.mem.Allocator) void {
        allocator.free(self.field_id);
        allocator.free(self.value_text);
        allocator.free(self.provenance);
        self.* = undefined;
    }
};

pub const OwnedDraft = struct {
    id: []u8,
    form_code: []u8,
    form_revision: []u8,
    period_key: []u8,
    profile_as_of: []u8,
    lifecycle: []u8,
    intent: []u8,
    mapping_revision: []u8,
    amendment_of: ?[]u8,
    bindings: []OwnedRoleBinding,
    snapshots: []OwnedSnapshotField,
    values: []OwnedDraftValue,

    pub fn deinit(self: *OwnedDraft, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.form_code);
        allocator.free(self.form_revision);
        allocator.free(self.period_key);
        allocator.free(self.profile_as_of);
        allocator.free(self.lifecycle);
        allocator.free(self.intent);
        allocator.free(self.mapping_revision);
        freeOptional(allocator, self.amendment_of);
        for (self.bindings) |*binding| binding.deinit(allocator);
        allocator.free(self.bindings);
        for (self.snapshots) |*snapshot| snapshot.deinit(allocator);
        allocator.free(self.snapshots);
        for (self.values) |*value| value.deinit(allocator);
        allocator.free(self.values);
        self.* = undefined;
    }
};

pub const Store = struct {
    db: ?*sqlite.sqlite3,

    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Store {
        if (path.len == 0) return Error.InvalidValue;
        return openInternal(allocator, path, true);
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
            sqlite.SQLITE_OPEN_FULLMUTEX;
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

    pub fn foreignKeysEnabled(self: *Store) !bool {
        var statement = try self.prepare("PRAGMA foreign_keys;");
        defer statement.deinit();
        if (try statement.step() != .row) return Error.SqliteFailure;
        return sqlite.sqlite3_column_int(statement.raw, 0) == 1;
    }

    pub fn schemaVersion(self: *Store) !u32 {
        var statement = try self.prepare(
            \\SELECT version
            \\FROM app_component_migrations
            \\WHERE component = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, migration_component);
        return switch (try statement.step()) {
            .done => 0,
            .row => blk: {
                const value = sqlite.sqlite3_column_int64(statement.raw, 0);
                if (value < 0 or value > std.math.maxInt(u32)) {
                    return Error.SqliteFailure;
                }
                break :blk @intCast(value);
            },
        };
    }

    pub fn migrate(self: *Store) !void {
        try self.exec(
            \\CREATE TABLE IF NOT EXISTS app_component_migrations (
            \\    component TEXT PRIMARY KEY,
            \\    version INTEGER NOT NULL CHECK (version >= 0),
            \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch())
            \\);
        );
        const observed = try self.schemaVersion();
        if (observed > latest_schema_version) return Error.SchemaTooNew;
        if (observed == latest_schema_version) return;

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        const current = try self.schemaVersion();
        if (current > latest_schema_version) return Error.SchemaTooNew;
        if (current < 1) {
            try self.exec(schema_v1);
            var version = try self.prepare(
                \\INSERT INTO app_component_migrations(component, version)
                \\VALUES (?, 1)
                \\ON CONFLICT(component) DO UPDATE SET
                \\    version = excluded.version,
                \\    updated_at = unixepoch();
            );
            defer version.deinit();
            try version.bindText(1, migration_component);
            try version.expectDone();
        }
        if (current < 2) {
            try self.exec(schema_v2);
            var version = try self.prepare(
                \\UPDATE app_component_migrations
                \\SET version = 2, updated_at = unixepoch()
                \\WHERE component = ?;
            );
            defer version.deinit();
            try version.bindText(1, migration_component);
            try version.expectDone();
        }
        try self.commit();
        committed = true;
    }

    pub fn generateOpaqueId(self: *Store) !OpaqueId {
        var statement = try self.prepare("SELECT lower(hex(randomblob(16)));");
        defer statement.deinit();
        if (try statement.step() != .row) return Error.SqliteFailure;
        const raw = columnText(statement.raw, 0) orelse return Error.SqliteFailure;
        if (raw.len != 32) return Error.SqliteFailure;
        var id: OpaqueId = undefined;
        @memcpy(&id, raw);
        if (try statement.step() != .done) return Error.SqliteFailure;
        return id;
    }

    pub fn createProfile(self: *Store, value: ProfileCreate) !void {
        try validateProfileCreate(value);
        var statement = try self.prepare(
            \\INSERT INTO tax_profiles(id, status)
            \\VALUES (?, ?);
        );
        defer statement.deinit();
        try statement.bindText(1, value.id);
        try statement.bindText(2, value.status.text());
        try statement.expectDone();
    }

    /// Production first-save path. The profile shell, first immutable
    /// revision, repeated components, and current pointer either all commit or
    /// none do, so a validation/constraint failure cannot leave an orphan
    /// profile.
    pub fn createProfileWithRevision(
        self: *Store,
        profile: ProfileCreate,
        revision: RevisionWrite,
        components: RevisionComponentsWrite,
    ) !void {
        try validateProfileCreate(profile);
        try validateRevision(revision, components);
        if (!std.mem.eql(u8, profile.id, revision.profile_id)) {
            return Error.InvalidValue;
        }
        if (revision.sequence != 1) return Error.RevisionConflict;
        if (revision.expected_current_sequence) |expected| {
            if (expected != 0) return Error.RevisionConflict;
        }

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        var add_profile = try self.prepare(
            \\INSERT INTO tax_profiles(id, status)
            \\VALUES (?, ?);
        );
        defer add_profile.deinit();
        try add_profile.bindText(1, profile.id);
        try add_profile.bindText(2, profile.status.text());
        try add_profile.expectDone();

        try self.insertRevisionRows(revision, components);
        var advance = try self.prepare(
            \\UPDATE tax_profiles
            \\SET current_revision_id = ?, updated_at = unixepoch()
            \\WHERE id = ? AND current_revision_id IS NULL;
        );
        defer advance.deinit();
        try advance.bindText(1, revision.id);
        try advance.bindText(2, profile.id);
        try advance.expectDone();
        if (sqlite.sqlite3_changes(try self.handle()) != 1) {
            return Error.RevisionConflict;
        }

        try self.commit();
        committed = true;
    }

    pub fn setProfileStatus(
        self: *Store,
        profile_id: []const u8,
        status: ProfileStatus,
    ) !void {
        try validateOpaqueText(profile_id);
        var statement = try self.prepare(
            \\UPDATE tax_profiles
            \\SET status = ?, updated_at = unixepoch()
            \\WHERE id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, status.text());
        try statement.bindText(2, profile_id);
        try statement.expectDone();
        if (sqlite.sqlite3_changes(try self.handle()) == 0) return Error.NotFound;
    }

    /// Appends an immutable revision and atomically advances the profile's
    /// current pointer. `expected_current_sequence` is the caller's observed
    /// sequence number. SQLite rowids never cross this boundary.
    pub fn appendRevision(
        self: *Store,
        value: RevisionWrite,
        components: RevisionComponentsWrite,
    ) !void {
        try validateRevision(value, components);

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        const current = try self.currentRevisionSequence(value.profile_id);
        const observed_sequence: u32 = current orelse 0;
        if (current == null and !(try self.profileExists(value.profile_id))) {
            return Error.NotFound;
        }
        if (value.expected_current_sequence) |expected| {
            if (expected != observed_sequence) return Error.RevisionConflict;
        }
        if (observed_sequence == std.math.maxInt(u32)) {
            return Error.InvalidValue;
        }
        if (value.sequence != observed_sequence + 1) {
            return Error.RevisionConflict;
        }

        try self.insertRevisionRows(value, components);

        var advance = try self.prepare(
            \\UPDATE tax_profiles
            \\SET current_revision_id = ?, updated_at = unixepoch()
            \\WHERE id = ? AND (
            \\    (? = 0 AND current_revision_id IS NULL) OR
            \\    current_revision_id = (
            \\        SELECT id
            \\        FROM tax_profile_revisions
            \\        WHERE profile_id = ? AND sequence = ?
            \\    )
            \\);
        );
        defer advance.deinit();
        try advance.bindText(1, value.id);
        try advance.bindText(2, value.profile_id);
        try advance.bindInt64(3, observed_sequence);
        try advance.bindText(4, value.profile_id);
        try advance.bindInt64(5, observed_sequence);
        try advance.expectDone();
        if (sqlite.sqlite3_changes(try self.handle()) != 1) {
            return Error.RevisionConflict;
        }

        try self.commit();
        committed = true;
    }

    fn insertRevisionRows(
        self: *Store,
        value: RevisionWrite,
        components: RevisionComponentsWrite,
    ) !void {
        const source_tag: RevisionSourceTag = value.source;
        const source_reference: ?[]const u8 = switch (value.source) {
            .manual_entry => null,
            .imported => |reference| reference,
            .migrated => |reference| reference,
        };
        const subject_kind = value.subject.kind();
        const taxpayer_name: ?[]const u8 = switch (value.subject) {
            .individual => |person| person.name,
            .sole_proprietor => |proprietor| proprietor.person.name,
            .legal_entity => null,
        };
        const registered_name: ?[]const u8 = switch (value.subject) {
            .individual => null,
            .sole_proprietor => |proprietor| proprietor.trade_name,
            .legal_entity => |entity| entity.registered_name,
        };
        const individual: ?IndividualWrite = switch (value.subject) {
            .individual => |person| person,
            .sole_proprietor => |proprietor| proprietor.person,
            .legal_entity => null,
        };
        var insert = try self.prepare(
            \\INSERT INTO tax_profile_revisions (
            \\    id, profile_id, sequence, effective_from, effective_until,
            \\    source_tag, source_reference, tin, rdo_code,
            \\    registered_address, zip_code, contact_number, email_address,
            \\    subject_kind, taxpayer_name, registered_name,
            \\    date_of_birth, citizenship, foreign_tax_number
            \\) VALUES (
            \\    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            \\);
        );
        defer insert.deinit();
        try insert.bindText(1, value.id);
        try insert.bindText(2, value.profile_id);
        try insert.bindInt64(3, value.sequence);
        try insert.bindDate(4, value.effective.from[0..]);
        try insert.bindOptionalDate(
            5,
            optionalDateSlice(&value.effective.until),
        );
        try insert.bindText(6, source_tag.text());
        try insert.bindOptionalText(7, source_reference);
        try insert.bindText(8, value.identity.tin);
        try insert.bindText(9, value.identity.rdo_code);
        try insert.bindText(10, value.contact.registered_address);
        try insert.bindOptionalText(11, value.contact.zip_code);
        try insert.bindOptionalText(12, value.contact.contact_number);
        try insert.bindOptionalText(13, value.contact.email_address);
        try insert.bindText(14, subject_kind.text());
        try insert.bindOptionalText(15, taxpayer_name);
        try insert.bindOptionalText(16, registered_name);
        try insert.bindOptionalDate(
            17,
            if (individual) |*person|
                optionalDateSlice(&person.date_of_birth)
            else
                null,
        );
        try insert.bindOptionalText(
            18,
            if (individual) |person| person.citizenship else null,
        );
        try insert.bindOptionalText(
            19,
            if (individual) |person| person.foreign_tax_number else null,
        );
        try insert.expectDone();

        var add_activity = try self.prepare(
            \\INSERT INTO tax_profile_business_activities (
            \\    profile_id, revision_id, id, line_of_business, atc,
            \\    effective_from, effective_until, ordinal
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_activity.deinit();
        for (components.business_activities) |activity| {
            try add_activity.bindText(1, value.profile_id);
            try add_activity.bindText(2, value.id);
            try add_activity.bindText(3, activity.id);
            try add_activity.bindText(4, activity.line_of_business);
            try add_activity.bindOptionalText(5, activity.atc);
            try add_activity.bindDate(6, activity.effective.from[0..]);
            try add_activity.bindOptionalDate(
                7,
                optionalDateSlice(&activity.effective.until),
            );
            try add_activity.bindInt64(8, activity.ordinal);
            try add_activity.expectDone();
            try add_activity.reset();
        }

        var add_fact = try self.prepare(
            \\INSERT INTO tax_profile_registration_facts (
            \\    profile_id, revision_id, id, kind, value_text,
            \\    effective_from, effective_until, ordinal
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_fact.deinit();
        for (components.registration_facts) |fact| {
            const kind: RegistrationFactKind = fact.value;
            const fact_value: []const u8 = switch (fact.value) {
                .tax_type => |text| text,
                .government_withholding_agent => |answer| answer.text(),
                .special_rate_basis => |text| text,
            };
            try add_fact.bindText(1, value.profile_id);
            try add_fact.bindText(2, value.id);
            try add_fact.bindText(3, fact.id);
            try add_fact.bindText(4, kind.text());
            try add_fact.bindText(5, fact_value);
            try add_fact.bindDate(6, fact.effective.from[0..]);
            try add_fact.bindOptionalDate(
                7,
                optionalDateSlice(&fact.effective.until),
            );
            try add_fact.bindInt64(8, fact.ordinal);
            try add_fact.expectDone();
            try add_fact.reset();
        }
    }

    pub fn getCurrentRevision(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
    ) !?OwnedProfileRevision {
        try validateOpaqueText(profile_id);
        var statement = try self.prepare(
            \\SELECT r.id, r.sequence, r.profile_id, r.effective_from,
            \\       r.effective_until, r.source_tag, r.source_reference,
            \\       r.tin, r.rdo_code, r.registered_address, r.zip_code,
            \\       r.contact_number, r.email_address, r.subject_kind,
            \\       r.taxpayer_name, r.registered_name, r.date_of_birth,
            \\       r.citizenship, r.foreign_tax_number
            \\FROM tax_profiles AS p
            \\JOIN tax_profile_revisions AS r
            \\  ON r.profile_id = p.id AND r.id = p.current_revision_id
            \\WHERE p.id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        return switch (try statement.step()) {
            .done => null,
            .row => try self.readRevision(allocator, statement.raw),
        };
    }

    pub fn getRevision(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        revision_id: []const u8,
    ) !?OwnedProfileRevision {
        try validateIdText(profile_id);
        try validateIdText(revision_id);
        var statement = try self.prepare(
            \\SELECT id, sequence, profile_id, effective_from,
            \\       effective_until, source_tag, source_reference, tin,
            \\       rdo_code, registered_address, zip_code, contact_number,
            \\       email_address, subject_kind, taxpayer_name,
            \\       registered_name, date_of_birth, citizenship,
            \\       foreign_tax_number
            \\FROM tax_profile_revisions
            \\WHERE profile_id = ? AND id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindText(2, revision_id);
        return switch (try statement.step()) {
            .done => null,
            .row => try self.readRevision(allocator, statement.raw),
        };
    }

    pub fn getRevisionBySequence(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        sequence: u32,
    ) !?OwnedProfileRevision {
        try validateIdText(profile_id);
        if (sequence == 0) return Error.InvalidValue;
        var statement = try self.prepare(
            \\SELECT id, sequence, profile_id, effective_from,
            \\       effective_until, source_tag, source_reference, tin,
            \\       rdo_code, registered_address, zip_code, contact_number,
            \\       email_address, subject_kind, taxpayer_name,
            \\       registered_name, date_of_birth, citizenship,
            \\       foreign_tax_number
            \\FROM tax_profile_revisions
            \\WHERE profile_id = ? AND sequence = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindInt64(2, sequence);
        return switch (try statement.step()) {
            .done => null,
            .row => try self.readRevision(allocator, statement.raw),
        };
    }

    pub fn getEffectiveRevision(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        effective_on: []const u8,
    ) !?OwnedProfileRevision {
        try validateOpaqueText(profile_id);
        try validateDate(effective_on);
        var statement = try self.prepare(
            \\SELECT id, sequence, profile_id, effective_from,
            \\       effective_until, source_tag, source_reference, tin,
            \\       rdo_code, registered_address, zip_code, contact_number,
            \\       email_address, subject_kind, taxpayer_name,
            \\       registered_name, date_of_birth, citizenship,
            \\       foreign_tax_number
            \\FROM tax_profile_revisions
            \\WHERE profile_id = ?
            \\  AND effective_from <= ?
            \\  AND (effective_until IS NULL OR effective_until >= ?)
            \\ORDER BY sequence DESC
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindText(2, effective_on);
        try statement.bindText(3, effective_on);
        return switch (try statement.step()) {
            .done => null,
            .row => try self.readRevision(allocator, statement.raw),
        };
    }

    pub fn listProfiles(
        self: *Store,
        allocator: std.mem.Allocator,
        include_archived: bool,
    ) !ProfileSummaryList {
        var statement = try self.prepare(
            \\SELECT p.id, p.status, p.current_revision_id, r.sequence,
            \\       COALESCE(r.taxpayer_name, r.registered_name),
            \\       r.tin, r.subject_kind
            \\FROM tax_profiles AS p
            \\JOIN tax_profile_revisions AS r
            \\  ON r.profile_id = p.id AND r.id = p.current_revision_id
            \\WHERE (? = 1 OR p.status = 'active')
            \\ORDER BY COALESCE(
            \\    r.taxpayer_name, r.registered_name
            \\) COLLATE NOCASE, p.id;
        );
        defer statement.deinit();
        try statement.bindBool(1, include_archived);

        var items: std.ArrayList(OwnedProfileSummary) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const item = try readProfileSummary(allocator, statement.raw);
            errdefer {
                var owned = item;
                owned.deinit(allocator);
            }
            try items.append(allocator, item);
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    /// Replaces the authoritative per-year Forms Set. Passing an empty slice
    /// intentionally leaves the parent row present with zero entries.
    pub fn replaceFormSet(
        self: *Store,
        profile_id: []const u8,
        tax_year: i32,
        forms: []const FormRegistrationWrite,
    ) !void {
        try validateOpaqueText(profile_id);
        try validateTaxYear(tax_year);
        for (forms) |form| {
            try requireValue(form.form_code);
            try requireValue(form.form_revision);
        }

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        var configure = try self.prepare(
            \\INSERT INTO tax_profile_form_sets(profile_id, tax_year)
            \\VALUES (?, ?)
            \\ON CONFLICT(profile_id, tax_year) DO UPDATE SET
            \\    configured_at = unixepoch();
        );
        defer configure.deinit();
        try configure.bindText(1, profile_id);
        try configure.bindInt64(2, tax_year);
        try configure.expectDone();

        var clear = try self.prepare(
            \\DELETE FROM tax_profile_form_set_entries
            \\WHERE profile_id = ? AND tax_year = ?;
        );
        defer clear.deinit();
        try clear.bindText(1, profile_id);
        try clear.bindInt64(2, tax_year);
        try clear.expectDone();

        var add = try self.prepare(
            \\INSERT INTO tax_profile_form_set_entries (
            \\    profile_id, tax_year, form_code, form_revision
            \\) VALUES (?, ?, ?, ?);
        );
        defer add.deinit();
        for (forms) |form| {
            try add.bindText(1, profile_id);
            try add.bindInt64(2, tax_year);
            try add.bindText(3, form.form_code);
            try add.bindText(4, form.form_revision);
            try add.expectDone();
            try add.reset();
        }

        try self.commit();
        committed = true;
    }

    /// `null` means no Forms Set is configured and callers may use their
    /// explicit fallback policy. A non-null list with zero items is the
    /// authoritative, intentionally empty set.
    pub fn getFormSet(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        tax_year: i32,
    ) !?FormRegistrationList {
        try validateOpaqueText(profile_id);
        try validateTaxYear(tax_year);
        var configured = try self.prepare(
            \\SELECT 1 FROM tax_profile_form_sets
            \\WHERE profile_id = ? AND tax_year = ?;
        );
        defer configured.deinit();
        try configured.bindText(1, profile_id);
        try configured.bindInt64(2, tax_year);
        if (try configured.step() == .done) return null;

        var statement = try self.prepare(
            \\SELECT form_code, form_revision
            \\FROM tax_profile_form_set_entries
            \\WHERE profile_id = ? AND tax_year = ?
            \\ORDER BY form_code COLLATE NOCASE, form_revision;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindInt64(2, tax_year);

        var items: std.ArrayList(OwnedFormRegistration) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const form_code = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(form_code);
            const form_revision = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(form_revision);
            try items.append(allocator, .{
                .form_code = form_code,
                .form_revision = form_revision,
            });
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    /// Removes the configuration marker so `getFormSet` returns null again.
    pub fn clearFormSet(
        self: *Store,
        profile_id: []const u8,
        tax_year: i32,
    ) !bool {
        try validateOpaqueText(profile_id);
        try validateTaxYear(tax_year);
        var statement = try self.prepare(
            \\DELETE FROM tax_profile_form_sets
            \\WHERE profile_id = ? AND tax_year = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindInt64(2, tax_year);
        try statement.expectDone();
        return sqlite.sqlite3_changes(try self.handle()) != 0;
    }

    /// Creates a draft, its named role bindings, immutable profile snapshot,
    /// and initial transaction values in one transaction. Binding order has no
    /// meaning; role names are the stable identity.
    pub fn createDraft(
        self: *Store,
        draft: DraftWrite,
        bindings: []const RoleBindingWrite,
        snapshots: []const SnapshotFieldWrite,
        values: []const DraftValueWrite,
    ) !void {
        try validateDraft(draft, bindings, snapshots, values);

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        if (draft.amendment_of) |prior_id| {
            var prior = try self.prepare(
                \\SELECT form_code, form_revision
                \\FROM tax_form_drafts
                \\WHERE id = ?;
            );
            defer prior.deinit();
            try prior.bindText(1, prior_id);
            if (try prior.step() != .row) return Error.InvalidAmendment;
            const prior_code = columnText(prior.raw, 0) orelse
                return Error.SqliteFailure;
            const prior_revision = columnText(prior.raw, 1) orelse
                return Error.SqliteFailure;
            if (!std.mem.eql(u8, prior_code, draft.form_code) or
                !std.mem.eql(u8, prior_revision, draft.form_revision))
            {
                return Error.InvalidAmendment;
            }
        }

        var add_draft = try self.prepare(
            \\INSERT INTO tax_form_drafts (
            \\    id, form_code, form_revision, period_key, profile_as_of,
            \\    lifecycle, intent, mapping_revision, amendment_of
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_draft.deinit();
        try add_draft.bindText(1, draft.id);
        try add_draft.bindText(2, draft.form_code);
        try add_draft.bindText(3, draft.form_revision);
        try add_draft.bindText(4, draft.period_key);
        try add_draft.bindDate(5, draft.profile_as_of[0..]);
        try add_draft.bindText(6, draft.lifecycle);
        try add_draft.bindText(7, draft.intent);
        try add_draft.bindText(8, draft.mapping_revision);
        try add_draft.bindOptionalText(9, draft.amendment_of);
        try add_draft.expectDone();

        var add_binding = try self.prepare(
            \\INSERT INTO tax_form_draft_role_bindings (
            \\    draft_id, role, profile_id, profile_revision_id,
            \\    profile_revision_sequence, business_activity_id
            \\) VALUES (?, ?, ?, ?, ?, ?);
        );
        defer add_binding.deinit();
        for (bindings) |binding| {
            try add_binding.bindText(1, draft.id);
            try add_binding.bindText(2, binding.role);
            try add_binding.bindText(3, binding.profile_id);
            try add_binding.bindText(4, binding.profile_revision_id);
            try add_binding.bindInt64(5, binding.profile_revision_sequence);
            try add_binding.bindOptionalText(6, binding.business_activity_id);
            try add_binding.expectDone();
            try add_binding.reset();
        }

        var add_snapshot = try self.prepare(
            \\INSERT INTO tax_form_draft_snapshot_fields (
            \\    draft_id, role, field_id, reusable_field, value_type,
            \\    value_text, provenance, profile_revision_id,
            \\    profile_revision_sequence, revision_source_tag,
            \\    revision_source_reference, business_activity_id,
            \\    registration_fact_id, overridden
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_snapshot.deinit();
        for (snapshots) |snapshot| {
            const binding = findBinding(bindings, snapshot.role) orelse
                return Error.InvalidValue;
            if (!std.mem.eql(
                u8,
                binding.profile_revision_id,
                snapshot.profile_revision_id,
            ) or binding.profile_revision_sequence !=
                snapshot.profile_revision_sequence)
            {
                return Error.InvalidValue;
            }
            const source_tag: RevisionSourceTag = snapshot.revision_source;
            const source_reference: ?[]const u8 = switch (snapshot.revision_source) {
                .manual_entry => null,
                .imported => |reference| reference,
                .migrated => |reference| reference,
            };
            try add_snapshot.bindText(1, draft.id);
            try add_snapshot.bindText(2, snapshot.role);
            try add_snapshot.bindText(3, snapshot.field_id);
            try add_snapshot.bindText(4, snapshot.reusable_field);
            try add_snapshot.bindText(5, snapshot.value_type);
            try add_snapshot.bindText(6, snapshot.value_text);
            try add_snapshot.bindText(7, snapshot.provenance);
            try add_snapshot.bindText(8, snapshot.profile_revision_id);
            try add_snapshot.bindInt64(9, snapshot.profile_revision_sequence);
            try add_snapshot.bindText(10, source_tag.text());
            try add_snapshot.bindOptionalText(11, source_reference);
            try add_snapshot.bindOptionalText(12, snapshot.business_activity_id);
            try add_snapshot.bindOptionalText(13, snapshot.registration_fact_id);
            try add_snapshot.bindBool(14, snapshot.overridden);
            try add_snapshot.expectDone();
            try add_snapshot.reset();
        }

        var add_value = try self.prepare(
            \\INSERT INTO tax_form_draft_values (
            \\    draft_id, field_id, value_text, provenance
            \\) VALUES (?, ?, ?, ?);
        );
        defer add_value.deinit();
        for (values) |value| {
            try add_value.bindText(1, draft.id);
            try add_value.bindText(2, value.field_id);
            try add_value.bindText(3, value.value_text);
            try add_value.bindText(4, value.provenance);
            try add_value.expectDone();
            try add_value.reset();
        }

        try self.commit();
        committed = true;
    }

    pub fn getDraft(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_id: []const u8,
    ) !?OwnedDraft {
        try validateOpaqueText(draft_id);
        var statement = try self.prepare(
            \\SELECT id, form_code, form_revision, period_key, profile_as_of,
            \\       lifecycle, intent, mapping_revision, amendment_of
            \\FROM tax_form_drafts
            \\WHERE id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        if (try statement.step() == .done) return null;

        const id = try dupColumn(allocator, statement.raw, 0);
        errdefer allocator.free(id);
        const form_code = try dupColumn(allocator, statement.raw, 1);
        errdefer allocator.free(form_code);
        const form_revision = try dupColumn(allocator, statement.raw, 2);
        errdefer allocator.free(form_revision);
        const period_key = try dupColumn(allocator, statement.raw, 3);
        errdefer allocator.free(period_key);
        const profile_as_of = try dupColumn(allocator, statement.raw, 4);
        errdefer allocator.free(profile_as_of);
        const lifecycle = try dupColumn(allocator, statement.raw, 5);
        errdefer allocator.free(lifecycle);
        const intent = try dupColumn(allocator, statement.raw, 6);
        errdefer allocator.free(intent);
        const mapping_revision = try dupColumn(allocator, statement.raw, 7);
        errdefer allocator.free(mapping_revision);
        const amendment_of = try dupOptionalColumn(allocator, statement.raw, 8);
        errdefer freeOptional(allocator, amendment_of);
        const bindings = try self.loadBindings(allocator, draft_id);
        errdefer {
            for (bindings) |*binding| binding.deinit(allocator);
            allocator.free(bindings);
        }
        const snapshots = try self.loadSnapshots(allocator, draft_id);
        errdefer {
            for (snapshots) |*snapshot| snapshot.deinit(allocator);
            allocator.free(snapshots);
        }
        const values = try self.loadDraftValues(allocator, draft_id);
        errdefer {
            for (values) |*value| value.deinit(allocator);
            allocator.free(values);
        }
        return .{
            .id = id,
            .form_code = form_code,
            .form_revision = form_revision,
            .period_key = period_key,
            .profile_as_of = profile_as_of,
            .lifecycle = lifecycle,
            .intent = intent,
            .mapping_revision = mapping_revision,
            .amendment_of = amendment_of,
            .bindings = bindings,
            .snapshots = snapshots,
            .values = values,
        };
    }

    pub fn putDraftValue(
        self: *Store,
        draft_id: []const u8,
        value: DraftValueWrite,
    ) !void {
        try validateOpaqueText(draft_id);
        try requireValue(value.field_id);
        try requireValue(value.provenance);
        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();
        if (!(try self.draftAcceptsEdits(draft_id))) return Error.InvalidTransition;
        var statement = try self.prepare(
            \\INSERT INTO tax_form_draft_values (
            \\    draft_id, field_id, value_text, provenance
            \\) VALUES (?, ?, ?, ?)
            \\ON CONFLICT(draft_id, field_id) DO UPDATE SET
            \\    value_text = excluded.value_text,
            \\    provenance = excluded.provenance,
            \\    updated_at = unixepoch();
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        try statement.bindText(2, value.field_id);
        try statement.bindText(3, value.value_text);
        try statement.bindText(4, value.provenance);
        try statement.expectDone();
        try self.commit();
        committed = true;
    }

    /// Atomically replaces the editable filing-value slice without touching
    /// immutable profile bindings or prefill snapshots.
    pub fn replaceDraftValues(
        self: *Store,
        draft_id: []const u8,
        values: []const DraftValueWrite,
    ) !void {
        try validateOpaqueText(draft_id);
        try validateDraftValues(values);
        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();
        if (!(try self.draftAcceptsEdits(draft_id))) {
            return Error.InvalidTransition;
        }

        var remove = try self.prepare(
            \\DELETE FROM tax_form_draft_values
            \\WHERE draft_id = ?;
        );
        defer remove.deinit();
        try remove.bindText(1, draft_id);
        try remove.expectDone();

        var insert = try self.prepare(
            \\INSERT INTO tax_form_draft_values (
            \\    draft_id, field_id, value_text, provenance
            \\) VALUES (?, ?, ?, ?);
        );
        defer insert.deinit();
        for (values) |value| {
            try insert.bindText(1, draft_id);
            try insert.bindText(2, value.field_id);
            try insert.bindText(3, value.value_text);
            try insert.bindText(4, value.provenance);
            try insert.expectDone();
            try insert.reset();
        }

        try self.commit();
        committed = true;
    }

    pub fn deleteDraftValue(
        self: *Store,
        draft_id: []const u8,
        field_id: []const u8,
    ) !bool {
        try validateOpaqueText(draft_id);
        try requireValue(field_id);
        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();
        if (!(try self.draftAcceptsEdits(draft_id))) return Error.InvalidTransition;
        var statement = try self.prepare(
            \\DELETE FROM tax_form_draft_values
            \\WHERE draft_id = ? AND field_id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        try statement.bindText(2, field_id);
        try statement.expectDone();
        const deleted = sqlite.sqlite3_changes(try self.handle()) != 0;
        try self.commit();
        committed = true;
        return deleted;
    }

    /// Performs an optimistic lifecycle transition. Both the transition graph
    /// and the expected current state are checked before updating.
    pub fn transitionDraft(
        self: *Store,
        draft_id: []const u8,
        expected: []const u8,
        next: []const u8,
    ) !void {
        try validateOpaqueText(draft_id);
        if (!validLifecycle(expected) or !validLifecycle(next)) {
            return Error.InvalidTransition;
        }
        if (!lifecycleTransitionAllowed(expected, next)) {
            return Error.InvalidTransition;
        }
        var statement = try self.prepare(
            \\UPDATE tax_form_drafts
            \\SET lifecycle = ?, updated_at = unixepoch()
            \\WHERE id = ? AND lifecycle = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, next);
        try statement.bindText(2, draft_id);
        try statement.bindText(3, expected);
        try statement.expectDone();
        if (sqlite.sqlite3_changes(try self.handle()) == 0) {
            if (try self.draftExists(draft_id)) return Error.RevisionConflict;
            return Error.NotFound;
        }
    }

    pub fn deleteDraft(self: *Store, draft_id: []const u8) !bool {
        try validateOpaqueText(draft_id);
        var statement = try self.prepare(
            \\DELETE FROM tax_form_drafts
            \\WHERE id = ? AND lifecycle IN ('editing', 'cancelled');
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        try statement.expectDone();
        return sqlite.sqlite3_changes(try self.handle()) != 0;
    }

    fn loadBindings(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_id: []const u8,
    ) ![]OwnedRoleBinding {
        var statement = try self.prepare(
            \\SELECT role, profile_id, profile_revision_id,
            \\       profile_revision_sequence, business_activity_id
            \\FROM tax_form_draft_role_bindings
            \\WHERE draft_id = ?
            \\ORDER BY role COLLATE BINARY;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        var items: std.ArrayList(OwnedRoleBinding) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const role = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(role);
            const profile_id = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(profile_id);
            const profile_revision_id = try dupColumn(
                allocator,
                statement.raw,
                2,
            );
            errdefer allocator.free(profile_revision_id);
            const sequence_raw = sqlite.sqlite3_column_int64(statement.raw, 3);
            if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
                return Error.SqliteFailure;
            }
            const business_activity_id = try dupOptionalColumn(
                allocator,
                statement.raw,
                4,
            );
            errdefer freeOptional(allocator, business_activity_id);
            try items.append(allocator, .{
                .role = role,
                .profile_id = profile_id,
                .profile_revision_id = profile_revision_id,
                .profile_revision_sequence = @intCast(sequence_raw),
                .business_activity_id = business_activity_id,
            });
        }
        return items.toOwnedSlice(allocator);
    }

    fn loadSnapshots(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_id: []const u8,
    ) ![]OwnedSnapshotField {
        var statement = try self.prepare(
            \\SELECT role, field_id, reusable_field, value_type, value_text,
            \\       provenance, profile_revision_id,
            \\       profile_revision_sequence, revision_source_tag,
            \\       revision_source_reference, business_activity_id,
            \\       registration_fact_id, overridden
            \\FROM tax_form_draft_snapshot_fields
            \\WHERE draft_id = ?
            \\ORDER BY field_id COLLATE BINARY;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        var items: std.ArrayList(OwnedSnapshotField) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const role = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(role);
            const field_id = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(field_id);
            const reusable_field = try dupColumn(allocator, statement.raw, 2);
            errdefer allocator.free(reusable_field);
            const value_type = try dupColumn(allocator, statement.raw, 3);
            errdefer allocator.free(value_type);
            const value_text = try dupColumn(allocator, statement.raw, 4);
            errdefer allocator.free(value_text);
            const provenance = try dupColumn(allocator, statement.raw, 5);
            errdefer allocator.free(provenance);
            const profile_revision_id = try dupColumn(
                allocator,
                statement.raw,
                6,
            );
            errdefer allocator.free(profile_revision_id);
            const sequence_raw = sqlite.sqlite3_column_int64(statement.raw, 7);
            if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
                return Error.SqliteFailure;
            }
            var revision_source = try readRevisionSource(
                allocator,
                statement.raw,
                8,
                9,
            );
            errdefer revision_source.deinit(allocator);
            const business_activity_id = try dupOptionalColumn(
                allocator,
                statement.raw,
                10,
            );
            errdefer freeOptional(allocator, business_activity_id);
            const registration_fact_id = try dupOptionalColumn(
                allocator,
                statement.raw,
                11,
            );
            errdefer freeOptional(allocator, registration_fact_id);
            try items.append(allocator, .{
                .role = role,
                .field_id = field_id,
                .reusable_field = reusable_field,
                .value_type = value_type,
                .value_text = value_text,
                .provenance = provenance,
                .profile_revision_id = profile_revision_id,
                .profile_revision_sequence = @intCast(sequence_raw),
                .revision_source = revision_source,
                .business_activity_id = business_activity_id,
                .registration_fact_id = registration_fact_id,
                .overridden = sqlite.sqlite3_column_int(statement.raw, 12) != 0,
            });
        }
        return items.toOwnedSlice(allocator);
    }

    fn loadDraftValues(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_id: []const u8,
    ) ![]OwnedDraftValue {
        var statement = try self.prepare(
            \\SELECT field_id, value_text, provenance
            \\FROM tax_form_draft_values
            \\WHERE draft_id = ?
            \\ORDER BY field_id COLLATE BINARY;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        var items: std.ArrayList(OwnedDraftValue) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const field_id = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(field_id);
            const value_text = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(value_text);
            const provenance = try dupColumn(allocator, statement.raw, 2);
            errdefer allocator.free(provenance);
            try items.append(allocator, .{
                .field_id = field_id,
                .value_text = value_text,
                .provenance = provenance,
            });
        }
        return items.toOwnedSlice(allocator);
    }

    fn draftAcceptsEdits(self: *Store, draft_id: []const u8) !bool {
        var statement = try self.prepare(
            \\SELECT lifecycle FROM tax_form_drafts WHERE id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        if (try statement.step() == .done) return Error.NotFound;
        const lifecycle = columnText(statement.raw, 0) orelse
            return Error.SqliteFailure;
        return std.mem.eql(u8, lifecycle, "editing");
    }

    fn draftExists(self: *Store, draft_id: []const u8) !bool {
        var statement = try self.prepare(
            "SELECT 1 FROM tax_form_drafts WHERE id = ?;",
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        return try statement.step() == .row;
    }

    fn currentRevisionSequence(
        self: *Store,
        profile_id: []const u8,
    ) !?u32 {
        var statement = try self.prepare(
            \\SELECT r.sequence
            \\FROM tax_profiles AS p
            \\JOIN tax_profile_revisions AS r
            \\  ON r.profile_id = p.id AND r.id = p.current_revision_id
            \\WHERE p.id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        return switch (try statement.step()) {
            .done => null,
            .row => blk: {
                const sequence = sqlite.sqlite3_column_int64(statement.raw, 0);
                if (sequence <= 0 or sequence > std.math.maxInt(u32)) {
                    return Error.SqliteFailure;
                }
                break :blk @intCast(sequence);
            },
        };
    }

    fn profileExists(self: *Store, profile_id: []const u8) !bool {
        var statement = try self.prepare(
            "SELECT 1 FROM tax_profiles WHERE id = ?;",
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        return try statement.step() == .row;
    }

    fn readRevision(
        self: *Store,
        allocator: std.mem.Allocator,
        row: *sqlite.sqlite3_stmt,
    ) !OwnedProfileRevision {
        const id = try dupColumn(allocator, row, 0);
        errdefer allocator.free(id);
        const sequence_raw = sqlite.sqlite3_column_int64(row, 1);
        if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
            return Error.SqliteFailure;
        }
        const profile_id = try dupColumn(allocator, row, 2);
        errdefer allocator.free(profile_id);
        const effective_from = try dupColumn(allocator, row, 3);
        errdefer allocator.free(effective_from);
        const effective_until = try dupOptionalColumn(allocator, row, 4);
        errdefer freeOptional(allocator, effective_until);
        var source = try readRevisionSource(allocator, row, 5, 6);
        errdefer source.deinit(allocator);
        const tin = try dupColumn(allocator, row, 7);
        errdefer allocator.free(tin);
        const rdo_code = try dupColumn(allocator, row, 8);
        errdefer allocator.free(rdo_code);
        const registered_address = try dupColumn(allocator, row, 9);
        errdefer allocator.free(registered_address);
        const zip_code = try dupOptionalColumn(allocator, row, 10);
        errdefer freeOptional(allocator, zip_code);
        const contact_number = try dupOptionalColumn(allocator, row, 11);
        errdefer freeOptional(allocator, contact_number);
        const email_address = try dupOptionalColumn(allocator, row, 12);
        errdefer freeOptional(allocator, email_address);
        var subject = try readSubject(allocator, row, 13);
        errdefer subject.deinit(allocator);
        const activities = try self.loadBusinessActivities(
            allocator,
            profile_id,
            id,
        );
        errdefer {
            for (activities) |*activity| activity.deinit(allocator);
            allocator.free(activities);
        }
        const facts = try self.loadRegistrationFacts(
            allocator,
            profile_id,
            id,
        );
        errdefer {
            for (facts) |*fact| fact.deinit(allocator);
            allocator.free(facts);
        }

        return .{
            .id = id,
            .sequence = @intCast(sequence_raw),
            .profile_id = profile_id,
            .effective_from = effective_from,
            .effective_until = effective_until,
            .source = source,
            .tin = tin,
            .rdo_code = rdo_code,
            .contact = .{
                .registered_address = registered_address,
                .zip_code = zip_code,
                .contact_number = contact_number,
                .email_address = email_address,
            },
            .subject = subject,
            .business_activities = activities,
            .registration_facts = facts,
        };
    }

    fn loadBusinessActivities(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        revision_id: []const u8,
    ) ![]OwnedBusinessActivity {
        var statement = try self.prepare(
            \\SELECT id, line_of_business, atc, effective_from,
            \\       effective_until, ordinal
            \\FROM tax_profile_business_activities
            \\WHERE profile_id = ? AND revision_id = ?
            \\ORDER BY ordinal, id;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindText(2, revision_id);

        var items: std.ArrayList(OwnedBusinessActivity) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const id = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(id);
            const line_of_business = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(line_of_business);
            const atc = try dupOptionalColumn(allocator, statement.raw, 2);
            errdefer freeOptional(allocator, atc);
            const effective_from = try dupColumn(allocator, statement.raw, 3);
            errdefer allocator.free(effective_from);
            const effective_until = try dupOptionalColumn(
                allocator,
                statement.raw,
                4,
            );
            errdefer freeOptional(allocator, effective_until);
            const ordinal_raw = sqlite.sqlite3_column_int64(statement.raw, 5);
            if (ordinal_raw < 0 or ordinal_raw > std.math.maxInt(u32)) {
                return Error.SqliteFailure;
            }
            try items.append(allocator, .{
                .id = id,
                .line_of_business = line_of_business,
                .atc = atc,
                .effective_from = effective_from,
                .effective_until = effective_until,
                .ordinal = @intCast(ordinal_raw),
            });
        }
        return items.toOwnedSlice(allocator);
    }

    fn loadRegistrationFacts(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        revision_id: []const u8,
    ) ![]OwnedRegistrationFact {
        var statement = try self.prepare(
            \\SELECT id, kind, value_text, effective_from,
            \\       effective_until, ordinal
            \\FROM tax_profile_registration_facts
            \\WHERE profile_id = ? AND revision_id = ?
            \\ORDER BY ordinal, id;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindText(2, revision_id);

        var items: std.ArrayList(OwnedRegistrationFact) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const id = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(id);
            var value = try readRegistrationFactValue(
                allocator,
                statement.raw,
                1,
                2,
            );
            errdefer value.deinit(allocator);
            const effective_from = try dupColumn(allocator, statement.raw, 3);
            errdefer allocator.free(effective_from);
            const effective_until = try dupOptionalColumn(
                allocator,
                statement.raw,
                4,
            );
            errdefer freeOptional(allocator, effective_until);
            const ordinal_raw = sqlite.sqlite3_column_int64(statement.raw, 5);
            if (ordinal_raw < 0 or ordinal_raw > std.math.maxInt(u32)) {
                return Error.SqliteFailure;
            }
            try items.append(allocator, .{
                .id = id,
                .effective_from = effective_from,
                .effective_until = effective_until,
                .value = value,
                .ordinal = @intCast(ordinal_raw),
            });
        }
        return items.toOwnedSlice(allocator);
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
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }

    fn bindDate(self: *Statement, index: c_int, value: []const u8) !void {
        try self.bindText(index, value);
    }

    fn bindOptionalDate(
        self: *Statement,
        index: c_int,
        value: ?[]const u8,
    ) !void {
        if (value) |date| return self.bindDate(index, date);
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }

    fn bindInt64(self: *Statement, index: c_int, value: i64) !void {
        const rc = sqlite.sqlite3_bind_int64(self.raw, index, value);
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn bindOptionalInt64(
        self: *Statement,
        index: c_int,
        value: ?i64,
    ) !void {
        if (value) |number| return self.bindInt64(index, number);
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
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

fn readProfileSummary(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
) !OwnedProfileSummary {
    const id = try dupColumn(allocator, row, 0);
    errdefer allocator.free(id);
    const status_text = columnText(row, 1) orelse return Error.SqliteFailure;
    const status = parseProfileStatus(status_text) orelse return Error.SqliteFailure;
    const current_revision_id = try dupColumn(allocator, row, 2);
    errdefer allocator.free(current_revision_id);
    const sequence_raw = sqlite.sqlite3_column_int64(row, 3);
    if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
        return Error.SqliteFailure;
    }
    const display_name = try dupColumn(allocator, row, 4);
    errdefer allocator.free(display_name);
    const tin = try dupColumn(allocator, row, 5);
    errdefer allocator.free(tin);
    const subject_kind_text = columnText(row, 6) orelse return Error.SqliteFailure;
    const subject_kind = parseSubjectKind(subject_kind_text) orelse
        return Error.SqliteFailure;
    return .{
        .id = id,
        .status = status,
        .current_revision_id = current_revision_id,
        .current_revision_sequence = @intCast(sequence_raw),
        .display_name = display_name,
        .tin = tin,
        .subject_kind = subject_kind,
    };
}

fn readRevisionSource(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    tag_column: c_int,
    reference_column: c_int,
) !OwnedRevisionSource {
    const tag_text = columnText(row, tag_column) orelse
        return Error.SqliteFailure;
    const tag = parseRevisionSourceTag(tag_text) orelse
        return Error.SqliteFailure;
    return switch (tag) {
        .manual_entry => {
            if (sqlite.sqlite3_column_type(row, reference_column) !=
                sqlite.SQLITE_NULL)
            {
                return Error.SqliteFailure;
            }
            return .{ .manual_entry = {} };
        },
        .imported => .{
            .imported = try dupColumn(allocator, row, reference_column),
        },
        .migrated => .{
            .migrated = try dupColumn(allocator, row, reference_column),
        },
    };
}

fn readSubject(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    kind_column: c_int,
) !OwnedSubject {
    const kind_text = columnText(row, kind_column) orelse
        return Error.SqliteFailure;
    const kind = parseSubjectKind(kind_text) orelse return Error.SqliteFailure;
    const taxpayer_name_column = kind_column + 1;
    const registered_name_column = kind_column + 2;
    const birth_date_column = kind_column + 3;
    const citizenship_column = kind_column + 4;
    const foreign_tax_number_column = kind_column + 5;

    switch (kind) {
        .individual, .sole_proprietor => {
            const name = try dupColumn(allocator, row, taxpayer_name_column);
            errdefer allocator.free(name);
            const date_of_birth = try dupOptionalColumn(
                allocator,
                row,
                birth_date_column,
            );
            errdefer freeOptional(allocator, date_of_birth);
            const citizenship = try dupOptionalColumn(
                allocator,
                row,
                citizenship_column,
            );
            errdefer freeOptional(allocator, citizenship);
            const foreign_tax_number = try dupOptionalColumn(
                allocator,
                row,
                foreign_tax_number_column,
            );
            errdefer freeOptional(allocator, foreign_tax_number);
            const person: OwnedIndividual = .{
                .name = name,
                .date_of_birth = date_of_birth,
                .citizenship = citizenship,
                .foreign_tax_number = foreign_tax_number,
            };
            if (kind == .individual) {
                if (sqlite.sqlite3_column_type(row, registered_name_column) !=
                    sqlite.SQLITE_NULL)
                {
                    return Error.SqliteFailure;
                }
                return .{ .individual = person };
            }
            const trade_name = try dupOptionalColumn(
                allocator,
                row,
                registered_name_column,
            );
            return .{ .sole_proprietor = .{
                .person = person,
                .trade_name = trade_name,
            } };
        },
        .corporation,
        .partnership,
        .estate,
        .trust,
        .other_legal_entity,
        => {
            const registered_name = try dupColumn(
                allocator,
                row,
                registered_name_column,
            );
            errdefer allocator.free(registered_name);
            return .{ .legal_entity = .{
                .registered_name = registered_name,
                .kind = switch (kind) {
                    .corporation => .corporation,
                    .partnership => .partnership,
                    .estate => .estate,
                    .trust => .trust,
                    .other_legal_entity => .other,
                    else => unreachable,
                },
            } };
        },
    }
}

fn readRegistrationFactValue(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    kind_column: c_int,
    value_column: c_int,
) !OwnedRegistrationFactValue {
    const kind_text = columnText(row, kind_column) orelse
        return Error.SqliteFailure;
    const kind = parseRegistrationFactKind(kind_text) orelse
        return Error.SqliteFailure;
    return switch (kind) {
        .tax_type => .{
            .tax_type = try dupColumn(allocator, row, value_column),
        },
        .government_withholding_agent => blk: {
            const value_text = columnText(row, value_column) orelse
                return Error.SqliteFailure;
            const value = parseGovernmentWithholdingAgent(value_text) orelse
                return Error.SqliteFailure;
            break :blk .{ .government_withholding_agent = value };
        },
        .special_rate_basis => .{
            .special_rate_basis = try dupColumn(
                allocator,
                row,
                value_column,
            ),
        },
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

fn mapResult(rc: c_int) Error {
    const primary = rc & 0xff;
    return switch (primary) {
        sqlite.SQLITE_BUSY, sqlite.SQLITE_LOCKED => Error.SqliteBusy,
        sqlite.SQLITE_CONSTRAINT => Error.SqliteConstraint,
        else => Error.SqliteFailure,
    };
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]u8) void {
    if (value) |bytes| allocator.free(bytes);
}

fn optionalDateSlice(value: *const ?DateText) ?[]const u8 {
    if (value.*) |*date| return date[0..];
    return null;
}

fn parseProfileStatus(value: []const u8) ?ProfileStatus {
    inline for (std.meta.fields(ProfileStatus)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseSubjectKind(value: []const u8) ?SubjectKind {
    inline for (std.meta.fields(SubjectKind)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseRevisionSourceTag(value: []const u8) ?RevisionSourceTag {
    inline for (std.meta.fields(RevisionSourceTag)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseRegistrationFactKind(value: []const u8) ?RegistrationFactKind {
    inline for (std.meta.fields(RegistrationFactKind)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseGovernmentWithholdingAgent(
    value: []const u8,
) ?GovernmentWithholdingAgent {
    inline for (std.meta.fields(GovernmentWithholdingAgent)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn validateProfileCreate(value: ProfileCreate) Error!void {
    try validateIdText(value.id);
}

fn validateRevision(
    value: RevisionWrite,
    components: RevisionComponentsWrite,
) Error!void {
    try validateIdText(value.id);
    try validateIdText(value.profile_id);
    if (value.sequence == 0) return Error.InvalidValue;
    try validatePeriod(value.effective);
    switch (value.source) {
        .manual_entry => {},
        .imported => |reference| try requireValue(reference),
        .migrated => |reference| try requireValue(reference),
    }
    try requireValue(value.identity.tin);
    try requireValue(value.identity.rdo_code);
    try requireValue(value.contact.registered_address);
    try validateOptionalValue(value.contact.zip_code);
    try validateOptionalValue(value.contact.contact_number);
    try validateOptionalValue(value.contact.email_address);
    switch (value.subject) {
        .individual => |person| try validateIndividual(person),
        .sole_proprietor => |proprietor| {
            try validateIndividual(proprietor.person);
            try validateOptionalValue(proprietor.trade_name);
        },
        .legal_entity => |entity| try requireValue(entity.registered_name),
    }
    for (components.business_activities, 0..) |activity, index| {
        try validateIdText(activity.id);
        try requireValue(activity.line_of_business);
        try validateOptionalValue(activity.atc);
        try validatePeriod(activity.effective);
        for (components.business_activities[index + 1 ..]) |other| {
            if (std.mem.eql(u8, activity.id, other.id)) {
                return Error.InvalidValue;
            }
        }
    }
    for (components.registration_facts, 0..) |fact, index| {
        try validateIdText(fact.id);
        try validatePeriod(fact.effective);
        switch (fact.value) {
            .tax_type => |text| try requireValue(text),
            .government_withholding_agent => {},
            .special_rate_basis => |text| try requireValue(text),
        }
        const kind: RegistrationFactKind = fact.value;
        for (components.registration_facts[index + 1 ..]) |other| {
            if (std.mem.eql(u8, fact.id, other.id)) {
                return Error.InvalidValue;
            }
            const other_kind: RegistrationFactKind = other.value;
            if (kind == other_kind and
                periodsOverlap(fact.effective, other.effective))
            {
                return Error.InvalidValue;
            }
        }
    }
}

fn validateIndividual(value: IndividualWrite) Error!void {
    try requireValue(value.name);
    if (value.date_of_birth) |date| try validateDate(date[0..]);
    try validateOptionalValue(value.citizenship);
    try validateOptionalValue(value.foreign_tax_number);
}

fn validatePeriod(value: EffectivePeriodWrite) Error!void {
    try validateDate(value.from[0..]);
    if (value.until) |until| {
        try validateDate(until[0..]);
        if (std.mem.order(u8, value.from[0..], until[0..]) == .gt) {
            return Error.InvalidDate;
        }
    }
}

fn periodsOverlap(
    left: EffectivePeriodWrite,
    right: EffectivePeriodWrite,
) bool {
    if (left.until) |last| {
        if (std.mem.order(u8, last[0..], right.from[0..]) == .lt) return false;
    }
    if (right.until) |last| {
        if (std.mem.order(u8, last[0..], left.from[0..]) == .lt) return false;
    }
    return true;
}

fn validateDraft(
    draft: DraftWrite,
    bindings: []const RoleBindingWrite,
    snapshots: []const SnapshotFieldWrite,
    values: []const DraftValueWrite,
) Error!void {
    try validateOpaqueText(draft.id);
    try requireValue(draft.form_code);
    try requireValue(draft.form_revision);
    try requireValue(draft.period_key);
    try validateDate(draft.profile_as_of[0..]);
    try requireValue(draft.mapping_revision);
    if (!validLifecycle(draft.lifecycle)) return Error.InvalidTransition;
    if (std.mem.eql(u8, draft.intent, "original")) {
        if (draft.amendment_of != null) return Error.InvalidAmendment;
    } else if (std.mem.eql(u8, draft.intent, "amended")) {
        const prior = draft.amendment_of orelse return Error.InvalidAmendment;
        try validateOpaqueText(prior);
    } else {
        return Error.InvalidAmendment;
    }
    for (bindings) |binding| {
        try requireValue(binding.role);
        try validateIdText(binding.profile_id);
        try validateIdText(binding.profile_revision_id);
        if (binding.profile_revision_sequence == 0) return Error.InvalidValue;
        if (binding.business_activity_id) |id| try validateIdText(id);
    }
    for (snapshots) |snapshot| {
        try requireValue(snapshot.role);
        try requireValue(snapshot.field_id);
        try requireValue(snapshot.reusable_field);
        try requireValue(snapshot.value_type);
        try requireValue(snapshot.provenance);
        try validateIdText(snapshot.profile_revision_id);
        if (snapshot.profile_revision_sequence == 0) return Error.InvalidValue;
        switch (snapshot.revision_source) {
            .manual_entry => {},
            .imported => |reference| try requireValue(reference),
            .migrated => |reference| try requireValue(reference),
        }
        if (snapshot.business_activity_id) |id| try validateIdText(id);
        if (snapshot.registration_fact_id) |id| try validateIdText(id);
        const binding = findBinding(bindings, snapshot.role) orelse
            return Error.InvalidValue;
        if (snapshot.business_activity_id) |activity_id| {
            const selected = binding.business_activity_id orelse
                return Error.InvalidValue;
            if (!std.mem.eql(u8, activity_id, selected)) {
                return Error.InvalidValue;
            }
        }
    }
    try validateDraftValues(values);
}

fn validateDraftValues(values: []const DraftValueWrite) Error!void {
    for (values, 0..) |value, index| {
        try requireValue(value.field_id);
        try requireValue(value.provenance);
        for (values[index + 1 ..]) |other| {
            if (std.mem.eql(u8, value.field_id, other.field_id)) {
                return Error.InvalidValue;
            }
        }
    }
}

fn findBinding(
    bindings: []const RoleBindingWrite,
    role: []const u8,
) ?RoleBindingWrite {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.role, role)) return binding;
    }
    return null;
}

fn validLifecycle(value: []const u8) bool {
    const allowed = [_][]const u8{
        "editing",
        "prepared",
        "queued",
        "submitted",
        "confirmed",
        "paid",
        "cancelled",
    };
    for (allowed) |candidate| {
        if (std.mem.eql(u8, value, candidate)) return true;
    }
    return false;
}

fn lifecycleTransitionAllowed(current: []const u8, next: []const u8) bool {
    if (std.mem.eql(u8, current, "editing")) {
        return std.mem.eql(u8, next, "prepared") or
            std.mem.eql(u8, next, "cancelled");
    }
    if (std.mem.eql(u8, current, "prepared")) {
        return std.mem.eql(u8, next, "editing") or
            std.mem.eql(u8, next, "queued") or
            std.mem.eql(u8, next, "cancelled");
    }
    if (std.mem.eql(u8, current, "queued")) {
        return std.mem.eql(u8, next, "submitted") or
            std.mem.eql(u8, next, "cancelled");
    }
    if (std.mem.eql(u8, current, "submitted")) {
        return std.mem.eql(u8, next, "confirmed");
    }
    if (std.mem.eql(u8, current, "confirmed")) {
        return std.mem.eql(u8, next, "paid");
    }
    return false;
}

fn validateOptionalValue(value: ?[]const u8) Error!void {
    if (value) |text| try requireValue(text);
}

fn validateIdText(value: []const u8) Error!void {
    const normalized = trimmed(value);
    if (normalized.len == 0 or normalized.len > 64) return Error.InvalidValue;
    if (normalized.len != value.len) return Error.InvalidValue;
    for (normalized) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and
            byte != '-' and byte != '_' and byte != '.' and byte != ':')
        {
            return Error.InvalidValue;
        }
    }
}

fn validateOpaqueText(value: []const u8) Error!void {
    try validateIdText(value);
}

fn validateTaxYear(value: i32) Error!void {
    if (value < 1 or value > 9999) return Error.InvalidValue;
}

fn requireValue(value: []const u8) Error!void {
    if (trimmed(value).len == 0) return Error.InvalidValue;
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
    \\CREATE TABLE tax_profiles (
    \\    id TEXT PRIMARY KEY
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    status TEXT NOT NULL DEFAULT 'active'
    \\        CHECK (status IN ('active', 'archived')),
    \\    current_revision_id TEXT,
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    FOREIGN KEY (id, current_revision_id)
    \\        REFERENCES tax_profile_revisions(profile_id, id)
    \\        ON UPDATE RESTRICT ON DELETE RESTRICT
    \\        DEFERRABLE INITIALLY DEFERRED
    \\);
    \\
    \\CREATE TABLE tax_profile_revisions (
    \\    storage_rowid INTEGER PRIMARY KEY,
    \\    id TEXT NOT NULL
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE CASCADE,
    \\    sequence INTEGER NOT NULL CHECK (
    \\        sequence > 0 AND sequence <= 4294967295
    \\    ),
    \\    effective_from TEXT NOT NULL,
    \\    effective_until TEXT,
    \\    source_tag TEXT NOT NULL
    \\        CHECK (source_tag IN ('manual_entry', 'imported', 'migrated')),
    \\    source_reference TEXT,
    \\    tin TEXT NOT NULL CHECK (length(trim(tin)) > 0),
    \\    rdo_code TEXT NOT NULL CHECK (length(trim(rdo_code)) > 0),
    \\    registered_address TEXT NOT NULL
    \\        CHECK (length(trim(registered_address)) > 0),
    \\    zip_code TEXT,
    \\    contact_number TEXT,
    \\    email_address TEXT,
    \\    subject_kind TEXT NOT NULL
    \\        CHECK (subject_kind IN (
    \\            'individual', 'sole_proprietor', 'corporation',
    \\            'partnership', 'estate', 'trust', 'other_legal_entity'
    \\        )),
    \\    taxpayer_name TEXT,
    \\    registered_name TEXT,
    \\    date_of_birth TEXT,
    \\    citizenship TEXT,
    \\    foreign_tax_number TEXT,
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    UNIQUE (profile_id, id),
    \\    UNIQUE (profile_id, sequence),
    \\    UNIQUE (profile_id, id, sequence),
    \\    CHECK (
    \\        effective_until IS NULL OR effective_from <= effective_until
    \\    ),
    \\    CHECK (
    \\        (source_tag = 'manual_entry' AND source_reference IS NULL) OR
    \\        (source_tag IN ('imported', 'migrated') AND
    \\            length(trim(source_reference)) > 0)
    \\    ),
    \\    CHECK (
    \\        (subject_kind = 'individual' AND
    \\            length(trim(taxpayer_name)) > 0 AND
    \\            registered_name IS NULL) OR
    \\        (subject_kind = 'sole_proprietor' AND
    \\            length(trim(taxpayer_name)) > 0) OR
    \\        (subject_kind IN (
    \\            'corporation', 'partnership', 'estate', 'trust',
    \\            'other_legal_entity'
    \\        ) AND
    \\            taxpayer_name IS NULL AND
    \\            length(trim(registered_name)) > 0 AND
    \\            date_of_birth IS NULL AND citizenship IS NULL AND
    \\            foreign_tax_number IS NULL)
    \\    )
    \\);
    \\CREATE INDEX tax_profile_revisions_effective_idx
    \\    ON tax_profile_revisions(profile_id, effective_from, effective_until);
    \\
    \\CREATE TRIGGER tax_profile_revisions_immutable
    \\BEFORE UPDATE ON tax_profile_revisions
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'tax profile revisions are append-only');
    \\END;
    \\
    \\CREATE TABLE tax_profile_business_activities (
    \\    profile_id TEXT NOT NULL,
    \\    revision_id TEXT NOT NULL,
    \\    id TEXT NOT NULL
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    line_of_business TEXT NOT NULL
    \\        CHECK (length(trim(line_of_business)) > 0),
    \\    atc TEXT,
    \\    effective_from TEXT NOT NULL,
    \\    effective_until TEXT,
    \\    ordinal INTEGER NOT NULL DEFAULT 0 CHECK (ordinal >= 0),
    \\    PRIMARY KEY (profile_id, revision_id, id),
    \\    FOREIGN KEY (profile_id, revision_id)
    \\        REFERENCES tax_profile_revisions(profile_id, id)
    \\        ON DELETE CASCADE,
    \\    CHECK (
    \\        effective_until IS NULL OR effective_from <= effective_until
    \\    )
    \\);
    \\CREATE INDEX tax_profile_business_activities_order_idx
    \\    ON tax_profile_business_activities(
    \\        profile_id, revision_id, ordinal, id
    \\    );
    \\
    \\CREATE TRIGGER tax_profile_business_activities_immutable
    \\BEFORE UPDATE ON tax_profile_business_activities
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'business activities are immutable');
    \\END;
    \\
    \\CREATE TABLE tax_profile_registration_facts (
    \\    profile_id TEXT NOT NULL,
    \\    revision_id TEXT NOT NULL,
    \\    id TEXT NOT NULL
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    kind TEXT NOT NULL CHECK (kind IN (
    \\        'tax_type', 'government_withholding_agent',
    \\        'special_rate_basis'
    \\    )),
    \\    value_text TEXT NOT NULL CHECK (length(trim(value_text)) > 0),
    \\    effective_from TEXT NOT NULL,
    \\    effective_until TEXT,
    \\    ordinal INTEGER NOT NULL DEFAULT 0 CHECK (ordinal >= 0),
    \\    PRIMARY KEY (profile_id, revision_id, id),
    \\    FOREIGN KEY (profile_id, revision_id)
    \\        REFERENCES tax_profile_revisions(profile_id, id)
    \\        ON DELETE CASCADE,
    \\    CHECK (
    \\        effective_until IS NULL OR effective_from <= effective_until
    \\    ),
    \\    CHECK (
    \\        kind <> 'government_withholding_agent' OR
    \\        value_text IN ('no', 'yes')
    \\    )
    \\);
    \\CREATE INDEX tax_profile_registration_facts_order_idx
    \\    ON tax_profile_registration_facts(
    \\        profile_id, revision_id, ordinal, id
    \\    );
    \\
    \\CREATE TRIGGER tax_profile_registration_facts_immutable
    \\BEFORE UPDATE ON tax_profile_registration_facts
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'registration facts are immutable');
    \\END;
    \\
    \\CREATE TABLE tax_profile_form_sets (
    \\    profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE CASCADE,
    \\    tax_year INTEGER NOT NULL CHECK (tax_year BETWEEN 1 AND 9999),
    \\    configured_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (profile_id, tax_year)
    \\);
    \\
    \\CREATE TABLE tax_profile_form_set_entries (
    \\    profile_id TEXT NOT NULL,
    \\    tax_year INTEGER NOT NULL,
    \\    form_code TEXT NOT NULL CHECK (length(trim(form_code)) > 0),
    \\    form_revision TEXT NOT NULL
    \\        CHECK (length(trim(form_revision)) > 0),
    \\    PRIMARY KEY (profile_id, tax_year, form_code, form_revision),
    \\    FOREIGN KEY (profile_id, tax_year)
    \\        REFERENCES tax_profile_form_sets(profile_id, tax_year)
    \\        ON DELETE CASCADE
    \\);
    \\
    \\CREATE TABLE tax_form_drafts (
    \\    id TEXT PRIMARY KEY
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    form_code TEXT NOT NULL CHECK (length(trim(form_code)) > 0),
    \\    form_revision TEXT NOT NULL
    \\        CHECK (length(trim(form_revision)) > 0),
    \\    period_key TEXT NOT NULL CHECK (length(trim(period_key)) > 0),
    \\    profile_as_of TEXT NOT NULL,
    \\    lifecycle TEXT NOT NULL CHECK (lifecycle IN (
    \\        'editing', 'prepared', 'queued', 'submitted', 'confirmed',
    \\        'paid', 'cancelled'
    \\    )),
    \\    intent TEXT NOT NULL CHECK (intent IN ('original', 'amended')),
    \\    mapping_revision TEXT NOT NULL
    \\        CHECK (length(trim(mapping_revision)) > 0),
    \\    amendment_of TEXT
    \\        REFERENCES tax_form_drafts(id) ON DELETE RESTRICT,
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    CHECK (amendment_of IS NULL OR amendment_of <> id),
    \\    CHECK (
    \\        (intent = 'original' AND amendment_of IS NULL) OR
    \\        (intent = 'amended' AND amendment_of IS NOT NULL)
    \\    )
    \\);
    \\
    \\CREATE TABLE tax_form_draft_role_bindings (
    \\    draft_id TEXT NOT NULL
    \\        REFERENCES tax_form_drafts(id) ON DELETE CASCADE,
    \\    role TEXT NOT NULL CHECK (length(trim(role)) > 0),
    \\    profile_id TEXT NOT NULL,
    \\    profile_revision_id TEXT NOT NULL,
    \\    profile_revision_sequence INTEGER NOT NULL CHECK (
    \\        profile_revision_sequence > 0 AND
    \\        profile_revision_sequence <= 4294967295
    \\    ),
    \\    business_activity_id TEXT,
    \\    PRIMARY KEY (draft_id, role),
    \\    UNIQUE (
    \\        draft_id, role, profile_revision_id, profile_revision_sequence
    \\    ),
    \\    FOREIGN KEY (
    \\        profile_id, profile_revision_id, profile_revision_sequence
    \\    ) REFERENCES tax_profile_revisions(profile_id, id, sequence)
    \\        ON DELETE RESTRICT,
    \\    FOREIGN KEY (
    \\        profile_id, profile_revision_id, business_activity_id
    \\    ) REFERENCES tax_profile_business_activities(
    \\        profile_id, revision_id, id
    \\    )
    \\        ON DELETE RESTRICT
    \\);
    \\CREATE INDEX tax_form_draft_role_profile_idx
    \\    ON tax_form_draft_role_bindings(
    \\        profile_id, profile_revision_id, profile_revision_sequence
    \\    );
    \\
    \\CREATE TABLE tax_form_draft_snapshot_fields (
    \\    draft_id TEXT NOT NULL,
    \\    role TEXT NOT NULL,
    \\    field_id TEXT NOT NULL CHECK (length(trim(field_id)) > 0),
    \\    reusable_field TEXT NOT NULL
    \\        CHECK (length(trim(reusable_field)) > 0),
    \\    value_type TEXT NOT NULL CHECK (length(trim(value_type)) > 0),
    \\    value_text TEXT NOT NULL,
    \\    provenance TEXT NOT NULL CHECK (length(trim(provenance)) > 0),
    \\    profile_revision_id TEXT NOT NULL,
    \\    profile_revision_sequence INTEGER NOT NULL CHECK (
    \\        profile_revision_sequence > 0 AND
    \\        profile_revision_sequence <= 4294967295
    \\    ),
    \\    revision_source_tag TEXT NOT NULL CHECK (
    \\        revision_source_tag IN ('manual_entry', 'imported', 'migrated')
    \\    ),
    \\    revision_source_reference TEXT,
    \\    business_activity_id TEXT,
    \\    registration_fact_id TEXT,
    \\    overridden INTEGER NOT NULL DEFAULT 0
    \\        CHECK (overridden IN (0, 1)),
    \\    PRIMARY KEY (draft_id, field_id),
    \\    FOREIGN KEY (
    \\        draft_id, role, profile_revision_id, profile_revision_sequence
    \\    )
    \\        REFERENCES tax_form_draft_role_bindings(
    \\            draft_id, role, profile_revision_id,
    \\            profile_revision_sequence
    \\        ) ON DELETE CASCADE
    \\    ,
    \\    CHECK (
    \\        (revision_source_tag = 'manual_entry' AND
    \\            revision_source_reference IS NULL) OR
    \\        (revision_source_tag IN ('imported', 'migrated') AND
    \\            length(trim(revision_source_reference)) > 0)
    \\    )
    \\);
    \\
    \\CREATE TRIGGER tax_form_draft_snapshot_fields_immutable
    \\BEFORE UPDATE ON tax_form_draft_snapshot_fields
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'prefill snapshots are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_form_draft_snapshot_activity_valid
    \\BEFORE INSERT ON tax_form_draft_snapshot_fields
    \\WHEN NEW.business_activity_id IS NOT NULL AND NOT EXISTS (
    \\    SELECT 1
    \\    FROM tax_form_draft_role_bindings AS b
    \\    JOIN tax_profile_business_activities AS a
    \\      ON a.profile_id = b.profile_id
    \\     AND a.revision_id = b.profile_revision_id
    \\     AND a.id = NEW.business_activity_id
    \\    WHERE b.draft_id = NEW.draft_id
    \\      AND b.role = NEW.role
    \\      AND b.profile_revision_id = NEW.profile_revision_id
    \\      AND b.profile_revision_sequence =
    \\          NEW.profile_revision_sequence
    \\      AND b.business_activity_id = NEW.business_activity_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'invalid snapshot business activity');
    \\END;
    \\
    \\CREATE TRIGGER tax_form_draft_snapshot_fact_valid
    \\BEFORE INSERT ON tax_form_draft_snapshot_fields
    \\WHEN NEW.registration_fact_id IS NOT NULL AND NOT EXISTS (
    \\    SELECT 1
    \\    FROM tax_form_draft_role_bindings AS b
    \\    JOIN tax_profile_registration_facts AS f
    \\      ON f.profile_id = b.profile_id
    \\     AND f.revision_id = b.profile_revision_id
    \\     AND f.id = NEW.registration_fact_id
    \\    WHERE b.draft_id = NEW.draft_id
    \\      AND b.role = NEW.role
    \\      AND b.profile_revision_id = NEW.profile_revision_id
    \\      AND b.profile_revision_sequence =
    \\          NEW.profile_revision_sequence
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'invalid snapshot registration fact');
    \\END;
    \\
    \\CREATE TABLE tax_form_draft_values (
    \\    draft_id TEXT NOT NULL
    \\        REFERENCES tax_form_drafts(id) ON DELETE CASCADE,
    \\    field_id TEXT NOT NULL CHECK (length(trim(field_id)) > 0),
    \\    value_text TEXT NOT NULL,
    \\    provenance TEXT NOT NULL CHECK (length(trim(provenance)) > 0),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (draft_id, field_id)
    \\);
;

const schema_v2 =
    \\CREATE TRIGGER tax_profile_revisions_delete_guard
    \\BEFORE DELETE ON tax_profile_revisions
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'tax profile revisions are append-only');
    \\END;
    \\
    \\CREATE TRIGGER tax_profile_business_activities_delete_guard
    \\BEFORE DELETE ON tax_profile_business_activities
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'business activities are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_profile_registration_facts_delete_guard
    \\BEFORE DELETE ON tax_profile_registration_facts
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'registration facts are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_form_draft_role_bindings_update_guard
    \\BEFORE UPDATE ON tax_form_draft_role_bindings
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'profile role bindings are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_form_draft_role_bindings_delete_guard
    \\BEFORE DELETE ON tax_form_draft_role_bindings
    \\WHEN EXISTS (
    \\    SELECT 1 FROM tax_form_drafts WHERE id = OLD.draft_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'profile role bindings are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_form_draft_snapshot_fields_delete_guard
    \\BEFORE DELETE ON tax_form_draft_snapshot_fields
    \\WHEN EXISTS (
    \\    SELECT 1 FROM tax_form_drafts WHERE id = OLD.draft_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'prefill snapshots are immutable');
    \\END;
;

test "tax profile migration is namespaced idempotent and preserves user_version" {
    var store = try Store.openMemory(std.testing.allocator);
    defer store.close();

    try std.testing.expect(try store.foreignKeysEnabled());
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
    try store.exec("PRAGMA user_version = 73;");
    try store.migrate();
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());

    var user_version = try store.prepare("PRAGMA user_version;");
    defer user_version.deinit();
    try std.testing.expectEqual(StepResult.row, try user_version.step());
    try std.testing.expectEqual(
        @as(i64, 73),
        sqlite.sqlite3_column_int64(user_version.raw, 0),
    );
}

test "schema version one upgrades append-only delete guards atomically" {
    var store = try Store.openMemory(std.testing.allocator);
    defer store.close();

    try store.exec(
        \\DROP TRIGGER tax_profile_revisions_delete_guard;
        \\DROP TRIGGER tax_profile_business_activities_delete_guard;
        \\DROP TRIGGER tax_profile_registration_facts_delete_guard;
        \\DROP TRIGGER tax_form_draft_role_bindings_update_guard;
        \\DROP TRIGGER tax_form_draft_role_bindings_delete_guard;
        \\DROP TRIGGER tax_form_draft_snapshot_fields_delete_guard;
        \\UPDATE app_component_migrations
        \\SET version = 1
        \\WHERE component = 'tax_profile';
    );
    try store.migrate();
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());

    const profile_id = "tax-profile-v1-upgrade";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Upgrade Guard", "2026-01-01"),
        .{},
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_profile_revisions
            \\WHERE profile_id = 'tax-profile-v1-upgrade';
        ),
    );
}

test "atomic first revision and optimistic append maintain current revision" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-test-0001";
    const activities = [_]BusinessActivityWrite{.{
        .id = "business-main",
        .line_of_business = "Professional services",
        .atc = "PT010",
        .effective = testPeriod("2026-01-01", null),
    }};
    const facts = [_]RegistrationFactWrite{.{
        .id = "tax-type-main",
        .effective = testPeriod("2026-01-01", null),
        .value = .{ .tax_type = "Percentage Tax" },
    }};
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Juan Dela Cruz", "2026-01-01"),
        .{
            .business_activities = &activities,
            .registration_facts = &facts,
        },
    );

    var first = (try store.getCurrentRevision(allocator, profile_id)).?;
    defer first.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), first.sequence);
    try std.testing.expectEqualStrings("revision-1", first.id);
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        first.subject.sole_proprietor.person.name,
    );
    try std.testing.expectEqual(@as(usize, 1), first.business_activities.len);
    try std.testing.expectEqualStrings(
        "PT010",
        first.business_activities[0].atc.?,
    );
    try std.testing.expectEqual(@as(usize, 1), first.registration_facts.len);
    try std.testing.expectEqualStrings(
        "Percentage Tax",
        first.registration_facts[0].value.tax_type,
    );

    try std.testing.expectError(
        Error.RevisionConflict,
        store.appendRevision(
            testRevision(profile_id, 0, "Juan Updated", "2026-07-01"),
            .{},
        ),
    );
    try store.appendRevision(
        testRevision(profile_id, 1, "Juan Updated", "2026-07-01"),
        .{},
    );

    var current = (try store.getCurrentRevision(allocator, profile_id)).?;
    defer current.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 2), current.sequence);
    try std.testing.expectEqualStrings("revision-2", current.id);
    try std.testing.expectEqualStrings(
        "Juan Updated",
        current.subject.sole_proprietor.person.name,
    );

    var historical = (try store.getRevision(
        allocator,
        profile_id,
        "revision-1",
    )).?;
    defer historical.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        historical.subject.sole_proprietor.person.name,
    );

    try store.appendRevision(
        testRevision(
            profile_id,
            2,
            "Juan Retroactive",
            "2026-06-01",
        ),
        .{},
    );
    var retroactive = (try store.getEffectiveRevision(
        allocator,
        profile_id,
        "2026-08-01",
    )).?;
    defer retroactive.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 3), retroactive.sequence);
    try std.testing.expectEqualStrings(
        "Juan Retroactive",
        retroactive.subject.sole_proprietor.person.name,
    );

    var effective = (try store.getEffectiveRevision(
        allocator,
        profile_id,
        "2026-03-31",
    )).?;
    defer effective.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), effective.sequence);

    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_profile_business_activities
            \\WHERE profile_id = 'tax-profile-test-0001'
            \\  AND revision_id = 'revision-1';
        ),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_profile_registration_facts
            \\WHERE profile_id = 'tax-profile-test-0001'
            \\  AND revision_id = 'revision-1';
        ),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_profile_revisions
            \\WHERE profile_id = 'tax-profile-test-0001'
            \\  AND id = 'revision-1';
        ),
    );
}

test "Forms Set distinguishes unconfigured configured-empty and populated" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-test-forms";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Forms Profile", "2026-01-01"),
        .{},
    );

    try std.testing.expect(
        try store.getFormSet(allocator, profile_id, 2026) == null,
    );
    try store.replaceFormSet(profile_id, 2026, &.{});
    var empty = (try store.getFormSet(allocator, profile_id, 2026)).?;
    defer empty.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), empty.items.len);

    const forms = [_]FormRegistrationWrite{
        .{ .form_code = "2551Q", .form_revision = "2018-01-ENCS" },
        .{ .form_code = "1701Q", .form_revision = "2018-01-ENCS" },
    };
    try store.replaceFormSet(profile_id, 2026, &forms);
    var populated = (try store.getFormSet(allocator, profile_id, 2026)).?;
    defer populated.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), populated.items.len);
    try std.testing.expectEqualStrings("1701Q", populated.items[0].form_code);
    try std.testing.expectEqualStrings("2551Q", populated.items[1].form_code);

    try std.testing.expect(try store.clearFormSet(profile_id, 2026));
    try std.testing.expect(
        try store.getFormSet(allocator, profile_id, 2026) == null,
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.replaceFormSet("missing-profile", 2026, &forms),
    );
}

test "draft role bindings are named and snapshots survive profile revision changes" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const employer_id = "tax-profile-employer";
    const employee_id = "tax-profile-employee";
    try store.createProfileWithRevision(
        .{ .id = employer_id },
        testRevision(employer_id, 0, "ACME OPC", "2026-01-01"),
        .{},
    );
    const employee_activities = [_]BusinessActivityWrite{.{
        .id = "activity-employment",
        .line_of_business = "Employment",
        .effective = testPeriod("2026-01-01", null),
    }};
    const employee_facts = [_]RegistrationFactWrite{.{
        .id = "fact-withholding-agent",
        .effective = testPeriod("2026-01-01", null),
        .value = .{ .government_withholding_agent = .yes },
    }};
    try store.createProfileWithRevision(
        .{ .id = employee_id },
        testRevision(employee_id, 0, "Juan Dela Cruz", "2026-01-01"),
        .{
            .business_activities = &employee_activities,
            .registration_facts = &employee_facts,
        },
    );
    const revision_id = "revision-1";

    const bindings = [_]RoleBindingWrite{
        .{
            .role = "employer",
            .profile_id = employer_id,
            .profile_revision_id = revision_id,
            .profile_revision_sequence = 1,
        },
        .{
            .role = "employee",
            .profile_id = employee_id,
            .profile_revision_id = revision_id,
            .profile_revision_sequence = 1,
            .business_activity_id = "activity-employment",
        },
    };
    const snapshots = [_]SnapshotFieldWrite{
        .{
            .role = "employee",
            .field_id = "employee.registered_name",
            .reusable_field = "registered_name",
            .value_type = "text",
            .value_text = "Juan Dela Cruz",
            .provenance = "tax_profile",
            .profile_revision_id = revision_id,
            .profile_revision_sequence = 1,
            .revision_source = .{ .imported = "test fixture" },
            .business_activity_id = "activity-employment",
            .registration_fact_id = "fact-withholding-agent",
        },
        .{
            .role = "employer",
            .field_id = "employer.registered_name",
            .reusable_field = "registered_name",
            .value_type = "text",
            .value_text = "ACME OPC",
            .provenance = "tax_profile",
            .profile_revision_id = revision_id,
            .profile_revision_sequence = 1,
            .revision_source = .{ .imported = "test fixture" },
        },
    };
    const values = [_]DraftValueWrite{.{
        .field_id = "gross_compensation",
        .value_text = "60000000",
    }};
    const draft_id = "draft-2316-original";
    try store.createDraft(
        .{
            .id = draft_id,
            .form_code = "2316",
            .form_revision = "2026-test",
            .period_key = "2026",
            .profile_as_of = testDate("2026-12-31"),
            .mapping_revision = "mapping-v1",
        },
        &bindings,
        &snapshots,
        &values,
    );

    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\UPDATE tax_form_draft_role_bindings
            \\SET role = role
            \\WHERE draft_id = 'draft-2316-original';
        ),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_form_draft_snapshot_fields
            \\WHERE draft_id = 'draft-2316-original';
        ),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_form_draft_role_bindings
            \\WHERE draft_id = 'draft-2316-original';
        ),
    );

    const disposable_draft_id = "draft-2316-disposable";
    try store.createDraft(
        .{
            .id = disposable_draft_id,
            .form_code = "2316",
            .form_revision = "2026-test",
            .period_key = "2026-disposable",
            .profile_as_of = testDate("2026-12-31"),
            .mapping_revision = "mapping-v1",
        },
        &bindings,
        &snapshots,
        &values,
    );
    try store.exec(
        \\DELETE FROM tax_form_drafts
        \\WHERE id = 'draft-2316-disposable';
    );
    try std.testing.expect(
        try store.getDraft(allocator, disposable_draft_id) == null,
    );

    const replacement_values = [_]DraftValueWrite{
        .{
            .field_id = "gross_compensation",
            .value_text = "61000000",
        },
        .{
            .field_id = "filing_note",
            .value_text = "reviewed",
            .provenance = "transaction",
        },
    };
    try store.replaceDraftValues(draft_id, &replacement_values);
    try std.testing.expectError(
        Error.InvalidValue,
        store.replaceDraftValues(draft_id, &.{
            .{ .field_id = "duplicate", .value_text = "one" },
            .{ .field_id = "duplicate", .value_text = "two" },
        }),
    );

    var original = (try store.getDraft(allocator, draft_id)).?;
    defer original.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), original.bindings.len);
    try std.testing.expectEqualStrings("employee", original.bindings[0].role);
    try std.testing.expectEqualStrings("employer", original.bindings[1].role);
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        original.snapshots[0].value_text,
    );
    try std.testing.expectEqual(@as(usize, 2), original.values.len);
    var found_replaced_gross = false;
    for (original.values) |value| {
        if (!std.mem.eql(u8, value.field_id, "gross_compensation")) continue;
        try std.testing.expectEqualStrings("61000000", value.value_text);
        found_replaced_gross = true;
    }
    try std.testing.expect(found_replaced_gross);
    try std.testing.expectEqualStrings(
        "2026-12-31",
        original.profile_as_of,
    );
    try std.testing.expectEqualStrings(
        "test fixture",
        original.snapshots[0].revision_source.imported,
    );
    try std.testing.expectEqualStrings(
        "activity-employment",
        original.snapshots[0].business_activity_id.?,
    );
    try std.testing.expectEqualStrings(
        "fact-withholding-agent",
        original.snapshots[0].registration_fact_id.?,
    );

    try store.appendRevision(
        testRevision(employee_id, 1, "Juan Dela Cruz Updated", "2027-01-01"),
        .{},
    );
    var after_revision = (try store.getDraft(allocator, draft_id)).?;
    defer after_revision.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        after_revision.snapshots[0].value_text,
    );
    try std.testing.expectEqualStrings(
        revision_id,
        after_revision.snapshots[0].profile_revision_id,
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        after_revision.snapshots[0].profile_revision_sequence,
    );

    try store.putDraftValue(draft_id, .{
        .field_id = "tax_withheld",
        .value_text = "3500000",
    });
    try store.transitionDraft(draft_id, "editing", "prepared");
    try std.testing.expectError(
        Error.InvalidTransition,
        store.replaceDraftValues(draft_id, &replacement_values),
    );
    try std.testing.expectError(
        Error.InvalidTransition,
        store.putDraftValue(draft_id, .{
            .field_id = "tax_withheld",
            .value_text = "3600000",
        }),
    );
    try store.transitionDraft(draft_id, "prepared", "editing");
    try store.putDraftValue(draft_id, .{
        .field_id = "tax_withheld",
        .value_text = "3600000",
    });
    try store.transitionDraft(draft_id, "editing", "prepared");
    try store.transitionDraft(draft_id, "prepared", "queued");

    const amendment_id = "draft-2316-amendment";
    try store.createDraft(
        .{
            .id = amendment_id,
            .form_code = "2316",
            .form_revision = "2026-test",
            .period_key = "2026",
            .profile_as_of = testDate("2026-12-31"),
            .intent = "amended",
            .mapping_revision = "mapping-v1",
            .amendment_of = draft_id,
        },
        &bindings,
        &snapshots,
        &.{},
    );
    var amendment = (try store.getDraft(allocator, amendment_id)).?;
    defer amendment.deinit(allocator);
    try std.testing.expectEqualStrings(draft_id, amendment.amendment_of.?);
}

test "foreign keys reject role bindings to missing profile revisions" {
    var store = try Store.openMemory(std.testing.allocator);
    defer store.close();

    const missing_bindings = [_]RoleBindingWrite{.{
        .role = "filer",
        .profile_id = "tax-profile-missing",
        .profile_revision_id = "revision-missing",
        .profile_revision_sequence = 999,
    }};
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.createDraft(
            .{
                .id = "draft-missing-profile",
                .form_code = "2551Q",
                .form_revision = "2018-01-ENCS",
                .period_key = "2026-Q1",
                .profile_as_of = testDate("2026-03-31"),
                .mapping_revision = "mapping-v1",
            },
            &missing_bindings,
            &.{},
            &.{},
        ),
    );
}

test "failed first save rolls back and immutable rows reject updates" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-rollback";
    var invalid_revision = testRevision(
        profile_id,
        0,
        "Rollback",
        "2026-01-01",
    );
    invalid_revision.source = .{ .imported = "\x00" };
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.createProfileWithRevision(
            .{ .id = profile_id },
            invalid_revision,
            .{},
        ),
    );
    try std.testing.expect(!(try store.profileExists(profile_id)));

    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Immutable", "2026-01-01"),
        .{},
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\UPDATE tax_profile_revisions
            \\SET taxpayer_name = 'Mutated'
            \\WHERE profile_id = 'tax-profile-rollback';
        ),
    );
    var current = (try store.getCurrentRevision(allocator, profile_id)).?;
    defer current.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Immutable",
        current.subject.sole_proprietor.person.name,
    );
}

test "file store reopens with revisions Forms Set and drafts intact" {
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
        "{s}/profiles.sqlite3",
        .{directory_buffer[0..directory_len]},
    );

    const profile_id = "tax-profile-reopen";
    const draft_id = "draft-reopen-2551q";
    {
        var store = try Store.open(allocator, database_path);
        defer store.close();
        try store.createProfileWithRevision(
            .{ .id = profile_id },
            testRevision(profile_id, 0, "Reopen Profile", "2026-01-01"),
            .{},
        );
        const revision_id = "revision-1";
        try store.replaceFormSet(profile_id, 2026, &.{.{
            .form_code = "2551Q",
            .form_revision = "2018-01-ENCS",
        }});
        try store.createDraft(
            .{
                .id = draft_id,
                .form_code = "2551Q",
                .form_revision = "2018-01-ENCS",
                .period_key = "2026-Q1",
                .profile_as_of = testDate("2026-03-31"),
                .mapping_revision = "mapping-v1",
            },
            &.{.{
                .role = "filer",
                .profile_id = profile_id,
                .profile_revision_id = revision_id,
                .profile_revision_sequence = 1,
            }},
            &.{.{
                .role = "filer",
                .field_id = "filer.tin",
                .reusable_field = "tin",
                .value_type = "tin",
                .value_text = "123456789000",
                .provenance = "tax_profile",
                .profile_revision_id = revision_id,
                .profile_revision_sequence = 1,
                .revision_source = .{ .imported = "test fixture" },
            }},
            &.{},
        );
    }

    {
        var reopened = try Store.open(allocator, database_path);
        defer reopened.close();
        try std.testing.expectEqual(
            latest_schema_version,
            try reopened.schemaVersion(),
        );
        var revision = (try reopened.getCurrentRevision(
            allocator,
            profile_id,
        )).?;
        defer revision.deinit(allocator);
        try std.testing.expectEqualStrings(
            "Reopen Profile",
            revision.subject.sole_proprietor.person.name,
        );

        var form_set = (try reopened.getFormSet(allocator, profile_id, 2026)).?;
        defer form_set.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 1), form_set.items.len);

        var draft = (try reopened.getDraft(allocator, draft_id)).?;
        defer draft.deinit(allocator);
        try std.testing.expectEqualStrings("123456789000", draft.snapshots[0].value_text);
    }
}

fn testRevision(
    profile_id: []const u8,
    expected_current_sequence: u32,
    display_name: []const u8,
    effective_from: []const u8,
) RevisionWrite {
    return .{
        .id = switch (expected_current_sequence) {
            0 => "revision-1",
            1 => "revision-2",
            2 => "revision-3",
            else => "revision-later",
        },
        .profile_id = profile_id,
        .sequence = expected_current_sequence + 1,
        .expected_current_sequence = expected_current_sequence,
        .effective = testPeriod(effective_from, null),
        .source = .{ .imported = "test fixture" },
        .identity = .{
            .tin = "123456789000",
            .rdo_code = "040",
        },
        .contact = .{
            .registered_address = "123 Sample Street",
            .zip_code = "1100",
            .contact_number = "+639000000000",
            .email_address = "demo@example.test",
        },
        .subject = .{ .sole_proprietor = .{
            .person = .{
                .name = display_name,
                .date_of_birth = testDate("1990-01-01"),
                .citizenship = "PH",
            },
            .trade_name = "Sample Trade",
        } },
    };
}

fn testPeriod(
    from: []const u8,
    until: ?[]const u8,
) EffectivePeriodWrite {
    return .{
        .from = testDate(from),
        .until = if (until) |date| testDate(date) else null,
    };
}

fn testDate(value: []const u8) DateText {
    std.debug.assert(value.len == 10);
    return value[0..10].*;
}
