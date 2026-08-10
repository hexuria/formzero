//! SQLite adapter for the taxpayer-registration ledger.
//!
//! The public interface is intentionally small: list taxpayer identities,
//! record evidence, atomically promote reviewed evidence with its dependent
//! commands, apply one pure registration command, or read a registration
//! snapshot. Filing policy and legacy-profile migration remain outside this
//! module.

const std = @import("std");
const builtin = @import("builtin");
const key_custody = @import("../security/key_custody.zig");
const store = @import("store.zig");
const domain = @import("registration_domain.zig");
const storage_contract = @import("registration_storage_contract.zig");
const evidence_binding = @import("../filing/evidence_binding.zig");
const filing_planner = @import("../filing/planner.zig");
const filing_policy = @import("../filing/policy.zig");
const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

pub const ReviewedEvidenceBinding = evidence_binding.ReviewedEvidenceBinding;

pub const Error = domain.RegistrationError || store.Error ||
    std.mem.Allocator.Error || error{
    EvidenceNotAccepted,
    EvidenceAssertionNotAccepted,
    EvidenceAssertionSetFrozen,
    NonAuthoritativeEvidenceStorage,
    InvalidEvidenceWrite,
    InvalidEvidenceReviewDecisionWrite,
    InvalidEvidenceAssertionWrite,
    InvalidReviewedEvidenceBundleWrite,
    InvalidStoredValue,
    StaleRegistrationUnitHistory,
    StaleRegistrationUnitContactHistory,
    StaleTaxTypeRegistrationHistory,
    StaleTaxpayerHistory,
    StaleEvidenceReviewHistory,
    RevisionSequenceExhausted,
    LegacyMigrationCutoverAuthorityRequired,
};

/// No production constructor exists until a separately reviewed cutover
/// design defines how authority is approved, scoped, recorded, and revoked.
/// This private token exists only so tests can seed unresolved legacy state.
const LegacyMigrationCutoverAuthority = opaque {};
var legacy_migration_test_authority_token: u8 = 0;

pub const EvidenceSourceKind = enum {
    cor,
    ecor,
    bir_registration_record,
    migration_record,
    other_reviewed,
};

pub const EvidenceReviewState = enum {
    accepted,
    rejected,
    superseded,
};

/// Where the evidence bytes are governed. The metadata-only state is
/// deliberately explicit and never authorizes reading or locating content.
pub const EvidenceStorageReference = union(enum) {
    metadata_only_non_authoritative,
    protected_local_path: []const u8,
    encrypted_blob_reference: []const u8,
};

/// Actor that made one immutable review decision. A local human/operator is
/// bound to the store's singleton owner row; service decisions use their own
/// typed stable identity.
pub const EvidenceReviewActor = union(enum) {
    local_owner: store.OpaqueId,
    service: domain.RegistrationEvidenceReviewServiceActorId,
};

/// Immutable metadata for one captured evidence artifact. Recording metadata
/// never implies acceptance; review decisions are a separate append-only
/// stream. The SHA-256 digest is preserved exactly as captured.
pub const EvidenceWrite = struct {
    id: domain.RegistrationEvidenceId,
    source_kind: EvidenceSourceKind,
    sha256: []const u8,
    display_name: []const u8,
    byte_size: u64,
    captured_on: domain.Date,
    storage: EvidenceStorageReference,
};

pub const EvidenceReviewDecisionWrite = struct {
    id: domain.RegistrationEvidenceReviewDecisionId,
    evidence_id: domain.RegistrationEvidenceId,
    expected_history_sequence: u32 = 0,
    state: EvidenceReviewState,
    reviewer: EvidenceReviewActor,
    reviewed_at_unix_seconds: i64,
    reason: []const u8,
    supersedes: ?domain.RegistrationEvidenceReviewDecisionId = null,
    contradicts: ?domain.RegistrationEvidenceReviewDecisionId = null,
};

/// A reviewed fact asserted by an accepted evidence document. Metadata saying
/// a COR was accepted is intentionally insufficient: a filing-capable unit or
/// tax registration must cite the exact taxpayer, registration unit, fact, and
/// effective date that the reviewer accepted.
pub const EvidenceAssertionFact = union(enum) {
    taxpayer_tin_root: struct {
        tin_root: domain.Tin9,
    },
    registration_unit: struct {
        branch_code: domain.BranchCode5,
        status: domain.RegistrationUnitStatus,
        rdo_code: ?domain.RdoCode3 = null,
    },
    registration_unit_contact: domain.RegistrationUnitContact,
    tax_type_registration: struct {
        tax_type: domain.TaxType,
        status: domain.TaxTypeRegistrationStatus,
    },
};

pub const EvidenceAssertionWrite = struct {
    id: domain.RegistrationEvidenceAssertionId,
    evidence_id: domain.RegistrationEvidenceId,
    taxpayer_id: domain.TaxpayerId,
    registration_unit_id: ?domain.RegistrationUnitId = null,
    effective_from: domain.Date,
    fact: EvidenceAssertionFact,
};

/// Caller-owned input for one atomic evidence promotion. The slices are
/// borrowed only for the duration of `recordReviewedEvidenceBundle`; no
/// command results or borrowed database values escape the transaction.
pub const ReviewedEvidenceBundleWrite = struct {
    evidence: EvidenceWrite,
    initial_review: EvidenceReviewDecisionWrite,
    assertions: []const EvidenceAssertionWrite,
    commands: []const domain.RegistrationCommand,
};

/// Allocator-owned deterministic taxpayer identifiers. Call `deinit` exactly
/// once with the same allocator supplied to `TaxpayerRegistrationLedger.init`.
pub const OwnedTaxpayerIdList = struct {
    items: []const domain.TaxpayerId,

    pub fn deinit(self: *OwnedTaxpayerIdList, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
        self.* = undefined;
    }
};

/// A request for one coherent civil-date registration view. A filing period
/// with different endpoints must be handled by policy/planner code that can
/// review mid-period changes; this adapter never picks one endpoint silently.
pub const SnapshotRequest = struct {
    taxpayer_id: domain.TaxpayerId,
    start: domain.Date,
    end: domain.Date,
};

pub const EvidenceReviewReason = evidence_binding.EvidenceReviewReason;
pub const EvidenceReviewSubject = evidence_binding.EvidenceReviewSubject;
pub const EvidenceReviewIssue = evidence_binding.EvidenceReviewIssue;

pub const SnapshotReviewRequired = union(enum) {
    period_spans_multiple_dates,
    taxpayer_identity_missing,
    evidence: EvidenceReviewIssue,
};

/// A period-coherent input for FilingPlanner. Unlike `snapshot`, this retains
/// every unit and tax-registration revision whose derived effective interval
/// intersects the entire requested civil period, so the planner can reject a
/// mid-period change rather than silently selecting an endpoint.
pub const PlanningSnapshotReviewRequired = union(enum) {
    taxpayer_identity_missing,
    taxpayer_identity_changed_during_period,
    evidence: EvidenceReviewIssue,
};

/// Borrowed view of allocator-owned rows. It intentionally exposes only
/// registration facts; planners consume this value without importing SQLite or
/// profile storage.
pub const ResolvedRegistrationSnapshot = struct {
    taxpayer_identity: domain.TaxpayerIdentityRevision,
    units: []const domain.RegistrationUnitRevision,
    contacts: []const domain.RegistrationUnitContactRevision,
    tax_type_registrations: []const domain.TaxTypeRegistrationRevision,
    lineage: []const domain.BranchCodeLineageEntry,
    /// False means current registration facts are coherent but at least one
    /// historical lineage artifact is no longer review-authoritative. Callers
    /// must disable lineage-derived suggestions while retaining current facts.
    lineage_complete: bool,
    reviewed_evidence_bindings: []const ReviewedEvidenceBinding,
    as_of: domain.Date,

    pub fn deinit(
        self: *ResolvedRegistrationSnapshot,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.units);
        allocator.free(self.contacts);
        allocator.free(self.tax_type_registrations);
        allocator.free(self.lineage);
        allocator.free(self.reviewed_evidence_bindings);
        self.* = undefined;
    }
};

pub const RegistrationSnapshotResult = union(enum) {
    resolved: ResolvedRegistrationSnapshot,
    review_required: SnapshotReviewRequired,

    pub fn deinit(
        self: *RegistrationSnapshotResult,
        allocator: std.mem.Allocator,
    ) void {
        switch (self.*) {
            .resolved => |*value| value.deinit(allocator),
            .review_required => {},
        }
        self.* = undefined;
    }
};

pub const ResolvedPlanningRegistrationSnapshot = struct {
    taxpayer_identity: domain.TaxpayerIdentityRevision,
    units: []const domain.RegistrationUnitRevision,
    contacts: []const domain.RegistrationUnitContactRevision,
    tax_type_registrations: []const domain.TaxTypeRegistrationRevision,
    reviewed_evidence_bindings: []const ReviewedEvidenceBinding,
    period_start: domain.Date,
    period_end: domain.Date,

    pub fn deinit(
        self: *ResolvedPlanningRegistrationSnapshot,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.units);
        allocator.free(self.contacts);
        allocator.free(self.tax_type_registrations);
        allocator.free(self.reviewed_evidence_bindings);
        self.* = undefined;
    }
};

pub const PlanningRegistrationSnapshotResult = union(enum) {
    resolved: ResolvedPlanningRegistrationSnapshot,
    review_required: PlanningSnapshotReviewRequired,

    pub fn deinit(
        self: *PlanningRegistrationSnapshotResult,
        allocator: std.mem.Allocator,
    ) void {
        switch (self.*) {
            .resolved => |*value| value.deinit(allocator),
            .review_required => {},
        }
        self.* = undefined;
    }
};

/// Fail-closed result supplied by the caller-owned evidence byte verifier.
/// The ledger owns metadata and subject selection; the verifier owns storage
/// I/O. This keeps filesystem access out of SQLite and UI code out of tables.
pub const EvidenceIntegrityReviewRequired = enum {
    protected_bytes_missing,
    protected_bytes_unreadable,
    protected_bytes_size_mismatch,
    protected_bytes_digest_mismatch,
    stored_metadata_invalid,
    storage_backend_unverifiable,
};

/// The verifier cause plus the exact document whose protected bytes failed.
pub const EvidenceIntegrityReviewIssue = struct {
    cause: EvidenceIntegrityReviewRequired,
    evidence_id: domain.RegistrationEvidenceId,
};

/// Borrowed immutable metadata for one referenced protected evidence object.
/// All slices remain valid only for the duration of the verifier callback.
pub const ProtectedEvidenceVerificationInput = struct {
    evidence_id: domain.RegistrationEvidenceId,
    protected_path: []const u8,
    sha256: []const u8,
    byte_size: u64,
};

pub const EvidenceIntegrityVerifier = struct {
    context: *anyopaque,
    verify_fn: *const fn (
        context: *anyopaque,
        input: ProtectedEvidenceVerificationInput,
    ) ?EvidenceIntegrityReviewRequired,

    fn verify(
        self: EvidenceIntegrityVerifier,
        input: ProtectedEvidenceVerificationInput,
    ) ?EvidenceIntegrityReviewRequired {
        return self.verify_fn(self.context, input);
    }
};

pub const IntegrityCheckedRegistrationSnapshotResult = union(enum) {
    resolved: ResolvedRegistrationSnapshot,
    registration_review_required: SnapshotReviewRequired,
    evidence_integrity_review_required: EvidenceIntegrityReviewIssue,

    pub fn deinit(
        self: *IntegrityCheckedRegistrationSnapshotResult,
        allocator: std.mem.Allocator,
    ) void {
        switch (self.*) {
            .resolved => |*value| value.deinit(allocator),
            .registration_review_required,
            .evidence_integrity_review_required,
            => {},
        }
        self.* = undefined;
    }
};

pub const IntegrityCheckedPlanningRegistrationSnapshotResult = union(enum) {
    resolved: ResolvedPlanningRegistrationSnapshot,
    registration_review_required: PlanningSnapshotReviewRequired,
    evidence_integrity_review_required: EvidenceIntegrityReviewIssue,

    pub fn deinit(
        self: *IntegrityCheckedPlanningRegistrationSnapshotResult,
        allocator: std.mem.Allocator,
    ) void {
        switch (self.*) {
            .resolved => |*value| value.deinit(allocator),
            .registration_review_required,
            .evidence_integrity_review_required,
            => {},
        }
        self.* = undefined;
    }
};

const SnapshotReadHook = struct {
    context: *anyopaque,
    after_taxpayer_identity_fn: *const fn (context: *anyopaque) void,

    fn afterTaxpayerIdentity(self: SnapshotReadHook) void {
        self.after_taxpayer_identity_fn(self.context);
    }
};

