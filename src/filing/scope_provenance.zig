//! Immutable, allocator-owned provenance for a resolved filing scope.
//!
//! This module is intentionally downstream of `planner.FilingObligation`.
//! It does not accept a profile, workspace selection, branch selection, or
//! independently assembled filing identity. Its purpose is to preserve the
//! planner's exact decision before a future draft path can consume it.

const std = @import("std");
const evidence_binding = @import("evidence_binding.zig");
const planner = @import("planner.zig");
const policy = @import("policy.zig");
const registration = @import("../tax_profile/registration_domain.zig");

pub const decision_schema_version: u16 = planner.decision_schema_version;

pub const ScopeError = error{
    UnsupportedDecisionSchemaVersion,
    ResolutionHashMismatch,
    MissingTaxpayerIdentity,
    InvalidTaxpayerIdentity,
    TaxpayerIdentityNotEffective,
    InvalidFormRevision,
    InvalidCivilPeriod,
    MissingFilingUnit,
    InvalidFilingBranchCode,
    MissingFilingBranchEvidence,
    InvalidFilingUnitContact,
    FilingUnitContactMismatch,
    FilingUnitContactNotEffective,
    EmptyCoverage,
    InvalidCoverage,
    DuplicateCoverage,
    NonCanonicalCoverage,
    FilingUnitNotCovered,
    FilingUnitCoverageMismatch,
    EmptyTaxTypeRegistrationBindings,
    InvalidTaxTypeRegistrationBinding,
    DuplicateTaxTypeRegistrationBinding,
    NonCanonicalTaxTypeRegistrationBinding,
    TaxTypeRegistrationBindingNotCovered,
    Invalid2550QVatBinding,
    EmptyReviewedEvidenceBindings,
    InvalidReviewedEvidenceBinding,
    DuplicateReviewedEvidenceBinding,
    NonCanonicalReviewedEvidenceBinding,
    MissingReviewedEvidenceBinding,
    ReviewedEvidenceBindingMismatch,
    InvalidLtsRevisionBinding,
    InvalidFacilityRevisionBinding,
    DuplicateFacilityRevisionBinding,
    NonCanonicalFacilityRevisionBinding,
    InvalidSpecialContextDigest,
    FilingVenueReviewRequired,
    Invalid2550QContextBindings,
    MissingPolicyRevision,
    EmptyPolicyEvidence,
    DuplicatePolicyEvidence,
    NonCanonicalPolicyEvidence,
    NotFileable,
};

/// A copied, versioned scope decision. Its VAT binding retains the exact
/// tax-type registration shell, revision, and accepted evidence selected by
/// the planner; it is not an editor or Forms Set preference.
pub const ScopeProvenance = struct {
    decision_schema_version: u16,
    taxpayer_identity: registration.TaxpayerIdentityRevision,
    form_revision: policy.FormRevisionKey,
    civil_period: planner.CivilPeriod,
    filing_unit_id: registration.RegistrationUnitId,
    filing_unit_revision_id: registration.RegistrationUnitRevisionId,
    filing_branch_code: registration.BranchCode5,
    filing_branch_evidence_id: registration.RegistrationEvidenceId,
    filing_unit_rdo_code: ?registration.RdoCode3,
    filing_unit_contact: registration.RegistrationUnitContactRevision,
    coverage: []const planner.RegistrationUnitCoverage,
    tax_type_registration_bindings: []const planner.TaxTypeRegistrationBinding,
    reviewed_evidence_bindings: []const planner.ReviewedEvidenceBinding,
    lts_revision_id: ?planner.LargeTaxpayerServiceRevisionId,
    facility_revision_ids: []const planner.RegisteredFacilityRevisionId,
    source_attribution_requirement: planner.SourceAttributionRequirement,
    policy_revision_id: policy.FilingPolicyRevisionId,
    policy_evidence_ids: []const policy.PolicyEvidenceId,
    special_context_digest: ?[32]u8,
    policy_capability: policy.CapabilityState,
    filing_capability: planner.FilingCapability,
    filing_venue_resolution: planner.FilingVenueResolution,
    resolution_hash: planner.ResolutionHash,

    /// The sole supported construction path copies a planner obligation after
    /// validating its exact structure and canonical resolution hash.
    pub fn capture(
        allocator: std.mem.Allocator,
        obligation: *const planner.FilingObligation,
    ) (ScopeError || std.mem.Allocator.Error)!ScopeProvenance {
        try validateObligation(obligation);
        return copyObligation(allocator, obligation);
    }

    pub fn deinit(self: ScopeProvenance, allocator: std.mem.Allocator) void {
        allocator.free(self.coverage);
        allocator.free(self.tax_type_registration_bindings);
        allocator.free(self.reviewed_evidence_bindings);
        allocator.free(self.facility_revision_ids);
        allocator.free(self.policy_evidence_ids);
    }

    /// Rechecks a retained snapshot without reaching back to mutable storage.
    pub fn validate(self: *const ScopeProvenance) ScopeError!void {
        if (self.decision_schema_version != decision_schema_version) {
            return error.UnsupportedDecisionSchemaVersion;
        }
        const obligation = self.asObligation();
        try validateObligation(&obligation);
    }

    fn asObligation(self: *const ScopeProvenance) planner.FilingObligation {
        return .{
            .decision_schema_version = self.decision_schema_version,
            .taxpayer_identity = self.taxpayer_identity,
            .form_revision = self.form_revision,
            .civil_period = self.civil_period,
            .filing_unit_id = self.filing_unit_id,
            .filing_unit_revision_id = self.filing_unit_revision_id,
            .filing_branch_code = self.filing_branch_code,
            .filing_branch_evidence_id = self.filing_branch_evidence_id,
            .filing_unit_rdo_code = self.filing_unit_rdo_code,
            .filing_unit_contact = self.filing_unit_contact,
            .coverage = self.coverage,
            .tax_type_registration_bindings = self.tax_type_registration_bindings,
            .reviewed_evidence_bindings = self.reviewed_evidence_bindings,
            .lts_revision_id = self.lts_revision_id,
            .facility_revision_ids = self.facility_revision_ids,
            .source_attribution_requirement = self.source_attribution_requirement,
            .policy_revision_id = self.policy_revision_id,
            .policy_evidence_ids = self.policy_evidence_ids,
            .special_context_digest = self.special_context_digest,
            .policy_capability = self.policy_capability,
            .filing_capability = self.filing_capability,
            .filing_venue_resolution = self.filing_venue_resolution,
            .resolution_hash = self.resolution_hash,
        };
    }
};

