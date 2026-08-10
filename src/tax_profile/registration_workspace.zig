//! Registration-unit workspace presentation and action state.
//!
//! The workspace owns no database. Callers provide the v28 registration
//! ledger to each load or write operation. Taxpayer and Registration Unit
//! selections are workspace presentation state only. A Registration Unit
//! selection is neither evidence-backed Source Attribution nor a Filing Unit.

const std = @import("std");
const registration = @import("registration_domain.zig");
const registration_ledger = @import("registration_ledger.zig");
const storage_contract = @import("registration_storage_contract.zig");
const registration_ui = @import("registration_ui.zig");
const source_attribution = @import("source_attribution.zig");
const profile_field = @import("field.zig");
const planner = @import("../filing/planner.zig");
const policy = @import("../filing/policy.zig");
const projection = @import("../filing/projection_context.zig");
const provenance = @import("../filing/scope_provenance.zig");

pub const EvidenceSourceKind = registration_ledger.EvidenceSourceKind;
pub const SourceRecord = source_attribution.SourceRecord;
pub const SourceRecordId = source_attribution.SourceRecordId;
pub const SourceAttribution = source_attribution.Attribution;
pub const SourceUnitBinding = source_attribution.SourceUnitBinding;
pub const SourceEvidenceReference = source_attribution.EvidenceReference;
pub const SourceDerivationRuleId = source_attribution.DerivationRuleId;
pub const SourceLegacyUnknownReason = source_attribution.LegacyUnknownReason;

pub const max_taxpayers: usize = 64;
pub const max_units: usize = 64;
pub const max_source_records: usize = 64;
pub const max_coverage_units: usize = 64;
pub const max_review_reasons: usize = 48;
pub const max_occupied_branch_codes: usize = 128;
pub const max_reviewed_evidence_rows: usize = max_units * 4;
pub const max_policy_evidence_rows: usize = 8;
const max_policy_evidence_display_name_bytes: usize = 160;
const max_policy_evidence_review_basis_bytes: usize = 512;

const production_policy_revisions = [_]policy.FilingPolicyRevision{};

/// Production has no persisted, reviewed policy catalog yet. Keeping this
/// catalog explicitly empty makes `FilingPlanner.plan` return Review Required
/// instead of promoting the test-only 2550Q fixture into production.
pub const production_policy_catalog: policy.FilingPolicyCatalog = .{
    .revisions = &production_policy_revisions,
};

/// Selects the isolated preview catalog only after the caller has enforced
/// the explicit fixture-preview environment and data-directory gates.
/// Production remains fail closed because its catalog is intentionally empty.
pub const PolicyCatalogAccess = enum {
    production_fail_closed,
    isolated_fixture_preview,
};

pub fn policyCatalog(access: PolicyCatalogAccess) policy.FilingPolicyCatalog {
    return switch (access) {
        .production_fail_closed => production_policy_catalog,
        .isolated_fixture_preview => policy.isolated_fixture_preview.catalog2550Q(),
    };
}

pub const requested_preview_form_revision = policy.FormRevisionKey.initComptime(
    "2550Q",
    "2024-04-ENCS",
);

pub const WorkspaceStatus = enum {
    no_data,
    pending_evidence,
    confirmed_active,
    confirmed_closed,
    legacy_unresolved,
    review_required,
};

pub const PlanningStatus = enum {
    unavailable,
    review_required,
    not_applicable,
    resolved_not_fileable,
    resolved_fileable,
    integration_error,
};

pub const IntegrationReason = enum {
    none,
    invalid_preview_period,
    taxpayer_list_truncated,
    unit_list_truncated,
    review_issue_capacity_exceeded,
    unexpected_obligation_count,
    coverage_capacity_exceeded,
    reviewed_evidence_capacity_exceeded,
    policy_evidence_capacity_exceeded,
    policy_evidence_metadata_unavailable,
    projection_context_invalid,
    provenance_validation_failed,
    filer_identity_projection_failed,
    workspace_load_failed,
};

pub const ResolvedScopeCategory = enum {
    head_office_consolidated,
};

pub const VatRegistrationState = enum {
    absent,
    confirmed_active,
    requires_review,
};

pub const ActionStatus = enum {
    none,
    taxpayer_created,
    branch_created,
    unit_confirmed,
    vat_registration_recorded,
    invalid_tin_root,
    invalid_observed_tin_root,
    observed_tin_root_mismatch,
    invalid_effective_date,
    effective_date_must_advance,
    invalid_branch_code,
    invalid_rdo_code,
    invalid_registered_address,
    invalid_zip_code,
    invalid_contact_number,
    invalid_email_address,
    evidence_source_required,
    invalid_evidence_date,
    invalid_evidence_path,
    invalid_evidence_name,
    invalid_evidence_digest,
    invalid_evidence_size,
    vat_registration_requires_head_office,
    vat_registration_not_recordable,
    vat_registration_already_exists,
    vat_registration_assertion_required,
    no_taxpayer_selected,
    no_registration_unit_selected,
    taxpayer_capacity_reached,
    registration_unit_capacity_reached,
    registration_unit_not_reviewable,
    review_time_unavailable,
    load_failed,
    write_failed,

    pub fn label(self: ActionStatus) []const u8 {
        return switch (self) {
            .none => "",
            .taxpayer_created => "Taxpayer created with a pending-evidence head office (00000).",
            .branch_created => "Pending branch created. Its candidate code is not BIR confirmation.",
            .unit_confirmed => "Reviewed evidence recorded. The unit is active on its effective date.",
            .vat_registration_recorded => "Reviewed VAT registration evidence recorded for the confirmed head office.",
            .invalid_tin_root => "Enter exactly the nine-digit taxpayer TIN root.",
            .invalid_observed_tin_root => "Enter the exact nine-digit taxpayer TIN shown on the reviewed evidence.",
            .observed_tin_root_mismatch => "Review Required — the taxpayer TIN on the reviewed evidence does not match the selected taxpayer. No change was saved.",
            .invalid_effective_date => "Enter a valid effective date as YYYY-MM-DD.",
            .effective_date_must_advance => "The effective date cannot be earlier than the current revision; the same date is allowed and superseded by append sequence.",
            .invalid_branch_code => "Enter the exact five-digit BIR Branch Code.",
            .invalid_rdo_code => "RDO must be empty or exactly three digits.",
            .invalid_registered_address => "Enter the registered address shown by the reviewed BIR evidence.",
            .invalid_zip_code => "ZIP code must be empty or exactly four digits.",
            .invalid_contact_number => "Enter a valid contact number or leave it empty.",
            .invalid_email_address => "Enter a valid email address or leave it empty.",
            .evidence_source_required => "Choose whether the reviewed evidence is a COR, eCOR, or another reviewed BIR registration record.",
            .invalid_evidence_date => "Enter a valid evidence capture date as YYYY-MM-DD.",
            .invalid_evidence_path => "Choose the reviewed PDF, PNG, or JPEG evidence file.",
            .invalid_evidence_name => "Enter the reviewed evidence document name.",
            .invalid_evidence_digest => "Enter the evidence file's complete 64-character SHA-256 digest.",
            .invalid_evidence_size => "Enter the evidence file size in bytes.",
            .vat_registration_requires_head_office => "An active VAT registration can be recorded in this slice only for the reviewed head office. No change was saved.",
            .vat_registration_not_recordable => "Select the confirmed-active head office with no VAT registration. Existing or conflicting VAT history requires a separate revision review.",
            .vat_registration_already_exists => "A VAT registration shell already exists for this head office. Use a future reviewed revision workflow; no duplicate was created.",
            .vat_registration_assertion_required => "Explicitly confirm that the reviewed evidence records an active VAT registration.",
            .no_taxpayer_selected => "Select a taxpayer first.",
            .no_registration_unit_selected => "Select a Registration Unit first.",
            .taxpayer_capacity_reached => "This preview can show at most 64 Taxpayers. No Taxpayer was created; review or migrate the existing records first.",
            .registration_unit_capacity_reached => "This preview can show at most 64 Registration Units. No branch was created; review or migrate the existing records first.",
            .registration_unit_not_reviewable => "Only a pending-evidence or legacy-unresolved Registration Unit can be reviewed here.",
            .review_time_unavailable => "The review time could not be recorded. No evidence decision or Registration Unit change was saved.",
            .load_failed => "Registration data could not be loaded. Refresh and try again; no change was saved.",
            .write_failed => "The registration ledger rejected the change. Refresh and review the evidence and effective date.",
        };
    }
};

pub const ActionContext = enum {
    none,
    taxpayer,
    branch,
    unit_confirmation,
    vat_registration,
};

pub const TaxpayerRow = struct {
    id: usize,
    taxpayer_id: registration.TaxpayerId,
    masked_tin: [11]u8 = "***-***-***".*,
    status: WorkspaceStatus = .review_required,
    selected: bool = false,

    pub fn maskedTin(self: *const TaxpayerRow) []const u8 {
        return &self.masked_tin;
    }

    /// Deterministic within the current ID-sorted workspace list and does not
    /// reveal any additional TIN digits or opaque persistence identifiers.
    pub fn displayOrdinal(self: *const TaxpayerRow) usize {
        return self.id + 1;
    }

    /// Stable widget identity across list insertions and reordering. This key
    /// is consumed by Native markup only and is never rendered or announced.
    pub fn stableKey(self: *const TaxpayerRow) []const u8 {
        return self.taxpayer_id.asSlice();
    }

    pub fn visibleLabel(
        self: *const TaxpayerRow,
        allocator: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            allocator,
            "Taxpayer {d} · {s}",
            .{ self.displayOrdinal(), self.maskedTin() },
        ) catch self.maskedTin();
    }

    pub fn statusLabel(self: *const TaxpayerRow) []const u8 {
        return workspaceStatusLabel(self.status);
    }

    pub fn accessibleLabel(
        self: *const TaxpayerRow,
        allocator: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            allocator,
            "Taxpayer {d}, {s}, {s}",
            .{ self.displayOrdinal(), self.maskedTin(), self.statusLabel() },
        ) catch self.maskedTin();
    }
};

pub const UnitRow = struct {
    id: usize,
    revision: registration.RegistrationUnitRevision,
    contact_revision: ?registration.RegistrationUnitContactRevision = null,
    vat_registration_state: VatRegistrationState = .absent,
    code_text: [32]u8 = [_]u8{0} ** 32,
    code_text_len: u8 = 0,
    selected: bool = false,

    pub fn kindLabel(self: *const UnitRow) []const u8 {
        return switch (self.revision.kind) {
            .head_office => "Head office",
            .branch => "Branch",
        };
    }

    pub fn codeLabel(self: *const UnitRow) []const u8 {
        return self.code_text[0..self.code_text_len];
    }

    pub fn statusLabel(self: *const UnitRow) []const u8 {
        return registration_ui.statusLabel(self.revision.status);
    }

    pub fn rdoLabel(self: *const UnitRow) []const u8 {
        return if (self.revision.rdo_code) |*rdo| rdo.asDigits() else "Not recorded";
    }

    pub fn vatRegistrationLabel(self: *const UnitRow) []const u8 {
        return switch (self.vat_registration_state) {
            .absent => "VAT not recorded",
            .confirmed_active => "VAT confirmed active",
            .requires_review => "VAT Review Required",
        };
    }

    pub fn vatRegistrationTone(self: *const UnitRow) []const u8 {
        return switch (self.vat_registration_state) {
            .absent => "secondary",
            .confirmed_active => "outline",
            .requires_review => "destructive",
        };
    }

    /// Stable widget identity across branch-code sorting and reordering.
    pub fn stableKey(self: *const UnitRow) []const u8 {
        return self.revision.registration_unit_id.asSlice();
    }

    pub fn accessibleLabel(
        self: *const UnitRow,
        allocator: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            allocator,
            "Registration Unit, {s}, code {s}, {s}, RDO {s}, {s}",
            .{
                self.kindLabel(),
                self.codeLabel(),
                self.statusLabel(),
                self.rdoLabel(),
                self.vatRegistrationLabel(),
            },
        ) catch self.kindLabel();
    }
};

/// Presentation row for a source record that was explicitly attributed before
/// the current workspace selection. Selection only decides whether this row is
/// visible; the record keeps its original Source Unit revision binding.
pub const SourceRecordRow = struct {
    id: usize,
    record: SourceRecord,

    pub fn stableKey(self: *const SourceRecordRow) []const u8 {
        return self.record.id.asSlice();
    }

    pub fn visibleLabel(self: *const SourceRecordRow) []const u8 {
        return self.record.kind.label();
    }

    pub fn occurredOnLabel(
        self: *const SourceRecordRow,
        allocator: std.mem.Allocator,
    ) []const u8 {
        const date = self.record.occurred_on;
        return std.fmt.allocPrint(
            allocator,
            "{d:0>4}-{d:0>2}-{d:0>2}",
            .{ date.year, date.month, date.day },
        ) catch "Date unavailable";
    }

    pub fn attributionLabel(
        self: *const SourceRecordRow,
        allocator: std.mem.Allocator,
    ) []const u8 {
        return switch (self.record.attribution) {
            .entered => |value| std.fmt.allocPrint(
                allocator,
                "Entered · reference {s}",
                .{value.evidence_reference.asSlice()},
            ) catch "Entered from reviewed reference",
            .derived => |value| std.fmt.allocPrint(
                allocator,
                "Derived · {s} v{d}",
                .{ value.rule_id.asSlice(), value.rule_version },
            ) catch "Derived by versioned rule",
            .legacy_unknown => |reason| reason.label(),
        };
    }

    pub fn accessibleLabel(
        self: *const SourceRecordRow,
        allocator: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            allocator,
            "Source-attributed {s}, record {s}, {s}",
            .{
                self.visibleLabel(),
                self.record.id.asSlice(),
                self.attributionLabel(allocator),
            },
        ) catch self.visibleLabel();
    }
};

pub const ReviewIssueRow = struct {
    id: usize,
    issue: planner.ReviewIssue,
    subject_text: [96]u8 = [_]u8{0} ** 96,
    subject_text_len: u8 = 0,
    detail_text: [96]u8 = [_]u8{0} ** 96,
    detail_text_len: u8 = 0,

    pub fn label(
        self: *const ReviewIssueRow,
        allocator: std.mem.Allocator,
    ) []const u8 {
        const reason = reviewReasonLabel(self.issue.reason);
        const subject = self.subject_text[0..self.subject_text_len];
        const detail = self.detail_text[0..self.detail_text_len];
        const evidence_id = if (self.issue.evidence_id) |*id| id.asSlice() else null;
        if (detail.len == 0) {
            if (evidence_id) |id| {
                return std.fmt.allocPrint(
                    allocator,
                    "{s} Evidence: {s}. Affected: {s}.",
                    .{ reason, id, subject },
                ) catch reason;
            }
            return std.fmt.allocPrint(
                allocator,
                "{s} Affected: {s}.",
                .{ reason, subject },
            ) catch reason;
        }
        return if (evidence_id) |id|
            std.fmt.allocPrint(
                allocator,
                "{s} Evidence: {s}. Affected: {s}. Detail: {s}.",
                .{ reason, id, subject, detail },
            ) catch reason
        else
            std.fmt.allocPrint(
                allocator,
                "{s} Affected: {s}. Detail: {s}.",
                .{ reason, subject, detail },
            ) catch reason;
    }
};

/// One exact covered Registration Unit revision from the immutable resolved
/// obligation. The row retains the complete binding even when the Native view
/// chooses to render only its branch-code label.
pub const CoverageRow = struct {
    id: usize,
    registration_unit_id: registration.RegistrationUnitId,
    registration_unit_revision_id: registration.RegistrationUnitRevisionId,
    branch_code: registration.BranchCode5,
    branch_code_evidence_id: registration.RegistrationEvidenceId,

    pub fn branchCodeLabel(self: *const CoverageRow) []const u8 {
        return self.branch_code.asDigits();
    }

    pub fn branchCodeEvidenceId(self: *const CoverageRow) []const u8 {
        return self.branch_code_evidence_id.asSlice();
    }

    pub fn accessibleLabel(
        self: *const CoverageRow,
        allocator: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            allocator,
            "Covered Registration Unit {s}, branch-code evidence {s}",
            .{ self.branchCodeLabel(), self.branchCodeEvidenceId() },
        ) catch self.branchCodeLabel();
    }
};

/// One exact reviewed-registration-evidence authority binding retained by the
/// preview snapshot. Displaying the full binding prevents a count-only UI from
/// hiding which assertion and human review decision authorized a fact.
pub const ReviewedEvidenceRow = struct {
    id: usize,
    binding: planner.ReviewedEvidenceBinding,

    pub fn subjectLabel(self: *const ReviewedEvidenceRow) []const u8 {
        return switch (self.binding.subject) {
            .taxpayer_identity_revision => "Taxpayer identity revision",
            .registration_unit_branch_code_revision => "Registration Unit branch-code revision",
            .registration_unit_lifecycle_revision => "Registration Unit lifecycle revision",
            .registration_unit_contact_revision => "Registration Unit contact revision",
            .tax_type_registration_revision => "Tax-type registration revision",
        };
    }

    pub fn subjectId(self: *const ReviewedEvidenceRow) []const u8 {
        return self.binding.subject.idBytes();
    }

    pub fn evidenceId(self: *const ReviewedEvidenceRow) []const u8 {
        return self.binding.evidence_id.asSlice();
    }

    pub fn reviewDecisionId(self: *const ReviewedEvidenceRow) []const u8 {
        return self.binding.review_decision_id.asSlice();
    }

    pub fn reviewDecisionSequence(self: *const ReviewedEvidenceRow) u32 {
        return self.binding.review_decision_sequence;
    }

    pub fn assertionId(self: *const ReviewedEvidenceRow) []const u8 {
        return self.binding.assertion_id.asSlice();
    }

    pub fn accessibleLabel(
        self: *const ReviewedEvidenceRow,
        allocator: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            allocator,
            "{s} {s}, evidence {s}, review decision {s} sequence {d}, assertion {s}",
            .{
                self.subjectLabel(),
                self.subjectId(),
                self.evidenceId(),
                self.reviewDecisionId(),
                self.reviewDecisionSequence(),
                self.assertionId(),
            },
        ) catch self.subjectLabel();
    }
};

/// Value-owned policy evidence presented with a resolved scope preview. The
/// fixed buffers keep the preview independent from the policy catalog's
/// lifetime and force oversized or missing explanations to fail closed.
pub const PolicyEvidenceRow = struct {
    id: usize,
    evidence_id: policy.PolicyEvidenceId,
    display_name_text: [max_policy_evidence_display_name_bytes]u8 =
        [_]u8{0} ** max_policy_evidence_display_name_bytes,
    display_name_len: u16 = 0,
    review_basis_text: [max_policy_evidence_review_basis_bytes]u8 =
        [_]u8{0} ** max_policy_evidence_review_basis_bytes,
    review_basis_len: u16 = 0,

    fn init(id: usize, evidence: *const policy.PolicyEvidenceRef) !PolicyEvidenceRow {
        if (evidence.display_name.len == 0 or
            evidence.display_name.len > max_policy_evidence_display_name_bytes or
            evidence.review_basis.len == 0 or
            evidence.review_basis.len > max_policy_evidence_review_basis_bytes)
        {
            return error.PolicyEvidenceMetadataUnavailable;
        }
        var row = PolicyEvidenceRow{
            .id = id,
            .evidence_id = evidence.id,
            .display_name_len = @intCast(evidence.display_name.len),
            .review_basis_len = @intCast(evidence.review_basis.len),
        };
        @memcpy(
            row.display_name_text[0..evidence.display_name.len],
            evidence.display_name,
        );
        @memcpy(
            row.review_basis_text[0..evidence.review_basis.len],
            evidence.review_basis,
        );
        return row;
    }

    pub fn evidenceId(self: *const PolicyEvidenceRow) []const u8 {
        return self.evidence_id.asSlice();
    }

    pub fn displayName(self: *const PolicyEvidenceRow) []const u8 {
        return self.display_name_text[0..self.display_name_len];
    }

    pub fn reviewBasis(self: *const PolicyEvidenceRow) []const u8 {
        return self.review_basis_text[0..self.review_basis_len];
    }
};

/// Immutable, value-owned presentation snapshot for the isolated 2550Q
/// preview. This is deliberately not draft provenance: it exists only while
/// the read-only preview is open and cannot authorize a draft or filing.
/// Keeping the workspace filter and covered-unit rows beside the validated
/// projection prevents later workspace refreshes from changing the scope the
/// user is reviewing.
pub const Resolved2550QPreviewSnapshot = struct {
    projection_context: projection.FilingProjectionContext,
    source_workspace_unit: UnitRow,
    source_rows: [max_source_records]SourceRecordRow = undefined,
    source_row_count: usize,
    source_review_required_count: usize,
    source_input_truncated: bool,
    coverage_rows: [max_coverage_units]CoverageRow = undefined,
    coverage_count: usize,
    reviewed_evidence_rows: [max_reviewed_evidence_rows]ReviewedEvidenceRow = undefined,
    reviewed_evidence_binding_count: usize,
    scope_category: ResolvedScopeCategory,
    policy_revision_id: policy.FilingPolicyRevisionId,
    policy_evidence_id: ?policy.PolicyEvidenceId,
    policy_evidence_rows: [max_policy_evidence_rows]PolicyEvidenceRow = undefined,
    policy_capability: policy.CapabilityState,
    filing_capability: planner.FilingCapability,
    filing_venue_resolution: planner.FilingVenueResolution,
    policy_evidence_count: usize,
    decision_hash_text: [64]u8,

    pub fn coverageRows(self: *const Resolved2550QPreviewSnapshot) []const CoverageRow {
        return self.coverage_rows[0..self.coverage_count];
    }

    pub fn sourceRecordRows(
        self: *const Resolved2550QPreviewSnapshot,
    ) []const SourceRecordRow {
        return self.source_rows[0..self.source_row_count];
    }

    pub fn reviewedEvidenceRows(
        self: *const Resolved2550QPreviewSnapshot,
    ) []const ReviewedEvidenceRow {
        return self.reviewed_evidence_rows[0..self.reviewed_evidence_binding_count];
    }

    pub fn policyEvidenceRows(
        self: *const Resolved2550QPreviewSnapshot,
    ) []const PolicyEvidenceRow {
        return self.policy_evidence_rows[0..self.policy_evidence_count];
    }
};

/// Common input for one accepted reviewed-evidence bundle. The asserted
/// effective date remains distinct from document capture and review times.
/// `evidence_path` is the protected storage reference, never the picker path.
pub const ReviewedEvidenceInput = struct {
    source_kind: EvidenceSourceKind,
    effective_from: []const u8,
    evidence_path: []const u8,
    evidence_display_name: []const u8,
    evidence_sha256: []const u8,
    evidence_byte_size: []const u8,
    evidence_captured_on: []const u8,
    reviewed_at_unix_seconds: i64,
};

pub const ConfirmationInput = struct {
    reviewed_evidence: ReviewedEvidenceInput,
    observed_tin_root: []const u8,
    observed_branch_code: []const u8,
    observed_rdo_code: []const u8,
    /// Required at runtime. The default keeps older callers compiling while
    /// their UI buffers are upgraded; confirmation rejects an empty value.
    registered_address: []const u8 = "",
    zip_code: []const u8 = "",
    contact_number: []const u8 = "",
    email_address: []const u8 = "",
    /// Explicit human assertion that this same reviewed evidence records an
    /// active VAT registration for the selected head office. Never inferred
    /// from Forms Set, form launch, or Registration Unit status.
    confirm_vat_registration: bool = false,
};

