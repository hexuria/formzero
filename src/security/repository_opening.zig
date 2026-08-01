//! Typed, fail-before-I/O boundary for future production repositories.
//!
//! No backend, custody provider, database path, recovery policy, transition
//! policy, or qualification evidence is selected here.  The public factory
//! can only reject.  A private value-free test harness exercises the
//! provider-neutral, state-routed order that a later source-selected
//! implementation must satisfy before it may release a production repository
//! capability.

const builtin = @import("builtin");
const std = @import("std");
const key_custody = @import("key_custody.zig");
pub const requirements = @import("production_storage_requirements.zig");

/// Existing stock-SQLite constructors have this classification. It is not a
/// production capability and cannot be promoted by configuration.
pub const LegacyPlaintextRepositoryClassification =
    key_custody.ArtifactStorageClassification;

pub const legacy_plaintext_repository_classification: LegacyPlaintextRepositoryClassification =
    key_custody.current_artifact_storage_classification;

/// The file-backed calendar/profile call sites now require the source-minted
/// development capability. Production remains unavailable because no
/// authenticated repository implementation is integrated.
pub const ProductionRepositoryIntegrationState = enum {
    unavailable_development_plaintext_artifact_only,
};

pub const current_production_repository_integration_state: ProductionRepositoryIntegrationState =
    .unavailable_development_plaintext_artifact_only;

comptime {
    for (std.meta.fields(ProductionRepositoryIntegrationState)) |field| {
        if (!std.mem.startsWith(u8, field.name, "unavailable_")) {
            @compileError(
                "production repository integration must remain unavailable " ++
                    "until a reviewed authenticated implementation is connected",
            );
        }
    }
}

/// Calendar policy, taxpayer profiles, form snapshots, and exact draft
/// histories currently share one SQLite database and therefore one production
/// protection boundary.
pub const ProductionRepositoryScope = enum {
    shared_calendar_tax_profile_database,
};

/// Ordering is security-significant.  Policy and qualification binding precede
/// custody; custody and backend establishment precede location discovery;
/// only an authenticated repository marker reaches the schema callback that
/// is designated for SQL or PRAGMA work.
pub const OpeningStage = enum {
    release_qualification_binding,
    recovery_policy_binding,
    repository_transition_policy_binding,
    custody_provider_authentication,
    storage_backend_initialization,
    repository_location_resolution,
    artifact_set_classification,
    interrupted_operation_recovery,
    approved_provision_or_legacy_transition,
    repository_authentication,
    schema_inspection_or_migration,
    operational_readiness_verification,
};

/// Maximum repository authority available at each stage.  This is a contract
/// description; it does not make any stage reachable in production.
pub const StageAuthority = enum {
    no_repository_access,
    location_metadata_only,
    authenticated_backend_repository_bytes_only,
    authenticated_repository_sql_and_pragma,
};

pub fn stageAuthority(stage: OpeningStage) StageAuthority {
    return switch (stage) {
        .release_qualification_binding,
        .recovery_policy_binding,
        .repository_transition_policy_binding,
        .custody_provider_authentication,
        .storage_backend_initialization,
        => .no_repository_access,
        .repository_location_resolution => .location_metadata_only,
        .artifact_set_classification,
        .interrupted_operation_recovery,
        .approved_provision_or_legacy_transition,
        .repository_authentication,
        => .authenticated_backend_repository_bytes_only,
        .schema_inspection_or_migration,
        .operational_readiness_verification,
        => .authenticated_repository_sql_and_pragma,
    };
}

/// Opaque stage markers keep the private synthetic harness typed to the stage
/// that must precede each callback. They are not public capabilities: an opaque
/// pointer alone is forgeable and must never become production authority.
const QualifiedReleaseStage = opaque {};
const ApprovedRecoveryPolicyStage = opaque {};
const ApprovedRepositoryTransitionPolicyStage = opaque {};
const AuthenticatedCustodyStage = opaque {};
const AuthenticatedStorageBackendStage = opaque {};
const ResolvedRepositoryLocationStage = opaque {};
const ClassifiedArtifactSetStage = opaque {};
const ReconciledArtifactSetStage = opaque {};
const AuthenticatedRepositoryStage = opaque {};
const MigratedSchemaStage = opaque {};

