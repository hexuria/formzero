//! Allocation-free view/edit state for repeatable registration components.
//!
//! Persistence and Native markup deliberately live elsewhere. This module
//! copies the effective confirmed activity/obligation set into fixed storage,
//! keeps every review-required component visible in a separate read-only list,
//! and emits a borrowed save intent. A persistence adapter can translate that
//! desired state into append-only component revisions without teaching the UI
//! about database rows.

const std = @import("std");
const applicability = @import("applicability.zig");
const field = @import("field.zig");
const model = @import("model.zig");
const registration = @import("registration.zig");
const registration_adapter = @import("registration_adapter.zig");

pub const max_business_activities: usize = 24;
pub const max_registration_obligations: usize = 48;
pub const max_review_rows: usize = 96;
pub const max_read_only_facts: usize = 16;

pub const Error = registration.Error || field.TextError || field.AtcError ||
    error{
        InvalidRange,
        TooManyBusinessActivities,
        TooManyRegistrationObligations,
        TooManyReviewRows,
        TooManyReadOnlyFacts,
        DuplicateActivityAnchor,
        DuplicateObligationAnchor,
        ActivityAnchorPendingReview,
        ObligationAnchorPendingReview,
        BusinessActivityNotFound,
        RegistrationObligationNotFound,
        BusinessRegistrationNotApplicable,
        DuplicateTypedObligation,
        VatPercentageConflict,
        NotViewing,
        NotEditing,
        ActionDisabled,
        InvalidTransition,
        NoConflict,
        WrongConflictSequence,
        WrongReloadIdentity,
        WrongSavedSequence,
    };

pub const PageState = enum {
    viewing,
    editing,
};

pub const SaveStatus = enum {
    idle,
    saving,
    failed,
};

pub const Conflict = struct {
    expected_sequence: u32,
    current_sequence: u32,
};

/// Immutable component identity is retained separately from editable content.
/// It is excluded from normalized dirty comparison.
pub const Origin = struct {
    revision_id: registration.ComponentRevisionId,
    sequence: u32,
};

pub const BusinessActivityRow = struct {
    anchor_id: registration.ActivityAnchorId,
    effective: registration.EffectivePeriod,
    line_of_business: field.LineOfBusiness,
    atc: ?field.Atc = null,
    origin: ?Origin = null,
};

pub const RegistrationObligationRow = struct {
    anchor_id: registration.ObligationAnchorId,
    effective: registration.EffectivePeriod,
    kind: registration.RegistrationObligationKind,
    origin: ?Origin = null,
};

/// Closed input vocabulary for newly confirmed obligations. The ambiguous
/// legacy variants intentionally do not appear here: callers cannot turn an
/// unknown string into a filing-relevant value by merely opening the editor.
pub const TypedObligationInput = union(enum) {
    registered_income_tax,
    vat,
    percentage_tax,
    withholding_compensation,
    withholding_expanded,
    withholding_final,
    withholding_other: []const u8,
};

/// All unconfirmed components remain inspectable, including inactive-period
/// proposals. `active_on_view_date` is presentation metadata, not inference.
pub const ReviewRow = union(enum) {
    business_activity: struct {
        value: registration.BusinessActivity,
        active_on_view_date: bool,
    },
    registration_obligation: struct {
        value: registration.RegistrationObligation,
        active_on_view_date: bool,
    },
    agent_designation: struct {
        value: registration.AgentDesignationRevision,
        active_on_view_date: bool,
    },
    eopt_tier: struct {
        value: registration.EoptTierRevision,
        active_on_view_date: bool,
    },
    registration_activity_status: struct {
        value: registration.RegistrationActivityStatusRevision,
        active_on_view_date: bool,
    },
    special_law_or_treaty_basis: struct {
        value: registration.SpecialLawOrTreatyBasisRevision,
        active_on_view_date: bool,
    },

    pub fn revisionId(self: *const ReviewRow) registration.ComponentRevisionId {
        return switch (self.*) {
            inline else => |row| row.value.metadata.revision_id,
        };
    }

    pub fn isActiveOnViewDate(self: *const ReviewRow) bool {
        return switch (self.*) {
            inline else => |row| row.active_on_view_date,
        };
    }

    pub fn isUnsupportedLegacyValue(self: *const ReviewRow) bool {
        return switch (self.*) {
            .registration_obligation => |row| switch (row.value.kind) {
                .unknown_requires_review => true,
                .withholding => |value| value == .unspecified_requires_review,
                else => false,
            },
            .agent_designation => |row| row.value.value ==
                .unknown_requires_review,
            .eopt_tier => |row| row.value.value == .unknown_requires_review,
            .registration_activity_status => |row| row.value.value ==
                .unknown_requires_review,
            .special_law_or_treaty_basis => |row| switch (row.value.value) {
                .unknown_requires_review => true,
                else => false,
            },
            .business_activity => false,
        };
    }
};

/// Confirmed auxiliary registration facts are shown but are not collapsed
/// into the activity/obligation editor. They need dedicated evidence-aware
/// controls before they can safely become mutable.
pub const ReadOnlyFact = union(enum) {
    agent_designation: registration.AgentDesignationRevision,
    eopt_tier: registration.EoptTierRevision,
    registration_activity_status: registration.RegistrationActivityStatusRevision,
    special_law_or_treaty_basis: registration.SpecialLawOrTreatyBasisRevision,
};

pub const SaveIntent = struct {
    profile_id: model.ProfileId,
    viewed_on: model.Date,
    /// When present, the editor owns every confirmed activity and obligation
    /// selected for this tax year, including rows that are no longer active
    /// on `viewed_on`. Persistence must diff against the same year projection
    /// instead of silently falling back to one day such as December 31.
    selected_tax_year: ?u16 = null,
    expected_sequence: u32,
    /// Complete normalized desired sets, keyed by stable anchors. The adapter
    /// compares them with persisted state and appends changes/retirements.
    business_activities: []const BusinessActivityRow,
    registration_obligations: []const RegistrationObligationRow,
    /// Review-required rows are deliberately carried through untouched so a
    /// save implementation cannot accidentally treat absence as resolution.
    retained_review_rows: []const ReviewRow,
};

pub const Affordances = struct {
    show_business_activity_section: bool,
    show_registration_obligation_section: bool,
    show_review_required_section: bool,
    can_begin_edit: bool,
    can_add_business_activity: bool,
    can_add_registration_obligation: bool,
    can_modify_business_activities: bool,
    can_modify_registration_obligations: bool,
    can_save: bool,
    can_cancel: bool,
    can_reload_conflict: bool,
    can_rebase_conflict: bool,
};

pub const OpenArgs = struct {
    aggregate: *const registration.RegistrationAggregate,
    viewed_on: model.Date,
    /// Registration & Forms is a tax-year workspace, not an as-of-day screen.
    /// A selected year keeps confirmed finite intervals visible even when
    /// their last day is earlier than `viewed_on`.
    selected_tax_year: ?u16 = null,
    subject_kind: model.SubjectKind,
    natural_person_classification: model.NaturalPersonClassification =
        .classification_unknown,
    /// Registration stream revision, supplied by persistence. Component
    /// sequences remain component-local and are never guessed into this value.
    expected_sequence: u32 = 0,
};

pub const CompositionOpenArgs = struct {
    composition: *const registration_adapter.OwnedComposition,
    viewed_on: model.Date,
    selected_tax_year: ?u16 = null,
    subject_kind: model.SubjectKind,
    natural_person_classification: model.NaturalPersonClassification =
        .classification_unknown,
    expected_sequence: u32 = 0,
};