/// Production-facing registration module. It accepts a caller-owned `Store`
/// so all v28 writes share that store's connection, locking, migration, and
/// foreign-key configuration.
pub const TaxpayerRegistrationLedger = struct {
    allocator: std.mem.Allocator,
    profile_store: *store.Store,

    pub fn init(
        allocator: std.mem.Allocator,
        profile_store: *store.Store,
    ) TaxpayerRegistrationLedger {
        return .{
            .allocator = allocator,
            .profile_store = profile_store,
        };
    }

    /// Mints a storage-safe opaque identifier without exposing the ledger's
    /// backing profile store to workspace callers. The value is not reserved
    /// until a ledger write containing it commits successfully.
    pub fn generateOpaqueId(self: *TaxpayerRegistrationLedger) Error![32]u8 {
        return self.profile_store.generateOpaqueId();
    }

    /// Returns the local human-owner identity used for reviewed evidence.
    pub fn localOwnerId(self: *TaxpayerRegistrationLedger) Error![32]u8 {
        return self.profile_store.localOwnerId();
    }

    /// Appends one v28 ledger command and its derived immutable rows in one
    /// SQLite transaction. It never reads or writes legacy profile tables.
    pub fn apply(
        self: *TaxpayerRegistrationLedger,
        command: domain.RegistrationCommand,
    ) Error!domain.RegistrationWriteResult {
        return self.applyWithLegacyMigrationAuthority(command, null);
    }

    fn applyWithLegacyMigrationAuthority(
        self: *TaxpayerRegistrationLedger,
        command: domain.RegistrationCommand,
        authority: ?*const LegacyMigrationCutoverAuthority,
    ) Error!domain.RegistrationWriteResult {
        const db = try self.handle();
        try exec(db, "BEGIN IMMEDIATE;");
        var committed = false;
        errdefer if (!committed) rollbackNoFail(db);
        try self.profile_store
            .requireRegistrationFixturePreviewWriteAuthorizationInTransaction();
        const result = try self.applyCommandInTransaction(db, command, authority);
        try exec(db, "COMMIT;");
        committed = true;
        return result;
    }

    /// Records immutable evidence metadata. It deliberately has no update
    /// operation: a corrected artifact is a new evidence record, while later
    /// review decisions append to the original evidence's decision stream.
    pub fn recordEvidence(
        self: *TaxpayerRegistrationLedger,
        value: EvidenceWrite,
    ) Error!void {
        try validateEvidenceWrite(value);
        const db = try self.handle();

        try exec(db, "BEGIN IMMEDIATE;");
        var committed = false;
        errdefer if (!committed) rollbackNoFail(db);
        try self.profile_store
            .requireRegistrationFixturePreviewWriteAuthorizationInTransaction();
        try insertEvidence(db, value);
        try exec(db, "COMMIT;");
        committed = true;
    }

    /// Appends one review decision. The current decision is the greatest
    /// sequence for the evidence stream; only a current `accepted` decision
    /// authorizes a registration command.
    pub fn recordEvidenceReviewDecision(
        self: *TaxpayerRegistrationLedger,
        value: EvidenceReviewDecisionWrite,
    ) Error!void {
        try validateEvidenceReviewDecisionWrite(value);
        const db = try self.handle();
        try exec(db, "BEGIN IMMEDIATE;");
        var committed = false;
        errdefer if (!committed) rollbackNoFail(db);
        try self.profile_store
            .requireRegistrationFixturePreviewWriteAuthorizationInTransaction();
        if (value.state == .accepted) {
            try requireAuthoritativeEvidenceStorage(db, value.evidence_id);
        }
        try insertEvidenceReviewDecision(db, value);
        try exec(db, "COMMIT;");
        committed = true;
    }

    /// Records one immutable asserted fact tied to captured evidence. The fact
    /// becomes command authority only while that evidence's latest review is
    /// accepted; keeping the rows separate lets one document support several
    /// exact facts without becoming generic authority for another subject.
    pub fn recordEvidenceAssertion(
        self: *TaxpayerRegistrationLedger,
        value: EvidenceAssertionWrite,
    ) Error!void {
        try validateEvidenceAssertionWrite(value);
        const db = try self.handle();
        try exec(db, "BEGIN IMMEDIATE;");
        var committed = false;
        errdefer if (!committed) rollbackNoFail(db);
        try self.profile_store
            .requireRegistrationFixturePreviewWriteAuthorizationInTransaction();
        try requireEvidenceAssertionSetOpen(db, value.evidence_id);
        try insertEvidenceAssertion(db, value);
        try exec(db, "COMMIT;");
        committed = true;
    }

    /// Promotes one evidence artifact, its initial acceptance, exact asserted
    /// facts, and every dependent registration command in one transaction.
    /// Commands run in caller order and reload persisted context after each
    /// prior command. No command result or borrowed database value is returned;
    /// callers refresh through `snapshot` or `planningSnapshot` after success.
    pub fn recordReviewedEvidenceBundle(
        self: *TaxpayerRegistrationLedger,
        value: ReviewedEvidenceBundleWrite,
    ) Error!void {
        try validateReviewedEvidenceBundleWrite(value);
        const db = try self.handle();
        try exec(db, "BEGIN IMMEDIATE;");
        var committed = false;
        errdefer if (!committed) rollbackNoFail(db);
        try self.profile_store
            .requireRegistrationFixturePreviewWriteAuthorizationInTransaction();

        try insertEvidence(db, value.evidence);
        for (value.assertions) |assertion| {
            try insertEvidenceAssertion(db, assertion);
        }
        try insertEvidenceReviewDecision(db, value.initial_review);
        for (value.commands) |command| {
            _ = try self.applyCommandInTransaction(db, command, null);
        }

        try exec(db, "COMMIT;");
        committed = true;
    }

    /// Lists every taxpayer shell in stable bytewise ID order. The returned
    /// list owns allocator memory; call `OwnedTaxpayerIdList.deinit` exactly
    /// once with the allocator passed to `init`, including for an empty list.
    pub fn listTaxpayerIds(
        self: *TaxpayerRegistrationLedger,
    ) Error!OwnedTaxpayerIdList {
        const db = try self.handle();
        var statement = try prepare(db,
            \\SELECT id
            \\FROM taxpayer_registration_taxpayers
            \\ORDER BY id COLLATE BINARY ASC;
        );
        defer statement.deinit();

        var values: std.ArrayList(domain.TaxpayerId) = .empty;
        errdefer values.deinit(self.allocator);
        while (try statement.step() == .row) {
            try values.append(
                self.allocator,
                try taxpayerIdFromColumn(statement.raw, 0),
            );
        }
        return .{ .items = try values.toOwnedSlice(self.allocator) };
    }

    /// Returns an effective registration view only when the requester names
    /// one civil date. A differing period is intentionally Review Required.
    pub fn snapshot(
        self: *TaxpayerRegistrationLedger,
        request: SnapshotRequest,
    ) Error!RegistrationSnapshotResult {
        return self.snapshotWithReadHook(request, null);
    }

    fn snapshotWithReadHook(
        self: *TaxpayerRegistrationLedger,
        request: SnapshotRequest,
        hook: ?SnapshotReadHook,
    ) Error!RegistrationSnapshotResult {
        if (!request.start.eql(request.end)) {
            return .{ .review_required = .period_spans_multiple_dates };
        }
        const db = try self.handle();
        // A filing snapshot is one database fact, even though materializing it
        // requires several SELECTs. Keep the deferred read transaction open
        // until every revision, review, assertion, and lineage row is owned.
        try exec(db, "BEGIN DEFERRED;");
        defer rollbackNoFail(db);
        const taxpayer_identity = (try loadTaxpayerIdentityAt(
            db,
            request.taxpayer_id,
            request.start,
        )) orelse return .{ .review_required = .taxpayer_identity_missing };
        if (hook) |value| value.afterTaxpayerIdentity();
        const units = try loadEffectiveUnits(
            self.allocator,
            db,
            request.taxpayer_id,
            request.start,
        );
        errdefer self.allocator.free(units);
        const contacts = try loadEffectiveRegistrationUnitContacts(
            self.allocator,
            db,
            request.taxpayer_id,
            request.start,
        );
        errdefer self.allocator.free(contacts);
        const tax_type_registrations = try loadEffectiveTaxTypeRegistrations(
            self.allocator,
            db,
            request.taxpayer_id,
            request.start,
        );
        errdefer self.allocator.free(tax_type_registrations);
        const lineage = try loadConfirmedCodeLineage(
            self.allocator,
            db,
            request.taxpayer_id,
        );
        errdefer self.allocator.free(lineage);
        if (try registrationEvidenceReviewProblem(
            db,
            taxpayer_identity,
            units,
            contacts,
            tax_type_registrations,
            null,
            false,
        )) |issue| {
            self.allocator.free(lineage);
            self.allocator.free(tax_type_registrations);
            self.allocator.free(contacts);
            self.allocator.free(units);
            return .{ .review_required = .{ .evidence = issue } };
        }
        const lineage_complete = (try lineageEvidenceReviewProblem(db, lineage)) == null;
        const reviewed_evidence_bindings = try self.loadReviewedEvidenceBindings(
            db,
            taxpayer_identity,
            units,
            contacts,
            tax_type_registrations,
        );
        errdefer self.allocator.free(reviewed_evidence_bindings);
        return .{ .resolved = .{
            .taxpayer_identity = taxpayer_identity,
            .units = units,
            .contacts = contacts,
            .tax_type_registrations = tax_type_registrations,
            .lineage = lineage,
            .lineage_complete = lineage_complete,
            .reviewed_evidence_bindings = reviewed_evidence_bindings,
            .as_of = request.start,
        } };
    }

    /// Resolves the registration snapshot, then verifies every distinct
    /// evidence object referenced by the result before exposing it to the app.
    pub fn snapshotWithEvidenceIntegrity(
        self: *TaxpayerRegistrationLedger,
        request: SnapshotRequest,
        verifier: EvidenceIntegrityVerifier,
    ) Error!IntegrityCheckedRegistrationSnapshotResult {
        const base = try self.snapshot(request);
        return switch (base) {
            .review_required => |issue| .{
                .registration_review_required = issue,
            },
            .resolved => |resolved| blk: {
                var checked = resolved;
                var seen: std.ArrayList(domain.RegistrationEvidenceId) = .empty;
                defer seen.deinit(self.allocator);
                if (try self.verifyRegistrationSnapshotEvidence(
                    checked,
                    verifier,
                    &seen,
                )) |issue| {
                    var discarded = checked;
                    discarded.deinit(self.allocator);
                    break :blk .{ .evidence_integrity_review_required = issue };
                }
                if (checked.lineage_complete and
                    try self.verifyLineageEvidence(
                        checked.lineage,
                        verifier,
                        &seen,
                    ) != null)
                {
                    checked.lineage_complete = false;
                }
                break :blk .{ .resolved = checked };
            },
        };
    }

    /// Obtains the only production-facing registration input for a filing
    /// period. It does not pick the start or end state when taxpayer identity
    /// changed; unit/tax-registration history remains complete so planner
    /// logic can report an ordered, evidence-specific review reason.
    pub fn planningSnapshot(
        self: *TaxpayerRegistrationLedger,
        request: SnapshotRequest,
    ) Error!PlanningRegistrationSnapshotResult {
        return self.planningSnapshotWithReadHook(request, null);
    }

    fn planningSnapshotWithReadHook(
        self: *TaxpayerRegistrationLedger,
        request: SnapshotRequest,
        hook: ?SnapshotReadHook,
    ) Error!PlanningRegistrationSnapshotResult {
        const db = try self.handle();
        // Pin all period endpoints and dependent evidence bindings to the same
        // WAL snapshot; otherwise a concurrent commit could produce a plan
        // assembled from revisions that never coexisted.
        try exec(db, "BEGIN DEFERRED;");
        defer rollbackNoFail(db);
        const taxpayer_identity = (try loadTaxpayerIdentityAt(
            db,
            request.taxpayer_id,
            request.start,
        )) orelse return .{ .review_required = .taxpayer_identity_missing };
        if (hook) |value| value.afterTaxpayerIdentity();
        const taxpayer_identity_at_end = (try loadTaxpayerIdentityAt(
            db,
            request.taxpayer_id,
            request.end,
        )) orelse return .{ .review_required = .taxpayer_identity_missing };
        if (!taxpayer_identity.id.eql(&taxpayer_identity_at_end.id) or
            taxpayer_identity.sequence != taxpayer_identity_at_end.sequence)
        {
            return .{ .review_required = .taxpayer_identity_changed_during_period };
        }

        const units = try loadUnitRevisionsOverlappingPeriod(
            self.allocator,
            db,
            request.taxpayer_id,
            request.start,
            request.end,
        );
        errdefer self.allocator.free(units);
        const contacts = try loadRegistrationUnitContactRevisionsOverlappingPeriod(
            self.allocator,
            db,
            request.taxpayer_id,
            request.start,
            request.end,
        );
        errdefer self.allocator.free(contacts);
        const tax_type_registrations = try loadTaxTypeRegistrationRevisionsOverlappingPeriod(
            self.allocator,
            db,
            request.taxpayer_id,
            request.start,
            request.end,
        );
        errdefer self.allocator.free(tax_type_registrations);
        if (try registrationEvidenceReviewProblem(
            db,
            taxpayer_identity,
            units,
            contacts,
            tax_type_registrations,
            null,
            true,
        )) |issue| {
            self.allocator.free(tax_type_registrations);
            self.allocator.free(contacts);
            self.allocator.free(units);
            return .{ .review_required = .{ .evidence = issue } };
        }
        const reviewed_evidence_bindings = try self.loadReviewedEvidenceBindings(
            db,
            taxpayer_identity,
            units,
            contacts,
            tax_type_registrations,
        );
        errdefer self.allocator.free(reviewed_evidence_bindings);
        return .{ .resolved = .{
            .taxpayer_identity = taxpayer_identity,
            .units = units,
            .contacts = contacts,
            .tax_type_registrations = tax_type_registrations,
            .reviewed_evidence_bindings = reviewed_evidence_bindings,
            .period_start = request.start,
            .period_end = request.end,
        } };
    }

    /// Planning counterpart of `snapshotWithEvidenceIntegrity`; callers must
    /// use this seam before planner output is exposed as an app decision.
    pub fn planningSnapshotWithEvidenceIntegrity(
        self: *TaxpayerRegistrationLedger,
        request: SnapshotRequest,
        verifier: EvidenceIntegrityVerifier,
    ) Error!IntegrityCheckedPlanningRegistrationSnapshotResult {
        const base = try self.planningSnapshot(request);
        return switch (base) {
            .review_required => |issue| .{
                .registration_review_required = issue,
            },
            .resolved => |resolved| blk: {
                if (try self.verifyPlanningSnapshotEvidence(
                    resolved,
                    verifier,
                )) |issue| {
                    var discarded = resolved;
                    discarded.deinit(self.allocator);
                    break :blk .{ .evidence_integrity_review_required = issue };
                }
                break :blk .{ .resolved = resolved };
            },
        };
    }

    fn verifyRegistrationSnapshotEvidence(
        self: *TaxpayerRegistrationLedger,
        snapshot_value: ResolvedRegistrationSnapshot,
        verifier: EvidenceIntegrityVerifier,
        seen: *std.ArrayList(domain.RegistrationEvidenceId),
    ) Error!?EvidenceIntegrityReviewIssue {
        const db = try self.handle();

        if (snapshot_value.taxpayer_identity.evidence_id) |evidence_id| {
            if (try self.verifyEvidenceReference(db, seen, evidence_id, verifier)) |issue| {
                return integrityIssue(evidence_id, issue);
            }
        }
        for (snapshot_value.units) |unit| {
            if (unit.branch_code_evidence.confirmedCode()) |confirmation| {
                if (try self.verifyEvidenceReference(
                    db,
                    seen,
                    confirmation.evidence_id,
                    verifier,
                )) |issue| return integrityIssue(confirmation.evidence_id, issue);
            }
            if (unit.lifecycle_evidence_id) |evidence_id| {
                if (try self.verifyEvidenceReference(
                    db,
                    seen,
                    evidence_id,
                    verifier,
                )) |issue| return integrityIssue(evidence_id, issue);
            }
        }
        for (snapshot_value.contacts) |contact| {
            if (try self.verifyEvidenceReference(
                db,
                seen,
                contact.evidence_id,
                verifier,
            )) |issue| return integrityIssue(contact.evidence_id, issue);
        }
        for (snapshot_value.tax_type_registrations) |registration| {
            if (registration.evidence_id) |evidence_id| {
                if (try self.verifyEvidenceReference(
                    db,
                    seen,
                    evidence_id,
                    verifier,
                )) |issue| return integrityIssue(evidence_id, issue);
            }
        }
        return null;
    }

    fn verifyLineageEvidence(
        self: *TaxpayerRegistrationLedger,
        lineage: []const domain.BranchCodeLineageEntry,
        verifier: EvidenceIntegrityVerifier,
        seen: *std.ArrayList(domain.RegistrationEvidenceId),
    ) Error!?EvidenceIntegrityReviewIssue {
        const db = try self.handle();
        for (lineage) |entry| {
            if (try self.verifyEvidenceReference(
                db,
                seen,
                entry.evidence_id,
                verifier,
            )) |issue| return integrityIssue(entry.evidence_id, issue);
        }
        return null;
    }

    fn verifyPlanningSnapshotEvidence(
        self: *TaxpayerRegistrationLedger,
        snapshot_value: ResolvedPlanningRegistrationSnapshot,
        verifier: EvidenceIntegrityVerifier,
    ) Error!?EvidenceIntegrityReviewIssue {
        const db = try self.handle();
        var seen: std.ArrayList(domain.RegistrationEvidenceId) = .empty;
        defer seen.deinit(self.allocator);

        if (snapshot_value.taxpayer_identity.evidence_id) |evidence_id| {
            if (try self.verifyEvidenceReference(db, &seen, evidence_id, verifier)) |issue| {
                return integrityIssue(evidence_id, issue);
            }
        }
        for (snapshot_value.units) |unit| {
            if (unit.branch_code_evidence.confirmedCode()) |confirmation| {
                if (try self.verifyEvidenceReference(
                    db,
                    &seen,
                    confirmation.evidence_id,
                    verifier,
                )) |issue| return integrityIssue(confirmation.evidence_id, issue);
            }
            if (unit.lifecycle_evidence_id) |evidence_id| {
                if (try self.verifyEvidenceReference(
                    db,
                    &seen,
                    evidence_id,
                    verifier,
                )) |issue| return integrityIssue(evidence_id, issue);
            }
        }
        for (snapshot_value.contacts) |contact| {
            if (try self.verifyEvidenceReference(
                db,
                &seen,
                contact.evidence_id,
                verifier,
            )) |issue| return integrityIssue(contact.evidence_id, issue);
        }
        for (snapshot_value.tax_type_registrations) |registration| {
            if (registration.evidence_id) |evidence_id| {
                if (try self.verifyEvidenceReference(
                    db,
                    &seen,
                    evidence_id,
                    verifier,
                )) |issue| return integrityIssue(evidence_id, issue);
            }
        }
        return null;
    }

    fn integrityIssue(
        evidence_id: domain.RegistrationEvidenceId,
        cause: EvidenceIntegrityReviewRequired,
    ) EvidenceIntegrityReviewIssue {
        return .{ .cause = cause, .evidence_id = evidence_id };
    }

    fn verifyEvidenceReference(
        self: *TaxpayerRegistrationLedger,
        db: *sqlite.sqlite3,
        seen: *std.ArrayList(domain.RegistrationEvidenceId),
        evidence_id: domain.RegistrationEvidenceId,
        verifier: EvidenceIntegrityVerifier,
    ) Error!?EvidenceIntegrityReviewRequired {
        for (seen.items) |existing| {
            if (existing.eql(&evidence_id)) return null;
        }
        try seen.append(self.allocator, evidence_id);

        var statement = try prepare(db,
            \\SELECT storage_reference_kind, storage_reference, sha256, byte_size
            \\FROM taxpayer_registration_evidence
            \\WHERE id = ?
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, evidence_id.asSlice());
        if (try statement.step() != .row) return .stored_metadata_invalid;

        const storage_kind = optionalText(statement.raw, 0) orelse
            return .stored_metadata_invalid;
        const reference = optionalText(statement.raw, 1) orelse
            return .stored_metadata_invalid;
        const sha256 = optionalText(statement.raw, 2) orelse
            return .stored_metadata_invalid;
        _ = domain.Sha256Digest.parse(sha256) catch
            return .stored_metadata_invalid;
        if (!validStorageReference(reference) or
            sqlite.sqlite3_column_type(statement.raw, 3) != sqlite.SQLITE_INTEGER)
        {
            return .stored_metadata_invalid;
        }
        const raw_byte_size = sqlite.sqlite3_column_int64(statement.raw, 3);
        if (raw_byte_size < 0) return .stored_metadata_invalid;

        if (std.mem.eql(u8, storage_kind, "protected_local_path")) {
            return verifier.verify(.{
                .evidence_id = evidence_id,
                .protected_path = reference,
                .sha256 = sha256,
                .byte_size = @intCast(raw_byte_size),
            });
        }
        if (std.mem.eql(u8, storage_kind, "encrypted_blob_reference")) {
            return .storage_backend_unverifiable;
        }
        return .stored_metadata_invalid;
    }

    fn registrationEvidenceReviewProblem(
        db: *sqlite.sqlite3,
        taxpayer_identity: domain.TaxpayerIdentityRevision,
        units: []const domain.RegistrationUnitRevision,
        contacts: []const domain.RegistrationUnitContactRevision,
        tax_type_registrations: []const domain.TaxTypeRegistrationRevision,
        lineage: ?[]const domain.BranchCodeLineageEntry,
        require_taxpayer_evidence: bool,
    ) Error!?EvidenceReviewIssue {
        if (taxpayer_identity.evidence_id) |taxpayer_evidence_id| {
            const subject: EvidenceReviewSubject = .{
                .taxpayer_identity_revision = taxpayer_identity.id,
            };
            if (try evidenceReviewIssue(
                db,
                taxpayer_evidence_id,
                subject,
            )) |issue| {
                return issue;
            }
            _ = loadTaxpayerIdentityEvidenceBinding(
                db,
                taxpayer_evidence_id,
                taxpayer_identity,
            ) catch |err| switch (err) {
                error.EvidenceAssertionNotAccepted => return missingEvidenceReviewIssue(
                    taxpayer_evidence_id,
                    subject,
                ),
                else => return err,
            };
        } else if (require_taxpayer_evidence) {
            return .{
                .reason = .missing,
                .evidence_id = null,
                .subject = .{
                    .taxpayer_identity_revision = taxpayer_identity.id,
                },
            };
        }
        for (units) |unit| {
            if (unit.branch_code_evidence.confirmedCode()) |confirmation| {
                const subject: EvidenceReviewSubject = .{
                    .registration_unit_branch_code_revision = unit.id,
                };
                if (try evidenceReviewIssue(
                    db,
                    confirmation.evidence_id,
                    subject,
                )) |issue| {
                    return issue;
                }
                _ = loadRegistrationUnitBranchEvidenceBinding(
                    db,
                    confirmation.evidence_id,
                    unit,
                ) catch |err| switch (err) {
                    error.EvidenceAssertionNotAccepted => return missingEvidenceReviewIssue(
                        confirmation.evidence_id,
                        subject,
                    ),
                    else => return err,
                };
            }
            if (unit.lifecycle_evidence_id) |evidence_id| {
                const subject: EvidenceReviewSubject = .{
                    .registration_unit_lifecycle_revision = unit.id,
                };
                if (try evidenceReviewIssue(db, evidence_id, subject)) |issue| {
                    return issue;
                }
                _ = loadRegistrationUnitLifecycleEvidenceBinding(
                    db,
                    evidence_id,
                    unit,
                ) catch |err| switch (err) {
                    error.EvidenceAssertionNotAccepted => return missingEvidenceReviewIssue(
                        evidence_id,
                        subject,
                    ),
                    else => return err,
                };
            }
        }
        for (contacts) |contact| {
            const subject: EvidenceReviewSubject = .{
                .registration_unit_contact_revision = contact.id,
            };
            if (try evidenceReviewIssue(db, contact.evidence_id, subject)) |issue| {
                return issue;
            }
            _ = loadRegistrationUnitContactEvidenceBinding(
                db,
                contact.evidence_id,
                contact,
            ) catch |err| switch (err) {
                error.EvidenceAssertionNotAccepted => return missingEvidenceReviewIssue(
                    contact.evidence_id,
                    subject,
                ),
                else => return err,
            };
        }
        for (tax_type_registrations) |registration| {
            if (registration.evidence_id) |evidence_id| {
                const subject: EvidenceReviewSubject = .{
                    .tax_type_registration_revision = registration.id,
                };
                if (try evidenceReviewIssue(db, evidence_id, subject)) |issue| {
                    return issue;
                }
                _ = loadTaxTypeRegistrationEvidenceBinding(
                    db,
                    evidence_id,
                    registration,
                ) catch |err| switch (err) {
                    error.EvidenceAssertionNotAccepted => return missingEvidenceReviewIssue(
                        evidence_id,
                        subject,
                    ),
                    else => return err,
                };
            }
        }
        if (lineage) |entries| {
            return try lineageEvidenceReviewProblem(db, entries);
        }
        return null;
    }

    fn evidenceReviewIssue(
        db: *sqlite.sqlite3,
        evidence_id: domain.RegistrationEvidenceId,
        subject: EvidenceReviewSubject,
    ) Error!?EvidenceReviewIssue {
        const reason = (try currentEvidenceReviewProblem(db, evidence_id)) orelse
            return null;
        return .{
            .reason = reason,
            .evidence_id = evidence_id,
            .subject = subject,
        };
    }

    fn missingEvidenceReviewIssue(
        evidence_id: domain.RegistrationEvidenceId,
        subject: EvidenceReviewSubject,
    ) EvidenceReviewIssue {
        return .{
            .reason = .missing,
            .evidence_id = evidence_id,
            .subject = subject,
        };
    }

    fn lineageEvidenceReviewProblem(
        db: *sqlite.sqlite3,
        lineage: []const domain.BranchCodeLineageEntry,
    ) Error!?EvidenceReviewIssue {
        for (lineage) |entry| {
            const subject: EvidenceReviewSubject = .{ .branch_code_lineage = .{
                .registration_unit_id = entry.registration_unit_id,
                .code = entry.code,
            } };
            if (try evidenceReviewIssue(db, entry.evidence_id, subject)) |issue| {
                return issue;
            }
            requireAcceptedLineageAssertion(db, entry) catch |err| switch (err) {
                error.EvidenceAssertionNotAccepted => return missingEvidenceReviewIssue(
                    entry.evidence_id,
                    subject,
                ),
                else => return err,
            };
        }
        return null;
    }

    fn requireAcceptedLineageAssertion(
        db: *sqlite.sqlite3,
        entry: domain.BranchCodeLineageEntry,
    ) Error!void {
        var statement = try prepare(db,
            \\SELECT 1
            \\FROM taxpayer_registration_evidence_assertions AS assertion
            \\JOIN taxpayer_registration_current_evidence_reviews AS review
            \\  ON review.evidence_id = assertion.evidence_id
            \\WHERE assertion.evidence_id = ?
            \\  AND assertion.taxpayer_id = ?
            \\  AND assertion.registration_unit_id = ?
            \\  AND assertion.fact_kind = 'registration_unit'
            \\  AND assertion.branch_code = ?
            \\  AND review.review_state = 'accepted'
            \\ORDER BY assertion.id COLLATE BINARY
            \\LIMIT 2;
        );
        defer statement.deinit();
        try statement.bindText(1, entry.evidence_id.asSlice());
        try statement.bindText(2, entry.taxpayer_id.asSlice());
        try statement.bindText(3, entry.registration_unit_id.asSlice());
        try statement.bindText(4, entry.code.asDigits());
        try requireUniqueAcceptedAssertion(&statement);
    }

    fn loadReviewedEvidenceBindings(
        self: *TaxpayerRegistrationLedger,
        db: *sqlite.sqlite3,
        taxpayer_identity: domain.TaxpayerIdentityRevision,
        units: []const domain.RegistrationUnitRevision,
        contacts: []const domain.RegistrationUnitContactRevision,
        tax_type_registrations: []const domain.TaxTypeRegistrationRevision,
    ) Error![]ReviewedEvidenceBinding {
        var values: std.ArrayList(ReviewedEvidenceBinding) = .empty;
        errdefer values.deinit(self.allocator);

        if (taxpayer_identity.evidence_id) |evidence_id| {
            try values.append(
                self.allocator,
                try loadTaxpayerIdentityEvidenceBinding(
                    db,
                    evidence_id,
                    taxpayer_identity,
                ),
            );
        }
        for (units) |unit| {
            if (unit.branch_code_evidence.confirmedCode()) |confirmation| {
                try values.append(
                    self.allocator,
                    try loadRegistrationUnitBranchEvidenceBinding(
                        db,
                        confirmation.evidence_id,
                        unit,
                    ),
                );
            }
            if (unit.lifecycle_evidence_id) |evidence_id| {
                try values.append(
                    self.allocator,
                    try loadRegistrationUnitLifecycleEvidenceBinding(
                        db,
                        evidence_id,
                        unit,
                    ),
                );
            }
        }
        for (contacts) |contact| {
            try values.append(
                self.allocator,
                try loadRegistrationUnitContactEvidenceBinding(
                    db,
                    contact.evidence_id,
                    contact,
                ),
            );
        }
        for (tax_type_registrations) |registration_value| {
            if (registration_value.evidence_id) |evidence_id| {
                try values.append(
                    self.allocator,
                    try loadTaxTypeRegistrationEvidenceBinding(
                        db,
                        evidence_id,
                        registration_value,
                    ),
                );
            }
        }

        evidence_binding.sort(values.items);
        return values.toOwnedSlice(self.allocator);
    }

    fn loadTaxpayerIdentityEvidenceBinding(
        db: *sqlite.sqlite3,
        evidence_id: domain.RegistrationEvidenceId,
        revision: domain.TaxpayerIdentityRevision,
    ) Error!ReviewedEvidenceBinding {
        var statement = try prepare(db,
            \\SELECT assertion.id, review.decision_id, review.sequence
            \\FROM taxpayer_registration_evidence_assertions AS assertion
            \\JOIN taxpayer_registration_current_evidence_reviews AS review
            \\  ON review.evidence_id = assertion.evidence_id
            \\WHERE assertion.evidence_id = ?
            \\  AND assertion.taxpayer_id = ?
            \\  AND assertion.registration_unit_id IS NULL
            \\  AND assertion.effective_from = ?
            \\  AND assertion.fact_kind = 'taxpayer_tin_root'
            \\  AND assertion.tin9 = ?
            \\  AND review.review_state = 'accepted'
            \\ORDER BY assertion.id COLLATE BINARY
            \\LIMIT 2;
        );
        defer statement.deinit();
        var effective_from: [10]u8 = undefined;
        try statement.bindText(1, evidence_id.asSlice());
        try statement.bindText(2, revision.taxpayer_id.asSlice());
        try statement.bindText(3, revision.effective.from.writeIso(&effective_from));
        try statement.bindText(4, revision.tin_root.asDigits());
        return readUniqueEvidenceBinding(
            &statement,
            .{ .taxpayer_identity_revision = revision.id },
            evidence_id,
        );
    }

    fn loadRegistrationUnitBranchEvidenceBinding(
        db: *sqlite.sqlite3,
        evidence_id: domain.RegistrationEvidenceId,
        revision: domain.RegistrationUnitRevision,
    ) Error!ReviewedEvidenceBinding {
        const confirmed = revision.branch_code_evidence.confirmedCode() orelse
            return error.InvalidStoredValue;
        var statement = try prepare(db,
            \\SELECT assertion.id, review.decision_id, review.sequence
            \\FROM taxpayer_registration_evidence_assertions AS assertion
            \\JOIN taxpayer_registration_current_evidence_reviews AS review
            \\  ON review.evidence_id = assertion.evidence_id
            \\WHERE assertion.evidence_id = ?
            \\  AND assertion.taxpayer_id = ?
            \\  AND assertion.registration_unit_id = ?
            \\  AND assertion.fact_kind = 'registration_unit'
            \\  AND assertion.branch_code = ?
            \\  AND review.review_state = 'accepted'
            \\ORDER BY assertion.id COLLATE BINARY
            \\LIMIT 2;
        );
        defer statement.deinit();
        try statement.bindText(1, evidence_id.asSlice());
        try statement.bindText(2, revision.taxpayer_id.asSlice());
        try statement.bindText(3, revision.registration_unit_id.asSlice());
        try statement.bindText(4, confirmed.code.asDigits());
        return readUniqueEvidenceBinding(
            &statement,
            .{ .registration_unit_branch_code_revision = revision.id },
            evidence_id,
        );
    }

    fn loadRegistrationUnitLifecycleEvidenceBinding(
        db: *sqlite.sqlite3,
        evidence_id: domain.RegistrationEvidenceId,
        revision: domain.RegistrationUnitRevision,
    ) Error!ReviewedEvidenceBinding {
        const confirmed = revision.branch_code_evidence.confirmedCode() orelse
            return error.InvalidStoredValue;
        var statement = try prepare(db,
            \\SELECT assertion.id, review.decision_id, review.sequence
            \\FROM taxpayer_registration_evidence_assertions AS assertion
            \\JOIN taxpayer_registration_current_evidence_reviews AS review
            \\  ON review.evidence_id = assertion.evidence_id
            \\WHERE assertion.evidence_id = ?
            \\  AND assertion.taxpayer_id = ?
            \\  AND assertion.registration_unit_id = ?
            \\  AND assertion.effective_from = ?
            \\  AND assertion.fact_kind = 'registration_unit'
            \\  AND assertion.branch_code = ?
            \\  AND assertion.registration_unit_status = ?
            \\  AND assertion.rdo_code IS ?
            \\  AND review.review_state = 'accepted'
            \\ORDER BY assertion.id COLLATE BINARY
            \\LIMIT 2;
        );
        defer statement.deinit();
        var effective_from: [10]u8 = undefined;
        try statement.bindText(1, evidence_id.asSlice());
        try statement.bindText(2, revision.taxpayer_id.asSlice());
        try statement.bindText(3, revision.registration_unit_id.asSlice());
        try statement.bindText(4, revision.effective.from.writeIso(&effective_from));
        try statement.bindText(5, confirmed.code.asDigits());
        try statement.bindText(6, @tagName(revision.status));
        try statement.bindOptionalText(7, if (revision.rdo_code) |code|
            code.asDigits()
        else
            null);
        return readUniqueEvidenceBinding(
            &statement,
            .{ .registration_unit_lifecycle_revision = revision.id },
            evidence_id,
        );
    }

    fn loadRegistrationUnitContactEvidenceBinding(
        db: *sqlite.sqlite3,
        evidence_id: domain.RegistrationEvidenceId,
        revision: domain.RegistrationUnitContactRevision,
    ) Error!ReviewedEvidenceBinding {
        var statement = try prepare(db,
            \\SELECT assertion.id, review.decision_id, review.sequence
            \\FROM taxpayer_registration_evidence_assertions AS assertion
            \\JOIN taxpayer_registration_current_evidence_reviews AS review
            \\  ON review.evidence_id = assertion.evidence_id
            \\WHERE assertion.evidence_id = ?
            \\  AND assertion.taxpayer_id = ?
            \\  AND assertion.registration_unit_id = ?
            \\  AND assertion.effective_from = ?
            \\  AND assertion.fact_kind = 'registration_unit_contact'
            \\  AND assertion.registered_address = ?
            \\  AND assertion.zip_code IS ?
            \\  AND assertion.contact_number IS ?
            \\  AND assertion.email_address IS ?
            \\  AND review.review_state = 'accepted'
            \\ORDER BY assertion.id COLLATE BINARY
            \\LIMIT 2;
        );
        defer statement.deinit();
        var effective_from: [10]u8 = undefined;
        try statement.bindText(1, evidence_id.asSlice());
        try statement.bindText(2, revision.taxpayer_id.asSlice());
        try statement.bindText(3, revision.registration_unit_id.asSlice());
        try statement.bindText(4, revision.effective.from.writeIso(&effective_from));
        try statement.bindText(5, revision.contact.registered_address.asSlice());
        try statement.bindOptionalText(6, if (revision.contact.zip_code) |value| value.asSlice() else null);
        try statement.bindOptionalText(7, if (revision.contact.contact_number) |value| value.asSlice() else null);
        try statement.bindOptionalText(8, if (revision.contact.email_address) |value| value.asSlice() else null);
        return readUniqueEvidenceBinding(
            &statement,
            .{ .registration_unit_contact_revision = revision.id },
            evidence_id,
        );
    }

    fn loadTaxTypeRegistrationEvidenceBinding(
        db: *sqlite.sqlite3,
        evidence_id: domain.RegistrationEvidenceId,
        revision: domain.TaxTypeRegistrationRevision,
    ) Error!ReviewedEvidenceBinding {
        var statement = try prepare(db,
            \\SELECT assertion.id, review.decision_id, review.sequence
            \\FROM taxpayer_registration_evidence_assertions AS assertion
            \\JOIN taxpayer_registration_current_evidence_reviews AS review
            \\  ON review.evidence_id = assertion.evidence_id
            \\WHERE assertion.evidence_id = ?
            \\  AND assertion.taxpayer_id = ?
            \\  AND assertion.registration_unit_id = ?
            \\  AND assertion.effective_from = ?
            \\  AND assertion.fact_kind = 'tax_type_registration'
            \\  AND assertion.tax_type = ?
            \\  AND assertion.tax_type_status = ?
            \\  AND review.review_state = 'accepted'
            \\ORDER BY assertion.id COLLATE BINARY
            \\LIMIT 2;
        );
        defer statement.deinit();
        var effective_from: [10]u8 = undefined;
        try statement.bindText(1, evidence_id.asSlice());
        try statement.bindText(2, revision.taxpayer_id.asSlice());
        try statement.bindText(3, revision.registration_unit_id.asSlice());
        try statement.bindText(4, revision.effective.from.writeIso(&effective_from));
        try statement.bindText(5, @tagName(revision.tax_type));
        try statement.bindText(6, @tagName(revision.status));
        return readUniqueEvidenceBinding(
            &statement,
            .{ .tax_type_registration_revision = revision.id },
            evidence_id,
        );
    }

    fn readUniqueEvidenceBinding(
        statement: *Statement,
        subject: evidence_binding.FactSubject,
        evidence_id: domain.RegistrationEvidenceId,
    ) Error!ReviewedEvidenceBinding {
        if (try statement.step() != .row) return error.EvidenceAssertionNotAccepted;
        const assertion_id = domain.RegistrationEvidenceAssertionId.parse(
            requiredText(statement.raw, 0),
        ) catch return error.InvalidStoredValue;
        const review_decision_id = domain.RegistrationEvidenceReviewDecisionId.parse(
            requiredText(statement.raw, 1),
        ) catch return error.InvalidStoredValue;
        const review_decision_sequence = try nonnegativeU32(statement.raw, 2);
        if (review_decision_sequence == 0) return error.InvalidStoredValue;
        if (try statement.step() == .row) return error.EvidenceAssertionNotAccepted;
        return .{
            .subject = subject,
            .evidence_id = evidence_id,
            .review_decision_id = review_decision_id,
            .review_decision_sequence = review_decision_sequence,
            .assertion_id = assertion_id,
        };
    }

    fn currentEvidenceReviewProblem(
        db: *sqlite.sqlite3,
        evidence_id: domain.RegistrationEvidenceId,
    ) Error!?EvidenceReviewReason {
        var statement = try prepare(db,
            \\SELECT review.review_state, evidence.storage_reference_kind
            \\FROM taxpayer_registration_current_evidence_reviews AS review
            \\JOIN taxpayer_registration_evidence AS evidence
            \\  ON evidence.id = review.evidence_id
            \\WHERE review.evidence_id = ?
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, evidence_id.asSlice());
        if (try statement.step() != .row) return .missing;
        const state = requiredText(statement.raw, 0);
        if (state.len == 0) return error.InvalidStoredValue;
        const storage_kind = requiredText(statement.raw, 1);
        if (std.mem.eql(u8, storage_kind, "metadata_only_non_authoritative")) {
            return .missing;
        }
        if (std.mem.eql(u8, state, "accepted")) return null;
        if (std.mem.eql(u8, state, "rejected")) return .rejected;
        if (std.mem.eql(u8, state, "superseded")) return .superseded;
        return error.InvalidStoredValue;
    }

    fn handle(self: *TaxpayerRegistrationLedger) Error!*sqlite.sqlite3 {
        const raw = self.profile_store.db orelse return error.Closed;
        return @ptrCast(raw);
    }

    fn requireAuthoritativeEvidenceStorage(
        db: *sqlite.sqlite3,
        evidence_id: domain.RegistrationEvidenceId,
    ) Error!void {
        var statement = try prepare(db,
            \\SELECT storage_reference_kind
            \\FROM taxpayer_registration_evidence
            \\WHERE id = ?
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, evidence_id.asSlice());
        if (try statement.step() != .row) {
            return error.InvalidEvidenceReviewDecisionWrite;
        }
        const storage_kind = requiredText(statement.raw, 0);
        if (std.mem.eql(u8, storage_kind, "metadata_only_non_authoritative")) {
            return error.NonAuthoritativeEvidenceStorage;
        }
        if (!std.mem.eql(u8, storage_kind, "protected_local_path") and
            !std.mem.eql(u8, storage_kind, "encrypted_blob_reference"))
        {
            return error.InvalidStoredValue;
        }
    }

    fn requireEvidenceAssertionSetOpen(
        db: *sqlite.sqlite3,
        evidence_id: domain.RegistrationEvidenceId,
    ) Error!void {
        var statement = try prepare(db,
            \\SELECT 1
            \\FROM taxpayer_registration_evidence_review_decisions
            \\WHERE evidence_id = ?
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, evidence_id.asSlice());
        if (try statement.step() == .row) {
            return error.EvidenceAssertionSetFrozen;
        }
    }

    fn requireAcceptedEvidence(
        self: *TaxpayerRegistrationLedger,
        db: *sqlite.sqlite3,
        evidence_id: domain.RegistrationEvidenceId,
    ) Error!void {
        _ = self;
        var statement = try prepare(db,
            \\SELECT 1
            \\FROM taxpayer_registration_current_evidence_reviews AS review
            \\JOIN taxpayer_registration_evidence AS evidence
            \\  ON evidence.id = review.evidence_id
            \\WHERE review.evidence_id = ?
            \\  AND review.review_state = 'accepted'
            \\  AND evidence.storage_reference_kind IN (
            \\    'protected_local_path', 'encrypted_blob_reference'
            \\  )
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, evidence_id.asSlice());
        if (try statement.step() != .row) return error.EvidenceNotAccepted;
    }

    fn requireEvidenceAssertionsForResult(
        self: *TaxpayerRegistrationLedger,
        db: *sqlite.sqlite3,
        command: domain.RegistrationCommand,
        result: domain.RegistrationWriteResult,
    ) Error!void {
        _ = self;
        switch (command) {
            .confirm_taxpayer_tin_root => |value| {
                const revision = switch (result) {
                    .taxpayer_revised => |item| item,
                    else => return error.InvalidStoredValue,
                };
                try requireAcceptedTaxpayerTinRootAssertion(
                    db,
                    value.evidence_id,
                    revision,
                );
            },
            .correct_taxpayer_tin_root => |value| {
                const revision = switch (result) {
                    .taxpayer_revised => |item| item,
                    else => return error.InvalidStoredValue,
                };
                try requireAcceptedTaxpayerTinRootAssertion(
                    db,
                    value.evidence_id,
                    revision,
                );
            },
            .confirm_registration_unit => |value| {
                const revision = switch (result) {
                    .unit_revised => |item| item,
                    else => return error.InvalidStoredValue,
                };
                try requireAcceptedRegistrationUnitAssertion(
                    db,
                    value.evidence_id,
                    revision,
                );
            },
            .close_registration_unit => |value| {
                const revision = switch (result) {
                    .unit_revised => |item| item,
                    else => return error.InvalidStoredValue,
                };
                try requireAcceptedRegistrationUnitAssertion(db, value.evidence_id, revision);
            },
            .transfer_registration_unit => |value| {
                const revision = switch (result) {
                    .unit_revised => |item| item,
                    else => return error.InvalidStoredValue,
                };
                try requireAcceptedRegistrationUnitAssertion(db, value.evidence_id, revision);
            },
            .correct_branch_code => |value| {
                const revision = switch (result) {
                    .unit_revised => |item| item,
                    else => return error.InvalidStoredValue,
                };
                try requireAcceptedRegistrationUnitAssertion(db, value.evidence_id, revision);
            },
            .resolve_legacy_registration_unit => |value| {
                const revision = switch (result) {
                    .unit_revised => |item| item,
                    else => return error.InvalidStoredValue,
                };
                try requireAcceptedRegistrationUnitAssertion(db, value.evidence_id, revision);
            },
            .create_registration_unit_contact => |value| {
                const revision = switch (result) {
                    .registration_unit_contact_created => |item| item,
                    else => return error.InvalidStoredValue,
                };
                try requireAcceptedRegistrationUnitContactAssertion(
                    db,
                    value.evidence_id,
                    revision,
                );
            },
            .revise_registration_unit_contact => |value| {
                const revision = switch (result) {
                    .registration_unit_contact_revised => |item| item,
                    else => return error.InvalidStoredValue,
                };
                try requireAcceptedRegistrationUnitContactAssertion(
                    db,
                    value.evidence_id,
                    revision,
                );
            },
            .create_tax_type_registration => {
                const revision = switch (result) {
                    .tax_type_registration_created, .tax_type_registration_revised => |item| item,
                    else => return error.InvalidStoredValue,
                };
                if (revision.evidence_id) |evidence_id| {
                    try requireAcceptedTaxTypeRegistrationAssertion(db, evidence_id, revision);
                }
            },
            .revise_tax_type_registration => {
                const revision = switch (result) {
                    .tax_type_registration_created, .tax_type_registration_revised => |item| item,
                    else => return error.InvalidStoredValue,
                };
                if (revision.evidence_id) |evidence_id| {
                    try requireAcceptedTaxTypeRegistrationAssertion(db, evidence_id, revision);
                }
            },
            else => {},
        }
    }

    /// Applies one command while the caller owns the SQLite transaction. Each
    /// invocation reloads effective context from the same connection so a
    /// later bundle command observes every prior uncommitted ledger append.
    fn applyCommandInTransaction(
        self: *TaxpayerRegistrationLedger,
        db: *sqlite.sqlite3,
        command: domain.RegistrationCommand,
        legacy_migration_authority: ?*const LegacyMigrationCutoverAuthority,
    ) Error!domain.RegistrationWriteResult {
        try requireLegacyMigrationCutoverAuthority(
            command,
            legacy_migration_authority,
        );
        var normalized_command = command;
        switch (normalized_command) {
            .create_tax_type_registration => |value| {
                try requireNoTaxTypeRegistrationShell(
                    db,
                    value.taxpayer_id,
                    value.registration_unit_id,
                    value.tax_type,
                );
            },
            else => {},
        }
        const taxpayer_id = commandTaxpayerId(normalized_command);
        const as_of = commandEffectiveFrom(normalized_command);

        var context = try self.loadCommandContext(db, taxpayer_id, as_of);
        defer context.deinit(self.allocator);

        try self.hydrateCurrentCommand(&normalized_command, context.view());
        try self.assignHistorySequence(db, &normalized_command);
        if (commandRequiredEvidence(normalized_command)) |evidence_id| {
            try self.requireAcceptedEvidence(db, evidence_id);
        }

        const result = try domain.apply(normalized_command, context.view());
        try self.requireEvidenceAssertionsForResult(db, normalized_command, result);
        try self.persistCommandResult(db, normalized_command, result);
        return result;
    }

    /// Creation owns a stable unit/tax-type shell. Closing or otherwise
    /// revising that registration must append to the same shell; a new ID for
    /// the same fact would split history and make replayed evidence ambiguous.
    fn requireNoTaxTypeRegistrationShell(
        db: *sqlite.sqlite3,
        taxpayer_id: domain.TaxpayerId,
        registration_unit_id: domain.RegistrationUnitId,
        tax_type: domain.TaxType,
    ) Error!void {
        var statement = try prepare(db,
            \\SELECT 1
            \\FROM taxpayer_registration_tax_type_registrations AS registration
            \\JOIN taxpayer_registration_tax_type_registration_revisions AS revision
            \\  ON revision.registration_id = registration.id
            \\WHERE registration.taxpayer_id = ?
            \\  AND registration.registration_unit_id = ?
            \\  AND revision.tax_type = ?
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, taxpayer_id.asSlice());
        try statement.bindText(2, registration_unit_id.asSlice());
        try statement.bindText(3, @tagName(tax_type));
        if (try statement.step() == .row) {
            return error.DuplicateTaxTypeRegistration;
        }
    }

    fn loadCommandContext(
        self: *TaxpayerRegistrationLedger,
        db: *sqlite.sqlite3,
        taxpayer_id: domain.TaxpayerId,
        as_of: domain.Date,
    ) Error!OwnedCommandContext {
        const identities = try loadEffectiveTaxpayerIdentities(
            self.allocator,
            db,
            as_of,
        );
        errdefer self.allocator.free(identities);
        const units = try loadEffectiveUnits(
            self.allocator,
            db,
            taxpayer_id,
            as_of,
        );
        errdefer self.allocator.free(units);
        const contacts = try loadEffectiveRegistrationUnitContacts(
            self.allocator,
            db,
            taxpayer_id,
            as_of,
        );
        errdefer self.allocator.free(contacts);
        const lineage = try loadConfirmedCodeLineage(
            self.allocator,
            db,
            taxpayer_id,
        );
        errdefer self.allocator.free(lineage);
        const tax_type_registrations = try loadEffectiveTaxTypeRegistrations(
            self.allocator,
            db,
            taxpayer_id,
            as_of,
        );
        errdefer self.allocator.free(tax_type_registrations);
        return .{
            .identities = identities,
            .units = units,
            .contacts = contacts,
            .lineage = lineage,
            .tax_type_registrations = tax_type_registrations,
        };
    }

    fn persistCommandResult(
        self: *TaxpayerRegistrationLedger,
        db: *sqlite.sqlite3,
        command: domain.RegistrationCommand,
        result: domain.RegistrationWriteResult,
    ) Error!void {
        _ = self;
        switch (command) {
            .create_taxpayer => {
                const created = switch (result) {
                    .taxpayer_created => |value| value,
                    else => return error.InvalidStoredValue,
                };
                try insertTaxpayerShell(db, created.taxpayer_identity);
                try insertTaxpayerIdentityRevision(db, created.taxpayer_identity);
                try insertRegistrationUnitShell(db, created.head_office);
                try insertRegistrationUnitRevision(db, created.head_office);
            },
            .confirm_taxpayer_tin_root, .correct_taxpayer_tin_root => {
                const revision = switch (result) {
                    .taxpayer_revised => |value| value,
                    else => return error.InvalidStoredValue,
                };
                try insertTaxpayerIdentityRevision(db, revision);
            },
            .create_branch, .import_legacy_registration_unit => {
                const unit = switch (result) {
                    .unit_created => |value| value,
                    else => return error.InvalidStoredValue,
                };
                try insertRegistrationUnitShell(db, unit);
                try insertRegistrationUnitRevision(db, unit);
            },
            .replace_candidate_branch_code,
            .close_registration_unit,
            .transfer_registration_unit,
            => {
                const unit = switch (result) {
                    .unit_revised => |value| value,
                    else => return error.InvalidStoredValue,
                };
                try insertRegistrationUnitRevision(db, unit);
            },
            .confirm_registration_unit,
            .correct_branch_code,
            .resolve_legacy_registration_unit,
            => {
                const unit = switch (result) {
                    .unit_revised => |value| value,
                    else => return error.InvalidStoredValue,
                };
                try insertRegistrationUnitRevision(db, unit);
                try insertConfirmedCodeLineage(db, unit);
            },
            .create_registration_unit_contact => {
                const revision = switch (result) {
                    .registration_unit_contact_created => |value| value,
                    else => return error.InvalidStoredValue,
                };
                try insertRegistrationUnitContactRevision(db, revision);
            },
            .revise_registration_unit_contact => {
                const revision = switch (result) {
                    .registration_unit_contact_revised => |value| value,
                    else => return error.InvalidStoredValue,
                };
                try insertRegistrationUnitContactRevision(db, revision);
            },
            .create_tax_type_registration => {
                const revision = switch (result) {
                    .tax_type_registration_created => |value| value,
                    else => return error.InvalidStoredValue,
                };
                try insertTaxTypeRegistrationShell(db, revision);
                try insertTaxTypeRegistrationRevision(db, revision);
            },
            .revise_tax_type_registration => {
                const revision = switch (result) {
                    .tax_type_registration_revised => |value| value,
                    else => return error.InvalidStoredValue,
                };
                try insertTaxTypeRegistrationRevision(db, revision);
            },
        }
    }

    /// The unit/tax-registration append sequence is a history-head token, not
    /// the sequence visible at a caller's effective date. This permits safe
    /// backdated revisions while rejecting two writers that race from the same
    /// observed history head.
    fn assignHistorySequence(
        self: *TaxpayerRegistrationLedger,
        db: *sqlite.sqlite3,
        command: *domain.RegistrationCommand,
    ) Error!void {
        _ = self;
        switch (command.*) {
            .confirm_taxpayer_tin_root => |*value| {
                value.next.sequence = try nextTaxpayerRevisionSequence(
                    db,
                    value.current.taxpayer_id,
                    value.next.expected_history_sequence,
                );
            },
            .correct_taxpayer_tin_root => |*value| {
                value.next.sequence = try nextTaxpayerRevisionSequence(
                    db,
                    value.current.taxpayer_id,
                    value.next.expected_history_sequence,
                );
            },
            .replace_candidate_branch_code => |*value| {
                value.next.sequence = try nextUnitRevisionSequence(
                    db,
                    value.current.registration_unit_id,
                    value.next.expected_history_sequence,
                );
            },
            .confirm_registration_unit => |*value| {
                value.next.sequence = try nextUnitRevisionSequence(
                    db,
                    value.current.registration_unit_id,
                    value.next.expected_history_sequence,
                );
            },
            .close_registration_unit => |*value| {
                value.next.sequence = try nextUnitRevisionSequence(
                    db,
                    value.current.registration_unit_id,
                    value.next.expected_history_sequence,
                );
            },
            .transfer_registration_unit => |*value| {
                value.next.sequence = try nextUnitRevisionSequence(
                    db,
                    value.current.registration_unit_id,
                    value.next.expected_history_sequence,
                );
            },
            .correct_branch_code => |*value| {
                value.next.sequence = try nextUnitRevisionSequence(
                    db,
                    value.current.registration_unit_id,
                    value.next.expected_history_sequence,
                );
            },
            .resolve_legacy_registration_unit => |*value| {
                value.next.sequence = try nextUnitRevisionSequence(
                    db,
                    value.current.registration_unit_id,
                    value.next.expected_history_sequence,
                );
            },
            .create_registration_unit_contact => |*value| {
                value.next.sequence = try nextRegistrationUnitContactRevisionSequence(
                    db,
                    value.registration_unit_id,
                    value.next.expected_history_sequence,
                );
            },
            .revise_registration_unit_contact => |*value| {
                value.next.sequence = try nextRegistrationUnitContactRevisionSequence(
                    db,
                    value.current.registration_unit_id,
                    value.next.expected_history_sequence,
                );
            },
            .revise_tax_type_registration => |*value| {
                value.next.sequence = try nextTaxTypeRegistrationRevisionSequence(
                    db,
                    value.current.registration_id,
                    value.next.expected_history_sequence,
                );
            },
            else => {},
        }
    }

    /// Domain transitions must receive the persisted effective revision, not
    /// a caller-crafted copy with only a matching ID/sequence.
    fn hydrateCurrentCommand(
        self: *TaxpayerRegistrationLedger,
        command: *domain.RegistrationCommand,
        context: domain.RegistrationCommandContext,
    ) Error!void {
        _ = self;
        switch (command.*) {
            .confirm_taxpayer_tin_root => |*value| {
                value.current = try matchingTaxpayerIdentityRevision(
                    value.current,
                    context.taxpayer_identity_revisions,
                );
            },
            .correct_taxpayer_tin_root => |*value| {
                value.current = try matchingTaxpayerIdentityRevision(
                    value.current,
                    context.taxpayer_identity_revisions,
                );
            },
            .replace_candidate_branch_code => |*value| {
                value.current = try matchingUnitRevision(value.current, context.effective_units);
            },
            .confirm_registration_unit => |*value| {
                value.current = try matchingUnitRevision(value.current, context.effective_units);
            },
            .close_registration_unit => |*value| {
                value.current = try matchingUnitRevision(value.current, context.effective_units);
            },
            .transfer_registration_unit => |*value| {
                value.current = try matchingUnitRevision(value.current, context.effective_units);
            },
            .correct_branch_code => |*value| {
                value.current = try matchingUnitRevision(value.current, context.effective_units);
            },
            .resolve_legacy_registration_unit => |*value| {
                value.current = try matchingUnitRevision(value.current, context.effective_units);
            },
            .revise_registration_unit_contact => |*value| {
                value.current = try matchingRegistrationUnitContactRevision(
                    value.current,
                    context.effective_registration_unit_contacts,
                );
            },
            .revise_tax_type_registration => |*value| {
                value.current = try matchingTaxTypeRegistrationRevision(
                    value.current,
                    context.effective_tax_type_registrations,
                );
            },
            else => {},
        }
    }
};