/// Qualification is source/release evidence, not a runtime self-assertion.
/// The final callback must bind the opened repository back to that same
/// release approval.
const ReleaseQualificationContract = struct {
    context: *anyopaque,
    bind_release_evidence: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        required_scenarios: []const requirements.QualificationScenario,
    ) anyerror!void,
    verify_operational_readiness: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        release: *const QualifiedReleaseStage,
        repository: *const AuthenticatedRepositoryStage,
        schema: *const MigratedSchemaStage,
    ) anyerror!void,
};

/// Recovery and repository-transition authority are separate source-selected
/// approvals.  Neither callback receives a path, database bytes, or key.
const PolicyApprovalContract = struct {
    context: *anyopaque,
    bind_recovery_policy: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        required_scenarios: []const requirements.RecoveryScenario,
    ) anyerror!void,
    bind_repository_transition_policy: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        recovery: *const ApprovedRecoveryPolicyStage,
        classified_states: []const requirements.RepositoryArtifactState,
    ) anyerror!void,
};

/// A future approved operating-system provider must authenticate custody
/// without receiving a database path or exposing raw key bytes through this
/// interface.
const CustodyProviderContract = struct {
    context: *anyopaque,
    authenticate: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        recovery: *const ApprovedRecoveryPolicyStage,
        fail_closed_conditions: []const requirements.CustodyFailClosedCondition,
    ) anyerror!void,
};

/// Backend initialization receives only an opaque custody proof plus explicit
/// requirement vocabularies.  Classification and final authentication occur
/// through that backend, never by opening stock SQLite optimistically.
const AuthenticatedStorageBackendContract = struct {
    context: *anyopaque,
    initialize: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        custody: *const AuthenticatedCustodyStage,
        backend_requirements: []const requirements.AuthenticatedBackendRequirement,
        protected_surfaces: []const requirements.ProtectedArtifactSurface,
    ) anyerror!void,
    classify_artifact_set: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        backend: *const AuthenticatedStorageBackendStage,
        location: *const ResolvedRepositoryLocationStage,
        protected_surfaces: []const requirements.ProtectedArtifactSurface,
    ) anyerror!requirements.RepositoryArtifactState,
    authenticate_repository: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        backend: *const AuthenticatedStorageBackendStage,
        location: *const ResolvedRepositoryLocationStage,
        artifacts: *const ReconciledArtifactSetStage,
        state: requirements.RepositoryArtifactState,
    ) anyerror!void,
};

/// Location resolution cannot run until the authenticated backend exists.
/// The schema callback designated for SQL or PRAGMA work cannot run until the
/// entire artifact set has passed final backend authentication. A future
/// implementation still requires review of every callback body.
const RepositoryIoContract = struct {
    context: *anyopaque,
    resolve_location: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        backend: *const AuthenticatedStorageBackendStage,
    ) anyerror!void,
    inspect_or_migrate_schema: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        repository: *const AuthenticatedRepositoryStage,
    ) anyerror!void,
};

/// Interrupted authenticated operations are reconciled before any legacy or
/// initial-provision transition.  The central pipeline validates the allowed
/// state transition and never accepts an unrelated unsafe state as current.
const RecoveryContract = struct {
    context: *anyopaque,
    reconcile_interrupted_operation: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        recovery: *const ApprovedRecoveryPolicyStage,
        backend: *const AuthenticatedStorageBackendStage,
        location: *const ResolvedRepositoryLocationStage,
        artifacts: *const ClassifiedArtifactSetStage,
        state: requirements.RepositoryArtifactState,
    ) anyerror!requirements.RepositoryArtifactState,
};

/// This stage may provision an absent repository or apply an explicitly
/// approved legacy transition.  A legacy classification itself grants no
/// authority to read SQL, mutate, back up, quarantine, reset, or delete.
const RepositoryTransitionContract = struct {
    context: *anyopaque,
    apply_approved_transition: *const fn (
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        policy: *const ApprovedRepositoryTransitionPolicyStage,
        backend: *const AuthenticatedStorageBackendStage,
        location: *const ResolvedRepositoryLocationStage,
        artifacts: *const ClassifiedArtifactSetStage,
        state: requirements.RepositoryArtifactState,
    ) anyerror!requirements.RepositoryArtifactState,
};

const ProductionRepositoryContracts = struct {
    release_qualification: ReleaseQualificationContract,
    policy_approval: PolicyApprovalContract,
    custody_provider: CustodyProviderContract,
    storage_backend: AuthenticatedStorageBackendContract,
    repository_io: RepositoryIoContract,
    recovery: RecoveryContract,
    repository_transition: RepositoryTransitionContract,
};

