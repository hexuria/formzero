//! Deterministic, read-only pre-cutover inventory for legacy tax profiles.
//!
//! This is deliberately not a migrator. It inventories every persisted stream
//! owned by the tax-profile store, but reads row contents only for the legacy
//! profile shell and its selected revision. All other tables are observed via
//! `COUNT(*)`; COR/evidence contents are never opened or selected. A human
//! reviewed Migration Decision remains required before a later, write-frozen
//! cutover can create or reconcile taxpayer and registration-unit rows.

const std = @import("std");
const field = @import("field.zig");
const store = @import("store.zig");
const key_custody = @import("../security/key_custody.zig");
const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

pub const Error = store.Error || std.mem.Allocator.Error || error{
    InvalidStoredValue,
    InventoryRegistryMismatch,
    NonReadOnlyStatement,
    WriteObservedDuringInventory,
};

pub const schema_contract_version: u16 = 5;
pub const expected_schema_contract_digest: [32]u8 = .{
    0xeb, 0x9d, 0xf5, 0x01, 0x53, 0x58, 0xe5, 0xce,
    0xbd, 0x46, 0x70, 0x0b, 0x74, 0x2c, 0x50, 0x97,
    0xbb, 0xd1, 0x76, 0x72, 0xc8, 0x5e, 0xf1, 0x62,
    0x76, 0xb2, 0xc2, 0xf1, 0x75, 0x1d, 0xcc, 0x0a,
};

/// TIN values are diagnostic data. The default leaves only the final three
/// root digits visible, matching `field.Tin.writeMasked` diagnostics.
pub const TinVisibility = enum {
    masked,
    unmasked,
};

pub const Options = struct {
    tin_visibility: TinVisibility = .masked,
};

const RegistryDiagnosticSink = struct {
    context: *anyopaque,
    unknown_table_fn: *const fn (context: *anyopaque, table_name: []const u8) void,

    fn unknownTable(self: RegistryDiagnosticSink, table_name: []const u8) void {
        self.unknown_table_fn(self.context, table_name);
    }
};

/// Private deterministic seam used to prove an external WAL write cannot tear
/// the inventory between its detailed profile read and aggregate stream reads.
const CollectionHook = struct {
    context: *anyopaque,
    after_profiles_fn: *const fn (context: *anyopaque) void,

    fn afterProfiles(self: CollectionHook) void {
        self.after_profiles_fn(self.context);
    }
};

/// Intentionally excludes `safe_to_map`: this inventory is not authorized to
/// establish an identity or branch-code mapping from legacy data alone.
pub const MigrationDisposition = enum {
    reuse,
    rekey,
    split,
    legacy_read_only,
    supersede,
    blocked,
};

/// The subsystem that owns the meaning and lifecycle of an inventoried
/// stream. Ownership is separate from storage location: calendar integration
/// tables may share the SQLite file while remaining outside this store.
pub const OwnerCategory = enum {
    base_tax_profile,
    identity_history,
    relationship_history,
    registration_evidence,
    legacy_registration,
    taxpayer_year,
    tax_form_profile,
    forms_set,
    calendar_selection,
    generic_draft,
    exact_draft,
    draft_provenance,
    occurrence_and_business_key,
    target_registration_ledger,
    external_calendar,
};

pub const StreamReason = enum {
    profile_identity_requires_new_keys,
    taxpayer_and_unit_facts_require_split,
    identity_correction_facts_require_split,
    evidence_metadata_and_subject_bindings_require_split,
    legacy_registration_rows_require_owner_classification,
    canonical_history_can_be_reused,
    identity_bearing_references_require_rekey,
    rekey_requires_business_identity_equivalence,
    mixed_scalar_and_identity_values_require_split,
    retained_only_as_legacy_audit_source,
    superseded_by_forms_set_decisions,
    legacy_map_cannot_prove_occurrence_order,
    exact_history_must_be_preserved,
    target_rows_require_reviewed_reconciliation,
    generated_export_is_not_persisted,
    external_component_owns_lifecycle,
    rejected_pilot_table_is_absent,
};

pub const StreamPresence = enum {
    /// A table owned by this store and present in the current schema.
    table,
    /// A formerly proposed/rejected table that must remain absent.
    absent,
    /// State owned by another component or generated outside SQLite.
    external_not_owned,
};

pub const DependencyFlags = struct {
    profile_identity: bool = false,
    profile_revision: bool = false,
    forms_set_decision: bool = false,
    draft_identity: bool = false,
    exact_schema: bool = false,
    external_repository: bool = false,
};

pub const AmbiguityFlags = struct {
    taxpayer_group: bool = false,
    registration_unit: bool = false,
    legacy_suffix: bool = false,
    occurrence_order: bool = false,
    legacy_provenance: bool = false,
    target_reconciliation: bool = false,
};

/// Static, reviewable disposition for one physical or explicitly non-physical
/// stream. The registry order is the report order.
pub const StreamDefinition = struct {
    stream_id: []const u8,
    table_name: ?[]const u8,
    presence: StreamPresence,
    introduced_schema_version: ?u32,
    owner: OwnerCategory,
    disposition: MigrationDisposition,
    reason: StreamReason,
    dependencies: DependencyFlags = .{},
    ambiguities: AmbiguityFlags = .{},
};

pub const StreamInventory = struct {
    definition: StreamDefinition,
    /// `null` means there is no table owned by this store. Persisted tables,
    /// including empty ones, always report a count.
    row_count: ?u64,
};

/// Logical owner of one persisted column. This is intentionally more precise
/// than `OwnerCategory`: a legacy table such as `tax_profile_revisions`
/// contains taxpayer, Registration Unit, local-metadata, and unresolved facts
/// in the same physical row.
pub const FieldOwner = enum {
    taxpayer_identity,
    taxpayer_relationship,
    registration_unit,
    registered_facility,
    tax_type_registration,
    registration_evidence,
    taxpayer_year,
    tax_form_profile,
    form_workspace_preference,
    calendar_preference,
    filing_transaction,
    draft_provenance,
    source_attribution,
    occurrence_and_business_key,
    local_metadata,
    migration_control,
    unresolved_legacy_fact,
};

/// One physical SQLite column plus its reviewed table-level disposition and
/// logical owner. Names and declared schema text are copied from read-only
/// PRAGMA output so the report is self-contained and deterministic.
pub const FieldInventory = struct {
    table_name: []const u8,
    ordinal: u32,
    column_name: []u8,
    declared_type: []u8,
    default_sql: ?[]u8,
    not_null: bool,
    primary_key_ordinal: u32,
    hidden: u8,
    owner: FieldOwner,
    disposition: MigrationDisposition,
    reason: StreamReason,

    fn deinit(self: *FieldInventory, allocator: std.mem.Allocator) void {
        allocator.free(self.column_name);
        allocator.free(self.declared_type);
        if (self.default_sql) |value| allocator.free(value);
        self.* = undefined;
    }
};

/// One physical SQLite foreign-key edge. Composite keys retain SQLite's
/// `(id, sequence)` ordering instead of being flattened into an ambiguous
/// comma-delimited string.
pub const ForeignKeyInventory = struct {
    table_name: []const u8,
    id: u32,
    sequence: u32,
    referenced_table: []u8,
    from_column: []u8,
    to_column: ?[]u8,
    on_update: []u8,
    on_delete: []u8,
    match: []u8,
    disposition: MigrationDisposition,

    fn deinit(self: *ForeignKeyInventory, allocator: std.mem.Allocator) void {
        allocator.free(self.referenced_table);
        allocator.free(self.from_column);
        if (self.to_column) |value| allocator.free(value);
        allocator.free(self.on_update);
        allocator.free(self.on_delete);
        allocator.free(self.match);
        self.* = undefined;
    }
};

/// One trigger attached to an inventoried physical table. Trigger SQL is
/// schema metadata, not row or evidence content, and is retained so a reviewer
/// can see the actual append-only/collision guard surface.
pub const TriggerInventory = struct {
    table_name: []const u8,
    name: []u8,
    sql: []u8,
    disposition: MigrationDisposition,

    fn deinit(self: *TriggerInventory, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.sql);
        self.* = undefined;
    }
};

pub const SchemaObjectType = enum {
    table,
    index,
    view,
    trigger,
};

/// Exact owned SQLite schema object. SQL is whitespace-normalized outside
/// quoted literals before hashing; auto-indexes have no SQL text but retain
/// their stable object name and owning table in the contract.
pub const SchemaObjectInventory = struct {
    object_type: SchemaObjectType,
    name: []u8,
    table_name: []u8,
    normalized_sql: ?[]u8,

    fn deinit(self: *SchemaObjectInventory, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.table_name);
        if (self.normalized_sql) |value| allocator.free(value);
        self.* = undefined;
    }
};

pub const RuntimeCallerRole = enum {
    native_application_composition,
    legacy_profile_ui_state,
    legacy_profile_projection,
    generic_draft_persistence,
    exact_draft_persistence,
    draft_provenance_resolution,
    registration_ledger,
    registration_workspace,
    filing_planner,
    read_only_migration_inventory,
};

/// Static repository seam that reads or writes an inventoried stream. This
/// list is deliberately source-path based so code review can update it when a
/// new runtime bypass appears; it is not inferred from SQL text at runtime.
pub const RuntimeCallerDefinition = struct {
    path: []const u8,
    stream_id: []const u8,
    role: RuntimeCallerRole,
    disposition: MigrationDisposition,
};

/// Migration-relevant Store surface that transports persisted identity,
/// preference, draft, or provenance data across module boundaries.
pub const ExportedStructureDefinition = struct {
    path: []const u8,
    symbol: []const u8,
    stream_id: []const u8,
    disposition: MigrationDisposition,
};

pub const GeneratedKeyAuthority = enum {
    caller_supplied_pointer,
    random_local_identity,
    canonical_digest,
    transactional_counter,
};

/// One component of a generated/reusable key. Composite keys repeat `key_id`
/// with increasing `component_order`; each component is checked against the
/// live field inventory so a renamed or removed column fails closed.
pub const GeneratedKeyDefinition = struct {
    key_id: []const u8,
    table_name: []const u8,
    column_name: []const u8,
    component_order: u8,
    authority: GeneratedKeyAuthority,
    disposition: MigrationDisposition,
    reason: StreamReason,
    /// Runtime module that mints this value. `null` means the key is derived
    /// from caller-supplied or already-persisted components rather than minted
    /// by one repository module.
    generator_path: ?[]const u8 = null,
    /// Domain type produced by `generator_path`. Kept as a reviewed source
    /// symbol so tests can compare the registry with typed mint call sites.
    value_type: ?[]const u8 = null,
};

fn table(
    name: []const u8,
    version: u32,
    owner: OwnerCategory,
    disposition: MigrationDisposition,
    reason: StreamReason,
    dependencies: DependencyFlags,
    ambiguities: AmbiguityFlags,
) StreamDefinition {
    return .{
        .stream_id = name,
        .table_name = name,
        .presence = .table,
        .introduced_schema_version = version,
        .owner = owner,
        .disposition = disposition,
        .reason = reason,
        .dependencies = dependencies,
        .ambiguities = ambiguities,
    };
}

fn absent(
    name: []const u8,
    owner: OwnerCategory,
    disposition: MigrationDisposition,
    reason: StreamReason,
) StreamDefinition {
    return .{
        .stream_id = name,
        .table_name = name,
        .presence = .absent,
        .introduced_schema_version = null,
        .owner = owner,
        .disposition = disposition,
        .reason = reason,
    };
}

fn external(
    stream_id: []const u8,
    table_name: ?[]const u8,
    reason: StreamReason,
) StreamDefinition {
    return .{
        .stream_id = stream_id,
        .table_name = table_name,
        .presence = .external_not_owned,
        .introduced_schema_version = null,
        .owner = .external_calendar,
        .disposition = .legacy_read_only,
        .reason = reason,
        .dependencies = .{ .external_repository = true },
    };
}

const identity_dependency: DependencyFlags = .{ .profile_identity = true };
const revision_dependency: DependencyFlags = .{
    .profile_identity = true,
    .profile_revision = true,
};
const draft_dependency: DependencyFlags = .{
    .profile_identity = true,
    .profile_revision = true,
    .draft_identity = true,
};
const exact_dependency: DependencyFlags = .{
    .profile_identity = true,
    .profile_revision = true,
    .draft_identity = true,
    .exact_schema = true,
};
const identity_ambiguity: AmbiguityFlags = .{
    .taxpayer_group = true,
    .registration_unit = true,
    .legacy_suffix = true,
};
const unit_ambiguity: AmbiguityFlags = .{ .registration_unit = true };
const provenance_ambiguity: AmbiguityFlags = .{
    .registration_unit = true,
    .legacy_provenance = true,
};
const target_ambiguity: AmbiguityFlags = .{ .target_reconciliation = true };

