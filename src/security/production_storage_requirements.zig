//! Provider-neutral requirements for production taxpayer-data persistence.
//!
//! This module is a closed requirements vocabulary, not an implementation,
//! provider selection, qualification record, or production authority.  The
//! arrays are intentionally explicit: adding a requirement to an enum without
//! adding it to the corresponding reviewed array is a compile error.

const std = @import("std");

/// Closed minimum categories currently known to contain repository values,
/// structural metadata, a database key, or an authenticated transition record.
/// Compile-time exhaustiveness is relative to this enum; provider review may
/// identify additional surfaces that must be added here and to the array.
pub const ProtectedArtifactSurface = enum {
    primary_database,
    write_ahead_log,
    shared_memory_index,
    rollback_journal,
    statement_and_temporary_spill,
    backup_and_export_copy,
    migration_and_rotation_copy,
    wrapped_key_and_custody_metadata,
};

pub const required_protected_artifact_surfaces = [_]ProtectedArtifactSurface{
    .primary_database,
    .write_ahead_log,
    .shared_memory_index,
    .rollback_journal,
    .statement_and_temporary_spill,
    .backup_and_export_copy,
    .migration_and_rotation_copy,
    .wrapped_key_and_custody_metadata,
};

/// These are properties a selected database backend must prove.  Merely
/// returning success from an interface callback is not proof of any property.
pub const AuthenticatedBackendRequirement = enum {
    confidentiality_and_authenticity,
    whole_repository_surface_coverage,
    authentication_before_sql_or_pragma,
    no_plaintext_probe_or_fallback,
    no_create_over_unreadable_repository,
    key_and_cipher_version_binding,
    database_and_sidecar_anti_swap_binding,
    truncation_tamper_and_replay_detection,
    trusted_freshness_and_restore_lineage_binding,
    crash_consistent_create_migrate_and_rotate,
    bounded_and_cleared_application_buffers,
    qualified_database_library_page_cache,
    windows_directory_and_sidecar_access_control,
    windows_reparse_resistant_handle_relative_resolution,
    windows_parent_leaf_file_identity_continuity,
};

pub const required_authenticated_backend_requirements =
    [_]AuthenticatedBackendRequirement{
        .confidentiality_and_authenticity,
        .whole_repository_surface_coverage,
        .authentication_before_sql_or_pragma,
        .no_plaintext_probe_or_fallback,
        .no_create_over_unreadable_repository,
        .key_and_cipher_version_binding,
        .database_and_sidecar_anti_swap_binding,
        .truncation_tamper_and_replay_detection,
        .trusted_freshness_and_restore_lineage_binding,
        .crash_consistent_create_migrate_and_rotate,
        .bounded_and_cleared_application_buffers,
        .qualified_database_library_page_cache,
        .windows_directory_and_sidecar_access_control,
        .windows_reparse_resistant_handle_relative_resolution,
        .windows_parent_leaf_file_identity_continuity,
    };

/// Custody failures that must be distinguished internally and exposed only as
/// value-free diagnostics to callers.
pub const CustodyFailClosedCondition = enum {
    provider_missing,
    provider_unavailable,
    authentication_cancelled,
    wrapped_key_missing,
    wrapped_key_corrupt,
    wrapped_key_replayed,
    wrapped_key_swapped,
    wrong_operating_system_user,
    wrong_machine,
    wrong_application_identity,
    unsupported_provider_or_key_version,
    revoked_or_expired_authority,
};

pub const required_custody_fail_closed_conditions =
    [_]CustodyFailClosedCondition{
        .provider_missing,
        .provider_unavailable,
        .authentication_cancelled,
        .wrapped_key_missing,
        .wrapped_key_corrupt,
        .wrapped_key_replayed,
        .wrapped_key_swapped,
        .wrong_operating_system_user,
        .wrong_machine,
        .wrong_application_identity,
        .unsupported_provider_or_key_version,
        .revoked_or_expired_authority,
    };

/// Recovery behavior is part of the security policy, including cases where
/// the approved outcome may be that recovery is impossible.
pub const RecoveryScenario = enum {
    interrupted_initial_provision,
    interrupted_key_rotation,
    interrupted_cipher_or_schema_migration,
    interrupted_wal_or_checkpoint_recovery,
    protected_backup_restore,
    approved_device_transfer,
    operating_system_password_or_account_reset,
    lost_primary_custody_material,
    lost_all_approved_custody_and_recovery_material,
};

