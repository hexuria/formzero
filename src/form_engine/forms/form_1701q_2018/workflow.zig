//! 1701Q January 2018 orchestration boundary.
//!
//! The only production path to generated plaintext in this module is:
//!
//! profile snapshot -> editing transaction -> calculated transaction ->
//! save validation -> optional full validation -> exact ASCII codec ->
//! append-only ordered draft -> masked artifact-lab session.
//!
//! Editable plaintext requires the save gate. Final Copy plaintext requires
//! both the save gate and terminal full-validation success. Profile refresh
//! returns a new editing value and never mutates an earlier state or stored
//! draft revision.
//!
//! There is intentionally no persistence, filesystem, encryption, endpoint,
//! queue, upload, or submission operation here.

const std = @import("std");
const form = @import("../../../forms/form_1701q.zig");
const field = @import("../../../tax_profile/field.zig");
const model = @import("../../../tax_profile/model.zig");
const projection = @import("../../../tax_profile/projection.zig");
const occurrence = @import("../../occurrence.zig");
const identity = @import("../../identity.zig");
const draft = @import("../../draft.zig");
const artifact_lab = @import("../../../artifact_lab/session.zig");
const profile_mapping = @import("profile_mapping.zig");
const transaction = @import("transaction.zig");
const calculations = @import("calculations.zig");
const validation = @import("validation.zig");
const occurrences = @import("occurrences.zig");
const editable_codec = @import("editable_codec.zig");
const final_copy_codec = @import("final_copy_codec.zig");
const document = @import("document.zig");
const evidence = @import("evidence.zig");
const sensitive_memory = @import("../../../security/sensitive_memory.zig");

pub const Error =
    std.mem.Allocator.Error ||
    transaction.Error ||
    calculations.CalculationError ||
    occurrence.ManifestError ||
    editable_codec.Error ||
    final_copy_codec.Error ||
    draft.SchemaError ||
    draft.DraftError ||
    draft.SnapshotRenderError ||
    artifact_lab.Error ||
    error{
        ParsedOccurrenceCountMismatch,
        OccurrenceSourceMismatch,
        CodecDraftMismatch,
    };

pub const SecurityBoundary = struct {
    pub const stores_credential_values = false;
    pub const persists_values = false;
    pub const filesystem_enabled = false;
    pub const encryption_enabled = false;
    pub const transport_enabled = false;
};

pub const integration_gaps = [_][]const u8{
    "transaction state retains normalized controls, not pre-normalization UI lexemes",
    "editable constant raw stage is the grounded emitted page-reset value",
    "strict calculation input can reject malformed year or money before full validation reports a lexical rule",
    "spouse TIN checksum remains an injected legacy-adapter result",
    "artifact-lab session binds package/profile directly; workflow wrapper binds transaction and occurrence digests",
    "callers must expose this typestate surface rather than the lower-level public DraftHistory status input",
    "editable and Final Copy histories have distinct schema identities; cross-shape lineage is not yet modeled",
    "ASCII codec candidates remain unqualified until evidence readiness changes",
    "workflow histories are in-memory only and are not registered in the application root",
    "Zig cannot statically prohibit bitwise copies of inline typestate owners; callers must use consuming transitions or deinit every intentional fork",
};

/// Unique inline owner. Call `deinit` exactly once, or transfer ownership
/// through a consuming `...Into` transition.
pub const Editing = struct {
    transaction_state: transaction.State,

    pub fn init(
        profile: *const profile_mapping.ControlSnapshot,
    ) Error!Editing {
        var state = try transaction.State.init();
        errdefer state.deinit();
        try state.applyProfile(profile);
        return .{ .transaction_state = state };
    }

    pub fn deinit(self: *Editing) void {
        self.transaction_state.deinit();
        sensitive_memory.wipeValue(Editing, self);
    }

    pub fn setText(
        self: *Editing,
        origin: transaction.Origin,
        control_id: []const u8,
        value: []const u8,
    ) Error!void {
        try self.transaction_state.setText(origin, control_id, value);
    }

    pub fn setChecked(
        self: *Editing,
        origin: transaction.Origin,
        control_id: []const u8,
        value: bool,
    ) Error!void {
        try self.transaction_state.setChecked(origin, control_id, value);
    }

    /// Returns a new value. `self` and every already appended draft snapshot
    /// retain their original profile-produced controls and digest.
    pub fn refreshedProfile(
        self: *const Editing,
        profile: *const profile_mapping.ControlSnapshot,
    ) Error!Editing {
        var next = self.*;
        errdefer next.deinit();
        try next.transaction_state.applyProfile(profile);
        const refreshed = next;
        next.deinit();
        return refreshed;
    }

    /// On success, consumes `self` into a refreshed `out`. On failure,
    /// preserves `self` and leaves `out` uninitialized.
    pub fn refreshedProfileInto(
        self: *Editing,
        profile: *const profile_mapping.ControlSnapshot,
        out: *Editing,
    ) Error!void {
        std.debug.assert(@intFromPtr(self) != @intFromPtr(out));
        var next = self.*;
        defer next.deinit();
        try next.transaction_state.applyProfile(profile);
        out.* = next;
        self.deinit();
    }

    pub fn calculate(self: *const Editing) Error!Calculated {
        var next = self.transaction_state;
        errdefer next.deinit();
        var result = try next.recalculateAndApply();
        defer sensitive_memory.wipeValue(
            calculations.FormState,
            &result,
        );
        const calculated: Calculated = .{
            .transaction_state = next,
            .calculation = result,
        };
        next.deinit();
        return calculated;
    }

    /// On success, consumes `self` and initializes `out`. On failure, `self`
    /// remains byte-for-byte unchanged and `out` remains uninitialized.
    pub fn calculateInto(
        self: *Editing,
        out: *Calculated,
    ) Error!void {
        std.debug.assert(@intFromPtr(self) != @intFromPtr(out));
        var next = self.transaction_state;
        defer next.deinit();
        var result = try next.recalculateAndApply();
        defer sensitive_memory.wipeValue(
            calculations.FormState,
            &result,
        );
        out.* = .{
            .transaction_state = next,
            .calculation = result,
        };
        self.deinit();
    }
};