const OwnedCommandContext = struct {
    identities: []domain.TaxpayerIdentityRevision,
    units: []domain.RegistrationUnitRevision,
    contacts: []domain.RegistrationUnitContactRevision,
    lineage: []domain.BranchCodeLineageEntry,
    tax_type_registrations: []domain.TaxTypeRegistrationRevision,

    fn deinit(self: *OwnedCommandContext, allocator: std.mem.Allocator) void {
        allocator.free(self.identities);
        allocator.free(self.units);
        allocator.free(self.contacts);
        allocator.free(self.lineage);
        allocator.free(self.tax_type_registrations);
        self.* = undefined;
    }

    fn view(self: *const OwnedCommandContext) domain.RegistrationCommandContext {
        return .{
            .taxpayer_identity_revisions = self.identities,
            .effective_units = self.units,
            .effective_registration_unit_contacts = self.contacts,
            .confirmed_code_lineage = self.lineage,
            .effective_tax_type_registrations = self.tax_type_registrations,
        };
    }
};

const StepResult = enum {
    row,
    done,
};

const Statement = struct {
    raw: *sqlite.sqlite3_stmt,

    fn deinit(self: *Statement) void {
        _ = sqlite.sqlite3_finalize(self.raw);
        self.* = undefined;
    }

    fn bindText(
        self: *Statement,
        index: c_int,
        value: []const u8,
    ) Error!void {
        const rc = sqlite.sqlite3_bind_text(
            self.raw,
            index,
            value.ptr,
            @intCast(value.len),
            null,
        );
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn bindOptionalText(
        self: *Statement,
        index: c_int,
        value: ?[]const u8,
    ) Error!void {
        if (value) |text| return self.bindText(index, text);
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return error.SqliteFailure;
        }
    }

    fn bindInt64(self: *Statement, index: c_int, value: i64) Error!void {
        const rc = sqlite.sqlite3_bind_int64(self.raw, index, value);
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn bindOptionalInt64(
        self: *Statement,
        index: c_int,
        value: ?i64,
    ) Error!void {
        if (value) |number| return self.bindInt64(index, number);
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return error.SqliteFailure;
        }
    }

    fn step(self: *Statement) Error!StepResult {
        return switch (sqlite.sqlite3_step(self.raw)) {
            sqlite.SQLITE_ROW => .row,
            sqlite.SQLITE_DONE => .done,
            else => |rc| mapResult(rc),
        };
    }

    fn expectDone(self: *Statement) Error!void {
        if (try self.step() != .done) return error.SqliteFailure;
    }
};

fn prepare(db: *sqlite.sqlite3, sql_text: []const u8) Error!Statement {
    var raw: ?*sqlite.sqlite3_stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(
        db,
        sql_text.ptr,
        @intCast(sql_text.len),
        &raw,
        null,
    );
    if (rc != sqlite.SQLITE_OK or raw == null) return mapResult(rc);
    return .{ .raw = raw.? };
}

fn exec(db: *sqlite.sqlite3, sql_text: [*:0]const u8) Error!void {
    const rc = sqlite.sqlite3_exec(db, sql_text, null, null, null);
    if (rc != sqlite.SQLITE_OK) return mapResult(rc);
}

fn rollbackNoFail(db: *sqlite.sqlite3) void {
    exec(db, "ROLLBACK;") catch {};
}

fn mapResult(rc: c_int) store.Error {
    return switch (rc & 0xff) {
        sqlite.SQLITE_BUSY, sqlite.SQLITE_LOCKED => error.SqliteBusy,
        sqlite.SQLITE_CONSTRAINT => error.SqliteConstraint,
        else => error.SqliteFailure,
    };
}

fn insertEvidence(db: *sqlite.sqlite3, value: EvidenceWrite) Error!void {
    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_evidence (
        \\    id, source_kind, sha256, display_name, byte_size, captured_on,
        \\    storage_reference_kind, storage_reference
        \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    );
    defer statement.deinit();

    var captured_on: [10]u8 = undefined;
    try statement.bindText(1, value.id.asSlice());
    try statement.bindText(2, @tagName(value.source_kind));
    try statement.bindText(3, value.sha256);
    try statement.bindText(4, value.display_name);
    try statement.bindInt64(5, try u64ToSqliteInt(value.byte_size));
    try statement.bindText(6, value.captured_on.writeIso(&captured_on));
    switch (value.storage) {
        .metadata_only_non_authoritative => {
            try statement.bindText(7, "metadata_only_non_authoritative");
            try statement.bindOptionalText(8, null);
        },
        .protected_local_path => |reference| {
            try statement.bindText(7, "protected_local_path");
            try statement.bindOptionalText(8, reference);
        },
        .encrypted_blob_reference => |reference| {
            try statement.bindText(7, "encrypted_blob_reference");
            try statement.bindOptionalText(8, reference);
        },
    }
    try statement.expectDone();
}

fn insertEvidenceReviewDecision(
    db: *sqlite.sqlite3,
    value: EvidenceReviewDecisionWrite,
) Error!void {
    const sequence = try nextEvidenceReviewSequence(
        db,
        value.evidence_id,
        value.expected_history_sequence,
    );
    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_evidence_review_decisions (
        \\    id, evidence_id, sequence, review_state, reviewer_kind,
        \\    reviewer_local_owner_id, reviewer_service_actor_id, reviewed_at,
        \\    review_reason, supersedes_decision_id, contradicts_decision_id
        \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    );
    defer statement.deinit();
    try statement.bindText(1, value.id.asSlice());
    try statement.bindText(2, value.evidence_id.asSlice());
    try statement.bindInt64(3, @intCast(sequence));
    try statement.bindText(4, @tagName(value.state));
    switch (value.reviewer) {
        .local_owner => |id| {
            try statement.bindText(5, "local_owner");
            try statement.bindOptionalText(6, id[0..]);
            try statement.bindOptionalText(7, null);
        },
        .service => |id| {
            try statement.bindText(5, "service");
            try statement.bindOptionalText(6, null);
            try statement.bindOptionalText(7, id.asSlice());
        },
    }
    try statement.bindInt64(8, value.reviewed_at_unix_seconds);
    try statement.bindText(9, value.reason);
    try statement.bindOptionalText(
        10,
        optionalReviewDecisionIdText(&value.supersedes),
    );
    try statement.bindOptionalText(
        11,
        optionalReviewDecisionIdText(&value.contradicts),
    );
    try statement.expectDone();
}

fn insertEvidenceAssertion(
    db: *sqlite.sqlite3,
    value: EvidenceAssertionWrite,
) Error!void {
    try requireEvidenceAssertionSubject(db, value);

    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\    id, evidence_id, taxpayer_id, registration_unit_id,
        \\    effective_from, fact_kind, tin9, branch_code,
        \\    registration_unit_status, rdo_code, tax_type, tax_type_status,
        \\    registered_address, zip_code, contact_number, email_address
        \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    );
    defer statement.deinit();

    var effective_from: [10]u8 = undefined;
    var tin_root_storage: [9]u8 = undefined;
    var branch_code_storage: [5]u8 = undefined;
    var rdo_code_storage: [3]u8 = undefined;
    var tin_root: ?[]const u8 = null;
    var branch_code: ?[]const u8 = null;
    var registration_unit_status: ?[]const u8 = null;
    var rdo_code: ?[]const u8 = null;
    var tax_type: ?[]const u8 = null;
    var tax_type_status: ?[]const u8 = null;
    var registered_address: ?[]const u8 = null;
    var zip_code: ?[]const u8 = null;
    var contact_number: ?[]const u8 = null;
    var email_address: ?[]const u8 = null;
    const fact_kind: []const u8 = switch (value.fact) {
        .taxpayer_tin_root => |fact| blk: {
            @memcpy(&tin_root_storage, fact.tin_root.asDigits());
            tin_root = &tin_root_storage;
            break :blk "taxpayer_tin_root";
        },
        .registration_unit => |fact| blk: {
            @memcpy(&branch_code_storage, fact.branch_code.asDigits());
            branch_code = &branch_code_storage;
            registration_unit_status = @tagName(fact.status);
            if (fact.rdo_code) |code| {
                @memcpy(&rdo_code_storage, code.asDigits());
                rdo_code = &rdo_code_storage;
            }
            break :blk "registration_unit";
        },
        .registration_unit_contact => |fact| blk: {
            registered_address = fact.registered_address.asSlice();
            zip_code = if (fact.zip_code) |item| item.asSlice() else null;
            contact_number = if (fact.contact_number) |item| item.asSlice() else null;
            email_address = if (fact.email_address) |item| item.asSlice() else null;
            break :blk "registration_unit_contact";
        },
        .tax_type_registration => |fact| blk: {
            tax_type = @tagName(fact.tax_type);
            tax_type_status = @tagName(fact.status);
            break :blk "tax_type_registration";
        },
    };
    try statement.bindText(1, value.id.asSlice());
    try statement.bindText(2, value.evidence_id.asSlice());
    try statement.bindText(3, value.taxpayer_id.asSlice());
    try statement.bindOptionalText(4, if (value.registration_unit_id) |id|
        id.asSlice()
    else
        null);
    try statement.bindText(5, value.effective_from.writeIso(&effective_from));
    try statement.bindText(6, fact_kind);
    try statement.bindOptionalText(7, tin_root);
    try statement.bindOptionalText(8, branch_code);
    try statement.bindOptionalText(9, registration_unit_status);
    try statement.bindOptionalText(10, rdo_code);
    try statement.bindOptionalText(11, tax_type);
    try statement.bindOptionalText(12, tax_type_status);
    try statement.bindOptionalText(13, registered_address);
    try statement.bindOptionalText(14, zip_code);
    try statement.bindOptionalText(15, contact_number);
    try statement.bindOptionalText(16, email_address);
    try statement.expectDone();
}

fn requireAcceptedTaxpayerTinRootAssertion(
    db: *sqlite.sqlite3,
    evidence_id: domain.RegistrationEvidenceId,
    revision: domain.TaxpayerIdentityRevision,
) Error!void {
    var statement = try prepare(db,
        \\SELECT 1
        \\FROM taxpayer_registration_evidence_assertions AS assertion
        \\JOIN taxpayer_registration_current_evidence_reviews AS review
        \\ ON review.evidence_id = assertion.evidence_id
        \\WHERE assertion.evidence_id = ?
        \\ AND assertion.taxpayer_id = ?
        \\ AND assertion.registration_unit_id IS NULL
        \\ AND assertion.effective_from = ?
        \\ AND assertion.fact_kind = 'taxpayer_tin_root'
        \\ AND assertion.tin9 = ?
        \\ AND review.review_state = 'accepted'
        \\ORDER BY assertion.id COLLATE BINARY
        \\LIMIT 2;
    );
    defer statement.deinit();
    var effective_from: [10]u8 = undefined;
    try statement.bindText(1, evidence_id.asSlice());
    try statement.bindText(2, revision.taxpayer_id.asSlice());
    try statement.bindText(3, revision.effective.from.writeIso(&effective_from));
    try statement.bindText(4, revision.tin_root.asDigits());
    try requireUniqueAcceptedAssertion(&statement);
}

fn requireAcceptedRegistrationUnitAssertion(
    db: *sqlite.sqlite3,
    evidence_id: domain.RegistrationEvidenceId,
    revision: domain.RegistrationUnitRevision,
) Error!void {
    const confirmed = revision.branch_code_evidence.confirmedCode() orelse
        return error.InvalidStoredValue;
    var statement = try prepare(db,
        \\SELECT 1
        \\FROM taxpayer_registration_evidence_assertions AS assertion
        \\JOIN taxpayer_registration_current_evidence_reviews AS review
        \\  ON review.evidence_id = assertion.evidence_id
        \\WHERE assertion.evidence_id = ?
        \\  AND assertion.taxpayer_id = ?
        \\  AND assertion.registration_unit_id = ?
        \\  AND assertion.effective_from = ?
        \\  AND assertion.fact_kind = 'registration_unit'
        \\  AND assertion.branch_code = ?
        \\  AND assertion.registration_unit_status = ?
        \\  AND assertion.rdo_code IS ?
        \\  AND review.review_state = 'accepted'
        \\ORDER BY assertion.id COLLATE BINARY
        \\LIMIT 2;
    );
    defer statement.deinit();
    var effective_from: [10]u8 = undefined;
    try statement.bindText(1, evidence_id.asSlice());
    try statement.bindText(2, revision.taxpayer_id.asSlice());
    try statement.bindText(3, revision.registration_unit_id.asSlice());
    try statement.bindText(4, revision.effective.from.writeIso(&effective_from));
    try statement.bindText(5, confirmed.code.asDigits());
    try statement.bindText(6, @tagName(revision.status));
    try statement.bindOptionalText(7, if (revision.rdo_code) |code|
        code.asDigits()
    else
        null);
    try requireUniqueAcceptedAssertion(&statement);
}

fn requireAcceptedRegistrationUnitContactAssertion(
    db: *sqlite.sqlite3,
    evidence_id: domain.RegistrationEvidenceId,
    revision: domain.RegistrationUnitContactRevision,
) Error!void {
    var statement = try prepare(db,
        \\SELECT 1
        \\FROM taxpayer_registration_evidence_assertions AS assertion
        \\JOIN taxpayer_registration_current_evidence_reviews AS review
        \\    ON review.evidence_id = assertion.evidence_id
        \\WHERE assertion.evidence_id = ?
        \\    AND assertion.taxpayer_id = ?
        \\    AND assertion.registration_unit_id = ?
        \\    AND assertion.effective_from = ?
        \\    AND assertion.fact_kind = 'registration_unit_contact'
        \\    AND assertion.registered_address = ?
        \\    AND assertion.zip_code IS ?
        \\    AND assertion.contact_number IS ?
        \\    AND assertion.email_address IS ?
        \\    AND review.review_state = 'accepted'
        \\ORDER BY assertion.id COLLATE BINARY
        \\LIMIT 2;
    );
    defer statement.deinit();

    var effective_from: [10]u8 = undefined;
    try statement.bindText(1, evidence_id.asSlice());
    try statement.bindText(2, revision.taxpayer_id.asSlice());
    try statement.bindText(3, revision.registration_unit_id.asSlice());
    try statement.bindText(4, revision.effective.from.writeIso(&effective_from));
    try statement.bindText(5, revision.contact.registered_address.asSlice());
    try statement.bindOptionalText(6, if (revision.contact.zip_code) |value| value.asSlice() else null);
    try statement.bindOptionalText(7, if (revision.contact.contact_number) |value| value.asSlice() else null);
    try statement.bindOptionalText(8, if (revision.contact.email_address) |value| value.asSlice() else null);
    try requireUniqueAcceptedAssertion(&statement);
}

fn requireAcceptedTaxTypeRegistrationAssertion(
    db: *sqlite.sqlite3,
    evidence_id: domain.RegistrationEvidenceId,
    revision: domain.TaxTypeRegistrationRevision,
) Error!void {
    var statement = try prepare(db,
        \\SELECT 1
        \\FROM taxpayer_registration_evidence_assertions AS assertion
        \\JOIN taxpayer_registration_current_evidence_reviews AS review
        \\  ON review.evidence_id = assertion.evidence_id
        \\WHERE assertion.evidence_id = ?
        \\  AND assertion.taxpayer_id = ?
        \\  AND assertion.registration_unit_id = ?
        \\  AND assertion.effective_from = ?
        \\  AND assertion.fact_kind = 'tax_type_registration'
        \\  AND assertion.tax_type = ?
        \\  AND assertion.tax_type_status = ?
        \\  AND review.review_state = 'accepted'
        \\ORDER BY assertion.id COLLATE BINARY
        \\LIMIT 2;
    );
    defer statement.deinit();
    var effective_from: [10]u8 = undefined;
    try statement.bindText(1, evidence_id.asSlice());
    try statement.bindText(2, revision.taxpayer_id.asSlice());
    try statement.bindText(3, revision.registration_unit_id.asSlice());
    try statement.bindText(4, revision.effective.from.writeIso(&effective_from));
    try statement.bindText(5, @tagName(revision.tax_type));
    try statement.bindText(6, @tagName(revision.status));
    try requireUniqueAcceptedAssertion(&statement);
}

fn requireUniqueAcceptedAssertion(statement: *Statement) Error!void {
    if (try statement.step() != .row) return error.EvidenceAssertionNotAccepted;
    if (try statement.step() == .row) return error.EvidenceAssertionNotAccepted;
}

fn validateEvidenceAssertionWrite(value: EvidenceAssertionWrite) Error!void {
    if (!value.id.isPresent() or !value.evidence_id.isPresent() or
        !value.taxpayer_id.isPresent())
    {
        return error.InvalidEvidenceAssertionWrite;
    }
    switch (value.fact) {
        .taxpayer_tin_root => {
            if (value.registration_unit_id != null) {
                return error.InvalidEvidenceAssertionWrite;
            }
        },
        .registration_unit => |fact| {
            if (value.registration_unit_id == null) {
                return error.InvalidEvidenceAssertionWrite;
            }
            switch (fact.status) {
                .confirmed_active, .confirmed_closed => {},
                .pending_evidence, .legacy_unresolved => return error.InvalidEvidenceAssertionWrite,
            }
        },
        .registration_unit_contact => {
            if (value.registration_unit_id == null) {
                return error.InvalidEvidenceAssertionWrite;
            }
        },
        .tax_type_registration => |fact| {
            if (value.registration_unit_id == null) {
                return error.InvalidEvidenceAssertionWrite;
            }
            switch (fact.status) {
                .confirmed_active, .confirmed_closed => {},
                .pending_evidence, .legacy_unresolved => return error.InvalidEvidenceAssertionWrite,
            }
        },
    }
}

fn validateReviewedEvidenceBundleWrite(
    value: ReviewedEvidenceBundleWrite,
) Error!void {
    try validateEvidenceWrite(value.evidence);
    switch (value.evidence.storage) {
        .metadata_only_non_authoritative => return error.NonAuthoritativeEvidenceStorage,
        .protected_local_path, .encrypted_blob_reference => {},
    }
    try validateEvidenceReviewDecisionWrite(value.initial_review);
    if (!value.initial_review.evidence_id.eql(&value.evidence.id) or
        value.initial_review.expected_history_sequence != 0 or
        value.initial_review.state != .accepted or
        value.initial_review.supersedes != null or
        value.initial_review.contradicts != null or
        value.assertions.len == 0 or value.commands.len == 0)
    {
        return error.InvalidReviewedEvidenceBundleWrite;
    }

    for (value.assertions) |assertion| {
        try validateEvidenceAssertionWrite(assertion);
        if (!assertion.evidence_id.eql(&value.evidence.id)) {
            return error.InvalidReviewedEvidenceBundleWrite;
        }
    }
    for (value.commands) |command| {
        const command_evidence_id = commandRequiredEvidence(command) orelse
            return error.InvalidReviewedEvidenceBundleWrite;
        if (!command_evidence_id.eql(&value.evidence.id)) {
            return error.InvalidReviewedEvidenceBundleWrite;
        }
    }
}

fn requireEvidenceAssertionSubject(
    db: *sqlite.sqlite3,
    value: EvidenceAssertionWrite,
) Error!void {
    switch (value.fact) {
        .taxpayer_tin_root => {
            var statement = try prepare(db,
                \\SELECT 1
                \\FROM taxpayer_registration_taxpayers
                \\WHERE id = ?
                \\LIMIT 1;
            );
            defer statement.deinit();
            try statement.bindText(1, value.taxpayer_id.asSlice());
            if (try statement.step() != .row) {
                return error.InvalidEvidenceAssertionWrite;
            }
        },
        .registration_unit, .registration_unit_contact, .tax_type_registration => {
            var statement = try prepare(db,
                \\SELECT 1
                \\FROM taxpayer_registration_units
                \\WHERE id = ? AND taxpayer_id = ?
                \\LIMIT 1;
            );
            defer statement.deinit();
            try statement.bindText(1, value.registration_unit_id.?.asSlice());
            try statement.bindText(2, value.taxpayer_id.asSlice());
            if (try statement.step() != .row) {
                return error.InvalidEvidenceAssertionWrite;
            }
        },
    }
}

fn validateEvidenceWrite(value: EvidenceWrite) Error!void {
    if (!value.id.isPresent()) return error.InvalidEvidenceWrite;
    _ = domain.Sha256Digest.parse(value.sha256) catch
        return error.InvalidEvidenceWrite;
    if (!validRequiredText(value.display_name)) {
        return error.InvalidEvidenceWrite;
    }
    if (value.byte_size > std.math.maxInt(i64)) return error.InvalidEvidenceWrite;
    switch (value.storage) {
        .metadata_only_non_authoritative => {},
        .protected_local_path, .encrypted_blob_reference => |reference| {
            if (!validStorageReference(reference)) {
                return error.InvalidEvidenceWrite;
            }
        },
    }
}

fn validateEvidenceReviewDecisionWrite(
    value: EvidenceReviewDecisionWrite,
) Error!void {
    if (!value.id.isPresent() or !value.evidence_id.isPresent() or
        value.reviewed_at_unix_seconds < 0 or !validReviewReason(value.reason))
    {
        return error.InvalidEvidenceReviewDecisionWrite;
    }
    switch (value.reviewer) {
        .local_owner => |id| {
            if (!validLocalOwnerActorId(id)) {
                return error.InvalidEvidenceReviewDecisionWrite;
            }
        },
        .service => |id| {
            if (!id.isPresent()) {
                return error.InvalidEvidenceReviewDecisionWrite;
            }
        },
    }
    if (value.supersedes) |id| {
        if (!id.isPresent() or id.eql(&value.id)) {
            return error.InvalidEvidenceReviewDecisionWrite;
        }
    }
    if (value.contradicts) |id| {
        if (!id.isPresent() or id.eql(&value.id)) {
            return error.InvalidEvidenceReviewDecisionWrite;
        }
    }
    if (value.supersedes != null and value.contradicts != null and
        value.supersedes.?.eql(&value.contradicts.?))
    {
        return error.InvalidEvidenceReviewDecisionWrite;
    }
    if (value.expected_history_sequence > 0 and
        value.supersedes == null and value.contradicts == null)
    {
        return error.InvalidEvidenceReviewDecisionWrite;
    }
    switch (value.state) {
        .accepted => {},
        .rejected => {
            if (value.expected_history_sequence > 0 and
                value.contradicts == null)
            {
                return error.InvalidEvidenceReviewDecisionWrite;
            }
        },
        .superseded => if (value.supersedes == null) {
            return error.InvalidEvidenceReviewDecisionWrite;
        },
    }
}

fn optionalReviewDecisionIdText(
    value: *const ?domain.RegistrationEvidenceReviewDecisionId,
) ?[]const u8 {
    if (value.*) |*id| return id.asSlice();
    return null;
}

fn validLocalOwnerActorId(value: store.OpaqueId) bool {
    for (value) |byte| {
        if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) {
            return false;
        }
    }
    return true;
}

fn validReviewReason(value: []const u8) bool {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    return trimmed.len > 0 and value.len <= 1024 and
        std.unicode.utf8ValidateSlice(value);
}

fn validStorageReference(value: []const u8) bool {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0 or
        value.len > storage_contract.max_evidence_storage_reference_bytes or
        !std.unicode.utf8ValidateSlice(value))
    {
        return false;
    }
    for (value) |byte| {
        if (byte < 0x20 or byte == 0x7f) return false;
    }
    return true;
}

fn validRequiredText(value: []const u8) bool {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    return trimmed.len > 0 and trimmed.len <= 255 and
        std.unicode.utf8ValidateSlice(value);
}

fn u64ToSqliteInt(value: u64) Error!i64 {
    if (value > std.math.maxInt(i64)) return error.InvalidEvidenceWrite;
    return @intCast(value);
}

fn nextUnitRevisionSequence(
    db: *sqlite.sqlite3,
    registration_unit_id: domain.RegistrationUnitId,
    expected_history_sequence: u32,
) Error!u32 {
    var statement = try prepare(db,
        \\SELECT COALESCE(MAX(sequence), 0)
        \\FROM taxpayer_registration_unit_revisions
        \\WHERE registration_unit_id = ?;
    );
    defer statement.deinit();
    try statement.bindText(1, registration_unit_id.asSlice());
    if (try statement.step() != .row) return error.SqliteFailure;
    const actual = try nonnegativeU32(statement.raw, 0);
    if (actual != expected_history_sequence) return error.StaleRegistrationUnitHistory;
    if (actual == std.math.maxInt(u32)) return error.RevisionSequenceExhausted;
    return actual + 1;
}

fn nextRegistrationUnitContactRevisionSequence(
    db: *sqlite.sqlite3,
    registration_unit_id: domain.RegistrationUnitId,
    expected_history_sequence: u32,
) Error!u32 {
    var statement = try prepare(db,
        \\SELECT COALESCE(MAX(sequence), 0)
        \\FROM taxpayer_registration_unit_contact_revisions
        \\WHERE registration_unit_id = ?;
    );
    defer statement.deinit();
    try statement.bindText(1, registration_unit_id.asSlice());
    if (try statement.step() != .row) return error.SqliteFailure;
    const actual = try nonnegativeU32(statement.raw, 0);
    if (actual != expected_history_sequence) {
        return error.StaleRegistrationUnitContactHistory;
    }
    if (actual == std.math.maxInt(u32)) return error.RevisionSequenceExhausted;
    return actual + 1;
}

fn nextTaxpayerRevisionSequence(
    db: *sqlite.sqlite3,
    taxpayer_id: domain.TaxpayerId,
    expected_history_sequence: u32,
) Error!u32 {
    var statement = try prepare(db,
        \\SELECT COALESCE(MAX(sequence), 0)
        \\FROM taxpayer_registration_taxpayer_revisions
        \\WHERE taxpayer_id = ?;
    );
    defer statement.deinit();
    try statement.bindText(1, taxpayer_id.asSlice());
    if (try statement.step() != .row) return error.SqliteFailure;
    const actual = try nonnegativeU32(statement.raw, 0);
    if (actual != expected_history_sequence) return error.StaleTaxpayerHistory;
    if (actual == std.math.maxInt(u32)) return error.RevisionSequenceExhausted;
    return actual + 1;
}

fn nextEvidenceReviewSequence(
    db: *sqlite.sqlite3,
    evidence_id: domain.RegistrationEvidenceId,
    expected_history_sequence: u32,
) Error!u32 {
    var statement = try prepare(db,
        \\SELECT COALESCE(MAX(sequence), 0)
        \\FROM taxpayer_registration_evidence_review_decisions
        \\WHERE evidence_id = ?;
    );
    defer statement.deinit();
    try statement.bindText(1, evidence_id.asSlice());
    if (try statement.step() != .row) return error.SqliteFailure;
    const actual = try nonnegativeU32(statement.raw, 0);
    if (actual != expected_history_sequence) return error.StaleEvidenceReviewHistory;
    if (actual == std.math.maxInt(u32)) return error.RevisionSequenceExhausted;
    return actual + 1;
}

fn nextTaxTypeRegistrationRevisionSequence(
    db: *sqlite.sqlite3,
    registration_id: domain.TaxTypeRegistrationId,
    expected_history_sequence: u32,
) Error!u32 {
    var statement = try prepare(db,
        \\SELECT COALESCE(MAX(sequence), 0)
        \\FROM taxpayer_registration_tax_type_registration_revisions
        \\WHERE registration_id = ?;
    );
    defer statement.deinit();
    try statement.bindText(1, registration_id.asSlice());
    if (try statement.step() != .row) return error.SqliteFailure;
    const actual = try nonnegativeU32(statement.raw, 0);
    if (actual != expected_history_sequence) return error.StaleTaxTypeRegistrationHistory;
    if (actual == std.math.maxInt(u32)) return error.RevisionSequenceExhausted;
    return actual + 1;
}

fn matchingUnitRevision(
    requested: domain.RegistrationUnitRevision,
    effective_units: []const domain.RegistrationUnitRevision,
) Error!domain.RegistrationUnitRevision {
    var resolved: ?domain.RegistrationUnitRevision = null;
    for (effective_units) |candidate| {
        if (!requested.registration_unit_id.eql(&candidate.registration_unit_id)) continue;
        if (resolved != null) return error.StaleRegistrationUnitRevision;
        resolved = candidate;
    }
    const value = resolved orelse return error.StaleRegistrationUnitRevision;
    if (!requested.id.eql(&value.id) or requested.sequence != value.sequence) {
        return error.StaleRegistrationUnitRevision;
    }
    return value;
}

fn matchingRegistrationUnitContactRevision(
    requested: domain.RegistrationUnitContactRevision,
    effective_contacts: []const domain.RegistrationUnitContactRevision,
) Error!domain.RegistrationUnitContactRevision {
    var resolved: ?domain.RegistrationUnitContactRevision = null;
    for (effective_contacts) |candidate| {
        if (!requested.taxpayer_id.eql(&candidate.taxpayer_id) or
            !requested.registration_unit_id.eql(&candidate.registration_unit_id))
        {
            continue;
        }
        if (resolved != null) return error.StaleRegistrationUnitContactRevision;
        resolved = candidate;
    }
    const value = resolved orelse return error.StaleRegistrationUnitContactRevision;
    if (!requested.id.eql(&value.id) or requested.sequence != value.sequence) {
        return error.StaleRegistrationUnitContactRevision;
    }
    return value;
}

fn matchingTaxpayerIdentityRevision(
    requested: domain.TaxpayerIdentityRevision,
    effective_identities: []const domain.TaxpayerIdentityRevision,
) Error!domain.TaxpayerIdentityRevision {
    var resolved: ?domain.TaxpayerIdentityRevision = null;
    for (effective_identities) |candidate| {
        if (!requested.taxpayer_id.eql(&candidate.taxpayer_id)) continue;
        if (resolved != null) return error.StaleTaxpayerRevision;
        resolved = candidate;
    }
    const value = resolved orelse return error.StaleTaxpayerRevision;
    if (!requested.id.eql(&value.id) or requested.sequence != value.sequence) {
        return error.StaleTaxpayerRevision;
    }
    return value;
}

