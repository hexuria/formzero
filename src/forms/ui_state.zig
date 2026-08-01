//! Bounded application state for profile-prefilled Native form editors.
//!
//! The state keeps three boundaries explicit:
//!
//! - SQLite revisions are reconstructed through the validated profile
//!   persistence adapter.
//! - Every live form prefill is projected through the generated catalog.
//! - Draft-backed opens resume a recurring original's immutable snapshot and
//!   lock profile-role selectors.
//! - Exact 1701Q uses an explicit projection-only open boundary which never
//!   looks up or persists the older coarse recurring-draft representation.
//!
//! Transaction controls live in separate form-specific states. This module
//! never invents a 2551Q ATC schedule row or rate, but it can atomically carry
//! a caller-validated filing-value slice into draft persistence.

const std = @import("std");
const catalog = @import("generated/catalog.zig");
const catalog_projection = @import("catalog_projection.zig");
const form_persistence = @import("persistence_adapter.zig");
const form_1701q = @import("form_1701q.zig");
const form_2551q = @import("form_2551q.zig");
const ids = @import("id.zig");
const runtime = @import("runtime.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");
const profile_persistence = @import("../tax_profile/persistence_adapter.zig");
const projection = @import("../tax_profile/projection.zig");
const store_module = @import("../tax_profile/store.zig");

pub const max_spouse_candidates = 64;
pub const max_activity_candidates = 32;
pub const max_notice_len = 511;
const reusable_field_count = std.meta.fields(field.ReusableField).len;

comptime {
    if (catalog.editor_count != editor_revisions.len) {
        @compileError("editor_revisions must cover every static catalog form");
    }
    if (reusable_field_count != 16) {
        @compileError("Native value cache must cover the closed 16-field vocabulary");
    }
}

pub const editor_revisions = [_]ids.FormRevision{
    ids.FormRevision.initComptime("0605", "1999-07-ENCS"),
    ids.FormRevision.initComptime("0619E", "2018-01-ENCS"),
    ids.FormRevision.initComptime("0619F", "2018-01-ENCS"),
    ids.FormRevision.initComptime("1601C", "2018-01-ENCS"),
    ids.FormRevision.initComptime("1701", "2018-01-ENCS"),
    ids.FormRevision.initComptime("1701Q", "2018-01-ENCS"),
    ids.FormRevision.initComptime("1702MX", "2018-01-ENCS"),
    ids.FormRevision.initComptime("1702RT", "2018-01-ENCS"),
    ids.FormRevision.initComptime("2550Q", "2024-04-ENCS"),
    ids.FormRevision.initComptime("2551Q", "2018-01-ENCS"),
};

pub const NoticeKind = enum {
    none,
    info,
    success,
    warning,
    failure,
};

pub const DraftStatus = enum {
    editing,
    prepared,
    queued,
    submitted,
    confirmed,
    paid,
    cancelled,

    pub fn text(self: DraftStatus) []const u8 {
        return @tagName(self);
    }

    fn parse(raw: []const u8) ?DraftStatus {
        return std.meta.stringToEnum(DraftStatus, raw);
    }
};

pub const DraftDisposition = form_persistence.OpenDisposition;

pub const OpenRequest = struct {
    form: ids.FormRevision,
    filer_profile_id: model.ProfileId,
    spouse_profile_id: ?model.ProfileId = null,
    tax_year: u16,
    quarter: u8,
    /// When omitted, the inclusive calendar-quarter end is used.
    profile_as_of: ?model.Date = null,
};

pub const DraftSaveResult = struct {
    id: ids.DraftId,
    disposition: DraftDisposition,
    status: DraftStatus,
};

pub const SpouseCandidate = struct {
    profile_id: model.ProfileId,
    name: field.TaxpayerName,
    tin: field.Tin,
    subject_kind: model.SubjectKind,
    selected: bool,
};

pub const ActivityCandidate = struct {
    id: model.BusinessActivityId,
    line_of_business: field.LineOfBusiness,
    atc: ?field.Atc,
    effective_on_profile_date: bool,
    selected: bool,
};

pub const Error = error{
    CacheConflict,
    CalendarOnlyForm,
    DraftPersistenceDisabled,
    DraftProfileSnapshotLocked,
    ExistingDraftMismatch,
    InvalidQuarter,
    NoAcceptedProjection,
    NoEffectiveFilerRevision,
    NoEffectiveSpouseRevision,
    NotAttached,
    NotOpen,
    RoleNotLoaded,
    SpouseNotSupported,
    UnsupportedRecurringForm,
    UnknownForm,
    WrongFormRevision,
};

const OpenPolicy = enum {
    draft_backed,
    exact_1701q_projection_only,
};

const RoleValueCache = struct {
    values: [reusable_field_count]?field.Value =
        [_]?field.Value{null} ** reusable_field_count,
    text_buffers: [reusable_field_count][255]u8 = undefined,
    text_lengths: [reusable_field_count]u16 =
        [_]u16{0} ** reusable_field_count,

    fn clear(self: *RoleValueCache) void {
        self.values = [_]?field.Value{null} ** reusable_field_count;
        self.text_lengths = [_]u16{0} ** reusable_field_count;
    }

    fn put(self: *RoleValueCache, value: field.Value) Error!void {
        const index = @intFromEnum(value.field());
        if (self.values[index]) |existing| {
            if (!existing.eql(&value)) return error.CacheConflict;
            return;
        }
        self.values[index] = value;
        const serialized = profile_persistence.serializeValue(
            &value,
            &self.text_buffers[index],
        );
        self.text_lengths[index] = @intCast(serialized.text.len);
    }

    fn get(
        self: *const RoleValueCache,
        reusable_field: field.ReusableField,
    ) ?*const field.Value {
        return if (self.values[@intFromEnum(reusable_field)]) |*value|
            value
        else
            null;
    }

    fn text(
        self: *const RoleValueCache,
        reusable_field: field.ReusableField,
    ) []const u8 {
        const index = @intFromEnum(reusable_field);
        return self.text_buffers[index][0..self.text_lengths[index]];
    }
};

