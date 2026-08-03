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
const multi_select = @import("../components/multi_select.zig");

const canvas = native_sdk.canvas;

pub const max_profiles: usize = 64;
pub const max_registered_forms: usize = catalog.registry_count;
pub const max_form_set_summaries: usize = 128;
/// Covers every recurring catalog slot (51 forms × 12 periods) plus a
/// bounded on-demand history window. If that window is exceeded the library
/// reports status as unavailable instead of falsely labelling omitted work
/// as New.
pub const max_draft_summaries: usize = catalog.registry_count * 12 + 64;
const FormSelectionState = multi_select.State(catalog.registry_count, 96);

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
    FormsRequireSavedProfile,
    UnsavedFormSetChanges,
    UnsavedProfileChanges,
    NoFactsEffectiveForYear,
    DuplicateTaxpayerIdentifier,
    BranchTinRootChanged,
    BranchCodeRequired,
    BranchLegalPersonChanged,
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

/// Why the user is editing taxpayer details. Both append to the same
/// append-only history; they differ in which period the new record claims and
/// therefore in what the interface must tell the user about older filings.
pub const ChangeIntent = enum {
    /// Something changed in the real world on a date.
    record_change,
    /// Something was recorded wrongly and the same period must be restated.
    fix_mistake,
};

pub const FormActivityFilter = enum { active, inactive, all };
pub const FormCapabilityFilter = enum { all, editor, calendar_only };

/// Oldest tax year the setup UI offers. The storage layer accepts 1-9999,
/// but that is a data bound rather than a product promise: the oldest catalog
/// revision is 1999-07-ENCS, so older years would only add unreachable rows.
pub const minimum_setup_year: i32 = 2000;

/// The yearly setup workspace. Exactly one mode is active while a year is
/// open, and only `draft_*` modes may create a Forms Set. A year is never
/// classified from a cached summary: `openYearWorkspace` resolves the store
/// first, so a configured year cannot present a create action.
pub const YearWorkspaceMode = enum {
    /// A configured year (including explicitly empty and the legacy catalog
    /// compatibility state) is loaded for editing.
    viewing,
    /// An unconfigured year is open, but the user has not chosen how to start.
    draft_choice,
    /// An unconfigured year started from no forms.
    draft_empty,
    /// An unconfigured year seeded from another year's active forms.
    draft_seeded,
    /// Saving a draft lost the race with another writer. The staged selection
    /// is preserved until the user reviews or discards it.
    conflict,
    /// The year could not be read. No create action may be offered, because an
    /// unknown year must never be treated as unconfigured.
    open_failed,

    pub fn isDraft(self: YearWorkspaceMode) bool {
        return switch (self) {
            .draft_choice, .draft_empty, .draft_seeded => true,
            .viewing, .conflict, .open_failed => false,
        };
    }
};

