//! Allocation-free Tax Form Profile page state.
//!
//! This module deliberately owns no persistence and no Native markup. It is a
//! small composition seam between the generated form-profile contract, the
//! append-only `tax_form_profile` aggregate, and `main.zig`/markup. The page
//! states are product states; save progress, review, copy provenance, and
//! optimistic conflicts are independent axes so they cannot manufacture an
//! editable annual profile for `calendar_only`, `no_setup`, or inactive forms.

const std = @import("std");
const catalog = @import("../forms/generated/catalog.zig");
const model = @import("model.zig");
const tax_form_profile = @import("tax_form_profile.zig");

pub const Error = tax_form_profile.Error || error{
    NotOpen,
    UnknownForm,
    InvalidTaxYear,
    InvalidInheritedReadiness,
    MissingActivationPeriod,
    UnexpectedActivationPeriod,
    WrongActivationPeriod,
    UnexpectedAnnualRevision,
    WrongViewedIdentity,
    WrongExpectedSequence,
    InactiveForm,
    ProfileUnavailable,
    SetupNotSupported,
    LockedByFiling,
    NotEditing,
    ActionDisabled,
    TooManyValues,
    IncompleteAnnualSetup,
    InvalidTransition,
    InvalidCopySource,
    CopyUnavailable,
    CopyRequiresCompatibilityReview,
    NoReviewRequired,
    NoConflict,
    WrongConflictSequence,
};

/// The generated registry currently has only a few values per form. Using the
/// registry-wide value count as a fixed upper bound keeps this module robust
/// when a form gains another generated value without introducing allocation.
pub const max_annual_values: usize = catalog.tax_form_profile_value_count;

/// Locked page modes. Saving, failure, review, and conflict are deliberately
/// not page modes; the editor stays mounted and keeps its draft through them.
pub const PageState = enum {
    inactive_history_only,
    calendar_only_no_profile,
    inherited_only,
    needs_setup,
    viewing_ready,
    editing,
};

pub const SaveStatus = enum {
    idle,
    saving,
    failed,
};

/// Readiness of canonical taxpayer/profile values inherited by the form.
/// These counts never include generated annual values.
pub const InheritedReadiness = struct {
    required_count: u16 = 0,
    missing_count: u16 = 0,
    invalid_count: u16 = 0,

    pub fn validate(self: InheritedReadiness) Error!void {
        if (@as(u32, self.missing_count) + self.invalid_count >
            self.required_count)
        {
            return error.InvalidInheritedReadiness;
        }
    }

    pub fn resolvedCount(self: InheritedReadiness) u16 {
        return self.required_count - self.missing_count - self.invalid_count;
    }

    pub fn ready(self: InheritedReadiness) bool {
        return self.missing_count == 0 and self.invalid_count == 0;
    }
};

/// Exact identity shown by the page. `annual_revision_*` identifies a saved
/// setup revision; it stays null for a new setup, `no_setup`, and
/// `calendar_only` forms. Form/spec identity is copied from the generated
/// catalog and never inferred from a title or field label.
pub const ViewedIdentity = struct {
    profile_id: model.ProfileId,
    tax_year: u16,
    form_code: tax_form_profile.FormCode,
    form_revision: ?tax_form_profile.FormRevision,
    spec_revision: ?u32,
    spec_hash: ?tax_form_profile.SpecHash,
    annual_revision_id: ?tax_form_profile.RevisionId = null,
    annual_revision_sequence: u32 = 0,

    pub fn formCode(self: *const ViewedIdentity) []const u8 {
        return self.form_code.asSlice();
    }

    pub fn formRevision(self: *const ViewedIdentity) ?[]const u8 {
        if (self.form_revision == null) return null;
        return self.form_revision.?.asSlice();
    }

    pub fn specHash(self: *const ViewedIdentity) ?[]const u8 {
        if (self.spec_hash == null) return null;
        return self.spec_hash.?.asSlice();
    }
};

/// A complete immutable source identity for explicit prior-year reuse.
pub const RevisionIdentity = struct {
    profile_id: model.ProfileId,
    tax_year: u16,
    form_code: tax_form_profile.FormCode,
    form_revision: tax_form_profile.FormRevision,
    spec_revision: u32,
    spec_hash: tax_form_profile.SpecHash,
    revision_id: tax_form_profile.RevisionId,
    revision_sequence: u32,

    pub fn fromRevision(revision: *const tax_form_profile.Revision) RevisionIdentity {
        return .{
            .profile_id = revision.stream.profile_id,
            .tax_year = revision.stream.tax_year,
            .form_code = revision.stream.form_code,
            .form_revision = revision.stream.form_revision,
            .spec_revision = revision.spec_revision,
            .spec_hash = revision.spec_hash,
            .revision_id = revision.id,
            .revision_sequence = revision.sequence,
        };
    }
};

pub const CopyCompatibility = enum {
    exact,
    requires_mapping_review,
    incompatible,
};

pub const ReuseReason = enum {
    prior_year,
    reactivation,
    form_revision_mapping,
};

pub const CopyOffer = struct {
    source: RevisionIdentity,
    compatibility: CopyCompatibility,
    reason: ReuseReason = .prior_year,
};

/// Copy provenance retained by the current persisted revision. The domain's
/// compact source does not contain form/spec/profile dimensions, so the UI
/// shows exactly these proven fields and never fills the rest from a possibly
/// unrelated current copy offer.
pub const PersistedCopyProvenance = struct {
    source_tax_year: u16,
    source_form_revision: tax_form_profile.FormRevision,
    source_spec_revision: u32,
    source_spec_hash: tax_form_profile.SpecHash,
    source_revision_id: tax_form_profile.RevisionId,
};

pub const MappingIssueReason = enum {
    not_in_current_spec,
    value_type_changed,
    evidence_gated,
    unsupported_ownership,
};

pub const MappingIssue = struct {
    role: catalog.Role,
    semantic_key: catalog.TaxFormProfileSemanticKey,
    reason: MappingIssueReason,
};

/// Deterministic result of comparing one historical setup with the generated
/// current spec. Only the canonical role/key/type intersection is staged;
/// every omitted source value is retained here for explicit user review.
pub const MappingReview = struct {
    source: RevisionIdentity,
    mapped_count: u16 = 0,
    missing_required_count: u16 = 0,
    issues: [max_annual_values]MappingIssue = undefined,
    issue_count: usize = 0,

    pub fn issueSlice(self: *const MappingReview) []const MappingIssue {
        return self.issues[0..self.issue_count];
    }
};

/// Review is explicit. A review acknowledgement is draft state and therefore
/// participates in dirty checking just like a normalized value change.
pub const ReviewRequirement = enum {
    none,
    prior_year_copy,
    reactivation,
    form_revision_mapping,
    persisted_unconfirmed_revision,
};

pub const Conflict = struct {
    expected_sequence: u32,
    current_sequence: u32,
};

pub const AnnualReadiness = struct {
    applicable: bool,
    generated_value_count: u16,
    editable_value_count: u16,
    evidence_gated_value_count: u16,
    supplied_value_count: u16,
    missing_required_count: u16,
    has_nonempty_candidate: bool,
    has_confirmed_revision: bool,
    review_required: bool,
    /// A confirmed revision can still become unusable when one of its
    /// date-effective named-profile role bindings no longer resolves.
    bindings_resolved: bool,

    /// Candidate completeness answers whether the annual editor can be saved.
    /// It does not claim filing readiness until a confirmed revision exists.
    pub fn candidateComplete(self: AnnualReadiness) bool {
        return self.applicable and
            self.has_nonempty_candidate and
            self.missing_required_count == 0;
    }

    pub fn ready(self: AnnualReadiness) bool {
        return self.applicable and
            self.has_confirmed_revision and
            !self.review_required and
            self.bindings_resolved and
            self.candidateComplete();
    }
};

pub const FilingReadiness = enum {
    unavailable,
    inactive,
    conflict,
    editing,
    missing_inherited_values,
    missing_annual_setup,
    requires_review,
    ready,
};

/// Values and provenance borrowed from `State`; consume this synchronously
/// when constructing an append command. No allocation or ownership transfer
/// occurs here.
pub const SaveIntent = struct {
    identity: ViewedIdentity,
    /// Exact active Forms Set interval that owns this annual setup revision.
    /// Callers persist this value verbatim; they must not manufacture a
    /// full-tax-year interval at the persistence boundary.
    effective: tax_form_profile.EffectivePeriod,
    expected_sequence: u32,
    values: []const tax_form_profile.SetupValue,
    review_requirement: ReviewRequirement,
    copied_from: ?RevisionIdentity,
};

pub const Affordances = struct {
    can_view_history: bool,
    can_edit_tax_profile: bool,
    can_edit_tax_form_profile: bool,
    can_save: bool,
    can_cancel: bool,
    can_copy_prior_year: bool,
    can_reuse_after_reactivation: bool,
    can_review_copy_or_reuse: bool,
    can_review_compatibility: bool,
    can_reload_conflict: bool,
    can_rebase_conflict: bool,
    can_start_new_filing: bool,
};

