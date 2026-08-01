//! Provider-neutral, observational production-storage evidence validation.
//!
//! This module records and validates structural qualification completeness. It
//! selects no provider or backend, accepts no key material, performs no I/O,
//! and exposes no path that can mint production storage authority. A complete
//! verdict remains observational while the source-selected production state is
//! unavailable.

const std = @import("std");
pub const requirements = @import("production_storage_requirements.zig");

pub const Digest = [32]u8;
pub const current_schema_version: u16 = 1;
pub const production_authority_minted = false;

pub const EvidenceAuthorityClaim = enum {
    observational_unselected,
    attempted_self_selection,
};

pub const EffectiveSourceSelection = enum {
    unavailable_unselected,
};

pub const ObservationResult = enum {
    passed,
    failed,
};

pub const DecisionResult = enum {
    approved,
    pending,
    denied,
};

pub const ComponentKind = enum {
    custody_provider,
    authenticated_storage_backend,
};

pub const ComponentIdentity = struct {
    stable_id: []const u8,
    version: []const u8,
    configuration_id: []const u8,
    binary_sha256: Digest,
    configuration_sha256: Digest,
    binding_sha256: Digest,
};

pub const ArchitectureComponentIdentity = struct {
    architecture: requirements.WindowsArchitecture,
    provider: ComponentIdentity,
    backend: ComponentIdentity,
    binding_sha256: Digest,
};

pub const ArchitectureArtifactIdentity = struct {
    architecture: requirements.WindowsArchitecture,
    target_triple: []const u8,
    pe_machine: u16,
    os_build_id: []const u8,
    conformance_harness_version: []const u8,
    executable_sha256: Digest,
    package_inventory_sha256: Digest,
    package_manifest_sha256: Digest,
    toolchain_sha256: Digest,
    conformance_harness_sha256: Digest,
    binding_sha256: Digest,
};

pub const PrincipalBinding = struct {
    stable_id: []const u8,
    binding_sha256: Digest,
};

pub const ProtectedSurfaceResult = struct {
    id: requirements.ProtectedArtifactSurface,
    result: ObservationResult,
};

pub const BackendRequirementResult = struct {
    id: requirements.AuthenticatedBackendRequirement,
    result: ObservationResult,
};

pub const CustodyFailureResult = struct {
    id: requirements.CustodyFailClosedCondition,
    result: ObservationResult,
};

pub const RecoveryScenarioResult = struct {
    id: requirements.RecoveryScenario,
    result: ObservationResult,
};

pub const RepositoryArtifactStateResult = struct {
    id: requirements.RepositoryArtifactState,
    result: ObservationResult,
};

pub const QualificationScenarioResult = struct {
    architecture: requirements.WindowsArchitecture,
    id: requirements.QualificationScenario,
    result: ObservationResult,
    qualification_binding_sha256: Digest,
    architecture_artifact_binding_sha256: Digest,
    architecture_component_binding_sha256: Digest,
    provider_identity_binding_sha256: Digest,
    backend_identity_binding_sha256: Digest,
    result_record_sha256: Digest,
};

pub const KeyPurposeSeparationResult = struct {
    architecture: requirements.WindowsArchitecture,
    compared_domain: requirements.KeyPurposeDomain,
    material_distinct: ObservationResult,
    non_derived: ObservationResult,
    handle_not_reused: ObservationResult,
    qualification_binding_sha256: Digest,
    architecture_artifact_binding_sha256: Digest,
    architecture_component_binding_sha256: Digest,
    separation_attestation_sha256: Digest,
    result_record_sha256: Digest,
};

pub const DecisionApproval = struct {
    id: requirements.ExternalDecision,
    result: DecisionResult,
    owner: PrincipalBinding,
    reviewer: PrincipalBinding,
    approved_at_unix_seconds: i64,
    expires_at_unix_seconds: i64,
    revoked: bool,
    qualification_binding_sha256: Digest,
    architecture_component_set_binding_sha256: Digest,
    approval_attestation_sha256: Digest,
    approval_record_sha256: Digest,
};

pub const QualificationEvidence = struct {
    schema_version: u16,
    authority_claim: EvidenceAuthorityClaim,
    recorded_at_unix_seconds: i64,
    expires_at_unix_seconds: i64,
    revoked: bool,

    reviewed_source_inventory_sha256: Digest,
    architecture_artifacts: []const ArchitectureArtifactIdentity,
    architecture_components: []const ArchitectureComponentIdentity,
    architecture_component_set_binding_sha256: Digest,
    qualification_binding_sha256: Digest,
    canonical_evidence_sha256: Digest,

    protected_surfaces: []const ProtectedSurfaceResult,
    backend_requirements: []const BackendRequirementResult,
    custody_failures: []const CustodyFailureResult,
    recovery_scenarios: []const RecoveryScenarioResult,
    repository_artifact_states: []const RepositoryArtifactStateResult,
    qualification_results: []const QualificationScenarioResult,
    key_purpose_separation_results: []const KeyPurposeSeparationResult,
    decision_approvals: []const DecisionApproval,
};

pub const EvidenceGate = enum {
    schema_and_observational_authority,
    evidence_time_window,
    exact_architecture_artifacts,
    stable_component_identities,
    protected_surface_coverage,
    backend_requirement_coverage,
    custody_failure_coverage,
    recovery_scenario_coverage,
    repository_artifact_state_coverage,
    dual_architecture_qualification_matrix,
    key_purpose_separation_matrix,
    external_decision_approvals,
    canonical_evidence_binding,
};

pub const ValidationStatus = enum {
    rejected,
    structurally_complete_observational_only,
};

/// Closed and value-free. Provider error text, paths, keys, taxpayer values,
/// and approval identities must never be carried in a validation failure.
pub const ValidationFailure = enum {
    none,
    unsupported_schema,
    evidence_attempted_self_selection,
    invalid_validation_time,
    invalid_evidence_time_window,
    evidence_expired,
    evidence_revoked,
    zero_reviewed_source_inventory_digest,
    duplicate_architecture_artifact,
    missing_architecture_artifact,
    invalid_architecture_target_binding,
    zero_architecture_executable_digest,
    zero_architecture_package_inventory_digest,
    zero_architecture_package_manifest_digest,
    zero_architecture_toolchain_digest,
    zero_architecture_conformance_harness_digest,
    invalid_architecture_os_build_identity,
    invalid_architecture_conformance_harness_version,
    architecture_artifact_binding_mismatch,
    architecture_executable_digest_not_distinct,
    duplicate_architecture_component_identity,
    missing_architecture_component_identity,
    invalid_provider_identity,
    invalid_backend_identity,
    zero_provider_binary_digest,
    zero_provider_configuration_digest,
    zero_backend_binary_digest,
    zero_backend_configuration_digest,
    provider_identity_binding_mismatch,
    backend_identity_binding_mismatch,
    provider_backend_identity_not_distinct,
    architecture_component_binding_mismatch,
    provider_product_identity_inconsistent_across_architectures,
    backend_product_identity_inconsistent_across_architectures,
    provider_binary_digest_not_distinct,
    backend_binary_digest_not_distinct,
    zero_architecture_component_set_binding_digest,
    architecture_component_set_binding_mismatch,
    zero_qualification_binding_digest,
    qualification_binding_mismatch,
    duplicate_protected_surface,
    missing_protected_surface,
    failed_protected_surface,
    duplicate_backend_requirement,
    missing_backend_requirement,
    failed_backend_requirement,
    duplicate_custody_failure,
    missing_custody_failure,
    failed_custody_failure,
    duplicate_recovery_scenario,
    missing_recovery_scenario,
    failed_recovery_scenario,
    duplicate_repository_artifact_state,
    missing_repository_artifact_state,
    failed_repository_artifact_state,
    unexpected_qualification_architecture_pair,
    duplicate_qualification_architecture_pair,
    missing_qualification_architecture_pair,
    failed_qualification_scenario,
    qualification_architecture_artifact_binding_mismatch,
    qualification_architecture_component_binding_mismatch,
    qualification_identity_binding_mismatch,
    qualification_result_digest_mismatch,
    unexpected_key_purpose_separation_domain,
    duplicate_key_purpose_separation_pair,
    missing_key_purpose_separation_pair,
    failed_key_material_distinction,
    failed_key_non_derivation,
    failed_key_handle_non_reuse,
    key_purpose_architecture_binding_mismatch,
    zero_key_purpose_separation_attestation_digest,
    key_purpose_separation_result_digest_mismatch,
    duplicate_external_decision,
    missing_external_decision,
    decision_not_approved,
    invalid_decision_owner,
    invalid_decision_reviewer,
    decision_owner_reviewer_not_distinct,
    invalid_decision_time_window,
    decision_expired,
    decision_revoked,
    decision_identity_binding_mismatch,
    zero_decision_attestation_digest,
    decision_record_digest_mismatch,
    zero_canonical_evidence_digest,
    canonical_evidence_digest_mismatch,
};

pub const VerdictCounts = struct {
    gates_required: usize,
    gates_passed: usize,
    records_required: usize,
    records_presented: usize,
    /// Records whose complete validation gate has passed. This is deliberately
    /// not initialized from caller-claimed `passed`/`approved` values.
    records_validated: usize,
};

pub const ValidationVerdict = struct {
    status: ValidationStatus,
    failure: ValidationFailure,
    counts: VerdictCounts,
    all_required_evidence_gates_passed: bool,
    effective_source_selection: EffectiveSourceSelection,
    production_authorized: bool,
};