const ActivityCandidateCache = struct {
    items: [max_activity_candidates]ActivityCandidate = undefined,
    len: u8 = 0,
    truncated: bool = false,

    fn clear(self: *ActivityCandidateCache) void {
        self.len = 0;
        self.truncated = false;
    }

    fn slice(self: *const ActivityCandidateCache) []const ActivityCandidate {
        return self.items[0..self.len];
    }
};

pub const State = struct {
    allocator: ?std.mem.Allocator = null,
    store: ?*store_module.Store = null,

    opened_form: ?ids.FormRevision = null,
    opened_tax_year: u16 = 0,
    opened_quarter: u8 = 0,
    opened_profile_as_of: ?model.Date = null,
    selected_filer_id: ?model.ProfileId = null,
    selected_spouse_id: ?model.ProfileId = null,
    selected_filer_activity_id: ?model.BusinessActivityId = null,
    selected_spouse_activity_id: ?model.BusinessActivityId = null,

    filer_revision: ?profile_persistence.OwnedDomainRevision = null,
    spouse_revision: ?profile_persistence.OwnedDomainRevision = null,

    projected_snapshot: ?projection.Snapshot = null,
    projected_bindings: runtime.RoleBindings = .{},
    projection_is_accepted: bool = false,
    projection_issue_count: u16 = 0,
    save_is_disabled: bool = true,
    open_policy: OpenPolicy = .draft_backed,

    filer_cache: RoleValueCache = .{},
    spouse_cache: RoleValueCache = .{},

    spouse_candidate_items: [max_spouse_candidates]SpouseCandidate = undefined,
    spouse_candidate_len: u8 = 0,
    spouse_candidates_truncated: bool = false,
    filer_activity_candidates: ActivityCandidateCache = .{},
    spouse_activity_candidates: ActivityCandidateCache = .{},

    notice_kind_value: NoticeKind = .none,
    notice_buffer: [max_notice_len]u8 = undefined,
    notice_len: u16 = 0,

    persisted_draft_id: ?ids.DraftId = null,
    persisted_draft_disposition: ?DraftDisposition = null,
    persisted_draft_status: ?DraftStatus = null,

    pub fn init(
        allocator: std.mem.Allocator,
        store: *store_module.Store,
    ) State {
        var result: State = .{};
        result.attach(allocator, store);
        return result;
    }

    pub fn attach(
        self: *State,
        allocator: std.mem.Allocator,
        store: *store_module.Store,
    ) void {
        self.deinit();
        self.* = .{
            .allocator = allocator,
            .store = store,
        };
    }

    pub fn deinit(self: *State) void {
        self.clearOwnedRevisions();
        self.* = .{};
    }

    pub fn open(self: *State, request: OpenRequest) !void {
        self.openWithPolicy(request, .draft_backed) catch |err| {
            self.clearOwnedRevisions();
            self.resetOpenData();
            self.setErrorNotice(err);
            return err;
        };
    }

    /// Projects exact 1701Q exclusively from the effective profile revisions
    /// requested by the caller. This boundary never derives or probes the
    /// deterministic ID used by the retired coarse recurring-draft model, and
    /// generic recurring-draft persistence remains disabled for the lifetime
    /// of this open state.
    pub fn openExact1701QProjectionOnly(
        self: *State,
        request: OpenRequest,
    ) !void {
        self.openWithPolicy(
            request,
            .exact_1701q_projection_only,
        ) catch |err| {
            self.clearOwnedRevisions();
            self.resetOpenData();
            self.setErrorNotice(err);
            return err;
        };
    }

    fn openWithPolicy(
        self: *State,
        request: OpenRequest,
        open_policy: OpenPolicy,
    ) !void {
        _ = self.allocator orelse return error.NotAttached;
        _ = self.store orelse return error.NotAttached;
        try validateEditorRevision(request.form);
        try validateQuarter(request.form, request.tax_year, request.quarter);
        if (open_policy == .exact_1701q_projection_only and
            !request.form.eql(&form_1701q.revision))
        {
            return error.WrongFormRevision;
        }

        self.clearOwnedRevisions();
        self.resetOpenData();
        self.open_policy = open_policy;
        self.opened_form = request.form;
        self.opened_tax_year = request.tax_year;
        self.opened_quarter = request.quarter;
        self.opened_profile_as_of = request.profile_as_of orelse
            try quarterEnd(request.tax_year, request.quarter);
        self.selected_filer_id = request.filer_profile_id;
        self.selected_spouse_id = request.spouse_profile_id;

        if (open_policy == .draft_backed and
            try self.openExistingOriginal())
        {
            try self.refreshCandidateCaches();
            self.setNotice(
                .info,
                "Existing draft resumed. Its persisted tax-profile snapshot is authoritative.",
            );
            return;
        }

        const allocator = self.allocator.?;
        const store = self.store.?;
        self.filer_revision = (try profile_persistence.loadEffectiveRevision(
            store,
            allocator,
            request.filer_profile_id,
            self.opened_profile_as_of.?,
        )) orelse return error.NoEffectiveFilerRevision;

        if (request.spouse_profile_id) |spouse_id| {
            if (!supportsSpouse(request.form)) {
                return error.SpouseNotSupported;
            }
            if (request.filer_profile_id.eql(&spouse_id)) {
                self.invalidateProjection();
                self.setNotice(
                    .failure,
                    "Filer and spouse must use different tax profiles.",
                );
                try self.refreshCandidateCaches();
                return;
            }
            self.spouse_revision =
                (try profile_persistence.loadEffectiveRevision(
                    store,
                    allocator,
                    spouse_id,
                    self.opened_profile_as_of.?,
                )) orelse return error.NoEffectiveSpouseRevision;
        }

        try self.refreshCandidateCaches();
        try self.reproject();
    }

    /// Selects or clears the optional spouse role. Both 1701 and 1701Q reject
    /// a profile that is already bound as filer.
    pub fn setSpouseProfile(
        self: *State,
        profile_id: ?model.ProfileId,
    ) !void {
        self.ensureSnapshotMutable() catch |err| {
            self.setErrorNotice(err);
            return err;
        };
        const form = self.opened_form orelse return error.NotOpen;
        if (!supportsSpouse(form)) {
            self.setErrorNotice(error.SpouseNotSupported);
            return error.SpouseNotSupported;
        }
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;

        if (profile_id) |selected| {
            const filer_id = self.selected_filer_id orelse
                return error.NotOpen;
            if (filer_id.eql(&selected)) {
                self.setNotice(
                    .failure,
                    "Filer and spouse must use different tax profiles.",
                );
                return error.FilerAndSpouseMustDiffer;
            }
        }

        if (self.spouse_revision) |*owned| owned.deinit(allocator);
        self.spouse_revision = null;
        self.selected_spouse_activity_id = null;
        self.selected_spouse_id = profile_id;

        if (profile_id) |selected| {
            self.spouse_revision =
                (try profile_persistence.loadEffectiveRevision(
                    store,
                    allocator,
                    selected,
                    self.opened_profile_as_of orelse return error.NotOpen,
                )) orelse {
                    self.invalidateProjection();
                    self.setErrorNotice(error.NoEffectiveSpouseRevision);
                    return error.NoEffectiveSpouseRevision;
                };
        }

        try self.refreshCandidateCaches();
        try self.reproject();
    }

    pub fn clearSpouseProfile(self: *State) !void {
        try self.setSpouseProfile(null);
    }

    /// A null selection restores domain resolution: zero activities yields no
    /// value, one effective activity is unambiguous, and repeated effective
    /// activities are rejected until the user explicitly chooses one.
    pub fn setBusinessActivity(
        self: *State,
        role: ids.Role,
        activity_id: ?model.BusinessActivityId,
    ) !void {
        self.ensureSnapshotMutable() catch |err| {
            self.setErrorNotice(err);
            return err;
        };
        switch (role) {
            .filer => {
                if (self.filer_revision == null) return error.RoleNotLoaded;
                self.selected_filer_activity_id = activity_id;
            },
            .spouse => {
                if (self.spouse_revision == null) return error.RoleNotLoaded;
                self.selected_spouse_activity_id = activity_id;
            },
            else => return error.RoleNotLoaded,
        }
        self.refreshActivityCandidateCaches();
        try self.reproject();
    }

    /// Creates or resumes an original recurring 2551Q/1701Q draft.
    ///
    /// The empty transaction slice is deliberate for profile-only callers.
    /// Form-specific states use `saveRecurringDraftWithValues` instead.
    pub fn saveRecurringDraft(self: *State) !DraftSaveResult {
        return self.saveRecurringDraftInternal(&.{}, false) catch |err| {
            self.setErrorNotice(err);
            return err;
        };
    }

    /// Saves a complete filing-value slice alongside the immutable profile
    /// snapshot. A new draft persists both atomically; an editing draft
    /// replaces only its mutable transaction values atomically.
    pub fn saveRecurringDraftWithValues(
        self: *State,
        transaction_values: []const store_module.DraftValueWrite,
    ) !DraftSaveResult {
        return self.saveRecurringDraftInternal(
            transaction_values,
            true,
        ) catch |err| {
            self.setErrorNotice(err);
            return err;
        };
    }

    fn saveRecurringDraftInternal(
        self: *State,
        transaction_values: []const store_module.DraftValueWrite,
        replace_resumed_values: bool,
    ) !DraftSaveResult {
        if (self.open_policy == .exact_1701q_projection_only) {
            self.setErrorNotice(error.DraftPersistenceDisabled);
            return error.DraftPersistenceDisabled;
        }
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const form = self.opened_form orelse return error.NotOpen;
        if (!isRecurring(form)) {
            self.setErrorNotice(error.UnsupportedRecurringForm);
            return error.UnsupportedRecurringForm;
        }
        if (!self.projection_is_accepted or self.projected_snapshot == null) {
            self.setErrorNotice(error.NoAcceptedProjection);
            return error.NoAcceptedProjection;
        }

        const period = runtime.RecurringQuarter{
            .form = form,
            .tax_year = self.opened_tax_year,
            .quarter = self.opened_quarter,
        };
        var opened = try form_persistence.createOrLoad(
            allocator,
            store,
            .{
                .period = period,
                .role_bindings = &self.projected_bindings,
                .snapshot = &self.projected_snapshot.?,
                .transaction_values = transaction_values,
            },
        );
        defer opened.deinit(allocator);

        const disposition = opened.disposition;
        if (disposition == .resumed and replace_resumed_values) {
            try store.replaceDraftValues(
                opened.draft.id,
                transaction_values,
            );
        }
        try self.adoptPersistedDraft(&opened.draft, disposition);
        const result: DraftSaveResult = .{
            .id = self.persisted_draft_id.?,
            .disposition = disposition,
            .status = self.persisted_draft_status.?,
        };
        self.setNotice(
            if (disposition == .created) .success else .info,
            if (disposition == .created)
                "Draft saved with an immutable tax-profile snapshot."
            else
                "Existing draft resumed. Its persisted tax-profile snapshot remains authoritative.",
        );
        return result;
    }

    pub fn formRevision(self: *const State) ?ids.FormRevision {
        return self.opened_form;
    }

    pub fn profileAsOf(self: *const State) ?model.Date {
        return self.opened_profile_as_of;
    }

    pub fn taxYear(self: *const State) u16 {
        return self.opened_tax_year;
    }

    pub fn quarter(self: *const State) u8 {
        return self.opened_quarter;
    }

    pub fn snapshot(self: *const State) ?*const projection.Snapshot {
        return if (self.projected_snapshot) |*value| value else null;
    }

    pub fn roleBindings(self: *const State) *const runtime.RoleBindings {
        return &self.projected_bindings;
    }

    pub fn roleBinding(
        self: *const State,
        role: ids.Role,
    ) ?*const runtime.RoleRevisionBinding {
        return self.projected_bindings.get(role);
    }

    pub fn projectionAccepted(self: *const State) bool {
        return self.projection_is_accepted;
    }

    pub fn saveDisabled(self: *const State) bool {
        return self.save_is_disabled;
    }

    pub fn profileSnapshotLocked(self: *const State) bool {
        return self.persisted_draft_id != null;
    }

    pub fn projectionIssueCount(self: *const State) u16 {
        return self.projection_issue_count;
    }

    pub fn reusableValue(
        self: *const State,
        role: ids.Role,
        reusable_field: field.ReusableField,
    ) ?*const field.Value {
        return switch (role) {
            .filer => self.filer_cache.get(reusable_field),
            .spouse => self.spouse_cache.get(reusable_field),
            else => null,
        };
    }

    pub fn reusableText(
        self: *const State,
        role: ids.Role,
        reusable_field: field.ReusableField,
    ) []const u8 {
        return switch (role) {
            .filer => self.filer_cache.text(reusable_field),
            .spouse => self.spouse_cache.text(reusable_field),
            else => "",
        };
    }

    pub fn filerText(
        self: *const State,
        reusable_field: field.ReusableField,
    ) []const u8 {
        return self.reusableText(.filer, reusable_field);
    }

    pub fn spouseText(
        self: *const State,
        reusable_field: field.ReusableField,
    ) []const u8 {
        return self.reusableText(.spouse, reusable_field);
    }

    pub fn noticeKind(self: *const State) NoticeKind {
        return self.notice_kind_value;
    }

    pub fn noticeText(self: *const State) []const u8 {
        return self.notice_buffer[0..self.notice_len];
    }

    pub fn draftId(self: *const State) ?ids.DraftId {
        return self.persisted_draft_id;
    }

    pub fn draftDisposition(self: *const State) ?DraftDisposition {
        return self.persisted_draft_disposition;
    }

    pub fn draftStatus(self: *const State) ?DraftStatus {
        return self.persisted_draft_status;
    }

    /// Mints only an opaque exact-workspace identity through the attached
    /// Store's CSPRNG. The caller receives no Store or persistence capability.
    pub fn generateExactWorkspaceId(
        self: *const State,
    ) !store_module.DraftWorkspaceId {
        const store = self.store orelse return error.NotAttached;
        return store.generateDraftWorkspaceId();
    }

    /// Loads the currently opened persisted draft for a form-specific
    /// transaction-state adapter. The caller must return it through
    /// `deinitLoadedDraft`.
    pub fn loadPersistedDraft(
        self: *const State,
    ) !?store_module.OwnedDraft {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const id = self.persisted_draft_id orelse return null;
        return store.getDraft(allocator, id.asSlice());
    }

    pub fn deinitLoadedDraft(
        self: *const State,
        draft: *store_module.OwnedDraft,
    ) void {
        const allocator = self.allocator orelse return;
        draft.deinit(allocator);
    }

    pub fn spouseCandidates(self: *const State) []const SpouseCandidate {
        return self.spouse_candidate_items[0..self.spouse_candidate_len];
    }

    pub fn spouseCandidatesTruncated(self: *const State) bool {
        return self.spouse_candidates_truncated;
    }

    pub fn activityCandidates(
        self: *const State,
        role: ids.Role,
    ) []const ActivityCandidate {
        return switch (role) {
            .filer => self.filer_activity_candidates.slice(),
            .spouse => self.spouse_activity_candidates.slice(),
            else => &.{},
        };
    }

    pub fn activityCandidatesTruncated(
        self: *const State,
        role: ids.Role,
    ) bool {
        return switch (role) {
            .filer => self.filer_activity_candidates.truncated,
            .spouse => self.spouse_activity_candidates.truncated,
            else => false,
        };
    }

    fn openExistingOriginal(self: *State) !bool {
        const form = self.opened_form orelse return false;
        if (!isRecurring(form)) return false;
        const allocator = self.allocator.?;
        const store = self.store.?;
        const filer_id = self.selected_filer_id orelse return false;
        const period: runtime.RecurringQuarter = .{
            .form = form,
            .tax_year = self.opened_tax_year,
            .quarter = self.opened_quarter,
        };
        const id = try form_persistence.originalDraftId(filer_id, period);
        var draft = (try store.getDraft(
            allocator,
            id.asSlice(),
        )) orelse return false;
        defer draft.deinit(allocator);

        if (!std.mem.eql(u8, draft.intent, "original") or
            draft.amendment_of != null)
        {
            return error.ExistingDraftMismatch;
        }
        try self.adoptPersistedDraft(&draft, .resumed);
        return true;
    }

    fn adoptPersistedDraft(
        self: *State,
        draft: *const store_module.OwnedDraft,
        disposition: DraftDisposition,
    ) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const rehydrated = try form_persistence.rehydrate(draft);
        const requested_form = self.opened_form orelse return error.NotOpen;
        const requested_filer = self.selected_filer_id orelse return error.NotOpen;
        if (!rehydrated.period.form.eql(&requested_form) or
            rehydrated.period.tax_year != self.opened_tax_year or
            rehydrated.period.quarter != self.opened_quarter)
        {
            return error.ExistingDraftMismatch;
        }
        const filer_binding = rehydrated.role_bindings.get(.filer) orelse
            return error.ExistingDraftMismatch;
        if (!filer_binding.profile_id.eql(&requested_filer)) {
            return error.ExistingDraftMismatch;
        }

        var loaded_filer = (try profile_persistence.loadRevision(
            store,
            allocator,
            filer_binding.profile_id,
            filer_binding.revision_id,
        )) orelse return error.ExistingDraftMismatch;
        var revisions_transferred = false;
        errdefer if (!revisions_transferred) loaded_filer.deinit(allocator);

        var loaded_spouse: ?profile_persistence.OwnedDomainRevision = null;
        errdefer if (!revisions_transferred) {
            if (loaded_spouse) |*owned| owned.deinit(allocator);
        };
        if (rehydrated.role_bindings.get(.spouse)) |spouse_binding| {
            loaded_spouse = (try profile_persistence.loadRevision(
                store,
                allocator,
                spouse_binding.profile_id,
                spouse_binding.revision_id,
            )) orelse return error.ExistingDraftMismatch;
        }

        self.clearOwnedRevisions();
        self.filer_revision = loaded_filer;
        self.spouse_revision = loaded_spouse;
        revisions_transferred = true;
        self.selected_filer_id = filer_binding.profile_id;
        self.selected_filer_activity_id = filer_binding.business_activity_id;
        if (rehydrated.role_bindings.get(.spouse)) |spouse_binding| {
            self.selected_spouse_id = spouse_binding.profile_id;
            self.selected_spouse_activity_id =
                spouse_binding.business_activity_id;
        } else {
            self.selected_spouse_id = null;
            self.selected_spouse_activity_id = null;
        }
        self.opened_profile_as_of = rehydrated.snapshot.effective_on;
        self.projected_snapshot = rehydrated.snapshot;
        self.projected_bindings = rehydrated.role_bindings;
        self.projection_is_accepted = true;
        self.projection_issue_count = 0;
        try self.cacheSnapshot(&rehydrated.snapshot);
        self.refreshActivityCandidateCaches();

        self.persisted_draft_id = try ids.DraftId.parse(draft.id);
        self.persisted_draft_disposition = disposition;
        self.persisted_draft_status = DraftStatus.parse(draft.lifecycle) orelse
            return error.ExistingDraftMismatch;
        self.save_is_disabled = self.persisted_draft_status.? != .editing;
    }

    fn reproject(self: *State) !void {
        self.invalidateProjection();
        const allocator = self.allocator orelse return error.NotAttached;
        const form = self.opened_form orelse return error.NotOpen;
        const effective_on = self.opened_profile_as_of orelse return error.NotOpen;
        const filer = if (self.filer_revision) |*owned|
            &owned.revision
        else
            return error.RoleNotLoaded;

        var binding_storage: [2]projection.Binding = undefined;
        binding_storage[0] = .{
            .role = .filer,
            .revision = filer,
            .selection = .{
                .business_activity_id = self.selected_filer_activity_id,
            },
        };
        var binding_len: usize = 1;
        if (self.spouse_revision) |*owned| {
            if (filer.profile_id.eql(&owned.revision.profile_id)) {
                self.setNotice(
                    .failure,
                    "Filer and spouse must use different tax profiles.",
                );
                return;
            }
            binding_storage[1] = .{
                .role = .spouse,
                .revision = &owned.revision,
                .selection = .{
                    .business_activity_id = self.selected_spouse_activity_id,
                },
            };
            binding_len = 2;
        }
        const bindings = binding_storage[0..binding_len];

        var result = try catalog_projection.project(
            allocator,
            form,
            bindings,
            effective_on,
        );
        defer result.deinit(allocator);
        switch (result) {
            .rejected => |rejected| {
                self.projection_issue_count =
                    @intCast(@min(rejected.issues.len, std.math.maxInt(u16)));
                self.setProjectionNotice(rejected.slice());
            },
            .accepted => |accepted| {
                var built_snapshot = projection.Snapshot.init(
                    accepted.form,
                    accepted.effective_on,
                );
                for (accepted.slice()) |entry| {
                    try built_snapshot.append(entry);
                }
                self.projected_snapshot = built_snapshot;
                self.projected_bindings =
                    try runtime.RoleBindings.from(bindings);
                try self.cacheSnapshot(&built_snapshot);
                self.projection_is_accepted = true;
                self.save_is_disabled =
                    !isRecurring(form) or
                    self.open_policy == .exact_1701q_projection_only;
                self.setNoticeFmt(
                    .success,
                    "Loaded {d} reusable tax-profile field{s}.",
                    .{
                        built_snapshot.len,
                        if (built_snapshot.len == 1) "" else "s",
                    },
                );
            },
        }
    }

    fn cacheSnapshot(
        self: *State,
        snapshot_value: *const projection.Snapshot,
    ) !void {
        self.filer_cache.clear();
        self.spouse_cache.clear();
        for (snapshot_value.slice()) |entry| {
            switch (entry.role) {
                .filer => try self.filer_cache.put(entry.value),
                .spouse => try self.spouse_cache.put(entry.value),
                else => {},
            }
        }
    }

    fn refreshCandidateCaches(self: *State) !void {
        self.refreshActivityCandidateCaches();
        try self.refreshSpouseCandidates();
    }

    fn refreshActivityCandidateCaches(self: *State) void {
        self.filer_activity_candidates.clear();
        self.spouse_activity_candidates.clear();
        if (self.opened_profile_as_of) |effective_on| {
            if (self.filer_revision) |*owned| {
                fillActivityCandidates(
                    &self.filer_activity_candidates,
                    owned.revision.business_activities,
                    effective_on,
                    self.selected_filer_activity_id,
                );
            }
            if (self.spouse_revision) |*owned| {
                fillActivityCandidates(
                    &self.spouse_activity_candidates,
                    owned.revision.business_activities,
                    effective_on,
                    self.selected_spouse_activity_id,
                );
            }
        }
    }

    fn refreshSpouseCandidates(self: *State) !void {
        self.spouse_candidate_len = 0;
        self.spouse_candidates_truncated = false;
        const form = self.opened_form orelse return;
        const policy = spousePolicy(form) orelse return;
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const effective_on = self.opened_profile_as_of orelse return;
        const filer_id = self.selected_filer_id orelse return;

        var profiles = try store.listProfiles(allocator, false);
        defer profiles.deinit(allocator);
        for (profiles.items) |*summary| {
            const candidate_id = try model.ProfileId.parse(summary.id);
            if (candidate_id.eql(&filer_id)) continue;
            const maybe_revision = try profile_persistence.loadEffectiveRevision(
                store,
                allocator,
                candidate_id,
                effective_on,
            );
            if (maybe_revision == null) continue;
            var owned = maybe_revision.?;
            defer owned.deinit(allocator);
            if (!policyAllowsSubject(policy, owned.revision.subject.kind())) {
                continue;
            }
            if (self.spouse_candidate_len == max_spouse_candidates) {
                self.spouse_candidates_truncated = true;
                continue;
            }
            const index = self.spouse_candidate_len;
            self.spouse_candidate_items[index] = .{
                .profile_id = candidate_id,
                .name = owned.revision.subject.taxpayerName(),
                .tin = owned.revision.identity.tin,
                .subject_kind = owned.revision.subject.kind(),
                .selected = if (self.selected_spouse_id) |selected|
                    selected.eql(&candidate_id)
                else
                    false,
            };
            self.spouse_candidate_len += 1;
        }
    }

    fn ensureSnapshotMutable(self: *const State) Error!void {
        if (self.persisted_draft_id != null) {
            return error.DraftProfileSnapshotLocked;
        }
    }

    fn clearOwnedRevisions(self: *State) void {
        const allocator = self.allocator orelse return;
        if (self.filer_revision) |*owned| owned.deinit(allocator);
        if (self.spouse_revision) |*owned| owned.deinit(allocator);
        self.filer_revision = null;
        self.spouse_revision = null;
    }

    fn resetOpenData(self: *State) void {
        self.open_policy = .draft_backed;
        self.opened_form = null;
        self.opened_tax_year = 0;
        self.opened_quarter = 0;
        self.opened_profile_as_of = null;
        self.selected_filer_id = null;
        self.selected_spouse_id = null;
        self.selected_filer_activity_id = null;
        self.selected_spouse_activity_id = null;
        self.spouse_candidate_len = 0;
        self.spouse_candidates_truncated = false;
        self.filer_activity_candidates.clear();
        self.spouse_activity_candidates.clear();
        self.invalidateProjection();
    }

    fn invalidateProjection(self: *State) void {
        self.projected_snapshot = null;
        self.projected_bindings = .{};
        self.projection_is_accepted = false;
        self.projection_issue_count = 0;
        self.save_is_disabled = true;
        self.filer_cache.clear();
        self.spouse_cache.clear();
        self.persisted_draft_id = null;
        self.persisted_draft_disposition = null;
        self.persisted_draft_status = null;
    }

    fn setProjectionNotice(
        self: *State,
        issues: []const catalog_projection.Issue,
    ) void {
        if (issues.len == 0) {
            self.setNotice(.warning, "Tax-profile projection was rejected.");
            return;
        }
        const first_tag = @tagName(std.meta.activeTag(issues[0]));
        self.setNoticeFmt(
            .warning,
            "Tax-profile projection needs attention: {s} ({d} issue{s}).",
            .{ first_tag, issues.len, if (issues.len == 1) "" else "s" },
        );
    }

    fn setErrorNotice(self: *State, err: anyerror) void {
        self.setNoticeFmt(
            .failure,
            "Tax-profile form state error: {s}.",
            .{@errorName(err)},
        );
    }

    fn setNotice(self: *State, kind: NoticeKind, text: []const u8) void {
        const length = @min(text.len, self.notice_buffer.len);
        @memcpy(self.notice_buffer[0..length], text[0..length]);
        self.notice_len = @intCast(length);
        self.notice_kind_value = kind;
    }

    fn setNoticeFmt(
        self: *State,
        kind: NoticeKind,
        comptime format: []const u8,
        args: anytype,
    ) void {
        const written = std.fmt.bufPrint(
            &self.notice_buffer,
            format,
            args,
        ) catch {
            self.setNotice(kind, "Tax-profile form state changed.");
            return;
        };
        self.notice_len = @intCast(written.len);
        self.notice_kind_value = kind;
    }
};

