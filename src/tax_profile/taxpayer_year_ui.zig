//! Allocation-free view/edit state for taxpayer-year settings.
//!
//! Persistence and Native markup deliberately stay outside this module. The
//! state owns only a fixed-size baseline/draft projection, exact
//! `(profile_id, tax_year)` identity, active-consumer applicability, and the
//! transitions needed by a read-only page with an explicit editor. Missing
//! settings are surfaced only while at least one active form consumes them.

const std = @import("std");
const model = @import("model.zig");
const taxpayer_year = @import("taxpayer_year_settings.zig");

pub const Error = taxpayer_year.Error || error{
    NotOpen,
    InvalidEffectiveDate,
    InvalidConsumption,
    WrongViewedIdentity,
    InactiveProfile,
    NoConsumingForms,
    NotEditing,
    ActionDisabled,
    TooManyValues,
    DuplicateSetting,
    InvalidTransition,
    InvalidCopySource,
    CopyUnavailable,
    NoReviewRequired,
    NoConflict,
    WrongConflictSequence,
    WrongSavedRevision,
};

pub const max_setting_values: usize = std.meta.tags(
    taxpayer_year.SettingKey,
).len;

/// The page always opens read-only. Save progress and optimistic conflicts are
/// separate state axes so a failed append cannot silently exit the editor.
pub const PageState = enum {
    inactive_history_only,
    no_consuming_forms,
    needs_settings,
    requires_review,
    viewing_ready,
    editing,
};

pub const SaveStatus = enum {
    idle,
    saving,
    failed,
};

/// Aggregated requirements of the active Forms Set for the viewed year.
/// `deduction_method` is conditional: it is required only after a graduated
/// election is selected. A caller may not manufacture requirements without an
/// active consumer, or claim consumers while supplying no approved setting.
pub const Consumption = struct {
    active_form_count: u16 = 0,
    income_tax_rate_election: bool = false,
    deduction_method_when_graduated: bool = false,

    pub fn validate(self: Consumption) Error!void {
        const any_requirement = self.income_tax_rate_election or
            self.deduction_method_when_graduated;
        if ((self.active_form_count == 0) != !any_requirement) {
            return error.InvalidConsumption;
        }
        if (self.deduction_method_when_graduated and
            !self.income_tax_rate_election)
        {
            return error.InvalidConsumption;
        }
    }

    pub fn hasActiveConsumers(self: Consumption) bool {
        return self.active_form_count != 0;
    }
};

pub const ViewedIdentity = struct {
    stream: taxpayer_year.StreamKey,
    effective_on: taxpayer_year.Date,
    revision_id: ?taxpayer_year.RevisionId = null,
    revision_sequence: u32 = 0,
};

pub const ReviewRequirement = enum {
    none,
    prior_year_copy,
    persisted_unconfirmed_revision,
};

pub const Conflict = struct {
    expected_sequence: u32,
    current_sequence: u32,
};

/// Page-level readiness is intentionally distinct from editor validity. A
/// complete draft is not filing-ready until a confirmed revision is saved.
pub const Readiness = struct {
    applicable: bool,
    active_consumer_count: u16,
    required_count: u8,
    supplied_required_count: u8,
    missing_required_count: u8,
    supplied_value_count: u8,
    candidate_valid: bool,
    has_confirmed_revision: bool,
    review_required: bool,

    pub fn candidateComplete(self: Readiness) bool {
        return self.applicable and self.candidate_valid and
            self.missing_required_count == 0;
    }

    pub fn ready(self: Readiness) bool {
        return self.candidateComplete() and
            self.has_confirmed_revision and
            !self.review_required;
    }
};

pub const ReadinessStatus = enum {
    unavailable,
    inactive,
    no_consuming_forms,
    conflict,
    editing,
    invalid_settings,
    missing_required_settings,
    requires_review,
    ready,
};

pub const PriorYearCopyIdentity = taxpayer_year.PriorYearCopySource;

/// Values and exact copy provenance borrowed from `State`. Consume the intent
/// synchronously while constructing the persistence append command.
pub const SaveIntent = struct {
    identity: ViewedIdentity,
    expected_sequence: u32,
    values: []const taxpayer_year.SettingValue,
    review_requirement: ReviewRequirement,
    reviewed_copy_source: ?PriorYearCopyIdentity,

    /// Constructs the only confirmed append accepted for this save intent.
    /// In particular, a reviewed prior-year copy cannot be silently rewritten
    /// as manual entry at the persistence boundary.
    pub fn confirmedRevision(
        self: *const SaveIntent,
        id: taxpayer_year.RevisionId,
        confirmed_at_unix_seconds: i64,
    ) Error!taxpayer_year.Revision {
        if (self.expected_sequence == std.math.maxInt(u32)) {
            return error.InvalidCandidateSequence;
        }
        if (self.review_requirement == .prior_year_copy and
            self.reviewed_copy_source == null)
        {
            return error.InvalidCopySource;
        }
        const revision: taxpayer_year.Revision = .{
            .id = id,
            .stream = self.identity.stream,
            .sequence = self.expected_sequence + 1,
            .effective = try taxpayer_year.fullTaxYearPeriod(
                self.identity.stream.tax_year,
            ),
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = confirmed_at_unix_seconds,
            .source = if (self.reviewed_copy_source) |source|
                .{ .copied_from_prior_year = source }
            else
                .manual_entry,
            .values = self.values,
        };
        try revision.validate();
        return revision;
    }
};