pub const required_recovery_scenarios = [_]RecoveryScenario{
    .interrupted_initial_provision,
    .interrupted_key_rotation,
    .interrupted_cipher_or_schema_migration,
    .interrupted_wal_or_checkpoint_recovery,
    .protected_backup_restore,
    .approved_device_transfer,
    .operating_system_password_or_account_reset,
    .lost_primary_custody_material,
    .lost_all_approved_custody_and_recovery_material,
};

/// Classification is performed only through the selected authenticated
/// backend.  A legacy-plaintext result is untrusted and grants no SQL, PRAGMA,
/// mutation, migration, quarantine, reset, or deletion authority.
pub const RepositoryArtifactState = enum {
    absent,
    authenticated_current,
    authenticated_interrupted_provision,
    authenticated_interrupted_rotation,
    authenticated_interrupted_migration,
    legacy_plaintext_untrusted,
    unsupported_cipher_version,
    custody_database_pair_mismatch,
    unrecognized_or_tampered,
};

pub const required_repository_artifact_states = [_]RepositoryArtifactState{
    .absent,
    .authenticated_current,
    .authenticated_interrupted_provision,
    .authenticated_interrupted_rotation,
    .authenticated_interrupted_migration,
    .legacy_plaintext_untrusted,
    .unsupported_cipher_version,
    .custody_database_pair_mismatch,
    .unrecognized_or_tampered,
};

/// Release evidence must cover both Windows product architectures and each
/// security-sensitive lifecycle.  These names do not claim that evidence
/// exists.
pub const QualificationScenario = enum {
    windows_x86_64_release,
    windows_aarch64_release,
    clean_install_and_first_provision,
    normal_restart_and_concurrent_wal,
    wrong_user_wrong_machine_and_wrong_key,
    tamper_truncation_replay_and_artifact_swap,
    full_bundle_replay_and_restore_freshness,
    crash_during_provision_migration_and_rotation,
    backup_restore_transfer_and_unrecoverable_key,
    upgrade_downgrade_and_cipher_version_mismatch,
    windows_acl_reparse_and_file_identity_attacks,
    packaged_binary_provenance_and_code_signing,
};

pub const required_qualification_scenarios = [_]QualificationScenario{
    .windows_x86_64_release,
    .windows_aarch64_release,
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
};

/// Qualification is a native execution matrix, not a cross-compilation claim.
/// Architecture-specific release rows apply only to their matching target;
/// every other qualification scenario must be observed on both targets.
pub const WindowsArchitecture = enum {
    x86_64,
    aarch64,
};

pub const required_windows_architectures = [_]WindowsArchitecture{
    .x86_64,
    .aarch64,
};

/// Source, product, security, and operations owners must resolve every item.
/// Runtime flags, environment variables, or caller-supplied strings cannot
/// satisfy these decisions.
pub const ExternalDecision = enum {
    backend_product_version_and_license,
    backend_build_provenance_and_update_policy,
    custody_provider_and_identity_scope,
    custody_user_presence_policy,
    backup_export_and_device_transfer_policy,
    password_reset_disaster_recovery_and_unrecoverable_key_ux,
    key_rotation_cadence_and_interruption_policy,
    anti_rollback_freshness_and_restore_policy,
    legacy_plaintext_backup_migrate_quarantine_reset_or_delete_policy,
    installer_code_signing_release_hardening_and_support_policy,
};

pub const outstanding_external_decisions = [_]ExternalDecision{
    .backend_product_version_and_license,
    .backend_build_provenance_and_update_policy,
    .custody_provider_and_identity_scope,
    .custody_user_presence_policy,
    .backup_export_and_device_transfer_policy,
    .password_reset_disaster_recovery_and_unrecoverable_key_ux,
    .key_rotation_cadence_and_interruption_policy,
    .anti_rollback_freshness_and_restore_policy,
    .legacy_plaintext_backup_migrate_quarantine_reset_or_delete_policy,
    .installer_code_signing_release_hardening_and_support_policy,
};

/// The database key has one purpose.  It must never be derived from, reused
/// as, or substituted by any of the other domains.
pub const KeyPurposeDomain = enum {
    database_at_rest,
    submission_container_protocol,
    application_credential,
    signing_identity,
    taxpayer_identifier,
};