pub const OpenArgs = struct {
    profile_id: model.ProfileId,
    tax_year: u16,
    form_code: []const u8,
    active: bool,
    /// A queued or later filing has frozen the exact Tax Form Profile
    /// revision used for this form/year stream.  The profile remains readable
    /// and filing-ready, but no further setup revisions may be authored.
    locked_by_filing: bool = false,
    /// Exact interval resolved from the Forms Set for this form revision.
    /// Kept optional in the input shape for source compatibility, but an
    /// active page fails closed when the caller omits it. Inactive/history
    /// routes must not masquerade a historical setup interval as a current
    /// activation interval.
    activation_period: ?tax_form_profile.EffectivePeriod = null,
    history_exists: bool = false,
    inherited: InheritedReadiness = .{},
    /// True when the generated form contract requires an explicit annual
    /// candidate. Optional-only contracts otherwise remain filing-ready
    /// without an empty fabricated revision.
    annual_setup_required: bool = false,
    saved_revision: ?*const tax_form_profile.Revision = null,
    /// Stream-wide optimistic head. This is separate from the revision shown
    /// for one activation interval. Omit only in isolated callers/tests that
    /// have no separately loaded stream history.
    expected_current_sequence: ?u32 = null,
    review_requirement: ReviewRequirement = .none,
    copy_offer: ?CopyOffer = null,
};