pub const Calculated = struct {
    transaction_state: transaction.State,
    calculation: calculations.FormState,

    pub fn deinit(self: *Calculated) void {
        self.transaction_state.deinit();
        sensitive_memory.wipeValue(Calculated, self);
    }

    pub fn refreshedProfile(
        self: *const Calculated,
        profile: *const profile_mapping.ControlSnapshot,
    ) Error!Editing {
        var next = self.transaction_state;
        errdefer next.deinit();
        try next.applyProfile(profile);
        const editing: Editing = .{ .transaction_state = next };
        next.deinit();
        return editing;
    }

    /// On success, consumes this calculated state into refreshed editing.
    /// On failure, preserves `self` and leaves `out` uninitialized.
    pub fn refreshedProfileInto(
        self: *Calculated,
        profile: *const profile_mapping.ControlSnapshot,
        out: *Editing,
    ) Error!void {
        var next = self.transaction_state;
        defer next.deinit();
        try next.applyProfile(profile);
        out.* = .{ .transaction_state = next };
        self.deinit();
    }

    pub fn validateSave(
        self: *const Calculated,
        current_year: i32,
        spouse_tin_checksum: validation.TinChecksumStatus,
    ) Error!SaveCheck {
        var input = try self.transaction_state.toValidationInput(
            current_year,
            spouse_tin_checksum,
        );
        defer sensitive_memory.wipeValue(
            validation.FormValidationInput,
            &input,
        );
        const result = validation.validateBeforeSave(input);
        return switch (result) {
            .failure => |rule| .{ .failed = rule },
            .success => .{ .passed = .{
                .calculated = self.*,
                .current_year = current_year,
                .spouse_tin_checksum = spouse_tin_checksum,
            } },
        };
    }

    /// Failed validation preserves `self`; a passed validation consumes it
    /// into `out.passed`.
    pub fn validateSaveInto(
        self: *Calculated,
        current_year: i32,
        spouse_tin_checksum: validation.TinChecksumStatus,
        out: *SaveCheck,
    ) Error!void {
        var input = try self.transaction_state.toValidationInput(
            current_year,
            spouse_tin_checksum,
        );
        defer sensitive_memory.wipeValue(
            validation.FormValidationInput,
            &input,
        );
        switch (validation.validateBeforeSave(input)) {
            .failure => |rule| out.* = .{ .failed = rule },
            .success => {
                out.* = .{ .passed = .{
                    .calculated = self.*,
                    .current_year = current_year,
                    .spouse_tin_checksum = spouse_tin_checksum,
                } };
                self.deinit();
            },
        }
    }
};

pub const SaveCheck = union(enum) {
    failed: validation.SaveRule,
    passed: SaveValidated,

    pub fn deinit(self: *SaveCheck) void {
        switch (self.*) {
            .failed => {},
            .passed => |*passed| passed.deinit(),
        }
        sensitive_memory.wipeValue(SaveCheck, self);
    }
};

pub const SaveValidated = struct {
    calculated: Calculated,
    current_year: i32,
    spouse_tin_checksum: validation.TinChecksumStatus,

    pub fn deinit(self: *SaveValidated) void {
        self.calculated.deinit();
        sensitive_memory.wipeValue(SaveValidated, self);
    }

    pub fn validateFull(self: *const SaveValidated) Error!FullCheck {
        var input = try self.calculated.transaction_state.toValidationInput(
            self.current_year,
            self.spouse_tin_checksum,
        );
        defer sensitive_memory.wipeValue(
            validation.FormValidationInput,
            &input,
        );
        const result = validation.validateFull(input);
        return switch (result) {
            .failure => |failure| .{ .failed = failure },
            .blocked => |block| .{ .blocked = block },
            .success => |success| .{ .passed = .{
                .save_validated = self.*,
                .success = success,
            } },
        };
    }

    /// Failed or blocked validation preserves `self`; terminal success
    /// consumes it into `out.passed`.
    pub fn validateFullInto(
        self: *SaveValidated,
        out: *FullCheck,
    ) Error!void {
        var input = try self.calculated.transaction_state.toValidationInput(
            self.current_year,
            self.spouse_tin_checksum,
        );
        defer sensitive_memory.wipeValue(
            validation.FormValidationInput,
            &input,
        );
        switch (validation.validateFull(input)) {
            .failure => |failure| {
                out.* = .{ .failed = failure };
            },
            .blocked => |block| out.* = .{ .blocked = block },
            .success => |success| {
                out.* = .{ .passed = .{
                    .save_validated = self.*,
                    .success = success,
                } };
                self.deinit();
            },
        }
    }

    pub fn appendEditableCandidate(
        self: *const SaveValidated,
        workspace: *Workspace,
        guard: draft.RevisionGuard,
    ) Error!ArtifactCandidate {
        return appendEditable(
            workspace.allocator,
            &workspace.editable_history,
            guard,
            &self.calculated.transaction_state,
        );
    }
};

pub const FullCheck = union(enum) {
    failed: validation.FullFailure,
    blocked: validation.ValidationBlock,
    passed: FullyValidated,

    pub fn deinit(self: *FullCheck) void {
        switch (self.*) {
            .failed, .blocked => {},
            .passed => |*passed| passed.deinit(),
        }
        sensitive_memory.wipeValue(FullCheck, self);
    }
};

pub const FullyValidated = struct {
    save_validated: SaveValidated,
    success: validation.FullSuccess,

    pub fn deinit(self: *FullyValidated) void {
        self.save_validated.deinit();
        sensitive_memory.wipeValue(FullyValidated, self);
    }

    pub fn appendFinalCandidate(
        self: *const FullyValidated,
        workspace: *Workspace,
        guard: draft.RevisionGuard,
    ) Error!ArtifactCandidate {
        return appendFinal(
            workspace.allocator,
            &workspace.final_history,
            guard,
            &self.save_validated.calculated.transaction_state,
        );
    }
};