/// Presentation status for one catalog form while the Forms Set editor is
/// open. Persisted membership and staged membership stay separate so Manage
/// mode can describe the pending effect without changing Browse mode.
pub const ManagedFormStatus = enum {
    inactive,
    active,
    will_activate,
    will_deactivate,

    pub fn label(self: ManagedFormStatus) []const u8 {
        return switch (self) {
            .inactive => "Inactive",
            .active => "Active",
            .will_activate => "Will activate",
            .will_deactivate => "Will deactivate",
        };
    }

    pub fn changed(self: ManagedFormStatus) bool {
        return switch (self) {
            .will_activate, .will_deactivate => true,
            .inactive, .active => false,
        };
    }
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
const DraftIdText = FixedText(64);
const PeriodKeyText = FixedText(32);
const LifecycleText = FixedText(16);
const IntentText = FixedText(16);
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
    /// The nine-digit root shared by a head office and its branches, and the
    /// branch segment that distinguishes them. Both are derived from the
    /// canonical TIN; neither is a second source of truth.
    tin_root: FixedText(9) = .{},
    branch_code: FixedText(5) = .{},

    pub fn tinRoot(self: *const ProfileRow) []const u8 {
        return self.tin_root.text();
    }

    pub fn branchCode(self: *const ProfileRow) []const u8 {
        return self.branch_code.text();
    }

    /// A registration with no branch segment, or segment zero, is the head
    /// office. Anything else is a branch of the same taxpayer.
    pub fn isBranch(self: *const ProfileRow) bool {
        const code = self.branch_code.text();
        if (code.len == 0) return false;
        for (code) |digit| {
            if (digit != '0') return true;
        }
        return false;
    }

    pub fn branchLabel(
        self: *const ProfileRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (!self.isBranch()) return "Head office";
        return std.fmt.allocPrint(
            arena,
            "Branch {s}",
            .{self.branch_code.text()},
        ) catch "Branch";
    }

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

pub const DraftSummaryRow = struct {
    slot: usize,
    draft_id: DraftIdText = .{},
    form_code: FormCodeText = .{},
    period_key: PeriodKeyText = .{},
    lifecycle: LifecycleText = .{},
    intent: IntentText = .{},

    pub fn key(self: *const DraftSummaryRow) canvas.UiKey {
        return canvas.uiKey(self.slot);
    }

    pub fn draftId(self: *const DraftSummaryRow) []const u8 {
        return self.draft_id.text();
    }

    pub fn formCode(self: *const DraftSummaryRow) []const u8 {
        return self.form_code.text();
    }

    pub fn periodKey(self: *const DraftSummaryRow) []const u8 {
        return self.period_key.text();
    }

    pub fn lifecycleText(self: *const DraftSummaryRow) []const u8 {
        return self.lifecycle.text();
    }

    pub fn intentText(self: *const DraftSummaryRow) []const u8 {
        return self.intent.text();
    }
};

const CalendarFormSetResolution = enum {
    /// No successful persistence read exists for this profile/year. Callers
    /// must treat the cache as authoritative-empty, never catalog-all.
    unavailable,
    /// A successful query found no configured Forms Set.
    catalog_fallback,
    /// A successful query found an authoritative set, including zero forms.
    configured,
};

const CalendarFormSetCache = struct {
    tax_year: i32 = 0,
    resolution: CalendarFormSetResolution = .unavailable,
    codes: [max_registered_forms]FormCodeText = undefined,
    count: usize = 0,
};

fn calendarFormSetCacheEntries(tax_year: i32) [2]CalendarFormSetCache {
    var entries: [2]CalendarFormSetCache = .{ .{}, .{} };
    entries[0].tax_year = tax_year;
    if (tax_year > 1) entries[1].tax_year = tax_year - 1;
    return entries;
}

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
    form_set_state: persistence.FormSetState = .needs_configuration,
    legacy_form_set_reset_allowed: bool = false,
    saved_forms: FormSelectionState = .{},
    staged_forms: FormSelectionState = .{},
    managing_forms: bool = false,
    form_set_create_mode: bool = false,
    year_workspace: YearWorkspaceMode = .viewing,
    /// The source year a draft copied its forms from. Presentation only: no
    /// facts are duplicated and the source year is never opened for writing.
    draft_source_year: ?i32 = null,
    /// A year the user selected while the workspace still held unsaved work.
    /// Nothing is discarded until they answer the prompt.
    pending_year_switch: ?i32 = null,
    form_activity_filter: FormActivityFilter = .active,
    form_capability_filter: FormCapabilityFilter = .all,
    input_was_truncated: bool = false,

    default_effective_from: FixedText(10) = .{},
    default_tax_year: i32 = 2026,

    /// Fingerprint of the editor values as they were loaded. Saving compares
    /// against it so reopening a taxpayer and pressing save cannot append a
    /// revision that records no actual change.
    baseline_fingerprint: u64 = 0,
    /// Which taxpayer facts apply to the workspace year, summarized without
    /// revision vocabulary.
    facts_summary_year: i32 = 0,
    facts_summary_available: bool = false,
    facts_effective_from: FixedText(10) = .{},
    facts_missing_for_year: bool = false,
    facts_changed_during_year: bool = false,
    facts_same_as_prior_year: bool = false,
    /// Persisted registered tax type for header display, kept separate from
    /// the editable buffer so unsaved typing never reads as recorded fact.
    selected_tax_type: FixedText(80) = .{},
    change_intent: ChangeIntent = .record_change,
    /// Set while creating another registration of the taxpayer already
    /// selected. The nine-digit root and the legal person are fixed by that
    /// taxpayer; everything branch-specific must be reviewed, not inherited.
    branch_mode: bool = false,
    branch_source_root: FixedText(9) = .{},
    branch_source_name: NameText = .{},
    branch_source_kind: model.SubjectKind = .individual,
    /// The effective date as loaded, so switching to a correction can restore
    /// the period being restated without guessing.
    loaded_effective_from: FixedText(10) = .{},

    /// The dashboard renders deadlines for the viewed year while some of
    /// those deadlines belong to the immediately preceding taxable year.
    /// Keep both authoritative Forms Sets in memory so view rendering never
    /// performs persistence I/O and an explicitly empty set stays distinct
    /// from the catalog fallback.
    cached_calendar_form_sets: [2]CalendarFormSetCache = .{ .{}, .{} },

    form_set_summaries: [max_form_set_summaries]persistence.FormSetSummary = undefined,
    form_set_summary_count: usize = 0,
    form_set_summaries_truncated: bool = false,

    draft_summaries: [max_draft_summaries]DraftSummaryRow = undefined,
    draft_summary_count: usize = 0,
    draft_summaries_truncated: bool = false,

    notice: NoticeText = .{},
    notice_kind: NoticeKind = .neutral,
    notice_epoch: u64 = 0,
    /// A composed failure message that outranks the generic error mapping,
    /// used where the refusal can name the taxpayer involved.
    pending_error_detail: NoticeText = .{},
    has_pending_error_detail: bool = false,

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

    pub fn noticeSuccess(self: *const State) bool {
        return self.notice_kind == .success;
    }

    pub fn noticeFailure(self: *const State) bool {
        return self.notice_kind == .failure;
    }

    pub fn noticeAutoDismissible(self: *const State) bool {
        return self.noticeVisible() and self.notice_kind != .failure;
    }

    pub fn noticeEpoch(self: *const State) u64 {
        return self.notice_epoch;
    }

    pub fn dismissNotice(self: *State) void {
        self.notice.clear();
        self.notice_kind = .neutral;
        self.notice_epoch +%= 1;
    }

    pub fn reportFormLaunchFailure(self: *State, message: []const u8) void {
        self.setNotice(.failure, message);
    }

    pub fn saveDisabled(self: *const State) bool {
        return self.store == null or !self.loaded_shape_supported;
    }

    /// Order-stable fingerprint of every value the editor can change. Used
    /// only to detect "nothing actually changed"; the domain remains the
    /// authority on what a revision contains.
    fn editorFingerprint(self: *const State) u64 {
        var hasher = std.hash.Wyhash.init(0);
        const parts = [_][]const u8{
            trimmed(self.tin.text()),
            trimmed(self.rdo.text()),
            trimmed(self.display_name.text()),
            trimmed(self.trade_name.text()),
            trimmed(self.registered_address.text()),
            trimmed(self.zip_code.text()),
            trimmed(self.phone.text()),
            trimmed(self.email.text()),
            trimmed(self.birth_date.text()),
            trimmed(self.citizenship.text()),
            trimmed(self.foreign_tax_number.text()),
            trimmed(self.business_line.text()),
            trimmed(self.atc.text()),
            trimmed(self.tax_type.text()),
            trimmed(self.special_rate_basis.text()),
            trimmed(self.effective_from.text()),
            trimmed(self.effective_until.text()),
            trimmed(self.source_reference.text()),
        };
        for (parts) |part| {
            hasher.update(part);
            hasher.update("\x1e");
        }
        hasher.update(&[_]u8{
            @intFromEnum(self.subject_kind),
            @intFromEnum(self.source_kind),
            @intFromEnum(self.government_withholding_agent),
        });
        return hasher.final();
    }

    fn captureBaseline(self: *State) void {
        self.baseline_fingerprint = self.editorFingerprint();
    }

    /// True when the open taxpayer has editor changes that saving would
    /// record. A brand-new taxpayer is never "dirty" in this sense: it has no
    /// saved state to diverge from and is guarded by its own save path.
    pub fn factsDirty(self: *const State) bool {
        if (self.editing_new or !self.has_selection) return false;
        return self.editorFingerprint() != self.baseline_fingerprint;
    }

    /// The editor's current value for one canonical reusable fact. Forms
    /// consume these facts through named roles; they never own a private copy,
    /// so there is exactly one place to fix a missing one.
    pub fn reusableValueText(
        self: *const State,
        key: fields.ReusableField,
    ) []const u8 {
        return switch (key) {
            .tin => trimmed(self.tin.text()),
            .rdo_code => trimmed(self.rdo.text()),
            .taxpayer_name => trimmed(self.display_name.text()),
            .registered_name => if (self.subject_kind == .sole_proprietor)
                trimmed(self.trade_name.text())
            else
                trimmed(self.display_name.text()),
            .registered_address => trimmed(self.registered_address.text()),
            .zip_code => trimmed(self.zip_code.text()),
            .contact_number => trimmed(self.phone.text()),
            .email_address => trimmed(self.email.text()),
            .date_of_birth => trimmed(self.birth_date.text()),
            .citizenship => trimmed(self.citizenship.text()),
            .foreign_tax_number => trimmed(self.foreign_tax_number.text()),
            .line_of_business => trimmed(self.business_line.text()),
            .atc => trimmed(self.atc.text()),
            .tax_type => trimmed(self.tax_type.text()),
            // Recorded either way; only "not recorded" counts as missing.
            .government_withholding_agent => if (self.government_withholding_agent == .unset)
                ""
            else
                "recorded",
            .special_rate_basis => trimmed(self.special_rate_basis.text()),
        };
    }

    pub fn changeIntent(self: *const State) ChangeIntent {
        return self.change_intent;
    }

    /// Records something that happened on a date. Earlier periods keep the
    /// details they already had.
    pub fn beginRecordChange(self: *State) void {
        if (self.editing_new or !self.has_selection) return;
        self.change_intent = .record_change;
        setEditorBuffer(&self.effective_from, self.default_effective_from.text());
    }

    /// Restates the period that is already on screen, because what was
    /// recorded for it was wrong. Filings already prepared keep their values.
    pub fn beginFixMistake(self: *State) void {
        if (self.editing_new or !self.has_selection) return;
        self.change_intent = .fix_mistake;
        setEditorBuffer(&self.effective_from, self.loaded_effective_from.text());
    }

    pub fn factsSummaryAvailable(self: *const State) bool {
        return self.facts_summary_available;
    }

    pub fn factsSummaryYear(self: *const State) i32 {
        return self.facts_summary_year;
    }

    pub fn factsMissingForYear(self: *const State) bool {
        return self.facts_summary_available and self.facts_missing_for_year;
    }

    pub fn factsChangedDuringYear(self: *const State) bool {
        return self.facts_summary_available and self.facts_changed_during_year;
    }

    pub fn factsSameAsPriorYear(self: *const State) bool {
        return self.facts_summary_available and self.facts_same_as_prior_year;
    }

    pub fn factsEffectiveFrom(self: *const State) []const u8 {
        return self.facts_effective_from.text();
    }

    /// Summarizes which taxpayer facts apply to one year by resolving the
    /// effective history at its boundaries. Nothing is duplicated per year:
    /// this only reports what the append-only history already says.
    pub fn refreshFactsSummary(self: *State, year: i32) void {
        self.facts_summary_year = year;
        self.facts_summary_available = false;
        self.facts_missing_for_year = false;
        self.facts_changed_during_year = false;
        self.facts_same_as_prior_year = false;
        self.facts_effective_from.clear();
        self.refreshFactsSummaryFallible(year) catch return;
        self.facts_summary_available = true;
    }

    fn refreshFactsSummaryFallible(self: *State, year: i32) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const profile_id = self.selectedProfileDomainId() orelse
            return error.NoSelectedProfile;
        if (year < 1 or year > 9999) return error.InvalidTaxYear;

        var opening = try profile_persistence.loadEffectiveRevision(
            store,
            allocator,
            profile_id,
            try model.Date.init(@intCast(year), 1, 1),
        );
        defer if (opening) |*owned| owned.deinit(allocator);
        var closing = try profile_persistence.loadEffectiveRevision(
            store,
            allocator,
            profile_id,
            try model.Date.init(@intCast(year), 12, 31),
        );
        defer if (closing) |*owned| owned.deinit(allocator);

        // Only a year with no facts at any point needs a reviewed retroactive
        // record. A taxpayer registered partway through a year legitimately
        // has none on its first day, and that is not a gap to fix.
        if (opening == null and closing == null) {
            self.facts_missing_for_year = true;
            return;
        }
        if (opening != null and closing != null and
            !opening.?.revision.id.eql(&closing.?.revision.id))
        {
            self.facts_changed_during_year = true;
        }

        const anchor = opening orelse closing.?;
        var buffer: [10]u8 = undefined;
        try self.facts_effective_from.set(
            anchor.revision.effective.from.writeIso(&buffer),
        );

        if (year > 1) {
            var prior = try profile_persistence.loadEffectiveRevision(
                store,
                allocator,
                profile_id,
                try model.Date.init(@intCast(year - 1), 12, 31),
            );
            defer if (prior) |*owned| owned.deinit(allocator);
            if (prior) |*owned| {
                self.facts_same_as_prior_year =
                    owned.revision.id.eql(&anchor.revision.id) and
                    !self.facts_changed_during_year;
            }
        }
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

    /// The registered tax type as persisted, never as currently typed. A
    /// header states what is on file, so it must not echo an unsaved edit and
    /// must not assert a classification that was never recorded.
    pub fn selectedTaxTypeLabel(self: *const State) []const u8 {
        if (!self.has_selection) return "Tax type not recorded";
        const value = self.selected_tax_type.text();
        return if (value.len == 0) "Tax type not recorded" else value;
    }

    pub fn draftSummaries(self: *const State) []const DraftSummaryRow {
        return self.draft_summaries[0..self.draft_summary_count];
    }

    pub fn draftSummariesTruncated(self: *const State) bool {
        return self.draft_summaries_truncated;
    }

    pub fn selectSlot(self: *State, slot: usize) !void {
        if (slot >= self.profile_count) return persistence.Error.NotFound;
        if (self.formsDirty()) return error.UnsavedFormSetChanges;
        if (self.factsDirty()) return error.UnsavedProfileChanges;
        // Invalidate before changing identity or performing any fallible load.
        // A failed profile switch must not expose the prior profile's forms.
        self.invalidateCalendarFormSetCache(self.default_tax_year);
        try self.selected_id.set(self.profiles[slot].stable_id.text());
        self.has_selection = true;
        self.markActiveRow();
        try self.loadSelectedRevision(true);
        try self.refreshCalendarFormSet(self.default_tax_year);
        try self.refreshFormSetSummaries();
        try self.refreshDraftSummariesForYear(self.default_tax_year);
    }

    pub fn select(self: *State, slot: usize) void {
        self.selectSlot(slot) catch |err| self.setError(err);
    }

    /// Repairs only the presentation flags derived from the already-selected
    /// stable profile identity. It does not reload a revision or overwrite an
    /// in-progress profile editor.
    pub fn reconcileSelectedRow(self: *State) void {
        self.markActiveRow();
    }

    pub fn startNew(self: *State) void {
        if (self.formsDirty()) {
            self.setError(error.UnsavedFormSetChanges);
            return;
        }
        if (self.factsDirty()) {
            self.setError(error.UnsavedProfileChanges);
            return;
        }
        self.editing_new = true;
        self.loaded_shape_supported = true;
        self.clearEditor();
        setEditorBuffer(&self.effective_from, self.default_effective_from.text());
        setTaxYearBuffer(&self.tax_year, self.default_tax_year);
        self.forms_set_configured = false;
        self.form_set_state = .needs_configuration;
        self.legacy_form_set_reset_allowed = false;
        self.saved_forms = .{};
        self.staged_forms = .{};
        self.managing_forms = false;
        self.form_set_create_mode = false;
        self.form_set_summary_count = 0;
        self.form_set_summaries_truncated = false;
        self.updateFormSetSummary() catch |err| self.setError(err);
        self.setNotice(
            .neutral,
            "New profile. Saving creates revision 1 and opaque stable IDs.",
        );
    }

    pub fn branchMode(self: *const State) bool {
        return self.branch_mode;
    }

    pub fn branchSourceName(self: *const State) []const u8 {
        return self.branch_source_name.text();
    }

    pub fn branchSourceRoot(self: *const State) []const u8 {
        return self.branch_source_root.text();
    }

    pub fn canAddBranch(self: *const State) bool {
        if (!self.has_selection or self.editing_new) return false;
        const row = self.selectedRow() orelse return false;
        return row.tin_root.len == 9;
    }

    /// Starts another registration of the selected taxpayer.
    ///
    /// Contact details and the registered name are reused because they
    /// describe the same taxpayer. The branch segment, RDO, address, and every
    /// registration fact are deliberately left blank: they are the facts most
    /// likely to differ, and a silent copy would assert something unverified.
    /// Nothing is copied that belongs to a filing, an evidence document, or a
    /// secret.
    pub fn beginAddBranch(self: *State) bool {
        if (!self.canAddBranch()) {
            self.setError(error.FormsRequireSavedProfile);
            return false;
        }
        if (self.formsDirty()) {
            self.setError(error.UnsavedFormSetChanges);
            return false;
        }
        if (self.factsDirty()) {
            self.setError(error.UnsavedProfileChanges);
            return false;
        }
        const row = self.selectedRow() orelse return false;
        const source_root = row.tin_root.text();
        const source_name = row.name.text();
        const source_kind = row.subject_kind;

        const reused_name = self.display_name.text();
        const reused_trade_name = self.trade_name.text();
        const reused_phone = self.phone.text();
        const reused_email = self.email.text();
        var name_buffer: [160]u8 = undefined;
        var trade_buffer: [160]u8 = undefined;
        var phone_buffer: [32]u8 = undefined;
        var email_buffer: [254]u8 = undefined;
        const name = copyInto(&name_buffer, reused_name);
        const trade_name = copyInto(&trade_buffer, reused_trade_name);
        const phone = copyInto(&phone_buffer, reused_phone);
        const email = copyInto(&email_buffer, reused_email);

        self.editing_new = true;
        self.loaded_shape_supported = true;
        self.clearEditor();
        self.branch_mode = true;
        self.branch_source_root.set(source_root) catch {};
        self.branch_source_name.set(source_name) catch {};
        self.branch_source_kind = source_kind;

        // The branch belongs to the same legal person, so its kind is fixed.
        self.subject_kind = source_kind;
        // Prefill the root the way a TIN is normally written, so the user
        // appends a branch code to something they recognize.
        var root_buffer: [11]u8 = undefined;
        setEditorBuffer(&self.tin, std.fmt.bufPrint(
            &root_buffer,
            "{s}-{s}-{s}",
            .{ source_root[0..3], source_root[3..6], source_root[6..9] },
        ) catch source_root);
        setEditorBuffer(&self.display_name, name);
        if (source_kind == .sole_proprietor) {
            setEditorBuffer(&self.trade_name, trade_name);
        }
        setEditorBuffer(&self.phone, phone);
        setEditorBuffer(&self.email, email);
        setEditorBuffer(&self.effective_from, self.default_effective_from.text());
        setTaxYearBuffer(&self.tax_year, self.default_tax_year);
        self.captureBaseline();
        self.setNotice(
            .neutral,
            "Add the branch code, then review its RDO, address, and registration details.",
        );
        return true;
    }

    pub fn cancelAddBranch(self: *State) void {
        self.branch_mode = false;
        self.branch_source_root.clear();
        self.branch_source_name.clear();
    }

    /// Reports the taxpayer already registered under a canonical TIN, so a
    /// duplicate registration is refused with somewhere to go instead.
    fn profileWithTin(
        self: *const State,
        tin: *const fields.Tin,
    ) ?*const ProfileRow {
        for (self.profiles[0..self.profile_count]) |*row| {
            const existing = fields.Tin.parse(row.tin.text()) catch continue;
            if (existing.eql(tin)) return row;
        }
        return null;
    }

    /// Refuses a second registration of one canonical TIN, naming the taxpayer
    /// that already holds it.
    ///
    /// A TIN is issued once and never reassigned, so an archived taxpayer's
    /// TIN is still theirs — the answer is to restore that taxpayer, not to
    /// register a second one that its filings could never be told apart from.
    fn rejectDuplicateTin(self: *State, tin: *const fields.Tin) !void {
        if (self.profileWithTin(tin)) |row| {
            var message: [256]u8 = undefined;
            self.setErrorDetail(std.fmt.bufPrint(
                &message,
                "That TIN already belongs to {s}. Open it instead of adding it again.",
                .{row.name.text()},
            ) catch "That TIN already belongs to a taxpayer you have.");
            return error.DuplicateTaxpayerIdentifier;
        }

        // The loaded rows are active-only and bounded; ask the store about
        // every taxpayer, archived ones included. A failed read falls through
        // to the store's own check, which refuses without naming anyone.
        const allocator = self.allocator orelse return;
        const store = self.store orelse return;
        var owner = (store.findProfileWithCanonicalTin(
            allocator,
            tin.asDigits(),
            null,
        ) catch return) orelse return;
        defer owner.deinit(allocator);

        var message: [256]u8 = undefined;
        const name = owner.display_name orelse "another taxpayer";
        self.setErrorDetail(switch (owner.status) {
            .archived => std.fmt.bufPrint(
                &message,
                "That TIN belongs to {s}, which is archived. Restore it instead of adding it again.",
                .{name},
            ) catch "That TIN belongs to an archived taxpayer. Restore it instead of adding it again.",
            .active => std.fmt.bufPrint(
                &message,
                "That TIN already belongs to {s}. Open it instead of adding it again.",
                .{name},
            ) catch "That TIN already belongs to a taxpayer you have.",
        });
        return error.DuplicateTaxpayerIdentifier;
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

    pub fn save(self: *State) bool {
        const was_new = self.editing_new;
        // Reopening a taxpayer and saving must not record a change that did
        // not happen: history stays a log of real events, not of visits.
        if (!was_new and !self.factsDirty()) {
            self.setNotice(.neutral, "No changes to save.");
            return true;
        }
        self.saveFallible() catch |err| {
            self.setError(err);
            return false;
        };
        const was_branch = self.branch_mode;
        self.branch_mode = false;
        self.branch_source_root.clear();
        self.branch_source_name.clear();
        self.setNotice(
            .success,
            if (was_branch)
                "Branch created. Upload its COR and choose its forms when ready."
            else if (was_new)
                "Taxpayer created."
            else
                "Your change was saved.",
        );
        return true;
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

        const year = try parseTaxYear(self.tax_year.text());

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
        if (creating) {
            // One registration per canonical TIN. Two profiles sharing a full
            // TIN would make filings and evidence ambiguous with no way to
            // tell them apart afterwards. The store repeats this check inside
            // its write transaction; this one exists to name the taxpayer who
            // already holds the TIN, including an archived one the loaded
            // rows cannot see.
            try self.rejectDuplicateTin(&tin);
            if (self.branch_mode) {
                if (!std.mem.eql(u8, tin.root(), self.branch_source_root.text())) {
                    return error.BranchTinRootChanged;
                }
                if (tin.branch() == null) return error.BranchCodeRequired;
                // A branch is another registration of the same legal person.
                // Changing the kind would make it a different taxpayer, which
                // needs its own profile rather than a branch of this one.
                if (self.subject_kind != self.branch_source_kind) {
                    return error.BranchLegalPersonChanged;
                }
            }
        }
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

        try self.selected_id.set(profile_id.asSlice());
        self.has_selection = true;
        try self.reloadRows();
        try self.loadSelectedRevision(true);
        setTaxYearBuffer(&self.tax_year, year);
        try self.loadEditorFormSet(year);
        try self.refreshCalendarFormSet(year);
        try self.refreshFormSetSummaries();
        try self.refreshDraftSummariesForYear(year);
    }

    /// Compatibility wrapper for screens that still follow the application's
    /// default year. Calendar views should call `refreshDraftSummariesForYear`
    /// whenever their viewed year changes.
    pub fn refreshDraftSummaries(self: *State) !void {
        return self.refreshDraftSummariesForYear(self.default_tax_year);
    }

    /// Loads only filing work relevant to a dashboard year: that viewed tax
    /// year and the immediately preceding taxable year. Older history remains
    /// persisted but cannot consume the bounded presentation cache.
    pub fn refreshDraftSummariesForYear(
        self: *State,
        viewed_tax_year: i32,
    ) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        self.draft_summary_count = 0;
        self.draft_summaries_truncated = false;
        const profile_id = self.selectedProfileId() orelse return;
        var summaries = try store.listDraftSummariesForProfile(
            allocator,
            profile_id,
            viewed_tax_year,
        );
        defer summaries.deinit(allocator);
        self.draft_summaries_truncated =
            summaries.items.len > self.draft_summaries.len;
        for (
            summaries.items[0..@min(
                summaries.items.len,
                self.draft_summaries.len,
            )],
            0..,
        ) |summary, slot| {
            var row = DraftSummaryRow{ .slot = slot };
            try row.draft_id.set(summary.id);
            try row.form_code.set(summary.form_code);
            try row.period_key.set(summary.period_key);
            try row.lifecycle.set(summary.lifecycle);
            try row.intent.set(summary.intent);
            self.draft_summaries[self.draft_summary_count] = row;
            self.draft_summary_count += 1;
        }
    }

    pub fn rejectIfFormsDirty(self: *State) bool {
        if (!self.formsDirty()) return false;
        self.setError(error.UnsavedFormSetChanges);
        return true;
    }

    pub fn loadFormsForYear(self: *State, year: i32) bool {
        if (self.rejectIfFormsDirty()) return false;
        setTaxYearBuffer(&self.tax_year, year);
        self.loadEditorFormSet(year) catch |err| {
            self.setError(err);
            return false;
        };
        return true;
    }

    pub fn formSetSummaries(
        self: *const State,
    ) []const persistence.FormSetSummary {
        return self.form_set_summaries[0..self.form_set_summary_count];
    }

    pub fn formSetSummariesTruncated(self: *const State) bool {
        return self.form_set_summaries_truncated;
    }

    pub fn hasExplicitFormSet(self: *const State, tax_year: i32) bool {
        for (self.form_set_summaries[0..self.form_set_summary_count]) |summary| {
            if (summary.tax_year == tax_year) return true;
        }
        return false;
    }

    pub fn formSetYearInput(self: *const State) ?i32 {
        return parseTaxYear(self.tax_year.text()) catch null;
    }

    pub fn refreshFormSetSummaries(self: *State) !void {
        self.form_set_summary_count = 0;
        self.form_set_summaries_truncated = false;
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const profile_id = self.selectedProfileId() orelse return;
        var summaries = try store.listFormSetSummaries(allocator, profile_id);
        defer summaries.deinit(allocator);
        self.form_set_summaries_truncated =
            summaries.items.len > self.form_set_summaries.len;
        for (
            summaries.items[0..@min(
                summaries.items.len,
                self.form_set_summaries.len,
            )],
            0..,
        ) |summary, slot| {
            self.form_set_summaries[slot] = summary;
            self.form_set_summary_count += 1;
        }
    }

    /// Reverts edits without leaving the year. A configured year returns to
    /// its saved membership; a draft returns to its starting choice, because
    /// there is no earlier state to restore.
    pub fn cancelYearWorkspaceEdits(self: *State) void {
        switch (self.year_workspace) {
            .viewing => {
                self.staged_forms.copySelectionFrom(&self.saved_forms);
                self.staged_forms.resetInteraction();
            },
            .draft_choice, .draft_empty, .draft_seeded => {
                _ = self.staged_forms.clear();
                self.staged_forms.resetInteraction();
                self.draft_source_year = null;
                self.year_workspace = .draft_choice;
            },
            .conflict, .open_failed => {},
        }
        self.resetFormFilters();
    }

    /// The newest year the setup UI may open. A Forms Set is never created
    /// for a year that has not started.
    pub fn maximumSetupYear(self: *const State) i32 {
        return self.default_tax_year;
    }

    pub fn workspaceYear(self: *const State) ?i32 {
        return self.formSetYearInput();
    }

    /// True when the workspace holds work that a year switch would destroy.
    /// A draft that has only been opened holds nothing worth a prompt.
    pub fn workspaceDirty(self: *const State) bool {
        return switch (self.year_workspace) {
            .open_failed, .draft_choice => false,
            .viewing, .draft_empty, .draft_seeded, .conflict =>
                self.changedFormCount() > 0,
        };
    }

    pub fn pendingYearSwitch(self: *const State) ?i32 {
        return self.pending_year_switch;
    }

    pub fn cancelPendingYearSwitch(self: *State) void {
        self.pending_year_switch = null;
    }

    /// Applies a year switch the user confirmed after being warned. Staged
    /// work is dropped only on this explicit path.
    pub fn confirmPendingYearSwitch(self: *State) bool {
        const year = self.pending_year_switch orelse return false;
        self.pending_year_switch = null;
        self.staged_forms.copySelectionFrom(&self.saved_forms);
        return self.openYearWorkspace(year);
    }

    /// The single entry point for the yearly setup workspace.
    ///
    /// The create-versus-edit decision is always resolved against the store,
    /// never against the cached yearly summaries: a summary cache that has
    /// not caught up must not be able to present a blank create workspace for
    /// a year that already exists.
    pub fn openYearWorkspace(self: *State, year: i32) bool {
        if (self.editing_new or !self.has_selection) {
            self.setError(error.FormsRequireSavedProfile);
            return false;
        }
        if (year < minimum_setup_year or year > self.maximumSetupYear()) {
            self.setError(error.InvalidTaxYear);
            return false;
        }
        if (self.workspaceDirty() and self.workspaceYear() != year) {
            self.pending_year_switch = year;
            return false;
        }
        self.pending_year_switch = null;
        self.openYearWorkspaceFallible(year) catch |err| {
            // Fail closed: an unreadable year keeps no selection at all and
            // offers no create action, so it can never be mistaken for one
            // that is merely unconfigured.
            setTaxYearBuffer(&self.tax_year, year);
            self.saved_forms = .{};
            self.staged_forms = .{};
            self.managing_forms = false;
            self.form_set_create_mode = false;
            self.draft_source_year = null;
            self.year_workspace = .open_failed;
            self.setError(err);
            return false;
        };
        return true;
    }

    fn openYearWorkspaceFallible(self: *State, year: i32) !void {
        try self.loadEditorFormSet(year);
        setTaxYearBuffer(&self.tax_year, year);
        self.draft_source_year = null;
        self.managing_forms = true;
        self.resetFormFilters();
        self.refreshFactsSummary(year);
        if (self.form_set_state == .needs_configuration) {
            self.saved_forms = .{};
            self.staged_forms = .{};
            self.form_set_create_mode = true;
            self.year_workspace = .draft_choice;
        } else {
            self.form_set_create_mode = false;
            self.year_workspace = .viewing;
        }
    }

    /// Starts an unconfigured year from no forms. Saving this is a deliberate
    /// empty configuration, not an absence of one.
    pub fn chooseDraftEmpty(self: *State) bool {
        if (!self.year_workspace.isDraft()) return false;
        _ = self.staged_forms.clear();
        self.draft_source_year = null;
        self.year_workspace = .draft_empty;
        return true;
    }

    /// Copies another year's active forms into this draft's staged selection.
    /// Only form membership is copied: taxpayer facts are resolved from the
    /// effective history for the target period, never duplicated.
    pub fn chooseDraftSeed(self: *State, source_year: i32) bool {
        if (!self.year_workspace.isDraft()) return false;
        self.chooseDraftSeedFallible(source_year) catch |err| {
            self.setError(err);
            return false;
        };
        return true;
    }

    fn chooseDraftSeedFallible(self: *State, source_year: i32) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;
        const target_year = self.workspaceYear() orelse
            return error.InvalidTaxYear;
        if (source_year == target_year) return error.InvalidTaxYear;

        var resolved = try store.resolveFormSet(
            allocator,
            profile_id,
            source_year,
        );
        defer resolved.deinit(allocator);
        if (resolved.state == .needs_configuration) {
            return persistence.Error.NotFound;
        }

        var seeded: FormSelectionState = if (resolved.state == .legacy_catalog_default)
            FormSelectionState.allSelected()
        else
            FormSelectionState{};
        for (resolved.forms.items) |item| {
            for (&catalog.forms, 0..) |*form, index| {
                if (!std.ascii.eqlIgnoreCase(item.form_code, form.code)) continue;
                _ = seeded.set(index, true);
                break;
            }
        }
        self.staged_forms.copySelectionFrom(&seeded);
        self.draft_source_year = source_year;
        self.year_workspace = .draft_seeded;
    }

    pub fn draftSourceYear(self: *const State) ?i32 {
        return self.draft_source_year;
    }

    /// The year a draft should offer as its recommended source: the newest
    /// configured year that is not the year being set up.
    pub fn recommendedSeedYear(self: *const State) ?i32 {
        const target = self.workspaceYear();
        for (self.form_set_summaries[0..self.form_set_summary_count]) |summary| {
            if (target != null and summary.tax_year == target.?) continue;
            return summary.tax_year;
        }
        return null;
    }

    /// Recovers from a duplicate created by another window. The persisted set
    /// becomes the comparison baseline while the user's staged choices are
    /// preserved as pending changes they can still save or abandon.
    pub fn reviewConflictingYear(self: *State) bool {
        if (self.year_workspace != .conflict) return false;
        const year = self.workspaceYear() orelse return false;
        self.rebaseOnPersisted(year) catch |err| {
            self.setError(err);
            return false;
        };
        self.setNotice(
            .neutral,
            "Loaded the saved setup. Your choices are shown as pending changes.",
        );
        return true;
    }

    /// Abandons the staged draft and adopts the setup another window saved.
    pub fn discardConflictingDraft(self: *State) bool {
        if (self.year_workspace != .conflict) return false;
        const year = self.workspaceYear() orelse return false;
        if (!self.openYearWorkspaceAfterConflict(year)) return false;
        self.setNotice(.neutral, "Your draft was discarded.");
        return true;
    }

    fn openYearWorkspaceAfterConflict(self: *State, year: i32) bool {
        self.year_workspace = .viewing;
        self.staged_forms.copySelectionFrom(&self.saved_forms);
        return self.openYearWorkspace(year);
    }

    /// Loads persisted membership into the saved baseline only. The staged
    /// selection is deliberately untouched so a conflict never discards work.
    fn rebaseOnPersisted(self: *State, year: i32) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;
        var resolved = try store.resolveFormSet(allocator, profile_id, year);
        defer resolved.deinit(allocator);

        self.form_set_state = resolved.state;
        self.legacy_form_set_reset_allowed = resolved.legacy_reset_allowed;
        self.forms_set_configured = switch (resolved.state) {
            .active_empty, .active_nonempty => true,
            .needs_configuration, .legacy_catalog_default => false,
        };
        self.saved_forms = if (resolved.state == .legacy_catalog_default)
            FormSelectionState.allSelected()
        else
            FormSelectionState{};
        for (resolved.forms.items) |item| {
            for (&catalog.forms, 0..) |*form, index| {
                if (!std.ascii.eqlIgnoreCase(item.form_code, form.code)) continue;
                _ = self.saved_forms.set(index, true);
                break;
            }
        }
        self.form_set_create_mode = false;
        self.managing_forms = true;
        self.year_workspace = .viewing;
        self.draft_source_year = null;
        try self.updateFormSetSummary();
        try self.refreshFormSetSummaries();
    }

    /// Saves the open year. A draft creates; a configured year updates. A
    /// duplicate created concurrently becomes a recoverable conflict rather
    /// than a lost draft or a silent overwrite.
    pub fn saveYearWorkspace(self: *State) bool {
        if (self.year_workspace == .draft_choice or
            self.year_workspace == .open_failed or
            self.year_workspace == .conflict)
        {
            return false;
        }
        const creating = self.year_workspace.isDraft();
        const year = self.workspaceYear();
        // Setting up a historical year must not invent facts for it. The user
        // records what was true then, reviewed, before its forms can be saved.
        if (creating and self.factsMissingForYear()) {
            self.setError(error.NoFactsEffectiveForYear);
            return false;
        }
        self.saveManagedFormsFallible() catch |err| {
            if (creating and err == persistence.Error.FormSetAlreadyExists) {
                self.year_workspace = .conflict;
                self.managing_forms = true;
                self.setNotice(
                    .failure,
                    "This year was set up in another window while you were working. Your choices are still here.",
                );
                return false;
            }
            self.setError(err);
            return false;
        };
        self.year_workspace = .viewing;
        self.draft_source_year = null;
        self.managing_forms = true;
        self.resetFormFilters();
        self.setSaveNotice(year);
        return true;
    }

    fn setSaveNotice(self: *State, year: ?i32) void {
        var message: [128]u8 = undefined;
        const active = self.saved_forms.selectedCount();
        const rendered = if (year) |value| (if (active == 0)
            std.fmt.bufPrint(
                &message,
                "Forms for {d} saved · no active forms.",
                .{value},
            ) catch "Your forms were saved."
        else if (active == 1)
            std.fmt.bufPrint(
                &message,
                "Forms for {d} saved · 1 active form.",
                .{value},
            ) catch "Your forms were saved."
        else
            std.fmt.bufPrint(
                &message,
                "Forms for {d} saved · {d} active forms.",
                .{ value, active },
            ) catch "Your forms were saved.") else "Your forms were saved.";
        self.setNotice(.success, rendered);
    }

    pub fn beginManageForms(self: *State) bool {
        if (self.editing_new or !self.has_selection) {
            self.setError(error.FormsRequireSavedProfile);
            return false;
        }
        self.staged_forms.copySelectionFrom(&self.saved_forms);
        self.staged_forms.resetInteraction();
        self.managing_forms = true;
        self.form_set_create_mode =
            self.form_set_state == .needs_configuration or
            self.form_set_state == .legacy_catalog_default;
        self.resetFormFilters();
        return true;
    }

    pub fn applyFormsQuery(self: *State, edit: canvas.TextInputEvent) void {
        self.staged_forms.applyQuery(edit);
    }

    pub fn formsQuery(self: *const State) []const u8 {
        return self.staged_forms.query();
    }

    pub fn formFilterActiveSelected(self: *const State) bool {
        return self.form_activity_filter != .inactive;
    }

    pub fn formFilterInactiveSelected(self: *const State) bool {
        return self.form_activity_filter != .active;
    }

    pub fn formFilterEditorSelected(self: *const State) bool {
        return self.form_capability_filter != .calendar_only;
    }

    pub fn formFilterCalendarOnlySelected(self: *const State) bool {
        return self.form_capability_filter != .editor;
    }

    pub fn formFilterActiveLocked(self: *const State) bool {
        return self.form_activity_filter == .active;
    }

    pub fn formFilterInactiveLocked(self: *const State) bool {
        return self.form_activity_filter == .inactive;
    }

    pub fn formFilterEditorLocked(self: *const State) bool {
        return self.form_capability_filter == .editor;
    }

    pub fn formFilterCalendarOnlyLocked(self: *const State) bool {
        return self.form_capability_filter == .calendar_only;
    }

    pub fn toggleFormFilterActive(self: *State) void {
        self.form_activity_filter = switch (self.form_activity_filter) {
            .active => .active,
            .inactive => .all,
            .all => .inactive,
        };
    }

    pub fn toggleFormFilterInactive(self: *State) void {
        self.form_activity_filter = switch (self.form_activity_filter) {
            .active => .all,
            .inactive => .inactive,
            .all => .active,
        };
    }

    pub fn toggleFormFilterEditor(self: *State) void {
        self.form_capability_filter = switch (self.form_capability_filter) {
            .all => .calendar_only,
            .editor => .editor,
            .calendar_only => .all,
        };
    }

    pub fn toggleFormFilterCalendarOnly(self: *State) void {
        self.form_capability_filter = switch (self.form_capability_filter) {
            .all => .editor,
            .editor => .all,
            .calendar_only => .calendar_only,
        };
    }

    pub fn resetFormFilters(self: *State) void {
        self.form_activity_filter = if (self.managing_forms) .all else .active;
        self.form_capability_filter = .all;
    }

    pub fn cancelManageForms(self: *State) void {
        self.staged_forms.copySelectionFrom(&self.saved_forms);
        self.staged_forms.resetInteraction();
        self.managing_forms = false;
        self.form_set_create_mode = false;
        self.resetFormFilters();
    }

    pub fn toggleStagedForm(self: *State, index: usize) void {
        if (!self.managing_forms) return;
        _ = self.staged_forms.toggle(index);
    }

    pub fn selectAllStagedForms(self: *State) void {
        if (self.managing_forms) _ = self.staged_forms.setAll(true);
    }

    pub fn clearAllStagedForms(self: *State) void {
        if (self.managing_forms) _ = self.staged_forms.clear();
    }

    pub fn formsDirty(self: *const State) bool {
        return self.managing_forms and
            !self.staged_forms.selectionEql(&self.saved_forms);
    }

    pub fn displayedFormSelected(self: *const State, index: usize) bool {
        if (index >= catalog.registry_count) return false;
        return if (self.managing_forms)
            self.staged_forms.isSelected(index)
        else
            self.saved_forms.isSelected(index);
    }

    /// Authoritative membership used by Browse mode. This never reflects an
    /// unsaved Manage-mode toggle.
    pub fn persistedFormSelected(self: *const State, index: usize) bool {
        return self.saved_forms.isSelected(index);
    }

    /// Candidate membership used only by Manage mode until Save succeeds.
    pub fn stagedFormSelected(self: *const State, index: usize) bool {
        return self.staged_forms.isSelected(index);
    }

    pub fn activeFormCount(self: *const State) usize {
        return self.saved_forms.selectedCount();
    }

    pub fn stagedFormCount(self: *const State) usize {
        return self.staged_forms.selectedCount();
    }

    pub fn changedFormCount(self: *const State) usize {
        var count: usize = 0;
        for (0..catalog.registry_count) |index| {
            if (self.saved_forms.isSelected(index) !=
                self.staged_forms.isSelected(index))
            {
                count += 1;
            }
        }
        return count;
    }

    pub fn managedFormStatus(
        self: *const State,
        index: usize,
    ) ?ManagedFormStatus {
        if (index >= catalog.registry_count) return null;
        const persisted = self.saved_forms.isSelected(index);
        const staged = self.staged_forms.isSelected(index);
        return switch (@as(u2, @intFromBool(persisted)) << 1 |
            @as(u2, @intFromBool(staged))) {
            0b00 => .inactive,
            0b01 => .will_activate,
            0b10 => .will_deactivate,
            0b11 => .active,
        };
    }

    pub fn managedFormStatusLabel(
        self: *const State,
        index: usize,
    ) []const u8 {
        const status = self.managedFormStatus(index) orelse
            return "Unavailable";
        return status.label();
    }

    pub fn saveManagedForms(self: *State) bool {
        self.saveManagedFormsFallible() catch |err| {
            self.setError(err);
            return false;
        };
        self.setNotice(.success, "Your forms were saved for this tax year.");
        return true;
    }

    fn saveManagedFormsFallible(self: *State) !void {
        const store = self.store orelse return error.NotAttached;
        if (self.editing_new) return error.FormsRequireSavedProfile;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;
        const year = try parseTaxYear(self.tax_year.text());
        var writes: [max_registered_forms]persistence.FormRegistrationWrite =
            undefined;
        var count: usize = 0;
        for (&catalog.forms, 0..) |*form, index| {
            if (!self.staged_forms.isSelected(index)) continue;
            writes[count] = .{
                .form_code = form.code,
                .form_revision = form.revision orelse "calendar-only",
            };
            count += 1;
        }
        if (self.form_set_create_mode or
            self.form_set_state == .needs_configuration or
            self.form_set_state == .legacy_catalog_default)
        {
            try store.createFormSet(profile_id, year, writes[0..count]);
        } else {
            try store.updateFormSet(profile_id, year, writes[0..count]);
        }
        self.saved_forms.copySelectionFrom(&self.staged_forms);
        self.staged_forms.resetInteraction();
        self.form_set_state = if (count == 0) .active_empty else .active_nonempty;
        self.forms_set_configured = true;
        self.managing_forms = false;
        self.form_set_create_mode = false;
        self.resetFormFilters();
        try self.updateFormSetSummary();
        try self.refreshFormSetSummaries();
        try self.refreshCalendarFormSet(year);
    }

    pub fn resetManagedFormsToLegacyDefault(self: *State) bool {
        self.resetManagedFormsToLegacyDefaultFallible() catch |err| {
            self.setError(err);
            return false;
        };
        self.setNotice(.success, "The original catalog default was restored.");
        return true;
    }

    fn resetManagedFormsToLegacyDefaultFallible(self: *State) !void {
        const store = self.store orelse return error.NotAttached;
        if (self.editing_new) return error.FormsRequireSavedProfile;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;
        const year = try parseTaxYear(self.tax_year.text());
        try store.resetToLegacyCatalogDefault(profile_id, year);
        self.saved_forms = FormSelectionState.allSelected();
        self.staged_forms.copySelectionFrom(&self.saved_forms);
        self.staged_forms.resetInteraction();
        self.form_set_state = .legacy_catalog_default;
        self.forms_set_configured = false;
        self.managing_forms = false;
        self.form_set_create_mode = false;
        self.resetFormFilters();
        try self.updateFormSetSummary();
        try self.refreshCalendarFormSet(year);
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
        if (tax_year < 1 or tax_year > 9999) return error.InvalidTaxYear;
        // Publish an unavailable, authoritative-empty cache first. Any later
        // persistence or bounded-copy failure therefore remains fail-closed
        // and cannot leave stale data from a prior profile or viewed year.
        self.invalidateCalendarFormSetCache(tax_year);

        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;

        var refreshed = calendarFormSetCacheEntries(tax_year);

        if (self.selectedProfileId()) |profile_id| {
            for (&refreshed) |*cache| {
                if (cache.tax_year == 0) continue;
                var resolved = try store.resolveFormSet(
                    allocator,
                    profile_id,
                    cache.tax_year,
                );
                defer resolved.deinit(allocator);
                cache.resolution = if (resolved.state == .legacy_catalog_default)
                    .catalog_fallback
                else
                    .configured;
                if (resolved.forms.items.len > cache.codes.len) {
                    return error.TooManyForms;
                }
                for (resolved.forms.items, 0..) |item, index| {
                    try cache.codes[index].set(item.form_code);
                }
                cache.count = resolved.forms.items.len;
            }
        }

        // Publish both successful resolutions together. Until this point the
        // visible cache remains unavailable rather than partially refreshed.
        self.cached_calendar_form_sets = refreshed;
    }

    /// Tells existing calendar callers whether cached codes are authoritative.
    /// `false` is reserved for a successfully resolved catalog fallback.
    /// Missing or failed resolutions return `true` with zero cached codes so
    /// callers that branch on this API remain fail-closed.
    pub fn calendarFormSetConfigured(
        self: *const State,
        tax_year: i32,
    ) bool {
        const cache = self.calendarFormSetCache(tax_year) orelse return true;
        return cache.resolution != .catalog_fallback;
    }

    pub fn calendarFormSetAvailable(
        self: *const State,
        tax_year: i32,
    ) bool {
        const cache = self.calendarFormSetCache(tax_year) orelse return false;
        return cache.resolution != .unavailable;
    }

    pub fn calendarFormCodes(
        self: *const State,
        arena: std.mem.Allocator,
        tax_year: i32,
    ) []const []const u8 {
        const cache = self.calendarFormSetCache(tax_year) orelse return &.{};
        if (cache.resolution != .configured) return &.{};
        const output = arena.alloc([]const u8, cache.count) catch return &.{};
        for (cache.codes[0..cache.count], 0..) |*code, index| {
            output[index] = code.text();
        }
        return output;
    }

    /// Successfully queried, unconfigured years use the catalog fallback.
    /// Configured sets are authoritative, including when empty; unavailable
    /// or uncached years are also authoritative-empty until a refresh succeeds.
    pub fn formAvailable(
        self: *const State,
        tax_year: i32,
        form_code: []const u8,
    ) bool {
        const cache = self.calendarFormSetCache(tax_year) orelse return false;
        if (cache.resolution == .unavailable) return false;
        if (cache.resolution == .catalog_fallback) return true;
        for (cache.codes[0..cache.count]) |*code| {
            if (std.ascii.eqlIgnoreCase(code.text(), form_code)) return true;
        }
        return false;
    }

    fn calendarFormSetCache(
        self: *const State,
        tax_year: i32,
    ) ?*const CalendarFormSetCache {
        for (&self.cached_calendar_form_sets) |*cache| {
            if (cache.tax_year == tax_year) return cache;
        }
        return null;
    }

    fn invalidateCalendarFormSetCache(self: *State, tax_year: i32) void {
        self.cached_calendar_form_sets = calendarFormSetCacheEntries(tax_year);
    }

    /// Loads the profile-level calendar filter into caller-owned selection
    /// state. No persisted parent means every current catalog form is
    /// selected; a present parent with no rows means none are selected.
    pub fn refreshCalendarFormSelection(
        self: *State,
        catalog_codes: []const []const u8,
        selected: []bool,
    ) bool {
        self.refreshCalendarFormSelectionFallible(
            catalog_codes,
            selected,
        ) catch {
            // A durable preference that could not be read must never be
            // widened to every form. Keep the caller fail-closed until a
            // later refresh succeeds.
            @memset(selected, false);
            self.setNotice(
                .failure,
                "Calendar form choices could not be loaded. Deadlines and export are unavailable until the profile is reopened.",
            );
            return false;
        };
        return true;
    }

    fn refreshCalendarFormSelectionFallible(
        self: *State,
        catalog_codes: []const []const u8,
        selected: []bool,
    ) !void {
        if (catalog_codes.len != selected.len or
            catalog_codes.len > max_registered_forms)
        {
            return error.TooManyForms;
        }
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;

        @memset(selected, true);
        var maybe_selection = try store.getCalendarFormSelection(
            allocator,
            profile_id,
        );
        if (maybe_selection) |*selection| {
            defer selection.deinit(allocator);
            @memset(selected, false);
            for (selection.form_codes) |stored_code| {
                for (catalog_codes, 0..) |catalog_code, index| {
                    if (!std.ascii.eqlIgnoreCase(
                        stored_code,
                        catalog_code,
                    )) continue;
                    selected[index] = true;
                    break;
                }
            }
        }
    }

    /// Persists only explicit subsets. Selecting the complete catalog removes
    /// the parent marker so new forms remain selected automatically.
    pub fn persistCalendarFormSelection(
        self: *State,
        catalog_codes: []const []const u8,
        selected: []const bool,
    ) bool {
        self.persistCalendarFormSelectionFallible(
            catalog_codes,
            selected,
        ) catch {
            self.setNotice(
                .failure,
                "Calendar form choices could not be saved. The last saved selection will be restored.",
            );
            return false;
        };
        return true;
    }

    fn persistCalendarFormSelectionFallible(
        self: *State,
        catalog_codes: []const []const u8,
        selected: []const bool,
    ) !void {
        if (catalog_codes.len != selected.len or
            catalog_codes.len > max_registered_forms)
        {
            return error.TooManyForms;
        }
        const store = self.store orelse return error.NotAttached;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;

        var selected_count: usize = 0;
        for (selected) |is_selected| {
            if (is_selected) selected_count += 1;
        }
        if (selected_count == catalog_codes.len) {
            _ = try store.clearCalendarFormSelection(profile_id);
            return;
        }

        var selected_codes: [max_registered_forms][]const u8 = undefined;
        var output_index: usize = 0;
        for (catalog_codes, selected) |form_code, is_selected| {
            if (!is_selected) continue;
            selected_codes[output_index] = form_code;
            output_index += 1;
        }
        try store.replaceCalendarFormSelection(
            profile_id,
            selected_codes[0..output_index],
        );
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
            if (fields.Tin.parse(item.tin)) |parsed| {
                try row.tin_root.set(parsed.root());
                if (parsed.branch()) |segment| {
                    try row.branch_code.set(segment);
                }
            } else |_| {}
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
        self.reportSharedTin();
    }

    /// Names a TIN held by two loaded taxpayers.
    ///
    /// Nothing can create this state now, but data written before the rule
    /// existed still can hold it, and silently rendering two taxpayers that
    /// cannot be told apart is worse than saying so. Never prints a full TIN.
    fn reportSharedTin(self: *State) void {
        const loaded = self.profiles[0..self.profile_count];
        for (loaded, 0..) |*row, index| {
            const left = fields.Tin.parse(row.tin.text()) catch continue;
            for (loaded[index + 1 ..]) |*other| {
                const right = fields.Tin.parse(other.tin.text()) catch continue;
                if (!left.eql(&right)) continue;
                var masked_buffer: [24]u8 = undefined;
                const masked = left.writeMasked(&masked_buffer) catch return;
                var message: [200]u8 = undefined;
                self.setNotice(.failure, std.fmt.bufPrint(
                    &message,
                    "Two taxpayers share TIN {s}. Their filings cannot be told apart — review them.",
                    .{masked},
                ) catch "Two taxpayers share one TIN. Their filings cannot be told apart.");
                return;
            }
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
        const loaded_from = revision.effective.from.writeIso(&date_buffer);
        setEditorBuffer(&self.effective_from, loaded_from);
        try self.loaded_effective_from.set(loaded_from);
        self.change_intent = .record_change;
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
        self.selected_tax_type.clear();
        self.government_withholding_agent = .unset;
        for (revision.registration_facts) |fact| {
            switch (fact.value) {
                .tax_type => |value| {
                    if (registrationFactKindCount(revision, .tax_type) == 1) {
                        setEditorBuffer(&self.tax_type, value.asSlice());
                        try self.selected_tax_type.set(value.asSlice());
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
        self.captureBaseline();
        self.refreshFactsSummary(self.default_tax_year);
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
        var resolved = try store.resolveFormSet(allocator, profile_id, tax_year);
        defer resolved.deinit(allocator);
        self.form_set_state = resolved.state;
        self.legacy_form_set_reset_allowed = resolved.legacy_reset_allowed;
        self.forms_set_configured = switch (resolved.state) {
            .active_empty, .active_nonempty => true,
            .needs_configuration, .legacy_catalog_default => false,
        };
        self.saved_forms = if (resolved.state == .legacy_catalog_default)
            FormSelectionState.allSelected()
        else
            FormSelectionState{};
        for (resolved.forms.items) |item| {
            for (&catalog.forms, 0..) |*form, index| {
                if (!std.ascii.eqlIgnoreCase(item.form_code, form.code)) continue;
                _ = self.saved_forms.set(index, true);
                break;
            }
        }
        self.staged_forms.copySelectionFrom(&self.saved_forms);
        self.staged_forms.resetInteraction();
        self.managing_forms = false;
        self.form_set_create_mode = false;
        self.year_workspace = .viewing;
        self.draft_source_year = null;
        self.resetFormFilters();
        try self.updateFormSetSummary();
    }

    fn updateFormSetSummary(self: *State) !void {
        var summary: [128]u8 = undefined;
        const state_label = switch (self.form_set_state) {
            .needs_configuration => "Needs configuration",
            .legacy_catalog_default => "Legacy catalog default",
            .active_empty => "Active empty",
            .active_nonempty => "Active",
        };
        const text = try std.fmt.bufPrint(
            &summary,
            "{s} - {d} of {d} active",
            .{ state_label, self.saved_forms.selectedCount(), catalog.registry_count },
        );
        setEditorBuffer(&self.forms_set, text);
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
        self.form_set_state = .needs_configuration;
        self.legacy_form_set_reset_allowed = false;
        self.saved_forms = .{};
        self.staged_forms = .{};
        self.managing_forms = false;
        self.form_set_create_mode = false;
        self.year_workspace = .viewing;
        self.draft_source_year = null;
        self.pending_year_switch = null;
        self.branch_mode = false;
        self.branch_source_root.clear();
        self.branch_source_name.clear();
        self.change_intent = .record_change;
        self.selected_tax_type.clear();
        self.resetFormFilters();
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
        self.notice_epoch +%= 1;
    }

    /// Records a specific failure message for the error about to be returned.
    /// Refusals that can name the taxpayer involved are far more useful than
    /// the generic mapping, which cannot see the offending row.
    fn setErrorDetail(self: *State, message: []const u8) void {
        self.pending_error_detail.set(message) catch {
            self.pending_error_detail.clear();
            return;
        };
        self.has_pending_error_detail = true;
    }

    fn setError(self: *State, err: anyerror) void {
        if (self.has_pending_error_detail) {
            self.has_pending_error_detail = false;
            self.setNotice(.failure, self.pending_error_detail.text());
            self.pending_error_detail.clear();
            return;
        }
        const message = switch (err) {
            persistence.Error.RevisionConflict => "This profile changed elsewhere. Reload it before saving a new revision.",
            error.UnknownFormCode => "One of the chosen forms is not in the 51-form catalog.",
            error.InvalidTaxYear => "Tax year must be a four-digit year from 0001 through 9999.",
            error.ActivityRequiresBusinessLine => "An activity ATC requires a line of business. Tax type remains an independent registration fact.",
            error.PersonalFieldsNotApplicable => "Birth date, citizenship, and foreign tax number apply only to individual subjects.",
            error.TradeNameNotApplicable => "A trade name applies only to a sole proprietor.",
            error.SourceReferenceRequired => "Imported and migrated revisions require a source reference.",
            error.ManualSourceHasReference => "Manual entry has no external source reference. Choose Imported or Migrated.",
            error.UnsupportedRepeatedComponents => "This repeated-component revision is preserved, but cannot be rewritten by the single-activity editor.",
            error.UnsavedFormSetChanges => "Save or cancel your unsaved form changes before switching taxpayers.",
            error.UnsavedProfileChanges => "Save or cancel your unsaved taxpayer details before switching taxpayers.",
            error.DuplicateTaxpayerIdentifier,
            persistence.Error.DuplicateCanonicalTin,
            => "That TIN already belongs to a taxpayer you have. Open it instead of adding it again.",
            error.BranchTinRootChanged => "A branch keeps the same nine-digit TIN as its head office. Change only the branch code.",
            error.BranchCodeRequired => "Add the branch code after the nine-digit TIN, for example 123-456-789-002.",
            error.BranchLegalPersonChanged => "A branch is the same taxpayer. A different kind of taxpayer needs its own profile.",
            error.NoFactsEffectiveForYear => "No taxpayer details exist for that year yet. Record what was true then before setting up its forms.",
            error.FormsRequireSavedProfile => "Save this taxpayer profile before choosing its forms.",
            persistence.Error.FormSetAlreadyExists => "That year is already set up. Choose it from the year list to edit its forms.",
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

/// End-user names for the canonical reusable facts. These are the words the
/// editor uses, so a missing-detail message points at a field the user can see.
pub fn reusableFieldLabel(key: fields.ReusableField) []const u8 {
    return switch (key) {
        .tin => "Taxpayer Identification Number (TIN)",
        .rdo_code => "Revenue District Office (RDO) code",
        .taxpayer_name => "Taxpayer or registered name",
        .registered_name => "Registered name",
        .registered_address => "Registered address",
        .zip_code => "ZIP code",
        .contact_number => "Contact number",
        .email_address => "Registered email address",
        .date_of_birth => "Birth date",
        .citizenship => "Citizenship",
        .foreign_tax_number => "Foreign tax number",
        .line_of_business => "Line of business",
        .atc => "Alphanumeric Tax Code (ATC)",
        .tax_type => "Registered tax type",
        .government_withholding_agent => "Government withholding agent",
        .special_rate_basis => "Special-rate basis",
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

/// Copies a slice into caller-owned scratch so it survives the editor being
/// cleared. Reusing values across a reset would otherwise read freed bytes.
fn copyInto(buffer: []u8, value: []const u8) []const u8 {
    const length = @min(buffer.len, value.len);
    @memcpy(buffer[0..length], value[0..length]);
    return buffer[0..length];
}

test "form filter checkbox groups stay nonempty and reset by context" {
    var state = State{};

    try std.testing.expect(state.formFilterActiveSelected());
    try std.testing.expect(!state.formFilterInactiveSelected());
    try std.testing.expect(state.formFilterEditorSelected());
    try std.testing.expect(state.formFilterCalendarOnlySelected());
    try std.testing.expect(state.formFilterActiveLocked());

    state.toggleFormFilterActive();
    try std.testing.expectEqual(FormActivityFilter.active, state.form_activity_filter);

    state.toggleFormFilterInactive();
    try std.testing.expectEqual(FormActivityFilter.all, state.form_activity_filter);
    try std.testing.expect(state.formFilterActiveSelected());
    try std.testing.expect(state.formFilterInactiveSelected());

    state.toggleFormFilterActive();
    try std.testing.expectEqual(FormActivityFilter.inactive, state.form_activity_filter);
    try std.testing.expect(state.formFilterInactiveLocked());

    state.toggleFormFilterEditor();
    try std.testing.expectEqual(
        FormCapabilityFilter.calendar_only,
        state.form_capability_filter,
    );
    try std.testing.expect(state.formFilterCalendarOnlyLocked());

    state.toggleFormFilterEditor();
    try std.testing.expectEqual(FormCapabilityFilter.all, state.form_capability_filter);

    state.managing_forms = true;
    state.resetFormFilters();
    try std.testing.expectEqual(FormActivityFilter.all, state.form_activity_filter);
    try std.testing.expectEqual(FormCapabilityFilter.all, state.form_capability_filter);

    state.managing_forms = false;
    state.resetFormFilters();
    try std.testing.expectEqual(FormActivityFilter.active, state.form_activity_filter);
    try std.testing.expectEqual(FormCapabilityFilter.all, state.form_capability_filter);
}

test "managed Forms Set status compares persisted and staged membership" {
    var state = State{};

    // 0: inactive, 1: active, 2: pending activation, 3: pending
    // deactivation. These are the four states rendered by Manage cards.
    _ = state.saved_forms.set(1, true);
    _ = state.staged_forms.set(1, true);
    _ = state.staged_forms.set(2, true);
    _ = state.saved_forms.set(3, true);

    try std.testing.expectEqual(@as(usize, 2), state.activeFormCount());
    try std.testing.expectEqual(@as(usize, 2), state.stagedFormCount());
    try std.testing.expectEqual(@as(usize, 2), state.changedFormCount());

    try std.testing.expectEqual(
        ManagedFormStatus.inactive,
        state.managedFormStatus(0).?,
    );
    try std.testing.expectEqualStrings("Inactive", state.managedFormStatusLabel(0));
    try std.testing.expectEqual(
        ManagedFormStatus.active,
        state.managedFormStatus(1).?,
    );
    try std.testing.expectEqualStrings("Active", state.managedFormStatusLabel(1));
    try std.testing.expectEqual(
        ManagedFormStatus.will_activate,
        state.managedFormStatus(2).?,
    );
    try std.testing.expectEqualStrings(
        "Will activate",
        state.managedFormStatusLabel(2),
    );
    try std.testing.expectEqual(
        ManagedFormStatus.will_deactivate,
        state.managedFormStatus(3).?,
    );
    try std.testing.expectEqualStrings(
        "Will deactivate",
        state.managedFormStatusLabel(3),
    );

    try std.testing.expect(!state.managedFormStatus(0).?.changed());
    try std.testing.expect(state.managedFormStatus(2).?.changed());
    try std.testing.expect(state.persistedFormSelected(3));
    try std.testing.expect(!state.stagedFormSelected(3));
    try std.testing.expect(
        state.managedFormStatus(catalog.registry_count) == null,
    );
    try std.testing.expectEqualStrings(
        "Unavailable",
        state.managedFormStatusLabel(catalog.registry_count),
    );
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

test "form availability distinguishes unavailable fallback and configured sets" {
    var state = State{};
    state.cached_calendar_form_sets[0].tax_year = 2026;
    state.cached_calendar_form_sets[1].tax_year = 2025;

    try std.testing.expect(!state.formAvailable(2026, "2551Q"));
    try std.testing.expect(state.calendarFormSetConfigured(2026));

    state.cached_calendar_form_sets[0].resolution = .catalog_fallback;
    try std.testing.expect(state.formAvailable(2026, "2551Q"));
    try std.testing.expect(!state.calendarFormSetConfigured(2026));

    state.cached_calendar_form_sets[0].resolution = .configured;
    try std.testing.expect(!state.formAvailable(2026, "2551Q"));

    try state.cached_calendar_form_sets[0].codes[0].set("2551Q");
    state.cached_calendar_form_sets[0].count = 1;
    try std.testing.expect(state.formAvailable(2026, "2551q"));
    try std.testing.expect(!state.formAvailable(2026, "1701Q"));

    state.cached_calendar_form_sets[1].resolution = .configured;
    try std.testing.expect(!state.formAvailable(2025, "2551Q"));
    try state.cached_calendar_form_sets[1].codes[0].set("1701Q");
    state.cached_calendar_form_sets[1].count = 1;
    try std.testing.expect(state.formAvailable(2025, "1701q"));
    try std.testing.expect(!state.formAvailable(2025, "2551Q"));

    // A year outside the two-entry cache has no successful fallback query and
    // therefore remains authoritative-empty.
    try std.testing.expect(!state.formAvailable(2024, "2551Q"));
    try std.testing.expect(state.calendarFormSetConfigured(2024));
}

test "calendar form refresh failure invalidates stale profile and year data" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    store.close();

    var state = State{
        .allocator = allocator,
        .store = &store,
        .has_selection = true,
    };
    try state.selected_id.set("closed-store-profile");
    state.cached_calendar_form_sets[0].tax_year = 2026;
    state.cached_calendar_form_sets[0].resolution = .configured;
    try state.cached_calendar_form_sets[0].codes[0].set("2551Q");
    state.cached_calendar_form_sets[0].count = 1;
    try std.testing.expect(state.formAvailable(2026, "2551Q"));

    try std.testing.expectError(
        persistence.Error.Closed,
        state.refreshCalendarFormSet(2027),
    );

    // The failed refresh published unavailable entries for 2027 and 2026
    // before attempting I/O, so neither the stale code nor catalog-all leaks.
    try std.testing.expect(!state.formAvailable(2027, "2551Q"));
    try std.testing.expect(!state.formAvailable(2026, "2551Q"));
    try std.testing.expect(!state.formAvailable(2025, "2551Q"));
    try std.testing.expect(state.calendarFormSetConfigured(2027));
    try std.testing.expect(state.calendarFormSetConfigured(2026));

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    try std.testing.expectEqual(
        @as(usize, 0),
        state.calendarFormCodes(arena_state.allocator(), 2026).len,
    );
}

test "failed selected profile switch cannot reuse prior profile forms" {
    var state = State{};
    state.default_tax_year = 2027;
    state.profile_count = 1;
    state.profiles[0] = .{
        .slot = 0,
        .subject_kind = .individual,
    };
    try state.profiles[0].stable_id.set("new-profile");

    state.cached_calendar_form_sets[0].tax_year = 2026;
    state.cached_calendar_form_sets[0].resolution = .configured;
    try state.cached_calendar_form_sets[0].codes[0].set("1701Q");
    state.cached_calendar_form_sets[0].count = 1;
    try std.testing.expect(state.formAvailable(2026, "1701Q"));

    try std.testing.expectError(error.NotAttached, state.selectSlot(0));
    try std.testing.expect(!state.formAvailable(2027, "1701Q"));
    try std.testing.expect(!state.formAvailable(2026, "1701Q"));
}

test "profile notices expose transient and manually dismissible lifecycles" {
    var state = State{};
    const initial_epoch = state.noticeEpoch();

    state.startNew();
    try std.testing.expect(state.noticeVisible());
    try std.testing.expect(state.noticeAutoDismissible());
    try std.testing.expect(state.noticeEpoch() != initial_epoch);
    try std.testing.expect(!state.noticeSuccess());
    try std.testing.expect(!state.noticeFailure());

    state.setNotice(.failure, "Profile validation failed.");
    try std.testing.expect(state.noticeVisible());
    try std.testing.expect(!state.noticeAutoDismissible());
    try std.testing.expect(!state.noticeSuccess());
    try std.testing.expect(state.noticeFailure());

    const failure_epoch = state.noticeEpoch();
    state.dismissNotice();
    try std.testing.expect(!state.noticeVisible());
    try std.testing.expect(state.noticeEpoch() != failure_epoch);
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
    try std.testing.expect(state.save());
    _ = state.beginManageForms();
    state.clearAllStagedForms();
    try std.testing.expect(state.saveManagedForms());

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

    // A newly-created profile never widens an unconfigured year to the
    // catalog. The preceding year is authoritative-empty until configured.
    try std.testing.expect(state.calendarFormSetConfigured(2025));
    try std.testing.expect(!state.formAvailable(2025, "2551Q"));

    try store.replaceFormSet(profile_id.asSlice(), 2025, &.{.{
        .form_code = "1701Q",
        .form_revision = "2018-01-ENCS",
    }});
    try state.refreshCalendarFormSet(2026);
    try std.testing.expect(state.calendarFormSetConfigured(2026));
    try std.testing.expect(!state.formAvailable(2026, "1701Q"));
    try std.testing.expect(state.calendarFormSetConfigured(2025));
    try std.testing.expect(state.formAvailable(2025, "1701q"));
    try std.testing.expect(!state.formAvailable(2025, "2551Q"));

    var cache_arena = std.heap.ArenaAllocator.init(allocator);
    defer cache_arena.deinit();
    const prior_codes = state.calendarFormCodes(
        cache_arena.allocator(),
        2025,
    );
    try std.testing.expectEqual(@as(usize, 1), prior_codes.len);
    try std.testing.expectEqualStrings("1701Q", prior_codes[0]);
}

test "staged Forms Set is isolated until save and blocks context switches" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-07-29", 2026);
    state.tin.set("123-456-789-000");
    state.rdo.set("040");
    state.display_name.set("Staged Forms Taxpayer");
    state.registered_address.set("Quezon City");
    state.effective_from.set("2026-01-01");
    try std.testing.expect(state.save());
    try std.testing.expectEqual(
        persistence.FormSetState.needs_configuration,
        state.form_set_state,
    );
    try std.testing.expect(!state.formAvailable(2026, "2551Q"));

    var form_index: ?usize = null;
    for (&catalog.forms, 0..) |*form, index| {
        if (std.mem.eql(u8, form.code, "2551Q")) form_index = index;
    }
    const index = form_index.?;
    _ = state.beginManageForms();
    try std.testing.expectEqual(FormActivityFilter.all, state.form_activity_filter);
    try std.testing.expectEqual(FormCapabilityFilter.all, state.form_capability_filter);
    state.toggleStagedForm(index);
    try std.testing.expect(state.formsDirty());
    try std.testing.expectEqual(@as(usize, 1), state.stagedFormCount());
    try std.testing.expectEqual(@as(usize, 1), state.changedFormCount());
    try std.testing.expectEqual(
        ManagedFormStatus.will_activate,
        state.managedFormStatus(index).?,
    );
    try std.testing.expect(!state.formAvailable(2026, "2551Q"));
    try std.testing.expectError(error.UnsavedFormSetChanges, state.selectSlot(0));

    state.cancelManageForms();
    try std.testing.expect(!state.formsDirty());
    try std.testing.expectEqual(@as(usize, 0), state.stagedFormCount());
    try std.testing.expectEqual(@as(usize, 0), state.changedFormCount());
    try std.testing.expect(!state.displayedFormSelected(index));
    try std.testing.expectEqual(FormActivityFilter.active, state.form_activity_filter);
    try std.testing.expectEqual(FormCapabilityFilter.all, state.form_capability_filter);

    _ = state.beginManageForms();
    state.toggleStagedForm(index);
    try std.testing.expect(state.saveManagedForms());
    try std.testing.expect(state.formAvailable(2026, "2551Q"));
    try std.testing.expect(!state.formAvailable(2026, "1701Q"));
    try std.testing.expectEqual(@as(usize, 1), state.activeFormCount());
    try std.testing.expectEqual(@as(usize, 1), state.stagedFormCount());
    try std.testing.expectEqual(@as(usize, 0), state.changedFormCount());
    try std.testing.expectEqual(
        ManagedFormStatus.active,
        state.managedFormStatus(index).?,
    );
    try std.testing.expectEqual(FormActivityFilter.active, state.form_activity_filter);
    try std.testing.expectEqual(FormCapabilityFilter.all, state.form_capability_filter);
}

test "new profile cannot manage or save the prior profile Forms Set" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-07-29", 2026);
    state.tin.set("123-456-789-000");
    state.rdo.set("040");
    state.display_name.set("Existing Taxpayer");
    state.registered_address.set("Quezon City");
    state.effective_from.set("2026-01-01");
    try std.testing.expect(state.save());

    const existing_id = state.selectedProfileDomainId().?;
    _ = state.beginManageForms();
    state.clearAllStagedForms();
    try std.testing.expect(state.saveManagedForms());

    state.startNew();
    try std.testing.expectEqualStrings(
        "Needs configuration - 0 of 51 active",
        state.forms_set.text(),
    );
    try std.testing.expect(!state.beginManageForms());
    try std.testing.expect(!state.saveManagedForms());

    var persisted = (try store.getFormSet(
        allocator,
        existing_id.asSlice(),
        2026,
    )).?;
    defer persisted.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), persisted.items.len);
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
    try std.testing.expect(state.save());
    const profile_id = state.selectedProfileDomainId().?;
    const first_id = state.selectedRevisionContext().?.revision_id;

    state.display_name.set("Maria Santos Updated");
    state.effective_from.set("2026-07-01");
    state.setSourceKind(.imported);
    state.source_reference.set("COR import batch 7");
    try std.testing.expect(state.save());
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

fn workspaceFixture(
    state: *State,
    allocator: std.mem.Allocator,
    store: *persistence.Store,
) !void {
    try state.attach(allocator, store, "2026-01-01", 2026);
    state.tin.set("123-456-789-000");
    state.rdo.set("040");
    state.display_name.set("Workspace Taxpayer");
    state.registered_address.set("Quezon City");
    // Registered well before the years these tests set up, so historical years
    // resolve real facts instead of hitting the retroactive-record guard.
    state.effective_from.set("2020-01-01");
    try std.testing.expect(state.save());
}

fn catalogIndexOf(code: []const u8) usize {
    for (&catalog.forms, 0..) |*form, index| {
        if (std.mem.eql(u8, form.code, code)) return index;
    }
    unreachable;
}

test "configured year opens for editing and never offers a create workspace" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    const profile_id = state.selectedProfileId().?;
    try store.createFormSet(profile_id, 2026, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});
    try state.refreshFormSetSummaries();

    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(!state.year_workspace.isDraft());
    try std.testing.expect(!state.form_set_create_mode);
    try std.testing.expectEqual(@as(usize, 1), state.activeFormCount());
    // Editing an existing year takes the update path: the insert-only create
    // path is unreachable, so a save can never collide with itself.
    try std.testing.expect(state.saveYearWorkspace());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expectEqual(@as(usize, 1), state.activeFormCount());

    // Even a stale summary cache cannot reclassify a configured year, because
    // the workspace resolves membership from the store on every open.
    state.form_set_summary_count = 0;
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expectEqual(@as(usize, 1), state.activeFormCount());
}

test "a duplicate created elsewhere becomes a recoverable conflict" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    const profile_id = state.selectedProfileId().?;
    const index_2551q = catalogIndexOf("2551Q");
    const index_1701q = catalogIndexOf("1701Q");

    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expectEqual(YearWorkspaceMode.draft_choice, state.year_workspace);
    try std.testing.expect(state.chooseDraftEmpty());
    state.toggleStagedForm(index_2551q);
    try std.testing.expect(state.stagedFormSelected(index_2551q));

    // Another window configures the same year first.
    try store.createFormSet(profile_id, 2026, &.{.{
        .form_code = "1701Q",
        .form_revision = "2018-01-ENCS",
    }});

    try std.testing.expect(!state.saveYearWorkspace());
    try std.testing.expectEqual(YearWorkspaceMode.conflict, state.year_workspace);
    // The staged work survives the collision.
    try std.testing.expect(state.stagedFormSelected(index_2551q));

    try std.testing.expect(state.reviewConflictingYear());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    // The saved setup is the new baseline; the user's pick reads as pending.
    try std.testing.expect(state.persistedFormSelected(index_1701q));
    try std.testing.expectEqual(
        ManagedFormStatus.will_activate,
        state.managedFormStatus(index_2551q).?,
    );
    try std.testing.expectEqual(
        ManagedFormStatus.will_deactivate,
        state.managedFormStatus(index_1701q).?,
    );
    try std.testing.expect(state.saveYearWorkspace());
    try std.testing.expect(state.persistedFormSelected(index_2551q));
    try std.testing.expect(!state.persistedFormSelected(index_1701q));
}

test "discarding a conflicting draft adopts the setup saved elsewhere" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    const profile_id = state.selectedProfileId().?;
    const index_2551q = catalogIndexOf("2551Q");
    const index_1701q = catalogIndexOf("1701Q");

    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    state.toggleStagedForm(index_2551q);
    try store.createFormSet(profile_id, 2026, &.{.{
        .form_code = "1701Q",
        .form_revision = "2018-01-ENCS",
    }});
    try std.testing.expect(!state.saveYearWorkspace());

    try std.testing.expect(state.discardConflictingDraft());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(state.persistedFormSelected(index_1701q));
    try std.testing.expect(!state.stagedFormSelected(index_2551q));
    try std.testing.expect(!state.workspaceDirty());
}

test "a missing year seeded from another year saves without touching the source" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    const profile_id = state.selectedProfileId().?;
    const index_2551q = catalogIndexOf("2551Q");
    const index_1701q = catalogIndexOf("1701Q");
    try store.createFormSet(profile_id, 2026, &.{
        .{ .form_code = "2551Q", .form_revision = "2018-01-ENCS" },
        .{ .form_code = "1701Q", .form_revision = "2018-01-ENCS" },
    });
    try state.refreshFormSetSummaries();

    try std.testing.expect(state.openYearWorkspace(2025));
    try std.testing.expectEqual(YearWorkspaceMode.draft_choice, state.year_workspace);
    try std.testing.expectEqual(@as(i32, 2026), state.recommendedSeedYear().?);

    try std.testing.expect(state.chooseDraftSeed(2026));
    try std.testing.expectEqual(YearWorkspaceMode.draft_seeded, state.year_workspace);
    try std.testing.expectEqual(@as(i32, 2026), state.draftSourceYear().?);
    try std.testing.expectEqual(@as(usize, 2), state.stagedFormCount());

    state.toggleStagedForm(index_1701q);
    try std.testing.expectEqual(@as(usize, 1), state.stagedFormCount());
    try std.testing.expect(state.saveYearWorkspace());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);

    var saved_2025 = (try store.getFormSet(allocator, profile_id, 2025)).?;
    defer saved_2025.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), saved_2025.items.len);
    try std.testing.expectEqualStrings("2551Q", saved_2025.items[0].form_code);

    // The source year is read-only during a copy.
    var saved_2026 = (try store.getFormSet(allocator, profile_id, 2026)).?;
    defer saved_2026.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), saved_2026.items.len);
    _ = index_2551q;
}