pub const State = struct {
    opened: bool = false,
    page_state: PageState = .calendar_only_no_profile,
    identity: ?ViewedIdentity = null,
    setup_mode: catalog.TaxFormProfileSetupMode = .calendar_only,
    active: bool = false,
    locked_by_filing: bool = false,
    activation_period: ?tax_form_profile.EffectivePeriod = null,
    history_exists: bool = false,
    inherited: InheritedReadiness = .{},
    annual_setup_required: bool = false,
    baseline_values: [max_annual_values]tax_form_profile.SetupValue = undefined,
    baseline_value_count: usize = 0,
    draft_values: [max_annual_values]tax_form_profile.SetupValue = undefined,
    draft_value_count: usize = 0,
    baseline_review_requirement: ReviewRequirement = .none,
    draft_review_requirement: ReviewRequirement = .none,
    baseline_review_acknowledged: bool = true,
    draft_review_acknowledged: bool = true,
    baseline_confirmed: bool = false,
    saved_bindings_resolved: bool = true,
    persisted_copy_provenance: ?PersistedCopyProvenance = null,
    baseline_copy_source: ?RevisionIdentity = null,
    draft_copy_source: ?RevisionIdentity = null,
    copy_offer: ?CopyOffer = null,
    mapping_review: ?MappingReview = null,
    expected_sequence: u32 = 0,
    save_status: SaveStatus = .idle,
    conflict: ?Conflict = null,

    pub fn open(args: OpenArgs) Error!State {
        if (args.tax_year == 0) return error.InvalidTaxYear;
        try args.inherited.validate();
        if (args.active) {
            const activation = args.activation_period orelse
                return error.MissingActivationPeriod;
            try validatePeriodWithinTaxYear(activation, args.tax_year);
        } else if (args.activation_period != null) {
            return error.UnexpectedActivationPeriod;
        }
        const form = catalog.findForm(args.form_code) orelse
            return error.UnknownForm;

        var result: State = .{};
        result.opened = true;
        result.setup_mode = form.tax_form_profile.mode;
        result.active = args.active;
        result.locked_by_filing = args.locked_by_filing;
        result.activation_period = args.activation_period;
        result.history_exists = args.history_exists or
            args.saved_revision != null;
        result.inherited = args.inherited;
        result.annual_setup_required = args.annual_setup_required;
        result.identity = try identityFor(form, args.profile_id, args.tax_year);
        result.copy_offer = args.copy_offer;

        if (args.copy_offer) |offer| {
            try validateCopyOffer(&result.identity.?, offer);
        }

        if (args.saved_revision) |revision| {
            if (form.tax_form_profile.mode != .setup) {
                return error.UnexpectedAnnualRevision;
            }
            if (revisionMatchesView(&result.identity.?, revision)) {
                try revision.validate(form);
            } else if (!args.active) {
                // Deactivation/catalog upgrades must not erase old setup
                // visibility. Historical mode validates the append-only
                // envelope without pretending the current generated spec is
                // the old spec, then displays the exact stored identity.
                try validateHistoricalRevisionEnvelope(
                    &result.identity.?,
                    revision,
                );
                result.identity.?.form_revision = revision.stream.form_revision;
                result.identity.?.spec_revision = revision.spec_revision;
                result.identity.?.spec_hash = revision.spec_hash;
            } else {
                // An active form may never treat an older/incompatible spec as
                // current readiness. It must use the explicit migration/copy
                // review flow instead.
                return error.WrongViewedIdentity;
            }
            if (args.active and
                !revision.effective.eql(result.activation_period.?))
            {
                return error.WrongActivationPeriod;
            }
            try result.loadBaseline(revision);
        } else {
            result.baseline_review_requirement = args.review_requirement;
            result.draft_review_requirement = args.review_requirement;
            result.baseline_review_acknowledged =
                args.review_requirement == .none;
            result.draft_review_acknowledged =
                result.baseline_review_acknowledged;
        }

        if (args.review_requirement != .none) {
            result.baseline_review_requirement = args.review_requirement;
            result.draft_review_requirement = args.review_requirement;
            result.baseline_review_acknowledged = false;
            result.draft_review_acknowledged = false;
        }
        const expected_current_sequence = args.expected_current_sequence orelse
            if (args.saved_revision) |revision| revision.sequence else 0;
        if (args.saved_revision) |revision| {
            if (revision.sequence > expected_current_sequence) {
                return error.WrongExpectedSequence;
            }
        }
        result.expected_sequence = expected_current_sequence;
        result.page_state = result.basePageState(form);
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

    /// Current Forms Set activation interval. Inactive/history-only pages
    /// deliberately return null even when the displayed saved revision has a
    /// historical effective interval.
    pub fn activationPeriod(
        self: *const State,
    ) ?tax_form_profile.EffectivePeriod {
        return if (self.opened and self.active)
            self.activation_period
        else
            null;
    }

    pub fn baselineValues(self: *const State) []const tax_form_profile.SetupValue {
        return self.baseline_values[0..self.baseline_value_count];
    }

    pub fn draftValues(self: *const State) []const tax_form_profile.SetupValue {
        return self.draft_values[0..self.draft_value_count];
    }

    pub fn persistedCopyProvenance(
        self: *const State,
    ) ?PersistedCopyProvenance {
        return self.persisted_copy_provenance;
    }

    pub fn setInheritedReadiness(
        self: *State,
        readiness: InheritedReadiness,
    ) Error!void {
        if (!self.opened) return error.NotOpen;
        try readiness.validate();
        self.inherited = readiness;
    }

    /// Applies the shared store-backed binding resolver result. This is kept
    /// separate from revision validation: a saved identifier may be valid
    /// annual data while no longer resolving on the viewed activation date.
    pub fn setSavedBindingsResolved(
        self: *State,
        resolved: bool,
    ) Error!void {
        const form = try self.requireOpenForm();
        self.saved_bindings_resolved = resolved;
        if (self.page_state != .editing) {
            self.page_state = self.basePageState(form);
        }
    }

    /// Explicit View -> Edit transition. Merely opening a form never enters
    /// edit mode.
    pub fn beginEdit(self: *State) Error!void {
        const form = try self.requireOpenForm();
        if (!self.active) return error.InactiveForm;
        if (form.tax_form_profile.mode == .calendar_only) {
            return error.ProfileUnavailable;
        }
        if (form.tax_form_profile.mode != .setup) {
            return error.SetupNotSupported;
        }
        if (self.locked_by_filing) return error.LockedByFiling;
        switch (self.page_state) {
            .needs_setup, .viewing_ready => {},
            else => return error.InvalidTransition,
        }
        self.page_state = .editing;
        self.save_status = .idle;
        self.conflict = null;
    }

    pub fn setDraftValue(
        self: *State,
        value: tax_form_profile.SetupValue,
    ) Error!void {
        const form = try self.requireEditableForm();
        try validateEditableValue(form, value);
        for (self.draft_values[0..self.draft_value_count]) |*existing| {
            if (sameValueKey(existing.*, value)) {
                existing.* = value;
                self.noteDraftMutation();
                return;
            }
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
        values: []const tax_form_profile.SetupValue,
    ) Error!void {
        const form = try self.requireEditableForm();
        try validateEditableValues(form, values, false);
        if (values.len > self.draft_values.len) return error.TooManyValues;
        @memcpy(self.draft_values[0..values.len], values);
        self.draft_value_count = values.len;
        self.noteDraftMutation();
    }

    pub fn removeDraftValue(
        self: *State,
        role: catalog.Role,
        key: catalog.TaxFormProfileSemanticKey,
    ) Error!void {
        _ = try self.requireEditableForm();
        for (self.draft_values[0..self.draft_value_count], 0..) |value, index| {
            if (value.role != role or value.semantic_key != key) continue;
            var cursor = index;
            while (cursor + 1 < self.draft_value_count) : (cursor += 1) {
                self.draft_values[cursor] = self.draft_values[cursor + 1];
            }
            self.draft_value_count -= 1;
            self.noteDraftMutation();
            return;
        }
    }

    /// Stages an exact-compatible prior-year copy and enters Edit. The copy
    /// cannot be saved until the user explicitly acknowledges review.
    pub fn stagePriorYearCopy(
        self: *State,
        values: []const tax_form_profile.SetupValue,
    ) Error!void {
        const offer = self.copy_offer orelse return error.CopyUnavailable;
        if (offer.reason != .prior_year) return error.CopyUnavailable;
        try self.stageOfferedReuse(values, .prior_year_copy);
    }

    /// Stages a compatible setup previously confirmed for another active
    /// interval in the same tax year. Reuse is deliberately a dirty draft and
    /// cannot be saved until the user acknowledges the reactivation review.
    pub fn stageReactivationReuse(
        self: *State,
        values: []const tax_form_profile.SetupValue,
    ) Error!void {
        const offer = self.copy_offer orelse return error.CopyUnavailable;
        if (offer.reason != .reactivation) return error.CopyUnavailable;
        try self.stageOfferedReuse(values, .reactivation);
    }

    /// Maps a prior setup from a different form/spec revision into the current
    /// generated contract. Semantic aliases are deliberately impossible: a
    /// value is staged only when role, canonical key, and value type all match
    /// a current supported definition. Review and current-spec completeness
    /// remain independent Save gates.
    pub fn stageFormRevisionMapping(
        self: *State,
        values: []const tax_form_profile.SetupValue,
    ) Error!void {
        const form = try self.requireOpenForm();
        if (!self.active) return error.InactiveForm;
        if (form.tax_form_profile.mode != .setup) {
            return error.SetupNotSupported;
        }
        switch (self.page_state) {
            .needs_setup, .viewing_ready => {},
            else => return error.InvalidTransition,
        }
        const offer = self.copy_offer orelse return error.CopyUnavailable;
        if (offer.reason != .form_revision_mapping or
            offer.compatibility != .requires_mapping_review)
        {
            return error.CopyUnavailable;
        }

        var review: MappingReview = .{ .source = offer.source };
        self.draft_value_count = 0;
        for (values) |source_value| {
            const definition = findDefinition(
                &form.tax_form_profile,
                source_value.role,
                source_value.semantic_key,
            ) orelse {
                try appendMappingIssue(
                    &review,
                    source_value,
                    .not_in_current_spec,
                );
                continue;
            };
            if (definition.availability == .evidence_required) {
                try appendMappingIssue(&review, source_value, .evidence_gated);
                continue;
            }
            if (definition.ownership != .binding_selection and
                definition.ownership != .yearly_value and
                definition.ownership != .transaction_default)
            {
                try appendMappingIssue(
                    &review,
                    source_value,
                    .unsupported_ownership,
                );
                continue;
            }
            if (definition.value_type != source_value.value.valueType()) {
                try appendMappingIssue(
                    &review,
                    source_value,
                    .value_type_changed,
                );
                continue;
            }
            if (self.draft_value_count == self.draft_values.len) {
                return error.TooManyValues;
            }
            self.draft_values[self.draft_value_count] = source_value;
            self.draft_values[self.draft_value_count].source = .{
                .copied_from_revision = offer.source.revision_id,
            };
            self.draft_value_count += 1;
            review.mapped_count += 1;
        }
        try validateEditableValues(form, self.draftValues(), false);
        for (form.tax_form_profile.values) |definition| {
            if (definition.availability != .supported or
                definition.presence != .required)
            {
                continue;
            }
            if (findValue(
                self.draftValues(),
                definition.role,
                definition.semantic_key,
            ) == null) review.missing_required_count += 1;
        }

        self.draft_copy_source = offer.source;
        self.draft_review_requirement = .form_revision_mapping;
        self.draft_review_acknowledged = false;
        self.mapping_review = review;
        self.page_state = .editing;
        self.save_status = .idle;
        self.conflict = null;
    }

    pub fn mappingReview(self: *const State) ?*const MappingReview {
        if (self.mapping_review) |*review| return review;
        return null;
    }

    fn stageOfferedReuse(
        self: *State,
        values: []const tax_form_profile.SetupValue,
        review_requirement: ReviewRequirement,
    ) Error!void {
        const form = try self.requireOpenForm();
        if (!self.active) return error.InactiveForm;
        if (form.tax_form_profile.mode != .setup) {
            return error.SetupNotSupported;
        }
        switch (self.page_state) {
            .needs_setup, .viewing_ready => {},
            else => return error.InvalidTransition,
        }
        const offer = self.copy_offer orelse return error.CopyUnavailable;
        switch (offer.compatibility) {
            .exact => {},
            .requires_mapping_review => return error.CopyRequiresCompatibilityReview,
            .incompatible => return error.CopyUnavailable,
        }
        try validateEditableValues(form, values, true);
        if (values.len > self.draft_values.len) return error.TooManyValues;
        @memcpy(self.draft_values[0..values.len], values);
        self.draft_value_count = values.len;
        for (self.draft_values[0..self.draft_value_count]) |*value| {
            value.source = .{
                .copied_from_revision = offer.source.revision_id,
            };
        }
        self.draft_copy_source = offer.source;
        self.draft_review_requirement = review_requirement;
        self.draft_review_acknowledged = false;
        self.page_state = .editing;
        self.save_status = .idle;
        self.conflict = null;
    }

    pub fn acknowledgeReview(self: *State) Error!void {
        _ = try self.requireEditableForm();
        if (self.draft_review_requirement == .none or
            self.draft_review_acknowledged)
        {
            return error.NoReviewRequired;
        }
        self.draft_review_acknowledged = true;
        self.noteDraftMutation();
    }

    /// Normalized dirty comparison ignores value ordering and per-value
    /// storage provenance. Identifiers are already trimmed/canonicalized by
    /// their domain parsers; source-only rewrites cannot enable Save.
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
        return !optionalRevisionIdentityEql(
            self.baseline_copy_source,
            self.draft_copy_source,
        );
    }

    pub fn annualReadiness(self: *const State) AnnualReadiness {
        if (!self.opened) return .{
            .applicable = false,
            .generated_value_count = 0,
            .editable_value_count = 0,
            .evidence_gated_value_count = 0,
            .supplied_value_count = 0,
            .missing_required_count = 0,
            .has_nonempty_candidate = false,
            .has_confirmed_revision = false,
            .review_required = false,
            .bindings_resolved = true,
        };
        const form = catalog.findForm(self.identity.?.form_code.asSlice()).?;
        if (form.tax_form_profile.mode != .setup) return .{
            .applicable = false,
            .generated_value_count = @intCast(form.tax_form_profile.values.len),
            .editable_value_count = 0,
            .evidence_gated_value_count = 0,
            .supplied_value_count = 0,
            .missing_required_count = 0,
            .has_nonempty_candidate = false,
            .has_confirmed_revision = false,
            .review_required = false,
            .bindings_resolved = true,
        };

        const values = if (self.page_state == .editing)
            self.draft_values[0..self.draft_value_count]
        else
            self.baseline_values[0..self.baseline_value_count];
        var result: AnnualReadiness = .{
            .applicable = true,
            .generated_value_count = @intCast(form.tax_form_profile.values.len),
            .editable_value_count = 0,
            .evidence_gated_value_count = 0,
            .supplied_value_count = @intCast(values.len),
            .missing_required_count = 0,
            .has_nonempty_candidate = values.len != 0,
            .has_confirmed_revision = self.baseline_confirmed,
            .review_required = self.draft_review_requirement != .none and
                !self.draft_review_acknowledged,
            .bindings_resolved = self.saved_bindings_resolved,
        };
        for (form.tax_form_profile.values) |definition| {
            switch (definition.availability) {
                .supported => result.editable_value_count += 1,
                .evidence_required => result.evidence_gated_value_count += 1,
            }
            if (definition.availability == .supported and
                definition.presence == .required and
                findValue(values, definition.role, definition.semantic_key) == null)
            {
                result.missing_required_count += 1;
            }
        }
        return result;
    }

    pub fn filingReadiness(self: *const State) FilingReadiness {
        if (!self.opened) return .unavailable;
        if (self.conflict != null) return .conflict;
        switch (self.page_state) {
            .calendar_only_no_profile => return .unavailable,
            .inactive_history_only => return .inactive,
            .editing => return .editing,
            else => {},
        }
        if (!self.inherited.ready()) return .missing_inherited_values;
        if (self.setup_mode == .no_setup or
            self.setup_mode == .calendar_only) return .ready;
        const annual = self.annualReadiness();
        if (annual.review_required) return .requires_review;
        if (!self.annual_setup_required and
            !annual.has_nonempty_candidate and
            annual.missing_required_count == 0)
        {
            return .ready;
        }
        if (!annual.ready()) return .missing_annual_setup;
        return .ready;
    }

    pub fn affordances(self: *const State) Affordances {
        if (!self.opened) return .{
            .can_view_history = false,
            .can_edit_tax_profile = false,
            .can_edit_tax_form_profile = false,
            .can_save = false,
            .can_cancel = false,
            .can_copy_prior_year = false,
            .can_reuse_after_reactivation = false,
            .can_review_copy_or_reuse = false,
            .can_review_compatibility = false,
            .can_reload_conflict = false,
            .can_rebase_conflict = false,
            .can_start_new_filing = false,
        };
        const editing = self.page_state == .editing;
        const form_supports_setup = self.setup_mode == .setup;
        const annual = self.annualReadiness();
        // A saved optional-only setup can be cleared.  The resulting empty
        // revision is meaningful append-only history, not a fabricated first
        // setup: a brand-new optional form remains clean and cannot save.
        const draft_complete = annual.applicable and
            annual.missing_required_count == 0 and
            (annual.has_nonempty_candidate or !self.annual_setup_required);
        const review_complete = self.draft_review_requirement == .none or
            self.draft_review_acknowledged;
        const copy_exact = if (self.copy_offer) |offer|
            offer.compatibility == .exact
        else
            false;
        const reuse_reason = if (self.copy_offer) |offer|
            offer.reason
        else
            null;
        const copy_needs_mapping = if (self.copy_offer) |offer|
            offer.compatibility == .requires_mapping_review
        else
            false;
        const mutable = self.active and form_supports_setup and
            !self.locked_by_filing;
        const idle_enough = self.save_status != .saving;
        const has_conflict = self.conflict != null;
        return .{
            .can_view_history = self.history_exists,
            .can_edit_tax_profile = self.active and
                self.setup_mode != .calendar_only and
                !self.inherited.ready(),
            .can_edit_tax_form_profile = mutable and !editing,
            .can_save = mutable and editing and self.dirty() and
                draft_complete and review_complete and idle_enough and
                !has_conflict,
            .can_cancel = mutable and editing and self.dirty() and
                idle_enough,
            .can_copy_prior_year = mutable and !editing and copy_exact and
                reuse_reason == .prior_year,
            .can_reuse_after_reactivation = mutable and !editing and copy_exact and
                reuse_reason == .reactivation,
            .can_review_copy_or_reuse = mutable and editing and
                self.draft_review_requirement != .none and
                !self.draft_review_acknowledged,
            .can_review_compatibility = mutable and !editing and
                copy_needs_mapping,
            .can_reload_conflict = has_conflict,
            .can_rebase_conflict = has_conflict,
            .can_start_new_filing = self.setup_mode != .calendar_only and
                self.filingReadiness() == .ready,
        };
    }

    /// Dirty Cancel is the only enabled Cancel. It restores the captured
    /// baseline and returns to the appropriate read-only state without
    /// navigating away from this page.
    pub fn cancel(self: *State) Error!void {
        _ = try self.requireEditableForm();
        if (!self.affordances().can_cancel) return error.ActionDisabled;
        @memcpy(
            self.draft_values[0..self.baseline_value_count],
            self.baseline_values[0..self.baseline_value_count],
        );
        self.draft_value_count = self.baseline_value_count;
        self.draft_review_requirement = self.baseline_review_requirement;
        self.draft_review_acknowledged = self.baseline_review_acknowledged;
        self.draft_copy_source = self.baseline_copy_source;
        self.mapping_review = null;
        self.save_status = .idle;
        self.conflict = null;
        self.page_state = self.basePageState(try self.requireOpenForm());
    }

    pub fn beginSave(self: *State) Error!SaveIntent {
        const form = try self.requireEditableForm();
        if (!self.affordances().can_save) return error.ActionDisabled;
        try validateEditableValues(form, self.draftValues(), true);
        self.save_status = .saving;
        return .{
            .identity = self.identity.?,
            .effective = self.activation_period orelse
                return error.MissingActivationPeriod,
            .expected_sequence = self.expected_sequence,
            .values = self.draftValues(),
            .review_requirement = self.draft_review_requirement,
            .copied_from = self.draft_copy_source,
        };
    }

    pub fn saveFailed(self: *State) Error!void {
        _ = try self.requireEditableForm();
        if (self.save_status != .saving) return error.InvalidTransition;
        self.save_status = .failed;
    }

    /// Records an optimistic append conflict without changing one byte of the
    /// draft. Retry remains blocked until the caller explicitly reviews and
    /// rebases or explicitly reloads the latest saved revision.
    pub fn noteConflict(self: *State, current_sequence: u32) Error!void {
        _ = try self.requireEditableForm();
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

    /// Caller-reviewed rebase: preserve the user's draft, accept the exact
    /// current sequence as the next optimistic base, then permit retry.
    pub fn acceptReviewedConflictBase(
        self: *State,
        current_sequence: u32,
    ) Error!void {
        _ = try self.requireEditableForm();
        const conflict = self.conflict orelse return error.NoConflict;
        if (conflict.current_sequence != current_sequence) {
            return error.WrongConflictSequence;
        }
        self.expected_sequence = current_sequence;
        self.conflict = null;
        self.save_status = .idle;
    }

    /// Explicit reload is the destructive conflict affordance. It replaces
    /// baseline and draft with the exact latest persisted revision and exits
    /// the editor; callers should label this action accordingly.
    pub fn reloadAfterConflict(
        self: *State,
        revision: ?*const tax_form_profile.Revision,
        current_stream_sequence: u32,
    ) Error!void {
        const form = try self.requireEditableForm();
        const conflict = self.conflict orelse return error.NoConflict;
        if (current_stream_sequence != conflict.current_sequence) {
            return error.WrongConflictSequence;
        }
        if (revision) |saved| {
            if (saved.sequence > current_stream_sequence) {
                return error.WrongConflictSequence;
            }
            try saved.validate(form);
            try requireRevisionMatchesView(&self.identity.?, saved);
            if (!saved.effective.eql(self.activation_period orelse
                return error.MissingActivationPeriod))
            {
                return error.WrongActivationPeriod;
            }
            try self.loadBaseline(saved);
        } else {
            self.baseline_value_count = 0;
            self.draft_value_count = 0;
            self.baseline_review_requirement = .none;
            self.draft_review_requirement = .none;
            self.baseline_review_acknowledged = true;
            self.draft_review_acknowledged = true;
            self.baseline_confirmed = false;
            self.saved_bindings_resolved = true;
            self.persisted_copy_provenance = null;
            self.baseline_copy_source = null;
            self.draft_copy_source = null;
            self.mapping_review = null;
            self.identity.?.annual_revision_id = null;
            self.identity.?.annual_revision_sequence = 0;
        }
        self.expected_sequence = current_stream_sequence;
        self.conflict = null;
        self.save_status = .idle;
        self.page_state = self.basePageState(form);
    }

    pub fn saveSucceeded(
        self: *State,
        revision: *const tax_form_profile.Revision,
    ) Error!void {
        const form = try self.requireEditableForm();
        if (self.save_status != .saving) return error.InvalidTransition;
        try revision.validate(form);
        try requireRevisionMatchesView(&self.identity.?, revision);
        if (!revision.effective.eql(self.activation_period orelse
            return error.MissingActivationPeriod))
        {
            return error.WrongActivationPeriod;
        }
        if (self.expected_sequence == std.math.maxInt(u32) or
            revision.sequence != self.expected_sequence + 1)
        {
            return error.WrongViewedIdentity;
        }
        try self.loadBaseline(revision);
        self.history_exists = true;
        self.conflict = null;
        self.save_status = .idle;
        self.page_state = self.basePageState(form);
    }

    fn requireOpenForm(self: *const State) Error!*const catalog.FormDefinition {
        if (!self.opened) return error.NotOpen;
        return catalog.findForm(self.identity.?.form_code.asSlice()) orelse
            error.UnknownForm;
    }

    fn requireEditableForm(self: *State) Error!*const catalog.FormDefinition {
        const form = try self.requireOpenForm();
        if (!self.active) return error.InactiveForm;
        if (form.tax_form_profile.mode == .calendar_only) {
            return error.ProfileUnavailable;
        }
        if (form.tax_form_profile.mode != .setup) {
            return error.SetupNotSupported;
        }
        if (self.page_state != .editing) return error.NotEditing;
        return form;
    }

    fn basePageState(
        self: *const State,
        form: *const catalog.FormDefinition,
    ) PageState {
        if (!self.active) return .inactive_history_only;
        if (form.tax_form_profile.mode == .calendar_only or
            form.tax_form_profile.mode == .no_setup) return .inherited_only;
        if (self.baseline_confirmed and
            self.baseline_review_requirement == .none and
            self.saved_bindings_resolved)
        {
            return .viewing_ready;
        }
        return .needs_setup;
    }

    fn loadBaseline(
        self: *State,
        revision: *const tax_form_profile.Revision,
    ) Error!void {
        if (revision.values.len > self.baseline_values.len) {
            return error.TooManyValues;
        }
        // A successful save may hand this state a revision whose value slice
        // is the state's own draft. Snapshot first so loading the new
        // baseline is valid even when caller and destination alias.
        var values: [max_annual_values]tax_form_profile.SetupValue = undefined;
        @memcpy(values[0..revision.values.len], revision.values);
        @memcpy(self.baseline_values[0..revision.values.len], values[0..revision.values.len]);
        @memcpy(self.draft_values[0..revision.values.len], values[0..revision.values.len]);
        self.baseline_value_count = revision.values.len;
        self.draft_value_count = revision.values.len;
        self.baseline_confirmed = revision.review_state == .confirmed;
        self.history_exists = true;
        self.expected_sequence = revision.sequence;
        self.identity.?.annual_revision_id = revision.id;
        self.identity.?.annual_revision_sequence = revision.sequence;

        const derived_review: ReviewRequirement = switch (revision.review_state) {
            .confirmed => .none,
            .requires_review => .persisted_unconfirmed_revision,
        };
        self.baseline_review_requirement = derived_review;
        self.draft_review_requirement = derived_review;
        self.baseline_review_acknowledged = derived_review == .none;
        self.draft_review_acknowledged = derived_review == .none;
        self.persisted_copy_provenance = switch (revision.source) {
            .copied_from_prior_year => |copy| .{
                .source_tax_year = copy.source_tax_year,
                .source_form_revision = copy.source_form_revision,
                .source_spec_revision = copy.source_spec_revision,
                .source_spec_hash = copy.source_spec_hash,
                .source_revision_id = copy.source_revision_id,
            },
            .manual_entry, .migrated => null,
        };
        // A full source identity is present only while this UI explicitly
        // stages a copy. The persisted domain source is intentionally compact;
        // do not fill missing identity dimensions from `copy_offer`.
        self.baseline_copy_source = null;
        self.draft_copy_source = self.baseline_copy_source;
        self.mapping_review = null;
    }

    fn noteDraftMutation(self: *State) void {
        if (self.save_status == .failed and self.conflict == null) {
            self.save_status = .idle;
        }
    }
};

fn validatePeriodWithinTaxYear(
    period: tax_form_profile.EffectivePeriod,
    tax_year: u16,
) Error!void {
    if (period.from.year != tax_year or
        (period.until != null and period.until.?.year != tax_year))
    {
        return error.EffectivePeriodOutsideTaxYear;
    }
}

fn identityFor(
    form: *const catalog.FormDefinition,
    profile_id: model.ProfileId,
    tax_year: u16,
) Error!ViewedIdentity {
    return .{
        .profile_id = profile_id,
        .tax_year = tax_year,
        .form_code = try tax_form_profile.FormCode.parse(form.code),
        .form_revision = if (form.revision) |revision|
            try tax_form_profile.FormRevision.parse(revision)
        else
            null,
        .spec_revision = form.tax_form_profile.spec_revision,
        .spec_hash = if (form.tax_form_profile.spec_hash) |hash|
            try tax_form_profile.SpecHash.parse(hash)
        else
            null,
    };
}

fn requireRevisionMatchesView(
    identity: *const ViewedIdentity,
    revision: *const tax_form_profile.Revision,
) Error!void {
    if (!revisionMatchesView(identity, revision)) {
        return error.WrongViewedIdentity;
    }
}

fn revisionMatchesView(
    identity: *const ViewedIdentity,
    revision: *const tax_form_profile.Revision,
) bool {
    return revision.stream.profile_id.eql(&identity.profile_id) and
        revision.stream.tax_year == identity.tax_year and
        std.mem.eql(
            u8,
            revision.stream.form_code.asSlice(),
            identity.form_code.asSlice(),
        ) and
        identity.form_revision != null and
        std.mem.eql(
            u8,
            revision.stream.form_revision.asSlice(),
            identity.form_revision.?.asSlice(),
        ) and
        identity.spec_revision != null and
        revision.spec_revision == identity.spec_revision.? and
        identity.spec_hash != null and
        std.mem.eql(
            u8,
            revision.spec_hash.asSlice(),
            identity.spec_hash.?.asSlice(),
        );
}

fn validateHistoricalRevisionEnvelope(
    current_identity: *const ViewedIdentity,
    revision: *const tax_form_profile.Revision,
) Error!void {
    if (!revision.stream.profile_id.eql(&current_identity.profile_id) or
        revision.stream.tax_year != current_identity.tax_year or
        !std.mem.eql(
            u8,
            revision.stream.form_code.asSlice(),
            current_identity.form_code.asSlice(),
        ))
    {
        return error.WrongViewedIdentity;
    }
    if (revision.sequence == 0) return error.InvalidSequence;
    if (revision.effective.from.year != revision.stream.tax_year or
        (revision.effective.until != null and
            revision.effective.until.?.year != revision.stream.tax_year))
    {
        return error.EffectivePeriodOutsideTaxYear;
    }
    for (revision.values, 0..) |value, index| {
        for (revision.values[index + 1 ..]) |other| {
            if (sameValueKey(value, other)) return error.DuplicateValue;
        }
    }
    switch (revision.review_state) {
        .requires_review => if (revision.confirmed_at_unix != null) {
            return error.InvalidConfirmation;
        },
        .confirmed => if (revision.confirmed_at_unix == null) {
            return error.InvalidConfirmation;
        },
    }
    switch (revision.source) {
        .manual_entry, .migrated => {},
        .copied_from_prior_year => |copy| {
            if (copy.source_tax_year >= revision.stream.tax_year or
                revision.review_state != .requires_review)
            {
                return error.InvalidCopySource;
            }
        },
    }
}

fn validateCopyOffer(
    target: *const ViewedIdentity,
    offer: CopyOffer,
) Error!void {
    const source = &offer.source;
    if (!source.profile_id.eql(&target.profile_id) or
        source.tax_year == 0 or
        source.revision_sequence == 0 or
        !std.mem.eql(
            u8,
            source.form_code.asSlice(),
            target.form_code.asSlice(),
        ))
    {
        return error.InvalidCopySource;
    }
    switch (offer.reason) {
        .prior_year => if (source.tax_year >= target.tax_year) {
            return error.InvalidCopySource;
        },
        .reactivation => if (source.tax_year != target.tax_year) {
            return error.InvalidCopySource;
        },
        .form_revision_mapping => if (source.tax_year > target.tax_year) {
            return error.InvalidCopySource;
        },
    }
    if (offer.compatibility != .exact) return;
    if (target.form_revision == null or target.spec_revision == null or
        target.spec_hash == null or
        !std.mem.eql(
            u8,
            source.form_revision.asSlice(),
            target.form_revision.?.asSlice(),
        ) or source.spec_revision != target.spec_revision.? or
        !std.mem.eql(
            u8,
            source.spec_hash.asSlice(),
            target.spec_hash.?.asSlice(),
        ))
    {
        return error.InvalidCopySource;
    }
}

fn validateEditableValues(
    form: *const catalog.FormDefinition,
    values: []const tax_form_profile.SetupValue,
    require_complete: bool,
) Error!void {
    if (values.len > max_annual_values) return error.TooManyValues;
    for (values, 0..) |value, index| {
        try validateEditableValue(form, value);
        for (values[index + 1 ..]) |other| {
            if (sameValueKey(value, other)) return error.DuplicateValue;
        }
    }
    if (!require_complete) return;
    for (form.tax_form_profile.values) |definition| {
        if (definition.availability != .supported or
            definition.presence != .required)
        {
            continue;
        }
        if (findValue(values, definition.role, definition.semantic_key) == null) {
            return error.IncompleteAnnualSetup;
        }
    }
}

fn appendMappingIssue(
    review: *MappingReview,
    value: tax_form_profile.SetupValue,
    reason: MappingIssueReason,
) Error!void {
    if (review.issue_count == review.issues.len) return error.TooManyValues;
    review.issues[review.issue_count] = .{
        .role = value.role,
        .semantic_key = value.semantic_key,
        .reason = reason,
    };
    review.issue_count += 1;
}

fn validateEditableValue(
    form: *const catalog.FormDefinition,
    value: tax_form_profile.SetupValue,
) Error!void {
    if (form.tax_form_profile.mode != .setup) return error.SetupNotSupported;
    const definition = findDefinition(
        &form.tax_form_profile,
        value.role,
        value.semantic_key,
    ) orelse return error.UnknownSemanticKey;
    if (definition.availability == .evidence_required) {
        return error.EvidenceRequired;
    }
    if (definition.ownership != .binding_selection and
        definition.ownership != .yearly_value and
        definition.ownership != .transaction_default)
    {
        return error.UnsupportedOwnership;
    }
    if (definition.value_type != value.value.valueType()) {
        return error.WrongValueType;
    }
}

fn findDefinition(
    spec: *const catalog.TaxFormProfileSpec,
    role: catalog.Role,
    key: catalog.TaxFormProfileSemanticKey,
) ?*const catalog.TaxFormProfileValueDefinition {
    for (spec.values) |*definition| {
        if (definition.role == role and definition.semantic_key == key) {
            return definition;
        }
    }
    return null;
}

fn findValue(
    values: []const tax_form_profile.SetupValue,
    role: catalog.Role,
    key: catalog.TaxFormProfileSemanticKey,
) ?*const tax_form_profile.SetupValue {
    for (values) |*value| {
        if (value.role == role and value.semantic_key == key) return value;
    }
    return null;
}

fn sameValueKey(
    left: tax_form_profile.SetupValue,
    right: tax_form_profile.SetupValue,
) bool {
    return left.role == right.role and left.semantic_key == right.semantic_key;
}

fn valueSetsEqual(
    left: []const tax_form_profile.SetupValue,
    right: []const tax_form_profile.SetupValue,
) bool {
    if (left.len != right.len) return false;
    for (left) |left_value| {
        const right_value = findValue(
            right,
            left_value.role,
            left_value.semantic_key,
        ) orelse return false;
        if (!scalarValueEqual(left_value.value, right_value.value)) return false;
    }
    return true;
}

fn scalarValueEqual(
    left: tax_form_profile.ScalarValue,
    right: tax_form_profile.ScalarValue,
) bool {
    return switch (left) {
        .profile_id => |value| switch (right) {
            .profile_id => |other| value.eql(&other),
            else => false,
        },
        .text => |value| switch (right) {
            .text => |other| value.eql(&other),
            else => false,
        },
        .boolean => |value| switch (right) {
            .boolean => |other| value == other,
            else => false,
        },
        .integer => |value| switch (right) {
            .integer => |other| value == other,
            else => false,
        },
        .date => |value| switch (right) {
            .date => |other| value.eql(other),
            else => false,
        },
        .year => |value| switch (right) {
            .year => |other| value == other,
            else => false,
        },
        .choice => |value| switch (right) {
            .choice => |other| value.eql(&other),
            else => false,
        },
    };
}

fn revisionIdentityEql(left: RevisionIdentity, right: RevisionIdentity) bool {
    return left.profile_id.eql(&right.profile_id) and
        left.tax_year == right.tax_year and
        left.form_code.eql(&right.form_code) and
        left.form_revision.eql(&right.form_revision) and
        left.spec_revision == right.spec_revision and
        left.spec_hash.eql(&right.spec_hash) and
        left.revision_id.eql(&right.revision_id) and
        left.revision_sequence == right.revision_sequence;
}

fn optionalRevisionIdentityEql(
    left: ?RevisionIdentity,
    right: ?RevisionIdentity,
) bool {
    if (left) |left_value| {
        const right_value = right orelse return false;
        return revisionIdentityEql(left_value, right_value);
    }
    return right == null;
}

fn incomeRateValue(raw: []const u8) !tax_form_profile.SetupValue {
    return .{
        .semantic_key = .income_tax_rate_election,
        .role = .filer,
        .value = .{ .choice = try tax_form_profile.TextValue.parse(raw) },
    };
}

fn fullYearActivation(tax_year: u16) !tax_form_profile.EffectivePeriod {
    return tax_form_profile.EffectivePeriod.init(
        try tax_form_profile.Date.init(tax_year, 1, 1),
        try tax_form_profile.Date.init(tax_year, 12, 31),
    );
}

fn fixtureRevision(
    form_code: []const u8,
    profile_id: model.ProfileId,
    tax_year: u16,
    revision_id: []const u8,
    sequence: u32,
    review_state: tax_form_profile.ReviewState,
    values: []const tax_form_profile.SetupValue,
) !tax_form_profile.Revision {
    const form = catalog.findForm(form_code).?;
    return .{
        .id = try tax_form_profile.RevisionId.parse(revision_id),
        .stream = .{
            .profile_id = profile_id,
            .tax_year = tax_year,
            .form_code = try tax_form_profile.FormCode.parse(form.code),
            .form_revision = try tax_form_profile.FormRevision.parse(form.revision.?),
        },
        .sequence = sequence,
        .effective = try tax_form_profile.EffectivePeriod.init(
            try tax_form_profile.Date.init(tax_year, 1, 1),
            try tax_form_profile.Date.init(tax_year, 12, 31),
        ),
        .spec_revision = form.tax_form_profile.spec_revision.?,
        .spec_hash = try tax_form_profile.SpecHash.parse(
            form.tax_form_profile.spec_hash.?,
        ),
        .review_state = review_state,
        .confirmed_at_unix = if (review_state == .confirmed) 1 else null,
        .source = .manual_entry,
        .values = values,
    };
}

test "active calendar-only form exposes inherited details without filing actions" {
    const profile_id = try model.ProfileId.parse("profile-one");
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "1905",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .inherited = .{ .required_count = 3 },
    });
    try std.testing.expectEqual(
        PageState.inherited_only,
        state.page().?,
    );
    try std.testing.expect(state.viewedIdentity().?.form_revision == null);
    try std.testing.expect(state.viewedIdentity().?.spec_hash == null);
    try std.testing.expectEqual(FilingReadiness.ready, state.filingReadiness());
    const actions = state.affordances();
    try std.testing.expect(!actions.can_edit_tax_form_profile);
    try std.testing.expect(!actions.can_start_new_filing);
    try std.testing.expectError(error.ProfileUnavailable, state.beginEdit());
}