pub const Affordances = struct {
    can_view_history: bool,
    can_edit: bool,
    can_save: bool,
    can_cancel: bool,
    can_copy_prior_year: bool,
    can_acknowledge_review: bool,
    can_reload_conflict: bool,
    can_rebase_conflict: bool,
};

pub const OpenArgs = struct {
    profile_id: model.ProfileId,
    tax_year: u16,
    effective_on: taxpayer_year.Date,
    profile_active: bool,
    consumption: Consumption,
    history_exists: bool = false,
    saved_revision: ?*const taxpayer_year.Revision = null,
    copy_offer: ?*const taxpayer_year.Revision = null,
};

pub const State = struct {
    opened: bool = false,
    page_state: PageState = .no_consuming_forms,
    identity: ?ViewedIdentity = null,
    profile_active: bool = false,
    consumption: Consumption = .{},
    history_exists: bool = false,

    baseline_values: [max_setting_values]taxpayer_year.SettingValue = undefined,
    baseline_value_count: usize = 0,
    draft_values: [max_setting_values]taxpayer_year.SettingValue = undefined,
    draft_value_count: usize = 0,

    baseline_review_requirement: ReviewRequirement = .none,
    draft_review_requirement: ReviewRequirement = .none,
    baseline_review_acknowledged: bool = true,
    draft_review_acknowledged: bool = true,
    baseline_confirmed: bool = false,
    persisted_copy_source: ?PriorYearCopyIdentity = null,
    baseline_copy_source: ?PriorYearCopyIdentity = null,
    draft_copy_source: ?PriorYearCopyIdentity = null,

    copy_offer_source: ?PriorYearCopyIdentity = null,
    copy_offer_values: [max_setting_values]taxpayer_year.SettingValue = undefined,
    copy_offer_value_count: usize = 0,

    expected_sequence: u32 = 0,
    save_status: SaveStatus = .idle,
    conflict: ?Conflict = null,

    pub fn open(args: OpenArgs) Error!State {
        if (args.tax_year == 0) return error.InvalidTaxYear;
        if (args.effective_on.year != args.tax_year) {
            return error.InvalidEffectiveDate;
        }
        try args.consumption.validate();

        var result: State = .{};
        result.opened = true;
        result.identity = .{
            .stream = .{
                .profile_id = args.profile_id,
                .tax_year = args.tax_year,
            },
            .effective_on = args.effective_on,
        };
        result.profile_active = args.profile_active;
        result.consumption = args.consumption;
        result.history_exists = args.history_exists;

        if (args.copy_offer) |source| {
            try result.loadCopyOffer(source);
        }
        if (args.saved_revision) |revision| {
            try result.requireRevisionMatchesView(revision);
            try result.loadBaseline(revision);
        }
        result.page_state = result.basePageState();
        return result;
    }

    pub fn reset(self: *State) void {
        self.* = .{};
    }

    pub fn page(self: *const State) ?PageState {
        return if (self.opened) self.page_state else null;
    }

    pub fn viewedIdentity(self: *const State) ?*const ViewedIdentity {
        return if (self.opened) &self.identity.? else null;
    }

    pub fn baselineValues(self: *const State) []const taxpayer_year.SettingValue {
        return self.baseline_values[0..self.baseline_value_count];
    }

    pub fn draftValues(self: *const State) []const taxpayer_year.SettingValue {
        return self.draft_values[0..self.draft_value_count];
    }

    pub fn persistedCopySource(self: *const State) ?PriorYearCopyIdentity {
        return self.persisted_copy_source;
    }

    pub fn priorYearCopyOffer(self: *const State) ?PriorYearCopyIdentity {
        return if (self.opened) self.copy_offer_source else null;
    }

    pub fn pendingConflict(self: *const State) ?Conflict {
        return if (self.opened) self.conflict else null;
    }

    /// Explicit View -> Edit transition. Opening the page never opts the user
    /// into an editable session.
    pub fn beginEdit(self: *State) Error!void {
        try self.requireMutable();
        switch (self.page_state) {
            .needs_settings, .requires_review, .viewing_ready => {},
            else => return error.InvalidTransition,
        }
        self.page_state = .editing;
        self.save_status = .idle;
        self.conflict = null;
    }

    pub fn setDraftValue(
        self: *State,
        value: taxpayer_year.SettingValue,
    ) Error!void {
        try self.requireEditing();
        for (self.draft_values[0..self.draft_value_count]) |*existing| {
            if (existing.key() != value.key()) continue;
            if (settingValueEql(existing.*, value)) return;
            existing.* = value;
            self.noteDraftMutation();
            return;
        }
        if (self.draft_value_count == self.draft_values.len) {
            return error.TooManyValues;
        }
        self.draft_values[self.draft_value_count] = value;
        self.draft_value_count += 1;
        self.noteDraftMutation();
    }

    pub fn setDraftValues(
        self: *State,
        values: []const taxpayer_year.SettingValue,
    ) Error!void {
        try self.requireEditing();
        try validateValueSetShape(values);
        if (values.len > self.draft_values.len) return error.TooManyValues;
        @memcpy(self.draft_values[0..values.len], values);
        self.draft_value_count = values.len;
        self.noteDraftMutation();
    }

    pub fn removeDraftSetting(
        self: *State,
        key: taxpayer_year.SettingKey,
    ) Error!void {
        try self.requireEditing();
        for (self.draft_values[0..self.draft_value_count], 0..) |value, index| {
            if (value.key() != key) continue;
            var cursor = index;
            while (cursor + 1 < self.draft_value_count) : (cursor += 1) {
                self.draft_values[cursor] = self.draft_values[cursor + 1];
            }
            self.draft_value_count -= 1;
            self.noteDraftMutation();
            return;
        }
    }

    /// Copies the exact offered prior-year values into a draft. Review is a
    /// first-class dirty change and must be acknowledged before Save can be
    /// invoked. Merely offering or displaying the source never copies it.
    pub fn stagePriorYearCopy(self: *State) Error!void {
        try self.requireMutable();
        switch (self.page_state) {
            .needs_settings, .requires_review, .viewing_ready => {},
            else => return error.InvalidTransition,
        }
        const source = self.copy_offer_source orelse
            return error.CopyUnavailable;
        @memcpy(
            self.draft_values[0..self.copy_offer_value_count],
            self.copy_offer_values[0..self.copy_offer_value_count],
        );
        self.draft_value_count = self.copy_offer_value_count;
        self.draft_copy_source = source;
        self.draft_review_requirement = .prior_year_copy;
        self.draft_review_acknowledged = false;
        self.page_state = .editing;
        self.save_status = .idle;
        self.conflict = null;
    }

    pub fn acknowledgeReview(self: *State) Error!void {
        try self.requireEditing();
        if (self.draft_review_requirement == .none or
            self.draft_review_acknowledged)
        {
            return error.NoReviewRequired;
        }
        self.draft_review_acknowledged = true;
        self.noteDraftMutation();
    }

    /// Normalized equality is insensitive to storage order. Source-only
    /// rewrites do not enable Save, while review acknowledgement and exact
    /// copy provenance do participate in dirty tracking.
    pub fn dirty(self: *const State) bool {
        if (!self.opened or self.page_state != .editing) return false;
        if (!valueSetsEqual(
            self.baseline_values[0..self.baseline_value_count],
            self.draft_values[0..self.draft_value_count],
        )) return true;
        if (self.baseline_review_requirement !=
            self.draft_review_requirement) return true;
        if (self.baseline_review_acknowledged !=
            self.draft_review_acknowledged) return true;
        return !optionalCopySourceEql(
            self.baseline_copy_source,
            self.draft_copy_source,
        );
    }

    pub fn readiness(self: *const State) Readiness {
        if (!self.opened or !self.profile_active or
            !self.consumption.hasActiveConsumers())
        {
            return .{
                .applicable = false,
                .active_consumer_count = if (self.opened)
                    self.consumption.active_form_count
                else
                    0,
                .required_count = 0,
                .supplied_required_count = 0,
                .missing_required_count = 0,
                .supplied_value_count = 0,
                .candidate_valid = true,
                .has_confirmed_revision = false,
                .review_required = false,
            };
        }

        const values = if (self.page_state == .editing)
            self.draftValues()
        else
            self.baselineValues();
        const election = findElection(values);
        const deduction_required =
            self.consumption.deduction_method_when_graduated and
            election == .graduated;
        var required_count: u8 = 0;
        var supplied_count: u8 = 0;
        if (self.consumption.income_tax_rate_election) {
            required_count += 1;
            if (election != null) supplied_count += 1;
        }
        if (deduction_required) {
            required_count += 1;
            if (findDeduction(values) != null) supplied_count += 1;
        }
        return .{
            .applicable = true,
            .active_consumer_count = self.consumption.active_form_count,
            .required_count = required_count,
            .supplied_required_count = supplied_count,
            .missing_required_count = required_count - supplied_count,
            .supplied_value_count = @intCast(values.len),
            .candidate_valid = valueSetValid(values),
            .has_confirmed_revision = self.baseline_confirmed,
            .review_required = self.draft_review_requirement != .none and
                !self.draft_review_acknowledged,
        };
    }

    pub fn readinessStatus(self: *const State) ReadinessStatus {
        if (!self.opened) return .unavailable;
        if (self.conflict != null) return .conflict;
        if (!self.profile_active) return .inactive;
        if (!self.consumption.hasActiveConsumers()) {
            return .no_consuming_forms;
        }
        if (self.page_state == .editing) return .editing;
        const current = self.readiness();
        if (!current.candidate_valid) return .invalid_settings;
        if (current.review_required) return .requires_review;
        if (!current.ready()) return .missing_required_settings;
        return .ready;
    }

    pub fn affordances(self: *const State) Affordances {
        if (!self.opened) return emptyAffordances();
        const editing = self.page_state == .editing;
        const mutable = self.profile_active and
            self.consumption.hasActiveConsumers();
        const current = self.readiness();
        const review_complete = self.draft_review_requirement == .none or
            self.draft_review_acknowledged;
        const idle_enough = self.save_status != .saving;
        const has_conflict = self.conflict != null;
        return .{
            .can_view_history = self.history_exists,
            .can_edit = mutable and !editing,
            .can_save = mutable and editing and self.dirty() and
                current.candidateComplete() and review_complete and
                idle_enough and !has_conflict,
            .can_cancel = mutable and editing and self.dirty() and
                idle_enough and !has_conflict,
            .can_copy_prior_year = mutable and !editing and
                self.copy_offer_source != null,
            .can_acknowledge_review = mutable and editing and
                self.draft_review_requirement != .none and
                !self.draft_review_acknowledged and !has_conflict,
            .can_reload_conflict = has_conflict,
            .can_rebase_conflict = has_conflict,
        };
    }

    /// Dirty Cancel restores the exact captured baseline and stays on this
    /// taxpayer-year page. Clean Cancel is intentionally disabled.
    pub fn cancel(self: *State) Error!void {
        try self.requireEditing();
        if (!self.affordances().can_cancel) return error.ActionDisabled;
        @memcpy(
            self.draft_values[0..self.baseline_value_count],
            self.baseline_values[0..self.baseline_value_count],
        );
        self.draft_value_count = self.baseline_value_count;
        self.draft_review_requirement = self.baseline_review_requirement;
        self.draft_review_acknowledged = self.baseline_review_acknowledged;
        self.draft_copy_source = self.baseline_copy_source;
        self.save_status = .idle;
        self.conflict = null;
        self.page_state = self.basePageState();
    }

    pub fn beginSave(self: *State) Error!SaveIntent {
        try self.requireEditing();
        if (!self.affordances().can_save) return error.ActionDisabled;
        self.save_status = .saving;
        return .{
            .identity = self.identity.?,
            .expected_sequence = self.expected_sequence,
            .values = self.draftValues(),
            .review_requirement = self.draft_review_requirement,
            .reviewed_copy_source = self.draft_copy_source,
        };
    }

    pub fn saveFailed(self: *State) Error!void {
        try self.requireEditing();
        if (self.save_status != .saving) return error.InvalidTransition;
        self.save_status = .failed;
    }

    /// Conflict handling preserves the exact draft. Retry remains blocked
    /// until the user explicitly reviews the new sequence or reloads it.
    pub fn noteConflict(self: *State, current_sequence: u32) Error!void {
        try self.requireEditing();
        if (self.save_status != .saving) return error.InvalidTransition;
        if (current_sequence <= self.expected_sequence) {
            return error.WrongConflictSequence;
        }
        self.conflict = .{
            .expected_sequence = self.expected_sequence,
            .current_sequence = current_sequence,
        };
        self.save_status = .failed;
    }

    /// Explicit "Keep Draft" conflict action. The exact latest persisted
    /// revision becomes the new baseline while every draft value, review
    /// acknowledgement, and copy source remains intact. This makes a later
    /// Cancel return to the latest saved state instead of the stale state that
    /// originally lost the optimistic race.
    pub fn keepDraftAfterConflict(
        self: *State,
        revision: *const taxpayer_year.Revision,
    ) Error!void {
        try self.requireEditing();
        const conflict = self.conflict orelse return error.NoConflict;
        if (revision.sequence != conflict.current_sequence) {
            return error.WrongConflictSequence;
        }
        try self.requireRevisionMatchesView(revision);

        var draft_values: [max_setting_values]taxpayer_year.SettingValue =
            undefined;
        @memcpy(
            draft_values[0..self.draft_value_count],
            self.draft_values[0..self.draft_value_count],
        );
        const draft_value_count = self.draft_value_count;
        const draft_review_requirement = self.draft_review_requirement;
        const draft_review_acknowledged = self.draft_review_acknowledged;
        const draft_copy_source = self.draft_copy_source;

        try self.loadBaseline(revision);
        @memcpy(
            self.draft_values[0..draft_value_count],
            draft_values[0..draft_value_count],
        );
        self.draft_value_count = draft_value_count;
        self.draft_review_requirement = draft_review_requirement;
        self.draft_review_acknowledged = draft_review_acknowledged;
        self.draft_copy_source = draft_copy_source;
        self.conflict = null;
        self.save_status = .idle;
        self.page_state = .editing;
        if (!self.dirty()) self.page_state = self.basePageState();
    }

    /// Reload is the explicit destructive conflict action. It replaces the
    /// draft with the exact persisted revision and exits Edit.
    pub fn reloadAfterConflict(
        self: *State,
        revision: *const taxpayer_year.Revision,
    ) Error!void {
        try self.requireEditing();
        const conflict = self.conflict orelse return error.NoConflict;
        if (revision.sequence != conflict.current_sequence) {
            return error.WrongConflictSequence;
        }
        try self.requireRevisionMatchesView(revision);
        try self.loadBaseline(revision);
        self.conflict = null;
        self.save_status = .idle;
        self.page_state = self.basePageState();
    }

    /// Product-language alias for the destructive conflict action.
    pub fn reloadSavedAfterConflict(
        self: *State,
        revision: *const taxpayer_year.Revision,
    ) Error!void {
        return self.reloadAfterConflict(revision);
    }

    pub fn saveSucceeded(
        self: *State,
        revision: *const taxpayer_year.Revision,
    ) Error!void {
        try self.requireEditing();
        if (self.save_status != .saving) return error.InvalidTransition;
        try self.requireRevisionMatchesView(revision);
        if (self.expected_sequence == std.math.maxInt(u32) or
            revision.sequence != self.expected_sequence + 1)
        {
            return error.WrongSavedRevision;
        }
        if (!valueSetsEqual(self.draftValues(), revision.values)) {
            return error.WrongSavedRevision;
        }
        if (revision.review_state != .confirmed or
            !revisionSourceMatchesCopy(
                &revision.source,
                self.draft_copy_source,
            ))
        {
            return error.WrongSavedRevision;
        }
        try self.loadBaseline(revision);
        self.history_exists = true;
        self.conflict = null;
        self.save_status = .idle;
        self.page_state = self.basePageState();
    }

    fn requireMutable(self: *const State) Error!void {
        if (!self.opened) return error.NotOpen;
        if (!self.profile_active) return error.InactiveProfile;
        if (!self.consumption.hasActiveConsumers()) {
            return error.NoConsumingForms;
        }
    }

    fn requireEditing(self: *const State) Error!void {
        try self.requireMutable();
        if (self.page_state != .editing) return error.NotEditing;
    }

    fn requireRevisionMatchesView(
        self: *const State,
        revision: *const taxpayer_year.Revision,
    ) Error!void {
        try revision.validate();
        if (!self.opened or
            !revision.stream.eql(&self.identity.?.stream) or
            !revision.effectiveOn(self.identity.?.effective_on))
        {
            return error.WrongViewedIdentity;
        }
        if (revision.values.len > max_setting_values) {
            return error.TooManyValues;
        }
    }

    fn loadBaseline(
        self: *State,
        revision: *const taxpayer_year.Revision,
    ) Error!void {
        if (revision.values.len > self.baseline_values.len) {
            return error.TooManyValues;
        }
        // Save revisions may borrow this state's draft slice. Snapshot before
        // updating either buffer so the transition remains alias-safe.
        var values: [max_setting_values]taxpayer_year.SettingValue = undefined;
        @memcpy(values[0..revision.values.len], revision.values);
        @memcpy(self.baseline_values[0..revision.values.len], values[0..revision.values.len]);
        @memcpy(self.draft_values[0..revision.values.len], values[0..revision.values.len]);
        self.baseline_value_count = revision.values.len;
        self.draft_value_count = revision.values.len;
        self.baseline_confirmed = revision.review_state == .confirmed;
        self.history_exists = true;
        self.expected_sequence = revision.sequence;
        self.identity.?.revision_id = revision.id;
        self.identity.?.revision_sequence = revision.sequence;

        const derived_review: ReviewRequirement = switch (revision.review_state) {
            .confirmed => .none,
            .requires_review => .persisted_unconfirmed_revision,
        };
        self.baseline_review_requirement = derived_review;
        self.draft_review_requirement = derived_review;
        self.baseline_review_acknowledged = derived_review == .none;
        self.draft_review_acknowledged = derived_review == .none;
        self.persisted_copy_source = switch (revision.source) {
            .copied_from_prior_year => |copy| copy,
            .manual_entry, .imported, .migrated => null,
        };
        self.baseline_copy_source = self.persisted_copy_source;
        self.draft_copy_source = self.baseline_copy_source;
    }

    fn loadCopyOffer(
        self: *State,
        source: *const taxpayer_year.Revision,
    ) Error!void {
        try source.validate();
        if (source.review_state != .confirmed or
            !source.stream.profile_id.eql(&self.identity.?.stream.profile_id) or
            @as(u32, source.stream.tax_year) + 1 !=
                self.identity.?.stream.tax_year or
            source.sequence == 0)
        {
            return error.InvalidCopySource;
        }
        if (source.values.len > self.copy_offer_values.len) {
            return error.TooManyValues;
        }
        @memcpy(self.copy_offer_values[0..source.values.len], source.values);
        self.copy_offer_value_count = source.values.len;
        self.copy_offer_source = .{
            .stream = source.stream,
            .revision_id = source.id,
            .revision_sequence = source.sequence,
        };
    }

    fn basePageState(self: *const State) PageState {
        if (!self.profile_active) return .inactive_history_only;
        if (!self.consumption.hasActiveConsumers()) {
            return .no_consuming_forms;
        }
        const current = readinessFor(
            self.consumption,
            self.baselineValues(),
            self.baseline_confirmed,
            self.baseline_review_requirement,
            self.baseline_review_acknowledged,
        );
        if (current.review_required) return .requires_review;
        if (current.ready()) return .viewing_ready;
        return .needs_settings;
    }

    fn noteDraftMutation(self: *State) void {
        if (self.save_status == .failed and self.conflict == null) {
            self.save_status = .idle;
        }
    }
};