/// Complete physical-table disposition registry for the source schema through
/// v27 plus the v28 target ledger that now coexists with it. The final entries
/// explicitly describe absent or externally owned calendar state.
pub const stream_registry = [_]StreamDefinition{
    table("tax_profiles", 1, .base_tax_profile, .rekey, .profile_identity_requires_new_keys, .{}, identity_ambiguity),
    table("tax_profile_revisions", 1, .base_tax_profile, .split, .taxpayer_and_unit_facts_require_split, identity_dependency, identity_ambiguity),
    table("tax_profile_business_activities", 1, .legacy_registration, .split, .legacy_registration_rows_require_owner_classification, revision_dependency, unit_ambiguity),
    table("tax_profile_registration_facts", 1, .legacy_registration, .split, .legacy_registration_rows_require_owner_classification, revision_dependency, unit_ambiguity),
    table("tax_profile_form_sets", 1, .forms_set, .supersede, .superseded_by_forms_set_decisions, identity_dependency, .{}),
    table("tax_profile_form_set_entries", 1, .forms_set, .supersede, .superseded_by_forms_set_decisions, identity_dependency, .{}),
    table("tax_form_drafts", 1, .generic_draft, .reuse, .canonical_history_can_be_reused, .{}, .{ .occurrence_order = true }),
    table("tax_form_draft_role_bindings", 1, .generic_draft, .rekey, .identity_bearing_references_require_rekey, draft_dependency, provenance_ambiguity),
    table("tax_form_draft_snapshot_fields", 1, .generic_draft, .reuse, .canonical_history_can_be_reused, .{ .draft_identity = true }, .{ .legacy_provenance = true }),
    table("tax_form_draft_values", 1, .generic_draft, .legacy_read_only, .legacy_map_cannot_prove_occurrence_order, .{ .draft_identity = true }, .{ .occurrence_order = true }),
    table("tax_profile_identity_anchors", 3, .identity_history, .rekey, .profile_identity_requires_new_keys, identity_dependency, identity_ambiguity),
    table("tax_profile_identity_corrections", 3, .identity_history, .split, .identity_correction_facts_require_split, revision_dependency, identity_ambiguity),
    table("tax_profile_civil_status_revisions", 3, .relationship_history, .rekey, .identity_bearing_references_require_rekey, revision_dependency, .{ .taxpayer_group = true }),
    table("tax_profile_relationships", 3, .relationship_history, .rekey, .identity_bearing_references_require_rekey, revision_dependency, .{ .taxpayer_group = true }),
    table("tax_exact_draft_streams", 4, .occurrence_and_business_key, .rekey, .rekey_requires_business_identity_equivalence, identity_dependency, .{ .taxpayer_group = true, .legacy_provenance = true }),
    table("tax_exact_draft_revisions", 4, .exact_draft, .reuse, .exact_history_must_be_preserved, exact_dependency, .{}),
    table("tax_exact_draft_revision_bindings", 4, .exact_draft, .rekey, .identity_bearing_references_require_rekey, exact_dependency, provenance_ambiguity),
    table("tax_exact_draft_occurrences", 4, .occurrence_and_business_key, .reuse, .exact_history_must_be_preserved, exact_dependency, .{}),
    table("tax_profile_calendar_form_selections", 5, .calendar_selection, .rekey, .identity_bearing_references_require_rekey, identity_dependency, .{ .taxpayer_group = true }),
    table("tax_profile_calendar_form_selection_entries", 5, .calendar_selection, .rekey, .identity_bearing_references_require_rekey, identity_dependency, .{ .taxpayer_group = true }),
    table("tax_profile_local_owner", 6, .base_tax_profile, .reuse, .canonical_history_can_be_reused, .{}, .{}),
    table("tax_form_on_demand_occurrence_counters", 7, .occurrence_and_business_key, .rekey, .rekey_requires_business_identity_equivalence, identity_dependency, .{ .taxpayer_group = true, .legacy_provenance = true }),
    table("tax_profile_cor_documents", 8, .registration_evidence, .split, .evidence_metadata_and_subject_bindings_require_split, identity_dependency, .{ .registration_unit = true }),
    table("tax_profile_form_set_interval_revisions", 9, .forms_set, .supersede, .superseded_by_forms_set_decisions, identity_dependency, .{}),
    table("tax_profile_form_set_interval_entries", 9, .forms_set, .supersede, .superseded_by_forms_set_decisions, identity_dependency, .{}),
    table("tax_profile_business_activity_anchors", 12, .legacy_registration, .split, .legacy_registration_rows_require_owner_classification, identity_dependency, unit_ambiguity),
    table("tax_profile_registration_fact_anchors", 12, .legacy_registration, .split, .legacy_registration_rows_require_owner_classification, identity_dependency, unit_ambiguity),
    table("tax_profile_taxpayer_year_revisions", 14, .taxpayer_year, .rekey, .identity_bearing_references_require_rekey, identity_dependency, .{ .taxpayer_group = true }),
    table("tax_profile_taxpayer_year_values", 14, .taxpayer_year, .rekey, .identity_bearing_references_require_rekey, identity_dependency, .{ .taxpayer_group = true }),
    table("tax_profile_form_profile_revisions", 14, .tax_form_profile, .rekey, .identity_bearing_references_require_rekey, identity_dependency, .{ .taxpayer_group = true }),
    table("tax_profile_form_profile_values", 14, .tax_form_profile, .split, .mixed_scalar_and_identity_values_require_split, identity_dependency, provenance_ambiguity),
    table("tax_profile_form_set_decisions", 15, .forms_set, .rekey, .identity_bearing_references_require_rekey, .{ .profile_identity = true, .forms_set_decision = true }, .{ .taxpayer_group = true }),
    table("tax_profile_registration_commits", 16, .legacy_registration, .split, .legacy_registration_rows_require_owner_classification, identity_dependency, unit_ambiguity),
    table("tax_profile_registration_obligation_anchors", 16, .legacy_registration, .split, .legacy_registration_rows_require_owner_classification, identity_dependency, unit_ambiguity),
    table("tax_profile_registration_component_revisions", 16, .legacy_registration, .split, .legacy_registration_rows_require_owner_classification, identity_dependency, unit_ambiguity),
    table("tax_profile_registration_activity_values", 16, .legacy_registration, .split, .legacy_registration_rows_require_owner_classification, identity_dependency, unit_ambiguity),
    table("tax_profile_registration_obligation_values", 16, .legacy_registration, .split, .legacy_registration_rows_require_owner_classification, identity_dependency, unit_ambiguity),
    table("tax_profile_registration_fact_values", 16, .legacy_registration, .split, .legacy_registration_rows_require_owner_classification, identity_dependency, unit_ambiguity),
    table("tax_form_draft_provenance", 17, .draft_provenance, .rekey, .identity_bearing_references_require_rekey, draft_dependency, provenance_ambiguity),
    table("tax_form_draft_provenance_taxpayer_revisions", 17, .draft_provenance, .rekey, .identity_bearing_references_require_rekey, draft_dependency, provenance_ambiguity),
    table("tax_form_draft_provenance_components", 17, .draft_provenance, .legacy_read_only, .retained_only_as_legacy_audit_source, draft_dependency, provenance_ambiguity),
    table("tax_form_draft_provenance_sources", 17, .draft_provenance, .reuse, .canonical_history_can_be_reused, draft_dependency, .{}),
    table("tax_form_draft_provenance_transaction_seeds", 17, .draft_provenance, .reuse, .canonical_history_can_be_reused, draft_dependency, .{}),
    table("tax_exact_draft_revision_provenance", 19, .draft_provenance, .rekey, .identity_bearing_references_require_rekey, exact_dependency, provenance_ambiguity),
    table("tax_exact_draft_provenance_components", 19, .draft_provenance, .legacy_read_only, .retained_only_as_legacy_audit_source, exact_dependency, provenance_ambiguity),
    table("tax_exact_draft_provenance_sources", 19, .draft_provenance, .reuse, .exact_history_must_be_preserved, exact_dependency, .{}),
    table("tax_exact_draft_provenance_transaction_seeds", 19, .draft_provenance, .reuse, .exact_history_must_be_preserved, exact_dependency, .{}),
    table("tax_form_draft_provenance_sources_v26_legacy", 27, .draft_provenance, .legacy_read_only, .retained_only_as_legacy_audit_source, draft_dependency, .{ .legacy_provenance = true }),
    table("tax_form_draft_provenance_transaction_seeds_v26_legacy", 27, .draft_provenance, .legacy_read_only, .retained_only_as_legacy_audit_source, draft_dependency, .{ .legacy_provenance = true }),
    table("tax_exact_draft_provenance_sources_v26_legacy", 27, .draft_provenance, .legacy_read_only, .retained_only_as_legacy_audit_source, exact_dependency, .{ .legacy_provenance = true }),
    table("tax_exact_draft_provenance_transaction_seeds_v26_legacy", 27, .draft_provenance, .legacy_read_only, .retained_only_as_legacy_audit_source, exact_dependency, .{ .legacy_provenance = true }),
    table("tax_profile_form_profile_filing_locks", 27, .tax_form_profile, .rekey, .identity_bearing_references_require_rekey, .{ .profile_identity = true, .draft_identity = true }, .{ .taxpayer_group = true }),

    table("taxpayer_registration_taxpayers", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, .{}, target_ambiguity),
    table("taxpayer_registration_taxpayer_revisions", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, identity_dependency, target_ambiguity),
    table("taxpayer_registration_evidence", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, .{}, target_ambiguity),
    table("taxpayer_registration_evidence_review_decisions", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, identity_dependency, target_ambiguity),
    table("taxpayer_registration_evidence_assertions", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, identity_dependency, target_ambiguity),
    table("taxpayer_registration_units", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, identity_dependency, target_ambiguity),
    table("taxpayer_registration_unit_revisions", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, identity_dependency, target_ambiguity),
    table("taxpayer_registration_unit_contact_revisions", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, identity_dependency, target_ambiguity),
    table("taxpayer_registration_tax_type_registrations", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, identity_dependency, target_ambiguity),
    table("taxpayer_registration_tax_type_registration_revisions", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, identity_dependency, target_ambiguity),
    table("taxpayer_registration_branch_code_lineage", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, identity_dependency, target_ambiguity),
    table("taxpayer_registration_migration_decisions", 28, .target_registration_ledger, .blocked, .target_rows_require_reviewed_reconciliation, identity_dependency, target_ambiguity),

    absent("tax_profile_annual_income_tax_election_events", .tax_form_profile, .supersede, .rejected_pilot_table_is_absent),
    external("calendar_provider_connections", "calendar_connections", .external_component_owns_lifecycle),
    external("calendar_provider_event_links", "calendar_event_links", .external_component_owns_lifecycle),
    external("calendar_export_artifacts", null, .generated_export_is_not_persisted),
};

/// Runtime modules that currently cross the tax-profile persistence boundary.
/// Each entry names a representative owned stream for the seam; modules that
/// touch multiple streams intentionally appear more than once.
pub const runtime_caller_registry = [_]RuntimeCallerDefinition{
    .{ .path = "src/main.zig", .stream_id = "tax_profiles", .role = .native_application_composition, .disposition = .rekey },
    .{ .path = "src/main.zig", .stream_id = "tax_profile_form_set_decisions", .role = .native_application_composition, .disposition = .rekey },
    .{ .path = "src/main.zig", .stream_id = "taxpayer_registration_taxpayers", .role = .native_application_composition, .disposition = .blocked },
    .{ .path = "src/tax_profile/ui_state.zig", .stream_id = "tax_profile_revisions", .role = .legacy_profile_ui_state, .disposition = .split },
    .{ .path = "src/tax_profile/persistence_adapter.zig", .stream_id = "tax_profile_revisions", .role = .legacy_profile_projection, .disposition = .split },
    .{ .path = "src/forms/persistence_adapter.zig", .stream_id = "tax_form_drafts", .role = .generic_draft_persistence, .disposition = .reuse },
    .{ .path = "src/forms/draft_provenance_runtime.zig", .stream_id = "tax_form_draft_provenance", .role = .draft_provenance_resolution, .disposition = .rekey },
    .{ .path = "src/forms/form_1701q_exact_persistence.zig", .stream_id = "tax_exact_draft_streams", .role = .exact_draft_persistence, .disposition = .rekey },
    .{ .path = "src/forms/form_1701q_exact_runtime.zig", .stream_id = "tax_exact_draft_streams", .role = .exact_draft_persistence, .disposition = .rekey },

    // Direct v28 SQLite adapter. The migration-decision table is deliberately
    // absent because reviewed cutover is not implemented or authorized.
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_taxpayers", .role = .registration_ledger, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_taxpayer_revisions", .role = .registration_ledger, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_evidence", .role = .registration_ledger, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_evidence_review_decisions", .role = .registration_ledger, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_evidence_assertions", .role = .registration_ledger, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_units", .role = .registration_ledger, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_unit_revisions", .role = .registration_ledger, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_unit_contact_revisions", .role = .registration_ledger, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_tax_type_registrations", .role = .registration_ledger, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_tax_type_registration_revisions", .role = .registration_ledger, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .stream_id = "taxpayer_registration_branch_code_lineage", .role = .registration_ledger, .disposition = .blocked },

    // Taxpayer-first workspace caller. It lists/snapshots every v28 planning
    // stream and owns the currently implemented registration write flows.
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_taxpayers", .role = .registration_workspace, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_taxpayer_revisions", .role = .registration_workspace, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_evidence", .role = .registration_workspace, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_evidence_review_decisions", .role = .registration_workspace, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_evidence_assertions", .role = .registration_workspace, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_units", .role = .registration_workspace, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_unit_revisions", .role = .registration_workspace, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_unit_contact_revisions", .role = .registration_workspace, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_tax_type_registrations", .role = .registration_workspace, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_tax_type_registration_revisions", .role = .registration_workspace, .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_workspace.zig", .stream_id = "taxpayer_registration_branch_code_lineage", .role = .registration_workspace, .disposition = .blocked },

    // The pure planner reaches persistence only through the verified planning
    // snapshot seam. It does not read unit shells, code lineage, or migration
    // decisions and does not mint a database identifier.
    .{ .path = "src/filing/planner.zig", .stream_id = "taxpayer_registration_taxpayer_revisions", .role = .filing_planner, .disposition = .blocked },
    .{ .path = "src/filing/planner.zig", .stream_id = "taxpayer_registration_evidence", .role = .filing_planner, .disposition = .blocked },
    .{ .path = "src/filing/planner.zig", .stream_id = "taxpayer_registration_evidence_review_decisions", .role = .filing_planner, .disposition = .blocked },
    .{ .path = "src/filing/planner.zig", .stream_id = "taxpayer_registration_evidence_assertions", .role = .filing_planner, .disposition = .blocked },
    .{ .path = "src/filing/planner.zig", .stream_id = "taxpayer_registration_unit_revisions", .role = .filing_planner, .disposition = .blocked },
    .{ .path = "src/filing/planner.zig", .stream_id = "taxpayer_registration_unit_contact_revisions", .role = .filing_planner, .disposition = .blocked },
    .{ .path = "src/filing/planner.zig", .stream_id = "taxpayer_registration_tax_type_registrations", .role = .filing_planner, .disposition = .blocked },
    .{ .path = "src/filing/planner.zig", .stream_id = "taxpayer_registration_tax_type_registration_revisions", .role = .filing_planner, .disposition = .blocked },

    .{ .path = "src/tax_profile/registration_migration_inventory.zig", .stream_id = "tax_profiles", .role = .read_only_migration_inventory, .disposition = .rekey },
};