test "active no-setup form is inherited-only and never creates annual values" {
    const profile_id = try model.ProfileId.parse("profile-one");
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "1601C",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .inherited = .{ .required_count = 8 },
    });
    try std.testing.expectEqual(PageState.inherited_only, state.page().?);
    try std.testing.expect(!state.annualReadiness().applicable);
    try std.testing.expectEqual(FilingReadiness.ready, state.filingReadiness());
    try std.testing.expect(state.affordances().can_start_new_filing);
    try std.testing.expectError(error.SetupNotSupported, state.beginEdit());

    try state.setInheritedReadiness(.{
        .required_count = 8,
        .missing_count = 1,
    });
    try std.testing.expectEqual(
        FilingReadiness.missing_inherited_values,
        state.filingReadiness(),
    );
    try std.testing.expect(state.affordances().can_edit_tax_profile);
    try std.testing.expect(!state.affordances().can_start_new_filing);
    try std.testing.expectEqual(@as(usize, 0), state.baselineValues().len);
}

test "setup opens needs-setup and clean edit actions stay disabled" {
    const profile_id = try model.ProfileId.parse("profile-one");
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .inherited = .{ .required_count = 4 },
        .annual_setup_required = true,
    });
    try std.testing.expectEqual(PageState.needs_setup, state.page().?);
    try std.testing.expectEqual(
        FilingReadiness.missing_annual_setup,
        state.filingReadiness(),
    );
    try state.beginEdit();
    try std.testing.expectEqual(PageState.editing, state.page().?);
    try std.testing.expect(!state.dirty());
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expect(!state.affordances().can_cancel);
    try std.testing.expectError(error.ActionDisabled, state.beginSave());
    try std.testing.expectError(error.ActionDisabled, state.cancel());

    try state.setDraftValue(try incomeRateValue("graduated"));
    try std.testing.expect(state.dirty());
    try std.testing.expect(state.affordances().can_save);
    try std.testing.expect(state.affordances().can_cancel);
    try state.cancel();
    try std.testing.expectEqual(PageState.needs_setup, state.page().?);
    try std.testing.expectEqual(@as(usize, 0), state.draftValues().len);
}