fn fillActivityCandidates(
    cache: *ActivityCandidateCache,
    activities: []const model.BusinessActivity,
    effective_on: model.Date,
    selected_id: ?model.BusinessActivityId,
) void {
    for (activities) |*activity| {
        if (cache.len == max_activity_candidates) {
            cache.truncated = true;
            continue;
        }
        const selected = if (selected_id) |id| id.eql(&activity.id) else false;
        cache.items[cache.len] = .{
            .id = activity.id,
            .line_of_business = activity.line_of_business,
            .atc = activity.atc,
            .effective_on_profile_date = activity.isEffective(effective_on),
            .selected = selected,
        };
        cache.len += 1;
    }
}

fn validateEditorRevision(form: ids.FormRevision) Error!void {
    const definition = catalog.findForm(form.code.asSlice()) orelse
        return error.UnknownForm;
    if (definition.status != .static_layout) return error.CalendarOnlyForm;
    const revision = definition.revision orelse return error.CalendarOnlyForm;
    if (!std.mem.eql(u8, revision, form.revision.asSlice())) {
        return error.WrongFormRevision;
    }
}

fn validateQuarter(
    form: ids.FormRevision,
    tax_year: u16,
    quarter: u8,
) Error!void {
    if (tax_year == 0 or quarter < 1 or quarter > 4) {
        return error.InvalidQuarter;
    }
    if (form.eql(&form_1701q.revision) and quarter == 4) {
        return error.InvalidQuarter;
    }
}

