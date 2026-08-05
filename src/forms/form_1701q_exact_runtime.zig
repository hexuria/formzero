//! Application-facing development runtime for exact BIR Form 1701Q drafts.
//!
//! This bridge is intentionally narrow. The caller injects the source-minted
//! development plaintext capability and the already-open profile repository;
//! there is no environment switch, path lookup, or production fallback here.
//! It persists only through the exact occurrence adapter and resumes only a
//! single exact workspace matching the canonical filing business key.
//!
//! Exact saves require a frozen, allocation-free annual provenance value.
//! The preparation aggregate may therefore release its SQLite-owned history
//! immediately; taxpayer-year, Tax Form Profile, source, and seed
//! identities cannot drift before the exact revision commits.

const std = @import("std");
const ids = @import("id.zig");
const draft = @import("../form_engine/draft.zig");
const draft_provenance = @import("draft_provenance.zig");
const draft_provenance_runtime = @import("draft_provenance_runtime.zig");
const form_catalog = @import("generated/catalog.zig");
const key_custody = @import("../security/key_custody.zig");
const forms_set_history = @import("../tax_profile/forms_set_history.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");
const profile_persistence = @import("../tax_profile/persistence_adapter.zig");
const projection = @import("../tax_profile/projection.zig");
const store = @import("../tax_profile/store.zig");
const annual_profile = @import("../tax_profile/tax_form_profile.zig");
const year_settings = @import("../tax_profile/taxpayer_year_settings.zig");
const exact_persistence = @import("form_1701q_exact_persistence.zig");
const exact_ui = @import("form_1701q_exact_ui_state.zig");

pub const max_exact_role_instances: usize = 2;

pub const BindingError = error{
    MissingFilerRole,
    UnsupportedExactRole,
    InconsistentRoleProfileRevision,
    DuplicateProfileRoleInstance,
};

pub const GuardError = error{
    InvalidCandidateRevisionLineage,
};

pub const BridgeError = BindingError || GuardError || error{
    MultipleMatchingPersistedWorkspaces,
    ReopenProfileMappingBlocked,
    MissingFrozenExactProvenance,
    FrozenFormsSetEvidenceReferenceTooLong,
    WrongHistoricalExactForm,
    HistoricalApplicabilityDateMismatch,
    MissingHistoricalProfileRevision,
    HistoricalProfileRevisionIdentityMismatch,
    HistoricalProfileRevisionNotEffective,
    HistoricalProfileProjectionRejected,
    HistoricalSourceSnapshotMismatch,
    MissingHistoricalTaxpayerYearRevision,
    HistoricalTaxpayerYearRevisionMismatch,
    MissingHistoricalTaxFormProfileRevision,
    HistoricalTaxFormProfileRevisionMismatch,
    HistoricalFormsSetDecisionMismatch,
};

/// Matches the exact store's bounded provenance-text ceiling so every valid
/// persisted evidence reference can be frozen without widening the runtime.
pub const max_frozen_forms_set_evidence_bytes: usize = 4096;

/// Fixed-storage copy of a prepared exact composition. No field borrows the
/// preparation aggregate: only `forms_set_decision.evidence_reference` needed
/// an explicit bounded copy because the DraftProvenance snapshot and all
/// decision identifiers/dates are already value types.
pub const FrozenExactProvenance = struct {
    provenance_snapshot: draft_provenance.DraftProvenance,
    applicability_date: model.Date,
    decision_id: forms_set_history.DecisionId,
    decision_sequence: u32,
    decision_state: forms_set_history.DecisionState,
    decision_scope: forms_set_history.DecisionScope,
    decision_effective: model.EffectivePeriod,
    decision_source: forms_set_history.DecisionSource,
    decision_review: forms_set_history.ReviewState,
    decision_supersedes: ?forms_set_history.DecisionId,
    evidence_storage: [max_frozen_forms_set_evidence_bytes]u8 = undefined,
    evidence_len: u16 = 0,
    evidence_present: bool = false,

    pub fn capture(
        prepared: *const draft_provenance_runtime.OwnedComposition,
    ) BridgeError!FrozenExactProvenance {
        return captureParts(
            &prepared.composition.provenance_snapshot,
            prepared.composition.applicability_date,
            prepared.formSetDecision(),
        );
    }

    pub fn captureDecoded(
        decoded: *const exact_persistence.DecodedExactProvenance,
    ) BridgeError!FrozenExactProvenance {
        return captureParts(
            &decoded.provenance_snapshot,
            decoded.applicability_date,
            &decoded.forms_set_decision,
        );
    }

    fn captureParts(
        provenance_snapshot: *const draft_provenance.DraftProvenance,
        applicability_date: model.Date,
        decision: *const forms_set_history.Decision,
    ) BridgeError!FrozenExactProvenance {
        var frozen: FrozenExactProvenance = .{
            .provenance_snapshot = provenance_snapshot.*,
            .applicability_date = applicability_date,
            .decision_id = decision.id,
            .decision_sequence = decision.sequence,
            .decision_state = decision.state,
            .decision_scope = decision.scope,
            .decision_effective = decision.effective,
            .decision_source = decision.source,
            .decision_review = decision.review,
            .decision_supersedes = decision.supersedes,
        };
        if (decision.evidence_reference) |reference| {
            if (reference.len > frozen.evidence_storage.len or
                reference.len > std.math.maxInt(u16))
            {
                return error.FrozenFormsSetEvidenceReferenceTooLong;
            }
            @memcpy(frozen.evidence_storage[0..reference.len], reference);
            frozen.evidence_len = @intCast(reference.len);
            frozen.evidence_present = true;
        }
        return frozen;
    }

    pub fn evidenceReference(self: *const FrozenExactProvenance) ?[]const u8 {
        if (!self.evidence_present) return null;
        return self.evidence_storage[0..self.evidence_len];
    }

    pub fn input(
        self: *const FrozenExactProvenance,
    ) exact_persistence.ProvenanceInput {
        const identity = &self.provenance_snapshot.identity;
        return .{
            .applicability_date = self.applicability_date,
            .forms_set_decision = .{
                .id = self.decision_id,
                .sequence = self.decision_sequence,
                .stream = .{
                    .profile_id = identity.owner_profile_id,
                    .tax_year = identity.tax_year,
                    .form = .{
                        .code = identity.form_code.asSlice(),
                        .revision = identity.form_revision.asSlice(),
                    },
                },
                .state = self.decision_state,
                .scope = self.decision_scope,
                .effective = self.decision_effective,
                .source = self.decision_source,
                .evidence_reference = self.evidenceReference(),
                .review = self.decision_review,
                .supersedes = self.decision_supersedes,
            },
            .snapshot = &self.provenance_snapshot,
        };
    }

    /// Typed annual election used by Native open logic. It shares the exact
    /// duplicate/missing/conditional-deduction checks enforced at persistence
    /// time, so UI wiring cannot grow a second interpretation of Item 16/16A.
    pub fn annualFilerElection(
        self: *const FrozenExactProvenance,
    ) exact_persistence.Error!exact_persistence.FilerAnnualElection {
        return exact_persistence.filerAnnualElectionFromProvenance(
            &self.provenance_snapshot,
        );
    }
};

