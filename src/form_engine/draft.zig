//! Append-only, occurrence-first draft state for the exact 1701Q contract.
//!
//! This module owns in-memory value snapshots only. It has no filesystem,
//! encryption, queue, endpoint, or transport dependency. Every revision is
//! bound to the complete exact package key and to the digest of the ordered
//! occurrence manifest that accepted it.
//!
//! Values are never collapsed into a map: ordinal, serialized key, repeated
//! key index, and raw/normalized/emitted states are copied in slice order.
//! Value-bearing buffers are zeroed before they are released.

const std = @import("std");
const sensitive_memory = @import("../security/sensitive_memory.zig");
const identity = @import("identity.zig");
const engine_evidence = @import("evidence.zig");
const occurrence = @import("occurrence.zig");
const form_evidence = @import("forms/form_1701q_2018/evidence.zig");
const form_occurrences = @import("forms/form_1701q_2018/occurrences.zig");
const document = @import("forms/form_1701q_2018/document.zig");
const validation = @import("forms/form_1701q_2018/validation.zig");

pub const max_total_draft_value_bytes: usize =
    document.max_document_bytes * 3;

/// One editable or Final Copy stream is append-only but never unbounded.
/// Sixty-four audited save events leave useful history while bounding the
/// repeated keys and snapshot metadata retained alongside the value budget.
pub const max_revisions_per_exact_shape_stream: usize = 64;

/// Aggregate raw + normalized + emitted bytes retained by one exact shape
/// stream. This is deliberately independent of the smaller per-revision
/// document-derived ceiling above.
pub const max_retained_exact_value_bytes: usize = 64 * 1024 * 1024;

pub const HistoryLimits = struct {
    max_revisions: usize = max_revisions_per_exact_shape_stream,
    max_retained_value_bytes: usize = max_retained_exact_value_bytes,
};

pub const exact_history_limits: HistoryLimits = .{};

comptime {
    if (max_revisions_per_exact_shape_stream == 0 or
        max_retained_exact_value_bytes < max_total_draft_value_bytes)
    {
        @compileError("exact draft history limits cannot retain one revision");
    }
}

/// Compile-time boundary facts, not feature flags.
pub const SecurityBoundary = struct {
    pub const stores_protocol_secrets = false;
    pub const outbound_encryption_enabled = false;
    pub const transport_enabled = false;
};

pub const PayloadShape = enum(u8) {
    editable_save = 1,
    final_copy_plaintext = 2,

    pub fn marker(self: PayloadShape) document.Marker {
        return switch (self) {
            .editable_save => .editable,
            .final_copy_plaintext => .final,
        };
    }
};

pub const DraftWorkspaceId = struct {
    const Self = @This();

    bytes: [16]u8,

    pub fn init(bytes: [16]u8) error{AllZeroWorkspaceId}!Self {
        for (bytes) |byte| {
            if (byte != 0) return .{ .bytes = bytes };
        }
        return error.AllZeroWorkspaceId;
    }

    pub fn eql(self: *const Self, other: *const Self) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }
};

pub const DraftRevision = struct {
    const Self = @This();

    value: u64,

    pub fn init(value: u64) error{InvalidDraftRevision}!Self {
        if (value == 0) return error.InvalidDraftRevision;
        return .{ .value = value };
    }

    pub fn eql(self: Self, other: Self) bool {
        return self.value == other.value;
    }
};

pub const RevisionGuard = union(enum) {
    create,
    match: DraftRevision,
};

pub const DraftIdentity = struct {
    workspace_id: DraftWorkspaceId,
    exact_schema_digest: identity.Sha256Digest,

    pub fn eql(self: *const DraftIdentity, other: *const DraftIdentity) bool {
        return self.workspace_id.eql(&other.workspace_id) and
            self.exact_schema_digest.eql(&other.exact_schema_digest);
    }
};

pub const SchemaError =
    occurrence.ManifestError ||
    engine_evidence.ManifestError ||
    error{
        TooManySchemaOccurrences,
        TransportMustRemainDisabled,
    };

pub const CandidateSchemaError =
    occurrence.ManifestError ||
    error{
        WrongFormPackage,
        WrongPayloadShape,
        WrongOccurrenceManifest,
    };

/// Frozen schema and evidence binding copied into every immutable revision.
pub const SchemaBinding = struct {
    const Self = @This();

    package_key: identity.ExactFormPackageKey,
    package_digest: identity.Sha256Digest,
    occurrence_manifest_digest: identity.Sha256Digest,
    exact_schema_digest: identity.Sha256Digest,
    payload_shape: PayloadShape,
    occurrence_count: u16,
    evidence_readiness: engine_evidence.EvidenceReadiness,

    pub fn exact1701Q(shape: PayloadShape) SchemaError!Self {
        try form_evidence.manifest.validate();
        const manifest = try exactManifest(shape);
        return bind(
            form_evidence.package_key,
            shape,
            manifest,
            form_evidence.readiness,
        );
    }

    pub fn verifyCandidate(
        self: *const Self,
        candidate_package: *const identity.ExactFormPackageKey,
        candidate_shape: PayloadShape,
        candidate_manifest: occurrence.OrderedOccurrenceManifest,
    ) CandidateSchemaError!occurrence.OrderedOccurrenceManifest {
        if (!self.package_key.eql(candidate_package)) {
            return error.WrongFormPackage;
        }
        if (self.payload_shape != candidate_shape) {
            return error.WrongPayloadShape;
        }

        // The struct is public, so never trust that a caller used `init`.
        const checked = try occurrence.OrderedOccurrenceManifest.init(
            candidate_manifest.items,
        );
        const digest = checked.canonicalDigest();
        if (checked.items.len != self.occurrence_count or
            !digest.eql(&self.occurrence_manifest_digest))
        {
            return error.WrongOccurrenceManifest;
        }
        return checked;
    }

    fn bind(
        package_key: identity.ExactFormPackageKey,
        shape: PayloadShape,
        manifest: occurrence.OrderedOccurrenceManifest,
        readiness: engine_evidence.EvidenceReadiness,
    ) SchemaError!Self {
        try readiness.validateOfflineBoundary();
        if (manifest.items.len > std.math.maxInt(u16)) {
            return error.TooManySchemaOccurrences;
        }
        const package_digest = package_key.canonicalDigest();
        const manifest_digest = manifest.canonicalDigest();
        return .{
            .package_key = package_key,
            .package_digest = package_digest,
            .occurrence_manifest_digest = manifest_digest,
            .exact_schema_digest = schemaDigest(
                &package_digest,
                &manifest_digest,
                shape,
                @intCast(manifest.items.len),
            ),
            .payload_shape = shape,
            .occurrence_count = @intCast(manifest.items.len),
            .evidence_readiness = readiness,
        };
    }

    fn plaintextIsExact(self: *const Self) bool {
        if (self.package_key.codec_version == null or
            !self.evidence_readiness.identityReady() or
            !self.evidence_readiness.profile_mapping_reviewed or
            !self.evidence_readiness.calculation_reconciled or
            !self.evidence_readiness.validation_reconciled)
        {
            return false;
        }
        return switch (self.payload_shape) {
            .editable_save => self.evidence_readiness.editable_serializer_exact,
            .final_copy_plaintext => self.evidence_readiness.final_plaintext_serializer_exact,
        };
    }
};

fn exactManifest(
    shape: PayloadShape,
) occurrence.ManifestError!occurrence.OrderedOccurrenceManifest {
    return switch (shape) {
        .editable_save => form_occurrences.editableManifest(),
        .final_copy_plaintext => form_occurrences.finalCopyManifest(),
    };
}