/// Migration-relevant structures exported across repository modules. This is
/// deliberately a contract registry, not a dump of every public helper type.
pub const exported_structure_registry = [_]ExportedStructureDefinition{
    .{ .path = "src/tax_profile/store.zig", .symbol = "ProfileCreate", .stream_id = "tax_profiles", .disposition = .rekey },
    .{ .path = "src/tax_profile/store.zig", .symbol = "RevisionWrite", .stream_id = "tax_profile_revisions", .disposition = .split },
    .{ .path = "src/tax_profile/store.zig", .symbol = "OwnedProfileRevision", .stream_id = "tax_profile_revisions", .disposition = .split },
    .{ .path = "src/tax_profile/store.zig", .symbol = "TaxpayerYearRevisionWrite", .stream_id = "tax_profile_taxpayer_year_revisions", .disposition = .rekey },
    .{ .path = "src/tax_profile/store.zig", .symbol = "OwnedTaxpayerYearRevision", .stream_id = "tax_profile_taxpayer_year_revisions", .disposition = .rekey },
    .{ .path = "src/tax_profile/store.zig", .symbol = "TaxFormProfileRevisionWrite", .stream_id = "tax_profile_form_profile_revisions", .disposition = .rekey },
    .{ .path = "src/tax_profile/store.zig", .symbol = "OwnedTaxFormProfileRevision", .stream_id = "tax_profile_form_profile_revisions", .disposition = .rekey },
    .{ .path = "src/tax_profile/store.zig", .symbol = "FormSetDecisionWrite", .stream_id = "tax_profile_form_set_decisions", .disposition = .rekey },
    .{ .path = "src/tax_profile/store.zig", .symbol = "OwnedFormSetDecision", .stream_id = "tax_profile_form_set_decisions", .disposition = .rekey },
    .{ .path = "src/tax_profile/store.zig", .symbol = "DraftWrite", .stream_id = "tax_form_drafts", .disposition = .reuse },
    .{ .path = "src/tax_profile/store.zig", .symbol = "OwnedDraft", .stream_id = "tax_form_drafts", .disposition = .reuse },
    .{ .path = "src/tax_profile/store.zig", .symbol = "DraftProvenanceWrite", .stream_id = "tax_form_draft_provenance", .disposition = .rekey },
    .{ .path = "src/tax_profile/store.zig", .symbol = "OwnedDraftProvenance", .stream_id = "tax_form_draft_provenance", .disposition = .rekey },
    .{ .path = "src/tax_profile/store.zig", .symbol = "ExactDraftRevisionWrite", .stream_id = "tax_exact_draft_revisions", .disposition = .reuse },
    .{ .path = "src/tax_profile/store.zig", .symbol = "OwnedExactDraftHistory", .stream_id = "tax_exact_draft_revisions", .disposition = .reuse },
    .{ .path = "src/tax_profile/store.zig", .symbol = "CanonicalFilingBusinessKeyWrite", .stream_id = "tax_exact_draft_streams", .disposition = .rekey },
    .{ .path = "src/tax_profile/store.zig", .symbol = "OwnedCanonicalFilingBusinessKey", .stream_id = "tax_exact_draft_streams", .disposition = .rekey },
    .{ .path = "src/tax_profile/registration_domain.zig", .symbol = "RegistrationCommand", .stream_id = "taxpayer_registration_taxpayers", .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_ledger.zig", .symbol = "ResolvedRegistrationSnapshot", .stream_id = "taxpayer_registration_taxpayer_revisions", .disposition = .blocked },
    .{ .path = "src/tax_profile/registration_domain.zig", .symbol = "RegistrationUnitContactRevision", .stream_id = "taxpayer_registration_unit_contact_revisions", .disposition = .blocked },
};

/// Generated or reusable identity/key components whose semantics must survive
/// migration review. A caller-provided draft/profile ID is not listed merely
/// because it is a primary key; this registry targets generated pointers,
/// canonical digests, and occurrence allocation state.
pub const generated_key_registry = [_]GeneratedKeyDefinition{
    .{ .key_id = "legacy-current-profile-revision", .table_name = "tax_profiles", .column_name = "current_revision_id", .component_order = 0, .authority = .caller_supplied_pointer, .disposition = .rekey, .reason = .identity_bearing_references_require_rekey },
    .{ .key_id = "exact-draft-workspace", .table_name = "tax_exact_draft_streams", .column_name = "workspace_id", .component_order = 0, .authority = .random_local_identity, .disposition = .reuse, .reason = .exact_history_must_be_preserved },
    .{ .key_id = "exact-filing-business-key", .table_name = "tax_exact_draft_streams", .column_name = "filing_business_key_digest", .component_order = 0, .authority = .canonical_digest, .disposition = .rekey, .reason = .rekey_requires_business_identity_equivalence },
    .{ .key_id = "on-demand-occurrence", .table_name = "tax_form_on_demand_occurrence_counters", .column_name = "owner_id", .component_order = 0, .authority = .transactional_counter, .disposition = .rekey, .reason = .rekey_requires_business_identity_equivalence },
    .{ .key_id = "on-demand-occurrence", .table_name = "tax_form_on_demand_occurrence_counters", .column_name = "profile_id", .component_order = 1, .authority = .transactional_counter, .disposition = .rekey, .reason = .rekey_requires_business_identity_equivalence },
    .{ .key_id = "on-demand-occurrence", .table_name = "tax_form_on_demand_occurrence_counters", .column_name = "form_code", .component_order = 2, .authority = .transactional_counter, .disposition = .rekey, .reason = .rekey_requires_business_identity_equivalence },
    .{ .key_id = "on-demand-occurrence", .table_name = "tax_form_on_demand_occurrence_counters", .column_name = "form_revision", .component_order = 3, .authority = .transactional_counter, .disposition = .rekey, .reason = .rekey_requires_business_identity_equivalence },
    .{ .key_id = "on-demand-occurrence", .table_name = "tax_form_on_demand_occurrence_counters", .column_name = "tax_year", .component_order = 4, .authority = .transactional_counter, .disposition = .rekey, .reason = .rekey_requires_business_identity_equivalence },
    .{ .key_id = "on-demand-occurrence", .table_name = "tax_form_on_demand_occurrence_counters", .column_name = "last_occurrence", .component_order = 5, .authority = .transactional_counter, .disposition = .rekey, .reason = .rekey_requires_business_identity_equivalence },

    // Opaque v28 identities minted by the taxpayer-first workspace. These are
    // values, not reviewed migration mappings: every target stream remains
    // blocked until a later reviewed cutover disposition exists.
    .{ .key_id = "registration-taxpayer-id", .table_name = "taxpayer_registration_taxpayers", .column_name = "id", .component_order = 0, .authority = .random_local_identity, .disposition = .blocked, .reason = .target_rows_require_reviewed_reconciliation, .generator_path = "src/tax_profile/registration_workspace.zig", .value_type = "TaxpayerId" },
    .{ .key_id = "registration-taxpayer-revision-id", .table_name = "taxpayer_registration_taxpayer_revisions", .column_name = "id", .component_order = 0, .authority = .random_local_identity, .disposition = .blocked, .reason = .target_rows_require_reviewed_reconciliation, .generator_path = "src/tax_profile/registration_workspace.zig", .value_type = "TaxpayerRevisionId" },
    .{ .key_id = "registration-evidence-id", .table_name = "taxpayer_registration_evidence", .column_name = "id", .component_order = 0, .authority = .random_local_identity, .disposition = .blocked, .reason = .target_rows_require_reviewed_reconciliation, .generator_path = "src/tax_profile/registration_workspace.zig", .value_type = "RegistrationEvidenceId" },
    .{ .key_id = "registration-evidence-review-decision-id", .table_name = "taxpayer_registration_evidence_review_decisions", .column_name = "id", .component_order = 0, .authority = .random_local_identity, .disposition = .blocked, .reason = .target_rows_require_reviewed_reconciliation, .generator_path = "src/tax_profile/registration_workspace.zig", .value_type = "RegistrationEvidenceReviewDecisionId" },
    .{ .key_id = "registration-evidence-assertion-id", .table_name = "taxpayer_registration_evidence_assertions", .column_name = "id", .component_order = 0, .authority = .random_local_identity, .disposition = .blocked, .reason = .target_rows_require_reviewed_reconciliation, .generator_path = "src/tax_profile/registration_workspace.zig", .value_type = "RegistrationEvidenceAssertionId" },
    .{ .key_id = "registration-unit-id", .table_name = "taxpayer_registration_units", .column_name = "id", .component_order = 0, .authority = .random_local_identity, .disposition = .blocked, .reason = .target_rows_require_reviewed_reconciliation, .generator_path = "src/tax_profile/registration_workspace.zig", .value_type = "RegistrationUnitId" },
    .{ .key_id = "registration-unit-revision-id", .table_name = "taxpayer_registration_unit_revisions", .column_name = "id", .component_order = 0, .authority = .random_local_identity, .disposition = .blocked, .reason = .target_rows_require_reviewed_reconciliation, .generator_path = "src/tax_profile/registration_workspace.zig", .value_type = "RegistrationUnitRevisionId" },
    .{ .key_id = "registration-unit-contact-revision-id", .table_name = "taxpayer_registration_unit_contact_revisions", .column_name = "id", .component_order = 0, .authority = .random_local_identity, .disposition = .blocked, .reason = .target_rows_require_reviewed_reconciliation, .generator_path = "src/tax_profile/registration_workspace.zig", .value_type = "RegistrationUnitContactRevisionId" },
    .{ .key_id = "registration-tax-type-registration-id", .table_name = "taxpayer_registration_tax_type_registrations", .column_name = "id", .component_order = 0, .authority = .random_local_identity, .disposition = .blocked, .reason = .target_rows_require_reviewed_reconciliation, .generator_path = "src/tax_profile/registration_workspace.zig", .value_type = "TaxTypeRegistrationId" },
    .{ .key_id = "registration-tax-type-registration-revision-id", .table_name = "taxpayer_registration_tax_type_registration_revisions", .column_name = "id", .component_order = 0, .authority = .random_local_identity, .disposition = .blocked, .reason = .target_rows_require_reviewed_reconciliation, .generator_path = "src/tax_profile/registration_workspace.zig", .value_type = "TaxTypeRegistrationRevisionId" },
};

pub const DispositionReason = enum {
    /// Valid-looking legacy data still needs a reviewed Migration Decision.
    automatic_mapping_not_authorized,
    current_revision_missing,
    current_revision_sequence_invalid,
    current_revision_tin_missing,
    current_revision_tin_malformed,
    /// Legacy three- and four-digit suffixes cannot be padded into a BIR
    /// `BranchCode5` without losing the original fact.
    legacy_suffix_not_five_digits,
};

/// A five-digit suffix is only a parsed legacy candidate. It is not a
/// confirmed BIR Branch Code because this read-only inventory never reviews
/// or opens registration evidence.
pub const TinSuffixKind = enum {
    missing,
    no_suffix,
    five_digit_candidate,
    unsupported_legacy_length,
    malformed,
};

pub const OwnedTinSuffixFact = struct {
    /// Normalized masked or explicitly requested unmasked display value.
    display_tin: []u8,
    /// Same visibility policy as `display_tin`; `null` for missing/malformed
    /// legacy data. It is a candidate grouping aid, never a TaxpayerId.
    root: ?[]u8,
    /// Same visibility policy as `display_tin`; it never proves confirmation.
    suffix: ?[]u8,
    suffix_digit_count: ?u8,
    kind: TinSuffixKind,

    pub fn deinit(self: *OwnedTinSuffixFact, allocator: std.mem.Allocator) void {
        allocator.free(self.display_tin);
        if (self.root) |value| allocator.free(value);
        if (self.suffix) |value| allocator.free(value);
        self.* = undefined;
    }
};

pub const OwnedLegacyProfile = struct {
    profile_id: []u8,
    profile_status: []u8,
    /// The legacy pointer is preserved for review. It does not become a new
    /// taxpayer or registration-unit identity.
    current_revision_id: ?[]u8,
    current_revision_sequence: ?u32,
    has_current_revision: bool,
    current_tin: OwnedTinSuffixFact,
    disposition: MigrationDisposition,
    reasons: []DispositionReason,

    pub fn deinit(self: *OwnedLegacyProfile, allocator: std.mem.Allocator) void {
        allocator.free(self.profile_id);
        allocator.free(self.profile_status);
        if (self.current_revision_id) |value| allocator.free(value);
        self.current_tin.deinit(allocator);
        allocator.free(self.reasons);
        self.* = undefined;
    }
};

/// Runtime evidence that this invocation prepared a read-only statement and
/// did not change this SQLite connection's cumulative change counter.
pub const ReadOnlyProof = struct {
    statement_read_only: bool,
    total_changes_before: i64,
    total_changes_after: i64,

    pub fn verifiedNoWrites(self: ReadOnlyProof) bool {
        return self.statement_read_only and
            self.total_changes_before == self.total_changes_after;
    }
};

pub const Inventory = struct {
    profiles: []OwnedLegacyProfile,
    streams: []StreamInventory,
    fields: []FieldInventory,
    foreign_keys: []ForeignKeyInventory,
    triggers: []TriggerInventory,
    schema_objects: []SchemaObjectInventory,
    runtime_callers: []const RuntimeCallerDefinition,
    exported_structures: []const ExportedStructureDefinition,
    generated_keys: []const GeneratedKeyDefinition,
    schema_contract_digest: [32]u8,
    read_only_proof: ReadOnlyProof,

    pub fn deinit(self: *Inventory, allocator: std.mem.Allocator) void {
        for (self.profiles) |*profile| profile.deinit(allocator);
        allocator.free(self.profiles);
        allocator.free(self.streams);
        for (self.fields) |*field_inventory| field_inventory.deinit(allocator);
        allocator.free(self.fields);
        for (self.foreign_keys) |*foreign_key| foreign_key.deinit(allocator);
        allocator.free(self.foreign_keys);
        for (self.triggers) |*trigger| trigger.deinit(allocator);
        allocator.free(self.triggers);
        for (self.schema_objects) |*schema_object| schema_object.deinit(allocator);
        allocator.free(self.schema_objects);
        self.* = undefined;
    }
};

/// Collects a deterministic, masked-by-default inventory. This function only
/// borrows the already-open Store connection; it has no path or evidence-file
/// input surface and performs no schema migration, transaction, or DML.
pub fn collect(
    allocator: std.mem.Allocator,
    profile_store: *store.Store,
) Error!Inventory {
    return collectWithOptions(allocator, profile_store, .{});
}

/// Same as `collect`, with an explicit, caller-controlled diagnostic display
/// choice. `unmasked` remains an inventory view, not migration approval.
pub fn collectWithOptions(
    allocator: std.mem.Allocator,
    profile_store: *store.Store,
    options: Options,
) Error!Inventory {
    return collectWithOptionsAndDiagnosticSink(
        allocator,
        profile_store,
        options,
        null,
    );
}

fn collectWithOptionsAndDiagnosticSink(
    allocator: std.mem.Allocator,
    profile_store: *store.Store,
    options: Options,
    diagnostic_sink: ?RegistryDiagnosticSink,
) Error!Inventory {
    return collectWithOptionsAndDiagnosticSinkAndHook(
        allocator,
        profile_store,
        options,
        diagnostic_sink,
        null,
    );
}

fn collectWithOptionsAndHook(
    allocator: std.mem.Allocator,
    profile_store: *store.Store,
    options: Options,
    hook: CollectionHook,
) Error!Inventory {
    return collectWithOptionsAndDiagnosticSinkAndHook(
        allocator,
        profile_store,
        options,
        null,
        hook,
    );
}

fn collectWithOptionsAndDiagnosticSinkAndHook(
    allocator: std.mem.Allocator,
    profile_store: *store.Store,
    options: Options,
    diagnostic_sink: ?RegistryDiagnosticSink,
    hook: ?CollectionHook,
) Error!Inventory {
    const db = try databaseHandle(profile_store);
    try execReadTransaction(db, "BEGIN DEFERRED;");
    var transaction_open = true;
    errdefer if (transaction_open) rollbackReadTransactionNoFail(db);
    const total_changes_before = sqlite.sqlite3_total_changes64(db);

    var statement = try prepare(db,
        \\SELECT p.id, p.status, p.current_revision_id,
        \\       revision.id, revision.sequence, revision.tin
        \\FROM tax_profiles AS p
        \\LEFT JOIN tax_profile_revisions AS revision
        \\  ON revision.profile_id = p.id
        \\ AND revision.id = p.current_revision_id
        \\ORDER BY p.id COLLATE BINARY ASC;
    );
    defer statement.deinit();

    const statement_read_only = sqlite.sqlite3_stmt_readonly(statement.raw) != 0;
    if (!statement_read_only) return error.NonReadOnlyStatement;

    var profiles: std.ArrayList(OwnedLegacyProfile) = .empty;
    errdefer {
        for (profiles.items) |*profile| profile.deinit(allocator);
        profiles.deinit(allocator);
    }

    while (try statement.step() == .row) {
        var profile = try readLegacyProfile(allocator, statement.raw, options);
        profiles.append(allocator, profile) catch |err| {
            profile.deinit(allocator);
            return err;
        };
    }

    if (hook) |value| value.afterProfiles();

    const streams = try collectStreams(allocator, db, diagnostic_sink);
    errdefer allocator.free(streams);
    const fields = try collectFields(allocator, db);
    errdefer deinitFields(allocator, fields);
    try validateGeneratedKeyRegistry(fields);
    const foreign_keys = try collectForeignKeys(allocator, db);
    errdefer deinitForeignKeys(allocator, foreign_keys);
    const triggers = try collectTriggers(allocator, db);
    errdefer deinitTriggers(allocator, triggers);
    const schema_objects = try collectSchemaObjects(allocator, db);
    errdefer deinitSchemaObjects(allocator, schema_objects);
    try validateStaticContractRegistries();
    const schema_contract_digest = computeSchemaContractDigest(
        fields,
        foreign_keys,
        triggers,
        schema_objects,
    );
    if (!std.mem.eql(
        u8,
        &schema_contract_digest,
        &expected_schema_contract_digest,
    )) {
        return error.InventoryRegistryMismatch;
    }

    const total_changes_after = sqlite.sqlite3_total_changes64(db);
    if (total_changes_before != total_changes_after) {
        return error.WriteObservedDuringInventory;
    }

    try execReadTransaction(db, "COMMIT;");
    transaction_open = false;

    return .{
        .profiles = try profiles.toOwnedSlice(allocator),
        .streams = streams,
        .fields = fields,
        .foreign_keys = foreign_keys,
        .triggers = triggers,
        .schema_objects = schema_objects,
        .runtime_callers = &runtime_caller_registry,
        .exported_structures = &exported_structure_registry,
        .generated_keys = &generated_key_registry,
        .schema_contract_digest = schema_contract_digest,
        .read_only_proof = .{
            .statement_read_only = statement_read_only,
            .total_changes_before = total_changes_before,
            .total_changes_after = total_changes_after,
        },
    };
}

fn collectStreams(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
    diagnostic_sink: ?RegistryDiagnosticSink,
) Error![]StreamInventory {
    try verifyRegistryCoversSchema(db, diagnostic_sink);

    var streams: std.ArrayList(StreamInventory) = .empty;
    errdefer streams.deinit(allocator);

    for (stream_registry) |definition| {
        const row_count: ?u64 = switch (definition.presence) {
            .table => blk: {
                const name = definition.table_name orelse
                    return error.InventoryRegistryMismatch;
                if (!(try tableExists(db, name))) {
                    return error.InventoryRegistryMismatch;
                }
                break :blk try countRows(db, name);
            },
            .absent => blk: {
                const name = definition.table_name orelse
                    return error.InventoryRegistryMismatch;
                if (try tableExists(db, name)) {
                    return error.InventoryRegistryMismatch;
                }
                break :blk null;
            },
            .external_not_owned => null,
        };

        try streams.append(allocator, .{
            .definition = definition,
            .row_count = row_count,
        });
    }

    return streams.toOwnedSlice(allocator);
}

fn collectFields(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
) Error![]FieldInventory {
    var fields: std.ArrayList(FieldInventory) = .empty;
    errdefer {
        for (fields.items) |*field_inventory| field_inventory.deinit(allocator);
        fields.deinit(allocator);
    }

    for (stream_registry) |definition| {
        if (definition.presence != .table) continue;
        const table_name = definition.table_name orelse
            return error.InventoryRegistryMismatch;
        if (!isSqlIdentifier(table_name)) return error.InventoryRegistryMismatch;

        var sql_buffer: [192]u8 = undefined;
        const sql_text = std.fmt.bufPrint(
            &sql_buffer,
            "PRAGMA table_xinfo(\"{s}\");",
            .{table_name},
        ) catch unreachable;
        var statement = try prepare(db, sql_text);
        defer statement.deinit();
        if (sqlite.sqlite3_stmt_readonly(statement.raw) == 0) {
            return error.NonReadOnlyStatement;
        }

        var expected_ordinal: u32 = 0;
        while (try statement.step() == .row) {
            const raw_ordinal = sqlite.sqlite3_column_int64(statement.raw, 0);
            if (raw_ordinal < 0 or raw_ordinal > std.math.maxInt(u32)) {
                return error.InvalidStoredValue;
            }
            const ordinal: u32 = @intCast(raw_ordinal);
            if (ordinal != expected_ordinal) return error.InventoryRegistryMismatch;
            expected_ordinal += 1;

            const column_name = try dupRequiredColumn(allocator, statement.raw, 1);
            errdefer allocator.free(column_name);
            const declared_type = if (columnText(statement.raw, 2)) |value|
                try allocator.dupe(u8, value)
            else
                try allocator.dupe(u8, "");
            errdefer allocator.free(declared_type);
            const default_sql = try dupOptionalColumn(allocator, statement.raw, 4);
            errdefer if (default_sql) |value| allocator.free(value);

            const not_null = try readBooleanInteger(statement.raw, 3);
            const primary_key_ordinal = try readU32Integer(statement.raw, 5);
            const hidden_raw = try readU32Integer(statement.raw, 6);
            if (hidden_raw > std.math.maxInt(u8)) return error.InvalidStoredValue;

            try fields.append(allocator, .{
                .table_name = table_name,
                .ordinal = ordinal,
                .column_name = column_name,
                .declared_type = declared_type,
                .default_sql = default_sql,
                .not_null = not_null,
                .primary_key_ordinal = primary_key_ordinal,
                .hidden = @intCast(hidden_raw),
                .owner = fieldOwner(definition, column_name),
                .disposition = definition.disposition,
                .reason = definition.reason,
            });
        }
        if (expected_ordinal == 0) return error.InventoryRegistryMismatch;
    }

    return fields.toOwnedSlice(allocator);
}

fn collectForeignKeys(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
) Error![]ForeignKeyInventory {
    var foreign_keys: std.ArrayList(ForeignKeyInventory) = .empty;
    errdefer {
        for (foreign_keys.items) |*foreign_key| foreign_key.deinit(allocator);
        foreign_keys.deinit(allocator);
    }

    for (stream_registry) |definition| {
        if (definition.presence != .table) continue;
        const table_name = definition.table_name orelse
            return error.InventoryRegistryMismatch;
        if (!isSqlIdentifier(table_name)) return error.InventoryRegistryMismatch;

        var sql_buffer: [192]u8 = undefined;
        const sql_text = std.fmt.bufPrint(
            &sql_buffer,
            "PRAGMA foreign_key_list(\"{s}\");",
            .{table_name},
        ) catch unreachable;
        var statement = try prepare(db, sql_text);
        defer statement.deinit();
        if (sqlite.sqlite3_stmt_readonly(statement.raw) == 0) {
            return error.NonReadOnlyStatement;
        }

        while (try statement.step() == .row) {
            const id = try readU32Integer(statement.raw, 0);
            const sequence = try readU32Integer(statement.raw, 1);
            const referenced_table = try dupRequiredColumn(allocator, statement.raw, 2);
            errdefer allocator.free(referenced_table);
            const from_column = try dupRequiredColumn(allocator, statement.raw, 3);
            errdefer allocator.free(from_column);
            const to_column = try dupOptionalColumn(allocator, statement.raw, 4);
            errdefer if (to_column) |value| allocator.free(value);
            const on_update = try dupRequiredColumn(allocator, statement.raw, 5);
            errdefer allocator.free(on_update);
            const on_delete = try dupRequiredColumn(allocator, statement.raw, 6);
            errdefer allocator.free(on_delete);
            const match = try dupRequiredColumn(allocator, statement.raw, 7);
            errdefer allocator.free(match);

            try foreign_keys.append(allocator, .{
                .table_name = table_name,
                .id = id,
                .sequence = sequence,
                .referenced_table = referenced_table,
                .from_column = from_column,
                .to_column = to_column,
                .on_update = on_update,
                .on_delete = on_delete,
                .match = match,
                .disposition = definition.disposition,
            });
        }
    }

    return foreign_keys.toOwnedSlice(allocator);
}

fn collectTriggers(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
) Error![]TriggerInventory {
    var triggers: std.ArrayList(TriggerInventory) = .empty;
    errdefer {
        for (triggers.items) |*trigger| trigger.deinit(allocator);
        triggers.deinit(allocator);
    }

    var statement = try prepare(db,
        \\SELECT name, tbl_name, sql
        \\FROM sqlite_schema
        \\WHERE type = 'trigger'
        \\  AND (
        \\    tbl_name GLOB 'tax_*' OR
        \\    tbl_name GLOB 'taxpayer_registration_*'
        \\  )
        \\ORDER BY tbl_name COLLATE BINARY ASC, name COLLATE BINARY ASC;
    );
    defer statement.deinit();
    if (sqlite.sqlite3_stmt_readonly(statement.raw) == 0) {
        return error.NonReadOnlyStatement;
    }

    while (try statement.step() == .row) {
        const table_name_value = columnText(statement.raw, 1) orelse
            return error.InvalidStoredValue;
        const definition = definitionForTable(table_name_value) orelse
            return error.InventoryRegistryMismatch;
        if (definition.presence != .table) return error.InventoryRegistryMismatch;
        const table_name = definition.table_name orelse
            return error.InventoryRegistryMismatch;

        const name = try dupRequiredColumn(allocator, statement.raw, 0);
        errdefer allocator.free(name);
        const sql = try dupRequiredColumn(allocator, statement.raw, 2);
        errdefer allocator.free(sql);
        try triggers.append(allocator, .{
            .table_name = table_name,
            .name = name,
            .sql = sql,
            .disposition = definition.disposition,
        });
    }

    return triggers.toOwnedSlice(allocator);
}

fn deinitFields(allocator: std.mem.Allocator, fields: []FieldInventory) void {
    for (fields) |*field_inventory| field_inventory.deinit(allocator);
    allocator.free(fields);
}

fn deinitForeignKeys(
    allocator: std.mem.Allocator,
    foreign_keys: []ForeignKeyInventory,
) void {
    for (foreign_keys) |*foreign_key| foreign_key.deinit(allocator);
    allocator.free(foreign_keys);
}

fn deinitTriggers(allocator: std.mem.Allocator, triggers: []TriggerInventory) void {
    for (triggers) |*trigger| trigger.deinit(allocator);
    allocator.free(triggers);
}

fn collectSchemaObjects(
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
) Error![]SchemaObjectInventory {
    var objects: std.ArrayList(SchemaObjectInventory) = .empty;
    errdefer {
        for (objects.items) |*object| object.deinit(allocator);
        objects.deinit(allocator);
    }

    var statement = try prepare(db,
        \\SELECT type, name, tbl_name, sql
        \\FROM sqlite_schema
        \\WHERE type IN ('table', 'index', 'view', 'trigger')
        \\  AND (
        \\    name GLOB 'tax_*'
        \\    OR name GLOB 'taxpayer_registration_*'
        \\    OR tbl_name GLOB 'tax_*'
        \\    OR tbl_name GLOB 'taxpayer_registration_*'
        \\  )
        \\ORDER BY type COLLATE BINARY ASC,
        \\  name COLLATE BINARY ASC,
        \\  tbl_name COLLATE BINARY ASC;
    );
    defer statement.deinit();
    if (sqlite.sqlite3_stmt_readonly(statement.raw) == 0) {
        return error.NonReadOnlyStatement;
    }

    while (try statement.step() == .row) {
        const object_type_text = columnText(statement.raw, 0) orelse
            return error.InvalidStoredValue;
        const object_type = std.meta.stringToEnum(
            SchemaObjectType,
            object_type_text,
        ) orelse return error.InvalidStoredValue;
        const name = try dupRequiredColumn(allocator, statement.raw, 1);
        errdefer allocator.free(name);
        const table_name = try dupRequiredColumn(allocator, statement.raw, 2);
        errdefer allocator.free(table_name);
        try validateOwnedSchemaObject(object_type, name, table_name);
        const normalized_sql = if (columnText(statement.raw, 3)) |sql_text|
            try normalizeSchemaSql(allocator, sql_text)
        else
            null;
        errdefer if (normalized_sql) |value| allocator.free(value);

        try objects.append(allocator, .{
            .object_type = object_type,
            .name = name,
            .table_name = table_name,
            .normalized_sql = normalized_sql,
        });
    }

    return objects.toOwnedSlice(allocator);
}

fn validateOwnedSchemaObject(
    object_type: SchemaObjectType,
    name: []const u8,
    table_name: []const u8,
) Error!void {
    switch (object_type) {
        .table => {
            const definition = definitionForTable(name) orelse
                return error.InventoryRegistryMismatch;
            if (definition.presence != .table or
                definition.table_name == null or
                !std.mem.eql(u8, definition.table_name.?, name))
            {
                return error.InventoryRegistryMismatch;
            }
        },
        .index, .trigger => {
            const definition = definitionForTable(table_name) orelse
                return error.InventoryRegistryMismatch;
            if (definition.presence != .table) {
                return error.InventoryRegistryMismatch;
            }
        },
        .view => {
            if (!hasOwnedSchemaPrefix(name) or !std.mem.eql(u8, name, table_name)) {
                return error.InventoryRegistryMismatch;
            }
        },
    }
}

fn hasOwnedSchemaPrefix(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "tax_") or
        std.mem.startsWith(u8, name, "taxpayer_registration_");
}