/// Stable, bounded role instances borrowed from an accepted projection.
/// `instance_id` is the stable profile ID: exact 1701Q permits one filer and
/// at most one spouse, so it is the relation identity without inventing a
/// second random identifier at save time.
pub const DerivedRoleBindings = struct {
    entries: [max_exact_role_instances]exact_persistence.RoleInstanceBinding =
        undefined,
    len: u8 = 0,

    pub fn slice(
        self: *const DerivedRoleBindings,
    ) []const exact_persistence.RoleInstanceBinding {
        return self.entries[0..self.len];
    }

    pub fn filerProfileId(
        self: *const DerivedRoleBindings,
    ) ?[]const u8 {
        for (self.slice()) |binding| {
            if (binding.role == .filer) return binding.instance_id;
        }
        return null;
    }
};

pub const FailureStage = enum {
    require_frozen_provenance,
    derive_role_bindings,
    derive_revision_guard,
    persist_exact_candidate,
    list_matching_workspaces,
    allocate_reopened_state,
    load_matching_workspace,
    load_exact_provenance,
    reconstruct_historical_projection,
    reopen_matching_workspace,
};

pub const Failure = struct {
    stage: FailureStage,
    reason: anyerror,
};

pub const SaveReport = union(enum) {
    saved: exact_persistence.PersistReceipt,
    blocked: Failure,
};

/// Owns a successfully reopened exact state until the Native page consumes it.
/// The state was allocated by the same caller-supplied allocator used during
/// replay; callers must either `take` it exactly once or `deinit` this owner.
pub const OwnedReopenedState = struct {
    allocator: std.mem.Allocator,
    state: ?*exact_ui.State,
    /// Fixed-storage projection used for the exact replay. A later current
    /// Tax Profile revision cannot change this value.
    historical_profile: projection.Snapshot,
    /// Present for every v19 exact workspace. Legacy pre-v19 workspaces keep
    /// their explicit no-sidecar behavior and therefore retain null here.
    frozen_provenance: ?FrozenExactProvenance = null,

    pub fn deinit(self: *OwnedReopenedState) void {
        const reopened = self.state orelse return;
        reopened.deinit();
        self.allocator.destroy(reopened);
        self.state = null;
    }

    pub fn take(self: *OwnedReopenedState) *exact_ui.State {
        const reopened = self.state orelse @panic(
            "exact reopened state already consumed",
        );
        self.state = null;
        return reopened;
    }

    pub fn historicalProfile(
        self: *const OwnedReopenedState,
    ) *const projection.Snapshot {
        return &self.historical_profile;
    }

    pub fn frozenProvenance(
        self: *const OwnedReopenedState,
    ) ?*const FrozenExactProvenance {
        if (self.frozen_provenance) |*value| return value;
        return null;
    }
};

pub const ResumeReport = union(enum) {
    opened: OwnedReopenedState,
    /// The persisted exact sidecar is authoritative. Reopening is blocked
    /// until a historical projection can be reconstructed from these frozen
    /// bindings; current mutable profile state is never substituted.
    historical_projection_required: FrozenExactProvenance,
    not_found,
    blocked: Failure,
};

/// Derives the exact adapter's relation bindings directly from the accepted,
/// immutable projection. Every field for a role must name one profile
/// revision.
pub fn roleBindingsFromAcceptedProjection(
    accepted: *const projection.Snapshot,
) BindingError!DerivedRoleBindings {
    var result: DerivedRoleBindings = .{};
    const filer = try bindingForRole(accepted, .filer) orelse
        return error.MissingFilerRole;
    result.entries[0] = filer;
    result.len = 1;

    if (try bindingForRole(accepted, .spouse)) |spouse| {
        if (std.mem.eql(u8, filer.instance_id, spouse.instance_id)) {
            return error.DuplicateProfileRoleInstance;
        }
        result.entries[1] = spouse;
        result.len = 2;
    }

    for (accepted.slice()) |entry| {
        switch (entry.role) {
            .filer, .spouse => {},
            .employer, .employee => return error.UnsupportedExactRole,
        }
    }
    return result;
}

fn bindingForRole(
    accepted: *const projection.Snapshot,
    role: ids.Role,
) BindingError!?exact_persistence.RoleInstanceBinding {
    var representative: ?*const projection.Provenance = null;
    for (accepted.slice()) |*entry| {
        if (entry.role != role) continue;
        if (representative) |prior| {
            if (!sameProfileRevision(prior, &entry.provenance)) {
                return error.InconsistentRoleProfileRevision;
            }
        } else {
            representative = &entry.provenance;
        }
    }
    const provenance = representative orelse return null;
    return .{
        .role = role,
        .instance_id = provenance.profile_id.asSlice(),
        .provenance = "historical_profile_projection",
    };
}

fn sameProfileRevision(
    left: *const projection.Provenance,
    right: *const projection.Provenance,
) bool {
    return left.profile_id.eql(&right.profile_id) and
        left.revision_id.eql(&right.revision_id) and
        left.revision_sequence == right.revision_sequence and
        std.meta.eql(left.revision_source, right.revision_source);
}

pub fn revisionGuardForCurrentCandidate(
    state: *const exact_ui.State,
) (exact_ui.Error || GuardError)!draft.RevisionGuard {
    const candidate = try state.candidateSnapshot();
    if (candidate.parent_revision) |parent| {
        if (parent.value == std.math.maxInt(u64) or
            candidate.revision.value != parent.value + 1)
        {
            return error.InvalidCandidateRevisionLineage;
        }
        return .{ .match = parent };
    }
    if (candidate.revision.value != 1) {
        return error.InvalidCandidateRevisionLineage;
    }
    return .create;
}

/// Persists the current exact candidate and converts every failure into a
/// stage-tagged fail-closed report suitable for a Native notice. This function
/// never calls the coarse recurring-draft adapter.
pub fn persistCurrentCandidateDevelopmentPlaintext(
    plaintext_capability: *const key_custody.DevelopmentPlaintextStorageCapability,
    repository: *store.Store,
    state: *const exact_ui.State,
    accepted: *const projection.Snapshot,
    frozen_provenance: ?*const FrozenExactProvenance,
    recorded_at_unix_seconds: i64,
) SaveReport {
    const frozen = frozen_provenance orelse return .{ .blocked = .{
        .stage = .require_frozen_provenance,
        .reason = error.MissingFrozenExactProvenance,
    } };
    const provenance = frozen.input();
    return persistCurrentCandidateDevelopmentPlaintextInternal(
        plaintext_capability,
        repository,
        state,
        accepted,
        provenance,
        recorded_at_unix_seconds,
    );
}