test "an explicitly empty year stays configured and never widens" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);

    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    try std.testing.expectEqual(YearWorkspaceMode.draft_empty, state.year_workspace);
    try std.testing.expect(state.saveYearWorkspace());

    try std.testing.expectEqual(
        persistence.FormSetState.active_empty,
        state.form_set_state,
    );
    try std.testing.expect(state.forms_set_configured);
    try std.testing.expect(!state.formAvailable(2026, "2551Q"));
    // Reopening keeps it configured rather than reverting to a setup draft.
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
}

test "the year workspace rejects future and out-of-range years" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);

    try std.testing.expect(!state.openYearWorkspace(2027));
    try std.testing.expect(state.noticeFailure());
    try std.testing.expect(!state.openYearWorkspace(minimum_setup_year - 1));
    try std.testing.expectEqual(@as(i32, 2026), state.maximumSetupYear());
}

test "switching year with unsaved work prompts instead of discarding" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    const index_2551q = catalogIndexOf("2551Q");

    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    try std.testing.expect(!state.workspaceDirty());
    state.toggleStagedForm(index_2551q);
    try std.testing.expect(state.workspaceDirty());

    // The switch is withheld, not applied, and nothing is written.
    try std.testing.expect(!state.openYearWorkspace(2025));
    try std.testing.expectEqual(@as(i32, 2025), state.pendingYearSwitch().?);
    try std.testing.expectEqual(@as(i32, 2026), state.workspaceYear().?);
    try std.testing.expect(state.stagedFormSelected(index_2551q));

    state.cancelPendingYearSwitch();
    try std.testing.expect(state.pendingYearSwitch() == null);
    try std.testing.expectEqual(@as(i32, 2026), state.workspaceYear().?);

    try std.testing.expect(!state.openYearWorkspace(2025));
    try std.testing.expect(state.confirmPendingYearSwitch());
    try std.testing.expectEqual(@as(i32, 2025), state.workspaceYear().?);
    try std.testing.expectEqual(YearWorkspaceMode.draft_choice, state.year_workspace);
    try std.testing.expect(!state.stagedFormSelected(index_2551q));
}