fn normalizeSchemaSql(
    allocator: std.mem.Allocator,
    sql_text: []const u8,
) std.mem.Allocator.Error![]u8 {
    var normalized: std.ArrayList(u8) = .empty;
    errdefer normalized.deinit(allocator);

    var quote_end: ?u8 = null;
    var pending_space = false;
    var index: usize = 0;
    while (index < sql_text.len) : (index += 1) {
        const byte = sql_text[index];
        if (quote_end) |end| {
            try normalized.append(allocator, byte);
            if (byte == end) {
                if (end != ']' and index + 1 < sql_text.len and
                    sql_text[index + 1] == end)
                {
                    index += 1;
                    try normalized.append(allocator, sql_text[index]);
                } else {
                    quote_end = null;
                }
            }
            continue;
        }

        if (std.ascii.isWhitespace(byte)) {
            pending_space = true;
            continue;
        }
        if (pending_space and normalized.items.len != 0) {
            try normalized.append(allocator, ' ');
        }
        pending_space = false;
        try normalized.append(allocator, byte);
        quote_end = switch (byte) {
            '\'', '"', '`' => byte,
            '[' => ']',
            else => null,
        };
    }

    return normalized.toOwnedSlice(allocator);
}

fn deinitSchemaObjects(
    allocator: std.mem.Allocator,
    objects: []SchemaObjectInventory,
) void {
    for (objects) |*object| object.deinit(allocator);
    allocator.free(objects);
}

fn readBooleanInteger(row: *sqlite.sqlite3_stmt, column: c_int) Error!bool {
    if (sqlite.sqlite3_column_type(row, column) != sqlite.SQLITE_INTEGER) {
        return error.InvalidStoredValue;
    }
    return switch (sqlite.sqlite3_column_int64(row, column)) {
        0 => false,
        1 => true,
        else => error.InvalidStoredValue,
    };
}

fn readU32Integer(row: *sqlite.sqlite3_stmt, column: c_int) Error!u32 {
    if (sqlite.sqlite3_column_type(row, column) != sqlite.SQLITE_INTEGER) {
        return error.InvalidStoredValue;
    }
    const value = sqlite.sqlite3_column_int64(row, column);
    if (value < 0 or value > std.math.maxInt(u32)) {
        return error.InvalidStoredValue;
    }
    return @intCast(value);
}