fn quarterEnd(tax_year: u16, quarter: u8) !model.Date {
    return switch (quarter) {
        1 => model.Date.init(tax_year, 3, 31),
        2 => model.Date.init(tax_year, 6, 30),
        3 => model.Date.init(tax_year, 9, 30),
        4 => model.Date.init(tax_year, 12, 31),
        else => error.InvalidQuarter,
    };
}

fn isRecurring(form: ids.FormRevision) bool {
    return form.eql(&form_2551q.revision) or
        form.eql(&form_1701q.revision);
}

fn supportsSpouse(form: ids.FormRevision) bool {
    return spousePolicy(form) != null;
}

fn spousePolicy(
    form: ids.FormRevision,
) ?*const catalog.ProfileRoleDefinition {
    const definition = catalog.findForm(form.code.asSlice()) orelse return null;
    const revision = definition.revision orelse return null;
    if (!std.mem.eql(u8, revision, form.revision.asSlice())) return null;
    for (definition.profile_roles) |*policy| {
        if (policy.role == .spouse) return policy;
    }
    return null;
}

fn policyAllowsSubject(
    policy: *const catalog.ProfileRoleDefinition,
    subject: model.SubjectKind,
) bool {
    for (policy.allowed_subjects) |allowed| {
        if (catalog_projection.domainSubjectKind(allowed) == subject) {
            return true;
        }
    }
    return false;
}

