//! Native-UI state for persisted, immutable tax-profile revisions.
//!
//! The UI is an adapter over the validated domain model. It never writes a
//! nullable SQLite field bag directly: all saves pass through the typestate
//! editor and all reads pass through the lossless persistence adapter.

const std = @import("std");
const native_sdk = @import("native_sdk");
const persistence = @import("store.zig");
const profile_persistence = @import("persistence_adapter.zig");
const editor = @import("editor.zig");
const fields = @import("field.zig");
const model = @import("model.zig");
const catalog = @import("../forms/generated/catalog.zig");

const canvas = native_sdk.canvas;

pub const max_profiles: usize = 64;
pub const max_registered_forms: usize = catalog.registry_count;

pub const Error = error{
    FieldTooLong,
    InvalidTaxYear,
    UnknownFormCode,
    TooManyForms,
    PersonalFieldsNotApplicable,
    TradeNameNotApplicable,
    ActivityRequiresBusinessLine,
    ManualSourceHasReference,
    SourceReferenceRequired,
    UnsupportedRepeatedComponents,
    ProfileCapacityExceeded,
    NotAttached,
    NoSelectedProfile,
} || persistence.Error;

pub const NoticeKind = enum {
    neutral,
    success,
    failure,
};

pub const SourceKind = enum {
    manual_entry,
    imported,
    migrated,
};

pub const GovernmentWithholdingChoice = enum {
    unset,
    no,
    yes,
};

fn FixedText(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        storage: [capacity]u8 = undefined,
        len: usize = 0,

        pub fn set(self: *Self, value: []const u8) error{FieldTooLong}!void {
            if (value.len > capacity) return error.FieldTooLong;
            @memcpy(self.storage[0..value.len], value);
            self.len = value.len;
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn text(self: *const Self) []const u8 {
            return self.storage[0..self.len];
        }
    };
}

const StableIdText = FixedText(64);
const NameText = FixedText(160);
const TinText = FixedText(32);
const InitialsText = FixedText(8);
const FormCodeText = FixedText(32);
const NoticeText = FixedText(256);

pub const RevisionContext = struct {
    profile_id: model.ProfileId,
    revision_id: model.RevisionId,
    sequence: u32,

    pub fn eql(self: *const RevisionContext, other: *const RevisionContext) bool {
        return self.profile_id.eql(&other.profile_id) and
            self.revision_id.eql(&other.revision_id) and
            self.sequence == other.sequence;
    }
};

pub const ProfileRow = struct {
    slot: usize,
    stable_id: StableIdText = .{},
    name: NameText = .{},
    tin: TinText = .{},
    initials: InitialsText = .{},
    subject_kind: model.SubjectKind,
    active: bool = false,

    pub fn nameLabel(self: *const ProfileRow) []const u8 {
        return self.name.text();
    }

    pub fn idLabel(self: *const ProfileRow) []const u8 {
        return self.stable_id.text();
    }

    pub fn tinLabel(
        self: *const ProfileRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(arena, "TIN: {s}", .{self.tin.text()}) catch
            "TIN unavailable";
    }

    pub fn initialsLabel(self: *const ProfileRow) []const u8 {
        return self.initials.text();
    }
};