/// This source-selected factory remains inert.  Every representable state is
/// unavailable, and `open` accepts no runtime contracts or provider selector.
/// A later provider change must bind its implementation in reviewed source.
pub const ProductionRepositoryFactory = struct {
    const Self = @This();

    pub fn current() Self {
        return .{};
    }

    /// Fails before qualification, policy, custody, backend, path, artifact,
    /// recovery, transition, authentication, schema, or readiness callbacks.
    pub fn open(
        self: Self,
        scope: ProductionRepositoryScope,
    ) key_custody.ProductionStorageError!*const key_custody.ProductionStorageCapability {
        _ = self;
        return openUnavailableProductionState(
            key_custody.current_production_storage_state,
            scope,
        );
    }
};

fn openUnavailableProductionState(
    state: key_custody.ProductionStorageState,
    scope: ProductionRepositoryScope,
) key_custody.ProductionStorageError!*const key_custody.ProductionStorageCapability {
    _ = scope;
    return switch (state) {
        .unavailable_authenticated_storage_backend_unselected,
        .unavailable_operating_system_custody_provider_unimplemented,
        .unavailable_recovery_policy_unapproved,
        .unavailable_legacy_plaintext_transition_unapproved,
        => key_custody.requireProductionStorage(),
    };
}

var release_stage_token: u8 = 0;
var recovery_policy_stage_token: u8 = 0;
var transition_policy_stage_token: u8 = 0;
var custody_stage_token: u8 = 0;
var backend_stage_token: u8 = 0;
var location_stage_token: u8 = 0;
var classified_stage_token: u8 = 0;
var reconciled_stage_token: u8 = 0;
var repository_stage_token: u8 = 0;
var schema_stage_token: u8 = 0;

const OrderedContractError = error{
    InvalidRecoveryStateTransition,
    InvalidRepositoryTransition,
    RepositoryNotAuthenticated,
};

fn validRecoveryTransition(
    before: requirements.RepositoryArtifactState,
    after: requirements.RepositoryArtifactState,
) bool {
    return switch (before) {
        .authenticated_interrupted_provision,
        .authenticated_interrupted_rotation,
        .authenticated_interrupted_migration,
        => after == .authenticated_current,
        .absent,
        .authenticated_current,
        .legacy_plaintext_untrusted,
        .unsupported_cipher_version,
        .custody_database_pair_mismatch,
        .unrecognized_or_tampered,
        => false,
    };
}

fn validRepositoryTransition(
    before: requirements.RepositoryArtifactState,
    after: requirements.RepositoryArtifactState,
) bool {
    return switch (before) {
        .absent,
        .legacy_plaintext_untrusted,
        => after == .authenticated_current,
        .authenticated_current,
        .authenticated_interrupted_provision,
        .authenticated_interrupted_rotation,
        .authenticated_interrupted_migration,
        .unsupported_cipher_version,
        .custody_database_pair_mismatch,
        .unrecognized_or_tampered,
        => false,
    };
}