/// Shape-specific histories share a user-visible workspace identifier but
/// retain distinct exact-schema identities and revision streams.
pub const Workspace = struct {
    allocator: std.mem.Allocator,
    editable_history: draft.DraftHistory,
    final_history: draft.DraftHistory,

    pub fn init(
        allocator: std.mem.Allocator,
        workspace_id: draft.DraftWorkspaceId,
    ) Error!Workspace {
        var editable_history = try draft.DraftHistory.initExact1701Q(
            allocator,
            workspace_id,
            .editable_save,
        );
        errdefer editable_history.deinit();
        const final_history = try draft.DraftHistory.initExact1701Q(
            allocator,
            workspace_id,
            .final_copy_plaintext,
        );
        return .{
            .allocator = allocator,
            .editable_history = editable_history,
            .final_history = final_history,
        };
    }

    pub fn deinit(self: *Workspace) void {
        self.editable_history.deinit();
        self.final_history.deinit();
        sensitive_memory.wipeValue(Workspace, self);
    }

    pub fn editableRevisionCount(self: *const Workspace) usize {
        return self.editable_history.revisionCount();
    }

    pub fn finalRevisionCount(self: *const Workspace) usize {
        return self.final_history.revisionCount();
    }

    pub fn editableSnapshot(
        self: *const Workspace,
        revision: draft.DraftRevision,
    ) ?*const draft.DraftSnapshot {
        return self.editable_history.snapshot(revision);
    }

    pub fn finalSnapshot(
        self: *const Workspace,
        revision: draft.DraftRevision,
    ) ?*const draft.DraftSnapshot {
        return self.final_history.snapshot(revision);
    }
};

pub const Exactness = enum {
    candidate,
    exact,
};

pub const BoundDigests = struct {
    package: identity.Sha256Digest,
    profile_snapshot: identity.Sha256Digest,
    transaction_state: identity.Sha256Digest,
    occurrence_manifest: identity.Sha256Digest,
    ordered_occurrence_values: identity.Sha256Digest,
};

pub const ArtifactCandidate = struct {
    lab_session: artifact_lab.Session,
    shape: draft.PayloadShape,
    exactness: Exactness,
    draft_revision: draft.DraftRevision,
    parent_revision: ?draft.DraftRevision,
    digests: BoundDigests,
    receipt: draft.PlaintextReceipt,
    validation_status: draft.ValidationStatus,

    pub fn deinit(self: *ArtifactCandidate) void {
        self.lab_session.deinit();
        sensitive_memory.wipeValue(ArtifactCandidate, self);
    }

    pub fn displayGenerated(
        self: *const ArtifactCandidate,
    ) artifact_lab.Error!artifact_lab.DisplayValue {
        return self.lab_session.display(.generated_plaintext);
    }

    pub fn setGeneratedRevealed(
        self: *ArtifactCandidate,
        revealed: bool,
    ) artifact_lab.Error!void {
        try self.lab_session.setRevealed(
            .generated_plaintext,
            revealed,
        );
    }
};

/// Rebuilds a masked artifact-lab owner from an already validated, replayed
/// snapshot. It never appends a draft revision and therefore cannot duplicate
/// persisted history during reopen.
pub fn restoreCandidateFromSnapshot(
    allocator: std.mem.Allocator,
    snapshot: *const draft.DraftSnapshot,
) Error!ArtifactCandidate {
    const plaintext = try snapshot.renderReadyPlaintextAlloc(allocator);
    defer secureFree(allocator, plaintext);
    const strict_validator: *const fn ([]const u8) bool =
        switch (snapshot.schema.payload_shape) {
            .editable_save => strictEditable,
            .final_copy_plaintext => strictFinal,
        };
    var session = try prepareLabSession(
        allocator,
        snapshot.schema.package_digest,
        snapshot.profile_snapshot_digest,
        plaintext,
        strict_validator,
    );
    errdefer session.deinit();
    return finishCandidate(
        session,
        snapshot,
        expectedExactness(&snapshot.schema),
    );
}

fn appendEditable(
    allocator: std.mem.Allocator,
    history: *draft.DraftHistory,
    guard: draft.RevisionGuard,
    state: *const transaction.State,
) Error!ArtifactCandidate {
    var controls = try state.toCodecControls();
    defer sensitive_memory.wipeValue(
        [transaction.control_count]document.ControlInput,
        &controls,
    );
    const codec_bytes = try editable_codec.serializeAsciiExactAlloc(
        allocator,
        &controls,
        .editable,
    );
    defer secureFree(allocator, codec_bytes);

    var parsed = try editable_codec.parseAsciiExact(
        allocator,
        codec_bytes,
        .editable,
    );
    defer secureParsed(allocator, &parsed);
    var source_values = try state.editableOccurrenceValues();
    defer sensitive_memory.wipeValue(
        [transaction.editable_occurrence_count]transaction.OccurrenceValue,
        &source_values,
    );
    var draft_values: [occurrences.editable_occurrence_items.len]draft.OccurrenceValue =
        undefined;
    defer sensitive_memory.wipeValue(
        [occurrences.editable_occurrence_items.len]draft.OccurrenceValue,
        &draft_values,
    );
    var temporary_buffers: [occurrences.editable_occurrence_items.len][]u8 = undefined;
    var temporary_count: usize = 0;
    defer {
        for (temporary_buffers[0..temporary_count]) |buffer| {
            sensitive_memory.wipeAndFreeDefaultAligned(
                u8,
                allocator,
                buffer,
            );
        }
        sensitive_memory.wipeValue(
            [occurrences.editable_occurrence_items.len][]u8,
            &temporary_buffers,
        );
    }
    try prepareDraftValues(
        allocator,
        &source_values,
        parsed.occurrences,
        &draft_values,
        &temporary_buffers,
        &temporary_count,
    );
    try verifyPreparedBytes(
        allocator,
        &draft_values,
        .editable,
        codec_bytes,
    );

    const manifest = try occurrences.editableManifest();
    const digests = try state.digestBundle();
    var session = try prepareLabSession(
        allocator,
        history.schema.package_digest,
        digests.profile_snapshot,
        codec_bytes,
        strictEditable,
    );
    errdefer session.deinit();
    const snapshot = try history.appendRevision(guard, .{
        .package_key = evidence.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = manifest,
        .occurrences = &draft_values,
        .profile_snapshot_digest = digests.profile_snapshot,
        .transaction_state_digest = digests.transaction_state,
        .validation_status = .{
            .save_gate = .passed,
            .full_validation = .not_run,
        },
        .artifact_request = .plaintext,
    });
    return finishCandidate(
        session,
        snapshot,
        expectedExactness(&history.schema),
    );
}