pub const VatRegistrationInput = struct {
    reviewed_evidence: ReviewedEvidenceInput,
    /// Independently entered from the reviewed record. The repair workflow
    /// must prove that the VAT fact belongs to the selected Taxpayer rather
    /// than inheriting identity from workspace selection.
    observed_tin_root: []const u8,
    assert_active_vat_registration: bool,
};

const ParsedReviewedEvidence = struct {
    effective_from: registration.Date,
    path: []const u8,
    display_name: []const u8,
    digest: registration.Sha256Digest,
    byte_size: u64,
    captured_on: registration.Date,
};

const ParsedConfirmationFacts = struct {
    observed_tin_root: registration.Tin9,
    observed_code: registration.BranchCode5,
    observed_rdo: ?registration.RdoCode3,
    contact: registration.RegistrationUnitContact,
};

const ReviewedEvidenceParseError = error{
    InvalidEffectiveDate,
    InvalidEvidenceDate,
    InvalidEvidencePath,
    InvalidEvidenceName,
    InvalidEvidenceDigest,
    InvalidEvidenceSize,
};

const ConfirmationFactsParseError = error{
    InvalidObservedTinRoot,
    InvalidBranchCode,
    InvalidRdoCode,
    InvalidRegisteredAddress,
    InvalidZipCode,
    InvalidContactNumber,
    InvalidEmailAddress,
};

/// Pure readiness check shared by the Native action state and the write path.
/// It deliberately covers only syntactic and required input facts; selected-
/// unit lifecycle and effective-date ordering remain authoritative in `State`.
pub fn confirmationInputValidationStatus(input: ConfirmationInput) ?ActionStatus {
    _ = parseReviewedEvidenceValue(input.reviewed_evidence) catch |err| {
        return reviewedEvidenceActionStatus(err);
    };
    _ = parseConfirmationFactsValue(input) catch |err| {
        return confirmationFactsActionStatus(err);
    };
    return null;
}

pub fn vatRegistrationInputValidationStatus(input: VatRegistrationInput) ?ActionStatus {
    _ = registration.Tin9.parse(input.observed_tin_root) catch
        return .invalid_observed_tin_root;
    if (!input.assert_active_vat_registration) {
        return .vat_registration_assertion_required;
    }
    _ = parseReviewedEvidenceValue(input.reviewed_evidence) catch |err| {
        return reviewedEvidenceActionStatus(err);
    };
    return null;
}

