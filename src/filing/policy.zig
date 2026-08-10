//! Pure, evidence-linked filing-policy catalog.
//!
//! This module deliberately knows nothing about taxpayer storage, selected
//! workspaces, form editors, draft creation, filing venues, or deadlines.
//! Its single job is to make an exact form revision's reviewed filing-scope
//! policy explicit and to fail closed when the catalog cannot select one
//! unambiguous effective revision.

const builtin = @import("builtin");
const std = @import("std");
const domain_date = @import("../domain/date.zig");
const forms_id = @import("../forms/id.zig");

/// Filing policy uses the repository's canonical civil-date vocabulary. This
/// keeps validation, ordering, leap-year handling, and inclusive effective
/// period semantics identical to registration facts and every other domain.
pub const Date = domain_date.Date;
pub const DateError = domain_date.Error;
pub const EffectivePeriod = domain_date.EffectivePeriod;

pub const IdError = forms_id.Error;
pub const FormCode = forms_id.FormCode;
pub const FormRevisionLabel = forms_id.RevisionLabel;
pub const FormRevisionKey = forms_id.FormRevision;
pub const FilingPolicyRevisionId = forms_id.FilingPolicyRevisionId;
pub const PolicyEvidenceId = forms_id.PolicyEvidenceId;

/// Product capability is deliberately separate from obligation resolution and
/// fileability.  For example, an editor may be present while its reviewed
/// scope policy still blocks launch, and an editor-supported form is not
/// thereby a qualified artifact or an enabled submission.
pub const CapabilityState = enum {
    editor_supported,
    reference_only,
    unsupported,
};

/// Policy and evidence promotion are explicit audit states.  Candidate and
/// reviewed entries may be stored in a catalog but cannot resolve filing
/// scope.  A superseded entry retains a closed historical effective interval
/// and can resolve only a date inside that interval.
pub const PolicyRevisionLifecycle = enum {
    candidate,
    reviewed,
    effective,
    superseded,

    pub fn isResolutionEligible(self: PolicyRevisionLifecycle) bool {
        return switch (self) {
            .effective, .superseded => true,
            .candidate, .reviewed => false,
        };
    }
};

pub const PolicyEvidenceState = enum {
    candidate,
    reviewed,
    effective,
    superseded,

    pub fn supportsResolution(self: PolicyEvidenceState) bool {
        return switch (self) {
            .effective, .superseded => true,
            .candidate, .reviewed => false,
        };
    }
};

pub const PolicyEvidenceRef = struct {
    id: PolicyEvidenceId,
    state: PolicyEvidenceState,
    display_name: []const u8,
    review_basis: []const u8,
};

pub const PolicyCategory = enum {
    head_office_consolidated,
    registration_driven,
    transaction_specific,
    payment_inherit_liability,
    supporting_artifact,
    administrative,
    historical_only,
    review_required,
};

pub const HeadOfficeCoverage = enum {
    all_applicable_registration_units,
};

pub const HeadOfficeConsolidatedPolicy = struct {
    coverage: HeadOfficeCoverage = .all_applicable_registration_units,
};

pub const RegistrationDrivenScope = enum {
    /// Effective registration evidence determines whether a unit has its own
    /// return or is covered by another return.
    registration_evidence_decides,
    per_registered_unit,
    head_office_consolidated,
};

pub const LargeTaxpayerOverride = enum {
    head_office_consolidated,
};

pub const RegistrationDrivenPolicy = struct {
    ordinary_scope: RegistrationDrivenScope,
    large_taxpayer_override: ?LargeTaxpayerOverride = null,
};

pub const TransactionContextKind = enum {
    property,
    instrument,
    transfer,
    facility,
    other,
};

pub const TransactionScopePolicy = struct {
    required_context: TransactionContextKind,
};

/// A payment form derives its Filing Unit and Return Coverage from an exact
/// assessed, return, installment, penalty, or other underlying liability.
pub const LiabilityScopePolicy = enum {
    inherit_liability,
};

pub const ParentArtifactKind = enum {
    return_attachment,
    supporting_schedule,
    other,
};

pub const SourceRecipientKind = enum {
    employee,
    payee,
    counterparty,
    other,
};

pub const ArtifactScopePolicy = union(enum) {
    inherit_parent: ParentArtifactKind,
    source_recipient_document: SourceRecipientKind,
};