fn emptyAffordances() Affordances {
    return .{
        .can_view_history = false,
        .can_edit = false,
        .can_save = false,
        .can_cancel = false,
        .can_copy_prior_year = false,
        .can_acknowledge_review = false,
        .can_reload_conflict = false,
        .can_rebase_conflict = false,
    };
}

fn readinessFor(
    consumption: Consumption,
    values: []const taxpayer_year.SettingValue,
    confirmed: bool,
    review_requirement: ReviewRequirement,
    review_acknowledged: bool,
) Readiness {
    const election = findElection(values);
    const deduction_required = consumption.deduction_method_when_graduated and
        election == .graduated;
    var required_count: u8 = 0;
    var supplied_count: u8 = 0;
    if (consumption.income_tax_rate_election) {
        required_count += 1;
        if (election != null) supplied_count += 1;
    }
    if (deduction_required) {
        required_count += 1;
        if (findDeduction(values) != null) supplied_count += 1;
    }
    return .{
        .applicable = true,
        .active_consumer_count = consumption.active_form_count,
        .required_count = required_count,
        .supplied_required_count = supplied_count,
        .missing_required_count = required_count - supplied_count,
        .supplied_value_count = @intCast(values.len),
        .candidate_valid = valueSetValid(values),
        .has_confirmed_revision = confirmed,
        .review_required = review_requirement != .none and
            !review_acknowledged,
    };
}