pub const database_key_purpose = KeyPurposeDomain.database_at_rest;

/// Every other purpose is an explicit negative domain for the database key.
/// Qualification must prove that database-at-rest material and handles are
/// distinct, non-derived, and non-reused relative to each entry.
pub const required_database_key_separation_domains = [_]KeyPurposeDomain{
    .submission_container_protocol,
    .application_credential,
    .signing_identity,
    .taxpayer_identifier,
};

fn assertExplicitlyExhaustive(
    comptime Enum: type,
    comptime values: anytype,
    comptime label: []const u8,
) void {
    const fields = std.meta.fields(Enum);
    if (values.len != fields.len) {
        @compileError(label ++ " must list every enum tag exactly once");
    }
    inline for (std.meta.tags(Enum)) |tag| {
        var count: usize = 0;
        inline for (values) |value| {
            if (value == tag) count += 1;
        }
        if (count != 1) {
            @compileError(label ++ " must list every enum tag exactly once");
        }
    }
}

fn assertDatabaseKeySeparationDomains() void {
    const fields = std.meta.fields(KeyPurposeDomain);
    if (required_database_key_separation_domains.len + 1 != fields.len) {
        @compileError(
            "database key separation domains must list every non-database purpose exactly once",
        );
    }
    inline for (required_database_key_separation_domains) |domain| {
        if (domain == database_key_purpose) {
            @compileError(
                "database key purpose cannot be its own separation domain",
            );
        }
        var count: usize = 0;
        inline for (required_database_key_separation_domains) |candidate| {
            if (candidate == domain) count += 1;
        }
        if (count != 1) {
            @compileError(
                "database key separation domains must be unique",
            );
        }
    }
    inline for (std.meta.tags(KeyPurposeDomain)) |domain| {
        if (domain == database_key_purpose) continue;
        var count: usize = 0;
        inline for (required_database_key_separation_domains) |candidate| {
            if (candidate == domain) count += 1;
        }
        if (count != 1) {
            @compileError(
                "database key separation domains must list every non-database purpose exactly once",
            );
        }
    }
}

comptime {
    @setEvalBranchQuota(3_000);
    assertExplicitlyExhaustive(
        ProtectedArtifactSurface,
        required_protected_artifact_surfaces,
        "protected artifact surfaces",
    );
    assertExplicitlyExhaustive(
        AuthenticatedBackendRequirement,
        required_authenticated_backend_requirements,
        "authenticated backend requirements",
    );
    assertExplicitlyExhaustive(
        CustodyFailClosedCondition,
        required_custody_fail_closed_conditions,
        "custody fail-closed conditions",
    );
    assertExplicitlyExhaustive(
        RecoveryScenario,
        required_recovery_scenarios,
        "recovery scenarios",
    );
    assertExplicitlyExhaustive(
        RepositoryArtifactState,
        required_repository_artifact_states,
        "repository artifact states",
    );
    assertExplicitlyExhaustive(
        QualificationScenario,
        required_qualification_scenarios,
        "qualification scenarios",
    );
    assertExplicitlyExhaustive(
        WindowsArchitecture,
        required_windows_architectures,
        "Windows architectures",
    );
    assertExplicitlyExhaustive(
        ExternalDecision,
        outstanding_external_decisions,
        "outstanding external decisions",
    );
    assertDatabaseKeySeparationDomains();
}

test "production storage requirements stay explicit and provider-neutral" {
    try std.testing.expectEqual(
        KeyPurposeDomain.database_at_rest,
        database_key_purpose,
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        required_database_key_separation_domains.len,
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        required_protected_artifact_surfaces.len,
    );
    try std.testing.expectEqual(
        @as(usize, 15),
        required_authenticated_backend_requirements.len,
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        required_custody_fail_closed_conditions.len,
    );
    try std.testing.expectEqual(
        @as(usize, 9),
        required_recovery_scenarios.len,
    );
    try std.testing.expectEqual(
        @as(usize, 9),
        required_repository_artifact_states.len,
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        required_qualification_scenarios.len,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        required_windows_architectures.len,
    );
    try std.testing.expectEqual(
        @as(usize, 10),
        outstanding_external_decisions.len,
    );
}