/// Exercises only value-free ordering and state-transition rules.  It cannot
/// compile into a non-test artifact and creates no production authority.
fn exerciseOrderedContractsForTest(
    scope: ProductionRepositoryScope,
    contracts: *const ProductionRepositoryContracts,
) anyerror!void {
    comptime {
        if (!builtin.is_test) {
            @compileError(
                "synthetic repository-opening stages are test-only",
            );
        }
    }

    try contracts.release_qualification.bind_release_evidence(
        contracts.release_qualification.context,
        scope,
        &requirements.required_qualification_scenarios,
    );
    const release: *const QualifiedReleaseStage =
        @ptrCast(&release_stage_token);

    try contracts.policy_approval.bind_recovery_policy(
        contracts.policy_approval.context,
        scope,
        &requirements.required_recovery_scenarios,
    );
    const recovery_policy: *const ApprovedRecoveryPolicyStage =
        @ptrCast(&recovery_policy_stage_token);

    try contracts.policy_approval.bind_repository_transition_policy(
        contracts.policy_approval.context,
        scope,
        recovery_policy,
        &requirements.required_repository_artifact_states,
    );
    const transition_policy: *const ApprovedRepositoryTransitionPolicyStage =
        @ptrCast(&transition_policy_stage_token);

    try contracts.custody_provider.authenticate(
        contracts.custody_provider.context,
        scope,
        recovery_policy,
        &requirements.required_custody_fail_closed_conditions,
    );
    const custody: *const AuthenticatedCustodyStage =
        @ptrCast(&custody_stage_token);

    try contracts.storage_backend.initialize(
        contracts.storage_backend.context,
        scope,
        custody,
        &requirements.required_authenticated_backend_requirements,
        &requirements.required_protected_artifact_surfaces,
    );
    const backend: *const AuthenticatedStorageBackendStage =
        @ptrCast(&backend_stage_token);

    try contracts.repository_io.resolve_location(
        contracts.repository_io.context,
        scope,
        backend,
    );
    const location: *const ResolvedRepositoryLocationStage =
        @ptrCast(&location_stage_token);

    var state = try contracts.storage_backend.classify_artifact_set(
        contracts.storage_backend.context,
        scope,
        backend,
        location,
        &requirements.required_protected_artifact_surfaces,
    );
    const classified: *const ClassifiedArtifactSetStage =
        @ptrCast(&classified_stage_token);

    switch (state) {
        .authenticated_interrupted_provision,
        .authenticated_interrupted_rotation,
        .authenticated_interrupted_migration,
        => {
            const recovered_state =
                try contracts.recovery.reconcile_interrupted_operation(
                    contracts.recovery.context,
                    scope,
                    recovery_policy,
                    backend,
                    location,
                    classified,
                    state,
                );
            if (!validRecoveryTransition(state, recovered_state)) {
                return error.InvalidRecoveryStateTransition;
            }
            state = recovered_state;
        },
        .absent,
        .authenticated_current,
        .legacy_plaintext_untrusted,
        => {},
        .unsupported_cipher_version,
        .custody_database_pair_mismatch,
        .unrecognized_or_tampered,
        => return error.RepositoryNotAuthenticated,
    }

    switch (state) {
        .absent,
        .legacy_plaintext_untrusted,
        => {
            const transitioned_state =
                try contracts.repository_transition.apply_approved_transition(
                    contracts.repository_transition.context,
                    scope,
                    transition_policy,
                    backend,
                    location,
                    classified,
                    state,
                );
            if (!validRepositoryTransition(state, transitioned_state)) {
                return error.InvalidRepositoryTransition;
            }
            state = transitioned_state;
        },
        .authenticated_current => {},
        .authenticated_interrupted_provision,
        .authenticated_interrupted_rotation,
        .authenticated_interrupted_migration,
        .unsupported_cipher_version,
        .custody_database_pair_mismatch,
        .unrecognized_or_tampered,
        => return error.RepositoryNotAuthenticated,
    }
    if (state != .authenticated_current) {
        return error.RepositoryNotAuthenticated;
    }
    const reconciled: *const ReconciledArtifactSetStage =
        @ptrCast(&reconciled_stage_token);

    try contracts.storage_backend.authenticate_repository(
        contracts.storage_backend.context,
        scope,
        backend,
        location,
        reconciled,
        state,
    );
    const repository: *const AuthenticatedRepositoryStage =
        @ptrCast(&repository_stage_token);

    try contracts.repository_io.inspect_or_migrate_schema(
        contracts.repository_io.context,
        scope,
        repository,
    );
    const schema: *const MigratedSchemaStage =
        @ptrCast(&schema_stage_token);

    try contracts.release_qualification.verify_operational_readiness(
        contracts.release_qualification.context,
        scope,
        release,
        repository,
        schema,
    );
}

const opening_stage_count = std.meta.fields(OpeningStage).len;