fn matchingTaxTypeRegistrationRevision(
    requested: domain.TaxTypeRegistrationRevision,
    effective_revisions: []const domain.TaxTypeRegistrationRevision,
) Error!domain.TaxTypeRegistrationRevision {
    var resolved: ?domain.TaxTypeRegistrationRevision = null;
    for (effective_revisions) |candidate| {
        if (!requested.registration_id.eql(&candidate.registration_id)) continue;
        if (resolved != null) return error.StaleTaxTypeRegistrationRevision;
        resolved = candidate;
    }
    const value = resolved orelse return error.StaleTaxTypeRegistrationRevision;
    if (!requested.id.eql(&value.id) or requested.sequence != value.sequence) {
        return error.StaleTaxTypeRegistrationRevision;
    }
    return value;
}

fn requireLegacyMigrationCutoverAuthority(
    command: domain.RegistrationCommand,
    authority: ?*const LegacyMigrationCutoverAuthority,
) Error!void {
    switch (command) {
        .import_legacy_registration_unit => {
            const expected: *const LegacyMigrationCutoverAuthority =
                @ptrCast(&legacy_migration_test_authority_token);
            if (authority == null or authority.? != expected) {
                return error.LegacyMigrationCutoverAuthorityRequired;
            }
        },
        else => {},
    }
}

fn commandTaxpayerId(command: domain.RegistrationCommand) domain.TaxpayerId {
    return switch (command) {
        .create_taxpayer => |value| value.taxpayer_id,
        .confirm_taxpayer_tin_root => |value| value.current.taxpayer_id,
        .correct_taxpayer_tin_root => |value| value.current.taxpayer_id,
        .create_branch => |value| value.taxpayer_id,
        .replace_candidate_branch_code => |value| value.current.taxpayer_id,
        .confirm_registration_unit => |value| value.current.taxpayer_id,
        .close_registration_unit => |value| value.current.taxpayer_id,
        .transfer_registration_unit => |value| value.current.taxpayer_id,
        .correct_branch_code => |value| value.current.taxpayer_id,
        .import_legacy_registration_unit => |value| value.taxpayer_id,
        .resolve_legacy_registration_unit => |value| value.current.taxpayer_id,
        .create_registration_unit_contact => |value| value.taxpayer_id,
        .revise_registration_unit_contact => |value| value.current.taxpayer_id,
        .create_tax_type_registration => |value| value.taxpayer_id,
        .revise_tax_type_registration => |value| value.current.taxpayer_id,
    };
}

fn commandEffectiveFrom(command: domain.RegistrationCommand) domain.Date {
    return switch (command) {
        .create_taxpayer => |value| value.effective_from,
        .confirm_taxpayer_tin_root => |value| value.next.effective.from,
        .correct_taxpayer_tin_root => |value| value.next.effective.from,
        .create_branch => |value| value.effective_from,
        .replace_candidate_branch_code => |value| value.next.effective.from,
        .confirm_registration_unit => |value| value.next.effective.from,
        .close_registration_unit => |value| value.next.effective.from,
        .transfer_registration_unit => |value| value.next.effective.from,
        .correct_branch_code => |value| value.next.effective.from,
        .import_legacy_registration_unit => |value| value.effective_from,
        .resolve_legacy_registration_unit => |value| value.next.effective.from,
        .create_registration_unit_contact => |value| value.next.effective.from,
        .revise_registration_unit_contact => |value| value.next.effective.from,
        .create_tax_type_registration => |value| value.effective_from,
        .revise_tax_type_registration => |value| value.next.effective.from,
    };
}

fn commandRequiredEvidence(
    command: domain.RegistrationCommand,
) ?domain.RegistrationEvidenceId {
    return switch (command) {
        .confirm_taxpayer_tin_root => |value| value.evidence_id,
        .correct_taxpayer_tin_root => |value| value.evidence_id,
        .confirm_registration_unit => |value| value.evidence_id,
        .close_registration_unit => |value| value.evidence_id,
        .transfer_registration_unit => |value| value.evidence_id,
        // A correction is also an audited registration fact. Requiring an
        // accepted evidence row prevents a branch-code rewrite by assertion.
        .correct_branch_code => |value| value.evidence_id,
        .resolve_legacy_registration_unit => |value| value.evidence_id,
        .create_registration_unit_contact => |value| value.evidence_id,
        .revise_registration_unit_contact => |value| value.evidence_id,
        .create_tax_type_registration => |value| requiredTaxTypeEvidence(
            value.status,
            value.evidence_id,
        ),
        .revise_tax_type_registration => |value| requiredTaxTypeEvidence(
            value.status,
            value.evidence_id,
        ),
        else => null,
    };
}

fn requiredTaxTypeEvidence(
    status: domain.TaxTypeRegistrationStatus,
    evidence_id: ?domain.RegistrationEvidenceId,
) ?domain.RegistrationEvidenceId {
    return switch (status) {
        .confirmed_active, .confirmed_closed => evidence_id,
        .pending_evidence, .legacy_unresolved => null,
    };
}

fn insertTaxpayerShell(
    db: *sqlite.sqlite3,
    revision: domain.TaxpayerIdentityRevision,
) Error!void {
    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_taxpayers (id)
        \\VALUES (?);
    );
    defer statement.deinit();
    try statement.bindText(1, revision.taxpayer_id.asSlice());
    try statement.expectDone();
}

fn insertTaxpayerIdentityRevision(
    db: *sqlite.sqlite3,
    revision: domain.TaxpayerIdentityRevision,
) Error!void {
    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_taxpayer_revisions (
        \\    id, taxpayer_id, sequence, effective_from, effective_until,
        \\    tin9, evidence_id
        \\) VALUES (?, ?, ?, ?, ?, ?, ?);
    );
    defer statement.deinit();
    var effective_from: [10]u8 = undefined;
    var effective_until: [10]u8 = undefined;
    try statement.bindText(1, revision.id.asSlice());
    try statement.bindText(2, revision.taxpayer_id.asSlice());
    try statement.bindInt64(3, @intCast(revision.sequence));
    try statement.bindText(4, revision.effective.from.writeIso(&effective_from));
    try statement.bindOptionalText(5, if (revision.effective.until) |until|
        until.writeIso(&effective_until)
    else
        null);
    try statement.bindText(6, revision.tin_root.asDigits());
    try statement.bindOptionalText(7, if (revision.evidence_id) |id|
        id.asSlice()
    else
        null);
    try statement.expectDone();
}

fn insertRegistrationUnitShell(
    db: *sqlite.sqlite3,
    revision: domain.RegistrationUnitRevision,
) Error!void {
    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_units (id, taxpayer_id)
        \\VALUES (?, ?);
    );
    defer statement.deinit();
    try statement.bindText(1, revision.registration_unit_id.asSlice());
    try statement.bindText(2, revision.taxpayer_id.asSlice());
    try statement.expectDone();
}

fn insertRegistrationUnitRevision(
    db: *sqlite.sqlite3,
    revision: domain.RegistrationUnitRevision,
) Error!void {
    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_unit_revisions (
        \\    id, taxpayer_id, registration_unit_id, sequence, effective_from,
        \\    effective_until, kind, branch_code_state, branch_code,
        \\    legacy_suffix, status, rdo_code, branch_code_evidence_id,
        \\    lifecycle_evidence_id
        \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    );
    defer statement.deinit();

    var effective_from: [10]u8 = undefined;
    var effective_until: [10]u8 = undefined;
    var branch_code_storage: [5]u8 = undefined;
    var legacy_suffix_storage: [4]u8 = undefined;
    var branch_code_evidence_storage: [64]u8 = undefined;
    var lifecycle_evidence_storage: [64]u8 = undefined;
    var branch_code: ?[]const u8 = null;
    var legacy_suffix: ?[]const u8 = null;
    var branch_code_evidence_id: ?[]const u8 = null;
    switch (revision.branch_code_evidence) {
        .unconfirmed => |code| {
            @memcpy(&branch_code_storage, code.asDigits());
            branch_code = &branch_code_storage;
        },
        .confirmed => |confirmation| {
            @memcpy(&branch_code_storage, confirmation.code.asDigits());
            branch_code = &branch_code_storage;
            const evidence_id = confirmation.evidence_id.asSlice();
            @memcpy(
                branch_code_evidence_storage[0..evidence_id.len],
                evidence_id,
            );
            branch_code_evidence_id =
                branch_code_evidence_storage[0..evidence_id.len];
        },
        .legacy_unresolved => |suffix| {
            const digits = suffix.asDigits();
            @memcpy(legacy_suffix_storage[0..digits.len], digits);
            legacy_suffix = legacy_suffix_storage[0..digits.len];
        },
    }
    var lifecycle_evidence_id: ?[]const u8 = null;
    if (revision.lifecycle_evidence_id) |evidence_id| {
        const raw = evidence_id.asSlice();
        @memcpy(lifecycle_evidence_storage[0..raw.len], raw);
        lifecycle_evidence_id = lifecycle_evidence_storage[0..raw.len];
    }

    try statement.bindText(1, revision.id.asSlice());
    try statement.bindText(2, revision.taxpayer_id.asSlice());
    try statement.bindText(3, revision.registration_unit_id.asSlice());
    try statement.bindInt64(4, @intCast(revision.sequence));
    try statement.bindText(5, revision.effective.from.writeIso(&effective_from));
    try statement.bindOptionalText(6, if (revision.effective.until) |until|
        until.writeIso(&effective_until)
    else
        null);
    try statement.bindText(7, @tagName(revision.kind));
    try statement.bindText(8, @tagName(revision.branch_code_evidence));
    try statement.bindOptionalText(9, branch_code);
    try statement.bindOptionalText(10, legacy_suffix);
    try statement.bindText(11, @tagName(revision.status));
    try statement.bindOptionalText(12, if (revision.rdo_code) |code|
        code.asDigits()
    else
        null);
    try statement.bindOptionalText(13, branch_code_evidence_id);
    try statement.bindOptionalText(14, lifecycle_evidence_id);
    try statement.expectDone();
}

fn insertRegistrationUnitContactRevision(
    db: *sqlite.sqlite3,
    revision: domain.RegistrationUnitContactRevision,
) Error!void {
    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_unit_contact_revisions (
        \\    id, taxpayer_id, registration_unit_id, sequence,
        \\    effective_from, effective_until, registered_address,
        \\    zip_code, contact_number, email_address, evidence_id
        \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    );
    defer statement.deinit();

    var effective_from: [10]u8 = undefined;
    var effective_until: [10]u8 = undefined;
    try statement.bindText(1, revision.id.asSlice());
    try statement.bindText(2, revision.taxpayer_id.asSlice());
    try statement.bindText(3, revision.registration_unit_id.asSlice());
    try statement.bindInt64(4, @intCast(revision.sequence));
    try statement.bindText(5, revision.effective.from.writeIso(&effective_from));
    try statement.bindOptionalText(6, if (revision.effective.until) |until|
        until.writeIso(&effective_until)
    else
        null);
    try statement.bindText(7, revision.contact.registered_address.asSlice());
    try statement.bindOptionalText(8, if (revision.contact.zip_code) |value| value.asSlice() else null);
    try statement.bindOptionalText(9, if (revision.contact.contact_number) |value| value.asSlice() else null);
    try statement.bindOptionalText(10, if (revision.contact.email_address) |value| value.asSlice() else null);
    try statement.bindText(11, revision.evidence_id.asSlice());
    try statement.expectDone();
}

fn insertConfirmedCodeLineage(
    db: *sqlite.sqlite3,
    revision: domain.RegistrationUnitRevision,
) Error!void {
    const confirmation = revision.branch_code_evidence.confirmedCode() orelse
        return error.InvalidStoredValue;
    var existing = try prepare(db,
        \\SELECT registration_unit_id
        \\FROM taxpayer_registration_branch_code_lineage
        \\WHERE taxpayer_id = ? AND branch_code = ?
        \\LIMIT 1;
    );
    defer existing.deinit();
    try existing.bindText(1, revision.taxpayer_id.asSlice());
    try existing.bindText(2, confirmation.code.asDigits());
    if (try existing.step() == .row) {
        const existing_unit_id = try registrationUnitIdFromColumn(existing.raw, 0);
        if (existing_unit_id.eql(&revision.registration_unit_id)) return;
        return error.BranchCodeLineageCannotBeReused;
    }

    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_branch_code_lineage (
        \\    taxpayer_id, branch_code, registration_unit_id, evidence_id,
        \\    unit_revision_id
        \\) VALUES (?, ?, ?, ?, ?);
    );
    defer statement.deinit();
    try statement.bindText(1, revision.taxpayer_id.asSlice());
    try statement.bindText(2, confirmation.code.asDigits());
    try statement.bindText(3, revision.registration_unit_id.asSlice());
    try statement.bindText(4, confirmation.evidence_id.asSlice());
    try statement.bindText(5, revision.id.asSlice());
    try statement.expectDone();
}

fn insertTaxTypeRegistrationShell(
    db: *sqlite.sqlite3,
    revision: domain.TaxTypeRegistrationRevision,
) Error!void {
    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_tax_type_registrations (
        \\    id, taxpayer_id, registration_unit_id
        \\) VALUES (?, ?, ?);
    );
    defer statement.deinit();
    try statement.bindText(1, revision.registration_id.asSlice());
    try statement.bindText(2, revision.taxpayer_id.asSlice());
    try statement.bindText(3, revision.registration_unit_id.asSlice());
    try statement.expectDone();
}

fn insertTaxTypeRegistrationRevision(
    db: *sqlite.sqlite3,
    revision: domain.TaxTypeRegistrationRevision,
) Error!void {
    var statement = try prepare(db,
        \\INSERT INTO taxpayer_registration_tax_type_registration_revisions (
        \\    id, registration_id, sequence, effective_from, effective_until,
        \\    tax_type, status, evidence_id
        \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    );
    defer statement.deinit();
    var effective_from: [10]u8 = undefined;
    var effective_until: [10]u8 = undefined;
    try statement.bindText(1, revision.id.asSlice());
    try statement.bindText(2, revision.registration_id.asSlice());
    try statement.bindInt64(3, @intCast(revision.sequence));
    try statement.bindText(4, revision.effective.from.writeIso(&effective_from));
    try statement.bindOptionalText(5, if (revision.effective.until) |until|
        until.writeIso(&effective_until)
    else
        null);
    try statement.bindText(6, @tagName(revision.tax_type));
    try statement.bindText(7, @tagName(revision.status));
    if (revision.evidence_id) |evidence_id| {
        try statement.bindText(8, evidence_id.asSlice());
    } else {
        try statement.bindOptionalText(8, null);
    }
    try statement.expectDone();
}

fn loadEffectiveTaxpayerIdentities(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
    as_of: domain.Date,
) Error![]domain.TaxpayerIdentityRevision {
    var statement = try prepare(db,
        \\SELECT revision.taxpayer_id, revision.id, revision.sequence,
        \\       revision.effective_from, revision.tin9, revision.evidence_id,
        \\       revision.effective_until,
        \\       (
        \\           SELECT MIN(next_revision.effective_from)
        \\           FROM taxpayer_registration_taxpayer_revisions AS next_revision
        \\           WHERE next_revision.taxpayer_id = revision.taxpayer_id
        \\             AND next_revision.effective_from > revision.effective_from
        \\       ) AS next_effective_from
        \\FROM taxpayer_registration_taxpayer_revisions AS revision
        \\JOIN (
        \\    SELECT taxpayer_id, MAX(effective_from) AS effective_from
        \\    FROM taxpayer_registration_taxpayer_revisions
        \\    WHERE effective_from <= ?
        \\    GROUP BY taxpayer_id
        \\) AS current
        \\  ON current.taxpayer_id = revision.taxpayer_id
        \\ AND current.effective_from = revision.effective_from
        \\WHERE revision.sequence = (
        \\  SELECT MAX(same_day.sequence)
        \\  FROM taxpayer_registration_taxpayer_revisions AS same_day
        \\  WHERE same_day.taxpayer_id = revision.taxpayer_id
        \\    AND same_day.effective_from = revision.effective_from
        \\)
        \\ AND (revision.effective_until IS NULL OR revision.effective_until >= ?)
        \\ORDER BY revision.taxpayer_id;
    );
    defer statement.deinit();
    var as_of_text: [10]u8 = undefined;
    const as_of_slice = as_of.writeIso(&as_of_text);
    try statement.bindText(1, as_of_slice);
    try statement.bindText(2, as_of_slice);

    var values: std.ArrayList(domain.TaxpayerIdentityRevision) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.step() == .row) {
        try values.append(
            allocator,
            try readTaxpayerIdentityRevisionWithNext(statement.raw, 7),
        );
    }
    return values.toOwnedSlice(allocator);
}

fn loadTaxpayerIdentityAt(
    db: *sqlite.sqlite3,
    taxpayer_id: domain.TaxpayerId,
    as_of: domain.Date,
) Error!?domain.TaxpayerIdentityRevision {
    var statement = try prepare(db,
        \\SELECT revision.taxpayer_id, revision.id, revision.sequence,
        \\       revision.effective_from, revision.tin9, revision.evidence_id,
        \\       revision.effective_until,
        \\       (
        \\           SELECT MIN(next_revision.effective_from)
        \\           FROM taxpayer_registration_taxpayer_revisions AS next_revision
        \\           WHERE next_revision.taxpayer_id = revision.taxpayer_id
        \\             AND next_revision.effective_from > revision.effective_from
        \\       ) AS next_effective_from
        \\FROM taxpayer_registration_taxpayer_revisions AS revision
        \\WHERE revision.taxpayer_id = ?
        \\  AND revision.effective_from = (
        \\      SELECT MAX(candidate.effective_from)
        \\      FROM taxpayer_registration_taxpayer_revisions AS candidate
        \\      WHERE candidate.taxpayer_id = revision.taxpayer_id
        \\        AND candidate.effective_from <= ?
        \\  )
        \\  AND revision.sequence = (
        \\      SELECT MAX(same_day.sequence)
        \\      FROM taxpayer_registration_taxpayer_revisions AS same_day
        \\      WHERE same_day.taxpayer_id = revision.taxpayer_id
        \\        AND same_day.effective_from = revision.effective_from
        \\  )
        \\  AND (
        \\      revision.effective_until IS NULL OR revision.effective_until >= ?
        \\  )
        \\LIMIT 1;
    );
    defer statement.deinit();
    var as_of_text: [10]u8 = undefined;
    const as_of_slice = as_of.writeIso(&as_of_text);
    try statement.bindText(1, taxpayer_id.asSlice());
    try statement.bindText(2, as_of_slice);
    try statement.bindText(3, as_of_slice);
    if (try statement.step() == .done) return null;
    return try readTaxpayerIdentityRevisionWithNext(statement.raw, 7);
}

fn loadEffectiveUnits(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
    taxpayer_id: domain.TaxpayerId,
    as_of: domain.Date,
) Error![]domain.RegistrationUnitRevision {
    var statement = try prepare(db,
        \\SELECT revision.taxpayer_id, revision.registration_unit_id,
        \\       revision.id, revision.sequence, revision.effective_from,
        \\       revision.kind, revision.branch_code_state,
        \\       revision.branch_code, revision.legacy_suffix, revision.status,
        \\       revision.rdo_code, revision.branch_code_evidence_id,
        \\       revision.lifecycle_evidence_id, revision.effective_until,
        \\       (
        \\           SELECT MIN(next_revision.effective_from)
        \\           FROM taxpayer_registration_unit_revisions AS next_revision
        \\           WHERE next_revision.registration_unit_id = revision.registration_unit_id
        \\             AND next_revision.effective_from > revision.effective_from
        \\       ) AS next_effective_from
        \\FROM taxpayer_registration_unit_revisions AS revision
        \\JOIN (
        \\    SELECT registration_unit_id, MAX(effective_from) AS effective_from
        \\    FROM taxpayer_registration_unit_revisions
        \\    WHERE taxpayer_id = ? AND effective_from <= ?
        \\    GROUP BY registration_unit_id
        \\) AS current
        \\  ON current.registration_unit_id = revision.registration_unit_id
        \\ AND current.effective_from = revision.effective_from
        \\WHERE revision.taxpayer_id = ?
        \\  AND revision.sequence = (
        \\      SELECT MAX(same_day.sequence)
        \\      FROM taxpayer_registration_unit_revisions AS same_day
        \\      WHERE same_day.registration_unit_id = revision.registration_unit_id
        \\        AND same_day.effective_from = revision.effective_from
        \\  )
        \\  AND (
        \\      revision.effective_until IS NULL OR revision.effective_until >= ?
        \\  )
        \\ORDER BY revision.registration_unit_id;
    );
    defer statement.deinit();
    var as_of_text: [10]u8 = undefined;
    const as_of_slice = as_of.writeIso(&as_of_text);
    try statement.bindText(1, taxpayer_id.asSlice());
    try statement.bindText(2, as_of_slice);
    try statement.bindText(3, taxpayer_id.asSlice());
    try statement.bindText(4, as_of_slice);

    var values: std.ArrayList(domain.RegistrationUnitRevision) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.step() == .row) {
        try values.append(
            allocator,
            try readRegistrationUnitRevisionWithNext(statement.raw, 14),
        );
    }
    return values.toOwnedSlice(allocator);
}

fn loadEffectiveRegistrationUnitContacts(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
    taxpayer_id: domain.TaxpayerId,
    as_of: domain.Date,
) Error![]domain.RegistrationUnitContactRevision {
    var statement = try prepare(db,
        \\SELECT revision.taxpayer_id, revision.registration_unit_id,
        \\    revision.id, revision.sequence, revision.effective_from,
        \\    revision.effective_until, revision.registered_address,
        \\    revision.zip_code, revision.contact_number,
        \\    revision.email_address, revision.evidence_id,
        \\    (
        \\        SELECT MIN(next_revision.effective_from)
        \\        FROM taxpayer_registration_unit_contact_revisions AS next_revision
        \\        WHERE next_revision.registration_unit_id = revision.registration_unit_id
        \\            AND next_revision.effective_from > revision.effective_from
        \\    ) AS next_effective_from
        \\FROM taxpayer_registration_unit_contact_revisions AS revision
        \\JOIN (
        \\    SELECT registration_unit_id, MAX(effective_from) AS effective_from
        \\    FROM taxpayer_registration_unit_contact_revisions
        \\    WHERE taxpayer_id = ? AND effective_from <= ?
        \\    GROUP BY registration_unit_id
        \\) AS current
        \\    ON current.registration_unit_id = revision.registration_unit_id
        \\    AND current.effective_from = revision.effective_from
        \\WHERE revision.taxpayer_id = ?
        \\    AND revision.sequence = (
        \\        SELECT MAX(same_day.sequence)
        \\        FROM taxpayer_registration_unit_contact_revisions AS same_day
        \\        WHERE same_day.registration_unit_id = revision.registration_unit_id
        \\            AND same_day.effective_from = revision.effective_from
        \\    )
        \\    AND (revision.effective_until IS NULL OR revision.effective_until >= ?)
        \\ORDER BY revision.registration_unit_id;
    );
    defer statement.deinit();

    var as_of_text: [10]u8 = undefined;
    const as_of_slice = as_of.writeIso(&as_of_text);
    try statement.bindText(1, taxpayer_id.asSlice());
    try statement.bindText(2, as_of_slice);
    try statement.bindText(3, taxpayer_id.asSlice());
    try statement.bindText(4, as_of_slice);

    var values: std.ArrayList(domain.RegistrationUnitContactRevision) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.step() == .row) {
        try values.append(
            allocator,
            try readRegistrationUnitContactRevisionWithNext(statement.raw, 11),
        );
    }
    return values.toOwnedSlice(allocator);
}

fn loadEffectiveTaxTypeRegistrations(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
    taxpayer_id: domain.TaxpayerId,
    as_of: domain.Date,
) Error![]domain.TaxTypeRegistrationRevision {
    var statement = try prepare(db,
        \\SELECT registration.taxpayer_id, registration.registration_unit_id,
        \\       registration.id, revision.id, revision.sequence,
        \\       revision.effective_from, revision.tax_type, revision.status,
        \\       revision.evidence_id, revision.effective_until,
        \\       (
        \\           SELECT MIN(next_revision.effective_from)
        \\           FROM taxpayer_registration_tax_type_registration_revisions AS next_revision
        \\           WHERE next_revision.registration_id = revision.registration_id
        \\             AND next_revision.effective_from > revision.effective_from
        \\       ) AS next_effective_from
        \\FROM taxpayer_registration_tax_type_registration_revisions AS revision
        \\JOIN taxpayer_registration_tax_type_registrations AS registration
        \\  ON registration.id = revision.registration_id
        \\JOIN (
        \\    SELECT registration_id, MAX(effective_from) AS effective_from
        \\    FROM taxpayer_registration_tax_type_registration_revisions
        \\    WHERE effective_from <= ?
        \\    GROUP BY registration_id
        \\) AS current
        \\  ON current.registration_id = revision.registration_id
        \\ AND current.effective_from = revision.effective_from
        \\WHERE registration.taxpayer_id = ?
        \\  AND revision.sequence = (
        \\      SELECT MAX(same_day.sequence)
        \\      FROM taxpayer_registration_tax_type_registration_revisions AS same_day
        \\      WHERE same_day.registration_id = revision.registration_id
        \\        AND same_day.effective_from = revision.effective_from
        \\  )
        \\  AND (
        \\      revision.effective_until IS NULL OR revision.effective_until >= ?
        \\  )
        \\ORDER BY registration.registration_unit_id, revision.tax_type,
        \\         registration.id, revision.id;
    );
    defer statement.deinit();
    var as_of_text: [10]u8 = undefined;
    const as_of_slice = as_of.writeIso(&as_of_text);
    try statement.bindText(1, as_of_slice);
    try statement.bindText(2, taxpayer_id.asSlice());
    try statement.bindText(3, as_of_slice);

    var values: std.ArrayList(domain.TaxTypeRegistrationRevision) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.step() == .row) {
        try values.append(
            allocator,
            try readTaxTypeRegistrationRevisionWithNext(statement.raw, 10),
        );
    }
    return values.toOwnedSlice(allocator);
}

fn loadUnitRevisionsOverlappingPeriod(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
    taxpayer_id: domain.TaxpayerId,
    start: domain.Date,
    end: domain.Date,
) Error![]domain.RegistrationUnitRevision {
    var statement = try prepare(db,
        \\SELECT revision.taxpayer_id, revision.registration_unit_id,
        \\       revision.id, revision.sequence, revision.effective_from,
        \\       revision.kind, revision.branch_code_state,
        \\       revision.branch_code, revision.legacy_suffix, revision.status,
        \\       revision.rdo_code, revision.branch_code_evidence_id,
        \\       revision.lifecycle_evidence_id, revision.effective_until,
        \\       (
        \\           SELECT MIN(next_revision.effective_from)
        \\           FROM taxpayer_registration_unit_revisions AS next_revision
        \\           WHERE next_revision.registration_unit_id = revision.registration_unit_id
        \\             AND next_revision.effective_from > revision.effective_from
        \\       ) AS next_effective_from
        \\FROM taxpayer_registration_unit_revisions AS revision
        \\WHERE revision.taxpayer_id = ?
        \\  AND revision.sequence = (
        \\      SELECT MAX(same_day.sequence)
        \\      FROM taxpayer_registration_unit_revisions AS same_day
        \\      WHERE same_day.registration_unit_id = revision.registration_unit_id
        \\        AND same_day.effective_from = revision.effective_from
        \\  )
        \\  AND revision.effective_from <= ?
        \\  AND MIN(
        \\      COALESCE(revision.effective_until, '9999-12-31'),
        \\      COALESCE((
        \\          SELECT date(MIN(next_revision.effective_from), '-1 day')
        \\          FROM taxpayer_registration_unit_revisions AS next_revision
        \\          WHERE next_revision.registration_unit_id = revision.registration_unit_id
        \\            AND next_revision.effective_from > revision.effective_from
        \\      ), '9999-12-31')
        \\  ) >= ?
        \\ORDER BY revision.registration_unit_id, revision.effective_from, revision.sequence;
    );
    defer statement.deinit();
    var start_text: [10]u8 = undefined;
    var end_text: [10]u8 = undefined;
    try statement.bindText(1, taxpayer_id.asSlice());
    try statement.bindText(2, end.writeIso(&end_text));
    try statement.bindText(3, start.writeIso(&start_text));

    var values: std.ArrayList(domain.RegistrationUnitRevision) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.step() == .row) {
        try values.append(allocator, try readRegistrationUnitRevisionWithNext(statement.raw, 14));
    }
    return values.toOwnedSlice(allocator);
}

fn loadRegistrationUnitContactRevisionsOverlappingPeriod(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
    taxpayer_id: domain.TaxpayerId,
    start: domain.Date,
    end: domain.Date,
) Error![]domain.RegistrationUnitContactRevision {
    var statement = try prepare(db,
        \\SELECT revision.taxpayer_id, revision.registration_unit_id,
        \\    revision.id, revision.sequence, revision.effective_from,
        \\    revision.effective_until, revision.registered_address,
        \\    revision.zip_code, revision.contact_number,
        \\    revision.email_address, revision.evidence_id,
        \\    (
        \\        SELECT MIN(next_revision.effective_from)
        \\        FROM taxpayer_registration_unit_contact_revisions AS next_revision
        \\        WHERE next_revision.registration_unit_id = revision.registration_unit_id
        \\            AND next_revision.effective_from > revision.effective_from
        \\    ) AS next_effective_from
        \\FROM taxpayer_registration_unit_contact_revisions AS revision
        \\WHERE revision.taxpayer_id = ?
        \\    AND revision.sequence = (
        \\        SELECT MAX(same_day.sequence)
        \\        FROM taxpayer_registration_unit_contact_revisions AS same_day
        \\        WHERE same_day.registration_unit_id = revision.registration_unit_id
        \\            AND same_day.effective_from = revision.effective_from
        \\    )
        \\    AND revision.effective_from <= ?
        \\    AND MIN(
        \\        COALESCE(revision.effective_until, '9999-12-31'),
        \\        COALESCE((
        \\            SELECT date(MIN(next_revision.effective_from), '-1 day')
        \\            FROM taxpayer_registration_unit_contact_revisions AS next_revision
        \\            WHERE next_revision.registration_unit_id = revision.registration_unit_id
        \\                AND next_revision.effective_from > revision.effective_from
        \\        ), '9999-12-31')
        \\    ) >= ?
        \\ORDER BY revision.registration_unit_id, revision.effective_from,
        \\    revision.sequence;
    );
    defer statement.deinit();

    var start_text: [10]u8 = undefined;
    var end_text: [10]u8 = undefined;
    try statement.bindText(1, taxpayer_id.asSlice());
    try statement.bindText(2, end.writeIso(&end_text));
    try statement.bindText(3, start.writeIso(&start_text));

    var values: std.ArrayList(domain.RegistrationUnitContactRevision) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.step() == .row) {
        try values.append(
            allocator,
            try readRegistrationUnitContactRevisionWithNext(statement.raw, 11),
        );
    }
    return values.toOwnedSlice(allocator);
}

fn loadTaxTypeRegistrationRevisionsOverlappingPeriod(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
    taxpayer_id: domain.TaxpayerId,
    start: domain.Date,
    end: domain.Date,
) Error![]domain.TaxTypeRegistrationRevision {
    var statement = try prepare(db,
        \\SELECT registration.taxpayer_id, registration.registration_unit_id,
        \\       registration.id, revision.id, revision.sequence,
        \\       revision.effective_from, revision.tax_type, revision.status,
        \\       revision.evidence_id, revision.effective_until,
        \\       (
        \\           SELECT MIN(next_revision.effective_from)
        \\           FROM taxpayer_registration_tax_type_registration_revisions AS next_revision
        \\           WHERE next_revision.registration_id = revision.registration_id
        \\             AND next_revision.effective_from > revision.effective_from
        \\       ) AS next_effective_from
        \\FROM taxpayer_registration_tax_type_registration_revisions AS revision
        \\JOIN taxpayer_registration_tax_type_registrations AS registration
        \\  ON registration.id = revision.registration_id
        \\WHERE registration.taxpayer_id = ?
        \\  AND revision.sequence = (
        \\      SELECT MAX(same_day.sequence)
        \\      FROM taxpayer_registration_tax_type_registration_revisions AS same_day
        \\      WHERE same_day.registration_id = revision.registration_id
        \\        AND same_day.effective_from = revision.effective_from
        \\  )
        \\  AND revision.effective_from <= ?
        \\  AND MIN(
        \\      COALESCE(revision.effective_until, '9999-12-31'),
        \\      COALESCE((
        \\          SELECT date(MIN(next_revision.effective_from), '-1 day')
        \\          FROM taxpayer_registration_tax_type_registration_revisions AS next_revision
        \\          WHERE next_revision.registration_id = revision.registration_id
        \\            AND next_revision.effective_from > revision.effective_from
        \\      ), '9999-12-31')
        \\  ) >= ?
        \\ORDER BY registration.registration_unit_id, revision.tax_type,
        \\         registration.id, revision.effective_from, revision.sequence;
    );
    defer statement.deinit();
    var start_text: [10]u8 = undefined;
    var end_text: [10]u8 = undefined;
    try statement.bindText(1, taxpayer_id.asSlice());
    try statement.bindText(2, end.writeIso(&end_text));
    try statement.bindText(3, start.writeIso(&start_text));

    var values: std.ArrayList(domain.TaxTypeRegistrationRevision) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.step() == .row) {
        try values.append(allocator, try readTaxTypeRegistrationRevisionWithNext(statement.raw, 10));
    }
    return values.toOwnedSlice(allocator);
}