pub const State = struct {
    allocator: ?std.mem.Allocator = null,
    store: ?*persistence.Store = null,

    profiles: [max_profiles]ProfileRow = undefined,
    profile_count: usize = 0,
    profile_records_truncated: bool = false,
    selected_id: StableIdText = .{},
    has_selection: bool = false,
    selected_revision_id: StableIdText = .{},
    selected_revision_sequence: ?u32 = null,
    selected_activity_id: StableIdText = .{},
    has_selected_activity: bool = false,

    editing_new: bool = true,
    loaded_shape_supported: bool = true,
    subject_kind: model.SubjectKind = .individual,
    source_kind: SourceKind = .manual_entry,
    government_withholding_agent: GovernmentWithholdingChoice = .unset,
    tin: canvas.TextBuffer(32) = .{},
    rdo: canvas.TextBuffer(8) = .{},
    display_name: canvas.TextBuffer(160) = .{},
    trade_name: canvas.TextBuffer(160) = .{},
    registered_address: canvas.TextBuffer(255) = .{},
    zip_code: canvas.TextBuffer(8) = .{},
    phone: canvas.TextBuffer(32) = .{},
    email: canvas.TextBuffer(254) = .{},
    birth_date: canvas.TextBuffer(10) = .{},
    citizenship: canvas.TextBuffer(80) = .{},
    foreign_tax_number: canvas.TextBuffer(64) = .{},
    business_line: canvas.TextBuffer(160) = .{},
    atc: canvas.TextBuffer(16) = .{},
    tax_type: canvas.TextBuffer(80) = .{},
    special_rate_basis: canvas.TextBuffer(160) = .{},
    effective_from: canvas.TextBuffer(10) = .{},
    effective_until: canvas.TextBuffer(10) = .{},
    source_reference: canvas.TextBuffer(160) = .{},
    tax_year: canvas.TextBuffer(4) = .{},
    forms_set: canvas.TextBuffer(1024) = .{},
    forms_set_configured: bool = false,
    input_was_truncated: bool = false,

    default_effective_from: FixedText(10) = .{},
    default_tax_year: i32 = 2026,

    cached_form_year: i32 = 0,
    cached_form_set_configured: bool = false,
    cached_form_codes: [max_registered_forms]FormCodeText = undefined,
    cached_form_count: usize = 0,

    notice: NoticeText = .{},
    notice_kind: NoticeKind = .neutral,

    pub fn attach(
        self: *State,
        allocator: std.mem.Allocator,
        store: *persistence.Store,
        effective_from: []const u8,
        tax_year: i32,
    ) !void {
        _ = try model.Date.parseIso(effective_from);
        if (tax_year < 1 or tax_year > 9999) return error.InvalidTaxYear;
        self.allocator = allocator;
        self.store = store;
        try self.default_effective_from.set(effective_from);
        self.default_tax_year = tax_year;
        try self.reloadRows();
        if (self.profile_count == 0) {
            self.startNew();
            self.setNotice(
                .neutral,
                "Create a tax profile to make recurring form prefills available.",
            );
        } else {
            try self.selectSlot(0);
            if (self.loaded_shape_supported) {
                self.setNotice(.success, "Persisted tax profiles loaded.");
            }
        }
    }

    pub fn rows(self: *const State) []const ProfileRow {
        return self.profiles[0..self.profile_count];
    }

    pub fn rowsEmpty(self: *const State) bool {
        return self.profile_count == 0;
    }

    pub fn rowAt(self: *const State, slot: usize) ?*const ProfileRow {
        if (slot >= self.profile_count) return null;
        return &self.profiles[slot];
    }

    pub fn noticeVisible(self: *const State) bool {
        return self.notice.len != 0;
    }

    pub fn noticeText(self: *const State) []const u8 {
        return self.notice.text();
    }

    pub fn noticeTone(self: *const State) []const u8 {
        return switch (self.notice_kind) {
            .neutral => "secondary",
            .success => "primary",
            .failure => "destructive",
        };
    }

    pub fn saveDisabled(self: *const State) bool {
        return self.store == null or !self.loaded_shape_supported;
    }

    pub fn selectedProfileId(self: *const State) ?[]const u8 {
        return if (self.has_selection) self.selected_id.text() else null;
    }

    pub fn selectedProfileDomainId(self: *const State) ?model.ProfileId {
        if (!self.has_selection) return null;
        return model.ProfileId.parse(self.selected_id.text()) catch null;
    }

    pub fn selectedRevisionId(self: *const State) ?[]const u8 {
        return if (self.selected_revision_sequence != null)
            self.selected_revision_id.text()
        else
            null;
    }

    pub fn selectedRevisionSequence(self: *const State) ?u32 {
        return self.selected_revision_sequence;
    }

    pub fn selectedRevisionContext(self: *const State) ?RevisionContext {
        const profile_id = self.selectedProfileDomainId() orelse return null;
        const sequence = self.selected_revision_sequence orelse return null;
        const revision_id = model.RevisionId.parse(
            self.selected_revision_id.text(),
        ) catch return null;
        return .{
            .profile_id = profile_id,
            .revision_id = revision_id,
            .sequence = sequence,
        };
    }

    pub fn selectedActivityId(self: *const State) ?model.BusinessActivityId {
        if (!self.has_selected_activity) return null;
        return model.BusinessActivityId.parse(
            self.selected_activity_id.text(),
        ) catch null;
    }

    pub fn selectedName(self: *const State) []const u8 {
        const row = self.selectedRow() orelse return "No tax profile selected";
        return row.name.text();
    }

    pub fn selectedTin(self: *const State) []const u8 {
        const row = self.selectedRow() orelse return "—";
        return row.tin.text();
    }

    pub fn selectedInitials(self: *const State) []const u8 {
        const row = self.selectedRow() orelse return "—";
        return row.initials.text();
    }

    pub fn selectedKindLabel(self: *const State) []const u8 {
        const row = self.selectedRow() orelse return "None";
        return subjectKindLabel(row.subject_kind);
    }

    pub fn selectSlot(self: *State, slot: usize) !void {
        if (slot >= self.profile_count) return persistence.Error.NotFound;
        try self.selected_id.set(self.profiles[slot].stable_id.text());
        self.has_selection = true;
        self.markActiveRow();
        try self.loadSelectedRevision(true);
        try self.refreshCalendarFormSet(self.default_tax_year);
    }

    pub fn select(self: *State, slot: usize) void {
        self.selectSlot(slot) catch |err| self.setError(err);
    }

    pub fn startNew(self: *State) void {
        self.editing_new = true;
        self.loaded_shape_supported = true;
        self.clearEditor();
        setEditorBuffer(&self.effective_from, self.default_effective_from.text());
        setTaxYearBuffer(&self.tax_year, self.default_tax_year);
        self.forms_set_configured = false;
        self.setNotice(
            .neutral,
            "New profile. Saving creates revision 1 and opaque stable IDs.",
        );
    }

    pub fn editSelected(self: *State) void {
        if (!self.has_selection) {
            self.startNew();
            return;
        }
        self.loadSelectedRevision(true) catch |err| self.setError(err);
    }

    pub fn cancelEdit(self: *State) void {
        if (self.has_selection) {
            self.loadSelectedRevision(true) catch |err| self.setError(err);
        } else {
            self.startNew();
        }
    }

    pub fn setSubjectKind(self: *State, subject_kind: model.SubjectKind) void {
        self.subject_kind = subject_kind;
        if (subject_kind != .sole_proprietor) {
            clearEditorBuffer(&self.trade_name);
        }
        switch (subject_kind) {
            .individual, .sole_proprietor => {},
            .corporation,
            .partnership,
            .estate,
            .trust,
            .other_legal_entity,
            => {
                clearEditorBuffer(&self.birth_date);
                clearEditorBuffer(&self.citizenship);
                clearEditorBuffer(&self.foreign_tax_number);
            },
        }
    }

    pub fn setSourceKind(self: *State, source_kind: SourceKind) void {
        self.source_kind = source_kind;
        if (source_kind == .manual_entry) {
            clearEditorBuffer(&self.source_reference);
        }
    }

    pub fn setGovernmentWithholdingAgent(
        self: *State,
        value: GovernmentWithholdingChoice,
    ) void {
        self.government_withholding_agent = value;
    }

    pub fn setFormsSetConfigured(self: *State, configured: bool) void {
        self.forms_set_configured = configured;
        self.setNotice(
            .neutral,
            if (configured)
                "The registered Forms Set is authoritative, including when empty."
            else
                "This tax year will use the catalog fallback.",
        );
    }

    pub fn save(self: *State) void {
        const was_new = self.editing_new;
        self.saveFallible() catch |err| return self.setError(err);
        self.setNotice(
            .success,
            if (was_new)
                "Tax profile created."
            else
                "A new immutable profile revision was saved.",
        );
    }

    fn saveFallible(self: *State) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        if (!self.loaded_shape_supported) {
            return error.UnsupportedRepeatedComponents;
        }
        if (self.input_was_truncated or self.inputsTruncated()) {
            return error.FieldTooLong;
        }

        // Validate the Forms Set before any profile persistence occurs.
        const year = try parseTaxYear(self.tax_year.text());
        var form_writes: [max_registered_forms]persistence.FormRegistrationWrite =
            undefined;
        const form_count = if (self.forms_set_configured)
            try parseFormsSet(self.forms_set.text(), &form_writes)
        else
            0;

        const tin = try fields.Tin.parse(trimmed(self.tin.text()));
        const rdo = try fields.RdoCode.parse(trimmed(self.rdo.text()));
        const address = try fields.RegisteredAddress.parse(
            trimmed(self.registered_address.text()),
        );
        const effective = try model.EffectivePeriod.init(
            try model.Date.parseIso(trimmed(self.effective_from.text())),
            if (optionalTrimmed(self.effective_until.text())) |until|
                try model.Date.parseIso(until)
            else
                null,
        );

        const contact: model.RegisteredContact = .{
            .address = address,
            .zip_code = if (optionalTrimmed(self.zip_code.text())) |value|
                try fields.ZipCode.parse(value)
            else
                null,
            .contact_number = if (optionalTrimmed(self.phone.text())) |value|
                try fields.ContactNumber.parse(value)
            else
                null,
            .email_address = if (optionalTrimmed(self.email.text())) |value|
                try fields.EmailAddress.parse(value)
            else
                null,
        };

        const source = try self.buildSource();
        const creating = self.editing_new;
        var generated_profile_id: persistence.OpaqueId = undefined;
        const profile_id = if (creating) blk: {
            generated_profile_id = try store.generateOpaqueId();
            break :blk try model.ProfileId.parse(&generated_profile_id);
        } else self.selectedProfileDomainId() orelse
            return error.NoSelectedProfile;
        const observed_sequence: u32 = if (creating)
            0
        else
            self.selected_revision_sequence orelse
                return error.NoSelectedProfile;
        if (observed_sequence == std.math.maxInt(u32)) {
            return persistence.Error.InvalidValue;
        }
        const sequence = observed_sequence + 1;
        const generated_revision_id = try store.generateOpaqueId();
        const revision_id = try model.RevisionId.parse(&generated_revision_id);

        const base: editor.Base = .{
            .profile_id = profile_id,
            .revision_id = revision_id,
            .sequence = sequence,
            .effective = effective,
            .source = source,
            .identity = .{ .tin = tin, .rdo_code = rdo },
            .contact = contact,
        };

        var activities: [1]model.BusinessActivity = undefined;
        var activity_count: usize = 0;
        const business_line = optionalTrimmed(self.business_line.text());
        const atc = optionalTrimmed(self.atc.text());
        if (business_line) |line| {
            activities[0] = .{
                .id = try model.BusinessActivityId.parse("primary"),
                .line_of_business = try fields.LineOfBusiness.parse(line),
                .atc = if (atc) |value|
                    try fields.Atc.parse(value)
                else
                    null,
                .effective = effective,
            };
            activity_count = 1;
        } else if (atc != null) {
            return error.ActivityRequiresBusinessLine;
        }

        var facts: [3]model.RegistrationFact = undefined;
        var fact_count: usize = 0;
        if (optionalTrimmed(self.tax_type.text())) |value| {
            facts[fact_count] = .{
                .id = try model.RegistrationFactId.parse("tax-type"),
                .effective = effective,
                .value = .{
                    .tax_type = try fields.TaxType.parse(value),
                },
            };
            fact_count += 1;
        }
        if (self.government_withholding_agent != .unset) {
            facts[fact_count] = .{
                .id = try model.RegistrationFactId.parse(
                    "government-withholding-agent",
                ),
                .effective = effective,
                .value = .{
                    .government_withholding_agent = switch (self.government_withholding_agent) {
                        .unset => unreachable,
                        .no => .no,
                        .yes => .yes,
                    },
                },
            };
            fact_count += 1;
        }
        if (optionalTrimmed(self.special_rate_basis.text())) |value| {
            facts[fact_count] = .{
                .id = try model.RegistrationFactId.parse(
                    "special-rate-basis",
                ),
                .effective = effective,
                .value = .{
                    .special_rate_basis = try fields.SpecialRateBasis.parse(value),
                },
            };
            fact_count += 1;
        }

        const ready = try self.buildSubject(base);
        const revision = try ready
            .withBusinessActivities(activities[0..activity_count])
            .withRegistrationFacts(facts[0..fact_count])
            .build();

        if (creating) {
            try profile_persistence.createProfileWithRevision(
                store,
                allocator,
                .active,
                &revision,
            );
        } else {
            try profile_persistence.appendRevision(
                store,
                allocator,
                &revision,
                observed_sequence,
            );
        }

        if (self.forms_set_configured) {
            try store.replaceFormSet(
                profile_id.asSlice(),
                year,
                form_writes[0..form_count],
            );
        } else {
            _ = try store.clearFormSet(profile_id.asSlice(), year);
        }

        try self.selected_id.set(profile_id.asSlice());
        self.has_selection = true;
        try self.reloadRows();
        try self.loadSelectedRevision(true);
        setTaxYearBuffer(&self.tax_year, year);
        try self.loadEditorFormSet(year);
        try self.refreshCalendarFormSet(year);
    }

    pub fn taxYearInputChanged(self: *State) void {
        if (self.editing_new or !self.has_selection) return;
        const year = parseTaxYear(self.tax_year.text()) catch return;
        self.loadEditorFormSet(year) catch |err| self.setError(err);
    }

    fn buildSource(self: *const State) !model.RevisionSource {
        const reference = optionalTrimmed(self.source_reference.text());
        return switch (self.source_kind) {
            .manual_entry => blk: {
                if (reference != null) return error.ManualSourceHasReference;
                break :blk .manual_entry;
            },
            .imported => .{
                .imported = try fields.SourceReference.parse(
                    reference orelse return error.SourceReferenceRequired,
                ),
            },
            .migrated => .{
                .migrated = try fields.SourceReference.parse(
                    reference orelse return error.SourceReferenceRequired,
                ),
            },
        };
    }

    fn buildSubject(
        self: *const State,
        base: editor.Base,
    ) !editor.Ready {
        const name = trimmed(self.display_name.text());
        const has_personal = optionalTrimmed(self.birth_date.text()) != null or
            optionalTrimmed(self.citizenship.text()) != null or
            optionalTrimmed(self.foreign_tax_number.text()) != null;
        const trade_name = optionalTrimmed(self.trade_name.text());
        return switch (self.subject_kind) {
            .individual, .sole_proprietor => blk: {
                const person: model.Individual = .{
                    .name = try fields.TaxpayerName.parse(name),
                    .date_of_birth = if (optionalTrimmed(self.birth_date.text())) |value|
                        try model.Date.parseIso(value)
                    else
                        null,
                    .citizenship = if (optionalTrimmed(self.citizenship.text())) |value|
                        try fields.Citizenship.parse(value)
                    else
                        null,
                    .foreign_tax_number = if (optionalTrimmed(self.foreign_tax_number.text())) |value|
                        try fields.ForeignTaxNumber.parse(value)
                    else
                        null,
                };
                if (self.subject_kind == .individual) {
                    if (trade_name != null) return error.TradeNameNotApplicable;
                    break :blk editor.begin(base).individual(person);
                }
                break :blk editor.begin(base).soleProprietor(.{
                    .person = person,
                    .trade_name = if (trade_name) |value|
                        try fields.RegisteredName.parse(value)
                    else
                        null,
                });
            },
            .corporation,
            .partnership,
            .estate,
            .trust,
            .other_legal_entity,
            => blk: {
                if (has_personal) return error.PersonalFieldsNotApplicable;
                if (trade_name != null) return error.TradeNameNotApplicable;
                break :blk editor.begin(base).legalEntity(.{
                    .registered_name = try fields.RegisteredName.parse(name),
                    .kind = switch (self.subject_kind) {
                        .corporation => .corporation,
                        .partnership => .partnership,
                        .estate => .estate,
                        .trust => .trust,
                        .other_legal_entity => .other,
                        .individual, .sole_proprietor => unreachable,
                    },
                });
            },
        };
    }

    pub fn refreshCalendarFormSet(self: *State, tax_year: i32) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        self.cached_form_year = tax_year;
        self.cached_form_set_configured = false;
        self.cached_form_count = 0;
        const profile_id = self.selectedProfileId() orelse return;
        var maybe_set = try store.getFormSet(allocator, profile_id, tax_year);
        if (maybe_set) |*form_set| {
            defer form_set.deinit(allocator);
            self.cached_form_set_configured = true;
            if (form_set.items.len > self.cached_form_codes.len) {
                return error.TooManyForms;
            }
            for (form_set.items, 0..) |item, index| {
                try self.cached_form_codes[index].set(item.form_code);
            }
            self.cached_form_count = form_set.items.len;
        }
    }

    pub fn calendarFormSetConfigured(
        self: *const State,
        tax_year: i32,
    ) bool {
        return self.cached_form_year == tax_year and
            self.cached_form_set_configured;
    }

    pub fn calendarFormCodes(
        self: *const State,
        arena: std.mem.Allocator,
        tax_year: i32,
    ) []const []const u8 {
        if (!self.calendarFormSetConfigured(tax_year)) return &.{};
        const output = arena.alloc([]const u8, self.cached_form_count) catch
            return &.{};
        for (
            self.cached_form_codes[0..self.cached_form_count],
            0..,
        ) |*code, index| {
            output[index] = code.text();
        }
        return output;
    }

    /// Unconfigured years use the caller's catalog fallback. Once a Forms Set
    /// is configured it is authoritative, including when it contains no
    /// entries.
    pub fn formAvailable(
        self: *const State,
        tax_year: i32,
        form_code: []const u8,
    ) bool {
        if (!self.calendarFormSetConfigured(tax_year)) return true;
        for (self.cached_form_codes[0..self.cached_form_count]) |*code| {
            if (std.ascii.eqlIgnoreCase(code.text(), form_code)) return true;
        }
        return false;
    }

    fn reloadRows(self: *State) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        var profiles = try store.listProfiles(allocator, false);
        defer profiles.deinit(allocator);

        self.profile_records_truncated = profiles.items.len > max_profiles;
        self.profile_count = 0;
        for (
            profiles.items[0..@min(profiles.items.len, max_profiles)],
            0..,
        ) |item, slot| {
            var row = ProfileRow{
                .slot = slot,
                .subject_kind = subjectKindToDomain(item.subject_kind),
            };
            try row.stable_id.set(item.id);
            try row.name.set(item.display_name);
            try row.tin.set(item.tin);
            try setInitials(&row.initials, item.display_name);
            row.active = self.has_selection and
                std.mem.eql(u8, self.selected_id.text(), item.id);
            self.profiles[self.profile_count] = row;
            self.profile_count += 1;
        }

        if (self.profile_count == 0) {
            self.has_selection = false;
            self.selected_id.clear();
            self.selected_revision_id.clear();
            self.selected_revision_sequence = null;
            self.has_selected_activity = false;
            self.selected_activity_id.clear();
            return;
        }
        if (self.selectedRow() == null) {
            try self.selected_id.set(self.profiles[0].stable_id.text());
            self.has_selection = true;
        }
        self.markActiveRow();
        if (self.profile_records_truncated) {
            self.setNotice(
                .neutral,
                "Only the first 64 active tax profiles are shown.",
            );
        }
    }

    fn loadSelectedRevision(self: *State, load_editor: bool) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const profile_id = self.selectedProfileDomainId() orelse
            return error.NoSelectedProfile;
        var owned = (try profile_persistence.loadCurrentRevision(
            store,
            allocator,
            profile_id,
        )) orelse return persistence.Error.NotFound;
        defer owned.deinit(allocator);
        const revision = &owned.revision;

        try self.selected_revision_id.set(revision.id.asSlice());
        self.selected_revision_sequence = revision.sequence;
        // A sole activity is unambiguous. Repeated effective activities must
        // be selected explicitly by the form session; never silently choose
        // array position zero.
        self.has_selected_activity = revision.business_activities.len == 1;
        if (revision.business_activities.len == 1) {
            try self.selected_activity_id.set(
                revision.business_activities[0].id.asSlice(),
            );
        } else {
            self.selected_activity_id.clear();
        }
        if (!load_editor) return;

        self.editing_new = false;
        self.loaded_shape_supported = editorSupports(revision);
        self.subject_kind = revision.subject.kind();
        var tin_buffer: [32]u8 = undefined;
        setEditorBuffer(
            &self.tin,
            try revision.identity.tin.write(&tin_buffer),
        );
        setEditorBuffer(&self.rdo, revision.identity.rdo_code.asSlice());
        switch (revision.subject) {
            .individual => |person| {
                setEditorBuffer(&self.display_name, person.name.asSlice());
                clearEditorBuffer(&self.trade_name);
                loadIndividualFields(self, &person);
            },
            .sole_proprietor => |proprietor| {
                setEditorBuffer(
                    &self.display_name,
                    proprietor.person.name.asSlice(),
                );
                setOptionalBoundedBuffer(
                    &self.trade_name,
                    proprietor.trade_name,
                );
                loadIndividualFields(self, &proprietor.person);
            },
            .legal_entity => |entity| {
                setEditorBuffer(
                    &self.display_name,
                    entity.registered_name.asSlice(),
                );
                clearEditorBuffer(&self.trade_name);
                clearEditorBuffer(&self.birth_date);
                clearEditorBuffer(&self.citizenship);
                clearEditorBuffer(&self.foreign_tax_number);
            },
        }
        setEditorBuffer(
            &self.registered_address,
            revision.contact.address.asSlice(),
        );
        setOptionalBoundedBuffer(&self.zip_code, revision.contact.zip_code);
        setOptionalBoundedBuffer(
            &self.phone,
            revision.contact.contact_number,
        );
        setOptionalBoundedBuffer(
            &self.email,
            revision.contact.email_address,
        );

        var date_buffer: [10]u8 = undefined;
        setEditorBuffer(
            &self.effective_from,
            revision.effective.from.writeIso(&date_buffer),
        );
        if (revision.effective.until) |until| {
            var until_buffer: [10]u8 = undefined;
            setEditorBuffer(
                &self.effective_until,
                until.writeIso(&until_buffer),
            );
        } else {
            clearEditorBuffer(&self.effective_until);
        }
        switch (revision.source) {
            .manual_entry => {
                self.source_kind = .manual_entry;
                clearEditorBuffer(&self.source_reference);
            },
            .imported => |reference| {
                self.source_kind = .imported;
                setEditorBuffer(
                    &self.source_reference,
                    reference.asSlice(),
                );
            },
            .migrated => |reference| {
                self.source_kind = .migrated;
                setEditorBuffer(
                    &self.source_reference,
                    reference.asSlice(),
                );
            },
        }

        clearEditorBuffer(&self.business_line);
        clearEditorBuffer(&self.atc);
        if (revision.business_activities.len == 1) {
            const activity = revision.business_activities[0];
            setEditorBuffer(
                &self.business_line,
                activity.line_of_business.asSlice(),
            );
            setOptionalBoundedBuffer(&self.atc, activity.atc);
        }

        clearEditorBuffer(&self.tax_type);
        clearEditorBuffer(&self.special_rate_basis);
        self.government_withholding_agent = .unset;
        for (revision.registration_facts) |fact| {
            switch (fact.value) {
                .tax_type => |value| {
                    if (registrationFactKindCount(revision, .tax_type) == 1) {
                        setEditorBuffer(&self.tax_type, value.asSlice());
                    }
                },
                .government_withholding_agent => |value| {
                    if (registrationFactKindCount(
                        revision,
                        .government_withholding_agent,
                    ) == 1) {
                        self.government_withholding_agent = switch (value) {
                            .no => .no,
                            .yes => .yes,
                        };
                    }
                },
                .special_rate_basis => |value| {
                    if (registrationFactKindCount(
                        revision,
                        .special_rate_basis,
                    ) == 1) {
                        setEditorBuffer(
                            &self.special_rate_basis,
                            value.asSlice(),
                        );
                    }
                },
            }
        }

        setTaxYearBuffer(&self.tax_year, self.default_tax_year);
        try self.loadEditorFormSet(self.default_tax_year);
        self.input_was_truncated = false;
        if (!self.loaded_shape_supported) {
            self.setNotice(
                .failure,
                "This revision has repeated activities or effective-dated facts. It is preserved losslessly, but this single-activity editor cannot revise it.",
            );
        }
    }

    fn loadEditorFormSet(self: *State, tax_year: i32) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;
        var maybe_set = try store.getFormSet(allocator, profile_id, tax_year);
        clearEditorBuffer(&self.forms_set);
        self.forms_set_configured = maybe_set != null;
        if (maybe_set) |*form_set| {
            defer form_set.deinit(allocator);
            var joined: [1024]u8 = undefined;
            var length: usize = 0;
            for (form_set.items, 0..) |item, index| {
                if (index != 0) {
                    if (length + 2 > joined.len) return error.FieldTooLong;
                    joined[length] = ',';
                    joined[length + 1] = ' ';
                    length += 2;
                }
                if (length + item.form_code.len > joined.len) {
                    return error.FieldTooLong;
                }
                @memcpy(joined[length..][0..item.form_code.len], item.form_code);
                length += item.form_code.len;
            }
            setEditorBuffer(&self.forms_set, joined[0..length]);
        }
    }

    fn selectedRow(self: *const State) ?*const ProfileRow {
        if (!self.has_selection) return null;
        for (self.profiles[0..self.profile_count]) |*row| {
            if (std.mem.eql(
                u8,
                row.stable_id.text(),
                self.selected_id.text(),
            )) return row;
        }
        return null;
    }

    fn markActiveRow(self: *State) void {
        for (self.profiles[0..self.profile_count]) |*row| {
            row.active = self.has_selection and std.mem.eql(
                u8,
                row.stable_id.text(),
                self.selected_id.text(),
            );
        }
    }

    fn clearEditor(self: *State) void {
        clearEditorBuffer(&self.tin);
        clearEditorBuffer(&self.rdo);
        clearEditorBuffer(&self.display_name);
        clearEditorBuffer(&self.trade_name);
        clearEditorBuffer(&self.registered_address);
        clearEditorBuffer(&self.zip_code);
        clearEditorBuffer(&self.phone);
        clearEditorBuffer(&self.email);
        clearEditorBuffer(&self.birth_date);
        clearEditorBuffer(&self.citizenship);
        clearEditorBuffer(&self.foreign_tax_number);
        clearEditorBuffer(&self.business_line);
        clearEditorBuffer(&self.atc);
        clearEditorBuffer(&self.tax_type);
        clearEditorBuffer(&self.special_rate_basis);
        clearEditorBuffer(&self.effective_from);
        clearEditorBuffer(&self.effective_until);
        clearEditorBuffer(&self.source_reference);
        clearEditorBuffer(&self.tax_year);
        clearEditorBuffer(&self.forms_set);
        self.subject_kind = .individual;
        self.source_kind = .manual_entry;
        self.government_withholding_agent = .unset;
        self.forms_set_configured = false;
        self.input_was_truncated = false;
    }

    pub fn captureInputTruncation(self: *State) void {
        self.input_was_truncated =
            self.input_was_truncated or self.inputsTruncated();
    }

    fn inputsTruncated(self: *const State) bool {
        return self.tin.truncated or
            self.rdo.truncated or
            self.display_name.truncated or
            self.trade_name.truncated or
            self.registered_address.truncated or
            self.zip_code.truncated or
            self.phone.truncated or
            self.email.truncated or
            self.birth_date.truncated or
            self.citizenship.truncated or
            self.foreign_tax_number.truncated or
            self.business_line.truncated or
            self.atc.truncated or
            self.tax_type.truncated or
            self.special_rate_basis.truncated or
            self.effective_from.truncated or
            self.effective_until.truncated or
            self.source_reference.truncated or
            self.tax_year.truncated or
            self.forms_set.truncated;
    }

    fn setNotice(
        self: *State,
        kind: NoticeKind,
        message: []const u8,
    ) void {
        self.notice_kind = kind;
        self.notice.set(message) catch {
            self.notice.clear();
            self.notice.set("Tax-profile status changed.") catch unreachable;
        };
    }

    fn setError(self: *State, err: anyerror) void {
        const message = switch (err) {
            persistence.Error.RevisionConflict => "This profile changed elsewhere. Reload it before saving a new revision.",
            error.UnknownFormCode => "The Forms Set contains a code that is not in the 51-form catalog.",
            error.InvalidTaxYear => "Tax year must be a four-digit year from 0001 through 9999.",
            error.ActivityRequiresBusinessLine => "An activity ATC requires a line of business. Tax type remains an independent registration fact.",
            error.PersonalFieldsNotApplicable => "Birth date, citizenship, and foreign tax number apply only to individual subjects.",
            error.TradeNameNotApplicable => "A trade name applies only to a sole proprietor.",
            error.SourceReferenceRequired => "Imported and migrated revisions require a source reference.",
            error.ManualSourceHasReference => "Manual entry has no external source reference. Choose Imported or Migrated.",
            error.UnsupportedRepeatedComponents => "This repeated-component revision is preserved, but cannot be rewritten by the single-activity editor.",
            error.FieldTooLong => "One or more profile fields exceed their supported length.",
            else => "Profile was not saved. Check required fields and field formats.",
        };
        self.setNotice(.failure, message);
    }
};