pub const AdministrativePolicy = enum {
    taxpayer_registration,
    registration_unit,
    facility,
    tax_type_registration,
};

pub const HistoricalOnlyPolicy = struct {};

pub const ReviewReason = enum {
    unreviewed_policy,
    missing_primary_evidence,
    effectivity_unproven,
    form_identity_conflict,
    registration_scope_unproven,
    special_context_required,
    artifact_representation_unproven,
    historical_applicability_unproven,
};

pub const ReviewRequiredPolicy = struct {
    reason: ReviewReason,
};

/// A policy tells the planner which inputs are required to resolve a filing
/// scope.  It does not itself select a Filing Unit, calculate a deadline, or
/// establish a filing venue.
pub const FilingPolicy = union(enum) {
    periodic_return: ReturnScopePolicy,
    transaction_return: TransactionScopePolicy,
    payment: LiabilityScopePolicy,
    supporting_artifact: ArtifactScopePolicy,
    administrative_registration: AdministrativePolicy,
    historical_only: HistoricalOnlyPolicy,
    review_required: ReviewRequiredPolicy,

    pub fn category(self: FilingPolicy) PolicyCategory {
        return switch (self) {
            .periodic_return => |scope| switch (scope) {
                .head_office_consolidated => .head_office_consolidated,
                .registration_driven => .registration_driven,
            },
            .transaction_return => .transaction_specific,
            .payment => .payment_inherit_liability,
            .supporting_artifact => .supporting_artifact,
            .administrative_registration => .administrative,
            .historical_only => .historical_only,
            .review_required => .review_required,
        };
    }
};

pub const ReturnScopePolicy = union(enum) {
    head_office_consolidated: HeadOfficeConsolidatedPolicy,
    registration_driven: RegistrationDrivenPolicy,
};

pub const ValidationError = error{
    EmptyPolicyRevisionId,
    EmptyFormCode,
    EmptyFormRevision,
    InvalidEffectivePeriod,
    MissingPolicyEvidence,
    EmptyPolicyEvidenceId,
    EmptyPolicyEvidenceDisplayName,
    EmptyPolicyEvidenceReviewBasis,
    DuplicatePolicyEvidenceId,
    ResolutionEligibleEvidenceNotEffective,
    EmptySupersededRevisionId,
    SupersededPolicyRequiresClosedEffectivePeriod,
    DuplicatePolicyRevisionId,
    OverlappingEffectivePolicies,
};

/// Immutable, evidence-linked policy revision.  A caller should construct
/// these from reviewed catalog data; this module intentionally owns no
/// persistence format or policy-loading adapter.
pub const FilingPolicyRevision = struct {
    id: FilingPolicyRevisionId,
    form: FormRevisionKey,
    effective: EffectivePeriod,
    lifecycle: PolicyRevisionLifecycle,
    evidence: []const PolicyEvidenceRef,
    capability: CapabilityState,
    policy: FilingPolicy,
    supersedes: ?FilingPolicyRevisionId = null,

    pub fn validate(self: *const FilingPolicyRevision) ValidationError!void {
        if (self.id.isEmpty()) return error.EmptyPolicyRevisionId;
        if (self.form.code.isEmpty()) return error.EmptyFormCode;
        if (self.form.revision.isEmpty()) return error.EmptyFormRevision;
        if (self.effective.until) |until| {
            if (until.isBefore(self.effective.from)) {
                return error.InvalidEffectivePeriod;
            }
        }
        if (self.lifecycle == .superseded and self.effective.until == null) {
            return error.SupersededPolicyRequiresClosedEffectivePeriod;
        }
        if (self.evidence.len == 0) return error.MissingPolicyEvidence;

        for (self.evidence, 0..) |evidence, index| {
            if (evidence.id.isEmpty()) return error.EmptyPolicyEvidenceId;
            if (std.mem.trim(u8, evidence.display_name, " \t\r\n").len == 0) {
                return error.EmptyPolicyEvidenceDisplayName;
            }
            if (std.mem.trim(u8, evidence.review_basis, " \t\r\n").len == 0) {
                return error.EmptyPolicyEvidenceReviewBasis;
            }
            if (self.lifecycle.isResolutionEligible() and !evidence.state.supportsResolution()) {
                return error.ResolutionEligibleEvidenceNotEffective;
            }
            for (self.evidence[0..index]) |previous| {
                if (evidence.id.eql(&previous.id)) {
                    return error.DuplicatePolicyEvidenceId;
                }
            }
        }

        if (self.supersedes) |superseded| {
            if (superseded.isEmpty()) return error.EmptySupersededRevisionId;
        }
    }
};