fn validateValueSetShape(
    values: []const taxpayer_year.SettingValue,
) Error!void {
    if (values.len > max_setting_values) return error.TooManyValues;
    for (values, 0..) |value, index| {
        for (values[index + 1 ..]) |other| {
            if (value.key() == other.key()) return error.DuplicateSetting;
        }
    }
}

fn valueSetValid(values: []const taxpayer_year.SettingValue) bool {
    validateValueSetShape(values) catch return false;
    const deduction = findDeduction(values);
    if (deduction != null and findElection(values) != .graduated) return false;
    return true;
}

fn findElection(
    values: []const taxpayer_year.SettingValue,
) ?taxpayer_year.IncomeTaxRateElection {
    for (values) |value| switch (value) {
        .income_tax_rate_election => |election| return election,
        .deduction_method => {},
    };
    return null;
}

fn findDeduction(
    values: []const taxpayer_year.SettingValue,
) ?taxpayer_year.DeductionMethod {
    for (values) |value| switch (value) {
        .income_tax_rate_election => {},
        .deduction_method => |deduction| return deduction,
    };
    return null;
}

fn valueSetsEqual(
    left: []const taxpayer_year.SettingValue,
    right: []const taxpayer_year.SettingValue,
) bool {
    if (left.len != right.len) return false;
    for (left) |value| {
        var found = false;
        for (right) |other| {
            if (settingValueEql(value, other)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn settingValueEql(
    left: taxpayer_year.SettingValue,
    right: taxpayer_year.SettingValue,
) bool {
    if (left.key() != right.key()) return false;
    return switch (left) {
        .income_tax_rate_election => |value| switch (right) {
            .income_tax_rate_election => |other| value == other,
            else => false,
        },
        .deduction_method => |value| switch (right) {
            .deduction_method => |other| value == other,
            else => false,
        },
    };
}

fn optionalCopySourceEql(
    left: ?PriorYearCopyIdentity,
    right: ?PriorYearCopyIdentity,
) bool {
    if (left == null or right == null) return left == null and right == null;
    return left.?.stream.eql(&right.?.stream) and
        left.?.revision_id.eql(&right.?.revision_id) and
        left.?.revision_sequence == right.?.revision_sequence;
}

fn revisionSourceMatchesCopy(
    source: *const taxpayer_year.RevisionSource,
    expected: ?PriorYearCopyIdentity,
) bool {
    return switch (source.*) {
        .copied_from_prior_year => |copy| expected != null and
            optionalCopySourceEql(copy, expected),
        .manual_entry, .imported, .migrated => expected == null,
    };
}

fn confirmedRevision(
    profile_id: []const u8,
    tax_year: u16,
    revision_id: []const u8,
    sequence: u32,
    values: []const taxpayer_year.SettingValue,
) !taxpayer_year.Revision {
    return .{
        .id = try taxpayer_year.RevisionId.parse(revision_id),
        .stream = .{
            .profile_id = try model.ProfileId.parse(profile_id),
            .tax_year = tax_year,
        },
        .sequence = sequence,
        .effective = try taxpayer_year.fullTaxYearPeriod(tax_year),
        .review_state = .confirmed,
        .confirmed_at_unix_seconds = 1,
        .source = .manual_entry,
        .values = values,
    };
}

fn activeConsumption() Consumption {
    return .{
        .active_form_count = 3,
        .income_tax_rate_election = true,
        .deduction_method_when_graduated = true,
    };
}

fn openArgs(
    profile_id: []const u8,
    tax_year: u16,
) !OpenArgs {
    return .{
        .profile_id = try model.ProfileId.parse(profile_id),
        .tax_year = tax_year,
        .effective_on = try taxpayer_year.Date.init(tax_year, 6, 30),
        .profile_active = true,
        .consumption = activeConsumption(),
    };
}

test "confirmed settings open read-only and ready for the exact year" {
    const values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .itemized_deduction },
    };
    const revision = try confirmedRevision(
        "profile-maria",
        2026,
        "year-settings-2026-1",
        1,
        &values,
    );
    var args = try openArgs("profile-maria", 2026);
    args.saved_revision = &revision;
    var state = try State.open(args);

    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqual(ReadinessStatus.ready, state.readinessStatus());
    try std.testing.expect(state.readiness().ready());
    try std.testing.expect(!state.dirty());
    try std.testing.expect(state.affordances().can_edit);
    try std.testing.expect(!state.affordances().can_save);

    try state.beginEdit();
    try std.testing.expectEqual(PageState.editing, state.page().?);
    try std.testing.expect(!state.dirty());
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expect(!state.affordances().can_cancel);
}

test "a revision from another year or effective date is rejected" {
    const values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const revision = try confirmedRevision(
        "profile-maria",
        2025,
        "year-settings-2025-1",
        1,
        &values,
    );
    var args = try openArgs("profile-maria", 2026);
    args.saved_revision = &revision;
    try std.testing.expectError(
        error.WrongViewedIdentity,
        State.open(args),
    );

    args.saved_revision = null;
    args.effective_on = try taxpayer_year.Date.init(2025, 6, 30);
    try std.testing.expectError(error.InvalidEffectiveDate, State.open(args));
}

test "no active consuming form suppresses missing settings and editing" {
    var args = try openArgs("profile-maria", 2026);
    args.consumption = .{};
    const state = try State.open(args);

    try std.testing.expectEqual(PageState.no_consuming_forms, state.page().?);
    try std.testing.expectEqual(
        ReadinessStatus.no_consuming_forms,
        state.readinessStatus(),
    );
    try std.testing.expect(!state.readiness().applicable);
    try std.testing.expectEqual(@as(u8, 0), state.readiness().missing_required_count);
    try std.testing.expect(!state.affordances().can_edit);

    var mutable = state;
    try std.testing.expectError(error.NoConsumingForms, mutable.beginEdit());
}

test "inactive profile retains history but blocks mutation" {
    const values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const revision = try confirmedRevision(
        "profile-maria",
        2026,
        "year-settings-2026-1",
        1,
        &values,
    );
    var args = try openArgs("profile-maria", 2026);
    args.profile_active = false;
    args.saved_revision = &revision;
    var state = try State.open(args);

    try std.testing.expectEqual(PageState.inactive_history_only, state.page().?);
    try std.testing.expectEqual(ReadinessStatus.inactive, state.readinessStatus());
    try std.testing.expect(state.affordances().can_view_history);
    try std.testing.expect(!state.affordances().can_edit);
    try std.testing.expectError(error.InactiveProfile, state.beginEdit());
}

test "dirty Cancel restores the persisted baseline without leaving the page" {
    const values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const revision = try confirmedRevision(
        "profile-maria",
        2026,
        "year-settings-2026-1",
        1,
        &values,
    );
    var args = try openArgs("profile-maria", 2026);
    args.saved_revision = &revision;
    var state = try State.open(args);
    try state.beginEdit();
    try state.setDraftValue(.{ .income_tax_rate_election = .graduated });

    try std.testing.expect(state.dirty());
    try std.testing.expectEqual(@as(u8, 1), state.readiness().missing_required_count);
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expect(state.affordances().can_cancel);
    try state.cancel();

    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expect(!state.dirty());
    try std.testing.expectEqual(
        taxpayer_year.IncomeTaxRateElection.eight_percent,
        findElection(state.baselineValues()).?,
    );
}

test "graduated election conditionally requires deduction and rejects stale deduction" {
    var state = try State.open(try openArgs("profile-maria", 2026));
    try state.beginEdit();
    try state.setDraftValue(.{ .income_tax_rate_election = .graduated });
    try std.testing.expectEqual(@as(u8, 2), state.readiness().required_count);
    try std.testing.expectEqual(@as(u8, 1), state.readiness().missing_required_count);
    try state.setDraftValue(.{ .deduction_method = .optional_standard_deduction });
    try std.testing.expect(state.readiness().candidateComplete());
    try std.testing.expect(state.affordances().can_save);

    try state.setDraftValue(.{ .income_tax_rate_election = .eight_percent });
    try std.testing.expect(!state.readiness().candidate_valid);
    try std.testing.expect(!state.affordances().can_save);
    try state.removeDraftSetting(.deduction_method);
    try std.testing.expect(state.readiness().candidateComplete());
    try std.testing.expect(state.affordances().can_save);
}

test "prior-year copy is explicit review-gated and retains exact source" {
    const prior_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .optional_standard_deduction },
    };
    const source = try confirmedRevision(
        "profile-maria",
        2025,
        "year-settings-2025-4",
        4,
        &prior_values,
    );
    var args = try openArgs("profile-maria", 2026);
    args.copy_offer = &source;
    var state = try State.open(args);

    try std.testing.expect(state.affordances().can_copy_prior_year);
    try std.testing.expectEqual(
        @as(u16, 2025),
        state.priorYearCopyOffer().?.stream.tax_year,
    );
    try state.stagePriorYearCopy();
    try std.testing.expect(state.dirty());
    try std.testing.expect(state.readiness().review_required);
    try std.testing.expect(state.affordances().can_acknowledge_review);
    try std.testing.expect(!state.affordances().can_save);
    try state.acknowledgeReview();
    try std.testing.expect(!state.readiness().review_required);
    try std.testing.expect(state.affordances().can_save);

    const intent = try state.beginSave();
    try std.testing.expectEqual(@as(u32, 0), intent.expected_sequence);
    try std.testing.expectEqual(ReviewRequirement.prior_year_copy, intent.review_requirement);
    try std.testing.expectEqual(@as(u16, 2025), intent.reviewed_copy_source.?.stream.tax_year);
    try std.testing.expectEqual(@as(u32, 4), intent.reviewed_copy_source.?.revision_sequence);
    try std.testing.expectEqualStrings(
        "year-settings-2025-4",
        intent.reviewed_copy_source.?.revision_id.asSlice(),
    );

    const saved = try intent.confirmedRevision(
        try taxpayer_year.RevisionId.parse("year-settings-2026-1"),
        42,
    );
    try saved.validate();
    var provenance_dropped = saved;
    provenance_dropped.source = .manual_entry;
    try std.testing.expectError(
        error.WrongSavedRevision,
        state.saveSucceeded(&provenance_dropped),
    );
    try state.saveSucceeded(&saved);
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqual(@as(u16, 2025), state.persistedCopySource().?.stream.tax_year);
    try std.testing.expectEqualStrings(
        "year-settings-2025-4",
        state.persistedCopySource().?.revision_id.asSlice(),
    );
}