/// A future legacy draft adapter may require this type as its sole scope
/// input. No current planner result can create one because all current plans
/// are explicitly `not_fileable`.
pub const PreparedDraftScope = struct {
    scope: ScopeProvenance,

    pub fn deinit(self: PreparedDraftScope, allocator: std.mem.Allocator) void {
        self.scope.deinit(allocator);
    }
};

/// Gate for any draft path that wants a filing scope. It validates the source
/// decision before checking capability, then refuses the current vertical
/// slice's `not_fileable` obligations without allocating a transferable scope.
pub fn prepareDraftScope(
    allocator: std.mem.Allocator,
    obligation: *const planner.FilingObligation,
) (ScopeError || std.mem.Allocator.Error)!PreparedDraftScope {
    try validateObligation(obligation);
    if (obligation.filing_capability != .fileable) return error.NotFileable;
    return .{ .scope = try copyObligation(allocator, obligation) };
}

fn copyObligation(
    allocator: std.mem.Allocator,
    obligation: *const planner.FilingObligation,
) std.mem.Allocator.Error!ScopeProvenance {
    const coverage = try allocator.dupe(planner.RegistrationUnitCoverage, obligation.coverage);
    errdefer allocator.free(coverage);
    const tax_type_registration_bindings = try allocator.dupe(
        planner.TaxTypeRegistrationBinding,
        obligation.tax_type_registration_bindings,
    );
    errdefer allocator.free(tax_type_registration_bindings);
    const reviewed_evidence_bindings = try allocator.dupe(
        planner.ReviewedEvidenceBinding,
        obligation.reviewed_evidence_bindings,
    );
    errdefer allocator.free(reviewed_evidence_bindings);
    const facility_revision_ids = try allocator.dupe(
        planner.RegisteredFacilityRevisionId,
        obligation.facility_revision_ids,
    );
    errdefer allocator.free(facility_revision_ids);
    const policy_evidence_ids = try allocator.dupe(policy.PolicyEvidenceId, obligation.policy_evidence_ids);
    errdefer allocator.free(policy_evidence_ids);

    return .{
        .decision_schema_version = obligation.decision_schema_version,
        .taxpayer_identity = obligation.taxpayer_identity,
        .form_revision = obligation.form_revision,
        .civil_period = obligation.civil_period,
        .filing_unit_id = obligation.filing_unit_id,
        .filing_unit_revision_id = obligation.filing_unit_revision_id,
        .filing_branch_code = obligation.filing_branch_code,
        .filing_branch_evidence_id = obligation.filing_branch_evidence_id,
        .filing_unit_rdo_code = obligation.filing_unit_rdo_code,
        .filing_unit_contact = obligation.filing_unit_contact,
        .coverage = coverage,
        .tax_type_registration_bindings = tax_type_registration_bindings,
        .reviewed_evidence_bindings = reviewed_evidence_bindings,
        .lts_revision_id = obligation.lts_revision_id,
        .facility_revision_ids = facility_revision_ids,
        .source_attribution_requirement = obligation.source_attribution_requirement,
        .policy_revision_id = obligation.policy_revision_id,
        .policy_evidence_ids = policy_evidence_ids,
        .special_context_digest = obligation.special_context_digest,
        .policy_capability = obligation.policy_capability,
        .filing_capability = obligation.filing_capability,
        .filing_venue_resolution = obligation.filing_venue_resolution,
        .resolution_hash = obligation.resolution_hash,
    };
}

