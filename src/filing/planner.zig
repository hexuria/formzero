//! Pure, evidence-fail-closed filing-scope planning.
//!
//! This module deliberately has no dependency on UI selection, Forms Set, a
//! profile, or persistence. Callers supply an explicit policy catalog and an
//! effective-dated registration snapshot. A result is zero or more immutable
//! obligations, explicit non-applicability, or a deterministically ordered set
//! of review reasons. It never guesses a filing unit or falls back to a
//! selected workspace profile.

const std = @import("std");
const builtin = @import("builtin");
const evidence_binding = @import("evidence_binding.zig");
const policy = @import("policy.zig");
const registration = @import("../tax_profile/registration_domain.zig");

pub const ResolutionHash = [32]u8;
/// Versioned whenever the immutable decision payload changes. Version 7 binds
/// the exact accepted review decision/sequence and assertion for every
/// registration fact selected into an obligation or non-applicability result.
pub const decision_schema_version: u16 = 7;

/// Inclusive civil period. This is intentionally separate from a filing
/// deadline or a policy effective period: the planner needs to prove that
/// every registration fact is stable for this entire period.
pub const FilingPeriodKind = enum {
    calendar_month,
    calendar_quarter,
    taxable_year,
    fiscal_period,
    date_range,
    event_or_transaction,
};

pub const FilingPeriodError = error{
    InvalidDate,
    InvalidRange,
    InvalidCalendarMonth,
    InvalidCalendarQuarter,
    InvalidTaxableYear,
};

/// Typed inclusive civil period. Semantic identity is explicit because equal
/// bounds can represent a calendar period, an arbitrary range, or a specific
/// event/transaction and therefore must not resolve or hash interchangeably.
pub const FilingPeriod = struct {
    kind: FilingPeriodKind,
    from: registration.Date,
    until: registration.Date,

    /// Compatibility constructor for existing callers. Exact Gregorian month,
    /// quarter, and calendar-year bounds are classified; every other valid
    /// interval remains an explicit date range.
    pub fn init(
        from: registration.Date,
        until: registration.Date,
    ) FilingPeriodError!FilingPeriod {
        if (!isValidCivilDate(from) or !isValidCivilDate(until)) {
            return error.InvalidDate;
        }
        if (until.isBefore(from)) return error.InvalidRange;
        return .{
            .kind = classifyStandardPeriod(from, until),
            .from = from,
            .until = until,
        };
    }

    pub fn initTyped(
        kind: FilingPeriodKind,
        from: registration.Date,
        until: registration.Date,
    ) FilingPeriodError!FilingPeriod {
        const result: FilingPeriod = .{
            .kind = kind,
            .from = from,
            .until = until,
        };
        try result.validate();
        return result;
    }

    pub fn validate(self: FilingPeriod) FilingPeriodError!void {
        if (!isValidCivilDate(self.from) or !isValidCivilDate(self.until)) {
            return error.InvalidDate;
        }
        if (self.until.isBefore(self.from)) return error.InvalidRange;

        switch (self.kind) {
            .calendar_month => if (!isExactCalendarMonth(self.from, self.until)) {
                return error.InvalidCalendarMonth;
            },
            .calendar_quarter => if (!isExactCalendarQuarter(self.from, self.until)) {
                return error.InvalidCalendarQuarter;
            },
            .taxable_year => if (!isExactTaxableYear(self.from, self.until)) {
                return error.InvalidTaxableYear;
            },
            // A fiscal policy owns its own cadence and anchor. Until one is
            // implemented, the type preserves only the explicit semantics and
            // inclusive valid bounds instead of inventing a universal fiscal
            // year shape.
            .fiscal_period, .date_range, .event_or_transaction => {},
        }
    }

    pub fn contains(self: FilingPeriod, value: registration.Date) bool {
        return !value.isBefore(self.from) and !value.isAfter(self.until);
    }
};

/// Compatibility alias for downstream consumers while they adopt the more
/// precise name. This is no longer an untyped pair of dates.
pub const CivilPeriod = FilingPeriod;

const RevisionBindingKind = enum {
    large_taxpayer_service,
    registered_facility,
};

fn RevisionBindingId(comptime kind: RevisionBindingKind, comptime maximum: usize) type {
    const KindMarker = switch (kind) {
        .large_taxpayer_service => struct {},
        .registered_facility => struct {},
    };
    return struct {
        const Self = @This();

        _kind: KindMarker = .{},
        bytes: [maximum]u8 = [_]u8{0} ** maximum,
        len: std.math.IntFittingRange(0, maximum) = 0,

        pub fn parse(raw: []const u8) error{ Empty, TooLong, InvalidCharacter }!Self {
            const value = std.mem.trim(u8, raw, " \t\r\n");
            if (value.len == 0) return error.Empty;
            if (value.len > maximum) return error.TooLong;
            for (value) |byte| {
                if (!(std.ascii.isAlphanumeric(byte) or
                    byte == '-' or byte == '_' or byte == '.' or
                    byte == ':' or byte == '/'))
                {
                    return error.InvalidCharacter;
                }
            }
            var result: Self = .{};
            @memcpy(result.bytes[0..value.len], value);
            result.len = @intCast(value.len);
            return result;
        }

        pub fn asSlice(self: *const Self) []const u8 {
            return self.bytes[0..self.len];
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.len == 0;
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            return std.mem.eql(u8, self.asSlice(), other.asSlice());
        }
    };
}

pub const LargeTaxpayerServiceRevisionId = RevisionBindingId(.large_taxpayer_service, 64);
pub const RegisteredFacilityRevisionId = RevisionBindingId(.registered_facility, 64);
comptime {
    std.debug.assert(LargeTaxpayerServiceRevisionId != RegisteredFacilityRevisionId);
}

pub const ReviewedEvidenceBinding = evidence_binding.ReviewedEvidenceBinding;
pub const EvidenceFactSubject = evidence_binding.FactSubject;
pub const EvidenceReviewIssue = evidence_binding.EvidenceReviewIssue;
pub const EvidenceReviewSubject = evidence_binding.EvidenceReviewSubject;

/// Content-addressed reference to typed transaction/property/facility context.
/// The digest must already include its own domain and context-kind identity.
pub const SpecialFilingContextRef = struct {
    digest: [32]u8,
};

pub const SourceAttributionRequirement = enum {
    not_required,
    required,
};

/// Scope resolution must not be mistaken for legal venue resolution. The
/// initial slice has no reviewed venue policy and therefore cannot guess one.
pub const FilingVenueResolution = enum {
    not_resolved_by_scope,
    review_required,
};

/// A request contains identity and filing facts only. In particular, it has no
/// `filer_profile_id`, selected-branch, or Forms Set field.
pub const PlanningRequest = struct {
    taxpayer_id: registration.TaxpayerId,
    form_revision: policy.FormRevisionKey,
    civil_period: CivilPeriod,
    special_context: ?SpecialFilingContextRef = null,
};

pub const TaxType = registration.TaxType;

/// The planner mirrors the registration-unit lifecycle instead of deriving
/// active VAT registration from a profile flag or a UI choice.
pub const TaxTypeRegistrationState = registration.TaxTypeRegistrationStatus;

/// Exact tax-registration provenance is independent from return coverage. A
/// consolidated 2550Q covers applicable source units, while its reviewed VAT
/// registration remains a head-office fact.
pub const TaxTypeRegistrationBinding = struct {
    registration_unit_id: registration.RegistrationUnitId,
    registration_id: registration.TaxTypeRegistrationId,
    revision_id: registration.TaxTypeRegistrationRevisionId,
    tax_type: TaxType,
    status: TaxTypeRegistrationState,
    effective: registration.EffectivePeriod,
    evidence_id: registration.RegistrationEvidenceId,
};

/// An explicit snapshot prevents the planner from re-reading mutable storage
/// during resolution. The ledger can map its `ResolvedRegistrationSnapshot`
/// directly into this adapter while retaining its own evidence schema.
pub const RegistrationSnapshot = struct {
    taxpayer_identity: registration.TaxpayerIdentityRevision,
    unit_revisions: []const registration.RegistrationUnitRevision,
    registration_unit_contacts: []const registration.RegistrationUnitContactRevision = &.{},
    tax_type_registrations: []const registration.TaxTypeRegistrationRevision,
    /// Production snapshots always supply exact accepted authority bindings.
    /// The default exists only for quarantined pure test fixtures.
    reviewed_evidence_bindings: []const ReviewedEvidenceBinding = &.{},
    enforce_reviewed_evidence_bindings: bool = false,
};

/// Product/editor support is deliberately distinct from whether the resolved
/// obligation can be submitted. The first 2550Q slice is always not fileable.
pub const FilingCapability = enum {
    not_fileable,
    fileable,
};

pub const RegistrationUnitCoverage = struct {
    registration_unit_id: registration.RegistrationUnitId,
    registration_unit_revision_id: registration.RegistrationUnitRevisionId,
    branch_code: registration.BranchCode5,
    branch_code_evidence_id: registration.RegistrationEvidenceId,
};

/// The resolved filing unit and its coverage are exact immutable evidence
/// references. No profile or user-selected branch is present here.
pub const FilingObligation = struct {
    decision_schema_version: u16 = decision_schema_version,
    taxpayer_identity: registration.TaxpayerIdentityRevision,
    form_revision: policy.FormRevisionKey,
    civil_period: CivilPeriod,
    filing_unit_id: registration.RegistrationUnitId,
    filing_unit_revision_id: registration.RegistrationUnitRevisionId,
    filing_branch_code: registration.BranchCode5,
    filing_branch_evidence_id: registration.RegistrationEvidenceId,
    filing_unit_rdo_code: ?registration.RdoCode3,
    filing_unit_contact: registration.RegistrationUnitContactRevision,
    coverage: []const RegistrationUnitCoverage,
    tax_type_registration_bindings: []const TaxTypeRegistrationBinding,
    reviewed_evidence_bindings: []const ReviewedEvidenceBinding,
    lts_revision_id: ?LargeTaxpayerServiceRevisionId = null,
    facility_revision_ids: []const RegisteredFacilityRevisionId = &.{},
    source_attribution_requirement: SourceAttributionRequirement = .not_required,
    policy_revision_id: policy.FilingPolicyRevisionId,
    policy_evidence_ids: []const policy.PolicyEvidenceId,
    special_context_digest: ?[32]u8 = null,
    policy_capability: policy.CapabilityState,
    filing_capability: FilingCapability,
    filing_venue_resolution: FilingVenueResolution = .not_resolved_by_scope,
    resolution_hash: ResolutionHash,

    pub fn deinit(self: FilingObligation, allocator: std.mem.Allocator) void {
        allocator.free(self.coverage);
        allocator.free(self.tax_type_registration_bindings);
        allocator.free(self.reviewed_evidence_bindings);
        allocator.free(self.facility_revision_ids);
        allocator.free(self.policy_evidence_ids);
    }
};

/// Values are declared in resolution order so the result is stable even if a
/// caller supplies unit/evidence arrays in a different order.
pub const ReviewReason = enum {
    invalid_filing_period,
    unsupported_filing_period_semantics,
    unsupported_special_context,
    taxpayer_identity_mismatch,
    invalid_taxpayer_identity,
    taxpayer_identity_not_effective_for_period,
    taxpayer_identity_missing,
    taxpayer_identity_changed_during_period,
    evidence_review_missing,
    evidence_rejected,
    evidence_superseded,
    evidence_protected_bytes_missing,
    evidence_protected_bytes_unreadable,
    evidence_protected_bytes_size_mismatch,
    evidence_protected_bytes_digest_mismatch,
    evidence_stored_metadata_invalid,
    evidence_storage_backend_unverifiable,
    missing_effective_policy,
    conflicting_effective_policy,
    invalid_effective_policy,
    invalid_policy_catalog,
    policy_requires_review,
    policy_changed_during_period,
    unsupported_form_revision,
    unsupported_policy_category,
    missing_head_office,
    conflicting_head_office,
    head_office_not_confirmed,
    head_office_branch_code_invalid,
    registration_unit_taxpayer_mismatch,
    invalid_registration_unit,
    registration_unit_mid_period_state_change,
    registration_unit_pending_evidence,
    registration_unit_legacy_unresolved,
    registration_unit_closed,
    missing_filing_unit_contact,
    filing_unit_contact_mid_period_change,
    invalid_filing_unit_contact,
    filing_unit_contact_mismatch,
    missing_vat_registration_evidence,
    conflicting_vat_registration_evidence,
    vat_registration_not_bound_to_head_office,
    vat_registration_pending_evidence,
    vat_registration_legacy_unresolved,
    vat_registration_mid_period_state_change,
};

/// The concrete domain subject affected by one review finding. Keeping this
/// separate from the display-oriented `ReviewReason` prevents two units or
/// evidence objects with the same reason from being collapsed.
pub const ReviewSubject = union(enum) {
    planning_request,
    filing_period: CivilPeriod,
    taxpayer: registration.TaxpayerId,
    taxpayer_revision: registration.TaxpayerRevisionId,
    form_revision: policy.FormRevisionKey,
    policy_endpoint: struct {
        form_revision: policy.FormRevisionKey,
        date: registration.Date,
    },
    policy_revision: policy.FilingPolicyRevisionId,
    registration_unit: registration.RegistrationUnitId,
    registration_unit_revision: registration.RegistrationUnitRevisionId,
    registration_unit_contact_revision: registration.RegistrationUnitContactRevisionId,
    tax_type_registration: registration.TaxTypeRegistrationId,
    tax_type_registration_revision: registration.TaxTypeRegistrationRevisionId,
    evidence: registration.RegistrationEvidenceId,
};

pub const EvidenceIntegrityCause = enum {
    protected_bytes_missing,
    protected_bytes_unreadable,
    protected_bytes_size_mismatch,
    protected_bytes_digest_mismatch,
    stored_metadata_invalid,
    storage_backend_unverifiable,
};

/// Payloads retain source-layer diagnostics that the old reason-only list
/// discarded. They are domain values rather than localized UI strings.
pub const ReviewIssueDetail = union(enum) {
    none,
    policy_catalog_validation: policy.ValidationError,
    policy_selection: policy.PolicySelectionIssue,
    registration_validation: registration.RegistrationError,
    evidence_integrity: EvidenceIntegrityCause,
};

pub const ReviewIssue = struct {
    reason: ReviewReason,
    subject: ReviewSubject,
    /// Exact evidence reference for review-state failures. Null only when the
    /// registration fact itself has no evidence reference to repair.
    evidence_id: ?registration.RegistrationEvidenceId = null,
    detail: ReviewIssueDetail = .none,
};

/// Allocator-owned legal filing scope retained when header/contact projection
/// still needs review. This is intentionally preview-only and cannot be
/// converted into a draft or submission.
pub const ResolvedLegalFilingScope = struct {
    decision_schema_version: u16 = decision_schema_version,
    taxpayer_identity: registration.TaxpayerIdentityRevision,
    form_revision: policy.FormRevisionKey,
    civil_period: CivilPeriod,
    filing_unit_id: registration.RegistrationUnitId,
    filing_unit_revision_id: registration.RegistrationUnitRevisionId,
    filing_branch_code: registration.BranchCode5,
    filing_branch_evidence_id: registration.RegistrationEvidenceId,
    filing_unit_rdo_code: ?registration.RdoCode3,
    coverage: []const RegistrationUnitCoverage,
    tax_type_registration_bindings: []const TaxTypeRegistrationBinding,
    reviewed_evidence_bindings: []const ReviewedEvidenceBinding,
    policy_revision_id: policy.FilingPolicyRevisionId,
    policy_evidence_ids: []const policy.PolicyEvidenceId,
    policy_capability: policy.CapabilityState,
    resolution_hash: ResolutionHash,

    pub fn deinit(self: ResolvedLegalFilingScope, allocator: std.mem.Allocator) void {
        allocator.free(self.coverage);
        allocator.free(self.tax_type_registration_bindings);
        allocator.free(self.reviewed_evidence_bindings);
        allocator.free(self.policy_evidence_ids);
    }
};

pub const NotApplicableReason = enum {
    confirmed_closed_tax_type_registration,
};

/// Non-applicability is an immutable decision, not absence of an obligation.
/// It retains the same taxpayer, filing-scope, policy, registration, and exact
/// evidence authority needed to reproduce why the form did not apply.
pub const NotApplicableDecision = struct {
    scope: ResolvedLegalFilingScope,
    reason: NotApplicableReason,
    resolution_hash: ResolutionHash,

    pub fn deinit(self: NotApplicableDecision, allocator: std.mem.Allocator) void {
        self.scope.deinit(allocator);
    }
};

pub const ReviewRequiredPlan = struct {
    issues: []const ReviewIssue,
    resolved_legal_scope: ?ResolvedLegalFilingScope = null,

    pub fn deinit(self: ReviewRequiredPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.issues);
        if (self.resolved_legal_scope) |scope| scope.deinit(allocator);
    }
};

pub const ResolvedFilingPlan = union(enum) {
    obligations: []FilingObligation,
    not_applicable: NotApplicableDecision,
    review_required: ReviewRequiredPlan,

    pub fn deinit(self: *ResolvedFilingPlan, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .obligations => |values| {
                for (values) |value| value.deinit(allocator);
                allocator.free(values);
            },
            .not_applicable => |value| value.deinit(allocator),
            .review_required => |value| value.deinit(allocator),
        }
        self.* = undefined;
    }
};