const ContractSpy = struct {
    const Self = @This();
    const Error = error{SyntheticStageFailure};

    observed: [opening_stage_count]OpeningStage = undefined,
    observed_count: usize = 0,
    fail_at: ?OpeningStage = null,
    classified_state: requirements.RepositoryArtifactState =
        .authenticated_current,
    recovery_result: ?requirements.RepositoryArtifactState = null,
    transition_result: ?requirements.RepositoryArtifactState = null,

    fn contracts(self: *Self) ProductionRepositoryContracts {
        return .{
            .release_qualification = .{
                .context = self,
                .bind_release_evidence = bindReleaseEvidence,
                .verify_operational_readiness = verifyOperationalReadiness,
            },
            .policy_approval = .{
                .context = self,
                .bind_recovery_policy = bindRecoveryPolicy,
                .bind_repository_transition_policy = bindRepositoryTransitionPolicy,
            },
            .custody_provider = .{
                .context = self,
                .authenticate = authenticateCustody,
            },
            .storage_backend = .{
                .context = self,
                .initialize = initializeBackend,
                .classify_artifact_set = classifyArtifactSet,
                .authenticate_repository = authenticateRepository,
            },
            .repository_io = .{
                .context = self,
                .resolve_location = resolveLocation,
                .inspect_or_migrate_schema = inspectOrMigrateSchema,
            },
            .recovery = .{
                .context = self,
                .reconcile_interrupted_operation = reconcileInterruptedOperation,
            },
            .repository_transition = .{
                .context = self,
                .apply_approved_transition = applyApprovedTransition,
            },
        };
    }

    fn record(self: *Self, stage: OpeningStage) Error!void {
        self.observed[self.observed_count] = stage;
        self.observed_count += 1;
        if (self.fail_at == stage) return error.SyntheticStageFailure;
    }

    fn fromContext(context: *anyopaque) *Self {
        return @ptrCast(@alignCast(context));
    }

    fn bindReleaseEvidence(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        scenarios: []const requirements.QualificationScenario,
    ) anyerror!void {
        _ = scope;
        try std.testing.expectEqual(
            requirements.required_qualification_scenarios.len,
            scenarios.len,
        );
        try fromContext(context).record(.release_qualification_binding);
    }

    fn bindRecoveryPolicy(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        scenarios: []const requirements.RecoveryScenario,
    ) anyerror!void {
        _ = scope;
        try std.testing.expectEqual(
            requirements.required_recovery_scenarios.len,
            scenarios.len,
        );
        try fromContext(context).record(.recovery_policy_binding);
    }

    fn bindRepositoryTransitionPolicy(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        recovery: *const ApprovedRecoveryPolicyStage,
        states: []const requirements.RepositoryArtifactState,
    ) anyerror!void {
        _ = scope;
        _ = recovery;
        try std.testing.expectEqual(
            requirements.required_repository_artifact_states.len,
            states.len,
        );
        try fromContext(context).record(
            .repository_transition_policy_binding,
        );
    }

    fn authenticateCustody(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        recovery: *const ApprovedRecoveryPolicyStage,
        conditions: []const requirements.CustodyFailClosedCondition,
    ) anyerror!void {
        _ = scope;
        _ = recovery;
        try std.testing.expectEqual(
            requirements.required_custody_fail_closed_conditions.len,
            conditions.len,
        );
        try fromContext(context).record(
            .custody_provider_authentication,
        );
    }

    fn initializeBackend(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        custody: *const AuthenticatedCustodyStage,
        backend_requirements: []const requirements.AuthenticatedBackendRequirement,
        surfaces: []const requirements.ProtectedArtifactSurface,
    ) anyerror!void {
        _ = scope;
        _ = custody;
        try std.testing.expectEqual(
            requirements.required_authenticated_backend_requirements.len,
            backend_requirements.len,
        );
        try std.testing.expectEqual(
            requirements.required_protected_artifact_surfaces.len,
            surfaces.len,
        );
        try fromContext(context).record(.storage_backend_initialization);
    }

    fn resolveLocation(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        backend: *const AuthenticatedStorageBackendStage,
    ) anyerror!void {
        _ = scope;
        _ = backend;
        try fromContext(context).record(
            .repository_location_resolution,
        );
    }

    fn classifyArtifactSet(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        backend: *const AuthenticatedStorageBackendStage,
        location: *const ResolvedRepositoryLocationStage,
        surfaces: []const requirements.ProtectedArtifactSurface,
    ) anyerror!requirements.RepositoryArtifactState {
        _ = scope;
        _ = backend;
        _ = location;
        try std.testing.expectEqual(
            requirements.required_protected_artifact_surfaces.len,
            surfaces.len,
        );
        const self = fromContext(context);
        try self.record(.artifact_set_classification);
        return self.classified_state;
    }

    fn reconcileInterruptedOperation(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        recovery: *const ApprovedRecoveryPolicyStage,
        backend: *const AuthenticatedStorageBackendStage,
        location: *const ResolvedRepositoryLocationStage,
        artifacts: *const ClassifiedArtifactSetStage,
        state: requirements.RepositoryArtifactState,
    ) anyerror!requirements.RepositoryArtifactState {
        _ = scope;
        _ = recovery;
        _ = backend;
        _ = location;
        _ = artifacts;
        const self = fromContext(context);
        try self.record(.interrupted_operation_recovery);
        return self.recovery_result orelse state;
    }

    fn applyApprovedTransition(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        policy: *const ApprovedRepositoryTransitionPolicyStage,
        backend: *const AuthenticatedStorageBackendStage,
        location: *const ResolvedRepositoryLocationStage,
        artifacts: *const ClassifiedArtifactSetStage,
        state: requirements.RepositoryArtifactState,
    ) anyerror!requirements.RepositoryArtifactState {
        _ = scope;
        _ = policy;
        _ = backend;
        _ = location;
        _ = artifacts;
        const self = fromContext(context);
        try self.record(.approved_provision_or_legacy_transition);
        return self.transition_result orelse state;
    }

    fn authenticateRepository(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        backend: *const AuthenticatedStorageBackendStage,
        location: *const ResolvedRepositoryLocationStage,
        artifacts: *const ReconciledArtifactSetStage,
        state: requirements.RepositoryArtifactState,
    ) anyerror!void {
        _ = scope;
        _ = backend;
        _ = location;
        _ = artifacts;
        try std.testing.expectEqual(
            requirements.RepositoryArtifactState.authenticated_current,
            state,
        );
        try fromContext(context).record(.repository_authentication);
    }

    fn inspectOrMigrateSchema(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        repository: *const AuthenticatedRepositoryStage,
    ) anyerror!void {
        _ = scope;
        _ = repository;
        try fromContext(context).record(
            .schema_inspection_or_migration,
        );
    }

    fn verifyOperationalReadiness(
        context: *anyopaque,
        scope: ProductionRepositoryScope,
        release: *const QualifiedReleaseStage,
        repository: *const AuthenticatedRepositoryStage,
        schema: *const MigratedSchemaStage,
    ) anyerror!void {
        _ = scope;
        _ = release;
        _ = repository;
        _ = schema;
        try fromContext(context).record(
            .operational_readiness_verification,
        );
    }
};