test "an unreadable year fails closed instead of offering setup" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    try store.createFormSet(state.selectedProfileId().?, 2026, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expectEqual(@as(usize, 1), state.activeFormCount());

    store.close();
    try std.testing.expect(!state.openYearWorkspace(2025));
    try std.testing.expectEqual(YearWorkspaceMode.open_failed, state.year_workspace);
    try std.testing.expect(!state.year_workspace.isDraft());
    try std.testing.expect(!state.form_set_create_mode);
    // No selection from the previous year survives an unreadable one.
    try std.testing.expectEqual(@as(usize, 0), state.stagedFormCount());
    try std.testing.expectEqual(@as(usize, 0), state.activeFormCount());
}

test "saving unchanged taxpayer details records no new revision" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    try std.testing.expectEqual(@as(u32, 1), state.selectedRevisionSequence().?);
    try std.testing.expect(!state.factsDirty());

    // Reopening and saving is a visit, not a change.
    try std.testing.expect(state.save());
    try std.testing.expectEqual(@as(u32, 1), state.selectedRevisionSequence().?);
    try std.testing.expectEqualStrings("No changes to save.", state.noticeText());

    // A real edit still appends exactly one revision.
    state.registered_address.set("Makati City");
    try std.testing.expect(state.factsDirty());
    try std.testing.expect(state.save());
    try std.testing.expectEqual(@as(u32, 2), state.selectedRevisionSequence().?);
    try std.testing.expect(!state.factsDirty());
}

