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
const applicability = @import("applicability.zig");
const citizenship_reference = @import("citizenship_reference.zig");
const rdo_reference = @import("rdo_reference.zig");
const registration_evidence_store = @import("registration_evidence_store.zig");
const catalog = @import("../forms/generated/catalog.zig");
const multi_select = @import("../components/multi_select.zig");

const canvas = native_sdk.canvas;

/// Display bound for loaded taxpayer rows, not a reachability ceiling: the
/// sidebar search queries the store, so a taxpayer past this bound is still
/// found by typing. At ~300 bytes a row this is ~300 KB of fixed buffers.
pub const max_profiles: usize = 1024;
pub const max_registered_forms: usize = catalog.registry_count;
pub const max_form_set_summaries: usize = 128;
/// Recorded mid-year changes shown per year. The store holds every row; past
/// this bound the list says it is truncated rather than dropping silently.
pub const max_form_set_intervals: usize = 12;

/// Whether the year workspace's primary save applies to the whole year (the
/// default, today's behavior) or records a change effective from a date.
pub const FormsApplyScope = enum { whole_year, from_date };
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
    ManualSourceHasReference,
    SourceReferenceRequired,
    ProfileCapacityExceeded,
    NotAttached,
    NoSelectedProfile,
    FormsRequireSavedProfile,
    UnsavedFormSetChanges,
    UnsavedProfileChanges,
    NoFactsEffectiveForYear,
    CorFileUnreadable,
    CorFileEmpty,
    CorFileTooLarge,
    CorFileUnsupported,
    DuplicateTaxpayerIdentifier,
    NoProfileChanges,
    BranchTinRootChanged,
    BranchCodeRequired,
    BranchLegalPersonChanged,
    InvalidRdoSelection,
    NewProfileTinMustHaveFourteenDigits,
    InvalidProfileField,
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

/// The taxpayer details a COR states, which the user transcribes and reviews
/// before any of them become authoritative.
///
/// Deliberately a short list: a COR carries registration facts, and filing
/// amounts, schedules, and payments are not among them no matter what else
/// the document shows.
pub const CorCandidateField = enum {
    rdo_code,
    taxpayer_name,
    registered_address,
    zip_code,
    tax_type,

    pub fn reusable(self: CorCandidateField) fields.ReusableField {
        return switch (self) {
            .rdo_code => .rdo_code,
            .taxpayer_name => .taxpayer_name,
            .registered_address => .registered_address,
            .zip_code => .zip_code,
            .tax_type => .tax_type,
        };
    }
};

pub const cor_candidate_count = std.meta.tags(CorCandidateField).len;