pub const State = struct {
    taxpayers: [max_taxpayers]TaxpayerRow = undefined,
    taxpayer_count: usize = 0,
    taxpayers_truncated: bool = false,
    selected_taxpayer_index: ?usize = null,

    units: [max_units]UnitRow = undefined,
    unit_count: usize = 0,
    units_truncated: bool = false,
    selected_registration_unit_index: ?usize = null,

    source_records: [max_source_records]SourceRecord = undefined,
    source_records_loaded: bool = false,
    source_record_count: usize = 0,
    source_records_truncated: bool = false,
    source_records_omitted_count: usize = 0,
    source_load_invalid_count: usize = 0,
    source_invalid_count: usize = 0,
    source_rows: [max_source_records]SourceRecordRow = undefined,
    source_row_count: usize = 0,
    source_unresolved_count: usize = 0,

    selected_identity: ?registration.TaxpayerIdentityRevision = null,
    snapshot_review_required: bool = false,
    workspace_status: WorkspaceStatus = .no_data,
    suggested_branch_code: ?registration.BranchCode5 = null,
    branch_suggestion_incomplete: bool = false,

    period_year: u16 = 2026,
    period_quarter: u8 = 1,
    planning_status: PlanningStatus = .unavailable,
    integration_reason: IntegrationReason = .none,
    planning_reasons: [max_review_reasons]ReviewIssueRow = undefined,
    planning_reason_count: usize = 0,
    policy_catalog_missing: bool = true,
    effective_policy_resolved: bool = false,
    resolved_filing_code: ?registration.BranchCode5 = null,
    resolved_filing_rdo_code: ?registration.RdoCode3 = null,
    resolved_coverage_count: usize = 0,
    coverage_rows: [max_coverage_units]CoverageRow = undefined,
    coverage_count: usize = 0,
    coverage_truncated: bool = false,
    resolved_obligation_count: usize = 0,
    resolved_form_revision: ?policy.FormRevisionKey = null,
    resolved_policy_revision_id: ?policy.FilingPolicyRevisionId = null,
    resolved_policy_evidence_id: ?policy.PolicyEvidenceId = null,
    resolved_policy_capability: ?policy.CapabilityState = null,
    resolved_scope_category: ?ResolvedScopeCategory = null,
    resolved_venue: ?planner.FilingVenueResolution = null,
    decision_hash_text: [64]u8 = [_]u8{0} ** 64,
    decision_hash_present: bool = false,
    projection_filer_tin: [18]u8 = [_]u8{0} ** 18,
    projection_filer_tin_len: u8 = 0,
    resolved_preview_snapshot: ?Resolved2550QPreviewSnapshot = null,
    provenance_validated: bool = false,
    action_status: ActionStatus = .none,
    action_context: ActionContext = .none,

    pub fn taxpayerRows(self: *const State) []const TaxpayerRow {
        return self.taxpayers[0..self.taxpayer_count];
    }

    pub fn taxpayerListStatusLabel(self: *const State) []const u8 {
        return if (self.taxpayers_truncated)
            "Showing the first 64 Taxpayers; additional records are hidden — Review Required."
        else
            "Complete Taxpayer list loaded.";
    }

    pub fn unitRows(self: *const State) []const UnitRow {
        return self.units[0..self.unit_count];
    }

    pub fn unitListStatusLabel(self: *const State) []const u8 {
        return if (self.units_truncated)
            "Showing the first 64 Registration Units; additional records are hidden — Review Required."
        else
            "Complete Registration Unit list loaded.";
    }

    /// Replaces the caller-owned read-model snapshot. Invalid or excess rows
    /// are counted as Review Required and never repaired from current
    /// selection. The method performs no registration-ledger write.
    pub fn replaceSourceRecords(self: *State, records: []const SourceRecord) void {
        self.source_records_loaded = true;
        self.source_record_count = @min(records.len, self.source_records.len);
        self.source_records_truncated = records.len > self.source_records.len;
        self.source_records_omitted_count = records.len - self.source_record_count;
        @memcpy(
            self.source_records[0..self.source_record_count],
            records[0..self.source_record_count],
        );

        self.source_load_invalid_count = 0;
        for (self.source_records[0..self.source_record_count]) |*record| {
            record.validate() catch {
                self.source_load_invalid_count += 1;
            };
        }

        self.rebuildSourceWorkspaceView();
    }

    pub fn sourceRecordRows(self: *const State) []const SourceRecordRow {
        return self.source_rows[0..self.source_row_count];
    }

    pub fn sourceRecordsConnected(self: *const State) bool {
        return self.source_records_loaded;
    }

    /// Global diagnostics for the connected source stream. This remains
    /// separate from the selected workspace's Review Required state.
    pub fn sourceLoadInvalidCount(self: *const State) usize {
        return self.source_load_invalid_count;
    }

    pub fn sourceWorkspaceReviewRequired(self: *const State) bool {
        return self.source_unresolved_count != 0 or
            self.source_invalid_count != 0 or self.source_records_truncated;
    }

    pub fn sourceWorkspaceUnresolvedCount(self: *const State) usize {
        return self.source_unresolved_count + self.source_invalid_count +
            self.source_records_omitted_count;
    }

    pub fn reviewReasonRows(self: *const State) []const ReviewIssueRow {
        return self.planning_reasons[0..self.planning_reason_count];
    }

    pub fn coverageRows(self: *const State) []const CoverageRow {
        return self.coverage_rows[0..self.coverage_count];
    }

    pub fn policyEvidenceRows(self: *const State) []const PolicyEvidenceRow {
        const snapshot = self.resolvedPreviewSnapshot() orelse return &.{};
        return snapshot.policyEvidenceRows();
    }

    /// Returns the exact, validated planner projection that may be snapshotted
    /// into the isolated read-only 2550Q preview. It never falls back to a
    /// selected legacy ProfileId or workspace Registration Unit.
    pub fn resolvedPreviewSnapshot(
        self: *const State,
    ) ?*const Resolved2550QPreviewSnapshot {
        if (self.policy_catalog_missing or
            !self.effective_policy_resolved or
            !self.provenance_validated)
        {
            return null;
        }
        switch (self.planning_status) {
            .resolved_not_fileable, .resolved_fileable => {},
            else => return null,
        }
        if (self.resolved_policy_capability != .editor_supported) return null;
        const snapshot = &(self.resolved_preview_snapshot orelse return null);
        if (!snapshot.projection_context.form_revision.eql(
            &requested_preview_form_revision,
        )) {
            return null;
        }
        return snapshot;
    }

    /// Copies the validated planner result for presentation while refreshing
    /// only the current workspace filter. Registration Unit selection is not
    /// filing authority and must not rerun or mutate the resolved decision.
    pub fn resolvedPreviewSnapshotForOpen(
        self: *const State,
    ) ?Resolved2550QPreviewSnapshot {
        const stored = self.resolvedPreviewSnapshot() orelse return null;
        const selected = self.selectedRegistrationUnit() orelse return null;
        var snapshot = stored.*;
        snapshot.source_workspace_unit = selected.*;
        snapshot.source_row_count = self.source_row_count;
        snapshot.source_review_required_count = self.sourceWorkspaceUnresolvedCount();
        snapshot.source_input_truncated = self.source_records_truncated;
        @memcpy(
            snapshot.source_rows[0..self.source_row_count],
            self.source_rows[0..self.source_row_count],
        );
        return snapshot;
    }

    /// Revokes any planner result that depended on the isolated fixture policy.
    /// A late legacy writer or ownership drift must not leave an earlier
    /// resolved preview available for navigation.
    pub fn revokeResolvedPreviewAccess(self: *State) void {
        self.policy_catalog_missing = true;
        self.resetResolvedPresentation();
        self.planning_status = .review_required;
    }

    pub fn invalidateResolvedPreview(self: *State) void {
        self.revokeResolvedPreviewAccess();
    }

    pub fn resolvedProjectionContext(
        self: *const State,
    ) ?*const projection.FilingProjectionContext {
        const snapshot = self.resolvedPreviewSnapshot() orelse return null;
        return &snapshot.projection_context;
    }

    pub fn selectedTaxpayer(self: *const State) ?*const TaxpayerRow {
        const index = self.selected_taxpayer_index orelse return null;
        if (index >= self.taxpayer_count) return null;
        return &self.taxpayers[index];
    }

    pub fn selectedRegistrationUnit(self: *const State) ?*const UnitRow {
        const index = self.selected_registration_unit_index orelse return null;
        if (index >= self.unit_count) return null;
        return &self.units[index];
    }

    pub fn selectedHeadOfficeVatRegistrationRepairable(
        self: *const State,
    ) bool {
        const unit = self.selectedRegistrationUnit() orelse return false;
        if (unit.revision.kind != .head_office or
            unit.revision.status != .confirmed_active or
            unit.vat_registration_state != .absent)
        {
            return false;
        }
        const confirmation = unit.revision.branch_code_evidence.confirmedCode() orelse
            return false;
        return confirmation.code.isHeadOffice();
    }

    pub fn branchSuggestionLabel(self: *const State) []const u8 {
        return if (self.suggested_branch_code) |*code| code.asDigits() else "Unavailable";
    }

    pub fn branchSuggestionActionEnabled(self: *const State) bool {
        return !self.branch_suggestion_incomplete and
            self.suggested_branch_code != null;
    }

    pub fn taxpayerCreationAtCapacity(self: *const State) bool {
        return self.taxpayers_truncated or self.taxpayer_count >= max_taxpayers;
    }

    pub fn branchCreationAtCapacity(self: *const State) bool {
        return self.units_truncated or self.unit_count >= max_units;
    }

    pub fn branchSuggestionStatusLabel(self: *const State) []const u8 {
        if (self.branch_suggestion_incomplete) {
            return "Branch-code history is incomplete — no safe suggestion is available.";
        }
        if (self.suggested_branch_code != null) {
            return "Convenience suggestion only — verify the exact code against BIR registration evidence.";
        }
        return "No safe unused Branch Code is available.";
    }

    pub fn planningStatusLabel(self: *const State) []const u8 {
        return switch (self.planning_status) {
            .unavailable => "Select a canonical taxpayer to preview filing scope.",
            .review_required => if (self.resolved_filing_code != null)
                "Review Required — Filing Unit and Return Coverage are resolved, but registration contact review blocks the 2550Q preview."
            else
                "Review Required — no Filing Unit was resolved.",
            .not_applicable => "Not applicable for the selected taxpayer and period.",
            .resolved_not_fileable => "Scope resolved, but this 2550Q slice is explicitly not fileable.",
            .resolved_fileable => "Scope resolved and marked fileable by policy.",
            .integration_error => self.integrationReasonLabel(),
        };
    }

    pub fn integrationReasonLabel(self: *const State) []const u8 {
        return switch (self.integration_reason) {
            .none => "Review Required — filing-scope integration did not complete.",
            .invalid_preview_period => "Review Required — the requested preview period is invalid.",
            .taxpayer_list_truncated => "Review Required — the Taxpayer list exceeds this workspace's safe display capacity.",
            .unit_list_truncated => "Review Required — the Registration Unit list exceeds this workspace's safe display capacity.",
            .review_issue_capacity_exceeded => "Review Required — the planner returned more repair actions than this workspace can preserve, so none are shown.",
            .unexpected_obligation_count => "Review Required — the planner did not return exactly one obligation, so no obligation was selected for preview.",
            .coverage_capacity_exceeded => "Review Required — exact Return Coverage exceeds this workspace's safe display capacity.",
            .reviewed_evidence_capacity_exceeded => "Review Required — exact reviewed registration-evidence bindings exceed this preview's safe display capacity.",
            .policy_evidence_capacity_exceeded => "Review Required — the resolved policy has more evidence sources than this preview can preserve safely.",
            .policy_evidence_metadata_unavailable => "Review Required — the resolved policy evidence explanation is missing, oversized, or inconsistent with the policy revision.",
            .projection_context_invalid => "Review Required — the resolved obligation failed projection-context validation.",
            .provenance_validation_failed => "Review Required — scope-provenance validation failed; no preview scope is shown.",
            .filer_identity_projection_failed => "Review Required — the resolved filer identity could not be projected safely.",
            .workspace_load_failed => "Review Required — registration data could not be loaded; no filing scope is shown.",
        };
    }

    pub fn policyCatalogLabel(self: *const State) []const u8 {
        if (self.policy_catalog_missing) {
            return "Policy catalog unavailable — Review Required";
        }
        return if (self.effectivePolicyResolved())
            "Exact effective policy revision resolved"
        else
            "Policy catalog loaded, but no exact effective policy revision resolved — Review Required";
    }

    pub fn policyEvidenceLabel(self: *const State) []const u8 {
        return if (self.resolved_policy_evidence_id) |*evidence_id|
            evidence_id.asSlice()
        else
            "No exact policy evidence binding resolved";
    }

    pub fn effectivePolicyResolved(self: *const State) bool {
        return self.effective_policy_resolved and
            self.resolved_policy_revision_id != null;
    }

    pub fn requestedPreviewLabel(
        self: *const State,
        allocator: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            allocator,
            "{s} · {s} · Q{d} {d}",
            .{
                requested_preview_form_revision.code.asSlice(),
                requested_preview_form_revision.revision.asSlice(),
                self.period_quarter,
                self.period_year,
            },
        ) catch "2550Q filing-scope preview";
    }

    pub fn fileabilityLabel(self: *const State) []const u8 {
        return if (self.planning_status == .resolved_fileable)
            "Fileable by the resolved policy capability"
        else
            "Not fileable";
    }

    pub fn resolvedFilingCodeLabel(self: *const State) []const u8 {
        return if (self.resolved_filing_code) |*code| code.asDigits() else "Not resolved";
    }

    pub fn resolvedFilingRdoLabel(self: *const State) []const u8 {
        if (self.resolved_filing_rdo_code) |*code| return code.asDigits();
        return if (self.resolved_filing_code != null)
            "Not recorded"
        else
            "Not resolved";
    }

    pub fn beginAction(self: *State, context: ActionContext) void {
        self.action_context = context;
        self.action_status = .none;
    }

    pub fn clearAction(self: *State) void {
        self.action_context = .none;
        self.action_status = .none;
    }

    pub fn taxpayerIndex(self: *const State, taxpayer_id: registration.TaxpayerId) ?usize {
        for (self.taxpayers[0..self.taxpayer_count], 0..) |row, index| {
            if (row.taxpayer_id.eql(&taxpayer_id)) return index;
        }
        return null;
    }

    pub fn registrationUnitIndex(
        self: *const State,
        registration_unit_id: registration.RegistrationUnitId,
    ) ?usize {
        for (self.units[0..self.unit_count], 0..) |row, index| {
            if (row.revision.registration_unit_id.eql(&registration_unit_id)) {
                return index;
            }
        }
        return null;
    }

    pub fn projectionFilerTinLabel(self: *const State) []const u8 {
        return if (self.projection_filer_tin_len == 0)
            "Not projected"
        else
            self.projection_filer_tin[0..self.projection_filer_tin_len];
    }

    pub fn formRevisionLabel(
        self: *const State,
        allocator: std.mem.Allocator,
    ) []const u8 {
        const form = self.resolved_form_revision orelse return "Not resolved";
        return std.fmt.allocPrint(
            allocator,
            "{s} · {s}",
            .{ form.code.asSlice(), form.revision.asSlice() },
        ) catch "Not resolved";
    }

    pub fn policyRevisionLabel(self: *const State) []const u8 {
        return if (self.resolved_policy_revision_id) |*id|
            id.asSlice()
        else
            "Not resolved";
    }

    pub fn decisionHashLabel(self: *const State) []const u8 {
        return if (self.decision_hash_present)
            &self.decision_hash_text
        else
            "Not captured";
    }

    pub fn scopeCategoryLabel(self: *const State) []const u8 {
        return switch (self.resolved_scope_category orelse return "Not resolved") {
            .head_office_consolidated => "Head-office consolidated",
        };
    }

    pub fn policyCapabilityLabel(self: *const State) []const u8 {
        return switch (self.resolved_policy_capability orelse return "Not resolved") {
            .editor_supported => "Editor supported",
            .reference_only => "Reference only",
            .unsupported => "Unsupported",
        };
    }

    pub fn venueLabel(self: *const State) []const u8 {
        return switch (self.resolved_venue orelse return "Not resolved") {
            .not_resolved_by_scope => "Not resolved by filing scope",
            .review_required => "Review Required",
        };
    }

    pub fn provenanceLabel(self: *const State) []const u8 {
        return if (self.provenance_validated)
            "Scope provenance validated for this preview; no immutable draft provenance was retained."
        else
            "No retained immutable scope provenance.";
    }

    /// Loads the canonical v28 index and selected Registration Unit snapshot,
    /// then previews the exact 2550Q revision through the real planner API.
    /// The injected catalog exists for tests; production callers should use
    /// `refreshProduction` below.
    pub fn refresh(
        self: *State,
        allocator: std.mem.Allocator,
        ledger: anytype,
        evidence_integrity_verifier: anytype,
        as_of: registration.Date,
        policy_catalog: policy.FilingPolicyCatalog,
        period_year: u16,
        period_quarter: u8,
    ) !void {
        self.setRequestedPeriod(period_year, period_quarter);
        const previous_taxpayer = if (self.selectedTaxpayer()) |row|
            row.taxpayer_id
        else
            null;
        const previous_registration_unit = if (self.selectedRegistrationUnit()) |row|
            row.revision.registration_unit_id
        else
            null;

        var ids = try ledger.listTaxpayerIds();
        defer ids.deinit(ledger.allocator);

        self.taxpayer_count = 0;
        self.taxpayers_truncated = ids.items.len > self.taxpayers.len;
        for (ids.items[0..@min(ids.items.len, self.taxpayers.len)]) |taxpayer_id| {
            var row = TaxpayerRow{
                .id = self.taxpayer_count,
                .taxpayer_id = taxpayer_id,
            };
            var snapshot = try ledger.snapshot(.{
                .taxpayer_id = taxpayer_id,
                .start = as_of,
                .end = as_of,
            });
            defer snapshot.deinit(ledger.allocator);
            switch (snapshot) {
                .resolved => |resolved| {
                    writeMaskedTin(resolved.taxpayer_identity.tin_root, &row.masked_tin);
                    row.status = aggregateStatus(resolved.units);
                },
                .review_required => {
                    row.status = .review_required;
                },
            }
            self.taxpayers[self.taxpayer_count] = row;
            self.taxpayer_count += 1;
        }

        self.selected_taxpayer_index = null;
        if (previous_taxpayer) |wanted| {
            for (self.taxpayers[0..self.taxpayer_count], 0..) |row, index| {
                if (wanted.eql(&row.taxpayer_id)) {
                    self.selected_taxpayer_index = index;
                    break;
                }
            }
        }
        if (self.selected_taxpayer_index == null and self.taxpayer_count != 0) {
            self.selected_taxpayer_index = 0;
        }
        self.syncTaxpayerSelection();

        try self.loadSelectedSnapshot(ledger, as_of, previous_registration_unit);
        try self.preview(
            allocator,
            ledger,
            evidence_integrity_verifier,
            policy_catalog,
        );
    }

    pub fn refreshProduction(
        self: *State,
        allocator: std.mem.Allocator,
        ledger: anytype,
        evidence_integrity_verifier: anytype,
        as_of: registration.Date,
        period_year: u16,
        period_quarter: u8,
    ) !void {
        return self.refresh(
            allocator,
            ledger,
            evidence_integrity_verifier,
            as_of,
            production_policy_catalog,
            period_year,
            period_quarter,
        );
    }

    pub fn selectTaxpayer(
        self: *State,
        allocator: std.mem.Allocator,
        ledger: anytype,
        evidence_integrity_verifier: anytype,
        index: usize,
        as_of: registration.Date,
        policy_catalog: policy.FilingPolicyCatalog,
    ) !void {
        if (index >= self.taxpayer_count) return;
        self.selected_taxpayer_index = index;
        self.syncTaxpayerSelection();
        try self.loadSelectedSnapshot(ledger, as_of, null);
        try self.preview(
            allocator,
            ledger,
            evidence_integrity_verifier,
            policy_catalog,
        );
    }

    pub fn selectRegistrationUnit(self: *State, index: usize) void {
        if (index >= self.unit_count) return;
        self.selected_registration_unit_index = index;
        self.syncRegistrationUnitSelection();
        self.rebuildSourceWorkspaceView();
        // Deliberately do not rerun or modify the Filing Plan. This selection
        // is only a workspace filter, not Source Attribution or a Filing Unit.
    }

    pub fn createPendingTaxpayer(
        self: *State,
        ledger: anytype,
        tin_root_text: []const u8,
        effective_from_text: []const u8,
    ) ?registration.TaxpayerId {
        if (self.taxpayerCreationAtCapacity()) {
            self.action_status = .taxpayer_capacity_reached;
            return null;
        }
        const tin_root = registration.Tin9.parse(tin_root_text) catch {
            self.action_status = .invalid_tin_root;
            return null;
        };
        const effective_from = registration.Date.parseIso(effective_from_text) catch {
            self.action_status = .invalid_effective_date;
            return null;
        };
        const taxpayer_id = freshId(registration.TaxpayerId, ledger) catch {
            self.action_status = .write_failed;
            return null;
        };
        const taxpayer_revision_id = freshId(registration.TaxpayerRevisionId, ledger) catch {
            self.action_status = .write_failed;
            return null;
        };
        const unit_id = freshId(registration.RegistrationUnitId, ledger) catch {
            self.action_status = .write_failed;
            return null;
        };
        const unit_revision_id = freshId(registration.RegistrationUnitRevisionId, ledger) catch {
            self.action_status = .write_failed;
            return null;
        };
        _ = ledger.apply(.{ .create_taxpayer = .{
            .taxpayer_id = taxpayer_id,
            .taxpayer_revision_id = taxpayer_revision_id,
            .tin_root = tin_root,
            .effective_from = effective_from,
            .head_office_unit_id = unit_id,
            .head_office_revision_id = unit_revision_id,
        } }) catch {
            self.action_status = .write_failed;
            return null;
        };
        self.action_status = .taxpayer_created;
        return taxpayer_id;
    }

    pub fn createPendingBranch(
        self: *State,
        ledger: anytype,
        branch_code_text: []const u8,
        effective_from_text: []const u8,
    ) ?registration.RegistrationUnitId {
        const taxpayer = self.selectedTaxpayer() orelse {
            self.action_status = .no_taxpayer_selected;
            return null;
        };
        if (self.branchCreationAtCapacity()) {
            self.action_status = .registration_unit_capacity_reached;
            return null;
        }
        const code = registration.BranchCode5.parse(branch_code_text) catch {
            self.action_status = .invalid_branch_code;
            return null;
        };
        if (code.isHeadOffice()) {
            self.action_status = .invalid_branch_code;
            return null;
        }
        const effective_from = registration.Date.parseIso(effective_from_text) catch {
            self.action_status = .invalid_effective_date;
            return null;
        };
        const unit_id = freshId(registration.RegistrationUnitId, ledger) catch {
            self.action_status = .write_failed;
            return null;
        };
        const revision_id = freshId(registration.RegistrationUnitRevisionId, ledger) catch {
            self.action_status = .write_failed;
            return null;
        };
        _ = ledger.apply(.{ .create_branch = .{
            .taxpayer_id = taxpayer.taxpayer_id,
            .registration_unit_id = unit_id,
            .registration_unit_revision_id = revision_id,
            .effective_from = effective_from,
            .candidate = registration.CandidateBranchCode.entered(code),
        } }) catch {
            self.action_status = .write_failed;
            return null;
        };
        self.action_status = .branch_created;
        return unit_id;
    }

    fn parseReviewedEvidence(
        self: *State,
        input: ReviewedEvidenceInput,
    ) ?ParsedReviewedEvidence {
        return parseReviewedEvidenceValue(input) catch |err| {
            self.action_status = reviewedEvidenceActionStatus(err);
            return null;
        };
    }

    /// Promotes one workspace-selected pending or imported-legacy Registration
    /// Unit only through an accepted, local-human reviewed evidence bundle.
    /// Exact lifecycle and
    /// contact assertions, the unit transition, and the contact revision share
    /// one transaction and the same evidence ID.
    pub fn confirmSelectedUnit(
        self: *State,
        ledger: anytype,
        input: ConfirmationInput,
    ) bool {
        const unit = self.selectedRegistrationUnit() orelse {
            self.action_status = .no_registration_unit_selected;
            return false;
        };
        const identity = self.selected_identity orelse {
            self.action_status = .write_failed;
            return false;
        };
        if (!identity.taxpayer_id.eql(&unit.revision.taxpayer_id)) {
            self.action_status = .write_failed;
            return false;
        }
        switch (unit.revision.status) {
            .pending_evidence, .legacy_unresolved => {},
            else => {
                self.action_status = .registration_unit_not_reviewable;
                return false;
            },
        }
        if (input.confirm_vat_registration and
            unit.revision.kind != .head_office)
        {
            self.action_status = .vat_registration_requires_head_office;
            return false;
        }
        const reviewed = self.parseReviewedEvidence(
            input.reviewed_evidence,
        ) orelse return false;
        const facts = parseConfirmationFactsValue(input) catch |err| {
            self.action_status = confirmationFactsActionStatus(err);
            return false;
        };
        if (!facts.observed_tin_root.eql(&identity.tin_root)) {
            self.action_status = .observed_tin_root_mismatch;
            return false;
        }
        const effective_from = reviewed.effective_from;
        if (effective_from.isBefore(unit.revision.effective.from)) {
            self.action_status = .effective_date_must_advance;
            return false;
        }
        if (unit.contact_revision) |current_contact| {
            if (effective_from.isBefore(current_contact.effective.from)) {
                self.action_status = .effective_date_must_advance;
                return false;
            }
        }
        const observed_code = registration.BranchCode5.parse(input.observed_branch_code) catch {
            self.action_status = .invalid_branch_code;
            return false;
        };
        const observed_rdo = parseOptionalRdo(input.observed_rdo_code) catch {
            self.action_status = .invalid_rdo_code;
            return false;
        };
        const registered_address = profile_field.RegisteredAddress.parse(
            input.registered_address,
        ) catch {
            self.action_status = .invalid_registered_address;
            return false;
        };
        const zip_code = parseOptionalZipCode(input.zip_code) catch {
            self.action_status = .invalid_zip_code;
            return false;
        };
        const contact_number = parseOptionalContactNumber(input.contact_number) catch {
            self.action_status = .invalid_contact_number;
            return false;
        };
        const email_address = parseOptionalEmailAddress(input.email_address) catch {
            self.action_status = .invalid_email_address;
            return false;
        };
        const contact: registration.RegistrationUnitContact = .{
            .registered_address = registered_address,
            .zip_code = zip_code,
            .contact_number = contact_number,
            .email_address = email_address,
        };
        const captured_on = reviewed.captured_on;
        const evidence_path = reviewed.path;
        const evidence_name = reviewed.display_name;
        const canonical_digest = reviewed.digest;
        const byte_size = reviewed.byte_size;
        const evidence_id = freshId(registration.RegistrationEvidenceId, ledger) catch {
            self.action_status = .write_failed;
            return false;
        };
        const review_id = freshId(
            registration.RegistrationEvidenceReviewDecisionId,
            ledger,
        ) catch {
            self.action_status = .write_failed;
            return false;
        };
        const taxpayer_assertion_id = freshId(
            registration.RegistrationEvidenceAssertionId,
            ledger,
        ) catch {
            self.action_status = .write_failed;
            return false;
        };
        const lifecycle_assertion_id = freshId(
            registration.RegistrationEvidenceAssertionId,
            ledger,
        ) catch {
            self.action_status = .write_failed;
            return false;
        };
        const contact_assertion_id = freshId(
            registration.RegistrationEvidenceAssertionId,
            ledger,
        ) catch {
            self.action_status = .write_failed;
            return false;
        };
        var vat_assertion_id: ?registration.RegistrationEvidenceAssertionId = null;
        var vat_registration_id: ?registration.TaxTypeRegistrationId = null;
        var vat_revision_id: ?registration.TaxTypeRegistrationRevisionId = null;
        if (input.confirm_vat_registration) {
            vat_assertion_id = freshId(
                registration.RegistrationEvidenceAssertionId,
                ledger,
            ) catch {
                self.action_status = .write_failed;
                return false;
            };
            vat_registration_id = freshId(
                registration.TaxTypeRegistrationId,
                ledger,
            ) catch {
                self.action_status = .write_failed;
                return false;
            };
            vat_revision_id = freshId(
                registration.TaxTypeRegistrationRevisionId,
                ledger,
            ) catch {
                self.action_status = .write_failed;
                return false;
            };
        }
        const revision_id = freshId(registration.RegistrationUnitRevisionId, ledger) catch {
            self.action_status = .write_failed;
            return false;
        };
        const contact_revision_id = freshId(
            registration.RegistrationUnitContactRevisionId,
            ledger,
        ) catch {
            self.action_status = .write_failed;
            return false;
        };
        const needs_identity_confirmation = identity.evidence_id == null;
        const taxpayer_revision_id: ?registration.TaxpayerRevisionId = if (needs_identity_confirmation)
            freshId(registration.TaxpayerRevisionId, ledger) catch {
                self.action_status = .write_failed;
                return false;
            }
        else
            null;
        const local_owner_id = ledger.localOwnerId() catch {
            self.action_status = .write_failed;
            return false;
        };
        if (unit.revision.sequence == std.math.maxInt(u32)) {
            self.action_status = .write_failed;
            return false;
        }
        if (needs_identity_confirmation and
            (identity.sequence == std.math.maxInt(u32) or
                effective_from.isBefore(identity.effective.from)))
        {
            self.action_status = .effective_date_must_advance;
            return false;
        }
        if (unit.contact_revision) |current_contact| {
            if (current_contact.sequence == std.math.maxInt(u32)) {
                self.action_status = .write_failed;
                return false;
            }
        }

        const lifecycle_command: registration.RegistrationCommand = switch (unit.revision.status) {
            .pending_evidence => .{ .confirm_registration_unit = .{
                .current = unit.revision,
                .next = .{
                    .id = revision_id,
                    .expected_history_sequence = unit.revision.sequence,
                    .sequence = unit.revision.sequence + 1,
                    .effective = .{ .from = effective_from },
                },
                .evidence_id = evidence_id,
                .observed_code = observed_code,
                .observed_rdo_code = observed_rdo,
            } },
            .legacy_unresolved => .{ .resolve_legacy_registration_unit = .{
                .current = unit.revision,
                .next = .{
                    .id = revision_id,
                    .expected_history_sequence = unit.revision.sequence,
                    .sequence = unit.revision.sequence + 1,
                    .effective = .{ .from = effective_from },
                },
                .evidence_id = evidence_id,
                .observed_code = observed_code,
                .observed_rdo_code = observed_rdo,
            } },
            else => unreachable,
        };
        const contact_command: registration.RegistrationCommand = if (unit.contact_revision) |current_contact|
            .{ .revise_registration_unit_contact = .{
                .current = current_contact,
                .next = .{
                    .id = contact_revision_id,
                    .expected_history_sequence = current_contact.sequence,
                    .sequence = current_contact.sequence + 1,
                    .effective = .{ .from = effective_from },
                },
                .contact = contact,
                .evidence_id = evidence_id,
            } }
        else
            .{ .create_registration_unit_contact = .{
                .taxpayer_id = unit.revision.taxpayer_id,
                .registration_unit_id = unit.revision.registration_unit_id,
                .next = .{
                    .id = contact_revision_id,
                    .sequence = 1,
                    .effective = .{ .from = effective_from },
                },
                .contact = contact,
                .evidence_id = evidence_id,
            } };
        var commands: [4]registration.RegistrationCommand = undefined;
        var command_count: usize = 0;
        if (needs_identity_confirmation) {
            commands[command_count] = .{ .confirm_taxpayer_tin_root = .{
                .current = identity,
                .next = .{
                    .id = taxpayer_revision_id.?,
                    .expected_history_sequence = identity.sequence,
                    .sequence = identity.sequence + 1,
                    .effective = .{ .from = effective_from },
                },
                .evidence_id = evidence_id,
                .observed_tin_root = facts.observed_tin_root,
            } };
            command_count += 1;
        }
        commands[command_count] = lifecycle_command;
        command_count += 1;
        commands[command_count] = contact_command;
        command_count += 1;
        if (input.confirm_vat_registration) {
            commands[command_count] = .{ .create_tax_type_registration = .{
                .taxpayer_id = unit.revision.taxpayer_id,
                .registration_unit_id = unit.revision.registration_unit_id,
                .registration_id = vat_registration_id.?,
                .revision_id = vat_revision_id.?,
                .effective_from = effective_from,
                .tax_type = .vat,
                .status = .confirmed_active,
                .evidence_id = evidence_id,
            } };
            command_count += 1;
        }
        var assertions: [4]registration_ledger.EvidenceAssertionWrite = undefined;
        assertions[0] = .{
            .id = taxpayer_assertion_id,
            .evidence_id = evidence_id,
            .taxpayer_id = unit.revision.taxpayer_id,
            .effective_from = effective_from,
            .fact = .{ .taxpayer_tin_root = .{
                .tin_root = facts.observed_tin_root,
            } },
        };
        assertions[1] = .{
            .id = lifecycle_assertion_id,
            .evidence_id = evidence_id,
            .taxpayer_id = unit.revision.taxpayer_id,
            .registration_unit_id = unit.revision.registration_unit_id,
            .effective_from = effective_from,
            .fact = .{ .registration_unit = .{
                .branch_code = observed_code,
                .status = .confirmed_active,
                .rdo_code = observed_rdo,
            } },
        };
        assertions[2] = .{
            .id = contact_assertion_id,
            .evidence_id = evidence_id,
            .taxpayer_id = unit.revision.taxpayer_id,
            .registration_unit_id = unit.revision.registration_unit_id,
            .effective_from = effective_from,
            .fact = .{ .registration_unit_contact = contact },
        };
        var assertion_count: usize = 3;
        if (input.confirm_vat_registration) {
            assertions[assertion_count] = .{
                .id = vat_assertion_id.?,
                .evidence_id = evidence_id,
                .taxpayer_id = unit.revision.taxpayer_id,
                .registration_unit_id = unit.revision.registration_unit_id,
                .effective_from = effective_from,
                .fact = .{ .tax_type_registration = .{
                    .tax_type = .vat,
                    .status = .confirmed_active,
                } },
            };
            assertion_count += 1;
        }
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = .{
                .id = evidence_id,
                .source_kind = switch (input.reviewed_evidence.source_kind) {
                    .cor => .cor,
                    .ecor => .ecor,
                    .bir_registration_record => .bir_registration_record,
                    .migration_record => .migration_record,
                    .other_reviewed => .other_reviewed,
                },
                .sha256 = canonical_digest.asSlice(),
                .display_name = evidence_name,
                .byte_size = byte_size,
                .captured_on = captured_on,
                .storage = .{ .protected_local_path = evidence_path },
            },
            .initial_review = .{
                .id = review_id,
                .evidence_id = evidence_id,
                .state = .accepted,
                .reviewer = .{ .local_owner = local_owner_id },
                .reviewed_at_unix_seconds = input.reviewed_evidence.reviewed_at_unix_seconds,
                .reason = registrationUnitReviewReason(
                    input.reviewed_evidence.source_kind,
                ),
            },
            .assertions = assertions[0..assertion_count],
            .commands = commands[0..command_count],
        }) catch {
            self.action_status = .write_failed;
            return false;
        };
        self.action_status = .unit_confirmed;
        return true;
    }

    /// Records an active VAT registration after the Registration Unit itself
    /// has already been confirmed. This deliberately asserts only the VAT
    /// fact: it cannot revise taxpayer identity, unit lifecycle, Branch Code,
    /// RDO, contact details, or any existing tax-registration shell.
    pub fn recordSelectedHeadOfficeVatRegistration(
        self: *State,
        ledger: anytype,
        input: VatRegistrationInput,
    ) bool {
        const unit = self.selectedRegistrationUnit() orelse {
            self.action_status = .no_registration_unit_selected;
            return false;
        };
        const identity = self.selected_identity orelse {
            self.action_status = .write_failed;
            return false;
        };
        if (!identity.taxpayer_id.eql(&unit.revision.taxpayer_id)) {
            self.action_status = .write_failed;
            return false;
        }
        if (!self.selectedHeadOfficeVatRegistrationRepairable()) {
            self.action_status = .vat_registration_not_recordable;
            return false;
        }
        if (!input.assert_active_vat_registration) {
            self.action_status = .vat_registration_assertion_required;
            return false;
        }
        const observed_tin_root = registration.Tin9.parse(
            input.observed_tin_root,
        ) catch {
            self.action_status = .invalid_observed_tin_root;
            return false;
        };
        if (!observed_tin_root.eql(&identity.tin_root)) {
            self.action_status = .observed_tin_root_mismatch;
            return false;
        }
        const reviewed = self.parseReviewedEvidence(
            input.reviewed_evidence,
        ) orelse return false;
        if (!unit.revision.effective.contains(reviewed.effective_from)) {
            self.action_status = .invalid_effective_date;
            return false;
        }

        const evidence_id = freshId(registration.RegistrationEvidenceId, ledger) catch {
            self.action_status = .write_failed;
            return false;
        };
        const review_id = freshId(
            registration.RegistrationEvidenceReviewDecisionId,
            ledger,
        ) catch {
            self.action_status = .write_failed;
            return false;
        };
        const taxpayer_assertion_id = freshId(
            registration.RegistrationEvidenceAssertionId,
            ledger,
        ) catch {
            self.action_status = .write_failed;
            return false;
        };
        const vat_assertion_id = freshId(
            registration.RegistrationEvidenceAssertionId,
            ledger,
        ) catch {
            self.action_status = .write_failed;
            return false;
        };
        const registration_id = freshId(
            registration.TaxTypeRegistrationId,
            ledger,
        ) catch {
            self.action_status = .write_failed;
            return false;
        };
        const revision_id = freshId(
            registration.TaxTypeRegistrationRevisionId,
            ledger,
        ) catch {
            self.action_status = .write_failed;
            return false;
        };
        const local_owner_id = ledger.localOwnerId() catch {
            self.action_status = .write_failed;
            return false;
        };
        const assertions = [_]registration_ledger.EvidenceAssertionWrite{
            .{
                .id = taxpayer_assertion_id,
                .evidence_id = evidence_id,
                .taxpayer_id = unit.revision.taxpayer_id,
                .effective_from = reviewed.effective_from,
                .fact = .{ .taxpayer_tin_root = .{
                    .tin_root = observed_tin_root,
                } },
            },
            .{
                .id = vat_assertion_id,
                .evidence_id = evidence_id,
                .taxpayer_id = unit.revision.taxpayer_id,
                .registration_unit_id = unit.revision.registration_unit_id,
                .effective_from = reviewed.effective_from,
                .fact = .{ .tax_type_registration = .{
                    .tax_type = .vat,
                    .status = .confirmed_active,
                } },
            },
        };
        const commands = [_]registration.RegistrationCommand{.{
            .create_tax_type_registration = .{
                .taxpayer_id = unit.revision.taxpayer_id,
                .registration_unit_id = unit.revision.registration_unit_id,
                .registration_id = registration_id,
                .revision_id = revision_id,
                .effective_from = reviewed.effective_from,
                .tax_type = .vat,
                .status = .confirmed_active,
                .evidence_id = evidence_id,
            },
        }};
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = .{
                .id = evidence_id,
                .source_kind = switch (input.reviewed_evidence.source_kind) {
                    .cor => .cor,
                    .ecor => .ecor,
                    .bir_registration_record => .bir_registration_record,
                    .migration_record => .migration_record,
                    .other_reviewed => .other_reviewed,
                },
                .sha256 = reviewed.digest.asSlice(),
                .display_name = reviewed.display_name,
                .byte_size = reviewed.byte_size,
                .captured_on = reviewed.captured_on,
                .storage = .{ .protected_local_path = reviewed.path },
            },
            .initial_review = .{
                .id = review_id,
                .evidence_id = evidence_id,
                .state = .accepted,
                .reviewer = .{ .local_owner = local_owner_id },
                .reviewed_at_unix_seconds = input.reviewed_evidence.reviewed_at_unix_seconds,
                .reason = vatRegistrationReviewReason(
                    input.reviewed_evidence.source_kind,
                ),
            },
            .assertions = &assertions,
            .commands = &commands,
        }) catch |err| {
            self.action_status = if (err == error.DuplicateTaxTypeRegistration)
                .vat_registration_already_exists
            else
                .write_failed;
            return false;
        };
        self.action_status = .vat_registration_recorded;
        return true;
    }

    fn syncTaxpayerSelection(self: *State) void {
        for (self.taxpayers[0..self.taxpayer_count], 0..) |*row, index| {
            row.selected = self.selected_taxpayer_index == index;
        }
    }

    fn syncRegistrationUnitSelection(self: *State) void {
        for (self.units[0..self.unit_count], 0..) |*row, index| {
            row.selected = self.selected_registration_unit_index == index;
        }
    }

    fn rebuildSourceWorkspaceView(self: *State) void {
        self.source_row_count = 0;
        self.source_unresolved_count = 0;
        self.source_invalid_count = 0;

        const taxpayer = self.selectedTaxpayer() orelse return;
        const unit = self.selectedRegistrationUnit() orelse return;
        const civil_period = quarterPeriod(
            self.period_year,
            self.period_quarter,
        ) catch return;
        var filtered: [max_source_records]SourceRecord = undefined;
        const result = source_attribution.filterInto(
            self.source_records[0..self.source_record_count],
            .{
                .taxpayer_id = taxpayer.taxpayer_id,
                .registration_unit_id = unit.revision.registration_unit_id,
                .period = .{
                    .from = civil_period.from,
                    .until = civil_period.until,
                },
            },
            &filtered,
        );

        self.source_invalid_count = result.invalid_count;
        self.source_unresolved_count = result.unresolved_count;
        for (filtered[0..result.visible_count], 0..) |record, index| {
            self.source_rows[index] = .{ .id = index, .record = record };
        }
        self.source_row_count = result.visible_count;
        // `source_records` and `source_rows` share the same capacity, so this
        // can only trip if that invariant changes.
        std.debug.assert(!result.output_truncated);
    }

    fn setRequestedPeriod(
        self: *State,
        period_year: u16,
        period_quarter: u8,
    ) void {
        self.period_year = period_year;
        self.period_quarter = period_quarter;
        self.rebuildSourceWorkspaceView();
    }

    fn loadSelectedSnapshot(
        self: *State,
        ledger: anytype,
        as_of: registration.Date,
        previous_registration_unit: ?registration.RegistrationUnitId,
    ) !void {
        self.unit_count = 0;
        self.units_truncated = false;
        self.selected_registration_unit_index = null;
        self.selected_identity = null;
        self.snapshot_review_required = false;
        self.suggested_branch_code = null;
        self.branch_suggestion_incomplete = false;
        self.workspace_status = if (self.taxpayer_count == 0) .no_data else .review_required;
        self.rebuildSourceWorkspaceView();

        const taxpayer = self.selectedTaxpayer() orelse return;
        var snapshot = try ledger.snapshot(.{
            .taxpayer_id = taxpayer.taxpayer_id,
            .start = as_of,
            .end = as_of,
        });
        defer snapshot.deinit(ledger.allocator);
        switch (snapshot) {
            .review_required => {
                self.snapshot_review_required = true;
                self.workspace_status = .review_required;
            },
            .resolved => |resolved| {
                self.selected_identity = resolved.taxpayer_identity;
                self.workspace_status = aggregateStatus(resolved.units);
                self.units_truncated = resolved.units.len > self.units.len;
                for (resolved.units[0..@min(resolved.units.len, self.units.len)]) |revision| {
                    var row = makeUnitRow(self.unit_count, revision);
                    row.contact_revision = contactRevisionForUnit(
                        resolved.contacts,
                        revision.registration_unit_id,
                    );
                    row.vat_registration_state = vatRegistrationStateForUnit(
                        resolved.tax_type_registrations,
                        revision.registration_unit_id,
                    );
                    self.units[self.unit_count] = row;
                    self.unit_count += 1;
                }
                std.mem.sort(UnitRow, self.units[0..self.unit_count], {}, unitPrecedes);
                for (self.units[0..self.unit_count], 0..) |*row, index| row.id = index;

                if (previous_registration_unit) |wanted| {
                    for (self.units[0..self.unit_count], 0..) |row, index| {
                        if (wanted.eql(&row.revision.registration_unit_id)) {
                            self.selected_registration_unit_index = index;
                            break;
                        }
                    }
                }
                if (self.selected_registration_unit_index == null and self.unit_count != 0) {
                    self.selected_registration_unit_index = 0;
                }
                self.syncRegistrationUnitSelection();

                var occupied: [max_occupied_branch_codes]registration.BranchCode5 = undefined;
                var occupied_count: usize = 0;
                var occupied_complete = resolved.lineage_complete;
                for (resolved.lineage) |entry| {
                    if (!appendOccupiedCode(&occupied, &occupied_count, entry.code)) {
                        occupied_complete = false;
                    }
                }
                for (resolved.units) |unit| {
                    if (unit.branch_code_evidence.knownCode()) |code| {
                        if (!appendOccupiedCode(&occupied, &occupied_count, code)) {
                            occupied_complete = false;
                        }
                    }
                }
                self.branch_suggestion_incomplete = !occupied_complete;
                self.suggested_branch_code = if (occupied_complete)
                    if (registration.suggestLowestUnusedBranchCode(
                        occupied[0..occupied_count],
                    )) |suggestion| suggestion.code else null
                else
                    null;
            },
        }
        self.rebuildSourceWorkspaceView();
    }

    fn resetResolvedPresentation(self: *State) void {
        self.planning_status = .unavailable;
        self.integration_reason = .none;
        self.planning_reason_count = 0;
        self.effective_policy_resolved = false;
        self.resolved_filing_code = null;
        self.resolved_filing_rdo_code = null;
        self.resolved_coverage_count = 0;
        self.coverage_count = 0;
        self.coverage_truncated = false;
        self.resolved_obligation_count = 0;
        self.resolved_form_revision = null;
        self.resolved_policy_revision_id = null;
        self.resolved_policy_evidence_id = null;
        self.resolved_policy_capability = null;
        self.resolved_scope_category = null;
        self.resolved_venue = null;
        self.decision_hash_present = false;
        self.projection_filer_tin_len = 0;
        self.resolved_preview_snapshot = null;
        self.provenance_validated = false;
    }

    fn failIntegration(self: *State, reason: IntegrationReason) void {
        self.planning_status = .integration_error;
        self.integration_reason = reason;
    }

    pub fn reportLoadFailure(self: *State) void {
        self.resetResolvedPresentation();
        self.action_status = .load_failed;
        self.workspace_status = .review_required;
        self.failIntegration(.workspace_load_failed);
    }

    /// Presents a planner result only when this compact workspace can preserve
    /// every binding without choosing among obligations or truncating coverage.
    /// Retains the planner's legal-scope decision when only the filing-unit
    /// contact/header projection remains unresolved. These fields are
    /// presentation-only: no projection context, provenance snapshot, draft,
    /// or preview access is created from this partial result.
    fn presentResolvedLegalScope(
        self: *State,
        scope: planner.ResolvedLegalFilingScope,
    ) void {
        self.resolved_coverage_count = scope.coverage.len;
        if (scope.coverage.len > self.coverage_rows.len) {
            self.coverage_truncated = true;
            self.failIntegration(.coverage_capacity_exceeded);
            return;
        }

        const root_digits = scope.taxpayer_identity.tin_root.asDigits();
        const branch_digits = scope.filing_branch_code.asDigits();
        const written = std.fmt.bufPrint(
            &self.projection_filer_tin,
            "***-***-{s}-{s}",
            .{ root_digits[6..9], branch_digits },
        ) catch {
            self.failIntegration(.filer_identity_projection_failed);
            return;
        };

        for (scope.coverage, 0..) |binding, coverage_index| {
            self.coverage_rows[coverage_index] = .{
                .id = coverage_index,
                .registration_unit_id = binding.registration_unit_id,
                .registration_unit_revision_id = binding.registration_unit_revision_id,
                .branch_code = binding.branch_code,
                .branch_code_evidence_id = binding.branch_code_evidence_id,
            };
        }

        self.coverage_count = scope.coverage.len;
        self.resolved_filing_code = scope.filing_branch_code;
        self.resolved_filing_rdo_code = scope.filing_unit_rdo_code;
        self.resolved_form_revision = scope.form_revision;
        self.resolved_policy_revision_id = scope.policy_revision_id;
        self.resolved_policy_evidence_id = if (scope.policy_evidence_ids.len == 0)
            null
        else
            scope.policy_evidence_ids[0];
        self.resolved_policy_capability = scope.policy_capability;
        self.resolved_scope_category = .head_office_consolidated;
        self.resolved_venue = .review_required;
        self.decision_hash_text = std.fmt.bytesToHex(scope.resolution_hash, .lower);
        self.decision_hash_present = true;
        self.projection_filer_tin_len = @intCast(written.len);
        self.effective_policy_resolved = true;
    }

    pub fn presentResolvedPlan(
        self: *State,
        allocator: std.mem.Allocator,
        plan: *const planner.ResolvedFilingPlan,
        policy_catalog: policy.FilingPolicyCatalog,
    ) void {
        self.resetResolvedPresentation();

        switch (plan.*) {
            .not_applicable => self.planning_status = .not_applicable,
            .review_required => |review| {
                self.planning_status = .review_required;
                if (review.issues.len > self.planning_reasons.len) {
                    self.failIntegration(.review_issue_capacity_exceeded);
                    return;
                }
                for (review.issues) |issue| {
                    self.planning_reasons[self.planning_reason_count] =
                        reviewIssueRow(
                            self.planning_reason_count,
                            issue,
                            self.units[0..self.unit_count],
                        );
                    self.planning_reason_count += 1;
                }
                if (review.resolved_legal_scope) |scope| {
                    self.presentResolvedLegalScope(scope);
                }
            },
            .obligations => |obligations| {
                self.resolved_obligation_count = obligations.len;
                if (obligations.len != 1) {
                    self.failIntegration(.unexpected_obligation_count);
                    return;
                }

                const obligation = &obligations[0];
                self.resolved_coverage_count = obligation.coverage.len;
                if (obligation.coverage.len > self.coverage_rows.len) {
                    self.coverage_truncated = true;
                    self.failIntegration(.coverage_capacity_exceeded);
                    return;
                }
                if (obligation.reviewed_evidence_bindings.len > max_reviewed_evidence_rows) {
                    self.failIntegration(.reviewed_evidence_capacity_exceeded);
                    return;
                }
                if (obligation.policy_evidence_ids.len == 0) {
                    self.failIntegration(.policy_evidence_metadata_unavailable);
                    return;
                }
                if (obligation.policy_evidence_ids.len > max_policy_evidence_rows) {
                    self.failIntegration(.policy_evidence_capacity_exceeded);
                    return;
                }
                var policy_evidence_rows: [max_policy_evidence_rows]PolicyEvidenceRow = undefined;
                for (
                    obligation.policy_evidence_ids,
                    0..,
                ) |evidence_id, evidence_index| {
                    const evidence = policy_catalog.evidenceForRevision(
                        obligation.policy_revision_id,
                        evidence_id,
                    ) orelse {
                        self.failIntegration(.policy_evidence_metadata_unavailable);
                        return;
                    };
                    policy_evidence_rows[evidence_index] = PolicyEvidenceRow.init(
                        evidence_index,
                        evidence,
                    ) catch {
                        self.failIntegration(.policy_evidence_metadata_unavailable);
                        return;
                    };
                }

                const context = projection.FilingProjectionContext.init(obligation) catch {
                    self.failIntegration(.projection_context_invalid);
                    return;
                };
                // Preview-only structural validation. Draft creation owns the
                // separate lifecycle for retaining immutable provenance.
                var transient_provenance = provenance.ScopeProvenance.capture(
                    allocator,
                    obligation,
                ) catch {
                    self.failIntegration(.provenance_validation_failed);
                    return;
                };
                defer transient_provenance.deinit(allocator);

                const filer_tin = context.filerTin() catch {
                    self.failIntegration(.filer_identity_projection_failed);
                    return;
                };
                const digits = filer_tin.asDigits();
                const written = std.fmt.bufPrint(
                    &self.projection_filer_tin,
                    "***-***-{s}-{s}",
                    .{ digits[6..9], digits[9..14] },
                ) catch {
                    self.failIntegration(.filer_identity_projection_failed);
                    return;
                };

                for (obligation.coverage, 0..) |binding, coverage_index| {
                    self.coverage_rows[coverage_index] = .{
                        .id = coverage_index,
                        .registration_unit_id = binding.registration_unit_id,
                        .registration_unit_revision_id = binding.registration_unit_revision_id,
                        .branch_code = binding.branch_code,
                        .branch_code_evidence_id = binding.branch_code_evidence_id,
                    };
                }
                self.coverage_count = obligation.coverage.len;
                self.resolved_filing_code = obligation.filing_branch_code;
                self.resolved_filing_rdo_code = obligation.filing_unit_rdo_code;
                self.resolved_form_revision = obligation.form_revision;
                self.resolved_policy_revision_id = obligation.policy_revision_id;
                self.resolved_policy_evidence_id = if (obligation.policy_evidence_ids.len == 0)
                    null
                else
                    obligation.policy_evidence_ids[0];
                self.resolved_policy_capability = obligation.policy_capability;
                self.resolved_scope_category = .head_office_consolidated;
                self.resolved_venue = obligation.filing_venue_resolution;
                self.decision_hash_text = std.fmt.bytesToHex(
                    obligation.resolution_hash,
                    .lower,
                );
                self.decision_hash_present = true;
                self.projection_filer_tin_len = @intCast(written.len);
                const source_workspace_unit = self.selectedRegistrationUnit() orelse {
                    self.failIntegration(.workspace_load_failed);
                    return;
                };
                var preview_snapshot = Resolved2550QPreviewSnapshot{
                    .projection_context = context,
                    .source_workspace_unit = source_workspace_unit.*,
                    .source_row_count = self.source_row_count,
                    .source_review_required_count = self.sourceWorkspaceUnresolvedCount(),
                    .source_input_truncated = self.source_records_truncated,
                    .coverage_count = obligation.coverage.len,
                    .scope_category = .head_office_consolidated,
                    .policy_revision_id = obligation.policy_revision_id,
                    .policy_evidence_id = self.resolved_policy_evidence_id,
                    .policy_evidence_rows = policy_evidence_rows,
                    .policy_capability = obligation.policy_capability,
                    .filing_capability = obligation.filing_capability,
                    .filing_venue_resolution = obligation.filing_venue_resolution,
                    .reviewed_evidence_binding_count = obligation.reviewed_evidence_bindings.len,
                    .policy_evidence_count = obligation.policy_evidence_ids.len,
                    .decision_hash_text = self.decision_hash_text,
                };
                @memcpy(
                    preview_snapshot.source_rows[0..self.source_row_count],
                    self.source_rows[0..self.source_row_count],
                );
                @memcpy(
                    preview_snapshot.coverage_rows[0..obligation.coverage.len],
                    self.coverage_rows[0..obligation.coverage.len],
                );
                for (obligation.reviewed_evidence_bindings, 0..) |binding, evidence_index| {
                    preview_snapshot.reviewed_evidence_rows[evidence_index] = .{
                        .id = evidence_index,
                        .binding = binding,
                    };
                }
                self.resolved_preview_snapshot = preview_snapshot;
                self.provenance_validated = true;
                self.effective_policy_resolved = true;
                self.planning_status = switch (obligation.filing_capability) {
                    .fileable => .resolved_fileable,
                    .not_fileable => .resolved_not_fileable,
                };
            },
        }
    }

    fn preview(
        self: *State,
        allocator: std.mem.Allocator,
        ledger: anytype,
        evidence_integrity_verifier: anytype,
        policy_catalog: policy.FilingPolicyCatalog,
    ) !void {
        self.policy_catalog_missing = policy_catalog.revisions.len == 0;
        self.resetResolvedPresentation();

        if (self.taxpayers_truncated) {
            self.workspace_status = .review_required;
            self.failIntegration(.taxpayer_list_truncated);
            return;
        }
        if (self.units_truncated) {
            self.workspace_status = .review_required;
            self.failIntegration(.unit_list_truncated);
            return;
        }

        const taxpayer = self.selectedTaxpayer() orelse return;
        const civil_period = quarterPeriod(self.period_year, self.period_quarter) catch {
            self.failIntegration(.invalid_preview_period);
            return;
        };
        const filing_planner = planner.FilingPlanner.init(policy_catalog);
        var plan = try filing_planner.plan(
            allocator,
            ledger,
            evidence_integrity_verifier,
            .{
                .taxpayer_id = taxpayer.taxpayer_id,
                .form_revision = requested_preview_form_revision,
                .civil_period = civil_period,
            },
        );
        defer plan.deinit(allocator);

        self.presentResolvedPlan(allocator, &plan, policy_catalog);
    }
};