fn schemaDigest(
    package_digest: *const identity.Sha256Digest,
    manifest_digest: *const identity.Sha256Digest,
    shape: PayloadShape,
    count: u16,
) identity.Sha256Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.ordered-draft-schema.v1");
    hash.update(package_digest.asBytes());
    hash.update(manifest_digest.asBytes());
    hash.update(&.{@intFromEnum(shape)});
    updateU16(&hash, count);
    var result: identity.Sha256Digest = .{ .bytes = undefined };
    hash.final(&result.bytes);
    return result;
}

pub const SaveGateStatus = union(enum) {
    not_run,
    failed: validation.SaveRuleId,
    passed,
};

pub const FullValidationStatus = union(enum) {
    not_run,
    blocked: validation.ValidationBlock,
    failed: validation.FullRuleId,
    passed,
};

/// Value-free record of the exact save and full-validation entry points.
pub const ValidationStatus = struct {
    save_gate: SaveGateStatus = .not_run,
    full_validation: FullValidationStatus = .not_run,

    pub fn fromResults(
        save_result: ?validation.SaveValidationResult,
        full_result: ?validation.FullValidationResult,
    ) ValidationStatus {
        var result: ValidationStatus = .{};
        if (save_result) |save| {
            result.save_gate = switch (save) {
                .success => .passed,
                .failure => |failure| .{ .failed = failure.id },
            };
        }
        if (full_result) |full| {
            result.full_validation = switch (full) {
                .success => .passed,
                .blocked => |block| .{ .blocked = block },
                .failure => |failure| .{
                    .failed = failure.rule.id,
                },
            };
        }
        return result;
    }
};

pub const ArtifactRequest = enum {
    none,
    plaintext,
};

pub const PlaintextReceipt = struct {
    marker: document.Marker,
    byte_length: u32,
    sha256: identity.Sha256Digest,
};

/// `plaintext_candidate` is deliberate while the corresponding evidence
/// readiness facts are false. It must never be presented as exact-qualified.
pub const ArtifactStatus = union(enum) {
    not_generated,
    plaintext_candidate: PlaintextReceipt,
    plaintext_exact: PlaintextReceipt,

    pub fn receipt(self: *const ArtifactStatus) ?*const PlaintextReceipt {
        return switch (self.*) {
            .not_generated => null,
            .plaintext_candidate => |*value| value,
            .plaintext_exact => |*value| value,
        };
    }
};

/// Caller-owned input. `appendRevision` validates then deep-copies every
/// slice, so subsequent caller mutation cannot change a stored revision.
pub const OccurrenceValue = struct {
    ordinal: u16,
    serialized_key: []const u8,
    same_key_occurrence: u16,
    raw_value: []const u8,
    normalized_value: []const u8,
    emitted_value: []const u8,
};

pub const StoredOccurrenceValue = struct {
    ordinal: u16,
    serialized_key: []const u8,
    same_key_occurrence: u16,
    raw_value: []const u8,
    normalized_value: []const u8,
    emitted_value: []const u8,

    fn init(
        allocator: std.mem.Allocator,
        input: OccurrenceValue,
    ) std.mem.Allocator.Error!StoredOccurrenceValue {
        const key = try allocator.dupe(u8, input.serialized_key);
        errdefer secureFree(allocator, key);
        const raw = try allocator.dupe(u8, input.raw_value);
        errdefer secureFree(allocator, raw);
        const normalized = try allocator.dupe(u8, input.normalized_value);
        errdefer secureFree(allocator, normalized);
        const emitted = try allocator.dupe(u8, input.emitted_value);
        errdefer secureFree(allocator, emitted);
        return .{
            .ordinal = input.ordinal,
            .serialized_key = key,
            .same_key_occurrence = input.same_key_occurrence,
            .raw_value = raw,
            .normalized_value = normalized,
            .emitted_value = emitted,
        };
    }

    fn deinit(self: *StoredOccurrenceValue, allocator: std.mem.Allocator) void {
        secureFree(allocator, self.serialized_key);
        secureFree(allocator, self.raw_value);
        secureFree(allocator, self.normalized_value);
        secureFree(allocator, self.emitted_value);
        sensitive_memory.wipeValue(StoredOccurrenceValue, self);
    }
};

pub const RevisionInput = struct {
    package_key: identity.ExactFormPackageKey,
    payload_shape: PayloadShape,
    occurrence_manifest: occurrence.OrderedOccurrenceManifest,
    occurrences: []const OccurrenceValue,
    profile_snapshot_digest: identity.Sha256Digest,
    transaction_state_digest: identity.Sha256Digest,
    validation_status: ValidationStatus = .{},
    artifact_request: ArtifactRequest = .none,
};

/// Untrusted persisted representation presented for replay. `DraftHistory`
/// never adopts these buffers or struct fields directly: replay runs the same
/// schema, ordering, render/parse, validation, artifact-authorization, and
/// digest path as a newly appended revision, then compares every persisted
/// field before committing the in-memory history mutation.
pub const ReplayRevisionInput = struct {
    draft_identity: DraftIdentity,
    revision: DraftRevision,
    parent_revision: ?DraftRevision,
    schema: SchemaBinding,
    occurrences: []const OccurrenceValue,
    profile_snapshot_digest: identity.Sha256Digest,
    transaction_state_digest: identity.Sha256Digest,
    ordered_values_digest: identity.Sha256Digest,
    validation_status: ValidationStatus,
    artifact_status: ArtifactStatus,
};

pub const SnapshotRenderError =
    document.RenderError ||
    error{ArtifactNotGenerated};

pub const DraftSnapshot = struct {
    const Self = @This();

    draft_identity: DraftIdentity,
    revision: DraftRevision,
    parent_revision: ?DraftRevision,
    schema: SchemaBinding,
    occurrences: []const StoredOccurrenceValue,
    profile_snapshot_digest: identity.Sha256Digest,
    transaction_state_digest: identity.Sha256Digest,
    ordered_values_digest: identity.Sha256Digest,
    validation_status: ValidationStatus,
    artifact_status: ArtifactStatus,

    pub fn occurrenceAt(
        self: *const Self,
        zero_based_index: usize,
    ) ?*const StoredOccurrenceValue {
        if (zero_based_index >= self.occurrences.len) return null;
        return &self.occurrences[zero_based_index];
    }

    /// Returns newly allocated plaintext only for a revision whose artifact
    /// transition was authorized and recorded. No bytes are persisted here.
    pub fn renderReadyPlaintextAlloc(
        self: *const Self,
        allocator: std.mem.Allocator,
    ) SnapshotRenderError![]u8 {
        if (self.artifact_status.receipt() == null) {
            return error.ArtifactNotGenerated;
        }
        return renderOwnedAlloc(
            allocator,
            self.occurrences,
            self.schema.payload_shape.marker(),
        );
    }

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        const mutable = @constCast(self.occurrences);
        for (mutable) |*item| item.deinit(allocator);
        sensitive_memory.wipeAndFreeDefaultAligned(
            StoredOccurrenceValue,
            allocator,
            mutable,
        );
        sensitive_memory.wipeValue(Self, self);
    }
};

pub const DraftError =
    std.mem.Allocator.Error ||
    CandidateSchemaError ||
    document.ParseError ||
    document.RenderError ||
    document.ExactShapeError ||
    error{
        DraftAlreadyExists,
        StaleRevision,
        RevisionOverflow,
        OccurrenceCountMismatch,
        OccurrenceOrdinalMismatch,
        OccurrenceKeyMismatch,
        OccurrenceSameKeyMismatch,
        RawValueTooLong,
        NormalizedValueTooLong,
        InvalidRawUtf8,
        InvalidNormalizedUtf8,
        DraftValuesTooLarge,
        DraftRevisionLimitExceeded,
        DraftRetainedValueLimitExceeded,
        ArtifactNotAuthorized,
        RoundTripOrderMismatch,
        RoundTripKeyMismatch,
        RoundTripRepeatedKeyMismatch,
        RoundTripValueMismatch,
        RoundTripByteMismatch,
        ReplayIdentityMismatch,
        ReplayRevisionMismatch,
        ReplayParentMismatch,
        ReplaySchemaMismatch,
        ReplayProfileDigestMismatch,
        ReplayTransactionDigestMismatch,
        ReplayOrderedValuesDigestMismatch,
        ReplayValidationStatusMismatch,
        ReplayArtifactStatusMismatch,
        ReplayOccurrenceMismatch,
    };