pub const PolicySelectionIssue = union(enum) {
    invalid_form_revision_key,
    missing_effective_policy,
    overlapping_effective_policies,
    invalid_effective_policy: ValidationError,
    policy_requires_review: ReviewReason,
};

/// The policy stage has domain outcomes rather than a fallback policy.  The
/// planner turns a review outcome into ordered, actionable ResolutionIssues.
pub const PolicySelection = union(enum) {
    effective: *const FilingPolicyRevision,
    review_required: PolicySelectionIssue,
};

/// Pure catalog seam for exact form-revision policy selection.
pub const FilingPolicyCatalog = struct {
    revisions: []const FilingPolicyRevision,

    pub fn evidenceForRevision(
        self: FilingPolicyCatalog,
        revision_id: FilingPolicyRevisionId,
        evidence_id: PolicyEvidenceId,
    ) ?*const PolicyEvidenceRef {
        for (self.revisions) |*revision| {
            if (!revision.id.eql(&revision_id)) continue;
            for (revision.evidence) |*evidence| {
                if (evidence.id.eql(&evidence_id)) return evidence;
            }
            return null;
        }
        return null;
    }

    pub fn validate(self: FilingPolicyCatalog) ValidationError!void {
        for (0..self.revisions.len) |left_index| {
            const left = &self.revisions[left_index];
            try left.validate();

            for (left_index + 1..self.revisions.len) |right_index| {
                const right = &self.revisions[right_index];
                if (left.id.eql(&right.id)) return error.DuplicatePolicyRevisionId;

                if (!left.lifecycle.isResolutionEligible() or
                    !right.lifecycle.isResolutionEligible() or
                    !left.form.eql(&right.form) or
                    !left.effective.overlaps(right.effective))
                {
                    continue;
                }

                return error.OverlappingEffectivePolicies;
            }
        }
    }

    /// Select exactly one revision effective on `filing_date`.  No matching
    /// revision and multiple matching revisions both produce Review Required;
    /// neither path chooses a workspace, head office, branch, or catalog
    /// default.
    pub fn selectEffective(
        self: FilingPolicyCatalog,
        form: FormRevisionKey,
        filing_date: Date,
    ) PolicySelection {
        if (!form.isValid()) {
            return .{ .review_required = .invalid_form_revision_key };
        }

        var selected: ?*const FilingPolicyRevision = null;
        for (0..self.revisions.len) |index| {
            const revision = &self.revisions[index];
            if (!revision.lifecycle.isResolutionEligible() or
                !revision.form.eql(&form) or
                !revision.effective.contains(filing_date))
            {
                continue;
            }

            revision.validate() catch |err| {
                return .{ .review_required = .{ .invalid_effective_policy = err } };
            };
            if (selected != null) {
                return .{ .review_required = .overlapping_effective_policies };
            }
            selected = revision;
        }

        const revision = selected orelse {
            return .{ .review_required = .missing_effective_policy };
        };

        return switch (revision.policy) {
            .review_required => |review| .{
                .review_required = .{ .policy_requires_review = review.reason },
            },
            else => .{ .effective = revision },
        };
    }
};

fn fixtureDate(comptime raw: []const u8) Date {
    return Date.parseIso(raw) catch unreachable;
}

fn fixturePeriod(comptime from: []const u8, comptime until: ?[]const u8) EffectivePeriod {
    return EffectivePeriod.init(
        fixtureDate(from),
        if (until) |last| fixtureDate(last) else null,
    ) catch unreachable;
}

const fixture_2550q_evidence = [_]PolicyEvidenceRef{.{
    .id = PolicyEvidenceId.initComptime("bir-2550q-2024-04-instructions"),
    .state = .effective,
    .display_name = "BIR Form 2550Q April 2024 instructions",
    .review_basis = "Branches file one consolidated return at the principal place or head office covering all branches.",
}};

const fixture_2551q_evidence = [_]PolicyEvidenceRef{.{
    .id = PolicyEvidenceId.initComptime("bir-2551q-2018-01-instructions"),
    .state = .effective,
    .display_name = "BIR Form 2551Q January 2018 instructions",
    .review_basis = "The taxpayer may file separate head-office and branch returns or one consolidated head-office return; large taxpayers file one consolidated return.",
}};