pub fn workspaceStatusLabel(status: WorkspaceStatus) []const u8 {
    return switch (status) {
        .no_data => "No canonical registration data",
        .pending_evidence => "Pending evidence",
        .confirmed_active => "Confirmed active",
        .confirmed_closed => "Confirmed closed",
        .legacy_unresolved => "Legacy unresolved",
        .review_required => "Review Required",
    };
}

fn setReviewRowText(
    output: *[96]u8,
    output_len: *u8,
    comptime format: []const u8,
    args: anytype,
) void {
    const written = std.fmt.bufPrint(output, format, args) catch {
        const fallback = "Affected filing-scope fact";
        @memcpy(output[0..fallback.len], fallback);
        output_len.* = @intCast(fallback.len);
        return;
    };
    output_len.* = @intCast(written.len);
}

fn setRegistrationUnitReviewSubject(
    row: *ReviewIssueRow,
    units: []const UnitRow,
    registration_unit_id: registration.RegistrationUnitId,
) void {
    for (units) |unit| {
        if (!unit.revision.registration_unit_id.eql(&registration_unit_id)) {
            continue;
        }
        setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "{s} {s}",
            .{ unit.kindLabel(), unit.codeLabel() },
        );
        return;
    }
    setReviewRowText(
        &row.subject_text,
        &row.subject_text_len,
        "{s}",
        .{"Registration Unit"},
    );
}

fn reviewIssueRow(
    id: usize,
    issue: planner.ReviewIssue,
    units: []const UnitRow,
) ReviewIssueRow {
    var row: ReviewIssueRow = .{ .id = id, .issue = issue };
    switch (issue.subject) {
        .planning_request => setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "{s}",
            .{"Filing request"},
        ),
        .filing_period => |period| setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "period {d:0>4}-{d:0>2}-{d:0>2} to {d:0>4}-{d:0>2}-{d:0>2}",
            .{
                period.from.year,
                period.from.month,
                period.from.day,
                period.until.year,
                period.until.month,
                period.until.day,
            },
        ),
        .taxpayer => setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "{s}",
            .{"Selected Taxpayer"},
        ),
        .taxpayer_revision => setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "{s}",
            .{"Taxpayer identity revision"},
        ),
        .form_revision => |form| setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "BIR Form {s} {s}",
            .{ form.code.asSlice(), form.revision.asSlice() },
        ),
        .policy_endpoint => |endpoint| setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "policy for {s} {s} on {d:0>4}-{d:0>2}-{d:0>2}",
            .{
                endpoint.form_revision.code.asSlice(),
                endpoint.form_revision.revision.asSlice(),
                endpoint.date.year,
                endpoint.date.month,
                endpoint.date.day,
            },
        ),
        .policy_revision => |policy_revision_id| setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "policy {s}",
            .{policy_revision_id.asSlice()},
        ),
        .registration_unit => |registration_unit_id| {
            setRegistrationUnitReviewSubject(&row, units, registration_unit_id);
        },
        .registration_unit_revision => |revision_id| {
            var matched = false;
            for (units) |unit| {
                if (!unit.revision.id.eql(&revision_id)) continue;
                setRegistrationUnitReviewSubject(
                    &row,
                    units,
                    unit.revision.registration_unit_id,
                );
                matched = true;
                break;
            }
            if (!matched) setReviewRowText(
                &row.subject_text,
                &row.subject_text_len,
                "{s}",
                .{"Registration Unit revision"},
            );
        },
        .registration_unit_contact_revision => setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "{s}",
            .{"Filing Unit contact revision"},
        ),
        .tax_type_registration,
        .tax_type_registration_revision,
        => setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "{s}",
            .{"VAT registration"},
        ),
        .evidence => setReviewRowText(
            &row.subject_text,
            &row.subject_text_len,
            "{s}",
            .{"Registration evidence"},
        ),
    }

    switch (issue.detail) {
        .none => {},
        .policy_catalog_validation => |err| setReviewRowText(
            &row.detail_text,
            &row.detail_text_len,
            "{s}",
            .{@errorName(err)},
        ),
        .policy_selection => |selection_issue| setReviewRowText(
            &row.detail_text,
            &row.detail_text_len,
            "{s}",
            .{@tagName(std.meta.activeTag(selection_issue))},
        ),
        .registration_validation => |err| setReviewRowText(
            &row.detail_text,
            &row.detail_text_len,
            "{s}",
            .{@errorName(err)},
        ),
        .evidence_integrity => |cause| setReviewRowText(
            &row.detail_text,
            &row.detail_text_len,
            "{s}",
            .{@tagName(cause)},
        ),
    }
    return row;
}

pub fn reviewReasonLabel(reason: planner.ReviewReason) []const u8 {
    return switch (reason) {
        .invalid_filing_period => "The filing period is invalid.",
        .unsupported_filing_period_semantics => "The policy does not support this period type.",
        .unsupported_special_context => "Required special filing context is unsupported.",
        .taxpayer_identity_mismatch => "The plan and taxpayer identity do not match.",
        .invalid_taxpayer_identity => "The taxpayer identity revision is invalid.",
        .taxpayer_identity_not_effective_for_period => "The taxpayer identity does not cover the entire filing period.",
        .taxpayer_identity_missing => "No taxpayer identity covers the requested filing period.",
        .taxpayer_identity_changed_during_period => "The taxpayer identity changed during the requested filing period.",
        .evidence_review_missing => "Required registration evidence has not been reviewed.",
        .evidence_rejected => "Required registration evidence was rejected.",
        .evidence_superseded => "Required registration evidence was superseded.",
        .evidence_protected_bytes_missing => "Protected registration evidence is missing. Reattach and review the source document before resolving filing scope.",
        .evidence_protected_bytes_unreadable => "Protected registration evidence cannot be read. Restore or reattach the reviewed document before resolving filing scope.",
        .evidence_protected_bytes_size_mismatch => "Protected registration evidence has a different file size. Treat it as changed and review the source document again.",
        .evidence_protected_bytes_digest_mismatch => "Protected registration evidence no longer matches its recorded SHA-256 digest. Review the source document again.",
        .evidence_stored_metadata_invalid => "Stored registration-evidence metadata is invalid. Repair the evidence record before resolving filing scope.",
        .evidence_storage_backend_unverifiable => "The registration-evidence storage backend cannot verify protected bytes. Filing scope remains Review Required.",
        .missing_effective_policy => "No reviewed filing-scope policy exists for this form revision and period.",
        .conflicting_effective_policy => "More than one filing-scope policy is effective.",
        .invalid_effective_policy => "The effective filing-scope policy is invalid.",
        .invalid_policy_catalog => "The filing policy catalog is invalid.",
        .policy_requires_review => "The filing policy still requires legal-policy review.",
        .policy_changed_during_period => "The filing policy changes during the period.",
        .unsupported_form_revision => "This exact form revision is not supported by the planner.",
        .unsupported_policy_category => "This filing-policy category is not implemented.",
        .missing_head_office => "No effective head-office Registration Unit exists.",
        .conflicting_head_office => "More than one effective head office exists.",
        .head_office_not_confirmed => "The head office is not evidence-confirmed and active.",
        .head_office_branch_code_invalid => "The head-office Branch Code must be 00000.",
        .registration_unit_taxpayer_mismatch => "A Registration Unit belongs to another taxpayer.",
        .invalid_registration_unit => "A Registration Unit revision is invalid.",
        .registration_unit_mid_period_state_change => "A Registration Unit changes state during the filing period.",
        .registration_unit_pending_evidence => "A covered Registration Unit is pending evidence.",
        .registration_unit_legacy_unresolved => "A covered Registration Unit has an unresolved legacy branch suffix.",
        .registration_unit_closed => "A required Registration Unit is closed.",
        .missing_filing_unit_contact => "The Filing Unit has no evidence-backed registered address and contact revision.",
        .filing_unit_contact_mid_period_change => "The Filing Unit contact facts change during the filing period.",
        .invalid_filing_unit_contact => "The Filing Unit contact revision is invalid.",
        .filing_unit_contact_mismatch => "The Filing Unit contact revision belongs to another taxpayer or Registration Unit.",
        .missing_vat_registration_evidence => "Reviewed VAT registration evidence is missing.",
        .conflicting_vat_registration_evidence => "VAT registration evidence conflicts for this period.",
        .vat_registration_not_bound_to_head_office => "The VAT registration is not bound to the head office.",
        .vat_registration_pending_evidence => "VAT registration is pending evidence.",
        .vat_registration_legacy_unresolved => "VAT registration is legacy unresolved.",
        .vat_registration_mid_period_state_change => "VAT registration changes during the filing period.",
    };
}

fn aggregateStatus(units: []const registration.RegistrationUnitRevision) WorkspaceStatus {
    if (units.len == 0) return .review_required;
    var has_pending = false;
    var has_active = false;
    var has_legacy = false;
    var has_closed = false;
    for (units) |unit| switch (unit.status) {
        .pending_evidence => has_pending = true,
        .confirmed_active => has_active = true,
        .confirmed_closed => has_closed = true,
        .legacy_unresolved => has_legacy = true,
    };
    if (has_legacy) return .legacy_unresolved;
    if (has_pending) return .pending_evidence;
    if (has_active) return .confirmed_active;
    if (has_closed) return .confirmed_closed;
    return .review_required;
}

fn makeUnitRow(
    id: usize,
    revision: registration.RegistrationUnitRevision,
) UnitRow {
    var row = UnitRow{ .id = id, .revision = revision };
    const text = switch (revision.branch_code_evidence) {
        .unconfirmed => |code| std.fmt.bufPrint(
            &row.code_text,
            "{s} candidate",
            .{code.asDigits()},
        ) catch "candidate",
        .confirmed => |confirmed| std.fmt.bufPrint(
            &row.code_text,
            "{s}",
            .{confirmed.code.asDigits()},
        ) catch "confirmed",
        .legacy_unresolved => |suffix| std.fmt.bufPrint(
            &row.code_text,
            "legacy {s}",
            .{suffix.asDigits()},
        ) catch "legacy unresolved",
    };
    row.code_text_len = @intCast(text.len);
    return row;
}

fn contactRevisionForUnit(
    contacts: []const registration.RegistrationUnitContactRevision,
    registration_unit_id: registration.RegistrationUnitId,
) ?registration.RegistrationUnitContactRevision {
    for (contacts) |contact_revision| {
        if (contact_revision.registration_unit_id.eql(&registration_unit_id)) {
            return contact_revision;
        }
    }
    return null;
}

fn vatRegistrationStateForUnit(
    registrations: []const registration.TaxTypeRegistrationRevision,
    registration_unit_id: registration.RegistrationUnitId,
) VatRegistrationState {
    var found = false;
    var state: VatRegistrationState = .absent;
    for (registrations) |registration_revision| {
        if (registration_revision.tax_type != .vat or
            !registration_revision.registration_unit_id.eql(&registration_unit_id))
        {
            continue;
        }
        if (found) return .requires_review;
        found = true;
        state = if (registration_revision.status == .confirmed_active)
            .confirmed_active
        else
            .requires_review;
    }
    return state;
}