fn loadConfirmedCodeLineage(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
    taxpayer_id: domain.TaxpayerId,
) Error![]domain.BranchCodeLineageEntry {
    var statement = try prepare(db,
        \\SELECT taxpayer_id, branch_code, registration_unit_id, evidence_id
        \\FROM taxpayer_registration_branch_code_lineage
        \\WHERE taxpayer_id = ?
        \\ORDER BY branch_code;
    );
    defer statement.deinit();
    try statement.bindText(1, taxpayer_id.asSlice());

    var values: std.ArrayList(domain.BranchCodeLineageEntry) = .empty;
    errdefer values.deinit(allocator);
    while (try statement.step() == .row) {
        try values.append(allocator, try readBranchCodeLineageEntry(statement.raw));
    }
    return values.toOwnedSlice(allocator);
}

fn readTaxpayerIdentityRevisionWithNext(
    row: *sqlite.sqlite3_stmt,
    next_effective_from_column: ?c_int,
) Error!domain.TaxpayerIdentityRevision {
    const sequence = try requiredU32(row, 2);
    const revision: domain.TaxpayerIdentityRevision = .{
        .taxpayer_id = try taxpayerIdFromColumn(row, 0),
        .id = try taxpayerRevisionIdFromColumn(row, 1),
        .sequence = sequence,
        .effective = try effectivePeriodFromStoredAndNext(
            row,
            3,
            6,
            next_effective_from_column,
        ),
        .tin_root = try tin9FromColumn(row, 4),
        .evidence_id = try optionalEvidenceIdFromColumn(row, 5),
    };
    try revision.validate();
    return revision;
}

fn readRegistrationUnitRevision(
    row: *sqlite.sqlite3_stmt,
) Error!domain.RegistrationUnitRevision {
    return readRegistrationUnitRevisionWithNext(row, null);
}

fn readRegistrationUnitRevisionWithNext(
    row: *sqlite.sqlite3_stmt,
    next_effective_from_column: ?c_int,
) Error!domain.RegistrationUnitRevision {
    const state_text = requiredText(row, 6);
    const status_text = requiredText(row, 9);
    const branch_code_evidence = if (std.mem.eql(u8, state_text, "unconfirmed"))
        domain.BranchCodeEvidenceState{ .unconfirmed = try branchCode5FromColumn(row, 7) }
    else if (std.mem.eql(u8, state_text, "confirmed"))
        domain.BranchCodeEvidenceState{ .confirmed = .{
            .code = try branchCode5FromColumn(row, 7),
            .evidence_id = try evidenceIdFromColumn(row, 11),
        } }
    else if (std.mem.eql(u8, state_text, "legacy_unresolved"))
        domain.BranchCodeEvidenceState{ .legacy_unresolved = try legacySuffixFromColumn(row, 8) }
    else
        return error.InvalidStoredValue;

    const revision: domain.RegistrationUnitRevision = .{
        .taxpayer_id = try taxpayerIdFromColumn(row, 0),
        .registration_unit_id = try registrationUnitIdFromColumn(row, 1),
        .id = try registrationUnitRevisionIdFromColumn(row, 2),
        .sequence = try requiredU32(row, 3),
        .effective = try effectivePeriodFromStoredAndNext(
            row,
            4,
            13,
            next_effective_from_column,
        ),
        .kind = std.meta.stringToEnum(
            domain.RegistrationUnitKind,
            requiredText(row, 5),
        ) orelse return error.InvalidStoredValue,
        .branch_code_evidence = branch_code_evidence,
        .status = std.meta.stringToEnum(
            domain.RegistrationUnitStatus,
            status_text,
        ) orelse return error.InvalidStoredValue,
        .rdo_code = try optionalRdoCode3FromColumn(row, 10),
        .lifecycle_evidence_id = try optionalEvidenceIdFromColumn(row, 12),
    };
    try revision.validate();
    return revision;
}

fn readRegistrationUnitContactRevisionWithNext(
    row: *sqlite.sqlite3_stmt,
    next_effective_from_column: ?c_int,
) Error!domain.RegistrationUnitContactRevision {
    const revision: domain.RegistrationUnitContactRevision = .{
        .taxpayer_id = try taxpayerIdFromColumn(row, 0),
        .registration_unit_id = try registrationUnitIdFromColumn(row, 1),
        .id = try registrationUnitContactRevisionIdFromColumn(row, 2),
        .sequence = try requiredU32(row, 3),
        .effective = try effectivePeriodFromStoredAndNext(
            row,
            4,
            5,
            next_effective_from_column,
        ),
        .contact = .{
            .registered_address = domain.field.RegisteredAddress.parse(
                requiredText(row, 6),
            ) catch return error.InvalidStoredValue,
            .zip_code = if (optionalText(row, 7)) |value|
                domain.field.ZipCode.parse(value) catch return error.InvalidStoredValue
            else
                null,
            .contact_number = if (optionalText(row, 8)) |value|
                domain.field.ContactNumber.parse(value) catch return error.InvalidStoredValue
            else
                null,
            .email_address = if (optionalText(row, 9)) |value|
                domain.field.EmailAddress.parse(value) catch return error.InvalidStoredValue
            else
                null,
        },
        .evidence_id = try evidenceIdFromColumn(row, 10),
    };
    try revision.validate();
    return revision;
}

fn readTaxTypeRegistrationRevision(
    row: *sqlite.sqlite3_stmt,
) Error!domain.TaxTypeRegistrationRevision {
    return readTaxTypeRegistrationRevisionWithNext(row, null);
}

fn readTaxTypeRegistrationRevisionWithNext(
    row: *sqlite.sqlite3_stmt,
    next_effective_from_column: ?c_int,
) Error!domain.TaxTypeRegistrationRevision {
    const revision: domain.TaxTypeRegistrationRevision = .{
        .taxpayer_id = try taxpayerIdFromColumn(row, 0),
        .registration_unit_id = try registrationUnitIdFromColumn(row, 1),
        .registration_id = try taxTypeRegistrationIdFromColumn(row, 2),
        .id = try taxTypeRegistrationRevisionIdFromColumn(row, 3),
        .sequence = try requiredU32(row, 4),
        .effective = try effectivePeriodFromStoredAndNext(
            row,
            5,
            9,
            next_effective_from_column,
        ),
        .tax_type = std.meta.stringToEnum(
            domain.TaxType,
            requiredText(row, 6),
        ) orelse return error.InvalidStoredValue,
        .status = std.meta.stringToEnum(
            domain.TaxTypeRegistrationStatus,
            requiredText(row, 7),
        ) orelse return error.InvalidStoredValue,
        .evidence_id = try optionalEvidenceIdFromColumn(row, 8),
    };
    try revision.validate();
    return revision;
}

fn readBranchCodeLineageEntry(
    row: *sqlite.sqlite3_stmt,
) Error!domain.BranchCodeLineageEntry {
    const entry: domain.BranchCodeLineageEntry = .{
        .taxpayer_id = try taxpayerIdFromColumn(row, 0),
        .registration_unit_id = try registrationUnitIdFromColumn(row, 2),
        .code = try branchCode5FromColumn(row, 1),
        .evidence_id = try evidenceIdFromColumn(row, 3),
    };
    try entry.validate();
    return entry;
}

fn requiredText(row: *sqlite.sqlite3_stmt, column: c_int) []const u8 {
    if (sqlite.sqlite3_column_type(row, column) != sqlite.SQLITE_TEXT) {
        return &.{};
    }
    const raw = sqlite.sqlite3_column_text(row, column) orelse return &.{};
    const length = sqlite.sqlite3_column_bytes(row, column);
    if (length < 0) return &.{};
    const bytes: [*]const u8 = @ptrCast(raw);
    return bytes[0..@intCast(length)];
}

fn optionalText(row: *sqlite.sqlite3_stmt, column: c_int) ?[]const u8 {
    if (sqlite.sqlite3_column_type(row, column) == sqlite.SQLITE_NULL) {
        return null;
    }
    const value = requiredText(row, column);
    if (value.len == 0) return null;
    return value;
}

fn requiredU32(row: *sqlite.sqlite3_stmt, column: c_int) Error!u32 {
    if (sqlite.sqlite3_column_type(row, column) != sqlite.SQLITE_INTEGER) {
        return error.InvalidStoredValue;
    }
    const value = sqlite.sqlite3_column_int64(row, column);
    if (value <= 0 or value > std.math.maxInt(u32)) {
        return error.InvalidStoredValue;
    }
    return @intCast(value);
}

fn nonnegativeU32(row: *sqlite.sqlite3_stmt, column: c_int) Error!u32 {
    if (sqlite.sqlite3_column_type(row, column) != sqlite.SQLITE_INTEGER) {
        return error.InvalidStoredValue;
    }
    const value = sqlite.sqlite3_column_int64(row, column);
    if (value < 0 or value > std.math.maxInt(u32)) {
        return error.InvalidStoredValue;
    }
    return @intCast(value);
}

fn taxpayerIdFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.TaxpayerId {
    return domain.TaxpayerId.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn taxpayerRevisionIdFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.TaxpayerRevisionId {
    return domain.TaxpayerRevisionId.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn registrationUnitIdFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.RegistrationUnitId {
    return domain.RegistrationUnitId.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn registrationUnitRevisionIdFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.RegistrationUnitRevisionId {
    return domain.RegistrationUnitRevisionId.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn registrationUnitContactRevisionIdFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.RegistrationUnitContactRevisionId {
    return domain.RegistrationUnitContactRevisionId.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn taxTypeRegistrationIdFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.TaxTypeRegistrationId {
    return domain.TaxTypeRegistrationId.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn taxTypeRegistrationRevisionIdFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.TaxTypeRegistrationRevisionId {
    return domain.TaxTypeRegistrationRevisionId.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn evidenceIdFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.RegistrationEvidenceId {
    return domain.RegistrationEvidenceId.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn optionalEvidenceIdFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!?domain.RegistrationEvidenceId {
    const value = optionalText(row, column) orelse return null;
    return domain.RegistrationEvidenceId.parse(value) catch
        return error.InvalidStoredValue;
}

fn tin9FromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.Tin9 {
    return domain.Tin9.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn branchCode5FromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.BranchCode5 {
    return domain.BranchCode5.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn optionalRdoCode3FromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!?domain.RdoCode3 {
    const value = optionalText(row, column) orelse return null;
    return domain.RdoCode3.parse(value) catch return error.InvalidStoredValue;
}

fn legacySuffixFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!domain.LegacyBranchSuffix {
    return domain.LegacyBranchSuffix.parse(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn dateFromColumn(row: *sqlite.sqlite3_stmt, column: c_int) Error!domain.Date {
    return domain.Date.parseIso(requiredText(row, column)) catch
        return error.InvalidStoredValue;
}

fn effectivePeriodFromStoredAndNext(
    row: *sqlite.sqlite3_stmt,
    effective_from_column: c_int,
    effective_until_column: c_int,
    next_effective_from_column: ?c_int,
) Error!domain.EffectivePeriod {
    const from = try dateFromColumn(row, effective_from_column);
    var until = try optionalDateFromColumn(row, effective_until_column);
    if (next_effective_from_column) |column| {
        if (try optionalDateFromColumn(row, column)) |next_from| {
            const derived_until = try dayBefore(next_from);
            if (until == null or derived_until.isBefore(until.?)) {
                until = derived_until;
            }
        }
    }
    return domain.EffectivePeriod.init(from, until) catch return error.InvalidStoredValue;
}

fn optionalDateFromColumn(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!?domain.Date {
    const value = optionalText(row, column) orelse return null;
    return domain.Date.parseIso(value) catch return error.InvalidStoredValue;
}

fn dayBefore(value: domain.Date) Error!domain.Date {
    if (value.day > 1) {
        return domain.Date.init(value.year, value.month, value.day - 1) catch
            return error.InvalidStoredValue;
    }
    if (value.month > 1) {
        const previous_month: u8 = value.month - 1;
        return domain.Date.init(
            value.year,
            previous_month,
            daysInMonth(value.year, previous_month),
        ) catch return error.InvalidStoredValue;
    }
    if (value.year <= 1) return error.InvalidStoredValue;
    return domain.Date.init(value.year - 1, 12, 31) catch return error.InvalidStoredValue;
}

fn daysInMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => unreachable,
    };
}

fn isLeapYear(year: u16) bool {
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
}

fn testDate(year: u16, month: u8, day: u8) domain.Date {
    return domain.Date.init(year, month, day) catch unreachable;
}

fn testTaxpayerId(raw: []const u8) domain.TaxpayerId {
    return domain.TaxpayerId.parse(raw) catch unreachable;
}

fn testTaxpayerRevisionId(raw: []const u8) domain.TaxpayerRevisionId {
    return domain.TaxpayerRevisionId.parse(raw) catch unreachable;
}

fn testUnitId(raw: []const u8) domain.RegistrationUnitId {
    return domain.RegistrationUnitId.parse(raw) catch unreachable;
}

fn testUnitRevisionId(raw: []const u8) domain.RegistrationUnitRevisionId {
    return domain.RegistrationUnitRevisionId.parse(raw) catch unreachable;
}

fn testContactRevisionId(raw: []const u8) domain.RegistrationUnitContactRevisionId {
    return domain.RegistrationUnitContactRevisionId.parse(raw) catch unreachable;
}

fn testTaxTypeRegistrationId(raw: []const u8) domain.TaxTypeRegistrationId {
    return domain.TaxTypeRegistrationId.parse(raw) catch unreachable;
}

fn testTaxTypeRegistrationRevisionId(
    raw: []const u8,
) domain.TaxTypeRegistrationRevisionId {
    return domain.TaxTypeRegistrationRevisionId.parse(raw) catch unreachable;
}

fn testEvidenceId(raw: []const u8) domain.RegistrationEvidenceId {
    return domain.RegistrationEvidenceId.parse(raw) catch unreachable;
}

fn snapshotEvidenceIssue(value: SnapshotReviewRequired) !EvidenceReviewIssue {
    return switch (value) {
        .evidence => |issue| issue,
        else => error.TestExpectedEvidenceReviewIssue,
    };
}

fn planningEvidenceIssue(value: PlanningSnapshotReviewRequired) !EvidenceReviewIssue {
    return switch (value) {
        .evidence => |issue| issue,
        else => error.TestExpectedEvidenceReviewIssue,
    };
}

fn testEvidenceAssertionId(raw: []const u8) domain.RegistrationEvidenceAssertionId {
    return domain.RegistrationEvidenceAssertionId.parse(raw) catch unreachable;
}

fn testEvidenceReviewDecisionId(
    raw: []const u8,
) domain.RegistrationEvidenceReviewDecisionId {
    return domain.RegistrationEvidenceReviewDecisionId.parse(raw) catch unreachable;
}

fn recordUnitEvidenceAssertion(
    ledger: *TaxpayerRegistrationLedger,
    assertion_id: domain.RegistrationEvidenceAssertionId,
    evidence_id: domain.RegistrationEvidenceId,
    taxpayer_id: domain.TaxpayerId,
    registration_unit_id: domain.RegistrationUnitId,
    effective_from: domain.Date,
    branch_code: domain.BranchCode5,
    status: domain.RegistrationUnitStatus,
) !void {
    try ledger.recordEvidenceAssertion(.{
        .id = assertion_id,
        .evidence_id = evidence_id,
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = registration_unit_id,
        .effective_from = effective_from,
        .fact = .{ .registration_unit = .{
            .branch_code = branch_code,
            .status = status,
        } },
    });
}

fn recordUnitEvidenceAssertionWithRdo(
    ledger: *TaxpayerRegistrationLedger,
    assertion_id: domain.RegistrationEvidenceAssertionId,
    evidence_id: domain.RegistrationEvidenceId,
    taxpayer_id: domain.TaxpayerId,
    registration_unit_id: domain.RegistrationUnitId,
    effective_from: domain.Date,
    branch_code: domain.BranchCode5,
    status: domain.RegistrationUnitStatus,
    rdo_code: domain.RdoCode3,
) !void {
    try ledger.recordEvidenceAssertion(.{
        .id = assertion_id,
        .evidence_id = evidence_id,
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = registration_unit_id,
        .effective_from = effective_from,
        .fact = .{ .registration_unit = .{
            .branch_code = branch_code,
            .status = status,
            .rdo_code = rdo_code,
        } },
    });
}

fn recordContactEvidenceAssertion(
    ledger: *TaxpayerRegistrationLedger,
    assertion_id: domain.RegistrationEvidenceAssertionId,
    evidence_id: domain.RegistrationEvidenceId,
    taxpayer_id: domain.TaxpayerId,
    registration_unit_id: domain.RegistrationUnitId,
    effective_from: domain.Date,
    contact: domain.RegistrationUnitContact,
) !void {
    try ledger.recordEvidenceAssertion(.{
        .id = assertion_id,
        .evidence_id = evidence_id,
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = registration_unit_id,
        .effective_from = effective_from,
        .fact = .{ .registration_unit_contact = contact },
    });
}

fn recordTinRootEvidenceAssertion(
    ledger: *TaxpayerRegistrationLedger,
    assertion_id: domain.RegistrationEvidenceAssertionId,
    evidence_id: domain.RegistrationEvidenceId,
    taxpayer_id: domain.TaxpayerId,
    effective_from: domain.Date,
    tin_root: domain.Tin9,
) !void {
    try ledger.recordEvidenceAssertion(.{
        .id = assertion_id,
        .evidence_id = evidence_id,
        .taxpayer_id = taxpayer_id,
        .effective_from = effective_from,
        .fact = .{ .taxpayer_tin_root = .{ .tin_root = tin_root } },
    });
}

fn recordTaxTypeEvidenceAssertion(
    ledger: *TaxpayerRegistrationLedger,
    assertion_id: domain.RegistrationEvidenceAssertionId,
    evidence_id: domain.RegistrationEvidenceId,
    taxpayer_id: domain.TaxpayerId,
    registration_unit_id: domain.RegistrationUnitId,
    effective_from: domain.Date,
    tax_type: domain.TaxType,
    status: domain.TaxTypeRegistrationStatus,
) !void {
    try ledger.recordEvidenceAssertion(.{
        .id = assertion_id,
        .evidence_id = evidence_id,
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = registration_unit_id,
        .effective_from = effective_from,
        .fact = .{ .tax_type_registration = .{
            .tax_type = tax_type,
            .status = status,
        } },
    });
}

fn evidenceMetadata(id: domain.RegistrationEvidenceId) EvidenceWrite {
    return .{
        .id = id,
        .source_kind = .cor,
        .sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        .display_name = "Reviewed registration evidence",
        .byte_size = 1,
        .captured_on = testDate(2026, 1, 1),
        .storage = .{ .protected_local_path = "/protected/test/registration-evidence.pdf" },
    };
}

fn recordPendingEvidence(
    ledger: *TaxpayerRegistrationLedger,
    id: domain.RegistrationEvidenceId,
) !void {
    try ledger.recordEvidence(evidenceMetadata(id));
}

fn acceptEvidence(
    ledger: *TaxpayerRegistrationLedger,
    id: domain.RegistrationEvidenceId,
) !void {
    try ledger.recordEvidenceReviewDecision(initialAcceptedReview(
        testEvidenceReviewDecisionId(id.asSlice()),
        id,
    ));
}

fn testReviewActor() EvidenceReviewActor {
    return .{ .service = domain.RegistrationEvidenceReviewServiceActorId.parse(
        "test-review-service",
    ) catch unreachable };
}

fn initialAcceptedReview(
    id: domain.RegistrationEvidenceReviewDecisionId,
    evidence_id: domain.RegistrationEvidenceId,
) EvidenceReviewDecisionWrite {
    return .{
        .id = id,
        .evidence_id = evidence_id,
        .state = .accepted,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 1_770_000_000,
        .reason = "Evidence accepted for registration facts",
    };
}

fn recordAcceptedEvidence(
    ledger: *TaxpayerRegistrationLedger,
    id: domain.RegistrationEvidenceId,
) !void {
    try recordPendingEvidence(ledger, id);
    try acceptEvidence(ledger, id);
}

fn fixtureIdentityForTest(
    origin: store.RegistrationFixtureDatabaseOrigin,
) store.RegistrationFixtureDirectoryIdentity {
    return switch (origin) {
        .fixture_directory => |identity| identity,
        .preexisting_or_unknown => unreachable,
    };
}

fn confirmTaxpayerTinRootForTest(
    ledger: *TaxpayerRegistrationLedger,
    current: domain.TaxpayerIdentityRevision,
    next_revision_id: domain.TaxpayerRevisionId,
    evidence_id: domain.RegistrationEvidenceId,
    assertion_id: domain.RegistrationEvidenceAssertionId,
    effective_from: domain.Date,
) !domain.TaxpayerIdentityRevision {
    try recordPendingEvidence(ledger, evidence_id);
    try recordTinRootEvidenceAssertion(
        ledger,
        assertion_id,
        evidence_id,
        current.taxpayer_id,
        effective_from,
        current.tin_root,
    );
    try acceptEvidence(ledger, evidence_id);

    const result = try ledger.apply(.{ .confirm_taxpayer_tin_root = .{
        .current = current,
        .next = .{
            .id = next_revision_id,
            .expected_history_sequence = current.sequence,
            .sequence = 0,
            .effective = .{ .from = effective_from },
        },
        .evidence_id = evidence_id,
        .observed_tin_root = current.tin_root,
    } });
    return switch (result) {
        .taxpayer_revised => |value| value,
        else => unreachable,
    };
}

/// Test-only migration seeding surface. Production artifacts expose no
/// authority constructor and therefore cannot call the private ledger path.
pub const testing = if (builtin.is_test) struct {
    pub fn applyLegacyRegistrationUnit(
        ledger: *TaxpayerRegistrationLedger,
        command: domain.ImportLegacyRegistrationUnitCommand,
    ) Error!domain.RegistrationWriteResult {
        const authority: *const LegacyMigrationCutoverAuthority =
            @ptrCast(&legacy_migration_test_authority_token);
        return ledger.applyWithLegacyMigrationAuthority(
            .{ .import_legacy_registration_unit = command },
            authority,
        );
    }
} else struct {};

test "listTaxpayerIds owns a deterministic byte-ordered result" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    var empty = try ledger.listTaxpayerIds();
    defer empty.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), empty.items.len);

    const fixtures = [_]struct {
        taxpayer_id: []const u8,
        taxpayer_revision_id: []const u8,
        tin_root: []const u8,
        head_office_id: []const u8,
        head_office_revision_id: []const u8,
    }{
        .{
            .taxpayer_id = "workspace-taxpayer-z",
            .taxpayer_revision_id = "workspace-taxpayer-z-revision",
            .tin_root = "333333333",
            .head_office_id = "workspace-taxpayer-z-head",
            .head_office_revision_id = "workspace-taxpayer-z-head-revision",
        },
        .{
            .taxpayer_id = "workspace-taxpayer-a",
            .taxpayer_revision_id = "workspace-taxpayer-a-revision",
            .tin_root = "111111111",
            .head_office_id = "workspace-taxpayer-a-head",
            .head_office_revision_id = "workspace-taxpayer-a-head-revision",
        },
        .{
            .taxpayer_id = "workspace-taxpayer-m",
            .taxpayer_revision_id = "workspace-taxpayer-m-revision",
            .tin_root = "222222222",
            .head_office_id = "workspace-taxpayer-m-head",
            .head_office_revision_id = "workspace-taxpayer-m-head-revision",
        },
    };
    for (fixtures) |fixture| {
        _ = try ledger.apply(.{ .create_taxpayer = .{
            .taxpayer_id = testTaxpayerId(fixture.taxpayer_id),
            .taxpayer_revision_id = testTaxpayerRevisionId(
                fixture.taxpayer_revision_id,
            ),
            .tin_root = try domain.Tin9.parse(fixture.tin_root),
            .effective_from = testDate(2026, 1, 1),
            .head_office_unit_id = testUnitId(fixture.head_office_id),
            .head_office_revision_id = testUnitRevisionId(
                fixture.head_office_revision_id,
            ),
        } });
    }

    var listed = try ledger.listTaxpayerIds();
    defer listed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), listed.items.len);
    try std.testing.expectEqualStrings(
        "workspace-taxpayer-a",
        listed.items[0].asSlice(),
    );
    try std.testing.expectEqualStrings(
        "workspace-taxpayer-m",
        listed.items[1].asSlice(),
    );
    try std.testing.expectEqualStrings(
        "workspace-taxpayer-z",
        listed.items[2].asSlice(),
    );
}

test "fixture-owned ledger rejects a direct write after marker removal" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    const fixture_origin = store.testing.fixtureDatabaseOrigin(.claiming);
    const fixture_identity = fixtureIdentityForTest(fixture_origin);
    try std.testing.expectEqual(
        store.RegistrationFixtureOwnershipResult.claimed_empty_ledger,
        try profile_store.ensureRegistrationFixturePreviewOwnership(fixture_origin),
    );

    var component_buffer: [128]u8 = undefined;
    const component = try store.Store.registrationFixtureDatabaseComponentName(
        fixture_identity,
        &component_buffer,
    );
    var sql_buffer: [256]u8 = undefined;
    const sql = try std.fmt.bufPrintZ(
        &sql_buffer,
        "DELETE FROM app_component_migrations WHERE component = '{s}';",
        .{component},
    );
    try store.testing.execConstraintFixture(
        &profile_store,
        sql.ptr,
    );

    var ledger = TaxpayerRegistrationLedger.init(
        std.testing.allocator,
        &profile_store,
    );
    try std.testing.expectError(error.InvalidValue, ledger.apply(.{
        .create_taxpayer = .{
            .taxpayer_id = testTaxpayerId("marker-removed-taxpayer"),
            .taxpayer_revision_id = testTaxpayerRevisionId(
                "marker-removed-taxpayer-revision",
            ),
            .tin_root = try domain.Tin9.parse("123456789"),
            .effective_from = testDate(2026, 1, 1),
            .head_office_unit_id = testUnitId("marker-removed-head"),
            .head_office_revision_id = testUnitRevisionId(
                "marker-removed-head-revision",
            ),
        },
    }));
}

test "fixture-owned ledger rejects a direct write after marker version changes" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    const fixture_origin = store.testing.fixtureDatabaseOrigin(.claiming);
    const fixture_identity = fixtureIdentityForTest(fixture_origin);
    try std.testing.expectEqual(
        store.RegistrationFixtureOwnershipResult.claimed_empty_ledger,
        try profile_store.ensureRegistrationFixturePreviewOwnership(fixture_origin),
    );

    var component_buffer: [128]u8 = undefined;
    const component = try store.Store.registrationFixtureDatabaseComponentName(
        fixture_identity,
        &component_buffer,
    );
    var sql_buffer: [256]u8 = undefined;
    const sql = try std.fmt.bufPrintZ(
        &sql_buffer,
        "UPDATE app_component_migrations SET version = 99 WHERE component = '{s}';",
        .{component},
    );
    try store.testing.execConstraintFixture(
        &profile_store,
        sql.ptr,
    );

    var ledger = TaxpayerRegistrationLedger.init(
        std.testing.allocator,
        &profile_store,
    );
    try std.testing.expectError(
        error.InvalidValue,
        ledger.recordEvidence(evidenceMetadata(testEvidenceId("changed-marker-evidence"))),
    );
}

test "fixture-owned ledger rejects a direct write after a legacy row appears" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    const fixture_origin = store.testing.fixtureDatabaseOrigin(.claiming);
    try std.testing.expectEqual(
        store.RegistrationFixtureOwnershipResult.claimed_empty_ledger,
        try profile_store.ensureRegistrationFixturePreviewOwnership(fixture_origin),
    );
    try store.testing.execConstraintFixture(
        &profile_store,
        "INSERT INTO tax_profiles(id, owner_id) " ++
            "VALUES ('late-legacy-profile', " ++
            "(SELECT id FROM tax_profile_local_owner WHERE singleton = 1));",
    );

    var ledger = TaxpayerRegistrationLedger.init(
        std.testing.allocator,
        &profile_store,
    );
    try std.testing.expectError(error.InvalidValue, ledger.apply(.{
        .create_taxpayer = .{
            .taxpayer_id = testTaxpayerId("legacy-race-taxpayer"),
            .taxpayer_revision_id = testTaxpayerRevisionId(
                "legacy-race-taxpayer-revision",
            ),
            .tin_root = try domain.Tin9.parse("987654321"),
            .effective_from = testDate(2026, 1, 1),
            .head_office_unit_id = testUnitId("legacy-race-head"),
            .head_office_revision_id = testUnitRevisionId(
                "legacy-race-head-revision",
            ),
        },
    }));
}

test "reviewed evidence bundle confirms a unit then creates VAT atomically" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("bundle-success-taxpayer");
    const head_id = testUnitId("bundle-success-head");
    const created_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId(
            "bundle-success-taxpayer-revision",
        ),
        .tin_root = try domain.Tin9.parse("123456789"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = head_id,
        .head_office_revision_id = testUnitRevisionId(
            "bundle-success-head-revision-1",
        ),
    } });
    const pending_head = switch (created_result) {
        .taxpayer_created => |value| value.head_office,
        else => unreachable,
    };

    const evidence_id = testEvidenceId("bundle-success-evidence");
    const effective_from = testDate(2026, 1, 2);
    const assertions = [_]EvidenceAssertionWrite{
        .{
            .id = testEvidenceAssertionId("bundle-success-head-assertion"),
            .evidence_id = evidence_id,
            .taxpayer_id = taxpayer_id,
            .registration_unit_id = head_id,
            .effective_from = effective_from,
            .fact = .{ .registration_unit = .{
                .branch_code = domain.BranchCode5.headOffice(),
                .status = .confirmed_active,
                .rdo_code = try domain.RdoCode3.parse("123"),
            } },
        },
        .{
            .id = testEvidenceAssertionId("bundle-success-vat-assertion"),
            .evidence_id = evidence_id,
            .taxpayer_id = taxpayer_id,
            .registration_unit_id = head_id,
            .effective_from = effective_from,
            .fact = .{ .tax_type_registration = .{
                .tax_type = .vat,
                .status = .confirmed_active,
            } },
        },
    };
    const vat_registration_id = testTaxTypeRegistrationId(
        "bundle-success-vat-registration",
    );
    const commands = [_]domain.RegistrationCommand{
        .{ .confirm_registration_unit = .{
            .current = pending_head,
            .next = .{
                .id = testUnitRevisionId("bundle-success-head-revision-2"),
                .expected_history_sequence = 1,
                .sequence = 0,
                .effective = .{ .from = effective_from },
            },
            .evidence_id = evidence_id,
            .observed_code = domain.BranchCode5.headOffice(),
            .observed_rdo_code = try domain.RdoCode3.parse("123"),
        } },
        .{ .create_tax_type_registration = .{
            .taxpayer_id = taxpayer_id,
            .registration_unit_id = head_id,
            .registration_id = vat_registration_id,
            .revision_id = testTaxTypeRegistrationRevisionId(
                "bundle-success-vat-revision-1",
            ),
            .effective_from = effective_from,
            .tax_type = .vat,
            .status = .confirmed_active,
            .evidence_id = evidence_id,
        } },
    };

    var mismatched_assertions = assertions;
    mismatched_assertions[0].fact.registration_unit.rdo_code =
        try domain.RdoCode3.parse("999");
    try std.testing.expectError(
        error.EvidenceAssertionNotAccepted,
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = evidenceMetadata(evidence_id),
            .initial_review = initialAcceptedReview(
                testEvidenceReviewDecisionId("bundle-success-review"),
                evidence_id,
            ),
            .assertions = &mismatched_assertions,
            .commands = &commands,
        }),
    );

    // Two distinct assertion IDs for the same exact fact are ambiguous
    // authority. Reject them before any dependent revision can commit, so the
    // immutable assertion set cannot poison every later snapshot.
    var duplicate_head_assertion = assertions[0];
    duplicate_head_assertion.id = testEvidenceAssertionId(
        "bundle-success-head-assertion-duplicate",
    );
    const duplicate_assertions = [_]EvidenceAssertionWrite{
        assertions[0],
        duplicate_head_assertion,
        assertions[1],
    };
    try std.testing.expectError(
        error.EvidenceAssertionNotAccepted,
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = evidenceMetadata(evidence_id),
            .initial_review = initialAcceptedReview(
                testEvidenceReviewDecisionId("bundle-success-review"),
                evidence_id,
            ),
            .assertions = &duplicate_assertions,
            .commands = &commands,
        }),
    );

    // The evidence promotion and unit revision share one transaction, so the
    // mismatched or ambiguous assertion sets leave neither authoritative
    // evidence nor a confirmation.
    var after_mismatch = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = effective_from,
        .end = effective_from,
    });
    defer after_mismatch.deinit(std.testing.allocator);
    const pending_after_mismatch = switch (after_mismatch) {
        .resolved => |value| value,
        .review_required => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 1), pending_after_mismatch.units.len);
    try std.testing.expectEqual(
        domain.RegistrationUnitStatus.pending_evidence,
        pending_after_mismatch.units[0].status,
    );
    try std.testing.expectEqual(@as(usize, 0), pending_after_mismatch.lineage.len);

    try ledger.recordReviewedEvidenceBundle(.{
        .evidence = evidenceMetadata(evidence_id),
        .initial_review = initialAcceptedReview(
            testEvidenceReviewDecisionId("bundle-success-review"),
            evidence_id,
        ),
        .assertions = &assertions,
        .commands = &commands,
    });

    var snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = effective_from,
        .end = effective_from,
    });
    defer snapshot.deinit(std.testing.allocator);
    const resolved = switch (snapshot) {
        .resolved => |value| value,
        .review_required => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 1), resolved.units.len);
    try std.testing.expect(resolved.units[0].isFilingCapable());
    try std.testing.expectEqualStrings("123", resolved.units[0].rdo_code.?.asDigits());
    try std.testing.expectEqual(@as(usize, 1), resolved.tax_type_registrations.len);
    try std.testing.expect(
        resolved.tax_type_registrations[0].registration_id.eql(
            &vat_registration_id,
        ),
    );
    try std.testing.expectEqual(
        domain.TaxTypeRegistrationStatus.confirmed_active,
        resolved.tax_type_registrations[0].status,
    );
    try std.testing.expectError(
        error.DuplicateTaxTypeRegistration,
        ledger.apply(.{ .create_tax_type_registration = .{
            .taxpayer_id = taxpayer_id,
            .registration_unit_id = head_id,
            .registration_id = testTaxTypeRegistrationId(
                "bundle-success-duplicate-vat-registration",
            ),
            .revision_id = testTaxTypeRegistrationRevisionId(
                "bundle-success-duplicate-vat-revision-1",
            ),
            .effective_from = testDate(2026, 1, 3),
            .tax_type = .vat,
            .status = .pending_evidence,
        } }),
    );

    const db = try ledger.handle();
    var audit = try prepare(db,
        \\SELECT
        \\  (SELECT COUNT(*) FROM taxpayer_registration_evidence WHERE id = ?),
        \\  (SELECT COUNT(*) FROM taxpayer_registration_evidence_review_decisions
        \\   WHERE evidence_id = ?),
        \\  (SELECT COUNT(*) FROM taxpayer_registration_evidence_assertions
        \\   WHERE evidence_id = ?);
    );
    defer audit.deinit();
    try audit.bindText(1, evidence_id.asSlice());
    try audit.bindText(2, evidence_id.asSlice());
    try audit.bindText(3, evidence_id.asSlice());
    try std.testing.expectEqual(StepResult.row, try audit.step());
    try std.testing.expectEqual(@as(i64, 1), sqlite.sqlite3_column_int64(audit.raw, 0));
    try std.testing.expectEqual(@as(i64, 1), sqlite.sqlite3_column_int64(audit.raw, 1));
    try std.testing.expectEqual(@as(i64, 2), sqlite.sqlite3_column_int64(audit.raw, 2));
}