fn validateObligation(obligation: *const planner.FilingObligation) ScopeError!void {
    if (obligation.decision_schema_version != decision_schema_version) {
        return error.UnsupportedDecisionSchemaVersion;
    }
    if (!obligation.taxpayer_identity.taxpayer_id.isPresent() or
        !obligation.taxpayer_identity.id.isPresent())
    {
        return error.MissingTaxpayerIdentity;
    }
    obligation.taxpayer_identity.validate() catch {
        return error.InvalidTaxpayerIdentity;
    };
    if (obligation.taxpayer_identity.evidence_id) |evidence_id| {
        if (!evidence_id.isPresent()) return error.InvalidTaxpayerIdentity;
    }
    if (!obligation.form_revision.isValid()) return error.InvalidFormRevision;
    if (!isValidCivilPeriod(obligation.civil_period)) return error.InvalidCivilPeriod;
    if (!effectiveCovers(
        obligation.taxpayer_identity.effective,
        obligation.civil_period,
    )) {
        return error.TaxpayerIdentityNotEffective;
    }
    if (!obligation.filing_unit_id.isPresent() or !obligation.filing_unit_revision_id.isPresent()) {
        return error.MissingFilingUnit;
    }
    if (!isBranchCode(obligation.filing_branch_code)) return error.InvalidFilingBranchCode;
    if (!obligation.filing_branch_evidence_id.isPresent()) {
        return error.MissingFilingBranchEvidence;
    }
    obligation.filing_unit_contact.validate() catch {
        return error.InvalidFilingUnitContact;
    };
    if (!obligation.filing_unit_contact.taxpayer_id.eql(
        &obligation.taxpayer_identity.taxpayer_id,
    ) or !obligation.filing_unit_contact.registration_unit_id.eql(
        &obligation.filing_unit_id,
    )) {
        return error.FilingUnitContactMismatch;
    }
    if (!effectiveCovers(
        obligation.filing_unit_contact.effective,
        obligation.civil_period,
    )) {
        return error.FilingUnitContactNotEffective;
    }
    if (obligation.policy_revision_id.isEmpty()) return error.MissingPolicyRevision;

    try validateCoverage(obligation);
    try validateTaxTypeRegistrationBindings(obligation);
    try validateReviewedEvidenceBindings(obligation);
    try validatePolicyContextBindings(obligation);
    try validatePolicyEvidence(obligation.policy_evidence_ids);
    if (!planner.verifyResolutionHash(obligation)) return error.ResolutionHashMismatch;
}

fn isValidCivilPeriod(civil_period: planner.CivilPeriod) bool {
    civil_period.validate() catch return false;
    return true;
}

fn effectiveCovers(
    effective: registration.EffectivePeriod,
    period: planner.CivilPeriod,
) bool {
    if (effective.from.isAfter(period.from)) return false;
    if (effective.until) |until| {
        if (until.isBefore(period.until)) return false;
    }
    return true;
}

fn isBranchCode(code: registration.BranchCode5) bool {
    const digits = code.asDigits();
    if (digits.len != 5) return false;
    for (digits) |digit| {
        if (!std.ascii.isDigit(digit)) return false;
    }
    return true;
}

fn validateCoverage(obligation: *const planner.FilingObligation) ScopeError!void {
    if (obligation.coverage.len == 0) return error.EmptyCoverage;

    var filing_unit_count: usize = 0;
    for (obligation.coverage, 0..) |coverage, index| {
        if (!coverage.registration_unit_id.isPresent() or
            !coverage.registration_unit_revision_id.isPresent() or
            !coverage.branch_code_evidence_id.isPresent() or
            !isBranchCode(coverage.branch_code))
        {
            return error.InvalidCoverage;
        }

        for (obligation.coverage[0..index]) |previous| {
            if (coverage.registration_unit_id.eql(&previous.registration_unit_id)) {
                return error.DuplicateCoverage;
            }
        }
        if (index > 0 and !coverageLessThan(obligation.coverage[index - 1], coverage)) {
            return error.NonCanonicalCoverage;
        }

        if (coverage.registration_unit_id.eql(&obligation.filing_unit_id)) {
            filing_unit_count += 1;
            if (!coverage.registration_unit_revision_id.eql(&obligation.filing_unit_revision_id) or
                !coverage.branch_code.eql(&obligation.filing_branch_code) or
                !coverage.branch_code_evidence_id.eql(&obligation.filing_branch_evidence_id))
            {
                return error.FilingUnitCoverageMismatch;
            }
        }
    }

    if (filing_unit_count != 1) return error.FilingUnitNotCovered;
}