fn unitPrecedes(_: void, left: UnitRow, right: UnitRow) bool {
    if (left.revision.kind != right.revision.kind) {
        return left.revision.kind == .head_office;
    }
    const code_order = std.mem.order(u8, left.codeLabel(), right.codeLabel());
    if (code_order != .eq) return code_order == .lt;
    return std.mem.order(
        u8,
        left.revision.registration_unit_id.asSlice(),
        right.revision.registration_unit_id.asSlice(),
    ) == .lt;
}

fn writeMaskedTin(tin: registration.Tin9, output: *[11]u8) void {
    _ = std.fmt.bufPrint(
        output,
        "***-***-{s}",
        .{tin.asDigits()[6..9]},
    ) catch unreachable;
}

fn appendOccupiedCode(
    output: *[max_occupied_branch_codes]registration.BranchCode5,
    count: *usize,
    code: registration.BranchCode5,
) bool {
    for (output[0..count.*]) |existing| {
        if (existing.eql(&code)) return true;
    }
    if (count.* == output.len) return false;
    output[count.*] = code;
    count.* += 1;
    return true;
}

fn freshId(comptime Id: type, ledger: anytype) !Id {
    const raw = try ledger.generateOpaqueId();
    return Id.parse(&raw);
}

fn parseReviewedEvidenceValue(
    input: ReviewedEvidenceInput,
) ReviewedEvidenceParseError!ParsedReviewedEvidence {
    const effective_from = registration.Date.parseIso(input.effective_from) catch
        return error.InvalidEffectiveDate;
    const captured_on = registration.Date.parseIso(input.evidence_captured_on) catch
        return error.InvalidEvidenceDate;
    const evidence_path = std.mem.trim(u8, input.evidence_path, " \t\r\n");
    if (evidence_path.len == 0 or
        evidence_path.len > storage_contract.max_evidence_storage_reference_bytes)
    {
        return error.InvalidEvidencePath;
    }
    const evidence_name = std.mem.trim(u8, input.evidence_display_name, " \t\r\n");
    if (evidence_name.len == 0 or evidence_name.len > 255) {
        return error.InvalidEvidenceName;
    }
    const digest_text = std.mem.trim(u8, input.evidence_sha256, " \t\r\n");
    const digest = registration.Sha256Digest.parse(digest_text) catch
        return error.InvalidEvidenceDigest;
    const byte_size_text = std.mem.trim(u8, input.evidence_byte_size, " \t\r\n");
    const byte_size = std.fmt.parseInt(u64, byte_size_text, 10) catch
        return error.InvalidEvidenceSize;
    if (byte_size == 0) return error.InvalidEvidenceSize;
    return .{
        .effective_from = effective_from,
        .path = evidence_path,
        .display_name = evidence_name,
        .digest = digest,
        .byte_size = byte_size,
        .captured_on = captured_on,
    };
}

fn registrationUnitReviewReason(source_kind: EvidenceSourceKind) []const u8 {
    return switch (source_kind) {
        .cor => "Human reviewed the selected Certificate of Registration (COR) against the entered Registration Unit facts.",
        .ecor => "Human reviewed the selected electronic Certificate of Registration (eCOR) against the entered Registration Unit facts.",
        .bir_registration_record => "Human reviewed the selected BIR registration record against the entered Registration Unit facts.",
        .migration_record => "Human reviewed the selected migration record against the entered Registration Unit facts.",
        .other_reviewed => "Human reviewed the selected other registration evidence against the entered Registration Unit facts.",
    };
}

fn vatRegistrationReviewReason(source_kind: EvidenceSourceKind) []const u8 {
    return switch (source_kind) {
        .cor => "Human reviewed the selected Certificate of Registration (COR) against the entered taxpayer TIN and for an active VAT registration.",
        .ecor => "Human reviewed the selected electronic Certificate of Registration (eCOR) against the entered taxpayer TIN and for an active VAT registration.",
        .bir_registration_record => "Human reviewed the selected BIR registration record against the entered taxpayer TIN and for an active VAT registration.",
        .migration_record => "Human reviewed the selected migration record against the entered taxpayer TIN and for an active VAT registration.",
        .other_reviewed => "Human reviewed the selected other registration evidence against the entered taxpayer TIN and for an active VAT registration.",
    };
}

fn reviewedEvidenceActionStatus(err: ReviewedEvidenceParseError) ActionStatus {
    return switch (err) {
        error.InvalidEffectiveDate => .invalid_effective_date,
        error.InvalidEvidenceDate => .invalid_evidence_date,
        error.InvalidEvidencePath => .invalid_evidence_path,
        error.InvalidEvidenceName => .invalid_evidence_name,
        error.InvalidEvidenceDigest => .invalid_evidence_digest,
        error.InvalidEvidenceSize => .invalid_evidence_size,
    };
}

fn parseConfirmationFactsValue(
    input: ConfirmationInput,
) ConfirmationFactsParseError!ParsedConfirmationFacts {
    const observed_tin_root = registration.Tin9.parse(input.observed_tin_root) catch
        return error.InvalidObservedTinRoot;
    const observed_code = registration.BranchCode5.parse(input.observed_branch_code) catch
        return error.InvalidBranchCode;
    const observed_rdo = parseOptionalRdo(input.observed_rdo_code) catch
        return error.InvalidRdoCode;
    const registered_address = profile_field.RegisteredAddress.parse(
        input.registered_address,
    ) catch return error.InvalidRegisteredAddress;
    const zip_code = parseOptionalZipCode(input.zip_code) catch
        return error.InvalidZipCode;
    const contact_number = parseOptionalContactNumber(input.contact_number) catch
        return error.InvalidContactNumber;
    const email_address = parseOptionalEmailAddress(input.email_address) catch
        return error.InvalidEmailAddress;
    return .{
        .observed_tin_root = observed_tin_root,
        .observed_code = observed_code,
        .observed_rdo = observed_rdo,
        .contact = .{
            .registered_address = registered_address,
            .zip_code = zip_code,
            .contact_number = contact_number,
            .email_address = email_address,
        },
    };
}

fn confirmationFactsActionStatus(err: ConfirmationFactsParseError) ActionStatus {
    return switch (err) {
        error.InvalidObservedTinRoot => .invalid_observed_tin_root,
        error.InvalidBranchCode => .invalid_branch_code,
        error.InvalidRdoCode => .invalid_rdo_code,
        error.InvalidRegisteredAddress => .invalid_registered_address,
        error.InvalidZipCode => .invalid_zip_code,
        error.InvalidContactNumber => .invalid_contact_number,
        error.InvalidEmailAddress => .invalid_email_address,
    };
}

fn parseOptionalRdo(raw: []const u8) !?registration.RdoCode3 {
    const value = std.mem.trim(u8, raw, " \t\r\n");
    if (value.len == 0) return null;
    return try registration.RdoCode3.parse(value);
}

fn parseOptionalZipCode(raw: []const u8) !?profile_field.ZipCode {
    const value = std.mem.trim(u8, raw, " \t\r\n");
    if (value.len == 0) return null;
    return try profile_field.ZipCode.parse(value);
}

fn parseOptionalContactNumber(raw: []const u8) !?profile_field.ContactNumber {
    const value = std.mem.trim(u8, raw, " \t\r\n");
    if (value.len == 0) return null;
    return try profile_field.ContactNumber.parse(value);
}

fn parseOptionalEmailAddress(raw: []const u8) !?profile_field.EmailAddress {
    const value = std.mem.trim(u8, raw, " \t\r\n");
    if (value.len == 0) return null;
    return try profile_field.EmailAddress.parse(value);
}

fn quarterPeriod(year: u16, quarter: u8) !planner.CivilPeriod {
    const bounds = switch (quarter) {
        1 => .{ @as(u8, 1), @as(u8, 3), @as(u8, 31) },
        2 => .{ @as(u8, 4), @as(u8, 6), @as(u8, 30) },
        3 => .{ @as(u8, 7), @as(u8, 9), @as(u8, 30) },
        4 => .{ @as(u8, 10), @as(u8, 12), @as(u8, 31) },
        else => return error.InvalidQuarter,
    };
    return planner.CivilPeriod.initTyped(
        .calendar_quarter,
        try registration.Date.init(year, bounds[0], 1),
        try registration.Date.init(year, bounds[1], bounds[2]),
    );
}

const FakeStore = struct {
    next_id: u64 = 1,

    fn generateOpaqueId(self: *FakeStore) ![32]u8 {
        var result: [32]u8 = undefined;
        _ = try std.fmt.bufPrint(&result, "{x:0>32}", .{self.next_id});
        self.next_id += 1;
        return result;
    }

    fn localOwnerId(_: *FakeStore) ![32]u8 {
        return "11111111111111111111111111111111".*;
    }
};

// These test DTOs intentionally model the workspace's structural ledger
// protocol without importing the SQLite-backed adapter. Production callers
// use the adapter's own request/result/write types through contextual
// coercion at each generic method call.
const FakeOwnedTaxpayerIdList = struct {
    items: []const registration.TaxpayerId,

    fn deinit(self: *FakeOwnedTaxpayerIdList, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
        self.* = undefined;
    }
};

const FakeSnapshotRequest = struct {
    taxpayer_id: registration.TaxpayerId,
    start: registration.Date,
    end: registration.Date,
};

const FakeResolvedRegistrationSnapshot = struct {
    taxpayer_identity: registration.TaxpayerIdentityRevision,
    units: []const registration.RegistrationUnitRevision,
    contacts: []const registration.RegistrationUnitContactRevision,
    tax_type_registrations: []const registration.TaxTypeRegistrationRevision,
    lineage: []const registration.BranchCodeLineageEntry,
    lineage_complete: bool,
    as_of: registration.Date,

    fn deinit(
        self: *FakeResolvedRegistrationSnapshot,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.units);
        allocator.free(self.contacts);
        allocator.free(self.tax_type_registrations);
        allocator.free(self.lineage);
        self.* = undefined;
    }
};

const FakeRegistrationSnapshotResult = union(enum) {
    resolved: FakeResolvedRegistrationSnapshot,
    review_required,

    fn deinit(
        self: *FakeRegistrationSnapshotResult,
        allocator: std.mem.Allocator,
    ) void {
        switch (self.*) {
            .resolved => |*resolved| resolved.deinit(allocator),
            .review_required => {},
        }
        self.* = undefined;
    }
};

const FakeResolvedPlanningSnapshot = struct {
    taxpayer_identity: registration.TaxpayerIdentityRevision,
    units: []const registration.RegistrationUnitRevision,
    contacts: []const registration.RegistrationUnitContactRevision,
    tax_type_registrations: []const registration.TaxTypeRegistrationRevision,
    period_start: registration.Date,
    period_end: registration.Date,

    fn deinit(
        self: *FakeResolvedPlanningSnapshot,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.units);
        allocator.free(self.contacts);
        allocator.free(self.tax_type_registrations);
        self.* = undefined;
    }
};

const FakePlanningSnapshotReviewRequired = registration_ledger.PlanningSnapshotReviewRequired;

const FakePlanningSnapshotResult = union(enum) {
    resolved: FakeResolvedPlanningSnapshot,
    registration_review_required: FakePlanningSnapshotReviewRequired,
    evidence_integrity_review_required: FakeEvidenceIntegrityReviewRequired,

    pub fn deinit(
        self: *FakePlanningSnapshotResult,
        allocator: std.mem.Allocator,
    ) void {
        switch (self.*) {
            .resolved => |*resolved| resolved.deinit(allocator),
            .registration_review_required,
            .evidence_integrity_review_required,
            => {},
        }
        self.* = undefined;
    }
};

const FakeEvidenceIntegrityReviewRequired = enum {
    protected_bytes_missing,
    protected_bytes_unreadable,
    protected_bytes_size_mismatch,
    protected_bytes_digest_mismatch,
    stored_metadata_invalid,
    storage_backend_unverifiable,
};

const FakeEvidenceSourceKind = enum {
    cor,
    ecor,
    bir_registration_record,
    migration_record,
    other_reviewed,
};
const FakeEvidenceStorageReference = union(enum) {
    protected_local_path: []const u8,
};
const FakeEvidenceReviewState = enum { accepted };
const FakeEvidenceReviewActor = union(enum) {
    local_owner: [32]u8,
    service,
};
const FakeEvidenceAssertionFact = union(enum) {
    taxpayer_tin_root: struct {
        tin_root: registration.Tin9,
    },
    registration_unit: struct {
        branch_code: registration.BranchCode5,
        status: registration.RegistrationUnitStatus,
        rdo_code: ?registration.RdoCode3,
    },
    registration_unit_contact: registration.RegistrationUnitContact,
};
const FakeEvidenceAssertionWrite = struct {
    id: registration.RegistrationEvidenceAssertionId,
    evidence_id: registration.RegistrationEvidenceId,
    taxpayer_id: registration.TaxpayerId,
    registration_unit_id: ?registration.RegistrationUnitId = null,
    effective_from: registration.Date,
    fact: FakeEvidenceAssertionFact,
};
const FakeReviewedEvidenceBundleWrite = struct {
    evidence: struct {
        id: registration.RegistrationEvidenceId,
        source_kind: FakeEvidenceSourceKind,
        sha256: []const u8,
        display_name: []const u8,
        byte_size: u64,
        captured_on: registration.Date,
        storage: FakeEvidenceStorageReference,
    },
    initial_review: struct {
        id: registration.RegistrationEvidenceReviewDecisionId,
        evidence_id: registration.RegistrationEvidenceId,
        state: FakeEvidenceReviewState,
        reviewer: FakeEvidenceReviewActor,
        reviewed_at_unix_seconds: i64,
        reason: []const u8,
    },
    assertions: []const FakeEvidenceAssertionWrite,
    commands: []const registration.RegistrationCommand,
};

const FakeLedger = struct {
    allocator: std.mem.Allocator,
    profile_store: *FakeStore,
    identity: registration.TaxpayerIdentityRevision,
    planning_identity: ?registration.TaxpayerIdentityRevision = null,
    units: []const registration.RegistrationUnitRevision,
    contacts: []const registration.RegistrationUnitContactRevision = &.{},
    tax_type_registrations: []const registration.TaxTypeRegistrationRevision,
    lineage: []const registration.BranchCodeLineageEntry,
    lineage_complete: bool = true,
    listed_taxpayer_count: usize = 1,
    create_taxpayer_seen: bool = false,
    create_branch_seen: bool = false,
    reviewed_bundle_seen: bool = false,
    reviewed_bundle_local_owner: bool = false,
    reviewed_bundle_source_kind: ?registration_ledger.EvidenceSourceKind = null,
    reviewed_bundle_reason: []const u8 = "",
    reviewed_bundle_rdo: ?registration.RdoCode3 = null,
    reviewed_bundle_contact: ?registration.RegistrationUnitContact = null,
    reviewed_bundle_contact_revised: bool = false,
    reviewed_bundle_legacy_resolved: bool = false,
    reviewed_bundle_exact: bool = false,
    reviewed_vat_bundle_exact: bool = false,
    reviewed_bundle_tin_root: ?registration.Tin9 = null,
    generated_id_count: usize = 0,

    fn generateOpaqueId(self: *FakeLedger) ![32]u8 {
        self.generated_id_count += 1;
        return self.profile_store.generateOpaqueId();
    }

    fn localOwnerId(self: *FakeLedger) ![32]u8 {
        return self.profile_store.localOwnerId();
    }

    fn listTaxpayerIds(
        self: *FakeLedger,
    ) !FakeOwnedTaxpayerIdList {
        const values = try self.allocator.alloc(
            registration.TaxpayerId,
            self.listed_taxpayer_count,
        );
        for (values) |*value| value.* = self.identity.taxpayer_id;
        return .{ .items = values };
    }

    fn snapshot(
        self: *FakeLedger,
        request: FakeSnapshotRequest,
    ) !FakeRegistrationSnapshotResult {
        if (!request.taxpayer_id.eql(&self.identity.taxpayer_id)) {
            return .review_required;
        }
        return .{ .resolved = .{
            .taxpayer_identity = self.identity,
            .units = try self.allocator.dupe(
                registration.RegistrationUnitRevision,
                self.units,
            ),
            .contacts = try self.allocator.dupe(
                registration.RegistrationUnitContactRevision,
                self.contacts,
            ),
            .tax_type_registrations = try self.allocator.dupe(
                registration.TaxTypeRegistrationRevision,
                self.tax_type_registrations,
            ),
            .lineage = try self.allocator.dupe(
                registration.BranchCodeLineageEntry,
                self.lineage,
            ),
            .lineage_complete = self.lineage_complete,
            .as_of = request.start,
        } };
    }

    pub fn planningSnapshotWithEvidenceIntegrity(
        self: *FakeLedger,
        request: FakeSnapshotRequest,
        verifier: anytype,
    ) !FakePlanningSnapshotResult {
        _ = verifier;
        const identity = self.planning_identity orelse self.identity;
        if (!request.taxpayer_id.eql(&identity.taxpayer_id)) {
            return .{ .registration_review_required = .taxpayer_identity_missing };
        }
        return .{ .resolved = .{
            .taxpayer_identity = identity,
            .units = try self.allocator.dupe(
                registration.RegistrationUnitRevision,
                self.units,
            ),
            .contacts = try self.allocator.dupe(
                registration.RegistrationUnitContactRevision,
                self.contacts,
            ),
            .tax_type_registrations = try self.allocator.dupe(
                registration.TaxTypeRegistrationRevision,
                self.tax_type_registrations,
            ),
            .period_start = request.start,
            .period_end = request.end,
        } };
    }

    fn apply(self: *FakeLedger, command: registration.RegistrationCommand) !void {
        switch (command) {
            .create_taxpayer => self.create_taxpayer_seen = true,
            .create_branch => self.create_branch_seen = true,
            else => {},
        }
    }

    fn recordReviewedEvidenceBundle(
        self: *FakeLedger,
        bundle: registration_ledger.ReviewedEvidenceBundleWrite,
    ) !void {
        self.reviewed_bundle_seen = true;
        self.reviewed_bundle_source_kind = bundle.evidence.source_kind;
        self.reviewed_bundle_reason = bundle.initial_review.reason;
        self.reviewed_bundle_local_owner = switch (bundle.initial_review.reviewer) {
            .local_owner => true,
            .service => false,
        };
        if (bundle.assertions.len == 2 and bundle.commands.len == 1) {
            const protected_path = switch (bundle.evidence.storage) {
                .protected_local_path => |path| path,
                .metadata_only_non_authoritative,
                .encrypted_blob_reference,
                => return error.InvalidEvidencePath,
            };
            if (protected_path.len == 0) return error.InvalidEvidencePath;
            const taxpayer_assertion = bundle.assertions[0];
            const taxpayer_fact = switch (taxpayer_assertion.fact) {
                .taxpayer_tin_root => |value| value,
                else => return error.UnexpectedAssertion,
            };
            const vat_assertion = bundle.assertions[1];
            const vat_fact = switch (vat_assertion.fact) {
                .tax_type_registration => |value| value,
                else => return error.UnexpectedAssertion,
            };
            const registration_unit_id = vat_assertion.registration_unit_id orelse
                return error.AssertionMismatch;
            const command = switch (bundle.commands[0]) {
                .create_tax_type_registration => |value| value,
                else => return error.UnexpectedCommand,
            };
            if (taxpayer_assertion.registration_unit_id != null or
                !taxpayer_assertion.evidence_id.eql(&bundle.evidence.id) or
                !taxpayer_assertion.taxpayer_id.eql(&command.taxpayer_id) or
                !taxpayer_fact.tin_root.eql(&self.identity.tin_root) or
                !std.meta.eql(
                    taxpayer_assertion.effective_from,
                    command.effective_from,
                ) or
                !vat_assertion.evidence_id.eql(&bundle.evidence.id) or
                !vat_assertion.taxpayer_id.eql(&command.taxpayer_id) or
                !registration_unit_id.eql(&command.registration_unit_id) or
                !std.meta.eql(vat_assertion.effective_from, command.effective_from) or
                vat_fact.tax_type != .vat or
                vat_fact.status != .confirmed_active or
                command.tax_type != .vat or
                command.status != .confirmed_active or
                command.evidence_id == null or
                !command.evidence_id.?.eql(&bundle.evidence.id))
            {
                return error.AssertionMismatch;
            }
            self.reviewed_bundle_tin_root = taxpayer_fact.tin_root;
            self.reviewed_bundle_exact = true;
            self.reviewed_vat_bundle_exact = true;
            return;
        }
        const vat_registration_count: usize = for (bundle.assertions) |assertion| {
            switch (assertion.fact) {
                .tax_type_registration => break 1,
                else => {},
            }
        } else 0;
        if (bundle.assertions.len != 3 + vat_registration_count) {
            return error.InvalidAssertionCount;
        }
        const identity_command_count: usize = if (self.identity.evidence_id == null) 1 else 0;
        if (bundle.commands.len != identity_command_count + 2 + vat_registration_count) {
            return error.InvalidCommandCount;
        }
        const protected_path = switch (bundle.evidence.storage) {
            .protected_local_path => |path| path,
            .metadata_only_non_authoritative,
            .encrypted_blob_reference,
            => return error.InvalidEvidencePath,
        };
        if (protected_path.len == 0) return error.InvalidEvidencePath;
        const tin_fact = switch (bundle.assertions[0].fact) {
            .taxpayer_tin_root => |fact| fact,
            else => return error.UnexpectedAssertion,
        };
        self.reviewed_bundle_tin_root = tin_fact.tin_root;
        if (bundle.assertions[0].registration_unit_id != null or
            !tin_fact.tin_root.eql(&self.identity.tin_root))
        {
            return error.AssertionMismatch;
        }
        if (identity_command_count == 1) {
            const command = switch (bundle.commands[0]) {
                .confirm_taxpayer_tin_root => |value| value,
                else => return error.UnexpectedCommand,
            };
            if (!command.evidence_id.eql(&bundle.evidence.id) or
                !command.current.taxpayer_id.eql(&self.identity.taxpayer_id) or
                !command.observed_tin_root.eql(&tin_fact.tin_root))
            {
                return error.AssertionMismatch;
            }
        }
        const lifecycle_fact = switch (bundle.assertions[1].fact) {
            .registration_unit => |fact| fact,
            else => return error.UnexpectedAssertion,
        };
        const lifecycle_evidence_id = bundle.assertions[1].evidence_id;
        const lifecycle_unit_id = bundle.assertions[1].registration_unit_id orelse
            return error.AssertionMismatch;
        const contact_unit_id = bundle.assertions[2].registration_unit_id orelse
            return error.AssertionMismatch;
        if (!lifecycle_evidence_id.eql(&bundle.evidence.id) or
            !bundle.assertions[0].evidence_id.eql(&bundle.evidence.id) or
            !bundle.assertions[2].evidence_id.eql(&bundle.evidence.id) or
            bundle.assertions[0].id.eql(&bundle.assertions[1].id) or
            bundle.assertions[0].id.eql(&bundle.assertions[2].id) or
            bundle.assertions[1].id.eql(&bundle.assertions[2].id) or
            !bundle.assertions[0].taxpayer_id.eql(&bundle.assertions[1].taxpayer_id) or
            !bundle.assertions[1].taxpayer_id.eql(&bundle.assertions[2].taxpayer_id) or
            !lifecycle_unit_id.eql(&contact_unit_id) or
            !std.meta.eql(
                bundle.assertions[0].effective_from,
                bundle.assertions[1].effective_from,
            ) or
            !std.meta.eql(
                bundle.assertions[1].effective_from,
                bundle.assertions[2].effective_from,
            ) or
            lifecycle_fact.status != .confirmed_active)
        {
            return error.AssertionMismatch;
        }
        var command_evidence_id: registration.RegistrationEvidenceId = undefined;
        var command_code: registration.BranchCode5 = undefined;
        switch (bundle.commands[identity_command_count]) {
            .confirm_registration_unit => |command| {
                command_evidence_id = command.evidence_id;
                command_code = command.observed_code;
                self.reviewed_bundle_rdo = command.observed_rdo_code;
            },
            .resolve_legacy_registration_unit => |command| {
                self.reviewed_bundle_legacy_resolved = true;
                command_evidence_id = command.evidence_id;
                command_code = command.observed_code;
                self.reviewed_bundle_rdo = command.observed_rdo_code;
            },
            else => return error.UnexpectedCommand,
        }
        if (!command_evidence_id.eql(&bundle.evidence.id) or
            !command_code.eql(&lifecycle_fact.branch_code))
        {
            return error.AssertionMismatch;
        }
        if (self.reviewed_bundle_rdo) |command_rdo| {
            const asserted_rdo = lifecycle_fact.rdo_code orelse
                return error.AssertionMismatch;
            if (!command_rdo.eql(&asserted_rdo)) return error.AssertionMismatch;
        } else if (lifecycle_fact.rdo_code != null) {
            return error.AssertionMismatch;
        }
        self.reviewed_bundle_contact = switch (bundle.assertions[2].fact) {
            .registration_unit_contact => |contact| contact,
            else => return error.UnexpectedAssertion,
        };
        switch (bundle.commands[identity_command_count + 1]) {
            .create_registration_unit_contact => |command| {
                if (!command.evidence_id.eql(&bundle.evidence.id) or
                    !command.taxpayer_id.eql(&bundle.assertions[2].taxpayer_id) or
                    !command.registration_unit_id.eql(&contact_unit_id) or
                    !command.contact.registered_address.eql(
                        &self.reviewed_bundle_contact.?.registered_address,
                    )) return error.ContactMismatch;
            },
            .revise_registration_unit_contact => |command| {
                self.reviewed_bundle_contact_revised = true;
                if (!command.evidence_id.eql(&bundle.evidence.id) or
                    !command.current.taxpayer_id.eql(&bundle.assertions[2].taxpayer_id) or
                    !command.current.registration_unit_id.eql(&contact_unit_id) or
                    !command.contact.registered_address.eql(
                        &self.reviewed_bundle_contact.?.registered_address,
                    )) return error.ContactMismatch;
            },
            else => return error.UnexpectedCommand,
        }
        self.reviewed_bundle_exact = true;
    }
};