fn fieldOwner(definition: StreamDefinition, column_name: []const u8) FieldOwner {
    const table_name = definition.table_name orelse return .unresolved_legacy_fact;

    if (std.mem.eql(u8, table_name, "tax_profiles")) {
        if (std.mem.eql(u8, column_name, "status") or
            std.mem.eql(u8, column_name, "created_at") or
            std.mem.eql(u8, column_name, "updated_at"))
        {
            return .local_metadata;
        }
        return .migration_control;
    }

    if (std.mem.eql(u8, table_name, "tax_profile_revisions")) {
        if (std.mem.eql(u8, column_name, "tin")) {
            // The legacy value combines a taxpayer root and a variable-width
            // suffix; no single revised owner can be selected without review.
            return .unresolved_legacy_fact;
        }
        if (std.mem.eql(u8, column_name, "rdo_code") or
            std.mem.eql(u8, column_name, "registered_address") or
            std.mem.eql(u8, column_name, "zip_code"))
        {
            return .registration_unit;
        }
        if (std.mem.eql(u8, column_name, "contact_number") or
            std.mem.eql(u8, column_name, "email_address"))
        {
            return .unresolved_legacy_fact;
        }
        if (std.mem.eql(u8, column_name, "subject_kind") or
            std.mem.eql(u8, column_name, "taxpayer_name") or
            std.mem.eql(u8, column_name, "registered_name") or
            std.mem.eql(u8, column_name, "date_of_birth") or
            std.mem.eql(u8, column_name, "citizenship") or
            std.mem.eql(u8, column_name, "foreign_tax_number"))
        {
            return .taxpayer_identity;
        }
        return .migration_control;
    }

    return switch (definition.owner) {
        .base_tax_profile => .local_metadata,
        .identity_history => .unresolved_legacy_fact,
        .relationship_history => .taxpayer_relationship,
        .registration_evidence => .registration_evidence,
        .legacy_registration => .unresolved_legacy_fact,
        .taxpayer_year => .taxpayer_year,
        .tax_form_profile => .tax_form_profile,
        .forms_set => .form_workspace_preference,
        .calendar_selection => .calendar_preference,
        .generic_draft => draftFieldOwner(table_name, column_name, false),
        .exact_draft => draftFieldOwner(table_name, column_name, true),
        .draft_provenance => if (std.mem.indexOf(
            u8,
            table_name,
            "_sources",
        ) != null) .source_attribution else .draft_provenance,
        .occurrence_and_business_key => .occurrence_and_business_key,
        .target_registration_ledger => targetLedgerFieldOwner(table_name),
        .external_calendar => .calendar_preference,
    };
}

fn draftFieldOwner(
    table_name: []const u8,
    column_name: []const u8,
    exact: bool,
) FieldOwner {
    if (std.mem.eql(u8, column_name, "profile_id") or
        std.mem.eql(u8, column_name, "filer_profile_id") or
        std.mem.eql(u8, column_name, "profile_revision_id"))
    {
        return .unresolved_legacy_fact;
    }
    if (std.mem.indexOf(u8, table_name, "binding") != null or
        std.mem.indexOf(u8, table_name, "snapshot") != null)
    {
        return .draft_provenance;
    }
    if (exact and (std.mem.eql(u8, column_name, "workspace_id") or
        std.mem.eql(u8, column_name, "filing_business_key_digest")))
    {
        return .occurrence_and_business_key;
    }
    return .filing_transaction;
}

fn targetLedgerFieldOwner(table_name: []const u8) FieldOwner {
    if (std.mem.indexOf(u8, table_name, "migration_decisions") != null) {
        return .migration_control;
    }
    if (std.mem.indexOf(u8, table_name, "evidence") != null) {
        return .registration_evidence;
    }
    if (std.mem.indexOf(u8, table_name, "tax_type_registration") != null) {
        return .tax_type_registration;
    }
    if (std.mem.indexOf(u8, table_name, "unit") != null or
        std.mem.indexOf(u8, table_name, "branch_code_lineage") != null)
    {
        return .registration_unit;
    }
    return .taxpayer_identity;
}

fn validateStaticContractRegistries() Error!void {
    return validateStaticContractRegistriesFor(
        &runtime_caller_registry,
        &exported_structure_registry,
    );
}

fn validateStaticContractRegistriesFor(
    runtime_callers: []const RuntimeCallerDefinition,
    exported_structures: []const ExportedStructureDefinition,
) Error!void {
    for (runtime_callers, 0..) |caller, index| {
        if (caller.path.len == 0 or caller.stream_id.len == 0) {
            return error.InventoryRegistryMismatch;
        }
        const definition = definitionForStream(caller.stream_id) orelse
            return error.InventoryRegistryMismatch;
        if (definition.disposition != caller.disposition) {
            return error.InventoryRegistryMismatch;
        }
        const canonical_path: ?[]const u8 = switch (caller.role) {
            .registration_ledger => "src/tax_profile/registration_ledger.zig",
            .registration_workspace => "src/tax_profile/registration_workspace.zig",
            .filing_planner => "src/filing/planner.zig",
            else => null,
        };
        if (canonical_path) |path| {
            if (!std.mem.eql(u8, path, caller.path)) {
                return error.InventoryRegistryMismatch;
            }
        }
        for (runtime_callers[0..index]) |previous| {
            if (std.mem.eql(u8, caller.path, previous.path) and
                std.mem.eql(u8, caller.stream_id, previous.stream_id) and
                caller.role == previous.role)
            {
                return error.InventoryRegistryMismatch;
            }
        }
    }

    try validateV28RuntimeCallerCoverage(runtime_callers);

    for (exported_structures, 0..) |surface, index| {
        if (surface.path.len == 0 or surface.symbol.len == 0 or
            surface.stream_id.len == 0)
        {
            return error.InventoryRegistryMismatch;
        }
        const definition = definitionForStream(surface.stream_id) orelse
            return error.InventoryRegistryMismatch;
        if (definition.disposition != surface.disposition) {
            return error.InventoryRegistryMismatch;
        }
        for (exported_structures[0..index]) |previous| {
            if (std.mem.eql(u8, surface.path, previous.path) and
                std.mem.eql(u8, surface.symbol, previous.symbol))
            {
                return error.InventoryRegistryMismatch;
            }
        }
    }
}

const planner_v28_streams = [_][]const u8{
    "taxpayer_registration_taxpayer_revisions",
    "taxpayer_registration_evidence",
    "taxpayer_registration_evidence_review_decisions",
    "taxpayer_registration_evidence_assertions",
    "taxpayer_registration_unit_revisions",
    "taxpayer_registration_unit_contact_revisions",
    "taxpayer_registration_tax_type_registrations",
    "taxpayer_registration_tax_type_registration_revisions",
};

/// Fails closed when a v28 stream disappears from any currently implemented
/// runtime boundary. This coverage is derived from the physical stream
/// registry, so adding a v28 table cannot be made to pass merely by forgetting
/// to add it to `runtime_caller_registry`.
fn validateV28RuntimeCallerCoverage(
    runtime_callers: []const RuntimeCallerDefinition,
) Error!void {
    for (stream_registry) |definition| {
        if (definition.presence != .table or
            definition.introduced_schema_version != 28)
        {
            continue;
        }

        if (std.mem.eql(
            u8,
            definition.stream_id,
            "taxpayer_registration_migration_decisions",
        )) {
            // The reviewed migration cutover remains write-frozen and has no
            // runtime implementation. Listing a caller here would overstate
            // the current readiness boundary.
            for (runtime_callers) |caller| {
                if (std.mem.eql(u8, caller.stream_id, definition.stream_id)) {
                    return error.InventoryRegistryMismatch;
                }
            }
            continue;
        }

        try requireRuntimeCaller(
            runtime_callers,
            definition.stream_id,
            "src/tax_profile/registration_ledger.zig",
            .registration_ledger,
        );
        try requireRuntimeCaller(
            runtime_callers,
            definition.stream_id,
            "src/tax_profile/registration_workspace.zig",
            .registration_workspace,
        );
    }

    for (planner_v28_streams) |stream_id| {
        try requireRuntimeCaller(
            runtime_callers,
            stream_id,
            "src/filing/planner.zig",
            .filing_planner,
        );
    }
}

fn requireRuntimeCaller(
    runtime_callers: []const RuntimeCallerDefinition,
    stream_id: []const u8,
    path: []const u8,
    role: RuntimeCallerRole,
) Error!void {
    var matches: usize = 0;
    for (runtime_callers) |caller| {
        if (std.mem.eql(u8, caller.stream_id, stream_id) and
            std.mem.eql(u8, caller.path, path) and
            caller.role == role)
        {
            matches += 1;
        }
    }
    if (matches != 1) return error.InventoryRegistryMismatch;
}

const WorkspaceOpaqueIdRequirement = struct {
    value_type: []const u8,
    table_name: []const u8,
    column_name: []const u8,
};

const workspace_opaque_id_requirements = [_]WorkspaceOpaqueIdRequirement{
    .{ .value_type = "TaxpayerId", .table_name = "taxpayer_registration_taxpayers", .column_name = "id" },
    .{ .value_type = "TaxpayerRevisionId", .table_name = "taxpayer_registration_taxpayer_revisions", .column_name = "id" },
    .{ .value_type = "RegistrationEvidenceId", .table_name = "taxpayer_registration_evidence", .column_name = "id" },
    .{ .value_type = "RegistrationEvidenceReviewDecisionId", .table_name = "taxpayer_registration_evidence_review_decisions", .column_name = "id" },
    .{ .value_type = "RegistrationEvidenceAssertionId", .table_name = "taxpayer_registration_evidence_assertions", .column_name = "id" },
    .{ .value_type = "RegistrationUnitId", .table_name = "taxpayer_registration_units", .column_name = "id" },
    .{ .value_type = "RegistrationUnitRevisionId", .table_name = "taxpayer_registration_unit_revisions", .column_name = "id" },
    .{ .value_type = "RegistrationUnitContactRevisionId", .table_name = "taxpayer_registration_unit_contact_revisions", .column_name = "id" },
    .{ .value_type = "TaxTypeRegistrationId", .table_name = "taxpayer_registration_tax_type_registrations", .column_name = "id" },
    .{ .value_type = "TaxTypeRegistrationRevisionId", .table_name = "taxpayer_registration_tax_type_registration_revisions", .column_name = "id" },
};

fn validateWorkspaceOpaqueIdCoverage(
    generated_keys: []const GeneratedKeyDefinition,
) Error!void {
    const workspace_path = "src/tax_profile/registration_workspace.zig";
    for (workspace_opaque_id_requirements) |requirement| {
        var matches: usize = 0;
        for (generated_keys) |key| {
            const generator_path = key.generator_path orelse continue;
            const value_type = key.value_type orelse
                return error.InventoryRegistryMismatch;
            if (std.mem.eql(u8, generator_path, workspace_path) and
                std.mem.eql(u8, value_type, requirement.value_type) and
                std.mem.eql(u8, key.table_name, requirement.table_name) and
                std.mem.eql(u8, key.column_name, requirement.column_name) and
                key.authority == .random_local_identity and
                key.disposition == .blocked and
                key.reason == .target_rows_require_reviewed_reconciliation)
            {
                matches += 1;
            }
        }
        if (matches != 1) return error.InventoryRegistryMismatch;
    }

    for (generated_keys) |key| {
        const generator_path = key.generator_path orelse continue;
        if (!std.mem.eql(u8, generator_path, workspace_path)) continue;
        const value_type = key.value_type orelse
            return error.InventoryRegistryMismatch;
        var reviewed = false;
        for (workspace_opaque_id_requirements) |requirement| {
            if (std.mem.eql(u8, value_type, requirement.value_type)) {
                reviewed = true;
                break;
            }
        }
        if (!reviewed) return error.InventoryRegistryMismatch;
    }
}

fn optionalStringsEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn validateWorkspaceOpaqueIdMintSource(
    source: []const u8,
    generated_keys: []const GeneratedKeyDefinition,
) Error!void {
    const call_prefix = "freshId(";
    const type_prefix = "registration.";
    const workspace_path = "src/tax_profile/registration_workspace.zig";
    var search_from: usize = 0;
    var call_count: usize = 0;
    var requirements_seen =
        [_]bool{false} ** workspace_opaque_id_requirements.len;

    while (std.mem.indexOfPos(u8, source, search_from, call_prefix)) |offset| {
        var cursor = offset + call_prefix.len;
        search_from = cursor;
        while (cursor < source.len and std.ascii.isWhitespace(source[cursor])) {
            cursor += 1;
        }
        // Skip the generic helper declaration itself.
        if (std.mem.startsWith(u8, source[cursor..], "comptime")) continue;
        if (!std.mem.startsWith(u8, source[cursor..], type_prefix)) {
            return error.InventoryRegistryMismatch;
        }
        cursor += type_prefix.len;
        const type_start = cursor;
        while (cursor < source.len and
            (std.ascii.isAlphanumeric(source[cursor]) or source[cursor] == '_'))
        {
            cursor += 1;
        }
        if (cursor == type_start) return error.InventoryRegistryMismatch;
        const value_type = source[type_start..cursor];
        for (workspace_opaque_id_requirements, 0..) |requirement, index| {
            if (std.mem.eql(u8, requirement.value_type, value_type)) {
                requirements_seen[index] = true;
            }
        }

        var matches: usize = 0;
        for (generated_keys) |key| {
            const generator_path = key.generator_path orelse continue;
            const registered_type = key.value_type orelse
                return error.InventoryRegistryMismatch;
            if (std.mem.eql(u8, generator_path, workspace_path) and
                std.mem.eql(u8, registered_type, value_type))
            {
                matches += 1;
            }
        }
        if (matches != 1) return error.InventoryRegistryMismatch;
        call_count += 1;
    }

    if (call_count == 0) return error.InventoryRegistryMismatch;
    for (requirements_seen) |seen| {
        if (!seen) return error.InventoryRegistryMismatch;
    }
}

fn validateGeneratedKeyRegistry(fields: []const FieldInventory) Error!void {
    return validateGeneratedKeyRegistryFor(fields, &generated_key_registry);
}

fn validateGeneratedKeyRegistryFor(
    fields: []const FieldInventory,
    generated_keys: []const GeneratedKeyDefinition,
) Error!void {
    for (generated_keys, 0..) |key, index| {
        if (key.key_id.len == 0 or key.table_name.len == 0 or
            key.column_name.len == 0)
        {
            return error.InventoryRegistryMismatch;
        }
        const definition = definitionForTable(key.table_name) orelse
            return error.InventoryRegistryMismatch;
        if (definition.presence != .table) return error.InventoryRegistryMismatch;
        if ((key.generator_path == null) != (key.value_type == null)) {
            return error.InventoryRegistryMismatch;
        }
        if (key.generator_path) |path| {
            if (path.len == 0 or key.value_type.?.len == 0) {
                return error.InventoryRegistryMismatch;
            }
        }

        var matching_fields: usize = 0;
        for (fields) |field_inventory| {
            if (std.mem.eql(u8, field_inventory.table_name, key.table_name) and
                std.mem.eql(u8, field_inventory.column_name, key.column_name))
            {
                matching_fields += 1;
            }
        }
        if (matching_fields != 1) return error.InventoryRegistryMismatch;

        if (index == 0 or !std.mem.eql(
            u8,
            generated_keys[index - 1].key_id,
            key.key_id,
        )) {
            if (key.component_order != 0) return error.InventoryRegistryMismatch;
            for (generated_keys[0..index]) |previous| {
                if (std.mem.eql(u8, previous.key_id, key.key_id)) {
                    return error.InventoryRegistryMismatch;
                }
            }
        } else {
            const previous = generated_keys[index - 1];
            if (key.component_order != previous.component_order + 1 or
                key.authority != previous.authority or
                key.disposition != previous.disposition or
                key.reason != previous.reason or
                !optionalStringsEqual(key.generator_path, previous.generator_path) or
                !optionalStringsEqual(key.value_type, previous.value_type))
            {
                return error.InventoryRegistryMismatch;
            }
        }
    }

    try validateWorkspaceOpaqueIdCoverage(generated_keys);
}