pub const DraftHistory = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    identity: DraftIdentity,
    schema: SchemaBinding,
    snapshots: std.ArrayList(*DraftSnapshot) = .empty,
    limits: HistoryLimits = exact_history_limits,
    retained_value_bytes: usize = 0,

    pub fn initExact1701Q(
        allocator: std.mem.Allocator,
        workspace_id: DraftWorkspaceId,
        shape: PayloadShape,
    ) SchemaError!Self {
        return initBound(
            allocator,
            workspace_id,
            try SchemaBinding.exact1701Q(shape),
        );
    }

    fn initBound(
        allocator: std.mem.Allocator,
        workspace_id: DraftWorkspaceId,
        schema: SchemaBinding,
    ) Self {
        return initBoundWithLimits(
            allocator,
            workspace_id,
            schema,
            exact_history_limits,
        );
    }

    fn initBoundWithLimits(
        allocator: std.mem.Allocator,
        workspace_id: DraftWorkspaceId,
        schema: SchemaBinding,
        limits: HistoryLimits,
    ) Self {
        return .{
            .allocator = allocator,
            .identity = .{
                .workspace_id = workspace_id,
                .exact_schema_digest = schema.exact_schema_digest,
            },
            .schema = schema,
            .limits = limits,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.snapshots.items) |stored_snapshot| {
            self.releaseRetainedValueBytes(stored_snapshot.occurrences);
            stored_snapshot.deinit(self.allocator);
            sensitive_memory.wipeAndDestroyDefaultAligned(
                DraftSnapshot,
                self.allocator,
                stored_snapshot,
            );
        }
        std.debug.assert(self.retained_value_bytes == 0);
        self.snapshots.deinit(self.allocator);
        sensitive_memory.wipeValue(Self, self);
    }

    pub fn revisionCount(self: *const Self) usize {
        return self.snapshots.items.len;
    }

    pub fn retainedValueBytes(self: *const Self) usize {
        return self.retained_value_bytes;
    }

    pub fn current(self: *const Self) ?*const DraftSnapshot {
        if (self.snapshots.items.len == 0) return null;
        return self.snapshots.items[self.snapshots.items.len - 1];
    }

    pub fn snapshot(
        self: *const Self,
        revision: DraftRevision,
    ) ?*const DraftSnapshot {
        if (revision.value == 0 or
            revision.value > @as(u64, @intCast(self.snapshots.items.len)))
        {
            return null;
        }
        const index: usize = @intCast(revision.value - 1);
        const result = self.snapshots.items[index];
        if (!result.revision.eql(revision)) return null;
        return result;
    }

    pub fn appendRevision(
        self: *Self,
        guard: RevisionGuard,
        input: RevisionInput,
    ) DraftError!*const DraftSnapshot {
        try self.verifyRevisionGuard(guard);
        // Byte-identical revisions may be distinct, intentional audited save
        // events. Preserve them; explicit count and byte ceilings are the
        // safe cardinality invariant rather than guessing caller intent.
        const revision_limit = @min(
            self.limits.max_revisions,
            max_revisions_per_exact_shape_stream,
        );
        if (self.snapshots.items.len >= revision_limit) {
            return error.DraftRevisionLimitExceeded;
        }
        const retained_value_bytes = try self.checkedRetainedValueBytes();
        const checked_manifest = try self.schema.verifyCandidate(
            &input.package_key,
            input.payload_shape,
            input.occurrence_manifest,
        );
        const added_value_bytes = try validateOrderedValues(
            checked_manifest,
            input.occurrences,
        );
        const next_retained_value_bytes = std.math.add(
            usize,
            retained_value_bytes,
            added_value_bytes,
        ) catch return error.DraftRetainedValueLimitExceeded;
        const retained_value_limit = @min(
            self.limits.max_retained_value_bytes,
            max_retained_exact_value_bytes,
        );
        if (next_retained_value_bytes >
            retained_value_limit)
        {
            return error.DraftRetainedValueLimitExceeded;
        }

        // Always prove the current ASCII document layer can render, parse,
        // and reconstruct the ordered emitted values losslessly. The bytes
        // remain transient unless the caller explicitly requests a receipt.
        const plaintext = try renderAndVerifyAlloc(
            self.allocator,
            checked_manifest,
            input.occurrences,
            input.payload_shape.marker(),
        );
        defer secureFree(self.allocator, plaintext);

        var artifact_status: ArtifactStatus = .not_generated;
        if (input.artifact_request == .plaintext) {
            if (!artifactAuthorized(
                input.payload_shape,
                input.validation_status,
            )) {
                return error.ArtifactNotAuthorized;
            }
            const receipt: PlaintextReceipt = .{
                .marker = input.payload_shape.marker(),
                .byte_length = @intCast(plaintext.len),
                .sha256 = digestBytes(plaintext),
            };
            artifact_status = if (self.schema.plaintextIsExact())
                .{ .plaintext_exact = receipt }
            else
                .{ .plaintext_candidate = receipt };
        }

        const next_value = std.math.add(
            u64,
            @as(u64, @intCast(self.snapshots.items.len)),
            1,
        ) catch return error.RevisionOverflow;
        const next_revision = DraftRevision.init(next_value) catch
            return error.RevisionOverflow;
        const parent_revision = if (self.current()) |current_snapshot|
            current_snapshot.revision
        else
            null;

        const owned_values = try cloneValues(
            self.allocator,
            input.occurrences,
        );
        errdefer destroyValues(self.allocator, owned_values);

        const candidate = try self.allocator.create(DraftSnapshot);
        errdefer sensitive_memory.wipeAndDestroyDefaultAligned(
            DraftSnapshot,
            self.allocator,
            candidate,
        );
        candidate.* = .{
            .draft_identity = self.identity,
            .revision = next_revision,
            .parent_revision = parent_revision,
            .schema = self.schema,
            .occurrences = owned_values,
            .profile_snapshot_digest = input.profile_snapshot_digest,
            .transaction_state_digest = input.transaction_state_digest,
            .ordered_values_digest = orderedValuesDigest(input.occurrences),
            .validation_status = input.validation_status,
            .artifact_status = artifact_status,
        };
        try self.snapshots.append(self.allocator, candidate);
        self.retained_value_bytes = next_retained_value_bytes;
        return candidate;
    }

    /// Replays one untrusted persisted revision through `appendRevision`.
    /// Any mismatch discards and securely destroys the just-appended
    /// candidate, leaving the prior history byte-for-byte intact.
    pub fn replayPersistedRevision(
        self: *Self,
        persisted: ReplayRevisionInput,
    ) DraftError!*const DraftSnapshot {
        if (!self.identity.eql(&persisted.draft_identity)) {
            return error.ReplayIdentityMismatch;
        }
        if (!self.schema.exact_schema_digest.eql(
            &persisted.schema.exact_schema_digest,
        )) {
            return error.ReplaySchemaMismatch;
        }

        const expected_next: u64 = std.math.add(
            u64,
            @as(u64, @intCast(self.snapshots.items.len)),
            1,
        ) catch return error.RevisionOverflow;
        if (persisted.revision.value != expected_next) {
            return error.ReplayRevisionMismatch;
        }
        const expected_parent = if (self.current()) |latest|
            latest.revision
        else
            null;
        if (!optionalRevisionEql(
            expected_parent,
            persisted.parent_revision,
        )) {
            return error.ReplayParentMismatch;
        }

        const manifest = try exactManifest(persisted.schema.payload_shape);
        const guard: RevisionGuard = if (expected_parent) |parent|
            .{ .match = parent }
        else
            .create;
        const replayed = try self.appendRevision(guard, .{
            .package_key = persisted.schema.package_key,
            .payload_shape = persisted.schema.payload_shape,
            .occurrence_manifest = manifest,
            .occurrences = persisted.occurrences,
            .profile_snapshot_digest = persisted.profile_snapshot_digest,
            .transaction_state_digest = persisted.transaction_state_digest,
            .validation_status = persisted.validation_status,
            .artifact_request = if (persisted.artifact_status.receipt() == null)
                .none
            else
                .plaintext,
        });
        errdefer self.discardCurrentReplayCandidate();

        if (!schemaBindingEql(&replayed.schema, &persisted.schema)) {
            return error.ReplaySchemaMismatch;
        }
        if (!replayed.profile_snapshot_digest.eql(
            &persisted.profile_snapshot_digest,
        )) {
            return error.ReplayProfileDigestMismatch;
        }
        if (!replayed.transaction_state_digest.eql(
            &persisted.transaction_state_digest,
        )) {
            return error.ReplayTransactionDigestMismatch;
        }
        if (!replayed.ordered_values_digest.eql(
            &persisted.ordered_values_digest,
        )) {
            return error.ReplayOrderedValuesDigestMismatch;
        }
        if (!std.meta.eql(
            replayed.validation_status,
            persisted.validation_status,
        )) {
            return error.ReplayValidationStatusMismatch;
        }
        if (!std.meta.eql(
            replayed.artifact_status,
            persisted.artifact_status,
        )) {
            return error.ReplayArtifactStatusMismatch;
        }
        if (!storedOccurrencesMatchInput(
            replayed.occurrences,
            persisted.occurrences,
        )) {
            return error.ReplayOccurrenceMismatch;
        }
        return replayed;
    }

    fn discardCurrentReplayCandidate(self: *Self) void {
        std.debug.assert(self.snapshots.items.len != 0);
        const index = self.snapshots.items.len - 1;
        const candidate = self.snapshots.items[index];
        self.snapshots.items.len = index;
        self.releaseRetainedValueBytes(candidate.occurrences);
        candidate.deinit(self.allocator);
        sensitive_memory.wipeAndDestroyDefaultAligned(
            DraftSnapshot,
            self.allocator,
            candidate,
        );
    }

    fn releaseRetainedValueBytes(
        self: *Self,
        values: []const StoredOccurrenceValue,
    ) void {
        const released = storedRetainedValueBytes(values) orelse
            unreachable;
        std.debug.assert(released <= self.retained_value_bytes);
        self.retained_value_bytes -= released;
    }

    fn checkedRetainedValueBytes(self: *const Self) DraftError!usize {
        var computed: usize = 0;
        for (self.snapshots.items) |snapshot_value| {
            const snapshot_bytes = storedRetainedValueBytes(
                snapshot_value.occurrences,
            ) orelse return error.DraftRetainedValueLimitExceeded;
            computed = std.math.add(
                usize,
                computed,
                snapshot_bytes,
            ) catch return error.DraftRetainedValueLimitExceeded;
            if (computed > max_retained_exact_value_bytes) {
                return error.DraftRetainedValueLimitExceeded;
            }
        }
        if (computed != self.retained_value_bytes) {
            return error.DraftRetainedValueLimitExceeded;
        }
        return computed;
    }

    fn verifyRevisionGuard(
        self: *const Self,
        guard: RevisionGuard,
    ) error{ DraftAlreadyExists, StaleRevision }!void {
        const current_snapshot = self.current();
        switch (guard) {
            .create => {
                if (current_snapshot != null) {
                    return error.DraftAlreadyExists;
                }
            },
            .match => |expected| {
                const current_revision = if (current_snapshot) |value|
                    value.revision
                else
                    return error.StaleRevision;
                if (!current_revision.eql(expected)) {
                    return error.StaleRevision;
                }
            },
        }
    }
};