pub const State = struct {
    opened: bool = false,
    page_state: PageState = .viewing,
    save_status: SaveStatus = .idle,
    conflict: ?Conflict = null,

    profile_id: model.ProfileId = undefined,
    viewed_on: model.Date = undefined,
    selected_tax_year: ?u16 = null,
    subject_kind: model.SubjectKind = .individual,
    natural_person_classification: model.NaturalPersonClassification =
        .classification_unknown,
    expected_sequence: u32 = 0,

    baseline_activities: [max_business_activities]BusinessActivityRow = undefined,
    baseline_activity_count: usize = 0,
    draft_activities: [max_business_activities]BusinessActivityRow = undefined,
    draft_activity_count: usize = 0,

    baseline_obligations: [max_registration_obligations]RegistrationObligationRow =
        undefined,
    baseline_obligation_count: usize = 0,
    draft_obligations: [max_registration_obligations]RegistrationObligationRow =
        undefined,
    draft_obligation_count: usize = 0,

    review_rows: [max_review_rows]ReviewRow = undefined,
    review_row_count: usize = 0,
    read_only_facts: [max_read_only_facts]ReadOnlyFact = undefined,
    read_only_fact_count: usize = 0,

    pub fn open(args: OpenArgs) Error!State {
        try args.aggregate.validate();
        var result: State = .{
            .opened = true,
            .profile_id = args.aggregate.profile_id,
            .viewed_on = args.viewed_on,
            .selected_tax_year = args.selected_tax_year,
            .subject_kind = args.subject_kind,
            .natural_person_classification = args.natural_person_classification,
            .expected_sequence = args.expected_sequence,
        };
        try result.loadAggregate(args.aggregate);
        result.restoreExactBaseline();
        return result;
    }

    pub fn openFromComposition(args: CompositionOpenArgs) Error!State {
        return open(.{
            .aggregate = &args.composition.aggregate,
            .viewed_on = args.viewed_on,
            .selected_tax_year = args.selected_tax_year,
            .subject_kind = args.subject_kind,
            .natural_person_classification = args.natural_person_classification,
            .expected_sequence = args.expected_sequence,
        });
    }

    pub fn businessActivities(self: *const State) []const BusinessActivityRow {
        return if (self.page_state == .editing)
            self.draft_activities[0..self.draft_activity_count]
        else
            self.baseline_activities[0..self.baseline_activity_count];
    }

    pub fn registrationObligations(
        self: *const State,
    ) []const RegistrationObligationRow {
        return if (self.page_state == .editing)
            self.draft_obligations[0..self.draft_obligation_count]
        else
            self.baseline_obligations[0..self.baseline_obligation_count];
    }

    pub fn reviewRequiredRows(self: *const State) []const ReviewRow {
        return self.review_rows[0..self.review_row_count];
    }

    pub fn confirmedReadOnlyFacts(self: *const State) []const ReadOnlyFact {
        return self.read_only_facts[0..self.read_only_fact_count];
    }

    pub fn beginEdit(self: *State) Error!void {
        if (!self.opened or self.page_state != .viewing) {
            return error.NotViewing;
        }
        self.restoreExactBaseline();
        self.page_state = .editing;
        self.save_status = .idle;
        self.conflict = null;
    }

    pub fn addBusinessActivity(
        self: *State,
        anchor_id: registration.ActivityAnchorId,
        line_of_business: []const u8,
        atc: ?[]const u8,
        effective: registration.EffectivePeriod,
    ) Error!void {
        try self.requireBusinessMutation();
        if (findActivity(self.draftActivitiesMut(), &anchor_id) != null) {
            return error.DuplicateActivityAnchor;
        }
        if (self.reviewHasActivityAnchor(&anchor_id)) {
            return error.ActivityAnchorPendingReview;
        }
        if (self.draft_activity_count == self.draft_activities.len) {
            return error.TooManyBusinessActivities;
        }
        self.draft_activities[self.draft_activity_count] = .{
            .anchor_id = anchor_id,
            .effective = try normalizePeriod(effective),
            .line_of_business = try field.LineOfBusiness.parse(
                line_of_business,
            ),
            .atc = try parseOptionalAtc(atc),
            .origin = self.baselineActivityOrigin(&anchor_id),
        };
        self.draft_activity_count += 1;
        self.noteMutation();
    }

    pub fn updateBusinessActivity(
        self: *State,
        anchor_id: registration.ActivityAnchorId,
        line_of_business: []const u8,
        atc: ?[]const u8,
        effective: registration.EffectivePeriod,
    ) Error!void {
        try self.requireBusinessMutation();
        const normalized_line = try field.LineOfBusiness.parse(
            line_of_business,
        );
        const normalized_atc = try parseOptionalAtc(atc);
        const normalized_effective = try normalizePeriod(effective);
        const row = findActivity(self.draftActivitiesMut(), &anchor_id) orelse
            return error.BusinessActivityNotFound;
        row.line_of_business = normalized_line;
        row.atc = normalized_atc;
        row.effective = normalized_effective;
        self.noteMutation();
    }

    pub fn removeBusinessActivity(
        self: *State,
        anchor_id: registration.ActivityAnchorId,
    ) Error!void {
        try self.requireBusinessMutation();
        const index = findActivityIndex(
            self.draftActivitiesMut(),
            &anchor_id,
        ) orelse return error.BusinessActivityNotFound;
        removeAt(
            BusinessActivityRow,
            &self.draft_activities,
            &self.draft_activity_count,
            index,
        );
        self.noteMutation();
    }

    pub fn addRegistrationObligation(
        self: *State,
        anchor_id: registration.ObligationAnchorId,
        input: TypedObligationInput,
        effective: registration.EffectivePeriod,
    ) Error!void {
        try self.requireObligationMutation();
        if (findObligation(self.draftObligationsMut(), &anchor_id) != null) {
            return error.DuplicateObligationAnchor;
        }
        if (self.reviewHasObligationAnchor(&anchor_id)) {
            return error.ObligationAnchorPendingReview;
        }
        if (self.draft_obligation_count == self.draft_obligations.len) {
            return error.TooManyRegistrationObligations;
        }
        self.draft_obligations[self.draft_obligation_count] = .{
            .anchor_id = anchor_id,
            .effective = try normalizePeriod(effective),
            .kind = try obligationKindFromInput(input),
            .origin = self.baselineObligationOrigin(&anchor_id),
        };
        self.draft_obligation_count += 1;
        self.validateDraftObligations() catch |err| {
            self.draft_obligation_count -= 1;
            return err;
        };
        self.noteMutation();
    }

    pub fn updateRegistrationObligation(
        self: *State,
        anchor_id: registration.ObligationAnchorId,
        input: TypedObligationInput,
        effective: registration.EffectivePeriod,
    ) Error!void {
        try self.requireObligationMutation();
        const normalized_kind = try obligationKindFromInput(input);
        const normalized_effective = try normalizePeriod(effective);
        const row = findObligation(
            self.draftObligationsMut(),
            &anchor_id,
        ) orelse return error.RegistrationObligationNotFound;
        const old_kind = row.kind;
        const old_effective = row.effective;
        row.kind = normalized_kind;
        row.effective = normalized_effective;
        self.validateDraftObligations() catch |err| {
            row.kind = old_kind;
            row.effective = old_effective;
            return err;
        };
        self.noteMutation();
    }

    pub fn removeRegistrationObligation(
        self: *State,
        anchor_id: registration.ObligationAnchorId,
    ) Error!void {
        try self.requireObligationMutation();
        const index = findObligationIndex(
            self.draftObligationsMut(),
            &anchor_id,
        ) orelse return error.RegistrationObligationNotFound;
        removeAt(
            RegistrationObligationRow,
            &self.draft_obligations,
            &self.draft_obligation_count,
            index,
        );
        self.noteMutation();
    }

    /// Parsed values and stable-anchor sets are compared independent of row
    /// ordering and immutable origin metadata.
    pub fn dirty(self: *const State) bool {
        if (!self.opened or self.page_state != .editing) return false;
        return !activitySetsEqual(
            self.baseline_activities[0..self.baseline_activity_count],
            self.draft_activities[0..self.draft_activity_count],
        ) or !obligationSetsEqual(
            self.baseline_obligations[0..self.baseline_obligation_count],
            self.draft_obligations[0..self.draft_obligation_count],
        );
    }

    pub fn affordances(self: *const State) Affordances {
        const existing_activity = self.baseline_activity_count != 0 or
            self.draft_activity_count != 0 or self.hasActivityReviewRow();
        const existing_obligation = self.baseline_obligation_count != 0 or
            self.draft_obligation_count != 0 or self.hasObligationReviewRow();
        const activity_policy_context: applicability.Context = .{
            .subject_kind = self.subject_kind,
            .natural_person_classification = self.natural_person_classification,
            .has_business_activity = existing_activity,
        };
        const obligation_policy_context: applicability.Context = .{
            .subject_kind = self.subject_kind,
            .natural_person_classification = self.natural_person_classification,
            .has_business_activity = existing_obligation,
        };
        const subject_allows_mutation = self.subjectAllowsBusinessMutation();
        const editing = self.opened and self.page_state == .editing;
        const idle_enough = self.save_status != .saving;
        const has_conflict = self.conflict != null;
        const valid = self.validateDraftObligationsAsBool();
        return .{
            .show_business_activity_section = applicability.fieldGroupVisible(
                activity_policy_context,
                .business_activities,
            ),
            .show_registration_obligation_section = applicability.fieldGroupVisible(
                obligation_policy_context,
                .registration_obligations,
            ),
            .show_review_required_section = self.review_row_count != 0,
            .can_begin_edit = self.opened and self.page_state == .viewing,
            .can_add_business_activity = editing and idle_enough and
                subject_allows_mutation,
            .can_add_registration_obligation = editing and idle_enough and
                subject_allows_mutation,
            .can_modify_business_activities = editing and idle_enough and
                subject_allows_mutation,
            .can_modify_registration_obligations = editing and idle_enough and
                subject_allows_mutation,
            .can_save = editing and idle_enough and self.dirty() and valid and
                !has_conflict,
            .can_cancel = editing and idle_enough and self.dirty(),
            .can_reload_conflict = has_conflict,
            .can_rebase_conflict = has_conflict,
        };
    }

    /// Dirty Cancel restores exact captured row order, values, anchors,
    /// origins, and effectivity, then returns to read-only view in place.
    pub fn cancel(self: *State) Error!void {
        try self.requireEditing();
        if (!self.affordances().can_cancel) return error.ActionDisabled;
        self.restoreExactBaseline();
        self.page_state = .viewing;
        self.save_status = .idle;
        self.conflict = null;
    }

    pub fn beginSave(self: *State) Error!SaveIntent {
        try self.requireEditing();
        if (!self.affordances().can_save) return error.ActionDisabled;
        try self.validateDraftObligations();
        self.save_status = .saving;
        return .{
            .profile_id = self.profile_id,
            .viewed_on = self.viewed_on,
            .selected_tax_year = self.selected_tax_year,
            .expected_sequence = self.expected_sequence,
            .business_activities = self.draft_activities[0..self.draft_activity_count],
            .registration_obligations = self.draft_obligations[0..self.draft_obligation_count],
            .retained_review_rows = self.reviewRequiredRows(),
        };
    }

    pub fn saveFailed(self: *State) Error!void {
        try self.requireEditing();
        if (self.save_status != .saving) return error.InvalidTransition;
        self.save_status = .failed;
    }

    pub fn noteConflict(
        self: *State,
        current_sequence: u32,
    ) Error!void {
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

    /// Explicit caller-reviewed rebase keeps every draft byte and changes only
    /// the optimistic base sequence.
    pub fn acceptReviewedConflictBase(
        self: *State,
        current_sequence: u32,
    ) Error!void {
        try self.requireEditing();
        const conflict = self.conflict orelse return error.NoConflict;
        if (conflict.current_sequence != current_sequence) {
            return error.WrongConflictSequence;
        }
        self.expected_sequence = current_sequence;
        self.conflict = null;
        self.save_status = .idle;
    }

    /// Explicit reload replaces the dirty editor with the exact latest
    /// aggregate and returns to read-only view.
    pub fn reloadAfterConflict(
        self: *State,
        args: OpenArgs,
    ) Error!void {
        try self.requireEditing();
        const conflict = self.conflict orelse return error.NoConflict;
        if (args.expected_sequence != conflict.current_sequence) {
            return error.WrongConflictSequence;
        }
        if (!args.aggregate.profile_id.eql(&self.profile_id)) {
            return error.WrongReloadIdentity;
        }
        self.* = try open(args);
    }

    /// Commits the saved desired set as the new local baseline. Review rows
    /// remain untouched; callers reopen from persistence when a save also
    /// resolves or imports review evidence.
    pub fn saveSucceeded(self: *State, new_sequence: u32) Error!void {
        try self.requireEditing();
        if (self.save_status != .saving) return error.InvalidTransition;
        if (self.expected_sequence == std.math.maxInt(u32) or
            new_sequence != self.expected_sequence + 1)
        {
            return error.WrongSavedSequence;
        }
        copyRows(
            BusinessActivityRow,
            &self.baseline_activities,
            self.draft_activities[0..self.draft_activity_count],
        );
        self.baseline_activity_count = self.draft_activity_count;
        copyRows(
            RegistrationObligationRow,
            &self.baseline_obligations,
            self.draft_obligations[0..self.draft_obligation_count],
        );
        self.baseline_obligation_count = self.draft_obligation_count;
        self.expected_sequence = new_sequence;
        self.page_state = .viewing;
        self.save_status = .idle;
        self.conflict = null;
    }

    fn loadAggregate(
        self: *State,
        aggregate: *const registration.RegistrationAggregate,
    ) Error!void {
        if (self.selected_tax_year != null) {
            for (aggregate.business_activities) |*activity| {
                if (!activity.metadata.review.isConfirmed()) continue;
                try self.appendBaselineActivity(activity);
            }
            for (aggregate.obligations) |*obligation| {
                if (!obligation.metadata.review.isConfirmed()) continue;
                try self.appendBaselineObligation(obligation);
            }
        } else {
            for (aggregate.activity_anchors) |anchor| {
                const resolved = try aggregate.resolveActivity(
                    anchor.id,
                    self.viewed_on,
                );
                if (resolved.confirmed) |activity| {
                    try self.appendBaselineActivity(activity);
                }
            }
            for (aggregate.obligation_anchors) |anchor| {
                const resolved = try aggregate.resolveObligation(
                    anchor.id,
                    self.viewed_on,
                );
                if (resolved.confirmed) |obligation| {
                    try self.appendBaselineObligation(obligation);
                }
            }
        }

        for (aggregate.business_activities) |activity| {
            if (!activity.metadata.review.isConfirmed()) {
                try self.appendReviewRow(.{ .business_activity = .{
                    .value = activity,
                    .active_on_view_date = activity.metadata.isEffective(
                        self.viewed_on,
                    ),
                } });
            }
        }
        for (aggregate.obligations) |obligation| {
            if (!obligation.metadata.review.isConfirmed()) {
                try self.appendReviewRow(.{ .registration_obligation = .{
                    .value = obligation,
                    .active_on_view_date = obligation.metadata.isEffective(
                        self.viewed_on,
                    ),
                } });
            }
        }
        try self.loadAuxiliaryFacts(aggregate);
    }

    fn loadAuxiliaryFacts(
        self: *State,
        aggregate: *const registration.RegistrationAggregate,
    ) Error!void {
        if (self.selected_tax_year != null) {
            for (aggregate.agent_designations) |value| {
                if (value.metadata.review.isConfirmed()) {
                    try self.appendReadOnlyFact(.{ .agent_designation = value });
                }
            }
            for (aggregate.eopt_tiers) |value| {
                if (value.metadata.review.isConfirmed()) {
                    try self.appendReadOnlyFact(.{ .eopt_tier = value });
                }
            }
            for (aggregate.registration_activity_statuses) |value| {
                if (value.metadata.review.isConfirmed()) {
                    try self.appendReadOnlyFact(.{
                        .registration_activity_status = value,
                    });
                }
            }
            for (aggregate.special_law_or_treaty_bases) |value| {
                if (value.metadata.review.isConfirmed()) {
                    try self.appendReadOnlyFact(.{
                        .special_law_or_treaty_basis = value,
                    });
                }
            }
        } else {
            if ((try aggregate.resolveAgentDesignation(self.viewed_on)).confirmed) |value| {
                try self.appendReadOnlyFact(.{ .agent_designation = value.* });
            }
            if ((try aggregate.resolveEoptTier(self.viewed_on)).confirmed) |value| {
                try self.appendReadOnlyFact(.{ .eopt_tier = value.* });
            }
            if ((try aggregate.resolveRegistrationActivityStatus(
                self.viewed_on,
            )).confirmed) |value| {
                try self.appendReadOnlyFact(.{
                    .registration_activity_status = value.*,
                });
            }
            if ((try aggregate.resolveSpecialLawOrTreatyBasis(
                self.viewed_on,
            )).confirmed) |value| {
                try self.appendReadOnlyFact(.{
                    .special_law_or_treaty_basis = value.*,
                });
            }
        }

        for (aggregate.agent_designations) |value| {
            if (!value.metadata.review.isConfirmed()) {
                try self.appendReviewRow(.{ .agent_designation = .{
                    .value = value,
                    .active_on_view_date = value.metadata.isEffective(
                        self.viewed_on,
                    ),
                } });
            }
        }
        for (aggregate.eopt_tiers) |value| {
            if (!value.metadata.review.isConfirmed()) {
                try self.appendReviewRow(.{ .eopt_tier = .{
                    .value = value,
                    .active_on_view_date = value.metadata.isEffective(
                        self.viewed_on,
                    ),
                } });
            }
        }
        for (aggregate.registration_activity_statuses) |value| {
            if (!value.metadata.review.isConfirmed()) {
                try self.appendReviewRow(.{
                    .registration_activity_status = .{
                        .value = value,
                        .active_on_view_date = value.metadata.isEffective(
                            self.viewed_on,
                        ),
                    },
                });
            }
        }
        for (aggregate.special_law_or_treaty_bases) |value| {
            if (!value.metadata.review.isConfirmed()) {
                try self.appendReviewRow(.{
                    .special_law_or_treaty_basis = .{
                        .value = value,
                        .active_on_view_date = value.metadata.isEffective(
                            self.viewed_on,
                        ),
                    },
                });
            }
        }
    }

    fn appendBaselineActivity(
        self: *State,
        activity: *const registration.BusinessActivity,
    ) Error!void {
        if (self.baseline_activity_count == self.baseline_activities.len) {
            return error.TooManyBusinessActivities;
        }
        self.baseline_activities[self.baseline_activity_count] = .{
            .anchor_id = activity.anchor_id,
            .effective = activity.metadata.effective,
            .line_of_business = activity.line_of_business,
            .atc = activity.atc,
            .origin = .{
                .revision_id = activity.metadata.revision_id,
                .sequence = activity.metadata.sequence,
            },
        };
        self.baseline_activity_count += 1;
    }

    fn appendBaselineObligation(
        self: *State,
        obligation: *const registration.RegistrationObligation,
    ) Error!void {
        if (self.baseline_obligation_count == self.baseline_obligations.len) {
            return error.TooManyRegistrationObligations;
        }
        self.baseline_obligations[self.baseline_obligation_count] = .{
            .anchor_id = obligation.anchor_id,
            .effective = obligation.metadata.effective,
            .kind = obligation.kind,
            .origin = .{
                .revision_id = obligation.metadata.revision_id,
                .sequence = obligation.metadata.sequence,
            },
        };
        self.baseline_obligation_count += 1;
    }

    fn appendReviewRow(self: *State, row: ReviewRow) Error!void {
        if (self.review_row_count == self.review_rows.len) {
            return error.TooManyReviewRows;
        }
        self.review_rows[self.review_row_count] = row;
        self.review_row_count += 1;
    }

    fn appendReadOnlyFact(self: *State, row: ReadOnlyFact) Error!void {
        if (self.read_only_fact_count == self.read_only_facts.len) {
            return error.TooManyReadOnlyFacts;
        }
        self.read_only_facts[self.read_only_fact_count] = row;
        self.read_only_fact_count += 1;
    }

    fn restoreExactBaseline(self: *State) void {
        copyRows(
            BusinessActivityRow,
            &self.draft_activities,
            self.baseline_activities[0..self.baseline_activity_count],
        );
        self.draft_activity_count = self.baseline_activity_count;
        copyRows(
            RegistrationObligationRow,
            &self.draft_obligations,
            self.baseline_obligations[0..self.baseline_obligation_count],
        );
        self.draft_obligation_count = self.baseline_obligation_count;
    }

    fn requireEditing(self: *const State) Error!void {
        if (!self.opened or self.page_state != .editing) {
            return error.NotEditing;
        }
    }

    fn requireBusinessMutation(self: *State) Error!void {
        try self.requireEditing();
        if (self.save_status == .saving) return error.ActionDisabled;
        if (!self.subjectAllowsBusinessMutation()) {
            return error.BusinessRegistrationNotApplicable;
        }
    }

    fn requireObligationMutation(self: *State) Error!void {
        return self.requireBusinessMutation();
    }

    fn subjectAllowsBusinessMutation(self: *const State) bool {
        return applicability.fieldGroupVisible(.{
            .subject_kind = self.subject_kind,
            .natural_person_classification = self.natural_person_classification,
            // Existing incompatible imports make the section visible for
            // review, but never grant authority to create more values.
            .has_business_activity = false,
        }, .business_activities);
    }

    fn noteMutation(self: *State) void {
        if (self.save_status == .failed and self.conflict == null) {
            self.save_status = .idle;
        }
    }

    fn draftActivitiesMut(self: *State) []BusinessActivityRow {
        return self.draft_activities[0..self.draft_activity_count];
    }

    fn draftObligationsMut(self: *State) []RegistrationObligationRow {
        return self.draft_obligations[0..self.draft_obligation_count];
    }

    fn baselineActivityOrigin(
        self: *const State,
        anchor: *const registration.ActivityAnchorId,
    ) ?Origin {
        for (self.baseline_activities[0..self.baseline_activity_count]) |row| {
            if (row.anchor_id.eql(anchor)) return row.origin;
        }
        return null;
    }

    fn baselineObligationOrigin(
        self: *const State,
        anchor: *const registration.ObligationAnchorId,
    ) ?Origin {
        for (self.baseline_obligations[0..self.baseline_obligation_count]) |row| {
            if (row.anchor_id.eql(anchor)) return row.origin;
        }
        return null;
    }

    fn reviewHasActivityAnchor(
        self: *const State,
        anchor: *const registration.ActivityAnchorId,
    ) bool {
        for (self.reviewRequiredRows()) |row| switch (row) {
            .business_activity => |value| if (value.value.anchor_id.eql(anchor)) {
                return true;
            },
            else => {},
        };
        return false;
    }

    fn reviewHasObligationAnchor(
        self: *const State,
        anchor: *const registration.ObligationAnchorId,
    ) bool {
        for (self.reviewRequiredRows()) |row| switch (row) {
            .registration_obligation => |value| if (value.value.anchor_id.eql(
                anchor,
            )) return true,
            else => {},
        };
        return false;
    }

    fn hasActivityReviewRow(self: *const State) bool {
        for (self.reviewRequiredRows()) |row| {
            if (row == .business_activity) return true;
        }
        return false;
    }

    fn hasObligationReviewRow(self: *const State) bool {
        for (self.reviewRequiredRows()) |row| {
            if (row == .registration_obligation) return true;
        }
        return false;
    }

    fn validateDraftObligationsAsBool(self: *const State) bool {
        self.validateDraftObligations() catch return false;
        return true;
    }

    fn validateDraftObligations(self: *const State) Error!void {
        const rows = self.draft_obligations[0..self.draft_obligation_count];
        for (rows, 0..) |*left, index| {
            for (rows[index + 1 ..]) |*right| {
                if (left.anchor_id.eql(&right.anchor_id)) {
                    return error.DuplicateObligationAnchor;
                }
                if (!left.effective.overlaps(right.effective)) continue;
                if (vatPercentageConflict(&left.kind, &right.kind)) {
                    return error.VatPercentageConflict;
                }
                if (obligationKindsEqual(&left.kind, &right.kind)) {
                    return error.DuplicateTypedObligation;
                }
            }
        }
    }
};

fn copyRows(comptime T: type, destination: []T, source: []const T) void {
    std.debug.assert(source.len <= destination.len);
    for (source, 0..) |row, index| destination[index] = row;
}

fn removeAt(
    comptime T: type,
    rows: []T,
    count: *usize,
    index: usize,
) void {
    var cursor = index;
    while (cursor + 1 < count.*) : (cursor += 1) {
        rows[cursor] = rows[cursor + 1];
    }
    count.* -= 1;
}

fn normalizePeriod(
    effective: registration.EffectivePeriod,
) Error!registration.EffectivePeriod {
    return registration.EffectivePeriod.init(
        effective.from,
        effective.until,
    );
}

fn parseOptionalAtc(raw: ?[]const u8) Error!?field.Atc {
    const value = raw orelse return null;
    if (std.mem.trim(u8, value, " \t\r\n").len == 0) return null;
    return try field.Atc.parse(value);
}

fn obligationKindFromInput(
    input: TypedObligationInput,
) Error!registration.RegistrationObligationKind {
    return switch (input) {
        .registered_income_tax => .{ .registered_income_tax = {} },
        .vat => .{ .vat = {} },
        .percentage_tax => .{ .percentage_tax = {} },
        .withholding_compensation => .{
            .withholding = .{ .compensation = {} },
        },
        .withholding_expanded => .{
            .withholding = .{ .expanded = {} },
        },
        .withholding_final => .{ .withholding = .{ .final = {} } },
        .withholding_other => |value| .{
            .withholding = .{ .other = try field.TaxType.parse(value) },
        },
    };
}

fn findActivity(
    rows: []BusinessActivityRow,
    anchor: *const registration.ActivityAnchorId,
) ?*BusinessActivityRow {
    for (rows) |*row| {
        if (row.anchor_id.eql(anchor)) return row;
    }
    return null;
}

fn findActivityIndex(
    rows: []const BusinessActivityRow,
    anchor: *const registration.ActivityAnchorId,
) ?usize {
    for (rows, 0..) |*row, index| {
        if (row.anchor_id.eql(anchor)) return index;
    }
    return null;
}

fn findObligation(
    rows: []RegistrationObligationRow,
    anchor: *const registration.ObligationAnchorId,
) ?*RegistrationObligationRow {
    for (rows) |*row| {
        if (row.anchor_id.eql(anchor)) return row;
    }
    return null;
}

fn findObligationIndex(
    rows: []const RegistrationObligationRow,
    anchor: *const registration.ObligationAnchorId,
) ?usize {
    for (rows, 0..) |*row, index| {
        if (row.anchor_id.eql(anchor)) return index;
    }
    return null;
}

fn activitySetsEqual(
    left: []const BusinessActivityRow,
    right: []const BusinessActivityRow,
) bool {
    if (left.len != right.len) return false;
    for (left) |*left_row| {
        const index = findActivityIndex(right, &left_row.anchor_id) orelse
            return false;
        if (!activityContentEqual(left_row, &right[index])) return false;
    }
    return true;
}

fn activityContentEqual(
    left: *const BusinessActivityRow,
    right: *const BusinessActivityRow,
) bool {
    return left.anchor_id.eql(&right.anchor_id) and
        left.effective.eql(right.effective) and
        left.line_of_business.eql(&right.line_of_business) and
        optionalAtcEqual(left.atc, right.atc);
}

fn optionalAtcEqual(left: ?field.Atc, right: ?field.Atc) bool {
    if (left) |left_value| {
        const right_value = right orelse return false;
        return left_value.eql(&right_value);
    }
    return right == null;
}

fn obligationSetsEqual(
    left: []const RegistrationObligationRow,
    right: []const RegistrationObligationRow,
) bool {
    if (left.len != right.len) return false;
    for (left) |*left_row| {
        const index = findObligationIndex(right, &left_row.anchor_id) orelse
            return false;
        if (!obligationContentEqual(left_row, &right[index])) return false;
    }
    return true;
}

fn obligationContentEqual(
    left: *const RegistrationObligationRow,
    right: *const RegistrationObligationRow,
) bool {
    return left.anchor_id.eql(&right.anchor_id) and
        left.effective.eql(right.effective) and
        obligationKindsEqual(&left.kind, &right.kind);
}

fn obligationKindsEqual(
    left: *const registration.RegistrationObligationKind,
    right: *const registration.RegistrationObligationKind,
) bool {
    if (std.meta.activeTag(left.*) != std.meta.activeTag(right.*)) return false;
    return switch (left.*) {
        .registered_income_tax, .vat, .percentage_tax => true,
        .unknown_requires_review => |left_value| switch (right.*) {
            .unknown_requires_review => |right_value| left_value.eql(
                &right_value,
            ),
            else => unreachable,
        },
        .withholding => |left_value| switch (right.*) {
            .withholding => |right_value| withholdingKindsEqual(
                &left_value,
                &right_value,
            ),
            else => unreachable,
        },
    };
}

fn withholdingKindsEqual(
    left: *const registration.WithholdingObligation,
    right: *const registration.WithholdingObligation,
) bool {
    if (std.meta.activeTag(left.*) != std.meta.activeTag(right.*)) return false;
    return switch (left.*) {
        .compensation, .expanded, .final => true,
        .other => |left_value| switch (right.*) {
            .other => |right_value| left_value.eql(&right_value),
            else => unreachable,
        },
        .unspecified_requires_review => |left_value| switch (right.*) {
            .unspecified_requires_review => |right_value| left_value.eql(
                &right_value,
            ),
            else => unreachable,
        },
    };
}

fn vatPercentageConflict(
    left: *const registration.RegistrationObligationKind,
    right: *const registration.RegistrationObligationKind,
) bool {
    return left.* == .vat and right.* == .percentage_tax or
        left.* == .percentage_tax and right.* == .vat;
}

// -- Focused state-contract tests -----------------------------------------

fn testDate(raw: []const u8) !model.Date {
    return model.Date.parseIso(raw);
}

fn testPeriod(from: []const u8, until: ?[]const u8) !model.EffectivePeriod {
    return model.EffectivePeriod.init(
        try testDate(from),
        if (until) |value| try testDate(value) else null,
    );
}

fn testProfileId() !model.ProfileId {
    return model.ProfileId.parse("registration-ui-profile");
}

fn testMetadata(
    profile_id: model.ProfileId,
    revision_id: []const u8,
    sequence: u32,
    effective: model.EffectivePeriod,
    review: registration.ReviewState,
) !registration.RevisionMetadata {
    return .{
        .owner_profile_id = profile_id,
        .revision_id = try registration.ComponentRevisionId.parse(revision_id),
        .sequence = sequence,
        .effective = effective,
        .source = .manual_entry,
        .review = review,
    };
}

fn confirmed() registration.ReviewState {
    return .{ .confirmed = .{ .confirmed_at_unix_seconds = 1 } };
}

fn needsReview() registration.ReviewState {
    return .{ .requires_review = .migrated_without_confirmation };
}

fn emptyAggregate(profile_id: model.ProfileId) registration.RegistrationAggregate {
    return .{ .profile_id = profile_id };
}

test "registration editor defaults to read only and exposes effective confirmed rows" {
    const profile_id = try testProfileId();
    const period = try testPeriod("2026-01-01", null);
    const activity_anchor_id = try registration.ActivityAnchorId.parse(
        "activity-consulting",
    );
    const obligation_anchor_id = try registration.ObligationAnchorId.parse(
        "obligation-vat",
    );
    const activity_anchors = [_]registration.ActivityAnchor{.{
        .owner_profile_id = profile_id,
        .id = activity_anchor_id,
    }};
    const obligation_anchors = [_]registration.ObligationAnchor{.{
        .owner_profile_id = profile_id,
        .id = obligation_anchor_id,
    }};
    const activities = [_]registration.BusinessActivity{.{
        .anchor_id = activity_anchor_id,
        .metadata = try testMetadata(
            profile_id,
            "activity-revision-one",
            1,
            period,
            confirmed(),
        ),
        .line_of_business = try field.LineOfBusiness.parse("Consulting"),
        .atc = try field.Atc.parse("WI010"),
    }};
    const obligations = [_]registration.RegistrationObligation{.{
        .anchor_id = obligation_anchor_id,
        .metadata = try testMetadata(
            profile_id,
            "obligation-revision-one",
            1,
            period,
            confirmed(),
        ),
        .kind = .{ .vat = {} },
    }};
    const aggregate: registration.RegistrationAggregate = .{
        .profile_id = profile_id,
        .activity_anchors = &activity_anchors,
        .obligation_anchors = &obligation_anchors,
        .business_activities = &activities,
        .obligations = &obligations,
    };
    var state = try State.open(.{
        .aggregate = &aggregate,
        .viewed_on = try testDate("2026-08-04"),
        .subject_kind = .corporation,
        .expected_sequence = 7,
    });

    try std.testing.expectEqual(PageState.viewing, state.page_state);
    try std.testing.expect(!state.dirty());
    try std.testing.expectEqual(@as(usize, 1), state.businessActivities().len);
    try std.testing.expectEqual(
        @as(usize, 1),
        state.registrationObligations().len,
    );
    try std.testing.expectEqualStrings(
        "activity-consulting",
        state.businessActivities()[0].anchor_id.asSlice(),
    );
    try std.testing.expect(
        state.businessActivities()[0].effective.contains(
            try testDate("2026-12-31"),
        ),
    );
    const actions = state.affordances();
    try std.testing.expect(actions.can_begin_edit);
    try std.testing.expect(!actions.can_save);
    try std.testing.expect(!actions.can_cancel);
    try std.testing.expectError(
        error.NotEditing,
        state.addBusinessActivity(
            try registration.ActivityAnchorId.parse("view-mode-add"),
            "Consulting",
            null,
            period,
        ),
    );

    try state.beginEdit();
    try std.testing.expectEqual(PageState.editing, state.page_state);
    try std.testing.expect(!state.dirty());
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expect(!state.affordances().can_cancel);
}

test "registration year workspace keeps finite confirmed intervals editable" {
    const profile_id = try testProfileId();
    const finite_period = try testPeriod("2026-01-01", "2026-06-30");
    const activity_anchor_id = try registration.ActivityAnchorId.parse(
        "activity-first-half",
    );
    const obligation_anchor_id = try registration.ObligationAnchorId.parse(
        "obligation-first-half",
    );
    const activity_anchors = [_]registration.ActivityAnchor{.{
        .owner_profile_id = profile_id,
        .id = activity_anchor_id,
    }};
    const obligation_anchors = [_]registration.ObligationAnchor{.{
        .owner_profile_id = profile_id,
        .id = obligation_anchor_id,
    }};
    const activities = [_]registration.BusinessActivity{.{
        .anchor_id = activity_anchor_id,
        .metadata = try testMetadata(
            profile_id,
            "activity-first-half-r1",
            1,
            finite_period,
            confirmed(),
        ),
        .line_of_business = try field.LineOfBusiness.parse("Seasonal consulting"),
        .atc = try field.Atc.parse("PT010"),
    }};
    const obligations = [_]registration.RegistrationObligation{.{
        .anchor_id = obligation_anchor_id,
        .metadata = try testMetadata(
            profile_id,
            "obligation-first-half-r1",
            1,
            finite_period,
            confirmed(),
        ),
        .kind = .{ .percentage_tax = {} },
    }};
    const aggregate: registration.RegistrationAggregate = .{
        .profile_id = profile_id,
        .activity_anchors = &activity_anchors,
        .obligation_anchors = &obligation_anchors,
        .business_activities = &activities,
        .obligations = &obligations,
    };
    const year_end = try testDate("2026-12-31");
    var state = try State.open(.{
        .aggregate = &aggregate,
        .viewed_on = year_end,
        .selected_tax_year = 2026,
        .subject_kind = .sole_proprietor,
        .natural_person_classification = .self_employed,
        .expected_sequence = 3,
    });

    // The component is inactive on December 31 but still belongs to the
    // selected-year workspace with its stable identity and dates intact.
    try std.testing.expect(!finite_period.contains(year_end));
    try std.testing.expectEqual(@as(usize, 1), state.businessActivities().len);
    try std.testing.expectEqual(
        @as(usize, 1),
        state.registrationObligations().len,
    );
    try std.testing.expect(state.businessActivities()[0].anchor_id.eql(
        &activity_anchor_id,
    ));
    try std.testing.expect(state.businessActivities()[0].effective.eql(
        finite_period,
    ));

    try state.beginEdit();
    try state.updateBusinessActivity(
        activity_anchor_id,
        "Seasonal advisory",
        "PT011",
        finite_period,
    );
    const intent = try state.beginSave();
    try std.testing.expectEqual(@as(?u16, 2026), intent.selected_tax_year);
    try std.testing.expect(intent.business_activities[0].anchor_id.eql(
        &activity_anchor_id,
    ));
    try std.testing.expect(intent.business_activities[0].effective.eql(
        finite_period,
    ));
    try std.testing.expect(intent.registration_obligations[0].effective.eql(
        finite_period,
    ));
}

test "registration editor applicability hides pure compensation controls" {
    const profile_id = try testProfileId();
    const aggregate = emptyAggregate(profile_id);
    var pure = try State.open(.{
        .aggregate = &aggregate,
        .viewed_on = try testDate("2026-08-04"),
        .subject_kind = .individual,
        .natural_person_classification = .pure_compensation,
    });
    try std.testing.expect(
        !pure.affordances().show_business_activity_section,
    );
    try std.testing.expect(
        !pure.affordances().show_registration_obligation_section,
    );
    try pure.beginEdit();
    try std.testing.expect(!pure.affordances().can_add_business_activity);
    try std.testing.expectError(
        error.BusinessRegistrationNotApplicable,
        pure.addBusinessActivity(
            try registration.ActivityAnchorId.parse("not-allowed"),
            "Consulting",
            null,
            try testPeriod("2026-01-01", null),
        ),
    );

    inline for (.{
        .{ model.SubjectKind.sole_proprietor, model.NaturalPersonClassification.self_employed },
        .{ model.SubjectKind.corporation, model.NaturalPersonClassification.classification_unknown },
        .{ model.SubjectKind.partnership, model.NaturalPersonClassification.classification_unknown },
        .{ model.SubjectKind.other_legal_entity, model.NaturalPersonClassification.classification_unknown },
        .{ model.SubjectKind.individual, model.NaturalPersonClassification.self_employed },
        .{ model.SubjectKind.individual, model.NaturalPersonClassification.mixed_income },
    }) |case| {
        var supported = try State.open(.{
            .aggregate = &aggregate,
            .viewed_on = try testDate("2026-08-04"),
            .subject_kind = case[0],
            .natural_person_classification = case[1],
        });
        try supported.beginEdit();
        try std.testing.expect(
            supported.affordances().can_add_business_activity,
        );
        try std.testing.expect(
            supported.affordances().can_add_registration_obligation,
        );
    }
}

test "registration editor adds edits removes and saves stable anchored rows" {
    const profile_id = try testProfileId();
    const aggregate = emptyAggregate(profile_id);
    var state = try State.open(.{
        .aggregate = &aggregate,
        .viewed_on = try testDate("2026-08-04"),
        .subject_kind = .corporation,
        .expected_sequence = 4,
    });
    try state.beginEdit();
    const first_anchor = try registration.ActivityAnchorId.parse("activity-a");
    const second_anchor = try registration.ActivityAnchorId.parse("activity-b");
    try state.addBusinessActivity(
        first_anchor,
        "  Consulting  ",
        "wi-010",
        try testPeriod("2026-01-01", null),
    );
    try state.addBusinessActivity(
        second_anchor,
        "Retail",
        null,
        try testPeriod("2026-07-01", null),
    );
    try state.updateBusinessActivity(
        first_anchor,
        "Professional consulting",
        "WI 010",
        try testPeriod("2026-02-01", null),
    );
    try std.testing.expectEqualStrings(
        "activity-a",
        state.businessActivities()[0].anchor_id.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "Professional consulting",
        state.businessActivities()[0].line_of_business.asSlice(),
    );
    try state.removeBusinessActivity(second_anchor);

    try state.addRegistrationObligation(
        try registration.ObligationAnchorId.parse("income-tax"),
        .registered_income_tax,
        try testPeriod("2026-01-01", null),
    );
    try state.addRegistrationObligation(
        try registration.ObligationAnchorId.parse("withholding-expanded"),
        .withholding_expanded,
        try testPeriod("2026-01-01", null),
    );
    try std.testing.expect(state.dirty());
    const intent = try state.beginSave();
    try std.testing.expectEqual(@as(u32, 4), intent.expected_sequence);
    try std.testing.expectEqual(@as(usize, 1), intent.business_activities.len);
    try std.testing.expectEqual(
        @as(usize, 2),
        intent.registration_obligations.len,
    );
    try std.testing.expectEqualStrings(
        "activity-a",
        intent.business_activities[0].anchor_id.asSlice(),
    );
    try state.saveSucceeded(5);
    try std.testing.expectEqual(PageState.viewing, state.page_state);
    try std.testing.expectEqual(@as(u32, 5), state.expected_sequence);
    try std.testing.expect(!state.dirty());
}

test "registration editor dirty comparison normalizes input and row order" {
    const profile_id = try testProfileId();
    const period = try testPeriod("2026-01-01", null);
    const anchor_a = try registration.ActivityAnchorId.parse("activity-a");
    const anchor_b = try registration.ActivityAnchorId.parse("activity-b");
    const anchors = [_]registration.ActivityAnchor{
        .{ .owner_profile_id = profile_id, .id = anchor_a },
        .{ .owner_profile_id = profile_id, .id = anchor_b },
    };
    const activities = [_]registration.BusinessActivity{
        .{
            .anchor_id = anchor_a,
            .metadata = try testMetadata(
                profile_id,
                "activity-a-revision",
                1,
                period,
                confirmed(),
            ),
            .line_of_business = try field.LineOfBusiness.parse("Consulting"),
            .atc = try field.Atc.parse("WI010"),
        },
        .{
            .anchor_id = anchor_b,
            .metadata = try testMetadata(
                profile_id,
                "activity-b-revision",
                1,
                period,
                confirmed(),
            ),
            .line_of_business = try field.LineOfBusiness.parse("Retail"),
        },
    };
    const aggregate: registration.RegistrationAggregate = .{
        .profile_id = profile_id,
        .activity_anchors = &anchors,
        .business_activities = &activities,
    };
    var state = try State.open(.{
        .aggregate = &aggregate,
        .viewed_on = try testDate("2026-08-04"),
        .subject_kind = .corporation,
    });
    try state.beginEdit();
    try std.testing.expectError(
        error.Empty,
        state.updateBusinessActivity(anchor_a, "   ", "WI010", period),
    );
    try std.testing.expect(!state.dirty());
    try std.testing.expectError(
        error.InvalidRange,
        state.updateBusinessActivity(
            anchor_a,
            "Changed only if the whole update validates",
            "WI010",
            .{
                .from = try testDate("2026-07-01"),
                .until = try testDate("2026-06-30"),
            },
        ),
    );
    try std.testing.expect(!state.dirty());
    try state.updateBusinessActivity(
        anchor_a,
        "  Consulting ",
        "wi-010",
        period,
    );
    try std.testing.expect(!state.dirty());

    try state.removeBusinessActivity(anchor_a);
    try state.addBusinessActivity(anchor_a, "Consulting", "WI010", period);
    try std.testing.expect(!state.dirty());

    try state.updateBusinessActivity(
        anchor_a,
        "Architecture consulting",
        "WI010",
        period,
    );
    try std.testing.expect(state.dirty());
    try std.testing.expect(state.affordances().can_cancel);
    try state.cancel();
    try std.testing.expectEqual(PageState.viewing, state.page_state);
    try std.testing.expectEqual(@as(usize, 2), state.businessActivities().len);
    try std.testing.expectEqualStrings(
        "activity-a",
        state.businessActivities()[0].anchor_id.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "Consulting",
        state.businessActivities()[0].line_of_business.asSlice(),
    );
    try std.testing.expect(state.businessActivities()[0].origin != null);
}

test "registration editor rejects overlapping duplicate and VAT percentage obligations" {
    const profile_id = try testProfileId();
    const aggregate = emptyAggregate(profile_id);
    var state = try State.open(.{
        .aggregate = &aggregate,
        .viewed_on = try testDate("2026-08-04"),
        .subject_kind = .corporation,
    });
    try state.beginEdit();
    try state.addRegistrationObligation(
        try registration.ObligationAnchorId.parse("vat-one"),
        .vat,
        try testPeriod("2026-01-01", "2026-06-30"),
    );
    try std.testing.expectError(
        error.DuplicateTypedObligation,
        state.addRegistrationObligation(
            try registration.ObligationAnchorId.parse("vat-two"),
            .vat,
            try testPeriod("2026-06-30", null),
        ),
    );
    try std.testing.expectError(
        error.VatPercentageConflict,
        state.addRegistrationObligation(
            try registration.ObligationAnchorId.parse("percentage"),
            .percentage_tax,
            try testPeriod("2026-04-01", null),
        ),
    );
}

test "registration editor retains unsupported and inactive review rows exactly" {
    const profile_id = try testProfileId();
    const period = try testPeriod("2026-01-01", null);
    const old_period = try testPeriod("2025-01-01", "2025-12-31");
    const activity_anchor = try registration.ActivityAnchorId.parse(
        "review-activity",
    );
    const obligation_anchor = try registration.ObligationAnchorId.parse(
        "legacy-tax-row",
    );
    const activity_anchors = [_]registration.ActivityAnchor{.{
        .owner_profile_id = profile_id,
        .id = activity_anchor,
    }};
    const obligation_anchors = [_]registration.ObligationAnchor{.{
        .owner_profile_id = profile_id,
        .id = obligation_anchor,
    }};
    const activities = [_]registration.BusinessActivity{.{
        .anchor_id = activity_anchor,
        .metadata = try testMetadata(
            profile_id,
            "review-activity-revision",
            1,
            old_period,
            needsReview(),
        ),
        .line_of_business = try field.LineOfBusiness.parse("Legacy service"),
    }};
    const obligations = [_]registration.RegistrationObligation{.{
        .anchor_id = obligation_anchor,
        .metadata = try testMetadata(
            profile_id,
            "legacy-tax-revision",
            1,
            period,
            needsReview(),
        ),
        .kind = .{
            .unknown_requires_review = try field.TaxType.parse(
                "VAT / percentage tax (legacy)",
            ),
        },
    }};
    const special = [_]registration.SpecialLawOrTreatyBasisRevision{.{
        .metadata = try testMetadata(
            profile_id,
            "legacy-special-basis",
            1,
            period,
            needsReview(),
        ),
        .value = .{
            .unknown_requires_review = try field.SpecialRateBasis.parse(
                "PEZA or treaty - source did not distinguish",
            ),
        },
    }};
    const aggregate: registration.RegistrationAggregate = .{
        .profile_id = profile_id,
        .activity_anchors = &activity_anchors,
        .obligation_anchors = &obligation_anchors,
        .business_activities = &activities,
        .obligations = &obligations,
        .special_law_or_treaty_bases = &special,
    };
    var state = try State.open(.{
        .aggregate = &aggregate,
        .viewed_on = try testDate("2026-08-04"),
        .subject_kind = .individual,
        .natural_person_classification = .pure_compensation,
        .expected_sequence = 2,
    });
    try std.testing.expectEqual(@as(usize, 0), state.businessActivities().len);
    try std.testing.expectEqual(
        @as(usize, 0),
        state.registrationObligations().len,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        state.reviewRequiredRows().len,
    );
    try std.testing.expect(
        !state.reviewRequiredRows()[0].isActiveOnViewDate(),
    );
    try std.testing.expect(
        state.reviewRequiredRows()[1].isUnsupportedLegacyValue(),
    );
    const legacy = switch (state.reviewRequiredRows()[1]) {
        .registration_obligation => |row| switch (row.value.kind) {
            .unknown_requires_review => |value| value,
            else => unreachable,
        },
        else => unreachable,
    };
    try std.testing.expectEqualStrings(
        "VAT / percentage tax (legacy)",
        legacy.asSlice(),
    );
    try std.testing.expect(
        state.affordances().show_review_required_section,
    );
    try std.testing.expect(
        state.affordances().show_business_activity_section,
    );
    try state.beginEdit();
    try std.testing.expect(!state.affordances().can_add_business_activity);
    try std.testing.expectError(
        error.BusinessRegistrationNotApplicable,
        state.addRegistrationObligation(
            obligation_anchor,
            .vat,
            period,
        ),
    );

    var supported = try State.open(.{
        .aggregate = &aggregate,
        .viewed_on = try testDate("2026-08-04"),
        .subject_kind = .corporation,
        .expected_sequence = 2,
    });
    try supported.beginEdit();
    try supported.addBusinessActivity(
        try registration.ActivityAnchorId.parse("new-reviewed-activity"),
        "New confirmed activity",
        null,
        period,
    );
    const intent = try supported.beginSave();
    try std.testing.expectEqual(
        @as(usize, 3),
        intent.retained_review_rows.len,
    );
    try std.testing.expect(
        intent.retained_review_rows[1].isUnsupportedLegacyValue(),
    );
}

test "registration editor conflict retains draft and requires explicit rebase" {
    const profile_id = try testProfileId();
    const aggregate = emptyAggregate(profile_id);
    var state = try State.open(.{
        .aggregate = &aggregate,
        .viewed_on = try testDate("2026-08-04"),
        .subject_kind = .corporation,
        .expected_sequence = 8,
    });
    try state.beginEdit();
    try state.addBusinessActivity(
        try registration.ActivityAnchorId.parse("activity-conflict"),
        "Consulting",
        null,
        try testPeriod("2026-01-01", null),
    );
    _ = try state.beginSave();
    try std.testing.expectError(
        error.WrongConflictSequence,
        state.noteConflict(8),
    );
    try state.noteConflict(10);
    try std.testing.expectEqual(SaveStatus.failed, state.save_status);
    try std.testing.expectEqual(@as(usize, 1), state.businessActivities().len);
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expect(state.affordances().can_reload_conflict);
    try std.testing.expectError(
        error.WrongConflictSequence,
        state.acceptReviewedConflictBase(9),
    );
    try state.acceptReviewedConflictBase(10);
    try std.testing.expectEqual(@as(u32, 10), state.expected_sequence);
    _ = try state.beginSave();
    try state.saveFailed();
    try std.testing.expectEqual(SaveStatus.failed, state.save_status);
    try std.testing.expectEqual(@as(usize, 1), state.businessActivities().len);
}

test "registration editor opens lossless legacy adapter composition without fabrication" {
    const profile_id = try testProfileId();
    const period = try testPeriod("2026-01-01", null);
    const fact_id = try model.RegistrationFactId.parse("legacy-tax-fact");
    const facts = [_]model.RegistrationFact{.{
        .id = fact_id,
        .effective = period,
        .value = .{
            .tax_type = try field.TaxType.parse("VAT or percentage tax"),
        },
    }};
    const revision: model.ProfileRevision = .{
        .profile_id = profile_id,
        .id = try model.RevisionId.parse("legacy-profile-revision"),
        .sequence = 1,
        .effective = period,
        .source = .{
            .migrated = try field.SourceReference.parse("legacy eBIRForms"),
        },
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("040"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("Quezon City"),
        },
        .subject = .{ .legal_entity = .{
            .registered_name = try field.RegisteredName.parse("Example Corp"),
            .kind = .corporation,
        } },
        .registration_facts = &facts,
    };
    const identities = [_]registration_adapter.RegistrationFactIdentity{.{
        .source_fact_id = fact_id,
        .legacy_anchor_id = fact_id,
        .target_revision_id = try registration.ComponentRevisionId.parse(
            "legacy-tax-component-revision",
        ),
    }};
    var composition = try registration_adapter.compose(
        std.testing.allocator,
        &.{.{
            .revision = &revision,
            .registration_fact_identities = &identities,
        }},
    );
    defer composition.deinit(std.testing.allocator);

    const state = try State.openFromComposition(.{
        .composition = &composition,
        .viewed_on = try testDate("2026-08-04"),
        .subject_kind = .corporation,
        .expected_sequence = 1,
    });
    try std.testing.expectEqual(
        @as(usize, 0),
        state.registrationObligations().len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        state.reviewRequiredRows().len,
    );
    try std.testing.expect(
        state.reviewRequiredRows()[0].isUnsupportedLegacyValue(),
    );
    const row = switch (state.reviewRequiredRows()[0]) {
        .registration_obligation => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqualStrings(
        "legacy-tax-fact",
        row.value.anchor_id.asSlice(),
    );
    const text = switch (row.value.kind) {
        .unknown_requires_review => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqualStrings("VAT or percentage tax", text.asSlice());
}