/// The only currently implemented policy slice is the exact reviewed 2550Q
/// 2024-04-ENCS head-office-consolidated fixture. Every other policy result is
/// intentionally review required until a dedicated resolver is added.
pub const FilingPlanner = struct {
    policy_catalog: policy.FilingPolicyCatalog,

    pub fn init(policy_catalog: policy.FilingPolicyCatalog) FilingPlanner {
        return .{ .policy_catalog = policy_catalog };
    }

    /// Production planning entry point. The adapter remains generic so this
    /// pure module stays SQLite-free; the supplied ledger must expose
    /// `planningSnapshotWithEvidenceIntegrity({ taxpayer_id, start, end },
    /// verifier)` and an allocator used to release the snapshot. UI/profile
    /// callers cannot assemble arbitrary registration revisions or bypass
    /// verification of referenced protected evidence bytes.
    pub fn plan(
        self: FilingPlanner,
        allocator: std.mem.Allocator,
        ledger: anytype,
        evidence_integrity_verifier: anytype,
        request: PlanningRequest,
    ) anyerror!ResolvedFilingPlan {
        var request_review = ReviewCollector.init(allocator);
        defer request_review.deinit();
        try addRequestContractIssues(&request_review, request);
        if (request_review.hasAny()) {
            return reviewResult(allocator, &request_review);
        }

        var snapshot_result = try ledger.planningSnapshotWithEvidenceIntegrity(
            .{
                .taxpayer_id = request.taxpayer_id,
                .start = request.civil_period.from,
                .end = request.civil_period.until,
            },
            evidence_integrity_verifier,
        );
        defer snapshot_result.deinit(ledger.allocator);

        return switch (snapshot_result) {
            .registration_review_required => |cause| blk: {
                var review = ReviewCollector.init(allocator);
                defer review.deinit();
                switch (cause) {
                    .taxpayer_identity_missing => try review.addFor(
                        .taxpayer_identity_missing,
                        .{ .taxpayer = request.taxpayer_id },
                    ),
                    .taxpayer_identity_changed_during_period => try review.addFor(
                        .taxpayer_identity_changed_during_period,
                        .{ .taxpayer = request.taxpayer_id },
                    ),
                    .evidence => |issue| try review.addIssue(.{
                        .reason = switch (issue.reason) {
                            .missing => .evidence_review_missing,
                            .rejected => .evidence_rejected,
                            .superseded => .evidence_superseded,
                        },
                        .subject = reviewSubjectForEvidence(issue.subject),
                        .evidence_id = issue.evidence_id,
                    }),
                }
                break :blk reviewResult(allocator, &review);
            },
            .evidence_integrity_review_required => |cause| blk: {
                var review = ReviewCollector.init(allocator);
                defer review.deinit();
                const integrity_cause = evidenceIntegrityCause(cause);
                const reason: ReviewReason = switch (integrity_cause) {
                    .protected_bytes_missing => .evidence_protected_bytes_missing,
                    .protected_bytes_unreadable => .evidence_protected_bytes_unreadable,
                    .protected_bytes_size_mismatch => .evidence_protected_bytes_size_mismatch,
                    .protected_bytes_digest_mismatch => .evidence_protected_bytes_digest_mismatch,
                    .stored_metadata_invalid => .evidence_stored_metadata_invalid,
                    .storage_backend_unverifiable => .evidence_storage_backend_unverifiable,
                };
                try review.addIssue(.{
                    .reason = reason,
                    .subject = evidenceIntegritySubject(cause),
                    .detail = .{ .evidence_integrity = integrity_cause },
                });
                break :blk reviewResult(allocator, &review);
            },
            .resolved => |snapshot| blk: {
                const adapter: RegistrationSnapshot = .{
                    .taxpayer_identity = snapshot.taxpayer_identity,
                    .unit_revisions = snapshot.units,
                    .registration_unit_contacts = snapshot.contacts,
                    .tax_type_registrations = snapshot.tax_type_registrations,
                    .reviewed_evidence_bindings = if (@hasField(
                        @TypeOf(snapshot),
                        "reviewed_evidence_bindings",
                    )) snapshot.reviewed_evidence_bindings else &.{},
                    .enforce_reviewed_evidence_bindings = true,
                };
                if (builtin.is_test and !@hasField(
                    @TypeOf(snapshot),
                    "reviewed_evidence_bindings",
                )) {
                    break :blk testing.planForSnapshot(self, allocator, request, adapter);
                }
                break :blk self.planForSnapshot(allocator, request, adapter);
            },
        };
    }

    /// Internal pure resolver. Production callers can only reach it through
    /// `plan`, which obtains one coherent period snapshot from the ledger.
    fn planForSnapshot(
        self: FilingPlanner,
        allocator: std.mem.Allocator,
        request: PlanningRequest,
        snapshot: RegistrationSnapshot,
    ) std.mem.Allocator.Error!ResolvedFilingPlan {
        var review = ReviewCollector.init(allocator);
        defer review.deinit();

        try addRequestContractIssues(&review, request);
        if (review.hasAny()) {
            return reviewResult(allocator, &review);
        }

        self.policy_catalog.validate() catch |err| {
            try review.addIssue(.{
                .reason = .invalid_policy_catalog,
                .subject = .{ .form_revision = request.form_revision },
                .detail = .{ .policy_catalog_validation = err },
            });
            return reviewResult(allocator, &review);
        };

        snapshot.taxpayer_identity.validate() catch {
            try review.addFor(.invalid_taxpayer_identity, .{
                .taxpayer_revision = snapshot.taxpayer_identity.id,
            });
        };
        if (snapshot.taxpayer_identity.evidence_id == null) {
            try review.addFor(.invalid_taxpayer_identity, .{
                .taxpayer_revision = snapshot.taxpayer_identity.id,
            });
        }
        if (!request.taxpayer_id.eql(&snapshot.taxpayer_identity.taxpayer_id)) {
            try review.addFor(.taxpayer_identity_mismatch, .{
                .taxpayer_revision = snapshot.taxpayer_identity.id,
            });
        }
        if (!effectiveCovers(snapshot.taxpayer_identity.effective, request.civil_period)) {
            try review.addFor(.taxpayer_identity_not_effective_for_period, .{
                .taxpayer_revision = snapshot.taxpayer_identity.id,
            });
        }

        const policy_at_start = self.policy_catalog.selectEffective(
            request.form_revision,
            request.civil_period.from,
        );
        const selected_at_start = switch (policy_at_start) {
            .effective => |revision| revision,
            .review_required => |issue| blk: {
                try addPolicySelectionIssue(
                    &review,
                    request.form_revision,
                    request.civil_period.from,
                    issue,
                );
                break :blk null;
            },
        };

        const policy_at_end = self.policy_catalog.selectEffective(
            request.form_revision,
            request.civil_period.until,
        );
        const selected_at_end = switch (policy_at_end) {
            .effective => |revision| revision,
            .review_required => |issue| blk: {
                try addPolicySelectionIssue(
                    &review,
                    request.form_revision,
                    request.civil_period.until,
                    issue,
                );
                break :blk null;
            },
        };

        if (selected_at_start == null or selected_at_end == null) {
            return reviewResult(allocator, &review);
        }

        const selected_policy = selected_at_start.?;
        if (!selected_policy.id.eql(&selected_at_end.?.id)) {
            try review.addFor(.policy_changed_during_period, .{
                .policy_revision = selected_policy.id,
            });
        }

        const exact_2550q = policy.FormRevisionKey.initComptime("2550Q", "2024-04-ENCS");
        if (!request.form_revision.eql(&exact_2550q)) {
            try review.addFor(.unsupported_form_revision, .{
                .form_revision = request.form_revision,
            });
        }

        switch (selected_policy.policy) {
            .periodic_return => |scope| switch (scope) {
                .head_office_consolidated => {},
                .registration_driven => try review.addFor(.unsupported_policy_category, .{
                    .policy_revision = selected_policy.id,
                }),
            },
            else => try review.addFor(.unsupported_policy_category, .{
                .policy_revision = selected_policy.id,
            }),
        }

        if (review.hasAny()) return reviewResult(allocator, &review);

        var coverage_buffer = try allocator.alloc(
            RegistrationUnitCoverage,
            snapshot.unit_revisions.len,
        );
        defer allocator.free(coverage_buffer);

        var coverage_count: usize = 0;
        var head_office: ?*const registration.RegistrationUnitRevision = null;

        for (snapshot.unit_revisions, 0..) |unit, unit_index| {
            if (hasEarlierUnit(snapshot.unit_revisions, unit_index)) continue;

            var overlapping_revisions: usize = 0;
            var covering_revision: ?*const registration.RegistrationUnitRevision = null;
            for (snapshot.unit_revisions) |*candidate| {
                if (!candidate.registration_unit_id.eql(&unit.registration_unit_id)) continue;
                if (!effectiveOverlaps(candidate.effective, request.civil_period)) continue;

                overlapping_revisions += 1;
                if (effectiveCovers(candidate.effective, request.civil_period)) {
                    covering_revision = candidate;
                }
            }

            // A unit must have exactly one unchanged revision across the whole
            // civil period. Adjacent or overlapping revisions are still a
            // mid-period state change, even if their displayed values match.
            if (overlapping_revisions == 0) continue;
            if (overlapping_revisions != 1 or covering_revision == null) {
                try review.addFor(.registration_unit_mid_period_state_change, .{
                    .registration_unit = unit.registration_unit_id,
                });
                continue;
            }

            const covered_unit = covering_revision.?;
            // A unit closed before the entire filing period has no current source
            // coverage. A closure within the period already took the
            // multi-revision Review Required path above.
            if (covered_unit.status == .confirmed_closed) continue;
            try inspectUnit(&review, request.taxpayer_id, covered_unit);

            if (covered_unit.kind == .head_office) {
                if (head_office != null) {
                    try review.addFor(.conflicting_head_office, .{
                        .registration_unit_revision = covered_unit.id,
                    });
                } else {
                    head_office = covered_unit;
                }
            }

            if (coverageFromUnit(covered_unit)) |coverage| {
                coverage_buffer[coverage_count] = coverage;
                coverage_count += 1;
            }
        }

        if (head_office == null) {
            try review.addFor(.missing_head_office, .{ .taxpayer = request.taxpayer_id });
        } else {
            const unit = head_office.?;
            switch (unit.branch_code_evidence) {
                .confirmed => |confirmed| {
                    if (!confirmed.evidence_id.isPresent()) {
                        try review.addFor(.head_office_not_confirmed, .{
                            .registration_unit_revision = unit.id,
                        });
                    }
                    if (!confirmed.code.isHeadOffice()) {
                        try review.addFor(.head_office_branch_code_invalid, .{
                            .registration_unit_revision = unit.id,
                        });
                    }
                },
                else => try review.addFor(.head_office_not_confirmed, .{
                    .registration_unit_revision = unit.id,
                }),
            }
            if (unit.status != .confirmed_active) {
                try review.addFor(.head_office_not_confirmed, .{
                    .registration_unit_revision = unit.id,
                });
            }
        }

        if (review.hasAny()) return reviewResult(allocator, &review);

        const filing_unit = head_office.?;
        const filing_branch = confirmedBranch(filing_unit) orelse {
            try review.addFor(.head_office_not_confirmed, .{
                .registration_unit_revision = filing_unit.id,
            });
            return reviewResult(allocator, &review);
        };

        // Applicability is a legal registration decision and must be resolved
        // before optional form-header/contact projection. A missing contact
        // cannot turn a confirmed closed VAT registration into Review Required
        // or erase an already resolved active filing scope.
        const vat_resolution = try resolve2550QHeadOfficeVat(
            &review,
            request,
            snapshot.tax_type_registrations,
            filing_unit.registration_unit_id,
        );
        if (review.hasAny()) {
            return reviewResult(allocator, &review);
        }
        const vat_binding = switch (vat_resolution) {
            .binding => |binding| binding,
            .not_applicable => |closed_binding| {
                const closed_bindings = [_]TaxTypeRegistrationBinding{closed_binding};
                if (snapshot.enforce_reviewed_evidence_bindings) {
                    try addRequiredEvidenceBindingReviews(
                        &review,
                        snapshot,
                        coverage_buffer[0..coverage_count],
                        &closed_bindings,
                        null,
                    );
                    if (review.hasAny()) return reviewResult(allocator, &review);
                }
                var scope = try buildResolvedLegalScope(
                    allocator,
                    request,
                    snapshot,
                    filing_unit,
                    filing_branch,
                    coverage_buffer[0..coverage_count],
                    closed_binding,
                    selected_policy,
                );
                errdefer scope.deinit(allocator);
                var decision: NotApplicableDecision = .{
                    .scope = scope,
                    .reason = .confirmed_closed_tax_type_registration,
                    .resolution_hash = undefined,
                };
                decision.resolution_hash = hashNotApplicableDecision(decision);
                return .{ .not_applicable = decision };
            },
            .review_required => unreachable,
        };

        const filing_unit_contact = (try resolveFilingUnitContact(
            &review,
            request,
            snapshot.registration_unit_contacts,
            filing_unit,
        )) orelse {
            const scope = try buildResolvedLegalScope(
                allocator,
                request,
                snapshot,
                filing_unit,
                filing_branch,
                coverage_buffer[0..coverage_count],
                vat_binding,
                selected_policy,
            );
            return reviewResultWithScope(allocator, &review, scope);
        };

        const required_tax_bindings = [_]TaxTypeRegistrationBinding{vat_binding};
        if (snapshot.enforce_reviewed_evidence_bindings) {
            try addRequiredEvidenceBindingReviews(
                &review,
                snapshot,
                coverage_buffer[0..coverage_count],
                &required_tax_bindings,
                filing_unit_contact,
            );
            if (review.hasAny()) return reviewResult(allocator, &review);
        }

        const tax_type_registration_bindings = try allocator.alloc(
            TaxTypeRegistrationBinding,
            1,
        );
        errdefer allocator.free(tax_type_registration_bindings);
        tax_type_registration_bindings[0] = vat_binding;
        sortTaxTypeRegistrationBindings(tax_type_registration_bindings);

        const reviewed_evidence_bindings = try copyRelevantEvidenceBindings(
            allocator,
            snapshot.reviewed_evidence_bindings,
            snapshot.taxpayer_identity.id,
            coverage_buffer[0..coverage_count],
            tax_type_registration_bindings,
            filing_unit_contact.id,
        );
        errdefer allocator.free(reviewed_evidence_bindings);

        // The reviewed consolidated-VAT slice neither consumes an LTS override
        // nor registered-facility evidence. Keep the owned bindings explicit.
        const facility_revision_ids = try allocator.alloc(RegisteredFacilityRevisionId, 0);
        errdefer allocator.free(facility_revision_ids);
        sortFacilityRevisionIds(facility_revision_ids);

        const coverage = try allocator.dupe(
            RegistrationUnitCoverage,
            coverage_buffer[0..coverage_count],
        );
        errdefer allocator.free(coverage);
        sortCoverage(coverage);

        var policy_evidence_ids = try allocator.alloc(
            policy.PolicyEvidenceId,
            selected_policy.evidence.len,
        );
        errdefer allocator.free(policy_evidence_ids);
        for (selected_policy.evidence, 0..) |evidence, index| {
            policy_evidence_ids[index] = evidence.id;
        }
        sortPolicyEvidenceIds(policy_evidence_ids);

        const obligation = FilingObligation{
            .taxpayer_identity = snapshot.taxpayer_identity,
            .form_revision = request.form_revision,
            .civil_period = request.civil_period,
            .filing_unit_id = filing_unit.registration_unit_id,
            .filing_unit_revision_id = filing_unit.id,
            .filing_branch_code = filing_branch.code,
            .filing_branch_evidence_id = filing_branch.evidence_id,
            .filing_unit_rdo_code = filing_unit.rdo_code,
            .filing_unit_contact = filing_unit_contact.*,
            .coverage = coverage,
            .tax_type_registration_bindings = tax_type_registration_bindings,
            .reviewed_evidence_bindings = reviewed_evidence_bindings,
            .lts_revision_id = null,
            .facility_revision_ids = facility_revision_ids,
            .source_attribution_requirement = .not_required,
            .policy_revision_id = selected_policy.id,
            .policy_evidence_ids = policy_evidence_ids,
            .special_context_digest = null,
            .policy_capability = selected_policy.capability,
            .filing_capability = .not_fileable,
            .filing_venue_resolution = .not_resolved_by_scope,
            .resolution_hash = undefined,
        };
        var resolved = obligation;
        resolved.resolution_hash = hashObligation(resolved);
        const obligations = try allocator.alloc(FilingObligation, 1);
        obligations[0] = resolved;
        return .{ .obligations = obligations };
    }
};

/// Direct snapshot resolution is deliberately quarantined under a testing
/// namespace. Production paths must use `FilingPlanner.plan` so the ledger
/// supplies one coherent snapshot for the complete filing period.
pub const testing = if (builtin.is_test) struct {
    pub fn planForSnapshot(
        filing_planner: FilingPlanner,
        allocator: std.mem.Allocator,
        request: PlanningRequest,
        snapshot: RegistrationSnapshot,
    ) std.mem.Allocator.Error!ResolvedFilingPlan {
        if (snapshot.reviewed_evidence_bindings.len != 0) {
            return filing_planner.planForSnapshot(allocator, request, snapshot);
        }

        // Quarantined pure fixtures have no SQLite review rows. Synthesize
        // typed authority only inside this testing namespace so downstream
        // provenance tests exercise the production payload shape.
        var values: std.ArrayList(ReviewedEvidenceBinding) = .empty;
        defer values.deinit(allocator);
        if (snapshot.taxpayer_identity.evidence_id) |evidence_id| {
            try appendTestBinding(
                allocator,
                &values,
                .{ .taxpayer_identity_revision = snapshot.taxpayer_identity.id },
                evidence_id,
            );
        }
        for (snapshot.unit_revisions) |unit| {
            if (unit.branch_code_evidence.confirmedCode()) |confirmed| {
                try appendTestBinding(
                    allocator,
                    &values,
                    .{ .registration_unit_branch_code_revision = unit.id },
                    confirmed.evidence_id,
                );
            }
            if (unit.lifecycle_evidence_id) |evidence_id| {
                try appendTestBinding(
                    allocator,
                    &values,
                    .{ .registration_unit_lifecycle_revision = unit.id },
                    evidence_id,
                );
            }
        }
        for (snapshot.registration_unit_contacts) |contact| {
            try appendTestBinding(
                allocator,
                &values,
                .{ .registration_unit_contact_revision = contact.id },
                contact.evidence_id,
            );
        }
        for (snapshot.tax_type_registrations) |registration_revision| {
            if (registration_revision.evidence_id) |evidence_id| {
                try appendTestBinding(
                    allocator,
                    &values,
                    .{ .tax_type_registration_revision = registration_revision.id },
                    evidence_id,
                );
            }
        }
        evidence_binding.sort(values.items);
        var bound_snapshot = snapshot;
        bound_snapshot.reviewed_evidence_bindings = values.items;
        return filing_planner.planForSnapshot(allocator, request, bound_snapshot);
    }

    fn appendTestBinding(
        allocator: std.mem.Allocator,
        values: *std.ArrayList(ReviewedEvidenceBinding),
        subject: EvidenceFactSubject,
        evidence_id: registration.RegistrationEvidenceId,
    ) std.mem.Allocator.Error!void {
        try values.append(allocator, .{
            .subject = subject,
            .evidence_id = evidence_id,
            .review_decision_id = registration.RegistrationEvidenceReviewDecisionId.parse(
                evidence_id.asSlice(),
            ) catch unreachable,
            .review_decision_sequence = 1,
            .assertion_id = registration.RegistrationEvidenceAssertionId.parse(
                evidence_id.asSlice(),
            ) catch unreachable,
        });
    }
} else struct {};

