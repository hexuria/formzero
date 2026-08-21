//! Value-free evidence metadata and readiness gates.
//!
//! Source paths, byte lengths, hashes, and source locations are allowed here.
//! Runtime form values and payload bytes are deliberately not representable.

const std = @import("std");
const identity = @import("identity.zig");

pub const SourceRole = enum(u8) {
    form_source = 1,
    script_dependency = 2,
};

pub const OfficialDocumentKind = enum(u8) {
    form_pdf = 1,
    filing_guide = 2,
};

pub const OfficialDocumentEvidence = struct {
    kind: OfficialDocumentKind,
    evidence_id: []const u8,
    byte_length: u32,
    sha256: identity.Sha256Digest,
};

pub const SourceEvidence = struct {
    role: SourceRole,
    normalized_relative_path: []const u8,
    resource_id: u16,
    byte_length: u32,
    sha256: identity.Sha256Digest,
    exact_resource_match: bool,
    script_load_order: ?u8 = null,
    script_tag_line: ?u32 = null,
};

/// An active `<script src>` that is not an exact recovered package path.
/// Path-placement variants name the nearby recovered file without claiming
/// that the HTA loads it. Absent scripts have no recovered bytes.
pub const UnresolvedScriptKind = enum(u8) {
    absent_from_package = 1,
    path_placement_variant = 2,
};

pub const UnresolvedScriptEvidence = struct {
    kind: UnresolvedScriptKind,
    normalized_relative_path: []const u8,
    script_load_order: u8,
    script_tag_line: u32,
    recovered_relative_path: ?[]const u8 = null,
    recovered_sha256: ?identity.Sha256Digest = null,
};

pub const EvidenceReadiness = struct {
    identity_resolved: bool = false,
    dependency_closure: bool = false,
    profile_mapping_reviewed: bool = false,
    calculation_reconciled: bool = false,
    validation_reconciled: bool = false,
    editable_serializer_exact: bool = false,
    final_plaintext_serializer_exact: bool = false,
    decrypt_codec_qualified: bool = false,
    encrypt_codec_qualified: bool = false,
    persistence_integrated: bool = false,
    ui_integrated: bool = false,
    offline_package_verified: bool = false,
    transport_enabled: bool = false,

    pub fn identityReady(self: EvidenceReadiness) bool {
        return self.identity_resolved and self.dependency_closure;
    }

    pub fn plaintextCodecsReady(self: EvidenceReadiness) bool {
        return self.calculation_reconciled and
            self.validation_reconciled and
            self.editable_serializer_exact and
            self.final_plaintext_serializer_exact;
    }

    pub fn validateOfflineBoundary(
        self: EvidenceReadiness,
    ) error{TransportMustRemainDisabled}!void {
        if (self.transport_enabled) {
            return error.TransportMustRemainDisabled;
        }
    }
};

pub const ManifestError = error{
    WrongPrimarySourceRole,
    PrimarySourceNotExact,
    EmptyRelativePath,
    PathOrderNotCanonical,
    WrongDependencyRole,
    DependencyNotExact,
    MissingScriptLoadOrder,
    InvalidScriptLoadOrder,
    DuplicateScriptLoadOrder,
    MissingScriptTagLine,
    UnresolvedRecoveredPathMissing,
    UnresolvedRecoveredPathUnexpected,
    DependencyDigestMismatch,
    IdentityReadinessMismatch,
    DependencyReadinessMismatch,
    TransportMustRemainDisabled,
};