fn editorSupports(revision: *const model.ProfileRevision) bool {
    if (revision.business_activities.len > 1) return false;
    for (revision.business_activities) |activity| {
        if (!effectivePeriodsEqual(activity.effective, revision.effective)) {
            return false;
        }
    }
    inline for (std.meta.tags(model.RegistrationFactKind)) |kind| {
        if (registrationFactKindCount(revision, kind) > 1) return false;
    }
    for (revision.registration_facts) |fact| {
        if (!effectivePeriodsEqual(fact.effective, revision.effective)) {
            return false;
        }
    }
    return true;
}

fn effectivePeriodsEqual(
    left: model.EffectivePeriod,
    right: model.EffectivePeriod,
) bool {
    if (!left.from.eql(right.from)) return false;
    if (left.until == null or right.until == null) {
        return left.until == null and right.until == null;
    }
    return left.until.?.eql(right.until.?);
}

fn registrationFactKindCount(
    revision: *const model.ProfileRevision,
    kind: model.RegistrationFactKind,
) usize {
    var count: usize = 0;
    for (revision.registration_facts) |fact| {
        if (fact.kind() == kind) count += 1;
    }
    return count;
}

fn loadIndividualFields(state: *State, person: *const model.Individual) void {
    if (person.date_of_birth) |birth_date| {
        var buffer: [10]u8 = undefined;
        setEditorBuffer(&state.birth_date, birth_date.writeIso(&buffer));
    } else {
        clearEditorBuffer(&state.birth_date);
    }
    setOptionalBoundedBuffer(&state.citizenship, person.citizenship);
    setOptionalBoundedBuffer(
        &state.foreign_tax_number,
        person.foreign_tax_number,
    );
}