const TestSubject = enum {
    individual,
    sole_proprietor,
    corporation,
};

fn persistFullTestRevision(
    store: *store_module.Store,
    profile_id: []const u8,
    revision_id: []const u8,
    sequence: u32,
    subject_kind: TestSubject,
    display_name: []const u8,
    tin: []const u8,
) !void {
    const profile_editor = @import("../tax_profile/editor.zig");
    const effective = try model.EffectivePeriod.init(
        try model.Date.parseIso("2020-01-01"),
        null,
    );
    const activities = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("activity-primary"),
        .line_of_business = try field.LineOfBusiness.parse(
            "Software consulting",
        ),
        .atc = try field.Atc.parse("PT010"),
        .effective = effective,
    }};
    const facts = [_]model.RegistrationFact{
        .{
            .id = try model.RegistrationFactId.parse("fact-tax-type"),
            .effective = effective,
            .value = .{
                .tax_type = try field.TaxType.parse("Percentage Tax"),
            },
        },
        .{
            .id = try model.RegistrationFactId.parse("fact-gwa"),
            .effective = effective,
            .value = .{ .government_withholding_agent = .yes },
        },
        .{
            .id = try model.RegistrationFactId.parse("fact-special-rate"),
            .effective = effective,
            .value = .{
                .special_rate_basis = try field.SpecialRateBasis.parse(
                    "Treaty article 7",
                ),
            },
        },
    };
    const base: profile_editor.Base = .{
        .profile_id = try model.ProfileId.parse(profile_id),
        .revision_id = try model.RevisionId.parse(revision_id),
        .sequence = sequence,
        .effective = effective,
        .source = .{ .imported = try field.SourceReference.parse(
            if (sequence == 1) "test-import-v1" else "test-import-v2",
        ) },
        .identity = .{
            .tin = try field.Tin.parse(tin),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse(
                "1 Taxpayer Street, Quezon City",
            ),
            .zip_code = try field.ZipCode.parse("1100"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse(
                "taxpayer@example.ph",
            ),
        },
    };
    const ready: profile_editor.Ready = switch (subject_kind) {
        .individual => profile_editor.begin(base).individual(.{
            .name = try field.TaxpayerName.parse(display_name),
            .date_of_birth = try model.Date.parseIso("1990-01-02"),
            .citizenship = try field.Citizenship.parse("Filipino"),
            .foreign_tax_number = try field.ForeignTaxNumber.parse(
                "FOREIGN-123",
            ),
        }),
        .sole_proprietor => profile_editor.begin(base).soleProprietor(.{
            .person = .{
                .name = try field.TaxpayerName.parse(display_name),
                .date_of_birth = try model.Date.parseIso("1990-01-02"),
                .citizenship = try field.Citizenship.parse("Filipino"),
                .foreign_tax_number = try field.ForeignTaxNumber.parse(
                    "FOREIGN-123",
                ),
            },
            .trade_name = try field.RegisteredName.parse("TEST TRADE NAME"),
        }),
        .corporation => profile_editor.begin(base).legalEntity(.{
            .registered_name = try field.RegisteredName.parse(display_name),
            .kind = .corporation,
        }),
    };
    const revision = try ready
        .withBusinessActivities(&activities)
        .withRegistrationFacts(&facts)
        .build();
    if (sequence == 1) {
        try profile_persistence.createProfileWithRevision(
            store,
            std.testing.allocator,
            .active,
            &revision,
        );
    } else {
        try profile_persistence.appendRevision(
            store,
            std.testing.allocator,
            &revision,
            sequence - 1,
        );
    }
}