/// Whether the COR the user is transcribing belongs to this taxpayer.
pub const CorTinMatch = enum {
    /// No TIN entered yet, so nothing can be applied.
    unknown,
    /// The COR states this taxpayer's canonical TIN.
    matches,
    /// The COR belongs to a different taxpayer. Nothing may be applied.
    mismatched,
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

/// The editor normally presents taxpayer facts as an annual profile period,
/// but exact dates remain necessary for a genuine mid-year change or a legacy
/// revision that already has one. Persisted revisions always retain dates.
pub const EffectiveDateMode = enum {
    annual_years,
    exact_dates,
};

/// Field-level feedback is intentionally owned beside the validation rules so
/// save eligibility, focus-loss messages, and errors cannot drift apart.
pub const ProfileField = enum {
    rdo_code,
    taxpayer_type,
    tax_classification,
    taxpayer_name,
    registered_address,
    zip_code,
    contact_number,
    email_address,
    accounting_period_basis,
    fiscal_year_end_month,
    birth_date,
    citizenship,
    effective_start,
    effective_end,
};

const profile_field_count = std.meta.tags(ProfileField).len;

/// The Tax Profile screen has an explicit lifecycle. A persisted profile is
/// read-only until the user chooses Edit; creating remains a distinct editor
/// because its Cancel action exits creation instead of reverting a revision.
pub const ProfileMode = enum {
    creating,
    viewing,
    editing,
};

/// Startup has two deliberately different needs. Focused workspaces retain
/// the historical convenience of selecting the first available taxpayer,
/// while the global shell must only index sidebar rows until the user makes
/// an explicit taxpayer choice.
const AttachmentSelectionPolicy = enum {
    implicit_first,
    explicit_only,
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

/// Exact in-memory editor values captured before an edit starts. Cancel uses
/// this snapshot instead of querying persistence again, so reverting cannot
/// adopt a concurrent revision or fail halfway through because storage became
/// unavailable.
const ProfileEditorSnapshot = struct {
    valid: bool = false,
    loaded_shape_supported: bool = true,
    subject_kind: model.SubjectKind = .individual,
    subject_kind_selected: bool = false,
    natural_person_classification: model.NaturalPersonClassification =
        .classification_unknown,
    accounting_period_basis: ?model.AccountingPeriodBasis = null,
    fiscal_year_end_month: canvas.TextBuffer(2) = .{},
    eopt_tier: ?model.EoptTier = null,
    primary_line_of_business: canvas.TextBuffer(160) = .{},
    consolidation_review_state: model.ConsolidationReviewState = .confirmed,
    source_kind: SourceKind = .manual_entry,
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
    effective_date_mode: EffectiveDateMode = .annual_years,
    effective_start_year: canvas.TextBuffer(4) = .{},
    effective_end_year: canvas.TextBuffer(4) = .{},
    effective_from: canvas.TextBuffer(10) = .{},
    effective_until: canvas.TextBuffer(10) = .{},
    source_reference: canvas.TextBuffer(160) = .{},
    tax_year: canvas.TextBuffer(4) = .{},
    change_intent: ChangeIntent = .record_change,
    loaded_effective_from: FixedText(10) = .{},
    input_was_truncated: bool = false,
};

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

/// A bounded, process-only copy of an in-progress Tax Profile editor.  It is
/// deliberately owned by `main.zig` rather than the persistence layer: a
/// process restart starts with the default value and cannot recover it.
pub const SessionDraft = struct {
    valid: bool = false,
    has_selection: bool = false,
    selected_id: StableIdText = .{},
    selected_revision_id: StableIdText = .{},
    selected_revision_sequence: ?u32 = null,
    selected_display: ProfileRow = .{ .slot = 0, .subject_kind = .individual },
    has_selected_display: bool = false,
    profile_mode: ProfileMode = .viewing,
    editing_new: bool = false,
    branch_mode: bool = false,
    branch_source_root: FixedText(9) = .{},
    branch_source_name: NameText = .{},
    branch_source_kind: model.SubjectKind = .individual,
    current: ProfileEditorSnapshot = .{},
    baseline: ProfileEditorSnapshot = .{},
    baseline_fingerprint: u64 = 0,
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
    /// The sidebar search text. When set, the loaded rows are the store-wide
    /// matches rather than the first `max_profiles` taxpayers, which is what
    /// makes everyone findable regardless of the display bound.
    sidebar_query: FixedText(96) = .{},
    /// Display details of the selected taxpayer, kept current at selection
    /// time. The loaded rows are a view that a search narrows; the header
    /// must keep telling the truth about who is selected even while that view
    /// does not contain them.
    selected_display: ProfileRow = .{ .slot = 0, .subject_kind = .individual },
    has_selected_display: bool = false,
    selected_id: StableIdText = .{},
    has_selection: bool = false,
    attachment_selection_policy: AttachmentSelectionPolicy = .implicit_first,
    selected_revision_id: StableIdText = .{},
    selected_revision_sequence: ?u32 = null,
    /// The Registration Unit's district as the loaded revision records it,
    /// kept apart from the `rdo` editor buffer of the same value. Only an
    /// appended revision changes where a taxpayer is registered, so callers
    /// that scope policy by district must not read a half-typed field.
    registered_rdo: ?fields.RdoCode = null,
    editing_new: bool = true,
    profile_mode: ProfileMode = .creating,
    loaded_shape_supported: bool = true,
    subject_kind: model.SubjectKind = .individual,
    /// A new profile must affirm its legal taxpayer type rather than silently
    /// inheriting the implementation's internal Individual default.
    subject_kind_selected: bool = false,
    natural_person_classification: model.NaturalPersonClassification =
        .classification_unknown,
    accounting_period_basis: ?model.AccountingPeriodBasis = null,
    fiscal_year_end_month: canvas.TextBuffer(2) = .{},
    eopt_tier: ?model.EoptTier = null,
    primary_line_of_business: canvas.TextBuffer(160) = .{},
    consolidation_review_state: model.ConsolidationReviewState = .confirmed,
    source_kind: SourceKind = .manual_entry,
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
    effective_date_mode: EffectiveDateMode = .annual_years,
    effective_start_year: canvas.TextBuffer(4) = .{},
    effective_end_year: canvas.TextBuffer(4) = .{},
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
    /// Whether the primary save applies to the whole year or records a
    /// change taking effect on a date. From-a-date routes the save to the
    /// interval tables and leaves the year's base set untouched.
    forms_apply_scope: FormsApplyScope = .whole_year,
    change_effective_from: canvas.TextBuffer(10) = .{},
    form_set_intervals: [max_form_set_intervals]persistence.FormSetIntervalSummary = undefined,
    form_set_interval_count: usize = 0,
    form_set_intervals_truncated: bool = false,
    /// The source year a draft copied its forms from. Presentation only: no
    /// facts are duplicated and the source year is never opened for writing.
    draft_source_year: ?i32 = null,
    /// A year the user selected while the workspace still held unsaved work.
    /// Nothing is discarded until they answer the prompt.
    pending_year_switch: ?i32 = null,
    form_activity_filter: FormActivityFilter = .active,
    form_capability_filter: FormCapabilityFilter = .all,
    input_was_truncated: bool = false,
    profile_field_touched: [profile_field_count]bool =
        [_]bool{false} ** profile_field_count,

    default_effective_from: FixedText(10) = .{},
    default_tax_year: i32 = 2026,

    /// Fingerprint of the editor values as they were loaded. Saving compares
    /// against it so reopening a taxpayer and pressing save cannot append a
    /// revision that records no actual change.
    baseline_fingerprint: u64 = 0,
    editor_baseline: ProfileEditorSnapshot = .{},
    /// Which taxpayer facts apply to the workspace year, summarized without
    /// revision vocabulary.
    facts_summary_year: i32 = 0,
    facts_summary_available: bool = false,
    facts_effective_from: FixedText(10) = .{},
    facts_missing_for_year: bool = false,
    facts_changed_during_year: bool = false,
    facts_same_as_prior_year: bool = false,
    cor_state: CorEvidenceState = .none,
    cor_file_name: FixedText(160) = .{},
    cor_attached_at: i64 = 0,
    cor_digest: FixedText(64) = .{},
    cor_document_id: FixedText(64) = .{},
    /// Transcription of the COR under review. Nothing here is authoritative:
    /// it becomes a taxpayer record only through an explicit apply, and only
    /// for the rows the user accepted.
    cor_review_open: bool = false,
    cor_review_tin: canvas.TextBuffer(32) = .{},
    cor_review_values: [cor_candidate_count]canvas.TextBuffer(255) =
        [_]canvas.TextBuffer(255){.{}} ** cor_candidate_count,
    cor_review_accepted: [cor_candidate_count]bool = .{false} ** cor_candidate_count,
    cor_review_apply_forms: bool = false,
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
        return self.attachWithSelectionPolicy(
            allocator,
            store,
            effective_from,
            tax_year,
            .implicit_first,
        );
    }

    /// Attaches the profile store for the Global Dashboard shell. This is an
    /// index-only operation: it populates the sidebar but must never create,
    /// select, hydrate, or notify about a taxpayer before the user chooses
    /// one.
    pub fn attachForGlobalDashboard(
        self: *State,
        allocator: std.mem.Allocator,
        store: *persistence.Store,
        effective_from: []const u8,
        tax_year: i32,
    ) !void {
        return self.attachWithSelectionPolicy(
            allocator,
            store,
            effective_from,
            tax_year,
            .explicit_only,
        );
    }

    fn attachWithSelectionPolicy(
        self: *State,
        allocator: std.mem.Allocator,
        store: *persistence.Store,
        effective_from: []const u8,
        tax_year: i32,
        selection_policy: AttachmentSelectionPolicy,
    ) !void {
        _ = try model.Date.parseIso(effective_from);
        if (tax_year < 1 or tax_year > 9999) return error.InvalidTaxYear;
        self.allocator = allocator;
        self.store = store;
        try self.default_effective_from.set(effective_from);
        self.default_tax_year = tax_year;
        self.attachment_selection_policy = selection_policy;
        if (selection_policy == .explicit_only) {
            self.clearSelection();
            self.dismissNotice();
        }
        try self.reloadRows();
        if (selection_policy == .implicit_first) {
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

    pub fn profileMode(self: *const State) ProfileMode {
        return self.profile_mode;
    }

    pub fn profileCreating(self: *const State) bool {
        return self.profile_mode == .creating;
    }

    pub fn profileViewing(self: *const State) bool {
        return self.profile_mode == .viewing;
    }

    pub fn profileEditing(self: *const State) bool {
        return self.profile_mode == .editing;
    }

    pub fn profileInputsDisabled(self: *const State) bool {
        return self.profile_mode == .viewing or !self.loaded_shape_supported;
    }

    pub fn saveDisabled(self: *const State) bool {
        if (self.store == null or !self.loaded_shape_supported) return true;
        return switch (self.profile_mode) {
            .viewing => true,
            .editing => !self.profileDirty() or !self.profileDraftValid(),
            .creating => !self.profileDraftValid(),
        };
    }

    /// Fast, allocation-free syntax gate for the Native Save affordance.
    /// Domain construction and SQLite constraints remain authoritative at
    /// commit time; this prevents offering Save for inputs already known to
    /// be invalid.
    pub fn profileDraftValid(self: *const State) bool {
        if (!self.profileTinDraftValid()) return false;
        if (rdo_reference.findByCode(trimmed(self.rdo.text())) == null) {
            return false;
        }
        if (self.subject_kind == .individual and
            self.natural_person_classification == .classification_unknown)
        {
            return false;
        }
        if (optionalTrimmed(self.primary_line_of_business.text())) |raw| {
            _ = fields.LineOfBusiness.parse(raw) catch return false;
        }
        inline for (std.meta.tags(ProfileField)) |field| {
            if (self.profileFieldValidationMessage(field) != null) {
                return false;
            }
        }
        return true;
    }

    pub fn revealProfileFieldValidation(self: *State, field: ProfileField) void {
        self.profile_field_touched[@intFromEnum(field)] = true;
    }

    pub fn revealAllProfileFieldValidation(self: *State) void {
        self.profile_field_touched = [_]bool{true} ** profile_field_count;
    }

    pub fn profileFieldErrorVisible(
        self: *const State,
        field: ProfileField,
    ) bool {
        return !self.profileInputsDisabled() and
            self.profile_field_touched[@intFromEnum(field)] and
            self.profileFieldValidationMessage(field) != null;
    }

    pub fn profileFieldValidationMessage(
        self: *const State,
        field: ProfileField,
    ) ?[]const u8 {
        return switch (field) {
            .rdo_code => blk: {
                const value = trimmed(self.rdo.text());
                if (value.len == 0) {
                    break :blk "RDO is required.";
                }
                if (rdo_reference.findByCode(value) == null) {
                    break :blk "Choose an RDO from the filtered results.";
                }
                break :blk null;
            },
            .taxpayer_type => if (!self.subject_kind_selected)
                "Taxpayer Type is required."
            else
                null,
            .tax_classification => if (self.naturalPersonFieldsVisible() and
                self.natural_person_classification == .classification_unknown)
                "Tax Classification is required for an individual taxpayer."
            else
                null,
            .taxpayer_name => blk: {
                const value = trimmed(self.display_name.text());
                if (value.len == 0) {
                    break :blk "Taxpayer or registered name is required.";
                }
                _ = fields.TaxpayerName.parse(value) catch
                    break :blk "Enter a valid taxpayer or registered name.";
                break :blk null;
            },
            .registered_address => blk: {
                const value = trimmed(self.registered_address.text());
                if (value.len == 0) {
                    break :blk "Registered address is required.";
                }
                _ = fields.RegisteredAddress.parse(value) catch
                    break :blk "Enter a valid registered address.";
                break :blk null;
            },
            .zip_code => blk: {
                const value = trimmed(self.zip_code.text());
                if (value.len == 0) break :blk "ZIP code is required.";
                _ = fields.ZipCode.parse(value) catch
                    break :blk "Enter a four-digit Philippine ZIP code.";
                break :blk null;
            },
            .contact_number => blk: {
                const value = trimmed(self.phone.text());
                if (value.len == 0) break :blk "Contact number is required.";
                _ = fields.ContactNumber.parse(value) catch
                    break :blk "Use +63, 63, or 0 followed by a valid Philippine mobile or landline number.";
                break :blk null;
            },
            .email_address => blk: {
                const value = trimmed(self.email.text());
                if (value.len == 0) {
                    break :blk "Registered email address is required.";
                }
                _ = fields.EmailAddress.parse(value) catch
                    break :blk "Enter a valid email address, such as name@example.ph.";
                break :blk null;
            },
            .accounting_period_basis => if (self.accounting_period_basis == null)
                "Choose Calendar or Fiscal accounting period."
            else
                null,
            .fiscal_year_end_month => blk: {
                if (self.accounting_period_basis != .fiscal) break :blk null;
                const value = optionalTrimmed(
                    self.fiscal_year_end_month.text(),
                ) orelse break :blk "Fiscal year-end month is required.";
                const month = std.fmt.parseInt(u8, value, 10) catch
                    break :blk "Enter a fiscal year-end month from 1 to 12.";
                if (month < 1 or month > 12) {
                    break :blk "Enter a fiscal year-end month from 1 to 12.";
                }
                break :blk null;
            },
            .birth_date => blk: {
                if (!self.naturalPersonFieldsVisible()) break :blk null;
                if (trimmed(self.birth_date.text()).len == 0) {
                    break :blk "Birth date is required for an individual taxpayer.";
                }
                _ = self.birthDateForEditor() catch
                    break :blk "Enter a real birth date as M/D/YY, MM/DD/YYYY, or YYYY-MM-DD.";
                break :blk null;
            },
            .citizenship => blk: {
                if (!self.naturalPersonFieldsVisible()) break :blk null;
                const value = optionalTrimmed(self.citizenship.text()) orelse
                    break :blk "Citizenship is required for an individual taxpayer.";
                if (citizenship_reference.findByValue(value) == null) {
                    break :blk "Choose citizenship from the filtered results.";
                }
                break :blk null;
            },
            .effective_start => blk: {
                switch (self.effective_date_mode) {
                    .annual_years => {
                        if (optionalTrimmed(self.effective_start_year.text()) == null) {
                            break :blk "When this takes effect is required.";
                        }
                        _ = parseTaxYear(self.effective_start_year.text()) catch
                            break :blk "Enter a four-digit year from 0001 to 9999.";
                    },
                    .exact_dates => {
                        _ = model.Date.parseIso(
                            trimmed(self.effective_from.text()),
                        ) catch break :blk "Enter the exact start date as YYYY-MM-DD.";
                    },
                }
                break :blk null;
            },
            .effective_end => blk: {
                if (self.effective_date_mode == .annual_years) {
                    const until = optionalTrimmed(self.effective_end_year.text()) orelse
                        break :blk null;
                    const from_year = parseTaxYear(
                        self.effective_start_year.text(),
                    ) catch break :blk null;
                    const until_year = parseTaxYear(until) catch
                        break :blk "Enter a four-digit year from 0001 to 9999.";
                    if (until_year < from_year) {
                        break :blk "Applies until cannot be earlier than when this takes effect.";
                    }
                    break :blk null;
                }
                const until = optionalTrimmed(self.effective_until.text()) orelse
                    break :blk null;
                const from = model.Date.parseIso(
                    trimmed(self.effective_from.text()),
                ) catch break :blk null;
                const end = model.Date.parseIso(until) catch
                    break :blk "Enter the exact end date as YYYY-MM-DD.";
                if (end.isBefore(from)) {
                    break :blk "Applies until cannot be earlier than when this takes effect.";
                }
                break :blk null;
            },
        };
    }

    pub fn annualEffectiveYears(self: *const State) bool {
        return self.effective_date_mode == .annual_years;
    }

    pub fn exactEffectiveDates(self: *const State) bool {
        return self.effective_date_mode == .exact_dates;
    }

    pub fn useAnnualEffectiveYears(self: *State) void {
        // A persisted mid-year interval is historical fact, not a presentation
        // choice. Deriving a pair of years and then syncing them back would
        // silently round (for example) 2026-07-01 to 2026-01-01.
        if (self.effective_date_mode == .exact_dates and
            !self.effectiveDatesFitAnnualYears())
        {
            self.setNotice(
                .neutral,
                "This profile has exact dates. Keep them to preserve its historical period.",
            );
            return;
        }
        self.syncAnnualYearsFromDates();
        self.effective_date_mode = .annual_years;
        self.syncDatesFromAnnualYears();
    }

    pub fn useExactEffectiveDates(self: *State) void {
        // Do not expose a previously derived ISO interval through exact-date
        // mode while the annual-year controls are partial or invalid. The
        // annual input is the source of truth until it forms a real period.
        if (self.effective_date_mode == .annual_years) {
            _ = self.effectivePeriodForEditor() catch {
                self.revealProfileFieldValidation(.effective_start);
                self.revealProfileFieldValidation(.effective_end);
                return;
            };
        }
        self.syncDatesFromAnnualYears();
        self.effective_date_mode = .exact_dates;
    }

    pub fn applyEffectiveStartYearInput(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        self.effective_start_year.apply(edit);
        self.captureInputTruncation();
        self.syncDatesFromAnnualYears();
    }

    pub fn applyEffectiveEndYearInput(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        self.effective_end_year.apply(edit);
        self.captureInputTruncation();
        self.syncDatesFromAnnualYears();
    }

    pub fn selectEffectiveStartYear(self: *State, year: i32) void {
        setTaxYearBuffer(&self.effective_start_year, year);
        self.syncDatesFromAnnualYears();
    }

    pub fn selectEffectiveEndYear(self: *State, year: ?i32) void {
        if (year) |value| {
            setTaxYearBuffer(&self.effective_end_year, value);
        } else {
            clearEditorBuffer(&self.effective_end_year);
        }
        self.syncDatesFromAnnualYears();
    }

    /// Normalizes only a complete, real entry. Partial text remains visible
    /// while someone types, allowing M/D/YY and MM/DD/YYYY naturally.
    pub fn normalizeBirthDateInput(self: *State) void {
        const birth_date = self.birthDateForEditor() catch return;
        var buffer: [10]u8 = undefined;
        setEditorBuffer(&self.birth_date, birth_date.writeIso(&buffer));
    }

    fn birthDateForEditor(self: *const State) !model.Date {
        const current = try model.Date.parseIso(self.default_effective_from.text());
        const birth_date = try fields.parseBirthDate(
            trimmed(self.birth_date.text()),
            current.year,
        );
        if (birth_date.isAfter(current)) return error.InvalidBirthDate;
        return birth_date;
    }

    fn effectivePeriodForEditor(self: *const State) !model.EffectivePeriod {
        return switch (self.effective_date_mode) {
            .annual_years => blk: {
                const start_year = try parseTaxYear(
                    self.effective_start_year.text(),
                );
                const from = try model.Date.init(@intCast(start_year), 1, 1);
                const until = if (optionalTrimmed(
                    self.effective_end_year.text(),
                )) |raw| blk_until: {
                    const end_year = try parseTaxYear(raw);
                    break :blk_until try model.Date.init(
                        @intCast(end_year),
                        12,
                        31,
                    );
                } else null;
                break :blk try model.EffectivePeriod.init(from, until);
            },
            .exact_dates => try model.EffectivePeriod.init(
                try model.Date.parseIso(trimmed(self.effective_from.text())),
                if (optionalTrimmed(self.effective_until.text())) |raw|
                    try model.Date.parseIso(raw)
                else
                    null,
            ),
        };
    }

    fn syncDatesFromAnnualYears(self: *State) void {
        if (self.effective_date_mode != .annual_years) return;
        const start_year = parseTaxYear(self.effective_start_year.text()) catch
            return;
        const from = model.Date.init(@intCast(start_year), 1, 1) catch return;
        var from_buffer: [10]u8 = undefined;
        setEditorBuffer(&self.effective_from, from.writeIso(&from_buffer));

        const end_text = optionalTrimmed(self.effective_end_year.text()) orelse {
            clearEditorBuffer(&self.effective_until);
            return;
        };
        const end_year = parseTaxYear(end_text) catch return;
        const until = model.Date.init(@intCast(end_year), 12, 31) catch return;
        var until_buffer: [10]u8 = undefined;
        setEditorBuffer(&self.effective_until, until.writeIso(&until_buffer));
    }

    fn syncAnnualYearsFromDates(self: *State) void {
        const from = model.Date.parseIso(trimmed(self.effective_from.text())) catch
            return;
        setTaxYearBuffer(&self.effective_start_year, from.year);
        if (optionalTrimmed(self.effective_until.text())) |raw| {
            const until = model.Date.parseIso(raw) catch return;
            setTaxYearBuffer(&self.effective_end_year, until.year);
        } else {
            clearEditorBuffer(&self.effective_end_year);
        }
    }

    fn setDefaultAnnualEffectiveYear(self: *State) void {
        const date = model.Date.parseIso(self.default_effective_from.text()) catch
            return;
        self.effective_date_mode = .annual_years;
        setTaxYearBuffer(&self.effective_start_year, date.year);
        clearEditorBuffer(&self.effective_end_year);
        self.syncDatesFromAnnualYears();
    }

    fn effectiveDatesFitAnnualYears(self: *const State) bool {
        const from = model.Date.parseIso(trimmed(self.effective_from.text())) catch
            return false;
        if (from.month != 1 or from.day != 1) return false;
        const until_text = optionalTrimmed(self.effective_until.text()) orelse
            return true;
        const until = model.Date.parseIso(until_text) catch return false;
        return until.month == 12 and until.day == 31;
    }

    fn setEffectivePresentationFromStoredDates(self: *State) void {
        if (self.effectiveDatesFitAnnualYears()) {
            self.effective_date_mode = .annual_years;
            self.syncAnnualYearsFromDates();
        } else {
            self.effective_date_mode = .exact_dates;
            clearEditorBuffer(&self.effective_start_year);
            clearEditorBuffer(&self.effective_end_year);
        }
    }

    fn validateProfileFieldsForSave(self: *State) !void {
        inline for (std.meta.tags(ProfileField)) |field| {
            if (self.profileFieldValidationMessage(field)) |message| {
                self.revealAllProfileFieldValidation();
                self.setErrorDetail(message);
                return error.InvalidProfileField;
            }
        }
    }

    fn tinDiffersFromEditorBaseline(self: *const State) bool {
        if (!self.editor_baseline.valid) return true;
        const current = fields.Tin.parse(trimmed(self.tin.text())) catch
            return true;
        const baseline = fields.Tin.parse(
            trimmed(self.editor_baseline.tin.text()),
        ) catch return true;
        return !std.mem.eql(u8, current.asDigits(), baseline.asDigits());
    }

    /// Existing 9/12/13-digit legacy identities remain readable unchanged.
    /// Creating or correcting an identity must produce the complete 3-3-3-5
    /// value; partial edits are never eligible for Save.
    pub fn profileTinDraftValid(self: *const State) bool {
        const parsed = fields.Tin.parse(trimmed(self.tin.text())) catch
            return false;
        if ((self.editing_new or self.tinDiffersFromEditorBaseline()) and
            parsed.asDigits().len != 14) return false;
        return true;
    }

    pub fn cancelDisabled(self: *const State) bool {
        return switch (self.profile_mode) {
            .viewing => true,
            .editing => !self.profileDirty(),
            .creating => false,
        };
    }

    /// Persistent selected state for subject-kind controls. The view binds
    /// this predicate to `selected`; hover is never used as selection state.
    pub fn subjectKindSelected(
        self: *const State,
        subject_kind: model.SubjectKind,
    ) bool {
        return self.subject_kind_selected and self.subject_kind == subject_kind;
    }

    /// The editor stores a concrete enum for every rendering path, but a new
    /// profile must still have an explicit taxpayer-type choice before it is
    /// eligible to save.
    pub fn subjectKindSelectionCommitted(self: *const State) bool {
        return self.subject_kind_selected;
    }

    pub fn clearSubjectKindSelection(self: *State) void {
        if (self.branch_mode) return;
        self.subject_kind_selected = false;
    }

    pub fn subjectKind(self: *const State) model.SubjectKind {
        return self.subject_kind;
    }

    pub fn setNaturalPersonClassification(
        self: *State,
        classification: model.NaturalPersonClassification,
    ) void {
        self.natural_person_classification = classification;
    }

    pub fn naturalPersonClassification(
        self: *const State,
    ) model.NaturalPersonClassification {
        return self.natural_person_classification;
    }

    pub fn classificationSelected(
        self: *const State,
        classification: model.NaturalPersonClassification,
    ) bool {
        return self.natural_person_classification == classification;
    }

    pub fn classificationLabel(self: *const State) []const u8 {
        return classificationDisplayLabel(
            self.natural_person_classification,
        );
    }

    pub fn setAccountingPeriodBasis(
        self: *State,
        basis: ?model.AccountingPeriodBasis,
    ) void {
        self.accounting_period_basis = basis;
        if (basis != .fiscal) clearEditorBuffer(&self.fiscal_year_end_month);
    }

    pub fn accountingPeriodBasisSelected(
        self: *const State,
        basis: model.AccountingPeriodBasis,
    ) bool {
        return self.accounting_period_basis == basis;
    }

    pub fn accountingPeriodBasisLabel(self: *const State) []const u8 {
        return if (self.accounting_period_basis) |basis|
            basis.label()
        else
            "Not recorded";
    }

    pub fn fiscalYearEndMonthValue(self: *const State) ?u8 {
        const raw = optionalTrimmed(self.fiscal_year_end_month.text()) orelse
            return null;
        const month = std.fmt.parseInt(u8, raw, 10) catch return null;
        return if (month >= 1 and month <= 12) month else null;
    }

    pub fn setEoptTier(self: *State, tier: ?model.EoptTier) void {
        self.eopt_tier = tier;
    }

    pub fn eoptTierSelected(
        self: *const State,
        tier: model.EoptTier,
    ) bool {
        return self.eopt_tier == tier;
    }

    pub fn eoptTierLabel(self: *const State) []const u8 {
        return if (self.eopt_tier) |tier| tier.label() else "Not recorded";
    }

    pub fn primaryLineOfBusinessText(self: *const State) []const u8 {
        return trimmed(self.primary_line_of_business.text());
    }

    pub fn consolidationReviewRequired(self: *const State) bool {
        return self.consolidation_review_state == .requires_review;
    }

    /// An ambiguous legacy registration migration must be acknowledged by a
    /// person after the consolidated fields have been corrected. Merely
    /// opening or re-saving the profile never clears the review marker.
    pub fn confirmConsolidatedProfileFacts(self: *State) void {
        self.consolidation_review_state = .confirmed;
    }

    fn applicabilityContext(self: *const State) applicability.Context {
        return .{
            .subject_kind = self.subject_kind,
            .natural_person_classification = self.natural_person_classification,
            .has_trade_name = optionalTrimmed(self.trade_name.text()) != null,
        };
    }

    pub fn naturalPersonFieldsVisible(self: *const State) bool {
        return self.subject_kind_selected and applicability.fieldGroupVisible(
            self.applicabilityContext(),
            .natural_person_details,
        );
    }

    pub fn tradeNameVisible(self: *const State) bool {
        return self.subject_kind_selected and applicability.fieldGroupVisible(
            self.applicabilityContext(),
            .trade_name,
        );
    }

    pub fn businessFieldsVisible(self: *const State) bool {
        // Compatibility alias for generated markup while the old activity
        // editor bindings are removed. Business visibility now belongs to
        // the single Base Tax Profile Line of Business field.
        return self.lineOfBusinessVisible();
    }

    pub fn lineOfBusinessVisible(self: *const State) bool {
        return self.subject_kind_selected and applicability.fieldGroupVisible(
            self.applicabilityContext(),
            .line_of_business,
        );
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
            trimmed(self.fiscal_year_end_month.text()),
            trimmed(self.primary_line_of_business.text()),
            trimmed(self.effective_start_year.text()),
            trimmed(self.effective_end_year.text()),
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
            @intFromBool(self.subject_kind_selected),
            @intFromEnum(self.natural_person_classification),
            @intFromEnum(self.source_kind),
            @intFromEnum(self.effective_date_mode),
            if (self.accounting_period_basis) |basis|
                @as(u8, @intFromEnum(basis)) + 1
            else
                0,
            if (self.eopt_tier) |tier|
                @as(u8, @intFromEnum(tier)) + 1
            else
                0,
            @intFromEnum(self.consolidation_review_state),
        });
        return hasher.final();
    }

    fn captureBaseline(self: *State) void {
        self.baseline_fingerprint = self.editorFingerprint();
    }

    fn captureEditorSnapshot(self: *State) void {
        self.editor_baseline = .{
            .valid = true,
            .loaded_shape_supported = self.loaded_shape_supported,
            .subject_kind = self.subject_kind,
            .subject_kind_selected = self.subject_kind_selected,
            .natural_person_classification = self.natural_person_classification,
            .accounting_period_basis = self.accounting_period_basis,
            .fiscal_year_end_month = self.fiscal_year_end_month,
            .eopt_tier = self.eopt_tier,
            .primary_line_of_business = self.primary_line_of_business,
            .consolidation_review_state = self.consolidation_review_state,
            .source_kind = self.source_kind,
            .tin = self.tin,
            .rdo = self.rdo,
            .display_name = self.display_name,
            .trade_name = self.trade_name,
            .registered_address = self.registered_address,
            .zip_code = self.zip_code,
            .phone = self.phone,
            .email = self.email,
            .birth_date = self.birth_date,
            .citizenship = self.citizenship,
            .foreign_tax_number = self.foreign_tax_number,
            .effective_date_mode = self.effective_date_mode,
            .effective_start_year = self.effective_start_year,
            .effective_end_year = self.effective_end_year,
            .effective_from = self.effective_from,
            .effective_until = self.effective_until,
            .source_reference = self.source_reference,
            .tax_year = self.tax_year,
            .change_intent = self.change_intent,
            .loaded_effective_from = self.loaded_effective_from,
            .input_was_truncated = self.input_was_truncated,
        };
    }

    fn restoreEditorSnapshot(self: *State) bool {
        if (!self.editor_baseline.valid) return false;
        const baseline = self.editor_baseline;
        self.loaded_shape_supported = baseline.loaded_shape_supported;
        self.subject_kind = baseline.subject_kind;
        self.subject_kind_selected = baseline.subject_kind_selected;
        self.natural_person_classification =
            baseline.natural_person_classification;
        self.accounting_period_basis = baseline.accounting_period_basis;
        self.fiscal_year_end_month = baseline.fiscal_year_end_month;
        self.eopt_tier = baseline.eopt_tier;
        self.primary_line_of_business = baseline.primary_line_of_business;
        self.consolidation_review_state = baseline.consolidation_review_state;
        self.source_kind = baseline.source_kind;
        self.tin = baseline.tin;
        self.rdo = baseline.rdo;
        self.display_name = baseline.display_name;
        self.trade_name = baseline.trade_name;
        self.registered_address = baseline.registered_address;
        self.zip_code = baseline.zip_code;
        self.phone = baseline.phone;
        self.email = baseline.email;
        self.birth_date = baseline.birth_date;
        self.citizenship = baseline.citizenship;
        self.foreign_tax_number = baseline.foreign_tax_number;
        self.effective_date_mode = baseline.effective_date_mode;
        self.effective_start_year = baseline.effective_start_year;
        self.effective_end_year = baseline.effective_end_year;
        self.effective_from = baseline.effective_from;
        self.effective_until = baseline.effective_until;
        self.source_reference = baseline.source_reference;
        self.tax_year = baseline.tax_year;
        self.change_intent = baseline.change_intent;
        self.loaded_effective_from = baseline.loaded_effective_from;
        self.input_was_truncated = baseline.input_was_truncated;
        self.captureBaseline();
        self.profile_field_touched = [_]bool{false} ** profile_field_count;
        return true;
    }

    /// True when the editor differs from the values captured for its current
    /// mode. Creation captures its initialized blank/default draft too, so
    /// navigation can distinguish an untouched create screen from typed data.
    pub fn factsDirty(self: *const State) bool {
        if (!self.editor_baseline.valid) return false;
        return self.editorFingerprint() != self.baseline_fingerprint;
    }

    pub fn profileDirty(self: *const State) bool {
        return self.factsDirty();
    }

    pub fn hasSessionDraft(_: *const State, draft: *const SessionDraft) bool {
        return draft.valid;
    }

    pub fn canSaveSessionDraft(
        self: *const State,
        draft: *const SessionDraft,
    ) bool {
        if (self.profile_mode == .viewing or !self.profileDirty()) return false;
        // There is one process-only parking slot. Never silently replace it:
        // Resume or explicitly discard the parked draft first.
        return !draft.valid;
    }

    /// Copies the active editor into the in-memory draft supplied by the app
    /// model. This intentionally performs no persistence operation.
    pub fn saveSessionDraft(
        self: *const State,
        draft: *SessionDraft,
    ) bool {
        if (!self.canSaveSessionDraft(draft)) return false;

        draft.* = .{
            .valid = true,
            .has_selection = self.has_selection,
            .selected_id = self.selected_id,
            .selected_revision_id = self.selected_revision_id,
            .selected_revision_sequence = self.selected_revision_sequence,
            .selected_display = self.selected_display,
            .has_selected_display = self.has_selected_display,
            .profile_mode = self.profile_mode,
            .editing_new = self.editing_new,
            .branch_mode = self.branch_mode,
            .branch_source_root = self.branch_source_root,
            .branch_source_name = self.branch_source_name,
            .branch_source_kind = self.branch_source_kind,
            .current = .{
                .valid = true,
                .loaded_shape_supported = self.loaded_shape_supported,
                .subject_kind = self.subject_kind,
                .subject_kind_selected = self.subject_kind_selected,
                .natural_person_classification = self.natural_person_classification,
                .accounting_period_basis = self.accounting_period_basis,
                .fiscal_year_end_month = self.fiscal_year_end_month,
                .eopt_tier = self.eopt_tier,
                .primary_line_of_business = self.primary_line_of_business,
                .consolidation_review_state = self.consolidation_review_state,
                .source_kind = self.source_kind,
                .tin = self.tin,
                .rdo = self.rdo,
                .display_name = self.display_name,
                .trade_name = self.trade_name,
                .registered_address = self.registered_address,
                .zip_code = self.zip_code,
                .phone = self.phone,
                .email = self.email,
                .birth_date = self.birth_date,
                .citizenship = self.citizenship,
                .foreign_tax_number = self.foreign_tax_number,
                .effective_date_mode = self.effective_date_mode,
                .effective_start_year = self.effective_start_year,
                .effective_end_year = self.effective_end_year,
                .effective_from = self.effective_from,
                .effective_until = self.effective_until,
                .source_reference = self.source_reference,
                .tax_year = self.tax_year,
                .change_intent = self.change_intent,
                .loaded_effective_from = self.loaded_effective_from,
                .input_was_truncated = self.input_was_truncated,
            },
            .baseline = self.editor_baseline,
            .baseline_fingerprint = self.baseline_fingerprint,
        };
        return true;
    }

    pub fn discardSessionDraft(_: *State, draft: *SessionDraft) void {
        draft.* = .{};
    }

    /// Restores a parked editor after selecting its source profile again. The
    /// database is read only to refresh surrounding profile UI; the captured
    /// revision context is restored afterwards so a concurrent change still
    /// receives the normal optimistic-concurrency protection on Save.
    pub fn resumeSessionDraft(
        self: *State,
        draft: *const SessionDraft,
    ) bool {
        if (!draft.valid or !draft.current.valid or !draft.baseline.valid) return false;

        const creates_profile = draft.editing_new or draft.branch_mode;
        if (!creates_profile) {
            // The app must first select this taxpayer through its normal
            // context-switch lifecycle (form and exact-filer guards, calendar
            // refreshes, etc.). Do not mutate selection here on a failed
            // database load and leave the UI half-switched.
            if (!self.has_selection or
                !std.mem.eql(u8, self.selected_id.text(), draft.selected_id.text()))
            {
                return false;
            }
            self.loadSelectedRevision(true) catch |err| {
                self.setError(err);
                return false;
            };
            self.selected_revision_id = draft.selected_revision_id;
            self.selected_revision_sequence = draft.selected_revision_sequence;
        } else {
            // Creation and branch drafts are prepared by startNew() or
            // beginAddBranch() before this overlay. A creation editor may
            // deliberately retain its source selection for Cancel to restore.
            if (!self.editing_new or self.branch_mode != draft.branch_mode) return false;
            if (draft.has_selection) {
                if (!self.has_selection or
                    !std.mem.eql(u8, self.selected_id.text(), draft.selected_id.text()))
                {
                    return false;
                }
            } else if (self.has_selection) {
                return false;
            }
        }

        const current = draft.current;
        self.loaded_shape_supported = current.loaded_shape_supported;
        self.subject_kind = current.subject_kind;
        self.subject_kind_selected = current.subject_kind_selected;
        self.natural_person_classification = current.natural_person_classification;
        self.accounting_period_basis = current.accounting_period_basis;
        self.fiscal_year_end_month = current.fiscal_year_end_month;
        self.eopt_tier = current.eopt_tier;
        self.primary_line_of_business = current.primary_line_of_business;
        self.consolidation_review_state = current.consolidation_review_state;
        self.source_kind = current.source_kind;
        self.tin = current.tin;
        self.rdo = current.rdo;
        self.display_name = current.display_name;
        self.trade_name = current.trade_name;
        self.registered_address = current.registered_address;
        self.zip_code = current.zip_code;
        self.phone = current.phone;
        self.email = current.email;
        self.birth_date = current.birth_date;
        self.citizenship = current.citizenship;
        self.foreign_tax_number = current.foreign_tax_number;
        self.effective_date_mode = current.effective_date_mode;
        self.effective_start_year = current.effective_start_year;
        self.effective_end_year = current.effective_end_year;
        self.effective_from = current.effective_from;
        self.effective_until = current.effective_until;
        self.source_reference = current.source_reference;
        self.tax_year = current.tax_year;
        self.change_intent = current.change_intent;
        self.loaded_effective_from = current.loaded_effective_from;
        self.input_was_truncated = current.input_was_truncated;
        self.editor_baseline = draft.baseline;
        self.baseline_fingerprint = draft.baseline_fingerprint;
        self.profile_mode = draft.profile_mode;
        self.editing_new = draft.editing_new;
        self.branch_mode = draft.branch_mode;
        self.branch_source_root = draft.branch_source_root;
        self.branch_source_name = draft.branch_source_name;
        self.branch_source_kind = draft.branch_source_kind;
        self.profile_field_touched = [_]bool{false} ** profile_field_count;
        return true;
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
            .registered_name => switch (self.subject_kind) {
                .individual, .sole_proprietor => optionalTrimmed(self.trade_name.text()) orelse
                    trimmed(self.display_name.text()),
                .corporation,
                .partnership,
                .cooperative,
                .estate,
                .trust,
                .other_legal_entity,
                => trimmed(self.display_name.text()),
            },
            .registered_address => trimmed(self.registered_address.text()),
            .zip_code => trimmed(self.zip_code.text()),
            .contact_number => trimmed(self.phone.text()),
            .email_address => trimmed(self.email.text()),
            .accounting_period_basis => if (self.accounting_period_basis) |basis|
                basis.label()
            else
                "",
            .date_of_birth => trimmed(self.birth_date.text()),
            .citizenship => trimmed(self.citizenship.text()),
            .foreign_tax_number => trimmed(self.foreign_tax_number.text()),
            .line_of_business => trimmed(
                self.primary_line_of_business.text(),
            ),
            .eopt_tier => if (self.eopt_tier) |tier| tier.label() else "",
            // These values belong to form policy, a Tax Form Profile, or the
            // filing transaction. They are not Base Tax Profile fields.
            .atc,
            .tax_type,
            .government_withholding_agent,
            .special_rate_basis,
            => "",
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
        self.setDefaultAnnualEffectiveYear();
    }

    /// Restates the period that is already on screen, because what was
    /// recorded for it was wrong. Filings already prepared keep their values.
    pub fn beginFixMistake(self: *State) void {
        if (self.editing_new or !self.has_selection) return;
        self.change_intent = .fix_mistake;
        setEditorBuffer(&self.effective_from, self.loaded_effective_from.text());
        self.setEffectivePresentationFromStoredDates();
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

    /// Where the selected taxpayer is registered according to the revision on
    /// disk — the answer a restart would give. Empty when nobody is selected,
    /// or while a draft registration has never been saved.
    pub fn registeredRdoCode(self: *const State) []const u8 {
        if (!self.has_selection) return "";
        if (self.registered_rdo) |*code| return code.asSlice();
        return "";
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

    /// The row when loaded, else the captured display: a search narrowing the
    /// sidebar past the selected taxpayer must not make the header claim
    /// nobody is selected.
    fn selectedDisplay(self: *const State) ?*const ProfileRow {
        if (self.selectedRow()) |row| return row;
        if (self.has_selection and self.has_selected_display) {
            return &self.selected_display;
        }
        return null;
    }

    pub fn selectedName(self: *const State) []const u8 {
        const row = self.selectedDisplay() orelse return "No tax profile selected";
        return row.name.text();
    }

    pub fn selectedTin(self: *const State) []const u8 {
        const row = self.selectedDisplay() orelse return "—";
        return row.tin.text();
    }

    pub fn selectedInitials(self: *const State) []const u8 {
        const row = self.selectedDisplay() orelse return "—";
        return row.initials.text();
    }

    pub fn selectedKindLabel(self: *const State) []const u8 {
        const row = self.selectedDisplay() orelse return "None";
        return subjectKindLabel(row.subject_kind);
    }

    /// Whether the file a COR reference points at is still the one attached.
    pub const CorEvidenceState = enum {
        /// No document has been attached to this taxpayer.
        none,
        /// The file is where it was, byte for byte.
        on_file,
        /// The file is no longer readable at the path it was attached from.
        moved,
        /// A file is there, but it is not the document that was attached.
        changed,
    };

    pub fn corEvidenceState(self: *const State) CorEvidenceState {
        return self.cor_state;
    }

    pub fn corFileName(self: *const State) []const u8 {
        return self.cor_file_name.text();
    }

    pub fn corAttachedAt(self: *const State) i64 {
        return self.cor_attached_at;
    }

    /// Reloads the COR reference for the selected taxpayer and re-checks the
    /// file behind it, so the card reports what is true now rather than what
    /// was true when it was attached.
    pub fn refreshCorEvidence(self: *State) void {
        self.cor_state = .none;
        self.cor_file_name.clear();
        self.cor_digest.clear();
        self.cor_document_id.clear();
        self.cor_attached_at = 0;
        self.cor_review_open = false;
        self.refreshCorEvidenceFallible() catch return;
    }

    fn refreshCorEvidenceFallible(self: *State) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;
        var document = (try store.getLatestCorDocument(
            allocator,
            profile_id,
        )) orelse return;
        defer document.deinit(allocator);

        try self.cor_file_name.set(document.file_name);
        try self.cor_digest.set(document.sha256);
        try self.cor_document_id.set(document.id);
        self.cor_attached_at = document.attached_at_unix_seconds;
        self.cor_state = verifyCorFile(document.file_path, document.sha256);
    }

    /// Attaches the COR the user chose. The document is referenced, never
    /// copied: the profile database already holds more sensitive facts than a
    /// path and a digest, so a reference needs no key custody to be honest,
    /// while a copy would.
    pub fn attachCorDocument(self: *State, path: []const u8) bool {
        self.attachCorDocumentFallible(path) catch |err| {
            self.setError(err);
            return false;
        };
        self.setNotice(.success, "COR attached.");
        return true;
    }

    fn attachCorDocumentFallible(self: *State, path: []const u8) !void {
        const store = self.store orelse return error.NotAttached;
        if (self.editing_new) return error.FormsRequireSavedProfile;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;

        const fingerprint = try fingerprintEvidenceFile(path);
        const generated = try store.generateOpaqueId();
        try store.attachCorDocument(.{
            .id = &generated,
            .profile_id = profile_id,
            .file_path = path,
            .file_name = evidenceFileName(path),
            .sha256 = &fingerprint.sha256,
            .byte_size = fingerprint.byte_size,
        });
        self.refreshCorEvidence();
    }

    pub fn corReviewOpen(self: *const State) bool {
        return self.cor_review_open;
    }

    /// Opens the review. The user reads the COR and types what it says; there
    /// is no extraction engine behind this, and none is implied.
    pub fn beginCorReview(self: *State) bool {
        if (self.editing_new or !self.has_selection) {
            self.setError(error.FormsRequireSavedProfile);
            return false;
        }
        if (self.cor_state == .none) return false;
        self.cor_review_open = true;
        self.cor_review_tin.clear();
        for (&self.cor_review_values) |*value| value.clear();
        self.cor_review_accepted = .{false} ** cor_candidate_count;
        self.cor_review_apply_forms = false;
        return true;
    }

    pub fn cancelCorReview(self: *State) void {
        self.cor_review_open = false;
    }

    pub fn corReviewValue(self: *const State, field_index: usize) []const u8 {
        if (field_index >= cor_candidate_count) return "";
        return self.cor_review_values[field_index].text();
    }

    pub fn corReviewAccepted(self: *const State, field_index: usize) bool {
        if (field_index >= cor_candidate_count) return false;
        return self.cor_review_accepted[field_index];
    }

    /// A row can only be accepted once it states something, and accepting a
    /// value equal to the one on file is allowed but changes nothing.
    pub fn toggleCorReviewAccepted(self: *State, field_index: usize) void {
        if (field_index >= cor_candidate_count) return;
        if (trimmed(self.cor_review_values[field_index].text()).len == 0) {
            self.cor_review_accepted[field_index] = false;
            return;
        }
        self.cor_review_accepted[field_index] =
            !self.cor_review_accepted[field_index];
    }

    pub fn corReviewApplyForms(self: *const State) bool {
        return self.cor_review_apply_forms;
    }

    pub fn toggleCorReviewApplyForms(self: *State) void {
        self.cor_review_apply_forms = !self.cor_review_apply_forms;
    }

    pub fn corReviewAcceptedCount(self: *const State) usize {
        var count: usize = 0;
        for (self.cor_review_accepted, 0..) |accepted, index| {
            if (accepted and
                trimmed(self.cor_review_values[index].text()).len != 0) count += 1;
        }
        return count;
    }

    /// Whether the transcribed TIN is this taxpayer's.
    ///
    /// A COR naming a different taxpayer must never touch the selected one:
    /// applying it would merge two identities through a form the user thought
    /// was about details.
    pub fn corReviewTinMatch(self: *const State) CorTinMatch {
        const typed = trimmed(self.cor_review_tin.text());
        if (typed.len == 0) return .unknown;
        const stated = fields.Tin.parse(typed) catch return .mismatched;
        const current = fields.Tin.parse(
            trimmed(self.tin.text()),
        ) catch return .mismatched;
        return if (stated.eql(&current)) .matches else .mismatched;
    }

    pub fn corReviewApplyBlocked(self: *const State) bool {
        if (self.corReviewTinMatch() != .matches) return true;
        return self.corReviewAcceptedCount() == 0 and
            !self.cor_review_apply_forms;
    }

    /// Applies exactly what the user accepted.
    ///
    /// Accepted details go through the ordinary save path, so identity limits,
    /// validation, and the no-op check all still apply — which is why
    /// accepting only forms appends no taxpayer record at all, and why
    /// accepting a detail the taxpayer already has appends nothing either.
    pub fn applyCorReview(self: *State) bool {
        if (self.corReviewApplyBlocked()) return false;
        const accepted = self.corReviewAcceptedCount();
        const wants_forms = self.cor_review_apply_forms;

        if (accepted == 0) {
            // Forms alone are already one transaction, and nothing on this
            // path may create a profile revision.
            if (wants_forms and !self.saveYearWorkspace()) return false;
            self.cor_review_open = false;
            self.setNotice(.success, "The forms you accepted were saved.");
            return true;
        }

        for (self.cor_review_accepted, 0..) |is_accepted, index| {
            if (!is_accepted) continue;
            const value = trimmed(self.cor_review_values[index].text());
            if (value.len == 0) continue;
            self.applyCorCandidate(
                std.meta.tags(CorCandidateField)[index],
                value,
            );
        }
        self.setSourceKind(.imported);
        var reference: [160]u8 = undefined;
        setEditorBuffer(&self.source_reference, std.fmt.bufPrint(
            &reference,
            "COR {s} sha256:{s}",
            .{
                self.cor_file_name.text(),
                self.cor_digest.text()[0..@min(8, self.cor_digest.len)],
            },
        ) catch "COR");

        if (!wants_forms) {
            if (!self.saveWithCor(.{
                .document_id = self.cor_document_id.text(),
                .include_forms = false,
            })) return false;
        } else if (!self.applyCorReviewWithForms(self.cor_document_id.text())) {
            return false;
        }
        self.cor_review_open = false;
        return true;
    }

    /// The combined details-and-forms half of a COR decision: one store
    /// transaction, wrapped in the same guards, conflict handling, and
    /// afterwards-state as the standalone forms save.
    fn applyCorReviewWithForms(self: *State, document_id: []const u8) bool {
        if (self.year_workspace == .draft_choice or
            self.year_workspace == .open_failed or
            self.year_workspace == .conflict)
        {
            return false;
        }
        const creating_year = self.year_workspace.isDraft();
        const notice_year = self.workspaceYear();
        // Accepted values identical to what is already recorded from this
        // document: nothing to append, the forms half is the whole decision.
        if (!self.profileDirty()) {
            // A repeated COR decision can already match both the taxpayer and
            // the persisted Forms Set. There is then no management save to
            // perform, but the reviewed no-op remains a successful decision.
            if (!self.managing_forms) return true;
            return self.saveYearWorkspace();
        }
        _ = self.saveFallible(.{
            .document_id = document_id,
            .include_forms = true,
        }) catch |err| {
            if (err == error.NoProfileChanges) return self.saveYearWorkspace();
            if (creating_year and err == persistence.Error.FormSetAlreadyExists) {
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
        self.managing_forms = false;
        self.form_set_create_mode = false;
        self.resetFormFilters();
        self.setSaveNotice(notice_year);
        return true;
    }

    fn applyCorCandidate(
        self: *State,
        field_key: CorCandidateField,
        value: []const u8,
    ) void {
        switch (field_key) {
            .rdo_code => setEditorBuffer(&self.rdo, value),
            .taxpayer_name => setEditorBuffer(&self.display_name, value),
            .registered_address => setEditorBuffer(&self.registered_address, value),
            .zip_code => setEditorBuffer(&self.zip_code, value),
            // A COR tax-type transcription is retained only as evidence. It
            // is no longer copied into the Base Tax Profile or readiness.
            .tax_type => {},
        }
    }

    pub fn selectedTaxTypeLabel(self: *const State) []const u8 {
        _ = self;
        return "Tax type not recorded";
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
        if (self.profileDirty()) return error.UnsavedProfileChanges;
        // Invalidate before changing identity or performing any fallible load.
        // A failed profile switch must not expose the prior profile's forms.
        self.invalidateCalendarFormSetCache(self.default_tax_year);
        try self.selected_id.set(self.profiles[slot].stable_id.text());
        self.has_selection = true;
        self.markActiveRow();
        self.captureSelectedDisplay();
        try self.loadSelectedRevision(true);
        self.profile_mode = .viewing;
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
        if (self.profileDirty()) {
            self.setError(error.UnsavedProfileChanges);
            return;
        }
        self.editing_new = true;
        self.profile_mode = .creating;
        self.loaded_shape_supported = true;
        self.clearEditor();
        self.setDefaultAnnualEffectiveYear();
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
        self.captureBaseline();
        // A new taxpayer has no saved profile to return to. When creation was
        // opened from an existing selection, keep that selected revision's
        // snapshot so Cancel can restore it in place.
        if (!self.has_selection) self.captureEditorSnapshot();
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
    /// The taxpayer's name, personal facts, and portable contact details are
    /// reused because they describe the same taxpayer. The branch segment,
    /// RDO, address, and every registration fact are deliberately left blank:
    /// they are the facts most likely to differ, and a silent copy would assert
    /// something unverified.
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
        if (self.profileDirty()) {
            self.setError(error.UnsavedProfileChanges);
            return false;
        }
        const row = self.selectedRow() orelse return false;
        const source_root = row.tin_root.text();
        const source_name = row.name.text();
        // `loadSelectedRevision` has already normalized a legacy sole-
        // proprietor row into its canonical legal subject and classification.
        const source_kind = self.subject_kind;
        const source_classification = self.natural_person_classification;

        const reused_name = self.display_name.text();
        const reused_trade_name = self.trade_name.text();
        const reused_phone = self.phone.text();
        const reused_email = self.email.text();
        const reused_birth_date = self.birth_date.text();
        const reused_citizenship = self.citizenship.text();
        var name_buffer: [160]u8 = undefined;
        var trade_buffer: [160]u8 = undefined;
        var phone_buffer: [32]u8 = undefined;
        var email_buffer: [254]u8 = undefined;
        var birth_date_buffer: [10]u8 = undefined;
        var citizenship_buffer: [80]u8 = undefined;
        const name = copyInto(&name_buffer, reused_name);
        const trade_name = copyInto(&trade_buffer, reused_trade_name);
        const phone = copyInto(&phone_buffer, reused_phone);
        const email = copyInto(&email_buffer, reused_email);
        const birth_date = copyInto(&birth_date_buffer, reused_birth_date);
        const citizenship = copyInto(&citizenship_buffer, reused_citizenship);

        self.editing_new = true;
        self.profile_mode = .creating;
        self.loaded_shape_supported = true;
        self.clearEditor();
        self.branch_mode = true;
        self.branch_source_root.set(source_root) catch {};
        self.branch_source_name.set(source_name) catch {};
        self.branch_source_kind = source_kind;

        // The branch belongs to the same legal person, so its kind is fixed.
        self.subject_kind = source_kind;
        self.subject_kind_selected = true;
        self.natural_person_classification = source_classification;
        // Prefill the root the way a TIN is normally written, so the user
        // appends a branch code to something they recognize.
        var root_buffer: [11]u8 = undefined;
        setEditorBuffer(&self.tin, std.fmt.bufPrint(
            &root_buffer,
            "{s}-{s}-{s}",
            .{ source_root[0..3], source_root[3..6], source_root[6..9] },
        ) catch source_root);
        setEditorBuffer(&self.display_name, name);
        setEditorBuffer(&self.trade_name, trade_name);
        setEditorBuffer(&self.phone, phone);
        setEditorBuffer(&self.email, email);
        setEditorBuffer(&self.birth_date, birth_date);
        setEditorBuffer(&self.citizenship, citizenship);
        self.setDefaultAnnualEffectiveYear();
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
        self.loadSelectedRevision(true) catch |err| {
            self.setError(err);
            return;
        };
        self.profile_mode = .editing;
    }

    pub fn cancelEdit(self: *State) void {
        switch (self.profile_mode) {
            .viewing => return,
            .editing => {
                if (!self.restoreEditorSnapshot()) {
                    self.loadSelectedRevision(true) catch |err| {
                        self.setError(err);
                        return;
                    };
                }
                self.editing_new = false;
                self.profile_mode = .viewing;
            },
            .creating => {
                if (self.has_selection and self.restoreEditorSnapshot()) {
                    self.editing_new = false;
                    self.profile_mode = .viewing;
                    self.branch_mode = false;
                    self.branch_source_root.clear();
                    self.branch_source_name.clear();
                    return;
                }
                // An initial create screen has no saved view to restore. Keep
                // it in create mode but restore the initialized blank/default
                // draft; page navigation remains the caller's responsibility.
                if (!self.restoreEditorSnapshot()) self.startNew();
                self.editing_new = true;
                self.profile_mode = .creating;
            },
        }
    }

    pub fn setSubjectKind(self: *State, subject_kind: model.SubjectKind) void {
        if (subject_kind == .sole_proprietor) {
            // Compatibility-only UI shortcut. Persisted truth is one natural
            // person with a self-employed classification, never a competing
            // SoleProprietor subject row.
            self.subject_kind = .individual;
            self.natural_person_classification = .self_employed;
        } else {
            self.subject_kind = subject_kind;
        }
        self.subject_kind_selected = true;
        // Visibility is derived from the selected kind. Keep conditional
        // values buffered until Save or Cancel so changing a selector never
        // destroys data merely because a section became hidden.
    }

    pub fn setSourceKind(self: *State, source_kind: SourceKind) void {
        self.source_kind = source_kind;
        if (source_kind == .manual_entry) {
            clearEditorBuffer(&self.source_reference);
        }
    }

    /// What a save carries when it applies a reviewed COR decision: the
    /// durable document key, and whether the accepted forms ride in the same
    /// store transaction.
    const CorApply = struct {
        document_id: []const u8,
        include_forms: bool,
    };

    pub fn save(self: *State) bool {
        return self.saveWithCor(null);
    }

    fn saveWithCor(self: *State, cor: ?CorApply) bool {
        const was_new = self.editing_new;
        // Reopening a taxpayer and saving must not record a change that did
        // not happen: history stays a log of real events, not of visits.
        if (!was_new and !self.profileDirty()) {
            self.setNotice(.neutral, "No changes to save.");
            return true;
        }

        self.saveFallible(cor) catch |err| {
            // Nothing to record is a successful outcome, not a failure: the
            // taxpayer's details already say what the user wants them to say.
            if (err == error.NoProfileChanges) {
                _ = self.restoreEditorSnapshot();
                self.editing_new = false;
                self.profile_mode = .viewing;
                self.has_pending_error_detail = false;
                self.setNotice(.neutral, "No changes to save.");
                return true;
            }
            self.setError(err);
            return false;
        };
        const was_branch = self.branch_mode;
        self.branch_mode = false;
        self.branch_source_root.clear();
        self.branch_source_name.clear();
        self.profile_mode = .viewing;
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

    fn saveFallible(
        self: *State,
        cor: ?CorApply,
    ) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        if (self.input_was_truncated or self.inputsTruncated()) {
            return error.FieldTooLong;
        }
        const year = try parseTaxYear(self.tax_year.text());

        const tin = try fields.Tin.parse(trimmed(self.tin.text()));
        if ((self.editing_new or self.tinDiffersFromEditorBaseline()) and
            tin.asDigits().len != 14)
        {
            return error.NewProfileTinMustHaveFourteenDigits;
        }
        // Let Save reveal the same field-level RDO (and other required-field)
        // feedback as focus loss before parsing the validated identity.
        try self.validateProfileFieldsForSave();

        // Preserve the reference and parser checks at the domain boundary
        // after the UI-level validation has made its feedback visible.
        if (rdo_reference.findByCode(trimmed(self.rdo.text())) == null) {
            return error.InvalidRdoSelection;
        }
        const rdo = try fields.RdoCode.parse(trimmed(self.rdo.text()));

        const address = try fields.RegisteredAddress.parse(
            trimmed(self.registered_address.text()),
        );
        const effective = try self.effectivePeriodForEditor();

        if (cor) |apply| {
            // The forms half of a combined apply carries the same reviewed-
            // retroactive guard as the standalone forms save — checked before
            // commit, because one transaction refuses everything where the
            // old two-step flow would have committed the revision and then
            // refused the forms. The pending revision itself may be what
            // gives the year its facts.
            if (apply.include_forms and self.year_workspace.isDraft() and
                self.factsMissingForYear() and
                !effectiveCoversYearBoundary(effective, year))
            {
                return error.NoFactsEffectiveForYear;
            }
        }

        const contact: model.RegisteredContact = .{
            .address = address,
            .zip_code = try fields.ZipCode.parse(trimmed(self.zip_code.text())),
            .contact_number = try fields.ContactNumber.parse(trimmed(self.phone.text())),
            .email_address = try fields.EmailAddress.parse(trimmed(self.email.text())),
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

        const ready = try self.buildSubject(base);
        // Historical activity/obligation component rows remain readable, but
        // all reusable fields now belong to this one effective-dated Base Tax
        // Profile revision. New revisions deliberately carry no legacy
        // repeated component writes.
        var revision = try ready.build();
        revision.accounting_period_basis = self.accounting_period_basis;
        revision.fiscal_year_end_month = if (self.accounting_period_basis == .fiscal) blk: {
            const raw = optionalTrimmed(
                self.fiscal_year_end_month.text(),
            ) orelse return error.InvalidAccountingPeriod;
            const month = std.fmt.parseInt(u8, raw, 10) catch
                return error.InvalidAccountingPeriod;
            if (month < 1 or month > 12) {
                return error.InvalidAccountingPeriod;
            }
            break :blk month;
        } else blk: {
            if (optionalTrimmed(self.fiscal_year_end_month.text()) != null) {
                return error.InvalidAccountingPeriod;
            }
            break :blk null;
        };
        revision.eopt_tier = self.eopt_tier;
        revision.primary_line_of_business = if (optionalTrimmed(
            self.primary_line_of_business.text(),
        )) |line| try fields.LineOfBusiness.parse(line) else null;
        revision.consolidation_review_state =
            self.consolidation_review_state;
        try revision.validate();

        // The authority on "did anything change": the editor's text can differ
        // from what was loaded while parsing to the very same facts, and a
        // record that says a phone number changed when only its punctuation
        // did is a lie in the history.
        if (!creating) {
            var current = try profile_persistence.loadCurrentRevision(
                store,
                allocator,
                profile_id,
            );
            if (current) |*owned| {
                defer owned.deinit(allocator);
                if (revision.contentEquals(&owned.revision)) {
                    return error.NoProfileChanges;
                }
            }
        }

        if (creating) {
            try profile_persistence.createProfileWithRevision(
                store,
                allocator,
                .active,
                &revision,
            );
        } else if (cor) |apply| {
            if (apply.include_forms) {
                // Staged writes and the create-vs-update mode are computed
                // before any refresh below can rewrite workspace state; the
                // old two-step flow reloaded the workspace between the
                // halves and wiped the staged selection it was about to
                // save.
                var writes: [max_registered_forms]persistence.FormRegistrationWrite =
                    undefined;
                const count = self.stagedFormWrites(&writes);
                const mode: persistence.FormSetApplyMode =
                    if (self.form_set_create_mode or
                    self.form_set_state == .needs_configuration or
                    self.form_set_state == .legacy_catalog_default)
                        .create
                    else
                        .update;
                try profile_persistence.applyCorReview(
                    store,
                    allocator,
                    &revision,
                    observed_sequence,
                    apply.document_id,
                    year,
                    writes[0..count],
                    mode,
                );
            } else {
                try profile_persistence.appendRevisionLinked(
                    store,
                    allocator,
                    &revision,
                    observed_sequence,
                    apply.document_id,
                );
            }
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
        return;
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
                self.managing_forms = false;
            },
            .conflict, .open_failed => {},
        }
        self.forms_apply_scope = .whole_year;
        self.change_effective_from.clear();
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
            .viewing, .draft_empty, .draft_seeded, .conflict => self.changedFormCount() > 0,
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
            self.forms_apply_scope = .whole_year;
            self.change_effective_from.clear();
            self.form_set_interval_count = 0;
            self.form_set_intervals_truncated = false;
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
        // Loading is browse/setup-choice state. Checkboxes become reachable
        // only through Manage Forms for an existing set or through an
        // explicit choice for an unconfigured year.
        self.managing_forms = false;
        self.forms_apply_scope = .whole_year;
        self.change_effective_from.clear();
        self.resetFormFilters();
        self.refreshFactsSummary(year);
        try self.refreshFormSetIntervals(year);
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
        self.staged_forms.resetInteraction();
        self.draft_source_year = null;
        self.managing_forms = true;
        self.form_set_create_mode = true;
        self.year_workspace = .draft_empty;
        self.resetFormFilters();
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
        self.staged_forms.resetInteraction();
        self.draft_source_year = source_year;
        self.managing_forms = true;
        self.form_set_create_mode = true;
        self.year_workspace = .draft_seeded;
        self.resetFormFilters();
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
        // Conflict review enters Manage mode only when the preserved draft
        // still differs from the newly loaded persisted baseline.
        self.managing_forms =
            !self.staged_forms.selectionEql(&self.saved_forms);
        self.year_workspace = .viewing;
        self.draft_source_year = null;
        self.resetFormFilters();
        try self.updateFormSetSummary();
        try self.refreshFormSetSummaries();
        try self.refreshFormSetIntervals(year);
    }

    /// Saves the open year. A draft creates; a configured year updates. A
    /// duplicate created concurrently becomes a recoverable conflict rather
    /// than a lost draft or a silent overwrite.
    pub fn saveYearWorkspace(self: *State) bool {
        if (!self.managing_forms) return false;
        if (self.year_workspace == .draft_choice or
            self.year_workspace == .open_failed or
            self.year_workspace == .conflict)
        {
            return false;
        }
        if (self.year_workspace == .viewing and
            self.forms_apply_scope == .from_date)
        {
            return self.recordMidYearChange();
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
        self.managing_forms = false;
        self.form_set_create_mode = false;
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

    pub fn chooseApplyWholeYear(self: *State) void {
        if (self.year_workspace != .viewing or !self.managing_forms) return;
        self.forms_apply_scope = .whole_year;
    }

    pub fn chooseApplyFromDate(self: *State) void {
        if (self.year_workspace != .viewing or !self.managing_forms) return;
        self.forms_apply_scope = .from_date;
    }

    pub fn applyScopeFromDate(self: *const State) bool {
        return self.year_workspace == .viewing and
            self.forms_apply_scope == .from_date;
    }

    pub fn changeDateText(self: *const State) []const u8 {
        return self.change_effective_from.text();
    }

    pub fn changeDateEmpty(self: *const State) bool {
        return trimmed(self.change_effective_from.text()).len == 0;
    }

    pub fn formSetIntervals(
        self: *const State,
    ) []const persistence.FormSetIntervalSummary {
        return self.form_set_intervals[0..self.form_set_interval_count];
    }

    pub fn formSetIntervalsTruncated(self: *const State) bool {
        return self.form_set_intervals_truncated;
    }

    fn refreshFormSetIntervals(self: *State, year: i32) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        self.form_set_interval_count = 0;
        self.form_set_intervals_truncated = false;
        const profile_id = self.selectedProfileId() orelse return;
        var listed = try store.listFormSetIntervals(
            allocator,
            profile_id,
            year,
        );
        defer listed.deinit(allocator);
        self.form_set_intervals_truncated =
            listed.items.len > self.form_set_intervals.len;
        const count = @min(listed.items.len, self.form_set_intervals.len);
        @memcpy(self.form_set_intervals[0..count], listed.items[0..count]);
        self.form_set_interval_count = count;
    }

    /// Records the staged catalog selection as a change effective from the
    /// typed date, leaving the year's base setup untouched. The workspace
    /// afterwards shows the saved year again — proof the base did not move —
    /// with the recorded change in the review list.
    fn recordMidYearChange(self: *State) bool {
        self.recordMidYearChangeFallible() catch |err| {
            self.setError(err);
            return false;
        };
        return true;
    }

    fn recordMidYearChangeFallible(self: *State) !void {
        const store = self.store orelse return error.NotAttached;
        if (self.editing_new) return error.FormsRequireSavedProfile;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;
        const year = try parseTaxYear(self.tax_year.text());
        const raw_date = trimmed(self.change_effective_from.text());
        // A clamped paste can truncate to a plausible date; deliberately not
        // in the sticky global truncation chain, because a bad date here must
        // not block an unrelated profile save.
        if (self.change_effective_from.truncated) {
            self.setErrorDetail(
                "Enter the date the change took effect as YYYY-MM-DD.",
            );
            return error.InvalidValue;
        }
        _ = model.Date.parseIso(raw_date) catch {
            self.setErrorDetail(
                "Enter the date the change took effect as YYYY-MM-DD.",
            );
            return error.InvalidValue;
        };
        var year_text: [4]u8 = undefined;
        _ = std.fmt.bufPrint(&year_text, "{d:0>4}", .{
            @as(u32, @intCast(year)),
        }) catch return error.InvalidTaxYear;
        if (!std.mem.startsWith(u8, raw_date, &year_text)) {
            var message: [96]u8 = undefined;
            self.setErrorDetail(std.fmt.bufPrint(
                &message,
                "That date isn't in {d}. Record the change in the year it belongs to.",
                .{year},
            ) catch "That date isn't in the open year.");
            return error.InvalidValue;
        }

        var writes: [max_registered_forms]persistence.FormRegistrationWrite =
            undefined;
        const count = self.stagedFormWrites(&writes);
        const generated = try store.generateOpaqueId();
        store.createFormSetInterval(.{
            .id = &generated,
            .profile_id = profile_id,
            .tax_year = year,
            .effective_from = raw_date,
            .forms = writes[0..count],
        }) catch |err| {
            if (err == persistence.Error.FormSetIntervalOverlap) {
                var message: [160]u8 = undefined;
                // The recorded change runs open through year end, so the
                // collision is the first existing change still in effect on
                // or after the typed date.
                const existing_from: []const u8 = blk: {
                    for (self.formSetIntervals()) |*interval| {
                        const open = interval.effective_until == null;
                        if (open or std.mem.order(
                            u8,
                            &interval.effective_until.?,
                            raw_date,
                        ) != .lt) {
                            break :blk &interval.effective_from;
                        }
                    }
                    break :blk "an earlier date";
                };
                self.setErrorDetail(std.fmt.bufPrint(
                    &message,
                    "A change recorded from {s} already covers those days. {d} can hold one recorded change per day.",
                    .{ existing_from, year },
                ) catch "A recorded change already covers those days.");
                return err;
            }
            if (err == persistence.Error.FormSetIntervalOutsideYear) {
                self.setErrorDetail(
                    "That date isn't in the open year. Record the change in the year it belongs to.",
                );
            }
            return err;
        };

        // The base year set was not touched, so nothing base-derived is
        // refreshed: the catalog snaps back to the saved membership and the
        // recorded change appears in the review list.
        const recorded_count = count;
        self.staged_forms.copySelectionFrom(&self.saved_forms);
        self.staged_forms.resetInteraction();
        self.forms_apply_scope = .whole_year;
        self.managing_forms = false;
        self.form_set_create_mode = false;
        self.resetFormFilters();
        try self.refreshFormSetIntervals(year);
        var message: [160]u8 = undefined;
        const rendered = (if (recorded_count == 1)
            std.fmt.bufPrint(
                &message,
                "Mid-year change recorded · 1 form from {s}. Deadlines still follow the year's saved setup.",
                .{raw_date},
            )
        else
            std.fmt.bufPrint(
                &message,
                "Mid-year change recorded · {d} forms from {s}. Deadlines still follow the year's saved setup.",
                .{ recorded_count, raw_date },
            )) catch "Mid-year change recorded.";
        self.setNotice(.success, rendered);
        self.change_effective_from.clear();
    }

    pub fn beginManageForms(self: *State) bool {
        if (self.editing_new or !self.has_selection) {
            self.setError(error.FormsRequireSavedProfile);
            return false;
        }
        if (self.year_workspace != .viewing or self.managing_forms or
            self.form_set_state == .needs_configuration)
        {
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
        return self.saveYearWorkspace();
    }

    /// Collects the staged catalog selection as store writes. Callers copy
    /// before any reload can rewrite `staged_forms` underneath them.
    fn stagedFormWrites(
        self: *const State,
        output: *[max_registered_forms]persistence.FormRegistrationWrite,
    ) usize {
        var count: usize = 0;
        for (&catalog.forms, 0..) |*form, index| {
            if (!self.staged_forms.isSelected(index)) continue;
            output[count] = .{
                .form_code = form.code,
                .form_revision = form.revision orelse "calendar-only",
            };
            count += 1;
        }
        return count;
    }

    fn saveManagedFormsFallible(self: *State) !void {
        const store = self.store orelse return error.NotAttached;
        if (self.editing_new) return error.FormsRequireSavedProfile;
        const profile_id = self.selectedProfileId() orelse
            return error.NoSelectedProfile;
        const year = try parseTaxYear(self.tax_year.text());
        var writes: [max_registered_forms]persistence.FormRegistrationWrite =
            undefined;
        const count = self.stagedFormWrites(&writes);
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
                const classification: model.NaturalPersonClassification =
                    if (self.subject_kind == .sole_proprietor)
                        .self_employed
                    else
                        self.natural_person_classification;
                if (trade_name != null and !self.tradeNameVisible()) {
                    return error.TradeNameNotApplicable;
                }
                const person: model.Individual = .{
                    .name = try fields.TaxpayerName.parse(name),
                    .classification = classification,
                    .trade_name = if (trade_name) |value|
                        try fields.RegisteredName.parse(value)
                    else
                        null,
                    .date_of_birth = try self.birthDateForEditor(),
                    .citizenship = try fields.Citizenship.parse(
                        (citizenship_reference.findByValue(
                            optionalTrimmed(self.citizenship.text()) orelse
                                return error.InvalidProfileField,
                        ) orelse return error.InvalidProfileField).value(),
                    ),
                    .foreign_tax_number = if (optionalTrimmed(self.foreign_tax_number.text())) |value|
                        try fields.ForeignTaxNumber.parse(value)
                    else
                        null,
                };
                // `.sole_proprietor` is accepted only as an old UI input. New
                // revisions always store the canonical natural-person shape.
                break :blk editor.begin(base).individual(person);
            },
            .corporation,
            .partnership,
            .cooperative,
            .estate,
            .trust,
            .other_legal_entity,
            => blk: {
                if (has_personal) return error.PersonalFieldsNotApplicable;
                break :blk editor.begin(base).legalEntity(.{
                    .registered_name = try fields.RegisteredName.parse(name),
                    // Estate/trust presentation currently hides this group by
                    // central policy, but a loaded optional value is preserved
                    // losslessly when another legal-entity fact is revised.
                    .trade_name = if (trade_name) |value|
                        try fields.RegisteredName.parse(value)
                    else
                        null,
                    .kind = switch (self.subject_kind) {
                        .corporation => .corporation,
                        .partnership => .partnership,
                        .cooperative => .cooperative,
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

    /// Only an explicitly configured Forms Set can activate a form. The
    /// legacy catalog-default marker remains available to the migration UI,
    /// but it never grants filing or setup access by itself.
    pub fn formAvailable(
        self: *const State,
        tax_year: i32,
        form_code: []const u8,
    ) bool {
        const cache = self.calendarFormSetCache(tax_year) orelse return false;
        if (cache.resolution == .unavailable) return false;
        if (cache.resolution == .catalog_fallback) return false;
        for (cache.codes[0..cache.count]) |*code| {
            if (std.ascii.eqlIgnoreCase(code.text(), form_code)) return true;
        }
        return false;
    }

    /// Exact date-aware availability for filing-period guards. Unlike the
    /// year summary cache, this asks the persisted interval resolver and
    /// matches both form code and form revision. Callers cache the result for
    /// rendering; launch, calendar, and export therefore share one authority.
    pub fn formAvailableOnDate(
        self: *const State,
        form_code: []const u8,
        form_revision: []const u8,
        on: model.Date,
    ) bool {
        const allocator = self.allocator orelse return false;
        const store = self.store orelse return false;
        const profile_id = self.selectedProfileId() orelse return false;
        var date_buffer: [10]u8 = undefined;
        var resolved = store.resolveFormSetOn(
            allocator,
            profile_id,
            on.writeIso(&date_buffer),
        ) catch return false;
        defer resolved.deinit(allocator);

        // A legacy catalog default is a migration/review state, not a
        // taxpayer-confirmed activation decision. Date-sensitive actions stay
        // closed until the user saves an explicit Forms Set; otherwise merely
        // opening a missing year silently activates every catalog entry.
        if (resolved.state == .legacy_catalog_default) return false;
        if (resolved.state != .active_nonempty) return false;
        for (resolved.forms.items) |item| {
            if (std.ascii.eqlIgnoreCase(item.form_code, form_code) and
                std.mem.eql(u8, item.form_revision, form_revision)) return true;
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

    /// Reloads the sidebar rows against the current search text. Errors keep
    /// the previous rows rather than blanking the sidebar mid-keystroke.
    pub fn setSidebarQuery(self: *State, text: []const u8) void {
        self.sidebar_query.set(std.mem.trim(u8, text, " \t\r\n")) catch return;
        // Typing before a store is attached (tests, early boot) records the
        // text and nothing else; rows load once attachment happens.
        if (self.store == null) return;
        self.reloadRows() catch |err| self.setError(err);
    }

    pub fn sidebarQuery(self: *const State) []const u8 {
        return self.sidebar_query.text();
    }

    pub fn profileListTruncated(self: *const State) bool {
        return self.profile_records_truncated;
    }

    fn reloadRows(self: *State) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const query = self.sidebar_query.text();
        var profiles = if (query.len == 0)
            try store.listProfiles(allocator, false)
        else
            try store.searchProfiles(allocator, query, false);
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

        const searching = self.sidebar_query.text().len != 0;
        if (self.profile_count == 0) {
            // A search matching nobody narrows the view; it must not clear
            // the selection behind it.
            if (searching) return;
            self.clearSelection();
            return;
        }
        if (self.selectedRow() == null and !searching) {
            switch (self.attachment_selection_policy) {
                .implicit_first => {
                    try self.selected_id.set(self.profiles[0].stable_id.text());
                    self.has_selection = true;
                },
                .explicit_only => {
                    // A selected taxpayer can legitimately be outside the
                    // capped non-search sidebar list. Preserve that explicit
                    // context rather than silently selecting someone else.
                    if (!self.has_selection or !self.profile_records_truncated) {
                        self.clearSelection();
                    }
                },
            }
        }
        self.markActiveRow();
        self.captureSelectedDisplay();
        // A duplicate-TIN warning is important after a taxpayer context is
        // active, but a sidebar-only Global Dashboard bootstrap must remain
        // silent until the user explicitly enters that context.
        if (self.has_selection) self.reportSharedTin();
    }

    fn clearSelection(self: *State) void {
        self.has_selection = false;
        self.has_selected_display = false;
        self.selected_id.clear();
        self.selected_revision_id.clear();
        self.selected_revision_sequence = null;
        self.registered_rdo = null;
    }

    /// Remembers how the selected taxpayer presents, so the header stays
    /// truthful while a search narrows the loaded rows past them.
    fn captureSelectedDisplay(self: *State) void {
        const row = self.selectedRow() orelse return;
        self.selected_display = row.*;
        self.has_selected_display = true;
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
        self.registered_rdo = revision.identity.rdo_code;
        if (!load_editor) return;

        self.editing_new = false;
        // Legacy Registration arrays remain readable only through the
        // explicit migration/export boundary. Normal Base editing neither
        // selects nor reconstructs them.
        self.loaded_shape_supported = true;
        self.subject_kind = switch (revision.subject) {
            // Compatibility-only persisted rows present as the canonical
            // legal subject. Their old tag proves self-employment.
            .sole_proprietor => .individual,
            else => revision.subject.kind(),
        };
        self.subject_kind_selected = true;
        self.natural_person_classification =
            revision.subject.naturalPersonClassification() orelse
            .classification_unknown;
        var tin_buffer: [32]u8 = undefined;
        setEditorBuffer(
            &self.tin,
            try revision.identity.tin.write(&tin_buffer),
        );
        setEditorBuffer(&self.rdo, revision.identity.rdo_code.asSlice());
        switch (revision.subject) {
            .individual => |person| {
                setEditorBuffer(&self.display_name, person.name.asSlice());
                setOptionalBoundedBuffer(&self.trade_name, person.trade_name);
                loadIndividualFields(self, &person);
            },
            .sole_proprietor => |proprietor| {
                setEditorBuffer(
                    &self.display_name,
                    proprietor.person.name.asSlice(),
                );
                setOptionalBoundedBuffer(
                    &self.trade_name,
                    proprietor.trade_name orelse proprietor.person.trade_name,
                );
                loadIndividualFields(self, &proprietor.person);
            },
            .legal_entity => |entity| {
                setEditorBuffer(
                    &self.display_name,
                    entity.registered_name.asSlice(),
                );
                setOptionalBoundedBuffer(&self.trade_name, entity.trade_name);
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
        self.accounting_period_basis = revision.accounting_period_basis;
        if (revision.fiscal_year_end_month) |month| {
            var month_buffer: [2]u8 = undefined;
            setEditorBuffer(
                &self.fiscal_year_end_month,
                std.fmt.bufPrint(&month_buffer, "{d}", .{month}) catch
                    unreachable,
            );
        } else {
            clearEditorBuffer(&self.fiscal_year_end_month);
        }
        self.eopt_tier = revision.eopt_tier;
        setOptionalBoundedBuffer(
            &self.primary_line_of_business,
            revision.primary_line_of_business,
        );
        self.consolidation_review_state =
            revision.consolidation_review_state;

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
        self.setEffectivePresentationFromStoredDates();
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

        setTaxYearBuffer(&self.tax_year, self.default_tax_year);
        try self.loadEditorFormSet(self.default_tax_year);
        self.input_was_truncated = false;
        self.captureBaseline();
        self.captureEditorSnapshot();
        self.profile_field_touched = [_]bool{false} ** profile_field_count;
        self.refreshFactsSummary(self.default_tax_year);
        self.refreshCorEvidence();
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
        clearEditorBuffer(&self.fiscal_year_end_month);
        clearEditorBuffer(&self.primary_line_of_business);
        self.effective_date_mode = .annual_years;
        clearEditorBuffer(&self.effective_start_year);
        clearEditorBuffer(&self.effective_end_year);
        clearEditorBuffer(&self.effective_from);
        clearEditorBuffer(&self.effective_until);
        clearEditorBuffer(&self.source_reference);
        clearEditorBuffer(&self.tax_year);
        clearEditorBuffer(&self.forms_set);
        self.subject_kind = .individual;
        self.subject_kind_selected = false;
        self.natural_person_classification = .classification_unknown;
        self.accounting_period_basis = null;
        self.eopt_tier = null;
        self.consolidation_review_state = .confirmed;
        self.source_kind = .manual_entry;
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
        self.resetFormFilters();
        self.input_was_truncated = false;
        self.profile_field_touched = [_]bool{false} ** profile_field_count;
    }

    pub fn captureInputTruncation(self: *State) void {
        // TextBuffer clears its own truncation flag once the user corrects
        // the value. Mirror the current buffer state rather than latching a
        // past overflow that would permanently disable Save for this edit.
        self.input_was_truncated = self.inputsTruncated();
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
            self.fiscal_year_end_month.truncated or
            self.primary_line_of_business.truncated or
            self.effective_start_year.truncated or
            self.effective_end_year.truncated or
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
            error.PersonalFieldsNotApplicable => "Birth date, citizenship, and foreign tax number apply only to individual subjects.",
            error.TradeNameNotApplicable => "A trade name is not applicable to the selected taxpayer classification.",
            error.SourceReferenceRequired => "Imported and migrated revisions require a source reference.",
            error.ManualSourceHasReference => "Manual entry has no external source reference. Choose Imported or Migrated.",
            error.UnsavedFormSetChanges => "Save or cancel your unsaved form changes before switching taxpayers.",
            error.UnsavedProfileChanges => "Save or cancel your unsaved taxpayer details before switching taxpayers.",
            error.DuplicateTaxpayerIdentifier,
            persistence.Error.DuplicateCanonicalTin,
            => "That TIN already belongs to a taxpayer you have. Open it instead of adding it again.",
            error.BranchTinRootChanged => "A branch keeps the same nine-digit TIN as its head office. Change only the branch code.",
            error.BranchCodeRequired => "Add the branch code after the nine-digit TIN, for example 123-456-789-002.",
            error.BranchLegalPersonChanged => "A branch is the same taxpayer. A different kind of taxpayer needs its own profile.",
            error.InvalidRdoSelection => "Choose an RDO from the official code and office list.",
            error.NewProfileTinMustHaveFourteenDigits => "New or corrected taxpayer profiles require an exact 3-3-3-5, 14-digit TIN. Existing legacy TINs remain readable only while unchanged.",
            error.NoFactsEffectiveForYear => "No taxpayer details exist for that year yet. Record what was true then before setting up its forms.",
            error.CorFileUnreadable => "That file could not be opened. Check it is still where you chose it from.",
            error.CorFileEmpty => "That file is empty.",
            error.CorFileTooLarge => "That file is larger than 16 MB, so it is not a Certificate of Registration.",
            error.CorFileUnsupported => "A COR must be a PDF or an image.",
            error.FormsRequireSavedProfile => "Save this taxpayer profile before choosing its forms.",
            persistence.Error.FormSetAlreadyExists => "That year is already set up. Choose it from the year list to edit its forms.",
            error.FieldTooLong => "One or more profile fields exceed their supported length.",
            else => "Profile was not saved. Check required fields and field formats.",
        };
        self.setNotice(.failure, message);
    }
};

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

/// The facts-summary boundary rule: a year has facts when a revision is
/// effective on its first or its last day. A period from June to June covers
/// neither, so the disjunction must not collapse.
fn effectiveCoversYearBoundary(effective: model.EffectivePeriod, year: i32) bool {
    if (year < 1 or year > 9999) return false;
    const opening = model.Date.init(@intCast(year), 1, 1) catch return false;
    const closing = model.Date.init(@intCast(year), 12, 31) catch return false;
    return effective.contains(opening) or effective.contains(closing);
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
        .cooperative => .cooperative,
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
        .accounting_period_basis => "Accounting-period basis",
        .date_of_birth => "Birth date",
        .citizenship => "Citizenship",
        .foreign_tax_number => "Foreign tax number",
        .line_of_business => "Line of business",
        .eopt_tier => "EOPT tier",
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
        .cooperative => "Cooperative",
        .estate => "Estate",
        .trust => "Trust",
        .other_legal_entity => "Other legal entity",
    };
}

fn classificationDisplayLabel(
    classification: model.NaturalPersonClassification,
) []const u8 {
    return switch (classification) {
        .classification_unknown => "Not yet recorded",
        .pure_compensation => "Pure compensation",
        .self_employed => "Self-employed / professional",
        .mixed_income => "Mixed income",
    };
}

fn setTaxYearBuffer(buffer: anytype, year: i32) void {
    var value: [16]u8 = undefined;
    // The formatter renders signed integers with an explicit `+` when
    // zero-padding. Tax years are positive calendar values, so format an
    // unsigned value and keep every valid year within the four-byte editor.
    const text = std.fmt.bufPrint(
        &value,
        "{d:0>4}",
        .{@as(u16, @intCast(year))},
    ) catch unreachable;
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

/// A COR is a registration certificate, not an archive: anything past this is
/// not the document it claims to be, and reading it would only stall the app.
/// The application's I/O handle, published once at boot.
///
/// Filesystem calls need one, and a message handler has no other way to reach
/// it. Hashing a document is bounded and runs on the same loop thread as the
/// file chooser that produced the path, so it costs no more than the modal the
/// user just dismissed. Absent in tests, where no file is ever read.
var app_io: ?std.Io = null;

pub fn publishIo(io: std.Io) void {
    app_io = io;
}

pub const EvidenceFileError = error{
    CorFileUnreadable,
    CorFileEmpty,
    CorFileTooLarge,
    CorFileUnsupported,
};

pub const CorFileError = EvidenceFileError;

pub const EvidenceFileFingerprint = registration_evidence_store.Fingerprint;

/// Measures and fingerprints a selected registration-evidence file using the
/// same bounded, signature-checked path as the legacy COR attachment workflow.
pub fn fingerprintEvidenceFile(path: []const u8) EvidenceFileError!EvidenceFileFingerprint {
    const io = app_io orelse return error.CorFileUnreadable;
    return registration_evidence_store.inspect(io, path) catch |err| switch (err) {
        error.SourceMissing, error.SourceUnreadable => error.CorFileUnreadable,
        error.Empty => error.CorFileEmpty,
        error.TooLarge => error.CorFileTooLarge,
        error.Unsupported => error.CorFileUnsupported,
    };
}

/// Re-checks a referenced document without loading it into the model.
fn verifyCorFile(path: []const u8, expected_digest: []const u8) State.CorEvidenceState {
    const fingerprint = fingerprintEvidenceFile(path) catch |err| return switch (err) {
        // A file that is present but no longer the attached document is a
        // different situation from one that is gone, and the user needs to
        // be able to tell them apart.
        error.CorFileUnsupported, error.CorFileEmpty, error.CorFileTooLarge => .changed,
        error.CorFileUnreadable => .moved,
    };
    return if (std.mem.eql(u8, &fingerprint.sha256, expected_digest))
        .on_file
    else
        .changed;
}

pub fn evidenceFileName(path: []const u8) []const u8 {
    if (std.fs.path.basename(path).len != 0) return std.fs.path.basename(path);
    return path;
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
    try std.testing.expect(!state.formAvailable(2026, "2551Q"));
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

test "global dashboard attachment indexes saved profiles without implicit context" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var focused = State{};
    try focused.attach(allocator, &store, "2026-08-05", 2026);
    focused.tin.set("123-456-789-00000");
    focused.rdo.set("040");
    focused.display_name.set("Global Dashboard Taxpayer");
    focused.setNaturalPersonClassification(.pure_compensation);
    focused.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&focused);
    focused.selectEffectiveStartYear(2026);
    try std.testing.expect(focused.save());
    const expected_id = focused.selectedProfileId().?;

    var shell = State{};
    try shell.attachForGlobalDashboard(
        allocator,
        &store,
        "2026-08-05",
        2026,
    );
    try std.testing.expectEqual(@as(usize, 1), shell.rows().len);
    try std.testing.expect(shell.selectedProfileId() == null);
    try std.testing.expect(shell.selectedRevisionContext() == null);
    try std.testing.expect(!shell.noticeVisible());
    // `startNew` is deliberately not part of the Global Dashboard bootstrap.
    try std.testing.expectEqualStrings("", shell.tax_year.text());

    // Selecting a sidebar row remains the explicit point that hydrates the
    // profile workspace.
    shell.select(0);
    try std.testing.expectEqualStrings(
        expected_id,
        shell.selectedProfileId().?,
    );
    try std.testing.expect(shell.selectedRevisionContext() != null);
    try std.testing.expect(shell.profileViewing());
    try std.testing.expect(!shell.noticeVisible());
}

test "global dashboard attachment is silent with no saved profiles" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var shell = State{};
    try shell.attachForGlobalDashboard(
        allocator,
        &store,
        "2026-08-05",
        2026,
    );
    try std.testing.expectEqual(@as(usize, 0), shell.rows().len);
    try std.testing.expect(shell.selectedProfileId() == null);
    try std.testing.expect(shell.selectedRevisionContext() == null);
    try std.testing.expect(!shell.noticeVisible());
    try std.testing.expectEqualStrings("", shell.tax_year.text());
}

test "profile state builds domain revision and explicit empty Forms Set" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-07-29", 2026);
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("Maria Santos");
    state.setNaturalPersonClassification(.self_employed);
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&state);
    state.email.set("maria@example.ph");
    state.selectEffectiveStartYear(2026);
    state.accounting_period_basis = .calendar;
    state.primary_line_of_business.set("Professional services");
    try std.testing.expect(state.save());
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expectEqual(YearWorkspaceMode.draft_choice, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(state.chooseDraftEmpty());
    try std.testing.expect(state.managing_forms);
    try std.testing.expect(state.form_set_create_mode);
    state.clearAllStagedForms();
    try std.testing.expect(state.saveYearWorkspace());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(!state.form_set_create_mode);

    try std.testing.expectEqual(NoticeKind.success, state.notice_kind);
    const profile_id = state.selectedProfileDomainId().?;
    var loaded = (try profile_persistence.loadCurrentRevision(
        &store,
        allocator,
        profile_id,
    )).?;
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), loaded.revision.sequence);

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

test "new profile rejects a legacy-length TIN without padding it" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-08-05", 2026);
    state.tin.set("123-456-789-000");
    state.rdo.set("040");
    state.display_name.set("Legacy Length New Profile");
    state.registered_address.set("Quezon City");
    state.selectEffectiveStartYear(2026);
    state.setNaturalPersonClassification(.pure_compensation);

    try std.testing.expect(state.saveDisabled());
    try std.testing.expect(!state.save());
    try std.testing.expectEqualStrings(
        "New or corrected taxpayer profiles require an exact 3-3-3-5, 14-digit TIN. Existing legacy TINs remain readable only while unchanged.",
        state.noticeText(),
    );
    try std.testing.expectEqualStrings("123-456-789-000", state.tin.text());
    try std.testing.expectEqual(@as(usize, 0), state.rows().len);
}

test "unchanged legacy TIN stays readable but a correction requires 14 digits" {
    var state = State{};
    state.editing_new = false;
    state.editor_baseline.valid = true;
    state.editor_baseline.tin.set("123456789000");
    state.tin.set("123456789000");
    try std.testing.expect(state.profileTinDraftValid());

    state.tin.set("1234567890000");
    try std.testing.expect(!state.profileTinDraftValid());

    state.tin.set("12345678900000");
    try std.testing.expect(state.profileTinDraftValid());
}

test "staged Forms Set is isolated until save and blocks context switches" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-07-29", 2026);
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("Staged Forms Taxpayer");
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&state);
    state.selectEffectiveStartYear(2026);
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
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expectEqual(YearWorkspaceMode.draft_choice, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(state.chooseDraftEmpty());
    try std.testing.expect(state.managing_forms);
    try std.testing.expect(state.form_set_create_mode);
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

    state.cancelYearWorkspaceEdits();
    try std.testing.expectEqual(YearWorkspaceMode.draft_choice, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(state.form_set_create_mode);
    try std.testing.expect(!state.formsDirty());
    try std.testing.expectEqual(@as(usize, 0), state.stagedFormCount());
    try std.testing.expectEqual(@as(usize, 0), state.changedFormCount());
    try std.testing.expect(!state.displayedFormSelected(index));
    try std.testing.expectEqual(FormActivityFilter.active, state.form_activity_filter);
    try std.testing.expectEqual(FormCapabilityFilter.all, state.form_capability_filter);

    try std.testing.expect(state.chooseDraftEmpty());
    state.toggleStagedForm(index);
    try std.testing.expect(state.saveYearWorkspace());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(!state.form_set_create_mode);
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
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("Existing Taxpayer");
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&state);
    state.selectEffectiveStartYear(2026);
    try std.testing.expect(state.save());

    const existing_id = state.selectedProfileDomainId().?;
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expectEqual(YearWorkspaceMode.draft_choice, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(state.chooseDraftEmpty());
    state.clearAllStagedForms();
    try std.testing.expect(state.saveYearWorkspace());
    try std.testing.expect(!state.managing_forms);

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
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("Maria Santos");
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&state);
    state.selectEffectiveStartYear(2026);
    try std.testing.expect(state.save());
    const profile_id = state.selectedProfileDomainId().?;
    const first_id = state.selectedRevisionContext().?.revision_id;

    state.display_name.set("Maria Santos Updated");
    state.useExactEffectiveDates();
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
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("Workspace Taxpayer");
    state.setNaturalPersonClassification(.pure_compensation);
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(state);
    // Registered well before the years these tests set up, so historical years
    // resolve real facts instead of hitting the retroactive-record guard.
    state.selectEffectiveStartYear(2020);
    try std.testing.expect(state.save());
}

fn setRequiredIndividualDetailsForTest(state: *State) void {
    // New profiles must explicitly affirm the legal taxpayer type; the enum's
    // internal Individual default is deliberately not treated as a selection.
    state.setSubjectKind(.individual);
    state.setAccountingPeriodBasis(.calendar);
    setRequiredContactDetailsForTest(state);
    state.birth_date.set("1990-01-02");
    state.citizenship.set("Filipino");
}

fn setRequiredContactDetailsForTest(state: *State) void {
    state.zip_code.set("1100");
    state.phone.set("0281234567");
    state.email.set("records@example.ph");
}

test "new profiles default to the current calendar year and keep an open end" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-08-11", 2026);

    try std.testing.expect(state.annualEffectiveYears());
    try std.testing.expectEqualStrings("2026", state.effective_start_year.text());
    try std.testing.expectEqualStrings("2026-01-01", state.effective_from.text());
    try std.testing.expectEqualStrings("", state.effective_end_year.text());
    try std.testing.expectEqualStrings("", state.effective_until.text());
}

test "annual effective years map to whole calendar-year dates" {
    var state = State{};

    state.selectEffectiveStartYear(2026);
    state.selectEffectiveEndYear(2028);

    try std.testing.expectEqualStrings("2026", state.effective_start_year.text());
    try std.testing.expectEqualStrings("2028", state.effective_end_year.text());
    try std.testing.expectEqualStrings("2026-01-01", state.effective_from.text());
    try std.testing.expectEqualStrings("2028-12-31", state.effective_until.text());
}

test "typed older annual years and zero-padded boundary years are valid" {
    var state = State{};

    state.applyEffectiveStartYearInput(.{ .insert_text = "2019" });
    try std.testing.expectEqualStrings("2019", state.effective_start_year.text());
    try std.testing.expectEqualStrings("2019-01-01", state.effective_from.text());

    state.selectEffectiveStartYear(1);
    try std.testing.expectEqualStrings("0001", state.effective_start_year.text());
    try std.testing.expectEqual(@as(i32, 1), parseTaxYear(
        state.effective_start_year.text(),
    ));
}

test "incomplete annual years fail validation and appear after focus loss" {
    var state = State{};
    state.subject_kind = .corporation;
    state.display_name.set("Annual Profile Inc.");
    state.registered_address.set("Quezon City");
    state.zip_code.set("1100");
    state.phone.set("0281234567");
    state.email.set("records@example.ph");
    state.effective_start_year.set("20");

    try std.testing.expectEqualStrings(
        "Enter a four-digit year from 0001 to 9999.",
        state.profileFieldValidationMessage(.effective_start).?,
    );
    try std.testing.expect(!state.profileFieldErrorVisible(.effective_start));

    state.revealProfileFieldValidation(.effective_start);
    try std.testing.expect(state.profileFieldErrorVisible(.effective_start));
    try std.testing.expectError(
        error.InvalidProfileField,
        state.validateProfileFieldsForSave(),
    );
}

test "an incomplete annual start year cannot switch to exact dates" {
    var state = State{};
    state.selectEffectiveStartYear(2026);
    state.effective_start_year.set("20");

    state.useExactEffectiveDates();

    try std.testing.expect(state.annualEffectiveYears());
    try std.testing.expect(state.profileFieldErrorVisible(.effective_start));
    try std.testing.expectEqualStrings(
        "Enter a four-digit year from 0001 to 9999.",
        state.profileFieldValidationMessage(.effective_start).?,
    );
}

test "an incomplete annual end year cannot switch to exact dates" {
    var state = State{};
    state.selectEffectiveStartYear(2026);
    state.selectEffectiveEndYear(2027);
    state.effective_end_year.set("20");

    state.useExactEffectiveDates();

    try std.testing.expect(state.annualEffectiveYears());
    try std.testing.expect(state.profileFieldErrorVisible(.effective_end));
    try std.testing.expectEqualStrings(
        "Enter a four-digit year from 0001 to 9999.",
        state.profileFieldValidationMessage(.effective_end).?,
    );
}

test "correcting a truncated profile input clears the save block" {
    var state = State{};
    const too_long = [_]u8{'A'} ** 161;

    state.display_name.apply(.{ .insert_text = &too_long });
    state.captureInputTruncation();
    try std.testing.expect(state.input_was_truncated);

    state.display_name.apply(.clear);
    state.display_name.apply(.{ .insert_text = "Corrected Taxpayer Name" });
    state.captureInputTruncation();

    try std.testing.expect(!state.input_was_truncated);
    try std.testing.expect(!state.inputsTruncated());
}

test "a mid-year stored range remains exact when annual years are requested" {
    var state = State{};
    state.effective_from.set("2026-07-01");
    state.effective_until.set("2027-06-30");
    state.setEffectivePresentationFromStoredDates();

    try std.testing.expect(state.exactEffectiveDates());
    state.useAnnualEffectiveYears();

    try std.testing.expect(state.exactEffectiveDates());
    try std.testing.expectEqualStrings("2026-07-01", state.effective_from.text());
    try std.testing.expectEqualStrings("2027-06-30", state.effective_until.text());
    try std.testing.expectEqualStrings("", state.effective_start_year.text());
    try std.testing.expectEqualStrings("", state.effective_end_year.text());
}

test "registered address is required and parser-backed" {
    var state = State{};

    try std.testing.expectEqualStrings(
        "Registered address is required.",
        state.profileFieldValidationMessage(.registered_address).?,
    );

    state.registered_address.set("Quezon\x01City");
    try std.testing.expectEqualStrings(
        "Enter a valid registered address.",
        state.profileFieldValidationMessage(.registered_address).?,
    );
}

test "registered address validation becomes visible on blur and on save" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-08-11", 2026);
    state.setSubjectKind(.corporation);
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("Validation Profile Inc.");
    state.zip_code.set("1100");
    state.phone.set("0281234567");
    state.email.set("records@example.ph");

    try std.testing.expect(!state.profileFieldErrorVisible(.registered_address));
    state.revealProfileFieldValidation(.registered_address);
    try std.testing.expect(state.profileFieldErrorVisible(.registered_address));

    state.profile_field_touched = [_]bool{false} ** profile_field_count;
    try std.testing.expect(!state.save());
    try std.testing.expect(state.profileFieldErrorVisible(.registered_address));
    try std.testing.expect(
        state.profile_field_touched[@intFromEnum(ProfileField.email_address)],
    );
}

test "RDO validation becomes visible on save" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-08-11", 2026);
    state.setSubjectKind(.corporation);
    state.setAccountingPeriodBasis(.calendar);
    state.tin.set("123-456-789-00000");
    state.display_name.set("RDO Validation Profile Inc.");
    state.registered_address.set("Quezon City");
    state.zip_code.set("1100");
    state.phone.set("0281234567");
    state.email.set("records@example.ph");

    try std.testing.expect(!state.profileFieldErrorVisible(.rdo_code));
    try std.testing.expect(!state.save());
    try std.testing.expect(state.profileFieldErrorVisible(.rdo_code));
    try std.testing.expectEqualStrings(
        "RDO is required.",
        state.profileFieldValidationMessage(.rdo_code).?,
    );
}

test "taxpayer type and accounting basis require explicit choices" {
    var state = State{};

    try std.testing.expectEqualStrings(
        "Taxpayer Type is required.",
        state.profileFieldValidationMessage(.taxpayer_type).?,
    );
    try std.testing.expectEqualStrings(
        "Choose Calendar or Fiscal accounting period.",
        state.profileFieldValidationMessage(.accounting_period_basis).?,
    );

    state.setSubjectKind(.individual);
    state.setAccountingPeriodBasis(.calendar);
    try std.testing.expect(state.profileFieldValidationMessage(.taxpayer_type) == null);
    try std.testing.expect(
        state.profileFieldValidationMessage(.accounting_period_basis) == null,
    );

    state.clearSubjectKindSelection();
    try std.testing.expectEqualStrings(
        "Taxpayer Type is required.",
        state.profileFieldValidationMessage(.taxpayer_type).?,
    );
}

test "restoring a profile snapshot clears prior field validation visibility" {
    var state = State{};
    state.display_name.set("Saved name");
    state.captureEditorSnapshot();
    state.display_name.clear();
    state.revealProfileFieldValidation(.taxpayer_name);
    try std.testing.expect(state.profileFieldErrorVisible(.taxpayer_name));

    try std.testing.expect(state.restoreEditorSnapshot());
    try std.testing.expect(!state.profileFieldErrorVisible(.taxpayer_name));
}

test "birth date editor normalizes accepted Filipino short dates" {
    var state = State{};
    try state.default_effective_from.set("2026-08-11");
    state.birth_date.set("8/17/88");

    state.normalizeBirthDateInput();
    try std.testing.expectEqualStrings("1988-08-17", state.birth_date.text());
}

test "complete profile creation stores consolidated reusable fields" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-08-05", 2026);
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("New Complete Taxpayer");
    state.setNaturalPersonClassification(.self_employed);
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&state);
    state.selectEffectiveStartYear(2026);
    state.setAccountingPeriodBasis(.fiscal);
    state.fiscal_year_end_month.set("6");
    state.setEoptTier(.micro);
    state.primary_line_of_business.set("Professional services");
    try std.testing.expect(state.save());

    const profile_id = state.selectedProfileDomainId().?;
    var base = (try profile_persistence.loadCurrentRevision(
        &store,
        allocator,
        profile_id,
    )).?;
    defer base.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), base.revision.sequence);
    try std.testing.expectEqual(
        model.AccountingPeriodBasis.fiscal,
        base.revision.accounting_period_basis.?,
    );
    try std.testing.expectEqual(@as(?u8, 6), base.revision.fiscal_year_end_month);
    try std.testing.expectEqual(model.EoptTier.micro, base.revision.eopt_tier.?);
    try std.testing.expectEqualStrings(
        "Professional services",
        base.revision.primary_line_of_business.?.asSlice(),
    );

    var history = try persistence.testing.listLegacyRegistrationHistory(
        &store,
        allocator,
        profile_id.asSlice(),
    );
    defer history.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), history.stream_sequence);
    try std.testing.expectEqual(@as(usize, 0), history.activities.len);
}

