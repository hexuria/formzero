//! Durable persistence and fail-closed reopen bridge for the exact
//! BIR Form 1701Q January 2018 workflow.
//!
//! SQLite is an injected repository. This module owns no path, file dialog,
//! network, encryption, queue, endpoint, upload, or submission operation.
//! Stored occurrence values are currently plaintext. Until an independently
//! reviewed at-rest key-custody design exists, this bridge is restricted to
//! synthetic/test data and must not be presented as production-qualified.

const std = @import("std");
const ids = @import("id.zig");
const form = @import("form_1701q.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");
const projection = @import("../tax_profile/projection.zig");
const store = @import("../tax_profile/store.zig");
const key_custody = @import("../security/key_custody.zig");
const sensitive_memory = @import("../security/sensitive_memory.zig");
const draft = @import("../form_engine/draft.zig");
const occurrence = @import("../form_engine/occurrence.zig");
const evidence = @import(
    "../form_engine/forms/form_1701q_2018/evidence.zig",
);
const occurrences = @import(
    "../form_engine/forms/form_1701q_2018/occurrences.zig",
);
const profile_mapping = @import(
    "../form_engine/forms/form_1701q_2018/profile_mapping.zig",
);
const transaction = @import(
    "../form_engine/forms/form_1701q_2018/transaction.zig",
);
const workflow = @import(
    "../form_engine/forms/form_1701q_2018/workflow.zig",
);
const validation = @import(
    "../form_engine/forms/form_1701q_2018/validation.zig",
);
const ui = @import("form_1701q_exact_ui_state.zig");

pub const synthetic_test_only_at_rest = true;

pub const SecurityBoundary = struct {
    pub const plaintext_storage_state =
        key_custody.PlaintextStorageState.synthetic_plaintext_test_only;
    pub const production_storage_state =
        key_custody.current_production_storage_state;
    pub const synthetic_plaintext_persistence_enabled = true;
    pub const sqlite_values_are_plaintext = true;
    pub const synthetic_test_only = true;
    pub const production_key_custody_qualified = false;
    pub const stores_protocol_secrets = false;
    pub const outbound_encryption_enabled = false;
    pub const filesystem_owned_by_adapter = false;
    pub const endpoint_enabled = false;
    pub const queue_enabled = false;
    pub const upload_enabled = false;
    pub const submission_enabled = false;
    pub const transport_enabled = false;
};

pub const Error =
    store.Error ||
    key_custody.SyntheticPlaintextTestError ||
    workflow.Error ||
    ui.Error ||
    error{
        InvalidRoleBinding,
        DuplicateRoleBinding,
        MissingFilerBinding,
        UnexpectedSpouseBinding,
        MissingSpouseBinding,
        HistoricalProfileBindingMismatch,
        HistoricalProfileDigestMismatch,
        FilingBusinessKeyMismatch,
        ProfileAsOfMismatch,
        RecordedAtInvalid,
        EmptyPersistedWorkspace,
        SelectedShapeMissing,
        PersistedHistoryMismatch,
        PersistedBindingMismatch,
        PersistedOccurrenceContextMismatch,
        LoadedWorkspaceAlreadyConsumed,
        MissingValidationEvidenceReceipt,
    };

/// Caller-owned relation identity layered over the immutable revision
/// provenance already frozen into `projection.Snapshot`.
pub const RoleInstanceBinding = struct {
    role: ids.Role,
    instance_id: []const u8,
    business_activity_id: ?[]const u8 = null,
    provenance: []const u8 = "historical_profile_projection",
};

pub const PersistRequest = struct {
    historical_profile: *const projection.Snapshot,
    role_instances: []const RoleInstanceBinding,
    recorded_at_unix_seconds: i64,
    guard: draft.RevisionGuard,
};

pub const PersistReceipt = struct {
    draft_identity: draft.DraftIdentity,
    revision: draft.DraftRevision,
    parent_revision: ?draft.DraftRevision,
    shape: draft.PayloadShape,
};

const max_role_bindings = 2;
const max_occurrences = occurrences.control_seeds.len;

comptime {
    if (max_occurrences != 173) {
        @compileError("exact 1701Q persistence requires 173 controls");
    }
}

/// Copies the current generated candidate transactionally with an optimistic
/// create/match guard. Neither the state nor the historical projection is
/// mutated.
pub fn persistCurrentCandidate(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    repository: *store.Store,
    state: *const ui.State,
    request: PersistRequest,
) Error!PersistReceipt {
    try key_custody.requireSyntheticPlaintextForTest(
        plaintext_capability,
    );
    if (request.recorded_at_unix_seconds <= 0) {
        return error.RecordedAtInvalid;
    }
    if (!state.profileAsOf().eql(request.historical_profile.effective_on)) {
        return error.ProfileAsOfMismatch;
    }

    const snapshot = try state.candidateSnapshot();
    const supplied_profile_digest = try historicalProfileDigest(
        request.historical_profile,
    );
    if (!supplied_profile_digest.eql(
        &snapshot.profile_snapshot_digest,
    )) {
        return error.HistoricalProfileDigestMismatch;
    }

    var binding_storage: [max_role_bindings]store.ExactDraftRoleBindingWrite = undefined;
    const bindings = try buildRoleBindingWrites(
        request.historical_profile,
        request.role_instances,
        &binding_storage,
    );
    const filer_profile_id = filerProfileId(bindings) orelse
        return error.MissingFilerBinding;

    var key_storage = FilingKeyStorage.init(
        filer_profile_id,
        state.filingContext(),
    );
    defer sensitive_memory.wipeValue(FilingKeyStorage, &key_storage);
    const filing_key = key_storage.borrowed(filer_profile_id);

    var occurrence_storage: [max_occurrences]store.ExactDraftOccurrenceContextWrite = undefined;
    defer sensitive_memory.wipeValue(
        [max_occurrences]store.ExactDraftOccurrenceContextWrite,
        &occurrence_storage,
    );
    const contexts = try buildOccurrenceContexts(
        snapshot,
        &occurrence_storage,
    );
    const profile_as_of = dateText(state.profileAsOf());
    const validation_evidence = state.validationEvidenceReceipt() orelse
        return error.MissingValidationEvidenceReceipt;

    try repository.appendExactDraftRevision(plaintext_capability, request.guard, .{
        .filing_key = filing_key,
        .profile_as_of = profile_as_of,
        .recorded_at_unix_seconds = request.recorded_at_unix_seconds,
        .validation_evidence = .{
            .validation_current_year = validation_evidence.validation_current_year,
            .spouse_tin_checksum = validation_evidence.spouse_tin_checksum,
        },
        .snapshot = snapshot,
        .bindings = bindings,
        .occurrence_contexts = contexts,
    });
    return .{
        .draft_identity = snapshot.draft_identity,
        .revision = snapshot.revision,
        .parent_revision = snapshot.parent_revision,
        .shape = snapshot.schema.payload_shape,
    };
}