test "all ten static editors project catalog profile targets and cache values" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();
    try persistFullTestRevision(
        &store,
        "profile-person",
        "revision-person-1",
        1,
        .sole_proprietor,
        "MARIA SANTOS",
        "123-456-789-000",
    );
    try persistFullTestRevision(
        &store,
        "profile-corporation",
        "revision-corporation-1",
        1,
        .corporation,
        "EXAMPLE CORPORATION",
        "234-567-890-000",
    );
    try persistFullTestRevision(
        &store,
        "profile-spouse",
        "revision-spouse-1",
        1,
        .individual,
        "JUAN SANTOS",
        "345-678-901-000",
    );

    var state = State.init(allocator, &store);
    defer state.deinit();
    const person = try model.ProfileId.parse("profile-person");
    const corporation = try model.ProfileId.parse("profile-corporation");
    for (editor_revisions) |form| {
        const filer = if (std.mem.startsWith(
            u8,
            form.code.asSlice(),
            "1702",
        ))
            corporation
        else
            person;
        try state.open(.{
            .form = form,
            .filer_profile_id = filer,
            .tax_year = 2026,
            .quarter = 1,
        });
        try std.testing.expect(state.projectionAccepted());
        try std.testing.expect(state.snapshot().?.len > 0);
        try std.testing.expectEqual(
            @as(u32, 1),
            state.roleBinding(.filer).?.revision_sequence,
        );
    }

    try state.open(.{
        .form = editor_revisions[0],
        .filer_profile_id = person,
        .tax_year = 2026,
        .quarter = 1,
    });
    try std.testing.expectEqualStrings(
        "123456789000",
        state.filerText(.tin),
    );
    try std.testing.expectEqualStrings(
        "MARIA SANTOS",
        state.filerText(.taxpayer_name),
    );
    try std.testing.expectEqualStrings(
        "Software consulting",
        state.filerText(.line_of_business),
    );
    try std.testing.expectEqualStrings("PT010", state.filerText(.atc));
    try std.testing.expectEqual(@as(usize, 1), state.activityCandidates(.filer).len);

    try state.open(.{
        .form = editor_revisions[4],
        .filer_profile_id = person,
        .tax_year = 2026,
        .quarter = 1,
    });
    try std.testing.expectEqual(@as(usize, 1), state.spouseCandidates().len);
    try std.testing.expectEqualStrings(
        "JUAN SANTOS",
        state.spouseCandidates()[0].name.asSlice(),
    );
}