test "queued filing freezes the saved form-year profile without blocking filing" {
    const profile_id = try model.ProfileId.parse("profile-locked");
    const saved_value = try incomeRateValue("eight_percent");
    const saved = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "locked-rate-r1",
        1,
        .confirmed,
        &.{saved_value},
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .locked_by_filing = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &saved,
    });

    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqual(FilingReadiness.ready, state.filingReadiness());
    try std.testing.expect(state.affordances().can_start_new_filing);
    try std.testing.expect(!state.affordances().can_edit_tax_form_profile);
    try std.testing.expectError(error.LockedByFiling, state.beginEdit());
}

test "mid-year Forms Set activation is state-owned and emitted unchanged on save" {
    const profile_id = try model.ProfileId.parse("profile-midyear");
    const activation = try tax_form_profile.EffectivePeriod.init(
        try tax_form_profile.Date.init(2026, 7, 1),
        try tax_form_profile.Date.init(2026, 10, 31),
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = activation,
        .annual_setup_required = true,
    });
    try std.testing.expect(state.activationPeriod().?.eql(activation));

    try state.beginEdit();
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    try state.setDraftValues(&values);
    const intent = try state.beginSave();
    try std.testing.expect(intent.effective.eql(activation));

    var saved = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-midyear",
        1,
        .confirmed,
        &values,
    );
    saved.effective = activation;
    try state.saveSucceeded(&saved);
    try std.testing.expect(state.activationPeriod().?.eql(activation));
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
}