fn computeSchemaContractDigest(
    fields: []const FieldInventory,
    foreign_keys: []const ForeignKeyInventory,
    triggers: []const TriggerInventory,
    schema_objects: []const SchemaObjectInventory,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hashDelimited(&hasher, "tax-profile-migration-inventory");
    hashNumber(&hasher, schema_contract_version);

    hashNumber(&hasher, fields.len);
    for (fields) |field_inventory| {
        hashDelimited(&hasher, field_inventory.table_name);
        hashNumber(&hasher, field_inventory.ordinal);
        hashDelimited(&hasher, field_inventory.column_name);
        hashDelimited(&hasher, field_inventory.declared_type);
        if (field_inventory.default_sql) |default_sql| {
            hashDelimited(&hasher, "default");
            hashDelimited(&hasher, default_sql);
        } else {
            hashDelimited(&hasher, "no-default");
        }
        hashDelimited(&hasher, if (field_inventory.not_null) "not-null" else "nullable");
        hashNumber(&hasher, field_inventory.primary_key_ordinal);
        hashNumber(&hasher, field_inventory.hidden);
        hashDelimited(&hasher, @tagName(field_inventory.owner));
        hashDelimited(&hasher, @tagName(field_inventory.disposition));
        hashDelimited(&hasher, @tagName(field_inventory.reason));
    }

    hashNumber(&hasher, foreign_keys.len);
    for (foreign_keys) |foreign_key| {
        hashDelimited(&hasher, foreign_key.table_name);
        hashNumber(&hasher, foreign_key.id);
        hashNumber(&hasher, foreign_key.sequence);
        hashDelimited(&hasher, foreign_key.referenced_table);
        hashDelimited(&hasher, foreign_key.from_column);
        if (foreign_key.to_column) |to_column| {
            hashDelimited(&hasher, "to-column");
            hashDelimited(&hasher, to_column);
        } else {
            hashDelimited(&hasher, "implicit-primary-key");
        }
        hashDelimited(&hasher, foreign_key.on_update);
        hashDelimited(&hasher, foreign_key.on_delete);
        hashDelimited(&hasher, foreign_key.match);
        hashDelimited(&hasher, @tagName(foreign_key.disposition));
    }

    hashNumber(&hasher, triggers.len);
    for (triggers) |trigger| {
        hashDelimited(&hasher, trigger.table_name);
        hashDelimited(&hasher, trigger.name);
        hashDelimited(&hasher, @tagName(trigger.disposition));
    }

    hashNumber(&hasher, schema_objects.len);
    for (schema_objects) |schema_object| {
        hashDelimited(&hasher, @tagName(schema_object.object_type));
        hashDelimited(&hasher, schema_object.name);
        hashDelimited(&hasher, schema_object.table_name);
        if (schema_object.normalized_sql) |normalized_sql| {
            hashDelimited(&hasher, "sql");
            hashDelimited(&hasher, normalized_sql);
        } else {
            hashDelimited(&hasher, "implicit-sqlite-schema-object");
        }
    }

    hashNumber(&hasher, runtime_caller_registry.len);
    for (runtime_caller_registry) |caller| {
        hashDelimited(&hasher, caller.path);
        hashDelimited(&hasher, caller.stream_id);
        hashDelimited(&hasher, @tagName(caller.role));
        hashDelimited(&hasher, @tagName(caller.disposition));
    }

    hashNumber(&hasher, exported_structure_registry.len);
    for (exported_structure_registry) |surface| {
        hashDelimited(&hasher, surface.path);
        hashDelimited(&hasher, surface.symbol);
        hashDelimited(&hasher, surface.stream_id);
        hashDelimited(&hasher, @tagName(surface.disposition));
    }

    hashNumber(&hasher, generated_key_registry.len);
    for (generated_key_registry) |key| {
        hashDelimited(&hasher, key.key_id);
        hashDelimited(&hasher, key.table_name);
        hashDelimited(&hasher, key.column_name);
        hashNumber(&hasher, key.component_order);
        hashDelimited(&hasher, @tagName(key.authority));
        hashDelimited(&hasher, @tagName(key.disposition));
        hashDelimited(&hasher, @tagName(key.reason));
        if (key.generator_path) |path| {
            hashDelimited(&hasher, "generator-path");
            hashDelimited(&hasher, path);
        } else {
            hashDelimited(&hasher, "no-generator-path");
        }
        if (key.value_type) |value_type| {
            hashDelimited(&hasher, "value-type");
            hashDelimited(&hasher, value_type);
        } else {
            hashDelimited(&hasher, "no-value-type");
        }
    }

    var result: [32]u8 = undefined;
    hasher.final(&result);
    return result;
}

fn hashDelimited(hasher: anytype, value: []const u8) void {
    hasher.update(value);
    hasher.update(&[_]u8{0});
}

fn hashNumber(hasher: anytype, value: anytype) void {
    var buffer: [32]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable;
    hashDelimited(hasher, formatted);
}

fn verifyRegistryCoversSchema(
    db: *sqlite.sqlite3,
    diagnostic_sink: ?RegistryDiagnosticSink,
) Error!void {
    var statement = try prepare(db,
        \\SELECT name
        \\FROM sqlite_schema
        \\WHERE type = 'table'
        \\  AND (
        \\      name GLOB 'tax_*' OR
        \\      name GLOB 'taxpayer_registration_*'
        \\  )
        \\ORDER BY name COLLATE BINARY ASC;
    );
    defer statement.deinit();
    if (sqlite.sqlite3_stmt_readonly(statement.raw) == 0) {
        return error.NonReadOnlyStatement;
    }

    while (try statement.step() == .row) {
        const name = columnText(statement.raw, 0) orelse
            return error.InvalidStoredValue;
        const definition = definitionForTable(name) orelse {
            reportUnknownTable(diagnostic_sink, name);
            return error.InventoryRegistryMismatch;
        };
        if (definition.presence != .table) {
            return error.InventoryRegistryMismatch;
        }
    }
}

fn reportUnknownTable(
    diagnostic_sink: ?RegistryDiagnosticSink,
    table_name: []const u8,
) void {
    if (diagnostic_sink) |sink| {
        sink.unknownTable(table_name);
        return;
    }
    std.log.err(
        "registration inventory has no disposition for table {s}",
        .{table_name},
    );
}

fn definitionForTable(name: []const u8) ?StreamDefinition {
    for (stream_registry) |definition| {
        const registered_name = definition.table_name orelse continue;
        if (std.mem.eql(u8, registered_name, name)) return definition;
    }
    return null;
}

fn definitionForStream(stream_id: []const u8) ?StreamDefinition {
    for (stream_registry) |definition| {
        if (std.mem.eql(u8, definition.stream_id, stream_id)) return definition;
    }
    return null;
}

fn tableExists(db: *sqlite.sqlite3, table_name: []const u8) Error!bool {
    if (!isSqlIdentifier(table_name)) return error.InventoryRegistryMismatch;
    var sql_buffer: [256]u8 = undefined;
    const sql_text = std.fmt.bufPrint(
        &sql_buffer,
        "SELECT COUNT(*) FROM sqlite_schema " ++
            "WHERE type = 'table' AND name = '{s}';",
        .{table_name},
    ) catch unreachable;

    var statement = try prepare(db, sql_text);
    defer statement.deinit();
    if (sqlite.sqlite3_stmt_readonly(statement.raw) == 0) {
        return error.NonReadOnlyStatement;
    }
    if (try statement.step() != .row) return error.InvalidStoredValue;
    const count = sqlite.sqlite3_column_int64(statement.raw, 0);
    if (count < 0 or count > 1) return error.InvalidStoredValue;
    if (try statement.step() != .done) return error.InvalidStoredValue;
    return count == 1;
}

fn countRows(db: *sqlite.sqlite3, table_name: []const u8) Error!u64 {
    if (!isSqlIdentifier(table_name)) return error.InventoryRegistryMismatch;
    var sql_buffer: [192]u8 = undefined;
    const sql_text = std.fmt.bufPrint(
        &sql_buffer,
        "SELECT COUNT(*) FROM \"{s}\";",
        .{table_name},
    ) catch unreachable;

    var statement = try prepare(db, sql_text);
    defer statement.deinit();
    if (sqlite.sqlite3_stmt_readonly(statement.raw) == 0) {
        return error.NonReadOnlyStatement;
    }
    if (try statement.step() != .row) return error.InvalidStoredValue;
    const count = sqlite.sqlite3_column_int64(statement.raw, 0);
    if (count < 0) return error.InvalidStoredValue;
    if (try statement.step() != .done) return error.InvalidStoredValue;
    return @intCast(count);
}

fn isSqlIdentifier(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| {
        if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return false;
    }
    return true;
}

fn readLegacyProfile(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    options: Options,
) Error!OwnedLegacyProfile {
    const profile_id = try dupRequiredColumn(allocator, row, 0);
    errdefer allocator.free(profile_id);
    const profile_status = try dupRequiredColumn(allocator, row, 1);
    errdefer allocator.free(profile_status);
    const current_revision_id = try dupOptionalColumn(allocator, row, 2);
    errdefer if (current_revision_id) |value| allocator.free(value);

    const has_current_revision = columnText(row, 3) != null;
    const sequence = readCurrentRevisionSequence(row, has_current_revision);
    const raw_tin = columnText(row, 5);
    var tin_inspection = try inspectTin(allocator, raw_tin, options.tin_visibility);
    errdefer tin_inspection.fact.deinit(allocator);

    var reason_buffer: [3]DispositionReason = undefined;
    var reason_count: usize = 0;
    if (!has_current_revision) {
        reason_buffer[reason_count] = .current_revision_missing;
        reason_count += 1;
    } else {
        if (!sequence.valid) {
            reason_buffer[reason_count] = .current_revision_sequence_invalid;
            reason_count += 1;
        }
        if (raw_tin == null) {
            reason_buffer[reason_count] = .current_revision_tin_missing;
            reason_count += 1;
        } else if (!tin_inspection.valid) {
            reason_buffer[reason_count] = .current_revision_tin_malformed;
            reason_count += 1;
        } else if (tin_inspection.has_unsupported_suffix) {
            reason_buffer[reason_count] = .legacy_suffix_not_five_digits;
            reason_count += 1;
        }
    }

    const disposition: MigrationDisposition = if (reason_count == 0) .legacy_read_only else .blocked;
    if (reason_count == 0) {
        reason_buffer[0] = .automatic_mapping_not_authorized;
        reason_count = 1;
    }
    const reasons = try allocator.dupe(DispositionReason, reason_buffer[0..reason_count]);
    errdefer allocator.free(reasons);

    return .{
        .profile_id = profile_id,
        .profile_status = profile_status,
        .current_revision_id = current_revision_id,
        .current_revision_sequence = sequence.value,
        .has_current_revision = has_current_revision,
        .current_tin = tin_inspection.fact,
        .disposition = disposition,
        .reasons = reasons,
    };
}

const SequenceInspection = struct {
    value: ?u32,
    valid: bool,
};

fn readCurrentRevisionSequence(
    row: *sqlite.sqlite3_stmt,
    has_current_revision: bool,
) SequenceInspection {
    if (!has_current_revision) return .{ .value = null, .valid = true };
    if (sqlite.sqlite3_column_type(row, 4) != sqlite.SQLITE_INTEGER) {
        return .{ .value = null, .valid = false };
    }
    const value = sqlite.sqlite3_column_int64(row, 4);
    if (value < 1 or value > std.math.maxInt(u32)) {
        return .{ .value = null, .valid = false };
    }
    return .{ .value = @intCast(value), .valid = true };
}

const TinInspection = struct {
    fact: OwnedTinSuffixFact,
    valid: bool,
    has_unsupported_suffix: bool,
};

fn inspectTin(
    allocator: std.mem.Allocator,
    raw_tin: ?[]const u8,
    visibility: TinVisibility,
) Error!TinInspection {
    const raw = raw_tin orelse return .{
        .fact = try missingTinFact(allocator),
        .valid = false,
        .has_unsupported_suffix = false,
    };
    const parsed = field.Tin.parse(raw) catch return .{
        .fact = try malformedTinFact(allocator),
        .valid = false,
        .has_unsupported_suffix = false,
    };
    const suffix = parsed.branch();
    const suffix_digit_count: u8 = if (suffix) |value| @intCast(value.len) else 0;
    const kind: TinSuffixKind = switch (suffix_digit_count) {
        0 => .no_suffix,
        5 => .five_digit_candidate,
        else => .unsupported_legacy_length,
    };

    return .{
        .fact = try renderValidTinFact(allocator, &parsed, visibility, kind, suffix_digit_count),
        .valid = true,
        .has_unsupported_suffix = suffix_digit_count != 0 and suffix_digit_count != 5,
    };
}

fn missingTinFact(allocator: std.mem.Allocator) std.mem.Allocator.Error!OwnedTinSuffixFact {
    return .{
        .display_tin = try allocator.dupe(u8, "<missing legacy TIN>"),
        .root = null,
        .suffix = null,
        .suffix_digit_count = null,
        .kind = .missing,
    };
}

fn malformedTinFact(allocator: std.mem.Allocator) std.mem.Allocator.Error!OwnedTinSuffixFact {
    return .{
        .display_tin = try allocator.dupe(u8, "<malformed legacy TIN>"),
        .root = null,
        .suffix = null,
        .suffix_digit_count = null,
        .kind = .malformed,
    };
}

fn renderValidTinFact(
    allocator: std.mem.Allocator,
    tin: *const field.Tin,
    visibility: TinVisibility,
    kind: TinSuffixKind,
    suffix_digit_count: u8,
) std.mem.Allocator.Error!OwnedTinSuffixFact {
    var display_buffer: [18]u8 = undefined;
    const display = switch (visibility) {
        // Maximum normalized output is `000-000-000-00000` (17 bytes), so
        // this fixed buffer makes either diagnostic writer infallible here.
        .masked => tin.writeMasked(&display_buffer) catch unreachable,
        .unmasked => tin.write(&display_buffer) catch unreachable,
    };
    const display_tin = try allocator.dupe(u8, display);
    errdefer allocator.free(display_tin);

    const root = switch (visibility) {
        .masked => try std.fmt.allocPrint(allocator, "***-***-{s}", .{tin.root()[6..9]}),
        .unmasked => try allocator.dupe(u8, tin.root()),
    };
    errdefer allocator.free(root);

    var owned_suffix: ?[]u8 = null;
    errdefer if (owned_suffix) |value| allocator.free(value);
    if (tin.branch()) |suffix| {
        owned_suffix = switch (visibility) {
            .masked => try allocator.dupe(u8, "***"),
            .unmasked => try allocator.dupe(u8, suffix),
        };
    }

    return .{
        .display_tin = display_tin,
        .root = root,
        .suffix = owned_suffix,
        .suffix_digit_count = suffix_digit_count,
        .kind = kind,
    };
}

const StepResult = enum { row, done };