fn appendFinal(
    allocator: std.mem.Allocator,
    history: *draft.DraftHistory,
    guard: draft.RevisionGuard,
    state: *const transaction.State,
) Error!ArtifactCandidate {
    var controls = try state.toCodecControls();
    defer sensitive_memory.wipeValue(
        [transaction.control_count]document.ControlInput,
        &controls,
    );
    const codec_bytes = try final_copy_codec.serializeAsciiExactAlloc(
        allocator,
        &controls,
    );
    defer secureFree(allocator, codec_bytes);

    var parsed = try final_copy_codec.parseAsciiExact(
        allocator,
        codec_bytes,
    );
    defer secureParsed(allocator, &parsed);
    var source_values = try state.finalOccurrenceValues();
    defer sensitive_memory.wipeValue(
        [transaction.final_occurrence_count]transaction.OccurrenceValue,
        &source_values,
    );
    var draft_values: [occurrences.final_copy_occurrence_items.len]draft.OccurrenceValue =
        undefined;
    defer sensitive_memory.wipeValue(
        [occurrences.final_copy_occurrence_items.len]draft.OccurrenceValue,
        &draft_values,
    );
    var temporary_buffers: [occurrences.final_copy_occurrence_items.len][]u8 = undefined;
    var temporary_count: usize = 0;
    defer {
        for (temporary_buffers[0..temporary_count]) |buffer| {
            sensitive_memory.wipeAndFreeDefaultAligned(
                u8,
                allocator,
                buffer,
            );
        }
        sensitive_memory.wipeValue(
            [occurrences.final_copy_occurrence_items.len][]u8,
            &temporary_buffers,
        );
    }
    try prepareDraftValues(
        allocator,
        &source_values,
        parsed.occurrences,
        &draft_values,
        &temporary_buffers,
        &temporary_count,
    );
    try verifyPreparedBytes(
        allocator,
        &draft_values,
        .final,
        codec_bytes,
    );

    const manifest = try occurrences.finalCopyManifest();
    const digests = try state.digestBundle();
    var session = try prepareLabSession(
        allocator,
        history.schema.package_digest,
        digests.profile_snapshot,
        codec_bytes,
        strictFinal,
    );
    errdefer session.deinit();
    const snapshot = try history.appendRevision(guard, .{
        .package_key = evidence.package_key,
        .payload_shape = .final_copy_plaintext,
        .occurrence_manifest = manifest,
        .occurrences = &draft_values,
        .profile_snapshot_digest = digests.profile_snapshot,
        .transaction_state_digest = digests.transaction_state,
        .validation_status = .{
            .save_gate = .passed,
            .full_validation = .passed,
        },
        .artifact_request = .plaintext,
    });
    return finishCandidate(
        session,
        snapshot,
        expectedExactness(&history.schema),
    );
}

fn prepareDraftValues(
    allocator: std.mem.Allocator,
    source_values: []const transaction.OccurrenceValue,
    parsed_values: []const document.ParsedOccurrence,
    output: []draft.OccurrenceValue,
    owned_buffers: [][]u8,
    owned_count: *usize,
) Error!void {
    if (source_values.len != parsed_values.len or
        output.len != source_values.len)
    {
        return error.ParsedOccurrenceCountMismatch;
    }
    for (source_values, parsed_values, output) |
        source,
        parsed,
        *destination,
    | {
        if (parsed.source_order + 1 != source.metadata.ordinal or
            parsed.same_key_occurrence !=
                source.metadata.same_key_occurrence or
            !std.mem.eql(
                u8,
                parsed.key,
                source.metadata.serialized_key,
            ))
        {
            return error.OccurrenceSourceMismatch;
        }
        const prepared = try occurrenceSourceBytes(
            allocator,
            source.source,
        );
        if (prepared.owned) |owned| {
            std.debug.assert(owned_count.* < owned_buffers.len);
            owned_buffers[owned_count.*] = owned;
            owned_count.* += 1;
        }
        destination.* = .{
            .ordinal = source.metadata.ordinal,
            .serialized_key = source.metadata.serialized_key,
            .same_key_occurrence = source.metadata.same_key_occurrence,
            .raw_value = prepared.bytes,
            .normalized_value = prepared.bytes,
            .emitted_value = parsed.encoded_value,
        };
    }
}

const PreparedSource = struct {
    bytes: []const u8,
    owned: ?[]u8 = null,
};

fn occurrenceSourceBytes(
    allocator: std.mem.Allocator,
    source: transaction.OccurrenceSource,
) Error!PreparedSource {
    return switch (source) {
        .text => |value| .{ .bytes = value },
        .checked => |value| .{
            .bytes = if (value) "true" else "false",
        },
        .constant_text => |value| .{ .bytes = value },
        .concatenated_text => |parts| blk: {
            const joined_len = std.math.add(
                usize,
                parts[0].len,
                parts[1].len,
            ) catch return error.DocumentTooLarge;
            const joined = try allocator.alloc(
                u8,
                joined_len,
            );
            @memcpy(joined[0..parts[0].len], parts[0]);
            @memcpy(joined[parts[0].len..], parts[1]);
            break :blk .{
                .bytes = joined,
                .owned = joined,
            };
        },
    };
}

fn verifyPreparedBytes(
    allocator: std.mem.Allocator,
    values: []const draft.OccurrenceValue,
    marker: document.Marker,
    codec_bytes: []const u8,
) Error!void {
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
    const rendered = try document.renderOccurrencesAlloc(
        allocator,
        views,
        marker,
    );
    defer secureFree(allocator, rendered);
    if (!std.mem.eql(u8, rendered, codec_bytes)) {
        return error.CodecDraftMismatch;
    }
}

fn prepareLabSession(
    allocator: std.mem.Allocator,
    package_digest: identity.Sha256Digest,
    profile_digest: identity.Sha256Digest,
    plaintext: []const u8,
    strict_validator: *const fn ([]const u8) bool,
) Error!artifact_lab.Session {
    var session = artifact_lab.Session.init(
        allocator,
        package_digest.asBytes().*,
        profile_digest.asBytes().*,
    );
    errdefer session.deinit();
    try session.setGeneratedPlaintext(plaintext, strict_validator);
    return session;
}