const ReviewCollector = struct {
    allocator: std.mem.Allocator,
    values: std.ArrayList(ReviewIssue) = .empty,

    fn init(allocator: std.mem.Allocator) ReviewCollector {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *ReviewCollector) void {
        self.values.deinit(self.allocator);
    }

    fn add(
        self: *ReviewCollector,
        reason: ReviewReason,
    ) std.mem.Allocator.Error!void {
        try self.addFor(reason, .planning_request);
    }

    fn addFor(
        self: *ReviewCollector,
        reason: ReviewReason,
        subject: ReviewSubject,
    ) std.mem.Allocator.Error!void {
        try self.addIssue(.{ .reason = reason, .subject = subject });
    }

    fn addIssue(
        self: *ReviewCollector,
        issue: ReviewIssue,
    ) std.mem.Allocator.Error!void {
        for (self.values.items) |existing| {
            if (reviewIssueEql(existing, issue)) return;
        }
        try self.values.append(self.allocator, issue);
    }

    fn hasAny(self: *const ReviewCollector) bool {
        return self.values.items.len != 0;
    }

    fn intoOwnedIssues(self: *ReviewCollector) std.mem.Allocator.Error![]const ReviewIssue {
        sortReviewIssues(self.values.items);
        return self.values.toOwnedSlice(self.allocator);
    }
};

fn reviewResult(
    allocator: std.mem.Allocator,
    review: *ReviewCollector,
) std.mem.Allocator.Error!ResolvedFilingPlan {
    return reviewResultWithOptionalScope(allocator, review, null);
}

fn reviewResultWithScope(
    allocator: std.mem.Allocator,
    review: *ReviewCollector,
    resolved_scope: ResolvedLegalFilingScope,
) std.mem.Allocator.Error!ResolvedFilingPlan {
    return reviewResultWithOptionalScope(allocator, review, resolved_scope);
}

fn reviewResultWithOptionalScope(
    allocator: std.mem.Allocator,
    review: *ReviewCollector,
    resolved_scope: ?ResolvedLegalFilingScope,
) std.mem.Allocator.Error!ResolvedFilingPlan {
    errdefer if (resolved_scope) |scope| scope.deinit(allocator);
    const issues = try review.intoOwnedIssues();
    return .{ .review_required = .{
        .issues = issues,
        .resolved_legal_scope = resolved_scope,
    } };
}

fn addPolicySelectionIssue(
    review: *ReviewCollector,
    form_revision: policy.FormRevisionKey,
    date: registration.Date,
    issue: policy.PolicySelectionIssue,
) std.mem.Allocator.Error!void {
    const reason: ReviewReason = switch (issue) {
        .invalid_form_revision_key, .invalid_effective_policy => .invalid_effective_policy,
        .missing_effective_policy => .missing_effective_policy,
        .overlapping_effective_policies => .conflicting_effective_policy,
        .policy_requires_review => .policy_requires_review,
    };
    try review.addIssue(.{
        .reason = reason,
        .subject = .{ .policy_endpoint = .{
            .form_revision = form_revision,
            .date = date,
        } },
        .detail = .{ .policy_selection = issue },
    });
}

fn addRequestContractIssues(
    review: *ReviewCollector,
    request: PlanningRequest,
) std.mem.Allocator.Error!void {
    request.civil_period.validate() catch {
        try review.addFor(.invalid_filing_period, .{ .filing_period = request.civil_period });
        return;
    };
    if (request.civil_period.kind != .calendar_quarter) {
        try review.addFor(.unsupported_filing_period_semantics, .{
            .filing_period = request.civil_period,
        });
    }
    if (request.special_context != null) {
        try review.addFor(.unsupported_special_context, .planning_request);
    }
}

fn evidenceIntegrityCause(value: anytype) EvidenceIntegrityCause {
    return switch (@typeInfo(@TypeOf(value))) {
        .@"struct" => mapEvidenceIntegrityCause(value.cause),
        .@"enum" => mapEvidenceIntegrityCause(value),
        else => @compileError("unsupported evidence integrity issue type"),
    };
}

fn evidenceIntegritySubject(value: anytype) ReviewSubject {
    return switch (@typeInfo(@TypeOf(value))) {
        .@"struct" => .{ .evidence = value.evidence_id },
        .@"enum" => .planning_request,
        else => @compileError("unsupported evidence integrity issue type"),
    };
}

fn reviewSubjectForEvidence(subject: EvidenceReviewSubject) ReviewSubject {
    return switch (subject) {
        .taxpayer_identity_revision => |id| .{ .taxpayer_revision = id },
        .registration_unit_branch_code_revision,
        .registration_unit_lifecycle_revision,
        => |id| .{ .registration_unit_revision = id },
        .registration_unit_contact_revision => |id| .{
            .registration_unit_contact_revision = id,
        },
        .tax_type_registration_revision => |id| .{
            .tax_type_registration_revision = id,
        },
        .branch_code_lineage => |lineage| .{
            .registration_unit = lineage.registration_unit_id,
        },
    };
}

fn mapEvidenceIntegrityCause(value: anytype) EvidenceIntegrityCause {
    return switch (value) {
        .protected_bytes_missing => .protected_bytes_missing,
        .protected_bytes_unreadable => .protected_bytes_unreadable,
        .protected_bytes_size_mismatch => .protected_bytes_size_mismatch,
        .protected_bytes_digest_mismatch => .protected_bytes_digest_mismatch,
        .stored_metadata_invalid => .stored_metadata_invalid,
        .storage_backend_unverifiable => .storage_backend_unverifiable,
    };
}

fn classifyStandardPeriod(
    from: registration.Date,
    until: registration.Date,
) FilingPeriodKind {
    if (isExactCalendarMonth(from, until)) return .calendar_month;
    if (isExactCalendarQuarter(from, until)) return .calendar_quarter;
    if (isExactTaxableYear(from, until)) return .taxable_year;
    return .date_range;
}

fn isExactCalendarMonth(from: registration.Date, until: registration.Date) bool {
    const last_day = lastDayOfMonth(from.year, from.month) orelse return false;
    return from.day == 1 and
        until.year == from.year and
        until.month == from.month and
        until.day == last_day;
}

fn isExactCalendarQuarter(from: registration.Date, until: registration.Date) bool {
    if (from.day != 1 or (from.month - 1) % 3 != 0) return false;
    const end_month = from.month + 2;
    const last_day = lastDayOfMonth(from.year, end_month) orelse return false;
    return until.year == from.year and
        until.month == end_month and
        until.day == last_day;
}

fn isExactTaxableYear(from: registration.Date, until: registration.Date) bool {
    return from.month == 1 and
        from.day == 1 and
        until.year == from.year and
        until.month == 12 and
        until.day == 31;
}

fn lastDayOfMonth(year: u16, month: u8) ?u8 {
    var day: u8 = 31;
    while (day >= 28) : (day -= 1) {
        _ = registration.Date.init(year, month, day) catch continue;
        return day;
    }
    return null;
}

fn isValidCivilDate(value: registration.Date) bool {
    _ = registration.Date.init(value.year, value.month, value.day) catch return false;
    return true;
}

fn effectiveCovers(
    effective: registration.EffectivePeriod,
    civil_period: CivilPeriod,
) bool {
    if (effective.from.isAfter(civil_period.from)) return false;
    if (effective.until) |until| {
        if (until.isBefore(civil_period.until)) return false;
    }
    return true;
}

fn effectiveOverlaps(
    effective: registration.EffectivePeriod,
    civil_period: CivilPeriod,
) bool {
    if (effective.from.isAfter(civil_period.until)) return false;
    if (effective.until) |until| {
        if (until.isBefore(civil_period.from)) return false;
    }
    return true;
}

fn hasEarlierUnit(
    units: []const registration.RegistrationUnitRevision,
    index: usize,
) bool {
    for (units[0..index]) |earlier| {
        if (earlier.registration_unit_id.eql(&units[index].registration_unit_id)) return true;
    }
    return false;
}

fn inspectUnit(
    review: *ReviewCollector,
    taxpayer_id: registration.TaxpayerId,
    unit: *const registration.RegistrationUnitRevision,
) std.mem.Allocator.Error!void {
    unit.validate() catch |err| {
        try addRegistrationUnitValidationIssue(review, unit, err);
        return;
    };
    if (!taxpayer_id.eql(&unit.taxpayer_id)) {
        try review.addFor(.registration_unit_taxpayer_mismatch, .{
            .registration_unit_revision = unit.id,
        });
    }

    switch (unit.status) {
        .confirmed_active => {},
        .pending_evidence => try review.addFor(.registration_unit_pending_evidence, .{
            .registration_unit_revision = unit.id,
        }),
        .legacy_unresolved => try review.addFor(.registration_unit_legacy_unresolved, .{
            .registration_unit_revision = unit.id,
        }),
        .confirmed_closed => try review.addFor(.registration_unit_closed, .{
            .registration_unit_revision = unit.id,
        }),
    }
}

fn addRegistrationUnitValidationIssue(
    review: *ReviewCollector,
    unit: *const registration.RegistrationUnitRevision,
    err: registration.RegistrationError,
) std.mem.Allocator.Error!void {
    const reason: ReviewReason = switch (err) {
        error.EvidenceRequired,
        error.PendingEvidenceRequiresUnconfirmedCode,
        error.ConfirmedUnitRequiresConfirmedCode,
        => .registration_unit_pending_evidence,
        error.LegacyUnitRequiresLegacySuffix,
        error.UnresolvedBranchCodeRequiresReview,
        => .registration_unit_legacy_unresolved,
        error.HeadOfficeCodeMustBe00000,
        error.BranchCode00000ReservedForHeadOffice,
        => if (unit.kind == .head_office)
            .head_office_branch_code_invalid
        else
            .invalid_registration_unit,
        else => .invalid_registration_unit,
    };
    try review.addIssue(.{
        .reason = reason,
        .subject = .{ .registration_unit_revision = unit.id },
        .detail = .{ .registration_validation = err },
    });
}

fn confirmedBranch(
    unit: *const registration.RegistrationUnitRevision,
) ?registration.ConfirmedBranchCode {
    return switch (unit.branch_code_evidence) {
        .confirmed => |value| value,
        else => null,
    };
}

fn coverageFromUnit(
    unit: *const registration.RegistrationUnitRevision,
) ?RegistrationUnitCoverage {
    const branch = confirmedBranch(unit) orelse return null;
    return .{
        .registration_unit_id = unit.registration_unit_id,
        .registration_unit_revision_id = unit.id,
        .branch_code = branch.code,
        .branch_code_evidence_id = branch.evidence_id,
    };
}

fn resolveFilingUnitContact(
    review: *ReviewCollector,
    request: PlanningRequest,
    revisions: []const registration.RegistrationUnitContactRevision,
    filing_unit: *const registration.RegistrationUnitRevision,
) std.mem.Allocator.Error!?*const registration.RegistrationUnitContactRevision {
    var overlapping_count: usize = 0;
    var covering: ?*const registration.RegistrationUnitContactRevision = null;

    for (revisions) |*revision| {
        if (!revision.registration_unit_id.eql(&filing_unit.registration_unit_id)) {
            continue;
        }
        if (!effectiveOverlaps(revision.effective, request.civil_period)) continue;

        overlapping_count += 1;
        revision.validate() catch |err| {
            try review.addIssue(.{
                .reason = .invalid_filing_unit_contact,
                .subject = .{ .registration_unit_contact_revision = revision.id },
                .detail = .{ .registration_validation = err },
            });
            continue;
        };
        if (!revision.taxpayer_id.eql(&request.taxpayer_id)) {
            try review.addFor(.filing_unit_contact_mismatch, .{
                .registration_unit_contact_revision = revision.id,
            });
            continue;
        }
        if (effectiveCovers(revision.effective, request.civil_period)) {
            covering = revision;
        }
    }

    if (review.hasAny()) return null;
    if (overlapping_count == 0) {
        try review.addFor(.missing_filing_unit_contact, .{
            .registration_unit = filing_unit.registration_unit_id,
        });
        return null;
    }
    if (overlapping_count != 1 or covering == null) {
        try review.addFor(.filing_unit_contact_mid_period_change, .{
            .registration_unit = filing_unit.registration_unit_id,
        });
        return null;
    }
    return covering;
}

const VatRegistrationResolution = union(enum) {
    binding: TaxTypeRegistrationBinding,
    not_applicable: TaxTypeRegistrationBinding,
    review_required,
};

fn resolve2550QHeadOfficeVat(
    review: *ReviewCollector,
    request: PlanningRequest,
    revisions: []const registration.TaxTypeRegistrationRevision,
    filing_unit_id: registration.RegistrationUnitId,
) std.mem.Allocator.Error!VatRegistrationResolution {
    var active: ?*const registration.TaxTypeRegistrationRevision = null;
    var closed: ?*const registration.TaxTypeRegistrationRevision = null;
    var relevant_rows: usize = 0;

    for (revisions) |*revision| {
        if (!revision.taxpayer_id.eql(&request.taxpayer_id)) continue;
        if (revision.tax_type != .vat) continue;
        if (!effectiveOverlaps(revision.effective, request.civil_period)) continue;

        relevant_rows += 1;
        revision.validate() catch |err| {
            try review.addIssue(.{
                .reason = .vat_registration_pending_evidence,
                .subject = .{ .tax_type_registration_revision = revision.id },
                .detail = .{ .registration_validation = err },
            });
            continue;
        };

        const evidence_id = revision.evidence_id;
        const has_evidence_id = if (evidence_id) |value| value.isPresent() else false;
        if (!has_evidence_id) try review.addFor(.vat_registration_pending_evidence, .{
            .tax_type_registration_revision = revision.id,
        });
        if (!revision.registration_unit_id.eql(&filing_unit_id)) {
            try review.addFor(.vat_registration_not_bound_to_head_office, .{
                .tax_type_registration_revision = revision.id,
            });
            continue;
        }

        const covers_period = effectiveCovers(
            revision.effective,
            request.civil_period,
        );
        if (!covers_period) {
            try review.addFor(.vat_registration_mid_period_state_change, .{
                .tax_type_registration_revision = revision.id,
            });
        }

        switch (revision.status) {
            .confirmed_active => {
                if (!has_evidence_id or !covers_period) {
                    continue;
                }
                if (active != null) {
                    try review.addFor(.conflicting_vat_registration_evidence, .{
                        .tax_type_registration_revision = revision.id,
                    });
                } else {
                    active = revision;
                }
            },
            .pending_evidence => try review.addFor(.vat_registration_pending_evidence, .{
                .tax_type_registration_revision = revision.id,
            }),
            .legacy_unresolved => try review.addFor(.vat_registration_legacy_unresolved, .{
                .tax_type_registration_revision = revision.id,
            }),
            .confirmed_closed => {
                if (!has_evidence_id or !covers_period) continue;
                if (closed != null) {
                    try review.addFor(.conflicting_vat_registration_evidence, .{
                        .tax_type_registration_revision = revision.id,
                    });
                } else {
                    closed = revision;
                }
            },
        }
    }

    if (relevant_rows == 0) {
        try review.addFor(.missing_vat_registration_evidence, .{
            .registration_unit = filing_unit_id,
        });
    }
    if (active != null and closed != null) {
        try review.addFor(.conflicting_vat_registration_evidence, .{
            .registration_unit = filing_unit_id,
        });
    }
    if (review.hasAny()) return .review_required;

    const selected = active orelse {
        if (closed) |closed_revision| {
            return .{ .not_applicable = taxTypeRegistrationBinding(closed_revision) };
        }
        try review.addFor(.missing_vat_registration_evidence, .{
            .registration_unit = filing_unit_id,
        });
        return .review_required;
    };
    return .{ .binding = taxTypeRegistrationBinding(selected) };
}

fn taxTypeRegistrationBinding(
    selected: *const registration.TaxTypeRegistrationRevision,
) TaxTypeRegistrationBinding {
    const evidence_id = selected.evidence_id orelse unreachable;
    return .{
        .registration_unit_id = selected.registration_unit_id,
        .registration_id = selected.registration_id,
        .revision_id = selected.id,
        .tax_type = selected.tax_type,
        .status = selected.status,
        .effective = selected.effective,
        .evidence_id = evidence_id,
    };
}

fn buildResolvedLegalScope(
    allocator: std.mem.Allocator,
    request: PlanningRequest,
    snapshot: RegistrationSnapshot,
    filing_unit: *const registration.RegistrationUnitRevision,
    filing_branch: registration.ConfirmedBranchCode,
    coverage_source: []const RegistrationUnitCoverage,
    tax_type_registration_binding: TaxTypeRegistrationBinding,
    selected_policy: *const policy.FilingPolicyRevision,
) std.mem.Allocator.Error!ResolvedLegalFilingScope {
    const coverage = try allocator.dupe(RegistrationUnitCoverage, coverage_source);
    errdefer allocator.free(coverage);
    sortCoverage(coverage);

    const tax_type_registration_bindings = try allocator.alloc(TaxTypeRegistrationBinding, 1);
    errdefer allocator.free(tax_type_registration_bindings);
    tax_type_registration_bindings[0] = tax_type_registration_binding;
    sortTaxTypeRegistrationBindings(tax_type_registration_bindings);

    const reviewed_evidence_bindings = try copyRelevantEvidenceBindings(
        allocator,
        snapshot.reviewed_evidence_bindings,
        snapshot.taxpayer_identity.id,
        coverage,
        tax_type_registration_bindings,
        null,
    );
    errdefer allocator.free(reviewed_evidence_bindings);

    var policy_evidence_ids = try allocator.alloc(
        policy.PolicyEvidenceId,
        selected_policy.evidence.len,
    );
    errdefer allocator.free(policy_evidence_ids);
    for (selected_policy.evidence, 0..) |evidence, index| {
        policy_evidence_ids[index] = evidence.id;
    }
    sortPolicyEvidenceIds(policy_evidence_ids);

    var scope: ResolvedLegalFilingScope = .{
        .taxpayer_identity = snapshot.taxpayer_identity,
        .form_revision = request.form_revision,
        .civil_period = request.civil_period,
        .filing_unit_id = filing_unit.registration_unit_id,
        .filing_unit_revision_id = filing_unit.id,
        .filing_branch_code = filing_branch.code,
        .filing_branch_evidence_id = filing_branch.evidence_id,
        .filing_unit_rdo_code = filing_unit.rdo_code,
        .coverage = coverage,
        .tax_type_registration_bindings = tax_type_registration_bindings,
        .reviewed_evidence_bindings = reviewed_evidence_bindings,
        .policy_revision_id = selected_policy.id,
        .policy_evidence_ids = policy_evidence_ids,
        .policy_capability = selected_policy.capability,
        .resolution_hash = undefined,
    };
    scope.resolution_hash = hashLegalScope(scope);
    return scope;
}