test "unsaved taxpayer details block a profile switch instead of vanishing" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    state.display_name.set("Edited But Unsaved");
    try std.testing.expect(state.factsDirty());

    try std.testing.expectError(
        error.UnsavedProfileChanges,
        state.selectSlot(0),
    );
    try std.testing.expectEqualStrings(
        "Edited But Unsaved",
        state.display_name.text(),
    );

    state.startNew();
    try std.testing.expect(state.noticeFailure());
    try std.testing.expect(!state.editing_new);
}

test "a year carries details forward without a duplicate record" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);

    state.refreshFactsSummary(2026);
    try std.testing.expect(state.factsSummaryAvailable());
    try std.testing.expect(!state.factsMissingForYear());
    try std.testing.expect(!state.factsChangedDuringYear());
    // One record from 2020 still covers 2026, so 2025 and 2026 share it.
    try std.testing.expect(state.factsSameAsPriorYear());
    try std.testing.expectEqualStrings("2020-01-01", state.factsEffectiveFrom());

    // A mid-year change is reported as such, and earlier years are untouched.
    state.registered_address.set("Makati City");
    state.effective_from.set("2026-07-01");
    try std.testing.expect(state.save());

    state.refreshFactsSummary(2026);
    try std.testing.expect(state.factsChangedDuringYear());
    try std.testing.expect(!state.factsSameAsPriorYear());

    state.refreshFactsSummary(2025);
    try std.testing.expect(!state.factsChangedDuringYear());
    try std.testing.expect(state.factsSameAsPriorYear());
    try std.testing.expectEqualStrings("2020-01-01", state.factsEffectiveFrom());
}