/// Shape-specific histories remain siblings under one random workspace.
/// Sidecars retain immutable revision bindings, occurrence provenance,
/// profile-as-of, and timestamps that deliberately do not belong in the
/// pure engine `DraftHistory`.
pub const LoadedWorkspace = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    workspace: workflow.Workspace,
    workspace_owned: bool = true,
    editable_history: ?store.OwnedExactDraftHistory = null,
    final_history: ?store.OwnedExactDraftHistory = null,

    pub fn deinit(self: *Self) void {
        if (self.workspace_owned) self.workspace.deinit();
        if (self.editable_history) |*history| {
            history.deinit(self.allocator);
        }
        if (self.final_history) |*history| {
            history.deinit(self.allocator);
        }
        sensitive_memory.wipeValue(Self, self);
    }

    pub fn revisionCount(
        self: *const Self,
        shape: draft.PayloadShape,
    ) usize {
        return switch (shape) {
            .editable_save => self.workspace.editableRevisionCount(),
            .final_copy_plaintext => self.workspace.finalRevisionCount(),
        };
    }

    pub fn currentPersistedRevision(
        self: *const Self,
        shape: draft.PayloadShape,
    ) ?*const store.OwnedExactDraftRevision {
        const history = switch (shape) {
            .editable_save => if (self.editable_history) |*value|
                value
            else
                return null,
            .final_copy_plaintext => if (self.final_history) |*value|
                value
            else
                return null,
        };
        if (history.revisions.len == 0) return null;
        return &history.revisions[history.revisions.len - 1];
    }
};

/// Loads both exact-schema streams for one random workspace and replays every
/// revision through the public validating engine path. `out` is untouched on
/// failure.
pub fn loadWorkspaceInto(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    out: *LoadedWorkspace,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    workspace_id: draft.DraftWorkspaceId,
    filer_profile_id: []const u8,
    context: ui.FilingContext,
) Error!void {
    try key_custody.requireSyntheticPlaintextForTest(
        plaintext_capability,
    );
    var key_storage = FilingKeyStorage.init(filer_profile_id, context);
    defer sensitive_memory.wipeValue(FilingKeyStorage, &key_storage);
    const expected_key = key_storage.borrowed(filer_profile_id);

    const editable_schema = try draft.SchemaBinding.exact1701Q(
        .editable_save,
    );
    const final_schema = try draft.SchemaBinding.exact1701Q(
        .final_copy_plaintext,
    );
    const editable_identity: draft.DraftIdentity = .{
        .workspace_id = workspace_id,
        .exact_schema_digest = editable_schema.exact_schema_digest,
    };
    const final_identity: draft.DraftIdentity = .{
        .workspace_id = workspace_id,
        .exact_schema_digest = final_schema.exact_schema_digest,
    };

    var editable = try loadBoundedExactHistory(
        plaintext_capability,
        repository,
        allocator,
        editable_identity,
    );
    var editable_owned = editable != null;
    defer if (editable_owned) {
        editable.?.deinit(allocator);
    };
    var final_copy = try loadBoundedExactHistory(
        plaintext_capability,
        repository,
        allocator,
        final_identity,
    );
    var final_owned = final_copy != null;
    defer if (final_owned) {
        final_copy.?.deinit(allocator);
    };
    if (editable == null and final_copy == null) {
        return error.EmptyPersistedWorkspace;
    }

    if (editable) |*history| {
        if (!filingKeyEql(history.filing_key.borrowed(), expected_key)) {
            return error.FilingBusinessKeyMismatch;
        }
    }
    if (final_copy) |*history| {
        if (!filingKeyEql(history.filing_key.borrowed(), expected_key)) {
            return error.FilingBusinessKeyMismatch;
        }
    }

    var workspace = try workflow.Workspace.init(
        allocator,
        workspace_id,
    );
    var workspace_owned = true;
    defer if (workspace_owned) workspace.deinit();
    if (editable) |*history| {
        try replayOwnedHistory(
            &workspace.editable_history,
            history,
        );
    }
    if (final_copy) |*history| {
        try replayOwnedHistory(
            &workspace.final_history,
            history,
        );
    }

    out.* = .{
        .allocator = allocator,
        .workspace = workspace,
        .editable_history = editable,
        .final_history = final_copy,
    };
    sensitive_memory.wipeValue(workflow.Workspace, &workspace);
    sensitive_memory.wipeValue(
        ?store.OwnedExactDraftHistory,
        &editable,
    );
    sensitive_memory.wipeValue(
        ?store.OwnedExactDraftHistory,
        &final_copy,
    );
    workspace_owned = false;
    editable_owned = false;
    final_owned = false;
}

fn loadBoundedExactHistory(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    identity: draft.DraftIdentity,
) Error!?store.OwnedExactDraftHistory {
    return repository.getExactDraftHistory(
        plaintext_capability,
        allocator,
        identity,
    ) catch |err| switch (err) {
        // Preserve the store's precise limit reason. The repository returns
        // no owned history on either path, and loadWorkspaceInto's defers
        // release the already-loaded sibling before propagating the error.
        error.DraftRevisionLimitExceeded,
        error.DraftRetainedValueLimitExceeded,
        => return err,
        else => return err,
    };
}

/// Validates the latest immutable role bindings against the explicitly
/// supplied historical projection, then consumes the replayed engine
/// workspace into `out` only after UI recalculation, validation, ordered
/// occurrence, digest, and artifact parity all pass. Non-form validation
/// inputs come only from the selected revision's immutable receipt; this API
/// deliberately has no caller-supplied reopen-evidence parameter.
pub fn reopenStateInto(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    out: *ui.State,
    loaded: *LoadedWorkspace,
    selected_shape: draft.PayloadShape,
    context: ui.FilingContext,
    historical_profile: *const projection.Snapshot,
    role_instances: []const RoleInstanceBinding,
) Error!ui.OpenStatus {
    try key_custody.requireSyntheticPlaintextForTest(
        plaintext_capability,
    );
    if (!loaded.workspace_owned) {
        return error.LoadedWorkspaceAlreadyConsumed;
    }
    const persisted = loaded.currentPersistedRevision(
        selected_shape,
    ) orelse return error.SelectedShapeMissing;
    if (!historical_profile.effective_on.eql(
        try context.profileAsOf(),
    )) {
        return error.ProfileAsOfMismatch;
    }
    const expected_date = dateText(historical_profile.effective_on);
    if (!std.mem.eql(
        u8,
        persisted.profile_as_of,
        &expected_date,
    )) {
        return error.ProfileAsOfMismatch;
    }

    const supplied_profile_digest = try historicalProfileDigest(
        historical_profile,
    );
    if (!supplied_profile_digest.eql(
        &persisted.profile_snapshot_digest,
    )) {
        return error.HistoricalProfileDigestMismatch;
    }
    var expected_storage: [max_role_bindings]store.ExactDraftRoleBindingWrite = undefined;
    const expected_bindings = try buildRoleBindingWrites(
        historical_profile,
        role_instances,
        &expected_storage,
    );
    if (!ownedBindingsMatch(
        persisted.bindings,
        expected_bindings,
    )) {
        return error.PersistedBindingMismatch;
    }

    const status = try ui.State.reopenInto(
        out,
        loaded.allocator,
        &loaded.workspace,
        selected_shape,
        context,
        historical_profile,
        .{
            .validation_current_year = persisted.validation_evidence.validation_current_year,
            .spouse_tin_checksum = persisted.validation_evidence.spouse_tin_checksum,
        },
    );
    switch (status) {
        .opened => loaded.workspace_owned = false,
        .blocked => {},
    }
    return status;
}