fn coverageLessThan(
    left: planner.RegistrationUnitCoverage,
    right: planner.RegistrationUnitCoverage,
) bool {
    const unit_order = std.mem.order(
        u8,
        left.registration_unit_id.asSlice(),
        right.registration_unit_id.asSlice(),
    );
    if (unit_order != .eq) return unit_order == .lt;
    return std.mem.order(
        u8,
        left.registration_unit_revision_id.asSlice(),
        right.registration_unit_revision_id.asSlice(),
    ) == .lt;
}

fn validateTaxTypeRegistrationBindings(
    obligation: *const planner.FilingObligation,
) ScopeError!void {
    const bindings = obligation.tax_type_registration_bindings;
    if (bindings.len == 0) return error.EmptyTaxTypeRegistrationBindings;

    for (bindings, 0..) |binding, index| {
        if (!binding.registration_unit_id.isPresent() or
            !binding.registration_id.isPresent() or
            !binding.revision_id.isPresent() or
            !binding.evidence_id.isPresent() or
            binding.status != .confirmed_active or
            !effectiveCovers(binding.effective, obligation.civil_period))
        {
            return error.InvalidTaxTypeRegistrationBinding;
        }
        if (!coverageContainsUnit(obligation.coverage, binding.registration_unit_id)) {
            return error.TaxTypeRegistrationBindingNotCovered;
        }
        for (bindings[0..index]) |previous| {
            if (binding.registration_id.eql(&previous.registration_id) or
                binding.revision_id.eql(&previous.revision_id))
            {
                return error.DuplicateTaxTypeRegistrationBinding;
            }
        }
        if (index > 0 and !taxTypeRegistrationBindingLess(bindings[index - 1], binding)) {
            return error.NonCanonicalTaxTypeRegistrationBinding;
        }
    }

    const exact_2550q = policy.FormRevisionKey.initComptime("2550Q", "2024-04-ENCS");
    if (obligation.form_revision.eql(&exact_2550q)) {
        if (bindings.len != 1 or
            bindings[0].tax_type != .vat or
            !bindings[0].registration_unit_id.eql(&obligation.filing_unit_id))
        {
            return error.Invalid2550QVatBinding;
        }
    }
}

fn validateReviewedEvidenceBindings(obligation: *const planner.FilingObligation) ScopeError!void {
    const bindings = obligation.reviewed_evidence_bindings;
    if (bindings.len == 0) return error.EmptyReviewedEvidenceBindings;

    var taxpayer_binding_count: usize = 0;
    var contact_binding_count: usize = 0;
    for (bindings, 0..) |binding, index| {
        if (!binding.isValid()) return error.InvalidReviewedEvidenceBinding;
        for (bindings[0..index]) |previous| {
            if (std.meta.activeTag(previous.subject) == std.meta.activeTag(binding.subject) and
                std.mem.eql(u8, previous.subject.idBytes(), binding.subject.idBytes()))
            {
                return error.DuplicateReviewedEvidenceBinding;
            }
        }
        if (index > 0 and !evidence_binding.lessThan(
            bindings[index - 1],
            binding,
        )) {
            return error.NonCanonicalReviewedEvidenceBinding;
        }

        switch (binding.subject) {
            .taxpayer_identity_revision => |revision_id| {
                if (!revision_id.eql(&obligation.taxpayer_identity.id) or
                    obligation.taxpayer_identity.evidence_id == null or
                    !binding.evidence_id.eql(&obligation.taxpayer_identity.evidence_id.?))
                {
                    return error.ReviewedEvidenceBindingMismatch;
                }
                taxpayer_binding_count += 1;
            },
            .registration_unit_branch_code_revision => |revision_id| {
                const coverage = coverageForRevision(obligation.coverage, revision_id) orelse
                    return error.ReviewedEvidenceBindingMismatch;
                if (!binding.evidence_id.eql(&coverage.branch_code_evidence_id)) {
                    return error.ReviewedEvidenceBindingMismatch;
                }
            },
            .registration_unit_lifecycle_revision => |revision_id| {
                _ = coverageForRevision(obligation.coverage, revision_id) orelse
                    return error.ReviewedEvidenceBindingMismatch;
            },
            .registration_unit_contact_revision => |revision_id| {
                if (!revision_id.eql(&obligation.filing_unit_contact.id) or
                    !binding.evidence_id.eql(&obligation.filing_unit_contact.evidence_id))
                {
                    return error.ReviewedEvidenceBindingMismatch;
                }
                contact_binding_count += 1;
            },
            .tax_type_registration_revision => |revision_id| {
                const registration_binding = taxBindingForRevision(
                    obligation.tax_type_registration_bindings,
                    revision_id,
                ) orelse return error.ReviewedEvidenceBindingMismatch;
                if (!binding.evidence_id.eql(&registration_binding.evidence_id)) {
                    return error.ReviewedEvidenceBindingMismatch;
                }
            },
        }
    }

    if (taxpayer_binding_count != 1 or contact_binding_count != 1) {
        return error.MissingReviewedEvidenceBinding;
    }
    for (obligation.coverage) |coverage| {
        if (!hasEvidenceSubject(
            bindings,
            .registration_unit_branch_code_revision,
            coverage.registration_unit_revision_id.asSlice(),
        ) or !hasEvidenceSubject(
            bindings,
            .registration_unit_lifecycle_revision,
            coverage.registration_unit_revision_id.asSlice(),
        )) return error.MissingReviewedEvidenceBinding;
    }
    for (obligation.tax_type_registration_bindings) |binding| {
        if (!hasEvidenceSubject(
            bindings,
            .tax_type_registration_revision,
            binding.revision_id.asSlice(),
        )) return error.MissingReviewedEvidenceBinding;
    }
}