const Statement = struct {
    raw: *sqlite.sqlite3_stmt,

    fn deinit(self: *Statement) void {
        _ = sqlite.sqlite3_finalize(self.raw);
        self.* = undefined;
    }

    fn step(self: *Statement) Error!StepResult {
        return switch (sqlite.sqlite3_step(self.raw)) {
            sqlite.SQLITE_ROW => .row,
            sqlite.SQLITE_DONE => .done,
            else => |rc| mapResult(rc),
        };
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

/// `Store` owns its own C import. Convert its opaque SQLite handle at the
/// adapter boundary so this module's direct-query C calls use one C-import
/// type without exposing a new Store method.
fn databaseHandle(profile_store: *store.Store) Error!*sqlite.sqlite3 {
    const raw = profile_store.db orelse return error.Closed;
    return @ptrCast(raw);
}

fn dupRequiredColumn(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error![]u8 {
    const value = columnText(row, column) orelse return error.InvalidStoredValue;
    return allocator.dupe(u8, value);
}

fn dupOptionalColumn(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) Error!?[]u8 {
    const value = columnText(row, column) orelse return null;
    return @as(?[]u8, try allocator.dupe(u8, value));
}

fn columnText(row: *sqlite.sqlite3_stmt, column: c_int) ?[]const u8 {
    if (sqlite.sqlite3_column_type(row, column) == sqlite.SQLITE_NULL) return null;
    const raw = sqlite.sqlite3_column_text(row, column) orelse return null;
    const length = sqlite.sqlite3_column_bytes(row, column);
    if (length < 0) return null;
    const bytes: [*]const u8 = @ptrCast(raw);
    return bytes[0..@intCast(length)];
}

fn execReadTransaction(db: *sqlite.sqlite3, sql_text: [*:0]const u8) Error!void {
    const rc = sqlite.sqlite3_exec(db, sql_text, null, null, null);
    if (rc != sqlite.SQLITE_OK) return mapResult(rc);
}

fn rollbackReadTransactionNoFail(db: *sqlite.sqlite3) void {
    _ = sqlite.sqlite3_exec(db, "ROLLBACK;", null, null, null);
}

fn mapResult(rc: c_int) Error {
    return switch (rc & 0xff) {
        sqlite.SQLITE_BUSY, sqlite.SQLITE_LOCKED => error.SqliteBusy,
        sqlite.SQLITE_CONSTRAINT => error.SqliteConstraint,
        else => error.SqliteFailure,
    };
}

test "v28 runtime caller and generated-key registries fail closed on omissions" {
    try validateStaticContractRegistries();

    var incomplete_callers: std.ArrayList(RuntimeCallerDefinition) = .empty;
    defer incomplete_callers.deinit(std.testing.allocator);
    for (runtime_caller_registry) |caller| {
        if (caller.role == .registration_workspace and
            std.mem.eql(
                u8,
                caller.stream_id,
                "taxpayer_registration_taxpayers",
            ))
        {
            continue;
        }
        try incomplete_callers.append(std.testing.allocator, caller);
    }
    try std.testing.expectError(
        error.InventoryRegistryMismatch,
        validateStaticContractRegistriesFor(
            incomplete_callers.items,
            &exported_structure_registry,
        ),
    );

    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    const fields = try collectFields(
        std.testing.allocator,
        try databaseHandle(&profile_store),
    );
    defer deinitFields(std.testing.allocator, fields);
    try validateGeneratedKeyRegistry(fields);

    var incomplete_keys: std.ArrayList(GeneratedKeyDefinition) = .empty;
    defer incomplete_keys.deinit(std.testing.allocator);
    for (generated_key_registry) |key| {
        if (key.value_type) |value_type| {
            if (std.mem.eql(u8, value_type, "RegistrationEvidenceAssertionId")) {
                continue;
            }
        }
        try incomplete_keys.append(std.testing.allocator, key);
    }
    try std.testing.expectError(
        error.InventoryRegistryMismatch,
        validateGeneratedKeyRegistryFor(fields, incomplete_keys.items),
    );

    var malformed_keys = generated_key_registry;
    malformed_keys[malformed_keys.len - 1].value_type = null;
    try std.testing.expectError(
        error.InventoryRegistryMismatch,
        validateGeneratedKeyRegistryFor(fields, &malformed_keys),
    );
}

test "v28 runtime registry entries remain anchored to actual source seams" {
    const ledger_source = @embedFile("registration_ledger.zig");
    const workspace_source = @embedFile("registration_workspace.zig");
    const planner_source = @embedFile("../filing/planner.zig");

    for (stream_registry) |definition| {
        if (definition.presence != .table or
            definition.introduced_schema_version != 28)
        {
            continue;
        }
        const in_ledger = std.mem.indexOf(
            u8,
            ledger_source,
            definition.stream_id,
        ) != null;
        if (std.mem.eql(
            u8,
            definition.stream_id,
            "taxpayer_registration_migration_decisions",
        )) {
            try std.testing.expect(!in_ledger);
        } else {
            try std.testing.expect(in_ledger);
        }
    }

    for ([_][]const u8{
        "ledger.listTaxpayerIds(",
        "ledger.snapshot(",
        "ledger.apply(",
        "ledger.recordReviewedEvidenceBundle(",
    }) |anchor| {
        try std.testing.expect(std.mem.indexOf(u8, workspace_source, anchor) != null);
    }
    try std.testing.expect(std.mem.indexOf(
        u8,
        planner_source,
        "ledger.planningSnapshotWithEvidenceIntegrity(",
    ) != null);
}

test "workspace opaque ID mint sites are completely inventoried" {
    try validateWorkspaceOpaqueIdMintSource(
        @embedFile("registration_workspace.zig"),
        &generated_key_registry,
    );
}

test "inventory uses one snapshot while an external WAL writer commits" {
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
        "{s}/migration-inventory-snapshot.sqlite3",
        .{directory_path[0..directory_length]},
    );
    const capability =
        key_custody.bootstrapCurrentArtifactStorage().development_plaintext;

    var reader = try store.Store.testingOpenLatestDevelopmentPlaintext(
        capability,
        allocator,
        database_path,
    );
    defer reader.close();
    try reader.createProfile(.{ .id = "snapshot-before" });

    var writer = try store.Store.testingOpenLatestDevelopmentPlaintext(
        capability,
        allocator,
        database_path,
    );
    defer writer.close();

    const ExternalWrite = struct {
        writer: *store.Store,
        failed: bool = false,

        fn afterProfiles(context: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.writer.createProfile(.{ .id = "snapshot-during" }) catch {
                self.failed = true;
            };
        }
    };
    var external_write: ExternalWrite = .{ .writer = &writer };
    var inventory = try collectWithOptionsAndHook(
        allocator,
        &reader,
        .{},
        .{
            .context = &external_write,
            .after_profiles_fn = ExternalWrite.afterProfiles,
        },
    );
    defer inventory.deinit(allocator);

    try std.testing.expect(!external_write.failed);
    try std.testing.expectEqual(@as(usize, 1), inventory.profiles.len);
    try std.testing.expectEqual(
        @as(?u64, 1),
        findStream(&inventory, "tax_profiles").?.row_count,
    );

    var after = try collect(allocator, &reader);
    defer after.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), after.profiles.len);
    try std.testing.expectEqual(
        @as(?u64, 2),
        findStream(&after, "tax_profiles").?.row_count,
    );
}

test "inventory is deterministic, masked by default, and observes zero writes" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();

    try createFixtureProfile(
        &profile_store,
        "alpha-profile",
        "alpha-revision-1",
        "12345678900000",
    );
    try createFixtureProfile(
        &profile_store,
        "beta-profile",
        "beta-revision-1",
        "987654321001",
    );
    try createFixtureProfile(
        &profile_store,
        "gamma-profile",
        "gamma-revision-1",
        "5555555550001",
    );
    try profile_store.createProfile(.{ .id = "orphan-profile", .status = .archived });
    try createFixtureProfile(
        &profile_store,
        "root-only-profile",
        "root-only-revision-1",
        "444444444",
    );

    const db = try databaseHandle(&profile_store);
    const changes_before = sqlite.sqlite3_total_changes64(db);
    var first = try collect(std.testing.allocator, &profile_store);
    defer first.deinit(std.testing.allocator);
    const changes_after = sqlite.sqlite3_total_changes64(db);

    try std.testing.expect(first.read_only_proof.verifiedNoWrites());
    try std.testing.expectEqual(changes_before, first.read_only_proof.total_changes_before);
    try std.testing.expectEqual(changes_before, first.read_only_proof.total_changes_after);
    try std.testing.expectEqual(changes_before, changes_after);
    try std.testing.expectEqual(@as(usize, 5), first.profiles.len);

    const alpha = first.profiles[0];
    try std.testing.expectEqualStrings("alpha-profile", alpha.profile_id);
    try std.testing.expectEqual(MigrationDisposition.legacy_read_only, alpha.disposition);
    try std.testing.expectEqual(TinSuffixKind.five_digit_candidate, alpha.current_tin.kind);
    try std.testing.expectEqual(@as(?u8, 5), alpha.current_tin.suffix_digit_count);
    try std.testing.expectEqualStrings("***-***-789-***", alpha.current_tin.display_tin);
    try std.testing.expectEqualStrings("***-***-789", alpha.current_tin.root.?);
    try std.testing.expectEqualStrings("***", alpha.current_tin.suffix.?);
    try std.testing.expectEqual(@as(usize, 1), alpha.reasons.len);
    try std.testing.expectEqual(
        DispositionReason.automatic_mapping_not_authorized,
        alpha.reasons[0],
    );
    try std.testing.expect(std.mem.indexOf(u8, alpha.current_tin.display_tin, "123456789") == null);

    const beta = first.profiles[1];
    try std.testing.expectEqual(MigrationDisposition.blocked, beta.disposition);
    try std.testing.expectEqual(TinSuffixKind.unsupported_legacy_length, beta.current_tin.kind);
    try std.testing.expectEqual(@as(?u8, 3), beta.current_tin.suffix_digit_count);
    try std.testing.expectEqual(@as(usize, 1), beta.reasons.len);
    try std.testing.expectEqual(
        DispositionReason.legacy_suffix_not_five_digits,
        beta.reasons[0],
    );

    const gamma = first.profiles[2];
    try std.testing.expectEqual(MigrationDisposition.blocked, gamma.disposition);
    try std.testing.expectEqual(TinSuffixKind.unsupported_legacy_length, gamma.current_tin.kind);
    try std.testing.expectEqual(@as(?u8, 4), gamma.current_tin.suffix_digit_count);
    try std.testing.expectEqual(
        DispositionReason.legacy_suffix_not_five_digits,
        gamma.reasons[0],
    );

    const orphan = first.profiles[3];
    try std.testing.expectEqual(MigrationDisposition.blocked, orphan.disposition);
    try std.testing.expect(!orphan.has_current_revision);
    try std.testing.expectEqual(TinSuffixKind.missing, orphan.current_tin.kind);
    try std.testing.expectEqual(
        DispositionReason.current_revision_missing,
        orphan.reasons[0],
    );

    const root_only = first.profiles[4];
    try std.testing.expectEqual(MigrationDisposition.legacy_read_only, root_only.disposition);
    try std.testing.expectEqual(TinSuffixKind.no_suffix, root_only.current_tin.kind);
    try std.testing.expectEqual(@as(?u8, 0), root_only.current_tin.suffix_digit_count);

    var second = try collect(std.testing.allocator, &profile_store);
    defer second.deinit(std.testing.allocator);
    try std.testing.expect(second.read_only_proof.verifiedNoWrites());
    try std.testing.expectEqual(first.profiles.len, second.profiles.len);
    for (first.profiles, second.profiles) |left, right| {
        try std.testing.expectEqualStrings(left.profile_id, right.profile_id);
        try std.testing.expectEqual(left.disposition, right.disposition);
        try std.testing.expectEqual(left.current_tin.kind, right.current_tin.kind);
        try std.testing.expectEqual(left.current_tin.suffix_digit_count, right.current_tin.suffix_digit_count);
        try std.testing.expectEqualStrings(left.current_tin.display_tin, right.current_tin.display_tin);
    }
}

test "unmasked display remains an explicit diagnostic choice and never makes mapping safe" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    try createFixtureProfile(
        &profile_store,
        "unmasked-profile",
        "unmasked-revision-1",
        "12345678900000",
    );

    var inventory = try collectWithOptions(
        std.testing.allocator,
        &profile_store,
        .{ .tin_visibility = .unmasked },
    );
    defer inventory.deinit(std.testing.allocator);

    const profile = inventory.profiles[0];
    try std.testing.expectEqualStrings("123-456-789-00000", profile.current_tin.display_tin);
    try std.testing.expectEqual(MigrationDisposition.legacy_read_only, profile.disposition);
    try std.testing.expect(
        std.meta.stringToEnum(MigrationDisposition, "safe_to_map") == null,
    );
}

fn createFixtureProfile(
    profile_store: *store.Store,
    profile_id: []const u8,
    revision_id: []const u8,
    tin: []const u8,
) !void {
    try profile_store.createProfileWithRevision(
        .{ .id = profile_id, .status = .active },
        .{
            .id = revision_id,
            .profile_id = profile_id,
            .sequence = 1,
            .expected_current_sequence = 0,
            .effective = .{ .from = dateText("2026-01-01") },
            .source = .{ .imported = "migration inventory fixture" },
            .identity = .{ .tin = tin, .rdo_code = "040" },
            .contact = .{
                .registered_address = "123 Sample Street",
                .zip_code = "1100",
                .contact_number = "+639000000000",
                .email_address = "fixture@example.test",
            },
            .subject = .{ .sole_proprietor = .{
                .person = .{
                    .name = "Migration Inventory Fixture",
                    .date_of_birth = dateText("1990-01-01"),
                    .citizenship = "PH",
                },
                .trade_name = "Fixture Trade",
            } },
            .accounting_period_basis = .calendar,
        },
    );
}

fn dateText(comptime text: []const u8) store.DateText {
    comptime std.debug.assert(text.len == 10);
    return text[0..10].*;
}