fn addRequiredEvidenceBindingReviews(
    review: *ReviewCollector,
    snapshot: RegistrationSnapshot,
    coverage: []const RegistrationUnitCoverage,
    tax_type_registration_bindings: []const TaxTypeRegistrationBinding,
    filing_unit_contact: ?*const registration.RegistrationUnitContactRevision,
) std.mem.Allocator.Error!void {
    try requireEvidenceBinding(
        review,
        snapshot.reviewed_evidence_bindings,
        .{ .taxpayer_identity_revision = snapshot.taxpayer_identity.id },
        .{ .taxpayer_revision = snapshot.taxpayer_identity.id },
        snapshot.taxpayer_identity.evidence_id,
    );

    for (coverage) |covered| {
        try requireEvidenceBinding(
            review,
            snapshot.reviewed_evidence_bindings,
            .{ .registration_unit_branch_code_revision = covered.registration_unit_revision_id },
            .{ .registration_unit_revision = covered.registration_unit_revision_id },
            covered.branch_code_evidence_id,
        );
        const unit = registrationUnitRevisionById(
            snapshot.unit_revisions,
            covered.registration_unit_revision_id,
        );
        try requireEvidenceBinding(
            review,
            snapshot.reviewed_evidence_bindings,
            .{ .registration_unit_lifecycle_revision = covered.registration_unit_revision_id },
            .{ .registration_unit_revision = covered.registration_unit_revision_id },
            if (unit) |value| value.lifecycle_evidence_id else null,
        );
    }

    if (filing_unit_contact) |contact| {
        try requireEvidenceBinding(
            review,
            snapshot.reviewed_evidence_bindings,
            .{ .registration_unit_contact_revision = contact.id },
            .{ .registration_unit_contact_revision = contact.id },
            contact.evidence_id,
        );
    }

    for (tax_type_registration_bindings) |binding| {
        try requireEvidenceBinding(
            review,
            snapshot.reviewed_evidence_bindings,
            .{ .tax_type_registration_revision = binding.revision_id },
            .{ .tax_type_registration_revision = binding.revision_id },
            binding.evidence_id,
        );
    }
}

fn requireEvidenceBinding(
    review: *ReviewCollector,
    bindings: []const ReviewedEvidenceBinding,
    fact_subject: EvidenceFactSubject,
    review_subject: ReviewSubject,
    expected_evidence_id: ?registration.RegistrationEvidenceId,
) std.mem.Allocator.Error!void {
    var subject_count: usize = 0;
    var exact = false;
    for (bindings) |binding| {
        if (std.meta.activeTag(binding.subject) != std.meta.activeTag(fact_subject) or
            !std.mem.eql(u8, binding.subject.idBytes(), fact_subject.idBytes()))
        {
            continue;
        }
        subject_count += 1;
        if (expected_evidence_id) |evidence_id| {
            exact = exact or
                (binding.isValid() and binding.evidence_id.eql(&evidence_id));
        }
    }
    if (subject_count == 1 and exact) return;
    try review.addIssue(.{
        .reason = .evidence_review_missing,
        .subject = review_subject,
        .evidence_id = expected_evidence_id,
    });
}

fn registrationUnitRevisionById(
    revisions: []const registration.RegistrationUnitRevision,
    id: registration.RegistrationUnitRevisionId,
) ?*const registration.RegistrationUnitRevision {
    for (revisions) |*revision| {
        if (revision.id.eql(&id)) return revision;
    }
    return null;
}

fn copyRelevantEvidenceBindings(
    allocator: std.mem.Allocator,
    source: []const ReviewedEvidenceBinding,
    taxpayer_revision_id: registration.TaxpayerRevisionId,
    coverage: []const RegistrationUnitCoverage,
    tax_type_registration_bindings: []const TaxTypeRegistrationBinding,
    contact_revision_id: ?registration.RegistrationUnitContactRevisionId,
) std.mem.Allocator.Error![]ReviewedEvidenceBinding {
    var count: usize = 0;
    for (source) |binding| {
        if (evidenceBindingIsRelevant(
            binding,
            taxpayer_revision_id,
            coverage,
            tax_type_registration_bindings,
            contact_revision_id,
        )) count += 1;
    }

    const result = try allocator.alloc(ReviewedEvidenceBinding, count);
    var index: usize = 0;
    for (source) |binding| {
        if (!evidenceBindingIsRelevant(
            binding,
            taxpayer_revision_id,
            coverage,
            tax_type_registration_bindings,
            contact_revision_id,
        )) continue;
        result[index] = binding;
        index += 1;
    }
    evidence_binding.sort(result);
    return result;
}

fn evidenceBindingIsRelevant(
    binding: ReviewedEvidenceBinding,
    taxpayer_revision_id: registration.TaxpayerRevisionId,
    coverage: []const RegistrationUnitCoverage,
    tax_type_registration_bindings: []const TaxTypeRegistrationBinding,
    contact_revision_id: ?registration.RegistrationUnitContactRevisionId,
) bool {
    return switch (binding.subject) {
        .taxpayer_identity_revision => |id| id.eql(&taxpayer_revision_id),
        .registration_unit_branch_code_revision,
        .registration_unit_lifecycle_revision,
        => |id| blk: {
            for (coverage) |covered| {
                if (id.eql(&covered.registration_unit_revision_id)) break :blk true;
            }
            break :blk false;
        },
        .registration_unit_contact_revision => |id| if (contact_revision_id) |contact_id|
            id.eql(&contact_id)
        else
            false,
        .tax_type_registration_revision => |id| blk: {
            for (tax_type_registration_bindings) |registration_binding| {
                if (id.eql(&registration_binding.revision_id)) break :blk true;
            }
            break :blk false;
        },
    };
}

fn hashLegalScope(scope: ResolvedLegalFilingScope) ResolutionHash {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hashDelimited(&hasher, "legal-filing-scope-v7");
    hashNumber(&hasher, scope.decision_schema_version);
    hashTaxpayerIdentity(&hasher, scope.taxpayer_identity);
    hashFormAndPeriod(&hasher, scope.form_revision, scope.civil_period);
    hashDelimited(&hasher, scope.filing_unit_id.asSlice());
    hashDelimited(&hasher, scope.filing_unit_revision_id.asSlice());
    hashDelimited(&hasher, scope.filing_branch_code.asDigits());
    hashDelimited(&hasher, scope.filing_branch_evidence_id.asSlice());
    hashOptionalRdo(&hasher, scope.filing_unit_rdo_code);
    hashCoverage(&hasher, scope.coverage);
    hashTaxTypeRegistrationBindings(&hasher, scope.tax_type_registration_bindings);
    hashReviewedEvidenceBindings(&hasher, scope.reviewed_evidence_bindings);
    hashDelimited(&hasher, scope.policy_revision_id.asSlice());
    hashPolicyEvidence(&hasher, scope.policy_evidence_ids);
    hashDelimited(&hasher, @tagName(scope.policy_capability));

    var result: ResolutionHash = undefined;
    hasher.final(&result);
    return result;
}

pub fn verifyLegalScopeHash(scope: *const ResolvedLegalFilingScope) bool {
    const expected = hashLegalScope(scope.*);
    return std.mem.eql(u8, &scope.resolution_hash, &expected);
}

fn hashNotApplicableDecision(decision: NotApplicableDecision) ResolutionHash {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hashDelimited(&hasher, "filing-not-applicable-v7");
    hashFixedBytes(&hasher, &decision.scope.resolution_hash);
    hashDelimited(&hasher, @tagName(decision.reason));
    var result: ResolutionHash = undefined;
    hasher.final(&result);
    return result;
}

pub fn verifyNotApplicableHash(decision: *const NotApplicableDecision) bool {
    if (!verifyLegalScopeHash(&decision.scope)) return false;
    const expected = hashNotApplicableDecision(decision.*);
    return std.mem.eql(u8, &decision.resolution_hash, &expected);
}

fn sortReviewIssues(values: []ReviewIssue) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var cursor = index;
        while (cursor > 0 and reviewIssueLessThan(value, values[cursor - 1])) {
            values[cursor] = values[cursor - 1];
            cursor -= 1;
        }
        values[cursor] = value;
    }
}

fn reviewIssueLessThan(left: ReviewIssue, right: ReviewIssue) bool {
    if (left.reason != right.reason) {
        return @intFromEnum(left.reason) < @intFromEnum(right.reason);
    }
    const left_subject_tag = @intFromEnum(std.meta.activeTag(left.subject));
    const right_subject_tag = @intFromEnum(std.meta.activeTag(right.subject));
    if (left_subject_tag != right_subject_tag) return left_subject_tag < right_subject_tag;
    if (reviewSubjectLessThan(left.subject, right.subject)) return true;
    if (reviewSubjectLessThan(right.subject, left.subject)) return false;
    if (optionalEvidenceIdLessThan(left.evidence_id, right.evidence_id)) return true;
    if (optionalEvidenceIdLessThan(right.evidence_id, left.evidence_id)) return false;
    return reviewIssueDetailLessThan(left.detail, right.detail);
}

fn reviewIssueEql(left: ReviewIssue, right: ReviewIssue) bool {
    if (left.reason != right.reason) return false;
    if (std.meta.activeTag(left.subject) != std.meta.activeTag(right.subject)) {
        return false;
    }
    if (reviewSubjectLessThan(left.subject, right.subject) or
        reviewSubjectLessThan(right.subject, left.subject))
    {
        return false;
    }
    if (optionalEvidenceIdLessThan(left.evidence_id, right.evidence_id) or
        optionalEvidenceIdLessThan(right.evidence_id, left.evidence_id))
    {
        return false;
    }
    return reviewIssueDetailEql(left.detail, right.detail);
}

fn optionalEvidenceIdLessThan(
    left: ?registration.RegistrationEvidenceId,
    right: ?registration.RegistrationEvidenceId,
) bool {
    if (left == null) return right != null;
    if (right == null) return false;
    return idLessThan(left.?, right.?);
}

fn reviewIssueDetailEql(left: ReviewIssueDetail, right: ReviewIssueDetail) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .none => true,
        .policy_catalog_validation => |left_value| switch (right) {
            .policy_catalog_validation => |right_value| left_value == right_value,
            else => unreachable,
        },
        .policy_selection => |left_value| switch (right) {
            .policy_selection => |right_value| policySelectionIssueEql(
                left_value,
                right_value,
            ),
            else => unreachable,
        },
        .registration_validation => |left_value| switch (right) {
            .registration_validation => |right_value| left_value == right_value,
            else => unreachable,
        },
        .evidence_integrity => |left_value| switch (right) {
            .evidence_integrity => |right_value| left_value == right_value,
            else => unreachable,
        },
    };
}

fn reviewIssueDetailLessThan(left: ReviewIssueDetail, right: ReviewIssueDetail) bool {
    const left_tag = @intFromEnum(std.meta.activeTag(left));
    const right_tag = @intFromEnum(std.meta.activeTag(right));
    if (left_tag != right_tag) return left_tag < right_tag;
    return switch (left) {
        .none => false,
        .policy_catalog_validation => |left_value| switch (right) {
            .policy_catalog_validation => |right_value| {
                return @intFromError(left_value) < @intFromError(right_value);
            },
            else => unreachable,
        },
        .policy_selection => |left_value| switch (right) {
            .policy_selection => |right_value| policySelectionIssueLessThan(
                left_value,
                right_value,
            ),
            else => unreachable,
        },
        .registration_validation => |left_value| switch (right) {
            .registration_validation => |right_value| {
                return @intFromError(left_value) < @intFromError(right_value);
            },
            else => unreachable,
        },
        .evidence_integrity => |left_value| switch (right) {
            .evidence_integrity => |right_value| {
                return @intFromEnum(left_value) < @intFromEnum(right_value);
            },
            else => unreachable,
        },
    };
}

fn policySelectionIssueEql(
    left: policy.PolicySelectionIssue,
    right: policy.PolicySelectionIssue,
) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .invalid_form_revision_key,
        .missing_effective_policy,
        .overlapping_effective_policies,
        => true,
        .invalid_effective_policy => |left_value| switch (right) {
            .invalid_effective_policy => |right_value| left_value == right_value,
            else => unreachable,
        },
        .policy_requires_review => |left_value| switch (right) {
            .policy_requires_review => |right_value| left_value == right_value,
            else => unreachable,
        },
    };
}

fn policySelectionIssueLessThan(
    left: policy.PolicySelectionIssue,
    right: policy.PolicySelectionIssue,
) bool {
    const left_tag = @intFromEnum(std.meta.activeTag(left));
    const right_tag = @intFromEnum(std.meta.activeTag(right));
    if (left_tag != right_tag) return left_tag < right_tag;
    return switch (left) {
        .invalid_form_revision_key,
        .missing_effective_policy,
        .overlapping_effective_policies,
        => false,
        .invalid_effective_policy => |left_value| switch (right) {
            .invalid_effective_policy => |right_value| {
                return @intFromError(left_value) < @intFromError(right_value);
            },
            else => unreachable,
        },
        .policy_requires_review => |left_value| switch (right) {
            .policy_requires_review => |right_value| {
                return @intFromEnum(left_value) < @intFromEnum(right_value);
            },
            else => unreachable,
        },
    };
}

fn reviewSubjectLessThan(left: ReviewSubject, right: ReviewSubject) bool {
    return switch (left) {
        .planning_request => false,
        .filing_period => |left_value| switch (right) {
            .filing_period => |right_value| filingPeriodLessThan(left_value, right_value),
            else => unreachable,
        },
        .taxpayer => |left_value| switch (right) {
            .taxpayer => |right_value| idLessThan(left_value, right_value),
            else => unreachable,
        },
        .taxpayer_revision => |left_value| switch (right) {
            .taxpayer_revision => |right_value| idLessThan(left_value, right_value),
            else => unreachable,
        },
        .form_revision => |left_value| switch (right) {
            .form_revision => |right_value| formRevisionLessThan(left_value, right_value),
            else => unreachable,
        },
        .policy_endpoint => |left_value| switch (right) {
            .policy_endpoint => |right_value| {
                if (formRevisionLessThan(left_value.form_revision, right_value.form_revision)) {
                    return true;
                }
                if (formRevisionLessThan(right_value.form_revision, left_value.form_revision)) {
                    return false;
                }
                return dateLessThan(left_value.date, right_value.date);
            },
            else => unreachable,
        },
        .policy_revision => |left_value| switch (right) {
            .policy_revision => |right_value| idLessThan(left_value, right_value),
            else => unreachable,
        },
        .registration_unit => |left_value| switch (right) {
            .registration_unit => |right_value| idLessThan(left_value, right_value),
            else => unreachable,
        },
        .registration_unit_revision => |left_value| switch (right) {
            .registration_unit_revision => |right_value| idLessThan(left_value, right_value),
            else => unreachable,
        },
        .registration_unit_contact_revision => |left_value| switch (right) {
            .registration_unit_contact_revision => |right_value| idLessThan(left_value, right_value),
            else => unreachable,
        },
        .tax_type_registration => |left_value| switch (right) {
            .tax_type_registration => |right_value| idLessThan(left_value, right_value),
            else => unreachable,
        },
        .tax_type_registration_revision => |left_value| switch (right) {
            .tax_type_registration_revision => |right_value| idLessThan(left_value, right_value),
            else => unreachable,
        },
        .evidence => |left_value| switch (right) {
            .evidence => |right_value| idLessThan(left_value, right_value),
            else => unreachable,
        },
    };
}

fn idLessThan(left: anytype, right: @TypeOf(left)) bool {
    return std.mem.order(u8, left.asSlice(), right.asSlice()) == .lt;
}

fn formRevisionLessThan(left: policy.FormRevisionKey, right: policy.FormRevisionKey) bool {
    const code_order = std.mem.order(u8, left.code.asSlice(), right.code.asSlice());
    if (code_order != .eq) return code_order == .lt;
    return std.mem.order(u8, left.revision.asSlice(), right.revision.asSlice()) == .lt;
}

fn filingPeriodLessThan(left: FilingPeriod, right: FilingPeriod) bool {
    if (left.kind != right.kind) return @intFromEnum(left.kind) < @intFromEnum(right.kind);
    if (dateLessThan(left.from, right.from)) return true;
    if (dateLessThan(right.from, left.from)) return false;
    return dateLessThan(left.until, right.until);
}

fn dateLessThan(left: registration.Date, right: registration.Date) bool {
    if (left.year != right.year) return left.year < right.year;
    if (left.month != right.month) return left.month < right.month;
    return left.day < right.day;
}

fn sortCoverage(values: []RegistrationUnitCoverage) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var cursor = index;
        while (cursor > 0 and coverageLessThan(value, values[cursor - 1])) {
            values[cursor] = values[cursor - 1];
            cursor -= 1;
        }
        values[cursor] = value;
    }
}

fn sortTaxTypeRegistrationBindings(values: []TaxTypeRegistrationBinding) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var cursor = index;
        while (cursor > 0 and taxTypeRegistrationBindingLessThan(value, values[cursor - 1])) {
            values[cursor] = values[cursor - 1];
            cursor -= 1;
        }
        values[cursor] = value;
    }
}

fn taxTypeRegistrationBindingLessThan(
    left: TaxTypeRegistrationBinding,
    right: TaxTypeRegistrationBinding,
) bool {
    const unit_order = std.mem.order(
        u8,
        left.registration_unit_id.asSlice(),
        right.registration_unit_id.asSlice(),
    );
    if (unit_order != .eq) return unit_order == .lt;
    const registration_order = std.mem.order(
        u8,
        left.registration_id.asSlice(),
        right.registration_id.asSlice(),
    );
    if (registration_order != .eq) return registration_order == .lt;
    const revision_order = std.mem.order(
        u8,
        left.revision_id.asSlice(),
        right.revision_id.asSlice(),
    );
    if (revision_order != .eq) return revision_order == .lt;
    if (left.tax_type != right.tax_type) {
        return @intFromEnum(left.tax_type) < @intFromEnum(right.tax_type);
    }
    return std.mem.order(u8, left.evidence_id.asSlice(), right.evidence_id.asSlice()) == .lt;
}