fn expectedExactness(schema: *const draft.SchemaBinding) Exactness {
    if (schema.package_key.codec_version == null or
        !schema.evidence_readiness.identityReady() or
        !schema.evidence_readiness.profile_mapping_reviewed or
        !schema.evidence_readiness.calculation_reconciled or
        !schema.evidence_readiness.validation_reconciled)
    {
        return .candidate;
    }
    return switch (schema.payload_shape) {
        .editable_save => if (schema.evidence_readiness.editable_serializer_exact)
            .exact
        else
            .candidate,
        .final_copy_plaintext => if (schema.evidence_readiness.final_plaintext_serializer_exact)
            .exact
        else
            .candidate,
    };
}

fn finishCandidate(
    session: artifact_lab.Session,
    snapshot: *const draft.DraftSnapshot,
    expected_exactness: Exactness,
) ArtifactCandidate {
    const Actual = struct {
        exactness: Exactness,
        receipt: draft.PlaintextReceipt,
    };
    const actual: Actual = switch (snapshot.artifact_status) {
        .not_generated => unreachable,
        .plaintext_candidate => |receipt| .{
            .exactness = Exactness.candidate,
            .receipt = receipt,
        },
        .plaintext_exact => |receipt| .{
            .exactness = Exactness.exact,
            .receipt = receipt,
        },
    };
    std.debug.assert(actual.exactness == expected_exactness);
    return .{
        .lab_session = session,
        .shape = snapshot.schema.payload_shape,
        .exactness = actual.exactness,
        .draft_revision = snapshot.revision,
        .parent_revision = snapshot.parent_revision,
        .digests = .{
            .package = snapshot.schema.package_digest,
            .profile_snapshot = snapshot.profile_snapshot_digest,
            .transaction_state = snapshot.transaction_state_digest,
            .occurrence_manifest = snapshot.schema.occurrence_manifest_digest,
            .ordered_occurrence_values = snapshot.ordered_values_digest,
        },
        .receipt = actual.receipt,
        .validation_status = snapshot.validation_status,
    };
}

fn strictEditable(bytes: []const u8) bool {
    var parsed = editable_codec.parseAsciiExact(
        std.heap.page_allocator,
        bytes,
        .editable,
    ) catch return false;
    defer secureParsed(std.heap.page_allocator, &parsed);
    return true;
}

fn strictFinal(bytes: []const u8) bool {
    var parsed = final_copy_codec.parseAsciiExact(
        std.heap.page_allocator,
        bytes,
    ) catch return false;
    defer secureParsed(std.heap.page_allocator, &parsed);
    return true;
}

fn secureParsed(
    allocator: std.mem.Allocator,
    parsed: *document.ParsedDocument,
) void {
    parsed.deinit(allocator);
}

fn secureFree(allocator: std.mem.Allocator, bytes: []const u8) void {
    sensitive_memory.wipeAndFreeConstDefaultAligned(
        u8,
        allocator,
        bytes,
    );
}

fn exercisePreparedValueAllocationPaths(
    allocator: std.mem.Allocator,
) !void {
    const manifest = try occurrences.editableManifest();
    const metadata = blk: {
        for (manifest.items) |item| {
            if (item.emission == .concatenated_legacy_escape) {
                break :blk item;
            }
        }
        unreachable;
    };
    const source_values = [_]transaction.OccurrenceValue{.{
        .metadata = metadata,
        .origin = .profile,
        .source = .{
            .concatenated_text = .{ "FIRST ", "SECOND" },
        },
    }};
    const parsed_values = [_]document.ParsedOccurrence{.{
        .source_order = metadata.ordinal - 1,
        .same_key_occurrence = metadata.same_key_occurrence,
        .key = metadata.serialized_key,
        .encoded_value = "FIRST%20SECOND",
    }};
    var output: [1]draft.OccurrenceValue = undefined;
    defer sensitive_memory.wipeValue(
        [1]draft.OccurrenceValue,
        &output,
    );
    var owned_buffers: [1][]u8 = undefined;
    var owned_count: usize = 0;
    defer {
        for (owned_buffers[0..owned_count]) |buffer| {
            sensitive_memory.wipeAndFreeDefaultAligned(
                u8,
                allocator,
                buffer,
            );
        }
        sensitive_memory.wipeValue([1][]u8, &owned_buffers);
    }

    try prepareDraftValues(
        allocator,
        &source_values,
        &parsed_values,
        &output,
        &owned_buffers,
        &owned_count,
    );
    try std.testing.expectEqual(@as(usize, 1), owned_count);
    try std.testing.expectEqualStrings(
        "FIRST SECOND",
        output[0].normalized_value,
    );
}

test "all prepared-value allocation failures erase partial values" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exercisePreparedValueAllocationPaths,
        .{},
    );
}