test "reviewed evidence bundle rolls back first command when the second fails" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("bundle-rollback-taxpayer");
    const head_id = testUnitId("bundle-rollback-head");
    const created_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId(
            "bundle-rollback-taxpayer-revision",
        ),
        .tin_root = try domain.Tin9.parse("987654321"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = head_id,
        .head_office_revision_id = testUnitRevisionId(
            "bundle-rollback-head-revision-1",
        ),
    } });
    const pending_head = switch (created_result) {
        .taxpayer_created => |value| value.head_office,
        else => unreachable,
    };

    const evidence_id = testEvidenceId("bundle-rollback-evidence");
    const effective_from = testDate(2026, 1, 2);
    const assertions = [_]EvidenceAssertionWrite{.{
        .id = testEvidenceAssertionId("bundle-rollback-head-assertion"),
        .evidence_id = evidence_id,
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_id,
        .effective_from = effective_from,
        .fact = .{ .registration_unit = .{
            .branch_code = domain.BranchCode5.headOffice(),
            .status = .confirmed_active,
        } },
    }};
    const commands = [_]domain.RegistrationCommand{
        .{ .confirm_registration_unit = .{
            .current = pending_head,
            .next = .{
                .id = testUnitRevisionId("bundle-rollback-head-revision-2"),
                .expected_history_sequence = 1,
                .sequence = 0,
                .effective = .{ .from = effective_from },
            },
            .evidence_id = evidence_id,
            .observed_code = domain.BranchCode5.headOffice(),
            .observed_rdo_code = null,
        } },
        // This deliberately carries the stale pre-confirmation revision. The
        // bundle must reload the first command's uncommitted revision, reject
        // this second command, and roll back the entire evidence promotion.
        .{ .confirm_registration_unit = .{
            .current = pending_head,
            .next = .{
                .id = testUnitRevisionId("bundle-rollback-head-revision-3"),
                .expected_history_sequence = 1,
                .sequence = 0,
                .effective = .{ .from = effective_from },
            },
            .evidence_id = evidence_id,
            .observed_code = domain.BranchCode5.headOffice(),
            .observed_rdo_code = null,
        } },
    };

    try std.testing.expectError(
        error.StaleRegistrationUnitRevision,
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = evidenceMetadata(evidence_id),
            .initial_review = initialAcceptedReview(
                testEvidenceReviewDecisionId("bundle-rollback-review"),
                evidence_id,
            ),
            .assertions = &assertions,
            .commands = &commands,
        }),
    );

    var snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = effective_from,
        .end = effective_from,
    });
    defer snapshot.deinit(std.testing.allocator);
    const resolved = switch (snapshot) {
        .resolved => |value| value,
        .review_required => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 1), resolved.units.len);
    try std.testing.expectEqual(
        domain.RegistrationUnitStatus.pending_evidence,
        resolved.units[0].status,
    );
    try std.testing.expectEqual(@as(usize, 0), resolved.lineage.len);
    try std.testing.expectEqual(@as(usize, 0), resolved.tax_type_registrations.len);

    const db = try ledger.handle();
    var audit = try prepare(db,
        \\SELECT
        \\  (SELECT COUNT(*) FROM taxpayer_registration_evidence WHERE id = ?),
        \\  (SELECT COUNT(*) FROM taxpayer_registration_evidence_review_decisions
        \\   WHERE evidence_id = ?),
        \\  (SELECT COUNT(*) FROM taxpayer_registration_evidence_assertions
        \\   WHERE evidence_id = ?),
        \\  (SELECT COUNT(*) FROM taxpayer_registration_unit_revisions
        \\   WHERE registration_unit_id = ?),
        \\  (SELECT COUNT(*) FROM taxpayer_registration_branch_code_lineage
        \\   WHERE registration_unit_id = ?);
    );
    defer audit.deinit();
    try audit.bindText(1, evidence_id.asSlice());
    try audit.bindText(2, evidence_id.asSlice());
    try audit.bindText(3, evidence_id.asSlice());
    try audit.bindText(4, head_id.asSlice());
    try audit.bindText(5, head_id.asSlice());
    try std.testing.expectEqual(StepResult.row, try audit.step());
    try std.testing.expectEqual(@as(i64, 0), sqlite.sqlite3_column_int64(audit.raw, 0));
    try std.testing.expectEqual(@as(i64, 0), sqlite.sqlite3_column_int64(audit.raw, 1));
    try std.testing.expectEqual(@as(i64, 0), sqlite.sqlite3_column_int64(audit.raw, 2));
    try std.testing.expectEqual(@as(i64, 1), sqlite.sqlite3_column_int64(audit.raw, 3));
    try std.testing.expectEqual(@as(i64, 0), sqlite.sqlite3_column_int64(audit.raw, 4));
}

test "reviewed evidence bundle rejects incomplete and cross-evidence shapes" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("bundle-validation-taxpayer");
    const head_id = testUnitId("bundle-validation-head");
    const created_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId(
            "bundle-validation-taxpayer-revision",
        ),
        .tin_root = try domain.Tin9.parse("246813579"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = head_id,
        .head_office_revision_id = testUnitRevisionId(
            "bundle-validation-head-revision-1",
        ),
    } });
    const pending_head = switch (created_result) {
        .taxpayer_created => |value| value.head_office,
        else => unreachable,
    };

    const evidence_id = testEvidenceId("bundle-validation-evidence");
    const other_evidence_id = testEvidenceId("bundle-validation-other-evidence");
    const effective_from = testDate(2026, 1, 2);
    const assertions = [_]EvidenceAssertionWrite{.{
        .id = testEvidenceAssertionId("bundle-validation-assertion"),
        .evidence_id = evidence_id,
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_id,
        .effective_from = effective_from,
        .fact = .{ .registration_unit = .{
            .branch_code = domain.BranchCode5.headOffice(),
            .status = .confirmed_active,
        } },
    }};
    const commands = [_]domain.RegistrationCommand{.{
        .confirm_registration_unit = .{
            .current = pending_head,
            .next = .{
                .id = testUnitRevisionId("bundle-validation-head-revision-2"),
                .expected_history_sequence = 1,
                .sequence = 0,
                .effective = .{ .from = effective_from },
            },
            .evidence_id = evidence_id,
            .observed_code = domain.BranchCode5.headOffice(),
            .observed_rdo_code = null,
        },
    }};
    const no_assertions = [_]EvidenceAssertionWrite{};
    const no_commands = [_]domain.RegistrationCommand{};
    const evidence = evidenceMetadata(evidence_id);
    const review = initialAcceptedReview(
        testEvidenceReviewDecisionId("bundle-validation-review"),
        evidence_id,
    );

    try std.testing.expectError(
        error.InvalidReviewedEvidenceBundleWrite,
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = evidence,
            .initial_review = review,
            .assertions = &no_assertions,
            .commands = &commands,
        }),
    );
    try std.testing.expectError(
        error.InvalidReviewedEvidenceBundleWrite,
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = evidence,
            .initial_review = review,
            .assertions = &assertions,
            .commands = &no_commands,
        }),
    );

    var non_initial_review = review;
    non_initial_review.expected_history_sequence = 1;
    non_initial_review.supersedes = testEvidenceReviewDecisionId(
        "bundle-validation-prior-review",
    );
    try std.testing.expectError(
        error.InvalidReviewedEvidenceBundleWrite,
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = evidence,
            .initial_review = non_initial_review,
            .assertions = &assertions,
            .commands = &commands,
        }),
    );

    var mismatched_review = review;
    mismatched_review.evidence_id = other_evidence_id;
    try std.testing.expectError(
        error.InvalidReviewedEvidenceBundleWrite,
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = evidence,
            .initial_review = mismatched_review,
            .assertions = &assertions,
            .commands = &commands,
        }),
    );

    var mismatched_assertions = assertions;
    mismatched_assertions[0].evidence_id = other_evidence_id;
    try std.testing.expectError(
        error.InvalidReviewedEvidenceBundleWrite,
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = evidence,
            .initial_review = review,
            .assertions = &mismatched_assertions,
            .commands = &commands,
        }),
    );

    var mismatched_commands = commands;
    mismatched_commands[0].confirm_registration_unit.evidence_id =
        other_evidence_id;
    try std.testing.expectError(
        error.InvalidReviewedEvidenceBundleWrite,
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = evidence,
            .initial_review = review,
            .assertions = &assertions,
            .commands = &mismatched_commands,
        }),
    );

    const non_evidence_commands = [_]domain.RegistrationCommand{.{
        .create_branch = .{
            .taxpayer_id = taxpayer_id,
            .registration_unit_id = testUnitId("bundle-validation-branch"),
            .registration_unit_revision_id = testUnitRevisionId(
                "bundle-validation-branch-revision",
            ),
            .effective_from = effective_from,
            .candidate = domain.CandidateBranchCode.entered(
                try domain.BranchCode5.parse("00001"),
            ),
        },
    }};
    try std.testing.expectError(
        error.InvalidReviewedEvidenceBundleWrite,
        ledger.recordReviewedEvidenceBundle(.{
            .evidence = evidence,
            .initial_review = review,
            .assertions = &assertions,
            .commands = &non_evidence_commands,
        }),
    );

    const db = try ledger.handle();
    var evidence_count = try prepare(
        db,
        "SELECT COUNT(*) FROM taxpayer_registration_evidence WHERE id = ?;",
    );
    defer evidence_count.deinit();
    try evidence_count.bindText(1, evidence_id.asSlice());
    try std.testing.expectEqual(StepResult.row, try evidence_count.step());
    try std.testing.expectEqual(
        @as(i64, 0),
        sqlite.sqlite3_column_int64(evidence_count.raw, 0),
    );
}

test "ledger persists a pending head office and requires accepted evidence for confirmation" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(
        std.testing.allocator,
        &profile_store,
    );

    const taxpayer_id = testTaxpayerId("ledger-taxpayer-1");
    const create_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("ledger-taxpayer-revision-1"),
        .tin_root = try domain.Tin9.parse("123456789"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = testUnitId("ledger-head-office"),
        .head_office_revision_id = testUnitRevisionId("ledger-head-office-revision-1"),
    } });
    const created = switch (create_result) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };
    _ = try confirmTaxpayerTinRootForTest(
        &ledger,
        created.taxpayer_identity,
        testTaxpayerRevisionId("ledger-taxpayer-revision-2"),
        testEvidenceId("ledger-tin-confirmation-evidence"),
        testEvidenceAssertionId("ledger-tin-confirmation-assertion"),
        testDate(2026, 1, 2),
    );
    try std.testing.expectEqual(
        domain.RegistrationUnitStatus.pending_evidence,
        created.head_office.status,
    );

    var first_snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 1),
        .end = testDate(2026, 1, 1),
    });
    defer first_snapshot.deinit(std.testing.allocator);
    const pending = switch (first_snapshot) {
        .resolved => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 1), pending.units.len);
    try std.testing.expect(!pending.units[0].isFilingCapable());

    const confirmation: domain.RegistrationCommand = .{
        .confirm_registration_unit = .{
            .current = pending.units[0],
            .next = .{
                .id = testUnitRevisionId("ledger-head-office-revision-2"),
                .expected_history_sequence = 1,
                .sequence = 2,
                .effective = .{ .from = testDate(2026, 1, 2) },
            },
            .evidence_id = testEvidenceId("ledger-evidence-accepted"),
            .observed_code = domain.BranchCode5.headOffice(),
            .observed_rdo_code = null,
        },
    };
    try std.testing.expectError(error.EvidenceNotAccepted, ledger.apply(confirmation));

    const metadata_only_evidence_id = testEvidenceId("ledger-evidence-metadata-only");
    try ledger.recordEvidence(.{
        .id = metadata_only_evidence_id,
        .source_kind = .cor,
        .sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        .display_name = "Metadata-only BIR certificate of registration",
        .byte_size = 0,
        .captured_on = testDate(2026, 1, 1),
        .storage = .metadata_only_non_authoritative,
    });
    try std.testing.expectError(
        error.NonAuthoritativeEvidenceStorage,
        ledger.recordEvidenceReviewDecision(.{
            .id = testEvidenceReviewDecisionId("ledger-metadata-review-rejected"),
            .evidence_id = metadata_only_evidence_id,
            .state = .accepted,
            .reviewer = testReviewActor(),
            .reviewed_at_unix_seconds = 1_770_000_000,
            .reason = "Metadata alone must not become command authority",
        }),
    );

    const accepted_evidence_id = testEvidenceId("ledger-evidence-accepted");
    try recordPendingEvidence(&ledger, accepted_evidence_id);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("ledger-head-office-assertion"),
        accepted_evidence_id,
        taxpayer_id,
        created.head_office.registration_unit_id,
        testDate(2026, 1, 2),
        domain.BranchCode5.headOffice(),
        .confirmed_active,
    );
    try std.testing.expectError(error.EvidenceNotAccepted, ledger.apply(confirmation));
    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("ledger-evidence-review-accepted"),
        .evidence_id = accepted_evidence_id,
        .state = .accepted,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 1_770_000_000,
        .reason = "COR reviewed and accepted",
    });
    try std.testing.expectError(
        error.EvidenceAssertionSetFrozen,
        ledger.recordEvidenceAssertion(.{
            .id = testEvidenceAssertionId("ledger-post-review-assertion"),
            .evidence_id = accepted_evidence_id,
            .taxpayer_id = taxpayer_id,
            .registration_unit_id = created.head_office.registration_unit_id,
            .effective_from = testDate(2026, 1, 2),
            .fact = .{ .registration_unit = .{
                .branch_code = domain.BranchCode5.headOffice(),
                .status = .confirmed_active,
            } },
        }),
    );
    _ = try ledger.apply(confirmation);

    var confirmed_snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 1, 2),
    });
    defer confirmed_snapshot.deinit(std.testing.allocator);
    const confirmed = switch (confirmed_snapshot) {
        .resolved => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 1), confirmed.units.len);
    try std.testing.expectEqual(
        domain.RegistrationUnitStatus.confirmed_active,
        confirmed.units[0].status,
    );
    try std.testing.expect(confirmed.units[0].isFilingCapable());
    try std.testing.expectEqualStrings(
        "00000",
        (try confirmed.units[0].filingCode()).asDigits(),
    );
    try std.testing.expect(confirmed.units[0].rdo_code == null);
    try std.testing.expectEqual(@as(usize, 1), confirmed.lineage.len);
    try std.testing.expectEqualStrings(
        "00000",
        confirmed.lineage[0].code.asDigits(),
    );

    const VerificationProbe = struct {
        issue: ?EvidenceIntegrityReviewRequired,
        calls: usize = 0,
        path_matches: bool = true,
        digest_matches: bool = true,
        size_matches: bool = true,

        fn verify(
            context: *anyopaque,
            input: ProtectedEvidenceVerificationInput,
        ) ?EvidenceIntegrityReviewRequired {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.calls += 1;
            _ = input.evidence_id;
            self.path_matches = self.path_matches and std.mem.eql(
                u8,
                input.protected_path,
                "/protected/test/registration-evidence.pdf",
            );
            self.digest_matches = self.digest_matches and std.mem.eql(
                u8,
                input.sha256,
                "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            );
            self.size_matches = self.size_matches and input.byte_size == 1;
            return self.issue;
        }
    };
    for ([_]EvidenceIntegrityReviewRequired{
        .protected_bytes_missing,
        .protected_bytes_size_mismatch,
        .protected_bytes_digest_mismatch,
    }) |integrity_issue| {
        var probe: VerificationProbe = .{
            .issue = integrity_issue,
        };
        var checked = try ledger.snapshotWithEvidenceIntegrity(
            .{
                .taxpayer_id = taxpayer_id,
                .start = testDate(2026, 1, 2),
                .end = testDate(2026, 1, 2),
            },
            .{
                .context = &probe,
                .verify_fn = VerificationProbe.verify,
            },
        );
        defer checked.deinit(std.testing.allocator);
        try std.testing.expectEqual(
            integrity_issue,
            switch (checked) {
                .evidence_integrity_review_required => |issue| issue.cause,
                else => unreachable,
            },
        );
        try std.testing.expectEqual(@as(usize, 1), probe.calls);
        try std.testing.expect(probe.path_matches);
        try std.testing.expect(probe.digest_matches);
        try std.testing.expect(probe.size_matches);
    }

    var success_probe: VerificationProbe = .{
        .issue = null,
    };
    var integrity_checked = try ledger.snapshotWithEvidenceIntegrity(
        .{
            .taxpayer_id = taxpayer_id,
            .start = testDate(2026, 1, 2),
            .end = testDate(2026, 1, 2),
        },
        .{
            .context = &success_probe,
            .verify_fn = VerificationProbe.verify,
        },
    );
    defer integrity_checked.deinit(std.testing.allocator);
    try std.testing.expect(switch (integrity_checked) {
        .resolved => true,
        else => false,
    });
    try std.testing.expectEqual(@as(usize, 2), success_probe.calls);
    try std.testing.expect(success_probe.path_matches);
    try std.testing.expect(success_probe.digest_matches);
    try std.testing.expect(success_probe.size_matches);

    var planning_probe: VerificationProbe = .{ .issue = null };
    var planning_integrity_checked = try ledger.planningSnapshotWithEvidenceIntegrity(
        .{
            .taxpayer_id = taxpayer_id,
            .start = testDate(2026, 1, 2),
            .end = testDate(2026, 1, 2),
        },
        .{
            .context = &planning_probe,
            .verify_fn = VerificationProbe.verify,
        },
    );
    defer planning_integrity_checked.deinit(std.testing.allocator);
    try std.testing.expect(switch (planning_integrity_checked) {
        .resolved => true,
        else => false,
    });
    try std.testing.expectEqual(@as(usize, 2), planning_probe.calls);
    try std.testing.expect(planning_probe.path_matches);
    try std.testing.expect(planning_probe.digest_matches);
    try std.testing.expect(planning_probe.size_matches);

    const accepted_review_id = testEvidenceReviewDecisionId(
        "ledger-evidence-review-accepted",
    );
    const rejected_review_id = testEvidenceReviewDecisionId(
        "ledger-evidence-review-rejected",
    );
    try ledger.recordEvidenceReviewDecision(.{
        .id = rejected_review_id,
        .evidence_id = testEvidenceId("ledger-evidence-accepted"),
        .expected_history_sequence = 1,
        .state = .rejected,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 1_770_000_001,
        .reason = "Later review found the COR did not match the taxpayer",
        .contradicts = accepted_review_id,
    });

    var rejected_snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 1, 2),
    });
    defer rejected_snapshot.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        EvidenceReviewReason.rejected,
        (try snapshotEvidenceIssue(switch (rejected_snapshot) {
            .review_required => |issue| issue,
            .resolved => unreachable,
        })).reason,
    );

    var rejected_planning_snapshot = try ledger.planningSnapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 1, 2),
    });
    defer rejected_planning_snapshot.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        EvidenceReviewReason.rejected,
        (try planningEvidenceIssue(switch (rejected_planning_snapshot) {
            .review_required => |issue| issue,
            .resolved => unreachable,
        })).reason,
    );

    const reaccepted_review_id = testEvidenceReviewDecisionId(
        "ledger-evidence-review-reaccepted",
    );
    try ledger.recordEvidenceReviewDecision(.{
        .id = reaccepted_review_id,
        .evidence_id = testEvidenceId("ledger-evidence-accepted"),
        .expected_history_sequence = 2,
        .state = .accepted,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 1_770_000_002,
        .reason = "Independent review confirmed the COR belongs to the taxpayer",
        .contradicts = rejected_review_id,
    });

    var reaccepted_snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 1, 2),
    });
    defer reaccepted_snapshot.deinit(std.testing.allocator);
    switch (reaccepted_snapshot) {
        .resolved => |resolved| {
            var matching_bindings: usize = 0;
            const expected_assertion_id = testEvidenceAssertionId(
                "ledger-head-office-assertion",
            );
            for (resolved.reviewed_evidence_bindings) |binding| {
                if (!binding.evidence_id.eql(&accepted_evidence_id)) continue;
                matching_bindings += 1;
                try std.testing.expect(binding.review_decision_id.eql(
                    &reaccepted_review_id,
                ));
                try std.testing.expectEqual(@as(u32, 3), binding.review_decision_sequence);
                try std.testing.expect(binding.assertion_id.eql(&expected_assertion_id));
            }
            // The same reviewed registration-unit assertion authorizes the
            // branch-code and lifecycle fact roles without losing either role.
            try std.testing.expectEqual(@as(usize, 2), matching_bindings);
        },
        .review_required => unreachable,
    }

    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("ledger-evidence-review-superseded"),
        .evidence_id = testEvidenceId("ledger-evidence-accepted"),
        .expected_history_sequence = 3,
        .state = .superseded,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 1_770_000_003,
        .reason = "A newer reviewed COR replaces this artifact",
        .supersedes = reaccepted_review_id,
    });

    var superseded_snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 1, 2),
    });
    defer superseded_snapshot.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        EvidenceReviewReason.superseded,
        (try snapshotEvidenceIssue(switch (superseded_snapshot) {
            .review_required => |issue| issue,
            .resolved => unreachable,
        })).reason,
    );

    var superseded_planning_snapshot = try ledger.planningSnapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 1, 2),
    });
    defer superseded_planning_snapshot.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        EvidenceReviewReason.superseded,
        (try planningEvidenceIssue(switch (superseded_planning_snapshot) {
            .review_required => |issue| issue,
            .resolved => unreachable,
        })).reason,
    );

    const confirmed_evidence_id = testEvidenceId("ledger-evidence-accepted");
    const db = try ledger.handle();
    var audit_rows = try prepare(db,
        \\SELECT
        \\  (SELECT COUNT(*)
        \\   FROM taxpayer_registration_evidence_review_decisions
        \\   WHERE evidence_id = ?),
        \\  (SELECT COUNT(*)
        \\   FROM taxpayer_registration_evidence_assertions
        \\   WHERE evidence_id = ?),
        \\  (SELECT COUNT(*)
        \\   FROM taxpayer_registration_unit_revisions
        \\   WHERE registration_unit_id = ?);
    );
    defer audit_rows.deinit();
    try audit_rows.bindText(1, confirmed_evidence_id.asSlice());
    try audit_rows.bindText(2, confirmed_evidence_id.asSlice());
    try audit_rows.bindText(3, created.head_office.registration_unit_id.asSlice());
    try std.testing.expectEqual(StepResult.row, try audit_rows.step());
    try std.testing.expectEqual(@as(i64, 4), sqlite.sqlite3_column_int64(audit_rows.raw, 0));
    try std.testing.expectEqual(@as(i64, 1), sqlite.sqlite3_column_int64(audit_rows.raw, 1));
    try std.testing.expectEqual(@as(i64, 2), sqlite.sqlite3_column_int64(audit_rows.raw, 2));
}

test "ledger returns review required instead of choosing an endpoint for a range" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(
        std.testing.allocator,
        &profile_store,
    );
    var result = try ledger.snapshot(.{
        .taxpayer_id = testTaxpayerId("missing-taxpayer"),
        .start = testDate(2026, 1, 1),
        .end = testDate(2026, 1, 31),
    });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        SnapshotReviewRequired.period_spans_multiple_dates,
        switch (result) {
            .review_required => |issue| issue,
            .resolved => unreachable,
        },
    );
}

test "evidence metadata is pending until an append-only current review accepts it" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(
        std.testing.allocator,
        &profile_store,
    );

    const evidence_id = testEvidenceId("review-stream-evidence");
    try ledger.recordEvidence(evidenceMetadata(evidence_id));
    try std.testing.expectError(
        error.InvalidEvidenceReviewDecisionWrite,
        ledger.recordEvidenceReviewDecision(.{
            .id = testEvidenceReviewDecisionId("review-rejected-without-reason"),
            .evidence_id = evidence_id,
            .state = .rejected,
            .reviewer = testReviewActor(),
            .reviewed_at_unix_seconds = 1,
            .reason = "",
        }),
    );
    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("review-accepted-1"),
        .evidence_id = evidence_id,
        .state = .accepted,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 1,
        .reason = "Registration evidence accepted",
    });
    try std.testing.expectError(
        error.StaleEvidenceReviewHistory,
        ledger.recordEvidenceReviewDecision(.{
            .id = testEvidenceReviewDecisionId("review-stale-rejection"),
            .evidence_id = evidence_id,
            .expected_history_sequence = 0,
            .state = .rejected,
            .reviewer = testReviewActor(),
            .reviewed_at_unix_seconds = 2,
            .reason = "Wrong taxpayer",
        }),
    );
}

test "evidence storage references and review actor identities fail closed" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    var empty_path = evidenceMetadata(testEvidenceId("storage-empty-path"));
    empty_path.storage = .{ .protected_local_path = " \t" };
    try std.testing.expectError(
        error.InvalidEvidenceWrite,
        ledger.recordEvidence(empty_path),
    );

    var empty_blob = evidenceMetadata(testEvidenceId("storage-empty-blob"));
    empty_blob.storage = .{ .encrypted_blob_reference = "" };
    try std.testing.expectError(
        error.InvalidEvidenceWrite,
        ledger.recordEvidence(empty_blob),
    );

    var oversized_path = evidenceMetadata(testEvidenceId("storage-path-too-long"));
    oversized_path.storage = .{
        .protected_local_path = "x" ** (storage_contract.max_evidence_storage_reference_bytes + 1),
    };
    try std.testing.expectError(
        error.InvalidEvidenceWrite,
        ledger.recordEvidence(oversized_path),
    );

    var uppercase_digest = evidenceMetadata(testEvidenceId("storage-uppercase-digest"));
    uppercase_digest.sha256 =
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    try std.testing.expectError(
        error.InvalidEvidenceWrite,
        ledger.recordEvidence(uppercase_digest),
    );

    const protected_id = testEvidenceId("storage-protected-path");
    var protected = evidenceMetadata(protected_id);
    protected.storage = .{ .protected_local_path = "evidence/cor/sha256.enc" };
    try ledger.recordEvidence(protected);

    const encrypted_id = testEvidenceId("storage-encrypted-blob");
    var encrypted = evidenceMetadata(encrypted_id);
    encrypted.storage = .{ .encrypted_blob_reference = "keychain-blob:cor-1" };
    try ledger.recordEvidence(encrypted);

    var invalid_local_owner: store.OpaqueId = undefined;
    @memset(&invalid_local_owner, 'g');
    try std.testing.expectError(
        error.InvalidEvidenceReviewDecisionWrite,
        ledger.recordEvidenceReviewDecision(.{
            .id = testEvidenceReviewDecisionId("storage-invalid-local-review"),
            .evidence_id = protected_id,
            .state = .accepted,
            .reviewer = .{ .local_owner = invalid_local_owner },
            .reviewed_at_unix_seconds = 1,
            .reason = "Invalid local owner actor",
        }),
    );

    try std.testing.expectError(
        error.InvalidEvidenceReviewDecisionWrite,
        ledger.recordEvidenceReviewDecision(.{
            .id = testEvidenceReviewDecisionId("storage-empty-service-review"),
            .evidence_id = protected_id,
            .state = .accepted,
            .reviewer = .{
                .service = domain.RegistrationEvidenceReviewServiceActorId{},
            },
            .reviewed_at_unix_seconds = 1,
            .reason = "Empty service actor",
        }),
    );

    const local_owner_id = try profile_store.localOwnerId();
    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("storage-local-owner-review"),
        .evidence_id = protected_id,
        .state = .accepted,
        .reviewer = .{ .local_owner = local_owner_id },
        .reviewed_at_unix_seconds = 2,
        .reason = "Local owner reviewed protected evidence",
    });

    const db = try ledger.handle();
    var stored_shapes = try prepare(db,
        \\SELECT id, storage_reference_kind, storage_reference
        \\FROM taxpayer_registration_evidence
        \\WHERE id IN (?, ?)
        \\ORDER BY id;
    );
    defer stored_shapes.deinit();
    try stored_shapes.bindText(1, protected_id.asSlice());
    try stored_shapes.bindText(2, encrypted_id.asSlice());
    try std.testing.expectEqual(StepResult.row, try stored_shapes.step());
    try std.testing.expectEqualStrings(
        "storage-encrypted-blob",
        requiredText(stored_shapes.raw, 0),
    );
    try std.testing.expectEqualStrings(
        "encrypted_blob_reference",
        requiredText(stored_shapes.raw, 1),
    );
    try std.testing.expectEqualStrings(
        "keychain-blob:cor-1",
        requiredText(stored_shapes.raw, 2),
    );
    try std.testing.expectEqual(StepResult.row, try stored_shapes.step());
    try std.testing.expectEqualStrings(
        "storage-protected-path",
        requiredText(stored_shapes.raw, 0),
    );
    try std.testing.expectEqualStrings(
        "protected_local_path",
        requiredText(stored_shapes.raw, 1),
    );
    try std.testing.expectEqualStrings(
        "evidence/cor/sha256.enc",
        requiredText(stored_shapes.raw, 2),
    );
    try std.testing.expectEqual(StepResult.done, try stored_shapes.step());

    var stored_actor = try prepare(db,
        \\SELECT reviewer_kind, reviewer_local_owner_id, review_reason
        \\FROM taxpayer_registration_current_evidence_reviews
        \\WHERE evidence_id = ?;
    );
    defer stored_actor.deinit();
    try stored_actor.bindText(1, protected_id.asSlice());
    try std.testing.expectEqual(StepResult.row, try stored_actor.step());
    try std.testing.expectEqualStrings(
        "local_owner",
        requiredText(stored_actor.raw, 0),
    );
    try std.testing.expectEqualStrings(
        local_owner_id[0..],
        requiredText(stored_actor.raw, 1),
    );
    try std.testing.expectEqualStrings(
        "Local owner reviewed protected evidence",
        requiredText(stored_actor.raw, 2),
    );
}