test "2551Q saves exactly seven fields and open immediately resumes immutable snapshot" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();
    try persistFullTestRevision(
        &store,
        "profile-2551q",
        "revision-2551q-1",
        1,
        .sole_proprietor,
        "OLD TAXPAYER NAME",
        "456-789-012-000",
    );
    const profile_id = try model.ProfileId.parse("profile-2551q");

    var state = State.init(allocator, &store);
    try state.open(.{
        .form = form_2551q.revision,
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 1,
    });
    try std.testing.expectEqual(@as(u8, 7), state.snapshot().?.len);
    const initial_values = [_]store_module.DraftValueWrite{.{
        .field_id = "2551Q.schedule.row-a.rate",
        .value_text = "3.00",
        .provenance = "external_policy",
    }};
    const created = try state.saveRecurringDraftWithValues(&initial_values);
    try std.testing.expectEqual(DraftDisposition.created, created.disposition);
    try std.testing.expect(state.profileSnapshotLocked());
    const created_id = created.id;
    state.deinit();

    var stored = (try store.getDraft(
        allocator,
        created_id.asSlice(),
    )).?;
    defer stored.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 7), stored.snapshots.len);
    try std.testing.expectEqual(@as(usize, 1), stored.bindings.len);
    try std.testing.expectEqual(@as(usize, 1), stored.values.len);
    try std.testing.expectEqualStrings(
        "3.00",
        stored.values[0].value_text,
    );
    try std.testing.expectEqualStrings("2026-03-31", stored.profile_as_of);

    try persistFullTestRevision(
        &store,
        "profile-2551q",
        "revision-2551q-2",
        2,
        .sole_proprietor,
        "NEW TAXPAYER NAME",
        "456-789-012-000",
    );
    var resumed_state = State.init(allocator, &store);
    defer resumed_state.deinit();
    try resumed_state.open(.{
        .form = form_2551q.revision,
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 1,
    });
    try std.testing.expectEqual(
        DraftDisposition.resumed,
        resumed_state.draftDisposition().?,
    );
    try std.testing.expectEqualStrings(
        "OLD TAXPAYER NAME",
        resumed_state.filerText(.taxpayer_name),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        resumed_state.roleBinding(.filer).?.revision_sequence,
    );
    try std.testing.expectError(
        error.DraftProfileSnapshotLocked,
        resumed_state.setBusinessActivity(.filer, null),
    );
    const updated_values = [_]store_module.DraftValueWrite{.{
        .field_id = "2551Q.schedule.row-a.rate",
        .value_text = "5.00",
        .provenance = "external_policy",
    }};
    const resumed = try resumed_state.saveRecurringDraftWithValues(
        &updated_values,
    );
    try std.testing.expectEqual(DraftDisposition.resumed, resumed.disposition);
    var updated = (try store.getDraft(
        allocator,
        resumed.id.asSlice(),
    )).?;
    defer updated.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), updated.values.len);
    try std.testing.expectEqualStrings("5.00", updated.values[0].value_text);
}