fn coverageForRevision(
    coverage_values: []const planner.RegistrationUnitCoverage,
    revision_id: registration.RegistrationUnitRevisionId,
) ?*const planner.RegistrationUnitCoverage {
    for (coverage_values) |*coverage| {
        if (revision_id.eql(&coverage.registration_unit_revision_id)) return coverage;
    }
    return null;
}

fn taxBindingForRevision(
    bindings: []const planner.TaxTypeRegistrationBinding,
    revision_id: registration.TaxTypeRegistrationRevisionId,
) ?*const planner.TaxTypeRegistrationBinding {
    for (bindings) |*binding| {
        if (revision_id.eql(&binding.revision_id)) return binding;
    }
    return null;
}

fn hasEvidenceSubject(
    bindings: []const planner.ReviewedEvidenceBinding,
    tag: std.meta.Tag(planner.EvidenceFactSubject),
    id_bytes: []const u8,
) bool {
    for (bindings) |binding| {
        if (std.meta.activeTag(binding.subject) == tag and
            std.mem.eql(u8, binding.subject.idBytes(), id_bytes)) return true;
    }
    return false;
}

fn validatePolicyContextBindings(obligation: *const planner.FilingObligation) ScopeError!void {
    if (obligation.lts_revision_id) |lts_revision_id| {
        if (lts_revision_id.isEmpty()) return error.InvalidLtsRevisionBinding;
    }

    for (obligation.facility_revision_ids, 0..) |facility_revision_id, index| {
        if (facility_revision_id.isEmpty()) return error.InvalidFacilityRevisionBinding;
        for (obligation.facility_revision_ids[0..index]) |previous| {
            if (facility_revision_id.eql(&previous)) {
                return error.DuplicateFacilityRevisionBinding;
            }
        }
        if (index > 0 and std.mem.order(
            u8,
            obligation.facility_revision_ids[index - 1].asSlice(),
            facility_revision_id.asSlice(),
        ) != .lt) {
            return error.NonCanonicalFacilityRevisionBinding;
        }
    }

    if (obligation.special_context_digest) |digest| {
        var any_nonzero = false;
        for (digest) |byte| any_nonzero = any_nonzero or byte != 0;
        if (!any_nonzero) return error.InvalidSpecialContextDigest;
    }
    if (obligation.filing_venue_resolution == .review_required) {
        return error.FilingVenueReviewRequired;
    }

    const exact_2550q = policy.FormRevisionKey.initComptime("2550Q", "2024-04-ENCS");
    if (obligation.form_revision.eql(&exact_2550q) and
        (obligation.civil_period.kind != .calendar_quarter or
            obligation.lts_revision_id != null or
            obligation.facility_revision_ids.len != 0 or
            obligation.source_attribution_requirement != .not_required or
            obligation.special_context_digest != null or
            obligation.filing_venue_resolution != .not_resolved_by_scope))
    {
        return error.Invalid2550QContextBindings;
    }
}

fn coverageContainsUnit(
    coverage: []const planner.RegistrationUnitCoverage,
    registration_unit_id: registration.RegistrationUnitId,
) bool {
    for (coverage) |value| {
        if (registration_unit_id.eql(&value.registration_unit_id)) return true;
    }
    return false;
}

