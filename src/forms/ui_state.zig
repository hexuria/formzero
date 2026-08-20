//! Bounded application state for profile-prefilled Native form editors.
//!
//! The state keeps three boundaries explicit:
//!
//! - SQLite revisions are reconstructed through the validated profile
//!   persistence adapter.
//! - Every live form prefill is projected through the generated catalog.
//! - Draft-backed opens resume a recurring original's immutable snapshot and
//!   lock profile-role selectors.
//! - Exact 1701Q uses an explicit projection-only open boundary. Draft-backed
//!   open and recurring-draft persistence are retired for 1701Q.
//!
//! Transaction controls live in separate form-specific states. This module
//! never invents a 2551Q ATC schedule row or rate, but it can atomically carry
//! a caller-validated filing-value slice into draft persistence.

const std = @import("std");
const catalog = @import("generated/catalog.zig");
const catalog_projection = @import("catalog_projection.zig");
const draft_provenance_runtime = @import("draft_provenance_runtime.zig");
const form_persistence = @import("persistence_adapter.zig");
const form_1701q = @import("form_1701q.zig");
const form_2551q = @import("form_2551q.zig");
const ids = @import("id.zig");
const runtime = @import("runtime.zig");
const filing_period = @import("filing_period.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");
const profile_persistence = @import("../tax_profile/persistence_adapter.zig");
const projection = @import("../tax_profile/projection.zig");
const store_module = @import("../tax_profile/store.zig");
const tax_form_profile = @import("../tax_profile/tax_form_profile.zig");

pub const max_spouse_candidates = 64;
pub const max_notice_len = 511;
const reusable_field_count = std.meta.fields(field.ReusableField).len;