fn syntheticProfile(
    include_spouse: bool,
    filer_email: []const u8,
) !profile_mapping.ControlSnapshot {
    var snapshot = projection.Snapshot.init(
        form.revision,
        try model.Date.init(2025, 3, 31),
    );
    const filer_provenance: projection.Provenance = .{
        .profile_id = try model.ProfileId.parse("synthetic-filer-profile"),
        .revision_id = try model.RevisionId.parse("synthetic-filer-r1"),
        .revision_sequence = 1,
        .revision_source = .manual_entry,
    };
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[0].target,
        .value = .{ .tin = try field.Tin.parse("123-456-789-000") },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[1].target,
        .value = .{ .rdo_code = try field.RdoCode.parse("019") },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[2].target,
        .value = .{
            .taxpayer_name = try field.TaxpayerName.parse(
                "SYNTHETIC FILER",
            ),
        },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[3].target,
        .value = .{
            .registered_address = try field.RegisteredAddress.parse(
                "SYNTHETIC REGISTERED ADDRESS",
            ),
        },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[4].target,
        .value = .{ .zip_code = try field.ZipCode.parse("1000") },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[5].target,
        .value = .{
            .date_of_birth = try model.Date.init(1990, 1, 15),
        },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[6].target,
        .value = .{
            .email_address = try field.EmailAddress.parse(filer_email),
        },
        .provenance = filer_provenance,
    });

    if (include_spouse) {
        const spouse_provenance: projection.Provenance = .{
            .profile_id = try model.ProfileId.parse(
                "synthetic-spouse-profile",
            ),
            .revision_id = try model.RevisionId.parse(
                "synthetic-spouse-r1",
            ),
            .revision_sequence = 1,
            .revision_source = .manual_entry,
        };
        try snapshot.append(.{
            .role = .spouse,
            .target = form.spouse_requirements[0].target,
            .value = .{
                .tin = try field.Tin.parse("987-654-321-001"),
            },
            .provenance = spouse_provenance,
        });
        try snapshot.append(.{
            .role = .spouse,
            .target = form.spouse_requirements[1].target,
            .value = .{ .rdo_code = try field.RdoCode.parse("020") },
            .provenance = spouse_provenance,
        });
        try snapshot.append(.{
            .role = .spouse,
            .target = form.spouse_requirements[2].target,
            .value = .{
                .taxpayer_name = try field.TaxpayerName.parse(
                    "SYNTHETIC SPOUSE",
                ),
            },
            .provenance = spouse_provenance,
        });
    }

    return switch (profile_mapping.mapProfileSnapshot(snapshot)) {
        .accepted => |accepted| accepted,
        .blocked => error.UnexpectedProfileMappingBlock,
    };
}

fn populatedEditing(
    profile: *const profile_mapping.ControlSnapshot,
    include_spouse: bool,
) !Editing {
    var editing = try Editing.init(profile);
    errdefer editing.deinit();
    for (occurrences.control_seeds) |seed| {
        const origin = try editing.transaction_state.originFor(seed.id);
        switch (origin) {
            .profile, .derived, .preparer => {},
            .transaction => switch (seed.kind) {
                .radio => try editing.setChecked(
                    .transaction,
                    seed.id,
                    false,
                ),
                .text, .select_one => try editing.setText(
                    .transaction,
                    seed.id,
                    "0.00",
                ),
            },
            .filing_context => switch (seed.kind) {
                .radio => try editing.setChecked(
                    .filing_context,
                    seed.id,
                    false,
                ),
                .text, .select_one => try editing.setText(
                    .filing_context,
                    seed.id,
                    if (std.mem.eql(
                        u8,
                        seed.id,
                        "frm1701q:txtYear",
                    ))
                        "2025"
                    else
                        "0",
                ),
            },
            .external_evidence => try editing.setText(
                .external_evidence,
                seed.id,
                "",
            ),
            .system => try editing.setText(
                .system,
                seed.id,
                if (std.mem.eql(
                    u8,
                    seed.id,
                    "frm1701q:txtCurrentPage",
                ))
                    "1"
                else
                    "",
            ),
            .unreviewed => unreachable,
        }
    }

    try editing.setChecked(
        .filing_context,
        "frm1701q:DateQuarter_1",
        true,
    );
    try editing.setChecked(.transaction, "frm1701q:optType_1", true);
    try editing.setChecked(.transaction, "frm1701q:optATC_1", true);
    try editing.setChecked(
        .transaction,
        "frm1701q:optTaxRate_1",
        true,
    );
    try editing.setChecked(
        .transaction,
        "frm1701q:optMethodOfDeduction:_1",
        true,
    );
    if (include_spouse) {
        try editing.setChecked(
            .transaction,
            "frm1701q:optSpouseType_1",
            true,
        );
        try editing.setChecked(
            .transaction,
            "frm1701q:optSpouseATC_1",
            true,
        );
        try editing.setChecked(
            .transaction,
            "frm1701q:optSpouseTaxRate_1",
            true,
        );
        try editing.setChecked(
            .transaction,
            "frm1701q:optSpouseMethod:_1",
            true,
        );
    }
    return editing;
}