test "tax profile view edit dirty and cancel lifecycle is explicit" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    const selected_before = state.selectedRevisionContext().?;

    try std.testing.expectEqual(ProfileMode.viewing, state.profileMode());
    try std.testing.expect(state.profileViewing());
    try std.testing.expect(state.profileInputsDisabled());
    try std.testing.expect(state.saveDisabled());
    try std.testing.expect(state.cancelDisabled());

    state.editSelected();
    try std.testing.expectEqual(ProfileMode.editing, state.profileMode());
    try std.testing.expect(state.profileEditing());
    try std.testing.expect(!state.profileInputsDisabled());
    try std.testing.expect(!state.factsDirty());
    try std.testing.expect(state.saveDisabled());
    try std.testing.expect(state.cancelDisabled());

    state.setNaturalPersonClassification(.self_employed);
    // Classification alone is a persisted fact and must make the draft dirty.
    try std.testing.expect(state.factsDirty());
    state.registered_address.set("Makati City");
    state.trade_name.set("Unsaved Trade Name");
    state.setSourceKind(.imported);
    state.source_reference.set("COR under review");
    try std.testing.expect(state.factsDirty());
    try std.testing.expect(!state.saveDisabled());
    try std.testing.expect(!state.cancelDisabled());

    // Cancel is a pure in-memory revert. Closing storage proves it neither
    // reloads persistence nor changes the selected taxpayer/revision.
    store.close();
    state.cancelEdit();
    try std.testing.expectEqual(ProfileMode.viewing, state.profileMode());
    try std.testing.expectEqualStrings(
        "Quezon City",
        state.registered_address.text(),
    );
    try std.testing.expectEqual(SourceKind.manual_entry, state.source_kind);
    try std.testing.expectEqual(
        model.NaturalPersonClassification.pure_compensation,
        state.naturalPersonClassification(),
    );
    try std.testing.expectEqualStrings(
        "Pure compensation",
        state.classificationLabel(),
    );
    try std.testing.expectEqualStrings("", state.trade_name.text());
    try std.testing.expectEqualStrings("", state.source_reference.text());
    try std.testing.expect(!state.factsDirty());
    const selected_after = state.selectedRevisionContext().?;
    try std.testing.expect(selected_before.eql(&selected_after));
}