test "persisted copied proposal remains review-required until acknowledged" {
    const values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const source_stream: taxpayer_year.StreamKey = .{
        .profile_id = try model.ProfileId.parse("profile-maria"),
        .tax_year = 2025,
    };
    const revision: taxpayer_year.Revision = .{
        .id = try taxpayer_year.RevisionId.parse("year-settings-2026-copy"),
        .stream = .{
            .profile_id = source_stream.profile_id,
            .tax_year = 2026,
        },
        .sequence = 1,
        .effective = try taxpayer_year.fullTaxYearPeriod(2026),
        .review_state = .requires_review,
        .confirmed_at_unix_seconds = null,
        .source = .{ .copied_from_prior_year = .{
            .stream = source_stream,
            .revision_id = try taxpayer_year.RevisionId.parse("year-settings-2025-1"),
            .revision_sequence = 1,
        } },
        .values = &values,
    };
    var args = try openArgs("profile-maria", 2026);
    args.saved_revision = &revision;
    var state = try State.open(args);

    try std.testing.expectEqual(PageState.requires_review, state.page().?);
    try std.testing.expectEqual(ReadinessStatus.requires_review, state.readinessStatus());
    try std.testing.expectEqual(@as(u16, 2025), state.persistedCopySource().?.stream.tax_year);
    try state.beginEdit();
    try std.testing.expect(!state.affordances().can_save);
    try state.acknowledgeReview();
    try std.testing.expect(state.dirty());
    try std.testing.expect(state.affordances().can_save);

    const intent = try state.beginSave();
    const confirmed = try intent.confirmedRevision(
        try taxpayer_year.RevisionId.parse("year-settings-2026-confirmed"),
        2,
    );
    try state.saveSucceeded(&confirmed);
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqual(ReadinessStatus.ready, state.readinessStatus());
    try std.testing.expectEqual(
        @as(u16, 2025),
        state.persistedCopySource().?.stream.tax_year,
    );
}