test "ledger audits TIN-root correction and current review decisions fail closed" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("root-correction-ledger-taxpayer");
    const created_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("root-correction-revision-1"),
        .tin_root = try domain.Tin9.parse("123456789"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = testUnitId("root-correction-head"),
        .head_office_revision_id = testUnitRevisionId("root-correction-head-revision-1"),
    } });
    const created = switch (created_result) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };

    const evidence_id = testEvidenceId("root-correction-evidence");
    try ledger.recordEvidence(evidenceMetadata(evidence_id));
    try recordTinRootEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("root-correction-assertion"),
        evidence_id,
        taxpayer_id,
        testDate(2026, 2, 1),
        try domain.Tin9.parse("987654321"),
    );
    const correction: domain.RegistrationCommand = .{ .correct_taxpayer_tin_root = .{
        .current = created.taxpayer_identity,
        .next = .{
            .id = testTaxpayerRevisionId("root-correction-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 2, 1) },
        },
        .evidence_id = evidence_id,
        .corrected_tin_root = try domain.Tin9.parse("987654321"),
    } };
    try std.testing.expectError(error.EvidenceNotAccepted, ledger.apply(correction));
    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("root-correction-review-1"),
        .evidence_id = evidence_id,
        .state = .accepted,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 1,
        .reason = "Corrected TIN root accepted",
    });

    var stale = correction;
    stale.correct_taxpayer_tin_root.next.expected_history_sequence = 0;
    try std.testing.expectError(error.StaleTaxpayerHistory, ledger.apply(stale));
    const corrected_result = try ledger.apply(correction);
    const corrected = switch (corrected_result) {
        .taxpayer_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqualStrings("987654321", corrected.tin_root.asDigits());

    const next_evidence_id = testEvidenceId("root-correction-evidence-rejected");
    try ledger.recordEvidence(evidenceMetadata(next_evidence_id));
    try recordTinRootEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("root-correction-assertion-rejected"),
        next_evidence_id,
        taxpayer_id,
        testDate(2026, 3, 1),
        try domain.Tin9.parse("222222222"),
    );
    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("root-correction-review-accepted"),
        .evidence_id = next_evidence_id,
        .state = .accepted,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 2,
        .reason = "Replacement evidence initially accepted",
    });
    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("root-correction-review-rejected"),
        .evidence_id = next_evidence_id,
        .expected_history_sequence = 1,
        .state = .rejected,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 3,
        .reason = "Incorrect document",
        .contradicts = testEvidenceReviewDecisionId(
            "root-correction-review-accepted",
        ),
    });
    const rejected_correction: domain.RegistrationCommand = .{
        .correct_taxpayer_tin_root = .{
            .current = corrected,
            .next = .{
                .id = testTaxpayerRevisionId("root-correction-revision-3"),
                .expected_history_sequence = 2,
                .sequence = 0,
                .effective = .{ .from = testDate(2026, 3, 1) },
            },
            .evidence_id = next_evidence_id,
            .corrected_tin_root = try domain.Tin9.parse("222222222"),
        },
    };
    try std.testing.expectError(
        error.EvidenceNotAccepted,
        ledger.apply(rejected_correction),
    );
    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("root-correction-review-reaccepted"),
        .evidence_id = next_evidence_id,
        .expected_history_sequence = 2,
        .state = .accepted,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 4,
        .reason = "Correction accepted after second review",
        .contradicts = testEvidenceReviewDecisionId(
            "root-correction-review-rejected",
        ),
    });
    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("root-correction-review-superseded"),
        .evidence_id = next_evidence_id,
        .expected_history_sequence = 3,
        .state = .superseded,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 5,
        .reason = "Replaced by newer COR",
        .supersedes = testEvidenceReviewDecisionId(
            "root-correction-review-reaccepted",
        ),
    });
    try std.testing.expectError(
        error.EvidenceNotAccepted,
        ledger.apply(rejected_correction),
    );
}

test "ledger confirms and reconfirms an unchanged TIN root before planning" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("root-confirmation-ledger-taxpayer");
    const created_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("root-confirmation-revision-1"),
        .tin_root = try domain.Tin9.parse("123456789"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = testUnitId("root-confirmation-head"),
        .head_office_revision_id = testUnitRevisionId("root-confirmation-head-r1"),
    } });
    const created = switch (created_result) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };

    var before = try ledger.planningSnapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 1),
        .end = testDate(2026, 1, 1),
    });
    defer before.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        EvidenceReviewReason.missing,
        (try planningEvidenceIssue(switch (before) {
            .review_required => |reason| reason,
            else => return error.TestExpectedReviewRequired,
        })).reason,
    );

    const first_evidence = testEvidenceId("root-confirmation-evidence-1");
    try recordPendingEvidence(&ledger, first_evidence);
    try recordTinRootEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("root-confirmation-assertion-1"),
        first_evidence,
        taxpayer_id,
        testDate(2026, 1, 2),
        try domain.Tin9.parse("123456789"),
    );
    try acceptEvidence(&ledger, first_evidence);
    const confirmed_result = try ledger.apply(.{ .confirm_taxpayer_tin_root = .{
        .current = created.taxpayer_identity,
        .next = .{
            .id = testTaxpayerRevisionId("root-confirmation-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 2) },
        },
        .evidence_id = first_evidence,
        .observed_tin_root = try domain.Tin9.parse("123456789"),
    } });
    const confirmed = switch (confirmed_result) {
        .taxpayer_revised => |value| value,
        else => unreachable,
    };

    var after = try ledger.planningSnapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 1, 2),
    });
    defer after.deinit(std.testing.allocator);
    const resolved = switch (after) {
        .resolved => |value| value,
        else => return error.TestExpectedResolvedSnapshot,
    };
    try std.testing.expect(resolved.taxpayer_identity.id.eql(&confirmed.id));

    const second_evidence = testEvidenceId("root-confirmation-evidence-2");
    try recordPendingEvidence(&ledger, second_evidence);
    try recordTinRootEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("root-confirmation-assertion-2"),
        second_evidence,
        taxpayer_id,
        testDate(2026, 2, 1),
        try domain.Tin9.parse("123456789"),
    );
    try acceptEvidence(&ledger, second_evidence);
    const reconfirmed_result = try ledger.apply(.{ .confirm_taxpayer_tin_root = .{
        .current = confirmed,
        .next = .{
            .id = testTaxpayerRevisionId("root-confirmation-revision-3"),
            .expected_history_sequence = 2,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 2, 1) },
        },
        .evidence_id = second_evidence,
        .observed_tin_root = try domain.Tin9.parse("123456789"),
    } });
    const reconfirmed = switch (reconfirmed_result) {
        .taxpayer_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(u32, 3), reconfirmed.sequence);
    try std.testing.expectEqualStrings("123456789", reconfirmed.tin_root.asDigits());
}

test "ledger preserves an explicit taxpayer identity effective end" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("bounded-root-taxpayer");
    const created_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("bounded-root-r1"),
        .tin_root = try domain.Tin9.parse("159357486"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = testUnitId("bounded-root-head"),
        .head_office_revision_id = testUnitRevisionId("bounded-root-head-r1"),
    } });
    const created = switch (created_result) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };

    const evidence_id = testEvidenceId("bounded-root-evidence");
    try recordPendingEvidence(&ledger, evidence_id);
    try recordTinRootEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("bounded-root-assertion"),
        evidence_id,
        taxpayer_id,
        testDate(2026, 2, 1),
        try domain.Tin9.parse("951753864"),
    );
    try acceptEvidence(&ledger, evidence_id);
    _ = try ledger.apply(.{ .correct_taxpayer_tin_root = .{
        .current = created.taxpayer_identity,
        .next = .{
            .id = testTaxpayerRevisionId("bounded-root-r2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{
                .from = testDate(2026, 2, 1),
                .until = testDate(2026, 2, 28),
            },
        },
        .evidence_id = evidence_id,
        .corrected_tin_root = try domain.Tin9.parse("951753864"),
    } });

    var on_last_day = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 2, 28),
        .end = testDate(2026, 2, 28),
    });
    defer on_last_day.deinit(std.testing.allocator);
    const resolved = switch (on_last_day) {
        .resolved => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(
        testDate(2026, 2, 28),
        resolved.taxpayer_identity.effective.until.?,
    );

    var after_end = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 3, 1),
        .end = testDate(2026, 3, 1),
    });
    defer after_end.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        SnapshotReviewRequired.taxpayer_identity_missing,
        switch (after_end) {
            .review_required => |issue| issue,
            .resolved => unreachable,
        },
    );
}

test "ledger transfer requires an exact destination-RDO assertion" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("transfer-ledger-taxpayer");
    const head_id = testUnitId("transfer-ledger-head");
    const created_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("transfer-ledger-taxpayer-revision"),
        .tin_root = try domain.Tin9.parse("123456789"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = head_id,
        .head_office_revision_id = testUnitRevisionId("transfer-ledger-head-revision-1"),
    } });
    const pending_head = switch (created_result) {
        .taxpayer_created => |value| value.head_office,
        else => unreachable,
    };
    const confirmation_evidence = testEvidenceId("transfer-ledger-confirmation-evidence");
    try recordPendingEvidence(&ledger, confirmation_evidence);
    // A reviewed registration assertion with the right branch, status, and
    // effective date still cannot confirm a different observed RDO.
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("transfer-ledger-confirmation-assertion"),
        confirmation_evidence,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 2),
        domain.BranchCode5.headOffice(),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, confirmation_evidence);
    const confirmation: domain.RegistrationCommand = .{ .confirm_registration_unit = .{
        .current = pending_head,
        .next = .{
            .id = testUnitRevisionId("transfer-ledger-head-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 2) },
        },
        .evidence_id = confirmation_evidence,
        .observed_code = domain.BranchCode5.headOffice(),
        .observed_rdo_code = try domain.RdoCode3.parse("123"),
    } };
    try std.testing.expectError(
        error.EvidenceAssertionNotAccepted,
        ledger.apply(confirmation),
    );
    try std.testing.expectError(
        error.EvidenceAssertionSetFrozen,
        recordUnitEvidenceAssertionWithRdo(
            &ledger,
            testEvidenceAssertionId("transfer-ledger-frozen-rdo-assertion"),
            confirmation_evidence,
            taxpayer_id,
            head_id,
            testDate(2026, 1, 2),
            domain.BranchCode5.headOffice(),
            .confirmed_active,
            try domain.RdoCode3.parse("123"),
        ),
    );
    const valid_confirmation_evidence = testEvidenceId(
        "transfer-ledger-valid-confirmation-evidence",
    );
    try recordPendingEvidence(&ledger, valid_confirmation_evidence);
    try recordUnitEvidenceAssertionWithRdo(
        &ledger,
        testEvidenceAssertionId("transfer-ledger-confirmation-rdo-assertion"),
        valid_confirmation_evidence,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 2),
        domain.BranchCode5.headOffice(),
        .confirmed_active,
        try domain.RdoCode3.parse("123"),
    );
    try acceptEvidence(&ledger, valid_confirmation_evidence);
    var valid_confirmation = confirmation;
    valid_confirmation.confirm_registration_unit.evidence_id = valid_confirmation_evidence;
    const confirmed_result = try ledger.apply(valid_confirmation);
    const confirmed = switch (confirmed_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqualStrings("123", confirmed.rdo_code.?.asDigits());

    const transfer_evidence = testEvidenceId("transfer-ledger-destination-evidence");
    try recordPendingEvidence(&ledger, transfer_evidence);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("transfer-ledger-missing-rdo-assertion"),
        transfer_evidence,
        taxpayer_id,
        head_id,
        testDate(2026, 2, 1),
        domain.BranchCode5.headOffice(),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, transfer_evidence);
    const transfer: domain.RegistrationCommand = .{ .transfer_registration_unit = .{
        .current = confirmed,
        .next = .{
            .id = testUnitRevisionId("transfer-ledger-head-revision-3"),
            .expected_history_sequence = 2,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 2, 1) },
        },
        .evidence_id = transfer_evidence,
        .destination_rdo_code = try domain.RdoCode3.parse("456"),
    } };
    try std.testing.expectError(
        error.EvidenceAssertionNotAccepted,
        ledger.apply(transfer),
    );
    try std.testing.expectError(
        error.EvidenceAssertionSetFrozen,
        recordUnitEvidenceAssertionWithRdo(
            &ledger,
            testEvidenceAssertionId("transfer-ledger-frozen-destination-rdo"),
            transfer_evidence,
            taxpayer_id,
            head_id,
            testDate(2026, 2, 1),
            domain.BranchCode5.headOffice(),
            .confirmed_active,
            try domain.RdoCode3.parse("456"),
        ),
    );
    const valid_transfer_evidence = testEvidenceId("transfer-ledger-valid-destination");
    try recordPendingEvidence(&ledger, valid_transfer_evidence);
    try recordUnitEvidenceAssertionWithRdo(
        &ledger,
        testEvidenceAssertionId("transfer-ledger-destination-rdo-assertion"),
        valid_transfer_evidence,
        taxpayer_id,
        head_id,
        testDate(2026, 2, 1),
        domain.BranchCode5.headOffice(),
        .confirmed_active,
        try domain.RdoCode3.parse("456"),
    );
    try acceptEvidence(&ledger, valid_transfer_evidence);
    var valid_transfer = transfer;
    valid_transfer.transfer_registration_unit.evidence_id = valid_transfer_evidence;
    const transferred_result = try ledger.apply(valid_transfer);
    const transferred = switch (transferred_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqualStrings("456", transferred.rdo_code.?.asDigits());
}

test "closed branch corrections accept closed assertions and retain same-unit lineage" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("closed-correction-taxpayer");
    _ = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("closed-correction-taxpayer-revision"),
        .tin_root = try domain.Tin9.parse("741852963"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = testUnitId("closed-correction-head"),
        .head_office_revision_id = testUnitRevisionId("closed-correction-head-revision"),
    } });

    const branch_id = testUnitId("closed-correction-branch");
    const branch_result = try ledger.apply(.{ .create_branch = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = branch_id,
        .registration_unit_revision_id = testUnitRevisionId("closed-correction-branch-r1"),
        .effective_from = testDate(2026, 1, 1),
        .candidate = .entered(try domain.BranchCode5.parse("00001")),
    } });
    const pending = switch (branch_result) {
        .unit_created => |value| value,
        else => unreachable,
    };

    const confirmation_evidence = testEvidenceId("closed-correction-confirmation");
    try recordPendingEvidence(&ledger, confirmation_evidence);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("closed-correction-confirmation-assertion"),
        confirmation_evidence,
        taxpayer_id,
        branch_id,
        testDate(2026, 1, 2),
        try domain.BranchCode5.parse("00001"),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, confirmation_evidence);
    const confirmation_result = try ledger.apply(.{ .confirm_registration_unit = .{
        .current = pending,
        .next = .{
            .id = testUnitRevisionId("closed-correction-branch-r2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 2) },
        },
        .evidence_id = confirmation_evidence,
        .observed_code = try domain.BranchCode5.parse("00001"),
        .observed_rdo_code = null,
    } });
    const confirmed = switch (confirmation_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };

    const closure_evidence = testEvidenceId("closed-correction-closure");
    try recordPendingEvidence(&ledger, closure_evidence);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("closed-correction-closure-assertion"),
        closure_evidence,
        taxpayer_id,
        branch_id,
        testDate(2026, 2, 1),
        try domain.BranchCode5.parse("00001"),
        .confirmed_closed,
    );
    try acceptEvidence(&ledger, closure_evidence);
    const closure_result = try ledger.apply(.{ .close_registration_unit = .{
        .current = confirmed,
        .next = .{
            .id = testUnitRevisionId("closed-correction-branch-r3"),
            .expected_history_sequence = 2,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 2, 1) },
        },
        .evidence_id = closure_evidence,
    } });
    const closed = switch (closure_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };

    const first_correction_evidence = testEvidenceId("closed-correction-first");
    try recordPendingEvidence(&ledger, first_correction_evidence);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("closed-correction-first-assertion"),
        first_correction_evidence,
        taxpayer_id,
        branch_id,
        testDate(2026, 2, 2),
        try domain.BranchCode5.parse("00002"),
        .confirmed_closed,
    );
    try acceptEvidence(&ledger, first_correction_evidence);
    const first_correction_result = try ledger.apply(.{ .correct_branch_code = .{
        .current = closed,
        .next = .{
            .id = testUnitRevisionId("closed-correction-branch-r4"),
            .expected_history_sequence = 3,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 2, 2) },
        },
        .evidence_id = first_correction_evidence,
        .corrected_code = try domain.BranchCode5.parse("00002"),
    } });
    const first_correction = switch (first_correction_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(
        domain.RegistrationUnitStatus.confirmed_closed,
        first_correction.status,
    );

    const return_evidence = testEvidenceId("closed-correction-return");
    try recordPendingEvidence(&ledger, return_evidence);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("closed-correction-return-assertion"),
        return_evidence,
        taxpayer_id,
        branch_id,
        testDate(2026, 2, 3),
        try domain.BranchCode5.parse("00001"),
        .confirmed_closed,
    );
    try acceptEvidence(&ledger, return_evidence);
    const returned_result = try ledger.apply(.{ .correct_branch_code = .{
        .current = first_correction,
        .next = .{
            .id = testUnitRevisionId("closed-correction-branch-r5"),
            .expected_history_sequence = 4,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 2, 3) },
        },
        .evidence_id = return_evidence,
        .corrected_code = try domain.BranchCode5.parse("00001"),
    } });
    const returned = switch (returned_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqualStrings(
        "00001",
        returned.branch_code_evidence.confirmedCode().?.code.asDigits(),
    );

    var snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 2, 3),
        .end = testDate(2026, 2, 3),
    });
    defer snapshot.deinit(std.testing.allocator);
    const resolved = switch (snapshot) {
        .resolved => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 2), resolved.lineage.len);
}

test "ledger rejects confirmed-active tax registration for pending unit" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("pending-vat-ledger-taxpayer");
    const head_id = testUnitId("pending-vat-ledger-head-office");
    _ = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId(
            "pending-vat-ledger-taxpayer-revision",
        ),
        .tin_root = try domain.Tin9.parse("987654321"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = head_id,
        .head_office_revision_id = testUnitRevisionId(
            "pending-vat-ledger-head-revision-1",
        ),
    } });

    const evidence_id = testEvidenceId("pending-vat-ledger-evidence");
    try recordPendingEvidence(&ledger, evidence_id);
    try recordTaxTypeEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("pending-vat-ledger-assertion"),
        evidence_id,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 1),
        .vat,
        .confirmed_active,
    );
    try acceptEvidence(&ledger, evidence_id);

    try std.testing.expectError(
        error.TaxTypeRegistrationRequiresActiveUnit,
        ledger.apply(.{ .create_tax_type_registration = .{
            .taxpayer_id = taxpayer_id,
            .registration_unit_id = head_id,
            .registration_id = testTaxTypeRegistrationId(
                "pending-vat-ledger-registration",
            ),
            .revision_id = testTaxTypeRegistrationRevisionId(
                "pending-vat-ledger-registration-revision-1",
            ),
            .effective_from = testDate(2026, 1, 1),
            .tax_type = .vat,
            .status = .confirmed_active,
            .evidence_id = evidence_id,
        } }),
    );

    const db = try ledger.handle();
    var count = try prepare(db,
        \\SELECT COUNT(*)
        \\FROM taxpayer_registration_tax_type_registrations
        \\WHERE taxpayer_id = ? AND registration_unit_id = ?;
    );
    defer count.deinit();
    try count.bindText(1, taxpayer_id.asSlice());
    try count.bindText(2, head_id.asSlice());
    try std.testing.expectEqual(StepResult.row, try count.step());
    try std.testing.expectEqual(@as(i64, 0), sqlite.sqlite3_column_int64(count.raw, 0));
}

test "ledger persists typed tax registrations and retains mid-period revision history" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("vat-ledger-taxpayer");
    const head_id = testUnitId("vat-ledger-head-office");
    const created_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("vat-ledger-taxpayer-revision"),
        .tin_root = try domain.Tin9.parse("987654321"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = head_id,
        .head_office_revision_id = testUnitRevisionId("vat-ledger-head-revision-1"),
    } });
    const created = switch (created_result) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };
    const pending_head = created.head_office;
    _ = try confirmTaxpayerTinRootForTest(
        &ledger,
        created.taxpayer_identity,
        testTaxpayerRevisionId("vat-ledger-taxpayer-revision-2"),
        testEvidenceId("vat-ledger-tin-evidence"),
        testEvidenceAssertionId("vat-ledger-tin-assertion"),
        testDate(2026, 1, 2),
    );

    const head_evidence_id = testEvidenceId("vat-ledger-head-evidence");
    try recordPendingEvidence(&ledger, head_evidence_id);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("vat-ledger-head-assertion"),
        head_evidence_id,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 2),
        domain.BranchCode5.headOffice(),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, head_evidence_id);
    _ = try ledger.apply(.{ .confirm_registration_unit = .{
        .current = pending_head,
        .next = .{
            .id = testUnitRevisionId("vat-ledger-head-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 2) },
        },
        .evidence_id = head_evidence_id,
        .observed_code = domain.BranchCode5.headOffice(),
        .observed_rdo_code = null,
    } });

    const registration_id = testTaxTypeRegistrationId("vat-registration");
    const first_revision_id = testTaxTypeRegistrationRevisionId("vat-registration-revision-1");
    const first_evidence_id = testEvidenceId("vat-registration-evidence-1");
    const create_vat: domain.RegistrationCommand = .{ .create_tax_type_registration = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_id,
        .registration_id = registration_id,
        .revision_id = first_revision_id,
        .effective_from = testDate(2026, 1, 2),
        .tax_type = .vat,
        .status = .confirmed_active,
        .evidence_id = first_evidence_id,
    } };
    try std.testing.expectError(error.EvidenceNotAccepted, ledger.apply(create_vat));

    try recordPendingEvidence(&ledger, first_evidence_id);
    try recordTaxTypeEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("vat-registration-assertion-1"),
        first_evidence_id,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 2),
        .vat,
        .confirmed_active,
    );
    try acceptEvidence(&ledger, first_evidence_id);
    const first_result = try ledger.apply(create_vat);
    const first_revision = switch (first_result) {
        .tax_type_registration_created => |value| value,
        else => unreachable,
    };
    try std.testing.expect(first_revision.registration_id.eql(&registration_id));
    try std.testing.expect(first_revision.id.eql(&first_revision_id));
    try std.testing.expectEqual(domain.TaxType.vat, first_revision.tax_type);
    try std.testing.expectEqual(domain.TaxTypeRegistrationStatus.confirmed_active, first_revision.status);

    const second_evidence_id = testEvidenceId("vat-registration-evidence-2");
    try recordPendingEvidence(&ledger, second_evidence_id);
    try recordTaxTypeEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("vat-registration-assertion-2"),
        second_evidence_id,
        taxpayer_id,
        head_id,
        testDate(2026, 5, 1),
        .vat,
        .confirmed_active,
    );
    try acceptEvidence(&ledger, second_evidence_id);
    const second_revision_id = testTaxTypeRegistrationRevisionId("vat-registration-revision-2");
    const second_result = try ledger.apply(.{ .revise_tax_type_registration = .{
        .current = first_revision,
        .next = .{
            .id = second_revision_id,
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{
                .from = testDate(2026, 5, 1),
                .until = testDate(2026, 6, 15),
            },
        },
        .status = .confirmed_active,
        .evidence_id = second_evidence_id,
    } });
    const second_revision = switch (second_result) {
        .tax_type_registration_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(u32, 2), second_revision.sequence);

    var april_snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 4, 30),
        .end = testDate(2026, 4, 30),
    });
    defer april_snapshot.deinit(std.testing.allocator);
    const april = switch (april_snapshot) {
        .resolved => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 1), april.tax_type_registrations.len);
    try std.testing.expect(april.tax_type_registrations[0].id.eql(&first_revision_id));
    try std.testing.expect(april.tax_type_registrations[0].evidence_id.?.eql(&first_evidence_id));

    var period_snapshot = try ledger.planningSnapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 4, 1),
        .end = testDate(2026, 6, 30),
    });
    defer period_snapshot.deinit(std.testing.allocator);
    const period = switch (period_snapshot) {
        .resolved => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 2), period.tax_type_registrations.len);
    try std.testing.expect(period.tax_type_registrations[0].id.eql(&first_revision_id));
    try std.testing.expect(period.tax_type_registrations[1].id.eql(&second_revision_id));
    try std.testing.expectEqual(testDate(2026, 4, 30), period.tax_type_registrations[0].effective.until.?);
    try std.testing.expectEqual(
        testDate(2026, 6, 15),
        period.tax_type_registrations[1].effective.until.?,
    );

    var after_bounded_revision = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 6, 16),
        .end = testDate(2026, 6, 16),
    });
    defer after_bounded_revision.deinit(std.testing.allocator);
    const after_bounded = switch (after_bounded_revision) {
        .resolved => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 0), after_bounded.tax_type_registrations.len);
}

test "same-day tax-type correction resolves only highest append sequence" {
    const allocator = std.testing.allocator;
    var profile_store = try store.Store.openMemory(allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(allocator, &profile_store);

    const effective_from = testDate(2026, 1, 1);
    const taxpayer_id = testTaxpayerId("same-day-tax-type-taxpayer");
    const head_id = testUnitId("same-day-tax-type-head");
    _ = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId(
            "same-day-tax-type-taxpayer-revision-1",
        ),
        .tin_root = try domain.Tin9.parse("753951486"),
        .effective_from = effective_from,
        .head_office_unit_id = head_id,
        .head_office_revision_id = testUnitRevisionId(
            "same-day-tax-type-head-revision-1",
        ),
    } });

    const registration_id = testTaxTypeRegistrationId(
        "same-day-tax-type-registration",
    );
    const first_result = try ledger.apply(.{ .create_tax_type_registration = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_id,
        .registration_id = registration_id,
        .revision_id = testTaxTypeRegistrationRevisionId(
            "same-day-tax-type-revision-1",
        ),
        .effective_from = effective_from,
        .tax_type = .vat,
        .status = .pending_evidence,
    } });
    const first = switch (first_result) {
        .tax_type_registration_created => |value| value,
        else => unreachable,
    };

    const second_id = testTaxTypeRegistrationRevisionId(
        "same-day-tax-type-revision-2",
    );
    const second_result = try ledger.apply(.{ .revise_tax_type_registration = .{
        .current = first,
        .next = .{
            .id = second_id,
            .expected_history_sequence = first.sequence,
            .sequence = 0,
            .effective = .{ .from = effective_from },
        },
        .status = .pending_evidence,
    } });
    const second = switch (second_result) {
        .tax_type_registration_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(u32, 2), second.sequence);

    var snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = effective_from,
        .end = effective_from,
    });
    defer snapshot.deinit(allocator);
    const resolved = switch (snapshot) {
        .resolved => |value| value,
        .review_required => return error.TestExpectedResolvedSnapshot,
    };
    try std.testing.expectEqual(
        @as(usize, 1),
        resolved.tax_type_registrations.len,
    );
    try std.testing.expect(
        resolved.tax_type_registrations[0].id.eql(&second_id),
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        resolved.tax_type_registrations[0].sequence,
    );
}

test "ledger keeps equal branch-code candidates pending until one is evidence-confirmed" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("candidate-taxpayer");
    _ = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("candidate-taxpayer-revision"),
        .tin_root = try domain.Tin9.parse("123456789"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = testUnitId("candidate-head-office"),
        .head_office_revision_id = testUnitRevisionId("candidate-head-revision-1"),
    } });

    const first_branch_id = testUnitId("candidate-branch-first");
    const first_branch_result = try ledger.apply(.{ .create_branch = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = first_branch_id,
        .registration_unit_revision_id = testUnitRevisionId("candidate-branch-first-revision-1"),
        .effective_from = testDate(2026, 1, 1),
        .candidate = .entered(try domain.BranchCode5.parse("00001")),
    } });
    const first_branch = switch (first_branch_result) {
        .unit_created => |value| value,
        else => unreachable,
    };

    const second_branch_id = testUnitId("candidate-branch-second");
    const second_branch_result = try ledger.apply(.{ .create_branch = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = second_branch_id,
        .registration_unit_revision_id = testUnitRevisionId("candidate-branch-second-revision-1"),
        .effective_from = testDate(2026, 1, 1),
        .candidate = .entered(try domain.BranchCode5.parse("00001")),
    } });
    const second_branch = switch (second_branch_result) {
        .unit_created => |value| value,
        else => unreachable,
    };

    const first_evidence_id = testEvidenceId("candidate-branch-first-evidence");
    try recordPendingEvidence(&ledger, first_evidence_id);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("candidate-branch-first-assertion"),
        first_evidence_id,
        taxpayer_id,
        first_branch_id,
        testDate(2026, 1, 2),
        try domain.BranchCode5.parse("00001"),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, first_evidence_id);
    _ = try ledger.apply(.{ .confirm_registration_unit = .{
        .current = first_branch,
        .next = .{
            .id = testUnitRevisionId("candidate-branch-first-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 2) },
        },
        .evidence_id = first_evidence_id,
        .observed_code = try domain.BranchCode5.parse("00001"),
        .observed_rdo_code = null,
    } });

    var snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 1, 2),
    });
    defer snapshot.deinit(std.testing.allocator);
    const resolved = switch (snapshot) {
        .resolved => |value| value,
        else => unreachable,
    };
    var confirmed_count: usize = 0;
    var pending_count: usize = 0;
    for (resolved.units) |unit| {
        if (unit.registration_unit_id.eql(&first_branch_id)) {
            try std.testing.expectEqual(domain.RegistrationUnitStatus.confirmed_active, unit.status);
            confirmed_count += 1;
        }
        if (unit.registration_unit_id.eql(&second_branch_id)) {
            try std.testing.expectEqual(domain.RegistrationUnitStatus.pending_evidence, unit.status);
            try std.testing.expect(!unit.isFilingCapable());
            pending_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), confirmed_count);
    try std.testing.expectEqual(@as(usize, 1), pending_count);

    const second_evidence_id = testEvidenceId("candidate-branch-second-evidence");
    try recordAcceptedEvidence(&ledger, second_evidence_id);
    try std.testing.expectError(
        error.DuplicateEffectiveBranchCode,
        ledger.apply(.{ .confirm_registration_unit = .{
            .current = second_branch,
            .next = .{
                .id = testUnitRevisionId("candidate-branch-second-revision-2"),
                .expected_history_sequence = 1,
                .sequence = 0,
                .effective = .{ .from = testDate(2026, 1, 2) },
            },
            .evidence_id = second_evidence_id,
            .observed_code = try domain.BranchCode5.parse("00001"),
            .observed_rdo_code = null,
        } }),
    );
}

test "ledger allocates append sequence from global history while permitting a backdated revision" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("history-taxpayer");
    _ = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("history-taxpayer-revision"),
        .tin_root = try domain.Tin9.parse("456789123"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = testUnitId("history-head-office"),
        .head_office_revision_id = testUnitRevisionId("history-head-revision-1"),
    } });

    const branch_id = testUnitId("history-branch");
    const created_result = try ledger.apply(.{ .create_branch = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = branch_id,
        .registration_unit_revision_id = testUnitRevisionId("history-branch-revision-1"),
        .effective_from = testDate(2026, 1, 1),
        .candidate = .entered(try domain.BranchCode5.parse("00001")),
    } });
    const initial = switch (created_result) {
        .unit_created => |value| value,
        else => unreachable,
    };

    const confirmation_evidence_id = testEvidenceId("history-confirmation-evidence");
    try recordPendingEvidence(&ledger, confirmation_evidence_id);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("history-confirmation-assertion"),
        confirmation_evidence_id,
        taxpayer_id,
        branch_id,
        testDate(2026, 3, 1),
        try domain.BranchCode5.parse("00001"),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, confirmation_evidence_id);
    const confirmation_result = try ledger.apply(.{ .confirm_registration_unit = .{
        .current = initial,
        .next = .{
            .id = testUnitRevisionId("history-branch-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 3, 1) },
        },
        .evidence_id = confirmation_evidence_id,
        .observed_code = try domain.BranchCode5.parse("00001"),
        .observed_rdo_code = null,
    } });
    const confirmed = switch (confirmation_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(u32, 2), confirmed.sequence);

    const backdated_result = try ledger.apply(.{ .replace_candidate_branch_code = .{
        .current = initial,
        .next = .{
            .id = testUnitRevisionId("history-branch-revision-3"),
            .expected_history_sequence = 2,
            .sequence = 0,
            .effective = .{
                .from = testDate(2026, 2, 1),
                .until = testDate(2026, 2, 15),
            },
        },
        .candidate = .entered(try domain.BranchCode5.parse("00002")),
    } });
    const backdated = switch (backdated_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(u32, 3), backdated.sequence);
    try std.testing.expectEqual(testDate(2026, 2, 15), backdated.effective.until.?);

    var after_bounded_candidate = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 2, 16),
        .end = testDate(2026, 2, 16),
    });
    defer after_bounded_candidate.deinit(std.testing.allocator);
    const after_bounded = switch (after_bounded_candidate) {
        .resolved => |value| value,
        else => unreachable,
    };
    for (after_bounded.units) |unit| {
        try std.testing.expect(!unit.registration_unit_id.eql(&branch_id));
    }

    const correction_evidence_id = testEvidenceId("history-correction-evidence");
    try recordPendingEvidence(&ledger, correction_evidence_id);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("history-correction-assertion"),
        correction_evidence_id,
        taxpayer_id,
        branch_id,
        testDate(2026, 4, 1),
        try domain.BranchCode5.parse("00003"),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, correction_evidence_id);
    const stale_correction: domain.RegistrationCommand = .{ .correct_branch_code = .{
        .current = confirmed,
        .next = .{
            .id = testUnitRevisionId("history-branch-revision-4"),
            .expected_history_sequence = 2,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 4, 1) },
        },
        .evidence_id = correction_evidence_id,
        .corrected_code = try domain.BranchCode5.parse("00003"),
    } };
    try std.testing.expectError(error.StaleRegistrationUnitHistory, ledger.apply(stale_correction));

    var current_correction = stale_correction;
    current_correction.correct_branch_code.next.expected_history_sequence = 3;
    const corrected_result = try ledger.apply(current_correction);
    const corrected = switch (corrected_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(u32, 4), corrected.sequence);

    var snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 4, 1),
        .end = testDate(2026, 4, 1),
    });
    defer snapshot.deinit(std.testing.allocator);
    const resolved = switch (snapshot) {
        .resolved => |value| value,
        else => unreachable,
    };
    for (resolved.units) |unit| {
        if (unit.registration_unit_id.eql(&branch_id)) {
            try std.testing.expect(unit.id.eql(&corrected.id));
            try std.testing.expectEqual(@as(u32, 4), unit.sequence);
            return;
        }
    }
    return error.TestExpectedBranch;
}