test "legacy local profile label remains migration data only" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    const profile_id = state.selectedProfileId().?;
    try store.updateProfileLabel(.{
        .profile_id = profile_id,
        .label = "Historical household label",
    });
    try state.attach(allocator, &store, "2026-01-01", 2026);
    try std.testing.expectEqualStrings(
        "Workspace Taxpayer",
        state.selectedDisplay().?.nameLabel(),
    );

    state.editSelected();
    state.display_name.set("Workspace Taxpayer Legal Name");
    try std.testing.expect(state.save());

    try std.testing.expectEqual(@as(u32, 2), state.selectedRevisionSequence().?);
    try std.testing.expectEqualStrings(
        "Workspace Taxpayer Legal Name",
        state.selectedDisplay().?.nameLabel(),
    );
    try std.testing.expectEqualStrings(
        "Workspace Taxpayer Legal Name",
        state.display_name.text(),
    );

    var legacy = (try store.getProfileLabel(allocator, profile_id)).?;
    defer legacy.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Historical household label",
        legacy.label.?,
    );
}

test "create mode keeps cancel enabled and restores the selected profile" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    const selected_before = state.selectedRevisionContext().?;

    state.startNew();
    try std.testing.expectEqual(ProfileMode.creating, state.profileMode());
    try std.testing.expect(state.profileCreating());
    try std.testing.expect(!state.cancelDisabled());
    try std.testing.expect(state.saveDisabled());
    try std.testing.expect(!state.factsDirty());

    state.display_name.set("Unsaved New Taxpayer");
    try std.testing.expect(state.factsDirty());
    state.cancelEdit();

    try std.testing.expectEqual(ProfileMode.viewing, state.profileMode());
    try std.testing.expect(!state.editing_new);
    try std.testing.expectEqualStrings(
        "Workspace Taxpayer",
        state.display_name.text(),
    );
    try std.testing.expect(!state.factsDirty());
    const selected_after = state.selectedRevisionContext().?;
    try std.testing.expect(selected_before.eql(&selected_after));
}