pub const required_qualification_result_count: usize = blk: {
    var count: usize = 0;
    for (requirements.required_windows_architectures) |architecture| {
        for (requirements.required_qualification_scenarios) |scenario| {
            if (qualificationScenarioAppliesToArchitecture(
                scenario,
                architecture,
            )) {
                count += 1;
            }
        }
    }
    break :blk count;
};

pub const required_key_purpose_separation_result_count: usize =
    requirements.required_windows_architectures.len *
    requirements.required_database_key_separation_domains.len;

pub fn qualificationScenarioAppliesToArchitecture(
    scenario: requirements.QualificationScenario,
    architecture: requirements.WindowsArchitecture,
) bool {
    return switch (scenario) {
        .windows_x86_64_release => architecture == .x86_64,
        .windows_aarch64_release => architecture == .aarch64,
        .clean_install_and_first_provision,
        .normal_restart_and_concurrent_wal,
        .wrong_user_wrong_machine_and_wrong_key,
        .tamper_truncation_replay_and_artifact_swap,
        .full_bundle_replay_and_restore_freshness,
        .crash_during_provision_migration_and_rotation,
        .backup_restore_transfer_and_unrecoverable_key,
        .upgrade_downgrade_and_cipher_version_mismatch,
        .windows_acl_reparse_and_file_identity_attacks,
        .packaged_binary_provenance_and_code_signing,
        => true,
    };
}

pub fn expectedTargetTriple(
    architecture: requirements.WindowsArchitecture,
) []const u8 {
    return switch (architecture) {
        .x86_64 => "x86_64-windows",
        .aarch64 => "aarch64-windows",
    };
}

pub fn expectedPeMachine(
    architecture: requirements.WindowsArchitecture,
) u16 {
    return switch (architecture) {
        .x86_64 => 0x8664,
        .aarch64 => 0xaa64,
    };
}

pub fn architectureArtifactBinding(
    artifact: ArchitectureArtifactIdentity,
) Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.production-storage-architecture-artifact.v1");
    hash.update(&.{@intFromEnum(artifact.architecture)});
    updateLengthPrefixed(&hash, artifact.target_triple);
    updateU16(&hash, artifact.pe_machine);
    updateLengthPrefixed(&hash, artifact.os_build_id);
    updateLengthPrefixed(&hash, artifact.conformance_harness_version);
    hash.update(&artifact.executable_sha256);
    hash.update(&artifact.package_inventory_sha256);
    hash.update(&artifact.package_manifest_sha256);
    hash.update(&artifact.toolchain_sha256);
    hash.update(&artifact.conformance_harness_sha256);
    return finishDigest(&hash);
}

pub fn architectureComponentBinding(
    identity: ArchitectureComponentIdentity,
) Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.production-storage-architecture-components.v1");
    hash.update(&.{@intFromEnum(identity.architecture)});
    hash.update(&identity.provider.binding_sha256);
    hash.update(&identity.backend.binding_sha256);
    return finishDigest(&hash);
}

pub fn architectureComponentSetBinding(
    identities: []const ArchitectureComponentIdentity,
) Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.production-storage-component-set.v1");
    for (requirements.required_windows_architectures) |architecture| {
        if (findArchitectureComponent(identities, architecture)) |identity| {
            hash.update(&identity.binding_sha256);
        } else {
            const zero_digest = std.mem.zeroes(Digest);
            hash.update(&zero_digest);
        }
    }
    return finishDigest(&hash);
}

pub fn componentIdentityBinding(
    kind: ComponentKind,
    identity: ComponentIdentity,
) Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.production-storage-component-identity.v1");
    hash.update(&.{@intFromEnum(kind)});
    updateLengthPrefixed(&hash, identity.stable_id);
    updateLengthPrefixed(&hash, identity.version);
    updateLengthPrefixed(&hash, identity.configuration_id);
    hash.update(&identity.binary_sha256);
    hash.update(&identity.configuration_sha256);
    return finishDigest(&hash);
}

pub fn principalBinding(stable_id: []const u8) Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.production-storage-approval-principal.v1");
    updateLengthPrefixed(&hash, stable_id);
    return finishDigest(&hash);
}

pub fn qualificationBinding(evidence: QualificationEvidence) Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.production-storage-qualification-binding.v1");
    updateU16(&hash, evidence.schema_version);
    hash.update(&.{@intFromEnum(evidence.authority_claim)});
    updateI64(&hash, evidence.recorded_at_unix_seconds);
    updateI64(&hash, evidence.expires_at_unix_seconds);
    hash.update(&.{@intFromBool(evidence.revoked)});
    hash.update(&evidence.reviewed_source_inventory_sha256);
    for (requirements.required_windows_architectures) |architecture| {
        if (findArchitectureArtifact(
            evidence.architecture_artifacts,
            architecture,
        )) |artifact| {
            hash.update(&artifact.binding_sha256);
        } else {
            const zero_digest = std.mem.zeroes(Digest);
            hash.update(&zero_digest);
        }
    }
    hash.update(&evidence.architecture_component_set_binding_sha256);
    return finishDigest(&hash);
}

pub fn qualificationResultDigest(
    result: QualificationScenarioResult,
) Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.production-storage-scenario-result.v1");
    hash.update(&.{@intFromEnum(result.architecture)});
    hash.update(&.{@intFromEnum(result.id)});
    hash.update(&.{@intFromEnum(result.result)});
    hash.update(&result.qualification_binding_sha256);
    hash.update(&result.architecture_artifact_binding_sha256);
    hash.update(&result.architecture_component_binding_sha256);
    hash.update(&result.provider_identity_binding_sha256);
    hash.update(&result.backend_identity_binding_sha256);
    return finishDigest(&hash);
}

pub fn keyPurposeSeparationResultDigest(
    result: KeyPurposeSeparationResult,
) Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.production-storage-key-purpose-separation.v1");
    hash.update(&.{@intFromEnum(result.architecture)});
    hash.update(&.{@intFromEnum(result.compared_domain)});
    hash.update(&.{@intFromEnum(result.material_distinct)});
    hash.update(&.{@intFromEnum(result.non_derived)});
    hash.update(&.{@intFromEnum(result.handle_not_reused)});
    hash.update(&result.qualification_binding_sha256);
    hash.update(&result.architecture_artifact_binding_sha256);
    hash.update(&result.architecture_component_binding_sha256);
    hash.update(&result.separation_attestation_sha256);
    return finishDigest(&hash);
}

pub fn decisionApprovalDigest(approval: DecisionApproval) Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.production-storage-decision-approval.v1");
    hash.update(&.{@intFromEnum(approval.id)});
    hash.update(&.{@intFromEnum(approval.result)});
    updateLengthPrefixed(&hash, approval.owner.stable_id);
    hash.update(&approval.owner.binding_sha256);
    updateLengthPrefixed(&hash, approval.reviewer.stable_id);
    hash.update(&approval.reviewer.binding_sha256);
    updateI64(&hash, approval.approved_at_unix_seconds);
    updateI64(&hash, approval.expires_at_unix_seconds);
    hash.update(&.{@intFromBool(approval.revoked)});
    hash.update(&approval.qualification_binding_sha256);
    hash.update(&approval.architecture_component_set_binding_sha256);
    hash.update(&approval.approval_attestation_sha256);
    return finishDigest(&hash);
}