fn taxTypeRegistrationBindingLess(
    left: planner.TaxTypeRegistrationBinding,
    right: planner.TaxTypeRegistrationBinding,
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

fn validatePolicyEvidence(evidence_ids: []const policy.PolicyEvidenceId) ScopeError!void {
    if (evidence_ids.len == 0) return error.EmptyPolicyEvidence;

    for (evidence_ids, 0..) |evidence_id, index| {
        if (evidence_id.isEmpty()) return error.EmptyPolicyEvidence;
        for (evidence_ids[0..index]) |previous| {
            if (evidence_id.eql(&previous)) return error.DuplicatePolicyEvidence;
        }
        if (index > 0 and std.mem.order(
            u8,
            evidence_ids[index - 1].asSlice(),
            evidence_id.asSlice(),
        ) != .lt) {
            return error.NonCanonicalPolicyEvidence;
        }
    }
}

fn testId(comptime Id: type, raw: []const u8) Id {
    return Id.parse(raw) catch unreachable;
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

fn testIdentity() registration.TaxpayerIdentityRevision {
    return .{
        .taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a"),
        .id = testId(registration.TaxpayerRevisionId, "taxpayer-rev-a"),
        .sequence = 1,
        .effective = testPeriod(testDate(2024, 1, 1), null),
        .tin_root = registration.Tin9.parse("123456789") catch unreachable,
        .evidence_id = testId(
            registration.RegistrationEvidenceId,
            "evidence-taxpayer-tin",
        ),
    };
}

fn confirmedUnit(
    unit_id: registration.RegistrationUnitId,
    revision_id: registration.RegistrationUnitRevisionId,
    kind: registration.RegistrationUnitKind,
    code: []const u8,
    evidence_id: registration.RegistrationEvidenceId,
) registration.RegistrationUnitRevision {
    return .{
        .taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a"),
        .registration_unit_id = unit_id,
        .id = revision_id,
        .sequence = 1,
        .effective = testPeriod(testDate(2024, 1, 1), null),
        .kind = kind,
        .branch_code_evidence = .{ .confirmed = .{
            .code = registration.BranchCode5.parse(code) catch unreachable,
            .evidence_id = evidence_id,
        } },
        .status = .confirmed_active,
        .lifecycle_evidence_id = evidence_id,
        .rdo_code = if (kind == .head_office)
            registration.RdoCode3.parse("047") catch unreachable
        else
            null,
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

fn testResolvedPlan(allocator: std.mem.Allocator) !planner.ResolvedFilingPlan {
    const revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = planner.FilingPlanner.init(.{ .revisions = &revisions });
    const head_id = testId(registration.RegistrationUnitId, "unit-head");
    const branch_id = testId(registration.RegistrationUnitId, "unit-branch");
    const units = [_]registration.RegistrationUnitRevision{
        confirmedUnit(
            head_id,
            testId(registration.RegistrationUnitRevisionId, "unit-head-rev-a"),
            .head_office,
            "00000",
            testId(registration.RegistrationEvidenceId, "branch-evidence-head"),
        ),
        confirmedUnit(
            branch_id,
            testId(registration.RegistrationUnitRevisionId, "unit-branch-rev-a"),
            .branch,
            "00001",
            testId(registration.RegistrationEvidenceId, "branch-evidence-branch"),
        ),
    };
    const contacts = [_]registration.RegistrationUnitContactRevision{
        validContact(head_id),
    };
    const vat = [_]registration.TaxTypeRegistrationRevision{.{
        .taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a"),
        .registration_unit_id = head_id,
        .registration_id = testId(
            registration.TaxTypeRegistrationId,
            "vat-registration-a",
        ),
        .id = testId(
            registration.TaxTypeRegistrationRevisionId,
            "vat-registration-revision-a",
        ),
        .sequence = 1,
        .tax_type = .vat,
        .status = .confirmed_active,
        .effective = testPeriod(testDate(2024, 1, 1), null),
        .evidence_id = testId(registration.RegistrationEvidenceId, "vat-evidence-a"),
    }};

    return planner.testing.planForSnapshot(filing_planner, allocator, .{
        .taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a"),
        .form_revision = policy.FormRevisionKey.initComptime("2550Q", "2024-04-ENCS"),
        .civil_period = planner.CivilPeriod.init(
            testDate(2024, 4, 1),
            testDate(2024, 6, 30),
        ) catch unreachable,
    }, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
}

test "scope provenance copies one verified planner obligation" {
    const allocator = std.testing.allocator;
    var plan = try testResolvedPlan(allocator);
    defer plan.deinit(allocator);

    switch (plan) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            try std.testing.expectEqual(@as(usize, 1), obligations.len);
            const obligation = &obligations[0];
            var scope = try ScopeProvenance.capture(allocator, obligation);
            defer scope.deinit(allocator);

            try scope.validate();
            try std.testing.expect(scope.taxpayer_identity.id.eql(
                &obligation.taxpayer_identity.id,
            ));
            try std.testing.expectEqual(
                obligation.taxpayer_identity.sequence,
                scope.taxpayer_identity.sequence,
            );
            try std.testing.expectEqual(
                obligation.taxpayer_identity.effective,
                scope.taxpayer_identity.effective,
            );
            try std.testing.expectEqual(decision_schema_version, scope.decision_schema_version);
            try std.testing.expect(scope.coverage.ptr != obligation.coverage.ptr);
            try std.testing.expect(
                scope.tax_type_registration_bindings.ptr != obligation.tax_type_registration_bindings.ptr,
            );
            try std.testing.expect(
                scope.reviewed_evidence_bindings.ptr !=
                    obligation.reviewed_evidence_bindings.ptr,
            );
            try std.testing.expectEqual(
                obligation.reviewed_evidence_bindings.len,
                scope.reviewed_evidence_bindings.len,
            );
            try std.testing.expectEqual(obligation.lts_revision_id, scope.lts_revision_id);
            try std.testing.expectEqual(
                obligation.facility_revision_ids.len,
                scope.facility_revision_ids.len,
            );
            try std.testing.expectEqual(
                planner.SourceAttributionRequirement.not_required,
                scope.source_attribution_requirement,
            );
            try std.testing.expect(scope.policy_evidence_ids.ptr != obligation.policy_evidence_ids.ptr);
            try std.testing.expectEqual(obligation.special_context_digest, scope.special_context_digest);
            try std.testing.expectEqual(
                planner.FilingVenueResolution.not_resolved_by_scope,
                scope.filing_venue_resolution,
            );
            try std.testing.expectEqualSlices(
                u8,
                &scope.resolution_hash,
                &obligation.resolution_hash,
            );
        },
    }
}

test "scope provenance retains exact RDO and contact revision facts" {
    const allocator = std.testing.allocator;
    var plan = try testResolvedPlan(allocator);
    defer plan.deinit(allocator);

    switch (plan) {
        .review_required, .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            var scope = try ScopeProvenance.capture(allocator, &obligations[0]);
            defer scope.deinit(allocator);

            try std.testing.expectEqualStrings(
                "047",
                scope.filing_unit_rdo_code.?.asDigits(),
            );
            try std.testing.expectEqualStrings(
                "unit-contact-revision-a",
                scope.filing_unit_contact.id.asSlice(),
            );
            try std.testing.expectEqual(@as(u32, 1), scope.filing_unit_contact.sequence);
            try std.testing.expectEqual(
                testPeriod(testDate(2024, 1, 1), null),
                scope.filing_unit_contact.effective,
            );
            try std.testing.expectEqualStrings(
                "100 Example Street",
                scope.filing_unit_contact.contact.registered_address.asSlice(),
            );
            try std.testing.expectEqualStrings(
                "1000",
                scope.filing_unit_contact.contact.zip_code.?.asSlice(),
            );
            try std.testing.expectEqualStrings(
                "+639171234567",
                scope.filing_unit_contact.contact.contact_number.?.asSlice(),
            );
            try std.testing.expectEqualStrings(
                "filing-unit@example.test",
                scope.filing_unit_contact.contact.email_address.?.asSlice(),
            );
            try std.testing.expectEqualStrings(
                "unit-contact-evidence-a",
                scope.filing_unit_contact.evidence_id.asSlice(),
            );
        },
    }
}

test "scope provenance validates the bound taxpayer identity semantics" {
    const allocator = std.testing.allocator;
    var plan = try testResolvedPlan(allocator);
    defer plan.deinit(allocator);

    switch (plan) {
        .review_required, .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            const obligation = &obligations[0];
            const original_identity = obligation.taxpayer_identity;

            obligation.taxpayer_identity.sequence = 0;
            try std.testing.expectError(
                error.InvalidTaxpayerIdentity,
                ScopeProvenance.capture(allocator, obligation),
            );
            obligation.taxpayer_identity = original_identity;

            obligation.taxpayer_identity.effective = testPeriod(
                testDate(2025, 1, 1),
                null,
            );
            try std.testing.expectError(
                error.TaxpayerIdentityNotEffective,
                ScopeProvenance.capture(allocator, obligation),
            );
            obligation.taxpayer_identity = original_identity;

            obligation.taxpayer_identity.evidence_id = .{};
            try std.testing.expectError(
                error.InvalidTaxpayerIdentity,
                ScopeProvenance.capture(allocator, obligation),
            );
            obligation.taxpayer_identity = original_identity;
        },
    }
}

test "scope provenance deep-copies every policy-context binding" {
    const allocator = std.testing.allocator;
    var plan = try testResolvedPlan(allocator);
    defer plan.deinit(allocator);

    switch (plan) {
        .review_required, .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            var enriched = obligations[0];
            const facilities = [_]planner.RegisteredFacilityRevisionId{
                try planner.RegisteredFacilityRevisionId.parse("facility-revision-a"),
                try planner.RegisteredFacilityRevisionId.parse("facility-revision-b"),
            };
            enriched.lts_revision_id = try planner.LargeTaxpayerServiceRevisionId.parse("lts-revision-a");
            enriched.facility_revision_ids = &facilities;
            enriched.source_attribution_requirement = .required;
            enriched.special_context_digest = [_]u8{0xA5} ** 32;
            enriched.filing_venue_resolution = .review_required;

            var scope = try copyObligation(allocator, &enriched);
            defer scope.deinit(allocator);
            try std.testing.expect(scope.lts_revision_id.?.eql(&enriched.lts_revision_id.?));
            try std.testing.expectEqual(@as(usize, 2), scope.facility_revision_ids.len);
            try std.testing.expect(scope.facility_revision_ids.ptr != enriched.facility_revision_ids.ptr);
            try std.testing.expect(scope.facility_revision_ids[0].eql(&facilities[0]));
            try std.testing.expectEqual(
                planner.SourceAttributionRequirement.required,
                scope.source_attribution_requirement,
            );
            try std.testing.expectEqual(enriched.special_context_digest, scope.special_context_digest);
            try std.testing.expectEqual(
                planner.FilingVenueResolution.review_required,
                scope.filing_venue_resolution,
            );
        },
    }
}