test "editor visibility exhaustively delegates to central applicability" {
    // One state allocation avoids multiplying this large fixed-buffer model
    // across compile-time-unrolled cases and exhausting the test stack.
    var state = State{};
    // The visibility methods intentionally require an explicit taxpayer-type
    // choice; this exhaustive matrix supplies that committed UI state directly
    // so its raw SubjectKind cases (including legacy compatibility tags) stay
    // intact.
    state.subject_kind_selected = true;
    for (std.meta.tags(model.SubjectKind)) |subject_kind| {
        for (std.meta.tags(model.NaturalPersonClassification)) |classification| {
            for ([_]bool{ false, true }) |has_trade_name| {
                state.subject_kind = subject_kind;
                state.natural_person_classification = classification;
                clearEditorBuffer(&state.trade_name);
                if (has_trade_name) state.trade_name.set("Preserved trade");
                const context: applicability.Context = .{
                    .subject_kind = subject_kind,
                    .natural_person_classification = classification,
                    .has_trade_name = has_trade_name,
                };
                try std.testing.expectEqual(
                    applicability.fieldGroupVisible(
                        context,
                        .natural_person_details,
                    ),
                    state.naturalPersonFieldsVisible(),
                );
                try std.testing.expectEqual(
                    applicability.fieldGroupVisible(context, .trade_name),
                    state.tradeNameVisible(),
                );
                try std.testing.expectEqual(
                    applicability.fieldGroupVisible(
                        context,
                        .line_of_business,
                    ),
                    state.lineOfBusinessVisible(),
                );
                try std.testing.expectEqual(
                    state.lineOfBusinessVisible(),
                    state.businessFieldsVisible(),
                );
            }
        }
    }
}