pub fn listAlternateWorkspaces(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    filer_profile_id: []const u8,
    context: ui.FilingContext,
    excluding_workspace_id: ?draft.DraftWorkspaceId,
) Error!store.ExactDraftAlternateList {
    try key_custody.requireSyntheticPlaintextForTest(
        plaintext_capability,
    );
    var key_storage = FilingKeyStorage.init(filer_profile_id, context);
    defer sensitive_memory.wipeValue(FilingKeyStorage, &key_storage);
    return repository.listExactDraftAlternates(
        plaintext_capability,
        allocator,
        key_storage.borrowed(filer_profile_id),
        excluding_workspace_id,
    );
}

fn replayOwnedHistory(
    destination: *draft.DraftHistory,
    persisted: *const store.OwnedExactDraftHistory,
) Error!void {
    if (!destination.identity.eql(&persisted.draft_identity)) {
        return error.PersistedHistoryMismatch;
    }
    for (persisted.revisions) |*revision| {
        var values: [max_occurrences]draft.OccurrenceValue = undefined;
        defer sensitive_memory.wipeValue(
            [max_occurrences]draft.OccurrenceValue,
            &values,
        );
        if (revision.occurrences.len > values.len) {
            return error.PersistedHistoryMismatch;
        }
        for (revision.occurrences, 0..) |value, index| {
            values[index] = .{
                .ordinal = value.ordinal,
                .serialized_key = value.serialized_key,
                .same_key_occurrence = value.same_key_occurrence,
                .raw_value = value.raw_value,
                .normalized_value = value.normalized_value,
                .emitted_value = value.emitted_value,
            };
        }
        const replayed = try destination.replayPersistedRevision(.{
            .draft_identity = persisted.draft_identity,
            .revision = revision.revision,
            .parent_revision = revision.parent_revision,
            .schema = revision.schema,
            .occurrences = values[0..revision.occurrences.len],
            .profile_snapshot_digest = revision.profile_snapshot_digest,
            .transaction_state_digest = revision.transaction_state_digest,
            .ordered_values_digest = revision.ordered_values_digest,
            .validation_status = revision.validation_status,
            .artifact_status = revision.artifact_status,
        });
        if (!engineRevisionMatchesOwned(replayed, revision)) {
            return error.PersistedHistoryMismatch;
        }
    }
}

fn engineRevisionMatchesOwned(
    engine: *const draft.DraftSnapshot,
    owned: *const store.OwnedExactDraftRevision,
) bool {
    if (engine.revision.value != owned.revision.value or
        !optionalRevisionEql(
            engine.parent_revision,
            owned.parent_revision,
        ) or
        !schemaEql(&engine.schema, &owned.schema) or
        !engine.profile_snapshot_digest.eql(
            &owned.profile_snapshot_digest,
        ) or
        !engine.transaction_state_digest.eql(
            &owned.transaction_state_digest,
        ) or
        !engine.ordered_values_digest.eql(
            &owned.ordered_values_digest,
        ) or
        !std.meta.eql(
            engine.validation_status,
            owned.validation_status,
        ) or
        !std.meta.eql(
            engine.artifact_status,
            owned.artifact_status,
        ) or
        engine.occurrences.len != owned.occurrences.len)
    {
        return false;
    }
    for (engine.occurrences, owned.occurrences) |left, right| {
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

fn schemaEql(
    left: *const draft.SchemaBinding,
    right: *const draft.SchemaBinding,
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

fn optionalRevisionEql(
    left: ?draft.DraftRevision,
    right: ?draft.DraftRevision,
) bool {
    if (left == null or right == null) return left == null and right == null;
    return left.?.value == right.?.value;
}

fn historicalProfileDigest(
    historical_profile: *const projection.Snapshot,
) Error!@TypeOf(evidence.package_key.canonicalDigest()) {
    const mapped_outcome = profile_mapping.mapProfileSnapshot(
        historical_profile.*,
    );
    return switch (mapped_outcome) {
        .blocked => error.HistoricalProfileBindingMismatch,
        .accepted => |accepted| blk: {
            var mapped = accepted;
            defer sensitive_memory.wipeValue(
                profile_mapping.ControlSnapshot,
                &mapped,
            );
            var editing = try workflow.Editing.init(&mapped);
            defer editing.deinit();
            const digests = try editing.transaction_state.digestBundle();
            break :blk digests.profile_snapshot;
        },
    };
}

fn buildRoleBindingWrites(
    profile: *const projection.Snapshot,
    supplied: []const RoleInstanceBinding,
    output: *[max_role_bindings]store.ExactDraftRoleBindingWrite,
) Error![]const store.ExactDraftRoleBindingWrite {
    if (supplied.len == 0 or supplied.len > output.len) {
        return error.InvalidRoleBinding;
    }
    var filer_count: usize = 0;
    var spouse_count: usize = 0;
    for (supplied, 0..) |binding, index| {
        switch (binding.role) {
            .filer => filer_count += 1,
            .spouse => spouse_count += 1,
            else => return error.InvalidRoleBinding,
        }
        if (binding.instance_id.len == 0 or
            binding.provenance.len == 0)
        {
            return error.InvalidRoleBinding;
        }
        for (supplied[index + 1 ..]) |other| {
            if (binding.role == other.role and
                std.mem.eql(
                    u8,
                    binding.instance_id,
                    other.instance_id,
                ))
            {
                return error.DuplicateRoleBinding;
            }
        }

        const historical = try provenanceForRole(
            profile,
            binding.role,
            binding.business_activity_id,
        );
        output[index] = .{
            .role = @tagName(binding.role),
            .instance_id = binding.instance_id,
            .profile_id = historical.profile_id.asSlice(),
            .profile_revision_id = historical.revision_id.asSlice(),
            .profile_revision_sequence = historical.revision_sequence,
            .business_activity_id = binding.business_activity_id,
            .provenance = binding.provenance,
        };
    }
    if (filer_count != 1) return error.MissingFilerBinding;
    if (spouse_count > 1) return error.InvalidRoleBinding;

    const profile_has_spouse = profileRolePresent(profile, .spouse);
    if (profile_has_spouse and spouse_count == 0) {
        return error.MissingSpouseBinding;
    }
    if (!profile_has_spouse and spouse_count != 0) {
        return error.UnexpectedSpouseBinding;
    }
    return output[0..supplied.len];
}

fn provenanceForRole(
    profile: *const projection.Snapshot,
    role: ids.Role,
    expected_business_activity_id: ?[]const u8,
) Error!*const projection.Provenance {
    var representative: ?*const projection.Provenance = null;
    for (profile.slice()) |*entry| {
        if (entry.role != role) continue;
        if (representative) |prior| {
            if (!prior.profile_id.eql(
                &entry.provenance.profile_id,
            ) or
                !prior.revision_id.eql(
                    &entry.provenance.revision_id,
                ) or
                prior.revision_sequence !=
                    entry.provenance.revision_sequence)
            {
                return error.HistoricalProfileBindingMismatch;
            }
        } else {
            representative = &entry.provenance;
        }
        if (entry.provenance.business_activity_id) |activity| {
            const expected = expected_business_activity_id orelse
                return error.HistoricalProfileBindingMismatch;
            if (!std.mem.eql(u8, activity.asSlice(), expected)) {
                return error.HistoricalProfileBindingMismatch;
            }
        }
    }
    return representative orelse
        error.HistoricalProfileBindingMismatch;
}

fn profileRolePresent(
    profile: *const projection.Snapshot,
    role: ids.Role,
) bool {
    for (profile.slice()) |entry| {
        if (entry.role == role) return true;
    }
    return false;
}

fn filerProfileId(
    bindings: []const store.ExactDraftRoleBindingWrite,
) ?[]const u8 {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.role, "filer")) {
            return binding.profile_id;
        }
    }
    return null;
}