test "ledger-backed planner resolves a coherent head-office 2550Q scope" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("planner-ledger-taxpayer");
    const head_id = testUnitId("planner-ledger-head-office");
    const taxpayer_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("planner-ledger-taxpayer-revision"),
        .tin_root = try domain.Tin9.parse("741852963"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = head_id,
        .head_office_revision_id = testUnitRevisionId("planner-ledger-head-revision-1"),
    } });
    const created = switch (taxpayer_result) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };
    const pending_head = created.head_office;

    const tin_evidence_id = testEvidenceId("planner-ledger-tin-evidence");
    try recordPendingEvidence(&ledger, tin_evidence_id);
    try recordTinRootEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("planner-ledger-tin-assertion"),
        tin_evidence_id,
        taxpayer_id,
        testDate(2026, 1, 1),
        try domain.Tin9.parse("741852963"),
    );
    try acceptEvidence(&ledger, tin_evidence_id);
    _ = try ledger.apply(.{ .confirm_taxpayer_tin_root = .{
        .current = created.taxpayer_identity,
        .next = .{
            .id = testTaxpayerRevisionId("planner-ledger-taxpayer-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 1) },
        },
        .evidence_id = tin_evidence_id,
        .observed_tin_root = try domain.Tin9.parse("741852963"),
    } });

    const head_evidence_id = testEvidenceId("planner-ledger-head-evidence");
    try recordPendingEvidence(&ledger, head_evidence_id);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("planner-ledger-head-assertion"),
        head_evidence_id,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 1),
        domain.BranchCode5.headOffice(),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, head_evidence_id);
    _ = try ledger.apply(.{ .confirm_registration_unit = .{
        .current = pending_head,
        .next = .{
            .id = testUnitRevisionId("planner-ledger-head-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 1) },
        },
        .evidence_id = head_evidence_id,
        .observed_code = domain.BranchCode5.headOffice(),
        .observed_rdo_code = null,
    } });

    const head_contact: domain.RegistrationUnitContact = .{
        .registered_address = try domain.field.RegisteredAddress.parse(
            "100 Planner Avenue",
        ),
        .zip_code = try domain.field.ZipCode.parse("1000"),
        .contact_number = try domain.field.ContactNumber.parse("+639171234567"),
        .email_address = try domain.field.EmailAddress.parse("planner@example.test"),
    };
    const contact_evidence_id = testEvidenceId("planner-ledger-contact-evidence");
    try recordPendingEvidence(&ledger, contact_evidence_id);
    try recordContactEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("planner-ledger-contact-assertion"),
        contact_evidence_id,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 1),
        head_contact,
    );
    try acceptEvidence(&ledger, contact_evidence_id);
    _ = try ledger.apply(.{ .create_registration_unit_contact = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_id,
        .next = .{
            .id = testContactRevisionId("planner-ledger-contact-revision-1"),
            .expected_history_sequence = 0,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 1) },
        },
        .contact = head_contact,
        .evidence_id = contact_evidence_id,
    } });

    const branch_id = testUnitId("planner-ledger-branch");
    const branch_result = try ledger.apply(.{ .create_branch = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = branch_id,
        .registration_unit_revision_id = testUnitRevisionId("planner-ledger-branch-revision-1"),
        .effective_from = testDate(2026, 1, 2),
        .candidate = .entered(try domain.BranchCode5.parse("00001")),
    } });
    const pending_branch = switch (branch_result) {
        .unit_created => |value| value,
        else => unreachable,
    };
    const branch_evidence_id = testEvidenceId("planner-ledger-branch-evidence");
    try recordPendingEvidence(&ledger, branch_evidence_id);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("planner-ledger-branch-assertion"),
        branch_evidence_id,
        taxpayer_id,
        branch_id,
        testDate(2026, 1, 3),
        try domain.BranchCode5.parse("00001"),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, branch_evidence_id);
    const confirmed_branch_result = try ledger.apply(.{ .confirm_registration_unit = .{
        .current = pending_branch,
        .next = .{
            .id = testUnitRevisionId("planner-ledger-branch-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 3) },
        },
        .evidence_id = branch_evidence_id,
        .observed_code = try domain.BranchCode5.parse("00001"),
        .observed_rdo_code = null,
    } });
    const confirmed_branch = switch (confirmed_branch_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };

    const corrected_branch_evidence_id = testEvidenceId(
        "planner-ledger-branch-correction-evidence",
    );
    try recordPendingEvidence(&ledger, corrected_branch_evidence_id);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("planner-ledger-branch-correction-assertion"),
        corrected_branch_evidence_id,
        taxpayer_id,
        branch_id,
        testDate(2026, 1, 4),
        try domain.BranchCode5.parse("00002"),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, corrected_branch_evidence_id);
    const corrected_branch_result = try ledger.apply(.{ .correct_branch_code = .{
        .current = confirmed_branch,
        .next = .{
            .id = testUnitRevisionId("planner-ledger-branch-revision-3"),
            .expected_history_sequence = 2,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 4) },
        },
        .evidence_id = corrected_branch_evidence_id,
        .corrected_code = try domain.BranchCode5.parse("00002"),
    } });
    const corrected_branch = switch (corrected_branch_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };

    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("planner-ledger-branch-review-superseded"),
        .evidence_id = branch_evidence_id,
        .expected_history_sequence = 1,
        .state = .superseded,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 2,
        .reason = "Superseded historical branch-code observation",
        .supersedes = testEvidenceReviewDecisionId(branch_evidence_id.asSlice()),
    });

    const vat_evidence_id = testEvidenceId("planner-ledger-vat-evidence");
    try recordPendingEvidence(&ledger, vat_evidence_id);
    try recordTaxTypeEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("planner-ledger-vat-assertion"),
        vat_evidence_id,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 1),
        .vat,
        .confirmed_active,
    );
    try acceptEvidence(&ledger, vat_evidence_id);
    _ = try ledger.apply(.{ .create_tax_type_registration = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_id,
        .registration_id = testTaxTypeRegistrationId("planner-ledger-vat-registration"),
        .revision_id = testTaxTypeRegistrationRevisionId("planner-ledger-vat-revision-1"),
        .effective_from = testDate(2026, 1, 1),
        .tax_type = .vat,
        .status = .confirmed_active,
        .evidence_id = vat_evidence_id,
    } });

    var same_day_snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 1),
        .end = testDate(2026, 1, 1),
    });
    defer same_day_snapshot.deinit(std.testing.allocator);
    const same_day_resolved = switch (same_day_snapshot) {
        .resolved => |value| value,
        .review_required => return error.TestExpectedResolvedSnapshot,
    };
    try std.testing.expectEqual(@as(u32, 2), same_day_resolved.taxpayer_identity.sequence);
    try std.testing.expect(same_day_resolved.taxpayer_identity.id.eql(
        &testTaxpayerRevisionId("planner-ledger-taxpayer-revision-2"),
    ));
    try std.testing.expectEqual(@as(usize, 1), same_day_resolved.units.len);
    try std.testing.expectEqual(@as(u32, 2), same_day_resolved.units[0].sequence);
    try std.testing.expect(same_day_resolved.units[0].id.eql(
        &testUnitRevisionId("planner-ledger-head-revision-2"),
    ));

    var lineage_snapshot = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 4, 1),
        .end = testDate(2026, 4, 1),
    });
    defer lineage_snapshot.deinit(std.testing.allocator);
    const lineage_resolved = switch (lineage_snapshot) {
        .resolved => |value| value,
        .review_required => return error.TestExpectedResolvedSnapshot,
    };
    try std.testing.expect(!lineage_resolved.lineage_complete);
    var corrected_branch_found = false;
    for (lineage_resolved.units) |unit| {
        if (!unit.registration_unit_id.eql(&branch_id)) continue;
        try std.testing.expect(unit.id.eql(&corrected_branch.id));
        try std.testing.expectEqualStrings(
            "00002",
            unit.branch_code_evidence.confirmedCode().?.code.asDigits(),
        );
        corrected_branch_found = true;
    }
    try std.testing.expect(corrected_branch_found);

    const policy_revisions = [_]filing_policy.FilingPolicyRevision{
        filing_policy.testing.fixture2550Q(),
    };
    const planner = filing_planner.FilingPlanner.init(.{ .revisions = &policy_revisions });
    const NoIntegrityIssue = struct {
        fn verify(
            _: *anyopaque,
            _: ProtectedEvidenceVerificationInput,
        ) ?EvidenceIntegrityReviewRequired {
            return null;
        }
    };
    var verification_context: u8 = 0;
    var plan = try planner.plan(std.testing.allocator, &ledger, EvidenceIntegrityVerifier{
        .context = &verification_context,
        .verify_fn = NoIntegrityIssue.verify,
    }, .{
        .taxpayer_id = taxpayer_id,
        .form_revision = filing_policy.FormRevisionKey.initComptime("2550Q", "2024-04-ENCS"),
        .civil_period = try filing_planner.CivilPeriod.init(
            testDate(2026, 4, 1),
            testDate(2026, 6, 30),
        ),
    });
    defer plan.deinit(std.testing.allocator);
    switch (plan) {
        .review_required => try std.testing.expect(false),
        .not_applicable => try std.testing.expect(false),
        .obligations => |obligations| {
            try std.testing.expectEqual(@as(usize, 1), obligations.len);
            const obligation = obligations[0];
            try std.testing.expectEqual(@as(u32, 2), obligation.taxpayer_identity.sequence);
            try std.testing.expect(obligation.filing_unit_id.eql(&head_id));
            try std.testing.expect(obligation.filing_unit_revision_id.eql(
                &testUnitRevisionId("planner-ledger-head-revision-2"),
            ));
            try std.testing.expectEqual(@as(usize, 2), obligation.coverage.len);
            var corrected_coverage_found = false;
            for (obligation.coverage) |covered| {
                if (!covered.registration_unit_id.eql(&branch_id)) continue;
                try std.testing.expect(covered.registration_unit_revision_id.eql(
                    &corrected_branch.id,
                ));
                try std.testing.expectEqualStrings("00002", covered.branch_code.asDigits());
                try std.testing.expect(covered.branch_code_evidence_id.eql(
                    &corrected_branch_evidence_id,
                ));
                corrected_coverage_found = true;
            }
            try std.testing.expect(corrected_coverage_found);
            try std.testing.expectEqual(@as(usize, 1), obligation.tax_type_registration_bindings.len);
            try std.testing.expect(
                obligation.tax_type_registration_bindings[0]
                    .registration_unit_id.eql(&head_id),
            );
            try std.testing.expectEqual(filing_planner.FilingCapability.not_fileable, obligation.filing_capability);
            try std.testing.expectEqual(
                @as(usize, 7),
                obligation.reviewed_evidence_bindings.len,
            );
            for (obligation.reviewed_evidence_bindings) |binding| {
                try std.testing.expect(binding.isValid());
                try std.testing.expect(!binding.evidence_id.eql(&branch_evidence_id));
            }
            try std.testing.expect(filing_planner.verifyResolutionHash(&obligation));
        },
    }
}

test "registration-unit contact revisions remain independent from lifecycle evidence" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("contact-ledger-taxpayer");
    const head_id = testUnitId("contact-ledger-head");
    const created_taxpayer = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("contact-ledger-taxpayer-revision-1"),
        .tin_root = try domain.Tin9.parse("246813579"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = head_id,
        .head_office_revision_id = testUnitRevisionId("contact-ledger-head-revision-1"),
    } });
    const created = switch (created_taxpayer) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };
    const pending_head = created.head_office;
    _ = try confirmTaxpayerTinRootForTest(
        &ledger,
        created.taxpayer_identity,
        testTaxpayerRevisionId("contact-ledger-taxpayer-revision-2"),
        testEvidenceId("contact-ledger-tin-evidence"),
        testEvidenceAssertionId("contact-ledger-tin-assertion"),
        testDate(2026, 1, 2),
    );

    const first_contact: domain.RegistrationUnitContact = .{
        .registered_address = try domain.field.RegisteredAddress.parse("1 Initial Street"),
        .zip_code = try domain.field.ZipCode.parse("1000"),
        .contact_number = try domain.field.ContactNumber.parse("+639171111111"),
        .email_address = try domain.field.EmailAddress.parse("initial@example.test"),
    };
    const first_contact_evidence = testEvidenceId("contact-ledger-evidence-1");
    try recordPendingEvidence(&ledger, first_contact_evidence);
    try recordContactEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("contact-ledger-assertion-1"),
        first_contact_evidence,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 2),
        first_contact,
    );
    try acceptEvidence(&ledger, first_contact_evidence);
    const first_contact_result = try ledger.apply(.{ .create_registration_unit_contact = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_id,
        .next = .{
            .id = testContactRevisionId("contact-ledger-revision-1"),
            .expected_history_sequence = 0,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 2) },
        },
        .contact = first_contact,
        .evidence_id = first_contact_evidence,
    } });
    const stored_first_contact = switch (first_contact_result) {
        .registration_unit_contact_created => |value| value,
        else => unreachable,
    };

    const lifecycle_evidence = testEvidenceId("contact-ledger-lifecycle-evidence");
    try recordPendingEvidence(&ledger, lifecycle_evidence);
    try recordUnitEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("contact-ledger-lifecycle-assertion"),
        lifecycle_evidence,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 3),
        domain.BranchCode5.headOffice(),
        .confirmed_active,
    );
    try acceptEvidence(&ledger, lifecycle_evidence);
    _ = try ledger.apply(.{ .confirm_registration_unit = .{
        .current = pending_head,
        .next = .{
            .id = testUnitRevisionId("contact-ledger-head-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 3) },
        },
        .evidence_id = lifecycle_evidence,
        .observed_code = domain.BranchCode5.headOffice(),
        .observed_rdo_code = null,
    } });

    var after_lifecycle = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 3),
        .end = testDate(2026, 1, 3),
    });
    defer after_lifecycle.deinit(std.testing.allocator);
    const after_lifecycle_resolved = switch (after_lifecycle) {
        .resolved => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 1), after_lifecycle_resolved.contacts.len);
    try std.testing.expect(
        after_lifecycle_resolved.contacts[0].id.eql(&stored_first_contact.id),
    );
    try std.testing.expect(
        after_lifecycle_resolved.contacts[0].evidence_id.eql(&first_contact_evidence),
    );

    const revised_contact: domain.RegistrationUnitContact = .{
        .registered_address = try domain.field.RegisteredAddress.parse("2 Revised Avenue"),
        .zip_code = null,
        .contact_number = try domain.field.ContactNumber.parse("+639172222222"),
        .email_address = null,
    };
    const revised_contact_evidence = testEvidenceId("contact-ledger-evidence-2");
    try recordPendingEvidence(&ledger, revised_contact_evidence);
    try recordContactEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("contact-ledger-assertion-2"),
        revised_contact_evidence,
        taxpayer_id,
        head_id,
        testDate(2026, 2, 1),
        revised_contact,
    );
    try acceptEvidence(&ledger, revised_contact_evidence);
    _ = try ledger.apply(.{ .revise_registration_unit_contact = .{
        .current = stored_first_contact,
        .next = .{
            .id = testContactRevisionId("contact-ledger-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 2, 1) },
        },
        .contact = revised_contact,
        .evidence_id = revised_contact_evidence,
    } });

    var planning = try ledger.planningSnapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 2, 1),
    });
    defer planning.deinit(std.testing.allocator);
    const planning_resolved = switch (planning) {
        .resolved => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 2), planning_resolved.contacts.len);
    try std.testing.expectEqualStrings(
        "1 Initial Street",
        planning_resolved.contacts[0].contact.registered_address.asSlice(),
    );
    try std.testing.expect(
        planning_resolved.contacts[0].effective.until.?.eql(testDate(2026, 1, 31)),
    );
    try std.testing.expectEqualStrings(
        "2 Revised Avenue",
        planning_resolved.contacts[1].contact.registered_address.asSlice(),
    );

    try ledger.recordEvidenceReviewDecision(.{
        .id = testEvidenceReviewDecisionId("contact-ledger-evidence-2-superseded"),
        .evidence_id = revised_contact_evidence,
        .expected_history_sequence = 1,
        .state = .superseded,
        .reviewer = testReviewActor(),
        .reviewed_at_unix_seconds = 1_775_000_001,
        .reason = "A later COR supersedes this contact evidence",
        .supersedes = testEvidenceReviewDecisionId(revised_contact_evidence.asSlice()),
    });
    var superseded = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 2, 1),
        .end = testDate(2026, 2, 1),
    });
    defer superseded.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        EvidenceReviewReason.superseded,
        (try snapshotEvidenceIssue(switch (superseded) {
            .review_required => |issue| issue,
            .resolved => unreachable,
        })).reason,
    );
}

test "legacy resolution requires an exact observed assertion and preserves suffix history" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(std.testing.allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("legacy-ledger-taxpayer");
    const created_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId("legacy-ledger-taxpayer-revision-1"),
        .tin_root = try domain.Tin9.parse("135792468"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = testUnitId("legacy-ledger-head"),
        .head_office_revision_id = testUnitRevisionId("legacy-ledger-head-revision-1"),
    } });
    const created = switch (created_result) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };
    _ = try confirmTaxpayerTinRootForTest(
        &ledger,
        created.taxpayer_identity,
        testTaxpayerRevisionId("legacy-ledger-taxpayer-revision-2"),
        testEvidenceId("legacy-ledger-tin-evidence"),
        testEvidenceAssertionId("legacy-ledger-tin-assertion"),
        testDate(2026, 1, 2),
    );

    const resolved_unit_id = testUnitId("legacy-ledger-resolved-unit");
    const legacy_import_command: domain.ImportLegacyRegistrationUnitCommand = .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = resolved_unit_id,
        .registration_unit_revision_id = testUnitRevisionId("legacy-ledger-resolved-revision-1"),
        .effective_from = testDate(2026, 1, 1),
        .kind = .branch,
        .suffix = try domain.LegacyBranchSuffix.parse("001"),
    };
    try std.testing.expectError(
        error.LegacyMigrationCutoverAuthorityRequired,
        ledger.apply(.{ .import_legacy_registration_unit = legacy_import_command }),
    );
    const imported_result = try testing.applyLegacyRegistrationUnit(
        &ledger,
        legacy_import_command,
    );
    const imported = switch (imported_result) {
        .unit_created => |value| value,
        else => unreachable,
    };
    const still_unresolved_unit_id = testUnitId("legacy-ledger-still-unresolved-unit");
    _ = try testing.applyLegacyRegistrationUnit(&ledger, .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = still_unresolved_unit_id,
        .registration_unit_revision_id = testUnitRevisionId("legacy-ledger-still-unresolved-revision-1"),
        .effective_from = testDate(2026, 1, 1),
        .kind = .branch,
        .suffix = try domain.LegacyBranchSuffix.parse("002"),
    });

    const padded_evidence_id = testEvidenceId("legacy-ledger-padded-evidence");
    try recordPendingEvidence(&ledger, padded_evidence_id);
    try recordUnitEvidenceAssertionWithRdo(
        &ledger,
        testEvidenceAssertionId("legacy-ledger-padded-assertion"),
        padded_evidence_id,
        taxpayer_id,
        resolved_unit_id,
        testDate(2026, 3, 1),
        try domain.BranchCode5.parse("00001"),
        .confirmed_active,
        try domain.RdoCode3.parse("047"),
    );
    try acceptEvidence(&ledger, padded_evidence_id);
    const mismatched_command: domain.RegistrationCommand = .{ .resolve_legacy_registration_unit = .{
        .current = imported,
        .next = .{
            .id = testUnitRevisionId("legacy-ledger-resolved-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 3, 1) },
        },
        .evidence_id = padded_evidence_id,
        .observed_code = try domain.BranchCode5.parse("00019"),
        .observed_rdo_code = try domain.RdoCode3.parse("047"),
    } };
    try std.testing.expectError(
        error.EvidenceAssertionNotAccepted,
        ledger.apply(mismatched_command),
    );

    const evidence_id = testEvidenceId("legacy-ledger-resolution-evidence");
    try recordPendingEvidence(&ledger, evidence_id);
    try recordUnitEvidenceAssertionWithRdo(
        &ledger,
        testEvidenceAssertionId("legacy-ledger-explicit-assertion"),
        evidence_id,
        taxpayer_id,
        resolved_unit_id,
        testDate(2026, 3, 1),
        try domain.BranchCode5.parse("00019"),
        .confirmed_active,
        try domain.RdoCode3.parse("047"),
    );
    try acceptEvidence(&ledger, evidence_id);
    const command: domain.RegistrationCommand = .{ .resolve_legacy_registration_unit = .{
        .current = imported,
        .next = .{
            .id = testUnitRevisionId("legacy-ledger-resolved-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 3, 1) },
        },
        .evidence_id = evidence_id,
        .observed_code = try domain.BranchCode5.parse("00019"),
        .observed_rdo_code = try domain.RdoCode3.parse("047"),
    } };
    const result = try ledger.apply(command);
    const resolved_revision = switch (result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqualStrings("00019", (try resolved_revision.filingCode()).asDigits());

    var history = try ledger.planningSnapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 3, 1),
    });
    defer history.deinit(std.testing.allocator);
    const history_resolved = switch (history) {
        .resolved => |value| value,
        else => unreachable,
    };
    var saw_original_suffix = false;
    var saw_explicit_code = false;
    for (history_resolved.units) |unit| {
        if (!unit.registration_unit_id.eql(&resolved_unit_id)) continue;
        switch (unit.branch_code_evidence) {
            .legacy_unresolved => |suffix| {
                saw_original_suffix = true;
                try std.testing.expectEqualStrings("001", suffix.asDigits());
            },
            .confirmed => |confirmation| {
                saw_explicit_code = true;
                try std.testing.expectEqualStrings("00019", confirmation.code.asDigits());
            },
            .unconfirmed => unreachable,
        }
    }
    try std.testing.expect(saw_original_suffix);
    try std.testing.expect(saw_explicit_code);

    var point = try ledger.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 3, 1),
        .end = testDate(2026, 3, 1),
    });
    defer point.deinit(std.testing.allocator);
    const point_resolved = switch (point) {
        .resolved => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(usize, 1), point_resolved.lineage.len);
    var saw_other_unresolved = false;
    for (point_resolved.units) |unit| {
        if (unit.registration_unit_id.eql(&still_unresolved_unit_id)) {
            saw_other_unresolved = unit.status == .legacy_unresolved;
        }
    }
    try std.testing.expect(saw_other_unresolved);
}

test "same-day contact correction resolves only highest append sequence" {
    const allocator = std.testing.allocator;
    var profile_store = try store.Store.openMemory(allocator);
    defer profile_store.close();
    var ledger = TaxpayerRegistrationLedger.init(allocator, &profile_store);

    const taxpayer_id = testTaxpayerId("same-day-contact-taxpayer");
    const head_id = testUnitId("same-day-contact-head");
    const created_result = try ledger.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId(
            "same-day-contact-taxpayer-revision-1",
        ),
        .tin_root = try domain.Tin9.parse("159357486"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = head_id,
        .head_office_revision_id = testUnitRevisionId(
            "same-day-contact-head-revision-1",
        ),
    } });
    const created = switch (created_result) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };

    const unit_evidence_id = testEvidenceId("same-day-contact-unit-evidence");
    try recordPendingEvidence(&ledger, unit_evidence_id);
    try recordUnitEvidenceAssertionWithRdo(
        &ledger,
        testEvidenceAssertionId("same-day-contact-unit-assertion"),
        unit_evidence_id,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 1),
        domain.BranchCode5.headOffice(),
        .confirmed_active,
        try domain.RdoCode3.parse("123"),
    );
    try acceptEvidence(&ledger, unit_evidence_id);
    _ = try ledger.apply(.{ .confirm_registration_unit = .{
        .current = created.head_office,
        .next = .{
            .id = testUnitRevisionId("same-day-contact-head-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 1) },
        },
        .evidence_id = unit_evidence_id,
        .observed_code = domain.BranchCode5.headOffice(),
        .observed_rdo_code = try domain.RdoCode3.parse("123"),
    } });

    const first_contact: domain.RegistrationUnitContact = .{
        .registered_address = try domain.field.RegisteredAddress.parse(
            "100 First Avenue",
        ),
        .zip_code = try domain.field.ZipCode.parse("1000"),
        .contact_number = try domain.field.ContactNumber.parse("+639171111111"),
        .email_address = try domain.field.EmailAddress.parse(
            "first@example.test",
        ),
    };
    const first_evidence_id = testEvidenceId("same-day-contact-evidence-1");
    try recordPendingEvidence(&ledger, first_evidence_id);
    try recordContactEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("same-day-contact-assertion-1"),
        first_evidence_id,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 1),
        first_contact,
    );
    try acceptEvidence(&ledger, first_evidence_id);
    const first_result = try ledger.apply(.{
        .create_registration_unit_contact = .{
            .taxpayer_id = taxpayer_id,
            .registration_unit_id = head_id,
            .next = .{
                .id = testContactRevisionId("same-day-contact-revision-1"),
                .expected_history_sequence = 0,
                .sequence = 0,
                .effective = .{ .from = testDate(2026, 1, 1) },
            },
            .contact = first_contact,
            .evidence_id = first_evidence_id,
        },
    });
    const first_revision = switch (first_result) {
        .registration_unit_contact_created => |value| value,
        else => unreachable,
    };

    const corrected_contact: domain.RegistrationUnitContact = .{
        .registered_address = try domain.field.RegisteredAddress.parse(
            "200 Corrected Avenue",
        ),
        .zip_code = try domain.field.ZipCode.parse("2000"),
        .contact_number = try domain.field.ContactNumber.parse("+639172222222"),
        .email_address = try domain.field.EmailAddress.parse(
            "corrected@example.test",
        ),
    };
    const corrected_evidence_id = testEvidenceId(
        "same-day-contact-evidence-2",
    );
    try recordPendingEvidence(&ledger, corrected_evidence_id);
    try recordContactEvidenceAssertion(
        &ledger,
        testEvidenceAssertionId("same-day-contact-assertion-2"),
        corrected_evidence_id,
        taxpayer_id,
        head_id,
        testDate(2026, 1, 1),
        corrected_contact,
    );
    try acceptEvidence(&ledger, corrected_evidence_id);
    const corrected_result = try ledger.apply(.{
        .revise_registration_unit_contact = .{
            .current = first_revision,
            .next = .{
                .id = testContactRevisionId("same-day-contact-revision-2"),
                .expected_history_sequence = 1,
                .sequence = 0,
                .effective = .{ .from = testDate(2026, 1, 1) },
            },
            .contact = corrected_contact,
            .evidence_id = corrected_evidence_id,
        },
    });
    const corrected_revision = switch (corrected_result) {
        .registration_unit_contact_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(u32, 2), corrected_revision.sequence);

    const db = try ledger.handle();
    const effective = try loadEffectiveRegistrationUnitContacts(
        allocator,
        db,
        taxpayer_id,
        testDate(2026, 1, 1),
    );
    defer allocator.free(effective);
    try std.testing.expectEqual(@as(usize, 1), effective.len);
    try std.testing.expect(effective[0].id.eql(&corrected_revision.id));
    try std.testing.expectEqualStrings(
        "200 Corrected Avenue",
        effective[0].contact.registered_address.asSlice(),
    );

    const overlapping = try loadRegistrationUnitContactRevisionsOverlappingPeriod(
        allocator,
        db,
        taxpayer_id,
        testDate(2026, 1, 1),
        testDate(2026, 1, 1),
    );
    defer allocator.free(overlapping);
    try std.testing.expectEqual(@as(usize, 1), overlapping.len);
    try std.testing.expect(overlapping[0].id.eql(&corrected_revision.id));
}

test "point and planning snapshots remain coherent while a WAL writer commits" {
    const allocator = std.testing.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var directory_path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory_length = try temporary.dir.realPath(
        std.testing.io,
        &directory_path,
    );
    var database_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const database_path = try std.fmt.bufPrint(
        &database_path_buffer,
        "{s}/registration-snapshot-coherence.sqlite3",
        .{directory_path[0..directory_length]},
    );
    const capability =
        key_custody.bootstrapCurrentArtifactStorage().development_plaintext;
    const fixture_origin = store.testing.fixtureDatabaseOrigin(.claiming);
    const fixture_identity = fixtureIdentityForTest(fixture_origin);
    const ready_identity: store.RegistrationFixtureDirectoryIdentity = .{
        .state = .ready,
        .claim_id = fixture_identity.claim_id,
    };
    try std.testing.expectEqual(
        store.RegistrationFixtureOwnershipResult.claimed_empty_ledger,
        try store.Store.testingEstablishRegistrationFixturePreviewDatabaseOwnership(
            capability,
            allocator,
            database_path,
            fixture_origin,
        ),
    );

    var reader_store = try store.Store.testingOpenFixturePreviewDevelopmentPlaintext(
        capability,
        allocator,
        database_path,
        ready_identity,
    );
    defer reader_store.close();
    var reader = TaxpayerRegistrationLedger.init(allocator, &reader_store);

    const taxpayer_id = testTaxpayerId("coherent-snapshot-taxpayer");
    const created_result = try reader.apply(.{ .create_taxpayer = .{
        .taxpayer_id = taxpayer_id,
        .taxpayer_revision_id = testTaxpayerRevisionId(
            "coherent-snapshot-taxpayer-revision-1",
        ),
        .tin_root = try domain.Tin9.parse("123456789"),
        .effective_from = testDate(2026, 1, 1),
        .head_office_unit_id = testUnitId("coherent-snapshot-head"),
        .head_office_revision_id = testUnitRevisionId(
            "coherent-snapshot-head-revision-1",
        ),
    } });
    const created = switch (created_result) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };

    var writer_store = try store.Store.testingOpenFixturePreviewDevelopmentPlaintext(
        capability,
        allocator,
        database_path,
        ready_identity,
    );
    defer writer_store.close();
    var writer = TaxpayerRegistrationLedger.init(allocator, &writer_store);

    const ExternalBranchWrite = struct {
        ledger: *TaxpayerRegistrationLedger,
        command: domain.RegistrationCommand,
        failed: bool = false,

        fn afterTaxpayerIdentity(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            _ = self.ledger.apply(self.command) catch {
                self.failed = true;
                return;
            };
        }

        fn hook(self: *@This()) SnapshotReadHook {
            return .{
                .context = self,
                .after_taxpayer_identity_fn = afterTaxpayerIdentity,
            };
        }
    };

    var point_write: ExternalBranchWrite = .{
        .ledger = &writer,
        .command = .{ .create_branch = .{
            .taxpayer_id = taxpayer_id,
            .registration_unit_id = testUnitId("coherent-snapshot-branch-1"),
            .registration_unit_revision_id = testUnitRevisionId(
                "coherent-snapshot-branch-revision-1",
            ),
            .effective_from = testDate(2026, 1, 1),
            .candidate = .entered(try domain.BranchCode5.parse("00001")),
        } },
    };
    var point = try reader.snapshotWithReadHook(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 1),
        .end = testDate(2026, 1, 1),
    }, point_write.hook());
    defer point.deinit(allocator);
    try std.testing.expect(!point_write.failed);
    const point_resolved = switch (point) {
        .resolved => |value| value,
        .review_required => return error.TestExpectedResolvedSnapshot,
    };
    try std.testing.expectEqual(@as(usize, 1), point_resolved.units.len);

    var after_point = try reader.snapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 1),
        .end = testDate(2026, 1, 1),
    });
    defer after_point.deinit(allocator);
    try std.testing.expectEqual(
        @as(usize, 2),
        switch (after_point) {
            .resolved => |value| value.units.len,
            .review_required => return error.TestExpectedResolvedSnapshot,
        },
    );

    const tin_evidence_id = testEvidenceId("coherent-snapshot-tin-evidence");
    try recordPendingEvidence(&reader, tin_evidence_id);
    try recordTinRootEvidenceAssertion(
        &reader,
        testEvidenceAssertionId("coherent-snapshot-tin-assertion"),
        tin_evidence_id,
        taxpayer_id,
        testDate(2026, 1, 2),
        try domain.Tin9.parse("123456789"),
    );
    try acceptEvidence(&reader, tin_evidence_id);
    _ = try reader.apply(.{ .confirm_taxpayer_tin_root = .{
        .current = created.taxpayer_identity,
        .next = .{
            .id = testTaxpayerRevisionId("coherent-snapshot-taxpayer-revision-2"),
            .expected_history_sequence = 1,
            .sequence = 0,
            .effective = .{ .from = testDate(2026, 1, 2) },
        },
        .evidence_id = tin_evidence_id,
        .observed_tin_root = try domain.Tin9.parse("123456789"),
    } });

    var planning_write: ExternalBranchWrite = .{
        .ledger = &writer,
        .command = .{ .create_branch = .{
            .taxpayer_id = taxpayer_id,
            .registration_unit_id = testUnitId("coherent-snapshot-branch-2"),
            .registration_unit_revision_id = testUnitRevisionId(
                "coherent-snapshot-branch-revision-2",
            ),
            .effective_from = testDate(2026, 1, 2),
            .candidate = .entered(try domain.BranchCode5.parse("00002")),
        } },
    };
    var planning = try reader.planningSnapshotWithReadHook(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 1, 2),
    }, planning_write.hook());
    defer planning.deinit(allocator);
    try std.testing.expect(!planning_write.failed);
    const planning_resolved = switch (planning) {
        .resolved => |value| value,
        .review_required => return error.TestExpectedResolvedSnapshot,
    };
    try std.testing.expectEqual(@as(usize, 2), planning_resolved.units.len);

    var after_planning = try reader.planningSnapshot(.{
        .taxpayer_id = taxpayer_id,
        .start = testDate(2026, 1, 2),
        .end = testDate(2026, 1, 2),
    });
    defer after_planning.deinit(allocator);
    try std.testing.expectEqual(
        @as(usize, 3),
        switch (after_planning) {
            .resolved => |value| value.units.len,
            .review_required => return error.TestExpectedResolvedSnapshot,
        },
    );
}