pub const EvidenceManifest = struct {
    const Self = @This();

    package_key: identity.ExactFormPackageKey,
    primary_source: SourceEvidence,
    /// Canonical path order, not execution order. `script_load_order`
    /// separately preserves the official `<script>` order.
    dependencies: []const SourceEvidence,
    /// Active `<script src>` references that are not exact recovered paths.
    /// Canonical path order among themselves. Load order is the HTA order
    /// shared with `dependencies`.
    unresolved_scripts: []const UnresolvedScriptEvidence = &.{},
    readiness: EvidenceReadiness,

    pub fn validate(self: *const Self) ManifestError!void {
        try self.readiness.validateOfflineBoundary();

        if (self.primary_source.role != .form_source) {
            return error.WrongPrimarySourceRole;
        }
        if (self.primary_source.normalized_relative_path.len == 0) {
            return error.EmptyRelativePath;
        }
        if (!self.primary_source.exact_resource_match) {
            return error.PrimarySourceNotExact;
        }
        if (!self.primary_source.sha256.eql(
            &self.package_key.primary_source_sha256,
        )) {
            return error.IdentityReadinessMismatch;
        }

        const total_scripts = self.dependencies.len + self.unresolved_scripts.len;

        var prior_path = self.primary_source.normalized_relative_path;
        for (self.dependencies, 0..) |dependency, index| {
            if (dependency.role != .script_dependency) {
                return error.WrongDependencyRole;
            }
            if (dependency.normalized_relative_path.len == 0) {
                return error.EmptyRelativePath;
            }
            if (std.mem.order(
                u8,
                prior_path,
                dependency.normalized_relative_path,
            ) != .lt) {
                return error.PathOrderNotCanonical;
            }
            prior_path = dependency.normalized_relative_path;
            if (!dependency.exact_resource_match) {
                return error.DependencyNotExact;
            }
            const load_order = dependency.script_load_order orelse
                return error.MissingScriptLoadOrder;
            if (load_order == 0 or load_order > total_scripts) {
                return error.InvalidScriptLoadOrder;
            }
            if (dependency.script_tag_line == null) {
                return error.MissingScriptTagLine;
            }
            for (self.dependencies[0..index]) |earlier| {
                if (earlier.script_load_order.? == load_order) {
                    return error.DuplicateScriptLoadOrder;
                }
            }
        }

        var unresolved_prior: []const u8 = "";
        for (self.unresolved_scripts, 0..) |script, index| {
            if (script.normalized_relative_path.len == 0) {
                return error.EmptyRelativePath;
            }
            if (unresolved_prior.len != 0 and
                std.mem.order(
                    u8,
                    unresolved_prior,
                    script.normalized_relative_path,
                ) != .lt)
            {
                return error.PathOrderNotCanonical;
            }
            unresolved_prior = script.normalized_relative_path;
            if (script.script_load_order == 0 or
                script.script_load_order > total_scripts)
            {
                return error.InvalidScriptLoadOrder;
            }
            if (script.script_tag_line == 0) {
                return error.MissingScriptTagLine;
            }
            switch (script.kind) {
                .absent_from_package => {
                    if (script.recovered_relative_path != null or
                        script.recovered_sha256 != null)
                    {
                        return error.UnresolvedRecoveredPathUnexpected;
                    }
                },
                .path_placement_variant => {
                    const recovered = script.recovered_relative_path orelse
                        return error.UnresolvedRecoveredPathMissing;
                    if (recovered.len == 0 or script.recovered_sha256 == null) {
                        return error.UnresolvedRecoveredPathMissing;
                    }
                },
            }
            for (self.unresolved_scripts[0..index]) |earlier| {
                if (earlier.script_load_order == script.script_load_order) {
                    return error.DuplicateScriptLoadOrder;
                }
            }
            for (self.dependencies) |dependency| {
                if (dependency.script_load_order.? == script.script_load_order) {
                    return error.DuplicateScriptLoadOrder;
                }
            }
        }

        const computed_dependencies = dependencyDigest(self.dependencies);
        if (!computed_dependencies.eql(
            &self.package_key.dependency_manifest_sha256,
        )) {
            return error.DependencyDigestMismatch;
        }
        if (self.readiness.identity_resolved and
            !self.primary_source.exact_resource_match)
        {
            return error.IdentityReadinessMismatch;
        }
        if (self.readiness.dependency_closure and
            (self.dependencies.len == 0 or self.unresolved_scripts.len != 0))
        {
            return error.DependencyReadinessMismatch;
        }
    }
};

/// Hashes value-free path/hash records:
/// `normalized-path || NUL || lowercase-sha256 || LF`.
pub fn dependencyDigest(
    dependencies: []const SourceEvidence,
) identity.Sha256Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    for (dependencies) |dependency| {
        updateSourceRecord(&hash, dependency);
    }
    var result: identity.Sha256Digest = .{ .bytes = undefined };
    hash.final(&result.bytes);
    return result;
}

/// Uses the same canonical record format, with the primary form source first.
pub fn sourceSetDigest(
    manifest: *const EvidenceManifest,
) identity.Sha256Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    updateSourceRecord(&hash, manifest.primary_source);
    for (manifest.dependencies) |dependency| {
        updateSourceRecord(&hash, dependency);
    }
    var result: identity.Sha256Digest = .{ .bytes = undefined };
    hash.final(&result.bytes);
    return result;
}

fn updateSourceRecord(
    hash: *std.crypto.hash.sha2.Sha256,
    source: SourceEvidence,
) void {
    hash.update(source.normalized_relative_path);
    hash.update(&.{0});
    const hex = std.fmt.bytesToHex(source.sha256.bytes, .lower);
    hash.update(&hex);
    hash.update("\n");
}

test "readiness facts cannot collapse transport into local qualification" {
    const local: EvidenceReadiness = .{
        .identity_resolved = true,
        .dependency_closure = true,
    };
    try std.testing.expect(local.identityReady());
    try std.testing.expect(!local.plaintextCodecsReady());
    try local.validateOfflineBoundary();

    var unsafe = local;
    unsafe.transport_enabled = true;
    try std.testing.expectError(
        error.TransportMustRemainDisabled,
        unsafe.validateOfflineBoundary(),
    );
}

test "source evidence has no value-bearing field" {
    try std.testing.expect(!@hasField(SourceEvidence, "value"));
    try std.testing.expect(!@hasField(SourceEvidence, "raw_value"));
    try std.testing.expect(!@hasField(SourceEvidence, "payload"));
    try std.testing.expect(!@hasField(OfficialDocumentEvidence, "value"));
    try std.testing.expect(!@hasField(OfficialDocumentEvidence, "payload"));
    try std.testing.expect(!@hasField(UnresolvedScriptEvidence, "value"));
    try std.testing.expect(!@hasField(UnresolvedScriptEvidence, "raw_value"));
    try std.testing.expect(!@hasField(UnresolvedScriptEvidence, "payload"));
}