fn sortFacilityRevisionIds(values: []RegisteredFacilityRevisionId) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var cursor = index;
        while (cursor > 0 and
            std.mem.order(u8, value.asSlice(), values[cursor - 1].asSlice()) == .lt)
        {
            values[cursor] = values[cursor - 1];
            cursor -= 1;
        }
        values[cursor] = value;
    }
}

fn coverageLessThan(left: RegistrationUnitCoverage, right: RegistrationUnitCoverage) bool {
    const unit_order = std.mem.order(u8, left.registration_unit_id.asSlice(), right.registration_unit_id.asSlice());
    if (unit_order != .eq) return unit_order == .lt;
    return std.mem.order(
        u8,
        left.registration_unit_revision_id.asSlice(),
        right.registration_unit_revision_id.asSlice(),
    ) == .lt;
}

fn sortPolicyEvidenceIds(values: []policy.PolicyEvidenceId) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var cursor = index;
        while (cursor > 0 and std.mem.order(u8, value.asSlice(), values[cursor - 1].asSlice()) == .lt) {
            values[cursor] = values[cursor - 1];
            cursor -= 1;
        }
        values[cursor] = value;
    }
}

fn hashObligation(obligation: FilingObligation) ResolutionHash {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hashDelimited(&hasher, "filing-scope-v7");
    hashNumber(&hasher, obligation.decision_schema_version);
    hashDelimited(&hasher, obligation.taxpayer_identity.taxpayer_id.asSlice());
    hashDelimited(&hasher, obligation.taxpayer_identity.id.asSlice());
    hashNumber(&hasher, obligation.taxpayer_identity.sequence);
    hashEffectivePeriod(&hasher, obligation.taxpayer_identity.effective);
    hashDelimited(&hasher, obligation.taxpayer_identity.tin_root.asDigits());
    if (obligation.taxpayer_identity.evidence_id) |evidence_id| {
        hashDelimited(&hasher, "some");
        hashDelimited(&hasher, evidence_id.asSlice());
    } else {
        hashDelimited(&hasher, "none");
    }
    hashDelimited(&hasher, obligation.form_revision.code.asSlice());
    hashDelimited(&hasher, obligation.form_revision.revision.asSlice());
    hashDelimited(&hasher, @tagName(obligation.civil_period.kind));
    hashDate(&hasher, obligation.civil_period.from);
    hashDate(&hasher, obligation.civil_period.until);
    hashDelimited(&hasher, obligation.filing_unit_id.asSlice());
    hashDelimited(&hasher, obligation.filing_unit_revision_id.asSlice());
    hashDelimited(&hasher, obligation.filing_branch_code.asDigits());
    hashDelimited(&hasher, obligation.filing_branch_evidence_id.asSlice());
    if (obligation.filing_unit_rdo_code) |rdo| {
        hashDelimited(&hasher, "some");
        hashDelimited(&hasher, rdo.asDigits());
    } else {
        hashDelimited(&hasher, "none");
    }
    hashDelimited(&hasher, obligation.filing_unit_contact.taxpayer_id.asSlice());
    hashDelimited(&hasher, obligation.filing_unit_contact.registration_unit_id.asSlice());
    hashDelimited(&hasher, obligation.filing_unit_contact.id.asSlice());
    hashNumber(&hasher, obligation.filing_unit_contact.sequence);
    hashEffectivePeriod(&hasher, obligation.filing_unit_contact.effective);
    hashDelimited(
        &hasher,
        obligation.filing_unit_contact.contact.registered_address.asSlice(),
    );
    hashOptionalContactField(&hasher, obligation.filing_unit_contact.contact.zip_code);
    hashOptionalContactField(
        &hasher,
        obligation.filing_unit_contact.contact.contact_number,
    );
    hashOptionalContactField(
        &hasher,
        obligation.filing_unit_contact.contact.email_address,
    );
    hashDelimited(&hasher, obligation.filing_unit_contact.evidence_id.asSlice());
    hashNumber(&hasher, obligation.coverage.len);
    for (obligation.coverage) |coverage| {
        hashDelimited(&hasher, coverage.registration_unit_id.asSlice());
        hashDelimited(&hasher, coverage.registration_unit_revision_id.asSlice());
        hashDelimited(&hasher, coverage.branch_code.asDigits());
        hashDelimited(&hasher, coverage.branch_code_evidence_id.asSlice());
    }
    hashNumber(&hasher, obligation.tax_type_registration_bindings.len);
    for (obligation.tax_type_registration_bindings) |binding| {
        hashDelimited(&hasher, binding.registration_unit_id.asSlice());
        hashDelimited(&hasher, binding.registration_id.asSlice());
        hashDelimited(&hasher, binding.revision_id.asSlice());
        hashDelimited(&hasher, @tagName(binding.tax_type));
        hashDelimited(&hasher, @tagName(binding.status));
        hashEffectivePeriod(&hasher, binding.effective);
        hashDelimited(&hasher, binding.evidence_id.asSlice());
    }
    hashReviewedEvidenceBindings(&hasher, obligation.reviewed_evidence_bindings);
    if (obligation.lts_revision_id) |lts_revision_id| {
        hashDelimited(&hasher, "some");
        hashDelimited(&hasher, lts_revision_id.asSlice());
    } else {
        hashDelimited(&hasher, "none");
    }
    hashNumber(&hasher, obligation.facility_revision_ids.len);
    for (obligation.facility_revision_ids) |facility_revision_id| {
        hashDelimited(&hasher, facility_revision_id.asSlice());
    }
    hashDelimited(&hasher, @tagName(obligation.source_attribution_requirement));
    hashDelimited(&hasher, obligation.policy_revision_id.asSlice());
    hashNumber(&hasher, obligation.policy_evidence_ids.len);
    for (obligation.policy_evidence_ids) |evidence_id| {
        hashDelimited(&hasher, evidence_id.asSlice());
    }
    if (obligation.special_context_digest) |digest| {
        hashDelimited(&hasher, "some");
        hashFixedBytes(&hasher, &digest);
    } else {
        hashDelimited(&hasher, "none");
    }
    hashDelimited(&hasher, @tagName(obligation.policy_capability));
    hashDelimited(&hasher, @tagName(obligation.filing_capability));
    hashDelimited(&hasher, @tagName(obligation.filing_venue_resolution));

    var result: ResolutionHash = undefined;
    hasher.final(&result);
    return result;
}

fn hashTaxpayerIdentity(
    hasher: anytype,
    identity: registration.TaxpayerIdentityRevision,
) void {
    hashDelimited(hasher, identity.taxpayer_id.asSlice());
    hashDelimited(hasher, identity.id.asSlice());
    hashNumber(hasher, identity.sequence);
    hashEffectivePeriod(hasher, identity.effective);
    hashDelimited(hasher, identity.tin_root.asDigits());
    if (identity.evidence_id) |evidence_id| {
        hashDelimited(hasher, "some");
        hashDelimited(hasher, evidence_id.asSlice());
    } else {
        hashDelimited(hasher, "none");
    }
}

fn hashFormAndPeriod(
    hasher: anytype,
    form_revision: policy.FormRevisionKey,
    civil_period: CivilPeriod,
) void {
    hashDelimited(hasher, form_revision.code.asSlice());
    hashDelimited(hasher, form_revision.revision.asSlice());
    hashDelimited(hasher, @tagName(civil_period.kind));
    hashDate(hasher, civil_period.from);
    hashDate(hasher, civil_period.until);
}

fn hashOptionalRdo(hasher: anytype, value: ?registration.RdoCode3) void {
    if (value) |rdo| {
        hashDelimited(hasher, "some");
        hashDelimited(hasher, rdo.asDigits());
    } else {
        hashDelimited(hasher, "none");
    }
}

fn hashCoverage(hasher: anytype, coverage_values: []const RegistrationUnitCoverage) void {
    hashNumber(hasher, coverage_values.len);
    for (coverage_values) |coverage| {
        hashDelimited(hasher, coverage.registration_unit_id.asSlice());
        hashDelimited(hasher, coverage.registration_unit_revision_id.asSlice());
        hashDelimited(hasher, coverage.branch_code.asDigits());
        hashDelimited(hasher, coverage.branch_code_evidence_id.asSlice());
    }
}

fn hashTaxTypeRegistrationBindings(
    hasher: anytype,
    bindings: []const TaxTypeRegistrationBinding,
) void {
    hashNumber(hasher, bindings.len);
    for (bindings) |binding| {
        hashDelimited(hasher, binding.registration_unit_id.asSlice());
        hashDelimited(hasher, binding.registration_id.asSlice());
        hashDelimited(hasher, binding.revision_id.asSlice());
        hashDelimited(hasher, @tagName(binding.tax_type));
        hashDelimited(hasher, @tagName(binding.status));
        hashEffectivePeriod(hasher, binding.effective);
        hashDelimited(hasher, binding.evidence_id.asSlice());
    }
}

fn hashReviewedEvidenceBindings(
    hasher: anytype,
    bindings: []const ReviewedEvidenceBinding,
) void {
    hashNumber(hasher, bindings.len);
    for (bindings) |binding| {
        hashDelimited(hasher, @tagName(binding.subject));
        hashDelimited(hasher, binding.subject.idBytes());
        hashDelimited(hasher, binding.evidence_id.asSlice());
        hashDelimited(hasher, binding.review_decision_id.asSlice());
        hashNumber(hasher, binding.review_decision_sequence);
        hashDelimited(hasher, binding.assertion_id.asSlice());
    }
}

fn hashPolicyEvidence(hasher: anytype, values: []const policy.PolicyEvidenceId) void {
    hashNumber(hasher, values.len);
    for (values) |evidence_id| hashDelimited(hasher, evidence_id.asSlice());
}

/// Narrow integrity seam for immutable downstream provenance. It deliberately
/// verifies an existing planner result rather than exposing a constructor for
/// caller-supplied filing obligations.
pub fn verifyResolutionHash(obligation: *const FilingObligation) bool {
    const expected = hashObligation(obligation.*);
    return std.mem.eql(u8, &obligation.resolution_hash, &expected);
}

fn hashDelimited(hasher: anytype, bytes: []const u8) void {
    hasher.update(bytes);
    hasher.update(&[_]u8{0});
}

fn hashFixedBytes(hasher: anytype, bytes: []const u8) void {
    hashNumber(hasher, bytes.len);
    hasher.update(bytes);
}

fn hashNumber(hasher: anytype, value: anytype) void {
    var buffer: [32]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable;
    hashDelimited(hasher, formatted);
}

fn hashDate(hasher: anytype, value: registration.Date) void {
    var buffer: [10]u8 = undefined;
    const formatted = std.fmt.bufPrint(
        &buffer,
        "{d:0>4}-{d:0>2}-{d:0>2}",
        .{ value.year, value.month, value.day },
    ) catch unreachable;
    hashDelimited(hasher, formatted);
}

fn hashEffectivePeriod(
    hasher: anytype,
    value: registration.EffectivePeriod,
) void {
    hashDate(hasher, value.from);
    if (value.until) |until| {
        hashDelimited(hasher, "some");
        hashDate(hasher, until);
    } else {
        hashDelimited(hasher, "none");
    }
}

fn hashOptionalContactField(hasher: anytype, value: anytype) void {
    if (value) |item| {
        hashDelimited(hasher, "some");
        hashDelimited(hasher, item.asSlice());
    } else {
        hashDelimited(hasher, "none");
    }
}

fn testDate(year: u16, month: u8, day: u8) registration.Date {
    return registration.Date.init(year, month, day) catch unreachable;
}

fn testPeriod(
    from: registration.Date,
    until: ?registration.Date,
) registration.EffectivePeriod {
    return registration.EffectivePeriod.init(from, until) catch unreachable;
}

fn testId(comptime Id: type, raw: []const u8) Id {
    return Id.parse(raw) catch unreachable;
}

fn testRequest() PlanningRequest {
    return .{
        .taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a"),
        .form_revision = policy.FormRevisionKey.initComptime("2550Q", "2024-04-ENCS"),
        .civil_period = CivilPeriod.init(testDate(2024, 4, 1), testDate(2024, 6, 30)) catch unreachable,
    };
}

fn testIdentity() registration.TaxpayerIdentityRevision {
    return .{
        .taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a"),
        .id = testId(registration.TaxpayerRevisionId, "taxpayer-rev-a"),
        .sequence = 1,
        .effective = testPeriod(testDate(2024, 1, 1), null),
        .tin_root = registration.Tin9.parse("123456789") catch unreachable,
        .evidence_id = testId(
            registration.RegistrationEvidenceId,
            "taxpayer-tin-evidence-a",
        ),
    };
}

fn confirmedUnit(
    unit_id: registration.RegistrationUnitId,
    revision_id: registration.RegistrationUnitRevisionId,
    kind: registration.RegistrationUnitKind,
    code: []const u8,
    evidence_id: registration.RegistrationEvidenceId,
    effective: registration.EffectivePeriod,
) registration.RegistrationUnitRevision {
    return .{
        .taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a"),
        .registration_unit_id = unit_id,
        .id = revision_id,
        .sequence = 1,
        .effective = effective,
        .kind = kind,
        .branch_code_evidence = .{ .confirmed = .{
            .code = registration.BranchCode5.parse(code) catch unreachable,
            .evidence_id = evidence_id,
        } },
        .status = .confirmed_active,
        .lifecycle_evidence_id = evidence_id,
    };
}

fn validContact(
    registration_unit_id: registration.RegistrationUnitId,
) registration.RegistrationUnitContactRevision {
    return .{
        .taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a"),
        .registration_unit_id = registration_unit_id,
        .id = testId(
            registration.RegistrationUnitContactRevisionId,
            "unit-contact-revision-a",
        ),
        .sequence = 1,
        .effective = testPeriod(testDate(2024, 1, 1), null),
        .contact = .{
            .registered_address = registration.field.RegisteredAddress.parse(
                "100 Example Street",
            ) catch unreachable,
            .zip_code = registration.field.ZipCode.parse("1000") catch unreachable,
            .contact_number = registration.field.ContactNumber.parse(
                "+639171234567",
            ) catch unreachable,
            .email_address = registration.field.EmailAddress.parse(
                "filing-unit@example.test",
            ) catch unreachable,
        },
        .evidence_id = testId(
            registration.RegistrationEvidenceId,
            "unit-contact-evidence-a",
        ),
    };
}

fn validVatRegistration(
    registration_unit_id: registration.RegistrationUnitId,
) registration.TaxTypeRegistrationRevision {
    return vatRegistration(
        registration_unit_id,
        "vat-registration-a",
        "vat-registration-revision-a",
        "vat-evidence-a",
        1,
        testPeriod(testDate(2024, 1, 1), null),
    );
}

fn vatRegistration(
    registration_unit_id: registration.RegistrationUnitId,
    registration_id: []const u8,
    revision_id: []const u8,
    evidence_id: []const u8,
    sequence: u32,
    effective: registration.EffectivePeriod,
) registration.TaxTypeRegistrationRevision {
    return .{
        .taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a"),
        .registration_unit_id = registration_unit_id,
        .registration_id = testId(registration.TaxTypeRegistrationId, registration_id),
        .id = testId(registration.TaxTypeRegistrationRevisionId, revision_id),
        .sequence = sequence,
        .tax_type = .vat,
        .status = .confirmed_active,
        .effective = effective,
        .evidence_id = testId(registration.RegistrationEvidenceId, evidence_id),
    };
}

fn plannerFor2550Q(revisions: *const [1]policy.FilingPolicyRevision) FilingPlanner {
    return FilingPlanner.init(.{ .revisions = revisions });
}

fn expectReviewReason(
    result: *ResolvedFilingPlan,
    expected: ReviewReason,
) !void {
    switch (result.*) {
        .obligations, .not_applicable => return error.ExpectedReviewRequired,
        .review_required => |review| {
            for (review.issues) |issue| {
                if (issue.reason == expected) return;
            }
            return error.ExpectedReviewReason;
        },
    }
}

fn expectReviewReasonCount(
    result: *ResolvedFilingPlan,
    expected: ReviewReason,
    expected_count: usize,
) !void {
    switch (result.*) {
        .obligations, .not_applicable => return error.ExpectedReviewRequired,
        .review_required => |review| {
            var count: usize = 0;
            for (review.issues) |issue| {
                if (issue.reason == expected) count += 1;
            }
            try std.testing.expectEqual(expected_count, count);
        },
    }
}

const TestPlanningSnapshotReviewRequired = union(enum) {
    taxpayer_identity_missing,
    taxpayer_identity_changed_during_period,
    evidence: EvidenceReviewIssue,
};

const TestEvidenceIntegrityReviewRequired = enum {
    protected_bytes_missing,
    protected_bytes_unreadable,
    protected_bytes_size_mismatch,
    protected_bytes_digest_mismatch,
    stored_metadata_invalid,
    storage_backend_unverifiable,
};

const TestEvidenceIntegrityReviewIssue = struct {
    cause: TestEvidenceIntegrityReviewRequired,
    evidence_id: registration.RegistrationEvidenceId,
};

const TestResolvedPlanningSnapshot = struct {
    taxpayer_identity: registration.TaxpayerIdentityRevision,
    units: []const registration.RegistrationUnitRevision,
    contacts: []const registration.RegistrationUnitContactRevision,
    tax_type_registrations: []const registration.TaxTypeRegistrationRevision,
    reviewed_evidence_bindings: []const ReviewedEvidenceBinding,
};

const TestPlanningSnapshotResult = union(enum) {
    resolved: TestResolvedPlanningSnapshot,
    registration_review_required: TestPlanningSnapshotReviewRequired,
    evidence_integrity_review_required: TestEvidenceIntegrityReviewIssue,

    pub fn deinit(
        self: *TestPlanningSnapshotResult,
        allocator: std.mem.Allocator,
    ) void {
        _ = allocator;
        self.* = undefined;
    }
};

const ReviewOnlyPlanningLedger = struct {
    allocator: std.mem.Allocator,
    cause: TestPlanningSnapshotReviewRequired,

    pub fn planningSnapshotWithEvidenceIntegrity(
        self: *ReviewOnlyPlanningLedger,
        request: anytype,
        verifier: anytype,
    ) !TestPlanningSnapshotResult {
        _ = request;
        _ = verifier;
        return .{ .registration_review_required = self.cause };
    }
};