fn buildOccurrenceContexts(
    snapshot: *const draft.DraftSnapshot,
    output: *[max_occurrences]store.ExactDraftOccurrenceContextWrite,
) Error![]const store.ExactDraftOccurrenceContextWrite {
    const manifest = switch (snapshot.schema.payload_shape) {
        .editable_save => try occurrences.editableManifest(),
        .final_copy_plaintext => try occurrences.finalCopyManifest(),
    };
    if (manifest.items.len != snapshot.occurrences.len or
        manifest.items.len > output.len)
    {
        return error.PersistedOccurrenceContextMismatch;
    }
    for (manifest.items, snapshot.occurrences, 0..) |
        metadata,
        value,
        index,
    | {
        if (metadata.ordinal != value.ordinal or
            metadata.same_key_occurrence !=
                value.same_key_occurrence or
            !std.mem.eql(
                u8,
                metadata.serialized_key,
                value.serialized_key,
            ))
        {
            return error.PersistedOccurrenceContextMismatch;
        }
        const origin = try occurrenceOrigin(metadata);
        output[index] = .{
            .ordinal = value.ordinal,
            .origin = origin,
            .provenance = occurrenceProvenance(origin),
        };
    }
    return output[0..manifest.items.len];
}

fn occurrenceOrigin(
    metadata: occurrence.OccurrenceMetadata,
) Error!occurrence.OriginKind {
    var result: ?occurrence.OriginKind = null;
    for (0..metadata.source_controls.len()) |source_index| {
        const control_id = metadata.source_controls.at(
            @intCast(source_index),
        ).?;
        const candidate = transaction.classifyControl(control_id) orelse
            return error.PersistedOccurrenceContextMismatch;
        if (result) |prior| {
            if (prior != candidate) {
                return error.PersistedOccurrenceContextMismatch;
            }
        } else {
            result = candidate;
        }
    }
    return result orelse error.PersistedOccurrenceContextMismatch;
}

fn occurrenceProvenance(origin: occurrence.OriginKind) []const u8 {
    return switch (origin) {
        .profile => "immutable_profile_revision_binding",
        .transaction => "form_transaction",
        .preparer => "credential_locked_empty",
        .filing_context => "explicit_filing_context",
        .external_evidence => "historical_external_evidence",
        .derived => "grounded_calculation",
        .system => "grounded_runtime_system_value",
        .unreviewed => unreachable,
    };
}

fn ownedBindingsMatch(
    owned: []const store.OwnedExactDraftRoleBinding,
    expected: []const store.ExactDraftRoleBindingWrite,
) bool {
    if (owned.len != expected.len) return false;
    for (expected) |right| {
        const left = findOwnedBinding(
            owned,
            right.role,
            right.instance_id,
        ) orelse return false;
        if (!std.mem.eql(u8, left.profile_id, right.profile_id) or
            !std.mem.eql(
                u8,
                left.profile_revision_id,
                right.profile_revision_id,
            ) or
            left.profile_revision_sequence !=
                right.profile_revision_sequence or
            !optionalTextEql(
                left.business_activity_id,
                right.business_activity_id,
            ) or
            !std.mem.eql(u8, left.provenance, right.provenance))
        {
            return false;
        }
    }
    return true;
}

fn findOwnedBinding(
    bindings: []const store.OwnedExactDraftRoleBinding,
    role: []const u8,
    instance_id: []const u8,
) ?*const store.OwnedExactDraftRoleBinding {
    for (bindings) |*binding| {
        if (std.mem.eql(u8, binding.role, role) and
            std.mem.eql(u8, binding.instance_id, instance_id))
        {
            return binding;
        }
    }
    return null;
}

fn optionalTextEql(
    left: ?[]const u8,
    right: ?[]const u8,
) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

const FilingKeyStorage = struct {
    period_key: [7]u8,
    intent: store.FilingIntent,

    fn init(
        filer_profile_id: []const u8,
        context: ui.FilingContext,
    ) FilingKeyStorage {
        _ = filer_profile_id;
        const year = context.tax_year;
        return .{
            .period_key = .{
                @intCast('0' + (year / 1000) % 10),
                @intCast('0' + (year / 100) % 10),
                @intCast('0' + (year / 10) % 10),
                @intCast('0' + year % 10),
                '-',
                'Q',
                @as(u8, '0') +
                    @as(u8, @intFromEnum(context.quarter)),
            },
            .intent = if (context.amended) .amended else .original,
        };
    }

    fn borrowed(
        self: *const FilingKeyStorage,
        filer_profile_id: []const u8,
    ) store.CanonicalFilingBusinessKeyWrite {
        return .{
            .filer_profile_id = filer_profile_id,
            .form_code = evidence.package_key.revision.code.asSlice(),
            .form_revision = evidence.package_key.revision.revision.asSlice(),
            .period_key = &self.period_key,
            .intent = self.intent,
        };
    }
};