test "failed period validation clears prior form context instead of leaking it" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();
    try persistFullTestRevision(
        &store,
        "profile-period",
        "revision-period-1",
        1,
        .sole_proprietor,
        "PERIOD TAXPAYER",
        "789-012-345-000",
    );
    const filer = try model.ProfileId.parse("profile-period");

    var state = State.init(allocator, &store);
    defer state.deinit();
    try state.open(.{
        .form = form_2551q.revision,
        .filer_profile_id = filer,
        .tax_year = 2026,
        .quarter = 1,
    });
    try std.testing.expect(state.formRevision() != null);

    try std.testing.expectError(
        error.InvalidQuarter,
        state.open(.{
            .form = form_1701q.revision,
            .filer_profile_id = filer,
            .tax_year = 2026,
            .quarter = 4,
        }),
    );
    try std.testing.expect(state.formRevision() == null);
    try std.testing.expect(!state.projectionAccepted());
    try std.testing.expectEqual(@as(usize, 0), state.spouseCandidates().len);
    try std.testing.expectEqual(NoticeKind.failure, state.noticeKind());
}

test "1701Q optional spouse persists named role and same profile is rejected for both income forms" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();
    try persistFullTestRevision(
        &store,
        "profile-filer",
        "revision-filer-1",
        1,
        .sole_proprietor,
        "MARIA DELA CRUZ",
        "567-890-123-000",
    );
    try persistFullTestRevision(
        &store,
        "profile-spouse",
        "revision-spouse-1",
        1,
        .individual,
        "JUAN DELA CRUZ",
        "678-901-234-000",
    );
    const filer = try model.ProfileId.parse("profile-filer");
    const spouse = try model.ProfileId.parse("profile-spouse");

    var state = State.init(allocator, &store);
    defer state.deinit();
    try state.open(.{
        .form = form_1701q.revision,
        .filer_profile_id = filer,
        .tax_year = 2026,
        .quarter = 2,
    });
    try std.testing.expect(state.projectionAccepted());
    try std.testing.expect(state.roleBinding(.spouse) == null);
    try state.setSpouseProfile(spouse);
    try std.testing.expect(state.projectionAccepted());
    try std.testing.expect(state.roleBinding(.spouse) != null);
    try std.testing.expectEqualStrings(
        "JUAN DELA CRUZ",
        state.spouseText(.taxpayer_name),
    );
    const saved = try state.saveRecurringDraft();
    var draft = (try store.getDraft(allocator, saved.id.asSlice())).?;
    defer draft.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), draft.bindings.len);
    try std.testing.expectEqual(@as(usize, 0), draft.values.len);

    var rejected = State.init(allocator, &store);
    defer rejected.deinit();
    try rejected.open(.{
        .form = form_1701q.revision,
        .filer_profile_id = filer,
        .tax_year = 2026,
        .quarter = 3,
    });
    try std.testing.expectError(
        error.FilerAndSpouseMustDiffer,
        rejected.setSpouseProfile(filer),
    );
    try std.testing.expect(rejected.projectionAccepted());
    try std.testing.expect(rejected.roleBinding(.spouse) == null);
    try std.testing.expectEqual(NoticeKind.failure, rejected.noticeKind());

    try rejected.open(.{
        .form = editor_revisions[4],
        .filer_profile_id = filer,
        .spouse_profile_id = filer,
        .tax_year = 2026,
        .quarter = 1,
    });
    try std.testing.expect(!rejected.projectionAccepted());
    try std.testing.expectEqual(NoticeKind.failure, rejected.noticeKind());
}