/// Canonical top-level binding over the complete nested result and approval
/// set. Individual scenario and decision records are also independently bound
/// to the release identity, so they can be verified before this conjunction.
pub fn canonicalEvidenceDigest(evidence: QualificationEvidence) Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.production-storage-canonical-evidence.v1");
    hash.update(&evidence.qualification_binding_sha256);

    updateU64(&hash, @intCast(evidence.protected_surfaces.len));
    for (requirements.required_protected_artifact_surfaces) |required_id| {
        var found: ?ProtectedSurfaceResult = null;
        for (evidence.protected_surfaces) |record| {
            if (record.id == required_id) {
                found = record;
                break;
            }
        }
        hash.update(&.{@intFromEnum(required_id)});
        hash.update(&.{if (found) |record|
            @intFromEnum(record.result)
        else
            0xff});
    }

    updateU64(&hash, @intCast(evidence.backend_requirements.len));
    for (requirements.required_authenticated_backend_requirements) |required_id| {
        var found: ?BackendRequirementResult = null;
        for (evidence.backend_requirements) |record| {
            if (record.id == required_id) {
                found = record;
                break;
            }
        }
        hash.update(&.{@intFromEnum(required_id)});
        hash.update(&.{if (found) |record|
            @intFromEnum(record.result)
        else
            0xff});
    }

    updateU64(&hash, @intCast(evidence.custody_failures.len));
    for (requirements.required_custody_fail_closed_conditions) |required_id| {
        var found: ?CustodyFailureResult = null;
        for (evidence.custody_failures) |record| {
            if (record.id == required_id) {
                found = record;
                break;
            }
        }
        hash.update(&.{@intFromEnum(required_id)});
        hash.update(&.{if (found) |record|
            @intFromEnum(record.result)
        else
            0xff});
    }

    updateU64(&hash, @intCast(evidence.recovery_scenarios.len));
    for (requirements.required_recovery_scenarios) |required_id| {
        var found: ?RecoveryScenarioResult = null;
        for (evidence.recovery_scenarios) |record| {
            if (record.id == required_id) {
                found = record;
                break;
            }
        }
        hash.update(&.{@intFromEnum(required_id)});
        hash.update(&.{if (found) |record|
            @intFromEnum(record.result)
        else
            0xff});
    }

    updateU64(&hash, @intCast(evidence.repository_artifact_states.len));
    for (requirements.required_repository_artifact_states) |required_id| {
        var found: ?RepositoryArtifactStateResult = null;
        for (evidence.repository_artifact_states) |record| {
            if (record.id == required_id) {
                found = record;
                break;
            }
        }
        hash.update(&.{@intFromEnum(required_id)});
        hash.update(&.{if (found) |record|
            @intFromEnum(record.result)
        else
            0xff});
    }

    updateU64(&hash, @intCast(evidence.qualification_results.len));
    for (requirements.required_windows_architectures) |architecture| {
        for (requirements.required_qualification_scenarios) |scenario| {
            if (!qualificationScenarioAppliesToArchitecture(
                scenario,
                architecture,
            )) continue;
            var found: ?QualificationScenarioResult = null;
            for (evidence.qualification_results) |record| {
                if (record.architecture == architecture and
                    record.id == scenario)
                {
                    found = record;
                    break;
                }
            }
            hash.update(&.{@intFromEnum(architecture)});
            hash.update(&.{@intFromEnum(scenario)});
            if (found) |record| {
                hash.update(&record.result_record_sha256);
            } else {
                const zero_digest = std.mem.zeroes(Digest);
                hash.update(&zero_digest);
            }
        }
    }

    updateU64(
        &hash,
        @intCast(evidence.key_purpose_separation_results.len),
    );
    for (requirements.required_windows_architectures) |architecture| {
        for (
            requirements.required_database_key_separation_domains,
        ) |domain| {
            var found: ?KeyPurposeSeparationResult = null;
            for (evidence.key_purpose_separation_results) |record| {
                if (record.architecture == architecture and
                    record.compared_domain == domain)
                {
                    found = record;
                    break;
                }
            }
            hash.update(&.{@intFromEnum(architecture)});
            hash.update(&.{@intFromEnum(domain)});
            if (found) |record| {
                hash.update(&record.result_record_sha256);
            } else {
                const zero_digest = std.mem.zeroes(Digest);
                hash.update(&zero_digest);
            }
        }
    }

    updateU64(&hash, @intCast(evidence.decision_approvals.len));
    for (requirements.outstanding_external_decisions) |required_id| {
        var found: ?DecisionApproval = null;
        for (evidence.decision_approvals) |record| {
            if (record.id == required_id) {
                found = record;
                break;
            }
        }
        hash.update(&.{@intFromEnum(required_id)});
        if (found) |record| {
            hash.update(&record.approval_record_sha256);
        } else {
            const zero_digest = std.mem.zeroes(Digest);
            hash.update(&zero_digest);
        }
    }
    return finishDigest(&hash);
}

pub fn validate(
    evidence: QualificationEvidence,
    now_unix_seconds: i64,
) ValidationVerdict {
    var counts = initialCounts(evidence);

    if (evidence.schema_version != current_schema_version) {
        return rejected(counts, .unsupported_schema);
    }
    if (evidence.authority_claim != .observational_unselected) {
        return rejected(counts, .evidence_attempted_self_selection);
    }
    counts.gates_passed += 1;

    if (now_unix_seconds <= 0) {
        return rejected(counts, .invalid_validation_time);
    }
    if (evidence.revoked) {
        return rejected(counts, .evidence_revoked);
    }
    if (evidence.recorded_at_unix_seconds <= 0 or
        evidence.expires_at_unix_seconds <=
            evidence.recorded_at_unix_seconds or
        evidence.recorded_at_unix_seconds > now_unix_seconds)
    {
        return rejected(counts, .invalid_evidence_time_window);
    }
    if (now_unix_seconds >= evidence.expires_at_unix_seconds) {
        return rejected(counts, .evidence_expired);
    }
    counts.gates_passed += 1;

    if (!digestIsNonzero(evidence.reviewed_source_inventory_sha256)) {
        return rejected(counts, .zero_reviewed_source_inventory_digest);
    }
    if (validateArchitectureArtifacts(evidence.architecture_artifacts)) |failure| {
        return rejected(counts, failure);
    }
    counts.records_validated += evidence.architecture_artifacts.len;
    counts.gates_passed += 1;

    if (validateArchitectureComponents(
        evidence.architecture_components,
    )) |failure| {
        return rejected(counts, failure);
    }
    if (!digestIsNonzero(
        evidence.architecture_component_set_binding_sha256,
    )) {
        return rejected(
            counts,
            .zero_architecture_component_set_binding_digest,
        );
    }
    if (!digestEql(
        evidence.architecture_component_set_binding_sha256,
        architectureComponentSetBinding(evidence.architecture_components),
    )) {
        return rejected(counts, .architecture_component_set_binding_mismatch);
    }
    if (!digestIsNonzero(evidence.qualification_binding_sha256)) {
        return rejected(counts, .zero_qualification_binding_digest);
    }
    if (!digestEql(
        evidence.qualification_binding_sha256,
        qualificationBinding(evidence),
    )) {
        return rejected(counts, .qualification_binding_mismatch);
    }
    counts.records_validated += evidence.architecture_components.len;
    counts.gates_passed += 1;

    switch (exactCoverage(
        requirements.ProtectedArtifactSurface,
        evidence.protected_surfaces,
        &requirements.required_protected_artifact_surfaces,
    )) {
        .exact => {
            counts.records_validated += evidence.protected_surfaces.len;
            counts.gates_passed += 1;
        },
        .duplicate => return rejected(counts, .duplicate_protected_surface),
        .missing => return rejected(counts, .missing_protected_surface),
        .failed => return rejected(counts, .failed_protected_surface),
    }

    switch (exactCoverage(
        requirements.AuthenticatedBackendRequirement,
        evidence.backend_requirements,
        &requirements.required_authenticated_backend_requirements,
    )) {
        .exact => {
            counts.records_validated += evidence.backend_requirements.len;
            counts.gates_passed += 1;
        },
        .duplicate => return rejected(counts, .duplicate_backend_requirement),
        .missing => return rejected(counts, .missing_backend_requirement),
        .failed => return rejected(counts, .failed_backend_requirement),
    }

    switch (exactCoverage(
        requirements.CustodyFailClosedCondition,
        evidence.custody_failures,
        &requirements.required_custody_fail_closed_conditions,
    )) {
        .exact => {
            counts.records_validated += evidence.custody_failures.len;
            counts.gates_passed += 1;
        },
        .duplicate => return rejected(counts, .duplicate_custody_failure),
        .missing => return rejected(counts, .missing_custody_failure),
        .failed => return rejected(counts, .failed_custody_failure),
    }

    switch (exactCoverage(
        requirements.RecoveryScenario,
        evidence.recovery_scenarios,
        &requirements.required_recovery_scenarios,
    )) {
        .exact => {
            counts.records_validated += evidence.recovery_scenarios.len;
            counts.gates_passed += 1;
        },
        .duplicate => return rejected(counts, .duplicate_recovery_scenario),
        .missing => return rejected(counts, .missing_recovery_scenario),
        .failed => return rejected(counts, .failed_recovery_scenario),
    }

    switch (exactCoverage(
        requirements.RepositoryArtifactState,
        evidence.repository_artifact_states,
        &requirements.required_repository_artifact_states,
    )) {
        .exact => {
            counts.records_validated += evidence.repository_artifact_states.len;
            counts.gates_passed += 1;
        },
        .duplicate => {
            return rejected(counts, .duplicate_repository_artifact_state);
        },
        .missing => return rejected(counts, .missing_repository_artifact_state),
        .failed => return rejected(counts, .failed_repository_artifact_state),
    }

    if (validateQualificationResults(evidence)) |failure| {
        return rejected(counts, failure);
    }
    counts.records_validated += evidence.qualification_results.len;
    counts.gates_passed += 1;

    if (validateKeyPurposeSeparationResults(evidence)) |failure| {
        return rejected(counts, failure);
    }
    counts.records_validated += evidence.key_purpose_separation_results.len;
    counts.gates_passed += 1;

    if (validateDecisionApprovals(evidence, now_unix_seconds)) |failure| {
        return rejected(counts, failure);
    }
    counts.records_validated += evidence.decision_approvals.len;
    counts.gates_passed += 1;

    if (!digestIsNonzero(evidence.canonical_evidence_sha256)) {
        return rejected(counts, .zero_canonical_evidence_digest);
    }
    if (!digestEql(
        evidence.canonical_evidence_sha256,
        canonicalEvidenceDigest(evidence),
    )) {
        return rejected(counts, .canonical_evidence_digest_mismatch);
    }
    counts.gates_passed += 1;

    const all_gates = counts.gates_passed == counts.gates_required and
        counts.records_presented == counts.records_required and
        counts.records_validated == counts.records_required;
    if (!all_gates) {
        return rejected(counts, .missing_qualification_architecture_pair);
    }
    return .{
        .status = .structurally_complete_observational_only,
        .failure = .none,
        .counts = counts,
        .all_required_evidence_gates_passed = true,
        .effective_source_selection = .unavailable_unselected,
        .production_authorized = false,
    };
}

const Coverage = enum {
    exact,
    duplicate,
    missing,
    failed,
};

fn exactCoverage(
    comptime Enum: type,
    records: anytype,
    required: []const Enum,
) Coverage {
    for (records) |record| {
        if (record.result != .passed) return .failed;
    }
    for (required) |required_id| {
        var count: usize = 0;
        for (records) |record| {
            if (record.id == required_id) count += 1;
        }
        if (count > 1) return .duplicate;
    }
    for (required) |required_id| {
        var found = false;
        for (records) |record| {
            if (record.id == required_id) {
                found = true;
                break;
            }
        }
        if (!found) return .missing;
    }
    return .exact;
}