test "a historical year with no details asks for a record instead of inventing one" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-01-01", 2026);
    state.tin.set("123-456-789-000");
    state.rdo.set("040");
    state.display_name.set("Recently Registered Taxpayer");
    state.registered_address.set("Quezon City");
    state.effective_from.set("2026-01-01");
    try std.testing.expect(state.save());

    try std.testing.expect(state.openYearWorkspace(2023));
    try std.testing.expectEqual(YearWorkspaceMode.draft_choice, state.year_workspace);
    try std.testing.expect(state.factsMissingForYear());

    try std.testing.expect(state.chooseDraftEmpty());
    // Today's details are never copied backward to make the save succeed.
    try std.testing.expect(!state.saveYearWorkspace());
    try std.testing.expect(state.noticeFailure());
    try std.testing.expect(
        (try store.getFormSet(allocator, state.selectedProfileId().?, 2023)) == null,
    );

    // Recording what was true then unblocks the year.
    state.effective_from.set("2023-01-01");
    state.registered_address.set("Cebu City");
    try std.testing.expect(state.save());
    try std.testing.expect(state.openYearWorkspace(2023));
    try std.testing.expect(!state.factsMissingForYear());
    try std.testing.expect(state.chooseDraftEmpty());
    try std.testing.expect(state.saveYearWorkspace());
}