const IntegrityReviewOnlyPlanningLedger = struct {
    allocator: std.mem.Allocator,
    cause: TestEvidenceIntegrityReviewIssue,

    pub fn planningSnapshotWithEvidenceIntegrity(
        self: *IntegrityReviewOnlyPlanningLedger,
        request: anytype,
        verifier: anytype,
    ) !TestPlanningSnapshotResult {
        _ = request;
        _ = verifier;
        return .{ .evidence_integrity_review_required = self.cause };
    }
};

const ResolvedPlanningLedger = struct {
    allocator: std.mem.Allocator,
    snapshot: TestResolvedPlanningSnapshot,

    pub fn planningSnapshotWithEvidenceIntegrity(
        self: *ResolvedPlanningLedger,
        request: anytype,
        verifier: anytype,
    ) !TestPlanningSnapshotResult {
        _ = request;
        _ = verifier;
        return .{ .resolved = self.snapshot };
    }
};

fn emptyOwnedObligation(allocator: std.mem.Allocator) !FilingObligation {
    const coverage = try allocator.alloc(RegistrationUnitCoverage, 0);
    errdefer allocator.free(coverage);
    const bindings = try allocator.alloc(TaxTypeRegistrationBinding, 0);
    errdefer allocator.free(bindings);
    const reviewed_evidence_bindings = try allocator.alloc(ReviewedEvidenceBinding, 0);
    errdefer allocator.free(reviewed_evidence_bindings);
    const facility_revision_ids = try allocator.alloc(RegisteredFacilityRevisionId, 0);
    errdefer allocator.free(facility_revision_ids);
    const policy_evidence_ids = try allocator.alloc(policy.PolicyEvidenceId, 0);
    errdefer allocator.free(policy_evidence_ids);

    var obligation: FilingObligation = undefined;
    obligation.coverage = coverage;
    obligation.tax_type_registration_bindings = bindings;
    obligation.reviewed_evidence_bindings = reviewed_evidence_bindings;
    obligation.facility_revision_ids = facility_revision_ids;
    obligation.policy_evidence_ids = policy_evidence_ids;
    return obligation;
}

test "resolved plan deinit handles zero and multiple obligations" {
    const allocator = std.testing.allocator;

    var zero: ResolvedFilingPlan = .{
        .obligations = try allocator.alloc(FilingObligation, 0),
    };
    zero.deinit(allocator);

    const obligations = try allocator.alloc(FilingObligation, 2);
    var initialized: usize = 0;
    errdefer {
        for (obligations[0..initialized]) |obligation| obligation.deinit(allocator);
        allocator.free(obligations);
    }
    for (obligations) |*obligation| {
        obligation.* = try emptyOwnedObligation(allocator);
        initialized += 1;
    }

    var multiple: ResolvedFilingPlan = .{ .obligations = obligations };
    multiple.deinit(allocator);
}

test "planner preserves exact registration-ledger review causes" {
    const allocator = std.testing.allocator;
    const evidence_id = testId(
        registration.RegistrationEvidenceId,
        "review-evidence-a",
    );
    const unit_revision_id = testId(
        registration.RegistrationUnitRevisionId,
        "review-unit-rev-a",
    );
    const cases = [_]struct {
        cause: TestPlanningSnapshotReviewRequired,
        reason: ReviewReason,
    }{
        .{ .cause = .{ .evidence = .{
            .reason = .superseded,
            .evidence_id = evidence_id,
            .subject = .{ .registration_unit_lifecycle_revision = unit_revision_id },
        } }, .reason = .evidence_superseded },
        .{ .cause = .taxpayer_identity_missing, .reason = .taxpayer_identity_missing },
        .{ .cause = .{ .evidence = .{
            .reason = .rejected,
            .evidence_id = evidence_id,
            .subject = .{ .registration_unit_lifecycle_revision = unit_revision_id },
        } }, .reason = .evidence_rejected },
        .{
            .cause = .taxpayer_identity_changed_during_period,
            .reason = .taxpayer_identity_changed_during_period,
        },
        .{ .cause = .{ .evidence = .{
            .reason = .missing,
            .evidence_id = evidence_id,
            .subject = .{ .registration_unit_lifecycle_revision = unit_revision_id },
        } }, .reason = .evidence_review_missing },
    };

    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = plannerFor2550Q(&revisions);
    for (cases) |case| {
        var ledger = ReviewOnlyPlanningLedger{
            .allocator = allocator,
            .cause = case.cause,
        };
        var result = try filing_planner.plan(allocator, &ledger, .{}, testRequest());
        defer result.deinit(allocator);

        switch (result) {
            .review_required => |review| {
                try std.testing.expectEqual(@as(usize, 1), review.issues.len);
                try std.testing.expectEqual(case.reason, review.issues[0].reason);
                if (std.meta.activeTag(case.cause) == .evidence) {
                    try std.testing.expect(review.issues[0].evidence_id.?.eql(&evidence_id));
                    try std.testing.expectEqual(
                        std.meta.Tag(ReviewSubject).registration_unit_revision,
                        std.meta.activeTag(review.issues[0].subject),
                    );
                    try std.testing.expect(
                        review.issues[0].subject.registration_unit_revision.eql(
                            &unit_revision_id,
                        ),
                    );
                }
            },
            .obligations, .not_applicable => return error.ExpectedReviewRequired,
        }
    }
}

test "planner preserves distinct protected evidence integrity causes" {
    const allocator = std.testing.allocator;
    const cases = [_]struct {
        cause: TestEvidenceIntegrityReviewRequired,
        reason: ReviewReason,
    }{
        .{ .cause = .protected_bytes_missing, .reason = .evidence_protected_bytes_missing },
        .{ .cause = .protected_bytes_unreadable, .reason = .evidence_protected_bytes_unreadable },
        .{ .cause = .protected_bytes_size_mismatch, .reason = .evidence_protected_bytes_size_mismatch },
        .{ .cause = .protected_bytes_digest_mismatch, .reason = .evidence_protected_bytes_digest_mismatch },
        .{ .cause = .stored_metadata_invalid, .reason = .evidence_stored_metadata_invalid },
        .{ .cause = .storage_backend_unverifiable, .reason = .evidence_storage_backend_unverifiable },
    };
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = plannerFor2550Q(&revisions);

    for (cases) |case| {
        var ledger = IntegrityReviewOnlyPlanningLedger{
            .allocator = allocator,
            .cause = .{
                .cause = case.cause,
                .evidence_id = testId(
                    registration.RegistrationEvidenceId,
                    "integrity-evidence-a",
                ),
            },
        };
        var result = try filing_planner.plan(allocator, &ledger, .{}, testRequest());
        defer result.deinit(allocator);

        switch (result) {
            .review_required => |review| {
                try std.testing.expectEqual(@as(usize, 1), review.issues.len);
                try std.testing.expectEqual(case.reason, review.issues[0].reason);
                switch (review.issues[0].subject) {
                    .evidence => |evidence_id| try std.testing.expectEqualStrings(
                        "integrity-evidence-a",
                        evidence_id.asSlice(),
                    ),
                    else => return error.ExpectedEvidenceSubject,
                }
                switch (review.issues[0].detail) {
                    .evidence_integrity => |detail| try std.testing.expectEqual(
                        evidenceIntegrityCause(ledger.cause),
                        detail,
                    ),
                    else => return error.ExpectedIntegrityDetail,
                }
            },
            .obligations, .not_applicable => return error.ExpectedReviewRequired,
        }
    }
}

test "public planner rejects empty and mismatched reviewed evidence bindings with exact fact" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = plannerFor2550Q(&revisions);
    const identity = testIdentity();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const units = [_]registration.RegistrationUnitRevision{confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    )};
    const contacts = [_]registration.RegistrationUnitContactRevision{validContact(head_id)};
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};
    const mismatched = [_]ReviewedEvidenceBinding{.{
        .subject = .{ .taxpayer_identity_revision = identity.id },
        .evidence_id = testId(
            registration.RegistrationEvidenceId,
            "different-taxpayer-evidence",
        ),
        .review_decision_id = testId(
            registration.RegistrationEvidenceReviewDecisionId,
            "review-decision-a",
        ),
        .review_decision_sequence = 1,
        .assertion_id = testId(
            registration.RegistrationEvidenceAssertionId,
            "assertion-a",
        ),
    }};
    const cases = [_][]const ReviewedEvidenceBinding{ &.{}, &mismatched };

    for (cases) |bindings| {
        var ledger = ResolvedPlanningLedger{
            .allocator = allocator,
            .snapshot = .{
                .taxpayer_identity = identity,
                .units = &units,
                .contacts = &contacts,
                .tax_type_registrations = &vat,
                .reviewed_evidence_bindings = bindings,
            },
        };
        var result = try filing_planner.plan(allocator, &ledger, .{}, testRequest());
        defer result.deinit(allocator);

        switch (result) {
            .review_required => |review| {
                var exact_issue_found = false;
                for (review.issues) |issue| {
                    if (issue.reason != .evidence_review_missing) continue;
                    if (std.meta.activeTag(issue.subject) != .taxpayer_revision) continue;
                    try std.testing.expect(issue.subject.taxpayer_revision.eql(&identity.id));
                    try std.testing.expect(issue.evidence_id.?.eql(&identity.evidence_id.?));
                    exact_issue_found = true;
                }
                try std.testing.expect(exact_issue_found);
            },
            .obligations, .not_applicable => return error.ExpectedReviewRequired,
        }
    }
}

test "planner resolves confirmed 2550Q head-office coverage as not fileable" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const branch_id = testId(registration.RegistrationUnitId, "unit-branch");
    const units = [_]registration.RegistrationUnitRevision{
        confirmedUnit(
            head_id,
            testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
            .head_office,
            "00000",
            testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
            testPeriod(testDate(2024, 1, 1), null),
        ),
        confirmedUnit(
            branch_id,
            testId(registration.RegistrationUnitRevisionId, "unit-branch-rev-a"),
            .branch,
            "00001",
            testId(registration.RegistrationEvidenceId, "branch-evidence-branch"),
            testPeriod(testDate(2024, 1, 1), null),
        ),
    };
    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};

    var result = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer result.deinit(allocator);

    switch (result) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            try std.testing.expectEqual(@as(usize, 1), obligations.len);
            const obligation = obligations[0];
            try std.testing.expectEqual(@as(usize, 2), obligation.coverage.len);
            try std.testing.expectEqual(FilingPeriodKind.calendar_quarter, obligation.civil_period.kind);
            try std.testing.expect(obligation.filing_unit_id.eql(&head_id));
            try std.testing.expectEqual(FilingCapability.not_fileable, obligation.filing_capability);
            try std.testing.expectEqual(policy.CapabilityState.editor_supported, obligation.policy_capability);
            try std.testing.expectEqual(@as(?LargeTaxpayerServiceRevisionId, null), obligation.lts_revision_id);
            try std.testing.expectEqual(@as(usize, 0), obligation.facility_revision_ids.len);
            try std.testing.expectEqual(
                SourceAttributionRequirement.not_required,
                obligation.source_attribution_requirement,
            );
            try std.testing.expectEqual(@as(?[32]u8, null), obligation.special_context_digest);
            try std.testing.expectEqual(
                FilingVenueResolution.not_resolved_by_scope,
                obligation.filing_venue_resolution,
            );
            try std.testing.expect(verifyResolutionHash(&obligation));
            try std.testing.expect(obligation.coverage[0].registration_unit_id.eql(&branch_id));
            try std.testing.expect(obligation.coverage[1].registration_unit_id.eql(&head_id));
        },
    }
}

test "planner fails closed when taxpayer TIN root has no evidence" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    var taxpayer_identity = testIdentity();
    taxpayer_identity.evidence_id = null;

    var result = try planner.planForSnapshot(allocator, testRequest(), .{
        .taxpayer_identity = taxpayer_identity,
        .unit_revisions = &.{},
        .registration_unit_contacts = &.{},
        .tax_type_registrations = &.{},
    });
    defer result.deinit(allocator);
    try expectReviewReason(&result, .invalid_taxpayer_identity);
}

test "filing periods retain explicit calendar fiscal range and event semantics" {
    const quarter_bounds = [_][2]registration.Date{
        .{ testDate(2024, 1, 1), testDate(2024, 3, 31) },
        .{ testDate(2024, 4, 1), testDate(2024, 6, 30) },
        .{ testDate(2024, 7, 1), testDate(2024, 9, 30) },
        .{ testDate(2024, 10, 1), testDate(2024, 12, 31) },
    };
    for (quarter_bounds) |bounds| {
        const filing_period = try FilingPeriod.init(bounds[0], bounds[1]);
        try std.testing.expectEqual(FilingPeriodKind.calendar_quarter, filing_period.kind);
        try filing_period.validate();
    }

    const month = try FilingPeriod.init(testDate(2024, 2, 1), testDate(2024, 2, 29));
    try std.testing.expectEqual(FilingPeriodKind.calendar_month, month.kind);
    const taxable_year = try FilingPeriod.init(testDate(2024, 1, 1), testDate(2024, 12, 31));
    try std.testing.expectEqual(FilingPeriodKind.taxable_year, taxable_year.kind);
    const fiscal = try FilingPeriod.initTyped(
        .fiscal_period,
        testDate(2024, 7, 1),
        testDate(2025, 6, 30),
    );
    try std.testing.expectEqual(FilingPeriodKind.fiscal_period, fiscal.kind);
    const range = try FilingPeriod.initTyped(
        .date_range,
        testDate(2024, 4, 1),
        testDate(2024, 6, 30),
    );
    try std.testing.expectEqual(FilingPeriodKind.date_range, range.kind);
    const event = try FilingPeriod.initTyped(
        .event_or_transaction,
        testDate(2024, 5, 15),
        testDate(2024, 5, 15),
    );
    try std.testing.expectEqual(FilingPeriodKind.event_or_transaction, event.kind);

    const malformed_quarter: FilingPeriod = .{
        .kind = .calendar_quarter,
        .from = testDate(2024, 4, 2),
        .until = testDate(2024, 6, 30),
    };
    try std.testing.expectError(error.InvalidCalendarQuarter, malformed_quarter.validate());
}

test "2550Q resolves every exact quarter and rejects malformed or wrong period semantics" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const units = [_]registration.RegistrationUnitRevision{confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    )};
    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};
    const quarter_bounds = [_][2]registration.Date{
        .{ testDate(2025, 1, 1), testDate(2025, 3, 31) },
        .{ testDate(2025, 4, 1), testDate(2025, 6, 30) },
        .{ testDate(2025, 7, 1), testDate(2025, 9, 30) },
        .{ testDate(2025, 10, 1), testDate(2025, 12, 31) },
    };
    for (quarter_bounds) |bounds| {
        var request = testRequest();
        request.civil_period = try FilingPeriod.init(bounds[0], bounds[1]);
        var result = try planner.planForSnapshot(allocator, request, .{
            .taxpayer_identity = testIdentity(),
            .unit_revisions = &units,
            .registration_unit_contacts = &contacts,
            .tax_type_registrations = &vat,
        });
        defer result.deinit(allocator);
        switch (result) {
            .obligations => |obligations| {
                try std.testing.expectEqual(@as(usize, 1), obligations.len);
                try std.testing.expectEqual(
                    FilingPeriodKind.calendar_quarter,
                    obligations[0].civil_period.kind,
                );
            },
            .not_applicable, .review_required => try std.testing.expect(false),
        }
    }

    const unsupported_periods = [_]FilingPeriod{
        try FilingPeriod.init(testDate(2025, 4, 1), testDate(2025, 4, 30)),
        try FilingPeriod.init(testDate(2025, 1, 1), testDate(2025, 12, 31)),
        try FilingPeriod.initTyped(
            .fiscal_period,
            testDate(2024, 7, 1),
            testDate(2025, 6, 30),
        ),
        try FilingPeriod.initTyped(
            .date_range,
            testDate(2025, 4, 1),
            testDate(2025, 6, 30),
        ),
        try FilingPeriod.initTyped(
            .event_or_transaction,
            testDate(2025, 5, 15),
            testDate(2025, 5, 15),
        ),
        try FilingPeriod.init(testDate(2025, 4, 2), testDate(2025, 6, 30)),
    };
    for (unsupported_periods) |filing_period| {
        var request = testRequest();
        request.civil_period = filing_period;
        var result = try planner.planForSnapshot(allocator, request, .{
            .taxpayer_identity = testIdentity(),
            .unit_revisions = &units,
            .tax_type_registrations = &vat,
        });
        defer result.deinit(allocator);
        try expectReviewReason(&result, .unsupported_filing_period_semantics);
    }

    var malformed_request = testRequest();
    malformed_request.civil_period = .{
        .kind = .calendar_quarter,
        .from = testDate(2025, 4, 2),
        .until = testDate(2025, 6, 30),
    };
    var malformed = try planner.planForSnapshot(allocator, malformed_request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .tax_type_registrations = &vat,
    });
    defer malformed.deinit(allocator);
    try expectReviewReason(&malformed, .invalid_filing_period);

    var ordered_request = testRequest();
    ordered_request.civil_period = try FilingPeriod.initTyped(
        .date_range,
        testDate(2025, 4, 1),
        testDate(2025, 6, 30),
    );
    ordered_request.special_context = .{ .digest = [_]u8{0xA5} ** 32 };
    var ordered = try planner.planForSnapshot(allocator, ordered_request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .tax_type_registrations = &vat,
    });
    defer ordered.deinit(allocator);
    switch (ordered) {
        .review_required => |review| {
            try std.testing.expectEqual(@as(usize, 2), review.issues.len);
            try std.testing.expectEqual(
                ReviewReason.unsupported_filing_period_semantics,
                review.issues[0].reason,
            );
            try std.testing.expectEqual(
                ReviewReason.unsupported_special_context,
                review.issues[1].reason,
            );
        },
        .obligations, .not_applicable => try std.testing.expect(false),
    }
}

test "review collector owns and orders more than the former fixed capacity" {
    const allocator = std.testing.allocator;
    var review = ReviewCollector.init(allocator);
    defer review.deinit();

    const issue_count = 257;
    for (0..issue_count) |index| {
        var subject_buffer: [64]u8 = undefined;
        const subject_id = std.fmt.bufPrint(
            &subject_buffer,
            "review-subject-{d}",
            .{index},
        ) catch unreachable;
        try review.addFor(
            if (index % 2 == 0)
                .invalid_filing_period
            else
                .unsupported_special_context,
            .{ .registration_unit_revision = testId(
                registration.RegistrationUnitRevisionId,
                subject_id,
            ) },
        );
    }

    var result = try reviewResult(allocator, &review);
    defer result.deinit(allocator);
    switch (result) {
        .review_required => |value| {
            try std.testing.expectEqual(@as(usize, issue_count), value.issues.len);
            try std.testing.expectEqual(
                ReviewReason.invalid_filing_period,
                value.issues[0].reason,
            );
            try std.testing.expectEqual(
                ReviewReason.unsupported_special_context,
                value.issues[value.issues.len - 1].reason,
            );
        },
        .obligations, .not_applicable => return error.ExpectedReviewRequired,
    }
}