fn filingKeyEql(
    left: store.CanonicalFilingBusinessKeyWrite,
    right: store.CanonicalFilingBusinessKeyWrite,
) bool {
    return std.mem.eql(
        u8,
        left.filer_profile_id,
        right.filer_profile_id,
    ) and
        std.mem.eql(u8, left.form_code, right.form_code) and
        std.mem.eql(
            u8,
            left.form_revision,
            right.form_revision,
        ) and
        std.mem.eql(u8, left.period_key, right.period_key) and
        left.intent == right.intent;
}

fn dateText(value: model.Date) store.DateText {
    return .{
        @intCast('0' + (value.year / 1000) % 10),
        @intCast('0' + (value.year / 100) % 10),
        @intCast('0' + (value.year / 10) % 10),
        @intCast('0' + value.year % 10),
        '-',
        @intCast('0' + (value.month / 10) % 10),
        @intCast('0' + value.month % 10),
        '-',
        @intCast('0' + (value.day / 10) % 10),
        @intCast('0' + value.day % 10),
    };
}

// -------------------------------------------------------------------------
// Synthetic-only persistence/reopen tests.

fn syntheticPlaintextTestCapability() *const key_custody.SyntheticPlaintextTestCapability {
    return key_custody.acquireSyntheticPlaintextForTest();
}

fn testHistoricalProfile(
    revision_id: []const u8,
    email: []const u8,
    effective_on: model.Date,
) !projection.Snapshot {
    var snapshot = projection.Snapshot.init(form.revision, effective_on);
    const provenance: projection.Provenance = .{
        .profile_id = try model.ProfileId.parse(
            "persistence-synthetic-filer",
        ),
        .revision_id = try model.RevisionId.parse(revision_id),
        .revision_sequence = if (std.mem.endsWith(
            u8,
            revision_id,
            "r2",
        ))
            2
        else
            1,
        .revision_source = .manual_entry,
    };
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[0].target,
        .value = .{ .tin = try field.Tin.parse("123-456-789-000") },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[1].target,
        .value = .{ .rdo_code = try field.RdoCode.parse("019") },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[2].target,
        .value = .{
            .taxpayer_name = try field.TaxpayerName.parse(
                "PERSISTENCE SYNTHETIC FILER",
            ),
        },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[3].target,
        .value = .{
            .registered_address = try field.RegisteredAddress.parse(
                "SYNTHETIC PERSISTENCE ADDRESS",
            ),
        },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[4].target,
        .value = .{ .zip_code = try field.ZipCode.parse("1000") },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[5].target,
        .value = .{
            .date_of_birth = try model.Date.init(1990, 1, 15),
        },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[6].target,
        .value = .{
            .email_address = try field.EmailAddress.parse(email),
        },
        .provenance = provenance,
    });
    return snapshot;
}

fn testMixedHistoricalProfile(
    revision_id: []const u8,
    effective_on: model.Date,
) !projection.Snapshot {
    var snapshot = try testHistoricalProfile(
        revision_id,
        "Synthetic.R1@Example.Test",
        effective_on,
    );
    for (snapshot.entries[0..snapshot.len]) |*entry| {
        if (entry.target.eql(&form.filer_requirements[2].target)) {
            entry.value = .{
                .taxpayer_name = try field.TaxpayerName.parse(
                    "Persistence Synthetic Filer",
                ),
            };
        } else if (entry.target.eql(
            &form.filer_requirements[3].target,
        )) {
            entry.value = .{
                .registered_address = try field.RegisteredAddress.parse(
                    "Synthetic Persistence Address",
                ),
            };
        }
    }
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[7].target,
        .value = .{
            .citizenship = try field.Citizenship.parse("Filipino"),
        },
        .provenance = snapshot.entries[0].provenance,
    });
    return snapshot;
}

fn expectRevealedControlText(
    state: *ui.State,
    control_id: []const u8,
    expected: []const u8,
) !void {
    try state.setControlRevealed(control_id, true);
    defer state.setControlRevealed(control_id, false) catch {};
    switch ((try state.control(control_id)).display) {
        .revealed_text => |actual| {
            try std.testing.expectEqualStrings(expected, actual);
        },
        else => return error.ExpectedRevealedControlText,
    }
}

const test_context: ui.FilingContext = .{
    .tax_year = 2025,
    .quarter = .first,
    .amended = false,
};

const test_role_instances = [_]RoleInstanceBinding{.{
    .role = .filer,
    .instance_id = "synthetic-filer-instance",
}};