comptime {
    if (catalog.editor_count != editor_revisions.len) {
        @compileError("editor_revisions must cover every static catalog form");
    }
    if (reusable_field_count != 18) {
        @compileError("Native value cache must cover the closed 18-field vocabulary");
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

/// Exact provenance is mandatory for drafts created by the current runtime.
/// A real pre-v17 draft remains usable but is reported explicitly; it is
/// never upgraded from today's mutable profile state during resume.
pub const DraftProvenanceStatus = enum {
    exact,
    legacy_absent,
};

pub const OpenRequest = struct {
    form: ids.FormRevision,
    filer_profile_id: model.ProfileId,
    spouse_profile_id: ?model.ProfileId = null,
    tax_year: u16,
    quarter: u8,
    /// Optional cadence-aware identity supplied by the Tax Form Library. The
    /// quarter field remains for compatibility with the two existing
    /// recurring editors and is derived from this value when present.
    filing_period: ?filing_period.FilingPeriod = null,
    /// When omitted, the inclusive calendar-quarter end is used.
    profile_as_of: ?model.Date = null,
};

/// Read-only result used by the profile-scoped Tax Form Library before an
/// editor is mounted.  The application owns Forms Set membership; this type
/// only answers whether the selected profile can satisfy the editor's
/// generated profile projection for the requested period.
pub const LaunchStatus = enum {
    inactive,
    missing_base_profile,
    missing_tax_form_profile,
    unsupported_period,
    ready_new,
    ready_resume,
};

pub const LaunchBlocker = enum {
    none,
    missing_profile_data,
    missing_effective_revision,
    missing_tax_form_profile_data,
    missing_binding,
    invalid_revision,
    revision_not_effective,
    persistence_error,
};

pub const LaunchAssessment = struct {
    status: LaunchStatus = .inactive,
    blocker: LaunchBlocker = .none,
    issue_count: u16 = 0,
    first_missing_field: ?field.ReusableField = null,
    missing_base_fields: [std.meta.fields(field.ReusableField).len]field.ReusableField = undefined,
    missing_base_field_count: u8 = 0,

    pub fn ready(self: *const LaunchAssessment) bool {
        return self.status == .ready_new or
            self.status == .ready_resume;
    }

    pub fn missingBaseFields(self: *const LaunchAssessment) []const field.ReusableField {
        return self.missing_base_fields[0..self.missing_base_field_count];
    }

    fn addMissingBaseField(
        self: *LaunchAssessment,
        reusable_field: field.ReusableField,
    ) void {
        for (self.missingBaseFields()) |existing| {
            if (existing == reusable_field) return;
        }
        if (self.missing_base_field_count >= self.missing_base_fields.len) return;
        self.missing_base_fields[self.missing_base_field_count] = reusable_field;
        self.missing_base_field_count += 1;
        if (self.first_missing_field == null) {
            self.first_missing_field = reusable_field;
        }
    }
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

pub const Error = error{
    CacheConflict,
    CalendarOnlyForm,
    DraftProvenanceCorrupt,
    DraftPersistenceDisabled,
    DraftProfileSnapshotLocked,
    ExistingDraftMismatch,
    InvalidPeriod,
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

pub const State = struct {
    allocator: ?std.mem.Allocator = null,
    store: ?*store_module.Store = null,

    opened_form: ?ids.FormRevision = null,
    opened_tax_year: u16 = 0,
    opened_quarter: u8 = 0,
    opened_filing_period: ?filing_period.FilingPeriod = null,
    opened_profile_as_of: ?model.Date = null,
    selected_filer_id: ?model.ProfileId = null,
    selected_spouse_id: ?model.ProfileId = null,

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

    notice_kind_value: NoticeKind = .none,
    notice_buffer: [max_notice_len]u8 = undefined,
    notice_len: u16 = 0,

    persisted_draft_id: ?ids.DraftId = null,
    persisted_draft_disposition: ?DraftDisposition = null,
    persisted_draft_status: ?DraftStatus = null,
    persisted_draft_provenance: ?DraftProvenanceStatus = null,

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

    /// Opens the exact persisted draft selected by a caller-owned summary.
    /// The adopted draft must still match the requested form, filing period,
    /// and filer role; `adoptPersistedDraft` rejects every mismatch before the
    /// editor receives persisted values. Exact 1701Q remains projection-only.
    pub fn openPersistedDraft(
        self: *State,
        request: OpenRequest,
        draft_id: ids.DraftId,
    ) !void {
        self.openPersistedDraftInner(request, draft_id) catch |err| {
            self.clearOwnedRevisions();
            self.resetOpenData();
            self.setErrorNotice(err);
            return err;
        };
    }

    fn openPersistedDraftInner(
        self: *State,
        request: OpenRequest,
        draft_id: ids.DraftId,
    ) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        if (request.form.eql(&form_1701q.revision)) {
            return error.DraftPersistenceDisabled;
        }
        try validateEditorRevision(request.form);
        const request_quarter = try validateRequestPeriod(request);

        self.clearOwnedRevisions();
        self.resetOpenData();
        self.open_policy = .draft_backed;
        self.opened_form = request.form;
        self.opened_tax_year = request.tax_year;
        self.opened_quarter = request_quarter;
        self.opened_filing_period = request.filing_period orelse
            .{ .quarterly = .{
                .tax_year = request.tax_year,
                .quarter = request_quarter,
            } };
        self.opened_profile_as_of = request.profile_as_of orelse
            try filingPeriodEnd(self.opened_filing_period.?);
        self.selected_filer_id = request.filer_profile_id;
        self.selected_spouse_id = request.spouse_profile_id;

        var draft = (try store.getDraft(
            allocator,
            draft_id.asSlice(),
        )) orelse return error.NotFound;
        defer draft.deinit(allocator);
        const provenance_status = try loadPersistedDraftProvenanceStatus(
            store,
            allocator,
            draft_id,
        );
        try self.adoptPersistedDraft(&draft, .resumed);
        self.persisted_draft_provenance = provenance_status;
        try self.refreshSpouseCandidates();
        self.setDraftSavedNotice(.resumed, provenance_status);
    }

    fn openWithPolicy(
        self: *State,
        request: OpenRequest,
        open_policy: OpenPolicy,
    ) !void {
        _ = self.allocator orelse return error.NotAttached;
        _ = self.store orelse return error.NotAttached;
        try validateEditorRevision(request.form);
        const request_quarter = try validateRequestPeriod(request);
        if (open_policy == .exact_1701q_projection_only and
            !request.form.eql(&form_1701q.revision))
        {
            return error.WrongFormRevision;
        }
        if (request.form.eql(&form_1701q.revision) and
            open_policy != .exact_1701q_projection_only)
        {
            return error.DraftPersistenceDisabled;
        }

        self.clearOwnedRevisions();
        self.resetOpenData();
        self.open_policy = open_policy;
        self.opened_form = request.form;
        self.opened_tax_year = request.tax_year;
        self.opened_quarter = request_quarter;
        self.opened_filing_period = request.filing_period orelse .{ .quarterly = .{
            .tax_year = request.tax_year,
            .quarter = request_quarter,
        } };
        self.opened_profile_as_of = request.profile_as_of orelse if (request.filing_period) |period|
            try filingPeriodEnd(period)
        else
            try quarterEnd(request.tax_year, request_quarter);
        self.selected_filer_id = request.filer_profile_id;
        self.selected_spouse_id = request.spouse_profile_id;

        if (open_policy == .draft_backed and
            (request.filing_period != null or isRecurring(request.form)) and
            try self.openExistingOriginal())
        {
            try self.refreshSpouseCandidates();
            self.setDraftSavedNotice(
                .resumed,
                self.persisted_draft_provenance orelse
                    return error.ExistingDraftMismatch,
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
                try self.refreshSpouseCandidates();
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

        try self.refreshSpouseCandidates();
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

        try self.refreshSpouseCandidates();
        try self.reproject();
    }

    pub fn clearSpouseProfile(self: *State) !void {
        try self.setSpouseProfile(null);
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
        // Exact 1701Q owns a separate occurrence/revision persistence model.
        // Never mint or resume its retired coarse deterministic draft even if
        // a caller accidentally used the general `open` boundary.
        if (form.eql(&form_1701q.revision)) {
            self.setErrorNotice(error.DraftPersistenceDisabled);
            return error.DraftPersistenceDisabled;
        }
        if (!self.projection_is_accepted or self.projected_snapshot == null) {
            self.setErrorNotice(error.NoAcceptedProjection);
            return error.NoAcceptedProjection;
        }

        if (self.persisted_draft_id != null) {
            return self.saveResumedDraftValues(
                transaction_values,
                replace_resumed_values,
            );
        }

        const period = runtime.RecurringQuarter{
            .form = form,
            .tax_year = self.opened_tax_year,
            .quarter = self.opened_quarter,
        };
        const current_filing_period = self.opened_filing_period orelse
            return error.NotOpen;
        const definition = catalog.findForm(form.code.asSlice()) orelse
            return error.UnknownForm;
        const revision = definition.revision orelse
            return error.CalendarOnlyForm;
        if (!std.mem.eql(u8, revision, form.revision.asSlice())) {
            return error.WrongFormRevision;
        }
        const occurrence_date: ?model.Date = switch (current_filing_period) {
            // Recurring 2551Q intentionally resolves membership on the
            // quarter end derived from the period, never an ad-hoc date.
            .monthly, .quarterly, .annual => null,
            .on_demand => self.opened_profile_as_of,
        };
        var prepared = try draft_provenance_runtime.prepare(
            allocator,
            store,
            self,
            definition,
            current_filing_period,
            occurrence_date,
        );
        defer prepared.deinit();

        var opened = try form_persistence.createOrLoadWithProvenance(
            allocator,
            store,
            .{
                .period = period,
                .filing_period = current_filing_period,
                .role_bindings = &self.projected_bindings,
                .snapshot = &self.projected_snapshot.?,
                .transaction_values = transaction_values,
            },
            .{
                .applicability_date = prepared.composition.applicability_date,
                .forms_set_decision = prepared.formSetDecision(),
                .snapshot = &prepared.composition.provenance_snapshot,
            },
        );
        defer opened.deinit(allocator);

        const disposition = opened.disposition;
        const provenance_status: DraftProvenanceStatus =
            switch (opened.provenance) {
                .exact => .exact,
                .provenance_legacy_absent => .legacy_absent,
                .corrupt => {
                    self.invalidateProjection();
                    return error.DraftProvenanceCorrupt;
                },
            };
        if (disposition == .resumed and replace_resumed_values) {
            try store.replaceDraftValues(
                opened.draft.id,
                transaction_values,
            );
        }
        try self.adoptPersistedDraft(&opened.draft, disposition);
        self.persisted_draft_provenance = provenance_status;
        const result: DraftSaveResult = .{
            .id = self.persisted_draft_id.?,
            .disposition = disposition,
            .status = self.persisted_draft_status.?,
        };
        self.setDraftSavedNotice(disposition, provenance_status);
        return result;
    }

    /// A previously adopted draft already owns its immutable source snapshot.
    /// Reload provenance instead of recomposing from current profile state,
    /// then replace only the separate editable transaction-value slice.
    fn saveResumedDraftValues(
        self: *State,
        transaction_values: []const store_module.DraftValueWrite,
        replace_values: bool,
    ) !DraftSaveResult {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;
        const draft_id = self.persisted_draft_id orelse return error.NotOpen;
        var draft = (try store.getDraft(
            allocator,
            draft_id.asSlice(),
        )) orelse return error.NotFound;
        defer draft.deinit(allocator);

        const provenance_status = loadPersistedDraftProvenanceStatus(
            store,
            allocator,
            draft_id,
        ) catch |err| {
            if (err == error.DraftProvenanceCorrupt) {
                self.invalidateProjection();
            }
            return err;
        };
        const status = DraftStatus.parse(draft.lifecycle) orelse
            return error.ExistingDraftMismatch;
        if (replace_values) {
            if (status != .editing) return error.InvalidTransition;
            try store.replaceDraftValues(draft.id, transaction_values);
        }

        try self.adoptPersistedDraft(&draft, .resumed);
        self.persisted_draft_provenance = provenance_status;
        self.setDraftSavedNotice(.resumed, provenance_status);
        return .{
            .id = self.persisted_draft_id.?,
            .disposition = .resumed,
            .status = self.persisted_draft_status.?,
        };
    }

    fn setDraftSavedNotice(
        self: *State,
        disposition: DraftDisposition,
        provenance_status: DraftProvenanceStatus,
    ) void {
        if (provenance_status == .legacy_absent) {
            self.setNotice(
                .warning,
                "Legacy draft resumed without exact provenance. Its original persisted tax-profile snapshot remains authoritative.",
            );
            return;
        }
        self.setNotice(
            if (disposition == .created) .success else .info,
            if (disposition == .created)
                "Draft saved atomically with its immutable tax-profile provenance."
            else
                "Existing draft resumed with its exact persisted provenance.",
        );
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

    pub fn filingPeriod(self: *const State) ?filing_period.FilingPeriod {
        return self.opened_filing_period;
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

    /// Exact immutable taxpayer revision currently bound to a named filing
    /// role. Draft-provenance composition consumes this pointer synchronously;
    /// callers must not retain it after the form state is reset or re-opened.
    pub fn profileRevision(
        self: *const State,
        role: ids.Role,
    ) ?*const model.ProfileRevision {
        return switch (role) {
            .filer => if (self.filer_revision) |*owned| &owned.revision else null,
            .spouse => if (self.spouse_revision) |*owned| &owned.revision else null,
            else => null,
        };
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

    pub fn draftProvenanceStatus(
        self: *const State,
    ) ?DraftProvenanceStatus {
        return self.persisted_draft_provenance;
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

    /// Performs the same profile-revision and catalog-projection checks used
    /// by an editor open without mutating the live editor state.  View code
    /// should consume a cached result from the application model rather than
    /// calling this method while rendering.
    pub fn assessLaunch(
        self: *const State,
        request: OpenRequest,
    ) LaunchAssessment {
        const allocator = self.allocator orelse return .{
            .status = .unsupported_period,
            .blocker = .persistence_error,
        };
        const store = self.store orelse return .{
            .status = .unsupported_period,
            .blocker = .persistence_error,
        };

        validateEditorRevision(request.form) catch |err| {
            return .{
                .status = .unsupported_period,
                .blocker = launchBlockerForError(err),
            };
        };
        _ = validateRequestPeriod(request) catch |err| {
            return .{
                .status = .unsupported_period,
                .blocker = launchBlockerForError(err),
            };
        };

        if ((request.filing_period != null or isRecurring(request.form)) and
            existingOriginalIsUsable(
                allocator,
                store,
                request,
            ) catch false)
        {
            return .{
                .status = .ready_resume,
                .blocker = .none,
            };
        }

        const effective_on = request.profile_as_of orelse
            (if (request.filing_period) |period|
                filingPeriodEnd(period) catch return .{
                    .status = .unsupported_period,
                    .blocker = .invalid_revision,
                }
            else
                quarterEnd(request.tax_year, request.quarter) catch return .{
                    .status = .unsupported_period,
                    .blocker = .invalid_revision,
                });
        // Readiness projects only the effective Base Tax Profile. Historical
        // Registration activities and obligations are deliberately excluded.
        var filer = (profile_persistence.loadEffectiveRevision(
            store,
            allocator,
            request.filer_profile_id,
            effective_on,
        ) catch {
            return .{
                .status = .unsupported_period,
                .blocker = .persistence_error,
            };
        }) orelse {
            return .{
                .status = .missing_base_profile,
                .blocker = .missing_effective_revision,
            };
        };
        defer filer.deinit(allocator);

        const bindings = [_]projection.Binding{.{
            .role = .filer,
            .revision = &filer.revision,
            .selection = .{},
        }};
        var result = catalog_projection.project(
            allocator,
            request.form,
            &bindings,
            effective_on,
        ) catch {
            return .{
                .status = .unsupported_period,
                .blocker = .persistence_error,
            };
        };
        defer result.deinit(allocator);

        return switch (result) {
            .accepted => .{
                .status = .ready_new,
                .blocker = .none,
            },
            .rejected => |rejected| assessmentForIssues(rejected.slice()),
        };
    }

    pub fn spouseCandidates(self: *const State) []const SpouseCandidate {
        return self.spouse_candidate_items[0..self.spouse_candidate_len];
    }

    pub fn spouseCandidatesTruncated(self: *const State) bool {
        return self.spouse_candidates_truncated;
    }

    fn existingOriginalIsUsable(
        allocator: std.mem.Allocator,
        store: *store_module.Store,
        request: OpenRequest,
    ) !bool {
        const period: filing_period.FilingPeriod = request.filing_period orelse .{ .quarterly = .{
            .tax_year = request.tax_year,
            .quarter = request.quarter,
        } };
        const id = try form_persistence.originalDraftIdForFilingPeriod(
            request.filer_profile_id,
            &request.form,
            period,
        );
        var draft = (try store.getDraft(allocator, id.asSlice())) orelse
            return false;
        defer draft.deinit(allocator);

        if (!std.mem.eql(u8, draft.intent, "original") or
            draft.amendment_of != null)
        {
            return false;
        }
        const rehydrated = form_persistence.rehydrate(&draft) catch
            return false;
        if (!rehydrated.form.eql(&request.form) or
            rehydrated.period.taxYear() != request.tax_year or
            !rehydrated.period.eql(period))
        {
            return false;
        }
        const filer = rehydrated.role_bindings.get(.filer) orelse
            return false;
        return filer.profile_id.eql(&request.filer_profile_id);
    }

    fn assessmentForIssues(
        issues: []const catalog_projection.Issue,
    ) LaunchAssessment {
        var assessment = LaunchAssessment{
            .status = .ready_new,
            .blocker = .none,
        };
        for (issues) |issue| {
            switch (issue) {
                .missing_capability => |target| {
                    // Base Profile blockers take priority over form-specific
                    // setup so remediation always starts with shared data.
                    assessment.status = .missing_base_profile;
                    assessment.blocker = .missing_profile_data;
                    assessment.addMissingBaseField(target.reusable_field);
                    assessment.issue_count +|= 1;
                },
                .missing_binding => {
                    if (assessment.status == .ready_new) {
                        assessment.status = .missing_tax_form_profile;
                        assessment.blocker = .missing_binding;
                    }
                    assessment.issue_count +|= 1;
                },
                // Forms Set activation is authoritative. Subject-kind policy
                // cannot make an active form unavailable in the Library.
                .subject_not_allowed => {},
                .duplicate_binding,
                .unexpected_binding,
                .same_profile_binding,
                .invalid_revision,
                .revision_not_effective,
                => {
                    if (assessment.status == .ready_new) {
                        assessment.status = .unsupported_period;
                        assessment.blocker = switch (issue) {
                            .revision_not_effective => .revision_not_effective,
                            else => .invalid_revision,
                        };
                    }
                    assessment.issue_count +|= 1;
                },
            }
        }
        return assessment;
    }

    fn launchBlockerForError(err: anyerror) LaunchBlocker {
        return switch (err) {
            error.NoEffectiveFilerRevision => .missing_effective_revision,
            error.CalendarOnlyForm,
            error.UnknownForm,
            error.WrongFormRevision,
            error.InvalidPeriod,
            => .invalid_revision,
            error.InvalidQuarter => .invalid_revision,
            else => .persistence_error,
        };
    }

    fn openExistingOriginal(self: *State) !bool {
        const form = self.opened_form orelse return false;
        if (form.eql(&form_1701q.revision)) return false;
        const allocator = self.allocator.?;
        const store = self.store.?;
        const filer_id = self.selected_filer_id orelse return false;
        const period: filing_period.FilingPeriod = self.opened_filing_period orelse .{ .quarterly = .{
            .tax_year = self.opened_tax_year,
            .quarter = self.opened_quarter,
        } };
        const id = try form_persistence.originalDraftIdForFilingPeriod(
            filer_id,
            &form,
            period,
        );
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
        const provenance_status = try loadPersistedDraftProvenanceStatus(
            store,
            allocator,
            id,
        );
        try self.adoptPersistedDraft(&draft, .resumed);
        self.persisted_draft_provenance = provenance_status;
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
        if (!rehydrated.form.eql(&requested_form) or
            rehydrated.period.taxYear() != self.opened_tax_year or
            !rehydrated.period.eql(self.opened_filing_period.?))
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
        if (rehydrated.role_bindings.get(.spouse)) |spouse_binding| {
            self.selected_spouse_id = spouse_binding.profile_id;
        } else {
            self.selected_spouse_id = null;
        }
        self.opened_profile_as_of = rehydrated.snapshot.effective_on;
        self.opened_filing_period = rehydrated.period;
        self.projected_snapshot = rehydrated.snapshot;
        self.projected_bindings = rehydrated.role_bindings;
        self.projection_is_accepted = true;
        self.projection_issue_count = 0;
        try self.cacheSnapshot(&rehydrated.snapshot);

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
            .selection = .{},
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
                .selection = .{},
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
        self.opened_filing_period = null;
        self.opened_profile_as_of = null;
        self.selected_filer_id = null;
        self.selected_spouse_id = null;
        self.spouse_candidate_len = 0;
        self.spouse_candidates_truncated = false;
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
        self.persisted_draft_provenance = null;
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
        if (err == error.DraftProvenanceCorrupt) {
            self.setNotice(
                .failure,
                "Draft provenance is corrupt. The draft was blocked and no filing values were changed.",
            );
            return;
        }
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

fn loadPersistedDraftProvenanceStatus(
    store: *store_module.Store,
    allocator: std.mem.Allocator,
    draft_id: ids.DraftId,
) !DraftProvenanceStatus {
    var loaded = form_persistence.loadDraftProvenance(
        store,
        allocator,
        draft_id,
    ) catch |err| switch (err) {
        error.OutOfMemory,
        error.Closed,
        error.SqliteBusy,
        error.NotFound,
        => return err,
        else => return error.DraftProvenanceCorrupt,
    };
    defer loaded.deinit(allocator);
    return switch (loaded) {
        .provenance_legacy_absent => .legacy_absent,
        .exact => .exact,
        .corrupt => error.DraftProvenanceCorrupt,
    };
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

fn validateRequestPeriod(request: OpenRequest) Error!u8 {
    const period = request.filing_period orelse {
        try validateQuarter(request.form, request.tax_year, request.quarter);
        return request.quarter;
    };
    period.validate() catch return error.InvalidPeriod;
    if (period.taxYear() != request.tax_year) return error.InvalidPeriod;

    const definition = catalog.findForm(request.form.code.asSlice()) orelse
        return error.UnknownForm;
    if (period.cadence() != definition.cadence) return error.InvalidPeriod;

    const slot = switch (period) {
        .monthly => |value| value.month,
        .quarterly => |value| value.quarter,
        .annual, .on_demand => null,
    };
    if (slot) |value| {
        if (definition.min_period) |minimum| if (value < minimum)
            return error.InvalidPeriod;
        if (definition.max_period) |maximum| if (value > maximum)
            return error.InvalidPeriod;
    }

    const quarter = period.quarter() orelse request.quarter;
    try validateQuarter(request.form, request.tax_year, quarter);
    return quarter;
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

fn filingPeriodEnd(period: filing_period.FilingPeriod) !model.Date {
    return switch (period) {
        .monthly => |value| model.Date.init(
            value.tax_year,
            value.month,
            switch (value.month) {
                1, 3, 5, 7, 8, 10, 12 => 31,
                4, 6, 9, 11 => 30,
                2 => if (value.tax_year % 4 == 0 and
                    (value.tax_year % 100 != 0 or value.tax_year % 400 == 0))
                    29
                else
                    28,
                else => return error.InvalidPeriod,
            },
        ),
        .quarterly => |value| quarterEnd(value.tax_year, value.quarter),
        .annual, .on_demand => model.Date.init(period.taxYear(), 12, 31),
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
    var revision = try ready.build();
    revision.accounting_period_basis = .calendar;
    revision.eopt_tier = .micro;
    revision.primary_line_of_business = try field.LineOfBusiness.parse(
        "Software consulting",
    );
    try revision.validate();
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

fn configure2551QDraftProvenanceSources(
    allocator: std.mem.Allocator,
    store: *store_module.Store,
    profile_id: model.ProfileId,
) !void {
    const definition = catalog.findForm("2551Q").?;
    const registrations = [_]store_module.FormRegistrationWrite{.{
        .form_code = definition.code,
        .form_revision = definition.revision.?,
    }};
    try store.createFormSet(
        profile_id.asSlice(),
        2026,
        &registrations,
    );

    const values = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .income_tax_rate_election,
        .role = .filer,
        .value = .{ .choice = try tax_form_profile.TextValue.parse(
            "eight_percent",
        ) },
    }};
    const revision: tax_form_profile.Revision = .{
        .id = try tax_form_profile.RevisionId.parse(
            "ui-2551q-tax-form-profile-r1",
        ),
        .stream = .{
            .profile_id = profile_id,
            .tax_year = 2026,
            .form_code = try tax_form_profile.FormCode.parse(definition.code),
            .form_revision = try tax_form_profile.FormRevision.parse(
                definition.revision.?,
            ),
        },
        .sequence = 1,
        .effective = try tax_form_profile.EffectivePeriod.init(
            try tax_form_profile.Date.parseIso("2026-01-01"),
            try tax_form_profile.Date.parseIso("2026-12-31"),
        ),
        .spec_revision = definition.tax_form_profile.spec_revision.?,
        .spec_hash = try tax_form_profile.SpecHash.parse(
            definition.tax_form_profile.spec_hash.?,
        ),
        .review_state = .confirmed,
        .confirmed_at_unix = 1,
        .source = .manual_entry,
        .values = &values,
    };
    try profile_persistence.appendTaxFormProfileRevision(
        store,
        allocator,
        0,
        &revision,
    );
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
        const request: OpenRequest = .{
            .form = form,
            .filer_profile_id = filer,
            .tax_year = 2026,
            .quarter = 1,
        };
        if (form.eql(&form_1701q.revision)) {
            try state.openExact1701QProjectionOnly(request);
        } else {
            try state.open(request);
        }
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
    try std.testing.expectEqualStrings("", state.filerText(.atc));
    const form_0605 = catalog.findForm("0605").?;
    var found_line_of_business = false;
    for (form_0605.fields) |catalog_field| {
        if (!std.mem.eql(
            u8,
            catalog_field.id,
            "0605.1999-07-ENCS.input.line_of_business_occupation",
        )) continue;
        found_line_of_business = true;
        try std.testing.expectEqual(
            catalog.Provenance.profile,
            catalog_field.provenance,
        );
    }
    try std.testing.expect(found_line_of_business);

    try state.open(.{
        .form = editor_revisions[3],
        .filer_profile_id = person,
        .tax_year = 2026,
        .quarter = 1,
    });
    try std.testing.expectEqualStrings(
        "Software consulting",
        state.filerText(.line_of_business),
    );
    try std.testing.expectEqualStrings("", state.filerText(.atc));

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

test "typed catalog periods retain identity and block unconfigured provenance" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();
    try persistFullTestRevision(
        &store,
        "profile-generic-periods",
        "revision-generic-periods-1",
        1,
        .sole_proprietor,
        "GENERIC PERIOD FILER",
        "567-890-123-000",
    );
    const profile_id = try model.ProfileId.parse("profile-generic-periods");

    var annual = State.init(allocator, &store);
    try annual.open(.{
        .form = ids.FormRevision.initComptime("1701", "2018-01-ENCS"),
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 4,
        .filing_period = .{ .annual = .{ .tax_year = 2026 } },
    });
    try std.testing.expect(annual.projectionAccepted());
    try std.testing.expectEqual(
        filing_period.FilingPeriod{ .annual = .{ .tax_year = 2026 } },
        annual.filingPeriod().?,
    );
    try std.testing.expectError(
        error.MissingFormsSetDecision,
        annual.saveRecurringDraft(),
    );
    try std.testing.expect(annual.draftId() == null);
    annual.deinit();

    var monthly = State.init(allocator, &store);
    defer monthly.deinit();
    try monthly.open(.{
        .form = ids.FormRevision.initComptime("0619E", "2018-01-ENCS"),
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 1,
        .filing_period = .{ .monthly = .{ .tax_year = 2026, .month = 2 } },
    });
    try std.testing.expect(monthly.projectionAccepted());
    try std.testing.expectEqual(
        filing_period.FilingPeriod{ .monthly = .{ .tax_year = 2026, .month = 2 } },
        monthly.filingPeriod().?,
    );
    try std.testing.expectError(
        error.MissingFormsSetDecision,
        monthly.saveRecurringDraft(),
    );
    try std.testing.expect(monthly.draftId() == null);
    var label_buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2026 February",
        try monthly.filingPeriod().?.label(&label_buffer),
    );
}

test "2551Q UI atomically creates exact provenance and safely replaces resumed transaction values" {
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
    try configure2551QDraftProvenanceSources(
        allocator,
        &store,
        profile_id,
    );

    var state = State.init(allocator, &store);
    try state.open(.{
        .form = form_2551q.revision,
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 1,
    });
    try std.testing.expectEqual(@as(u8, 8), state.snapshot().?.len);
    const initial_values = [_]store_module.DraftValueWrite{.{
        .field_id = "2551Q.schedule.row-a.rate",
        .value_text = "3.00",
        .provenance = "external_policy",
    }};
    const created = try state.saveRecurringDraftWithValues(&initial_values);
    try std.testing.expectEqual(DraftDisposition.created, created.disposition);
    try std.testing.expect(state.profileSnapshotLocked());
    try std.testing.expectEqual(
        DraftProvenanceStatus.exact,
        state.draftProvenanceStatus().?,
    );
    const created_id = created.id;
    state.deinit();

    var stored = (try store.getDraft(
        allocator,
        created_id.asSlice(),
    )).?;
    defer stored.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 8), stored.snapshots.len);
    try std.testing.expectEqual(@as(usize, 1), stored.bindings.len);
    try std.testing.expectEqual(@as(usize, 1), stored.values.len);
    try std.testing.expectEqualStrings(
        "3.00",
        stored.values[0].value_text,
    );
    try std.testing.expectEqualStrings("2026-03-31", stored.profile_as_of);
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.draftProvenanceSequence(created_id.asSlice()),
    );

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
    try std.testing.expectEqual(
        DraftProvenanceStatus.exact,
        resumed_state.draftProvenanceStatus().?,
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
        resumed_state.setSpouseProfile(null),
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

test "2551Q UI resumes pre-v17 draft with explicit legacy provenance status" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();
    try persistFullTestRevision(
        &store,
        "profile-2551q-legacy",
        "revision-2551q-legacy-1",
        1,
        .sole_proprietor,
        "LEGACY PROVENANCE TAXPAYER",
        "567-890-123-000",
    );
    const profile_id = try model.ProfileId.parse("profile-2551q-legacy");

    var projected = State.init(allocator, &store);
    try projected.open(.{
        .form = form_2551q.revision,
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 2,
    });
    const initial_values = [_]store_module.DraftValueWrite{.{
        .field_id = "2551Q.schedule.row-a.rate",
        .value_text = "3.00",
        .provenance = "legacy_test",
    }};
    var legacy = try form_persistence.createOrLoad(
        allocator,
        &store,
        .{
            .period = .{
                .form = form_2551q.revision,
                .tax_year = 2026,
                .quarter = 2,
            },
            .filing_period = projected.filingPeriod(),
            .role_bindings = projected.roleBindings(),
            .snapshot = projected.snapshot().?,
            .transaction_values = &initial_values,
        },
    );
    const legacy_id = try ids.DraftId.parse(legacy.draft.id);
    legacy.deinit(allocator);
    projected.deinit();

    var resumed = State.init(allocator, &store);
    defer resumed.deinit();
    try resumed.open(.{
        .form = form_2551q.revision,
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 2,
    });
    try std.testing.expectEqual(
        DraftProvenanceStatus.legacy_absent,
        resumed.draftProvenanceStatus().?,
    );
    try std.testing.expectEqual(NoticeKind.warning, resumed.noticeKind());
    try std.testing.expect(
        std.mem.indexOf(u8, resumed.noticeText(), "without exact provenance") !=
            null,
    );

    const replacement = [_]store_module.DraftValueWrite{.{
        .field_id = "2551Q.schedule.row-a.rate",
        .value_text = "5.00",
        .provenance = "legacy_test",
    }};
    _ = try resumed.saveRecurringDraftWithValues(&replacement);
    try std.testing.expectEqual(
        DraftProvenanceStatus.legacy_absent,
        resumed.draftProvenanceStatus().?,
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        try store.draftProvenanceSequence(legacy_id.asSlice()),
    );
    var stored = (try store.getDraft(allocator, legacy_id.asSlice())).?;
    defer stored.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), stored.values.len);
    try std.testing.expectEqualStrings("5.00", stored.values[0].value_text);
}

test "2551Q UI blocks corrupt persisted provenance before adopting draft state" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();
    try persistFullTestRevision(
        &store,
        "profile-2551q-corrupt",
        "revision-2551q-corrupt-1",
        1,
        .sole_proprietor,
        "CORRUPT PROVENANCE TAXPAYER",
        "678-901-234-000",
    );
    const profile_id = try model.ProfileId.parse("profile-2551q-corrupt");
    try configure2551QDraftProvenanceSources(
        allocator,
        &store,
        profile_id,
    );
    const definition = catalog.findForm("2551Q").?;

    var projected = State.init(allocator, &store);
    try projected.open(.{
        .form = form_2551q.revision,
        .filer_profile_id = profile_id,
        .tax_year = 2026,
        .quarter = 3,
    });
    var prepared = try draft_provenance_runtime.prepare(
        allocator,
        &store,
        &projected,
        definition,
        projected.filingPeriod().?,
        null,
    );
    defer prepared.deinit();
    const initial_values = [_]store_module.DraftValueWrite{.{
        .field_id = "2551Q.schedule.row-a.rate",
        .value_text = "3.00",
        .provenance = "corrupt_test",
    }};
    var coarse = try form_persistence.createOrLoad(
        allocator,
        &store,
        .{
            .period = .{
                .form = form_2551q.revision,
                .tax_year = 2026,
                .quarter = 3,
            },
            .filing_period = projected.filingPeriod(),
            .role_bindings = projected.roleBindings(),
            .snapshot = projected.snapshot().?,
            .transaction_values = &initial_values,
        },
    );
    const coarse_id = try ids.DraftId.parse(coarse.draft.id);
    coarse.deinit(allocator);
    projected.deinit();

    const exact_decision = prepared.formSetDecision();
    var applicability_date: store_module.DateText = undefined;
    _ = prepared.composition.applicability_date.writeIso(
        &applicability_date,
    );
    const taxpayer_revisions =
        [_]store_module.DraftProvenanceTaxpayerRevisionWrite{.{
            .role = .filer,
            .profile_id = profile_id.asSlice(),
            .revision_id = "revision-2551q-corrupt-1",
            .revision_sequence = 1,
        }};
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.appendDraftProvenance(.{
            .draft_id = coarse_id.asSlice(),
            .expected_current_sequence = 0,
            .owner_profile_id = profile_id.asSlice(),
            .tax_year = 2026,
            .form_code = definition.code,
            .form_revision = definition.revision.?,
            .catalog_revision = catalog.catalog_revision,
            .catalog_sha256 = catalog.catalog_sha256,
            .setup_spec_revision = definition.tax_form_profile.spec_revision.?,
            // Storage accepts a well-formed hash. Domain rehydration rejects
            // it because it is not the generated 2551Q setup-spec hash.
            .setup_spec_hash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            .forms_set_decision = .{
                .id = exact_decision.id.asSlice(),
                .sequence = exact_decision.sequence,
                .source = switch (exact_decision.source) {
                    .manual => .manual,
                    .imported => .imported,
                    .cor => .cor,
                },
                .evidence_reference = exact_decision.evidence_reference,
                .applicability_date = applicability_date,
            },
            .taxpayer_revisions = &taxpayer_revisions,
        }),
    );

    var blocked = State.init(allocator, &store);
    defer blocked.deinit();
    try std.testing.expectError(
        error.DraftProvenanceCorrupt,
        blocked.open(.{
            .form = form_2551q.revision,
            .filer_profile_id = profile_id,
            .tax_year = 2026,
            .quarter = 3,
        }),
    );
    try std.testing.expect(blocked.draftId() == null);
    try std.testing.expect(blocked.draftProvenanceStatus() == null);
    try std.testing.expect(!blocked.projectionAccepted());
    try std.testing.expectEqual(NoticeKind.failure, blocked.noticeKind());
    var unchanged = (try store.getDraft(allocator, coarse_id.asSlice())).?;
    defer unchanged.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), unchanged.values.len);
    try std.testing.expectEqualStrings("3.00", unchanged.values[0].value_text);
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

test "1701Q optional spouse projects named role while draft-backed open stays retired" {
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
    try std.testing.expectError(
        error.DraftPersistenceDisabled,
        state.open(.{
            .form = form_1701q.revision,
            .filer_profile_id = filer,
            .tax_year = 2026,
            .quarter = 2,
        }),
    );
    try std.testing.expect(state.formRevision() == null);
    try state.openExact1701QProjectionOnly(.{
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
    try std.testing.expectError(
        error.DraftPersistenceDisabled,
        state.saveRecurringDraft(),
    );
    try std.testing.expect(state.draftId() == null);

    var rejected = State.init(allocator, &store);
    defer rejected.deinit();
    try rejected.openExact1701QProjectionOnly(.{
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

test "launch assessment reports Base and Tax Form Profile blockers separately" {
    const missing_base = catalog_projection.TargetContext{
        .role = .filer,
        .target = ids.FieldId.initComptime("test.base.zip-code"),
        .reusable_field = .zip_code,
    };
    const missing_form_binding = catalog_projection.TargetContext{
        .role = .spouse,
        .target = ids.FieldId.initComptime("test.form.spouse"),
        .reusable_field = .taxpayer_name,
    };

    const form_only_issues = [_]catalog_projection.Issue{
        .{ .missing_binding = missing_form_binding },
    };
    const form_only = State.assessmentForIssues(&form_only_issues);
    try std.testing.expectEqual(
        LaunchStatus.missing_tax_form_profile,
        form_only.status,
    );
    try std.testing.expectEqual(LaunchBlocker.missing_binding, form_only.blocker);
    try std.testing.expect(form_only.first_missing_field == null);

    const layered_issues = [_]catalog_projection.Issue{
        .{ .missing_binding = missing_form_binding },
        .{ .missing_capability = missing_base },
    };
    const layered = State.assessmentForIssues(&layered_issues);
    try std.testing.expectEqual(
        LaunchStatus.missing_base_profile,
        layered.status,
    );
    try std.testing.expectEqual(
        LaunchBlocker.missing_profile_data,
        layered.blocker,
    );
    try std.testing.expectEqual(field.ReusableField.zip_code, layered.first_missing_field.?);
    try std.testing.expectEqual(@as(usize, 1), layered.missingBaseFields().len);
    try std.testing.expectEqual(field.ReusableField.zip_code, layered.missingBaseFields()[0]);
    try std.testing.expectEqual(@as(u16, 2), layered.issue_count);
}

test "subject eligibility never blocks an active Forms Set launch" {
    const issues = [_]catalog_projection.Issue{
        .{ .subject_not_allowed = .{
            .role = .filer,
            .subject = .corporation,
        } },
    };
    const assessment = State.assessmentForIssues(&issues);
    try std.testing.expectEqual(LaunchStatus.ready_new, assessment.status);
    try std.testing.expectEqual(LaunchBlocker.none, assessment.blocker);
    try std.testing.expectEqual(@as(u16, 0), assessment.issue_count);
}