fn persistCurrentCandidateDevelopmentPlaintextInternal(
    plaintext_capability: *const key_custody.DevelopmentPlaintextStorageCapability,
    repository: *store.Store,
    state: *const exact_ui.State,
    accepted: *const projection.Snapshot,
    provenance: ?exact_persistence.ProvenanceInput,
    recorded_at_unix_seconds: i64,
) SaveReport {
    const bindings = roleBindingsFromAcceptedProjection(accepted) catch |err|
        return .{ .blocked = .{
            .stage = .derive_role_bindings,
            .reason = err,
        } };
    const guard = revisionGuardForCurrentCandidate(state) catch |err|
        return .{ .blocked = .{
            .stage = .derive_revision_guard,
            .reason = err,
        } };
    const receipt = exact_persistence
        .persistCurrentCandidateDevelopmentPlaintext(
        plaintext_capability,
        repository,
        state,
        .{
            .historical_profile = accepted,
            .role_instances = bindings.slice(),
            .recorded_at_unix_seconds = recorded_at_unix_seconds,
            .guard = guard,
            .provenance = provenance,
        },
    ) catch |err| return .{ .blocked = .{
        .stage = .persist_exact_candidate,
        .reason = err,
    } };
    return .{ .saved = receipt };
}

/// Existing persistence/reopen fixtures intentionally exercise the pre-v19
/// stream. Keeping this helper private prevents the application bridge from
/// silently minting a new exact revision without annual provenance.
fn persistCurrentCandidateDevelopmentPlaintextLegacyForTest(
    plaintext_capability: *const key_custody.DevelopmentPlaintextStorageCapability,
    repository: *store.Store,
    state: *const exact_ui.State,
    accepted: *const projection.Snapshot,
    recorded_at_unix_seconds: i64,
) SaveReport {
    return persistCurrentCandidateDevelopmentPlaintextInternal(
        plaintext_capability,
        repository,
        state,
        accepted,
        null,
        recorded_at_unix_seconds,
    );
}

/// Rebuilds the exact 1701Q profile snapshot exclusively from immutable
/// identities named by the v19 sidecar. Profile rows are loaded by revision
/// ID, never through the mutable current/effective resolver. The returned
/// snapshot owns every value by copy, so all SQLite-backed owners may be
/// released before the exact state is reopened or saved again.
fn reconstructHistoricalProjection(
    repository: *store.Store,
    allocator: std.mem.Allocator,
    frozen: *const FrozenExactProvenance,
    context: exact_ui.FilingContext,
) anyerror!projection.Snapshot {
    const snapshot = &frozen.provenance_snapshot;
    if (!std.mem.eql(
        u8,
        snapshot.identity.form_code.asSlice(),
        form.revision.code.asSlice(),
    ) or !std.mem.eql(
        u8,
        snapshot.identity.form_revision.asSlice(),
        form.revision.revision.asSlice(),
    )) return error.WrongHistoricalExactForm;
    if (!frozen.applicability_date.eql(try context.profileAsOf())) {
        return error.HistoricalApplicabilityDateMismatch;
    }

    try verifyFrozenFormsSetDecision(repository, allocator, frozen);

    var owned_profiles =
        [_]?profile_persistence.OwnedDomainRevision{null} **
        max_exact_role_instances;
    defer for (&owned_profiles) |*owned| {
        if (owned.*) |*value| value.deinit(allocator);
    };
    var bindings: [max_exact_role_instances]projection.Binding = undefined;
    const taxpayer_bindings = snapshot.taxpayerRevisions();
    if (taxpayer_bindings.len == 0 or
        taxpayer_bindings.len > owned_profiles.len)
    {
        return error.HistoricalProfileRevisionIdentityMismatch;
    }
    for (taxpayer_bindings, 0..) |*binding, index| {
        const role = exactDomainRole(binding.role) orelse
            return error.UnsupportedExactRole;
        owned_profiles[index] = try profile_persistence.loadRevision(
            repository,
            allocator,
            binding.profile_id,
            binding.revision_id,
        ) orelse return error.MissingHistoricalProfileRevision;
        const revision = &owned_profiles[index].?.revision;
        if (!revision.profile_id.eql(&binding.profile_id) or
            !revision.id.eql(&binding.revision_id) or
            revision.sequence != binding.revision_sequence)
        {
            return error.HistoricalProfileRevisionIdentityMismatch;
        }
        if (!revision.isEffective(frozen.applicability_date)) {
            return error.HistoricalProfileRevisionNotEffective;
        }
        bindings[index] = .{ .role = role, .revision = revision };
    }

    try verifyHistoricalSourceSnapshots(
        repository,
        allocator,
        frozen,
        &owned_profiles,
    );

    return switch (try form.composeProfiles(
        bindings[0..taxpayer_bindings.len],
        frozen.applicability_date,
    )) {
        .accepted => |accepted| accepted,
        .rejected => error.HistoricalProfileProjectionRejected,
    };
}

fn exactDomainRole(role: form_catalog.Role) ?ids.Role {
    return switch (role) {
        .filer => .filer,
        .spouse => .spouse,
        else => null,
    };
}

fn verifyFrozenFormsSetDecision(
    repository: *store.Store,
    allocator: std.mem.Allocator,
    frozen: *const FrozenExactProvenance,
) anyerror!void {
    const identity = &frozen.provenance_snapshot.identity;
    const stream: forms_set_history.StreamIdentity = .{
        .profile_id = identity.owner_profile_id,
        .tax_year = identity.tax_year,
        .form = .{
            .code = identity.form_code.asSlice(),
            .revision = identity.form_revision.asSlice(),
        },
    };
    var history = try profile_persistence.loadFormSetDecisionHistory(
        repository,
        allocator,
        stream,
    );
    defer history.deinit(allocator);
    const expected = frozen.input().forms_set_decision;
    for (history.history.records()) |*candidate| {
        if (!candidate.id.eql(&expected.id)) continue;
        if (candidate.sequence != expected.sequence or
            !candidate.stream.eql(&expected.stream) or
            candidate.state != expected.state or
            candidate.scope != expected.scope or
            !candidate.effective.eql(expected.effective) or
            candidate.source != expected.source or
            candidate.review != expected.review or
            !optionalDecisionIdEql(candidate.supersedes, expected.supersedes) or
            !optionalTextEql(
                candidate.evidence_reference,
                expected.evidence_reference,
            ) or !candidate.appliesOn(frozen.applicability_date))
        {
            return error.HistoricalFormsSetDecisionMismatch;
        }
        return;
    }
    return error.HistoricalFormsSetDecisionMismatch;
}

fn optionalDecisionIdEql(
    left: ?forms_set_history.DecisionId,
    right: ?forms_set_history.DecisionId,
) bool {
    if (left == null or right == null) return left == null and right == null;
    return left.?.eql(&right.?);
}