test "scope provenance validates context bindings and exact 2550Q absences" {
    const allocator = std.testing.allocator;
    var plan = try testResolvedPlan(allocator);
    defer plan.deinit(allocator);

    switch (plan) {
        .review_required, .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            const obligation = &obligations[0];

            obligation.lts_revision_id = .{};
            try std.testing.expectError(
                error.InvalidLtsRevisionBinding,
                ScopeProvenance.capture(allocator, obligation),
            );
            obligation.lts_revision_id = null;

            {
                const original_facilities = obligation.facility_revision_ids;
                defer obligation.facility_revision_ids = original_facilities;
                const noncanonical = [_]planner.RegisteredFacilityRevisionId{
                    try planner.RegisteredFacilityRevisionId.parse("facility-revision-b"),
                    try planner.RegisteredFacilityRevisionId.parse("facility-revision-a"),
                };
                obligation.facility_revision_ids = &noncanonical;
                try std.testing.expectError(
                    error.NonCanonicalFacilityRevisionBinding,
                    ScopeProvenance.capture(allocator, obligation),
                );
            }

            obligation.special_context_digest = [_]u8{0} ** 32;
            try std.testing.expectError(
                error.InvalidSpecialContextDigest,
                ScopeProvenance.capture(allocator, obligation),
            );
            obligation.special_context_digest = null;

            obligation.filing_venue_resolution = .review_required;
            try std.testing.expectError(
                error.FilingVenueReviewRequired,
                ScopeProvenance.capture(allocator, obligation),
            );
            obligation.filing_venue_resolution = .not_resolved_by_scope;

            obligation.lts_revision_id = try planner.LargeTaxpayerServiceRevisionId.parse("lts-revision-a");
            try std.testing.expectError(
                error.Invalid2550QContextBindings,
                ScopeProvenance.capture(allocator, obligation),
            );
            obligation.lts_revision_id = null;

            obligation.source_attribution_requirement = .required;
            try std.testing.expectError(
                error.Invalid2550QContextBindings,
                ScopeProvenance.capture(allocator, obligation),
            );
            obligation.source_attribution_requirement = .not_required;

            obligation.civil_period.kind = .date_range;
            try std.testing.expectError(
                error.Invalid2550QContextBindings,
                ScopeProvenance.capture(allocator, obligation),
            );
            obligation.civil_period.kind = .calendar_quarter;
        },
    }
}