test "stream inventory is schema complete deterministic and count bounded" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();

    try createFixtureProfile(
        &profile_store,
        "stream-count-profile",
        "stream-count-revision-1",
        "12345678900000",
    );

    const db = try databaseHandle(&profile_store);
    const changes_before = sqlite.sqlite3_total_changes64(db);

    var first = try collect(std.testing.allocator, &profile_store);
    defer first.deinit(std.testing.allocator);
    var second = try collect(std.testing.allocator, &profile_store);
    defer second.deinit(std.testing.allocator);

    try std.testing.expect(first.read_only_proof.verifiedNoWrites());
    try std.testing.expect(second.read_only_proof.verifiedNoWrites());
    try std.testing.expectEqual(
        changes_before,
        sqlite.sqlite3_total_changes64(db),
    );
    try std.testing.expectEqual(stream_registry.len, first.streams.len);
    try std.testing.expectEqual(first.streams.len, second.streams.len);

    for (stream_registry, 0..) |definition, index| {
        for (stream_registry[index + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(
                u8,
                definition.stream_id,
                other.stream_id,
            ));
            if (definition.table_name != null and other.table_name != null) {
                try std.testing.expect(!std.mem.eql(
                    u8,
                    definition.table_name.?,
                    other.table_name.?,
                ));
            }
        }
        if (definition.presence == .table) {
            try std.testing.expect(definition.table_name != null);
            try std.testing.expect(
                definition.introduced_schema_version.? <=
                    store.latest_schema_version,
            );
        }
    }

    var dispositions_seen =
        [_]bool{false} ** std.meta.fields(MigrationDisposition).len;
    for (first.streams, second.streams) |left, right| {
        try std.testing.expect(std.meta.eql(left.definition, right.definition));
        try std.testing.expectEqual(left.row_count, right.row_count);
        dispositions_seen[@intFromEnum(left.definition.disposition)] = true;

        switch (left.definition.presence) {
            .table => try std.testing.expect(left.row_count != null),
            .absent, .external_not_owned => try std.testing.expectEqual(@as(?u64, null), left.row_count),
        }
    }
    for (dispositions_seen) |seen| try std.testing.expect(seen);

    const profiles = findStream(&first, "tax_profiles").?;
    try std.testing.expectEqual(@as(?u64, 1), profiles.row_count);
    try std.testing.expectEqual(MigrationDisposition.rekey, profiles.definition.disposition);

    const revisions = findStream(&first, "tax_profile_revisions").?;
    try std.testing.expectEqual(@as(?u64, 1), revisions.row_count);
    try std.testing.expectEqual(MigrationDisposition.split, revisions.definition.disposition);

    const cor_documents = findStream(&first, "tax_profile_cor_documents").?;
    try std.testing.expectEqual(@as(?u64, 0), cor_documents.row_count);
    try std.testing.expectEqual(OwnerCategory.registration_evidence, cor_documents.definition.owner);

    const exact_business_keys = findStream(&first, "tax_exact_draft_streams").?;
    try std.testing.expectEqual(
        OwnerCategory.occurrence_and_business_key,
        exact_business_keys.definition.owner,
    );

    const rejected_pilot = findStream(
        &first,
        "tax_profile_annual_income_tax_election_events",
    ).?;
    try std.testing.expectEqual(StreamPresence.absent, rejected_pilot.definition.presence);
    try std.testing.expectEqual(@as(?u64, null), rejected_pilot.row_count);

    const calendar_export = findStream(&first, "calendar_export_artifacts").?;
    try std.testing.expectEqual(
        StreamPresence.external_not_owned,
        calendar_export.definition.presence,
    );
    try std.testing.expect(calendar_export.definition.dependencies.external_repository);

    for (first.streams) |stream| {
        if (stream.definition.presence != .table) continue;
        const version = stream.definition.introduced_schema_version orelse
            return error.TestUnexpectedResult;
        if (version <= 27) {
            try std.testing.expect(stream.row_count != null);
        }
    }
}

test "field foreign key trigger and code contract inventories are deterministic" {
    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();

    var first = try collect(std.testing.allocator, &profile_store);
    defer first.deinit(std.testing.allocator);
    var second = try collect(std.testing.allocator, &profile_store);
    defer second.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(
        u8,
        &expected_schema_contract_digest,
        &first.schema_contract_digest,
    );
    try std.testing.expectEqualSlices(
        u8,
        &first.schema_contract_digest,
        &second.schema_contract_digest,
    );

    try std.testing.expect(first.fields.len > 0);
    try std.testing.expectEqual(first.fields.len, second.fields.len);
    for (first.fields, second.fields) |left, right| {
        try std.testing.expectEqualStrings(left.table_name, right.table_name);
        try std.testing.expectEqual(left.ordinal, right.ordinal);
        try std.testing.expectEqualStrings(left.column_name, right.column_name);
        try std.testing.expectEqualStrings(left.declared_type, right.declared_type);
        try expectOptionalStringsEqual(left.default_sql, right.default_sql);
        try std.testing.expectEqual(left.not_null, right.not_null);
        try std.testing.expectEqual(left.primary_key_ordinal, right.primary_key_ordinal);
        try std.testing.expectEqual(left.hidden, right.hidden);
        try std.testing.expectEqual(left.owner, right.owner);
        try std.testing.expectEqual(left.disposition, right.disposition);
        try std.testing.expectEqual(left.reason, right.reason);
    }

    try std.testing.expectEqual(first.foreign_keys.len, second.foreign_keys.len);
    for (first.foreign_keys, second.foreign_keys) |left, right| {
        try std.testing.expectEqualStrings(left.table_name, right.table_name);
        try std.testing.expectEqual(left.id, right.id);
        try std.testing.expectEqual(left.sequence, right.sequence);
        try std.testing.expectEqualStrings(left.referenced_table, right.referenced_table);
        try std.testing.expectEqualStrings(left.from_column, right.from_column);
        try expectOptionalStringsEqual(left.to_column, right.to_column);
        try std.testing.expectEqualStrings(left.on_update, right.on_update);
        try std.testing.expectEqualStrings(left.on_delete, right.on_delete);
        try std.testing.expectEqualStrings(left.match, right.match);
        try std.testing.expectEqual(left.disposition, right.disposition);
    }

    try std.testing.expect(first.triggers.len > 0);
    try std.testing.expectEqual(first.triggers.len, second.triggers.len);
    for (first.triggers, second.triggers) |left, right| {
        try std.testing.expectEqualStrings(left.table_name, right.table_name);
        try std.testing.expectEqualStrings(left.name, right.name);
        try std.testing.expectEqualStrings(left.sql, right.sql);
        try std.testing.expectEqual(left.disposition, right.disposition);
    }

    try std.testing.expect(first.schema_objects.len > first.triggers.len);
    try std.testing.expectEqual(
        first.schema_objects.len,
        second.schema_objects.len,
    );
    for (first.schema_objects, second.schema_objects) |left, right| {
        try std.testing.expectEqual(left.object_type, right.object_type);
        try std.testing.expectEqualStrings(left.name, right.name);
        try std.testing.expectEqualStrings(left.table_name, right.table_name);
        try expectOptionalStringsEqual(left.normalized_sql, right.normalized_sql);
    }

    try std.testing.expectEqual(runtime_caller_registry.len, first.runtime_callers.len);
    try std.testing.expectEqual(
        exported_structure_registry.len,
        first.exported_structures.len,
    );
    try std.testing.expectEqual(generated_key_registry.len, first.generated_keys.len);

    try std.testing.expectEqual(
        FieldOwner.unresolved_legacy_fact,
        findField(&first, "tax_profile_revisions", "tin").?.owner,
    );
    try std.testing.expectEqual(
        FieldOwner.registration_unit,
        findField(&first, "tax_profile_revisions", "rdo_code").?.owner,
    );
    try std.testing.expectEqual(
        FieldOwner.taxpayer_identity,
        findField(&first, "tax_profile_revisions", "registered_name").?.owner,
    );
    try std.testing.expectEqual(
        FieldOwner.form_workspace_preference,
        findField(
            &first,
            "tax_profile_form_set_decisions",
            "form_code",
        ).?.owner,
    );
    try std.testing.expectEqual(
        FieldOwner.occurrence_and_business_key,
        findField(&first, "tax_exact_draft_streams", "workspace_id").?.owner,
    );
    try std.testing.expectEqual(
        FieldOwner.taxpayer_identity,
        findField(
            &first,
            "taxpayer_registration_taxpayer_revisions",
            "effective_until",
        ).?.owner,
    );
    try std.testing.expectEqual(
        FieldOwner.registration_unit,
        findField(
            &first,
            "taxpayer_registration_unit_revisions",
            "effective_until",
        ).?.owner,
    );
    try std.testing.expectEqual(
        FieldOwner.registration_unit,
        findField(
            &first,
            "taxpayer_registration_unit_contact_revisions",
            "registered_address",
        ).?.owner,
    );
    try std.testing.expectEqual(
        FieldOwner.tax_type_registration,
        findField(
            &first,
            "taxpayer_registration_tax_type_registration_revisions",
            "effective_until",
        ).?.owner,
    );
    try std.testing.expect(foreignKeyExists(
        &first,
        "tax_profile_revisions",
        "profile_id",
        "tax_profiles",
        "id",
    ));
    const immutable_revision_trigger = findTrigger(
        &first,
        "tax_profile_revisions_immutable",
    ).?;
    try std.testing.expect(std.mem.indexOf(
        u8,
        immutable_revision_trigger.sql,
        "append-only",
    ) != null);
    const effective_tin_guard = findTrigger(
        &first,
        "taxpayer_registration_taxpayer_revisions_tin_guard",
    ).?;
    try std.testing.expect(std.mem.indexOf(
        u8,
        effective_tin_guard.sql,
        "duplicate effective TIN root",
    ) != null);
    const authoritative_review_guard = findTrigger(
        &first,
        "taxpayer_registration_evidence_review_authoritative_storage_guard",
    ).?;
    try std.testing.expect(std.mem.indexOf(
        u8,
        authoritative_review_guard.sql,
        "accepted evidence requires authoritative storage",
    ) != null);
    const assertion_freeze_guard = findTrigger(
        &first,
        "taxpayer_registration_evidence_assertions_review_freeze_guard",
    ).?;
    try std.testing.expect(std.mem.indexOf(
        u8,
        assertion_freeze_guard.sql,
        "assertion set frozen at first review",
    ) != null);
}

test "unreviewed field or trigger changes fail the schema contract closed" {
    {
        var profile_store = try store.Store.openMemory(std.testing.allocator);
        defer profile_store.close();
        const db = try databaseHandle(&profile_store);
        var add_column = try prepare(
            db,
            "ALTER TABLE tax_profiles ADD COLUMN unreviewed_identity TEXT;",
        );
        defer add_column.deinit();
        try std.testing.expectEqual(StepResult.done, try add_column.step());
        try std.testing.expectError(
            error.InventoryRegistryMismatch,
            collect(std.testing.allocator, &profile_store),
        );
    }

    {
        var profile_store = try store.Store.openMemory(std.testing.allocator);
        defer profile_store.close();
        const db = try databaseHandle(&profile_store);
        var add_trigger = try prepare(db,
            \\CREATE TRIGGER tax_profiles_unreviewed_test
            \\AFTER INSERT ON tax_profiles
            \\BEGIN
            \\    SELECT 1;
            \\END;
        );
        defer add_trigger.deinit();
        try std.testing.expectEqual(StepResult.done, try add_trigger.step());
        try std.testing.expectError(
            error.InventoryRegistryMismatch,
            collect(std.testing.allocator, &profile_store),
        );
    }
}

test "weakened table index and view SQL fail the exact schema contract closed" {
    {
        var profile_store = try store.Store.openMemory(std.testing.allocator);
        defer profile_store.close();
        var inventory = try collect(std.testing.allocator, &profile_store);
        defer inventory.deinit(std.testing.allocator);
        var unit_table: ?*SchemaObjectInventory = null;
        for (inventory.schema_objects) |*schema_object| {
            if (schema_object.object_type == .table and std.mem.eql(
                u8,
                schema_object.name,
                "taxpayer_registration_units",
            )) {
                unit_table = schema_object;
                break;
            }
        }
        const table_sql = unit_table.?.normalized_sql.?;
        const unique_offset = std.mem.indexOf(
            u8,
            table_sql,
            "UNIQUE (id, taxpayer_id)",
        ) orelse return error.TestUnexpectedResult;
        @memcpy(table_sql[unique_offset .. unique_offset + 6], "CHECK ");
        const weakened_digest = computeSchemaContractDigest(
            inventory.fields,
            inventory.foreign_keys,
            inventory.triggers,
            inventory.schema_objects,
        );
        try std.testing.expect(!std.mem.eql(
            u8,
            &weakened_digest,
            &expected_schema_contract_digest,
        ));
    }

    {
        var profile_store = try store.Store.openMemory(std.testing.allocator);
        defer profile_store.close();
        const db = try databaseHandle(&profile_store);
        var drop_index = try prepare(
            db,
            "DROP INDEX taxpayer_registration_unit_contact_effective_idx;",
        );
        defer drop_index.deinit();
        try std.testing.expectEqual(StepResult.done, try drop_index.step());
        try std.testing.expectError(
            error.InventoryRegistryMismatch,
            collect(std.testing.allocator, &profile_store),
        );
    }

    {
        var profile_store = try store.Store.openMemory(std.testing.allocator);
        defer profile_store.close();
        const db = try databaseHandle(&profile_store);
        var drop_view = try prepare(
            db,
            "DROP VIEW taxpayer_registration_current_evidence_reviews;",
        );
        defer drop_view.deinit();
        try std.testing.expectEqual(StepResult.done, try drop_view.step());
        var weaken_view = try prepare(db,
            \\CREATE VIEW taxpayer_registration_current_evidence_reviews AS
            \\SELECT id AS decision_id, evidence_id
            \\FROM taxpayer_registration_evidence_review_decisions;
        );
        defer weaken_view.deinit();
        try std.testing.expectEqual(StepResult.done, try weaken_view.step());
        try std.testing.expectError(
            error.InventoryRegistryMismatch,
            collect(std.testing.allocator, &profile_store),
        );
    }
}

test "unregistered future tax profile table fails inventory closed" {
    const DiagnosticCapture = struct {
        count: usize = 0,
        saw_expected_table: bool = false,

        fn unknownTable(context: *anyopaque, table_name: []const u8) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.count += 1;
            self.saw_expected_table = std.mem.eql(
                u8,
                table_name,
                "tax_profile_unclassified_test_only",
            );
        }
    };

    var profile_store = try store.Store.openMemory(std.testing.allocator);
    defer profile_store.close();
    const db = try databaseHandle(&profile_store);

    var create = try prepare(
        db,
        "CREATE TABLE tax_profile_unclassified_test_only (id TEXT);",
    );
    defer create.deinit();
    try std.testing.expectEqual(StepResult.done, try create.step());

    var diagnostic_capture: DiagnosticCapture = .{};
    try std.testing.expectError(
        error.InventoryRegistryMismatch,
        collectWithOptionsAndDiagnosticSink(
            std.testing.allocator,
            &profile_store,
            .{},
            .{
                .context = &diagnostic_capture,
                .unknown_table_fn = DiagnosticCapture.unknownTable,
            },
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), diagnostic_capture.count);
    try std.testing.expect(diagnostic_capture.saw_expected_table);
}

fn findStream(inventory: *const Inventory, stream_id: []const u8) ?*const StreamInventory {
    for (inventory.streams) |*stream| {
        if (std.mem.eql(u8, stream.definition.stream_id, stream_id)) return stream;
    }
    return null;
}

fn findField(
    inventory: *const Inventory,
    table_name: []const u8,
    column_name: []const u8,
) ?*const FieldInventory {
    for (inventory.fields) |*field_inventory| {
        if (std.mem.eql(u8, field_inventory.table_name, table_name) and
            std.mem.eql(u8, field_inventory.column_name, column_name))
        {
            return field_inventory;
        }
    }
    return null;
}

fn findTrigger(inventory: *const Inventory, name: []const u8) ?*const TriggerInventory {
    for (inventory.triggers) |*trigger| {
        if (std.mem.eql(u8, trigger.name, name)) return trigger;
    }
    return null;
}

fn foreignKeyExists(
    inventory: *const Inventory,
    table_name: []const u8,
    from_column: []const u8,
    referenced_table: []const u8,
    to_column: []const u8,
) bool {
    for (inventory.foreign_keys) |foreign_key| {
        const actual_to_column = foreign_key.to_column orelse continue;
        if (std.mem.eql(u8, foreign_key.table_name, table_name) and
            std.mem.eql(u8, foreign_key.from_column, from_column) and
            std.mem.eql(u8, foreign_key.referenced_table, referenced_table) and
            std.mem.eql(u8, actual_to_column, to_column))
        {
            return true;
        }
    }
    return false;
}

fn expectOptionalStringsEqual(
    left: ?[]const u8,
    right: ?[]const u8,
) !void {
    if (left == null or right == null) {
        try std.testing.expectEqual(left == null, right == null);
        return;
    }
    try std.testing.expectEqualStrings(left.?, right.?);
}