fn openSyntheticState(
    out: *ui.State,
    allocator: std.mem.Allocator,
    workspace_id: draft.DraftWorkspaceId,
    profile: *const projection.Snapshot,
) !void {
    switch (try ui.State.openInto(
        out,
        allocator,
        workspace_id,
        test_context,
        profile,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
}

fn selectRequiredSyntheticElections(state: *ui.State) !void {
    try state.setRadio("frm1701q:optType_1", true);
    try state.setRadio("frm1701q:optATC_1", true);
    try state.setRadio("frm1701q:optTaxRate_1", true);
    try state.setRadio(
        "frm1701q:optMethodOfDeduction:_1",
        true,
    );
}

fn savePassed(state: *ui.State) !void {
    switch (try state.validateSave(2026, .not_evaluated)) {
        .passed => {},
        .failed => return error.ExpectedSavePass,
    }
}

fn fullPassed(state: *ui.State) !void {
    switch (try state.validateFull()) {
        .passed => {},
        .failed, .blocked => return error.ExpectedFullPass,
    }
}

fn seedSyntheticProfileRepository(repository: *store.Store) !void {
    try repository.createProfileWithRevision(
        .{ .id = "persistence-synthetic-filer" },
        .{
            .id = "persistence-synthetic-filer-r1",
            .profile_id = "persistence-synthetic-filer",
            .sequence = 1,
            .expected_current_sequence = 0,
            .effective = .{
                .from = dateText(try model.Date.init(2020, 1, 1)),
            },
            .source = .manual_entry,
            .identity = .{
                .tin = "123-456-789-000",
                .rdo_code = "019",
            },
            .contact = .{
                .registered_address = "SYNTHETIC PERSISTENCE ADDRESS",
                .zip_code = "1000",
                .email_address = "synthetic-r1@example.test",
            },
            .subject = .{ .individual = .{
                .name = "PERSISTENCE SYNTHETIC FILER",
                .date_of_birth = dateText(
                    try model.Date.init(1990, 1, 15),
                ),
            } },
        },
        .{},
    );
}

fn expectCandidateSummaryEqual(
    left: ui.CandidateSummary,
    right: ui.CandidateSummary,
) !void {
    try std.testing.expectEqual(left.shape, right.shape);
    try std.testing.expectEqual(left.exactness, right.exactness);
    try std.testing.expectEqual(left.byte_length, right.byte_length);
    try std.testing.expectEqualSlices(u8, &left.sha256, &right.sha256);
}

test "exact persistence boundary is plaintext synthetic-only and has no submission surface" {
    try std.testing.expect(synthetic_test_only_at_rest);
    try std.testing.expectEqual(
        key_custody.PlaintextStorageState.synthetic_plaintext_test_only,
        SecurityBoundary.plaintext_storage_state,
    );
    try std.testing.expectEqual(
        key_custody.ProductionStorageState
            .unavailable_authenticated_storage_backend_unselected,
        SecurityBoundary.production_storage_state,
    );
    try std.testing.expectError(
        error.ProductionStorageUnavailable,
        key_custody.requireProductionStorage(),
    );
    try std.testing.expect(
        SecurityBoundary.synthetic_plaintext_persistence_enabled,
    );
    try std.testing.expect(SecurityBoundary.sqlite_values_are_plaintext);
    try std.testing.expect(SecurityBoundary.synthetic_test_only);
    try std.testing.expect(
        !SecurityBoundary.production_key_custody_qualified,
    );
    try std.testing.expect(
        !SecurityBoundary.outbound_encryption_enabled,
    );
    try std.testing.expect(!SecurityBoundary.transport_enabled);
    try std.testing.expect(!@hasDecl(@This(), "submit"));
    try std.testing.expect(!@hasDecl(@This(), "encrypt"));
    try std.testing.expect(!@hasDecl(@This(), "upload"));
}

test "editable and Final sibling streams persist, replay, and reopen exactly" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);

    var profile = try testMixedHistoricalProfile(
        "persistence-synthetic-filer-r1",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(projection.Snapshot, &profile);
    const workspace_id = try repository.generateDraftWorkspaceId();

    var state: ui.State = undefined;
    try openSyntheticState(
        &state,
        allocator,
        workspace_id,
        &profile,
    );
    defer state.deinit();
    try selectRequiredSyntheticElections(&state);
    const qualified_blur_context: ui.QualifiedBlurContext = .{
        .current_year = 2026,
        .schedule_date = .{
            .current_date = .{ .year = 2026, .month = 7, .day = 30 },
            .empty_default_input_was_later = false,
        },
    };
    _ = try state.commitAndBlurQualified(
        "frm1701q:txtSheets",
        "2",
        qualified_blur_context,
    );
    _ = try state.commitAndBlurQualified(
        "frm1701q:txt36A",
        "123.45",
        qualified_blur_context,
    );
    try expectRevealedControlText(
        &state,
        "frm1701q:txtTaxpayerName",
        "PERSISTENCE SYNTHETIC FILER",
    );
    try expectRevealedControlText(
        &state,
        "frm1701q:txtAddress",
        "SYNTHETIC PERSISTENCE ADDRESS",
    );
    try expectRevealedControlText(
        &state,
        "frm1701q:txtCitizenship",
        "FILIPINO",
    );
    try expectRevealedControlText(
        &state,
        "txtEmail",
        "Synthetic.R1@Example.Test",
    );
    try state.calculate();
    try savePassed(&state);
    try state.generateEditableCandidate(.create);
    const editable_summary = try state.candidateSummary();
    const editable_receipt = try persistCurrentCandidate(
        syntheticPlaintextTestCapability(),
        &repository,
        &state,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_000_001,
            .guard = .create,
        },
    );
    try std.testing.expectEqual(
        draft.PayloadShape.editable_save,
        editable_receipt.shape,
    );

    try fullPassed(&state);
    try state.generateFinalCandidate(.create);
    const final_summary = try state.candidateSummary();
    const final_receipt = try persistCurrentCandidate(
        syntheticPlaintextTestCapability(),
        &repository,
        &state,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_000_002,
            .guard = .create,
        },
    );
    try std.testing.expect(
        editable_receipt.draft_identity.workspace_id.eql(
            &final_receipt.draft_identity.workspace_id,
        ),
    );
    try std.testing.expect(
        !editable_receipt.draft_identity.exact_schema_digest.eql(
            &final_receipt.draft_identity.exact_schema_digest,
        ),
    );

    var loaded: LoadedWorkspace = undefined;
    try loadWorkspaceInto(
        syntheticPlaintextTestCapability(),
        &loaded,
        &repository,
        allocator,
        workspace_id,
        "persistence-synthetic-filer",
        test_context,
    );
    defer loaded.deinit();
    try std.testing.expectEqual(
        @as(usize, 1),
        loaded.revisionCount(.editable_save),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        loaded.revisionCount(.final_copy_plaintext),
    );
    const persisted_editable = loaded.currentPersistedRevision(
        .editable_save,
    ).?;
    const persisted_final = loaded.currentPersistedRevision(
        .final_copy_plaintext,
    ).?;
    try std.testing.expect(std.meta.eql(
        persisted_editable.validation_evidence,
        persisted_final.validation_evidence,
    ));
    try std.testing.expectEqual(
        @as(usize, 173),
        persisted_final.occurrences.len,
    );
    try std.testing.expectEqual(
        @as(i64, 1_750_000_002),
        persisted_final.recorded_at_unix_seconds,
    );
    try std.testing.expectEqual(
        @as(i32, 2026),
        persisted_final.validation_evidence.validation_current_year,
    );
    try std.testing.expectEqual(
        validation.TinChecksumStatus.not_evaluated,
        persisted_final.validation_evidence.spouse_tin_checksum,
    );
    try std.testing.expectEqualStrings(
        "2025-03-31",
        persisted_final.profile_as_of,
    );
    try std.testing.expectEqualStrings(
        "persistence-synthetic-filer-r1",
        persisted_final.bindings[0].profile_revision_id,
    );
    try std.testing.expectEqualStrings(
        "synthetic-filer-instance",
        persisted_final.bindings[0].instance_id,
    );
    for (persisted_final.occurrences) |value| {
        try std.testing.expect(value.origin != .unreviewed);
        try std.testing.expect(value.provenance.len != 0);
    }
    // The caveat is observable and permanent: values are plaintext.
    var saw_synthetic_value = false;
    for (persisted_final.occurrences) |value| {
        if (std.mem.eql(u8, value.raw_value, "123.45")) {
            saw_synthetic_value = true;
            break;
        }
    }
    try std.testing.expect(saw_synthetic_value);

    var forged_token: u8 = 0;
    const forged: *const key_custody.SyntheticPlaintextTestCapability =
        @ptrCast(&forged_token);
    var rejected_reopen: ui.State = undefined;
    try std.testing.expectError(
        error.InvalidSyntheticPlaintextTestCapability,
        reopenStateInto(
            forged,
            &rejected_reopen,
            &loaded,
            .final_copy_plaintext,
            test_context,
            &profile,
            &test_role_instances,
        ),
    );
    try std.testing.expect(loaded.workspace_owned);

    var reopened: ui.State = undefined;
    switch (try reopenStateInto(
        syntheticPlaintextTestCapability(),
        &reopened,
        &loaded,
        .final_copy_plaintext,
        test_context,
        &profile,
        &test_role_instances,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    defer reopened.deinit();
    try std.testing.expectEqual(ui.Phase.final_candidate, reopened.phase());
    try expectCandidateSummaryEqual(
        final_summary,
        try reopened.candidateSummary(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        reopened.editableRevisionCount(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        reopened.finalRevisionCount(),
    );
    try expectRevealedControlText(
        &reopened,
        "frm1701q:txtTaxpayerName",
        "PERSISTENCE SYNTHETIC FILER",
    );
    try expectRevealedControlText(
        &reopened,
        "frm1701q:txtAddress",
        "SYNTHETIC PERSISTENCE ADDRESS",
    );
    try expectRevealedControlText(
        &reopened,
        "frm1701q:txtCitizenship",
        "FILIPINO",
    );
    try expectRevealedControlText(
        &reopened,
        "txtEmail",
        "Synthetic.R1@Example.Test",
    );

    var loaded_editable: LoadedWorkspace = undefined;
    try loadWorkspaceInto(
        syntheticPlaintextTestCapability(),
        &loaded_editable,
        &repository,
        allocator,
        workspace_id,
        "persistence-synthetic-filer",
        test_context,
    );
    defer loaded_editable.deinit();
    var reopened_editable: ui.State = undefined;
    switch (try reopenStateInto(
        syntheticPlaintextTestCapability(),
        &reopened_editable,
        &loaded_editable,
        .editable_save,
        test_context,
        &profile,
        &test_role_instances,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    defer reopened_editable.deinit();
    try expectCandidateSummaryEqual(
        editable_summary,
        try reopened_editable.candidateSummary(),
    );
    try expectRevealedControlText(
        &reopened_editable,
        "frm1701q:txtTaxpayerName",
        "PERSISTENCE SYNTHETIC FILER",
    );
    try expectRevealedControlText(
        &reopened_editable,
        "frm1701q:txtAddress",
        "SYNTHETIC PERSISTENCE ADDRESS",
    );
    try expectRevealedControlText(
        &reopened_editable,
        "frm1701q:txtCitizenship",
        "FILIPINO",
    );
    try expectRevealedControlText(
        &reopened_editable,
        "txtEmail",
        "Synthetic.R1@Example.Test",
    );
}

test "reopen requires old immutable profile binding and rejects context substitution" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);
    var old_profile = try testHistoricalProfile(
        "persistence-synthetic-filer-r1",
        "synthetic-old@example.test",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(
        projection.Snapshot,
        &old_profile,
    );
    const workspace_id = try repository.generateDraftWorkspaceId();
    var state: ui.State = undefined;
    try openSyntheticState(
        &state,
        allocator,
        workspace_id,
        &old_profile,
    );
    defer state.deinit();
    try selectRequiredSyntheticElections(&state);
    try state.calculate();
    try savePassed(&state);
    try state.generateEditableCandidate(.create);
    _ = try persistCurrentCandidate(
        syntheticPlaintextTestCapability(),
        &repository,
        &state,
        .{
            .historical_profile = &old_profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_000_010,
            .guard = .create,
        },
    );

    const wrong_context: ui.FilingContext = .{
        .tax_year = 2025,
        .quarter = .second,
        .amended = false,
    };
    var wrong_loaded: LoadedWorkspace = undefined;
    try std.testing.expectError(
        error.FilingBusinessKeyMismatch,
        loadWorkspaceInto(
            syntheticPlaintextTestCapability(),
            &wrong_loaded,
            &repository,
            allocator,
            workspace_id,
            "persistence-synthetic-filer",
            wrong_context,
        ),
    );

    var loaded: LoadedWorkspace = undefined;
    try loadWorkspaceInto(
        syntheticPlaintextTestCapability(),
        &loaded,
        &repository,
        allocator,
        workspace_id,
        "persistence-synthetic-filer",
        test_context,
    );
    defer loaded.deinit();
    var current_profile = try testHistoricalProfile(
        "persistence-synthetic-filer-r2",
        "synthetic-current@example.test",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(
        projection.Snapshot,
        &current_profile,
    );
    var rejected_state: ui.State = undefined;
    try std.testing.expectError(
        error.HistoricalProfileDigestMismatch,
        reopenStateInto(
            syntheticPlaintextTestCapability(),
            &rejected_state,
            &loaded,
            .editable_save,
            test_context,
            &current_profile,
            &test_role_instances,
        ),
    );
    try std.testing.expect(loaded.workspace_owned);

    var reopened: ui.State = undefined;
    switch (try reopenStateInto(
        syntheticPlaintextTestCapability(),
        &reopened,
        &loaded,
        .editable_save,
        test_context,
        &old_profile,
        &test_role_instances,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    defer reopened.deinit();
}

test "stale writer and tampered replay fail without mutating committed history" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);
    var profile = try testHistoricalProfile(
        "persistence-synthetic-filer-r1",
        "synthetic-stale@example.test",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(projection.Snapshot, &profile);
    const workspace_id = try repository.generateDraftWorkspaceId();
    var state: ui.State = undefined;
    try openSyntheticState(
        &state,
        allocator,
        workspace_id,
        &profile,
    );
    defer state.deinit();
    try selectRequiredSyntheticElections(&state);
    try state.calculate();
    try savePassed(&state);
    try state.generateEditableCandidate(.create);
    const first = try persistCurrentCandidate(
        syntheticPlaintextTestCapability(),
        &repository,
        &state,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_000_020,
            .guard = .create,
        },
    );
    try state.generateEditableCandidate(.{
        .match = first.revision,
    });
    try std.testing.expectError(
        error.DraftStaleRevision,
        persistCurrentCandidate(
            syntheticPlaintextTestCapability(),
            &repository,
            &state,
            .{
                .historical_profile = &profile,
                .role_instances = &test_role_instances,
                .recorded_at_unix_seconds = 1_750_000_021,
                .guard = .{
                    .match = try draft.DraftRevision.init(2),
                },
            },
        ),
    );

    const schema = try draft.SchemaBinding.exact1701Q(
        .editable_save,
    );
    const identity: draft.DraftIdentity = .{
        .workspace_id = workspace_id,
        .exact_schema_digest = schema.exact_schema_digest,
    };
    var persisted = (try repository.getExactDraftHistory(
        syntheticPlaintextTestCapability(),
        allocator,
        identity,
    )).?;
    defer persisted.deinit(allocator);
    try std.testing.expectEqual(
        @as(usize, 1),
        persisted.revisions.len,
    );

    const owned = &persisted.revisions[0];
    var values: [max_occurrences]draft.OccurrenceValue = undefined;
    defer sensitive_memory.wipeValue(
        [max_occurrences]draft.OccurrenceValue,
        &values,
    );
    for (owned.occurrences, 0..) |value, index| {
        values[index] = .{
            .ordinal = value.ordinal,
            .serialized_key = value.serialized_key,
            .same_key_occurrence = value.same_key_occurrence,
            .raw_value = value.raw_value,
            .normalized_value = value.normalized_value,
            .emitted_value = value.emitted_value,
        };
    }
    var history = try draft.DraftHistory.initExact1701Q(
        allocator,
        workspace_id,
        .editable_save,
    );
    defer history.deinit();
    var tampered_digest = owned.ordered_values_digest;
    tampered_digest.bytes[0] ^= 0xff;
    try std.testing.expectError(
        error.ReplayOrderedValuesDigestMismatch,
        history.replayPersistedRevision(.{
            .draft_identity = identity,
            .revision = owned.revision,
            .parent_revision = owned.parent_revision,
            .schema = owned.schema,
            .occurrences = values[0..owned.occurrences.len],
            .profile_snapshot_digest = owned.profile_snapshot_digest,
            .transaction_state_digest = owned.transaction_state_digest,
            .ordered_values_digest = tampered_digest,
            .validation_status = owned.validation_status,
            .artifact_status = owned.artifact_status,
        }),
    );
    try std.testing.expectEqual(@as(usize, 0), history.revisionCount());

    values[0].ordinal = 2;
    try std.testing.expectError(
        error.OccurrenceOrdinalMismatch,
        history.replayPersistedRevision(.{
            .draft_identity = identity,
            .revision = owned.revision,
            .parent_revision = owned.parent_revision,
            .schema = owned.schema,
            .occurrences = values[0..owned.occurrences.len],
            .profile_snapshot_digest = owned.profile_snapshot_digest,
            .transaction_state_digest = owned.transaction_state_digest,
            .ordered_values_digest = owned.ordered_values_digest,
            .validation_status = owned.validation_status,
            .artifact_status = owned.artifact_status,
        }),
    );
    try std.testing.expectEqual(@as(usize, 0), history.revisionCount());

    values[0].ordinal = 1;
    const wrong_shape_schema = try draft.SchemaBinding.exact1701Q(
        .final_copy_plaintext,
    );
    try std.testing.expectError(
        error.ReplaySchemaMismatch,
        history.replayPersistedRevision(.{
            .draft_identity = identity,
            .revision = owned.revision,
            .parent_revision = owned.parent_revision,
            .schema = wrong_shape_schema,
            .occurrences = values[0..owned.occurrences.len],
            .profile_snapshot_digest = owned.profile_snapshot_digest,
            .transaction_state_digest = owned.transaction_state_digest,
            .ordered_values_digest = owned.ordered_values_digest,
            .validation_status = owned.validation_status,
            .artifact_status = owned.artifact_status,
        }),
    );
    try std.testing.expectEqual(@as(usize, 0), history.revisionCount());
}

test "reopen replay rejects cap plus one with a destructible temporary owner" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);
    var profile = try testHistoricalProfile(
        "persistence-synthetic-filer-r1",
        "synthetic-replay-limit@example.test",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(projection.Snapshot, &profile);
    const workspace_id = try repository.generateDraftWorkspaceId();
    var state: ui.State = undefined;
    try openSyntheticState(
        &state,
        allocator,
        workspace_id,
        &profile,
    );
    defer state.deinit();
    try selectRequiredSyntheticElections(&state);
    try state.calculate();
    try savePassed(&state);
    try state.generateEditableCandidate(.create);
    const receipt = try persistCurrentCandidate(
        syntheticPlaintextTestCapability(),
        &repository,
        &state,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_000_025,
            .guard = .create,
        },
    );
    var persisted = (try repository.getExactDraftHistory(
        syntheticPlaintextTestCapability(),
        allocator,
        receipt.draft_identity,
    )).?;
    defer persisted.deinit(allocator);

    var repeated: [
        draft.max_revisions_per_exact_shape_stream +
            1
    ]store.OwnedExactDraftRevision = undefined;
    for (&repeated, 0..) |*revision, index| {
        revision.* = persisted.revisions[0];
        revision.revision = try draft.DraftRevision.init(index + 1);
        revision.parent_revision = if (index == 0)
            null
        else
            try draft.DraftRevision.init(index);
    }
    var forged = persisted;
    forged.revisions = &repeated;

    var temporary = try workflow.Workspace.init(
        allocator,
        workspace_id,
    );
    defer temporary.deinit();
    try std.testing.expectError(
        error.DraftRevisionLimitExceeded,
        replayOwnedHistory(&temporary.editable_history, &forged),
    );
    try std.testing.expectEqual(
        draft.max_revisions_per_exact_shape_stream,
        temporary.editableRevisionCount(),
    );
    try std.testing.expect(
        temporary.editable_history.retainedValueBytes() <=
            draft.max_retained_exact_value_bytes,
    );
}

test "alternate workspace listing groups sibling schema streams" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);
    var profile = try testHistoricalProfile(
        "persistence-synthetic-filer-r1",
        "synthetic-alternate@example.test",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(projection.Snapshot, &profile);

    var workspace_ids: [2]draft.DraftWorkspaceId = undefined;
    for (&workspace_ids, 0..) |*workspace_id, index| {
        workspace_id.* = try repository.generateDraftWorkspaceId();
        var state: ui.State = undefined;
        try openSyntheticState(
            &state,
            allocator,
            workspace_id.*,
            &profile,
        );
        defer state.deinit();
        try selectRequiredSyntheticElections(&state);
        try state.calculate();
        try savePassed(&state);
        try state.generateEditableCandidate(.create);
        _ = try persistCurrentCandidate(
            syntheticPlaintextTestCapability(),
            &repository,
            &state,
            .{
                .historical_profile = &profile,
                .role_instances = &test_role_instances,
                .recorded_at_unix_seconds = 1_750_000_030 + @as(i64, @intCast(index)),
                .guard = .create,
            },
        );
        if (index == 0) {
            try fullPassed(&state);
            try state.generateFinalCandidate(.create);
            _ = try persistCurrentCandidate(
                syntheticPlaintextTestCapability(),
                &repository,
                &state,
                .{
                    .historical_profile = &profile,
                    .role_instances = &test_role_instances,
                    .recorded_at_unix_seconds = 1_750_000_040,
                    .guard = .create,
                },
            );
        }
    }

    var alternates = try listAlternateWorkspaces(
        syntheticPlaintextTestCapability(),
        &repository,
        allocator,
        "persistence-synthetic-filer",
        test_context,
        workspace_ids[1],
    );
    defer alternates.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), alternates.items.len);
    try std.testing.expect(
        alternates.items[0].workspace_id.eql(&workspace_ids[0]),
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        alternates.items[0].schema_stream_count,
    );
}