fn validateArchitectureArtifacts(
    artifacts: []const ArchitectureArtifactIdentity,
) ?ValidationFailure {
    for (requirements.required_windows_architectures) |architecture| {
        var count: usize = 0;
        for (artifacts) |artifact| {
            if (artifact.architecture == architecture) count += 1;
        }
        if (count > 1) return .duplicate_architecture_artifact;
    }
    for (requirements.required_windows_architectures) |architecture| {
        if (findArchitectureArtifact(artifacts, architecture) == null) {
            return .missing_architecture_artifact;
        }
    }

    for (artifacts) |artifact| {
        if (!std.mem.eql(
            u8,
            artifact.target_triple,
            expectedTargetTriple(artifact.architecture),
        ) or artifact.pe_machine != expectedPeMachine(artifact.architecture)) {
            return .invalid_architecture_target_binding;
        }
        if (!validStableText(artifact.os_build_id)) {
            return .invalid_architecture_os_build_identity;
        }
        if (!validStableText(artifact.conformance_harness_version)) {
            return .invalid_architecture_conformance_harness_version;
        }
        if (!digestIsNonzero(artifact.executable_sha256)) {
            return .zero_architecture_executable_digest;
        }
        if (!digestIsNonzero(artifact.package_inventory_sha256)) {
            return .zero_architecture_package_inventory_digest;
        }
        if (!digestIsNonzero(artifact.package_manifest_sha256)) {
            return .zero_architecture_package_manifest_digest;
        }
        if (!digestIsNonzero(artifact.toolchain_sha256)) {
            return .zero_architecture_toolchain_digest;
        }
        if (!digestIsNonzero(artifact.conformance_harness_sha256)) {
            return .zero_architecture_conformance_harness_digest;
        }
        if (!digestEql(
            artifact.binding_sha256,
            architectureArtifactBinding(artifact),
        )) {
            return .architecture_artifact_binding_mismatch;
        }
    }

    const x86 = findArchitectureArtifact(artifacts, .x86_64).?;
    const arm = findArchitectureArtifact(artifacts, .aarch64).?;
    if (digestEql(x86.executable_sha256, arm.executable_sha256)) {
        return .architecture_executable_digest_not_distinct;
    }
    return null;
}

fn validateArchitectureComponents(
    identities: []const ArchitectureComponentIdentity,
) ?ValidationFailure {
    for (requirements.required_windows_architectures) |architecture| {
        var count: usize = 0;
        for (identities) |identity| {
            if (identity.architecture == architecture) count += 1;
        }
        if (count > 1) return .duplicate_architecture_component_identity;
    }
    for (requirements.required_windows_architectures) |architecture| {
        if (findArchitectureComponent(identities, architecture) == null) {
            return .missing_architecture_component_identity;
        }
    }

    for (identities) |identity| {
        if (!validStableIdentity(identity.provider)) {
            return .invalid_provider_identity;
        }
        if (!validStableIdentity(identity.backend)) {
            return .invalid_backend_identity;
        }
        if (!digestIsNonzero(identity.provider.binary_sha256)) {
            return .zero_provider_binary_digest;
        }
        if (!digestIsNonzero(identity.provider.configuration_sha256)) {
            return .zero_provider_configuration_digest;
        }
        if (!digestIsNonzero(identity.backend.binary_sha256)) {
            return .zero_backend_binary_digest;
        }
        if (!digestIsNonzero(identity.backend.configuration_sha256)) {
            return .zero_backend_configuration_digest;
        }
        if (!digestEql(
            identity.provider.binding_sha256,
            componentIdentityBinding(.custody_provider, identity.provider),
        )) {
            return .provider_identity_binding_mismatch;
        }
        if (!digestEql(
            identity.backend.binding_sha256,
            componentIdentityBinding(
                .authenticated_storage_backend,
                identity.backend,
            ),
        )) {
            return .backend_identity_binding_mismatch;
        }

        // ComponentKind domain separation makes role bindings unequal even
        // when the underlying implementation is reused. Compare the actual
        // product and binary/configuration identities instead.
        if (std.mem.eql(
            u8,
            identity.provider.stable_id,
            identity.backend.stable_id,
        ) or std.mem.eql(
            u8,
            identity.provider.configuration_id,
            identity.backend.configuration_id,
        ) or digestEql(
            identity.provider.binary_sha256,
            identity.backend.binary_sha256,
        ) or digestEql(
            identity.provider.configuration_sha256,
            identity.backend.configuration_sha256,
        )) {
            return .provider_backend_identity_not_distinct;
        }
        if (!digestEql(
            identity.binding_sha256,
            architectureComponentBinding(identity),
        )) {
            return .architecture_component_binding_mismatch;
        }
    }

    const x86 = findArchitectureComponent(identities, .x86_64).?;
    const arm = findArchitectureComponent(identities, .aarch64).?;
    if (!sameProductConfiguration(x86.provider, arm.provider)) {
        return .provider_product_identity_inconsistent_across_architectures;
    }
    if (!sameProductConfiguration(x86.backend, arm.backend)) {
        return .backend_product_identity_inconsistent_across_architectures;
    }
    if (digestEql(
        x86.provider.binary_sha256,
        arm.provider.binary_sha256,
    )) {
        return .provider_binary_digest_not_distinct;
    }
    if (digestEql(
        x86.backend.binary_sha256,
        arm.backend.binary_sha256,
    )) {
        return .backend_binary_digest_not_distinct;
    }
    return null;
}

fn findArchitectureArtifact(
    artifacts: []const ArchitectureArtifactIdentity,
    architecture: requirements.WindowsArchitecture,
) ?ArchitectureArtifactIdentity {
    for (artifacts) |artifact| {
        if (artifact.architecture == architecture) return artifact;
    }
    return null;
}

fn findArchitectureComponent(
    identities: []const ArchitectureComponentIdentity,
    architecture: requirements.WindowsArchitecture,
) ?ArchitectureComponentIdentity {
    for (identities) |identity| {
        if (identity.architecture == architecture) return identity;
    }
    return null;
}

fn sameProductConfiguration(
    left: ComponentIdentity,
    right: ComponentIdentity,
) bool {
    return std.mem.eql(u8, left.stable_id, right.stable_id) and
        std.mem.eql(u8, left.version, right.version) and
        std.mem.eql(
            u8,
            left.configuration_id,
            right.configuration_id,
        ) and
        digestEql(
            left.configuration_sha256,
            right.configuration_sha256,
        );
}

fn validateQualificationResults(
    evidence: QualificationEvidence,
) ?ValidationFailure {
    for (evidence.qualification_results) |result| {
        if (!qualificationScenarioAppliesToArchitecture(
            result.id,
            result.architecture,
        )) {
            return .unexpected_qualification_architecture_pair;
        }
        if (result.result != .passed) {
            return .failed_qualification_scenario;
        }
        const artifact = findArchitectureArtifact(
            evidence.architecture_artifacts,
            result.architecture,
        ) orelse return .missing_architecture_artifact;
        if (!digestEql(
            result.architecture_artifact_binding_sha256,
            artifact.binding_sha256,
        )) {
            return .qualification_architecture_artifact_binding_mismatch;
        }
        const components = findArchitectureComponent(
            evidence.architecture_components,
            result.architecture,
        ) orelse return .missing_architecture_component_identity;
        if (!digestEql(
            result.architecture_component_binding_sha256,
            components.binding_sha256,
        )) {
            return .qualification_architecture_component_binding_mismatch;
        }
        if (!digestEql(
            result.qualification_binding_sha256,
            evidence.qualification_binding_sha256,
        ) or !digestEql(
            result.provider_identity_binding_sha256,
            components.provider.binding_sha256,
        ) or !digestEql(
            result.backend_identity_binding_sha256,
            components.backend.binding_sha256,
        )) {
            return .qualification_identity_binding_mismatch;
        }
        if (!digestEql(
            result.result_record_sha256,
            qualificationResultDigest(result),
        )) {
            return .qualification_result_digest_mismatch;
        }
    }

    for (requirements.required_windows_architectures) |architecture| {
        for (requirements.required_qualification_scenarios) |scenario| {
            if (!qualificationScenarioAppliesToArchitecture(
                scenario,
                architecture,
            )) continue;
            var count: usize = 0;
            for (evidence.qualification_results) |result| {
                if (result.architecture == architecture and
                    result.id == scenario)
                {
                    count += 1;
                }
            }
            if (count > 1) {
                return .duplicate_qualification_architecture_pair;
            }
            if (count == 0) {
                return .missing_qualification_architecture_pair;
            }
        }
    }
    return null;
}