test "a taxpayer registered mid-year is not treated as missing details" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-08-04", 2026);
    state.tin.set("123-456-789-000");
    state.rdo.set("040");
    state.display_name.set("Mid Year Registrant");
    state.registered_address.set("Quezon City");
    state.effective_from.set("2026-08-04");
    try std.testing.expect(state.save());

    // No details on 1 January is normal for a taxpayer registered in August.
    state.refreshFactsSummary(2026);
    try std.testing.expect(!state.factsMissingForYear());
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    try std.testing.expect(state.saveYearWorkspace());
}

test "a branch reuses safe details and requires its own registration facts" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    state.phone.set("+639171234567");
    state.email.set("head@example.ph");
    state.business_line.set("Retail");
    try std.testing.expect(state.save());
    // Copy: the selection buffer is reused when the branch becomes selected.
    var head_office_storage: [64]u8 = undefined;
    const selected_head_office = state.selectedProfileId().?;
    @memcpy(
        head_office_storage[0..selected_head_office.len],
        selected_head_office,
    );
    const head_office_id = head_office_storage[0..selected_head_office.len];

    try std.testing.expect(state.canAddBranch());
    try std.testing.expect(state.beginAddBranch());
    try std.testing.expect(state.branchMode());
    try std.testing.expect(state.editing_new);

    // The taxpayer's own details carry over.
    try std.testing.expectEqualStrings("123-456-789", state.tin.text());
    try std.testing.expectEqualStrings("Workspace Taxpayer", state.display_name.text());
    try std.testing.expectEqualStrings("+639171234567", state.phone.text());
    try std.testing.expectEqualStrings("head@example.ph", state.email.text());
    // Everything branch-specific starts blank so it must be reviewed.
    try std.testing.expectEqualStrings("", state.rdo.text());
    try std.testing.expectEqualStrings("", state.registered_address.text());
    try std.testing.expectEqualStrings("", state.business_line.text());
    try std.testing.expectEqualStrings("", state.tax_type.text());

    // Saving without a branch code would create a duplicate registration.
    state.rdo.set("043");
    state.registered_address.set("Makati City");
    try std.testing.expect(!state.save());
    try std.testing.expect(state.noticeFailure());

    state.tin.set("123-456-789-002");
    try std.testing.expect(state.save());
    try std.testing.expect(!state.branchMode());

    const branch_id = state.selectedProfileId().?;
    try std.testing.expect(!std.mem.eql(u8, head_office_id, branch_id));
    // The branch keeps its own forms: nothing was copied from the head office.
    try std.testing.expect(
        (try store.getFormSet(allocator, branch_id, 2026)) == null,
    );
}