test "classification and subject switches preserve conditional editor data" {
    var state = State{};
    state.birth_date.set("1990-01-02");
    state.citizenship.set("Filipino");
    state.trade_name.set("Sample Trading");
    state.primary_line_of_business.set("Professional services");

    state.setSubjectKind(.sole_proprietor);
    try std.testing.expect(state.subjectKindSelected(.individual));
    try std.testing.expect(!state.subjectKindSelected(.sole_proprietor));
    try std.testing.expectEqual(
        model.NaturalPersonClassification.self_employed,
        state.naturalPersonClassification(),
    );
    try std.testing.expect(state.classificationSelected(.self_employed));
    try std.testing.expectEqualStrings(
        "Self-employed / professional",
        state.classificationLabel(),
    );
    try std.testing.expect(state.naturalPersonFieldsVisible());
    try std.testing.expect(state.tradeNameVisible());
    try std.testing.expect(state.lineOfBusinessVisible());

    // Direct Base fields remain buffered through selector changes; visibility
    // follows the chosen taxpayer type and classification.
    state.setNaturalPersonClassification(.pure_compensation);
    try std.testing.expect(!state.businessFieldsVisible());
    try std.testing.expect(!state.lineOfBusinessVisible());
    try std.testing.expect(state.tradeNameVisible());

    state.setSubjectKind(.estate);
    try std.testing.expect(!state.naturalPersonFieldsVisible());
    try std.testing.expect(!state.tradeNameVisible());
    try std.testing.expect(!state.businessFieldsVisible());
    state.setSubjectKind(.corporation);
    try std.testing.expect(state.tradeNameVisible());

    try std.testing.expectEqualStrings("1990-01-02", state.birth_date.text());
    try std.testing.expectEqualStrings("Filipino", state.citizenship.text());
    try std.testing.expectEqualStrings("Sample Trading", state.trade_name.text());
    try std.testing.expectEqualStrings(
        "Professional services",
        state.primary_line_of_business.text(),
    );
}

test "classification labels and selected state cover every classification" {
    const cases = [_]struct {
        value: model.NaturalPersonClassification,
        label: []const u8,
    }{
        .{ .value = .classification_unknown, .label = "Not yet recorded" },
        .{ .value = .pure_compensation, .label = "Pure compensation" },
        .{ .value = .self_employed, .label = "Self-employed / professional" },
        .{ .value = .mixed_income, .label = "Mixed income" },
    };
    var state = State{};
    for (cases) |case| {
        state.setNaturalPersonClassification(case.value);
        try std.testing.expectEqual(case.value, state.naturalPersonClassification());
        try std.testing.expect(state.classificationSelected(case.value));
        try std.testing.expectEqualStrings(case.label, state.classificationLabel());
    }
}

fn subjectBuildTestBase() !editor.Base {
    return .{
        .profile_id = try model.ProfileId.parse("profile-subject-build"),
        .revision_id = try model.RevisionId.parse("revision-subject-build"),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try fields.Tin.parse("123-456-789-000"),
            .rdo_code = try fields.RdoCode.parse("040"),
        },
        .contact = .{
            .address = try fields.RegisteredAddress.parse("Quezon City"),
        },
    };
}

test "new natural-person subjects never build sole-proprietor rows" {
    inline for (std.meta.tags(model.NaturalPersonClassification)) |classification| {
        var state = State{};
        try state.default_effective_from.set("2026-01-01");
        state.display_name.set("Maria Santos");
        state.setSubjectKind(.individual);
        state.setNaturalPersonClassification(classification);
        setRequiredIndividualDetailsForTest(&state);
        const has_trade_name = classification == .self_employed or
            classification == .mixed_income;
        if (has_trade_name) {
            state.trade_name.set("Maria Professional Services");
        }

        const ready = try state.buildSubject(try subjectBuildTestBase());
        const revision = try ready.build();
        switch (revision.subject) {
            .individual => |person| {
                try std.testing.expectEqual(classification, person.classification);
                if (has_trade_name) {
                    try std.testing.expectEqualStrings(
                        "Maria Professional Services",
                        person.trade_name.?.asSlice(),
                    );
                } else {
                    try std.testing.expect(person.trade_name == null);
                }
            },
            .sole_proprietor, .legal_entity => return error.TestUnexpectedResult,
        }
    }

    // The deprecated selector input is normalized before the build as well.
    var compatibility = State{};
    try compatibility.default_effective_from.set("2026-01-01");
    compatibility.display_name.set("Legacy UI Shortcut");
    compatibility.trade_name.set("Shortcut Trade Name");
    compatibility.setSubjectKind(.sole_proprietor);
    setRequiredIndividualDetailsForTest(&compatibility);
    const ready = try compatibility.buildSubject(try subjectBuildTestBase());
    const revision = try ready.build();
    switch (revision.subject) {
        .individual => |person| try std.testing.expectEqual(
            model.NaturalPersonClassification.self_employed,
            person.classification,
        ),
        .sole_proprietor, .legal_entity => return error.TestUnexpectedResult,
    }
}