test "Keep Draft rebases the exact saved baseline and Cancel never restores stale data" {
    const values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const revision = try confirmedRevision(
        "profile-maria",
        2026,
        "year-settings-2026-1",
        1,
        &values,
    );
    var args = try openArgs("profile-maria", 2026);
    args.saved_revision = &revision;
    var state = try State.open(args);
    try state.beginEdit();
    try state.setDraftValue(.{ .income_tax_rate_election = .graduated });
    try state.setDraftValue(.{ .deduction_method = .optional_standard_deduction });
    _ = try state.beginSave();
    try state.noteConflict(3);

    try std.testing.expectEqual(ReadinessStatus.conflict, state.readinessStatus());
    try std.testing.expect(state.dirty());
    try std.testing.expectEqual(
        taxpayer_year.IncomeTaxRateElection.graduated,
        findElection(state.draftValues()).?,
    );
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expect(!state.affordances().can_cancel);
    try std.testing.expect(state.affordances().can_rebase_conflict);
    try std.testing.expectEqual(
        @as(u32, 3),
        state.pendingConflict().?.current_sequence,
    );

    const latest_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .itemized_deduction },
    };
    const latest = try confirmedRevision(
        "profile-maria",
        2026,
        "year-settings-2026-3",
        3,
        &latest_values,
    );
    try state.keepDraftAfterConflict(&latest);
    try std.testing.expectEqual(@as(u32, 3), state.expected_sequence);
    try std.testing.expectEqual(
        taxpayer_year.DeductionMethod.itemized_deduction,
        findDeduction(state.baselineValues()).?,
    );
    try std.testing.expectEqual(
        taxpayer_year.DeductionMethod.optional_standard_deduction,
        findDeduction(state.draftValues()).?,
    );
    try std.testing.expect(state.affordances().can_save);
    try std.testing.expect(state.affordances().can_cancel);
    try state.cancel();
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqual(@as(u32, 3), state.expected_sequence);
    try std.testing.expectEqual(
        taxpayer_year.DeductionMethod.itemized_deduction,
        findDeduction(state.baselineValues()).?,
    );
}

