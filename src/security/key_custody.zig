//! Fail-closed classification for local taxpayer-data persistence.
//!
//! This module deliberately implements no encryption, key bytes, database
//! opening, operating-system provider, recovery, or migration behavior.
//! Production storage remains unavailable until a separately reviewed backend
//! and custody design replace this boundary in the same reviewed change.

const builtin = @import("builtin");
const std = @import("std");

/// The current executable is source-classified as a development artifact.
/// There is no production tag in this vocabulary: a production-ready artifact
/// requires a replacement custody decision and build boundary, not a flag.
pub const ArtifactStorageClassification = enum {
    development_only_plaintext_not_production,
};

pub const current_artifact_storage_classification: ArtifactStorageClassification =
    .development_only_plaintext_not_production;

pub const current_artifact_storage_classification_text: []const u8 =
    @tagName(current_artifact_storage_classification);

/// Value-free reason shared by the build gate and its negative regression.
/// Changing it cannot enable production; the build graph has no success branch
/// for `production-release` in current source.
pub const production_release_unavailable_reason =
    "production-release unavailable: authenticated backend, operating-system " ++
    "custody, recovery, legacy transition, and release qualification remain " ++
    "unapproved";

/// Synthetic fixture persistence has exactly one permitted classification. A
/// caller must also hold the opaque test capability returned by
/// `acquireSyntheticPlaintextForTest`. Development-artifact file storage uses
/// the separate source-minted capability below.
pub const PlaintextStorageState = enum {
    synthetic_plaintext_test_only,
};

/// Every state is intentionally unavailable. The comptime guard below prevents
/// a ready/enabled state from being added without deliberately changing this
/// module's fail-closed invariant.
pub const ProductionStorageState = enum {
    unavailable_authenticated_storage_backend_unselected,
    unavailable_operating_system_custody_provider_unimplemented,
    unavailable_recovery_policy_unapproved,
    unavailable_legacy_plaintext_transition_unapproved,
};

pub const current_production_storage_state: ProductionStorageState =
    .unavailable_authenticated_storage_backend_unselected;

pub const BoundarySnapshot = struct {
    plaintext: PlaintextStorageState,
    production: ProductionStorageState,
};

pub const ProductionStorageError = error{
    ProductionStorageUnavailable,
};

pub const SyntheticPlaintextTestError = error{
    InvalidSyntheticPlaintextTestCapability,
};

pub const DevelopmentPlaintextStorageError = error{
    InvalidDevelopmentPlaintextStorageCapability,
};

/// No public representation can carry a plaintext fixture key or other secret.
/// The pointer is only an authority marker for test-only adapter APIs.
pub const SyntheticPlaintextTestCapability = opaque {};

/// Authority to open the legacy file-backed plaintext stores exists only in
/// the source-selected development artifact. The opaque pointer is always
/// identity-checked before path validation or I/O, so a cast pointer is not
/// authority.
pub const DevelopmentPlaintextStorageCapability = opaque {};

pub const CurrentArtifactStorageBootstrap = struct {
    classification: ArtifactStorageClassification,
    development_plaintext: *const DevelopmentPlaintextStorageCapability,
};

/// Deliberately has no constructor. A future reviewed backend must replace this
/// unavailable boundary rather than toggling a flag or fabricating key bytes.
pub const ProductionStorageCapability = opaque {};

// Mutable storage gives the authority marker a unique addressable object.
// An immutable scalar could be constant-folded or pooled by a toolchain, which
// is not a sound foundation for an identity-checked capability.
var synthetic_plaintext_test_token: u8 = 0;
var development_plaintext_storage_token: u8 = 0;

comptime {
    for (std.meta.fields(ArtifactStorageClassification)) |field| {
        if (!std.mem.eql(
            u8,
            field.name,
            "development_only_plaintext_not_production",
        )) {
            @compileError(
                "current artifact storage classifications must remain " ++
                    "development-only until the production custody ADR is replaced",
            );
        }
    }
    for (std.meta.fields(ProductionStorageState)) |field| {
        if (!std.mem.startsWith(u8, field.name, "unavailable_")) {
            @compileError(
                "production storage states must remain fail-closed until " ++
                    "a replacement custody ADR is approved",
            );
        }
    }
}

/// The only minting path for legacy file-backed development authority. It has
/// no runtime input, environment lookup, build option, provider selector, or
/// key material. `main` must acquire this before inspecting any repository
/// location input.
pub fn bootstrapCurrentArtifactStorage() CurrentArtifactStorageBootstrap {
    return switch (current_artifact_storage_classification) {
        .development_only_plaintext_not_production => .{
            .classification = current_artifact_storage_classification,
            .development_plaintext = @ptrCast(&development_plaintext_storage_token),
        },
    };
}

pub fn requireDevelopmentPlaintextStorage(
    capability: *const DevelopmentPlaintextStorageCapability,
) DevelopmentPlaintextStorageError!void {
    const expected: *const DevelopmentPlaintextStorageCapability =
        @ptrCast(&development_plaintext_storage_token);
    if (capability != expected) {
        return error.InvalidDevelopmentPlaintextStorageCapability;
    }
}