fn optionalRevisionEql(
    left: ?DraftRevision,
    right: ?DraftRevision,
) bool {
    if (left == null or right == null) return left == null and right == null;
    return left.?.eql(right.?);
}

fn schemaBindingEql(
    left: *const SchemaBinding,
    right: *const SchemaBinding,
) bool {
    return left.package_key.eql(&right.package_key) and
        left.package_digest.eql(&right.package_digest) and
        left.occurrence_manifest_digest.eql(
            &right.occurrence_manifest_digest,
        ) and
        left.exact_schema_digest.eql(&right.exact_schema_digest) and
        left.payload_shape == right.payload_shape and
        left.occurrence_count == right.occurrence_count and
        std.meta.eql(
            left.evidence_readiness,
            right.evidence_readiness,
        );
}

fn storedOccurrencesMatchInput(
    stored: []const StoredOccurrenceValue,
    input: []const OccurrenceValue,
) bool {
    if (stored.len != input.len) return false;
    for (stored, input) |left, right| {
        if (left.ordinal != right.ordinal or
            left.same_key_occurrence != right.same_key_occurrence or
            !std.mem.eql(
                u8,
                left.serialized_key,
                right.serialized_key,
            ) or
            !std.mem.eql(u8, left.raw_value, right.raw_value) or
            !std.mem.eql(
                u8,
                left.normalized_value,
                right.normalized_value,
            ) or
            !std.mem.eql(
                u8,
                left.emitted_value,
                right.emitted_value,
            ))
        {
            return false;
        }
    }
    return true;
}

fn validateOrderedValues(
    manifest: occurrence.OrderedOccurrenceManifest,
    values: []const OccurrenceValue,
) DraftError!usize {
    if (values.len != manifest.items.len) {
        return error.OccurrenceCountMismatch;
    }
    var total_value_bytes: usize = 0;
    for (manifest.items, values) |metadata, value| {
        if (value.ordinal != metadata.ordinal) {
            return error.OccurrenceOrdinalMismatch;
        }
        if (!std.mem.eql(
            u8,
            value.serialized_key,
            metadata.serialized_key,
        )) {
            return error.OccurrenceKeyMismatch;
        }
        if (value.same_key_occurrence != metadata.same_key_occurrence) {
            return error.OccurrenceSameKeyMismatch;
        }
        if (value.raw_value.len > document.max_value_bytes) {
            return error.RawValueTooLong;
        }
        if (value.normalized_value.len > document.max_value_bytes) {
            return error.NormalizedValueTooLong;
        }
        if (!std.unicode.utf8ValidateSlice(value.raw_value)) {
            return error.InvalidRawUtf8;
        }
        if (!std.unicode.utf8ValidateSlice(value.normalized_value)) {
            return error.InvalidNormalizedUtf8;
        }
        total_value_bytes = std.math.add(
            usize,
            total_value_bytes,
            value.raw_value.len,
        ) catch return error.DraftValuesTooLarge;
        total_value_bytes = std.math.add(
            usize,
            total_value_bytes,
            value.normalized_value.len,
        ) catch return error.DraftValuesTooLarge;
        total_value_bytes = std.math.add(
            usize,
            total_value_bytes,
            value.emitted_value.len,
        ) catch return error.DraftValuesTooLarge;
        if (total_value_bytes > max_total_draft_value_bytes) {
            return error.DraftValuesTooLarge;
        }
    }
    return total_value_bytes;
}

fn storedRetainedValueBytes(
    values: []const StoredOccurrenceValue,
) ?usize {
    var total: usize = 0;
    for (values) |value| {
        total = std.math.add(usize, total, value.raw_value.len) catch
            return null;
        total = std.math.add(
            usize,
            total,
            value.normalized_value.len,
        ) catch return null;
        total = std.math.add(usize, total, value.emitted_value.len) catch
            return null;
    }
    return total;
}