fn fixtureId(comptime Id: type, raw: []const u8) Id {
    return Id.parse(raw) catch unreachable;
}

fn fixtureDate(raw: []const u8) registration.Date {
    return registration.Date.parseIso(raw) catch unreachable;
}

fn fixturePeriod(from: []const u8) registration.EffectivePeriod {
    return .{ .from = fixtureDate(from) };
}

fn optionalSemanticEql(comptime Value: type, left: ?Value, right: ?Value) bool {
    const left_value = left orelse return right == null;
    const right_value = right orelse return false;
    return left_value.eql(&right_value);
}

fn projectionContextsEql(
    left: *const projection.FilingProjectionContext,
    right: *const projection.FilingProjectionContext,
) bool {
    const left_identity = &left.taxpayer_identity;
    const right_identity = &right.taxpayer_identity;
    if (!left_identity.taxpayer_id.eql(&right_identity.taxpayer_id) or
        !left_identity.id.eql(&right_identity.id) or
        left_identity.sequence != right_identity.sequence or
        !std.meta.eql(left_identity.effective, right_identity.effective) or
        !left_identity.tin_root.eql(&right_identity.tin_root) or
        !optionalSemanticEql(
            registration.RegistrationEvidenceId,
            left_identity.evidence_id,
            right_identity.evidence_id,
        ))
    {
        return false;
    }

    if (!left.form_revision.eql(&right.form_revision) or
        !std.meta.eql(left.civil_period, right.civil_period) or
        !left.filing_unit_id.eql(&right.filing_unit_id) or
        !left.filing_unit_revision_id.eql(&right.filing_unit_revision_id) or
        !left.filing_branch_code.eql(&right.filing_branch_code) or
        !left.filing_branch_evidence_id.eql(&right.filing_branch_evidence_id) or
        !optionalSemanticEql(
            registration.RdoCode3,
            left.filing_unit_rdo_code,
            right.filing_unit_rdo_code,
        ))
    {
        return false;
    }

    const left_contact = &left.filing_unit_contact;
    const right_contact = &right.filing_unit_contact;
    return left_contact.taxpayer_id.eql(&right_contact.taxpayer_id) and
        left_contact.registration_unit_id.eql(&right_contact.registration_unit_id) and
        left_contact.id.eql(&right_contact.id) and
        left_contact.sequence == right_contact.sequence and
        std.meta.eql(left_contact.effective, right_contact.effective) and
        left_contact.contact.registered_address.eql(
            &right_contact.contact.registered_address,
        ) and
        optionalSemanticEql(
            profile_field.ZipCode,
            left_contact.contact.zip_code,
            right_contact.contact.zip_code,
        ) and
        optionalSemanticEql(
            profile_field.ContactNumber,
            left_contact.contact.contact_number,
            right_contact.contact.contact_number,
        ) and
        optionalSemanticEql(
            profile_field.EmailAddress,
            left_contact.contact.email_address,
            right_contact.contact.email_address,
        ) and
        left_contact.evidence_id.eql(&right_contact.evidence_id);
}

fn coverageRowsEql(left: CoverageRow, right: CoverageRow) bool {
    return left.id == right.id and
        left.registration_unit_id.eql(&right.registration_unit_id) and
        left.registration_unit_revision_id.eql(&right.registration_unit_revision_id) and
        left.branch_code.eql(&right.branch_code) and
        left.branch_code_evidence_id.eql(&right.branch_code_evidence_id);
}

fn validConfirmationInput() ConfirmationInput {
    return .{
        .reviewed_evidence = .{
            .source_kind = .bir_registration_record,
            .effective_from = "2026-01-02",
            .evidence_path = "/synthetic/BIR registration record.pdf",
            .evidence_display_name = "BIR registration record.pdf",
            .evidence_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            .evidence_byte_size = "4096",
            .evidence_captured_on = "2026-01-01",
            .reviewed_at_unix_seconds = 1_767_225_600,
        },
        .observed_tin_root = "123456789",
        .observed_branch_code = "00002",
        .observed_rdo_code = "081",
        .registered_address = "456 Branch Avenue, Makati City",
        .zip_code = "1200",
        .contact_number = "+63 917 765 4321",
        .email_address = "branch@example.test",
    };
}

fn validVatRegistrationInput() VatRegistrationInput {
    return .{
        .reviewed_evidence = .{
            .source_kind = .bir_registration_record,
            .effective_from = "2024-01-01",
            .evidence_path = "/synthetic/BIR VAT registration record.pdf",
            .evidence_display_name = "BIR VAT registration record.pdf",
            .evidence_sha256 = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
            .evidence_byte_size = "2048",
            .evidence_captured_on = "2026-01-01",
            .reviewed_at_unix_seconds = 1_767_225_600,
        },
        .observed_tin_root = "123456789",
        .assert_active_vat_registration = true,
    };
}

const WorkspaceFixture = struct {
    store: FakeStore = .{},
    identity: registration.TaxpayerIdentityRevision,
    units: [2]registration.RegistrationUnitRevision,
    contacts: [1]registration.RegistrationUnitContactRevision,
    tax_types: [1]registration.TaxTypeRegistrationRevision,
    lineage: [2]registration.BranchCodeLineageEntry,

    fn init() WorkspaceFixture {
        const taxpayer_id = fixtureId(registration.TaxpayerId, "taxpayer-a");
        const head_id = fixtureId(registration.RegistrationUnitId, "unit-head");
        const branch_id = fixtureId(registration.RegistrationUnitId, "unit-branch");
        const head_evidence = fixtureId(
            registration.RegistrationEvidenceId,
            "evidence-head",
        );
        const branch_evidence = fixtureId(
            registration.RegistrationEvidenceId,
            "evidence-branch",
        );
        return .{
            .identity = .{
                .taxpayer_id = taxpayer_id,
                .id = fixtureId(registration.TaxpayerRevisionId, "taxpayer-rev-a"),
                .sequence = 1,
                .effective = fixturePeriod("2024-01-01"),
                .tin_root = registration.Tin9.parse("123456789") catch unreachable,
                .evidence_id = head_evidence,
            },
            .units = .{
                .{
                    .taxpayer_id = taxpayer_id,
                    .registration_unit_id = head_id,
                    .id = fixtureId(
                        registration.RegistrationUnitRevisionId,
                        "unit-head-rev-a",
                    ),
                    .sequence = 1,
                    .effective = fixturePeriod("2024-01-01"),
                    .kind = .head_office,
                    .branch_code_evidence = .{ .confirmed = .{
                        .code = registration.BranchCode5.headOffice(),
                        .evidence_id = head_evidence,
                    } },
                    .status = .confirmed_active,
                    .rdo_code = registration.RdoCode3.parse("047") catch unreachable,
                    .lifecycle_evidence_id = head_evidence,
                },
                .{
                    .taxpayer_id = taxpayer_id,
                    .registration_unit_id = branch_id,
                    .id = fixtureId(
                        registration.RegistrationUnitRevisionId,
                        "unit-branch-rev-a",
                    ),
                    .sequence = 1,
                    .effective = fixturePeriod("2024-01-01"),
                    .kind = .branch,
                    .branch_code_evidence = .{ .confirmed = .{
                        .code = registration.BranchCode5.parse("00001") catch unreachable,
                        .evidence_id = branch_evidence,
                    } },
                    .status = .confirmed_active,
                    .rdo_code = registration.RdoCode3.parse("081") catch unreachable,
                    .lifecycle_evidence_id = branch_evidence,
                },
            },
            .contacts = .{.{
                .taxpayer_id = taxpayer_id,
                .registration_unit_id = head_id,
                .id = fixtureId(
                    registration.RegistrationUnitContactRevisionId,
                    "unit-head-contact-rev-a",
                ),
                .sequence = 1,
                .effective = fixturePeriod("2024-01-01"),
                .contact = .{
                    .registered_address = profile_field.RegisteredAddress.parse(
                        "123 Sample Street, Quezon City",
                    ) catch unreachable,
                    .zip_code = profile_field.ZipCode.parse("1100") catch unreachable,
                    .contact_number = profile_field.ContactNumber.parse(
                        "+63 917 123 4567",
                    ) catch unreachable,
                    .email_address = profile_field.EmailAddress.parse(
                        "filing@example.test",
                    ) catch unreachable,
                },
                .evidence_id = head_evidence,
            }},
            .tax_types = .{.{
                .taxpayer_id = taxpayer_id,
                .registration_unit_id = head_id,
                .registration_id = fixtureId(
                    registration.TaxTypeRegistrationId,
                    "vat-registration-a",
                ),
                .id = fixtureId(
                    registration.TaxTypeRegistrationRevisionId,
                    "vat-registration-rev-a",
                ),
                .sequence = 1,
                .tax_type = .vat,
                .status = .confirmed_active,
                .effective = fixturePeriod("2024-01-01"),
                .evidence_id = fixtureId(
                    registration.RegistrationEvidenceId,
                    "evidence-vat",
                ),
            }},
            .lineage = .{
                .{
                    .taxpayer_id = taxpayer_id,
                    .registration_unit_id = head_id,
                    .code = registration.BranchCode5.headOffice(),
                    .evidence_id = head_evidence,
                },
                .{
                    .taxpayer_id = taxpayer_id,
                    .registration_unit_id = branch_id,
                    .code = registration.BranchCode5.parse("00001") catch unreachable,
                    .evidence_id = branch_evidence,
                },
            },
        };
    }

    fn ledger(self: *WorkspaceFixture) FakeLedger {
        return .{
            .allocator = std.testing.allocator,
            .profile_store = &self.store,
            .identity = self.identity,
            .units = &self.units,
            .contacts = &self.contacts,
            .tax_type_registrations = &self.tax_types,
            .lineage = &self.lineage,
        };
    }
};

test "production filing policy catalog is intentionally empty" {
    try std.testing.expectEqual(@as(usize, 0), production_policy_catalog.revisions.len);
}

test "taxpayer labels distinguish rows with identical masked TIN roots" {
    const taxpayer_id = try registration.TaxpayerId.parse("taxpayer-a");
    const first = TaxpayerRow{ .id = 0, .taxpayer_id = taxpayer_id };
    const second = TaxpayerRow{ .id = 1, .taxpayer_id = taxpayer_id };

    const first_visible = first.visibleLabel(std.testing.allocator);
    defer std.testing.allocator.free(first_visible);
    const second_visible = second.visibleLabel(std.testing.allocator);
    defer std.testing.allocator.free(second_visible);
    try std.testing.expectEqualStrings("Taxpayer 1 · ***-***-***", first_visible);
    try std.testing.expectEqualStrings("Taxpayer 2 · ***-***-***", second_visible);
    try std.testing.expect(!std.mem.eql(u8, first_visible, second_visible));

    const first_accessible = first.accessibleLabel(std.testing.allocator);
    defer std.testing.allocator.free(first_accessible);
    const second_accessible = second.accessibleLabel(std.testing.allocator);
    defer std.testing.allocator.free(second_accessible);
    try std.testing.expect(!std.mem.eql(u8, first_accessible, second_accessible));
    try std.testing.expectEqualStrings("taxpayer-a", first.stableKey());
}

test "branch suggestion history capacity fails closed instead of dropping a used code" {
    var occupied: [max_occupied_branch_codes]registration.BranchCode5 = undefined;
    var occupied_count: usize = 0;
    var number: usize = 1;
    while (number <= max_occupied_branch_codes) : (number += 1) {
        var digits: [5]u8 = undefined;
        _ = try std.fmt.bufPrint(&digits, "{d:0>5}", .{number});
        try std.testing.expect(appendOccupiedCode(
            &occupied,
            &occupied_count,
            try registration.BranchCode5.parse(&digits),
        ));
    }

    const overflow = try registration.BranchCode5.parse("00129");
    try std.testing.expect(!appendOccupiedCode(
        &occupied,
        &occupied_count,
        overflow,
    ));
    try std.testing.expectEqual(max_occupied_branch_codes, occupied_count);
}

test "workspace truncation is visible and forces Review Required" {
    var fixture = WorkspaceFixture.init();
    var taxpayer_ledger = fixture.ledger();
    taxpayer_ledger.listed_taxpayer_count = max_taxpayers + 1;
    var taxpayer_state = State{};
    const reviewed_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};

    try taxpayer_state.refresh(
        std.testing.allocator,
        &taxpayer_ledger,
        .{},
        fixtureDate("2025-05-01"),
        .{ .revisions = &reviewed_policy },
        2025,
        2,
    );

    try std.testing.expect(taxpayer_state.taxpayers_truncated);
    try std.testing.expectEqual(WorkspaceStatus.review_required, taxpayer_state.workspace_status);
    try std.testing.expectEqual(PlanningStatus.integration_error, taxpayer_state.planning_status);
    try std.testing.expectEqual(
        IntegrationReason.taxpayer_list_truncated,
        taxpayer_state.integration_reason,
    );
    try std.testing.expectEqualStrings(
        "Showing the first 64 Taxpayers; additional records are hidden — Review Required.",
        taxpayer_state.taxpayerListStatusLabel(),
    );

    var many_units: [max_units + 1]registration.RegistrationUnitRevision = undefined;
    for (&many_units, 0..) |*unit, index| {
        unit.* = fixture.units[1];
        var id_buffer: [32]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buffer, "unit-{d:0>2}", .{index});
        unit.registration_unit_id = try registration.RegistrationUnitId.parse(id);
        unit.id = try registration.RegistrationUnitRevisionId.parse(id);
    }
    var unit_ledger = fixture.ledger();
    unit_ledger.units = &many_units;
    var unit_state = State{};

    try unit_state.refresh(
        std.testing.allocator,
        &unit_ledger,
        .{},
        fixtureDate("2025-05-01"),
        .{ .revisions = &reviewed_policy },
        2025,
        2,
    );

    try std.testing.expect(unit_state.units_truncated);
    try std.testing.expectEqual(WorkspaceStatus.review_required, unit_state.workspace_status);
    try std.testing.expectEqual(PlanningStatus.integration_error, unit_state.planning_status);
    try std.testing.expectEqual(
        IntegrationReason.unit_list_truncated,
        unit_state.integration_reason,
    );
    try std.testing.expectEqualStrings(
        "Showing the first 64 Registration Units; additional records are hidden — Review Required.",
        unit_state.unitListStatusLabel(),
    );
}

test "incomplete branch history exposes no actionable suggestion" {
    var fixture = WorkspaceFixture.init();
    var lineage: [max_occupied_branch_codes + 1]registration.BranchCodeLineageEntry = undefined;
    for (&lineage, 0..) |*entry, index| {
        entry.* = fixture.lineage[1];
        var digits: [5]u8 = undefined;
        _ = try std.fmt.bufPrint(&digits, "{d:0>5}", .{index + 1});
        entry.code = try registration.BranchCode5.parse(&digits);
    }
    var fake_ledger = fixture.ledger();
    fake_ledger.lineage = &lineage;
    var state = State{};
    const reviewed_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};

    try state.refresh(
        std.testing.allocator,
        &fake_ledger,
        .{},
        fixtureDate("2025-05-01"),
        .{ .revisions = &reviewed_policy },
        2025,
        2,
    );

    try std.testing.expect(state.branch_suggestion_incomplete);
    try std.testing.expect(!state.branchSuggestionActionEnabled());
    try std.testing.expectEqualStrings("Unavailable", state.branchSuggestionLabel());
    try std.testing.expectEqualStrings(
        "Branch-code history is incomplete — no safe suggestion is available.",
        state.branchSuggestionStatusLabel(),
    );
}

test "superseded historical lineage disables suggestions without blocking current planning" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    fake_ledger.lineage_complete = false;
    var state = State{};
    const reviewed_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};

    try state.refresh(
        std.testing.allocator,
        &fake_ledger,
        .{},
        fixtureDate("2025-05-01"),
        .{ .revisions = &reviewed_policy },
        2025,
        2,
    );

    try std.testing.expect(state.branch_suggestion_incomplete);
    try std.testing.expect(!state.branchSuggestionActionEnabled());
    try std.testing.expectEqualStrings("Unavailable", state.branchSuggestionLabel());
    try std.testing.expectEqualStrings(
        "Branch-code history is incomplete — no safe suggestion is available.",
        state.branchSuggestionStatusLabel(),
    );
    try std.testing.expectEqual(PlanningStatus.resolved_not_fileable, state.planning_status);
    try std.testing.expect(state.provenance_validated);
}

test "load failure has distinct fail-closed action and planning copy" {
    var state = State{};
    state.planning_status = .resolved_fileable;
    state.resolved_coverage_count = 1;
    state.coverage_count = 1;

    state.reportLoadFailure();

    try std.testing.expectEqual(ActionStatus.load_failed, state.action_status);
    try std.testing.expectEqualStrings(
        "Registration data could not be loaded. Refresh and try again; no change was saved.",
        state.action_status.label(),
    );
    try std.testing.expectEqual(WorkspaceStatus.review_required, state.workspace_status);
    try std.testing.expectEqual(PlanningStatus.integration_error, state.planning_status);
    try std.testing.expectEqual(
        IntegrationReason.workspace_load_failed,
        state.integration_reason,
    );
    try std.testing.expectEqual(@as(usize, 0), state.coverageRows().len);
    try std.testing.expectEqualStrings(
        "Review Required — registration data could not be loaded; no filing scope is shown.",
        state.integrationReasonLabel(),
    );
}

test "workspace status preserves pending active closed and legacy states" {
    const taxpayer_id = try registration.TaxpayerId.parse("taxpayer-a");
    const evidence_id = try registration.RegistrationEvidenceId.parse("evidence-a");
    const base = registration.RegistrationUnitRevision{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = try registration.RegistrationUnitId.parse("unit-a"),
        .id = try registration.RegistrationUnitRevisionId.parse("unit-rev-a"),
        .sequence = 1,
        .effective = .{ .from = try registration.Date.parseIso("2026-01-01") },
        .kind = .head_office,
        .branch_code_evidence = .{ .unconfirmed = registration.BranchCode5.headOffice() },
        .status = .pending_evidence,
    };
    try std.testing.expectEqual(WorkspaceStatus.pending_evidence, aggregateStatus(&.{base}));

    var active = base;
    active.status = .confirmed_active;
    active.branch_code_evidence = .{ .confirmed = .{
        .code = registration.BranchCode5.headOffice(),
        .evidence_id = evidence_id,
    } };
    active.lifecycle_evidence_id = evidence_id;
    try std.testing.expectEqual(WorkspaceStatus.confirmed_active, aggregateStatus(&.{active}));

    var closed = active;
    closed.status = .confirmed_closed;
    try std.testing.expectEqual(WorkspaceStatus.confirmed_closed, aggregateStatus(&.{closed}));

    var legacy = base;
    legacy.status = .legacy_unresolved;
    legacy.branch_code_evidence = .{
        .legacy_unresolved = try registration.LegacyBranchSuffix.parse("001"),
    };
    try std.testing.expectEqual(WorkspaceStatus.legacy_unresolved, aggregateStatus(&.{legacy}));
}

test "source workspace distinguishes loaded empty stream from unconnected" {
    var state = State{};
    try std.testing.expect(!state.sourceRecordsConnected());

    state.replaceSourceRecords(&.{});

    try std.testing.expect(state.sourceRecordsConnected());
    try std.testing.expectEqual(@as(usize, 0), state.sourceRecordRows().len);
    try std.testing.expect(!state.sourceWorkspaceReviewRequired());
}

test "source workspace preserves invalid input and rebuilds for period selection" {
    const fixture = WorkspaceFixture.init();
    var state = State{};
    state.taxpayers[0] = .{
        .id = 0,
        .taxpayer_id = fixture.identity.taxpayer_id,
        .selected = true,
    };
    state.taxpayer_count = 1;
    state.selected_taxpayer_index = 0;
    state.units[0] = makeUnitRow(0, fixture.units[0]);
    state.units[0].selected = true;
    state.unit_count = 1;
    state.selected_registration_unit_index = 0;

    const records = [_]SourceRecord{
        .{
            .id = try SourceRecordId.parse("q1-head"),
            .taxpayer_id = fixture.identity.taxpayer_id,
            .occurred_on = fixtureDate("2026-01-15"),
            .kind = .transaction,
            .attribution = .{ .entered = .{
                .source_unit = .{
                    .registration_unit_id = fixture.units[0].registration_unit_id,
                    .registration_unit_revision_id = fixture.units[0].id,
                },
                .evidence_reference = try SourceEvidenceReference.parse("q1-import"),
            } },
        },
        .{
            .id = try SourceRecordId.parse("q2-head"),
            .taxpayer_id = fixture.identity.taxpayer_id,
            .occurred_on = fixtureDate("2026-04-15"),
            .kind = .transaction,
            .attribution = .{ .entered = .{
                .source_unit = .{
                    .registration_unit_id = fixture.units[0].registration_unit_id,
                    .registration_unit_revision_id = fixture.units[0].id,
                },
                .evidence_reference = try SourceEvidenceReference.parse("q2-import"),
            } },
        },
        .{
            .id = .{},
            .taxpayer_id = fixture.identity.taxpayer_id,
            .occurred_on = fixtureDate("2026-01-20"),
            .kind = .attachment,
            .attribution = .{ .legacy_unknown = .missing_import_mapping },
        },
        .{
            .id = try SourceRecordId.parse("q1-legacy"),
            .taxpayer_id = fixture.identity.taxpayer_id,
            .occurred_on = fixtureDate("2026-02-01"),
            .kind = .attachment,
            .attribution = .{ .legacy_unknown = .historical_format_without_source_unit },
        },
    };

    state.replaceSourceRecords(&records);
    try std.testing.expectEqual(@as(usize, 1), state.sourceLoadInvalidCount());
    try std.testing.expectEqual(@as(usize, 1), state.source_invalid_count);
    try std.testing.expectEqual(@as(usize, 1), state.sourceRecordRows().len);
    try std.testing.expectEqualStrings("q1-head", state.sourceRecordRows()[0].stableKey());
    try std.testing.expectEqual(@as(usize, 2), state.sourceWorkspaceUnresolvedCount());
    try std.testing.expect(state.sourceWorkspaceReviewRequired());

    state.setRequestedPeriod(2026, 2);
    try std.testing.expectEqual(@as(usize, 1), state.sourceLoadInvalidCount());
    try std.testing.expectEqual(@as(usize, 0), state.source_invalid_count);
    try std.testing.expectEqual(@as(usize, 1), state.sourceRecordRows().len);
    try std.testing.expectEqualStrings("q2-head", state.sourceRecordRows()[0].stableKey());
    try std.testing.expectEqual(@as(usize, 0), state.sourceWorkspaceUnresolvedCount());
    try std.testing.expect(!state.sourceWorkspaceReviewRequired());
}