fn parseTaxYear(raw: []const u8) Error!i32 {
    const text = trimmed(raw);
    if (text.len != 4) return error.InvalidTaxYear;
    const value = std.fmt.parseInt(i32, text, 10) catch
        return error.InvalidTaxYear;
    if (value < 1 or value > 9999) return error.InvalidTaxYear;
    return value;
}

fn parseFormsSet(
    raw: []const u8,
    output: *[max_registered_forms]persistence.FormRegistrationWrite,
) Error!usize {
    var count: usize = 0;
    var iterator = std.mem.splitScalar(u8, raw, ',');
    while (iterator.next()) |part| {
        const candidate = trimmed(part);
        if (candidate.len == 0) continue;
        const form = findCatalogForm(candidate) orelse
            return error.UnknownFormCode;
        var duplicate = false;
        for (output[0..count]) |existing| {
            if (std.mem.eql(u8, existing.form_code, form.code)) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;
        if (count == output.len) return error.TooManyForms;
        output[count] = .{
            .form_code = form.code,
            .form_revision = form.revision orelse "calendar-only",
        };
        count += 1;
    }
    return count;
}

fn findCatalogForm(raw: []const u8) ?*const catalog.FormDefinition {
    var normalized: [32]u8 = undefined;
    const wanted = normalizeFormCode(raw, &normalized) orelse return null;
    for (&catalog.forms) |*form| {
        var candidate_buffer: [32]u8 = undefined;
        const candidate = normalizeFormCode(
            form.code,
            &candidate_buffer,
        ) orelse continue;
        if (std.mem.eql(u8, wanted, candidate)) return form;
    }
    return null;
}

fn normalizeFormCode(raw: []const u8, output: *[32]u8) ?[]const u8 {
    var length: usize = 0;
    for (raw) |byte| {
        if (!std.ascii.isAlphanumeric(byte)) continue;
        if (length == output.len) return null;
        output[length] = std.ascii.toUpper(byte);
        length += 1;
    }
    if (length == 0) return null;
    return output[0..length];
}

fn setInitials(
    output: *InitialsText,
    name: []const u8,
) error{FieldTooLong}!void {
    var initials: [8]u8 = undefined;
    var count: usize = 0;
    var at_word_start = true;
    for (name) |byte| {
        if (std.ascii.isWhitespace(byte)) {
            at_word_start = true;
            continue;
        }
        if (at_word_start and count < 2) {
            initials[count] = std.ascii.toUpper(byte);
            count += 1;
        }
        at_word_start = false;
    }
    if (count == 0) {
        initials[0] = '?';
        count = 1;
    }
    try output.set(initials[0..count]);
}

fn subjectKindToDomain(kind: persistence.SubjectKind) model.SubjectKind {
    return switch (kind) {
        .individual => .individual,
        .sole_proprietor => .sole_proprietor,
        .corporation => .corporation,
        .partnership => .partnership,
        .estate => .estate,
        .trust => .trust,
        .other_legal_entity => .other_legal_entity,
    };
}

fn subjectKindLabel(kind: model.SubjectKind) []const u8 {
    return switch (kind) {
        .individual => "Individual",
        .sole_proprietor => "Sole proprietor",
        .corporation => "Corporation",
        .partnership => "Partnership",
        .estate => "Estate",
        .trust => "Trust",
        .other_legal_entity => "Other legal entity",
    };
}

fn setTaxYearBuffer(buffer: anytype, year: i32) void {
    var value: [16]u8 = undefined;
    const text = std.fmt.bufPrint(&value, "{d}", .{year}) catch unreachable;
    setEditorBuffer(buffer, text);
}

fn setOptionalBoundedBuffer(buffer: anytype, value: anytype) void {
    if (value) |item| {
        setEditorBuffer(buffer, item.asSlice());
    } else {
        clearEditorBuffer(buffer);
    }
}

fn setEditorBuffer(buffer: anytype, value: []const u8) void {
    buffer.set(value);
    buffer.truncated = value.len > buffer.storage.len;
}

fn clearEditorBuffer(buffer: anytype) void {
    buffer.clear();
    buffer.truncated = false;
}

fn optionalTrimmed(value: []const u8) ?[]const u8 {
    const normalized = trimmed(value);
    return if (normalized.len == 0) null else normalized;
}

fn trimmed(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

test "forms set parsing canonicalizes codes and preserves explicit revisions" {
    var output: [max_registered_forms]persistence.FormRegistrationWrite =
        undefined;
    const count = try parseFormsSet("2551-q, 1701Q, 2551Q", &output);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualStrings("2551Q", output[0].form_code);
    try std.testing.expectEqualStrings("2018-01-ENCS", output[0].form_revision);
    try std.testing.expectEqualStrings("1701Q", output[1].form_code);
}

test "form availability distinguishes fallback from an explicit empty set" {
    var state = State{};
    state.cached_form_year = 2026;
    try std.testing.expect(state.formAvailable(2026, "2551Q"));

    state.cached_form_set_configured = true;
    try std.testing.expect(!state.formAvailable(2026, "2551Q"));

    try state.cached_form_codes[0].set("2551Q");
    state.cached_form_count = 1;
    try std.testing.expect(state.formAvailable(2026, "2551q"));
    try std.testing.expect(!state.formAvailable(2026, "1701Q"));
}

test "profile state builds domain revision and explicit empty Forms Set" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-07-29", 2026);
    state.tin.set("123-456-789-000");
    state.rdo.set("040");
    state.display_name.set("Maria Santos");
    state.registered_address.set("Quezon City");
    state.email.set("maria@example.ph");
    state.effective_from.set("2026-01-01");
    state.tax_type.set("Percentage Tax");
    state.forms_set_configured = true;
    state.save();

    try std.testing.expectEqual(NoticeKind.success, state.notice_kind);
    const profile_id = state.selectedProfileDomainId().?;
    var loaded = (try profile_persistence.loadCurrentRevision(
        &store,
        allocator,
        profile_id,
    )).?;
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), loaded.revision.sequence);
    try std.testing.expectEqual(
        model.RegistrationFactKind.tax_type,
        loaded.revision.registration_facts[0].kind(),
    );
    try std.testing.expectEqual(@as(usize, 0), loaded.revision.business_activities.len);

    const maybe_set = try store.getFormSet(
        allocator,
        profile_id.asSlice(),
        2026,
    );
    try std.testing.expect(maybe_set != null);
    var form_set = maybe_set.?;
    defer form_set.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), form_set.items.len);
}