fn artifactAuthorized(
    shape: PayloadShape,
    status: ValidationStatus,
) bool {
    const save_passed = switch (status.save_gate) {
        .passed => true,
        .not_run, .failed => false,
    };
    if (!save_passed) return false;
    if (shape == .editable_save) return true;
    return switch (status.full_validation) {
        .passed => true,
        .not_run, .blocked, .failed => false,
    };
}

fn renderAndVerifyAlloc(
    allocator: std.mem.Allocator,
    manifest: occurrence.OrderedOccurrenceManifest,
    values: []const OccurrenceValue,
    marker: document.Marker,
) DraftError![]u8 {
    const views = try allocator.alloc(document.Occurrence, values.len);
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        document.Occurrence,
        allocator,
        views,
    );
    const expected_keys = try allocator.alloc([]const u8, values.len);
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        []const u8,
        allocator,
        expected_keys,
    );
    for (values, 0..) |value, index| {
        views[index] = .{
            .key = value.serialized_key,
            .encoded_value = value.emitted_value,
        };
        expected_keys[index] = manifest.items[index].serialized_key;
    }

    const plaintext = try document.renderOccurrencesAlloc(
        allocator,
        views,
        marker,
    );
    errdefer secureFree(allocator, plaintext);
    var parsed = try document.parse(allocator, plaintext);
    defer {
        @memset(parsed.source, 0);
        parsed.deinit(allocator);
    }
    try parsed.validateExactKeys(expected_keys, marker);

    for (parsed.occurrences, values) |parsed_value, value| {
        if (parsed_value.source_order + 1 != value.ordinal) {
            return error.RoundTripOrderMismatch;
        }
        if (!std.mem.eql(u8, parsed_value.key, value.serialized_key)) {
            return error.RoundTripKeyMismatch;
        }
        if (parsed_value.same_key_occurrence !=
            value.same_key_occurrence)
        {
            return error.RoundTripRepeatedKeyMismatch;
        }
        if (!std.mem.eql(
            u8,
            parsed_value.encoded_value,
            value.emitted_value,
        )) {
            return error.RoundTripValueMismatch;
        }
    }

    const reconstructed = try parsed.renderAlloc(allocator);
    defer secureFree(allocator, reconstructed);
    if (!std.mem.eql(u8, plaintext, reconstructed)) {
        return error.RoundTripByteMismatch;
    }
    return plaintext;
}

fn renderOwnedAlloc(
    allocator: std.mem.Allocator,
    values: []const StoredOccurrenceValue,
    marker: document.Marker,
) document.RenderError![]u8 {
    const views = try allocator.alloc(document.Occurrence, values.len);
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        document.Occurrence,
        allocator,
        views,
    );
    for (values, 0..) |value, index| {
        views[index] = .{
            .key = value.serialized_key,
            .encoded_value = value.emitted_value,
        };
    }
    return document.renderOccurrencesAlloc(allocator, views, marker);
}

fn cloneValues(
    allocator: std.mem.Allocator,
    values: []const OccurrenceValue,
) std.mem.Allocator.Error![]StoredOccurrenceValue {
    const result = try allocator.alloc(StoredOccurrenceValue, values.len);
    var initialized: usize = 0;
    errdefer {
        for (result[0..initialized]) |*item| item.deinit(allocator);
        sensitive_memory.wipeAndFreeDefaultAligned(
            StoredOccurrenceValue,
            allocator,
            result,
        );
    }
    for (values, 0..) |value, index| {
        result[index] = try StoredOccurrenceValue.init(allocator, value);
        initialized += 1;
    }
    return result;
}

fn destroyValues(
    allocator: std.mem.Allocator,
    values: []StoredOccurrenceValue,
) void {
    for (values) |*item| item.deinit(allocator);
    sensitive_memory.wipeAndFreeDefaultAligned(
        StoredOccurrenceValue,
        allocator,
        values,
    );
}

fn orderedValuesDigest(
    values: []const OccurrenceValue,
) identity.Sha256Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.ordered-draft-values.v1");
    updateU32(&hash, @intCast(values.len));
    for (values) |value| {
        updateU16(&hash, value.ordinal);
        updateLengthPrefixed(&hash, value.serialized_key);
        updateU16(&hash, value.same_key_occurrence);
        updateLengthPrefixed(&hash, value.raw_value);
        updateLengthPrefixed(&hash, value.normalized_value);
        updateLengthPrefixed(&hash, value.emitted_value);
    }
    var result: identity.Sha256Digest = .{ .bytes = undefined };
    hash.final(&result.bytes);
    return result;
}

fn digestBytes(bytes: []const u8) identity.Sha256Digest {
    var result: identity.Sha256Digest = .{ .bytes = undefined };
    std.crypto.hash.sha2.Sha256.hash(bytes, &result.bytes, .{});
    return result;
}

fn updateLengthPrefixed(
    hash: *std.crypto.hash.sha2.Sha256,
    bytes: []const u8,
) void {
    std.debug.assert(bytes.len <= std.math.maxInt(u32));
    updateU32(hash, @intCast(bytes.len));
    hash.update(bytes);
}

fn updateU16(hash: *std.crypto.hash.sha2.Sha256, value: u16) void {
    hash.update(&.{
        @intCast(value >> 8),
        @intCast(value & 0xff),
    });
}

fn updateU32(hash: *std.crypto.hash.sha2.Sha256, value: u32) void {
    hash.update(&.{
        @intCast(value >> 24),
        @intCast((value >> 16) & 0xff),
        @intCast((value >> 8) & 0xff),
        @intCast(value & 0xff),
    });
}

fn secureFree(allocator: std.mem.Allocator, bytes: []const u8) void {
    sensitive_memory.wipeAndFreeConstDefaultAligned(
        u8,
        allocator,
        bytes,
    );
}

const duplicate_manifest_items = [_]occurrence.OccurrenceMetadata{
    .{
        .ordinal = 1,
        .canonical_field = .{
            .unreviewed_source_control = "test-first",
        },
        .serialized_key = "repeated",
        .same_key_occurrence = 1,
        .source_controls = .{ .one = "test-first" },
        .source_control_first_line = 1,
        .source_control_last_line = 1,
        .origin = .unreviewed,
        .inclusion = .{ .editable_save = true },
        .emission = .raw,
        .evidence = .{
            .evidence_id = "synthetic-value-safe-test",
            .first_line = 1,
            .last_line = 1,
        },
    },
    .{
        .ordinal = 2,
        .canonical_field = .{
            .unreviewed_source_control = "test-middle",
        },
        .serialized_key = "middle",
        .same_key_occurrence = 1,
        .source_controls = .{ .one = "test-middle" },
        .source_control_first_line = 2,
        .source_control_last_line = 2,
        .origin = .unreviewed,
        .inclusion = .{ .editable_save = true },
        .emission = .raw,
        .evidence = .{
            .evidence_id = "synthetic-value-safe-test",
            .first_line = 2,
            .last_line = 2,
        },
    },
    .{
        .ordinal = 3,
        .canonical_field = .{
            .unreviewed_source_control = "test-second",
        },
        .serialized_key = "repeated",
        .same_key_occurrence = 2,
        .source_controls = .{ .one = "test-second" },
        .source_control_first_line = 3,
        .source_control_last_line = 3,
        .origin = .unreviewed,
        .inclusion = .{ .editable_save = true },
        .emission = .raw,
        .evidence = .{
            .evidence_id = "synthetic-value-safe-test",
            .first_line = 3,
            .last_line = 3,
        },
    },
};

const test_profile_digest = identity.Sha256Digest.initComptime(
    "1111111111111111111111111111111111111111111111111111111111111111",
);
const test_transaction_digest = identity.Sha256Digest.initComptime(
    "2222222222222222222222222222222222222222222222222222222222222222",
);