test "invalid source row for another taxpayer is load-only diagnostics" {
    const fixture = WorkspaceFixture.init();
    var state = State{};
    state.taxpayers[0] = .{
        .id = 0,
        .taxpayer_id = fixture.identity.taxpayer_id,
        .selected = true,
    };
    state.taxpayer_count = 1;
    state.selected_taxpayer_index = 0;
    state.units[0] = makeUnitRow(0, fixture.units[0]);
    state.units[0].selected = true;
    state.unit_count = 1;
    state.selected_registration_unit_index = 0;

    const records = [_]SourceRecord{.{
        .id = .{},
        .taxpayer_id = try registration.TaxpayerId.parse("other-taxpayer"),
        .occurred_on = fixtureDate("2026-01-20"),
        .kind = .transaction,
        .attribution = .{ .legacy_unknown = .missing_import_mapping },
    }};

    state.replaceSourceRecords(&records);

    try std.testing.expectEqual(@as(usize, 1), state.sourceLoadInvalidCount());
    try std.testing.expectEqual(@as(usize, 0), state.source_invalid_count);
    try std.testing.expectEqual(@as(usize, 0), state.sourceWorkspaceUnresolvedCount());
    try std.testing.expect(!state.sourceWorkspaceReviewRequired());
}

test "workspace Registration Unit selection cannot alter an already resolved Filing Unit" {
    var state = State{};
    const taxpayer_id = try registration.TaxpayerId.parse("taxpayer-a");
    const evidence_id = try registration.RegistrationEvidenceId.parse("evidence-a");
    const effective = registration.EffectivePeriod{
        .from = try registration.Date.parseIso("2024-01-01"),
    };
    state.taxpayers[0] = .{ .id = 0, .taxpayer_id = taxpayer_id, .selected = true };
    state.taxpayer_count = 1;
    state.selected_taxpayer_index = 0;
    state.units[0] = makeUnitRow(0, .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = try registration.RegistrationUnitId.parse("unit-head"),
        .id = try registration.RegistrationUnitRevisionId.parse("unit-head-rev"),
        .sequence = 1,
        .effective = effective,
        .kind = .head_office,
        .branch_code_evidence = .{ .confirmed = .{
            .code = registration.BranchCode5.headOffice(),
            .evidence_id = evidence_id,
        } },
        .status = .confirmed_active,
        .lifecycle_evidence_id = evidence_id,
    });
    state.units[1] = makeUnitRow(1, .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = try registration.RegistrationUnitId.parse("unit-branch"),
        .id = try registration.RegistrationUnitRevisionId.parse("unit-branch-rev"),
        .sequence = 1,
        .effective = effective,
        .kind = .branch,
        .branch_code_evidence = .{ .confirmed = .{
            .code = try registration.BranchCode5.parse("00001"),
            .evidence_id = evidence_id,
        } },
        .status = .confirmed_active,
        .lifecycle_evidence_id = evidence_id,
    });
    state.unit_count = 2;
    state.selected_registration_unit_index = 0;
    state.syncRegistrationUnitSelection();
    state.resolved_filing_code = registration.BranchCode5.headOffice();
    state.resolved_filing_rdo_code = try registration.RdoCode3.parse("047");
    state.resolved_coverage_count = 2;
    state.resolved_obligation_count = 1;
    const projected_filer = "123-456-789-00000";
    @memcpy(
        state.projection_filer_tin[0..projected_filer.len],
        projected_filer,
    );
    state.projection_filer_tin_len = @intCast(projected_filer.len);
    state.decision_hash_text = [_]u8{'a'} ** 64;
    state.decision_hash_present = true;
    state.provenance_validated = true;

    const accessible = state.units[0].accessibleLabel(std.testing.allocator);
    defer std.testing.allocator.free(accessible);
    try std.testing.expect(std.mem.startsWith(
        u8,
        accessible,
        "Registration Unit, Head office, code 00000",
    ));
    try std.testing.expect(std.mem.indexOf(
        u8,
        accessible,
        "VAT not recorded",
    ) != null);
    try std.testing.expectEqualStrings(
        "secondary",
        state.units[0].vatRegistrationTone(),
    );

    state.selectRegistrationUnit(1);
    try std.testing.expect(state.units[1].selected);
    try std.testing.expectEqualStrings("00000", state.resolvedFilingCodeLabel());
    try std.testing.expectEqualStrings("047", state.resolvedFilingRdoLabel());
    try std.testing.expectEqual(@as(usize, 2), state.resolved_coverage_count);
    try std.testing.expectEqual(@as(usize, 1), state.resolved_obligation_count);
    try std.testing.expectEqualStrings(
        projected_filer,
        state.projectionFilerTinLabel(),
    );
    try std.testing.expectEqualStrings(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        state.decisionHashLabel(),
    );
    try std.testing.expectEqualStrings(
        "Scope provenance validated for this preview; no immutable draft provenance was retained.",
        state.provenanceLabel(),
    );
}

test "workspace reports one pending Registration Unit issue per revision" {
    var fixture = WorkspaceFixture.init();
    fixture.units[1].status = .pending_evidence;
    fixture.units[1].branch_code_evidence = .{
        .unconfirmed = registration.BranchCode5.parse("00001") catch unreachable,
    };
    fixture.units[1].lifecycle_evidence_id = null;

    var fake_ledger = fixture.ledger();
    fake_ledger.lineage = fixture.lineage[0..1];
    var state = State{};
    const reviewed_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};

    try state.refresh(
        std.testing.allocator,
        &fake_ledger,
        .{},
        fixtureDate("2025-05-01"),
        .{ .revisions = &reviewed_policy },
        2025,
        2,
    );

    try std.testing.expectEqual(
        PlanningStatus.review_required,
        state.planning_status,
    );
    try std.testing.expectEqual(@as(usize, 1), state.reviewReasonRows().len);
    const label = state.reviewReasonRows()[0].label(std.testing.allocator);
    defer std.testing.allocator.free(label);
    try std.testing.expectEqualStrings(
        "A covered Registration Unit is pending evidence. Affected: Branch 00001 candidate.",
        label,
    );
}

test "invalid requested quarter is preserved and never previewed as Q1" {
    const cases = [_]struct {
        quarter: u8,
        expected_label: []const u8,
    }{
        .{ .quarter = 0, .expected_label = "2550Q · 2024-04-ENCS · Q0 2025" },
        .{ .quarter = 5, .expected_label = "2550Q · 2024-04-ENCS · Q5 2025" },
    };

    for (cases) |case| {
        var fixture = WorkspaceFixture.init();
        var fake_ledger = fixture.ledger();
        var state = State{};
        const reviewed_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};

        try state.refresh(
            std.testing.allocator,
            &fake_ledger,
            .{},
            fixtureDate("2025-05-01"),
            .{ .revisions = &reviewed_policy },
            2025,
            case.quarter,
        );

        try std.testing.expectEqual(case.quarter, state.period_quarter);
        try std.testing.expectEqual(PlanningStatus.integration_error, state.planning_status);
        try std.testing.expectEqual(
            IntegrationReason.invalid_preview_period,
            state.integration_reason,
        );
        try std.testing.expectEqual(@as(usize, 0), state.resolved_obligation_count);
        try std.testing.expectEqualStrings("Not resolved", state.resolvedFilingCodeLabel());
        try std.testing.expectEqualStrings("Not projected", state.projectionFilerTinLabel());
        try std.testing.expect(!state.effectivePolicyResolved());
        try std.testing.expect(!state.provenance_validated);

        const label = state.requestedPreviewLabel(std.testing.allocator);
        defer std.testing.allocator.free(label);
        try std.testing.expectEqualStrings(case.expected_label, label);
    }
}

test "registration snapshot review labels preserve actionable causes" {
    const cases = [_]struct {
        reason: planner.ReviewReason,
        expected_label: []const u8,
    }{
        .{
            .reason = .taxpayer_identity_missing,
            .expected_label = "No taxpayer identity covers the requested filing period.",
        },
        .{
            .reason = .taxpayer_identity_changed_during_period,
            .expected_label = "The taxpayer identity changed during the requested filing period.",
        },
        .{
            .reason = .evidence_review_missing,
            .expected_label = "Required registration evidence has not been reviewed.",
        },
        .{
            .reason = .evidence_rejected,
            .expected_label = "Required registration evidence was rejected.",
        },
        .{
            .reason = .evidence_superseded,
            .expected_label = "Required registration evidence was superseded.",
        },
    };

    for (cases) |case| {
        try std.testing.expectEqualStrings(
            case.expected_label,
            reviewReasonLabel(case.reason),
        );
    }
}

test "resolved preview snapshot fails closed when resolved state has no payload" {
    var state = State{
        .planning_status = .resolved_not_fileable,
        .resolved_policy_capability = .editor_supported,
        .effective_policy_resolved = true,
        .provenance_validated = true,
    };

    try std.testing.expect(state.resolved_preview_snapshot == null);
    try std.testing.expect(state.resolvedPreviewSnapshot() == null);
    try std.testing.expect(state.resolvedProjectionContext() == null);
}

test "injected reviewed policy validates transient provenance without claiming retention" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    var state = State{};
    const reviewed_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};

    try state.refresh(
        std.testing.allocator,
        &fake_ledger,
        .{},
        fixtureDate("2025-05-01"),
        .{ .revisions = &reviewed_policy },
        2025,
        2,
    );

    try std.testing.expectEqual(@as(usize, 1), state.taxpayer_count);
    try std.testing.expectEqual(@as(usize, 2), state.unit_count);
    try std.testing.expectEqualStrings("***-***-789", state.taxpayers[0].maskedTin());
    try std.testing.expectEqualStrings("00002", state.branchSuggestionLabel());
    try std.testing.expectEqual(PlanningStatus.resolved_not_fileable, state.planning_status);
    try std.testing.expect(state.effectivePolicyResolved());
    const requested_preview_label = state.requestedPreviewLabel(std.testing.allocator);
    defer std.testing.allocator.free(requested_preview_label);
    try std.testing.expectEqualStrings(
        "2550Q · 2024-04-ENCS · Q2 2025",
        requested_preview_label,
    );
    try std.testing.expectEqualStrings(
        "Exact effective policy revision resolved",
        state.policyCatalogLabel(),
    );
    try std.testing.expectEqualStrings("00000", state.resolvedFilingCodeLabel());
    try std.testing.expectEqual(@as(usize, 2), state.resolved_coverage_count);
    const coverage_rows = state.coverageRows();
    try std.testing.expectEqual(@as(usize, 2), coverage_rows.len);
    try std.testing.expectEqualStrings("00001", coverage_rows[0].branchCodeLabel());
    try std.testing.expect(coverage_rows[0].registration_unit_id.eql(
        &fixture.units[1].registration_unit_id,
    ));
    try std.testing.expect(coverage_rows[0].registration_unit_revision_id.eql(
        &fixture.units[1].id,
    ));
    try std.testing.expectEqualStrings("00000", coverage_rows[1].branchCodeLabel());
    try std.testing.expect(coverage_rows[1].registration_unit_id.eql(
        &fixture.units[0].registration_unit_id,
    ));
    try std.testing.expect(coverage_rows[1].registration_unit_revision_id.eql(
        &fixture.units[0].id,
    ));
    try std.testing.expectEqualStrings(
        "***-***-789-00000",
        state.projectionFilerTinLabel(),
    );
    try std.testing.expect(state.provenance_validated);
    const form_revision_label = state.formRevisionLabel(std.testing.allocator);
    defer std.testing.allocator.free(form_revision_label);
    try std.testing.expectEqualStrings(
        "2550Q · 2024-04-ENCS",
        form_revision_label,
    );
    try std.testing.expectEqualStrings(
        "policy-2550q-2024-04",
        state.policyRevisionLabel(),
    );
    const policy_evidence_rows = state.policyEvidenceRows();
    try std.testing.expectEqual(@as(usize, 1), policy_evidence_rows.len);
    try std.testing.expectEqualStrings(
        "bir-2550q-2024-04-instructions",
        policy_evidence_rows[0].evidenceId(),
    );
    try std.testing.expectEqualStrings(
        "bir-2550q-2024-04-instructions",
        state.policyEvidenceLabel(),
    );
    try std.testing.expectEqualStrings(
        "BIR Form 2550Q April 2024 instructions",
        policy_evidence_rows[0].displayName(),
    );
    try std.testing.expectEqualStrings(
        "Branches file one consolidated return at the principal place or head office covering all branches.",
        policy_evidence_rows[0].reviewBasis(),
    );
    try std.testing.expectEqual(@as(usize, 64), state.decisionHashLabel().len);
    try std.testing.expectEqualStrings(
        "Head-office consolidated",
        state.scopeCategoryLabel(),
    );
    try std.testing.expectEqualStrings(
        "Not resolved by filing scope",
        state.venueLabel(),
    );
    try std.testing.expectEqualStrings(
        "Scope provenance validated for this preview; no immutable draft provenance was retained.",
        state.provenanceLabel(),
    );

    const source_records = [_]SourceRecord{
        .{
            .id = try SourceRecordId.parse("source-head"),
            .taxpayer_id = fixture.identity.taxpayer_id,
            .occurred_on = fixtureDate("2025-04-15"),
            .kind = .transaction,
            .attribution = .{ .entered = .{
                .source_unit = .{
                    .registration_unit_id = fixture.units[0].registration_unit_id,
                    .registration_unit_revision_id = fixture.units[0].id,
                },
                .evidence_reference = try SourceEvidenceReference.parse(
                    "import-row-head",
                ),
            } },
        },
        .{
            .id = try SourceRecordId.parse("source-branch"),
            .taxpayer_id = fixture.identity.taxpayer_id,
            .occurred_on = fixtureDate("2025-05-15"),
            .kind = .schedule_fact,
            .attribution = .{ .derived = .{
                .source_unit = .{
                    .registration_unit_id = fixture.units[1].registration_unit_id,
                    .registration_unit_revision_id = fixture.units[1].id,
                },
                .rule_id = try SourceDerivationRuleId.parse("fixture-import"),
                .rule_version = 1,
            } },
        },
        .{
            .id = try SourceRecordId.parse("source-legacy"),
            .taxpayer_id = fixture.identity.taxpayer_id,
            .occurred_on = fixtureDate("2025-06-01"),
            .kind = .attachment,
            .attribution = .{
                .legacy_unknown = .historical_format_without_source_unit,
            },
        },
    };
    state.replaceSourceRecords(&source_records);
    try std.testing.expectEqual(@as(usize, 1), state.sourceRecordRows().len);
    try std.testing.expectEqualStrings(
        "source-head",
        state.sourceRecordRows()[0].stableKey(),
    );
    try std.testing.expectEqual(@as(usize, 1), state.sourceWorkspaceUnresolvedCount());
    try std.testing.expect(state.sourceWorkspaceReviewRequired());
    try std.testing.expect(source_records[2].attribution.sourceUnit() == null);

    const decision_before_switch = state.decision_hash_text;
    const projection_before_switch = state.resolvedPreviewSnapshot().?.projection_context;
    const coverage_before_switch = state.resolvedPreviewSnapshot().?.coverage_rows;
    state.selectRegistrationUnit(1);
    try std.testing.expectEqualStrings("081", state.selectedRegistrationUnit().?.rdoLabel());
    try std.testing.expectEqual(@as(usize, 1), state.sourceRecordRows().len);
    try std.testing.expectEqualStrings(
        "source-branch",
        state.sourceRecordRows()[0].stableKey(),
    );
    try std.testing.expect(source_records[2].attribution.sourceUnit() == null);
    try std.testing.expect(state.sourceWorkspaceReviewRequired());
    const selected_source_binding = state.sourceRecordRows()[0].record
        .attribution.sourceUnit().?;
    try std.testing.expect(
        selected_source_binding.registration_unit_revision_id.eql(
            &fixture.units[1].id,
        ),
    );
    try std.testing.expectEqualStrings("00000", state.resolvedFilingCodeLabel());
    try std.testing.expectEqualStrings("047", state.resolvedFilingRdoLabel());
    const opened = state.resolvedPreviewSnapshotForOpen().?;
    try std.testing.expectEqualStrings("00001", opened.source_workspace_unit.codeLabel());
    try std.testing.expectEqualStrings(
        "00000",
        opened.projection_context.filing_branch_code.asDigits(),
    );
    try std.testing.expectEqual(@as(usize, 2), opened.coverageRows().len);
    try std.testing.expectEqual(@as(usize, 1), opened.sourceRecordRows().len);
    try std.testing.expectEqualStrings(
        "source-branch",
        opened.sourceRecordRows()[0].stableKey(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        opened.source_review_required_count,
    );
    try std.testing.expectEqualStrings(
        "BIR Form 2550Q April 2024 instructions",
        opened.policyEvidenceRows()[0].displayName(),
    );
    try std.testing.expect(projectionContextsEql(
        &projection_before_switch,
        &opened.projection_context,
    ));
    for (
        coverage_before_switch[0..opened.coverage_count],
        opened.coverageRows(),
    ) |before, after| {
        try std.testing.expect(coverageRowsEql(before, after));
    }
    try std.testing.expect(std.mem.eql(
        u8,
        &decision_before_switch,
        &opened.decision_hash_text,
    ));
}

test "missing Filing Unit contact retains legal scope while preview stays blocked" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    fake_ledger.contacts = &.{};
    var state = State{};
    const reviewed_policy = [_]policy.FilingPolicyRevision{
        policy.testing.fixture2550Q(),
    };

    try state.refresh(
        std.testing.allocator,
        &fake_ledger,
        .{},
        fixtureDate("2025-05-01"),
        .{ .revisions = &reviewed_policy },
        2025,
        2,
    );

    try std.testing.expectEqual(PlanningStatus.review_required, state.planning_status);
    var found_missing_contact = false;
    for (state.reviewReasonRows()) |row| {
        if (row.issue.reason == .missing_filing_unit_contact) {
            found_missing_contact = true;
        }
    }
    try std.testing.expect(found_missing_contact);

    try std.testing.expectEqualStrings("00000", state.resolvedFilingCodeLabel());
    try std.testing.expectEqualStrings("047", state.resolvedFilingRdoLabel());
    try std.testing.expectEqualStrings(
        "***-***-789-00000",
        state.projectionFilerTinLabel(),
    );
    try std.testing.expectEqual(@as(usize, 2), state.resolved_coverage_count);
    try std.testing.expectEqual(@as(usize, 2), state.coverageRows().len);
    var found_head_office_coverage = false;
    var found_branch_coverage = false;
    for (state.coverageRows()) |row| {
        if (std.mem.eql(u8, row.branchCodeLabel(), "00000")) {
            found_head_office_coverage = true;
        }
        if (std.mem.eql(u8, row.branchCodeLabel(), "00001")) {
            found_branch_coverage = true;
        }
    }
    try std.testing.expect(found_head_office_coverage);
    try std.testing.expect(found_branch_coverage);
    try std.testing.expect(state.effectivePolicyResolved());
    try std.testing.expect(state.decision_hash_present);
    try std.testing.expectEqual(@as(usize, 0), state.resolved_obligation_count);

    try std.testing.expect(state.resolvedPreviewSnapshot() == null);
    try std.testing.expect(state.resolvedProjectionContext() == null);
    try std.testing.expect(state.resolved_preview_snapshot == null);
    try std.testing.expect(!state.provenance_validated);
    try std.testing.expectEqualStrings(
        "Review Required — Filing Unit and Return Coverage are resolved, but registration contact review blocks the 2550Q preview.",
        state.planningStatusLabel(),
    );
    try std.testing.expectEqualStrings("Not fileable", state.fileabilityLabel());
}

test "revoking preview access clears resolved filing presentation" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    var state = State{};
    const reviewed_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};

    try state.refresh(
        std.testing.allocator,
        &fake_ledger,
        .{},
        fixtureDate("2025-05-01"),
        .{ .revisions = &reviewed_policy },
        2025,
        2,
    );
    try std.testing.expect(state.resolvedPreviewSnapshot() != null);
    try std.testing.expect(state.provenance_validated);
    try std.testing.expect(state.decision_hash_present);

    state.revokeResolvedPreviewAccess();

    try std.testing.expect(state.policy_catalog_missing);
    try std.testing.expectEqual(PlanningStatus.review_required, state.planning_status);
    try std.testing.expect(!state.effectivePolicyResolved());
    try std.testing.expect(state.resolved_filing_code == null);
    try std.testing.expect(state.resolved_filing_rdo_code == null);
    try std.testing.expectEqual(@as(usize, 0), state.resolved_coverage_count);
    try std.testing.expectEqual(@as(usize, 0), state.coverageRows().len);
    try std.testing.expectEqual(@as(usize, 0), state.resolved_obligation_count);
    try std.testing.expect(state.resolved_form_revision == null);
    try std.testing.expect(state.resolved_policy_revision_id == null);
    try std.testing.expect(state.resolved_policy_evidence_id == null);
    try std.testing.expect(state.resolved_policy_capability == null);
    try std.testing.expect(state.resolved_scope_category == null);
    try std.testing.expect(state.resolved_venue == null);
    try std.testing.expect(!state.decision_hash_present);
    try std.testing.expectEqual(@as(u8, 0), state.projection_filer_tin_len);
    try std.testing.expect(state.resolved_preview_snapshot == null);
    try std.testing.expect(state.resolvedPreviewSnapshot() == null);
    try std.testing.expect(state.resolvedProjectionContext() == null);
    try std.testing.expect(!state.provenance_validated);
}

test "production preview is Review Required without a policy fixture" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    var state = State{};

    try state.refreshProduction(
        std.testing.allocator,
        &fake_ledger,
        .{},
        fixtureDate("2025-05-01"),
        2025,
        2,
    );

    try std.testing.expectEqual(PlanningStatus.review_required, state.planning_status);
    try std.testing.expect(state.policy_catalog_missing);
    try std.testing.expect(!state.effectivePolicyResolved());
    try std.testing.expectEqual(@as(usize, 2), state.planning_reason_count);
    for (state.planning_reasons[0..state.planning_reason_count]) |row| {
        try std.testing.expectEqual(
            planner.ReviewReason.missing_effective_policy,
            row.issue.reason,
        );
    }
    try std.testing.expectEqualStrings("Not resolved", state.resolvedFilingCodeLabel());
    try std.testing.expectEqualStrings(
        "Policy catalog unavailable — Review Required",
        state.policyCatalogLabel(),
    );
    const requested_preview_label = state.requestedPreviewLabel(std.testing.allocator);
    defer std.testing.allocator.free(requested_preview_label);
    try std.testing.expectEqualStrings(
        "2550Q · 2024-04-ENCS · Q2 2025",
        requested_preview_label,
    );
    try std.testing.expectEqualStrings("Not resolved", state.formRevisionLabel(std.testing.allocator));
    try std.testing.expectEqualStrings("Not fileable", state.fileabilityLabel());
}