/// The test capability cannot be acquired by a non-test artifact. It contains
/// no key and grants no production authority.
pub fn acquireSyntheticPlaintextForTest() *const SyntheticPlaintextTestCapability {
    comptime {
        if (!builtin.is_test) {
            @compileError(
                "synthetic plaintext persistence is available only to tests",
            );
        }
    }
    return @ptrCast(&synthetic_plaintext_test_token);
}

/// Validates both the test-artifact boundary and the identity of the privately
/// minted authority marker. Merely fabricating a pointer of the opaque public
/// type must not authorize a plaintext persistence operation.
pub fn requireSyntheticPlaintextForTest(
    capability: *const SyntheticPlaintextTestCapability,
) SyntheticPlaintextTestError!void {
    comptime {
        if (!builtin.is_test) {
            @compileError(
                "synthetic plaintext persistence is available only to tests",
            );
        }
    }
    const expected: *const SyntheticPlaintextTestCapability =
        @ptrCast(&synthetic_plaintext_test_token);
    if (capability != expected) {
        return error.InvalidSyntheticPlaintextTestCapability;
    }
}

pub fn classifySyntheticPlaintext(
    capability: *const SyntheticPlaintextTestCapability,
) SyntheticPlaintextTestError!PlaintextStorageState {
    try requireSyntheticPlaintextForTest(capability);
    return .synthetic_plaintext_test_only;
}

pub fn boundarySnapshotForTest(
    capability: *const SyntheticPlaintextTestCapability,
) SyntheticPlaintextTestError!BoundarySnapshot {
    return .{
        .plaintext = try classifySyntheticPlaintext(capability),
        .production = current_production_storage_state,
    };
}

/// There is no success path while the authenticated backend and custody
/// provider remain unselected. In particular, this gate never opens the
/// existing plaintext SQLite stores and never accepts key material.
pub fn requireProductionStorage() ProductionStorageError!*const ProductionStorageCapability {
    return error.ProductionStorageUnavailable;
}

/// A pointer cast to the opaque type is not production authority.  Current
/// source has no valid production capability, so every attempted consumption
/// also fails closed.  A future provider change must replace this validator
/// and its private minting path together.
pub fn requireValidProductionStorageCapability(
    capability: *const ProductionStorageCapability,
) ProductionStorageError!void {
    _ = capability;
    return error.ProductionStorageUnavailable;
}

test "production custody gate is unavailable and has no plaintext fallback" {
    try std.testing.expectError(
        error.ProductionStorageUnavailable,
        requireProductionStorage(),
    );
    try std.testing.expectEqual(
        ProductionStorageState
            .unavailable_authenticated_storage_backend_unselected,
        current_production_storage_state,
    );
}

test "current artifact bootstrap mints only validated development authority" {
    const bootstrap = bootstrapCurrentArtifactStorage();
    try std.testing.expectEqual(
        ArtifactStorageClassification
            .development_only_plaintext_not_production,
        bootstrap.classification,
    );
    try std.testing.expectEqualStrings(
        "development_only_plaintext_not_production",
        current_artifact_storage_classification_text,
    );
    try requireDevelopmentPlaintextStorage(bootstrap.development_plaintext);
}

test "fabricated development plaintext authority fails closed" {
    var forged_token: u8 = 0;
    const forged: *const DevelopmentPlaintextStorageCapability =
        @ptrCast(&forged_token);
    try std.testing.expectError(
        error.InvalidDevelopmentPlaintextStorageCapability,
        requireDevelopmentPlaintextStorage(forged),
    );
}

test "synthetic plaintext authority is test-only and carries classification" {
    const capability = acquireSyntheticPlaintextForTest();
    const snapshot = try boundarySnapshotForTest(capability);
    try std.testing.expectEqual(
        PlaintextStorageState.synthetic_plaintext_test_only,
        snapshot.plaintext,
    );
    try std.testing.expectEqual(
        current_production_storage_state,
        snapshot.production,
    );
}

test "fabricated synthetic plaintext authority fails closed" {
    var forged_token: u8 = 0;
    const forged: *const SyntheticPlaintextTestCapability =
        @ptrCast(&forged_token);
    try std.testing.expectError(
        error.InvalidSyntheticPlaintextTestCapability,
        requireSyntheticPlaintextForTest(forged),
    );
    try std.testing.expectError(
        error.InvalidSyntheticPlaintextTestCapability,
        classifySyntheticPlaintext(forged),
    );
    try std.testing.expectError(
        error.InvalidSyntheticPlaintextTestCapability,
        boundarySnapshotForTest(forged),
    );
}

test "fabricated production authority fails closed" {
    var forged_token: u8 = 0;
    const forged: *const ProductionStorageCapability =
        @ptrCast(&forged_token);
    try std.testing.expectError(
        error.ProductionStorageUnavailable,
        requireValidProductionStorageCapability(forged),
    );
}

test "production state vocabulary contains unavailable states only" {
    inline for (std.meta.fields(ProductionStorageState)) |field| {
        try std.testing.expect(
            std.mem.startsWith(u8, field.name, "unavailable_"),
        );
    }
}