fn expectWorkflowValueZeroed(value: anytype) !void {
    for (std.mem.asBytes(value)) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

fn expectSavePassed(
    calculated: *const Calculated,
    spouse_tin_checksum: validation.TinChecksumStatus,
) !SaveValidated {
    return switch (try calculated.validateSave(
        2026,
        spouse_tin_checksum,
    )) {
        .failed => error.UnexpectedSaveFailure,
        .passed => |passed| passed,
    };
}

fn expectFullPassed(
    save_validated: *const SaveValidated,
) !FullyValidated {
    return switch (try save_validated.validateFull()) {
        .failed => error.UnexpectedFullFailure,
        .blocked => error.UnexpectedFullBlock,
        .passed => |passed| passed,
    };
}

fn testWorkspaceId(byte: u8) !draft.DraftWorkspaceId {
    return draft.DraftWorkspaceId.init([_]u8{byte} ** 16);
}

fn storedOccurrence(
    snapshot: *const draft.DraftSnapshot,
    key: []const u8,
) ?*const draft.StoredOccurrenceValue {
    for (snapshot.occurrences) |*value| {
        if (std.mem.eql(u8, value.serialized_key, key)) return value;
    }
    return null;
}

test "consuming workflow transitions wipe sources and transfer one owner" {
    var profile = try syntheticProfile(
        false,
        "consuming-owner@example.test",
    );
    defer sensitive_memory.wipeValue(
        profile_mapping.ControlSnapshot,
        &profile,
    );
    var editing = try populatedEditing(&profile, false);
    var calculated: Calculated = undefined;
    try editing.calculateInto(&calculated);
    try expectWorkflowValueZeroed(&editing);

    var save_check: SaveCheck = undefined;
    try calculated.validateSaveInto(
        2026,
        .not_evaluated,
        &save_check,
    );
    try expectWorkflowValueZeroed(&calculated);
    switch (save_check) {
        .failed => return error.UnexpectedSaveFailure,
        .passed => |*save_validated| {
            var full_check: FullCheck = undefined;
            try save_validated.validateFullInto(&full_check);
            try expectWorkflowValueZeroed(save_validated);
            switch (full_check) {
                .failed => return error.UnexpectedFullFailure,
                .blocked => return error.UnexpectedFullBlock,
                .passed => {},
            }
            full_check.deinit();
            try expectWorkflowValueZeroed(&full_check);
        },
    }
    sensitive_memory.wipeValue(SaveCheck, &save_check);
}

test "failed consuming calculation preserves its source bytes" {
    var profile = try syntheticProfile(
        false,
        "failed-owner@example.test",
    );
    defer sensitive_memory.wipeValue(
        profile_mapping.ControlSnapshot,
        &profile,
    );
    var editing = try populatedEditing(&profile, false);
    defer editing.deinit();
    try editing.setText(
        .filing_context,
        "frm1701q:txtYear",
        "NOPE",
    );
    var before = editing;
    defer before.deinit();
    var untouched_output: Calculated = undefined;
    try std.testing.expectError(
        error.InvalidYear,
        editing.calculateInto(&untouched_output),
    );
    try std.testing.expectEqualSlices(
        u8,
        std.mem.asBytes(&before),
        std.mem.asBytes(&editing),
    );
}

test "filer-only workflow reaches full validation without spouse inference" {
    const profile = try syntheticProfile(false, "filer@example.test");
    const editing = try populatedEditing(&profile, false);
    const calculated = try editing.calculate();
    const save_validated = try expectSavePassed(
        &calculated,
        .not_evaluated,
    );
    const fully_validated = try expectFullPassed(&save_validated);
    _ = fully_validated;

    try std.testing.expectEqualStrings(
        "",
        try calculated.transaction_state.text(
            .profile,
            "frm1701q:txtSpouseName",
        ),
    );
    try std.testing.expectEqualStrings(
        "000",
        try calculated.transaction_state.text(
            .profile,
            "frm1701q:txtSpouseRDOCode",
        ),
    );
}

test "distinct spouse profile remains separately provenanced and validates" {
    const profile = try syntheticProfile(true, "married@example.test");
    const editing = try populatedEditing(&profile, true);
    const calculated = try editing.calculate();
    const filer_source = (try calculated.transaction_state.profileProvenance(
        "frm1701q:txtTIN1",
    )).?;
    const spouse_source = (try calculated.transaction_state.profileProvenance(
        "frm1701q:txtSpouseTIN1",
    )).?;
    try std.testing.expect(
        !filer_source.profile_id.eql(&spouse_source.profile_id),
    );
    try std.testing.expectEqualStrings(
        "SYNTHETIC SPOUSE",
        try calculated.transaction_state.text(
            .profile,
            "frm1701q:txtSpouseName",
        ),
    );
    const save_validated = try expectSavePassed(&calculated, .valid);
    _ = try expectFullPassed(&save_validated);
}

test "calculation branch is applied before either validation gate" {
    const profile = try syntheticProfile(false, "calc@example.test");
    var editing = try populatedEditing(&profile, false);
    try editing.setChecked(
        .transaction,
        "frm1701q:optTaxRate_1",
        false,
    );
    try editing.setChecked(
        .transaction,
        "frm1701q:optTaxRate_2",
        true,
    );
    try editing.setText(
        .transaction,
        "frm1701q:txt47A",
        "1,000,000.00",
    );
    const calculated = try editing.calculate();
    try std.testing.expectEqual(
        calculated.calculation.taxpayer.derived.txt54.centavos,
        calculated.calculation.taxpayer.derived.txt26.centavos,
    );
    const expected = try transaction.formatMoney(
        calculated.calculation.taxpayer.derived.txt26,
    );
    try std.testing.expectEqualStrings(
        expected.asSlice(),
        try calculated.transaction_state.text(
            .derived,
            "frm1701q:txt26A",
        ),
    );
}

test "validation outcomes retain the first failing ordered rule" {
    const profile = try syntheticProfile(false, "failure@example.test");
    var missing_quarter = try populatedEditing(&profile, false);
    try missing_quarter.setChecked(
        .filing_context,
        "frm1701q:DateQuarter_1",
        false,
    );
    const calculated_missing_quarter = try missing_quarter.calculate();
    switch (try calculated_missing_quarter.validateSave(
        2026,
        .not_evaluated,
    )) {
        .failed => |rule| try std.testing.expectEqual(
            validation.SaveRuleId.quarter_required,
            rule.id,
        ),
        .passed => return error.ExpectedSaveFailure,
    }

    var missing_type = try populatedEditing(&profile, false);
    try missing_type.setChecked(
        .transaction,
        "frm1701q:optType_1",
        false,
    );
    const calculated_missing_type = try missing_type.calculate();
    const save_validated = try expectSavePassed(
        &calculated_missing_type,
        .not_evaluated,
    );
    switch (try save_validated.validateFull()) {
        .failed => |failure| try std.testing.expectEqual(
            validation.FullRuleId.taxpayer_type_required,
            failure.rule.id,
        ),
        .blocked => return error.ExpectedFullFailure,
        .passed => return error.ExpectedFullFailure,
    }
}

test "editable candidate binds digests and opens masked artifact lab" {
    const profile = try syntheticProfile(false, "editable@example.test");
    const editing = try populatedEditing(&profile, false);
    const calculated = try editing.calculate();
    const save_validated = try expectSavePassed(
        &calculated,
        .not_evaluated,
    );
    var workspace = try Workspace.init(
        std.testing.allocator,
        try testWorkspaceId(0x11),
    );
    defer workspace.deinit();
    var candidate = try save_validated.appendEditableCandidate(
        &workspace,
        .create,
    );
    defer candidate.deinit();

    try std.testing.expectEqual(
        draft.PayloadShape.editable_save,
        candidate.shape,
    );
    try std.testing.expectEqual(Exactness.candidate, candidate.exactness);
    try std.testing.expectEqual(@as(usize, 1), workspace.editableRevisionCount());
    try std.testing.expectEqual(@as(usize, 0), workspace.finalRevisionCount());
    const state_digests =
        try calculated.transaction_state.digestBundle();
    try std.testing.expect(
        candidate.digests.package.eql(&state_digests.package),
    );
    try std.testing.expect(
        candidate.digests.profile_snapshot.eql(
            &state_digests.profile_snapshot,
        ),
    );
    try std.testing.expect(
        candidate.digests.transaction_state.eql(
            &state_digests.transaction_state,
        ),
    );
    const stored = workspace.editableSnapshot(
        candidate.draft_revision,
    ).?;
    try std.testing.expect(
        candidate.digests.occurrence_manifest.eql(
            &stored.schema.occurrence_manifest_digest,
        ),
    );
    try std.testing.expect(
        candidate.digests.ordered_occurrence_values.eql(
            &stored.ordered_values_digest,
        ),
    );
    try std.testing.expect(std.mem.eql(
        u8,
        &candidate.lab_session.exact_form_package_digest,
        candidate.digests.package.asBytes(),
    ));
    try std.testing.expect(std.mem.eql(
        u8,
        &candidate.lab_session.profile_snapshot_digest,
        candidate.digests.profile_snapshot.asBytes(),
    ));
    switch (try candidate.displayGenerated()) {
        .masked => |summary| {
            try std.testing.expectEqual(
                @as(usize, candidate.receipt.byte_length),
                summary.byte_length,
            );
            try std.testing.expect(std.mem.eql(
                u8,
                &summary.sha256,
                candidate.receipt.sha256.asBytes(),
            ));
        },
        .revealed => return error.ExpectedMaskedArtifact,
    }
}

test "full validation is required for Final Copy candidate" {
    const profile = try syntheticProfile(false, "final@example.test");
    const editing = try populatedEditing(&profile, false);
    const calculated = try editing.calculate();
    const save_validated = try expectSavePassed(
        &calculated,
        .not_evaluated,
    );
    const fully_validated = try expectFullPassed(&save_validated);
    var workspace = try Workspace.init(
        std.testing.allocator,
        try testWorkspaceId(0x22),
    );
    defer workspace.deinit();
    var candidate = try fully_validated.appendFinalCandidate(
        &workspace,
        .create,
    );
    defer candidate.deinit();

    try std.testing.expectEqual(
        draft.PayloadShape.final_copy_plaintext,
        candidate.shape,
    );
    try std.testing.expectEqual(Exactness.candidate, candidate.exactness);
    try std.testing.expectEqual(@as(usize, 0), workspace.editableRevisionCount());
    try std.testing.expectEqual(@as(usize, 1), workspace.finalRevisionCount());
    try std.testing.expect(
        candidate.validation_status.save_gate == .passed,
    );
    try std.testing.expect(
        candidate.validation_status.full_validation == .passed,
    );
}

test "profile refresh creates a new immutable draft revision" {
    const first_profile = try syntheticProfile(
        false,
        "before@example.test",
    );
    const first_editing = try populatedEditing(&first_profile, false);
    const first_calculated = try first_editing.calculate();
    const first_save = try expectSavePassed(
        &first_calculated,
        .not_evaluated,
    );
    var workspace = try Workspace.init(
        std.testing.allocator,
        try testWorkspaceId(0x33),
    );
    defer workspace.deinit();
    var first_candidate = try first_save.appendEditableCandidate(
        &workspace,
        .create,
    );
    defer first_candidate.deinit();
    const first_revision = first_candidate.draft_revision;
    const first_snapshot =
        workspace.editableSnapshot(first_revision).?;
    const first_profile_digest = first_snapshot.profile_snapshot_digest;
    try std.testing.expectEqualStrings(
        "before@example.test",
        storedOccurrence(first_snapshot, "txtEmail").?.raw_value,
    );

    const refreshed_profile = try syntheticProfile(
        false,
        "after@example.test",
    );
    const refreshed_editing = try first_calculated.refreshedProfile(
        &refreshed_profile,
    );
    const refreshed_calculated = try refreshed_editing.calculate();
    const refreshed_save = try expectSavePassed(
        &refreshed_calculated,
        .not_evaluated,
    );
    var second_candidate = try refreshed_save.appendEditableCandidate(
        &workspace,
        .{ .match = first_revision },
    );
    defer second_candidate.deinit();
    const second_snapshot =
        workspace.editableSnapshot(second_candidate.draft_revision).?;
    try std.testing.expectEqual(
        @as(u64, 2),
        second_candidate.draft_revision.value,
    );
    try std.testing.expect(
        second_candidate.parent_revision.?.eql(first_revision),
    );
    try std.testing.expect(
        first_profile_digest.eql(&first_snapshot.profile_snapshot_digest),
    );
    try std.testing.expect(
        !first_snapshot.profile_snapshot_digest.eql(
            &second_snapshot.profile_snapshot_digest,
        ),
    );
    try std.testing.expectEqualStrings(
        "before@example.test",
        storedOccurrence(first_snapshot, "txtEmail").?.raw_value,
    );
    try std.testing.expectEqualStrings(
        "after@example.test",
        storedOccurrence(second_snapshot, "txtEmail").?.raw_value,
    );
    try std.testing.expectError(
        error.StaleRevision,
        refreshed_save.appendEditableCandidate(
            &workspace,
            .{ .match = first_revision },
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        workspace.editableRevisionCount(),
    );
}

test "unvalidated states and candidate API expose no submit or encryption" {
    try std.testing.expect(
        !@hasDecl(Editing, "appendEditableCandidate"),
    );
    try std.testing.expect(
        !@hasDecl(Calculated, "appendEditableCandidate"),
    );
    try std.testing.expect(
        !@hasDecl(SaveValidated, "appendFinalCandidate"),
    );
    try std.testing.expect(!@hasDecl(ArtifactCandidate, "encrypt"));
    try std.testing.expect(!@hasDecl(ArtifactCandidate, "submit"));
    try std.testing.expect(!@hasDecl(ArtifactCandidate, "queue"));
    try std.testing.expect(!@hasDecl(ArtifactCandidate, "upload"));
    try std.testing.expect(!@hasDecl(Workspace, "persist"));
    try std.testing.expect(!@hasDecl(Workspace, "writeFile"));
    try std.testing.expect(!SecurityBoundary.stores_credential_values);
    try std.testing.expect(!SecurityBoundary.persists_values);
    try std.testing.expect(!SecurityBoundary.filesystem_enabled);
    try std.testing.expect(!SecurityBoundary.encryption_enabled);
    try std.testing.expect(!SecurityBoundary.transport_enabled);
}