test "activation period is required for active routes and constrained to tax year" {
    const profile_id = try model.ProfileId.parse("profile-period-guard");
    try std.testing.expectError(error.MissingActivationPeriod, State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
    }));

    const crosses_year = try tax_form_profile.EffectivePeriod.init(
        try tax_form_profile.Date.init(2025, 12, 1),
        try tax_form_profile.Date.init(2026, 12, 31),
    );
    try std.testing.expectError(
        error.EffectivePeriodOutsideTaxYear,
        State.open(.{
            .profile_id = profile_id,
            .tax_year = 2026,
            .form_code = "2551Q",
            .active = true,
            .activation_period = crosses_year,
        }),
    );

    try std.testing.expectError(error.UnexpectedActivationPeriod, State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = false,
        .activation_period = try fullYearActivation(2026),
    }));
}

test "inactive history has no current activation and active revisions must match it" {
    const profile_id = try model.ProfileId.parse("profile-history-period");
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    var historical = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-history-period",
        2,
        .confirmed,
        &values,
    );
    historical.effective = try tax_form_profile.EffectivePeriod.init(
        try tax_form_profile.Date.init(2026, 3, 1),
        try tax_form_profile.Date.init(2026, 5, 31),
    );

    var inactive = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = false,
        .saved_revision = &historical,
    });
    try std.testing.expect(inactive.activationPeriod() == null);
    try std.testing.expectEqual(PageState.inactive_history_only, inactive.page().?);
    try std.testing.expectEqualStrings(
        "graduated",
        inactive.baselineValues()[0].value.choice.asSlice(),
    );
    try std.testing.expectError(error.InactiveForm, inactive.beginEdit());

    try std.testing.expectError(error.WrongActivationPeriod, State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &historical,
    }));
}

test "optional-only setup is ready without an empty annual revision" {
    const profile_id = try model.ProfileId.parse("profile-optional");
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "1701Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .inherited = .{ .required_count = 4 },
    });
    try std.testing.expectEqual(PageState.needs_setup, state.page().?);
    try std.testing.expectEqual(FilingReadiness.ready, state.filingReadiness());
    try std.testing.expect(state.affordances().can_start_new_filing);
    try std.testing.expectEqual(@as(usize, 0), state.baselineValues().len);

    try state.beginEdit();
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expectError(error.ActionDisabled, state.beginSave());
}