test "review issue dedup and ordering ignore opaque id padding but retain detail payloads" {
    const allocator = std.testing.allocator;
    var review = ReviewCollector.init(allocator);
    defer review.deinit();

    var evidence_a = try registration.RegistrationEvidenceId.parse("evidence-a");
    var evidence_a_with_other_padding = evidence_a;
    @memset(evidence_a.bytes[evidence_a.len..], 0x11);
    @memset(
        evidence_a_with_other_padding.bytes[evidence_a_with_other_padding.len..],
        0xEE,
    );
    try std.testing.expect(evidence_a.eql(&evidence_a_with_other_padding));
    try std.testing.expect(!std.meta.eql(evidence_a, evidence_a_with_other_padding));

    var subject_a = try registration.RegistrationUnitRevisionId.parse("unit-revision-a");
    var subject_a_with_other_padding = subject_a;
    @memset(subject_a.bytes[subject_a.len..], 0x22);
    @memset(
        subject_a_with_other_padding.bytes[subject_a_with_other_padding.len..],
        0xDD,
    );
    try std.testing.expect(subject_a.eql(&subject_a_with_other_padding));
    try std.testing.expect(!std.meta.eql(subject_a, subject_a_with_other_padding));

    const semantic_issue_a = ReviewIssue{
        .reason = .evidence_review_missing,
        .subject = .{ .registration_unit_revision = subject_a },
        .evidence_id = evidence_a,
    };
    const semantic_issue_b = ReviewIssue{
        .reason = .evidence_review_missing,
        .subject = .{ .registration_unit_revision = subject_a_with_other_padding },
        .evidence_id = evidence_a_with_other_padding,
    };
    try review.addIssue(semantic_issue_a);
    try review.addIssue(semantic_issue_b);

    const detail_a = ReviewIssue{
        .reason = .invalid_policy_catalog,
        .subject = .planning_request,
        .detail = .{
            .policy_catalog_validation = error.EmptyPolicyRevisionId,
        },
    };
    const detail_b = ReviewIssue{
        .reason = .invalid_policy_catalog,
        .subject = .planning_request,
        .detail = .{ .policy_catalog_validation = error.EmptyFormCode },
    };
    try std.testing.expect(!reviewIssueEql(detail_a, detail_b));
    try std.testing.expect(
        reviewIssueLessThan(detail_a, detail_b) !=
            reviewIssueLessThan(detail_b, detail_a),
    );
    try review.addIssue(detail_b);
    try review.addIssue(detail_a);

    const evidence_b_issue = ReviewIssue{
        .reason = .evidence_review_missing,
        .subject = .{ .registration_unit_revision = subject_a },
        .evidence_id = try registration.RegistrationEvidenceId.parse("evidence-b"),
    };
    try std.testing.expect(reviewIssueLessThan(semantic_issue_a, evidence_b_issue));

    const issues = try review.intoOwnedIssues();
    defer allocator.free(issues);
    try std.testing.expectEqual(@as(usize, 3), issues.len);
}

test "review issue evidence and detail ordering is insertion independent" {
    const allocator = std.testing.allocator;
    const evidence_a = try registration.RegistrationEvidenceId.parse("evidence-a");
    const evidence_b = try registration.RegistrationEvidenceId.parse("evidence-b");
    const subject = ReviewSubject{
        .registration_unit_revision = try registration.RegistrationUnitRevisionId.parse(
            "unit-revision",
        ),
    };

    const input = [_]ReviewIssue{
        .{
            .reason = .evidence_review_missing,
            .subject = subject,
            .detail = .{ .evidence_integrity = .protected_bytes_digest_mismatch },
        },
        .{
            .reason = .evidence_review_missing,
            .subject = subject,
            .evidence_id = evidence_a,
        },
        .{
            .reason = .evidence_review_missing,
            .subject = subject,
            .evidence_id = evidence_a,
            .detail = .{ .evidence_integrity = .protected_bytes_missing },
        },
        .{
            .reason = .evidence_review_missing,
            .subject = subject,
            .evidence_id = evidence_a,
            .detail = .{ .evidence_integrity = .protected_bytes_digest_mismatch },
        },
        .{
            .reason = .evidence_review_missing,
            .subject = subject,
            .evidence_id = evidence_b,
        },
    };

    var forward = ReviewCollector.init(allocator);
    defer forward.deinit();
    for (input) |issue| try forward.addIssue(issue);

    var reverse = ReviewCollector.init(allocator);
    defer reverse.deinit();
    var index = input.len;
    while (index > 0) {
        index -= 1;
        try reverse.addIssue(input[index]);
    }

    const forward_issues = try forward.intoOwnedIssues();
    defer allocator.free(forward_issues);
    const reverse_issues = try reverse.intoOwnedIssues();
    defer allocator.free(reverse_issues);

    try std.testing.expectEqual(input.len, forward_issues.len);
    try std.testing.expectEqual(forward_issues.len, reverse_issues.len);
    for (forward_issues, reverse_issues) |forward_issue, reverse_issue| {
        try std.testing.expect(reviewIssueEql(forward_issue, reverse_issue));
    }
    for (forward_issues[1..], 1..) |issue, issue_index| {
        try std.testing.expect(reviewIssueLessThan(forward_issues[issue_index - 1], issue));
    }

    try std.testing.expect(forward_issues[0].evidence_id == null);
    try std.testing.expect(forward_issues[1].evidence_id.?.eql(&evidence_a));
    try std.testing.expect(forward_issues[2].evidence_id.?.eql(&evidence_a));
    try std.testing.expect(forward_issues[3].evidence_id.?.eql(&evidence_a));
    try std.testing.expect(forward_issues[4].evidence_id.?.eql(&evidence_b));
    switch (forward_issues[1].detail) {
        .none => {},
        else => return error.ExpectedNoReviewIssueDetail,
    }
    switch (forward_issues[2].detail) {
        .evidence_integrity => |cause| try std.testing.expectEqual(
            EvidenceIntegrityCause.protected_bytes_missing,
            cause,
        ),
        else => return error.ExpectedEvidenceIntegrityDetail,
    }
    switch (forward_issues[3].detail) {
        .evidence_integrity => |cause| try std.testing.expectEqual(
            EvidenceIntegrityCause.protected_bytes_digest_mismatch,
            cause,
        ),
        else => return error.ExpectedEvidenceIntegrityDetail,
    }
}

test "resolution hash binds period kind and every policy-context field" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const units = [_]registration.RegistrationUnitRevision{confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    )};
    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};
    var result = try planner.planForSnapshot(allocator, testRequest(), .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer result.deinit(allocator);

    switch (result) {
        .obligations => |obligations| {
            const original = obligations[0];
            try std.testing.expect(verifyResolutionHash(&original));

            var changed = original;
            changed.civil_period.kind = .date_range;
            try std.testing.expect(!std.mem.eql(
                u8,
                &original.resolution_hash,
                &hashObligation(changed),
            ));

            changed = original;
            changed.lts_revision_id = try LargeTaxpayerServiceRevisionId.parse("lts-revision-a");
            try std.testing.expect(!std.mem.eql(u8, &original.resolution_hash, &hashObligation(changed)));

            var facility_ids = [_]RegisteredFacilityRevisionId{
                try RegisteredFacilityRevisionId.parse("facility-revision-b"),
                try RegisteredFacilityRevisionId.parse("facility-revision-a"),
            };
            sortFacilityRevisionIds(&facility_ids);
            try std.testing.expectEqualStrings("facility-revision-a", facility_ids[0].asSlice());
            try std.testing.expectEqualStrings("facility-revision-b", facility_ids[1].asSlice());
            changed = original;
            changed.facility_revision_ids = &facility_ids;
            try std.testing.expect(!std.mem.eql(u8, &original.resolution_hash, &hashObligation(changed)));

            changed = original;
            changed.source_attribution_requirement = .required;
            try std.testing.expect(!std.mem.eql(u8, &original.resolution_hash, &hashObligation(changed)));

            changed = original;
            changed.special_context_digest = [_]u8{0x5A} ** 32;
            try std.testing.expect(!std.mem.eql(u8, &original.resolution_hash, &hashObligation(changed)));

            changed = original;
            changed.filing_venue_resolution = .review_required;
            try std.testing.expect(!std.mem.eql(u8, &original.resolution_hash, &hashObligation(changed)));
        },
        .not_applicable, .review_required => try std.testing.expect(false),
    }
}

test "planner fails closed for pending, legacy, and mid-period registration evidence" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const branch_id = testId(registration.RegistrationUnitId, "unit-branch");
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};
    const head = confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    );

    var pending_head = head;
    pending_head.status = .pending_evidence;
    pending_head.branch_code_evidence = .{ .unconfirmed = registration.BranchCode5.parse("00000") catch unreachable };
    pending_head.lifecycle_evidence_id = null;
    const pending_units = [_]registration.RegistrationUnitRevision{pending_head};
    var pending = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &pending_units,
        .tax_type_registrations = &vat,
    });
    defer pending.deinit(allocator);
    try expectReviewReasonCount(
        &pending,
        .registration_unit_pending_evidence,
        1,
    );
    try expectReviewReasonCount(
        &pending,
        .head_office_not_confirmed,
        1,
    );

    var missing_lifecycle = head;
    missing_lifecycle.lifecycle_evidence_id = null;
    const missing_lifecycle_units = [_]registration.RegistrationUnitRevision{missing_lifecycle};
    var missing_lifecycle_result = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &missing_lifecycle_units,
        .tax_type_registrations = &vat,
    });
    defer missing_lifecycle_result.deinit(allocator);
    try expectReviewReason(&missing_lifecycle_result, .registration_unit_pending_evidence);

    var legacy_branch = confirmedUnit(
        branch_id,
        testId(registration.RegistrationUnitRevisionId, "unit-branch-rev-a"),
        .branch,
        "00001",
        testId(registration.RegistrationEvidenceId, "branch-evidence-branch"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    legacy_branch.status = .legacy_unresolved;
    legacy_branch.branch_code_evidence = .{ .legacy_unresolved = registration.LegacyBranchSuffix.parse("001") catch unreachable };
    const legacy_units = [_]registration.RegistrationUnitRevision{ head, legacy_branch };
    var legacy = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &legacy_units,
        .tax_type_registrations = &vat,
    });
    defer legacy.deinit(allocator);
    try expectReviewReasonCount(
        &legacy,
        .registration_unit_legacy_unresolved,
        1,
    );

    const branch_first = confirmedUnit(
        branch_id,
        testId(registration.RegistrationUnitRevisionId, "unit-branch-rev-a"),
        .branch,
        "00001",
        testId(registration.RegistrationEvidenceId, "branch-evidence-branch-a"),
        testPeriod(testDate(2024, 1, 1), testDate(2024, 5, 31)),
    );
    const branch_second = confirmedUnit(
        branch_id,
        testId(registration.RegistrationUnitRevisionId, "unit-branch-rev-b"),
        .branch,
        "00001",
        testId(registration.RegistrationEvidenceId, "branch-evidence-branch-b"),
        testPeriod(testDate(2024, 6, 1), null),
    );
    const changed_units = [_]registration.RegistrationUnitRevision{ head, branch_first, branch_second };
    var changed = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &changed_units,
        .tax_type_registrations = &vat,
    });
    defer changed.deinit(allocator);
    try expectReviewReason(&changed, .registration_unit_mid_period_state_change);
}

test "planner fails closed when the exact policy is missing" {
    const allocator = std.testing.allocator;
    const no_revisions = [_]policy.FilingPolicyRevision{};
    const planner = FilingPlanner.init(.{ .revisions = &no_revisions });
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const units = [_]registration.RegistrationUnitRevision{confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    )};
    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};

    var result = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer result.deinit(allocator);
    try expectReviewReason(&result, .missing_effective_policy);
    switch (result) {
        .review_required => |review| {
            try std.testing.expectEqual(@as(usize, 2), review.issues.len);
            for (review.issues) |issue| {
                try std.testing.expectEqual(
                    ReviewReason.missing_effective_policy,
                    issue.reason,
                );
                switch (issue.subject) {
                    .policy_endpoint => {},
                    else => return error.ExpectedPolicyEndpointSubject,
                }
                switch (issue.detail) {
                    .policy_selection => |detail| switch (detail) {
                        .missing_effective_policy => {},
                        else => return error.ExpectedMissingPolicyPayload,
                    },
                    else => return error.ExpectedPolicySelectionPayload,
                }
            }
        },
        .obligations, .not_applicable => return error.ExpectedReviewRequired,
    }

    const first = policy.testing.fixture2550Q();
    var duplicate_id = policy.testing.fixture2551Q();
    duplicate_id.id = first.id;
    const invalid_revisions = [_]policy.FilingPolicyRevision{ first, duplicate_id };
    const invalid_catalog_planner = FilingPlanner.init(.{ .revisions = &invalid_revisions });
    var invalid_catalog = try invalid_catalog_planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer invalid_catalog.deinit(allocator);
    try expectReviewReason(&invalid_catalog, .invalid_policy_catalog);
}

test "planner resolution hash is deterministic across input coverage order" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const branch_id = testId(registration.RegistrationUnitId, "unit-branch");
    const head = confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    const branch = confirmedUnit(
        branch_id,
        testId(registration.RegistrationUnitRevisionId, "unit-branch-rev-a"),
        .branch,
        "00001",
        testId(registration.RegistrationEvidenceId, "branch-evidence-branch"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    const units_forward = [_]registration.RegistrationUnitRevision{ head, branch };
    const units_reverse = [_]registration.RegistrationUnitRevision{ branch, head };
    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};

    var forward = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units_forward,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer forward.deinit(allocator);
    var reverse = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units_reverse,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer reverse.deinit(allocator);

    var corrected_identity = testIdentity();
    corrected_identity.id = testId(registration.TaxpayerRevisionId, "taxpayer-rev-b");
    corrected_identity.sequence = 2;
    var corrected = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = corrected_identity,
        .unit_revisions = &units_forward,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer corrected.deinit(allocator);

    switch (forward) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |forward_obligations| switch (reverse) {
            .review_required => try std.testing.expect(false),
            .not_applicable => try std.testing.expect(false),
            .obligations => |reverse_obligations| {
                try std.testing.expectEqual(@as(usize, 1), forward_obligations.len);
                try std.testing.expectEqual(@as(usize, 1), reverse_obligations.len);
                const forward_obligation = forward_obligations[0];
                const reverse_obligation = reverse_obligations[0];
                try std.testing.expectEqualSlices(
                    u8,
                    &forward_obligation.resolution_hash,
                    &reverse_obligation.resolution_hash,
                );
                switch (corrected) {
                    .review_required => try std.testing.expect(false),
                    .not_applicable => try std.testing.expect(false),
                    .obligations => |corrected_obligations| {
                        try std.testing.expectEqual(@as(usize, 1), corrected_obligations.len);
                        try std.testing.expect(!std.mem.eql(
                            u8,
                            &forward_obligation.resolution_hash,
                            &corrected_obligations[0].resolution_hash,
                        ));
                    },
                }
            },
        },
    }
}

test "planner binds one head-office VAT registration while covering every confirmed branch" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const first_branch_id = testId(registration.RegistrationUnitId, "unit-branch-a");
    const second_branch_id = testId(registration.RegistrationUnitId, "unit-branch-b");
    const head = confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    const first_branch = confirmedUnit(
        first_branch_id,
        testId(registration.RegistrationUnitRevisionId, "unit-branch-a-rev-a"),
        .branch,
        "00001",
        testId(registration.RegistrationEvidenceId, "branch-evidence-a"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    const second_branch = confirmedUnit(
        second_branch_id,
        testId(registration.RegistrationUnitRevisionId, "unit-branch-b-rev-a"),
        .branch,
        "00002",
        testId(registration.RegistrationEvidenceId, "branch-evidence-b"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    const units = [_]registration.RegistrationUnitRevision{ head, first_branch, second_branch };
    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };
    const head_vat = vatRegistration(
        head_id,
        "vat-registration-head",
        "vat-registration-head-revision-a",
        "vat-evidence-head",
        1,
        testPeriod(testDate(2024, 1, 1), null),
    );
    const head_vat_rows = [_]registration.TaxTypeRegistrationRevision{head_vat};

    var result = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &head_vat_rows,
    });
    defer result.deinit(allocator);
    switch (result) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            try std.testing.expectEqual(@as(usize, 1), obligations.len);
            const obligation = obligations[0];
            try std.testing.expectEqual(@as(usize, 3), obligation.coverage.len);
            try std.testing.expectEqual(@as(usize, 1), obligation.tax_type_registration_bindings.len);
            const binding = obligation.tax_type_registration_bindings[0];
            try std.testing.expect(binding.registration_unit_id.eql(&head_id));
            try std.testing.expect(binding.registration_id.eql(&head_vat.registration_id));
            try std.testing.expect(binding.revision_id.eql(&head_vat.id));
            try std.testing.expect(binding.evidence_id.eql(&head_vat.evidence_id.?));
        },
    }

    const branch_vat = vatRegistration(
        first_branch_id,
        "vat-registration-branch",
        "vat-registration-branch-revision-a",
        "vat-evidence-branch",
        1,
        testPeriod(testDate(2024, 1, 1), null),
    );
    const branch_only_rows = [_]registration.TaxTypeRegistrationRevision{branch_vat};
    var branch_only = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &branch_only_rows,
    });
    defer branch_only.deinit(allocator);
    try expectReviewReason(&branch_only, .vat_registration_not_bound_to_head_office);

    const conflicting_rows = [_]registration.TaxTypeRegistrationRevision{ head_vat, branch_vat };
    var conflicting = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &conflicting_rows,
    });
    defer conflicting.deinit(allocator);
    try expectReviewReason(&conflicting, .vat_registration_not_bound_to_head_office);
}