const opening_stage_definition_order = [_]OpeningStage{
    .release_qualification_binding,
    .recovery_policy_binding,
    .repository_transition_policy_binding,
    .custody_provider_authentication,
    .storage_backend_initialization,
    .repository_location_resolution,
    .artifact_set_classification,
    .interrupted_operation_recovery,
    .approved_provision_or_legacy_transition,
    .repository_authentication,
    .schema_inspection_or_migration,
    .operational_readiness_verification,
};

const classification_prefix_order = [_]OpeningStage{
    .release_qualification_binding,
    .recovery_policy_binding,
    .repository_transition_policy_binding,
    .custody_provider_authentication,
    .storage_backend_initialization,
    .repository_location_resolution,
    .artifact_set_classification,
};

const authenticated_current_order = [_]OpeningStage{
    .release_qualification_binding,
    .recovery_policy_binding,
    .repository_transition_policy_binding,
    .custody_provider_authentication,
    .storage_backend_initialization,
    .repository_location_resolution,
    .artifact_set_classification,
    .repository_authentication,
    .schema_inspection_or_migration,
    .operational_readiness_verification,
};

const interrupted_recovery_order = [_]OpeningStage{
    .release_qualification_binding,
    .recovery_policy_binding,
    .repository_transition_policy_binding,
    .custody_provider_authentication,
    .storage_backend_initialization,
    .repository_location_resolution,
    .artifact_set_classification,
    .interrupted_operation_recovery,
    .repository_authentication,
    .schema_inspection_or_migration,
    .operational_readiness_verification,
};

const provision_or_legacy_transition_order = [_]OpeningStage{
    .release_qualification_binding,
    .recovery_policy_binding,
    .repository_transition_policy_binding,
    .custody_provider_authentication,
    .storage_backend_initialization,
    .repository_location_resolution,
    .artifact_set_classification,
    .approved_provision_or_legacy_transition,
    .repository_authentication,
    .schema_inspection_or_migration,
    .operational_readiness_verification,
};

comptime {
    if (opening_stage_definition_order.len != opening_stage_count) {
        @compileError(
            "opening stage definition order must list every tag exactly once",
        );
    }
    for (std.meta.tags(OpeningStage)) |tag| {
        var count: usize = 0;
        for (opening_stage_definition_order) |candidate| {
            if (candidate == tag) count += 1;
        }
        if (count != 1) {
            @compileError(
                "opening stage definition order must list every tag exactly once",
            );
        }
    }
}