fn validateKeyPurposeSeparationResults(
    evidence: QualificationEvidence,
) ?ValidationFailure {
    for (evidence.key_purpose_separation_results) |result| {
        if (!isRequiredKeyPurposeSeparationDomain(result.compared_domain)) {
            return .unexpected_key_purpose_separation_domain;
        }
        if (result.material_distinct != .passed) {
            return .failed_key_material_distinction;
        }
        if (result.non_derived != .passed) {
            return .failed_key_non_derivation;
        }
        if (result.handle_not_reused != .passed) {
            return .failed_key_handle_non_reuse;
        }

        const artifact = findArchitectureArtifact(
            evidence.architecture_artifacts,
            result.architecture,
        ) orelse return .missing_architecture_artifact;
        const components = findArchitectureComponent(
            evidence.architecture_components,
            result.architecture,
        ) orelse return .missing_architecture_component_identity;
        if (!digestEql(
            result.qualification_binding_sha256,
            evidence.qualification_binding_sha256,
        ) or !digestEql(
            result.architecture_artifact_binding_sha256,
            artifact.binding_sha256,
        ) or !digestEql(
            result.architecture_component_binding_sha256,
            components.binding_sha256,
        )) {
            return .key_purpose_architecture_binding_mismatch;
        }
        if (!digestIsNonzero(result.separation_attestation_sha256)) {
            return .zero_key_purpose_separation_attestation_digest;
        }
        if (!digestEql(
            result.result_record_sha256,
            keyPurposeSeparationResultDigest(result),
        )) {
            return .key_purpose_separation_result_digest_mismatch;
        }
    }

    for (requirements.required_windows_architectures) |architecture| {
        for (
            requirements.required_database_key_separation_domains,
        ) |domain| {
            var count: usize = 0;
            for (evidence.key_purpose_separation_results) |result| {
                if (result.architecture == architecture and
                    result.compared_domain == domain)
                {
                    count += 1;
                }
            }
            if (count > 1) return .duplicate_key_purpose_separation_pair;
            if (count == 0) return .missing_key_purpose_separation_pair;
        }
    }
    return null;
}

fn isRequiredKeyPurposeSeparationDomain(
    domain: requirements.KeyPurposeDomain,
) bool {
    for (
        requirements.required_database_key_separation_domains,
    ) |required_domain| {
        if (domain == required_domain) return true;
    }
    return false;
}

fn validateDecisionApprovals(
    evidence: QualificationEvidence,
    now_unix_seconds: i64,
) ?ValidationFailure {
    for (evidence.decision_approvals) |approval| {
        if (approval.result != .approved) return .decision_not_approved;
        if (!validPrincipal(approval.owner)) {
            return .invalid_decision_owner;
        }
        if (!validPrincipal(approval.reviewer)) {
            return .invalid_decision_reviewer;
        }
        if (std.mem.eql(
            u8,
            approval.owner.stable_id,
            approval.reviewer.stable_id,
        ) or digestEql(
            approval.owner.binding_sha256,
            approval.reviewer.binding_sha256,
        )) {
            return .decision_owner_reviewer_not_distinct;
        }
        if (approval.revoked) return .decision_revoked;
        if (approval.approved_at_unix_seconds <= 0 or
            approval.approved_at_unix_seconds >
                evidence.recorded_at_unix_seconds or
            approval.expires_at_unix_seconds <=
                approval.approved_at_unix_seconds)
        {
            return .invalid_decision_time_window;
        }
        if (now_unix_seconds >= approval.expires_at_unix_seconds) {
            return .decision_expired;
        }
        if (!digestEql(
            approval.qualification_binding_sha256,
            evidence.qualification_binding_sha256,
        ) or !digestEql(
            approval.architecture_component_set_binding_sha256,
            evidence.architecture_component_set_binding_sha256,
        )) {
            return .decision_identity_binding_mismatch;
        }
        if (!digestIsNonzero(approval.approval_attestation_sha256)) {
            return .zero_decision_attestation_digest;
        }
        if (!digestEql(
            approval.approval_record_sha256,
            decisionApprovalDigest(approval),
        )) {
            return .decision_record_digest_mismatch;
        }
    }

    for (requirements.outstanding_external_decisions) |decision| {
        var count: usize = 0;
        for (evidence.decision_approvals) |approval| {
            if (approval.id == decision) count += 1;
        }
        if (count > 1) return .duplicate_external_decision;
    }
    for (requirements.outstanding_external_decisions) |decision| {
        var found = false;
        for (evidence.decision_approvals) |approval| {
            if (approval.id == decision) {
                found = true;
                break;
            }
        }
        if (!found) return .missing_external_decision;
    }
    return null;
}

fn initialCounts(evidence: QualificationEvidence) VerdictCounts {
    return .{
        .gates_required = std.meta.fields(EvidenceGate).len,
        .gates_passed = 0,
        .records_required = requirements.required_windows_architectures.len +
            requirements.required_windows_architectures.len +
            requirements.required_protected_artifact_surfaces.len +
            requirements.required_authenticated_backend_requirements.len +
            requirements.required_custody_fail_closed_conditions.len +
            requirements.required_recovery_scenarios.len +
            requirements.required_repository_artifact_states.len +
            required_qualification_result_count +
            required_key_purpose_separation_result_count +
            requirements.outstanding_external_decisions.len,
        .records_presented = evidence.architecture_artifacts.len +
            evidence.architecture_components.len +
            evidence.protected_surfaces.len +
            evidence.backend_requirements.len +
            evidence.custody_failures.len +
            evidence.recovery_scenarios.len +
            evidence.repository_artifact_states.len +
            evidence.qualification_results.len +
            evidence.key_purpose_separation_results.len +
            evidence.decision_approvals.len,
        .records_validated = 0,
    };
}

fn rejected(
    counts: VerdictCounts,
    failure: ValidationFailure,
) ValidationVerdict {
    return .{
        .status = .rejected,
        .failure = failure,
        .counts = counts,
        .all_required_evidence_gates_passed = false,
        .effective_source_selection = .unavailable_unselected,
        .production_authorized = false,
    };
}

fn validStableIdentity(identity: ComponentIdentity) bool {
    return validStableText(identity.stable_id) and
        validStableText(identity.version) and
        validStableText(identity.configuration_id);
}

fn validPrincipal(principal: PrincipalBinding) bool {
    return validStableText(principal.stable_id) and
        digestEql(
            principal.binding_sha256,
            principalBinding(principal.stable_id),
        );
}

fn validStableText(value: []const u8) bool {
    if (value.len == 0 or value.len > 256) return false;
    for (value) |byte| {
        if (byte < 0x21 or byte > 0x7e) return false;
    }
    return true;
}

fn digestIsNonzero(digest: Digest) bool {
    for (digest) |byte| {
        if (byte != 0) return true;
    }
    return false;
}

fn digestEql(left: Digest, right: Digest) bool {
    return std.mem.eql(u8, &left, &right);
}

fn finishDigest(hash: *std.crypto.hash.sha2.Sha256) Digest {
    var result: Digest = undefined;
    hash.final(&result);
    return result;
}

fn updateLengthPrefixed(
    hash: *std.crypto.hash.sha2.Sha256,
    bytes: []const u8,
) void {
    updateU64(hash, @intCast(bytes.len));
    hash.update(bytes);
}

fn updateU16(
    hash: *std.crypto.hash.sha2.Sha256,
    value: u16,
) void {
    hash.update(&.{
        @intCast(value >> 8),
        @intCast(value & 0xff),
    });
}

fn updateI64(
    hash: *std.crypto.hash.sha2.Sha256,
    value: i64,
) void {
    updateU64(hash, @bitCast(value));
}

fn updateU64(
    hash: *std.crypto.hash.sha2.Sha256,
    value: u64,
) void {
    hash.update(&.{
        @intCast(value >> 56),
        @intCast((value >> 48) & 0xff),
        @intCast((value >> 40) & 0xff),
        @intCast((value >> 32) & 0xff),
        @intCast((value >> 24) & 0xff),
        @intCast((value >> 16) & 0xff),
        @intCast((value >> 8) & 0xff),
        @intCast(value & 0xff),
    });
}

const fixture_now: i64 = 2_000_000;