const fixture_0605_evidence = [_]PolicyEvidenceRef{.{
    .id = PolicyEvidenceId.initComptime("bir-0605-underlying-liability"),
    .state = .effective,
    .display_name = "BIR Form 0605 underlying-liability instructions",
    .review_basis = "Payment scope inherits the exact assessed return, installment, penalty, or other underlying liability.",
}};

const fixture_review_evidence = [_]PolicyEvidenceRef{.{
    .id = PolicyEvidenceId.initComptime("policy-review-2550m-current-use"),
    .state = .effective,
    .display_name = "2550M current-use policy review",
    .review_basis = "Current filing use remains unverified, so the catalog keeps this revision reference-only and Review Required.",
}};

fn fixture2550QRevision() FilingPolicyRevision {
    return .{
        .id = FilingPolicyRevisionId.initComptime("policy-2550q-2024-04"),
        .form = FormRevisionKey.initComptime("2550Q", "2024-04-ENCS"),
        .effective = fixturePeriod("2024-04-01", null),
        .lifecycle = .effective,
        .evidence = &fixture_2550q_evidence,
        .capability = .editor_supported,
        .policy = .{ .periodic_return = .{
            .head_office_consolidated = .{},
        } },
    };
}

const isolated_preview_2550q_revisions = [_]FilingPolicyRevision{
    fixture2550QRevision(),
};

/// Deliberately non-production policy seam for the isolated TIN/branch
/// fixture-preview workflow. Callers must enforce the explicit fixture gate
/// and an explicit data directory before selecting this catalog. Normal app
/// execution continues to use an empty, fail-closed production catalog.
pub const isolated_fixture_preview = struct {
    pub const environment_gate = "EBIRFORMS_TIN_BRANCH_FIXTURE_PREVIEW";

    pub fn catalog2550Q() FilingPolicyCatalog {
        return .{ .revisions = &isolated_preview_2550q_revisions };
    }
};

pub const testing = if (builtin.is_test) struct {
    /// Test fixture only: it records the contract shape for the reviewed 2550Q
    /// example; it is not a production catalog or a fileability assertion.
    pub fn fixture2550Q() FilingPolicyRevision {
        return fixture2550QRevision();
    }

    /// Test fixture only: registration evidence determines ordinary 2551Q scope;
    /// a verified Large Taxpayer rule overrides that scope to head-office filing.
    pub fn fixture2551Q() FilingPolicyRevision {
        return .{
            .id = FilingPolicyRevisionId.initComptime("policy-2551q-2018-01"),
            .form = FormRevisionKey.initComptime("2551Q", "2018-01-ENCS"),
            .effective = fixturePeriod("2018-01-01", null),
            .lifecycle = .effective,
            .evidence = &fixture_2551q_evidence,
            .capability = .editor_supported,
            .policy = .{ .periodic_return = .{
                .registration_driven = .{
                    .ordinary_scope = .registration_evidence_decides,
                    .large_taxpayer_override = .head_office_consolidated,
                },
            } },
        };
    }

    /// Test fixture only: Form 0605 cannot create an independent branch or
    /// registration-fee obligation.  It inherits an exact underlying liability.
    pub fn fixture0605() FilingPolicyRevision {
        return .{
            .id = FilingPolicyRevisionId.initComptime("policy-0605-liability"),
            .form = FormRevisionKey.initComptime("0605", "1999-07-ENCS"),
            .effective = fixturePeriod("2024-01-22", null),
            .lifecycle = .effective,
            .evidence = &fixture_0605_evidence,
            .capability = .editor_supported,
            .policy = .{ .payment = .inherit_liability },
        };
    }

    /// Test fixture only: an exact revision can be catalogued explicitly while
    /// still blocking obligation generation pending review.
    pub fn fixtureReviewRequired() FilingPolicyRevision {
        return .{
            .id = FilingPolicyRevisionId.initComptime("policy-2550m-review"),
            .form = FormRevisionKey.initComptime("2550M", "unverified"),
            .effective = fixturePeriod("2024-01-01", null),
            .lifecycle = .effective,
            .evidence = &fixture_review_evidence,
            .capability = .reference_only,
            .policy = .{ .review_required = .{
                .reason = .unreviewed_policy,
            } },
        };
    }
} else struct {};