test "every production state fails before every external callback" {
    try std.testing.expectEqual(
        @as(usize, 0),
        std.meta.fields(ProductionRepositoryFactory).len,
    );
    inline for (std.meta.tags(key_custody.ProductionStorageState)) |state| {
        var spy: ContractSpy = .{};
        _ = spy.contracts();
        try std.testing.expectError(
            error.ProductionStorageUnavailable,
            openUnavailableProductionState(
                state,
                .shared_calendar_tax_profile_database,
            ),
        );
        try std.testing.expectEqual(@as(usize, 0), spy.observed_count);
    }
    const factory = ProductionRepositoryFactory.current();
    try std.testing.expectError(
        error.ProductionStorageUnavailable,
        factory.open(.shared_calendar_tax_profile_database),
    );
}

test "authenticated current route skips recovery and transition callbacks" {
    var spy: ContractSpy = .{};
    const contracts = spy.contracts();
    try exerciseOrderedContractsForTest(
        .shared_calendar_tax_profile_database,
        &contracts,
    );
    try std.testing.expectEqualSlices(
        OpeningStage,
        &authenticated_current_order,
        spy.observed[0..spy.observed_count],
    );
}

test "each callback failure prevents every later stage" {
    const routes = [_]struct {
        classified_state: requirements.RepositoryArtifactState,
        recovery_result: ?requirements.RepositoryArtifactState = null,
        transition_result: ?requirements.RepositoryArtifactState = null,
        order: []const OpeningStage,
    }{
        .{
            .classified_state = .authenticated_current,
            .order = &authenticated_current_order,
        },
        .{
            .classified_state = .authenticated_interrupted_provision,
            .recovery_result = .authenticated_current,
            .order = &interrupted_recovery_order,
        },
        .{
            .classified_state = .absent,
            .transition_result = .authenticated_current,
            .order = &provision_or_legacy_transition_order,
        },
    };
    for (routes) |route| {
        for (route.order, 0..) |failed_stage, failed_index| {
            var spy: ContractSpy = .{
                .fail_at = failed_stage,
                .classified_state = route.classified_state,
                .recovery_result = route.recovery_result,
                .transition_result = route.transition_result,
            };
            const contracts = spy.contracts();
            try std.testing.expectError(
                error.SyntheticStageFailure,
                exerciseOrderedContractsForTest(
                    .shared_calendar_tax_profile_database,
                    &contracts,
                ),
            );
            try std.testing.expectEqualSlices(
                OpeningStage,
                route.order[0 .. failed_index + 1],
                spy.observed[0..spy.observed_count],
            );
        }
    }
}

test "interrupted authenticated states require the recovery stage" {
    const interrupted = [_]requirements.RepositoryArtifactState{
        .authenticated_interrupted_provision,
        .authenticated_interrupted_rotation,
        .authenticated_interrupted_migration,
    };
    for (interrupted) |state| {
        var spy: ContractSpy = .{
            .classified_state = state,
            .recovery_result = .authenticated_current,
        };
        const contracts = spy.contracts();
        try exerciseOrderedContractsForTest(
            .shared_calendar_tax_profile_database,
            &contracts,
        );
        try std.testing.expectEqualSlices(
            OpeningStage,
            &interrupted_recovery_order,
            spy.observed[0..spy.observed_count],
        );
    }
}

test "absent and legacy states require an approved transition" {
    const transition_states = [_]requirements.RepositoryArtifactState{
        .absent,
        .legacy_plaintext_untrusted,
    };
    for (transition_states) |state| {
        var spy: ContractSpy = .{
            .classified_state = state,
            .transition_result = .authenticated_current,
        };
        const contracts = spy.contracts();
        try exerciseOrderedContractsForTest(
            .shared_calendar_tax_profile_database,
            &contracts,
        );
        try std.testing.expectEqualSlices(
            OpeningStage,
            &provision_or_legacy_transition_order,
            spy.observed[0..spy.observed_count],
        );
    }
}

test "unsafe artifact states cannot reach authentication or schema callback" {
    const transition_required = [_]requirements.RepositoryArtifactState{
        .absent,
        .legacy_plaintext_untrusted,
    };
    for (transition_required) |state| {
        var spy: ContractSpy = .{ .classified_state = state };
        const contracts = spy.contracts();
        try std.testing.expectError(
            error.InvalidRepositoryTransition,
            exerciseOrderedContractsForTest(
                .shared_calendar_tax_profile_database,
                &contracts,
            ),
        );
        try std.testing.expectEqualSlices(
            OpeningStage,
            provision_or_legacy_transition_order[0..8],
            spy.observed[0..spy.observed_count],
        );
    }

    const terminally_unsafe = [_]requirements.RepositoryArtifactState{
        .unsupported_cipher_version,
        .custody_database_pair_mismatch,
        .unrecognized_or_tampered,
    };
    for (terminally_unsafe) |state| {
        var spy: ContractSpy = .{ .classified_state = state };
        const contracts = spy.contracts();
        try std.testing.expectError(
            error.RepositoryNotAuthenticated,
            exerciseOrderedContractsForTest(
                .shared_calendar_tax_profile_database,
                &contracts,
            ),
        );
        try std.testing.expectEqualSlices(
            OpeningStage,
            &classification_prefix_order,
            spy.observed[0..spy.observed_count],
        );
    }
}