fn optionalTextEql(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn verifyHistoricalSourceSnapshots(
    repository: *store.Store,
    allocator: std.mem.Allocator,
    frozen: *const FrozenExactProvenance,
    owned_profiles: *const [max_exact_role_instances]?profile_persistence.OwnedDomainRevision,
) anyerror!void {
    const snapshot = &frozen.provenance_snapshot;

    var owned_year: ?profile_persistence.OwnedTaxpayerYearHistory = null;
    defer if (owned_year) |*value| value.deinit(allocator);
    const exact_year_revision: ?*const year_settings.Revision =
        if (snapshot.taxpayer_year_revision) |binding| blk: {
            owned_year = try profile_persistence.loadTaxpayerYearHistory(
                repository,
                allocator,
                binding.stream,
            );
            for (owned_year.?.revisions) |*revision| {
                if (!revision.id.eql(&binding.revision_id)) continue;
                if (revision.sequence != binding.revision_sequence or
                    !revision.stream.eql(&binding.stream) or
                    !revision.effectiveOn(frozen.applicability_date) or
                    revision.review_state != .confirmed)
                {
                    return error.HistoricalTaxpayerYearRevisionMismatch;
                }
                break :blk revision;
            }
            return error.MissingHistoricalTaxpayerYearRevision;
        } else null;

    var owned_form_profile: ?profile_persistence.OwnedTaxFormProfileHistory =
        null;
    defer if (owned_form_profile) |*value| value.deinit(allocator);
    const exact_form_profile_revision: ?*const annual_profile.Revision =
        if (snapshot.tax_form_profile_revision) |binding| blk: {
            owned_form_profile = try profile_persistence.loadTaxFormProfileHistory(
                repository,
                allocator,
                binding.stream,
            );
            for (owned_form_profile.?.revisions) |*revision| {
                if (!revision.id.eql(&binding.revision_id)) continue;
                if (revision.sequence != binding.revision_sequence or
                    !revision.stream.eql(&binding.stream) or
                    revision.spec_revision != binding.spec_revision or
                    !revision.spec_hash.eql(&binding.spec_hash) or
                    !revision.effectiveOn(frozen.applicability_date) or
                    revision.review_state != .confirmed)
                {
                    return error.HistoricalTaxFormProfileRevisionMismatch;
                }
                break :blk revision;
            }
            return error.MissingHistoricalTaxFormProfileRevision;
        } else null;

    for (snapshot.sourceSnapshots()) |*source| {
        const expected: ?draft_provenance.SnapshotValue = switch (source.key) {
            .taxpayer_fact => |key| blk: {
                const revision = historicalRevisionForRole(
                    snapshot,
                    owned_profiles,
                    key.role,
                ) orelse return error.MissingHistoricalProfileRevision;
                break :blk try taxpayerFactValue(revision, key.key);
            },
            .taxpayer_year_setting => |key| blk: {
                const revision = exact_year_revision orelse
                    return error.MissingHistoricalTaxpayerYearRevision;
                if (key.role != .filer) {
                    return error.HistoricalSourceSnapshotMismatch;
                }
                const value = revision.find(key.key) orelse
                    return error.HistoricalSourceSnapshotMismatch;
                break :blk taxpayerYearValue(value.*);
            },
            .tax_form_profile_value => |key| blk: {
                const revision = exact_form_profile_revision orelse
                    return error.MissingHistoricalTaxFormProfileRevision;
                const value = findFormProfileValue(
                    revision.values,
                    key.role,
                    key.key,
                ) orelse return error.HistoricalSourceSnapshotMismatch;
                break :blk try formProfileValue(value.value);
            },
        };
        const value = expected orelse
            return error.HistoricalSourceSnapshotMismatch;
        if (!snapshotValueEql(value, source.copied_value)) {
            return error.HistoricalSourceSnapshotMismatch;
        }
    }
}

fn historicalRevisionForRole(
    snapshot: *const draft_provenance.DraftProvenance,
    owned_profiles: *const [max_exact_role_instances]?profile_persistence.OwnedDomainRevision,
    role: form_catalog.Role,
) ?*const model.ProfileRevision {
    for (snapshot.taxpayerRevisions(), 0..) |binding, index| {
        if (binding.role != role) continue;
        return &owned_profiles[index].?.revision;
    }
    return null;
}

fn taxpayerFactValue(
    revision: *const model.ProfileRevision,
    key: draft_provenance.TaxpayerFactKey,
) !?draft_provenance.SnapshotValue {
    return switch (key) {
        .tin => .{ .text = try draft_provenance.OwnedText.copy(
            revision.identity.tin.asDigits(),
        ) },
        .rdo_code => .{ .text = try draft_provenance.OwnedText.copy(
            revision.identity.rdo_code.asSlice(),
        ) },
        .taxpayer_name => .{ .text = try draft_provenance.OwnedText.copy(
            revision.subject.taxpayerName().asSlice(),
        ) },
        .registered_name => if (revision.subject.registeredName()) |value|
            .{ .text = try draft_provenance.OwnedText.copy(value.asSlice()) }
        else
            null,
        .trade_name => if (revision.subject.tradeName()) |value|
            .{ .text = try draft_provenance.OwnedText.copy(value.asSlice()) }
        else
            null,
        .registered_address => .{
            .text = try draft_provenance.OwnedText.copy(
                revision.contact.address.asSlice(),
            ),
        },
        .zip_code => if (revision.contact.zip_code) |value|
            .{ .text = try draft_provenance.OwnedText.copy(value.asSlice()) }
        else
            null,
        .contact_number => if (revision.contact.contact_number) |value|
            .{ .text = try draft_provenance.OwnedText.copy(value.asSlice()) }
        else
            null,
        .email_address => if (revision.contact.email_address) |value|
            .{ .text = try draft_provenance.OwnedText.copy(value.asSlice()) }
        else
            null,
        .subject_kind => .{ .choice = try draft_provenance.OwnedText.copy(
            @tagName(revision.subject.kind()),
        ) },
        .natural_person_classification => if (revision.subject.naturalPersonClassification()) |value| .{ .choice = try draft_provenance.OwnedText.copy(
            @tagName(value),
        ) } else null,
    };
}

fn taxpayerYearValue(
    value: year_settings.SettingValue,
) draft_provenance.SnapshotValue {
    return switch (value) {
        .income_tax_rate_election => |item| .{
            .income_tax_rate_election = item,
        },
        .deduction_method => |item| .{ .deduction_method = item },
    };
}

fn findFormProfileValue(
    values: []const annual_profile.SetupValue,
    role: form_catalog.Role,
    key: form_catalog.TaxFormProfileSemanticKey,
) ?*const annual_profile.SetupValue {
    for (values) |*value| {
        if (value.role == role and value.semantic_key == key) return value;
    }
    return null;
}

fn formProfileValue(
    value: annual_profile.ScalarValue,
) !draft_provenance.SnapshotValue {
    return switch (value) {
        .profile_id => |item| .{ .profile_id = item },
        .text => |item| .{ .text = try draft_provenance.OwnedText.copy(
            item.asSlice(),
        ) },
        .choice => |item| .{ .choice = try draft_provenance.OwnedText.copy(
            item.asSlice(),
        ) },
        .boolean => |item| .{ .boolean = item },
        .integer => |item| .{ .integer = item },
        .date => |item| .{ .date = item },
        .year => |item| .{ .year = item },
    };
}

fn snapshotValueEql(
    left: draft_provenance.SnapshotValue,
    right: draft_provenance.SnapshotValue,
) bool {
    return switch (left) {
        .text => |value| switch (right) {
            .text => |other| std.mem.eql(u8, value.asSlice(), other.asSlice()),
            else => false,
        },
        .choice => |value| switch (right) {
            .choice => |other| std.mem.eql(u8, value.asSlice(), other.asSlice()),
            else => false,
        },
        .boolean => |value| switch (right) {
            .boolean => |other| value == other,
            else => false,
        },
        .integer => |value| switch (right) {
            .integer => |other| value == other,
            else => false,
        },
        .date => |value| switch (right) {
            .date => |other| value.eql(other),
            else => false,
        },
        .year => |value| switch (right) {
            .year => |other| value == other,
            else => false,
        },
        .profile_id => |value| switch (right) {
            .profile_id => |other| value.eql(&other),
            else => false,
        },
        .income_tax_rate_election => |value| switch (right) {
            .income_tax_rate_election => |other| value == other,
            else => false,
        },
        .deduction_method => |value| switch (right) {
            .deduction_method => |other| value == other,
            else => false,
        },
    };
}

/// Reopens only when the canonical exact filing key identifies one and only
/// one persisted workspace. Zero matches are a normal `not_found`; multiple
/// matches are surfaced and none is chosen implicitly. The returned state is
/// allocated only after uniqueness is established and is destroyed on every
/// load/replay/verification failure.
pub fn resumeUniqueDevelopmentPlaintext(
    plaintext_capability: *const key_custody.DevelopmentPlaintextStorageCapability,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    accepted: *const projection.Snapshot,
    context: exact_ui.FilingContext,
    selected_shape: draft.PayloadShape,
) ResumeReport {
    const bindings = roleBindingsFromAcceptedProjection(accepted) catch |err|
        return .{ .blocked = .{
            .stage = .derive_role_bindings,
            .reason = err,
        } };
    const filer_profile_id = bindings.filerProfileId() orelse
        return .{ .blocked = .{
            .stage = .derive_role_bindings,
            .reason = error.MissingFilerRole,
        } };

    var matches = exact_persistence
        .listAlternateWorkspacesDevelopmentPlaintext(
        plaintext_capability,
        repository,
        allocator,
        filer_profile_id,
        context,
        null,
    ) catch |err| return .{ .blocked = .{
        .stage = .list_matching_workspaces,
        .reason = err,
    } };
    defer matches.deinit(allocator);
    if (matches.items.len == 0) return .not_found;
    if (matches.items.len != 1) {
        return .{ .blocked = .{
            .stage = .list_matching_workspaces,
            .reason = error.MultipleMatchingPersistedWorkspaces,
        } };
    }

    const reopened = allocator.create(exact_ui.State) catch |err|
        return .{ .blocked = .{
            .stage = .allocate_reopened_state,
            .reason = err,
        } };
    var reopened_initialized = false;
    defer if (!reopened_initialized) allocator.destroy(reopened);

    var loaded: exact_persistence.LoadedWorkspace = undefined;
    exact_persistence.loadWorkspaceIntoDevelopmentPlaintext(
        plaintext_capability,
        &loaded,
        repository,
        allocator,
        matches.items[0].workspace_id,
        filer_profile_id,
        context,
    ) catch |err| return .{ .blocked = .{
        .stage = .load_matching_workspace,
        .reason = err,
    } };
    defer loaded.deinit();

    const persisted = loaded.currentPersistedRevision(selected_shape) orelse
        return .{ .blocked = .{
            .stage = .load_matching_workspace,
            .reason = error.SelectedShapeMissing,
        } };
    const persisted_identity = loaded.persistedIdentity(selected_shape) orelse
        return .{ .blocked = .{
            .stage = .load_matching_workspace,
            .reason = error.SelectedShapeMissing,
        } };
    var provenance_load = exact_persistence
        .loadRevisionProvenanceDevelopmentPlaintext(
        plaintext_capability,
        repository,
        allocator,
        persisted_identity,
        persisted.revision,
    ) catch |err| return .{ .blocked = .{
        .stage = .load_exact_provenance,
        .reason = err,
    } };
    defer provenance_load.deinit(allocator);
    switch (provenance_load) {
        .provenance_legacy_absent => {},
        .exact => |*owned| {
            const decoded = exact_persistence.decodeOwnedExactProvenance(
                owned,
            ) catch |err| return .{ .blocked = .{
                .stage = .load_exact_provenance,
                .reason = err,
            } };
            const frozen = FrozenExactProvenance.captureDecoded(
                &decoded,
            ) catch |err| return .{ .blocked = .{
                .stage = .load_exact_provenance,
                .reason = err,
            } };
            const historical_profile = reconstructHistoricalProjection(
                repository,
                allocator,
                &frozen,
                context,
            ) catch |err| return .{ .blocked = .{
                .stage = .reconstruct_historical_projection,
                .reason = err,
            } };
            const historical_bindings = roleBindingsFromAcceptedProjection(
                &historical_profile,
            ) catch |err| return .{ .blocked = .{
                .stage = .reconstruct_historical_projection,
                .reason = err,
            } };
            const status = exact_persistence
                .reopenStateIntoDevelopmentPlaintext(
                plaintext_capability,
                reopened,
                &loaded,
                selected_shape,
                context,
                &historical_profile,
                historical_bindings.slice(),
            ) catch |err| return .{ .blocked = .{
                .stage = .reopen_matching_workspace,
                .reason = err,
            } };
            switch (status) {
                .opened => {
                    reopened_initialized = true;
                    return .{ .opened = .{
                        .allocator = allocator,
                        .state = reopened,
                        .historical_profile = historical_profile,
                        .frozen_provenance = frozen,
                    } };
                },
                .blocked => return .{ .blocked = .{
                    .stage = .reopen_matching_workspace,
                    .reason = error.ReopenProfileMappingBlocked,
                } },
            }
        },
    }

    const status = exact_persistence
        .reopenStateIntoDevelopmentPlaintext(
        plaintext_capability,
        reopened,
        &loaded,
        selected_shape,
        context,
        accepted,
        bindings.slice(),
    ) catch |err| return .{ .blocked = .{
        .stage = .reopen_matching_workspace,
        .reason = err,
    } };
    switch (status) {
        .opened => {
            reopened_initialized = true;
            return .{ .opened = .{
                .allocator = allocator,
                .state = reopened,
                .historical_profile = accepted.*,
            } };
        },
        .blocked => return .{ .blocked = .{
            .stage = .reopen_matching_workspace,
            .reason = error.ReopenProfileMappingBlocked,
        } },
    }
}

// -------------------------------------------------------------------------
// Focused development-runtime tests.

const form = @import("form_1701q.zig");

const test_context: exact_ui.FilingContext = .{
    .tax_year = 2026,
    .quarter = .second,
    .amended = false,
};

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

fn testProfile() !projection.Snapshot {
    const effective_on = try test_context.profileAsOf();
    var snapshot = projection.Snapshot.init(form.revision, effective_on);
    const provenance: projection.Provenance = .{
        .profile_id = try model.ProfileId.parse("runtime-exact-filer"),
        .revision_id = try model.RevisionId.parse("runtime-exact-filer-r1"),
        .revision_sequence = 1,
        .revision_source = .manual_entry,
    };
    for (form.filer_requirements, 0..) |requirement, index| {
        const value: field.Value = switch (index) {
            0 => .{ .tin = try field.Tin.parse("123-456-789-000") },
            1 => .{ .rdo_code = try field.RdoCode.parse("040") },
            2 => .{ .taxpayer_name = try field.TaxpayerName.parse(
                "RUNTIME EXACT FILER",
            ) },
            3 => .{ .registered_address = try field.RegisteredAddress.parse(
                "RUNTIME EXACT ADDRESS",
            ) },
            4 => .{ .zip_code = try field.ZipCode.parse("1100") },
            5 => .{ .date_of_birth = try model.Date.init(1990, 1, 1) },
            6 => .{ .email_address = try field.EmailAddress.parse(
                "runtime@example.test",
            ) },
            7 => .{ .citizenship = try field.Citizenship.parse("FILIPINO") },
            8 => .{ .foreign_tax_number = try field.ForeignTaxNumber.parse(
                "FOREIGN-TEST-1",
            ) },
            else => unreachable,
        };
        try snapshot.append(.{
            .role = .filer,
            .target = requirement.target,
            .value = value,
            .provenance = provenance,
        });
    }
    return snapshot;
}

fn seedTestProfile(repository: *store.Store) !void {
    try repository.createProfileWithRevision(
        .{ .id = "runtime-exact-filer" },
        .{
            .id = "runtime-exact-filer-r1",
            .profile_id = "runtime-exact-filer",
            .sequence = 1,
            .expected_current_sequence = 0,
            .effective = .{
                .from = dateText(try model.Date.init(2020, 1, 1)),
            },
            .source = .manual_entry,
            .identity = .{
                .tin = "123-456-789-000",
                .rdo_code = "040",
            },
            .contact = .{
                .registered_address = "RUNTIME EXACT ADDRESS",
                .zip_code = "1100",
                .email_address = "runtime@example.test",
            },
            .subject = .{ .individual = .{
                .name = "RUNTIME EXACT FILER",
                .date_of_birth = dateText(
                    try model.Date.init(1990, 1, 1),
                ),
                .citizenship = "FILIPINO",
                .foreign_tax_number = "FOREIGN-TEST-1",
            } },
        },
    );
}

const test_taxpayer_year_revision_id = "runtime-taxpayer-year-r1";
const test_form_profile_revision_id = "runtime-form-profile-r1";

fn seedTestExactAnnualSources(
    repository: *store.Store,
    allocator: std.mem.Allocator,
) !FrozenExactProvenance {
    const profile_id = try model.ProfileId.parse("runtime-exact-filer");
    const applicability_date = try test_context.profileAsOf();
    const full_year = try model.EffectivePeriod.init(
        try model.Date.init(2026, 1, 1),
        try model.Date.init(2026, 12, 31),
    );
    const forms = [_]store.FormRegistrationWrite{.{
        .form_code = form.revision.code.asSlice(),
        .form_revision = form.revision.revision.asSlice(),
    }};
    try repository.createFormSet(profile_id.asSlice(), 2026, &forms);
    const decision_stream: forms_set_history.StreamIdentity = .{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form = .{
            .code = form.revision.code.asSlice(),
            .revision = form.revision.revision.asSlice(),
        },
    };
    var decision_history = try profile_persistence.loadFormSetDecisionHistory(
        repository,
        allocator,
        decision_stream,
    );
    defer decision_history.deinit(allocator);
    const recorded_decision = &decision_history.history.records()[0];

    const year_values = [_]year_settings.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .itemized_deduction },
    };
    const year_revision: year_settings.Revision = .{
        .id = try year_settings.RevisionId.parse(
            test_taxpayer_year_revision_id,
        ),
        .stream = .{ .profile_id = profile_id, .tax_year = 2026 },
        .sequence = 1,
        .effective = full_year,
        .review_state = .confirmed,
        .confirmed_at_unix_seconds = 1_780_000_000,
        .source = .manual_entry,
        .values = &year_values,
    };
    try profile_persistence.appendTaxpayerYearRevision(
        repository,
        allocator,
        0,
        &year_revision,
    );

    const definition = form_catalog.findForm("1701Q").?;
    const form_profile_values = [_]annual_profile.SetupValue{};
    const form_profile_revision: annual_profile.Revision = .{
        .id = try annual_profile.RevisionId.parse(
            test_form_profile_revision_id,
        ),
        .stream = .{
            .profile_id = profile_id,
            .tax_year = 2026,
            .form_code = try annual_profile.FormCode.parse("1701Q"),
            .form_revision = try annual_profile.FormRevision.parse(
                "2018-01-ENCS",
            ),
        },
        .sequence = 1,
        .effective = full_year,
        .spec_revision = definition.tax_form_profile.spec_revision.?,
        .spec_hash = try annual_profile.SpecHash.parse(
            definition.tax_form_profile.spec_hash.?,
        ),
        .review_state = .confirmed,
        .confirmed_at_unix = 1_780_000_002,
        .source = .manual_entry,
        .values = &form_profile_values,
    };
    try profile_persistence.appendTaxFormProfileRevision(
        repository,
        allocator,
        0,
        &form_profile_revision,
    );

    const taxpayer_bindings = [_]draft_provenance.TaxpayerRevisionBinding{.{
        .role = .filer,
        .profile_id = profile_id,
        .revision_id = try model.RevisionId.parse("runtime-exact-filer-r1"),
        .revision_sequence = 1,
    }};
    const source_snapshots = [_]draft_provenance.SourceSnapshot{
        .{
            .key = .{ .taxpayer_fact = .{ .role = .filer, .key = .tin } },
            .copied_value = .{ .text = try draft_provenance.OwnedText.copy(
                "123456789000",
            ) },
        },
        .{
            .key = .{ .taxpayer_fact = .{ .role = .filer, .key = .rdo_code } },
            .copied_value = .{ .text = try draft_provenance.OwnedText.copy(
                "040",
            ) },
        },
        .{
            .key = .{ .taxpayer_fact = .{
                .role = .filer,
                .key = .taxpayer_name,
            } },
            .copied_value = .{ .text = try draft_provenance.OwnedText.copy(
                "RUNTIME EXACT FILER",
            ) },
        },
        .{
            .key = .{ .taxpayer_fact = .{
                .role = .filer,
                .key = .registered_address,
            } },
            .copied_value = .{ .text = try draft_provenance.OwnedText.copy(
                "RUNTIME EXACT ADDRESS",
            ) },
        },
        .{
            .key = .{ .taxpayer_fact = .{ .role = .filer, .key = .zip_code } },
            .copied_value = .{ .text = try draft_provenance.OwnedText.copy(
                "1100",
            ) },
        },
        .{
            .key = .{ .taxpayer_fact = .{
                .role = .filer,
                .key = .email_address,
            } },
            .copied_value = .{ .text = try draft_provenance.OwnedText.copy(
                "runtime@example.test",
            ) },
        },
        .{
            .key = .{ .taxpayer_year_setting = .{
                .role = .filer,
                .key = .income_tax_rate_election,
            } },
            .copied_value = .{ .income_tax_rate_election = .graduated },
        },
        .{
            .key = .{ .taxpayer_year_setting = .{
                .role = .filer,
                .key = .deduction_method,
            } },
            .copied_value = .{ .deduction_method = .itemized_deduction },
        },
    };
    const capture_input: draft_provenance.CaptureInput = .{
        .identity = .{
            .owner_profile_id = profile_id,
            .tax_year = 2026,
            .form_code = try annual_profile.FormCode.parse("1701Q"),
            .form_revision = try annual_profile.FormRevision.parse(
                "2018-01-ENCS",
            ),
            .catalog = .{
                .revision = try draft_provenance.CatalogRevision.parse(
                    form_catalog.catalog_revision,
                ),
                .sha256 = try draft_provenance.Sha256.parse(
                    form_catalog.catalog_sha256,
                ),
            },
            .setup_spec_revision = definition.tax_form_profile.spec_revision.?,
            .setup_spec_hash = try draft_provenance.Sha256.parse(
                definition.tax_form_profile.spec_hash.?,
            ),
        },
        .taxpayer_revisions = &taxpayer_bindings,
        .taxpayer_year_revision = .{
            .stream = year_revision.stream,
            .revision_id = year_revision.id,
            .revision_sequence = year_revision.sequence,
        },
        .tax_form_profile_revision = .{
            .stream = form_profile_revision.stream,
            .revision_id = form_profile_revision.id,
            .revision_sequence = form_profile_revision.sequence,
            .spec_revision = form_profile_revision.spec_revision,
            .spec_hash = form_profile_revision.spec_hash,
        },
        .source_snapshots = &source_snapshots,
    };
    const provenance_snapshot = try draft_provenance.DraftProvenance.capture(
        &capture_input,
        definition,
    );
    return FrozenExactProvenance.captureParts(
        &provenance_snapshot,
        applicability_date,
        recorded_decision,
    );
}