test "planner fails closed for VAT registration lifecycle and mid-period changes" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const units = [_]registration.RegistrationUnitRevision{confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    )};
    const active = validVatRegistration(head_id);
    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };

    var pending_vat = active;
    pending_vat.status = .pending_evidence;
    pending_vat.evidence_id = null;
    const pending_rows = [_]registration.TaxTypeRegistrationRevision{pending_vat};
    var pending = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &pending_rows,
    });
    defer pending.deinit(allocator);
    try expectReviewReasonCount(
        &pending,
        .vat_registration_pending_evidence,
        1,
    );

    var closed_vat = active;
    closed_vat.status = .confirmed_closed;
    const closed_rows = [_]registration.TaxTypeRegistrationRevision{closed_vat};
    var closed = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &closed_rows,
    });
    defer closed.deinit(allocator);
    switch (closed) {
        .not_applicable => {},
        .obligations, .review_required => try std.testing.expect(false),
    }

    var legacy_vat = active;
    legacy_vat.status = .legacy_unresolved;
    legacy_vat.evidence_id = null;
    const legacy_rows = [_]registration.TaxTypeRegistrationRevision{legacy_vat};
    var legacy = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &legacy_rows,
    });
    defer legacy.deinit(allocator);
    try expectReviewReason(&legacy, .vat_registration_legacy_unresolved);

    const first = vatRegistration(
        head_id,
        "vat-registration-period",
        "vat-registration-period-revision-a",
        "vat-evidence-period-a",
        1,
        testPeriod(testDate(2024, 1, 1), testDate(2024, 5, 31)),
    );
    var second = vatRegistration(
        head_id,
        "vat-registration-period",
        "vat-registration-period-revision-b",
        "vat-evidence-period-b",
        2,
        testPeriod(testDate(2024, 6, 1), null),
    );
    second.status = .confirmed_closed;
    const mid_period_rows = [_]registration.TaxTypeRegistrationRevision{ first, second };
    var mid_period = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &mid_period_rows,
    });
    defer mid_period.deinit(allocator);
    try expectReviewReason(&mid_period, .vat_registration_mid_period_state_change);
}

test "planner hash changes when only the selected VAT revision or evidence changes" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const units = [_]registration.RegistrationUnitRevision{confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    )};
    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };
    const original = vatRegistration(
        head_id,
        "vat-registration-hash",
        "vat-registration-hash-revision-a",
        "vat-evidence-hash-a",
        1,
        testPeriod(testDate(2024, 1, 1), null),
    );
    const changed = vatRegistration(
        head_id,
        "vat-registration-hash",
        "vat-registration-hash-revision-b",
        "vat-evidence-hash-b",
        2,
        testPeriod(testDate(2024, 1, 1), null),
    );
    const original_rows = [_]registration.TaxTypeRegistrationRevision{original};
    const changed_rows = [_]registration.TaxTypeRegistrationRevision{changed};
    var original_plan = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &original_rows,
    });
    defer original_plan.deinit(allocator);
    var changed_plan = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &changed_rows,
    });
    defer changed_plan.deinit(allocator);

    switch (original_plan) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |original_obligations| switch (changed_plan) {
            .review_required => try std.testing.expect(false),
            .not_applicable => try std.testing.expect(false),
            .obligations => |changed_obligations| {
                try std.testing.expectEqual(@as(usize, 1), original_obligations.len);
                try std.testing.expectEqual(@as(usize, 1), changed_obligations.len);
                try std.testing.expect(!std.mem.eql(
                    u8,
                    &original_obligations[0].resolution_hash,
                    &changed_obligations[0].resolution_hash,
                ));
            },
        },
    }
}

test "planner excludes branch closed before whole 2550Q filing period" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const branch_id = testId(registration.RegistrationUnitId, "unit-closed-before-period");

    const head = confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    var closed_branch = confirmedUnit(
        branch_id,
        testId(registration.RegistrationUnitRevisionId, "unit-closed-before-period-rev-a"),
        .branch,
        "00001",
        testId(registration.RegistrationEvidenceId, "branch-evidence-closed-before-period"),
        testPeriod(testDate(2024, 1, 1), testDate(2024, 3, 31)),
    );
    closed_branch.status = .confirmed_closed;

    const units = [_]registration.RegistrationUnitRevision{ head, closed_branch };
    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};
    var result = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer result.deinit(allocator);

    switch (result) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            try std.testing.expectEqual(@as(usize, 1), obligations.len);
            const obligation = obligations[0];
            try std.testing.expectEqual(@as(usize, 1), obligation.coverage.len);
            try std.testing.expect(obligation.filing_unit_id.eql(&head_id));
            try std.testing.expect(obligation.coverage[0].registration_unit_id.eql(&head_id));
        },
    }
}

test "planner reviews 2550Q when a branch closes during the filing period" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const branch_id = testId(registration.RegistrationUnitId, "unit-closed-during-period");

    const head = confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    const active_branch = confirmedUnit(
        branch_id,
        testId(registration.RegistrationUnitRevisionId, "unit-closed-during-period-rev-a"),
        .branch,
        "00001",
        testId(registration.RegistrationEvidenceId, "branch-evidence-active"),
        testPeriod(testDate(2024, 1, 1), testDate(2024, 5, 31)),
    );
    var closed_branch = confirmedUnit(
        branch_id,
        testId(registration.RegistrationUnitRevisionId, "unit-closed-during-period-rev-b"),
        .branch,
        "00001",
        testId(registration.RegistrationEvidenceId, "branch-evidence-closed"),
        testPeriod(testDate(2024, 6, 1), null),
    );
    closed_branch.status = .confirmed_closed;

    const units = [_]registration.RegistrationUnitRevision{ head, active_branch, closed_branch };
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};
    var result = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .tax_type_registrations = &vat,
    });
    defer result.deinit(allocator);

    try expectReviewReason(&result, .registration_unit_mid_period_state_change);
}

test "planner resolution hash binds the complete taxpayer identity revision" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const units = [_]registration.RegistrationUnitRevision{confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    )};
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};

    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };
    const original_identity = testIdentity();
    var changed_identity = original_identity;
    changed_identity.tin_root = registration.Tin9.parse("987654321") catch unreachable;

    var original_plan = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = original_identity,
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer original_plan.deinit(allocator);
    var changed_plan = try planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = changed_identity,
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer changed_plan.deinit(allocator);

    switch (original_plan) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |original_obligations| switch (changed_plan) {
            .review_required => try std.testing.expect(false),
            .not_applicable => try std.testing.expect(false),
            .obligations => |changed_obligations| {
                try std.testing.expectEqual(@as(usize, 1), original_obligations.len);
                try std.testing.expectEqual(@as(usize, 1), changed_obligations.len);
                const original = original_obligations[0];
                try std.testing.expectEqual(
                    decision_schema_version,
                    original.decision_schema_version,
                );
                try std.testing.expectEqual(
                    original_identity.sequence,
                    original.taxpayer_identity.sequence,
                );
                try std.testing.expect(original_identity.id.eql(
                    &original.taxpayer_identity.id,
                ));
                try std.testing.expect(!std.mem.eql(
                    u8,
                    &original.resolution_hash,
                    &changed_obligations[0].resolution_hash,
                ));

                var changed = original;
                changed.taxpayer_identity.sequence += 1;
                try std.testing.expect(!std.mem.eql(
                    u8,
                    &original.resolution_hash,
                    &hashObligation(changed),
                ));

                changed = original;
                changed.taxpayer_identity.effective = testPeriod(
                    testDate(2023, 12, 1),
                    testDate(2025, 12, 31),
                );
                try std.testing.expect(!std.mem.eql(
                    u8,
                    &original.resolution_hash,
                    &hashObligation(changed),
                ));

                changed = original;
                changed.taxpayer_identity.evidence_id = testId(
                    registration.RegistrationEvidenceId,
                    "taxpayer-correction-evidence",
                );
                try std.testing.expect(!std.mem.eql(
                    u8,
                    &original.resolution_hash,
                    &hashObligation(changed),
                ));
            },
        },
    }
}

test "planner fails closed for missing changing mismatched or invalid filing-unit contact" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const units = [_]registration.RegistrationUnitRevision{confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    )};
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};

    var missing = try filing_planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .tax_type_registrations = &vat,
    });
    defer missing.deinit(allocator);
    try expectReviewReason(&missing, .missing_filing_unit_contact);
    switch (missing) {
        .review_required => |review| {
            try std.testing.expect(review.resolved_legal_scope != null);
            const scope = review.resolved_legal_scope.?;
            try std.testing.expect(scope.filing_unit_id.eql(&head_id));
            try std.testing.expectEqual(@as(usize, 1), scope.tax_type_registration_bindings.len);
            try std.testing.expectEqual(
                registration.TaxTypeRegistrationStatus.confirmed_active,
                scope.tax_type_registration_bindings[0].status,
            );
            try std.testing.expect(verifyLegalScopeHash(&scope));
        },
        .obligations, .not_applicable => return error.ExpectedReviewRequired,
    }

    var first = validContact(head_id);
    first.effective = testPeriod(
        testDate(2024, 1, 1),
        testDate(2024, 5, 31),
    );
    var second = validContact(head_id);
    second.id = testId(
        registration.RegistrationUnitContactRevisionId,
        "unit-contact-revision-b",
    );
    second.sequence = 2;
    second.effective = testPeriod(testDate(2024, 6, 1), null);
    second.evidence_id = testId(
        registration.RegistrationEvidenceId,
        "unit-contact-evidence-b",
    );
    const changing_contacts = [_]registration.RegistrationUnitContactRevision{ first, second };
    var changing = try filing_planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &changing_contacts,
        .tax_type_registrations = &vat,
    });
    defer changing.deinit(allocator);
    try expectReviewReason(&changing, .filing_unit_contact_mid_period_change);

    var mismatched_contact = validContact(head_id);
    mismatched_contact.taxpayer_id = testId(registration.TaxpayerId, "taxpayer-other");
    const mismatched_contacts = [_]registration.RegistrationUnitContactRevision{
        mismatched_contact,
    };
    var mismatched = try filing_planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &mismatched_contacts,
        .tax_type_registrations = &vat,
    });
    defer mismatched.deinit(allocator);
    try expectReviewReason(&mismatched, .filing_unit_contact_mismatch);

    var invalid_contact = validContact(head_id);
    invalid_contact.contact.registered_address.len = 0;
    const invalid_contacts = [_]registration.RegistrationUnitContactRevision{invalid_contact};
    var invalid = try filing_planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &invalid_contacts,
        .tax_type_registrations = &vat,
    });
    defer invalid.deinit(allocator);
    try expectReviewReason(&invalid, .invalid_filing_unit_contact);
}

test "closed VAT resolves evidence-bearing non-applicability before contact projection" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = plannerFor2550Q(&revisions);
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const units = [_]registration.RegistrationUnitRevision{confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    )};
    var closed_vat = validVatRegistration(head_id);
    closed_vat.status = .confirmed_closed;
    const vat = [_]registration.TaxTypeRegistrationRevision{closed_vat};

    var result = try testing.planForSnapshot(filing_planner, allocator, testRequest(), .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &.{},
        .tax_type_registrations = &vat,
    });
    defer result.deinit(allocator);

    switch (result) {
        .obligations, .review_required => return error.ExpectedNotApplicable,
        .not_applicable => |decision| {
            try std.testing.expect(verifyNotApplicableHash(&decision));
            try std.testing.expect(decision.scope.filing_unit_id.eql(&head_id));
            try std.testing.expect(decision.scope.taxpayer_identity.id.eql(&testIdentity().id));
            try std.testing.expect(decision.scope.policy_revision_id.eql(&revisions[0].id));
            try std.testing.expectEqual(@as(usize, 1), decision.scope.tax_type_registration_bindings.len);
            const binding = decision.scope.tax_type_registration_bindings[0];
            try std.testing.expect(binding.revision_id.eql(&closed_vat.id));
            try std.testing.expectEqual(
                registration.TaxTypeRegistrationStatus.confirmed_closed,
                binding.status,
            );
            try std.testing.expect(binding.evidence_id.eql(&closed_vat.evidence_id.?));
            try std.testing.expect(decision.scope.reviewed_evidence_bindings.len >= 4);
        },
    }
}

test "review issues retain two affected registration-unit revisions" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = plannerFor2550Q(&revisions);
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    var branch_a = confirmedUnit(
        testId(registration.RegistrationUnitId, "unit-branch-a"),
        testId(registration.RegistrationUnitRevisionId, "unit-branch-rev-a"),
        .branch,
        "00001",
        testId(registration.RegistrationEvidenceId, "branch-evidence-a"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    var branch_b = confirmedUnit(
        testId(registration.RegistrationUnitId, "unit-branch-b"),
        testId(registration.RegistrationUnitRevisionId, "unit-branch-rev-b"),
        .branch,
        "00002",
        testId(registration.RegistrationEvidenceId, "branch-evidence-b"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    branch_a.branch_code_evidence.confirmed.evidence_id = .{};
    branch_b.branch_code_evidence.confirmed.evidence_id = .{};
    const units = [_]registration.RegistrationUnitRevision{
        confirmedUnit(
            head_id,
            testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
            .head_office,
            "00000",
            testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
            testPeriod(testDate(2024, 1, 1), null),
        ),
        branch_b,
        branch_a,
    };
    var result = try filing_planner.planForSnapshot(allocator, testRequest(), .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .tax_type_registrations = &.{},
    });
    defer result.deinit(allocator);

    switch (result) {
        .obligations, .not_applicable => return error.ExpectedReviewRequired,
        .review_required => |review| {
            var affected: usize = 0;
            for (review.issues) |issue| {
                if (issue.reason != .registration_unit_pending_evidence) continue;
                switch (issue.subject) {
                    .registration_unit_revision => |revision_id| {
                        if (revision_id.eql(&branch_a.id) or revision_id.eql(&branch_b.id)) {
                            affected += 1;
                        }
                    },
                    else => {},
                }
            }
            try std.testing.expectEqual(@as(usize, 2), affected);
        },
    }
}

test "resolution hash binds exact accepted review decision and assertion" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = plannerFor2550Q(&revisions);
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const units = [_]registration.RegistrationUnitRevision{confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    )};
    const contacts = [_]registration.RegistrationUnitContactRevision{validContact(head_id)};
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};
    const identity = testIdentity();
    var exact_binding = ReviewedEvidenceBinding{
        .subject = .{ .taxpayer_identity_revision = identity.id },
        .evidence_id = identity.evidence_id.?,
        .review_decision_id = testId(
            registration.RegistrationEvidenceReviewDecisionId,
            "review-decision-a",
        ),
        .review_decision_sequence = 1,
        .assertion_id = testId(
            registration.RegistrationEvidenceAssertionId,
            "assertion-a",
        ),
    };
    var bindings = [_]ReviewedEvidenceBinding{exact_binding};
    var result = try filing_planner.planForSnapshot(allocator, testRequest(), .{
        .taxpayer_identity = identity,
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
        .reviewed_evidence_bindings = &bindings,
    });
    defer result.deinit(allocator);

    switch (result) {
        .review_required, .not_applicable => return error.ExpectedObligation,
        .obligations => |obligations| {
            const original = obligations[0];
            try std.testing.expectEqual(@as(usize, 1), original.reviewed_evidence_bindings.len);

            var changed_bindings = [_]ReviewedEvidenceBinding{original.reviewed_evidence_bindings[0]};
            changed_bindings[0].review_decision_id = testId(
                registration.RegistrationEvidenceReviewDecisionId,
                "review-decision-b",
            );
            changed_bindings[0].review_decision_sequence = 2;
            var changed = original;
            changed.reviewed_evidence_bindings = &changed_bindings;
            try std.testing.expect(!std.mem.eql(
                u8,
                &original.resolution_hash,
                &hashObligation(changed),
            ));

            exact_binding.assertion_id = testId(
                registration.RegistrationEvidenceAssertionId,
                "assertion-b",
            );
            changed_bindings[0] = exact_binding;
            changed.reviewed_evidence_bindings = &changed_bindings;
            try std.testing.expect(!std.mem.eql(
                u8,
                &original.resolution_hash,
                &hashObligation(changed),
            ));
        },
    }
}

test "large-taxpayer and facility revision bindings are distinct types" {
    try std.testing.expect(LargeTaxpayerServiceRevisionId != RegisteredFacilityRevisionId);
    const lts = try LargeTaxpayerServiceRevisionId.parse("revision-a");
    const facility = try RegisteredFacilityRevisionId.parse("revision-a");
    try std.testing.expectEqualStrings(lts.asSlice(), facility.asSlice());
}

test "resolution hash binds filing-unit RDO and complete contact revision" {
    const allocator = std.testing.allocator;
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = plannerFor2550Q(&revisions);
    const request = testRequest();
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    var head = confirmedUnit(
        head_id,
        testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
        .head_office,
        "00000",
        testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        testPeriod(testDate(2024, 1, 1), null),
    );
    head.rdo_code = registration.RdoCode3.parse("047") catch unreachable;
    const units = [_]registration.RegistrationUnitRevision{head};
    const contacts = [_]registration.RegistrationUnitContactRevision{validContact(head_id)};
    const vat = [_]registration.TaxTypeRegistrationRevision{validVatRegistration(head_id)};

    var result = try filing_planner.planForSnapshot(allocator, request, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    defer result.deinit(allocator);

    switch (result) {
        .review_required, .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            const original = obligations[0];
            try std.testing.expect(verifyResolutionHash(&original));

            var changed = original;
            changed.filing_unit_rdo_code = registration.RdoCode3.parse("048") catch unreachable;
            try std.testing.expect(!std.mem.eql(
                u8,
                &original.resolution_hash,
                &hashObligation(changed),
            ));

            changed = original;
            changed.filing_unit_contact.contact.registered_address =
                registration.field.RegisteredAddress.parse("200 Changed Avenue") catch unreachable;
            try std.testing.expect(!std.mem.eql(
                u8,
                &original.resolution_hash,
                &hashObligation(changed),
            ));

            changed = original;
            changed.filing_unit_contact.id = testId(
                registration.RegistrationUnitContactRevisionId,
                "unit-contact-revision-b",
            );
            try std.testing.expect(!std.mem.eql(
                u8,
                &original.resolution_hash,
                &hashObligation(changed),
            ));

            changed = original;
            changed.filing_unit_contact.evidence_id = testId(
                registration.RegistrationEvidenceId,
                "unit-contact-evidence-b",
            );
            try std.testing.expect(!std.mem.eql(
                u8,
                &original.resolution_hash,
                &hashObligation(changed),
            ));
        },
    }
}