test "scope provenance rejects duplicate coverage before retaining it" {
    const allocator = std.testing.allocator;
    var plan = try testResolvedPlan(allocator);
    defer plan.deinit(allocator);

    switch (plan) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            try std.testing.expectEqual(@as(usize, 1), obligations.len);
            const obligation = &obligations[0];
            const coverage = @constCast(obligation.coverage);
            coverage[1].registration_unit_id = coverage[0].registration_unit_id;
            try std.testing.expectError(
                error.DuplicateCoverage,
                ScopeProvenance.capture(allocator, obligation),
            );
        },
    }
}

test "scope provenance refuses a not-fileable plan at draft preparation" {
    const allocator = std.testing.allocator;
    var plan = try testResolvedPlan(allocator);
    defer plan.deinit(allocator);

    switch (plan) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            try std.testing.expectEqual(@as(usize, 1), obligations.len);
            const obligation = &obligations[0];
            try std.testing.expectError(
                error.NotFileable,
                prepareDraftScope(allocator, obligation),
            );
        },
    }
}

test "scope provenance rejects a changed resolution hash" {
    const allocator = std.testing.allocator;
    var plan = try testResolvedPlan(allocator);
    defer plan.deinit(allocator);

    switch (plan) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            try std.testing.expectEqual(@as(usize, 1), obligations.len);
            const obligation = &obligations[0];
            obligation.resolution_hash[0] ^= 0xff;
            try std.testing.expectError(
                error.ResolutionHashMismatch,
                ScopeProvenance.capture(allocator, obligation),
            );
        },
    }
}

test "scope provenance rejects a tax registration binding outside return coverage" {
    const allocator = std.testing.allocator;
    var plan = try testResolvedPlan(allocator);
    defer plan.deinit(allocator);

    switch (plan) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            try std.testing.expectEqual(@as(usize, 1), obligations.len);
            const obligation = &obligations[0];
            const bindings = @constCast(obligation.tax_type_registration_bindings);
            bindings[0].registration_unit_id = testId(
                registration.RegistrationUnitId,
                "uncovered-registration-unit",
            );
            try std.testing.expectError(
                error.TaxTypeRegistrationBindingNotCovered,
                ScopeProvenance.capture(allocator, obligation),
            );
        },
    }
}