const CompleteFixture = struct {
    const Self = @This();

    reviewed_source_inventory_sha256: Digest,
    architecture_artifacts: [requirements.required_windows_architectures.len]ArchitectureArtifactIdentity,
    architecture_components: [requirements.required_windows_architectures.len]ArchitectureComponentIdentity,
    architecture_component_set_binding_sha256: Digest,
    qualification_binding_sha256: Digest,
    canonical_evidence_sha256: Digest,
    protected_surfaces: [requirements.required_protected_artifact_surfaces.len]ProtectedSurfaceResult,
    backend_requirements: [requirements.required_authenticated_backend_requirements.len]BackendRequirementResult,
    custody_failures: [requirements.required_custody_fail_closed_conditions.len]CustodyFailureResult,
    recovery_scenarios: [requirements.required_recovery_scenarios.len]RecoveryScenarioResult,
    repository_artifact_states: [requirements.required_repository_artifact_states.len]RepositoryArtifactStateResult,
    qualification_results: [required_qualification_result_count]QualificationScenarioResult,
    key_purpose_separation_results: [required_key_purpose_separation_result_count]KeyPurposeSeparationResult,
    decision_approvals: [requirements.outstanding_external_decisions.len]DecisionApproval,

    fn init() Self {
        var fixture: Self = undefined;
        fixture.reviewed_source_inventory_sha256 = repeatedDigest(0x12);
        for (
            &fixture.architecture_artifacts,
            requirements.required_windows_architectures,
            0..,
        ) |*artifact, architecture, index| {
            artifact.* = fixtureArchitectureArtifact(
                architecture,
                @intCast(0x50 + index * 6),
            );
        }
        for (
            &fixture.architecture_components,
            requirements.required_windows_architectures,
            0..,
        ) |*identity, architecture, index| {
            identity.* = fixtureArchitectureComponents(
                architecture,
                @intCast(index),
            );
        }
        fixture.architecture_component_set_binding_sha256 =
            architectureComponentSetBinding(&fixture.architecture_components);

        for (
            &fixture.protected_surfaces,
            requirements.required_protected_artifact_surfaces,
        ) |*record, id| {
            record.* = .{ .id = id, .result = .passed };
        }
        for (
            &fixture.backend_requirements,
            requirements.required_authenticated_backend_requirements,
        ) |*record, id| {
            record.* = .{ .id = id, .result = .passed };
        }
        for (
            &fixture.custody_failures,
            requirements.required_custody_fail_closed_conditions,
        ) |*record, id| {
            record.* = .{ .id = id, .result = .passed };
        }
        for (
            &fixture.recovery_scenarios,
            requirements.required_recovery_scenarios,
        ) |*record, id| {
            record.* = .{ .id = id, .result = .passed };
        }
        for (
            &fixture.repository_artifact_states,
            requirements.required_repository_artifact_states,
        ) |*record, id| {
            record.* = .{ .id = id, .result = .passed };
        }

        fixture.qualification_binding_sha256 = qualificationBinding(
            fixture.evidenceBeforeDependentRecords(),
        );

        var result_index: usize = 0;
        for (
            requirements.required_windows_architectures,
        ) |architecture| {
            for (
                requirements.required_qualification_scenarios,
            ) |scenario| {
                if (!qualificationScenarioAppliesToArchitecture(
                    scenario,
                    architecture,
                )) continue;
                var result: QualificationScenarioResult = .{
                    .architecture = architecture,
                    .id = scenario,
                    .result = .passed,
                    .qualification_binding_sha256 = fixture.qualification_binding_sha256,
                    .architecture_artifact_binding_sha256 = findArchitectureArtifact(
                        &fixture.architecture_artifacts,
                        architecture,
                    ).?.binding_sha256,
                    .architecture_component_binding_sha256 = findArchitectureComponent(
                        &fixture.architecture_components,
                        architecture,
                    ).?.binding_sha256,
                    .provider_identity_binding_sha256 = findArchitectureComponent(
                        &fixture.architecture_components,
                        architecture,
                    ).?.provider.binding_sha256,
                    .backend_identity_binding_sha256 = findArchitectureComponent(
                        &fixture.architecture_components,
                        architecture,
                    ).?.backend.binding_sha256,
                    .result_record_sha256 = undefined,
                };
                result.result_record_sha256 =
                    qualificationResultDigest(result);
                fixture.qualification_results[result_index] = result;
                result_index += 1;
            }
        }
        std.debug.assert(result_index == required_qualification_result_count);

        var separation_index: usize = 0;
        for (
            requirements.required_windows_architectures,
        ) |architecture| {
            for (
                requirements.required_database_key_separation_domains,
            ) |domain| {
                var result: KeyPurposeSeparationResult = .{
                    .architecture = architecture,
                    .compared_domain = domain,
                    .material_distinct = .passed,
                    .non_derived = .passed,
                    .handle_not_reused = .passed,
                    .qualification_binding_sha256 = fixture.qualification_binding_sha256,
                    .architecture_artifact_binding_sha256 = findArchitectureArtifact(
                        &fixture.architecture_artifacts,
                        architecture,
                    ).?.binding_sha256,
                    .architecture_component_binding_sha256 = findArchitectureComponent(
                        &fixture.architecture_components,
                        architecture,
                    ).?.binding_sha256,
                    .separation_attestation_sha256 = repeatedDigest(
                        @intCast(0x70 + separation_index),
                    ),
                    .result_record_sha256 = undefined,
                };
                result.result_record_sha256 =
                    keyPurposeSeparationResultDigest(result);
                fixture.key_purpose_separation_results[separation_index] =
                    result;
                separation_index += 1;
            }
        }
        std.debug.assert(
            separation_index == required_key_purpose_separation_result_count,
        );

        const owner = fixturePrincipal("fixture.product-owner");
        const reviewer = fixturePrincipal("fixture.security-reviewer");
        for (
            &fixture.decision_approvals,
            requirements.outstanding_external_decisions,
            0..,
        ) |*record, id, index| {
            var approval: DecisionApproval = .{
                .id = id,
                .result = .approved,
                .owner = owner,
                .reviewer = reviewer,
                .approved_at_unix_seconds = fixture_now - 100,
                .expires_at_unix_seconds = fixture_now + 100,
                .revoked = false,
                .qualification_binding_sha256 = fixture.qualification_binding_sha256,
                .architecture_component_set_binding_sha256 = fixture.architecture_component_set_binding_sha256,
                .approval_attestation_sha256 = repeatedDigest(@intCast(0x40 + index)),
                .approval_record_sha256 = undefined,
            };
            approval.approval_record_sha256 =
                decisionApprovalDigest(approval);
            record.* = approval;
        }
        fixture.canonical_evidence_sha256 = std.mem.zeroes(Digest);
        fixture.canonical_evidence_sha256 =
            canonicalEvidenceDigest(fixture.evidence());
        return fixture;
    }

    fn evidenceBeforeDependentRecords(self: *const Self) QualificationEvidence {
        return .{
            .schema_version = current_schema_version,
            .authority_claim = .observational_unselected,
            .recorded_at_unix_seconds = fixture_now - 50,
            .expires_at_unix_seconds = fixture_now + 50,
            .revoked = false,
            .reviewed_source_inventory_sha256 = self.reviewed_source_inventory_sha256,
            .architecture_artifacts = &self.architecture_artifacts,
            .architecture_components = &self.architecture_components,
            .architecture_component_set_binding_sha256 = self.architecture_component_set_binding_sha256,
            .qualification_binding_sha256 = undefined,
            .canonical_evidence_sha256 = std.mem.zeroes(Digest),
            .protected_surfaces = &.{},
            .backend_requirements = &.{},
            .custody_failures = &.{},
            .recovery_scenarios = &.{},
            .repository_artifact_states = &.{},
            .qualification_results = &.{},
            .key_purpose_separation_results = &.{},
            .decision_approvals = &.{},
        };
    }

    fn evidence(self: *const Self) QualificationEvidence {
        var result = self.evidenceBeforeDependentRecords();
        result.qualification_binding_sha256 =
            self.qualification_binding_sha256;
        result.canonical_evidence_sha256 = self.canonical_evidence_sha256;
        result.protected_surfaces = &self.protected_surfaces;
        result.backend_requirements = &self.backend_requirements;
        result.custody_failures = &self.custody_failures;
        result.recovery_scenarios = &self.recovery_scenarios;
        result.repository_artifact_states = &self.repository_artifact_states;
        result.qualification_results = &self.qualification_results;
        result.key_purpose_separation_results =
            &self.key_purpose_separation_results;
        result.decision_approvals = &self.decision_approvals;
        return result;
    }
};

fn fixtureArchitectureArtifact(
    architecture: requirements.WindowsArchitecture,
    seed: u8,
) ArchitectureArtifactIdentity {
    var result: ArchitectureArtifactIdentity = .{
        .architecture = architecture,
        .target_triple = expectedTargetTriple(architecture),
        .pe_machine = expectedPeMachine(architecture),
        .os_build_id = switch (architecture) {
            .x86_64 => "fixture.windows-build.x86_64",
            .aarch64 => "fixture.windows-build.aarch64",
        },
        .conformance_harness_version = "fixture-harness-v1",
        .executable_sha256 = repeatedDigest(seed),
        .package_inventory_sha256 = repeatedDigest(seed + 1),
        .package_manifest_sha256 = repeatedDigest(seed + 2),
        .toolchain_sha256 = repeatedDigest(seed + 3),
        .conformance_harness_sha256 = repeatedDigest(seed + 4),
        .binding_sha256 = undefined,
    };
    result.binding_sha256 = architectureArtifactBinding(result);
    return result;
}

fn fixtureArchitectureComponents(
    architecture: requirements.WindowsArchitecture,
    architecture_index: u8,
) ArchitectureComponentIdentity {
    var result: ArchitectureComponentIdentity = .{
        .architecture = architecture,
        .provider = fixtureComponent(
            .custody_provider,
            "fixture.custody-provider",
            "0.0.0-fixture",
            "fixture.provider.configuration.v1",
            0x21 + architecture_index,
            0x23,
        ),
        .backend = fixtureComponent(
            .authenticated_storage_backend,
            "fixture.authenticated-backend",
            "0.0.0-fixture",
            "fixture.backend.configuration.v1",
            0x31 + architecture_index,
            0x33,
        ),
        .binding_sha256 = undefined,
    };
    result.binding_sha256 = architectureComponentBinding(result);
    return result;
}

fn refreshArchitectureComponentBindings(
    identity: *ArchitectureComponentIdentity,
) void {
    identity.provider.binding_sha256 =
        componentIdentityBinding(.custody_provider, identity.provider);
    identity.backend.binding_sha256 = componentIdentityBinding(
        .authenticated_storage_backend,
        identity.backend,
    );
    identity.binding_sha256 = architectureComponentBinding(identity.*);
}

fn fixtureComponent(
    kind: ComponentKind,
    stable_id: []const u8,
    version: []const u8,
    configuration_id: []const u8,
    binary_seed: u8,
    configuration_seed: u8,
) ComponentIdentity {
    var result: ComponentIdentity = .{
        .stable_id = stable_id,
        .version = version,
        .configuration_id = configuration_id,
        .binary_sha256 = repeatedDigest(binary_seed),
        .configuration_sha256 = repeatedDigest(configuration_seed),
        .binding_sha256 = undefined,
    };
    result.binding_sha256 = componentIdentityBinding(kind, result);
    return result;
}