test "required 2551Q setup cannot be cleared and saved" {
    const profile_id = try model.ProfileId.parse("profile-optional-clear");
    const saved_value = try incomeRateValue("graduated");
    const saved = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "optional-clear-r1",
        1,
        .confirmed,
        &.{saved_value},
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &saved,
    });
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);

    try state.beginEdit();
    try state.removeDraftValue(.filer, .income_tax_rate_election);
    try std.testing.expect(state.dirty());
    try std.testing.expectEqual(@as(usize, 0), state.draftValues().len);
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expectError(error.ActionDisabled, state.beginSave());
}

test "confirmed setup becomes repairable when shared bindings stop resolving" {
    const profile_id = try model.ProfileId.parse("profile-binding-owner");
    const value = try incomeRateValue("graduated");
    const revision = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "binding-revision-1",
        1,
        .confirmed,
        &.{value},
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &revision,
    });
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqual(FilingReadiness.ready, state.filingReadiness());

    try state.setSavedBindingsResolved(false);
    try std.testing.expectEqual(PageState.needs_setup, state.page().?);
    try std.testing.expectEqual(
        FilingReadiness.missing_annual_setup,
        state.filingReadiness(),
    );
    try std.testing.expect(state.affordances().can_edit_tax_form_profile);
    try std.testing.expect(!state.affordances().can_start_new_filing);

    try state.setSavedBindingsResolved(true);
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqual(FilingReadiness.ready, state.filingReadiness());
}

test "view edit compares normalized typed values and dirty cancel restores in place" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    const revision = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-one",
        3,
        .confirmed,
        &values,
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &revision,
    });
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqual(@as(u32, 3), state.viewedIdentity().?.annual_revision_sequence);
    try std.testing.expectEqualStrings("2018-01-ENCS", state.viewedIdentity().?.formRevision().?);
    try state.beginEdit();

    // Domain parsing trims identifiers; a normalized no-op stays clean even
    // when it arrived through a new value object with different provenance.
    var same = try incomeRateValue("  graduated \n");
    same.source = .{ .migrated = try tax_form_profile.TextValue.parse("legacy") };
    try state.setDraftValue(same);
    try std.testing.expect(!state.dirty());
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expect(!state.affordances().can_cancel);

    try state.setDraftValue(try incomeRateValue("eight_percent"));
    try std.testing.expect(state.dirty());
    try state.cancel();
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqualStrings(
        "graduated",
        state.draftValues()[0].value.choice.asSlice(),
    );
}

test "inactive form preserves exact history identity and rejects every edit path" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    const revision = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-history",
        7,
        .confirmed,
        &values,
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = false,
        .saved_revision = &revision,
    });
    try std.testing.expectEqual(PageState.inactive_history_only, state.page().?);
    try std.testing.expect(state.affordances().can_view_history);
    try std.testing.expect(!state.affordances().can_edit_tax_form_profile);
    try std.testing.expectEqual(FilingReadiness.inactive, state.filingReadiness());
    try std.testing.expectError(error.InactiveForm, state.beginEdit());
    try std.testing.expectEqualStrings(
        "annual-history",
        state.viewedIdentity().?.annual_revision_id.?.asSlice(),
    );
}

test "inactive history keeps an old exact form and spec identity readable" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    var historical = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-old-spec",
        2,
        .confirmed,
        &values,
    );
    historical.stream.form_revision =
        try tax_form_profile.FormRevision.parse("2017-OLD");
    historical.spec_revision = 9;
    historical.spec_hash = try tax_form_profile.SpecHash.parse("old-spec-hash");

    var inactive = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = false,
        .saved_revision = &historical,
    });
    try std.testing.expectEqual(PageState.inactive_history_only, inactive.page().?);
    try std.testing.expectEqualStrings(
        "2017-OLD",
        inactive.viewedIdentity().?.formRevision().?,
    );
    try std.testing.expectEqual(@as(u32, 9), inactive.viewedIdentity().?.spec_revision.?);
    try std.testing.expectEqualStrings(
        "old-spec-hash",
        inactive.viewedIdentity().?.specHash().?,
    );

    try std.testing.expectError(error.WrongViewedIdentity, State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &historical,
    }));
}

test "prior-year copy is explicit reviewable provenance and cancel restores baseline" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const prior_values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    const prior = try fixtureRevision(
        "2551Q",
        profile_id,
        2025,
        "annual-2025",
        2,
        .confirmed,
        &prior_values,
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .copy_offer = .{
            .source = RevisionIdentity.fromRevision(&prior),
            .compatibility = .exact,
        },
    });
    try std.testing.expect(state.affordances().can_copy_prior_year);
    try state.stagePriorYearCopy(&prior_values);
    try std.testing.expectEqual(PageState.editing, state.page().?);
    try std.testing.expect(state.dirty());
    try std.testing.expect(state.affordances().can_review_copy_or_reuse);
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expect(state.affordances().can_cancel);
    try state.acknowledgeReview();
    try std.testing.expect(state.affordances().can_save);
    const intent = try state.beginSave();
    try std.testing.expectEqual(ReviewRequirement.prior_year_copy, intent.review_requirement);
    try std.testing.expectEqual(@as(u16, 2025), intent.copied_from.?.tax_year);
    try std.testing.expectEqualStrings(
        "annual-2025",
        intent.copied_from.?.revision_id.asSlice(),
    );
    try std.testing.expect(
        intent.values[0].source.copied_from_revision.eql(
            &prior.id,
        ),
    );

    try state.saveFailed();
    try std.testing.expect(state.affordances().can_cancel);
    try state.cancel();
    try std.testing.expectEqual(PageState.needs_setup, state.page().?);
    try std.testing.expectEqual(@as(usize, 0), state.draftValues().len);
}

test "mapping review and incompatible copy never bypass exact compatibility" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const prior_values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    var prior = try fixtureRevision(
        "2551Q",
        profile_id,
        2025,
        "annual-2025",
        1,
        .confirmed,
        &prior_values,
    );
    prior.stream.form_revision = try tax_form_profile.FormRevision.parse(
        "2017-OLD",
    );
    prior.spec_revision = 9;
    prior.spec_hash = try tax_form_profile.SpecHash.parse("old-spec-hash");
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .copy_offer = .{
            .source = RevisionIdentity.fromRevision(&prior),
            .compatibility = .requires_mapping_review,
            .reason = .form_revision_mapping,
        },
    });
    try std.testing.expect(!state.affordances().can_copy_prior_year);
    try std.testing.expect(state.affordances().can_review_compatibility);
    try std.testing.expectError(
        error.CopyUnavailable,
        state.stagePriorYearCopy(&prior_values),
    );
    try state.stageFormRevisionMapping(&prior_values);
    try std.testing.expectEqual(@as(u16, 1), state.mappingReview().?.mapped_count);
    try std.testing.expectEqual(@as(usize, 0), state.mappingReview().?.issue_count);
    try std.testing.expect(!state.affordances().can_save);
    try state.acknowledgeReview();
    try std.testing.expect(state.affordances().can_save);
    const intent = try state.beginSave();
    try std.testing.expectEqual(
        ReviewRequirement.form_revision_mapping,
        intent.review_requirement,
    );
    try std.testing.expectEqualStrings(
        "2017-OLD",
        intent.copied_from.?.form_revision.asSlice(),
    );
}

test "mapping review surfaces removed and changed values" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const spouse_id = try model.ProfileId.parse("profile-spouse");
    const source_values = [_]tax_form_profile.SetupValue{
        .{
            .semantic_key = .spouse_profile_id,
            .role = .spouse,
            .value = .{ .profile_id = spouse_id },
        },
        .{
            .semantic_key = .income_tax_rate_election,
            .role = .filer,
            .value = .{ .choice = try tax_form_profile.TextValue.parse("graduated") },
        },
        .{
            .semantic_key = .spouse_profile_id,
            .role = .spouse,
            .value = .{ .text = try tax_form_profile.TextValue.parse("legacy-spouse") },
        },
    };
    var prior = try fixtureRevision(
        "1701Q",
        profile_id,
        2025,
        "annual-old-mixed",
        1,
        .confirmed,
        &source_values,
    );
    prior.stream.form_revision = try tax_form_profile.FormRevision.parse(
        "2017-OLD",
    );
    prior.spec_revision = 1;
    prior.spec_hash = try tax_form_profile.SpecHash.parse("old-spec-hash");
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "1701Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .copy_offer = .{
            .source = RevisionIdentity.fromRevision(&prior),
            .compatibility = .requires_mapping_review,
            .reason = .form_revision_mapping,
        },
    });
    try state.stageFormRevisionMapping(&source_values);
    const review = state.mappingReview().?;
    try std.testing.expectEqual(@as(u16, 1), review.mapped_count);
    try std.testing.expectEqual(@as(usize, 2), review.issue_count);
    try std.testing.expectEqual(
        MappingIssueReason.not_in_current_spec,
        review.issueSlice()[0].reason,
    );
    try std.testing.expectEqual(
        MappingIssueReason.value_type_changed,
        review.issueSlice()[1].reason,
    );
    try std.testing.expectEqual(@as(usize, 1), state.draftValues().len);
    try std.testing.expect(!state.affordances().can_save);
    try state.acknowledgeReview();
    try std.testing.expect(state.affordances().can_save);
}