fn testWorkspace(last_byte: u8) !DraftWorkspaceId {
    var bytes = [_]u8{0} ** 16;
    bytes[15] = last_byte;
    return DraftWorkspaceId.init(bytes);
}

fn testSchema(
    shape: PayloadShape,
    manifest: occurrence.OrderedOccurrenceManifest,
) !SchemaBinding {
    return SchemaBinding.bind(
        form_evidence.package_key,
        shape,
        manifest,
        form_evidence.readiness,
    );
}

fn exerciseDraftAllocationPaths(
    allocator: std.mem.Allocator,
) !void {
    const manifest = try occurrence.OrderedOccurrenceManifest.init(
        &duplicate_manifest_items,
    );
    var history = DraftHistory.initBound(
        allocator,
        try testWorkspace(0xf0),
        try testSchema(.editable_save, manifest),
    );
    defer history.deinit();
    const values = [_]OccurrenceValue{
        .{
            .ordinal = 1,
            .serialized_key = "repeated",
            .same_key_occurrence = 1,
            .raw_value = "first raw sensitive value",
            .normalized_value = "first normalized sensitive value",
            .emitted_value = "first emitted sensitive value",
        },
        .{
            .ordinal = 2,
            .serialized_key = "middle",
            .same_key_occurrence = 1,
            .raw_value = "middle raw sensitive value",
            .normalized_value = "middle normalized sensitive value",
            .emitted_value = "middle emitted sensitive value",
        },
        .{
            .ordinal = 3,
            .serialized_key = "repeated",
            .same_key_occurrence = 2,
            .raw_value = "second raw sensitive value",
            .normalized_value = "second normalized sensitive value",
            .emitted_value = "second emitted sensitive value",
        },
    };
    const snapshot = try history.appendRevision(.create, .{
        .package_key = form_evidence.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = manifest,
        .occurrences = &values,
        .profile_snapshot_digest = test_profile_digest,
        .transaction_state_digest = test_transaction_digest,
        .validation_status = .{ .save_gate = .passed },
        .artifact_request = .plaintext,
    });
    const plaintext = try snapshot.renderReadyPlaintextAlloc(allocator);
    defer secureFree(allocator, plaintext);
    try std.testing.expect(std.mem.indexOf(
        u8,
        plaintext,
        "second emitted sensitive value",
    ) != null);
}

test "all draft allocation failures erase and release partial values" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exerciseDraftAllocationPaths,
        .{},
    );
}

test "append-only revisions preserve duplicate keys order and old values" {
    const manifest = try occurrence.OrderedOccurrenceManifest.init(
        &duplicate_manifest_items,
    );
    var history = DraftHistory.initBound(
        std.testing.allocator,
        try testWorkspace(1),
        try testSchema(.editable_save, manifest),
    );
    defer history.deinit();

    const first_values = [_]OccurrenceValue{
        .{
            .ordinal = 1,
            .serialized_key = "repeated",
            .same_key_occurrence = 1,
            .raw_value = "first raw",
            .normalized_value = "first normalized",
            .emitted_value = "first",
        },
        .{
            .ordinal = 2,
            .serialized_key = "middle",
            .same_key_occurrence = 1,
            .raw_value = "middle",
            .normalized_value = "middle",
            .emitted_value = "middle",
        },
        .{
            .ordinal = 3,
            .serialized_key = "repeated",
            .same_key_occurrence = 2,
            .raw_value = "second raw",
            .normalized_value = "second normalized",
            .emitted_value = "second",
        },
    };
    const passed: ValidationStatus = .{
        .save_gate = .passed,
        .full_validation = .passed,
    };
    const first = try history.appendRevision(.create, .{
        .package_key = form_evidence.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = manifest,
        .occurrences = &first_values,
        .profile_snapshot_digest = test_profile_digest,
        .transaction_state_digest = test_transaction_digest,
        .validation_status = passed,
        .artifact_request = .plaintext,
    });
    try std.testing.expectEqual(@as(u64, 1), first.revision.value);
    try std.testing.expectEqual(@as(usize, 3), first.occurrences.len);
    try std.testing.expectEqualStrings(
        "second",
        first.occurrenceAt(2).?.emitted_value,
    );
    try std.testing.expect(
        std.meta.activeTag(first.artifact_status) == .plaintext_candidate,
    );

    const plaintext = try first.renderReadyPlaintextAlloc(
        std.testing.allocator,
    );
    defer secureFree(std.testing.allocator, plaintext);
    var parsed = try document.parse(std.testing.allocator, plaintext);
    defer {
        @memset(parsed.source, 0);
        parsed.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(usize, 3), parsed.occurrences.len);
    try std.testing.expectEqual(
        @as(u16, 2),
        parsed.occurrences[2].same_key_occurrence,
    );
    try std.testing.expectEqualStrings(
        "second",
        parsed.occurrences[2].encoded_value,
    );

    var second_values = first_values;
    second_values[0].emitted_value = "changed";
    const second = try history.appendRevision(.{
        .match = first.revision,
    }, .{
        .package_key = form_evidence.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = manifest,
        .occurrences = &second_values,
        .profile_snapshot_digest = test_profile_digest,
        .transaction_state_digest = test_transaction_digest,
        .validation_status = passed,
    });
    try std.testing.expectEqual(@as(u64, 2), second.revision.value);
    try std.testing.expectEqualStrings(
        "first",
        first.occurrenceAt(0).?.emitted_value,
    );
    try std.testing.expectEqualStrings(
        "changed",
        second.occurrenceAt(0).?.emitted_value,
    );
    try std.testing.expectEqual(@as(usize, 2), history.revisionCount());

    try std.testing.expectError(
        error.StaleRevision,
        history.appendRevision(.{ .match = first.revision }, .{
            .package_key = form_evidence.package_key,
            .payload_shape = .editable_save,
            .occurrence_manifest = manifest,
            .occurrences = &second_values,
            .profile_snapshot_digest = test_profile_digest,
            .transaction_state_digest = test_transaction_digest,
        }),
    );
    try std.testing.expectEqual(@as(usize, 2), history.revisionCount());
}