test "conflict reload explicitly discards the draft and exits edit" {
    const old_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const latest_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .itemized_deduction },
    };
    const old = try confirmedRevision(
        "profile-maria",
        2026,
        "year-settings-2026-1",
        1,
        &old_values,
    );
    const latest = try confirmedRevision(
        "profile-maria",
        2026,
        "year-settings-2026-2",
        2,
        &latest_values,
    );
    var args = try openArgs("profile-maria", 2026);
    args.saved_revision = &old;
    var state = try State.open(args);
    try state.beginEdit();
    try state.setDraftValue(.{ .income_tax_rate_election = .graduated });
    try state.setDraftValue(.{ .deduction_method = .optional_standard_deduction });
    _ = try state.beginSave();
    try state.noteConflict(2);
    try std.testing.expect(!state.affordances().can_cancel);
    try state.reloadSavedAfterConflict(&latest);

    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expect(!state.dirty());
    try std.testing.expectEqual(@as(u32, 2), state.expected_sequence);
    try std.testing.expectEqual(
        taxpayer_year.DeductionMethod.itemized_deduction,
        findDeduction(state.baselineValues()).?,
    );
}

test "successful save accepts only the exact draft and next sequence" {
    var state = try State.open(try openArgs("profile-maria", 2026));
    try state.beginEdit();
    try state.setDraftValue(.{ .income_tax_rate_election = .eight_percent });
    _ = try state.beginSave();

    const wrong_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .itemized_deduction },
    };
    const wrong = try confirmedRevision(
        "profile-maria",
        2026,
        "year-settings-2026-wrong",
        1,
        &wrong_values,
    );
    try std.testing.expectError(error.WrongSavedRevision, state.saveSucceeded(&wrong));

    const saved_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const saved = try confirmedRevision(
        "profile-maria",
        2026,
        "year-settings-2026-1",
        1,
        &saved_values,
    );
    try state.saveSucceeded(&saved);
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqual(ReadinessStatus.ready, state.readinessStatus());
    try std.testing.expectEqualStrings(
        "year-settings-2026-1",
        state.viewedIdentity().?.revision_id.?.asSlice(),
    );
}

test "invalid consumption cannot create phantom missing settings" {
    var args = try openArgs("profile-maria", 2026);
    args.consumption = .{
        .active_form_count = 0,
        .income_tax_rate_election = true,
    };
    try std.testing.expectError(error.InvalidConsumption, State.open(args));

    args.consumption = .{
        .active_form_count = 1,
        .deduction_method_when_graduated = true,
    };
    try std.testing.expectError(error.InvalidConsumption, State.open(args));
}