fn fixturePrincipal(stable_id: []const u8) PrincipalBinding {
    return .{
        .stable_id = stable_id,
        .binding_sha256 = principalBinding(stable_id),
    };
}

fn repeatedDigest(byte: u8) Digest {
    var result: Digest = undefined;
    @memset(&result, byte);
    return result;
}

fn expectFailure(
    evidence: QualificationEvidence,
    expected: ValidationFailure,
) !void {
    const verdict = validate(evidence, fixture_now);
    try std.testing.expectEqual(ValidationStatus.rejected, verdict.status);
    try std.testing.expectEqual(expected, verdict.failure);
    try std.testing.expect(!verdict.all_required_evidence_gates_passed);
    try std.testing.expect(!verdict.production_authorized);
    try std.testing.expectEqual(
        EffectiveSourceSelection.unavailable_unselected,
        verdict.effective_source_selection,
    );
}

test "complete evidence is exact but remains observational and unavailable" {
    var fixture = CompleteFixture.init();
    const verdict = validate(fixture.evidence(), fixture_now);
    try std.testing.expectEqual(
        ValidationStatus.structurally_complete_observational_only,
        verdict.status,
    );
    try std.testing.expectEqual(ValidationFailure.none, verdict.failure);
    try std.testing.expect(verdict.all_required_evidence_gates_passed);
    try std.testing.expectEqual(
        verdict.counts.gates_required,
        verdict.counts.gates_passed,
    );
    try std.testing.expectEqual(
        verdict.counts.records_required,
        verdict.counts.records_presented,
    );
    try std.testing.expectEqual(
        verdict.counts.records_required,
        verdict.counts.records_validated,
    );
    try std.testing.expect(!verdict.production_authorized);
    try std.testing.expect(!production_authority_minted);

    const key_custody = @import("key_custody.zig");
    try std.testing.expectEqual(
        key_custody.ProductionStorageState
            .unavailable_authenticated_storage_backend_unselected,
        key_custody.current_production_storage_state,
    );
    try std.testing.expectError(
        error.ProductionStorageUnavailable,
        key_custody.requireProductionStorage(),
    );
}

test "exact coverage rejects duplicate and omitted requirement records" {
    var fixture = CompleteFixture.init();
    fixture.protected_surfaces[
        fixture.protected_surfaces.len - 1
    ].id = fixture.protected_surfaces[0].id;
    try expectFailure(
        fixture.evidence(),
        .duplicate_protected_surface,
    );

    fixture = CompleteFixture.init();
    var evidence = fixture.evidence();
    evidence.backend_requirements =
        evidence.backend_requirements[0 .. evidence.backend_requirements.len - 1];
    try expectFailure(evidence, .missing_backend_requirement);

    fixture = CompleteFixture.init();
    fixture.custody_failures[
        fixture.custody_failures.len - 1
    ].id = fixture.custody_failures[0].id;
    try expectFailure(fixture.evidence(), .duplicate_custody_failure);

    fixture = CompleteFixture.init();
    evidence = fixture.evidence();
    evidence.recovery_scenarios =
        evidence.recovery_scenarios[0 .. evidence.recovery_scenarios.len - 1];
    try expectFailure(evidence, .missing_recovery_scenario);

    fixture = CompleteFixture.init();
    fixture.decision_approvals[
        fixture.decision_approvals.len - 1
    ].id = fixture.decision_approvals[0].id;
    fixture.decision_approvals[
        fixture.decision_approvals.len - 1
    ].approval_record_sha256 = decisionApprovalDigest(
        fixture.decision_approvals[fixture.decision_approvals.len - 1],
    );
    try expectFailure(fixture.evidence(), .duplicate_external_decision);
}

test "qualification requires every applicable scenario on both architectures" {
    var fixture = CompleteFixture.init();
    var evidence = fixture.evidence();
    var x86_only_count: usize = 0;
    for (fixture.qualification_results) |result| {
        if (result.architecture == .x86_64) x86_only_count += 1;
    }
    evidence.qualification_results =
        fixture.qualification_results[0..x86_only_count];
    try expectFailure(
        evidence,
        .missing_qualification_architecture_pair,
    );

    fixture = CompleteFixture.init();
    fixture.qualification_results[
        fixture.qualification_results.len - 1
    ] = fixture.qualification_results[0];
    try expectFailure(
        fixture.evidence(),
        .duplicate_qualification_architecture_pair,
    );
}

test "architecture artifacts are exact and reject cross-wiring" {
    var fixture = CompleteFixture.init();
    fixture.architecture_artifacts[1].architecture = .x86_64;
    try expectFailure(fixture.evidence(), .duplicate_architecture_artifact);

    fixture = CompleteFixture.init();
    var evidence = fixture.evidence();
    evidence.architecture_artifacts =
        evidence.architecture_artifacts[0 .. evidence.architecture_artifacts.len - 1];
    try expectFailure(evidence, .missing_architecture_artifact);

    fixture = CompleteFixture.init();
    fixture.architecture_artifacts[0].target_triple =
        expectedTargetTriple(.aarch64);
    try expectFailure(fixture.evidence(), .invalid_architecture_target_binding);

    fixture = CompleteFixture.init();
    fixture.qualification_results[0]
        .architecture_artifact_binding_sha256 =
        fixture.architecture_artifacts[1].binding_sha256;
    try expectFailure(
        fixture.evidence(),
        .qualification_architecture_artifact_binding_mismatch,
    );
}

test "architecture component identities are exact and architecture bound" {
    var fixture = CompleteFixture.init();
    fixture.architecture_components[1].architecture = .x86_64;
    try expectFailure(
        fixture.evidence(),
        .duplicate_architecture_component_identity,
    );

    fixture = CompleteFixture.init();
    var evidence = fixture.evidence();
    evidence.architecture_components =
        evidence.architecture_components[0 .. evidence.architecture_components.len - 1];
    try expectFailure(
        evidence,
        .missing_architecture_component_identity,
    );

    fixture = CompleteFixture.init();
    fixture.qualification_results[0]
        .architecture_component_binding_sha256 =
        fixture.architecture_components[1].binding_sha256;
    try expectFailure(
        fixture.evidence(),
        .qualification_architecture_component_binding_mismatch,
    );

    fixture = CompleteFixture.init();
    fixture.qualification_results[0]
        .provider_identity_binding_sha256 =
        fixture.architecture_components[1].provider.binding_sha256;
    try expectFailure(
        fixture.evidence(),
        .qualification_identity_binding_mismatch,
    );
}

test "architecture component binaries are distinct with stable product configuration" {
    var fixture = CompleteFixture.init();
    fixture.architecture_components[1].provider.binary_sha256 =
        fixture.architecture_components[0].provider.binary_sha256;
    refreshArchitectureComponentBindings(
        &fixture.architecture_components[1],
    );
    try expectFailure(
        fixture.evidence(),
        .provider_binary_digest_not_distinct,
    );

    fixture = CompleteFixture.init();
    fixture.architecture_components[1].backend.binary_sha256 =
        fixture.architecture_components[0].backend.binary_sha256;
    refreshArchitectureComponentBindings(
        &fixture.architecture_components[1],
    );
    try expectFailure(
        fixture.evidence(),
        .backend_binary_digest_not_distinct,
    );

    fixture = CompleteFixture.init();
    fixture.architecture_components[1].provider.version =
        "0.0.1-inconsistent-fixture";
    refreshArchitectureComponentBindings(
        &fixture.architecture_components[1],
    );
    try expectFailure(
        fixture.evidence(),
        .provider_product_identity_inconsistent_across_architectures,
    );

    fixture = CompleteFixture.init();
    fixture.architecture_components[1].backend.configuration_id =
        "fixture.backend.inconsistent-configuration.v1";
    refreshArchitectureComponentBindings(
        &fixture.architecture_components[1],
    );
    try expectFailure(
        fixture.evidence(),
        .backend_product_identity_inconsistent_across_architectures,
    );

    fixture = CompleteFixture.init();
    fixture.architecture_components[0].backend.binary_sha256 =
        fixture.architecture_components[0].provider.binary_sha256;
    refreshArchitectureComponentBindings(
        &fixture.architecture_components[0],
    );
    try expectFailure(
        fixture.evidence(),
        .provider_backend_identity_not_distinct,
    );
}

test "repository artifact state evidence is exact and canonically bound" {
    var fixture = CompleteFixture.init();
    fixture.repository_artifact_states[
        fixture.repository_artifact_states.len - 1
    ].id = fixture.repository_artifact_states[0].id;
    try expectFailure(
        fixture.evidence(),
        .duplicate_repository_artifact_state,
    );

    fixture = CompleteFixture.init();
    var evidence = fixture.evidence();
    evidence.repository_artifact_states =
        evidence.repository_artifact_states[0 .. evidence.repository_artifact_states.len - 1];
    try expectFailure(evidence, .missing_repository_artifact_state);

    fixture = CompleteFixture.init();
    fixture.repository_artifact_states[0].result = .failed;
    const changed_digest = canonicalEvidenceDigest(fixture.evidence());
    try std.testing.expect(!digestEql(
        fixture.canonical_evidence_sha256,
        changed_digest,
    ));
    try expectFailure(
        fixture.evidence(),
        .failed_repository_artifact_state,
    );
}