test "legacy citizenship codes stay editable and normalize on the next save" {
    var state = State{};
    try state.default_effective_from.set("2026-08-11");
    state.setSubjectKind(.individual);
    state.setNaturalPersonClassification(.pure_compensation);
    state.display_name.set("Maria Santos");
    state.birth_date.set("1990-01-02");
    state.citizenship.set("PH");

    try std.testing.expect(
        state.profileFieldValidationMessage(.citizenship) == null,
    );
    const ready = try state.buildSubject(try subjectBuildTestBase());
    const revision = try ready.build();
    switch (revision.subject) {
        .individual => |person| try std.testing.expectEqualStrings(
            "Filipino",
            person.citizenship.?.asSlice(),
        ),
        .sole_proprietor, .legal_entity => return error.TestUnexpectedResult,
    }
}

test "every legal-entity kind builds optional trade name without changing policy" {
    const cases = [_]struct {
        subject_kind: model.SubjectKind,
        entity_kind: model.LegalEntityKind,
        trade_visible: bool,
    }{
        .{ .subject_kind = .corporation, .entity_kind = .corporation, .trade_visible = true },
        .{ .subject_kind = .partnership, .entity_kind = .partnership, .trade_visible = true },
        .{ .subject_kind = .cooperative, .entity_kind = .cooperative, .trade_visible = true },
        .{ .subject_kind = .estate, .entity_kind = .estate, .trade_visible = false },
        .{ .subject_kind = .trust, .entity_kind = .trust, .trade_visible = false },
        .{ .subject_kind = .other_legal_entity, .entity_kind = .other, .trade_visible = true },
    };
    for (cases) |case| {
        var state = State{};
        state.display_name.set("Registered Legal Name");
        state.trade_name.set("Optional Trade Name");
        state.setSubjectKind(case.subject_kind);
        try std.testing.expectEqual(case.trade_visible, state.tradeNameVisible());

        const ready = try state.buildSubject(try subjectBuildTestBase());
        const revision = try ready.build();
        switch (revision.subject) {
            .legal_entity => |entity| {
                try std.testing.expectEqual(case.entity_kind, entity.kind);
                try std.testing.expectEqualStrings(
                    "Optional Trade Name",
                    entity.trade_name.?.asSlice(),
                );
            },
            .individual, .sole_proprietor => return error.TestUnexpectedResult,
        }
    }
}

test "legacy sole-proprietor load migrates through canonical individual save" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const revision: model.ProfileRevision = .{
        .profile_id = try model.ProfileId.parse("profile-legacy-sole"),
        .id = try model.RevisionId.parse("revision-legacy-sole-1"),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2020-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try fields.Tin.parse("321-654-987-000"),
            .rdo_code = try fields.RdoCode.parse("040"),
        },
        .contact = .{
            .address = try fields.RegisteredAddress.parse("Quezon City"),
            .zip_code = try fields.ZipCode.parse("1100"),
            .contact_number = try fields.ContactNumber.parse("09171234567"),
            .email_address = try fields.EmailAddress.parse("legacy@example.ph"),
        },
        .subject = .{ .sole_proprietor = .{
            .person = .{
                .name = try fields.TaxpayerName.parse("Legacy Professional"),
                .date_of_birth = try model.Date.parseIso("1990-01-02"),
                .citizenship = try fields.Citizenship.parse("Filipino"),
            },
            .trade_name = try fields.RegisteredName.parse("Legacy Trade Name"),
        } },
        .accounting_period_basis = .calendar,
    };
    try profile_persistence.createProfileWithRevision(
        &store,
        allocator,
        .active,
        &revision,
    );

    var state = State{};
    try state.attach(allocator, &store, "2026-08-04", 2026);
    try std.testing.expect(state.subjectKindSelected(.individual));
    try std.testing.expect(!state.subjectKindSelected(.sole_proprietor));
    try std.testing.expect(state.classificationSelected(.self_employed));
    try std.testing.expectEqualStrings(
        "Legacy Trade Name",
        state.trade_name.text(),
    );
    try std.testing.expectEqualStrings(
        "Legacy Trade Name",
        state.reusableValueText(.registered_name),
    );

    state.editSelected();
    setRequiredIndividualDetailsForTest(&state);
    state.registered_address.set("Makati City");
    try std.testing.expect(state.save());

    var current = (try profile_persistence.loadCurrentRevision(
        &store,
        allocator,
        revision.profile_id,
    )).?;
    defer current.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 2), current.revision.sequence);
    switch (current.revision.subject) {
        .individual => |person| {
            try std.testing.expectEqual(
                model.NaturalPersonClassification.self_employed,
                person.classification,
            );
            try std.testing.expectEqualStrings(
                "Legacy Trade Name",
                person.trade_name.?.asSlice(),
            );
        },
        .sole_proprietor, .legal_entity => return error.TestUnexpectedResult,
    }
}

test "legal-entity trade name loads and cancel restores it exactly" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(allocator, &store, "2026-08-04", 2026);
    state.tin.set("987-654-321-00000");
    state.rdo.set("040");
    state.display_name.set("Example Corporation");
    state.trade_name.set("Example Trading");
    state.registered_address.set("Makati City");
    setRequiredContactDetailsForTest(&state);
    state.selectEffectiveStartYear(2020);
    state.setSubjectKind(.corporation);
    state.setAccountingPeriodBasis(.calendar);
    try std.testing.expect(state.save());

    try std.testing.expect(state.subjectKindSelected(.corporation));
    try std.testing.expectEqualStrings("Example Trading", state.trade_name.text());
    const profile_id = state.selectedProfileDomainId().?;
    var current = (try profile_persistence.loadCurrentRevision(
        &store,
        allocator,
        profile_id,
    )).?;
    defer current.deinit(allocator);
    switch (current.revision.subject) {
        .legal_entity => |entity| try std.testing.expectEqualStrings(
            "Example Trading",
            entity.trade_name.?.asSlice(),
        ),
        .individual, .sole_proprietor => return error.TestUnexpectedResult,
    }

    state.editSelected();
    state.trade_name.set("Unsaved Replacement");
    try std.testing.expect(state.factsDirty());
    state.cancelEdit();
    try std.testing.expectEqualStrings("Example Trading", state.trade_name.text());
    try std.testing.expect(!state.factsDirty());
}

fn catalogIndexOf(code: []const u8) usize {
    for (&catalog.forms, 0..) |*form, index| {
        if (std.mem.eql(u8, form.code, code)) return index;
    }
    unreachable;
}

test "configured year opens in browse and explicit management uses update" {
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
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(!state.form_set_create_mode);
    try std.testing.expectEqual(@as(usize, 1), state.activeFormCount());

    // Browse cannot save. Explicit Manage starts clean and Cancel returns to
    // browse without changing the configured set.
    try std.testing.expect(!state.saveYearWorkspace());
    try std.testing.expect(state.beginManageForms());
    try std.testing.expect(state.managing_forms);
    try std.testing.expect(!state.form_set_create_mode);
    try std.testing.expect(!state.formsDirty());
    state.toggleStagedForm(catalogIndexOf("1701Q"));
    try std.testing.expect(state.formsDirty());
    state.cancelManageForms();
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(!state.formsDirty());
    try std.testing.expect(!state.displayedFormSelected(catalogIndexOf("1701Q")));
    try std.testing.expectEqual(@as(usize, 1), state.activeFormCount());

    // Editing an existing year takes the update path: the insert-only create
    // path is unreachable, so a save can never collide with itself.
    try std.testing.expect(state.beginManageForms());
    state.toggleStagedForm(catalogIndexOf("1701Q"));
    try std.testing.expect(state.formsDirty());
    try std.testing.expect(state.saveYearWorkspace());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expectEqual(@as(usize, 2), state.activeFormCount());

    // Even a stale summary cache cannot reclassify a configured year, because
    // the workspace resolves membership from the store on every open.
    state.form_set_summary_count = 0;
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expectEqual(@as(usize, 2), state.activeFormCount());
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
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(state.chooseDraftEmpty());
    try std.testing.expect(state.managing_forms);
    state.toggleStagedForm(index_2551q);
    try std.testing.expect(state.stagedFormSelected(index_2551q));

    // Another window configures the same year first.
    try store.createFormSet(profile_id, 2026, &.{.{
        .form_code = "1701Q",
        .form_revision = "2018-01-ENCS",
    }});

    try std.testing.expect(!state.saveYearWorkspace());
    try std.testing.expectEqual(YearWorkspaceMode.conflict, state.year_workspace);
    try std.testing.expect(state.managing_forms);
    // The staged work survives the collision.
    try std.testing.expect(state.stagedFormSelected(index_2551q));

    try std.testing.expect(state.reviewConflictingYear());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(state.managing_forms);
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
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(state.persistedFormSelected(index_2551q));
    try std.testing.expect(!state.persistedFormSelected(index_1701q));
}

test "conflict review stays in browse when pending work already matches" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    const profile_id = state.selectedProfileId().?;
    const index_2551q = catalogIndexOf("2551Q");

    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    state.toggleStagedForm(index_2551q);

    // Another window persisted exactly the same selection. Review adopts it
    // as the baseline and has no pending work that warrants Manage mode.
    try store.createFormSet(profile_id, 2026, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});
    try std.testing.expect(!state.saveYearWorkspace());
    try std.testing.expectEqual(YearWorkspaceMode.conflict, state.year_workspace);
    try std.testing.expect(state.reviewConflictingYear());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(!state.formsDirty());
    try std.testing.expect(state.persistedFormSelected(index_2551q));
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
    try std.testing.expect(!state.managing_forms);
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
    try std.testing.expect(!state.managing_forms);
    try std.testing.expectEqual(@as(i32, 2026), state.recommendedSeedYear().?);

    try std.testing.expect(state.chooseDraftSeed(2026));
    try std.testing.expectEqual(YearWorkspaceMode.draft_seeded, state.year_workspace);
    try std.testing.expect(state.managing_forms);
    try std.testing.expect(state.form_set_create_mode);
    try std.testing.expectEqual(@as(i32, 2026), state.draftSourceYear().?);
    try std.testing.expectEqual(@as(usize, 2), state.stagedFormCount());

    state.toggleStagedForm(index_1701q);
    try std.testing.expectEqual(@as(usize, 1), state.stagedFormCount());
    try std.testing.expect(state.saveYearWorkspace());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(!state.form_set_create_mode);

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
    try std.testing.expectEqual(YearWorkspaceMode.draft_choice, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(state.chooseDraftEmpty());
    try std.testing.expectEqual(YearWorkspaceMode.draft_empty, state.year_workspace);
    try std.testing.expect(state.managing_forms);
    try std.testing.expect(state.saveYearWorkspace());
    try std.testing.expect(!state.managing_forms);

    try std.testing.expectEqual(
        persistence.FormSetState.active_empty,
        state.form_set_state,
    );
    try std.testing.expect(state.forms_set_configured);
    try std.testing.expect(!state.formAvailable(2026, "2551Q"));
    // Reopening keeps it configured rather than reverting to a setup draft.
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
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
    try std.testing.expect(!state.managing_forms);
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

test "normal profile header does not infer a registered tax type" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    try std.testing.expectEqualStrings(
        "Tax type not recorded",
        state.selectedTaxTypeLabel(),
    );

    try std.testing.expect(state.save());
    try std.testing.expectEqualStrings(
        "Tax type not recorded",
        state.selectedTaxTypeLabel(),
    );
    try std.testing.expectEqualStrings("No changes to save.", state.noticeText());
}

test "an attached COR is a checked reference, not a copy" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    publishIo(std.testing.io);
    defer app_io = null;

    var state = State{};
    try workspaceFixture(&state, allocator, &store);

    // A real file on disk, because the point of a reference is that the
    // document stays where the user keeps it.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var full_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const document = try std.fmt.bufPrint(
        &full_buffer,
        ".zig-cache/tmp/{s}/cor.pdf",
        .{tmp.sub_path},
    );
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "cor.pdf",
        .data = "%PDF-1.4 registration",
    });

    try std.testing.expectEqual(State.CorEvidenceState.none, state.corEvidenceState());
    try std.testing.expect(state.attachCorDocument(document));
    try std.testing.expectEqual(State.CorEvidenceState.on_file, state.corEvidenceState());
    try std.testing.expectEqualStrings("cor.pdf", state.corFileName());

    // Nothing was copied: only a reference and a digest were recorded.
    var stored = (try store.getLatestCorDocument(
        allocator,
        state.selectedProfileId().?,
    )).?;
    defer stored.deinit(allocator);
    try std.testing.expectEqualStrings(document, stored.file_path);
    try std.testing.expectEqual(@as(u64, 21), stored.byte_size);
    try std.testing.expectEqual(@as(usize, 64), stored.sha256.len);

    // Editing the document behind the reference is detectable, which is the
    // whole reason the digest is stored.
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "cor.pdf",
        .data = "%PDF-1.4 tampered!!!!",
    });
    state.refreshCorEvidence();
    try std.testing.expectEqual(State.CorEvidenceState.changed, state.corEvidenceState());

    // So is removing it.
    try tmp.dir.deleteFile(std.testing.io, "cor.pdf");
    state.refreshCorEvidence();
    try std.testing.expectEqual(State.CorEvidenceState.moved, state.corEvidenceState());
}

fn attachTestCor(
    state: *State,
    tmp: *std.testing.TmpDir,
) !void {
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "cor.pdf",
        .data = "%PDF-1.4 registration",
    });
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const document = try std.fmt.bufPrint(
        &buffer,
        ".zig-cache/tmp/{s}/cor.pdf",
        .{tmp.sub_path},
    );
    try std.testing.expect(state.attachCorDocument(document));
}

test "accepting only forms from a COR records no taxpayer change" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    publishIo(std.testing.io);
    defer app_io = null;

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try attachTestCor(&state, &tmp);
    const sequence_before = state.selectedRevisionSequence().?;

    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    state.toggleStagedForm(catalogIndexOf("2551Q"));

    try std.testing.expect(state.beginCorReview());
    state.cor_review_tin.set("123-456-789-00000");
    try std.testing.expectEqual(CorTinMatch.matches, state.corReviewTinMatch());

    // Only the forms are accepted; no detail row is.
    state.toggleCorReviewApplyForms();
    try std.testing.expectEqual(@as(usize, 0), state.corReviewAcceptedCount());
    try std.testing.expect(!state.corReviewApplyBlocked());
    try std.testing.expect(state.applyCorReview());

    // The forms were saved and the taxpayer's history gained nothing, because
    // nothing about the taxpayer changed.
    try std.testing.expectEqual(
        sequence_before,
        state.selectedRevisionSequence().?,
    );
    try std.testing.expect(state.formAvailable(2026, "2551Q"));
    try std.testing.expect(!state.managing_forms);
}

test "accepting details from a COR records one change with its provenance" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    publishIo(std.testing.io);
    defer app_io = null;

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try attachTestCor(&state, &tmp);
    const sequence_before = state.selectedRevisionSequence().?;

    try std.testing.expect(state.beginCorReview());
    state.cor_review_tin.set("123-456-789-00000");
    const address_index = @intFromEnum(CorCandidateField.registered_address);
    state.cor_review_values[address_index].set("Makati City");
    state.toggleCorReviewAccepted(address_index);
    try std.testing.expectEqual(@as(usize, 1), state.corReviewAcceptedCount());
    try std.testing.expect(state.applyCorReview());

    try std.testing.expectEqual(
        sequence_before + 1,
        state.selectedRevisionSequence().?,
    );
    try std.testing.expectEqualStrings("Makati City", state.registered_address.text());

    // The record says where the value came from, so the history can be read
    // back to the document that justified it.
    var current = (try profile_persistence.loadCurrentRevision(
        &store,
        allocator,
        state.selectedProfileDomainId().?,
    )).?;
    defer current.deinit(allocator);
    try std.testing.expectEqual(
        std.meta.Tag(model.RevisionSource).imported,
        std.meta.activeTag(current.revision.source),
    );
    try std.testing.expect(std.mem.startsWith(
        u8,
        current.revision.source.imported.asSlice(),
        "COR cor.pdf sha256:",
    ));

    // Alongside the readable reference, the durable key points at the exact
    // evidence row.
    const linked = (try store.corDocumentIdForRevision(
        allocator,
        state.selectedProfileId().?,
        current.revision.id.asSlice(),
    )).?;
    defer allocator.free(linked);
    try std.testing.expectEqualStrings(state.cor_document_id.text(), linked);
}

test "applying details and forms from a COR is one decision" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    publishIo(std.testing.io);
    defer app_io = null;

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try attachTestCor(&state, &tmp);
    const sequence_before = state.selectedRevisionSequence().?;

    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    state.toggleStagedForm(catalogIndexOf("2551Q"));

    try std.testing.expect(state.beginCorReview());
    state.cor_review_tin.set("123-456-789-00000");
    const address_index = @intFromEnum(CorCandidateField.registered_address);
    state.cor_review_values[address_index].set("Makati City");
    state.toggleCorReviewAccepted(address_index);
    state.toggleCorReviewApplyForms();
    try std.testing.expect(state.applyCorReview());

    // Both halves of the decision landed: the detail change and the staged
    // forms, which the old two-step flow wiped before writing.
    try std.testing.expectEqual(
        sequence_before + 1,
        state.selectedRevisionSequence().?,
    );
    try std.testing.expectEqualStrings(
        "Makati City",
        state.registered_address.text(),
    );
    try std.testing.expect(state.formAvailable(2026, "2551Q"));
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(!state.corReviewOpen());

    var current = (try profile_persistence.loadCurrentRevision(
        &store,
        allocator,
        state.selectedProfileDomainId().?,
    )).?;
    defer current.deinit(allocator);
    const linked = (try store.corDocumentIdForRevision(
        allocator,
        state.selectedProfileId().?,
        current.revision.id.asSlice(),
    )).?;
    defer allocator.free(linked);
    try std.testing.expectEqualStrings(state.cor_document_id.text(), linked);
}

test "a year conflict leaves a COR review unapplied and recoverable" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    publishIo(std.testing.io);
    defer app_io = null;

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try attachTestCor(&state, &tmp);
    const sequence_before = state.selectedRevisionSequence().?;

    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    state.toggleStagedForm(catalogIndexOf("2551Q"));

    try std.testing.expect(state.beginCorReview());
    state.cor_review_tin.set("123-456-789-00000");
    const address_index = @intFromEnum(CorCandidateField.registered_address);
    state.cor_review_values[address_index].set("Makati City");
    state.toggleCorReviewAccepted(address_index);
    state.toggleCorReviewApplyForms();

    // The year is set up in another window while the review is open.
    try store.createFormSet(state.selectedProfileId().?, 2026, &.{});

    // The apply fails as one decision: no revision, review still open, the
    // staged choices intact behind the conflict card.
    try std.testing.expect(!state.applyCorReview());
    try std.testing.expectEqual(
        sequence_before,
        state.selectedRevisionSequence().?,
    );
    try std.testing.expect(state.corReviewOpen());
    try std.testing.expectEqual(YearWorkspaceMode.conflict, state.year_workspace);
    try std.testing.expect(state.managing_forms);
    try std.testing.expect(
        state.staged_forms.isSelected(catalogIndexOf("2551Q")),
    );
}