test "2550Q fixture selects a head-office-consolidated policy" {
    const revision = testing.fixture2550Q();
    const revisions = [_]FilingPolicyRevision{revision};
    const catalog = FilingPolicyCatalog{ .revisions = &revisions };
    try catalog.validate();

    const selection = catalog.selectEffective(revision.form, fixtureDate("2025-01-01"));
    switch (selection) {
        .effective => |selected| {
            try std.testing.expectEqual(CapabilityState.editor_supported, selected.capability);
            try std.testing.expectEqual(
                PolicyCategory.head_office_consolidated,
                selected.policy.category(),
            );
            switch (selected.policy) {
                .periodic_return => |scope| switch (scope) {
                    .head_office_consolidated => |policy| try std.testing.expectEqual(
                        HeadOfficeCoverage.all_applicable_registration_units,
                        policy.coverage,
                    ),
                    else => try std.testing.expect(false),
                },
                else => try std.testing.expect(false),
            }
        },
        .review_required => try std.testing.expect(false),
    }
}

test "policy catalog exposes the reviewed evidence explanation for a revision" {
    const revision = testing.fixture2550Q();
    const revisions = [_]FilingPolicyRevision{revision};
    const catalog = FilingPolicyCatalog{ .revisions = &revisions };
    const evidence = catalog.evidenceForRevision(
        revision.id,
        revision.evidence[0].id,
    );
    try std.testing.expect(evidence != null);

    try std.testing.expectEqualStrings(
        "BIR Form 2550Q April 2024 instructions",
        evidence.?.display_name,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, evidence.?.review_basis, "all branches") != null,
    );
}

test "2551Q fixture records registration-driven scope and LTS override" {
    const revision = testing.fixture2551Q();
    const revisions = [_]FilingPolicyRevision{revision};
    const catalog = FilingPolicyCatalog{ .revisions = &revisions };
    try catalog.validate();

    const selection = catalog.selectEffective(revision.form, fixtureDate("2025-01-01"));
    switch (selection) {
        .effective => |selected| {
            try std.testing.expectEqual(
                PolicyCategory.registration_driven,
                selected.policy.category(),
            );
            switch (selected.policy) {
                .periodic_return => |return_scope| switch (return_scope) {
                    .registration_driven => |scope| {
                        try std.testing.expectEqual(
                            RegistrationDrivenScope.registration_evidence_decides,
                            scope.ordinary_scope,
                        );
                        try std.testing.expectEqual(
                            LargeTaxpayerOverride.head_office_consolidated,
                            scope.large_taxpayer_override.?,
                        );
                    },
                    else => try std.testing.expect(false),
                },
                else => try std.testing.expect(false),
            }
        },
        .review_required => try std.testing.expect(false),
    }
}

test "0605 fixture inherits an exact underlying liability" {
    const revision = testing.fixture0605();
    const revisions = [_]FilingPolicyRevision{revision};
    const catalog = FilingPolicyCatalog{ .revisions = &revisions };
    try catalog.validate();

    const selection = catalog.selectEffective(revision.form, fixtureDate("2025-01-01"));
    switch (selection) {
        .effective => |selected| {
            try std.testing.expectEqual(
                PolicyCategory.payment_inherit_liability,
                selected.policy.category(),
            );
            switch (selected.policy) {
                .payment => |scope| try std.testing.expectEqual(
                    LiabilityScopePolicy.inherit_liability,
                    scope,
                ),
                else => try std.testing.expect(false),
            }
        },
        .review_required => try std.testing.expect(false),
    }
}

test "review-required policy remains a review outcome despite editor capability" {
    const revision = testing.fixtureReviewRequired();
    const revisions = [_]FilingPolicyRevision{revision};
    const catalog = FilingPolicyCatalog{ .revisions = &revisions };
    try catalog.validate();

    const selection = catalog.selectEffective(revision.form, fixtureDate("2025-01-01"));
    switch (selection) {
        .effective => try std.testing.expect(false),
        .review_required => |issue| switch (issue) {
            .policy_requires_review => |reason| try std.testing.expectEqual(
                ReviewReason.unreviewed_policy,
                reason,
            ),
            else => try std.testing.expect(false),
        },
    }
}