test "key purpose separation evidence is an exact dual-architecture matrix" {
    var fixture = CompleteFixture.init();
    var evidence = fixture.evidence();
    evidence.key_purpose_separation_results =
        evidence.key_purpose_separation_results[0 .. evidence.key_purpose_separation_results.len - 1];
    try expectFailure(evidence, .missing_key_purpose_separation_pair);

    fixture = CompleteFixture.init();
    fixture.key_purpose_separation_results[
        fixture.key_purpose_separation_results.len - 1
    ] = fixture.key_purpose_separation_results[0];
    try expectFailure(
        fixture.evidence(),
        .duplicate_key_purpose_separation_pair,
    );

    fixture = CompleteFixture.init();
    fixture.key_purpose_separation_results[0].compared_domain =
        .database_at_rest;
    try expectFailure(
        fixture.evidence(),
        .unexpected_key_purpose_separation_domain,
    );

    fixture = CompleteFixture.init();
    fixture.key_purpose_separation_results[0]
        .architecture_component_binding_sha256 =
        fixture.architecture_components[1].binding_sha256;
    try expectFailure(
        fixture.evidence(),
        .key_purpose_architecture_binding_mismatch,
    );
}

test "key purpose separation requires all three observations and attestation" {
    const cases = [_]struct {
        kind: enum {
            material_distinct,
            non_derived,
            handle_not_reused,
            attestation,
            result_digest,
        },
        expected: ValidationFailure,
    }{
        .{
            .kind = .material_distinct,
            .expected = .failed_key_material_distinction,
        },
        .{
            .kind = .non_derived,
            .expected = .failed_key_non_derivation,
        },
        .{
            .kind = .handle_not_reused,
            .expected = .failed_key_handle_non_reuse,
        },
        .{
            .kind = .attestation,
            .expected = .zero_key_purpose_separation_attestation_digest,
        },
        .{
            .kind = .result_digest,
            .expected = .key_purpose_separation_result_digest_mismatch,
        },
    };
    for (cases) |case| {
        var fixture = CompleteFixture.init();
        switch (case.kind) {
            .material_distinct => fixture.key_purpose_separation_results[0]
                .material_distinct = .failed,
            .non_derived => fixture.key_purpose_separation_results[0]
                .non_derived = .failed,
            .handle_not_reused => fixture.key_purpose_separation_results[0]
                .handle_not_reused = .failed,
            .attestation => fixture.key_purpose_separation_results[0]
                .separation_attestation_sha256 = std.mem.zeroes(Digest),
            .result_digest => fixture.key_purpose_separation_results[0]
                .result_record_sha256 = repeatedDigest(0x7d),
        }
        try expectFailure(fixture.evidence(), case.expected);
    }
}

test "canonical evidence binds key purpose separation result records" {
    var fixture = CompleteFixture.init();
    fixture.key_purpose_separation_results[0]
        .separation_attestation_sha256 = repeatedDigest(0x7c);
    fixture.key_purpose_separation_results[0].result_record_sha256 =
        keyPurposeSeparationResultDigest(
            fixture.key_purpose_separation_results[0],
        );
    try expectFailure(
        fixture.evidence(),
        .canonical_evidence_digest_mismatch,
    );
}

test "canonical evidence binding covers complete detached record set" {
    var fixture = CompleteFixture.init();
    fixture.decision_approvals[0].owner =
        fixturePrincipal("fixture.alternate-product-owner");
    fixture.decision_approvals[0].approval_record_sha256 =
        decisionApprovalDigest(fixture.decision_approvals[0]);
    try expectFailure(
        fixture.evidence(),
        .canonical_evidence_digest_mismatch,
    );
}

test "all exact release component digests must be nonzero" {
    const cases = [_]struct {
        kind: enum {
            source,
            architecture_executable,
            architecture_package_inventory,
            architecture_package_manifest,
            architecture_toolchain,
            architecture_harness,
            provider_binary,
            provider_configuration,
            backend_binary,
            backend_configuration,
            architecture_component_set,
            canonical_evidence,
        },
        expected: ValidationFailure,
    }{
        .{
            .kind = .source,
            .expected = .zero_reviewed_source_inventory_digest,
        },
        .{
            .kind = .architecture_executable,
            .expected = .zero_architecture_executable_digest,
        },
        .{
            .kind = .architecture_package_inventory,
            .expected = .zero_architecture_package_inventory_digest,
        },
        .{
            .kind = .architecture_package_manifest,
            .expected = .zero_architecture_package_manifest_digest,
        },
        .{
            .kind = .architecture_toolchain,
            .expected = .zero_architecture_toolchain_digest,
        },
        .{
            .kind = .architecture_harness,
            .expected = .zero_architecture_conformance_harness_digest,
        },
        .{ .kind = .provider_binary, .expected = .zero_provider_binary_digest },
        .{
            .kind = .provider_configuration,
            .expected = .zero_provider_configuration_digest,
        },
        .{ .kind = .backend_binary, .expected = .zero_backend_binary_digest },
        .{
            .kind = .backend_configuration,
            .expected = .zero_backend_configuration_digest,
        },
        .{
            .kind = .architecture_component_set,
            .expected = .zero_architecture_component_set_binding_digest,
        },
        .{
            .kind = .canonical_evidence,
            .expected = .zero_canonical_evidence_digest,
        },
    };
    for (cases) |case| {
        var fixture = CompleteFixture.init();
        var evidence = fixture.evidence();
        switch (case.kind) {
            .source => evidence.reviewed_source_inventory_sha256 =
                std.mem.zeroes(Digest),
            .architecture_executable => fixture.architecture_artifacts[0]
                .executable_sha256 =
                std.mem.zeroes(Digest),
            .architecture_package_inventory => fixture.architecture_artifacts[0]
                .package_inventory_sha256 =
                std.mem.zeroes(Digest),
            .architecture_package_manifest => fixture.architecture_artifacts[0]
                .package_manifest_sha256 =
                std.mem.zeroes(Digest),
            .architecture_toolchain => fixture.architecture_artifacts[0]
                .toolchain_sha256 =
                std.mem.zeroes(Digest),
            .architecture_harness => fixture.architecture_artifacts[0]
                .conformance_harness_sha256 =
                std.mem.zeroes(Digest),
            .provider_binary => fixture.architecture_components[0]
                .provider.binary_sha256 =
                std.mem.zeroes(Digest),
            .provider_configuration => fixture.architecture_components[0]
                .provider.configuration_sha256 =
                std.mem.zeroes(Digest),
            .backend_binary => fixture.architecture_components[0]
                .backend.binary_sha256 =
                std.mem.zeroes(Digest),
            .backend_configuration => fixture.architecture_components[0]
                .backend.configuration_sha256 =
                std.mem.zeroes(Digest),
            .architecture_component_set => evidence.architecture_component_set_binding_sha256 =
                std.mem.zeroes(Digest),
            .canonical_evidence => evidence.canonical_evidence_sha256 =
                std.mem.zeroes(Digest),
        }
        if (switch (case.kind) {
            .architecture_executable,
            .architecture_package_inventory,
            .architecture_package_manifest,
            .architecture_toolchain,
            .architecture_harness,
            => true,
            else => false,
        }) {
            evidence = fixture.evidence();
        }
        try expectFailure(evidence, case.expected);
    }
}

test "expired revoked and non-distinct decision approvals fail closed" {
    var fixture = CompleteFixture.init();
    fixture.decision_approvals[0].expires_at_unix_seconds = fixture_now;
    try expectFailure(fixture.evidence(), .decision_expired);

    fixture = CompleteFixture.init();
    fixture.decision_approvals[0].revoked = true;
    try expectFailure(fixture.evidence(), .decision_revoked);

    fixture = CompleteFixture.init();
    fixture.decision_approvals[0].reviewer =
        fixture.decision_approvals[0].owner;
    try expectFailure(
        fixture.evidence(),
        .decision_owner_reviewer_not_distinct,
    );
}

test "identity mismatches and unstable identities fail closed" {
    var fixture = CompleteFixture.init();
    fixture.qualification_results[0]
        .provider_identity_binding_sha256 = repeatedDigest(0x7f);
    try expectFailure(
        fixture.evidence(),
        .qualification_identity_binding_mismatch,
    );

    fixture = CompleteFixture.init();
    fixture.architecture_components[0].provider.version = "";
    try expectFailure(fixture.evidence(), .invalid_provider_identity);

    fixture = CompleteFixture.init();
    fixture.architecture_components[0].backend.binding_sha256 =
        repeatedDigest(0x7e);
    try expectFailure(
        fixture.evidence(),
        .backend_identity_binding_mismatch,
    );

    fixture = CompleteFixture.init();
    var evidence = fixture.evidence();
    evidence.architecture_component_set_binding_sha256 =
        repeatedDigest(0x7b);
    try expectFailure(
        evidence,
        .architecture_component_set_binding_mismatch,
    );
}

test "evidence cannot select its own provider or authorize production" {
    var fixture = CompleteFixture.init();
    var evidence = fixture.evidence();
    evidence.authority_claim = .attempted_self_selection;
    try expectFailure(evidence, .evidence_attempted_self_selection);

    fixture = CompleteFixture.init();
    fixture.backend_requirements[0].result = .failed;
    const verdict = validate(fixture.evidence(), fixture_now);
    try std.testing.expectEqual(
        ValidationFailure.failed_backend_requirement,
        verdict.failure,
    );
    try std.testing.expect(
        verdict.counts.gates_passed < verdict.counts.gates_required,
    );
    try std.testing.expect(
        verdict.counts.records_validated < verdict.counts.records_required,
    );
    try std.testing.expect(!verdict.all_required_evidence_gates_passed);
    try std.testing.expect(!verdict.production_authorized);
}