test "profile state appends immutable source-aware revision" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-01-01", 2026);
    state.tin.set("123-456-789-000");
    state.rdo.set("040");
    state.display_name.set("Maria Santos");
    state.registered_address.set("Quezon City");
    state.effective_from.set("2026-01-01");
    state.save();
    const profile_id = state.selectedProfileDomainId().?;
    const first_id = state.selectedRevisionContext().?.revision_id;

    state.display_name.set("Maria Santos Updated");
    state.effective_from.set("2026-07-01");
    state.setSourceKind(.imported);
    state.source_reference.set("COR import batch 7");
    state.save();
    try std.testing.expectEqual(@as(u32, 2), state.selectedRevisionSequence().?);

    var first = (try profile_persistence.loadRevision(
        &store,
        allocator,
        profile_id,
        first_id,
    )).?;
    defer first.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Maria Santos",
        first.revision.subject.taxpayerName().asSlice(),
    );
    var current = (try profile_persistence.loadCurrentRevision(
        &store,
        allocator,
        profile_id,
    )).?;
    defer current.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Maria Santos Updated",
        current.revision.subject.taxpayerName().asSlice(),
    );
    try std.testing.expectEqual(
        std.meta.Tag(model.RevisionSource).imported,
        std.meta.activeTag(current.revision.source),
    );
}