test "history count and retained-byte boundaries preserve audited saves" {
    const manifest = try occurrence.OrderedOccurrenceManifest.init(
        &duplicate_manifest_items,
    );
    const values = [_]OccurrenceValue{
        .{
            .ordinal = 1,
            .serialized_key = "repeated",
            .same_key_occurrence = 1,
            .raw_value = "raw-one",
            .normalized_value = "normalized-one",
            .emitted_value = "emitted-one",
        },
        .{
            .ordinal = 2,
            .serialized_key = "middle",
            .same_key_occurrence = 1,
            .raw_value = "raw-two",
            .normalized_value = "normalized-two",
            .emitted_value = "emitted-two",
        },
        .{
            .ordinal = 3,
            .serialized_key = "repeated",
            .same_key_occurrence = 2,
            .raw_value = "raw-three",
            .normalized_value = "normalized-three",
            .emitted_value = "emitted-three",
        },
    };
    const one_revision_bytes = try validateOrderedValues(manifest, &values);

    var count_limited = DraftHistory.initBoundWithLimits(
        std.testing.allocator,
        try testWorkspace(6),
        try testSchema(.editable_save, manifest),
        .{
            .max_revisions = 2,
            .max_retained_value_bytes = one_revision_bytes * 2,
        },
    );
    defer count_limited.deinit();
    const first = try count_limited.appendRevision(.create, .{
        .package_key = form_evidence.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = manifest,
        .occurrences = &values,
        .profile_snapshot_digest = test_profile_digest,
        .transaction_state_digest = test_transaction_digest,
    });
    const second = try count_limited.appendRevision(
        .{ .match = first.revision },
        .{
            .package_key = form_evidence.package_key,
            .payload_shape = .editable_save,
            .occurrence_manifest = manifest,
            .occurrences = &values,
            .profile_snapshot_digest = test_profile_digest,
            .transaction_state_digest = test_transaction_digest,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), count_limited.revisionCount());
    try std.testing.expectEqual(
        one_revision_bytes * 2,
        count_limited.retainedValueBytes(),
    );
    try std.testing.expectError(
        error.DraftRevisionLimitExceeded,
        count_limited.appendRevision(
            .{ .match = second.revision },
            .{
                .package_key = form_evidence.package_key,
                .payload_shape = .editable_save,
                .occurrence_manifest = manifest,
                .occurrences = &values,
                .profile_snapshot_digest = test_profile_digest,
                .transaction_state_digest = test_transaction_digest,
            },
        ),
    );
    try std.testing.expectEqual(@as(usize, 2), count_limited.revisionCount());
    try std.testing.expectEqual(
        one_revision_bytes * 2,
        count_limited.retainedValueBytes(),
    );

    var byte_limited = DraftHistory.initBoundWithLimits(
        std.testing.allocator,
        try testWorkspace(7),
        try testSchema(.editable_save, manifest),
        .{
            .max_revisions = 3,
            .max_retained_value_bytes = one_revision_bytes,
        },
    );
    defer byte_limited.deinit();
    const byte_first = try byte_limited.appendRevision(.create, .{
        .package_key = form_evidence.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = manifest,
        .occurrences = &values,
        .profile_snapshot_digest = test_profile_digest,
        .transaction_state_digest = test_transaction_digest,
    });
    try std.testing.expectEqual(
        one_revision_bytes,
        byte_limited.retainedValueBytes(),
    );
    try std.testing.expectError(
        error.DraftRetainedValueLimitExceeded,
        byte_limited.appendRevision(
            .{ .match = byte_first.revision },
            .{
                .package_key = form_evidence.package_key,
                .payload_shape = .editable_save,
                .occurrence_manifest = manifest,
                .occurrences = &values,
                .profile_snapshot_digest = test_profile_digest,
                .transaction_state_digest = test_transaction_digest,
            },
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), byte_limited.revisionCount());
    try std.testing.expectEqual(
        one_revision_bytes,
        byte_limited.retainedValueBytes(),
    );
}

test "zero retained-byte cap rejects both exact shapes before allocation" {
    const shapes = [_]PayloadShape{
        .editable_save,
        .final_copy_plaintext,
    };
    for (shapes, 0..) |shape, index| {
        const manifest = try exactManifest(shape);
        var value_storage: [form_occurrences.control_seeds.len]OccurrenceValue =
            undefined;
        for (manifest.items, 0..) |metadata, value_index| {
            value_storage[value_index] = .{
                .ordinal = metadata.ordinal,
                .serialized_key = metadata.serialized_key,
                .same_key_occurrence = metadata.same_key_occurrence,
                .raw_value = "",
                .normalized_value = "",
                .emitted_value = if (value_index == 0) "x" else "",
            };
        }
        var no_backing: [0]u8 = .{};
        var fixed = std.heap.FixedBufferAllocator.init(&no_backing);
        var history = DraftHistory.initBoundWithLimits(
            fixed.allocator(),
            try testWorkspace(@intCast(8 + index)),
            try SchemaBinding.exact1701Q(shape),
            .{
                .max_revisions = 1,
                .max_retained_value_bytes = 0,
            },
        );
        defer history.deinit();
        try std.testing.expectError(
            error.DraftRetainedValueLimitExceeded,
            history.appendRevision(.create, .{
                .package_key = form_evidence.package_key,
                .payload_shape = shape,
                .occurrence_manifest = manifest,
                .occurrences = value_storage[0..manifest.items.len],
                .profile_snapshot_digest = test_profile_digest,
                .transaction_state_digest = test_transaction_digest,
            }),
        );
        try std.testing.expectEqual(@as(usize, 0), history.revisionCount());
        try std.testing.expectEqual(
            @as(usize, 0),
            history.retainedValueBytes(),
        );
    }
}

test "wrong occurrence order and repeated-key index fail closed" {
    const manifest = try occurrence.OrderedOccurrenceManifest.init(
        &duplicate_manifest_items,
    );
    var history = DraftHistory.initBound(
        std.testing.allocator,
        try testWorkspace(2),
        try testSchema(.editable_save, manifest),
    );
    defer history.deinit();

    var values = [_]OccurrenceValue{
        .{
            .ordinal = 1,
            .serialized_key = "repeated",
            .same_key_occurrence = 1,
            .raw_value = "",
            .normalized_value = "",
            .emitted_value = "one",
        },
        .{
            .ordinal = 2,
            .serialized_key = "middle",
            .same_key_occurrence = 1,
            .raw_value = "",
            .normalized_value = "",
            .emitted_value = "middle",
        },
        .{
            .ordinal = 3,
            .serialized_key = "repeated",
            .same_key_occurrence = 2,
            .raw_value = "",
            .normalized_value = "",
            .emitted_value = "two",
        },
    };
    const swap = values[0];
    values[0] = values[1];
    values[1] = swap;
    try std.testing.expectError(
        error.OccurrenceOrdinalMismatch,
        history.appendRevision(.create, .{
            .package_key = form_evidence.package_key,
            .payload_shape = .editable_save,
            .occurrence_manifest = manifest,
            .occurrences = &values,
            .profile_snapshot_digest = test_profile_digest,
            .transaction_state_digest = test_transaction_digest,
        }),
    );

    values[1] = values[0];
    values[0] = swap;
    values[2].same_key_occurrence = 1;
    try std.testing.expectError(
        error.OccurrenceSameKeyMismatch,
        history.appendRevision(.create, .{
            .package_key = form_evidence.package_key,
            .payload_shape = .editable_save,
            .occurrence_manifest = manifest,
            .occurrences = &values,
            .profile_snapshot_digest = test_profile_digest,
            .transaction_state_digest = test_transaction_digest,
        }),
    );
}

test "exact 1701Q history rejects wrong package shape and manifest" {
    var history = try DraftHistory.initExact1701Q(
        std.testing.allocator,
        try testWorkspace(3),
        .final_copy_plaintext,
    );
    defer history.deinit();
    const final_manifest = try form_occurrences.finalCopyManifest();
    const editable_manifest = try form_occurrences.editableManifest();
    const no_values: []const OccurrenceValue = &.{};

    var wrong_package = form_evidence.package_key;
    wrong_package.codec_version = .legacy_1701q_v2018_v1;
    try std.testing.expectError(
        error.WrongFormPackage,
        history.appendRevision(.create, .{
            .package_key = wrong_package,
            .payload_shape = .final_copy_plaintext,
            .occurrence_manifest = final_manifest,
            .occurrences = no_values,
            .profile_snapshot_digest = test_profile_digest,
            .transaction_state_digest = test_transaction_digest,
        }),
    );
    try std.testing.expectError(
        error.WrongPayloadShape,
        history.appendRevision(.create, .{
            .package_key = form_evidence.package_key,
            .payload_shape = .editable_save,
            .occurrence_manifest = final_manifest,
            .occurrences = no_values,
            .profile_snapshot_digest = test_profile_digest,
            .transaction_state_digest = test_transaction_digest,
        }),
    );
    try std.testing.expectError(
        error.WrongOccurrenceManifest,
        history.appendRevision(.create, .{
            .package_key = form_evidence.package_key,
            .payload_shape = .final_copy_plaintext,
            .occurrence_manifest = editable_manifest,
            .occurrences = no_values,
            .profile_snapshot_digest = test_profile_digest,
            .transaction_state_digest = test_transaction_digest,
        }),
    );
    try std.testing.expectEqual(@as(usize, 0), history.revisionCount());
}