test "a branch cannot become a different kind of taxpayer" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    try std.testing.expect(state.beginAddBranch());
    try std.testing.expectEqual(state.subject_kind, state.branch_source_kind);

    state.rdo.set("043");
    state.registered_address.set("Makati City");
    state.tin.set("123-456-789-002");
    state.setSubjectKind(.corporation);
    try std.testing.expect(!state.save());
    try std.testing.expectEqualStrings(
        "A branch is the same taxpayer. A different kind of taxpayer needs its own profile.",
        state.noticeText(),
    );
    try std.testing.expectEqual(@as(usize, 1), state.rows().len);
}

test "a branch cannot change the taxpayer it belongs to" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    try std.testing.expect(state.beginAddBranch());

    state.rdo.set("043");
    state.registered_address.set("Makati City");
    state.tin.set("999-888-777-002");
    try std.testing.expect(!state.save());
    try std.testing.expectEqualStrings(
        "A branch keeps the same nine-digit TIN as its head office. Change only the branch code.",
        state.noticeText(),
    );
}

test "one canonical TIN cannot be registered twice" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);

    state.startNew();
    state.tin.set("123-456-789-000");
    state.rdo.set("040");
    state.display_name.set("Same TIN Again");
    state.registered_address.set("Quezon City");
    state.effective_from.set("2026-01-01");
    try std.testing.expect(!state.save());
    // The refusal names who holds the TIN, so the user has somewhere to go.
    try std.testing.expectEqualStrings(
        "That TIN already belongs to Workspace Taxpayer. Open it instead of adding it again.",
        state.noticeText(),
    );
    try std.testing.expectEqual(@as(usize, 1), state.rows().len);
}

test "an archived taxpayer still owns its TIN" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    const owner_id = state.selectedProfileId().?;
    var owner_storage: [64]u8 = undefined;
    @memcpy(owner_storage[0..owner_id.len], owner_id);
    const archived_id = owner_storage[0..owner_id.len];

    // Archiving is not deletion: a TIN is issued once and never reassigned.
    try store.setProfileStatus(archived_id, .archived);
    try state.attach(allocator, &store, "2026-01-01", 2026);
    try std.testing.expectEqual(@as(usize, 0), state.rows().len);

    state.startNew();
    state.tin.set("123-456-789-000");
    state.rdo.set("040");
    state.display_name.set("Different Taxpayer Same TIN");
    state.registered_address.set("Quezon City");
    state.effective_from.set("2020-01-01");
    try std.testing.expect(!state.save());
    try std.testing.expectEqualStrings(
        "That TIN belongs to Workspace Taxpayer, which is archived. Restore it instead of adding it again.",
        state.noticeText(),
    );
    try std.testing.expectEqual(@as(usize, 0), state.rows().len);

    // The store knows the owner independently of the loaded rows.
    var owner = (try store.findProfileWithCanonicalTin(
        allocator,
        "123456789000",
        null,
    )).?;
    defer owner.deinit(allocator);
    try std.testing.expectEqual(persistence.ProfileStatus.archived, owner.status);
    try std.testing.expectEqualStrings("Workspace Taxpayer", owner.display_name.?);
}

test "profile rows expose head office and branch identity" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    try std.testing.expect(state.beginAddBranch());
    state.rdo.set("043");
    state.registered_address.set("Makati City");
    state.tin.set("123-456-789-002");
    try std.testing.expect(state.save());

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var head_office: ?*const ProfileRow = null;
    var branch: ?*const ProfileRow = null;
    for (state.rows()) |*row| {
        if (row.isBranch()) branch = row else head_office = row;
    }
    try std.testing.expect(head_office != null);
    try std.testing.expect(branch != null);
    try std.testing.expectEqualStrings("123456789", head_office.?.tinRoot());
    try std.testing.expectEqualStrings("123456789", branch.?.tinRoot());
    try std.testing.expectEqualStrings("002", branch.?.branchCode());
    try std.testing.expectEqualStrings("Head office", head_office.?.branchLabel(arena));
    try std.testing.expectEqualStrings("Branch 002", branch.?.branchLabel(arena));
}

test "calendar form selection refresh fails closed" {
    var state = State{};
    var selected = [_]bool{ true, true };

    try std.testing.expect(!state.refreshCalendarFormSelection(
        &.{ "0605", "2551Q" },
        &selected,
    ));
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, false },
        &selected,
    );
    try std.testing.expect(state.noticeVisible());
    try std.testing.expectEqualStrings(
        "Calendar form choices could not be loaded. Deadlines and export are unavailable until the profile is reopened.",
        state.noticeText(),
    );
}