test "catalog selection fails closed on missing and overlapping effective policies" {
    const missing = FilingPolicyCatalog{ .revisions = &.{} };
    const form = FormRevisionKey.initComptime("2550Q", "2024-04-ENCS");
    switch (missing.selectEffective(form, fixtureDate("2025-01-01"))) {
        .review_required => |issue| switch (issue) {
            .missing_effective_policy => {},
            else => try std.testing.expect(false),
        },
        .effective => try std.testing.expect(false),
    }

    const first = testing.fixture2550Q();
    var second = testing.fixture2550Q();
    second.id = FilingPolicyRevisionId.initComptime("policy-2550q-overlap");
    const overlapping = [_]FilingPolicyRevision{ first, second };
    const catalog = FilingPolicyCatalog{ .revisions = &overlapping };
    try std.testing.expectError(error.OverlappingEffectivePolicies, catalog.validate());
    switch (catalog.selectEffective(form, fixtureDate("2025-01-01"))) {
        .review_required => |issue| switch (issue) {
            .overlapping_effective_policies => {},
            else => try std.testing.expect(false),
        },
        .effective => try std.testing.expect(false),
    }
}

test "candidate and evidence-incomplete policies cannot become actionable" {
    var candidate = testing.fixture2550Q();
    candidate.lifecycle = .candidate;
    const candidate_revisions = [_]FilingPolicyRevision{candidate};
    const candidate_catalog = FilingPolicyCatalog{ .revisions = &candidate_revisions };
    switch (candidate_catalog.selectEffective(candidate.form, fixtureDate("2025-01-01"))) {
        .review_required => |issue| switch (issue) {
            .missing_effective_policy => {},
            else => try std.testing.expect(false),
        },
        .effective => try std.testing.expect(false),
    }

    var missing_evidence = testing.fixture2550Q();
    const no_evidence = [_]PolicyEvidenceRef{};
    missing_evidence.evidence = &no_evidence;
    const invalid_revisions = [_]FilingPolicyRevision{missing_evidence};
    const invalid_catalog = FilingPolicyCatalog{ .revisions = &invalid_revisions };
    switch (invalid_catalog.selectEffective(missing_evidence.form, fixtureDate("2025-01-01"))) {
        .review_required => |issue| switch (issue) {
            .invalid_effective_policy => |err| try std.testing.expectEqual(
                ValidationError.MissingPolicyEvidence,
                err,
            ),
            else => try std.testing.expect(false),
        },
        .effective => try std.testing.expect(false),
    }
}

test "policy validation rejects duplicate evidence identifiers" {
    var duplicate_evidence_policy = testing.fixture2550Q();
    const duplicate_evidence = [_]PolicyEvidenceRef{
        fixture_2550q_evidence[0],
        fixture_2550q_evidence[0],
    };
    duplicate_evidence_policy.evidence = &duplicate_evidence;
    try std.testing.expectError(
        error.DuplicatePolicyEvidenceId,
        duplicate_evidence_policy.validate(),
    );
}

test "policy validation requires human-readable evidence context" {
    var policy_with_empty_name = testing.fixture2550Q();
    var empty_name = fixture_2550q_evidence;
    empty_name[0].display_name = " ";
    policy_with_empty_name.evidence = &empty_name;
    try std.testing.expectError(
        error.EmptyPolicyEvidenceDisplayName,
        policy_with_empty_name.validate(),
    );

    var policy_with_empty_basis = testing.fixture2550Q();
    var empty_basis = fixture_2550q_evidence;
    empty_basis[0].review_basis = "\t";
    policy_with_empty_basis.evidence = &empty_basis;
    try std.testing.expectError(
        error.EmptyPolicyEvidenceReviewBasis,
        policy_with_empty_basis.validate(),
    );
}

test "a superseded policy must have a closed effective interval" {
    var superseded = testing.fixture2550Q();
    superseded.lifecycle = .superseded;
    try std.testing.expectError(
        error.SupersededPolicyRequiresClosedEffectivePeriod,
        superseded.validate(),
    );

    const revisions = [_]FilingPolicyRevision{superseded};
    const catalog = FilingPolicyCatalog{ .revisions = &revisions };
    switch (catalog.selectEffective(superseded.form, fixtureDate("2025-01-01"))) {
        .effective => try std.testing.expect(false),
        .review_required => |issue| switch (issue) {
            .invalid_effective_policy => |err| try std.testing.expectEqual(
                ValidationError.SupersededPolicyRequiresClosedEffectivePeriod,
                err,
            ),
            else => try std.testing.expect(false),
        },
    }
}