test "nonempty unrelated policy catalog does not claim exact policy resolution" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    var state = State{};
    const unrelated_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2551Q()};

    try state.refresh(
        std.testing.allocator,
        &fake_ledger,
        .{},
        fixtureDate("2025-05-01"),
        .{ .revisions = &unrelated_policy },
        2025,
        2,
    );

    try std.testing.expect(!state.policy_catalog_missing);
    try std.testing.expect(!state.effectivePolicyResolved());
    try std.testing.expectEqualStrings(
        "Policy catalog loaded, but no exact effective policy revision resolved — Review Required",
        state.policyCatalogLabel(),
    );
}

test "workspace rejects review results it cannot preserve completely" {
    var issues: [max_review_reasons + 1]planner.ReviewIssue = undefined;
    for (&issues) |*issue| {
        issue.* = .{
            .reason = .missing_effective_policy,
            .subject = .planning_request,
        };
    }
    const overflowing_plan = planner.ResolvedFilingPlan{
        .review_required = .{ .issues = &issues },
    };
    var state = State{};

    state.presentResolvedPlan(
        std.testing.allocator,
        &overflowing_plan,
        production_policy_catalog,
    );

    try std.testing.expectEqual(PlanningStatus.integration_error, state.planning_status);
    try std.testing.expectEqual(
        IntegrationReason.review_issue_capacity_exceeded,
        state.integration_reason,
    );
    try std.testing.expectEqual(@as(usize, 0), state.reviewReasonRows().len);
    try std.testing.expectEqualStrings(
        "Review Required — the planner returned more repair actions than this workspace can preserve, so none are shown.",
        state.planningStatusLabel(),
    );
}

test "resolved preview fails closed when policy evidence metadata cannot be loaded" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    const reviewed_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = planner.FilingPlanner.init(.{ .revisions = &reviewed_policy });
    var plan = try filing_planner.plan(std.testing.allocator, &fake_ledger, .{}, .{
        .taxpayer_id = fixture.identity.taxpayer_id,
        .form_revision = requested_preview_form_revision,
        .civil_period = try quarterPeriod(2025, 2),
    });
    defer plan.deinit(std.testing.allocator);
    var state = State{};

    state.presentResolvedPlan(
        std.testing.allocator,
        &plan,
        production_policy_catalog,
    );

    try std.testing.expectEqual(PlanningStatus.integration_error, state.planning_status);
    try std.testing.expectEqual(
        IntegrationReason.policy_evidence_metadata_unavailable,
        state.integration_reason,
    );
    try std.testing.expect(state.resolvedPreviewSnapshot() == null);
    try std.testing.expectEqualStrings(
        "Review Required — the resolved policy evidence explanation is missing, oversized, or inconsistent with the policy revision.",
        state.planningStatusLabel(),
    );
}

test "workspace refuses a multi-obligation result instead of mixing presenters" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    const reviewed_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = planner.FilingPlanner.init(.{ .revisions = &reviewed_policy });
    var plan = try filing_planner.plan(std.testing.allocator, &fake_ledger, .{}, .{
        .taxpayer_id = fixture.identity.taxpayer_id,
        .form_revision = requested_preview_form_revision,
        .civil_period = try quarterPeriod(2025, 2),
    });
    defer plan.deinit(std.testing.allocator);
    const obligation = switch (plan) {
        .obligations => |obligations| obligations[0],
        else => return error.ExpectedResolvedObligation,
    };
    var duplicate_obligations = [_]planner.FilingObligation{
        obligation,
        obligation,
    };
    const duplicate_plan = planner.ResolvedFilingPlan{
        .obligations = &duplicate_obligations,
    };
    var state = State{};

    state.presentResolvedPlan(
        std.testing.allocator,
        &duplicate_plan,
        .{ .revisions = &reviewed_policy },
    );

    try std.testing.expectEqual(PlanningStatus.integration_error, state.planning_status);
    try std.testing.expectEqual(
        IntegrationReason.unexpected_obligation_count,
        state.integration_reason,
    );
    try std.testing.expectEqual(@as(usize, 2), state.resolved_obligation_count);
    try std.testing.expectEqual(@as(usize, 0), state.coverageRows().len);
    try std.testing.expectEqualStrings("Not resolved", state.resolvedFilingCodeLabel());
}

test "historical projection uses the identity bound into the resolved plan" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    var historical_identity = fake_ledger.identity;
    historical_identity.effective = registration.EffectivePeriod.init(
        fixtureDate("2024-01-01"),
        fixtureDate("2025-12-31"),
    ) catch unreachable;
    fake_ledger.planning_identity = historical_identity;
    fake_ledger.identity.id = fixtureId(
        registration.TaxpayerRevisionId,
        "taxpayer-rev-newer",
    );
    fake_ledger.identity.sequence = 2;
    fake_ledger.identity.effective = fixturePeriod("2026-01-01");
    fake_ledger.identity.tin_root = registration.Tin9.parse(
        "987654321",
    ) catch unreachable;
    var state = State{};
    const reviewed_policy = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};

    try state.refresh(
        std.testing.allocator,
        &fake_ledger,
        .{},
        fixtureDate("2026-05-01"),
        .{ .revisions = &reviewed_policy },
        2025,
        2,
    );

    try std.testing.expectEqualStrings(
        "***-***-321",
        state.taxpayers[0].maskedTin(),
    );
    try std.testing.expectEqual(
        PlanningStatus.resolved_not_fileable,
        state.planning_status,
    );
    try std.testing.expectEqualStrings(
        "***-***-789-00000",
        state.projectionFilerTinLabel(),
    );
    try std.testing.expect(state.provenance_validated);
}

test "reviewed confirmation accepts original effective date and rejects earlier date" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    fake_ledger.identity.evidence_id = null;
    var state = State{};
    state.selected_identity = fake_ledger.identity;
    var pending = fixture.units[1];
    pending.status = .pending_evidence;
    pending.branch_code_evidence = .{
        .unconfirmed = registration.BranchCode5.parse("00002") catch unreachable,
    };
    pending.lifecycle_evidence_id = null;
    pending.effective = fixturePeriod("2026-01-01");
    state.units[0] = makeUnitRow(0, pending);
    state.unit_count = 1;
    state.selected_registration_unit_index = 0;
    state.syncRegistrationUnitSelection();

    var common = validConfirmationInput();
    common.reviewed_evidence.effective_from = "2025-12-31";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, common));
    try std.testing.expectEqual(
        ActionStatus.effective_date_must_advance,
        state.action_status,
    );
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);

    var same_day = common;
    same_day.reviewed_evidence.effective_from = "2026-01-01";
    try std.testing.expect(state.confirmSelectedUnit(&fake_ledger, same_day));
    try std.testing.expect(fake_ledger.reviewed_bundle_seen);
    try std.testing.expect(fake_ledger.reviewed_bundle_local_owner);
    try std.testing.expect(fake_ledger.reviewed_bundle_exact);
    try std.testing.expect(!fake_ledger.reviewed_bundle_legacy_resolved);
    try std.testing.expect(!fake_ledger.reviewed_bundle_contact_revised);
    try std.testing.expectEqualStrings(
        "081",
        fake_ledger.reviewed_bundle_rdo.?.asDigits(),
    );
    const contact = fake_ledger.reviewed_bundle_contact.?;
    try std.testing.expectEqualStrings(
        "456 Branch Avenue, Makati City",
        contact.registered_address.asSlice(),
    );
    try std.testing.expectEqualStrings("1200", contact.zip_code.?.asSlice());
    try std.testing.expectEqualStrings(
        "+639177654321",
        contact.contact_number.?.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "branch@example.test",
        contact.email_address.?.asSlice(),
    );
}

test "Registration Unit confirmation persists every selectable evidence source and review basis" {
    const cases = [_]struct {
        source_kind: EvidenceSourceKind,
        expected_reason: []const u8,
    }{
        .{
            .source_kind = .cor,
            .expected_reason = "Human reviewed the selected Certificate of Registration (COR) against the entered Registration Unit facts.",
        },
        .{
            .source_kind = .ecor,
            .expected_reason = "Human reviewed the selected electronic Certificate of Registration (eCOR) against the entered Registration Unit facts.",
        },
        .{
            .source_kind = .bir_registration_record,
            .expected_reason = "Human reviewed the selected BIR registration record against the entered Registration Unit facts.",
        },
    };

    for (cases) |case| {
        var fixture = WorkspaceFixture.init();
        var fake_ledger = fixture.ledger();
        var state = State{};
        state.selected_identity = fake_ledger.identity;
        var pending = fixture.units[1];
        pending.status = .pending_evidence;
        pending.branch_code_evidence = .{
            .unconfirmed = registration.BranchCode5.parse("00002") catch unreachable,
        };
        pending.lifecycle_evidence_id = null;
        pending.effective = fixturePeriod("2026-01-01");
        state.units[0] = makeUnitRow(0, pending);
        state.unit_count = 1;
        state.selected_registration_unit_index = 0;
        state.syncRegistrationUnitSelection();
        var input = validConfirmationInput();
        input.reviewed_evidence.source_kind = case.source_kind;

        try std.testing.expect(state.confirmSelectedUnit(&fake_ledger, input));
        try std.testing.expect(fake_ledger.reviewed_bundle_exact);
        try std.testing.expectEqual(
            case.source_kind,
            fake_ledger.reviewed_bundle_source_kind.?,
        );
        try std.testing.expectEqualStrings(
            case.expected_reason,
            fake_ledger.reviewed_bundle_reason,
        );
    }
}

test "reviewed confirmation validates contact facts and evidence date before writing" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    var state = State{};
    state.selected_identity = fake_ledger.identity;
    var pending = fixture.units[1];
    pending.status = .pending_evidence;
    pending.branch_code_evidence = .{
        .unconfirmed = registration.BranchCode5.parse("00002") catch unreachable,
    };
    pending.lifecycle_evidence_id = null;
    pending.effective = fixturePeriod("2026-01-01");
    state.units[0] = makeUnitRow(0, pending);
    state.unit_count = 1;
    state.selected_registration_unit_index = 0;
    state.syncRegistrationUnitSelection();

    const valid = validConfirmationInput();
    var invalid = valid;
    invalid.registered_address = " ";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, invalid));
    try std.testing.expectEqual(ActionStatus.invalid_registered_address, state.action_status);

    invalid = valid;
    invalid.zip_code = "120";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, invalid));
    try std.testing.expectEqual(ActionStatus.invalid_zip_code, state.action_status);

    invalid = valid;
    invalid.contact_number = "not a phone";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, invalid));
    try std.testing.expectEqual(ActionStatus.invalid_contact_number, state.action_status);

    invalid = valid;
    invalid.email_address = "missing-at.example.test";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, invalid));
    try std.testing.expectEqual(ActionStatus.invalid_email_address, state.action_status);

    invalid = valid;
    invalid.reviewed_evidence.evidence_captured_on = "2026-13-01";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, invalid));
    try std.testing.expectEqual(ActionStatus.invalid_evidence_date, state.action_status);
    try std.testing.expectEqualStrings(
        "Enter a valid evidence capture date as YYYY-MM-DD.",
        state.action_status.label(),
    );

    invalid = valid;
    invalid.reviewed_evidence.evidence_path = " ";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, invalid));
    try std.testing.expectEqual(ActionStatus.invalid_evidence_path, state.action_status);

    invalid = valid;
    invalid.reviewed_evidence.evidence_path =
        "x" ** (storage_contract.max_evidence_storage_reference_bytes + 1);
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, invalid));
    try std.testing.expectEqual(ActionStatus.invalid_evidence_path, state.action_status);
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);

    invalid = valid;
    invalid.reviewed_evidence.evidence_sha256 =
        "ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, invalid));
    try std.testing.expectEqual(
        ActionStatus.invalid_evidence_digest,
        state.action_status,
    );
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);

    invalid = valid;
    invalid.reviewed_evidence.evidence_byte_size = "0";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, invalid));
    try std.testing.expectEqual(ActionStatus.invalid_evidence_size, state.action_status);
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);
}

test "confirmation requires an independently observed taxpayer TIN" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    fake_ledger.identity.evidence_id = null;
    var state = State{};
    state.selected_identity = fake_ledger.identity;
    var pending = fixture.units[1];
    pending.status = .pending_evidence;
    pending.branch_code_evidence = .{
        .unconfirmed = registration.BranchCode5.parse("00002") catch unreachable,
    };
    pending.lifecycle_evidence_id = null;
    pending.effective = fixturePeriod("2026-01-01");
    state.units[0] = makeUnitRow(0, pending);
    state.unit_count = 1;
    state.selected_registration_unit_index = 0;
    state.syncRegistrationUnitSelection();

    var input = validConfirmationInput();
    input.observed_tin_root = "";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, input));
    try std.testing.expectEqual(
        ActionStatus.invalid_observed_tin_root,
        state.action_status,
    );
    try std.testing.expectEqual(@as(usize, 0), fake_ledger.generated_id_count);
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);

    input.observed_tin_root = "12345678x";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, input));
    try std.testing.expectEqual(
        ActionStatus.invalid_observed_tin_root,
        state.action_status,
    );
    try std.testing.expectEqual(@as(usize, 0), fake_ledger.generated_id_count);

    input.observed_tin_root = "987654321";
    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, input));
    try std.testing.expectEqual(
        ActionStatus.observed_tin_root_mismatch,
        state.action_status,
    );
    try std.testing.expectEqualStrings(
        "Review Required — the taxpayer TIN on the reviewed evidence does not match the selected taxpayer. No change was saved.",
        state.action_status.label(),
    );
    try std.testing.expectEqual(@as(usize, 0), fake_ledger.generated_id_count);
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);

    input.observed_tin_root = "123456789";
    try std.testing.expect(state.confirmSelectedUnit(&fake_ledger, input));
    try std.testing.expect(fake_ledger.generated_id_count > 0);
    try std.testing.expect(fake_ledger.reviewed_bundle_seen);
    try std.testing.expect(fake_ledger.reviewed_bundle_exact);
    try std.testing.expectEqualStrings(
        "123456789",
        fake_ledger.reviewed_bundle_tin_root.?.asDigits(),
    );
}

test "branch confirmation cannot assert taxpayer VAT registration" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    var state = State{};
    state.selected_identity = fake_ledger.identity;
    var pending = fixture.units[1];
    pending.status = .pending_evidence;
    pending.branch_code_evidence = .{
        .unconfirmed = registration.BranchCode5.parse("00002") catch unreachable,
    };
    pending.lifecycle_evidence_id = null;
    pending.effective = fixturePeriod("2026-01-01");
    state.units[0] = makeUnitRow(0, pending);
    state.unit_count = 1;
    state.selected_registration_unit_index = 0;
    state.syncRegistrationUnitSelection();
    var input = validConfirmationInput();
    input.confirm_vat_registration = true;

    try std.testing.expect(!state.confirmSelectedUnit(&fake_ledger, input));
    try std.testing.expectEqual(
        ActionStatus.vat_registration_requires_head_office,
        state.action_status,
    );
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);
}

test "legacy evidence review emits legacy resolution and contact creation atomically" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    var state = State{};
    state.selected_identity = fake_ledger.identity;
    var legacy = fixture.units[1];
    legacy.status = .legacy_unresolved;
    legacy.branch_code_evidence = .{
        .legacy_unresolved = registration.LegacyBranchSuffix.parse("001") catch unreachable,
    };
    legacy.rdo_code = null;
    legacy.lifecycle_evidence_id = null;
    legacy.effective = fixturePeriod("2026-01-01");
    state.units[0] = makeUnitRow(0, legacy);
    state.unit_count = 1;
    state.selected_registration_unit_index = 0;
    state.syncRegistrationUnitSelection();

    var input = validConfirmationInput();
    input.observed_branch_code = "00007";
    try std.testing.expect(state.confirmSelectedUnit(&fake_ledger, input));
    try std.testing.expect(fake_ledger.reviewed_bundle_exact);
    try std.testing.expect(fake_ledger.reviewed_bundle_legacy_resolved);
    try std.testing.expect(!fake_ledger.reviewed_bundle_contact_revised);
}

test "reviewed confirmation revises an existing unit contact in the same bundle" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    var state = State{};
    state.selected_identity = fake_ledger.identity;
    var pending = fixture.units[1];
    pending.status = .pending_evidence;
    pending.branch_code_evidence = .{
        .unconfirmed = registration.BranchCode5.parse("00002") catch unreachable,
    };
    pending.lifecycle_evidence_id = null;
    pending.effective = fixturePeriod("2026-01-01");
    var current_contact = fixture.contacts[0];
    current_contact.registration_unit_id = pending.registration_unit_id;
    current_contact.id = fixtureId(
        registration.RegistrationUnitContactRevisionId,
        "branch-contact-rev-a",
    );
    current_contact.effective = fixturePeriod("2026-01-01");
    state.units[0] = makeUnitRow(0, pending);
    state.units[0].contact_revision = current_contact;
    state.unit_count = 1;
    state.selected_registration_unit_index = 0;
    state.syncRegistrationUnitSelection();

    try std.testing.expect(state.confirmSelectedUnit(
        &fake_ledger,
        validConfirmationInput(),
    ));
    try std.testing.expect(fake_ledger.reviewed_bundle_exact);
    try std.testing.expect(fake_ledger.reviewed_bundle_contact_revised);
}

test "confirmed head office accepts a separate exact VAT evidence bundle" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    fake_ledger.tax_type_registrations = &.{};

    var state = State{};
    state.selected_identity = fake_ledger.identity;
    state.units[0] = makeUnitRow(0, fixture.units[0]);
    state.unit_count = 1;
    state.selected_registration_unit_index = 0;
    state.syncRegistrationUnitSelection();

    var missing_assertion = validVatRegistrationInput();
    missing_assertion.assert_active_vat_registration = false;
    try std.testing.expect(!state.recordSelectedHeadOfficeVatRegistration(
        &fake_ledger,
        missing_assertion,
    ));
    try std.testing.expectEqual(
        ActionStatus.vat_registration_assertion_required,
        state.action_status,
    );
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);

    var invalid_tin = validVatRegistrationInput();
    invalid_tin.observed_tin_root = "12345678x";
    try std.testing.expect(!state.recordSelectedHeadOfficeVatRegistration(
        &fake_ledger,
        invalid_tin,
    ));
    try std.testing.expectEqual(
        ActionStatus.invalid_observed_tin_root,
        state.action_status,
    );
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);

    var mismatched_tin = validVatRegistrationInput();
    mismatched_tin.observed_tin_root = "987654321";
    try std.testing.expect(!state.recordSelectedHeadOfficeVatRegistration(
        &fake_ledger,
        mismatched_tin,
    ));
    try std.testing.expectEqual(
        ActionStatus.observed_tin_root_mismatch,
        state.action_status,
    );
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);

    const recorded = state.recordSelectedHeadOfficeVatRegistration(
        &fake_ledger,
        validVatRegistrationInput(),
    );
    try std.testing.expectEqual(
        ActionStatus.vat_registration_recorded,
        state.action_status,
    );
    try std.testing.expect(recorded);
    try std.testing.expect(fake_ledger.reviewed_bundle_local_owner);
    try std.testing.expect(fake_ledger.reviewed_bundle_exact);
    try std.testing.expect(fake_ledger.reviewed_vat_bundle_exact);
    try std.testing.expect(
        fake_ledger.reviewed_bundle_tin_root.?.eql(&fixture.identity.tin_root),
    );
    try std.testing.expectEqual(
        ActionStatus.vat_registration_recorded,
        state.action_status,
    );

    state.units[0].vat_registration_state = .confirmed_active;
    try std.testing.expect(!state.recordSelectedHeadOfficeVatRegistration(
        &fake_ledger,
        validVatRegistrationInput(),
    ));
    try std.testing.expectEqual(
        ActionStatus.vat_registration_not_recordable,
        state.action_status,
    );
}

test "VAT confirmation persists every selectable evidence source and review basis" {
    const cases = [_]struct {
        source_kind: EvidenceSourceKind,
        expected_reason: []const u8,
    }{
        .{
            .source_kind = .cor,
            .expected_reason = "Human reviewed the selected Certificate of Registration (COR) against the entered taxpayer TIN and for an active VAT registration.",
        },
        .{
            .source_kind = .ecor,
            .expected_reason = "Human reviewed the selected electronic Certificate of Registration (eCOR) against the entered taxpayer TIN and for an active VAT registration.",
        },
        .{
            .source_kind = .bir_registration_record,
            .expected_reason = "Human reviewed the selected BIR registration record against the entered taxpayer TIN and for an active VAT registration.",
        },
    };

    for (cases) |case| {
        var fixture = WorkspaceFixture.init();
        var fake_ledger = fixture.ledger();
        fake_ledger.tax_type_registrations = &.{};
        var state = State{};
        state.selected_identity = fake_ledger.identity;
        state.units[0] = makeUnitRow(0, fixture.units[0]);
        state.unit_count = 1;
        state.selected_registration_unit_index = 0;
        state.syncRegistrationUnitSelection();
        var input = validVatRegistrationInput();
        input.reviewed_evidence.source_kind = case.source_kind;

        try std.testing.expect(state.recordSelectedHeadOfficeVatRegistration(
            &fake_ledger,
            input,
        ));
        try std.testing.expect(fake_ledger.reviewed_vat_bundle_exact);
        try std.testing.expectEqual(
            case.source_kind,
            fake_ledger.reviewed_bundle_source_kind.?,
        );
        try std.testing.expectEqualStrings(
            case.expected_reason,
            fake_ledger.reviewed_bundle_reason,
        );
    }
}

test "VAT evidence repair rejects a confirmed branch" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    fake_ledger.tax_type_registrations = &.{};

    var state = State{};
    state.selected_identity = fake_ledger.identity;
    state.units[0] = makeUnitRow(0, fixture.units[1]);
    state.unit_count = 1;
    state.selected_registration_unit_index = 0;
    state.syncRegistrationUnitSelection();

    try std.testing.expect(!state.recordSelectedHeadOfficeVatRegistration(
        &fake_ledger,
        validVatRegistrationInput(),
    ));
    try std.testing.expectEqual(
        ActionStatus.vat_registration_not_recordable,
        state.action_status,
    );
    try std.testing.expect(!fake_ledger.reviewed_bundle_seen);
}

test "create actions call ledger with pending taxpayer and explicit branch candidate" {
    var fixture = WorkspaceFixture.init();
    var fake_ledger = fixture.ledger();
    var state = State{};
    try std.testing.expect(state.createPendingTaxpayer(
        &fake_ledger,
        "987654321",
        "2026-01-01",
    ) != null);
    try std.testing.expect(fake_ledger.create_taxpayer_seen);

    state.taxpayers[0] = .{
        .id = 0,
        .taxpayer_id = fixture.identity.taxpayer_id,
        .selected = true,
    };
    state.taxpayer_count = 1;
    state.selected_taxpayer_index = 0;
    try std.testing.expect(state.createPendingBranch(
        &fake_ledger,
        "00004",
        "2026-01-02",
    ) != null);
    try std.testing.expect(fake_ledger.create_branch_seen);
}