test "re-applying the same COR decision appends nothing new" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    publishIo(std.testing.io);
    defer app_io = null;

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try attachTestCor(&state, &tmp);

    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    state.toggleStagedForm(catalogIndexOf("2551Q"));

    const address_index = @intFromEnum(CorCandidateField.registered_address);
    try std.testing.expect(state.beginCorReview());
    state.cor_review_tin.set("123-456-789-00000");
    state.cor_review_values[address_index].set("Makati City");
    state.toggleCorReviewAccepted(address_index);
    state.toggleCorReviewApplyForms();
    try std.testing.expect(state.applyCorReview());
    try std.testing.expect(!state.managing_forms);
    const sequence_after_first = state.selectedRevisionSequence().?;

    // The same decision again — same value, same document — records nothing:
    // the history logs events, not repetitions.
    try std.testing.expect(state.beginCorReview());
    state.cor_review_tin.set("123-456-789-00000");
    state.cor_review_values[address_index].set("Makati City");
    state.toggleCorReviewAccepted(address_index);
    state.toggleCorReviewApplyForms();
    try std.testing.expect(state.applyCorReview());
    try std.testing.expectEqual(
        sequence_after_first,
        state.selectedRevisionSequence().?,
    );
    try std.testing.expect(state.formAvailable(2026, "2551Q"));
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(!state.corReviewOpen());
}

fn configuredYearFixture(
    state: *State,
    allocator: std.mem.Allocator,
    store: *persistence.Store,
) !void {
    try workspaceFixture(state, allocator, store);
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    state.toggleStagedForm(catalogIndexOf("2551Q"));
    try std.testing.expect(state.saveYearWorkspace());
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
}

test "a mid-year change is recorded without touching the year's saved setup" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    var state = State{};
    try configuredYearFixture(&state, allocator, &store);

    try std.testing.expect(state.beginManageForms());
    state.toggleStagedForm(catalogIndexOf("2550Q"));
    state.chooseApplyFromDate();
    state.change_effective_from.set("2026-07-01");
    try std.testing.expect(state.saveYearWorkspace());

    // The year's base setup did not move; the recorded change lives beside
    // it and answers only date-scoped resolution.
    const profile_id = state.selectedProfileId().?;
    var base = try store.resolveFormSet(allocator, profile_id, 2026);
    defer base.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), base.forms.items.len);
    try std.testing.expectEqualStrings(
        "2551Q",
        base.forms.items[0].form_code,
    );
    var dated = try store.resolveFormSetOn(allocator, profile_id, "2026-07-01");
    defer dated.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), dated.forms.items.len);
}

test "recording a mid-year change leaves the workspace showing the saved year" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    var state = State{};
    try configuredYearFixture(&state, allocator, &store);

    try std.testing.expect(state.beginManageForms());
    state.toggleStagedForm(catalogIndexOf("2550Q"));
    state.chooseApplyFromDate();
    state.change_effective_from.set("2026-07-01");
    try std.testing.expect(state.saveYearWorkspace());

    // The catalog snaps back to the saved year — zero unsaved changes, or
    // the record would read as a lost save — while the review list and the
    // notice carry what was recorded.
    try std.testing.expectEqual(@as(usize, 0), state.changedFormCount());
    try std.testing.expectEqual(FormsApplyScope.whole_year, state.forms_apply_scope);
    try std.testing.expectEqual(YearWorkspaceMode.viewing, state.year_workspace);
    try std.testing.expect(!state.managing_forms);
    try std.testing.expectEqual(@as(usize, 1), state.formSetIntervals().len);
    try std.testing.expectEqualStrings(
        "2026-07-01",
        &state.formSetIntervals()[0].effective_from,
    );
    try std.testing.expectEqual(@as(usize, 2), state.formSetIntervals()[0].form_count);
    try std.testing.expectEqualStrings(
        "Mid-year change recorded · 2 forms from 2026-07-01. Deadlines still follow the year's saved setup.",
        state.noticeText(),
    );
}

test "a second recorded change over the same days is refused in plain words" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    var state = State{};
    try configuredYearFixture(&state, allocator, &store);

    try std.testing.expect(state.beginManageForms());
    state.chooseApplyFromDate();
    state.change_effective_from.set("2026-07-01");
    try std.testing.expect(state.saveYearWorkspace());

    // The recorded change runs open through year end, so any later date in
    // the year collides with it — said plainly, not as a constraint name.
    try std.testing.expect(!state.managing_forms);
    try std.testing.expect(state.beginManageForms());
    state.chooseApplyFromDate();
    state.change_effective_from.set("2026-10-01");
    try std.testing.expect(!state.saveYearWorkspace());
    try std.testing.expectEqualStrings(
        "A change recorded from 2026-07-01 already covers those days. 2026 can hold one recorded change per day.",
        state.noticeText(),
    );
    try std.testing.expectEqual(@as(usize, 1), state.formSetIntervals().len);
}

test "a change dated outside the open year never reaches the store" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    var state = State{};
    try configuredYearFixture(&state, allocator, &store);

    try std.testing.expect(state.beginManageForms());
    state.chooseApplyFromDate();
    state.change_effective_from.set("2025-07-01");
    try std.testing.expect(!state.saveYearWorkspace());
    try std.testing.expectEqualStrings(
        "That date isn't in 2026. Record the change in the year it belongs to.",
        state.noticeText(),
    );
    const profile_id = state.selectedProfileId().?;
    var this_year = try store.listFormSetIntervals(allocator, profile_id, 2026);
    defer this_year.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), this_year.items.len);
    var other_year = try store.listFormSetIntervals(allocator, profile_id, 2025);
    defer other_year.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), other_year.items.len);
}

test "an invalid change date is named, not swallowed" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    var state = State{};
    try configuredYearFixture(&state, allocator, &store);

    try std.testing.expect(state.beginManageForms());
    state.chooseApplyFromDate();
    try std.testing.expect(!state.saveYearWorkspace());
    try std.testing.expectEqualStrings(
        "Enter the date the change took effect as YYYY-MM-DD.",
        state.noticeText(),
    );

    state.chooseApplyFromDate();
    state.change_effective_from.set("2026-13-40");
    try std.testing.expect(!state.saveYearWorkspace());
    try std.testing.expectEqualStrings(
        "Enter the date the change took effect as YYYY-MM-DD.",
        state.noticeText(),
    );
}

test "a COR for another taxpayer cannot change this one" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    publishIo(std.testing.io);
    defer app_io = null;

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try attachTestCor(&state, &tmp);
    const sequence_before = state.selectedRevisionSequence().?;

    try std.testing.expect(state.beginCorReview());
    state.cor_review_tin.set("987-654-321-000");
    const address_index = @intFromEnum(CorCandidateField.registered_address);
    state.cor_review_values[address_index].set("Somewhere Else");
    state.toggleCorReviewAccepted(address_index);

    // A document naming a different taxpayer has no path to this one, no
    // matter what has been accepted.
    try std.testing.expectEqual(CorTinMatch.mismatched, state.corReviewTinMatch());
    try std.testing.expect(state.corReviewApplyBlocked());
    try std.testing.expect(!state.applyCorReview());
    try std.testing.expectEqual(
        sequence_before,
        state.selectedRevisionSequence().?,
    );
    try std.testing.expectEqualStrings("Quezon City", state.registered_address.text());
}

test "a COR must be a document, not any file" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    publishIo(std.testing.io);
    defer app_io = null;

    var state = State{};
    try workspaceFixture(&state, allocator, &store);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var full_buffer: [std.fs.max_path_bytes]u8 = undefined;

    // The extension claims a PDF; the bytes do not. Signatures decide.
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "notes.pdf",
        .data = "just some text",
    });
    const disguised = try std.fmt.bufPrint(
        &full_buffer,
        ".zig-cache/tmp/{s}/notes.pdf",
        .{tmp.sub_path},
    );
    try std.testing.expect(!state.attachCorDocument(disguised));
    try std.testing.expectEqualStrings(
        "A COR must be a PDF or an image.",
        state.noticeText(),
    );
    try std.testing.expectEqual(State.CorEvidenceState.none, state.corEvidenceState());

    var missing_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const missing = try std.fmt.bufPrint(
        &missing_buffer,
        ".zig-cache/tmp/{s}/absent.pdf",
        .{tmp.sub_path},
    );
    try std.testing.expect(!state.attachCorDocument(missing));
    try std.testing.expect(state.noticeFailure());

    try std.testing.expect(
        (try store.getLatestCorDocument(allocator, state.selectedProfileId().?)) == null,
    );
}

test "reformatting a value is not a change worth recording" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    state.phone.set("+639171234567");
    try std.testing.expect(state.save());
    try std.testing.expectEqual(@as(u32, 2), state.selectedRevisionSequence().?);

    // The same TIN written the way it is normally printed parses to the same
    // canonical value, so appending would record a change nobody made.
    state.tin.set("12345678900000");
    try std.testing.expect(state.factsDirty());
    try std.testing.expect(state.save());
    try std.testing.expectEqualStrings("No changes to save.", state.noticeText());
    try std.testing.expectEqual(@as(u32, 2), state.selectedRevisionSequence().?);

    // A genuinely different value still appends.
    state.phone.set("+639179999999");
    try std.testing.expect(state.save());
    try std.testing.expectEqual(@as(u32, 3), state.selectedRevisionSequence().?);
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
    state.useExactEffectiveDates();
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
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("Recently Registered Taxpayer");
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&state);
    state.selectEffectiveStartYear(2026);
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
    state.selectEffectiveStartYear(2023);
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
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("Mid Year Registrant");
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&state);
    state.useExactEffectiveDates();
    state.effective_from.set("2026-08-04");
    try std.testing.expect(state.save());

    // No details on 1 January is normal for a taxpayer registered in August.
    state.refreshFactsSummary(2026);
    try std.testing.expect(!state.factsMissingForYear());
    try std.testing.expect(state.openYearWorkspace(2026));
    try std.testing.expect(state.chooseDraftEmpty());
    try std.testing.expect(state.saveYearWorkspace());
}

test "a branch reuses safe details and clears branch-specific base facts" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    state.phone.set("+639171234567");
    state.email.set("head@example.ph");
    state.primary_line_of_business.set("Retail");
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
    state.setAccountingPeriodBasis(.calendar);

    // The taxpayer's own details carry over.
    try std.testing.expectEqualStrings("123-456-789", state.tin.text());
    try std.testing.expectEqualStrings("Workspace Taxpayer", state.display_name.text());
    try std.testing.expectEqualStrings("+639171234567", state.phone.text());
    try std.testing.expectEqualStrings("head@example.ph", state.email.text());
    try std.testing.expectEqualStrings("1990-01-02", state.birth_date.text());
    try std.testing.expectEqualStrings("Filipino", state.citizenship.text());
    // Everything branch-specific starts blank so it must be reviewed.
    try std.testing.expectEqualStrings("", state.rdo.text());
    try std.testing.expectEqualStrings("", state.registered_address.text());
    try std.testing.expectEqualStrings("", state.zip_code.text());
    try std.testing.expectEqualStrings(
        "",
        state.primary_line_of_business.text(),
    );

    // Saving without a branch code would create a duplicate registration.
    state.rdo.set("043");
    state.registered_address.set("Makati City");
    state.zip_code.set("1200");
    try std.testing.expect(!state.save());
    try std.testing.expect(state.noticeFailure());

    state.tin.set("123-456-789-00002");
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
    state.setAccountingPeriodBasis(.calendar);

    state.rdo.set("043");
    state.registered_address.set("Makati City");
    state.zip_code.set("1200");
    state.tin.set("123-456-789-00002");
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
    state.setAccountingPeriodBasis(.calendar);

    state.rdo.set("043");
    state.registered_address.set("Makati City");
    state.zip_code.set("1200");
    state.tin.set("999-888-777-00002");
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
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("Same TIN Again");
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&state);
    state.selectEffectiveStartYear(2026);
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
    state.tin.set("123-456-789-00000");
    state.rdo.set("040");
    state.display_name.set("Different Taxpayer Same TIN");
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&state);
    state.selectEffectiveStartYear(2020);
    try std.testing.expect(!state.save());
    try std.testing.expectEqualStrings(
        "That TIN belongs to Workspace Taxpayer, which is archived. Restore it instead of adding it again.",
        state.noticeText(),
    );
    try std.testing.expectEqual(@as(usize, 0), state.rows().len);

    // The store knows the owner independently of the loaded rows.
    var owner = (try store.findProfileWithCanonicalTin(
        allocator,
        "12345678900000",
        null,
    )).?;
    defer owner.deinit(allocator);
    try std.testing.expectEqual(persistence.ProfileStatus.archived, owner.status);
    try std.testing.expectEqualStrings("Workspace Taxpayer", owner.display_name.?);
}

test "searching narrows the view without stealing the selection" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    state.startNew();
    state.tin.set("987-654-321-00000");
    state.rdo.set("040");
    state.display_name.set("Beta Other Taxpayer");
    state.registered_address.set("Quezon City");
    setRequiredIndividualDetailsForTest(&state);
    state.selectEffectiveStartYear(2020);
    try std.testing.expect(state.save());

    // Select the first taxpayer, then search for the other one.
    for (state.rows()) |*row| {
        if (std.mem.eql(u8, row.name.text(), "Workspace Taxpayer")) {
            try state.selectSlot(row.slot);
        }
    }
    try std.testing.expectEqualStrings("Workspace Taxpayer", state.selectedName());

    state.setSidebarQuery("Beta");
    try std.testing.expectEqual(@as(usize, 1), state.rows().len);
    try std.testing.expectEqualStrings("Beta Other Taxpayer", state.rows()[0].name.text());
    // The view narrowed; the selection did not move, and the header still
    // names the selected taxpayer even though their row is not loaded.
    try std.testing.expect(state.has_selection);
    try std.testing.expectEqualStrings("Workspace Taxpayer", state.selectedName());
    try std.testing.expectEqualStrings("12345678900000", state.selectedTin());

    // A search matching nobody is a narrow view, not a lost selection.
    state.setSidebarQuery("Nobody With This Name");
    try std.testing.expectEqual(@as(usize, 0), state.rows().len);
    try std.testing.expect(state.has_selection);
    try std.testing.expectEqualStrings("Workspace Taxpayer", state.selectedName());

    // TIN fragments find taxpayers however the digits were punctuated.
    state.setSidebarQuery("654-321");
    try std.testing.expectEqual(@as(usize, 1), state.rows().len);
    try std.testing.expectEqualStrings("Beta Other Taxpayer", state.rows()[0].name.text());

    state.setSidebarQuery("");
    try std.testing.expectEqual(@as(usize, 2), state.rows().len);
    try std.testing.expectEqualStrings("Workspace Taxpayer", state.selectedName());
}

test "a taxpayer past the display bound is reachable by search" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    // One more taxpayer than the sidebar will load. Creation goes through the
    // real path so anchors and uniqueness hold for every row.
    var index: usize = 0;
    while (index < max_profiles + 1) : (index += 1) {
        var id_buffer: [64]u8 = undefined;
        var name_buffer: [64]u8 = undefined;
        var tin_buffer: [16]u8 = undefined;
        const revision: model.ProfileRevision = .{
            .profile_id = try model.ProfileId.parse(
                try std.fmt.bufPrint(&id_buffer, "profile-scale-{d:0>4}", .{index}),
            ),
            .id = try model.RevisionId.parse("revision-1"),
            .sequence = 1,
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2020-01-01"),
                null,
            ),
            .source = .manual_entry,
            .identity = .{
                .tin = try fields.Tin.parse(
                    try std.fmt.bufPrint(&tin_buffer, "1{d:0>8}", .{index}),
                ),
                .rdo_code = try fields.RdoCode.parse("040"),
            },
            .contact = .{
                .address = try fields.RegisteredAddress.parse("Quezon City"),
                .zip_code = try fields.ZipCode.parse("1100"),
                .contact_number = try fields.ContactNumber.parse("09171234567"),
                .email_address = try fields.EmailAddress.parse("scale@example.ph"),
            },
            .subject = .{ .individual = .{
                .name = try fields.TaxpayerName.parse(
                    try std.fmt.bufPrint(&name_buffer, "Taxpayer {d:0>4}", .{index}),
                ),
                .date_of_birth = try model.Date.parseIso("1990-01-02"),
                .citizenship = try fields.Citizenship.parse("Filipino"),
            } },
            .accounting_period_basis = .calendar,
        };
        try profile_persistence.createProfileWithRevision(
            &store,
            allocator,
            .active,
            &revision,
        );
    }

    var state = State{};
    try state.attach(allocator, &store, "2026-01-01", 2026);
    try std.testing.expectEqual(max_profiles, state.rows().len);
    try std.testing.expect(state.profileListTruncated());

    // Names sort alphabetically, so the last taxpayer fell past the bound.
    var last_name_buffer: [64]u8 = undefined;
    const last_name = try std.fmt.bufPrint(
        &last_name_buffer,
        "Taxpayer {d:0>4}",
        .{max_profiles},
    );
    var found_in_listing = false;
    for (state.rows()) |*row| {
        if (std.mem.eql(u8, row.name.text(), last_name)) found_in_listing = true;
    }
    try std.testing.expect(!found_in_listing);

    // Search reaches them anyway: the store answers, not the loaded rows.
    state.setSidebarQuery(last_name);
    try std.testing.expectEqual(@as(usize, 1), state.rows().len);
    try std.testing.expectEqualStrings(last_name, state.rows()[0].name.text());
    try std.testing.expect(!state.profileListTruncated());
}

test "a corrected TIN reaches the sidebar and regroups its registrations" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    var owner_storage: [64]u8 = undefined;
    const selected = state.selectedProfileId().?;
    @memcpy(owner_storage[0..selected.len], selected);
    const head_office_id = owner_storage[0..selected.len];

    try std.testing.expect(state.beginAddBranch());
    state.setAccountingPeriodBasis(.calendar);
    state.rdo.set("043");
    state.registered_address.set("Makati City");
    state.zip_code.set("1200");
    state.tin.set("123-456-789-00002");
    try std.testing.expect(state.save());
    try std.testing.expectEqual(@as(usize, 2), state.rows().len);

    // Correcting the head office's TIN is audited and appends no revision, so
    // a sidebar reading the revision would keep the old identifier - and its
    // branch, still on the old root, would keep looking like family.
    _ = try store.recordIdentityCorrection(.{
        .id = "identity-correction-sidebar",
        .profile_id = head_office_id,
        .expected_anchor_sequence = 1,
        .new_canonical_tin = "555-666-777-00000",
        .new_legal_person_class = .natural_person,
        .reason = "clerical correction confirmed by source record",
        .actor_reference = "operator:test-reviewer",
        .recorded_at_unix_seconds = 1_785_369_600,
        .provenance = "synthetic reviewed identity source",
    });
    try state.attach(allocator, &store, "2026-01-01", 2026);

    var corrected: ?*const ProfileRow = null;
    var branch: ?*const ProfileRow = null;
    for (state.rows()) |*row| {
        if (std.mem.eql(u8, row.stable_id.text(), head_office_id)) {
            corrected = row;
        } else {
            branch = row;
        }
    }
    try std.testing.expect(corrected != null);
    try std.testing.expect(branch != null);
    // The sidebar follows the identity, and the two no longer group together
    // because the recorded identities no longer say they belong to one
    // taxpayer.
    try std.testing.expectEqualStrings("55566677700000", corrected.?.tin.text());
    try std.testing.expectEqualStrings("555666777", corrected.?.tinRoot());
    try std.testing.expectEqualStrings("123456789", branch.?.tinRoot());
}

test "profile rows expose head office and branch identity" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try workspaceFixture(&state, allocator, &store);
    try std.testing.expect(state.beginAddBranch());
    state.setAccountingPeriodBasis(.calendar);
    state.rdo.set("043");
    state.registered_address.set("Makati City");
    state.zip_code.set("1200");
    state.tin.set("123-456-789-00002");
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
    try std.testing.expectEqualStrings("00002", branch.?.branchCode());
    try std.testing.expectEqualStrings("Head office", head_office.?.branchLabel(arena));
    try std.testing.expectEqualStrings("Branch 00002", branch.?.branchLabel(arena));
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