test "optimistic conflict preserves draft and exposes explicit rebase and reload" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const baseline_values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    const baseline = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-one",
        3,
        .confirmed,
        &baseline_values,
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &baseline,
    });
    try state.beginEdit();
    try state.setDraftValue(try incomeRateValue("eight_percent"));
    _ = try state.beginSave();
    try state.noteConflict(4);
    try std.testing.expectEqual(FilingReadiness.conflict, state.filingReadiness());
    try std.testing.expectEqualStrings(
        "eight_percent",
        state.draftValues()[0].value.choice.asSlice(),
    );
    try std.testing.expect(state.affordances().can_reload_conflict);
    try std.testing.expect(state.affordances().can_rebase_conflict);
    try std.testing.expect(!state.affordances().can_save);
    try std.testing.expectError(
        error.WrongConflictSequence,
        state.acceptReviewedConflictBase(5),
    );
    try state.acceptReviewedConflictBase(4);
    try std.testing.expect(state.affordances().can_save);
    const retry = try state.beginSave();
    try std.testing.expectEqual(@as(u32, 4), retry.expected_sequence);
    try state.noteConflict(5);

    const latest_values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    const latest = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-latest",
        5,
        .confirmed,
        &latest_values,
    );
    try state.reloadAfterConflict(&latest, 5);
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqualStrings(
        "graduated",
        state.draftValues()[0].value.choice.asSlice(),
    );
}

test "successful save advances exact identity while failed save retains draft" {
    const profile_id = try model.ProfileId.parse("profile-one");
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
    });
    try state.beginEdit();
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    try state.setDraftValues(&values);
    _ = try state.beginSave();
    try state.saveFailed();
    try std.testing.expectEqual(SaveStatus.failed, state.save_status);
    try std.testing.expectEqualStrings(
        "graduated",
        state.draftValues()[0].value.choice.asSlice(),
    );
    _ = try state.beginSave();
    const saved = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-saved",
        1,
        .confirmed,
        &values,
    );
    try state.saveSucceeded(&saved);
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);
    try std.testing.expectEqual(@as(u32, 1), state.viewedIdentity().?.annual_revision_sequence);
    try std.testing.expectEqual(FilingReadiness.ready, state.filingReadiness());
    try std.testing.expect(!state.dirty());
}

test "persisted unconfirmed revision remains needs-setup until explicit review" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    var pending = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-pending",
        1,
        .requires_review,
        &values,
    );
    pending.source = .{ .copied_from_prior_year = .{
        .source_tax_year = 2025,
        .source_form_revision = pending.stream.form_revision,
        .source_spec_revision = pending.spec_revision,
        .source_spec_hash = pending.spec_hash,
        .source_revision_id = try tax_form_profile.RevisionId.parse("annual-2025"),
    } };
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &pending,
    });
    try std.testing.expectEqual(PageState.needs_setup, state.page().?);
    try std.testing.expectEqual(
        FilingReadiness.requires_review,
        state.filingReadiness(),
    );
    try std.testing.expectEqual(
        @as(u16, 2025),
        state.persistedCopyProvenance().?.source_tax_year,
    );
    try std.testing.expectEqualStrings(
        "annual-2025",
        state.persistedCopyProvenance().?.source_revision_id.asSlice(),
    );
    try state.beginEdit();
    try std.testing.expect(!state.affordances().can_save);
    try state.acknowledgeReview();
    try std.testing.expect(state.dirty());
    try std.testing.expect(state.affordances().can_save);
}

test "reactivated confirmed setup requires an explicit review acknowledgement" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    const revision = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-reactivated",
        4,
        .confirmed,
        &values,
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &revision,
        .review_requirement = .reactivation,
    });
    try std.testing.expectEqual(PageState.needs_setup, state.page().?);
    try std.testing.expectEqual(FilingReadiness.requires_review, state.filingReadiness());
    try state.beginEdit();
    try std.testing.expect(!state.dirty());
    try state.acknowledgeReview();
    try std.testing.expect(state.dirty());
    try std.testing.expect(state.affordances().can_save);
    try state.cancel();
    try std.testing.expectEqual(PageState.needs_setup, state.page().?);
    try std.testing.expectEqual(FilingReadiness.requires_review, state.filingReadiness());
}

test "same-year reactivation offers compatible setup as an explicit reviewed draft" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    const prior_segment = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-first-segment",
        3,
        .confirmed,
        &values,
    );
    const second_segment = try tax_form_profile.EffectivePeriod.init(
        try tax_form_profile.Date.init(2026, 7, 1),
        try tax_form_profile.Date.init(2026, 12, 31),
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = second_segment,
        .history_exists = true,
        .expected_current_sequence = prior_segment.sequence,
        .copy_offer = .{
            .source = RevisionIdentity.fromRevision(&prior_segment),
            .compatibility = .exact,
            .reason = .reactivation,
        },
    });
    try std.testing.expect(!state.affordances().can_copy_prior_year);
    try std.testing.expect(state.affordances().can_reuse_after_reactivation);
    try state.stageReactivationReuse(prior_segment.values);
    try std.testing.expectEqual(PageState.editing, state.page().?);
    try std.testing.expect(state.dirty());
    try std.testing.expect(state.affordances().can_review_copy_or_reuse);
    try std.testing.expect(!state.affordances().can_save);
    try state.acknowledgeReview();
    const intent = try state.beginSave();
    try std.testing.expectEqual(ReviewRequirement.reactivation, intent.review_requirement);
    try std.testing.expectEqual(prior_segment.sequence, intent.expected_sequence);
    try std.testing.expectEqual(@as(u16, 2026), intent.copied_from.?.tax_year);
    try std.testing.expect(intent.effective.eql(second_segment));
    try std.testing.expect(
        intent.values[0].source.copied_from_revision.eql(
            &prior_segment.id,
        ),
    );
}

test "an older activation segment edits against the stream-wide optimistic head" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    var first_segment = try fixtureRevision(
        "2551Q",
        profile_id,
        2026,
        "annual-first-segment",
        1,
        .confirmed,
        &values,
    );
    first_segment.effective = try tax_form_profile.EffectivePeriod.init(
        try tax_form_profile.Date.init(2026, 1, 1),
        try tax_form_profile.Date.init(2026, 6, 30),
    );
    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = first_segment.effective,
        .saved_revision = &first_segment,
        .expected_current_sequence = 2,
    });
    try std.testing.expectEqual(@as(u32, 1), state.viewedIdentity().?.annual_revision_sequence);
    try std.testing.expectEqual(@as(u32, 2), state.expected_sequence);
    try state.beginEdit();
    try state.setDraftValue(try incomeRateValue("eight_percent"));
    const intent = try state.beginSave();
    try std.testing.expectEqual(@as(u32, 2), intent.expected_sequence);
    try std.testing.expect(intent.effective.eql(first_segment.effective));

    // A conflict can be caused by a save in another activation interval. The
    // selected interval still reloads its own latest revision while adopting
    // the stream-wide sequence as the next optimistic base.
    try state.noteConflict(3);
    try state.reloadAfterConflict(&first_segment, 3);
    try std.testing.expectEqual(@as(u32, 1), state.viewedIdentity().?.annual_revision_sequence);
    try std.testing.expectEqual(@as(u32, 3), state.expected_sequence);
    try std.testing.expectEqual(PageState.viewing_ready, state.page().?);

    try std.testing.expectError(error.WrongExpectedSequence, State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = first_segment.effective,
        .saved_revision = &first_segment,
        .expected_current_sequence = 0,
    }));
}

test "wrong profile year and exact revision identities fail closed" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const other_profile = try model.ProfileId.parse("profile-two");
    const values = [_]tax_form_profile.SetupValue{
        try incomeRateValue("graduated"),
    };
    const wrong_owner = try fixtureRevision(
        "2551Q",
        other_profile,
        2026,
        "annual-other",
        1,
        .confirmed,
        &values,
    );
    try std.testing.expectError(error.WrongViewedIdentity, State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &wrong_owner,
    }));

    const wrong_year = try fixtureRevision(
        "2551Q",
        profile_id,
        2025,
        "annual-2025",
        1,
        .confirmed,
        &values,
    );
    try std.testing.expectError(error.WrongViewedIdentity, State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .saved_revision = &wrong_year,
    }));
}

test "invalid inherited counts and values outside the current contract are rejected" {
    const profile_id = try model.ProfileId.parse("profile-one");
    try std.testing.expectError(error.InvalidInheritedReadiness, State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "1601C",
        .active = true,
        .activation_period = try fullYearActivation(2026),
        .inherited = .{ .required_count = 1, .missing_count = 2 },
    }));

    var state = try State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "1701Q",
        .active = true,
        .activation_period = try fullYearActivation(2026),
    });
    try state.beginEdit();
    const unsupported: tax_form_profile.SetupValue = .{
        .semantic_key = .income_tax_rate_election,
        .role = .filer,
        .value = .{ .choice = try tax_form_profile.TextValue.parse("graduated") },
    };
    try std.testing.expectError(error.UnknownSemanticKey, state.setDraftValue(unsupported));
}