fn openCandidate(
    out: *exact_ui.State,
    allocator: std.mem.Allocator,
    repository: *store.Store,
    profile: *const projection.Snapshot,
) !void {
    switch (try exact_ui.State.openInto(
        out,
        allocator,
        try repository.generateDraftWorkspaceId(),
        test_context,
        profile,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    try out.setRadio("frm1701q:optType_1", true);
    try out.setRadio("frm1701q:optATC_1", true);
    try out.setRadio("frm1701q:optTaxRate_1", true);
    try out.setRadio("frm1701q:optMethodOfDeduction:_1", true);
    try out.calculate();
    switch (try out.validateSave(2026, .not_evaluated)) {
        .passed => {},
        .failed => return error.ExpectedSavePass,
    }
    try out.generateEditableCandidate(.create);
}

test "exact runtime derives bounded role instances" {
    var profile = try testProfile();
    const bindings = try roleBindingsFromAcceptedProjection(&profile);
    try std.testing.expectEqual(@as(usize, 1), bindings.slice().len);
    try std.testing.expectEqual(ids.Role.filer, bindings.slice()[0].role);
    try std.testing.expectEqualStrings(
        "runtime-exact-filer",
        bindings.slice()[0].instance_id,
    );
}

test "exact runtime blocks application save without frozen annual provenance" {
    const allocator = std.testing.allocator;
    const capability = key_custody.bootstrapCurrentArtifactStorage()
        .development_plaintext;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    var profile = try testProfile();
    var candidate: exact_ui.State = undefined;
    try openCandidate(&candidate, allocator, &repository, &profile);
    defer candidate.deinit();

    switch (persistCurrentCandidateDevelopmentPlaintext(
        capability,
        &repository,
        &candidate,
        &profile,
        null,
        1_780_000_000,
    )) {
        .saved => return error.ExpectedFrozenProvenanceBlock,
        .blocked => |failure| {
            try std.testing.expectEqual(
                FailureStage.require_frozen_provenance,
                failure.stage,
            );
            try std.testing.expectEqual(
                error.MissingFrozenExactProvenance,
                failure.reason,
            );
        },
    }
}

test "v19 historical reconstruction rejects copied-source corruption" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedTestProfile(&repository);
    const frozen = try seedTestExactAnnualSources(&repository, allocator);

    const reconstructed = try reconstructHistoricalProjection(
        &repository,
        allocator,
        &frozen,
        test_context,
    );
    try std.testing.expectEqualStrings(
        "runtime-exact-filer-r1",
        reconstructed.slice()[0].provenance.revision_id.asSlice(),
    );

    var corrupt_source = frozen;
    corrupt_source.provenance_snapshot.source_snapshots_storage[0]
        .copied_value = .{ .text = try draft_provenance.OwnedText.copy(
        "999999999000",
    ) };
    try std.testing.expectError(
        error.HistoricalSourceSnapshotMismatch,
        reconstructHistoricalProjection(
            &repository,
            allocator,
            &corrupt_source,
            test_context,
        ),
    );
}

test "v19 exact resume ignores current profile drift and reuses frozen history" {
    const allocator = std.testing.allocator;
    const capability = key_custody.bootstrapCurrentArtifactStorage()
        .development_plaintext;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedTestProfile(&repository);
    const frozen = try seedTestExactAnnualSources(&repository, allocator);
    var historical_profile = try testProfile();

    var original: exact_ui.State = undefined;
    try openCandidate(
        &original,
        allocator,
        &repository,
        &historical_profile,
    );
    defer original.deinit();
    const historical_candidate = try original.candidateSnapshot();
    const first_receipt = switch (persistCurrentCandidateDevelopmentPlaintext(
        capability,
        &repository,
        &original,
        &historical_profile,
        &frozen,
        1_780_000_010,
    )) {
        .saved => |receipt| receipt,
        .blocked => |failure| {
            std.debug.print(
                "strict v19 fixture save blocked at {s}: {s}\n",
                .{ @tagName(failure.stage), @errorName(failure.reason) },
            );
            return error.UnexpectedPersistenceBlock;
        },
    };

    try repository.appendRevision(.{
        .id = "runtime-exact-filer-r2",
        .profile_id = "runtime-exact-filer",
        .sequence = 2,
        .expected_current_sequence = 1,
        .effective = .{ .from = dateText(try model.Date.init(2020, 1, 1)) },
        .source = .manual_entry,
        .identity = .{
            .tin = "123-456-789-000",
            .rdo_code = "040",
        },
        .contact = .{
            .registered_address = "DRIFTED CURRENT ADDRESS",
            .zip_code = "1100",
            .email_address = "drifted-current@example.test",
        },
        .subject = .{ .individual = .{
            .name = "DRIFTED CURRENT FILER",
            .date_of_birth = dateText(try model.Date.init(1990, 1, 1)),
            .citizenship = "FILIPINO",
            .foreign_tax_number = "FOREIGN-TEST-1",
        } },
    });
    var current_revision = (try profile_persistence.loadRevision(
        &repository,
        allocator,
        try model.ProfileId.parse("runtime-exact-filer"),
        try model.RevisionId.parse("runtime-exact-filer-r2"),
    )).?;
    defer current_revision.deinit(allocator);
    var current_profile = switch (try form.composeProfiles(
        &.{.{ .role = .filer, .revision = &current_revision.revision }},
        try test_context.profileAsOf(),
    )) {
        .accepted => |accepted| accepted,
        .rejected => return error.UnexpectedProfileMappingBlock,
    };
    try std.testing.expectEqualStrings(
        "DRIFTED CURRENT FILER",
        current_profile.get(form.filer_requirements[2].target).?
            .value.taxpayer_name.asSlice(),
    );

    switch (resumeUniqueDevelopmentPlaintext(
        capability,
        &repository,
        allocator,
        &current_profile,
        test_context,
        .editable_save,
    )) {
        .opened => |value| {
            var resumed = value;
            defer resumed.deinit();
            try std.testing.expect(resumed.frozenProvenance() != null);
            try std.testing.expectEqualStrings(
                "RUNTIME EXACT FILER",
                resumed.historicalProfile().get(
                    form.filer_requirements[2].target,
                ).?.value.taxpayer_name.asSlice(),
            );
            try std.testing.expectEqualStrings(
                "runtime-exact-filer-r1",
                resumed.historicalProfile().slice()[0]
                    .provenance.revision_id.asSlice(),
            );

            const reopened = resumed.state.?;
            _ = try reopened.commitAndBlurQualified(
                "frm1701q:txtSheets",
                "2",
                .{
                    .current_year = 2026,
                    .schedule_date = .{
                        .current_date = .{
                            .year = 2026,
                            .month = 7,
                            .day = 30,
                        },
                        .empty_default_input_was_later = false,
                    },
                },
            );
            try reopened.calculate();
            switch (try reopened.validateSave(2026, .not_evaluated)) {
                .passed => {},
                .failed => return error.ExpectedSavePass,
            }
            try reopened.generateEditableCandidate(.{
                .match = first_receipt.revision,
            });
            const second_receipt = switch (persistCurrentCandidateDevelopmentPlaintext(
                capability,
                &repository,
                reopened,
                resumed.historicalProfile(),
                resumed.frozenProvenance(),
                1_780_000_011,
            )) {
                .saved => |receipt| receipt,
                .blocked => return error.UnexpectedPersistenceBlock,
            };
            try std.testing.expectEqual(
                @as(u64, 2),
                second_receipt.revision.value,
            );
            var exact_history = (try repository
                .getExactDraftHistoryDevelopmentPlaintext(
                capability,
                allocator,
                second_receipt.draft_identity,
            )).?;
            defer exact_history.deinit(allocator);
            try std.testing.expectEqual(
                @as(usize, 2),
                exact_history.revisions.len,
            );
            for (exact_history.revisions) |revision| {
                try std.testing.expect(
                    revision.profile_snapshot_digest.eql(
                        &historical_candidate.profile_snapshot_digest,
                    ),
                );
            }
        },
        .not_found => return error.ExpectedPersistedWorkspace,
        .historical_projection_required => return error.UnexpectedHistoricalProjectionBlock,
        .blocked => |failure| {
            std.debug.print(
                "strict v19 resume blocked at {s}: {s}\n",
                .{ @tagName(failure.stage), @errorName(failure.reason) },
            );
            return error.UnexpectedResumeBlock;
        },
    }
}

test "exact runtime persists and uniquely resumes without coarse drafts" {
    const allocator = std.testing.allocator;
    const capability = key_custody.bootstrapCurrentArtifactStorage()
        .development_plaintext;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedTestProfile(&repository);
    var profile = try testProfile();

    switch (resumeUniqueDevelopmentPlaintext(
        capability,
        &repository,
        allocator,
        &profile,
        test_context,
        .editable_save,
    )) {
        .not_found => {},
        .opened => |value| {
            var unexpected = value;
            defer unexpected.deinit();
            return error.ExpectedNoPersistedWorkspace;
        },
        .historical_projection_required => return error.ExpectedNoPersistedWorkspace,
        .blocked => return error.UnexpectedResumeBlock,
    }

    var original: exact_ui.State = undefined;
    try openCandidate(&original, allocator, &repository, &profile);
    defer original.deinit();
    const first_receipt = switch (persistCurrentCandidateDevelopmentPlaintextLegacyForTest(
        capability,
        &repository,
        &original,
        &profile,
        1_780_000_001,
    )) {
        .saved => |receipt| receipt,
        .blocked => return error.UnexpectedPersistenceBlock,
    };
    try std.testing.expectEqual(@as(u64, 1), first_receipt.revision.value);

    switch (persistCurrentCandidateDevelopmentPlaintextLegacyForTest(
        capability,
        &repository,
        &original,
        &profile,
        1_780_000_002,
    )) {
        .saved => return error.ExpectedDuplicateSaveBlock,
        .blocked => |failure| {
            try std.testing.expectEqual(
                FailureStage.persist_exact_candidate,
                failure.stage,
            );
            try std.testing.expectEqual(
                error.DraftAlreadyExists,
                failure.reason,
            );
        },
    }

    switch (resumeUniqueDevelopmentPlaintext(
        capability,
        &repository,
        allocator,
        &profile,
        test_context,
        .editable_save,
    )) {
        .opened => |value| {
            var resumed = value;
            defer resumed.deinit();
            const reopened = resumed.state.?;
            const summary = try reopened.candidateSummary();
            try std.testing.expectEqual(
                draft.PayloadShape.editable_save,
                summary.shape,
            );
            try std.testing.expect(
                reopened.workspaceId().eql(
                    &first_receipt.draft_identity.workspace_id,
                ),
            );
        },
        .not_found => return error.ExpectedPersistedWorkspace,
        .historical_projection_required => return error.UnexpectedHistoricalProjectionBlock,
        .blocked => return error.UnexpectedResumeBlock,
    }

    var coarse = try repository.listDraftSummariesForProfile(
        allocator,
        "runtime-exact-filer",
        2026,
    );
    defer coarse.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), coarse.items.len);

    var alternate: exact_ui.State = undefined;
    try openCandidate(&alternate, allocator, &repository, &profile);
    defer alternate.deinit();
    switch (persistCurrentCandidateDevelopmentPlaintextLegacyForTest(
        capability,
        &repository,
        &alternate,
        &profile,
        1_780_000_003,
    )) {
        .saved => {},
        .blocked => return error.UnexpectedPersistenceBlock,
    }

    switch (resumeUniqueDevelopmentPlaintext(
        capability,
        &repository,
        allocator,
        &profile,
        test_context,
        .editable_save,
    )) {
        .opened => |value| {
            var unexpected = value;
            defer unexpected.deinit();
            return error.ExpectedAmbiguousResumeBlock;
        },
        .not_found => return error.ExpectedAmbiguousResumeBlock,
        .historical_projection_required => return error.ExpectedAmbiguousResumeBlock,
        .blocked => |failure| {
            try std.testing.expectEqual(
                FailureStage.list_matching_workspaces,
                failure.stage,
            );
            try std.testing.expectEqual(
                error.MultipleMatchingPersistedWorkspaces,
                failure.reason,
            );
        },
    }
}