test "state callbacks cannot relabel unrelated unsafe artifacts" {
    var invalid_recovery: ContractSpy = .{
        .classified_state = .authenticated_interrupted_provision,
        .recovery_result = .legacy_plaintext_untrusted,
    };
    var contracts = invalid_recovery.contracts();
    try std.testing.expectError(
        error.InvalidRecoveryStateTransition,
        exerciseOrderedContractsForTest(
            .shared_calendar_tax_profile_database,
            &contracts,
        ),
    );
    try std.testing.expectEqualSlices(
        OpeningStage,
        interrupted_recovery_order[0..8],
        invalid_recovery.observed[0..invalid_recovery.observed_count],
    );

    var invalid_transition: ContractSpy = .{
        .classified_state = .legacy_plaintext_untrusted,
        .transition_result = .custody_database_pair_mismatch,
    };
    contracts = invalid_transition.contracts();
    try std.testing.expectError(
        error.InvalidRepositoryTransition,
        exerciseOrderedContractsForTest(
            .shared_calendar_tax_profile_database,
            &contracts,
        ),
    );
    try std.testing.expectEqualSlices(
        OpeningStage,
        provision_or_legacy_transition_order[0..8],
        invalid_transition.observed[0..invalid_transition.observed_count],
    );
}

test "recovery and repository transition allowlists are exhaustive" {
    const states = std.meta.tags(requirements.RepositoryArtifactState);
    for (states) |before| {
        for (states) |after| {
            const expected_recovery = switch (before) {
                .authenticated_interrupted_provision,
                .authenticated_interrupted_rotation,
                .authenticated_interrupted_migration,
                => after == .authenticated_current,
                .absent,
                .authenticated_current,
                .legacy_plaintext_untrusted,
                .unsupported_cipher_version,
                .custody_database_pair_mismatch,
                .unrecognized_or_tampered,
                => false,
            };
            try std.testing.expectEqual(
                expected_recovery,
                validRecoveryTransition(before, after),
            );

            const expected_transition = switch (before) {
                .absent,
                .legacy_plaintext_untrusted,
                => after == .authenticated_current,
                .authenticated_current,
                .authenticated_interrupted_provision,
                .authenticated_interrupted_rotation,
                .authenticated_interrupted_migration,
                .unsupported_cipher_version,
                .custody_database_pair_mismatch,
                .unrecognized_or_tampered,
                => false,
            };
            try std.testing.expectEqual(
                expected_transition,
                validRepositoryTransition(before, after),
            );
        }
    }
}

test "stage authority permits SQL only after repository authentication" {
    for (opening_stage_definition_order) |stage| {
        const expected: StageAuthority = switch (stage) {
            .release_qualification_binding,
            .recovery_policy_binding,
            .repository_transition_policy_binding,
            .custody_provider_authentication,
            .storage_backend_initialization,
            => .no_repository_access,
            .repository_location_resolution => .location_metadata_only,
            .artifact_set_classification,
            .interrupted_operation_recovery,
            .approved_provision_or_legacy_transition,
            .repository_authentication,
            => .authenticated_backend_repository_bytes_only,
            .schema_inspection_or_migration,
            .operational_readiness_verification,
            => .authenticated_repository_sql_and_pragma,
        };
        try std.testing.expectEqual(expected, stageAuthority(stage));
    }
}

test "legacy plaintext vocabulary cannot imply production authority" {
    inline for (
        std.meta.fields(LegacyPlaintextRepositoryClassification),
    ) |field| {
        try std.testing.expect(
            std.mem.endsWith(u8, field.name, "_not_production"),
        );
    }
    inline for (
        std.meta.fields(ProductionRepositoryIntegrationState),
    ) |field| {
        try std.testing.expect(
            std.mem.startsWith(u8, field.name, "unavailable_"),
        );
    }
}