test "exact 1701Q snapshot retains all Final Copy occurrences in order" {
    const manifest = try form_occurrences.finalCopyManifest();
    const values = try std.testing.allocator.alloc(
        OccurrenceValue,
        manifest.items.len,
    );
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        OccurrenceValue,
        std.testing.allocator,
        values,
    );
    for (manifest.items, 0..) |metadata, index| {
        values[index] = .{
            .ordinal = metadata.ordinal,
            .serialized_key = metadata.serialized_key,
            .same_key_occurrence = metadata.same_key_occurrence,
            .raw_value = "",
            .normalized_value = "",
            .emitted_value = "",
        };
    }

    var history = try DraftHistory.initExact1701Q(
        std.testing.allocator,
        try testWorkspace(4),
        .final_copy_plaintext,
    );
    defer history.deinit();
    const snapshot = try history.appendRevision(.create, .{
        .package_key = form_evidence.package_key,
        .payload_shape = .final_copy_plaintext,
        .occurrence_manifest = manifest,
        .occurrences = values,
        .profile_snapshot_digest = test_profile_digest,
        .transaction_state_digest = test_transaction_digest,
    });
    try std.testing.expectEqual(@as(usize, 173), snapshot.occurrences.len);
    try std.testing.expectEqualStrings(
        manifest.items[0].serialized_key,
        snapshot.occurrenceAt(0).?.serialized_key,
    );
    try std.testing.expectEqualStrings(
        manifest.items[172].serialized_key,
        snapshot.occurrenceAt(172).?.serialized_key,
    );
    try std.testing.expect(
        std.meta.activeTag(snapshot.artifact_status) == .not_generated,
    );
}

test "failed replay restores retained-byte accounting for both shapes" {
    const shapes = [_]PayloadShape{
        .editable_save,
        .final_copy_plaintext,
    };
    for (shapes, 0..) |shape, shape_index| {
        const manifest = try exactManifest(shape);
        var value_storage: [form_occurrences.control_seeds.len]OccurrenceValue =
            undefined;
        for (manifest.items, 0..) |metadata, index| {
            value_storage[index] = .{
                .ordinal = metadata.ordinal,
                .serialized_key = metadata.serialized_key,
                .same_key_occurrence = metadata.same_key_occurrence,
                .raw_value = if (index == 0) "sensitive raw" else "",
                .normalized_value = if (index == 0)
                    "sensitive normalized"
                else
                    "",
                .emitted_value = if (index == 0)
                    "sensitive emitted"
                else
                    "",
            };
        }
        const values = value_storage[0..manifest.items.len];
        const workspace_id = try testWorkspace(
            @intCast(20 + shape_index),
        );
        var source = try DraftHistory.initExact1701Q(
            std.testing.allocator,
            workspace_id,
            shape,
        );
        defer source.deinit();
        const snapshot = try source.appendRevision(.create, .{
            .package_key = form_evidence.package_key,
            .payload_shape = shape,
            .occurrence_manifest = manifest,
            .occurrences = values,
            .profile_snapshot_digest = test_profile_digest,
            .transaction_state_digest = test_transaction_digest,
        });

        var replay = try DraftHistory.initExact1701Q(
            std.testing.allocator,
            workspace_id,
            shape,
        );
        defer replay.deinit();
        var wrong_digest = snapshot.ordered_values_digest;
        wrong_digest.bytes[0] ^= 0xff;
        try std.testing.expectError(
            error.ReplayOrderedValuesDigestMismatch,
            replay.replayPersistedRevision(.{
                .draft_identity = snapshot.draft_identity,
                .revision = snapshot.revision,
                .parent_revision = snapshot.parent_revision,
                .schema = snapshot.schema,
                .occurrences = values,
                .profile_snapshot_digest = snapshot.profile_snapshot_digest,
                .transaction_state_digest = snapshot.transaction_state_digest,
                .ordered_values_digest = wrong_digest,
                .validation_status = snapshot.validation_status,
                .artifact_status = snapshot.artifact_status,
            }),
        );
        try std.testing.expectEqual(@as(usize, 0), replay.revisionCount());
        try std.testing.expectEqual(
            @as(usize, 0),
            replay.retainedValueBytes(),
        );
    }
}

test "history deinit wipes retained occurrence values and accounting" {
    const manifest = try occurrence.OrderedOccurrenceManifest.init(
        &duplicate_manifest_items,
    );
    const values = [_]OccurrenceValue{
        .{
            .ordinal = 1,
            .serialized_key = "repeated",
            .same_key_occurrence = 1,
            .raw_value = "sensitive retained raw",
            .normalized_value = "sensitive retained normalized",
            .emitted_value = "sensitive retained emitted",
        },
        .{
            .ordinal = 2,
            .serialized_key = "middle",
            .same_key_occurrence = 1,
            .raw_value = "",
            .normalized_value = "",
            .emitted_value = "",
        },
        .{
            .ordinal = 3,
            .serialized_key = "repeated",
            .same_key_occurrence = 2,
            .raw_value = "",
            .normalized_value = "",
            .emitted_value = "",
        },
    };
    var backing: [64 * 1024]u8 = undefined;
    @memset(&backing, 0xaa);
    var fixed = std.heap.FixedBufferAllocator.init(&backing);
    var history = DraftHistory.initBound(
        fixed.allocator(),
        try testWorkspace(22),
        try testSchema(.editable_save, manifest),
    );
    const snapshot = try history.appendRevision(.create, .{
        .package_key = form_evidence.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = manifest,
        .occurrences = &values,
        .profile_snapshot_digest = test_profile_digest,
        .transaction_state_digest = test_transaction_digest,
    });
    const first = snapshot.occurrences[0];
    const raw_offset =
        @intFromPtr(first.raw_value.ptr) - @intFromPtr(backing[0..].ptr);
    const normalized_offset =
        @intFromPtr(first.normalized_value.ptr) -
        @intFromPtr(backing[0..].ptr);
    const emitted_offset =
        @intFromPtr(first.emitted_value.ptr) -
        @intFromPtr(backing[0..].ptr);
    const raw_len = first.raw_value.len;
    const normalized_len = first.normalized_value.len;
    const emitted_len = first.emitted_value.len;
    try std.testing.expect(history.retainedValueBytes() > 0);
    history.deinit();
    for (backing[raw_offset .. raw_offset + raw_len]) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
    for (
        backing[normalized_offset .. normalized_offset + normalized_len],
    ) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
    for (
        backing[emitted_offset .. emitted_offset + emitted_len],
    ) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "plaintext artifact requires the exact validation transition" {
    const manifest = try occurrence.OrderedOccurrenceManifest.init(
        &duplicate_manifest_items,
    );
    var history = DraftHistory.initBound(
        std.testing.allocator,
        try testWorkspace(5),
        try testSchema(.final_copy_plaintext, manifest),
    );
    defer history.deinit();
    const values = [_]OccurrenceValue{
        .{
            .ordinal = 1,
            .serialized_key = "repeated",
            .same_key_occurrence = 1,
            .raw_value = "",
            .normalized_value = "",
            .emitted_value = "one",
        },
        .{
            .ordinal = 2,
            .serialized_key = "middle",
            .same_key_occurrence = 1,
            .raw_value = "",
            .normalized_value = "",
            .emitted_value = "middle",
        },
        .{
            .ordinal = 3,
            .serialized_key = "repeated",
            .same_key_occurrence = 2,
            .raw_value = "",
            .normalized_value = "",
            .emitted_value = "two",
        },
    };
    try std.testing.expectError(
        error.ArtifactNotAuthorized,
        history.appendRevision(.create, .{
            .package_key = form_evidence.package_key,
            .payload_shape = .final_copy_plaintext,
            .occurrence_manifest = manifest,
            .occurrences = &values,
            .profile_snapshot_digest = test_profile_digest,
            .transaction_state_digest = test_transaction_digest,
            .validation_status = .{ .save_gate = .passed },
            .artifact_request = .plaintext,
        }),
    );
}
