//! SQLite persistence for versioned tax profiles and form-prefill snapshots.
//!
//! The calendar store already owns `PRAGMA user_version` for its schema. This
//! repository deliberately uses a namespaced migration table instead, so both
//! repositories can share the legacy `calendar.sqlite3` file without making an
//! older calendar-only binary reject the database as too new.
//!
//! Schema v3 keeps legal-taxpayer identity, civil status, relationships, and
//! corrections append-only. Schema v4 adds a separate exact-draft repository:
//! random workspaces can share a canonical filing business key, while every
//! schema-bound revision, named profile binding, and ordered value occurrence
//! remains an immutable historical snapshot. Schema v7 adds owner-scoped,
//! transactional counters for unique on-demand filing occurrences.

const std = @import("std");
const profile_field = @import("field.zig");
const evolution = @import("evolution.zig");
const exact_draft = @import("../form_engine/draft.zig");
const exact_identity = @import("../form_engine/identity.zig");
const exact_evidence = @import("../form_engine/evidence.zig");
const exact_occurrence = @import("../form_engine/occurrence.zig");
const form_ids = @import("../forms/id.zig");
const key_custody = @import("../security/key_custody.zig");
const repository_opening = @import("../security/repository_opening.zig");
const sensitive_memory = @import("../security/sensitive_memory.zig");
const exact_document =
    @import("../form_engine/forms/form_1701q_2018/document.zig");
const exact_validation =
    @import("../form_engine/forms/form_1701q_2018/validation.zig");
const exact_form_occurrences =
    @import("../form_engine/forms/form_1701q_2018/occurrences.zig");
const exact_transaction =
    @import("../form_engine/forms/form_1701q_2018/transaction.zig");

const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

pub const latest_schema_version: u32 = 7;
const migration_component = "tax_profile";
pub const storage_classification =
    repository_opening.legacy_plaintext_repository_classification;
pub const production_repository_integration_state =
    repository_opening.current_production_repository_integration_state;
pub const production_repository_scope =
    repository_opening.ProductionRepositoryScope
        .shared_calendar_tax_profile_database;
const max_exact_provenance_bytes: usize = 4096;
const max_exact_role_bindings: usize = 2;
const max_exact_period_key_bytes: usize = 64;
pub const max_on_demand_occurrence: u32 = 999;
pub const max_exact_workspaces_per_filing_business_key: usize = 32;
pub const max_returned_exact_draft_alternates: usize = 32;

comptime {
    if (max_exact_workspaces_per_filing_business_key == 0 or
        max_returned_exact_draft_alternates == 0 or
        exact_draft.max_revisions_per_exact_shape_stream >
            std.math.maxInt(i64) or
        exact_draft.max_retained_exact_value_bytes >
            std.math.maxInt(i64))
    {
        @compileError("exact persistence limits must fit SQLite integers");
    }
    if (exact_draft.max_revisions_per_exact_shape_stream != 64) {
        @compileError("update the fresh-v4 revision CHECK with the shared limit");
    }
}

pub const Error = error{
    CanonicalTaxpayerIdentifierChanged,
    Closed,
    DraftAlreadyExists,
    DraftAlternateLimitExceeded,
    DraftRetainedValueLimitExceeded,
    DraftRevisionLimitExceeded,
    DraftSchemaMismatch,
    DraftStaleRevision,
    DraftWorkspaceLimitExceeded,
    IdentityCorrectionConflict,
    InconsistentIdentityHistory,
    InvalidDate,
    InvalidAmendment,
    InvalidRelationship,
    InvalidTransition,
    InvalidValue,
    LegalPersonClassChanged,
    MissingIdentityAnchor,
    NoIdentityCorrection,
    NotFound,
    OnDemandOccurrenceLimitExceeded,
    RevisionConflict,
    SchemaTooNew,
    SqliteBusy,
    SqliteConstraint,
    SqliteFailure,
};

/// Opaque 128-bit identifiers are serialized as 32 lowercase hexadecimal
/// characters. They deliberately carry no TIN, name, form, sequence, or
/// period meaning. Persistence accepts the domain's broader opaque-ID syntax
/// for imports, but all newly generated identifiers use this representation.
pub const OpaqueId = [32]u8;
pub const DateText = [10]u8;

/// Persistence aliases the pure evolution policy vocabulary instead of
/// creating a second set of classifications that could drift independently.
pub const LegalPersonClass = evolution.LegalPersonClass;
pub const CivilStatus = evolution.CivilStatus;
pub const RelationshipKind = evolution.RelationshipKind;
pub const Jurisdiction = evolution.Jurisdiction;
pub const TaxAuthority = evolution.TaxAuthority;
pub const DraftWorkspaceId = exact_draft.DraftWorkspaceId;
pub const DraftRevision = exact_draft.DraftRevision;
pub const ExactDraftIdentity = exact_draft.DraftIdentity;
pub const ExactDraftRevisionGuard = exact_draft.RevisionGuard;
pub const ExactDraftOrigin = exact_occurrence.OriginKind;

pub const EffectivePeriodWrite = struct {
    from: DateText,
    until: ?DateText = null,
};

pub const ProfileStatus = enum {
    active,
    archived,

    fn text(self: ProfileStatus) []const u8 {
        return @tagName(self);
    }
};

pub const SubjectKind = enum {
    individual,
    sole_proprietor,
    corporation,
    partnership,
    estate,
    trust,
    other_legal_entity,

    fn text(self: SubjectKind) []const u8 {
        return @tagName(self);
    }
};

pub const LegalEntityKind = enum {
    corporation,
    partnership,
    estate,
    trust,
    other,

    fn text(self: LegalEntityKind) []const u8 {
        return @tagName(self);
    }
};

pub const RevisionSourceTag = enum {
    manual_entry,
    imported,
    migrated,

    fn text(self: RevisionSourceTag) []const u8 {
        return @tagName(self);
    }
};

pub const RevisionSourceWrite = union(RevisionSourceTag) {
    manual_entry: void,
    imported: []const u8,
    migrated: []const u8,
};

pub const IdentityWrite = struct {
    tin: []const u8,
    rdo_code: []const u8,
};

pub const ContactWrite = struct {
    registered_address: []const u8,
    zip_code: ?[]const u8 = null,
    contact_number: ?[]const u8 = null,
    email_address: ?[]const u8 = null,
};

pub const IndividualWrite = struct {
    name: []const u8,
    date_of_birth: ?DateText = null,
    citizenship: ?[]const u8 = null,
    foreign_tax_number: ?[]const u8 = null,
};

pub const SoleProprietorWrite = struct {
    person: IndividualWrite,
    trade_name: ?[]const u8 = null,
};

pub const LegalEntityWrite = struct {
    registered_name: []const u8,
    kind: LegalEntityKind,
};

pub const SubjectWrite = union(enum) {
    individual: IndividualWrite,
    sole_proprietor: SoleProprietorWrite,
    legal_entity: LegalEntityWrite,

    pub fn kind(self: SubjectWrite) SubjectKind {
        return switch (self) {
            .individual => .individual,
            .sole_proprietor => .sole_proprietor,
            .legal_entity => |entity| switch (entity.kind) {
                .corporation => .corporation,
                .partnership => .partnership,
                .estate => .estate,
                .trust => .trust,
                .other => .other_legal_entity,
            },
        };
    }
};

pub const ProfileCreate = struct {
    id: []const u8,
    status: ProfileStatus = .active,
};

/// A cohesive immutable revision row. Repeated components are passed
/// separately through `RevisionComponentsWrite`; no tax-type fact is hidden
/// inside a business activity and no subject is represented by a nullable bag.
pub const RevisionWrite = struct {
    id: []const u8,
    profile_id: []const u8,
    sequence: u32,
    expected_current_sequence: ?u32 = null,
    effective: EffectivePeriodWrite,
    source: RevisionSourceWrite,
    identity: IdentityWrite,
    contact: ContactWrite,
    subject: SubjectWrite,
};

pub const BusinessActivityWrite = struct {
    id: []const u8,
    line_of_business: []const u8,
    atc: ?[]const u8 = null,
    effective: EffectivePeriodWrite,
    ordinal: u32 = 0,
};

pub const RegistrationFactKind = enum {
    tax_type,
    government_withholding_agent,
    special_rate_basis,

    fn text(self: RegistrationFactKind) []const u8 {
        return @tagName(self);
    }
};

pub const GovernmentWithholdingAgent = enum {
    no,
    yes,

    fn text(self: GovernmentWithholdingAgent) []const u8 {
        return @tagName(self);
    }
};

pub const RegistrationFactValueWrite = union(RegistrationFactKind) {
    tax_type: []const u8,
    government_withholding_agent: GovernmentWithholdingAgent,
    special_rate_basis: []const u8,
};

pub const RegistrationFactWrite = struct {
    id: []const u8,
    effective: EffectivePeriodWrite,
    value: RegistrationFactValueWrite,
    ordinal: u32 = 0,
};

pub const RevisionComponentsWrite = struct {
    business_activities: []const BusinessActivityWrite = &.{},
    registration_facts: []const RegistrationFactWrite = &.{},
};

pub const CivilStatusRevisionWrite = struct {
    profile_id: []const u8,
    sequence: u32,
    expected_current_sequence: u32,
    effective: EffectivePeriodWrite,
    status: CivilStatus,
    source: RevisionSourceWrite,
};

pub const ProfileRelationshipWrite = struct {
    id: []const u8,
    from_profile_id: []const u8,
    to_profile_id: []const u8,
    kind: RelationshipKind,
    effective: EffectivePeriodWrite,
    provenance: []const u8,
};

/// An identity correction is deliberately separate from ordinary profile
/// revision appends. The store captures the old anchor itself, then adds the
/// new immutable anchor and its complete audit event in one transaction.
pub const IdentityCorrectionWrite = struct {
    id: []const u8,
    profile_id: []const u8,
    expected_anchor_sequence: u32,
    new_canonical_tin: []const u8,
    new_legal_person_class: LegalPersonClass,
    reason: []const u8,
    actor_reference: []const u8,
    recorded_at_unix_seconds: i64,
    provenance: []const u8,
};

pub const FormRegistrationWrite = struct {
    form_code: []const u8,
    form_revision: []const u8,
};

pub const FormSetState = enum {
    needs_configuration,
    legacy_catalog_default,
    active_empty,
    active_nonempty,

    fn text(self: FormSetState) []const u8 {
        return @tagName(self);
    }
};

pub const DraftWrite = struct {
    id: []const u8,
    form_code: []const u8,
    form_revision: []const u8,
    period_key: []const u8,
    profile_as_of: DateText,
    lifecycle: []const u8 = "editing",
    intent: []const u8 = "original",
    mapping_revision: []const u8,
    amendment_of: ?[]const u8 = null,
};

/// Owner- and profile-scoped identity used to reserve a unique on-demand
/// filing occurrence. The returned occurrence is durably reserved even when
/// draft composition later fails, so retries can never overwrite an earlier
/// on-demand workspace.
pub const OnDemandOccurrenceScope = struct {
    owner_id: []const u8,
    profile_id: []const u8,
    form_code: []const u8,
    form_revision: []const u8,
    tax_year: i32,
};

pub const RoleBindingWrite = struct {
    role: []const u8,
    profile_id: []const u8,
    profile_revision_id: []const u8,
    profile_revision_sequence: u32,
    business_activity_id: ?[]const u8 = null,
};

pub const SnapshotFieldWrite = struct {
    role: []const u8,
    field_id: []const u8,
    reusable_field: []const u8,
    value_type: []const u8,
    value_text: []const u8,
    provenance: []const u8,
    profile_revision_id: []const u8,
    profile_revision_sequence: u32,
    revision_source: RevisionSourceWrite,
    business_activity_id: ?[]const u8 = null,
    registration_fact_id: ?[]const u8 = null,
    overridden: bool = false,
};

pub const DraftValueWrite = struct {
    field_id: []const u8,
    value_text: []const u8,
    provenance: []const u8 = "transaction",
};

pub const FilingIntent = enum(u8) {
    original = 1,
    amended = 2,

    fn text(self: FilingIntent) []const u8 {
        return @tagName(self);
    }
};

/// Canonical business identity for duplicate filing-workspace detection.
/// It deliberately excludes the random workspace ID and executable-package
/// hashes: alternate working copies and package upgrades still describe the
/// same filer/form/period/intent business filing.
pub const CanonicalFilingBusinessKeyWrite = struct {
    filer_profile_id: []const u8,
    form_code: []const u8,
    form_revision: []const u8,
    period_key: []const u8,
    intent: FilingIntent = .original,

    pub fn canonicalDigest(
        self: CanonicalFilingBusinessKeyWrite,
    ) exact_identity.Sha256Digest {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update("ebirforms.canonical-filing-business-key.v1");
        updateDigestLengthPrefixed(&hash, self.filer_profile_id);
        updateDigestLengthPrefixed(&hash, self.form_code);
        updateDigestLengthPrefixed(&hash, self.form_revision);
        updateDigestLengthPrefixed(&hash, self.period_key);
        hash.update(&.{@intFromEnum(self.intent)});
        var result: exact_identity.Sha256Digest = .{ .bytes = undefined };
        hash.final(&result.bytes);
        return result;
    }
};

/// Named bindings are revision-scoped. A later accepted profile refresh
/// appends another exact draft revision with another set of bindings, leaving
/// the old profile revision IDs and value snapshot untouched.
pub const ExactDraftRoleBindingWrite = struct {
    role: []const u8,
    instance_id: []const u8,
    profile_id: []const u8,
    profile_revision_id: []const u8,
    profile_revision_sequence: u32,
    business_activity_id: ?[]const u8 = null,
    provenance: []const u8,
};

/// Persistence-only context paired positionally with the engine-owned ordered
/// occurrence values. `origin` and `provenance` must match the reviewed 1701Q
/// transaction classification of every manifest source control.
pub const ExactDraftOccurrenceContextWrite = struct {
    ordinal: u16,
    origin: ExactDraftOrigin,
    provenance: []const u8,
};

/// Revision-scoped receipt for validation inputs that cannot be reconstructed
/// from exact form values. The persistence adapter derives this from the
/// `SaveValidated` payload that actually gated the candidate.
pub const ExactDraftValidationEvidenceReceipt = struct {
    validation_current_year: i32,
    spouse_tin_checksum: exact_validation.TinChecksumStatus,
};

/// The supplied engine snapshot is already schema-validated and deeply owns
/// its values. The store independently rechecks its public invariants before
/// copying it transactionally.
pub const ExactDraftRevisionWrite = struct {
    filing_key: CanonicalFilingBusinessKeyWrite,
    profile_as_of: DateText,
    recorded_at_unix_seconds: i64,
    validation_evidence: ExactDraftValidationEvidenceReceipt,
    snapshot: *const exact_draft.DraftSnapshot,
    bindings: []const ExactDraftRoleBindingWrite,
    occurrence_contexts: []const ExactDraftOccurrenceContextWrite,
};

pub const OwnedProfileSummary = struct {
    id: []u8,
    status: ProfileStatus,
    current_revision_id: []u8,
    current_revision_sequence: u32,
    display_name: []u8,
    tin: []u8,
    subject_kind: SubjectKind,

    pub fn deinit(self: *OwnedProfileSummary, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.current_revision_id);
        allocator.free(self.display_name);
        allocator.free(self.tin);
        self.* = undefined;
    }
};

pub const ProfileSummaryList = struct {
    items: []OwnedProfileSummary,

    pub fn deinit(self: *ProfileSummaryList, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const OwnedRevisionSource = union(RevisionSourceTag) {
    manual_entry: void,
    imported: []u8,
    migrated: []u8,

    pub fn deinit(self: *OwnedRevisionSource, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .manual_entry => {},
            .imported => |reference| allocator.free(reference),
            .migrated => |reference| allocator.free(reference),
        }
        self.* = undefined;
    }
};

pub const OwnedContact = struct {
    registered_address: []u8,
    zip_code: ?[]u8,
    contact_number: ?[]u8,
    email_address: ?[]u8,

    pub fn deinit(self: *OwnedContact, allocator: std.mem.Allocator) void {
        allocator.free(self.registered_address);
        freeOptional(allocator, self.zip_code);
        freeOptional(allocator, self.contact_number);
        freeOptional(allocator, self.email_address);
        self.* = undefined;
    }
};

pub const OwnedIndividual = struct {
    name: []u8,
    date_of_birth: ?[]u8,
    citizenship: ?[]u8,
    foreign_tax_number: ?[]u8,

    pub fn deinit(self: *OwnedIndividual, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        freeOptional(allocator, self.date_of_birth);
        freeOptional(allocator, self.citizenship);
        freeOptional(allocator, self.foreign_tax_number);
        self.* = undefined;
    }
};

pub const OwnedSoleProprietor = struct {
    person: OwnedIndividual,
    trade_name: ?[]u8,

    pub fn deinit(
        self: *OwnedSoleProprietor,
        allocator: std.mem.Allocator,
    ) void {
        self.person.deinit(allocator);
        freeOptional(allocator, self.trade_name);
        self.* = undefined;
    }
};

pub const OwnedLegalEntity = struct {
    registered_name: []u8,
    kind: LegalEntityKind,

    pub fn deinit(self: *OwnedLegalEntity, allocator: std.mem.Allocator) void {
        allocator.free(self.registered_name);
        self.* = undefined;
    }
};

pub const OwnedSubject = union(enum) {
    individual: OwnedIndividual,
    sole_proprietor: OwnedSoleProprietor,
    legal_entity: OwnedLegalEntity,

    pub fn deinit(self: *OwnedSubject, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .individual => |*person| person.deinit(allocator),
            .sole_proprietor => |*proprietor| proprietor.deinit(allocator),
            .legal_entity => |*entity| entity.deinit(allocator),
        }
        self.* = undefined;
    }

    pub fn kind(self: *const OwnedSubject) SubjectKind {
        return switch (self.*) {
            .individual => .individual,
            .sole_proprietor => .sole_proprietor,
            .legal_entity => |entity| switch (entity.kind) {
                .corporation => .corporation,
                .partnership => .partnership,
                .estate => .estate,
                .trust => .trust,
                .other => .other_legal_entity,
            },
        };
    }
};

pub const OwnedBusinessActivity = struct {
    id: []u8,
    line_of_business: []u8,
    atc: ?[]u8,
    effective_from: []u8,
    effective_until: ?[]u8,
    ordinal: u32,

    pub fn deinit(
        self: *OwnedBusinessActivity,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.id);
        allocator.free(self.line_of_business);
        freeOptional(allocator, self.atc);
        allocator.free(self.effective_from);
        freeOptional(allocator, self.effective_until);
        self.* = undefined;
    }
};

pub const OwnedRegistrationFactValue = union(RegistrationFactKind) {
    tax_type: []u8,
    government_withholding_agent: GovernmentWithholdingAgent,
    special_rate_basis: []u8,

    pub fn deinit(
        self: *OwnedRegistrationFactValue,
        allocator: std.mem.Allocator,
    ) void {
        switch (self.*) {
            .tax_type => |value| allocator.free(value),
            .government_withholding_agent => {},
            .special_rate_basis => |value| allocator.free(value),
        }
        self.* = undefined;
    }
};

pub const OwnedRegistrationFact = struct {
    id: []u8,
    effective_from: []u8,
    effective_until: ?[]u8,
    value: OwnedRegistrationFactValue,
    ordinal: u32,

    pub fn deinit(
        self: *OwnedRegistrationFact,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.id);
        allocator.free(self.effective_from);
        freeOptional(allocator, self.effective_until);
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

pub const OwnedProfileRevision = struct {
    id: []u8,
    sequence: u32,
    profile_id: []u8,
    effective_from: []u8,
    effective_until: ?[]u8,
    source: OwnedRevisionSource,
    tin: []u8,
    rdo_code: []u8,
    contact: OwnedContact,
    subject: OwnedSubject,
    business_activities: []OwnedBusinessActivity,
    registration_facts: []OwnedRegistrationFact,

    pub fn deinit(self: *OwnedProfileRevision, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.profile_id);
        allocator.free(self.effective_from);
        freeOptional(allocator, self.effective_until);
        self.source.deinit(allocator);
        allocator.free(self.tin);
        allocator.free(self.rdo_code);
        self.contact.deinit(allocator);
        self.subject.deinit(allocator);
        for (self.business_activities) |*activity| activity.deinit(allocator);
        allocator.free(self.business_activities);
        for (self.registration_facts) |*fact| fact.deinit(allocator);
        allocator.free(self.registration_facts);
        self.* = undefined;
    }
};

pub const OwnedTaxpayerIdentityAnchor = struct {
    profile_id: []u8,
    sequence: u32,
    jurisdiction: Jurisdiction,
    tax_authority: TaxAuthority,
    canonical_tin: []u8,
    legal_person_class: LegalPersonClass,
    established_from_revision_id: ?[]u8,
    identity_correction_id: ?[]u8,

    pub fn deinit(
        self: *OwnedTaxpayerIdentityAnchor,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.profile_id);
        allocator.free(self.canonical_tin);
        freeOptional(allocator, self.established_from_revision_id);
        freeOptional(allocator, self.identity_correction_id);
        self.* = undefined;
    }
};

pub const OwnedCivilStatusRevision = struct {
    profile_id: []u8,
    sequence: u32,
    effective_from: []u8,
    effective_until: ?[]u8,
    status: CivilStatus,
    source: OwnedRevisionSource,

    pub fn deinit(
        self: *OwnedCivilStatusRevision,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.profile_id);
        allocator.free(self.effective_from);
        freeOptional(allocator, self.effective_until);
        self.source.deinit(allocator);
        self.* = undefined;
    }
};

pub const OwnedProfileRelationship = struct {
    id: []u8,
    from_profile_id: []u8,
    to_profile_id: []u8,
    kind: RelationshipKind,
    effective_from: []u8,
    effective_until: ?[]u8,
    provenance: []u8,

    pub fn deinit(
        self: *OwnedProfileRelationship,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.id);
        allocator.free(self.from_profile_id);
        allocator.free(self.to_profile_id);
        allocator.free(self.effective_from);
        freeOptional(allocator, self.effective_until);
        allocator.free(self.provenance);
        self.* = undefined;
    }
};

pub const ProfileRelationshipList = struct {
    items: []OwnedProfileRelationship,

    pub fn deinit(
        self: *ProfileRelationshipList,
        allocator: std.mem.Allocator,
    ) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const OwnedIdentityCorrection = struct {
    id: []u8,
    profile_id: []u8,
    old_anchor_sequence: u32,
    new_anchor_sequence: u32,
    old_canonical_tin: []u8,
    new_canonical_tin: []u8,
    old_legal_person_class: LegalPersonClass,
    new_legal_person_class: LegalPersonClass,
    reason: []u8,
    actor_reference: []u8,
    recorded_at_unix_seconds: i64,
    provenance: []u8,

    pub fn deinit(
        self: *OwnedIdentityCorrection,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.id);
        allocator.free(self.profile_id);
        allocator.free(self.old_canonical_tin);
        allocator.free(self.new_canonical_tin);
        allocator.free(self.reason);
        allocator.free(self.actor_reference);
        allocator.free(self.provenance);
        self.* = undefined;
    }
};

const AnchorSnapshot = struct {
    sequence: u32,
    canonical_tin: [14]u8 = undefined,
    canonical_tin_len: u8 = 0,
    legal_person_class: LegalPersonClass,

    fn canonicalTin(self: *const AnchorSnapshot) []const u8 {
        return self.canonical_tin[0..self.canonical_tin_len];
    }
};

pub const OwnedFormRegistration = struct {
    form_code: []u8,
    form_revision: []u8,

    pub fn deinit(self: *OwnedFormRegistration, allocator: std.mem.Allocator) void {
        allocator.free(self.form_code);
        allocator.free(self.form_revision);
        self.* = undefined;
    }
};

pub const FormRegistrationList = struct {
    items: []OwnedFormRegistration,

    pub fn deinit(self: *FormRegistrationList, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const ResolvedFormSet = struct {
    state: FormSetState,
    legacy_reset_allowed: bool,
    forms: FormRegistrationList,

    pub fn deinit(self: *ResolvedFormSet, allocator: std.mem.Allocator) void {
        self.forms.deinit(allocator);
        self.* = undefined;
    }
};

/// Owned profile-level calendar filter. A missing selection parent means the
/// catalog default (all forms); a present value with no codes is an explicit
/// empty selection.
pub const CalendarFormSelection = struct {
    form_codes: [][]u8,

    pub fn deinit(
        self: *CalendarFormSelection,
        allocator: std.mem.Allocator,
    ) void {
        for (self.form_codes) |form_code| allocator.free(form_code);
        allocator.free(self.form_codes);
        self.* = undefined;
    }
};

pub const OwnedRoleBinding = struct {
    role: []u8,
    profile_id: []u8,
    profile_revision_id: []u8,
    profile_revision_sequence: u32,
    business_activity_id: ?[]u8,

    pub fn deinit(self: *OwnedRoleBinding, allocator: std.mem.Allocator) void {
        allocator.free(self.role);
        allocator.free(self.profile_id);
        allocator.free(self.profile_revision_id);
        freeOptional(allocator, self.business_activity_id);
        self.* = undefined;
    }
};

pub const OwnedSnapshotField = struct {
    role: []u8,
    field_id: []u8,
    reusable_field: []u8,
    value_type: []u8,
    value_text: []u8,
    provenance: []u8,
    profile_revision_id: []u8,
    profile_revision_sequence: u32,
    revision_source: OwnedRevisionSource,
    business_activity_id: ?[]u8,
    registration_fact_id: ?[]u8,
    overridden: bool,

    pub fn deinit(self: *OwnedSnapshotField, allocator: std.mem.Allocator) void {
        allocator.free(self.role);
        allocator.free(self.field_id);
        allocator.free(self.reusable_field);
        allocator.free(self.value_type);
        allocator.free(self.value_text);
        allocator.free(self.provenance);
        allocator.free(self.profile_revision_id);
        self.revision_source.deinit(allocator);
        freeOptional(allocator, self.business_activity_id);
        freeOptional(allocator, self.registration_fact_id);
        self.* = undefined;
    }
};

pub const OwnedDraftValue = struct {
    field_id: []u8,
    value_text: []u8,
    provenance: []u8,

    pub fn deinit(self: *OwnedDraftValue, allocator: std.mem.Allocator) void {
        allocator.free(self.field_id);
        allocator.free(self.value_text);
        allocator.free(self.provenance);
        self.* = undefined;
    }
};

pub const OwnedDraft = struct {
    id: []u8,
    form_code: []u8,
    form_revision: []u8,
    period_key: []u8,
    profile_as_of: []u8,
    lifecycle: []u8,
    intent: []u8,
    mapping_revision: []u8,
    amendment_of: ?[]u8,
    bindings: []OwnedRoleBinding,
    snapshots: []OwnedSnapshotField,
    values: []OwnedDraftValue,

    pub fn deinit(self: *OwnedDraft, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.form_code);
        allocator.free(self.form_revision);
        allocator.free(self.period_key);
        allocator.free(self.profile_as_of);
        allocator.free(self.lifecycle);
        allocator.free(self.intent);
        allocator.free(self.mapping_revision);
        freeOptional(allocator, self.amendment_of);
        for (self.bindings) |*binding| binding.deinit(allocator);
        allocator.free(self.bindings);
        for (self.snapshots) |*snapshot| snapshot.deinit(allocator);
        allocator.free(self.snapshots);
        for (self.values) |*value| value.deinit(allocator);
        allocator.free(self.values);
        self.* = undefined;
    }
};

/// Lightweight filing-work summary for profile dashboards. The immutable
/// snapshot and transaction values stay behind `getDraft`; calendar lanes
/// only need stable identity, period, and lifecycle.
pub const OwnedDraftSummary = struct {
    id: []u8,
    form_code: []u8,
    form_revision: []u8,
    period_key: []u8,
    lifecycle: []u8,
    intent: []u8,

    pub fn deinit(
        self: *OwnedDraftSummary,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.id);
        allocator.free(self.form_code);
        allocator.free(self.form_revision);
        allocator.free(self.period_key);
        allocator.free(self.lifecycle);
        allocator.free(self.intent);
        self.* = undefined;
    }
};

pub const DraftSummaryList = struct {
    items: []OwnedDraftSummary,

    pub fn deinit(
        self: *DraftSummaryList,
        allocator: std.mem.Allocator,
    ) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const OwnedCanonicalFilingBusinessKey = struct {
    filer_profile_id: []u8,
    form_code: []u8,
    form_revision: []u8,
    period_key: []u8,
    intent: FilingIntent,

    pub fn deinit(
        self: *OwnedCanonicalFilingBusinessKey,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.filer_profile_id);
        allocator.free(self.form_code);
        allocator.free(self.form_revision);
        allocator.free(self.period_key);
        self.* = undefined;
    }

    pub fn borrowed(self: *const OwnedCanonicalFilingBusinessKey) CanonicalFilingBusinessKeyWrite {
        return .{
            .filer_profile_id = self.filer_profile_id,
            .form_code = self.form_code,
            .form_revision = self.form_revision,
            .period_key = self.period_key,
            .intent = self.intent,
        };
    }
};

pub const OwnedExactDraftRoleBinding = struct {
    role: []u8,
    instance_id: []u8,
    profile_id: []u8,
    profile_revision_id: []u8,
    profile_revision_sequence: u32,
    business_activity_id: ?[]u8,
    provenance: []u8,

    pub fn deinit(
        self: *OwnedExactDraftRoleBinding,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.role);
        allocator.free(self.instance_id);
        allocator.free(self.profile_id);
        allocator.free(self.profile_revision_id);
        freeOptional(allocator, self.business_activity_id);
        allocator.free(self.provenance);
        self.* = undefined;
    }
};

pub const OwnedExactDraftOccurrence = struct {
    ordinal: u16,
    serialized_key: []u8,
    same_key_occurrence: u16,
    raw_value: []u8,
    normalized_value: []u8,
    emitted_value: []u8,
    origin: ExactDraftOrigin,
    provenance: []u8,

    pub fn deinit(
        self: *OwnedExactDraftOccurrence,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.serialized_key);
        secureFreeOwned(allocator, self.raw_value);
        secureFreeOwned(allocator, self.normalized_value);
        secureFreeOwned(allocator, self.emitted_value);
        allocator.free(self.provenance);
        self.* = undefined;
    }
};

pub const OwnedExactDraftRevision = struct {
    revision: DraftRevision,
    parent_revision: ?DraftRevision,
    profile_as_of: []u8,
    recorded_at_unix_seconds: i64,
    schema: exact_draft.SchemaBinding,
    profile_snapshot_digest: exact_identity.Sha256Digest,
    transaction_state_digest: exact_identity.Sha256Digest,
    ordered_values_digest: exact_identity.Sha256Digest,
    validation_evidence: ExactDraftValidationEvidenceReceipt,
    validation_status: exact_draft.ValidationStatus,
    artifact_status: exact_draft.ArtifactStatus,
    bindings: []OwnedExactDraftRoleBinding,
    occurrences: []OwnedExactDraftOccurrence,

    pub fn deinit(
        self: *OwnedExactDraftRevision,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.profile_as_of);
        for (self.bindings) |*binding| binding.deinit(allocator);
        allocator.free(self.bindings);
        for (self.occurrences) |*value| value.deinit(allocator);
        allocator.free(self.occurrences);
        self.* = undefined;
    }
};

pub const OwnedExactDraftHistory = struct {
    draft_identity: ExactDraftIdentity,
    filing_key: OwnedCanonicalFilingBusinessKey,
    revisions: []OwnedExactDraftRevision,

    pub fn deinit(
        self: *OwnedExactDraftHistory,
        allocator: std.mem.Allocator,
    ) void {
        self.filing_key.deinit(allocator);
        for (self.revisions) |*revision| revision.deinit(allocator);
        allocator.free(self.revisions);
        self.* = undefined;
    }
};

pub const ExactDraftAlternate = struct {
    workspace_id: DraftWorkspaceId,
    schema_stream_count: u32,
    created_at_unix_seconds: i64,
};

pub const ExactDraftAlternateList = struct {
    items: []ExactDraftAlternate,

    pub fn deinit(
        self: *ExactDraftAlternateList,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.items);
        self.* = undefined;
    }
};

const ExactDraftHistoryPreflight = struct {
    revision_count: usize,
    retained_value_bytes: usize,
};

pub const Store = struct {
    db: ?*sqlite.sqlite3,

    /// Opens the legacy file-backed plaintext repository only after validating
    /// authority minted by the source-selected development-artifact bootstrap.
    /// It is not a production repository factory.
    pub fn openDevelopmentPlaintext(
        capability: *const key_custody.DevelopmentPlaintextStorageCapability,
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !Store {
        try key_custody.requireDevelopmentPlaintextStorage(capability);
        if (path.len == 0) return Error.InvalidValue;
        return openInternal(allocator, path, true);
    }

    /// Explicit ephemeral in-memory constructor.
    pub fn openMemory(allocator: std.mem.Allocator) !Store {
        return openInternal(allocator, ":memory:", false);
    }

    fn openInternal(
        allocator: std.mem.Allocator,
        path: []const u8,
        file_backed: bool,
    ) !Store {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        var raw: ?*sqlite.sqlite3 = null;
        const flags = sqlite.SQLITE_OPEN_READWRITE |
            sqlite.SQLITE_OPEN_CREATE |
            sqlite.SQLITE_OPEN_FULLMUTEX;
        const rc = sqlite.sqlite3_open_v2(path_z.ptr, &raw, flags, null);
        if (rc != sqlite.SQLITE_OK or raw == null) {
            if (raw) |db| _ = sqlite.sqlite3_close_v2(db);
            return mapResult(rc);
        }

        var store = Store{ .db = raw.? };
        errdefer store.close();
        _ = sqlite.sqlite3_extended_result_codes(store.db.?, 1);
        if (sqlite.sqlite3_busy_timeout(store.db.?, 5_000) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
        try store.exec("PRAGMA foreign_keys = ON;");
        if (file_backed) try store.exec("PRAGMA journal_mode = WAL;");
        try store.migrate();
        return store;
    }

    pub fn close(self: *Store) void {
        if (self.db) |db| {
            _ = sqlite.sqlite3_close_v2(db);
            self.db = null;
        }
    }

    pub fn foreignKeysEnabled(self: *Store) !bool {
        var statement = try self.prepare("PRAGMA foreign_keys;");
        defer statement.deinit();
        if (try statement.step() != .row) return Error.SqliteFailure;
        return sqlite.sqlite3_column_int(statement.raw, 0) == 1;
    }

    pub fn schemaVersion(self: *Store) !u32 {
        var statement = try self.prepare(
            \\SELECT version
            \\FROM app_component_migrations
            \\WHERE component = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, migration_component);
        return switch (try statement.step()) {
            .done => 0,
            .row => blk: {
                const value = sqlite.sqlite3_column_int64(statement.raw, 0);
                if (value < 0 or value > std.math.maxInt(u32)) {
                    return Error.SqliteFailure;
                }
                break :blk @intCast(value);
            },
        };
    }

    pub fn migrate(self: *Store) !void {
        try self.exec(
            \\CREATE TABLE IF NOT EXISTS app_component_migrations (
            \\    component TEXT PRIMARY KEY,
            \\    version INTEGER NOT NULL CHECK (version >= 0),
            \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch())
            \\);
        );
        const observed = try self.schemaVersion();
        if (observed > latest_schema_version) return Error.SchemaTooNew;
        if (observed == latest_schema_version) return;

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        const current = try self.schemaVersion();
        if (current > latest_schema_version) return Error.SchemaTooNew;
        if (current < 1) {
            try self.exec(schema_v1);
            var version = try self.prepare(
                \\INSERT INTO app_component_migrations(component, version)
                \\VALUES (?, 1)
                \\ON CONFLICT(component) DO UPDATE SET
                \\    version = excluded.version,
                \\    updated_at = unixepoch();
            );
            defer version.deinit();
            try version.bindText(1, migration_component);
            try version.expectDone();
        }
        if (current < 2) {
            try self.exec(schema_v2);
            var version = try self.prepare(
                \\UPDATE app_component_migrations
                \\SET version = 2, updated_at = unixepoch()
                \\WHERE component = ?;
            );
            defer version.deinit();
            try version.bindText(1, migration_component);
            try version.expectDone();
        }
        if (current < 3) {
            // v1/v2 stored identity on every revision. Establishing a stable
            // anchor is safe only when that history describes one taxpayer.
            // Formatting-only TIN differences are normalized; a real TIN or
            // broad legal-person-class conflict aborts the whole migration.
            try self.validateLegacyIdentityHistories();
            try self.exec(schema_v3);
            try self.backfillIdentityAnchors();
            var version = try self.prepare(
                \\UPDATE app_component_migrations
                \\SET version = 3, updated_at = unixepoch()
                \\WHERE component = ?;
            );
            defer version.deinit();
            try version.bindText(1, migration_component);
            try version.expectDone();
        }
        if (current < 4) {
            // Exact ordered drafts intentionally do not upcast the mutable
            // legacy draft tables: their map-shaped values cannot prove
            // occurrence order, repeated-key identity, or exact package
            // binding. The legacy rows remain available through their
            // existing APIs while new exact histories start explicitly.
            try self.exec(schema_v4);
            var version = try self.prepare(
                \\UPDATE app_component_migrations
                \\SET version = 4, updated_at = unixepoch()
                \\WHERE component = ?;
            );
            defer version.deinit();
            try version.bindText(1, migration_component);
            try version.expectDone();
        }
        if (current < 5) {
            try self.exec(schema_v5);
            var version = try self.prepare(
                \\UPDATE app_component_migrations
                \\SET version = 5, updated_at = unixepoch()
                \\WHERE component = ?;
            );
            defer version.deinit();
            try version.bindText(1, migration_component);
            try version.expectDone();
        }
        if (current < 6) {
            try self.exec(schema_v6);
            var version = try self.prepare(
                \\UPDATE app_component_migrations
                \\SET version = 6, updated_at = unixepoch()
                \\WHERE component = ?;
            );
            defer version.deinit();
            try version.bindText(1, migration_component);
            try version.expectDone();
        }
        if (current < 7) {
            try self.exec(schema_v7);
            var version = try self.prepare(
                \\UPDATE app_component_migrations
                \\SET version = 7, updated_at = unixepoch()
                \\WHERE component = ?;
            );
            defer version.deinit();
            try version.bindText(1, migration_component);
            try version.expectDone();
        }
        try self.commit();
        committed = true;
    }

    fn validateLegacyIdentityHistories(self: *Store) !void {
        var statement = try self.prepare(
            \\SELECT profile_id, tin, subject_kind
            \\FROM tax_profile_revisions
            \\ORDER BY profile_id, sequence;
        );
        defer statement.deinit();

        var previous_profile: [64]u8 = undefined;
        var previous_profile_len: usize = 0;
        var previous_tin: profile_field.Tin = undefined;
        var previous_class: LegalPersonClass = undefined;
        var have_previous = false;

        while (try statement.step() == .row) {
            const profile_id = columnText(statement.raw, 0) orelse
                return Error.InconsistentIdentityHistory;
            if (profile_id.len == 0 or profile_id.len > previous_profile.len) {
                return Error.InconsistentIdentityHistory;
            }
            const raw_tin = columnText(statement.raw, 1) orelse
                return Error.InconsistentIdentityHistory;
            const tin = profile_field.Tin.parse(raw_tin) catch
                return Error.InconsistentIdentityHistory;
            const raw_kind = columnText(statement.raw, 2) orelse
                return Error.InconsistentIdentityHistory;
            const subject_kind = parseSubjectKind(raw_kind) orelse
                return Error.InconsistentIdentityHistory;
            const class = legalPersonClassForSubjectKind(subject_kind);

            const same_profile = have_previous and std.mem.eql(
                u8,
                previous_profile[0..previous_profile_len],
                profile_id,
            );
            if (same_profile) {
                if (!previous_tin.eql(&tin) or previous_class != class) {
                    return Error.InconsistentIdentityHistory;
                }
                continue;
            }

            @memcpy(previous_profile[0..profile_id.len], profile_id);
            previous_profile_len = profile_id.len;
            previous_tin = tin;
            previous_class = class;
            have_previous = true;
        }
    }

    fn backfillIdentityAnchors(self: *Store) !void {
        var revisions = try self.prepare(
            \\SELECT r.profile_id, r.id, r.tin, r.subject_kind
            \\FROM tax_profile_revisions AS r
            \\WHERE NOT EXISTS (
            \\    SELECT 1
            \\    FROM tax_profile_revisions AS earlier
            \\    WHERE earlier.profile_id = r.profile_id
            \\      AND earlier.sequence < r.sequence
            \\)
            \\ORDER BY r.profile_id;
        );
        defer revisions.deinit();
        var insert = try self.prepare(
            \\INSERT INTO tax_profile_identity_anchors (
            \\    profile_id, sequence, jurisdiction, tax_authority,
            \\    canonical_tin, legal_person_class,
            \\    established_from_revision_id, identity_correction_id
            \\) VALUES (?, 1, 'philippines',
            \\    'bureau_of_internal_revenue', ?, ?, ?, NULL);
        );
        defer insert.deinit();

        while (try revisions.step() == .row) {
            const profile_id = columnText(revisions.raw, 0) orelse
                return Error.InconsistentIdentityHistory;
            const revision_id = columnText(revisions.raw, 1) orelse
                return Error.InconsistentIdentityHistory;
            const raw_tin = columnText(revisions.raw, 2) orelse
                return Error.InconsistentIdentityHistory;
            const tin = profile_field.Tin.parse(raw_tin) catch
                return Error.InconsistentIdentityHistory;
            const raw_kind = columnText(revisions.raw, 3) orelse
                return Error.InconsistentIdentityHistory;
            const subject_kind = parseSubjectKind(raw_kind) orelse
                return Error.InconsistentIdentityHistory;

            try insert.bindText(1, profile_id);
            try insert.bindText(2, tin.asDigits());
            try insert.bindText(
                3,
                legalPersonClassText(
                    legalPersonClassForSubjectKind(subject_kind),
                ),
            );
            try insert.bindText(4, revision_id);
            try insert.expectDone();
            try insert.reset();
        }
    }

    pub fn generateOpaqueId(self: *Store) !OpaqueId {
        var statement = try self.prepare("SELECT lower(hex(randomblob(16)));");
        defer statement.deinit();
        if (try statement.step() != .row) return Error.SqliteFailure;
        const raw = columnText(statement.raw, 0) orelse return Error.SqliteFailure;
        if (raw.len != 32) return Error.SqliteFailure;
        var id: OpaqueId = undefined;
        @memcpy(&id, raw);
        if (try statement.step() != .done) return Error.SqliteFailure;
        return id;
    }

    pub fn localOwnerId(self: *Store) !OpaqueId {
        var statement = try self.prepare(
            "SELECT id FROM tax_profile_local_owner WHERE singleton = 1;",
        );
        defer statement.deinit();
        if (try statement.step() != .row) return Error.NotFound;
        const raw = columnText(statement.raw, 0) orelse
            return Error.SqliteFailure;
        if (raw.len != 32) return Error.SqliteFailure;
        var id: OpaqueId = undefined;
        @memcpy(&id, raw);
        if (try statement.step() != .done) return Error.SqliteFailure;
        return id;
    }

    /// Generates the independent random identifier used for an exact draft
    /// workspace. Filing duplicate detection uses the canonical business key,
    /// never this random value.
    pub fn generateDraftWorkspaceId(self: *Store) !DraftWorkspaceId {
        while (true) {
            var statement = try self.prepare("SELECT randomblob(16);");
            defer statement.deinit();
            if (try statement.step() != .row) return Error.SqliteFailure;
            const workspace_id = readDraftWorkspaceId(
                statement.raw,
                0,
            ) catch continue;
            if (try statement.step() != .done) return Error.SqliteFailure;
            return workspace_id;
        }
    }

    pub fn createProfile(self: *Store, value: ProfileCreate) !void {
        try validateProfileCreate(value);
        const sql: []const u8 = if (try self.schemaVersion() >= 6)
            "INSERT INTO tax_profiles(id, status, owner_id) VALUES (?, ?, (SELECT id FROM tax_profile_local_owner WHERE singleton = 1));"
        else
            "INSERT INTO tax_profiles(id, status) VALUES (?, ?);";
        var statement = try self.prepare(sql);
        defer statement.deinit();
        try statement.bindText(1, value.id);
        try statement.bindText(2, value.status.text());
        try statement.expectDone();
    }

    /// Production first-save path. The profile shell, first immutable
    /// revision, repeated components, and current pointer either all commit or
    /// none do, so a validation/constraint failure cannot leave an orphan
    /// profile.
    pub fn createProfileWithRevision(
        self: *Store,
        profile: ProfileCreate,
        revision: RevisionWrite,
        components: RevisionComponentsWrite,
    ) !void {
        try validateProfileCreate(profile);
        try validateRevision(revision, components);
        if (!std.mem.eql(u8, profile.id, revision.profile_id)) {
            return Error.InvalidValue;
        }
        if (revision.sequence != 1) return Error.RevisionConflict;
        if (revision.expected_current_sequence) |expected| {
            if (expected != 0) return Error.RevisionConflict;
        }

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        const profile_sql: []const u8 = if (try self.schemaVersion() >= 6)
            "INSERT INTO tax_profiles(id, status, owner_id) VALUES (?, ?, (SELECT id FROM tax_profile_local_owner WHERE singleton = 1));"
        else
            "INSERT INTO tax_profiles(id, status) VALUES (?, ?);";
        var add_profile = try self.prepare(profile_sql);
        defer add_profile.deinit();
        try add_profile.bindText(1, profile.id);
        try add_profile.bindText(2, profile.status.text());
        try add_profile.expectDone();

        try self.insertRevisionRows(revision, components);
        var advance = try self.prepare(
            \\UPDATE tax_profiles
            \\SET current_revision_id = ?, updated_at = unixepoch()
            \\WHERE id = ? AND current_revision_id IS NULL;
        );
        defer advance.deinit();
        try advance.bindText(1, revision.id);
        try advance.bindText(2, profile.id);
        try advance.expectDone();
        if (sqlite.sqlite3_changes(try self.handle()) != 1) {
            return Error.RevisionConflict;
        }

        try self.commit();
        committed = true;
    }

    pub fn setProfileStatus(
        self: *Store,
        profile_id: []const u8,
        status: ProfileStatus,
    ) !void {
        try validateOpaqueText(profile_id);
        var statement = try self.prepare(
            \\UPDATE tax_profiles
            \\SET status = ?, updated_at = unixepoch()
            \\WHERE id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, status.text());
        try statement.bindText(2, profile_id);
        try statement.expectDone();
        if (sqlite.sqlite3_changes(try self.handle()) == 0) return Error.NotFound;
    }

    /// Appends an immutable revision and atomically advances the profile's
    /// current pointer. `expected_current_sequence` is the caller's observed
    /// sequence number. SQLite rowids never cross this boundary.
    pub fn appendRevision(
        self: *Store,
        value: RevisionWrite,
        components: RevisionComponentsWrite,
    ) !void {
        try validateRevision(value, components);

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        const current = try self.currentRevisionSequence(value.profile_id);
        const observed_sequence: u32 = current orelse 0;
        if (current == null and !(try self.profileExists(value.profile_id))) {
            return Error.NotFound;
        }
        if (value.expected_current_sequence) |expected| {
            if (expected != observed_sequence) return Error.RevisionConflict;
        }
        if (observed_sequence == std.math.maxInt(u32)) {
            return Error.InvalidValue;
        }
        if (value.sequence != observed_sequence + 1) {
            return Error.RevisionConflict;
        }
        try self.validateOrdinaryIdentity(value, observed_sequence);

        try self.insertRevisionRows(value, components);

        var advance = try self.prepare(
            \\UPDATE tax_profiles
            \\SET current_revision_id = ?, updated_at = unixepoch()
            \\WHERE id = ? AND (
            \\    (? = 0 AND current_revision_id IS NULL) OR
            \\    current_revision_id = (
            \\        SELECT id
            \\        FROM tax_profile_revisions
            \\        WHERE profile_id = ? AND sequence = ?
            \\    )
            \\);
        );
        defer advance.deinit();
        try advance.bindText(1, value.id);
        try advance.bindText(2, value.profile_id);
        try advance.bindInt64(3, observed_sequence);
        try advance.bindText(4, value.profile_id);
        try advance.bindInt64(5, observed_sequence);
        try advance.expectDone();
        if (sqlite.sqlite3_changes(try self.handle()) != 1) {
            return Error.RevisionConflict;
        }

        try self.commit();
        committed = true;
    }

    pub fn getIdentityAnchor(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
    ) !?OwnedTaxpayerIdentityAnchor {
        try validateOpaqueText(profile_id);
        var statement = try self.prepare(
            \\SELECT profile_id, sequence, jurisdiction, tax_authority,
            \\       canonical_tin, legal_person_class,
            \\       established_from_revision_id, identity_correction_id
            \\FROM tax_profile_identity_anchors
            \\WHERE profile_id = ?
            \\ORDER BY sequence DESC
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        if (try statement.step() == .done) return null;
        return try readIdentityAnchor(allocator, statement.raw);
    }

    pub fn getIdentityAnchorAtSequence(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        sequence: u32,
    ) !?OwnedTaxpayerIdentityAnchor {
        try validateOpaqueText(profile_id);
        if (sequence == 0) return Error.InvalidValue;
        var statement = try self.prepare(
            \\SELECT profile_id, sequence, jurisdiction, tax_authority,
            \\       canonical_tin, legal_person_class,
            \\       established_from_revision_id, identity_correction_id
            \\FROM tax_profile_identity_anchors
            \\WHERE profile_id = ? AND sequence = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindInt64(2, sequence);
        if (try statement.step() == .done) return null;
        return try readIdentityAnchor(allocator, statement.raw);
    }

    /// Records an audited correction without rewriting either the prior
    /// anchor or any profile revision. The new anchor becomes authoritative
    /// only if both rows commit.
    pub fn recordIdentityCorrection(
        self: *Store,
        value: IdentityCorrectionWrite,
    ) !u32 {
        try validateIdText(value.id);
        try validateOpaqueText(value.profile_id);
        try validateEvolutionSourceReference(value.reason);
        try validateEvolutionSourceReference(value.actor_reference);
        try validateEvolutionSourceReference(value.provenance);
        const new_tin = profile_field.Tin.parse(
            value.new_canonical_tin,
        ) catch return Error.InvalidValue;

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        if (!(try self.profileExists(value.profile_id))) {
            return Error.NotFound;
        }
        const current = (try self.currentAnchorSnapshot(
            value.profile_id,
        )) orelse return Error.MissingIdentityAnchor;
        if (current.sequence != value.expected_anchor_sequence) {
            return Error.IdentityCorrectionConflict;
        }
        if (current.sequence == std.math.maxInt(u32)) {
            return Error.InvalidValue;
        }
        const same_tin = std.mem.eql(
            u8,
            current.canonicalTin(),
            new_tin.asDigits(),
        );
        if (same_tin and
            current.legal_person_class == value.new_legal_person_class)
        {
            return Error.NoIdentityCorrection;
        }
        const next_sequence = current.sequence + 1;

        var add_anchor = try self.prepare(
            \\INSERT INTO tax_profile_identity_anchors (
            \\    profile_id, sequence, jurisdiction, tax_authority,
            \\    canonical_tin, legal_person_class,
            \\    established_from_revision_id, identity_correction_id
            \\) VALUES (?, ?, 'philippines',
            \\    'bureau_of_internal_revenue', ?, ?, NULL, ?);
        );
        defer add_anchor.deinit();
        try add_anchor.bindText(1, value.profile_id);
        try add_anchor.bindInt64(2, next_sequence);
        try add_anchor.bindText(3, new_tin.asDigits());
        try add_anchor.bindText(
            4,
            legalPersonClassText(value.new_legal_person_class),
        );
        try add_anchor.bindText(5, value.id);
        try add_anchor.expectDone();

        var add_event = try self.prepare(
            \\INSERT INTO tax_profile_identity_corrections (
            \\    id, profile_id, old_anchor_sequence,
            \\    new_anchor_sequence, old_canonical_tin,
            \\    new_canonical_tin, old_legal_person_class,
            \\    new_legal_person_class, reason, actor_reference,
            \\    recorded_at_unix_seconds, provenance
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_event.deinit();
        try add_event.bindText(1, value.id);
        try add_event.bindText(2, value.profile_id);
        try add_event.bindInt64(3, current.sequence);
        try add_event.bindInt64(4, next_sequence);
        try add_event.bindText(5, current.canonicalTin());
        try add_event.bindText(6, new_tin.asDigits());
        try add_event.bindText(
            7,
            legalPersonClassText(current.legal_person_class),
        );
        try add_event.bindText(
            8,
            legalPersonClassText(value.new_legal_person_class),
        );
        try add_event.bindText(9, value.reason);
        try add_event.bindText(10, value.actor_reference);
        try add_event.bindInt64(11, value.recorded_at_unix_seconds);
        try add_event.bindText(12, value.provenance);
        try add_event.expectDone();

        try self.commit();
        committed = true;
        return next_sequence;
    }

    pub fn getIdentityCorrection(
        self: *Store,
        allocator: std.mem.Allocator,
        correction_id: []const u8,
    ) !?OwnedIdentityCorrection {
        try validateIdText(correction_id);
        var statement = try self.prepare(
            \\SELECT id, profile_id, old_anchor_sequence,
            \\       new_anchor_sequence, old_canonical_tin,
            \\       new_canonical_tin, old_legal_person_class,
            \\       new_legal_person_class, reason, actor_reference,
            \\       recorded_at_unix_seconds, provenance
            \\FROM tax_profile_identity_corrections
            \\WHERE id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, correction_id);
        if (try statement.step() == .done) return null;
        return try readIdentityCorrection(allocator, statement.raw);
    }

    pub fn appendCivilStatusRevision(
        self: *Store,
        value: CivilStatusRevisionWrite,
    ) !void {
        try validateOpaqueText(value.profile_id);
        if (value.sequence == 0) return Error.InvalidValue;
        try validatePeriod(value.effective);
        try validateRevisionSource(value.source);

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        if (!(try self.profileExists(value.profile_id))) return Error.NotFound;
        if ((try self.currentAnchorSnapshot(value.profile_id)) == null) {
            return Error.MissingIdentityAnchor;
        }
        const current_sequence = try self.currentCivilStatusSequence(
            value.profile_id,
        );
        if (current_sequence == std.math.maxInt(u32)) {
            return Error.InvalidValue;
        }
        if (current_sequence != value.expected_current_sequence or
            value.sequence != current_sequence + 1)
        {
            return Error.RevisionConflict;
        }
        const source_tag: RevisionSourceTag = value.source;
        const source_reference: ?[]const u8 = switch (value.source) {
            .manual_entry => null,
            .imported => |reference| reference,
            .migrated => |reference| reference,
        };
        var insert = try self.prepare(
            \\INSERT INTO tax_profile_civil_status_revisions (
            \\    profile_id, sequence, effective_from, effective_until,
            \\    status, source_tag, source_reference
            \\) VALUES (?, ?, ?, ?, ?, ?, ?);
        );
        defer insert.deinit();
        try insert.bindText(1, value.profile_id);
        try insert.bindInt64(2, value.sequence);
        try insert.bindDate(3, value.effective.from[0..]);
        try insert.bindOptionalDate(
            4,
            optionalDateSlice(&value.effective.until),
        );
        try insert.bindText(5, civilStatusText(value.status));
        try insert.bindText(6, source_tag.text());
        try insert.bindOptionalText(7, source_reference);
        try insert.expectDone();

        try self.commit();
        committed = true;
    }

    pub fn getCivilStatusAsOf(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        effective_on: []const u8,
    ) !?OwnedCivilStatusRevision {
        try validateOpaqueText(profile_id);
        try validateDate(effective_on);
        var statement = try self.prepare(
            \\SELECT profile_id, sequence, effective_from,
            \\       effective_until, status, source_tag, source_reference
            \\FROM tax_profile_civil_status_revisions
            \\WHERE profile_id = ?
            \\  AND effective_from <= ?
            \\  AND (effective_until IS NULL OR effective_until >= ?)
            \\ORDER BY sequence DESC
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindText(2, effective_on);
        try statement.bindText(3, effective_on);
        if (try statement.step() == .done) return null;
        return try readCivilStatusRevision(allocator, statement.raw);
    }

    pub fn addProfileRelationship(
        self: *Store,
        value: ProfileRelationshipWrite,
    ) !void {
        try validateIdText(value.id);
        try validateOpaqueText(value.from_profile_id);
        try validateOpaqueText(value.to_profile_id);
        if (std.mem.eql(
            u8,
            value.from_profile_id,
            value.to_profile_id,
        )) return Error.InvalidRelationship;
        try validatePeriod(value.effective);
        try validateEvolutionSourceReference(value.provenance);

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        if (!(try self.profileExists(value.from_profile_id)) or
            !(try self.profileExists(value.to_profile_id)))
        {
            return Error.NotFound;
        }
        const from_anchor = (try self.currentAnchorSnapshot(
            value.from_profile_id,
        )) orelse return Error.MissingIdentityAnchor;
        const to_anchor = (try self.currentAnchorSnapshot(
            value.to_profile_id,
        )) orelse return Error.MissingIdentityAnchor;
        if (!relationshipClassesValid(
            value.kind,
            from_anchor.legal_person_class,
            to_anchor.legal_person_class,
        )) return Error.InvalidRelationship;

        var insert = try self.prepare(
            \\INSERT INTO tax_profile_relationships (
            \\    id, from_profile_id, to_profile_id, kind,
            \\    effective_from, effective_until, provenance
            \\) VALUES (?, ?, ?, ?, ?, ?, ?);
        );
        defer insert.deinit();
        try insert.bindText(1, value.id);
        try insert.bindText(2, value.from_profile_id);
        try insert.bindText(3, value.to_profile_id);
        try insert.bindText(4, relationshipKindText(value.kind));
        try insert.bindDate(5, value.effective.from[0..]);
        try insert.bindOptionalDate(
            6,
            optionalDateSlice(&value.effective.until),
        );
        try insert.bindText(7, value.provenance);
        try insert.expectDone();

        try self.commit();
        committed = true;
    }

    pub fn listProfileRelationshipsAsOf(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        effective_on: []const u8,
    ) !ProfileRelationshipList {
        try validateOpaqueText(profile_id);
        try validateDate(effective_on);
        var statement = try self.prepare(
            \\SELECT id, from_profile_id, to_profile_id, kind,
            \\       effective_from, effective_until, provenance
            \\FROM tax_profile_relationships
            \\WHERE (from_profile_id = ? OR to_profile_id = ?)
            \\  AND effective_from <= ?
            \\  AND (effective_until IS NULL OR effective_until >= ?)
            \\ORDER BY effective_from, id;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindText(2, profile_id);
        try statement.bindText(3, effective_on);
        try statement.bindText(4, effective_on);

        var items: std.ArrayList(OwnedProfileRelationship) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const item = try readProfileRelationship(
                allocator,
                statement.raw,
            );
            errdefer {
                var owned = item;
                owned.deinit(allocator);
            }
            try items.append(allocator, item);
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    fn insertRevisionRows(
        self: *Store,
        value: RevisionWrite,
        components: RevisionComponentsWrite,
    ) !void {
        const source_tag: RevisionSourceTag = value.source;
        const source_reference: ?[]const u8 = switch (value.source) {
            .manual_entry => null,
            .imported => |reference| reference,
            .migrated => |reference| reference,
        };
        const subject_kind = value.subject.kind();
        const taxpayer_name: ?[]const u8 = switch (value.subject) {
            .individual => |person| person.name,
            .sole_proprietor => |proprietor| proprietor.person.name,
            .legal_entity => null,
        };
        const registered_name: ?[]const u8 = switch (value.subject) {
            .individual => null,
            .sole_proprietor => |proprietor| proprietor.trade_name,
            .legal_entity => |entity| entity.registered_name,
        };
        const individual: ?IndividualWrite = switch (value.subject) {
            .individual => |person| person,
            .sole_proprietor => |proprietor| proprietor.person,
            .legal_entity => null,
        };
        var insert = try self.prepare(
            \\INSERT INTO tax_profile_revisions (
            \\    id, profile_id, sequence, effective_from, effective_until,
            \\    source_tag, source_reference, tin, rdo_code,
            \\    registered_address, zip_code, contact_number, email_address,
            \\    subject_kind, taxpayer_name, registered_name,
            \\    date_of_birth, citizenship, foreign_tax_number
            \\) VALUES (
            \\    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            \\);
        );
        defer insert.deinit();
        try insert.bindText(1, value.id);
        try insert.bindText(2, value.profile_id);
        try insert.bindInt64(3, value.sequence);
        try insert.bindDate(4, value.effective.from[0..]);
        try insert.bindOptionalDate(
            5,
            optionalDateSlice(&value.effective.until),
        );
        try insert.bindText(6, source_tag.text());
        try insert.bindOptionalText(7, source_reference);
        try insert.bindText(8, value.identity.tin);
        try insert.bindText(9, value.identity.rdo_code);
        try insert.bindText(10, value.contact.registered_address);
        try insert.bindOptionalText(11, value.contact.zip_code);
        try insert.bindOptionalText(12, value.contact.contact_number);
        try insert.bindOptionalText(13, value.contact.email_address);
        try insert.bindText(14, subject_kind.text());
        try insert.bindOptionalText(15, taxpayer_name);
        try insert.bindOptionalText(16, registered_name);
        try insert.bindOptionalDate(
            17,
            if (individual) |*person|
                optionalDateSlice(&person.date_of_birth)
            else
                null,
        );
        try insert.bindOptionalText(
            18,
            if (individual) |person| person.citizenship else null,
        );
        try insert.bindOptionalText(
            19,
            if (individual) |person| person.foreign_tax_number else null,
        );
        try insert.expectDone();

        var add_activity = try self.prepare(
            \\INSERT INTO tax_profile_business_activities (
            \\    profile_id, revision_id, id, line_of_business, atc,
            \\    effective_from, effective_until, ordinal
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_activity.deinit();
        for (components.business_activities) |activity| {
            try add_activity.bindText(1, value.profile_id);
            try add_activity.bindText(2, value.id);
            try add_activity.bindText(3, activity.id);
            try add_activity.bindText(4, activity.line_of_business);
            try add_activity.bindOptionalText(5, activity.atc);
            try add_activity.bindDate(6, activity.effective.from[0..]);
            try add_activity.bindOptionalDate(
                7,
                optionalDateSlice(&activity.effective.until),
            );
            try add_activity.bindInt64(8, activity.ordinal);
            try add_activity.expectDone();
            try add_activity.reset();
        }

        var add_fact = try self.prepare(
            \\INSERT INTO tax_profile_registration_facts (
            \\    profile_id, revision_id, id, kind, value_text,
            \\    effective_from, effective_until, ordinal
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_fact.deinit();
        for (components.registration_facts) |fact| {
            const kind: RegistrationFactKind = fact.value;
            const fact_value: []const u8 = switch (fact.value) {
                .tax_type => |text| text,
                .government_withholding_agent => |answer| answer.text(),
                .special_rate_basis => |text| text,
            };
            try add_fact.bindText(1, value.profile_id);
            try add_fact.bindText(2, value.id);
            try add_fact.bindText(3, fact.id);
            try add_fact.bindText(4, kind.text());
            try add_fact.bindText(5, fact_value);
            try add_fact.bindDate(6, fact.effective.from[0..]);
            try add_fact.bindOptionalDate(
                7,
                optionalDateSlice(&fact.effective.until),
            );
            try add_fact.bindInt64(8, fact.ordinal);
            try add_fact.expectDone();
            try add_fact.reset();
        }
    }

    pub fn getCurrentRevision(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
    ) !?OwnedProfileRevision {
        try validateOpaqueText(profile_id);
        var statement = try self.prepare(
            \\SELECT r.id, r.sequence, r.profile_id, r.effective_from,
            \\       r.effective_until, r.source_tag, r.source_reference,
            \\       r.tin, r.rdo_code, r.registered_address, r.zip_code,
            \\       r.contact_number, r.email_address, r.subject_kind,
            \\       r.taxpayer_name, r.registered_name, r.date_of_birth,
            \\       r.citizenship, r.foreign_tax_number
            \\FROM tax_profiles AS p
            \\JOIN tax_profile_revisions AS r
            \\  ON r.profile_id = p.id AND r.id = p.current_revision_id
            \\WHERE p.id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        return switch (try statement.step()) {
            .done => null,
            .row => try self.readRevision(allocator, statement.raw),
        };
    }

    pub fn getRevision(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        revision_id: []const u8,
    ) !?OwnedProfileRevision {
        try validateIdText(profile_id);
        try validateIdText(revision_id);
        var statement = try self.prepare(
            \\SELECT id, sequence, profile_id, effective_from,
            \\       effective_until, source_tag, source_reference, tin,
            \\       rdo_code, registered_address, zip_code, contact_number,
            \\       email_address, subject_kind, taxpayer_name,
            \\       registered_name, date_of_birth, citizenship,
            \\       foreign_tax_number
            \\FROM tax_profile_revisions
            \\WHERE profile_id = ? AND id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindText(2, revision_id);
        return switch (try statement.step()) {
            .done => null,
            .row => try self.readRevision(allocator, statement.raw),
        };
    }

    pub fn getRevisionBySequence(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        sequence: u32,
    ) !?OwnedProfileRevision {
        try validateIdText(profile_id);
        if (sequence == 0) return Error.InvalidValue;
        var statement = try self.prepare(
            \\SELECT id, sequence, profile_id, effective_from,
            \\       effective_until, source_tag, source_reference, tin,
            \\       rdo_code, registered_address, zip_code, contact_number,
            \\       email_address, subject_kind, taxpayer_name,
            \\       registered_name, date_of_birth, citizenship,
            \\       foreign_tax_number
            \\FROM tax_profile_revisions
            \\WHERE profile_id = ? AND sequence = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindInt64(2, sequence);
        return switch (try statement.step()) {
            .done => null,
            .row => try self.readRevision(allocator, statement.raw),
        };
    }

    pub fn getEffectiveRevision(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        effective_on: []const u8,
    ) !?OwnedProfileRevision {
        try validateOpaqueText(profile_id);
        try validateDate(effective_on);
        var statement = try self.prepare(
            \\SELECT id, sequence, profile_id, effective_from,
            \\       effective_until, source_tag, source_reference, tin,
            \\       rdo_code, registered_address, zip_code, contact_number,
            \\       email_address, subject_kind, taxpayer_name,
            \\       registered_name, date_of_birth, citizenship,
            \\       foreign_tax_number
            \\FROM tax_profile_revisions
            \\WHERE profile_id = ?
            \\  AND effective_from <= ?
            \\  AND (effective_until IS NULL OR effective_until >= ?)
            \\ORDER BY sequence DESC
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindText(2, effective_on);
        try statement.bindText(3, effective_on);
        return switch (try statement.step()) {
            .done => null,
            .row => try self.readRevision(allocator, statement.raw),
        };
    }

    pub fn listProfiles(
        self: *Store,
        allocator: std.mem.Allocator,
        include_archived: bool,
    ) !ProfileSummaryList {
        var statement = try self.prepare(
            \\SELECT p.id, p.status, p.current_revision_id, r.sequence,
            \\       COALESCE(r.taxpayer_name, r.registered_name),
            \\       r.tin, r.subject_kind
            \\FROM tax_profiles AS p
            \\JOIN tax_profile_revisions AS r
            \\  ON r.profile_id = p.id AND r.id = p.current_revision_id
            \\WHERE (? = 1 OR p.status = 'active')
            \\ORDER BY COALESCE(
            \\    r.taxpayer_name, r.registered_name
            \\) COLLATE NOCASE, p.id;
        );
        defer statement.deinit();
        try statement.bindBool(1, include_archived);

        var items: std.ArrayList(OwnedProfileSummary) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const item = try readProfileSummary(allocator, statement.raw);
            errdefer {
                var owned = item;
                owned.deinit(allocator);
            }
            try items.append(allocator, item);
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    /// Replaces the authoritative per-year Forms Set. Passing an empty slice
    /// intentionally leaves the parent row present with zero entries.
    pub fn replaceFormSet(
        self: *Store,
        profile_id: []const u8,
        tax_year: i32,
        forms: []const FormRegistrationWrite,
    ) !void {
        try validateOpaqueText(profile_id);
        try validateTaxYear(tax_year);
        for (forms) |form| {
            try requireValue(form.form_code);
            try requireValue(form.form_revision);
        }

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        var configure = try self.prepare(
            \\INSERT INTO tax_profile_form_sets(profile_id, tax_year, state)
            \\VALUES (?, ?, ?)
            \\ON CONFLICT(profile_id, tax_year) DO UPDATE SET
            \\    state = excluded.state,
            \\    configured_at = unixepoch();
        );
        defer configure.deinit();
        try configure.bindText(1, profile_id);
        try configure.bindInt64(2, tax_year);
        try configure.bindText(
            3,
            if (forms.len == 0) "active_empty" else "active_nonempty",
        );
        try configure.expectDone();

        var clear = try self.prepare(
            \\DELETE FROM tax_profile_form_set_entries
            \\WHERE profile_id = ? AND tax_year = ?;
        );
        defer clear.deinit();
        try clear.bindText(1, profile_id);
        try clear.bindInt64(2, tax_year);
        try clear.expectDone();

        var add = try self.prepare(
            \\INSERT INTO tax_profile_form_set_entries (
            \\    profile_id, tax_year, form_code, form_revision
            \\) VALUES (?, ?, ?, ?);
        );
        defer add.deinit();
        for (forms) |form| {
            try add.bindText(1, profile_id);
            try add.bindInt64(2, tax_year);
            try add.bindText(3, form.form_code);
            try add.bindText(4, form.form_revision);
            try add.expectDone();
            try add.reset();
        }

        try self.commit();
        committed = true;
    }

    /// `null` means no Forms Set is configured and callers may use their
    /// explicit fallback policy. A non-null list with zero items is the
    /// authoritative, intentionally empty set.
    pub fn getFormSet(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        tax_year: i32,
    ) !?FormRegistrationList {
        try validateOpaqueText(profile_id);
        try validateTaxYear(tax_year);
        var configured = try self.prepare(
            \\SELECT 1 FROM tax_profile_form_sets
            \\WHERE profile_id = ? AND tax_year = ?;
        );
        defer configured.deinit();
        try configured.bindText(1, profile_id);
        try configured.bindInt64(2, tax_year);
        if (try configured.step() == .done) return null;

        var statement = try self.prepare(
            \\SELECT form_code, form_revision
            \\FROM tax_profile_form_set_entries
            \\WHERE profile_id = ? AND tax_year = ?
            \\ORDER BY form_code COLLATE NOCASE, form_revision;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindInt64(2, tax_year);

        var items: std.ArrayList(OwnedFormRegistration) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const form_code = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(form_code);
            const form_revision = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(form_revision);
            try items.append(allocator, .{
                .form_code = form_code,
                .form_revision = form_revision,
            });
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    /// Resolves all four product states without relying on a UI fallback.
    /// A missing row is legacy-only when the migrated profile is explicitly
    /// eligible; newly created profiles resolve to needs-configuration.
    pub fn resolveFormSet(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        tax_year: i32,
    ) !ResolvedFormSet {
        try validateOpaqueText(profile_id);
        try validateTaxYear(tax_year);

        var state_query = try self.prepare(
            \\SELECT fs.state, p.legacy_catalog_eligible
            \\FROM tax_profiles AS p
            \\LEFT JOIN tax_profile_form_sets AS fs
            \\  ON fs.profile_id = p.id AND fs.tax_year = ?
            \\WHERE p.id = ?;
        );
        defer state_query.deinit();
        try state_query.bindInt64(1, tax_year);
        try state_query.bindText(2, profile_id);
        if (try state_query.step() == .done) return Error.NotFound;

        const stored_state = columnText(state_query.raw, 0);
        const legacy_eligible = sqlite.sqlite3_column_int(
            state_query.raw,
            1,
        ) == 1;
        const resolved_state: FormSetState = if (stored_state) |value|
            std.meta.stringToEnum(FormSetState, value) orelse
                return Error.InvalidValue
        else if (legacy_eligible)
            .legacy_catalog_default
        else
            .needs_configuration;

        if (stored_state == null) {
            return .{
                .state = resolved_state,
                .legacy_reset_allowed = legacy_eligible,
                .forms = .{ .items = try allocator.alloc(OwnedFormRegistration, 0) },
            };
        }
        return .{
            .state = resolved_state,
            .legacy_reset_allowed = legacy_eligible,
            .forms = (try self.getFormSet(allocator, profile_id, tax_year)).?,
        };
    }

    /// Restores the catalog compatibility state only for profiles migrated
    /// from the former implicit-fallback behavior.
    pub fn resetToLegacyCatalogDefault(
        self: *Store,
        profile_id: []const u8,
        tax_year: i32,
    ) !void {
        try validateOpaqueText(profile_id);
        try validateTaxYear(tax_year);
        var eligibility = try self.prepare(
            \\SELECT legacy_catalog_eligible FROM tax_profiles WHERE id = ?;
        );
        defer eligibility.deinit();
        try eligibility.bindText(1, profile_id);
        if (try eligibility.step() == .done) return Error.NotFound;
        if (sqlite.sqlite3_column_int(eligibility.raw, 0) != 1) {
            return Error.InvalidValue;
        }
        _ = try self.clearFormSet(profile_id, tax_year);
    }

    /// Removes the configuration marker so `getFormSet` returns null again.
    pub fn clearFormSet(
        self: *Store,
        profile_id: []const u8,
        tax_year: i32,
    ) !bool {
        try validateOpaqueText(profile_id);
        try validateTaxYear(tax_year);
        var statement = try self.prepare(
            \\DELETE FROM tax_profile_form_sets
            \\WHERE profile_id = ? AND tax_year = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindInt64(2, tax_year);
        try statement.expectDone();
        return sqlite.sqlite3_changes(try self.handle()) != 0;
    }

    /// Replaces the selected forms for one tax profile. Passing an empty
    /// slice intentionally keeps the parent marker and therefore represents
    /// "show no forms". The all-forms default is restored only through
    /// `clearCalendarFormSelection`.
    pub fn replaceCalendarFormSelection(
        self: *Store,
        profile_id: []const u8,
        form_codes: []const []const u8,
    ) !void {
        try validateOpaqueText(profile_id);
        for (form_codes) |form_code| try requireValue(form_code);

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        var configure = try self.prepare(
            \\INSERT INTO tax_profile_calendar_form_selections(profile_id)
            \\VALUES (?)
            \\ON CONFLICT(profile_id) DO UPDATE SET
            \\    configured_at = unixepoch();
        );
        defer configure.deinit();
        try configure.bindText(1, profile_id);
        try configure.expectDone();

        var clear = try self.prepare(
            \\DELETE FROM tax_profile_calendar_form_selection_entries
            \\WHERE profile_id = ?;
        );
        defer clear.deinit();
        try clear.bindText(1, profile_id);
        try clear.expectDone();

        var add = try self.prepare(
            \\INSERT INTO tax_profile_calendar_form_selection_entries (
            \\    profile_id, form_code
            \\) VALUES (?, ?);
        );
        defer add.deinit();
        for (form_codes) |form_code| {
            try add.bindText(1, profile_id);
            try add.bindText(2, form_code);
            try add.expectDone();
            try add.reset();
        }

        try self.commit();
        committed = true;
    }

    /// `null` means the profile uses the catalog default (all forms). A
    /// non-null result with zero codes is an explicit empty selection.
    pub fn getCalendarFormSelection(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
    ) !?CalendarFormSelection {
        try validateOpaqueText(profile_id);
        var statement = try self.prepare(
            \\SELECT selection.profile_id, entry.form_code
            \\FROM tax_profile_calendar_form_selections AS selection
            \\LEFT JOIN tax_profile_calendar_form_selection_entries AS entry
            \\  ON entry.profile_id = selection.profile_id
            \\WHERE selection.profile_id = ?
            \\ORDER BY entry.form_code COLLATE NOCASE;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);

        var form_codes: std.ArrayList([]u8) = .empty;
        errdefer {
            for (form_codes.items) |form_code| allocator.free(form_code);
            form_codes.deinit(allocator);
        }
        var configured = false;
        while (try statement.step() == .row) {
            configured = true;
            const form_code = columnText(statement.raw, 1) orelse continue;
            try form_codes.ensureUnusedCapacity(allocator, 1);
            const owned_form_code = try allocator.dupe(u8, form_code);
            form_codes.appendAssumeCapacity(owned_form_code);
        }
        if (!configured) {
            form_codes.deinit(allocator);
            return null;
        }
        return .{ .form_codes = try form_codes.toOwnedSlice(allocator) };
    }

    /// Removes the explicit selection so future catalog additions remain
    /// selected by default.
    pub fn clearCalendarFormSelection(
        self: *Store,
        profile_id: []const u8,
    ) !bool {
        try validateOpaqueText(profile_id);
        var statement = try self.prepare(
            \\DELETE FROM tax_profile_calendar_form_selections
            \\WHERE profile_id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.expectDone();
        return sqlite.sqlite3_changes(try self.handle()) != 0;
    }

    /// Atomically reserves the next canonical `YYYY-O###` occurrence for one
    /// on-demand form. `BEGIN IMMEDIATE` serializes allocators across SQLite
    /// connections; the persisted counter makes the reservation durable even
    /// before a draft is composed. On first use, canonical legacy draft keys
    /// are reconciled so an existing occurrence is never reused.
    pub fn allocateOnDemandOccurrence(
        self: *Store,
        scope: OnDemandOccurrenceScope,
    ) !u32 {
        try validateLocalOwnerId(scope.owner_id);
        try validateOpaqueText(scope.profile_id);
        try requireExactText(scope.form_code);
        try requireExactText(scope.form_revision);
        try validateTaxYear(scope.tax_year);

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        var owned_profile = try self.prepare(
            \\SELECT 1
            \\FROM tax_profiles
            \\WHERE id = ? AND owner_id = ?;
        );
        defer owned_profile.deinit();
        try owned_profile.bindText(1, scope.profile_id);
        try owned_profile.bindText(2, scope.owner_id);
        if (try owned_profile.step() != .row) return Error.NotFound;
        if (try owned_profile.step() != .done) return Error.SqliteFailure;

        var counter_read = try self.prepare(
            \\SELECT last_occurrence
            \\FROM tax_form_on_demand_occurrence_counters
            \\WHERE owner_id = ? AND profile_id = ?
            \\  AND form_code = ? AND form_revision = ?
            \\  AND tax_year = ?;
        );
        defer counter_read.deinit();
        try counter_read.bindText(1, scope.owner_id);
        try counter_read.bindText(2, scope.profile_id);
        try counter_read.bindText(3, scope.form_code);
        try counter_read.bindText(4, scope.form_revision);
        try counter_read.bindInt64(5, scope.tax_year);
        const counter_value: u32 = switch (try counter_read.step()) {
            .done => 0,
            .row => blk: {
                const raw = sqlite.sqlite3_column_int64(counter_read.raw, 0);
                if (raw < 1 or raw > max_on_demand_occurrence) {
                    return Error.SqliteFailure;
                }
                if (try counter_read.step() != .done) {
                    return Error.SqliteFailure;
                }
                break :blk @intCast(raw);
            },
        };

        // Drafts created before this allocator remain authoritative. Only the
        // canonical fixed-width on-demand key is considered; recurring and
        // malformed legacy keys cannot influence this sequence.
        var draft_max_read = try self.prepare(
            \\SELECT COALESCE(MAX(CAST(substr(draft.period_key, 7, 3)
            \\                            AS INTEGER)), 0)
            \\FROM tax_form_drafts AS draft
            \\JOIN tax_form_draft_role_bindings AS binding
            \\  ON binding.draft_id = draft.id
            \\JOIN tax_profiles AS profile
            \\  ON profile.id = binding.profile_id
            \\WHERE binding.role = 'filer'
            \\  AND binding.profile_id = ? AND profile.owner_id = ?
            \\  AND draft.form_code = ? AND draft.form_revision = ?
            \\  AND length(draft.period_key) = 9
            \\  AND draft.period_key GLOB
            \\      printf('%04d-O[0-9][0-9][0-9]', ?);
        );
        defer draft_max_read.deinit();
        try draft_max_read.bindText(1, scope.profile_id);
        try draft_max_read.bindText(2, scope.owner_id);
        try draft_max_read.bindText(3, scope.form_code);
        try draft_max_read.bindText(4, scope.form_revision);
        try draft_max_read.bindInt64(5, scope.tax_year);
        if (try draft_max_read.step() != .row) return Error.SqliteFailure;
        const draft_max_raw = sqlite.sqlite3_column_int64(
            draft_max_read.raw,
            0,
        );
        if (draft_max_raw < 0 or
            draft_max_raw > max_on_demand_occurrence)
        {
            return Error.SqliteFailure;
        }
        if (try draft_max_read.step() != .done) return Error.SqliteFailure;
        const draft_max: u32 = @intCast(draft_max_raw);
        const prior = @max(counter_value, draft_max);
        if (prior == max_on_demand_occurrence) {
            return Error.OnDemandOccurrenceLimitExceeded;
        }
        const occurrence = prior + 1;

        var reserve = try self.prepare(
            \\INSERT INTO tax_form_on_demand_occurrence_counters (
            \\    owner_id, profile_id, form_code, form_revision,
            \\    tax_year, last_occurrence
            \\) VALUES (?, ?, ?, ?, ?, ?)
            \\ON CONFLICT(
            \\    owner_id, profile_id, form_code, form_revision, tax_year
            \\) DO UPDATE SET
            \\    last_occurrence = excluded.last_occurrence,
            \\    updated_at = unixepoch();
        );
        defer reserve.deinit();
        try reserve.bindText(1, scope.owner_id);
        try reserve.bindText(2, scope.profile_id);
        try reserve.bindText(3, scope.form_code);
        try reserve.bindText(4, scope.form_revision);
        try reserve.bindInt64(5, scope.tax_year);
        try reserve.bindInt64(6, occurrence);
        try reserve.expectDone();
        if (sqlite.sqlite3_changes(try self.handle()) != 1) {
            return Error.SqliteFailure;
        }

        try self.commit();
        committed = true;
        return occurrence;
    }

    /// Creates a draft, its named role bindings, immutable profile snapshot,
    /// and initial transaction values in one transaction. Binding order has no
    /// meaning; role names are the stable identity.
    pub fn createDraft(
        self: *Store,
        draft: DraftWrite,
        bindings: []const RoleBindingWrite,
        snapshots: []const SnapshotFieldWrite,
        values: []const DraftValueWrite,
    ) !void {
        try validateDraft(draft, bindings, snapshots, values);

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        if (draft.amendment_of) |prior_id| {
            var prior = try self.prepare(
                \\SELECT form_code, form_revision
                \\FROM tax_form_drafts
                \\WHERE id = ?;
            );
            defer prior.deinit();
            try prior.bindText(1, prior_id);
            if (try prior.step() != .row) return Error.InvalidAmendment;
            const prior_code = columnText(prior.raw, 0) orelse
                return Error.SqliteFailure;
            const prior_revision = columnText(prior.raw, 1) orelse
                return Error.SqliteFailure;
            if (!std.mem.eql(u8, prior_code, draft.form_code) or
                !std.mem.eql(u8, prior_revision, draft.form_revision))
            {
                return Error.InvalidAmendment;
            }
        }

        var add_draft = try self.prepare(
            \\INSERT INTO tax_form_drafts (
            \\    id, form_code, form_revision, period_key, profile_as_of,
            \\    lifecycle, intent, mapping_revision, amendment_of
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_draft.deinit();
        try add_draft.bindText(1, draft.id);
        try add_draft.bindText(2, draft.form_code);
        try add_draft.bindText(3, draft.form_revision);
        try add_draft.bindText(4, draft.period_key);
        try add_draft.bindDate(5, draft.profile_as_of[0..]);
        try add_draft.bindText(6, draft.lifecycle);
        try add_draft.bindText(7, draft.intent);
        try add_draft.bindText(8, draft.mapping_revision);
        try add_draft.bindOptionalText(9, draft.amendment_of);
        try add_draft.expectDone();

        var add_binding = try self.prepare(
            \\INSERT INTO tax_form_draft_role_bindings (
            \\    draft_id, role, profile_id, profile_revision_id,
            \\    profile_revision_sequence, business_activity_id
            \\) VALUES (?, ?, ?, ?, ?, ?);
        );
        defer add_binding.deinit();
        for (bindings) |binding| {
            try add_binding.bindText(1, draft.id);
            try add_binding.bindText(2, binding.role);
            try add_binding.bindText(3, binding.profile_id);
            try add_binding.bindText(4, binding.profile_revision_id);
            try add_binding.bindInt64(5, binding.profile_revision_sequence);
            try add_binding.bindOptionalText(6, binding.business_activity_id);
            try add_binding.expectDone();
            try add_binding.reset();
        }

        var add_snapshot = try self.prepare(
            \\INSERT INTO tax_form_draft_snapshot_fields (
            \\    draft_id, role, field_id, reusable_field, value_type,
            \\    value_text, provenance, profile_revision_id,
            \\    profile_revision_sequence, revision_source_tag,
            \\    revision_source_reference, business_activity_id,
            \\    registration_fact_id, overridden
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_snapshot.deinit();
        for (snapshots) |snapshot| {
            const binding = findBinding(bindings, snapshot.role) orelse
                return Error.InvalidValue;
            if (!std.mem.eql(
                u8,
                binding.profile_revision_id,
                snapshot.profile_revision_id,
            ) or binding.profile_revision_sequence !=
                snapshot.profile_revision_sequence)
            {
                return Error.InvalidValue;
            }
            const source_tag: RevisionSourceTag = snapshot.revision_source;
            const source_reference: ?[]const u8 = switch (snapshot.revision_source) {
                .manual_entry => null,
                .imported => |reference| reference,
                .migrated => |reference| reference,
            };
            try add_snapshot.bindText(1, draft.id);
            try add_snapshot.bindText(2, snapshot.role);
            try add_snapshot.bindText(3, snapshot.field_id);
            try add_snapshot.bindText(4, snapshot.reusable_field);
            try add_snapshot.bindText(5, snapshot.value_type);
            try add_snapshot.bindText(6, snapshot.value_text);
            try add_snapshot.bindText(7, snapshot.provenance);
            try add_snapshot.bindText(8, snapshot.profile_revision_id);
            try add_snapshot.bindInt64(9, snapshot.profile_revision_sequence);
            try add_snapshot.bindText(10, source_tag.text());
            try add_snapshot.bindOptionalText(11, source_reference);
            try add_snapshot.bindOptionalText(12, snapshot.business_activity_id);
            try add_snapshot.bindOptionalText(13, snapshot.registration_fact_id);
            try add_snapshot.bindBool(14, snapshot.overridden);
            try add_snapshot.expectDone();
            try add_snapshot.reset();
        }

        var add_value = try self.prepare(
            \\INSERT INTO tax_form_draft_values (
            \\    draft_id, field_id, value_text, provenance
            \\) VALUES (?, ?, ?, ?);
        );
        defer add_value.deinit();
        for (values) |value| {
            try add_value.bindText(1, draft.id);
            try add_value.bindText(2, value.field_id);
            try add_value.bindText(3, value.value_text);
            try add_value.bindText(4, value.provenance);
            try add_value.expectDone();
            try add_value.reset();
        }

        try self.commit();
        committed = true;
    }

    pub fn getDraft(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_id: []const u8,
    ) !?OwnedDraft {
        try validateOpaqueText(draft_id);
        var statement = try self.prepare(
            \\SELECT id, form_code, form_revision, period_key, profile_as_of,
            \\       lifecycle, intent, mapping_revision, amendment_of
            \\FROM tax_form_drafts
            \\WHERE id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        if (try statement.step() == .done) return null;

        const id = try dupColumn(allocator, statement.raw, 0);
        errdefer allocator.free(id);
        const form_code = try dupColumn(allocator, statement.raw, 1);
        errdefer allocator.free(form_code);
        const form_revision = try dupColumn(allocator, statement.raw, 2);
        errdefer allocator.free(form_revision);
        const period_key = try dupColumn(allocator, statement.raw, 3);
        errdefer allocator.free(period_key);
        const profile_as_of = try dupColumn(allocator, statement.raw, 4);
        errdefer allocator.free(profile_as_of);
        const lifecycle = try dupColumn(allocator, statement.raw, 5);
        errdefer allocator.free(lifecycle);
        const intent = try dupColumn(allocator, statement.raw, 6);
        errdefer allocator.free(intent);
        const mapping_revision = try dupColumn(allocator, statement.raw, 7);
        errdefer allocator.free(mapping_revision);
        const amendment_of = try dupOptionalColumn(allocator, statement.raw, 8);
        errdefer freeOptional(allocator, amendment_of);
        const bindings = try self.loadBindings(allocator, draft_id);
        errdefer {
            for (bindings) |*binding| binding.deinit(allocator);
            allocator.free(bindings);
        }
        const snapshots = try self.loadSnapshots(allocator, draft_id);
        errdefer {
            for (snapshots) |*snapshot| snapshot.deinit(allocator);
            allocator.free(snapshots);
        }
        const values = try self.loadDraftValues(allocator, draft_id);
        errdefer {
            for (values) |*value| value.deinit(allocator);
            allocator.free(values);
        }
        return .{
            .id = id,
            .form_code = form_code,
            .form_revision = form_revision,
            .period_key = period_key,
            .profile_as_of = profile_as_of,
            .lifecycle = lifecycle,
            .intent = intent,
            .mapping_revision = mapping_revision,
            .amendment_of = amendment_of,
            .bindings = bindings,
            .snapshots = snapshots,
            .values = values,
        };
    }

    /// Lists filing work bound to one taxpayer in the filer role for the
    /// viewed tax year and its immediately preceding taxable year. A draft may
    /// carry other profile roles (for example a spouse), but it belongs on
    /// exactly one taxpayer dashboard: the filer profile. Older history is
    /// intentionally excluded before allocation so it cannot crowd the
    /// dashboard's bounded presentation cache.
    pub fn listDraftSummariesForProfile(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        viewed_tax_year: i32,
    ) !DraftSummaryList {
        try validateOpaqueText(profile_id);
        try validateTaxYear(viewed_tax_year);
        const prior_tax_year = viewed_tax_year -| 1;
        var statement = try self.prepare(
            \\SELECT draft.id, draft.form_code, draft.form_revision,
            \\       draft.period_key, draft.lifecycle, draft.intent
            \\FROM tax_form_drafts AS draft
            \\JOIN tax_form_draft_role_bindings AS binding
            \\  ON binding.draft_id = draft.id
            \\WHERE binding.role = 'filer' AND binding.profile_id = ?
            \\  AND (substr(draft.period_key, 1, 4) = printf('%04d', ?)
            \\       OR substr(draft.period_key, 1, 4) = printf('%04d', ?))
            \\ORDER BY draft.period_key DESC,
            \\         draft.form_code COLLATE NOCASE, draft.id;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindInt64(2, viewed_tax_year);
        try statement.bindInt64(3, prior_tax_year);

        var items: std.ArrayList(OwnedDraftSummary) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const id = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(id);
            const form_code = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(form_code);
            const form_revision = try dupColumn(allocator, statement.raw, 2);
            errdefer allocator.free(form_revision);
            const period_key = try dupColumn(allocator, statement.raw, 3);
            errdefer allocator.free(period_key);
            const lifecycle = try dupColumn(allocator, statement.raw, 4);
            errdefer allocator.free(lifecycle);
            const intent = try dupColumn(allocator, statement.raw, 5);
            errdefer allocator.free(intent);
            try items.append(allocator, .{
                .id = id,
                .form_code = form_code,
                .form_revision = form_revision,
                .period_key = period_key,
                .lifecycle = lifecycle,
                .intent = intent,
            });
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    pub fn putDraftValue(
        self: *Store,
        draft_id: []const u8,
        value: DraftValueWrite,
    ) !void {
        try validateOpaqueText(draft_id);
        try requireValue(value.field_id);
        try requireValue(value.provenance);
        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();
        if (!(try self.draftAcceptsEdits(draft_id))) return Error.InvalidTransition;
        var statement = try self.prepare(
            \\INSERT INTO tax_form_draft_values (
            \\    draft_id, field_id, value_text, provenance
            \\) VALUES (?, ?, ?, ?)
            \\ON CONFLICT(draft_id, field_id) DO UPDATE SET
            \\    value_text = excluded.value_text,
            \\    provenance = excluded.provenance,
            \\    updated_at = unixepoch();
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        try statement.bindText(2, value.field_id);
        try statement.bindText(3, value.value_text);
        try statement.bindText(4, value.provenance);
        try statement.expectDone();
        try self.commit();
        committed = true;
    }

    /// Atomically replaces the editable filing-value slice without touching
    /// immutable profile bindings or prefill snapshots.
    pub fn replaceDraftValues(
        self: *Store,
        draft_id: []const u8,
        values: []const DraftValueWrite,
    ) !void {
        try validateOpaqueText(draft_id);
        try validateDraftValues(values);
        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();
        if (!(try self.draftAcceptsEdits(draft_id))) {
            return Error.InvalidTransition;
        }

        var remove = try self.prepare(
            \\DELETE FROM tax_form_draft_values
            \\WHERE draft_id = ?;
        );
        defer remove.deinit();
        try remove.bindText(1, draft_id);
        try remove.expectDone();

        var insert = try self.prepare(
            \\INSERT INTO tax_form_draft_values (
            \\    draft_id, field_id, value_text, provenance
            \\) VALUES (?, ?, ?, ?);
        );
        defer insert.deinit();
        for (values) |value| {
            try insert.bindText(1, draft_id);
            try insert.bindText(2, value.field_id);
            try insert.bindText(3, value.value_text);
            try insert.bindText(4, value.provenance);
            try insert.expectDone();
            try insert.reset();
        }

        try self.commit();
        committed = true;
    }

    pub fn deleteDraftValue(
        self: *Store,
        draft_id: []const u8,
        field_id: []const u8,
    ) !bool {
        try validateOpaqueText(draft_id);
        try requireValue(field_id);
        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();
        if (!(try self.draftAcceptsEdits(draft_id))) return Error.InvalidTransition;
        var statement = try self.prepare(
            \\DELETE FROM tax_form_draft_values
            \\WHERE draft_id = ? AND field_id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        try statement.bindText(2, field_id);
        try statement.expectDone();
        const deleted = sqlite.sqlite3_changes(try self.handle()) != 0;
        try self.commit();
        committed = true;
        return deleted;
    }

    /// Performs an optimistic lifecycle transition. Both the transition graph
    /// and the expected current state are checked before updating.
    pub fn transitionDraft(
        self: *Store,
        draft_id: []const u8,
        expected: []const u8,
        next: []const u8,
    ) !void {
        try validateOpaqueText(draft_id);
        if (!validLifecycle(expected) or !validLifecycle(next)) {
            return Error.InvalidTransition;
        }
        if (!lifecycleTransitionAllowed(expected, next)) {
            return Error.InvalidTransition;
        }
        var statement = try self.prepare(
            \\UPDATE tax_form_drafts
            \\SET lifecycle = ?, updated_at = unixepoch()
            \\WHERE id = ? AND lifecycle = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, next);
        try statement.bindText(2, draft_id);
        try statement.bindText(3, expected);
        try statement.expectDone();
        if (sqlite.sqlite3_changes(try self.handle()) == 0) {
            if (try self.draftExists(draft_id)) return Error.RevisionConflict;
            return Error.NotFound;
        }
    }

    pub fn deleteDraft(self: *Store, draft_id: []const u8) !bool {
        try validateOpaqueText(draft_id);
        var statement = try self.prepare(
            \\DELETE FROM tax_form_drafts
            \\WHERE id = ? AND lifecycle IN ('editing', 'cancelled');
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        try statement.expectDone();
        return sqlite.sqlite3_changes(try self.handle()) != 0;
    }

    /// Appends one complete exact draft revision. For `.create`, the
    /// workspace, immutable role bindings, ordered values, and revision row
    /// are committed together. For `.match`, the supplied revision must match
    /// the current persisted revision exactly; stale writers cannot branch or
    /// overwrite history.
    pub fn appendExactDraftRevision(
        self: *Store,
        plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
        guard: ExactDraftRevisionGuard,
        value: ExactDraftRevisionWrite,
    ) !void {
        try key_custody.requireSyntheticPlaintextForTest(
            plaintext_capability,
        );
        try validateExactDraftRevisionWrite(value);

        const snapshot = value.snapshot;
        const workspace_id = snapshot.draft_identity.workspace_id;
        const filing_digest = value.filing_key.canonicalDigest();
        const incoming_value_bytes = exactStoredRetainedValueBytes(
            snapshot.occurrences,
        ) orelse return Error.DraftRetainedValueLimitExceeded;
        if (incoming_value_bytes >
            exact_draft.max_retained_exact_value_bytes)
        {
            return Error.DraftRetainedValueLimitExceeded;
        }

        try self.beginImmediate();
        var committed = false;
        errdefer if (!committed) self.rollbackNoFail();

        const persisted_current = try self.exactWorkspaceCurrentRevision(
            workspace_id,
            value.filing_key,
            snapshot.schema.exact_schema_digest,
        );
        switch (guard) {
            .create => {
                if (persisted_current != null) {
                    return Error.DraftAlreadyExists;
                }
                if (snapshot.revision.value != 1 or
                    snapshot.parent_revision != null)
                {
                    return Error.DraftStaleRevision;
                }
                if (!(try self.exactWorkspaceMatchesFilingKey(
                    workspace_id,
                    value.filing_key,
                ))) {
                    try self.ensureExactWorkspaceCapacity(
                        value.filing_key,
                    );
                }
                var add_workspace = try self.prepare(
                    \\INSERT INTO tax_exact_draft_streams (
                    \\    workspace_id, filing_business_key_digest,
                    \\    filer_profile_id, form_code, form_revision,
                    \\    period_key, filing_intent, exact_schema_digest
                    \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                );
                defer add_workspace.deinit();
                try add_workspace.bindBlob(1, &workspace_id.bytes);
                try add_workspace.bindBlob(2, filing_digest.asBytes());
                try add_workspace.bindText(
                    3,
                    value.filing_key.filer_profile_id,
                );
                try add_workspace.bindText(4, value.filing_key.form_code);
                try add_workspace.bindText(5, value.filing_key.form_revision);
                try add_workspace.bindText(6, value.filing_key.period_key);
                try add_workspace.bindText(7, value.filing_key.intent.text());
                try add_workspace.bindBlob(
                    8,
                    snapshot.schema.exact_schema_digest.asBytes(),
                );
                try add_workspace.expectDone();
            },
            .match => |expected| {
                const current = persisted_current orelse
                    return Error.NotFound;
                if (current >=
                    exact_draft.max_revisions_per_exact_shape_stream)
                {
                    return Error.DraftRevisionLimitExceeded;
                }
                if (current != expected.value or
                    snapshot.revision.value != current + 1 or
                    snapshot.parent_revision == null or
                    snapshot.parent_revision.?.value != current)
                {
                    return Error.DraftStaleRevision;
                }
                const preflight = try self.preflightExactDraftHistory(
                    snapshot.draft_identity,
                );
                if (preflight.revision_count != current) {
                    return Error.SqliteFailure;
                }
                const next_retained_value_bytes = std.math.add(
                    usize,
                    preflight.retained_value_bytes,
                    incoming_value_bytes,
                ) catch return Error.DraftRetainedValueLimitExceeded;
                if (next_retained_value_bytes >
                    exact_draft.max_retained_exact_value_bytes)
                {
                    return Error.DraftRetainedValueLimitExceeded;
                }
            },
        }

        var add_binding = try self.prepare(
            \\INSERT INTO tax_exact_draft_revision_bindings (
            \\    workspace_id, exact_schema_digest, revision,
            \\    role, instance_id, profile_id,
            \\    profile_revision_id, profile_revision_sequence,
            \\    business_activity_id, provenance
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_binding.deinit();
        for (value.bindings) |binding| {
            try add_binding.bindBlob(1, &workspace_id.bytes);
            try add_binding.bindBlob(
                2,
                snapshot.schema.exact_schema_digest.asBytes(),
            );
            try add_binding.bindInt64(
                3,
                checkedU64ToI64(snapshot.revision.value) orelse
                    return Error.InvalidValue,
            );
            try add_binding.bindText(4, binding.role);
            try add_binding.bindText(5, binding.instance_id);
            try add_binding.bindText(6, binding.profile_id);
            try add_binding.bindText(7, binding.profile_revision_id);
            try add_binding.bindInt64(
                8,
                @intCast(binding.profile_revision_sequence),
            );
            try add_binding.bindOptionalText(9, binding.business_activity_id);
            try add_binding.bindText(10, binding.provenance);
            try add_binding.expectDone();
            try add_binding.reset();
        }

        var add_occurrence = try self.prepare(
            \\INSERT INTO tax_exact_draft_occurrences (
            \\    workspace_id, exact_schema_digest, revision,
            \\    ordinal, serialized_key,
            \\    same_key_occurrence, raw_value, normalized_value,
            \\    emitted_value, origin, provenance
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        );
        defer add_occurrence.deinit();
        for (
            snapshot.occurrences,
            value.occurrence_contexts,
        ) |occurrence_value, context| {
            try add_occurrence.bindBlob(1, &workspace_id.bytes);
            try add_occurrence.bindBlob(
                2,
                snapshot.schema.exact_schema_digest.asBytes(),
            );
            try add_occurrence.bindInt64(
                3,
                checkedU64ToI64(snapshot.revision.value) orelse
                    return Error.InvalidValue,
            );
            try add_occurrence.bindInt64(4, occurrence_value.ordinal);
            try add_occurrence.bindBlob(5, occurrence_value.serialized_key);
            try add_occurrence.bindInt64(
                6,
                occurrence_value.same_key_occurrence,
            );
            try add_occurrence.bindBlob(7, occurrence_value.raw_value);
            try add_occurrence.bindBlob(
                8,
                occurrence_value.normalized_value,
            );
            try add_occurrence.bindBlob(9, occurrence_value.emitted_value);
            try add_occurrence.bindText(
                10,
                exactDraftOriginText(context.origin),
            );
            try add_occurrence.bindText(11, context.provenance);
            try add_occurrence.expectDone();
            try add_occurrence.reset();
        }

        const validation_columns = exactValidationColumns(
            snapshot.validation_status,
        );
        const artifact_columns = exactArtifactColumns(
            snapshot.artifact_status,
        );
        const schema = snapshot.schema;
        const package = schema.package_key;
        var add_revision = try self.prepare(
            \\INSERT INTO tax_exact_draft_revisions (
            \\    workspace_id, revision, parent_revision, profile_as_of,
            \\    recorded_at_unix_seconds, package_form_code,
            \\    package_form_revision, locale, offline_package_version,
            \\    payload_schema_token, offline_package_sha256,
            \\    primary_source_sha256, dependency_manifest_sha256,
            \\    official_pdf_sha256, official_guide_sha256, codec_version,
            \\    package_digest, occurrence_manifest_digest,
            \\    exact_schema_digest, payload_shape, occurrence_count,
            \\    readiness_identity_resolved,
            \\    readiness_dependency_closure,
            \\    readiness_profile_mapping_reviewed,
            \\    readiness_calculation_reconciled,
            \\    readiness_validation_reconciled,
            \\    readiness_editable_serializer_exact,
            \\    readiness_final_plaintext_serializer_exact,
            \\    readiness_decrypt_codec_qualified,
            \\    readiness_encrypt_codec_qualified,
            \\    readiness_persistence_integrated,
            \\    readiness_ui_integrated,
            \\    readiness_offline_package_verified,
            \\    profile_snapshot_digest, transaction_state_digest,
            \\    ordered_values_digest, validation_current_year,
            \\    spouse_tin_checksum, save_gate_status, save_gate_rule,
            \\    full_validation_status, full_validation_code,
            \\    artifact_status, artifact_marker, artifact_byte_length,
            \\    artifact_sha256
            \\) VALUES (
            \\    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            \\    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            \\    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            \\);
        );
        defer add_revision.deinit();
        try add_revision.bindBlob(1, &workspace_id.bytes);
        try add_revision.bindInt64(
            2,
            checkedU64ToI64(snapshot.revision.value) orelse
                return Error.InvalidValue,
        );
        try add_revision.bindOptionalInt64(
            3,
            if (snapshot.parent_revision) |parent|
                checkedU64ToI64(parent.value)
            else
                null,
        );
        try add_revision.bindDate(4, value.profile_as_of[0..]);
        try add_revision.bindInt64(5, value.recorded_at_unix_seconds);
        try add_revision.bindText(6, package.revision.code.asSlice());
        try add_revision.bindText(7, package.revision.revision.asSlice());
        try add_revision.bindText(8, @tagName(package.locale));
        try add_revision.bindText(9, @tagName(package.offline_package_version));
        try add_revision.bindText(
            10,
            @tagName(package.payload_schema_or_form_token),
        );
        try add_revision.bindBlob(11, package.offline_package_sha256.asBytes());
        try add_revision.bindBlob(12, package.primary_source_sha256.asBytes());
        try add_revision.bindBlob(
            13,
            package.dependency_manifest_sha256.asBytes(),
        );
        try add_revision.bindOptionalDigest(14, &package.official_pdf_sha256);
        try add_revision.bindOptionalDigest(15, &package.official_guide_sha256);
        try add_revision.bindOptionalText(
            16,
            if (package.codec_version) |codec| @tagName(codec) else null,
        );
        try add_revision.bindBlob(17, schema.package_digest.asBytes());
        try add_revision.bindBlob(
            18,
            schema.occurrence_manifest_digest.asBytes(),
        );
        try add_revision.bindBlob(19, schema.exact_schema_digest.asBytes());
        try add_revision.bindText(20, @tagName(schema.payload_shape));
        try add_revision.bindInt64(21, schema.occurrence_count);
        try add_revision.bindBool(
            22,
            schema.evidence_readiness.identity_resolved,
        );
        try add_revision.bindBool(
            23,
            schema.evidence_readiness.dependency_closure,
        );
        try add_revision.bindBool(
            24,
            schema.evidence_readiness.profile_mapping_reviewed,
        );
        try add_revision.bindBool(
            25,
            schema.evidence_readiness.calculation_reconciled,
        );
        try add_revision.bindBool(
            26,
            schema.evidence_readiness.validation_reconciled,
        );
        try add_revision.bindBool(
            27,
            schema.evidence_readiness.editable_serializer_exact,
        );
        try add_revision.bindBool(
            28,
            schema.evidence_readiness.final_plaintext_serializer_exact,
        );
        try add_revision.bindBool(
            29,
            schema.evidence_readiness.decrypt_codec_qualified,
        );
        try add_revision.bindBool(
            30,
            schema.evidence_readiness.encrypt_codec_qualified,
        );
        try add_revision.bindBool(
            31,
            schema.evidence_readiness.persistence_integrated,
        );
        try add_revision.bindBool(
            32,
            schema.evidence_readiness.ui_integrated,
        );
        try add_revision.bindBool(
            33,
            schema.evidence_readiness.offline_package_verified,
        );
        try add_revision.bindBlob(
            34,
            snapshot.profile_snapshot_digest.asBytes(),
        );
        try add_revision.bindBlob(
            35,
            snapshot.transaction_state_digest.asBytes(),
        );
        try add_revision.bindBlob(
            36,
            snapshot.ordered_values_digest.asBytes(),
        );
        try add_revision.bindInt64(
            37,
            value.validation_evidence.validation_current_year,
        );
        try add_revision.bindText(
            38,
            @tagName(value.validation_evidence.spouse_tin_checksum),
        );
        try add_revision.bindText(39, validation_columns.save_status);
        try add_revision.bindOptionalInt64(40, validation_columns.save_code);
        try add_revision.bindText(41, validation_columns.full_status);
        try add_revision.bindOptionalInt64(42, validation_columns.full_code);
        try add_revision.bindText(43, artifact_columns.status);
        try add_revision.bindOptionalText(44, artifact_columns.marker);
        try add_revision.bindOptionalInt64(45, artifact_columns.byte_length);
        try add_revision.bindOptionalDigest(46, &artifact_columns.sha256);
        try add_revision.expectDone();

        try self.commit();
        committed = true;
    }

    /// Reads all immutable revisions in ascending order and deep-copies every
    /// value-bearing buffer. The caller owns the result.
    pub fn getExactDraftHistory(
        self: *Store,
        plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
        allocator: std.mem.Allocator,
        draft_identity: ExactDraftIdentity,
    ) !?OwnedExactDraftHistory {
        try key_custody.requireSyntheticPlaintextForTest(
            plaintext_capability,
        );
        try validateDraftWorkspaceId(draft_identity.workspace_id);
        var workspace = try self.prepare(
            \\SELECT filer_profile_id, form_code, form_revision, period_key,
            \\       filing_intent, exact_schema_digest
            \\FROM tax_exact_draft_streams
            \\WHERE workspace_id = ? AND exact_schema_digest = ?;
        );
        defer workspace.deinit();
        try workspace.bindBlob(1, &draft_identity.workspace_id.bytes);
        try workspace.bindBlob(
            2,
            draft_identity.exact_schema_digest.asBytes(),
        );
        if (try workspace.step() == .done) return null;

        // Preflight while every SQLite column is still borrowed. The filing
        // key, revisions, bindings, and sensitive occurrence values are only
        // deep-copied after the complete stream proves both limits.
        try validateStoredFilingBusinessKeyRow(workspace.raw);
        const exact_schema_digest = try readDigest(workspace.raw, 5);
        if (!exact_schema_digest.eql(&draft_identity.exact_schema_digest)) {
            return Error.SqliteFailure;
        }
        const preflight = try self.preflightExactDraftHistory(
            draft_identity,
        );
        var filing_key = try readOwnedFilingBusinessKey(
            allocator,
            workspace.raw,
        );
        errdefer filing_key.deinit(allocator);
        const revisions = try self.loadExactDraftRevisions(
            allocator,
            draft_identity,
            null,
        );
        errdefer {
            for (revisions) |*revision| revision.deinit(allocator);
            allocator.free(revisions);
        }
        if (revisions.len != preflight.revision_count) {
            return Error.SqliteFailure;
        }
        return .{
            .draft_identity = draft_identity,
            .filing_key = filing_key,
            .revisions = revisions,
        };
    }

    pub fn getExactDraftRevision(
        self: *Store,
        plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
        allocator: std.mem.Allocator,
        draft_identity: ExactDraftIdentity,
        revision: DraftRevision,
    ) !?OwnedExactDraftRevision {
        try key_custody.requireSyntheticPlaintextForTest(
            plaintext_capability,
        );
        try validateDraftWorkspaceId(draft_identity.workspace_id);
        if (revision.value == 0) return Error.InvalidValue;
        const revisions = try self.loadExactDraftRevisions(
            allocator,
            draft_identity,
            revision,
        );
        if (revisions.len == 0) {
            allocator.free(revisions);
            return null;
        }
        std.debug.assert(revisions.len == 1);
        const result = revisions[0];
        allocator.free(revisions);
        return result;
    }

    /// Returns every other random workspace with the same canonical filing
    /// business key. Same-key workspaces are valid alternates, not a uniqueness
    /// violation; this API makes the duplicate condition explicit to callers.
    pub fn listExactDraftAlternates(
        self: *Store,
        plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
        allocator: std.mem.Allocator,
        filing_key: CanonicalFilingBusinessKeyWrite,
        excluding_workspace_id: ?DraftWorkspaceId,
    ) !ExactDraftAlternateList {
        try key_custody.requireSyntheticPlaintextForTest(
            plaintext_capability,
        );
        try validateCanonicalFilingBusinessKey(filing_key);
        if (excluding_workspace_id) |workspace_id| {
            try validateDraftWorkspaceId(workspace_id);
        }
        const digest = filing_key.canonicalDigest();
        var statement = try self.prepare(
            \\SELECT w.workspace_id,
            \\       COUNT(*) AS schema_stream_count,
            \\       MIN(w.created_at)
            \\FROM tax_exact_draft_streams AS w
            \\WHERE w.filing_business_key_digest = ?
            \\  AND w.filer_profile_id = ?
            \\  AND w.form_code = ?
            \\  AND w.form_revision = ?
            \\  AND w.period_key = ?
            \\  AND w.filing_intent = ?
            \\  AND (? IS NULL OR w.workspace_id <> ?)
            \\GROUP BY w.workspace_id
            \\ORDER BY MIN(w.created_at), w.workspace_id
            \\LIMIT ?;
        );
        defer statement.deinit();
        try statement.bindBlob(1, digest.asBytes());
        try statement.bindText(2, filing_key.filer_profile_id);
        try statement.bindText(3, filing_key.form_code);
        try statement.bindText(4, filing_key.form_revision);
        try statement.bindText(5, filing_key.period_key);
        try statement.bindText(6, filing_key.intent.text());
        try statement.bindOptionalWorkspaceId(7, &excluding_workspace_id);
        try statement.bindOptionalWorkspaceId(8, &excluding_workspace_id);
        try statement.bindInt64(
            9,
            @intCast(max_returned_exact_draft_alternates + 1),
        );

        var items: std.ArrayList(ExactDraftAlternate) = .empty;
        errdefer items.deinit(allocator);
        while (try statement.step() == .row) {
            if (items.items.len ==
                max_returned_exact_draft_alternates)
            {
                return Error.DraftAlternateLimitExceeded;
            }
            const workspace_id = try readDraftWorkspaceId(statement.raw, 0);
            const stream_count_raw = sqlite.sqlite3_column_int64(
                statement.raw,
                1,
            );
            if (stream_count_raw <= 0 or
                stream_count_raw > std.math.maxInt(u32))
            {
                return Error.SqliteFailure;
            }
            try items.append(allocator, .{
                .workspace_id = workspace_id,
                .schema_stream_count = @intCast(stream_count_raw),
                .created_at_unix_seconds = sqlite.sqlite3_column_int64(statement.raw, 2),
            });
        }
        return .{ .items = try items.toOwnedSlice(allocator) };
    }

    fn exactWorkspaceMatchesFilingKey(
        self: *Store,
        workspace_id: DraftWorkspaceId,
        filing_key: CanonicalFilingBusinessKeyWrite,
    ) !bool {
        const expected_digest = filing_key.canonicalDigest();
        var statement = try self.prepare(
            \\SELECT filing_business_key_digest, filer_profile_id,
            \\       form_code, form_revision, period_key, filing_intent
            \\FROM tax_exact_draft_streams
            \\WHERE workspace_id = ?
            \\ORDER BY exact_schema_digest
            \\LIMIT 3;
        );
        defer statement.deinit();
        try statement.bindBlob(1, &workspace_id.bytes);
        var stream_count: usize = 0;
        while (try statement.step() == .row) {
            if (stream_count == 2) return Error.SqliteFailure;
            const stored_digest = try readDigest(statement.raw, 0);
            const stored_intent = parseFilingIntent(
                try textColumnCapped(statement.raw, 5, 16),
            ) orelse return Error.SqliteFailure;
            if (!stored_digest.eql(&expected_digest) or
                !columnTextEql(
                    statement.raw,
                    1,
                    filing_key.filer_profile_id,
                ) or
                !columnTextEql(statement.raw, 2, filing_key.form_code) or
                !columnTextEql(
                    statement.raw,
                    3,
                    filing_key.form_revision,
                ) or
                !columnTextEql(statement.raw, 4, filing_key.period_key) or
                stored_intent != filing_key.intent)
            {
                return Error.DraftSchemaMismatch;
            }
            stream_count += 1;
        }
        return stream_count != 0;
    }

    fn ensureExactWorkspaceCapacity(
        self: *Store,
        filing_key: CanonicalFilingBusinessKeyWrite,
    ) !void {
        const digest = filing_key.canonicalDigest();
        var statement = try self.prepare(
            \\SELECT COUNT(DISTINCT workspace_id)
            \\FROM tax_exact_draft_streams
            \\WHERE filing_business_key_digest = ?
            \\  AND filer_profile_id = ?
            \\  AND form_code = ?
            \\  AND form_revision = ?
            \\  AND period_key = ?
            \\  AND filing_intent = ?;
        );
        defer statement.deinit();
        try statement.bindBlob(1, digest.asBytes());
        try statement.bindText(2, filing_key.filer_profile_id);
        try statement.bindText(3, filing_key.form_code);
        try statement.bindText(4, filing_key.form_revision);
        try statement.bindText(5, filing_key.period_key);
        try statement.bindText(6, filing_key.intent.text());
        if (try statement.step() != .row or
            sqlite.sqlite3_column_type(statement.raw, 0) !=
                sqlite.SQLITE_INTEGER)
        {
            return Error.SqliteFailure;
        }
        const count = sqlite.sqlite3_column_int64(statement.raw, 0);
        if (count < 0) return Error.SqliteFailure;
        if (count >= max_exact_workspaces_per_filing_business_key) {
            return Error.DraftWorkspaceLimitExceeded;
        }
    }

    fn preflightExactDraftHistory(
        self: *Store,
        draft_identity: ExactDraftIdentity,
    ) !ExactDraftHistoryPreflight {
        var revisions = try self.prepare(
            \\SELECT revision, payload_shape, occurrence_count,
            \\       validation_current_year, spouse_tin_checksum
            \\FROM tax_exact_draft_revisions
            \\WHERE workspace_id = ? AND exact_schema_digest = ?
            \\ORDER BY revision
            \\LIMIT ?;
        );
        defer revisions.deinit();
        try revisions.bindBlob(1, &draft_identity.workspace_id.bytes);
        try revisions.bindBlob(
            2,
            draft_identity.exact_schema_digest.asBytes(),
        );
        try revisions.bindInt64(
            3,
            @intCast(
                exact_draft.max_revisions_per_exact_shape_stream + 1,
            ),
        );

        var revision_count: usize = 0;
        var shape: ?exact_draft.PayloadShape = null;
        var manifest: ?exact_occurrence.OrderedOccurrenceManifest = null;
        while (try revisions.step() == .row) {
            if (revision_count ==
                exact_draft.max_revisions_per_exact_shape_stream)
            {
                return Error.DraftRevisionLimitExceeded;
            }
            if (sqlite.sqlite3_column_type(revisions.raw, 0) !=
                sqlite.SQLITE_INTEGER or
                sqlite.sqlite3_column_type(revisions.raw, 2) !=
                    sqlite.SQLITE_INTEGER)
            {
                return Error.SqliteFailure;
            }
            const revision_raw = sqlite.sqlite3_column_int64(
                revisions.raw,
                0,
            );
            if (revision_raw != @as(i64, @intCast(revision_count + 1))) {
                return Error.SqliteFailure;
            }
            const row_shape = parseEnumText(
                exact_draft.PayloadShape,
                try textColumnCapped(revisions.raw, 1, 32),
            ) orelse return Error.SqliteFailure;
            if (shape) |expected_shape| {
                if (row_shape != expected_shape) {
                    return Error.SqliteFailure;
                }
            } else {
                shape = row_shape;
                manifest = try exactManifestForShape(row_shape);
            }
            const occurrence_count = sqlite.sqlite3_column_int64(
                revisions.raw,
                2,
            );
            if (occurrence_count !=
                @as(i64, @intCast(manifest.?.items.len)))
            {
                return Error.SqliteFailure;
            }
            _ = try readExactValidationEvidence(revisions.raw, 3);
            revision_count += 1;
        }
        if (revision_count == 0) return Error.SqliteFailure;

        const expected_occurrence_rows = std.math.mul(
            usize,
            revision_count,
            manifest.?.items.len,
        ) catch return Error.SqliteFailure;
        var occurrences = try self.prepare(
            \\SELECT revision, ordinal, raw_value, normalized_value,
            \\       emitted_value
            \\FROM tax_exact_draft_occurrences
            \\WHERE workspace_id = ? AND exact_schema_digest = ?
            \\ORDER BY revision, ordinal
            \\LIMIT ?;
        );
        defer occurrences.deinit();
        try occurrences.bindBlob(
            1,
            &draft_identity.workspace_id.bytes,
        );
        try occurrences.bindBlob(
            2,
            draft_identity.exact_schema_digest.asBytes(),
        );
        try occurrences.bindInt64(
            3,
            @intCast(expected_occurrence_rows + 1),
        );

        var retained_value_bytes: usize = 0;
        for (0..revision_count) |revision_index| {
            for (manifest.?.items) |metadata| {
                if (try occurrences.step() != .row) {
                    return Error.SqliteFailure;
                }
                if (sqlite.sqlite3_column_type(occurrences.raw, 0) !=
                    sqlite.SQLITE_INTEGER or
                    sqlite.sqlite3_column_type(occurrences.raw, 1) !=
                        sqlite.SQLITE_INTEGER)
                {
                    return Error.SqliteFailure;
                }
                if (sqlite.sqlite3_column_int64(occurrences.raw, 0) !=
                    @as(i64, @intCast(revision_index + 1)) or
                    sqlite.sqlite3_column_int64(occurrences.raw, 1) !=
                        metadata.ordinal)
                {
                    return Error.SqliteFailure;
                }
                const raw_value = try blobColumnCapped(
                    occurrences.raw,
                    2,
                    exact_document.max_value_bytes,
                );
                const normalized_value = try blobColumnCapped(
                    occurrences.raw,
                    3,
                    exact_document.max_value_bytes,
                );
                const emitted_value = try blobColumnCapped(
                    occurrences.raw,
                    4,
                    exact_document.max_value_bytes,
                );
                retained_value_bytes = try addExactRetainedValueLength(
                    retained_value_bytes,
                    raw_value.len,
                );
                retained_value_bytes = try addExactRetainedValueLength(
                    retained_value_bytes,
                    normalized_value.len,
                );
                retained_value_bytes = try addExactRetainedValueLength(
                    retained_value_bytes,
                    emitted_value.len,
                );
            }
        }
        if (try occurrences.step() != .done) {
            return Error.SqliteFailure;
        }
        return .{
            .revision_count = revision_count,
            .retained_value_bytes = retained_value_bytes,
        };
    }

    fn exactWorkspaceCurrentRevision(
        self: *Store,
        workspace_id: DraftWorkspaceId,
        filing_key: CanonicalFilingBusinessKeyWrite,
        exact_schema_digest: exact_identity.Sha256Digest,
    ) !?u64 {
        var statement = try self.prepare(
            \\SELECT filing_business_key_digest, filer_profile_id, form_code,
            \\       form_revision, period_key, filing_intent,
            \\       exact_schema_digest,
            \\       (SELECT MAX(r.revision)
            \\        FROM tax_exact_draft_revisions AS r
            \\        WHERE r.workspace_id = w.workspace_id
            \\          AND r.exact_schema_digest = w.exact_schema_digest)
            \\FROM tax_exact_draft_streams AS w
            \\WHERE workspace_id = ? AND exact_schema_digest = ?;
        );
        defer statement.deinit();
        try statement.bindBlob(1, &workspace_id.bytes);
        try statement.bindBlob(2, exact_schema_digest.asBytes());
        if (try statement.step() == .done) return null;

        const expected_filing_digest = filing_key.canonicalDigest();
        const stored_filing_digest = try readDigest(statement.raw, 0);
        const stored_schema_digest = try readDigest(statement.raw, 6);
        const stored_intent_text = columnText(statement.raw, 5) orelse
            return Error.SqliteFailure;
        const stored_intent = parseFilingIntent(stored_intent_text) orelse
            return Error.SqliteFailure;
        if (!stored_filing_digest.eql(&expected_filing_digest) or
            !stored_schema_digest.eql(&exact_schema_digest) or
            stored_intent != filing_key.intent or
            !columnTextEql(statement.raw, 1, filing_key.filer_profile_id) or
            !columnTextEql(statement.raw, 2, filing_key.form_code) or
            !columnTextEql(statement.raw, 3, filing_key.form_revision) or
            !columnTextEql(statement.raw, 4, filing_key.period_key))
        {
            return Error.DraftSchemaMismatch;
        }

        if (sqlite.sqlite3_column_type(statement.raw, 7) ==
            sqlite.SQLITE_NULL)
        {
            return Error.SqliteFailure;
        }
        const revision_raw = sqlite.sqlite3_column_int64(statement.raw, 7);
        if (revision_raw <= 0) return Error.SqliteFailure;
        return @intCast(revision_raw);
    }

    fn loadExactDraftRevisions(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_identity: ExactDraftIdentity,
        only_revision: ?DraftRevision,
    ) ![]OwnedExactDraftRevision {
        var statement = try self.prepare(
            \\SELECT revision, parent_revision, profile_as_of,
            \\       recorded_at_unix_seconds, package_form_code,
            \\       package_form_revision, locale, offline_package_version,
            \\       payload_schema_token, offline_package_sha256,
            \\       primary_source_sha256, dependency_manifest_sha256,
            \\       official_pdf_sha256, official_guide_sha256,
            \\       codec_version, package_digest,
            \\       occurrence_manifest_digest, exact_schema_digest,
            \\       payload_shape, occurrence_count,
            \\       readiness_identity_resolved,
            \\       readiness_dependency_closure,
            \\       readiness_profile_mapping_reviewed,
            \\       readiness_calculation_reconciled,
            \\       readiness_validation_reconciled,
            \\       readiness_editable_serializer_exact,
            \\       readiness_final_plaintext_serializer_exact,
            \\       readiness_decrypt_codec_qualified,
            \\       readiness_encrypt_codec_qualified,
            \\       readiness_persistence_integrated,
            \\       readiness_ui_integrated,
            \\       readiness_offline_package_verified,
            \\       profile_snapshot_digest, transaction_state_digest,
            \\       ordered_values_digest, validation_current_year,
            \\       spouse_tin_checksum, save_gate_status, save_gate_rule,
            \\       full_validation_status, full_validation_code,
            \\       artifact_status, artifact_marker, artifact_byte_length,
            \\       artifact_sha256
            \\FROM tax_exact_draft_revisions
            \\WHERE workspace_id = ? AND exact_schema_digest = ?
            \\  AND (? IS NULL OR revision = ?)
            \\ORDER BY revision
            \\LIMIT ?;
        );
        defer statement.deinit();
        try statement.bindBlob(1, &draft_identity.workspace_id.bytes);
        try statement.bindBlob(
            2,
            draft_identity.exact_schema_digest.asBytes(),
        );
        const revision_value: ?i64 = if (only_revision) |revision|
            checkedU64ToI64(revision.value)
        else
            null;
        if (only_revision != null and revision_value == null) {
            return Error.InvalidValue;
        }
        try statement.bindOptionalInt64(3, revision_value);
        try statement.bindOptionalInt64(4, revision_value);
        try statement.bindInt64(
            5,
            if (only_revision == null)
                @intCast(
                    exact_draft.max_revisions_per_exact_shape_stream + 1,
                )
            else
                2,
        );

        var items: std.ArrayList(OwnedExactDraftRevision) = .empty;
        var retained_value_bytes: usize = 0;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            if (only_revision == null and
                items.items.len ==
                    exact_draft.max_revisions_per_exact_shape_stream)
            {
                return Error.DraftRevisionLimitExceeded;
            }
            if (only_revision != null and items.items.len == 1) {
                return Error.SqliteFailure;
            }
            const revision_raw = sqlite.sqlite3_column_int64(
                statement.raw,
                0,
            );
            if (revision_raw <= 0) return Error.SqliteFailure;
            const revision = DraftRevision.init(@intCast(revision_raw)) catch
                return Error.SqliteFailure;
            const schema = try readExactDraftSchemaBinding(statement.raw);
            try validateExactSchemaBinding(schema);
            if (!schema.exact_schema_digest.eql(
                &draft_identity.exact_schema_digest,
            )) {
                return Error.SqliteFailure;
            }
            const manifest = try exactManifestForShape(schema.payload_shape);
            const bindings = try self.loadExactDraftBindings(
                allocator,
                draft_identity,
                revision,
            );
            var bindings_owned = true;
            errdefer {
                if (bindings_owned) {
                    for (bindings) |*binding| binding.deinit(allocator);
                    allocator.free(bindings);
                }
            }
            const occurrences = try self.loadExactDraftOccurrences(
                allocator,
                draft_identity,
                revision,
                manifest,
                &retained_value_bytes,
            );
            var occurrences_owned = true;
            errdefer {
                if (occurrences_owned) {
                    for (occurrences) |*occurrence_value| {
                        occurrence_value.deinit(allocator);
                    }
                    allocator.free(occurrences);
                }
            }
            var item = try readExactDraftRevision(
                allocator,
                statement.raw,
                schema,
                bindings,
                occurrences,
            );
            bindings_owned = false;
            occurrences_owned = false;
            errdefer item.deinit(allocator);
            try validateOwnedExactDraftRevisionIntegrity(&item);
            try items.append(allocator, item);
        }
        return items.toOwnedSlice(allocator);
    }

    fn loadExactDraftBindings(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_identity: ExactDraftIdentity,
        revision: DraftRevision,
    ) ![]OwnedExactDraftRoleBinding {
        var statement = try self.prepare(
            \\SELECT role, instance_id, profile_id, profile_revision_id,
            \\       profile_revision_sequence, business_activity_id,
            \\       provenance
            \\FROM tax_exact_draft_revision_bindings
            \\WHERE workspace_id = ? AND exact_schema_digest = ?
            \\  AND revision = ?
            \\ORDER BY role COLLATE BINARY, instance_id COLLATE BINARY;
        );
        defer statement.deinit();
        try statement.bindBlob(1, &draft_identity.workspace_id.bytes);
        try statement.bindBlob(
            2,
            draft_identity.exact_schema_digest.asBytes(),
        );
        try statement.bindInt64(
            3,
            checkedU64ToI64(revision.value) orelse
                return Error.InvalidValue,
        );

        var items: std.ArrayList(OwnedExactDraftRoleBinding) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            if (items.items.len == max_exact_role_bindings) {
                return Error.SqliteFailure;
            }
            const role_text = try textColumnCapped(statement.raw, 0, 64);
            const instance_id_text = try textColumnCapped(
                statement.raw,
                1,
                64,
            );
            const profile_id_text = try textColumnCapped(statement.raw, 2, 64);
            const profile_revision_id_text = try textColumnCapped(
                statement.raw,
                3,
                64,
            );
            const business_activity_id_text = try optionalTextColumnCapped(
                statement.raw,
                5,
                64,
            );
            const provenance_text = try textColumnCapped(
                statement.raw,
                6,
                max_exact_provenance_bytes,
            );
            if ((!std.mem.eql(u8, role_text, "filer") and
                !std.mem.eql(u8, role_text, "spouse")))
            {
                return Error.SqliteFailure;
            }
            validateIdText(instance_id_text) catch
                return Error.SqliteFailure;
            validateIdText(profile_id_text) catch
                return Error.SqliteFailure;
            validateIdText(profile_revision_id_text) catch
                return Error.SqliteFailure;
            if (business_activity_id_text) |activity_id| {
                validateIdText(activity_id) catch
                    return Error.SqliteFailure;
            }
            validateExactProvenance(provenance_text) catch
                return Error.SqliteFailure;
            const sequence_raw = sqlite.sqlite3_column_int64(
                statement.raw,
                4,
            );
            if (sequence_raw <= 0 or
                sequence_raw > std.math.maxInt(u32))
            {
                return Error.SqliteFailure;
            }

            const role = try allocator.dupe(u8, role_text);
            errdefer allocator.free(role);
            const instance_id = try allocator.dupe(u8, instance_id_text);
            errdefer allocator.free(instance_id);
            const profile_id = try allocator.dupe(u8, profile_id_text);
            errdefer allocator.free(profile_id);
            const profile_revision_id = try allocator.dupe(
                u8,
                profile_revision_id_text,
            );
            errdefer allocator.free(profile_revision_id);
            const business_activity_id: ?[]u8 =
                if (business_activity_id_text) |activity_id|
                    try allocator.dupe(u8, activity_id)
                else
                    null;
            errdefer freeOptional(allocator, business_activity_id);
            const provenance = try allocator.dupe(u8, provenance_text);
            errdefer allocator.free(provenance);
            try items.append(allocator, .{
                .role = role,
                .instance_id = instance_id,
                .profile_id = profile_id,
                .profile_revision_id = profile_revision_id,
                .profile_revision_sequence = @intCast(sequence_raw),
                .business_activity_id = business_activity_id,
                .provenance = provenance,
            });
        }
        var filer_count: usize = 0;
        var spouse_count: usize = 0;
        for (items.items) |binding| {
            if (std.mem.eql(u8, binding.role, "filer")) {
                filer_count += 1;
            } else if (std.mem.eql(u8, binding.role, "spouse")) {
                spouse_count += 1;
            } else {
                return Error.SqliteFailure;
            }
        }
        if (filer_count != 1 or spouse_count > 1) {
            return Error.SqliteFailure;
        }
        return items.toOwnedSlice(allocator);
    }

    fn loadExactDraftOccurrences(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_identity: ExactDraftIdentity,
        revision: DraftRevision,
        manifest: exact_occurrence.OrderedOccurrenceManifest,
        retained_value_bytes: *usize,
    ) ![]OwnedExactDraftOccurrence {
        var statement = try self.prepare(
            \\SELECT ordinal, serialized_key, same_key_occurrence,
            \\       raw_value, normalized_value, emitted_value, origin,
            \\       provenance
            \\FROM tax_exact_draft_occurrences
            \\WHERE workspace_id = ? AND exact_schema_digest = ?
            \\  AND revision = ?
            \\ORDER BY ordinal;
        );
        defer statement.deinit();
        try statement.bindBlob(1, &draft_identity.workspace_id.bytes);
        try statement.bindBlob(
            2,
            draft_identity.exact_schema_digest.asBytes(),
        );
        try statement.bindInt64(
            3,
            checkedU64ToI64(revision.value) orelse
                return Error.InvalidValue,
        );

        // Validate the entire persisted shape and all byte caps before the
        // first value-bearing allocation. This protects existing v4 databases
        // whose original table definition did not include the fresh-schema
        // CHECK constraints below.
        const revision_value_bytes = try validateExactOccurrenceRows(
            &statement,
            manifest,
        );
        const next_retained_value_bytes = try addExactRetainedValueLength(
            retained_value_bytes.*,
            revision_value_bytes,
        );
        try statement.reset();
        try statement.bindBlob(1, &draft_identity.workspace_id.bytes);
        try statement.bindBlob(
            2,
            draft_identity.exact_schema_digest.asBytes(),
        );
        try statement.bindInt64(
            3,
            checkedU64ToI64(revision.value) orelse
                return Error.InvalidValue,
        );

        const items = try allocator.alloc(
            OwnedExactDraftOccurrence,
            manifest.items.len,
        );
        var initialized: usize = 0;
        errdefer {
            for (items[0..initialized]) |*item| item.deinit(allocator);
            allocator.free(items);
        }
        for (manifest.items) |metadata| {
            if (try statement.step() != .row) {
                return Error.SqliteFailure;
            }
            items[initialized] = try readOwnedExactOccurrence(
                allocator,
                statement.raw,
                metadata,
            );
            initialized += 1;
        }
        if (try statement.step() != .done) return Error.SqliteFailure;
        retained_value_bytes.* = next_retained_value_bytes;
        return items;
    }

    fn loadBindings(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_id: []const u8,
    ) ![]OwnedRoleBinding {
        var statement = try self.prepare(
            \\SELECT role, profile_id, profile_revision_id,
            \\       profile_revision_sequence, business_activity_id
            \\FROM tax_form_draft_role_bindings
            \\WHERE draft_id = ?
            \\ORDER BY role COLLATE BINARY;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        var items: std.ArrayList(OwnedRoleBinding) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const role = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(role);
            const profile_id = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(profile_id);
            const profile_revision_id = try dupColumn(
                allocator,
                statement.raw,
                2,
            );
            errdefer allocator.free(profile_revision_id);
            const sequence_raw = sqlite.sqlite3_column_int64(statement.raw, 3);
            if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
                return Error.SqliteFailure;
            }
            const business_activity_id = try dupOptionalColumn(
                allocator,
                statement.raw,
                4,
            );
            errdefer freeOptional(allocator, business_activity_id);
            try items.append(allocator, .{
                .role = role,
                .profile_id = profile_id,
                .profile_revision_id = profile_revision_id,
                .profile_revision_sequence = @intCast(sequence_raw),
                .business_activity_id = business_activity_id,
            });
        }
        return items.toOwnedSlice(allocator);
    }

    fn loadSnapshots(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_id: []const u8,
    ) ![]OwnedSnapshotField {
        var statement = try self.prepare(
            \\SELECT role, field_id, reusable_field, value_type, value_text,
            \\       provenance, profile_revision_id,
            \\       profile_revision_sequence, revision_source_tag,
            \\       revision_source_reference, business_activity_id,
            \\       registration_fact_id, overridden
            \\FROM tax_form_draft_snapshot_fields
            \\WHERE draft_id = ?
            \\ORDER BY field_id COLLATE BINARY;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        var items: std.ArrayList(OwnedSnapshotField) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const role = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(role);
            const field_id = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(field_id);
            const reusable_field = try dupColumn(allocator, statement.raw, 2);
            errdefer allocator.free(reusable_field);
            const value_type = try dupColumn(allocator, statement.raw, 3);
            errdefer allocator.free(value_type);
            const value_text = try dupColumn(allocator, statement.raw, 4);
            errdefer allocator.free(value_text);
            const provenance = try dupColumn(allocator, statement.raw, 5);
            errdefer allocator.free(provenance);
            const profile_revision_id = try dupColumn(
                allocator,
                statement.raw,
                6,
            );
            errdefer allocator.free(profile_revision_id);
            const sequence_raw = sqlite.sqlite3_column_int64(statement.raw, 7);
            if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
                return Error.SqliteFailure;
            }
            var revision_source = try readRevisionSource(
                allocator,
                statement.raw,
                8,
                9,
            );
            errdefer revision_source.deinit(allocator);
            const business_activity_id = try dupOptionalColumn(
                allocator,
                statement.raw,
                10,
            );
            errdefer freeOptional(allocator, business_activity_id);
            const registration_fact_id = try dupOptionalColumn(
                allocator,
                statement.raw,
                11,
            );
            errdefer freeOptional(allocator, registration_fact_id);
            try items.append(allocator, .{
                .role = role,
                .field_id = field_id,
                .reusable_field = reusable_field,
                .value_type = value_type,
                .value_text = value_text,
                .provenance = provenance,
                .profile_revision_id = profile_revision_id,
                .profile_revision_sequence = @intCast(sequence_raw),
                .revision_source = revision_source,
                .business_activity_id = business_activity_id,
                .registration_fact_id = registration_fact_id,
                .overridden = sqlite.sqlite3_column_int(statement.raw, 12) != 0,
            });
        }
        return items.toOwnedSlice(allocator);
    }

    fn loadDraftValues(
        self: *Store,
        allocator: std.mem.Allocator,
        draft_id: []const u8,
    ) ![]OwnedDraftValue {
        var statement = try self.prepare(
            \\SELECT field_id, value_text, provenance
            \\FROM tax_form_draft_values
            \\WHERE draft_id = ?
            \\ORDER BY field_id COLLATE BINARY;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        var items: std.ArrayList(OwnedDraftValue) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const field_id = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(field_id);
            const value_text = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(value_text);
            const provenance = try dupColumn(allocator, statement.raw, 2);
            errdefer allocator.free(provenance);
            try items.append(allocator, .{
                .field_id = field_id,
                .value_text = value_text,
                .provenance = provenance,
            });
        }
        return items.toOwnedSlice(allocator);
    }

    fn draftAcceptsEdits(self: *Store, draft_id: []const u8) !bool {
        var statement = try self.prepare(
            \\SELECT lifecycle FROM tax_form_drafts WHERE id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        if (try statement.step() == .done) return Error.NotFound;
        const lifecycle = columnText(statement.raw, 0) orelse
            return Error.SqliteFailure;
        return std.mem.eql(u8, lifecycle, "editing");
    }

    fn draftExists(self: *Store, draft_id: []const u8) !bool {
        var statement = try self.prepare(
            "SELECT 1 FROM tax_form_drafts WHERE id = ?;",
        );
        defer statement.deinit();
        try statement.bindText(1, draft_id);
        return try statement.step() == .row;
    }

    fn validateOrdinaryIdentity(
        self: *Store,
        value: RevisionWrite,
        observed_revision_sequence: u32,
    ) !void {
        const maybe_anchor = try self.currentAnchorSnapshot(value.profile_id);
        if (maybe_anchor == null) {
            // A revision-less legacy/profile shell establishes its anchor
            // from revision 1 through the schema's AFTER INSERT trigger.
            if (observed_revision_sequence == 0 and value.sequence == 1) {
                return;
            }
            return Error.MissingIdentityAnchor;
        }
        const anchor = maybe_anchor.?;
        const incoming_tin = profile_field.Tin.parse(
            value.identity.tin,
        ) catch return Error.InvalidValue;
        if (!std.mem.eql(
            u8,
            anchor.canonicalTin(),
            incoming_tin.asDigits(),
        )) return Error.CanonicalTaxpayerIdentifierChanged;
        if (anchor.legal_person_class !=
            legalPersonClassForSubjectKind(value.subject.kind()))
        {
            return Error.LegalPersonClassChanged;
        }
    }

    fn currentAnchorSnapshot(
        self: *Store,
        profile_id: []const u8,
    ) !?AnchorSnapshot {
        var statement = try self.prepare(
            \\SELECT sequence, canonical_tin, legal_person_class
            \\FROM tax_profile_identity_anchors
            \\WHERE profile_id = ?
            \\ORDER BY sequence DESC
            \\LIMIT 1;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        if (try statement.step() == .done) return null;

        const sequence_raw = sqlite.sqlite3_column_int64(statement.raw, 0);
        if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
            return Error.SqliteFailure;
        }
        const tin = columnText(statement.raw, 1) orelse
            return Error.SqliteFailure;
        if (tin.len == 0 or tin.len > 14) return Error.SqliteFailure;
        const class_text = columnText(statement.raw, 2) orelse
            return Error.SqliteFailure;
        const class = parseLegalPersonClass(class_text) orelse
            return Error.SqliteFailure;

        var result: AnchorSnapshot = .{
            .sequence = @intCast(sequence_raw),
            .legal_person_class = class,
        };
        @memcpy(result.canonical_tin[0..tin.len], tin);
        result.canonical_tin_len = @intCast(tin.len);
        return result;
    }

    fn currentCivilStatusSequence(
        self: *Store,
        profile_id: []const u8,
    ) !u32 {
        var statement = try self.prepare(
            \\SELECT COALESCE(MAX(sequence), 0)
            \\FROM tax_profile_civil_status_revisions
            \\WHERE profile_id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        if (try statement.step() != .row) return Error.SqliteFailure;
        const sequence = sqlite.sqlite3_column_int64(statement.raw, 0);
        if (sequence < 0 or sequence > std.math.maxInt(u32)) {
            return Error.SqliteFailure;
        }
        return @intCast(sequence);
    }

    fn currentRevisionSequence(
        self: *Store,
        profile_id: []const u8,
    ) !?u32 {
        var statement = try self.prepare(
            \\SELECT r.sequence
            \\FROM tax_profiles AS p
            \\JOIN tax_profile_revisions AS r
            \\  ON r.profile_id = p.id AND r.id = p.current_revision_id
            \\WHERE p.id = ?;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        return switch (try statement.step()) {
            .done => null,
            .row => blk: {
                const sequence = sqlite.sqlite3_column_int64(statement.raw, 0);
                if (sequence <= 0 or sequence > std.math.maxInt(u32)) {
                    return Error.SqliteFailure;
                }
                break :blk @intCast(sequence);
            },
        };
    }

    fn profileExists(self: *Store, profile_id: []const u8) !bool {
        var statement = try self.prepare(
            "SELECT 1 FROM tax_profiles WHERE id = ?;",
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        return try statement.step() == .row;
    }

    fn readRevision(
        self: *Store,
        allocator: std.mem.Allocator,
        row: *sqlite.sqlite3_stmt,
    ) !OwnedProfileRevision {
        const id = try dupColumn(allocator, row, 0);
        errdefer allocator.free(id);
        const sequence_raw = sqlite.sqlite3_column_int64(row, 1);
        if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
            return Error.SqliteFailure;
        }
        const profile_id = try dupColumn(allocator, row, 2);
        errdefer allocator.free(profile_id);
        const effective_from = try dupColumn(allocator, row, 3);
        errdefer allocator.free(effective_from);
        const effective_until = try dupOptionalColumn(allocator, row, 4);
        errdefer freeOptional(allocator, effective_until);
        var source = try readRevisionSource(allocator, row, 5, 6);
        errdefer source.deinit(allocator);
        const tin = try dupColumn(allocator, row, 7);
        errdefer allocator.free(tin);
        const rdo_code = try dupColumn(allocator, row, 8);
        errdefer allocator.free(rdo_code);
        const registered_address = try dupColumn(allocator, row, 9);
        errdefer allocator.free(registered_address);
        const zip_code = try dupOptionalColumn(allocator, row, 10);
        errdefer freeOptional(allocator, zip_code);
        const contact_number = try dupOptionalColumn(allocator, row, 11);
        errdefer freeOptional(allocator, contact_number);
        const email_address = try dupOptionalColumn(allocator, row, 12);
        errdefer freeOptional(allocator, email_address);
        var subject = try readSubject(allocator, row, 13);
        errdefer subject.deinit(allocator);
        const activities = try self.loadBusinessActivities(
            allocator,
            profile_id,
            id,
        );
        errdefer {
            for (activities) |*activity| activity.deinit(allocator);
            allocator.free(activities);
        }
        const facts = try self.loadRegistrationFacts(
            allocator,
            profile_id,
            id,
        );
        errdefer {
            for (facts) |*fact| fact.deinit(allocator);
            allocator.free(facts);
        }

        return .{
            .id = id,
            .sequence = @intCast(sequence_raw),
            .profile_id = profile_id,
            .effective_from = effective_from,
            .effective_until = effective_until,
            .source = source,
            .tin = tin,
            .rdo_code = rdo_code,
            .contact = .{
                .registered_address = registered_address,
                .zip_code = zip_code,
                .contact_number = contact_number,
                .email_address = email_address,
            },
            .subject = subject,
            .business_activities = activities,
            .registration_facts = facts,
        };
    }

    fn loadBusinessActivities(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        revision_id: []const u8,
    ) ![]OwnedBusinessActivity {
        var statement = try self.prepare(
            \\SELECT id, line_of_business, atc, effective_from,
            \\       effective_until, ordinal
            \\FROM tax_profile_business_activities
            \\WHERE profile_id = ? AND revision_id = ?
            \\ORDER BY ordinal, id;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindText(2, revision_id);

        var items: std.ArrayList(OwnedBusinessActivity) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const id = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(id);
            const line_of_business = try dupColumn(allocator, statement.raw, 1);
            errdefer allocator.free(line_of_business);
            const atc = try dupOptionalColumn(allocator, statement.raw, 2);
            errdefer freeOptional(allocator, atc);
            const effective_from = try dupColumn(allocator, statement.raw, 3);
            errdefer allocator.free(effective_from);
            const effective_until = try dupOptionalColumn(
                allocator,
                statement.raw,
                4,
            );
            errdefer freeOptional(allocator, effective_until);
            const ordinal_raw = sqlite.sqlite3_column_int64(statement.raw, 5);
            if (ordinal_raw < 0 or ordinal_raw > std.math.maxInt(u32)) {
                return Error.SqliteFailure;
            }
            try items.append(allocator, .{
                .id = id,
                .line_of_business = line_of_business,
                .atc = atc,
                .effective_from = effective_from,
                .effective_until = effective_until,
                .ordinal = @intCast(ordinal_raw),
            });
        }
        return items.toOwnedSlice(allocator);
    }

    fn loadRegistrationFacts(
        self: *Store,
        allocator: std.mem.Allocator,
        profile_id: []const u8,
        revision_id: []const u8,
    ) ![]OwnedRegistrationFact {
        var statement = try self.prepare(
            \\SELECT id, kind, value_text, effective_from,
            \\       effective_until, ordinal
            \\FROM tax_profile_registration_facts
            \\WHERE profile_id = ? AND revision_id = ?
            \\ORDER BY ordinal, id;
        );
        defer statement.deinit();
        try statement.bindText(1, profile_id);
        try statement.bindText(2, revision_id);

        var items: std.ArrayList(OwnedRegistrationFact) = .empty;
        errdefer {
            for (items.items) |*item| item.deinit(allocator);
            items.deinit(allocator);
        }
        while (try statement.step() == .row) {
            const id = try dupColumn(allocator, statement.raw, 0);
            errdefer allocator.free(id);
            var value = try readRegistrationFactValue(
                allocator,
                statement.raw,
                1,
                2,
            );
            errdefer value.deinit(allocator);
            const effective_from = try dupColumn(allocator, statement.raw, 3);
            errdefer allocator.free(effective_from);
            const effective_until = try dupOptionalColumn(
                allocator,
                statement.raw,
                4,
            );
            errdefer freeOptional(allocator, effective_until);
            const ordinal_raw = sqlite.sqlite3_column_int64(statement.raw, 5);
            if (ordinal_raw < 0 or ordinal_raw > std.math.maxInt(u32)) {
                return Error.SqliteFailure;
            }
            try items.append(allocator, .{
                .id = id,
                .effective_from = effective_from,
                .effective_until = effective_until,
                .value = value,
                .ordinal = @intCast(ordinal_raw),
            });
        }
        return items.toOwnedSlice(allocator);
    }

    fn beginImmediate(self: *Store) !void {
        try self.exec("BEGIN IMMEDIATE;");
    }

    fn commit(self: *Store) !void {
        try self.exec("COMMIT;");
    }

    fn rollbackNoFail(self: *Store) void {
        self.exec("ROLLBACK;") catch {};
    }

    fn exec(self: *Store, sql_text: [*:0]const u8) !void {
        const db = try self.handle();
        const rc = sqlite.sqlite3_exec(db, sql_text, null, null, null);
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn prepare(self: *Store, sql_text: []const u8) !Statement {
        const db = try self.handle();
        var raw: ?*sqlite.sqlite3_stmt = null;
        const rc = sqlite.sqlite3_prepare_v2(
            db,
            sql_text.ptr,
            @intCast(sql_text.len),
            &raw,
            null,
        );
        if (rc != sqlite.SQLITE_OK or raw == null) return mapResult(rc);
        return .{ .db = db, .raw = raw.? };
    }

    fn handle(self: *Store) Error!*sqlite.sqlite3 {
        return self.db orelse Error.Closed;
    }
};

const StepResult = enum { row, done };

const Statement = struct {
    db: *sqlite.sqlite3,
    raw: *sqlite.sqlite3_stmt,

    fn deinit(self: *Statement) void {
        _ = sqlite.sqlite3_finalize(self.raw);
        self.* = undefined;
    }

    fn bindText(self: *Statement, index: c_int, value: []const u8) !void {
        const rc = sqlite.sqlite3_bind_text(
            self.raw,
            index,
            value.ptr,
            @intCast(value.len),
            null,
        );
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn bindBlob(self: *Statement, index: c_int, value: []const u8) !void {
        if (value.len == 0) {
            const empty_rc = sqlite.sqlite3_bind_zeroblob(
                self.raw,
                index,
                0,
            );
            if (empty_rc != sqlite.SQLITE_OK) return mapResult(empty_rc);
            return;
        }
        const rc = sqlite.sqlite3_bind_blob(
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
    ) !void {
        if (value) |text| return self.bindText(index, text);
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }

    fn bindOptionalDigest(
        self: *Statement,
        index: c_int,
        value: *const ?exact_identity.Sha256Digest,
    ) !void {
        // sqlite3_bind_blob uses SQLITE_STATIC above. Borrow the optional
        // payload in caller-owned storage instead of copying its fixed-size
        // bytes into this helper's stack frame before sqlite3_step().
        if (value.*) |*digest| return self.bindBlob(index, digest.asBytes());
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }

    fn bindOptionalWorkspaceId(
        self: *Statement,
        index: c_int,
        value: *const ?DraftWorkspaceId,
    ) !void {
        if (value.*) |*workspace_id| {
            return self.bindBlob(index, &workspace_id.bytes);
        }
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }

    fn bindDate(self: *Statement, index: c_int, value: []const u8) !void {
        try self.bindText(index, value);
    }

    fn bindOptionalDate(
        self: *Statement,
        index: c_int,
        value: ?[]const u8,
    ) !void {
        if (value) |date| return self.bindDate(index, date);
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }

    fn bindInt64(self: *Statement, index: c_int, value: i64) !void {
        const rc = sqlite.sqlite3_bind_int64(self.raw, index, value);
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn bindOptionalInt64(
        self: *Statement,
        index: c_int,
        value: ?i64,
    ) !void {
        if (value) |number| return self.bindInt64(index, number);
        if (sqlite.sqlite3_bind_null(self.raw, index) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }

    fn bindBool(self: *Statement, index: c_int, value: bool) !void {
        const rc = sqlite.sqlite3_bind_int(
            self.raw,
            index,
            @intFromBool(value),
        );
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
    }

    fn step(self: *Statement) !StepResult {
        return switch (sqlite.sqlite3_step(self.raw)) {
            sqlite.SQLITE_ROW => .row,
            sqlite.SQLITE_DONE => .done,
            else => |rc| mapResult(rc),
        };
    }

    fn expectDone(self: *Statement) !void {
        if (try self.step() != .done) return Error.SqliteFailure;
    }

    fn reset(self: *Statement) !void {
        const rc = sqlite.sqlite3_reset(self.raw);
        if (rc != sqlite.SQLITE_OK) return mapResult(rc);
        if (sqlite.sqlite3_clear_bindings(self.raw) != sqlite.SQLITE_OK) {
            return Error.SqliteFailure;
        }
    }
};

fn validateExactOccurrenceRows(
    statement: *Statement,
    manifest: exact_occurrence.OrderedOccurrenceManifest,
) !usize {
    var total_value_bytes: usize = 0;
    for (manifest.items) |metadata| {
        if (try statement.step() != .row) return Error.SqliteFailure;
        const row_value_bytes = try validateExactOccurrenceRow(
            statement.raw,
            metadata,
        );
        total_value_bytes = addExactValueLength(
            total_value_bytes,
            row_value_bytes,
        ) orelse return Error.SqliteFailure;
    }
    if (try statement.step() != .done) return Error.SqliteFailure;
    return total_value_bytes;
}

fn validateExactOccurrenceRow(
    row: *sqlite.sqlite3_stmt,
    metadata: exact_occurrence.OccurrenceMetadata,
) !usize {
    if (sqlite.sqlite3_column_type(row, 0) != sqlite.SQLITE_INTEGER or
        sqlite.sqlite3_column_type(row, 2) != sqlite.SQLITE_INTEGER)
    {
        return Error.SqliteFailure;
    }
    const ordinal_raw = sqlite.sqlite3_column_int64(row, 0);
    const same_key_raw = sqlite.sqlite3_column_int64(row, 2);
    if (ordinal_raw != metadata.ordinal or
        same_key_raw != metadata.same_key_occurrence)
    {
        return Error.SqliteFailure;
    }

    const serialized_key = try blobColumnCapped(
        row,
        1,
        exact_document.max_key_bytes,
    );
    if (!std.mem.eql(u8, serialized_key, metadata.serialized_key)) {
        return Error.SqliteFailure;
    }
    const raw_value = try blobColumnCapped(
        row,
        3,
        exact_document.max_value_bytes,
    );
    const normalized_value = try blobColumnCapped(
        row,
        4,
        exact_document.max_value_bytes,
    );
    const emitted_value = try blobColumnCapped(
        row,
        5,
        exact_document.max_value_bytes,
    );
    if (!std.unicode.utf8ValidateSlice(raw_value) or
        !std.unicode.utf8ValidateSlice(normalized_value))
    {
        return Error.SqliteFailure;
    }
    validateExactEmittedValue(emitted_value) catch
        return Error.SqliteFailure;

    const origin_text = try textColumnCapped(row, 6, 32);
    const origin = parseExactDraftOrigin(origin_text) orelse
        return Error.SqliteFailure;
    const provenance = try textColumnCapped(
        row,
        7,
        max_exact_provenance_bytes,
    );
    validateExactOccurrenceProvenance(
        metadata,
        origin,
        provenance,
    ) catch
        return Error.SqliteFailure;

    var total: usize = 0;
    total = std.math.add(usize, total, raw_value.len) catch
        return Error.SqliteFailure;
    total = std.math.add(usize, total, normalized_value.len) catch
        return Error.SqliteFailure;
    return std.math.add(usize, total, emitted_value.len) catch
        return Error.SqliteFailure;
}

fn readOwnedExactOccurrence(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    metadata: exact_occurrence.OccurrenceMetadata,
) !OwnedExactDraftOccurrence {
    _ = try validateExactOccurrenceRow(row, metadata);
    const serialized_key = try dupBlobColumnCapped(
        allocator,
        row,
        1,
        exact_document.max_key_bytes,
    );
    errdefer allocator.free(serialized_key);
    const raw_value = try dupBlobColumnCapped(
        allocator,
        row,
        3,
        exact_document.max_value_bytes,
    );
    errdefer secureFreeOwned(allocator, raw_value);
    const normalized_value = try dupBlobColumnCapped(
        allocator,
        row,
        4,
        exact_document.max_value_bytes,
    );
    errdefer secureFreeOwned(allocator, normalized_value);
    const emitted_value = try dupBlobColumnCapped(
        allocator,
        row,
        5,
        exact_document.max_value_bytes,
    );
    errdefer secureFreeOwned(allocator, emitted_value);
    const provenance = try dupTextColumnCapped(
        allocator,
        row,
        7,
        max_exact_provenance_bytes,
    );
    errdefer allocator.free(provenance);
    const origin = expectedExactOccurrenceOrigin(metadata) catch
        return Error.SqliteFailure;
    return .{
        .ordinal = metadata.ordinal,
        .serialized_key = serialized_key,
        .same_key_occurrence = metadata.same_key_occurrence,
        .raw_value = raw_value,
        .normalized_value = normalized_value,
        .emitted_value = emitted_value,
        .origin = origin,
        .provenance = provenance,
    };
}

fn readOwnedFilingBusinessKey(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
) !OwnedCanonicalFilingBusinessKey {
    try validateStoredFilingBusinessKeyRow(row);
    const filer_profile_id_text = try textColumnCapped(row, 0, 64);
    const form_code_text = try textColumnCapped(row, 1, 16);
    const form_revision_text = try textColumnCapped(row, 2, 48);
    const period_key_text = try textColumnCapped(
        row,
        3,
        max_exact_period_key_bytes,
    );
    const intent_text = try textColumnCapped(row, 4, 16);
    const intent = parseFilingIntent(intent_text).?;

    const filer_profile_id = try allocator.dupe(u8, filer_profile_id_text);
    errdefer allocator.free(filer_profile_id);
    const form_code = try allocator.dupe(u8, form_code_text);
    errdefer allocator.free(form_code);
    const form_revision = try allocator.dupe(u8, form_revision_text);
    errdefer allocator.free(form_revision);
    const period_key = try allocator.dupe(u8, period_key_text);
    errdefer allocator.free(period_key);
    return .{
        .filer_profile_id = filer_profile_id,
        .form_code = form_code,
        .form_revision = form_revision,
        .period_key = period_key,
        .intent = intent,
    };
}

fn validateStoredFilingBusinessKeyRow(
    row: *sqlite.sqlite3_stmt,
) !void {
    const filer_profile_id = try textColumnCapped(row, 0, 64);
    const form_code = try textColumnCapped(row, 1, 16);
    const form_revision = try textColumnCapped(row, 2, 48);
    const period_key = try textColumnCapped(
        row,
        3,
        max_exact_period_key_bytes,
    );
    validateIdText(filer_profile_id) catch
        return Error.SqliteFailure;
    _ = form_ids.FormCode.parse(form_code) catch
        return Error.SqliteFailure;
    _ = form_ids.RevisionLabel.parse(form_revision) catch
        return Error.SqliteFailure;
    requireExactText(period_key) catch
        return Error.SqliteFailure;
    _ = parseFilingIntent(
        try textColumnCapped(row, 4, 16),
    ) orelse return Error.SqliteFailure;
}

fn readExactDraftSchemaBinding(
    row: *sqlite.sqlite3_stmt,
) !exact_draft.SchemaBinding {
    const form_code_text = try textColumnCapped(row, 4, 16);
    const form_revision_text = try textColumnCapped(row, 5, 48);
    const form_code = form_ids.FormCode.parse(form_code_text) catch
        return Error.SqliteFailure;
    const form_revision = form_ids.RevisionLabel.parse(
        form_revision_text,
    ) catch return Error.SqliteFailure;
    const locale = parseEnumText(
        exact_identity.Locale,
        try textColumnCapped(row, 6, 16),
    ) orelse return Error.SqliteFailure;
    const package_version = parseEnumText(
        exact_identity.OfflinePackageVersion,
        try textColumnCapped(row, 7, 32),
    ) orelse return Error.SqliteFailure;
    const payload_token = parseEnumText(
        exact_identity.PayloadSchemaToken,
        try textColumnCapped(row, 8, 32),
    ) orelse return Error.SqliteFailure;
    const offline_digest = try readDigest(row, 9);
    const primary_digest = try readDigest(row, 10);
    const dependency_digest = try readDigest(row, 11);
    const official_pdf_digest = try readOptionalDigest(row, 12);
    const official_guide_digest = try readOptionalDigest(row, 13);
    const codec_version: ?exact_identity.CodecVersion = if (sqlite.sqlite3_column_type(row, 14) == sqlite.SQLITE_NULL)
        null
    else
        parseEnumText(
            exact_identity.CodecVersion,
            try textColumnCapped(row, 14, 64),
        ) orelse return Error.SqliteFailure;
    const package_key: exact_identity.ExactFormPackageKey = .{
        .revision = .{
            .code = form_code,
            .revision = form_revision,
        },
        .locale = locale,
        .offline_package_version = package_version,
        .payload_schema_or_form_token = payload_token,
        .offline_package_sha256 = offline_digest,
        .primary_source_sha256 = primary_digest,
        .dependency_manifest_sha256 = dependency_digest,
        .official_pdf_sha256 = official_pdf_digest,
        .official_guide_sha256 = official_guide_digest,
        .codec_version = codec_version,
    };
    const package_digest = try readDigest(row, 15);
    const manifest_digest = try readDigest(row, 16);
    const exact_schema_digest = try readDigest(row, 17);
    const payload_shape = parseEnumText(
        exact_draft.PayloadShape,
        columnText(row, 18) orelse return Error.SqliteFailure,
    ) orelse return Error.SqliteFailure;
    const occurrence_count_raw = sqlite.sqlite3_column_int64(row, 19);
    if (occurrence_count_raw <= 0 or
        occurrence_count_raw > std.math.maxInt(u16))
    {
        return Error.SqliteFailure;
    }
    const readiness: exact_evidence.EvidenceReadiness = .{
        .identity_resolved = try readStrictBool(row, 20),
        .dependency_closure = try readStrictBool(row, 21),
        .profile_mapping_reviewed = try readStrictBool(row, 22),
        .calculation_reconciled = try readStrictBool(row, 23),
        .validation_reconciled = try readStrictBool(row, 24),
        .editable_serializer_exact = try readStrictBool(row, 25),
        .final_plaintext_serializer_exact = try readStrictBool(row, 26),
        .decrypt_codec_qualified = try readStrictBool(row, 27),
        .encrypt_codec_qualified = try readStrictBool(row, 28),
        .persistence_integrated = try readStrictBool(row, 29),
        .ui_integrated = try readStrictBool(row, 30),
        .offline_package_verified = try readStrictBool(row, 31),
        .transport_enabled = false,
    };
    return .{
        .package_key = package_key,
        .package_digest = package_digest,
        .occurrence_manifest_digest = manifest_digest,
        .exact_schema_digest = exact_schema_digest,
        .payload_shape = payload_shape,
        .occurrence_count = @intCast(occurrence_count_raw),
        .evidence_readiness = readiness,
    };
}

fn readExactDraftRevision(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    schema: exact_draft.SchemaBinding,
    bindings: []OwnedExactDraftRoleBinding,
    occurrences: []OwnedExactDraftOccurrence,
) !OwnedExactDraftRevision {
    const revision_raw = sqlite.sqlite3_column_int64(row, 0);
    if (revision_raw <= 0) return Error.SqliteFailure;
    const revision = DraftRevision.init(@intCast(revision_raw)) catch
        return Error.SqliteFailure;
    const parent_revision: ?DraftRevision = if (sqlite.sqlite3_column_type(row, 1) == sqlite.SQLITE_NULL)
        null
    else blk: {
        const raw = sqlite.sqlite3_column_int64(row, 1);
        if (raw <= 0) return Error.SqliteFailure;
        break :blk DraftRevision.init(@intCast(raw)) catch
            return Error.SqliteFailure;
    };
    const profile_as_of_text = try textColumnCapped(row, 2, 10);
    try validateDate(profile_as_of_text);
    const profile_as_of = try allocator.dupe(u8, profile_as_of_text);
    errdefer allocator.free(profile_as_of);
    const recorded_at_unix_seconds = sqlite.sqlite3_column_int64(row, 3);
    if (recorded_at_unix_seconds <= 0) return Error.SqliteFailure;

    return .{
        .revision = revision,
        .parent_revision = parent_revision,
        .profile_as_of = profile_as_of,
        .recorded_at_unix_seconds = recorded_at_unix_seconds,
        .schema = schema,
        .profile_snapshot_digest = try readDigest(row, 32),
        .transaction_state_digest = try readDigest(row, 33),
        .ordered_values_digest = try readDigest(row, 34),
        .validation_evidence = try readExactValidationEvidence(row, 35),
        .validation_status = try readExactValidationStatus(row, 37),
        .artifact_status = try readExactArtifactStatus(row, 41),
        .bindings = bindings,
        .occurrences = occurrences,
    };
}

fn readExactValidationEvidence(
    row: *sqlite.sqlite3_stmt,
    first_column: c_int,
) !ExactDraftValidationEvidenceReceipt {
    if (sqlite.sqlite3_column_type(row, first_column) !=
        sqlite.SQLITE_INTEGER)
    {
        return Error.SqliteFailure;
    }
    const current_year = sqlite.sqlite3_column_int64(row, first_column);
    if (current_year < std.math.minInt(i32) or
        current_year > std.math.maxInt(i32))
    {
        return Error.SqliteFailure;
    }
    const spouse_tin_checksum = parseEnumText(
        exact_validation.TinChecksumStatus,
        try textColumnCapped(row, first_column + 1, 32),
    ) orelse return Error.SqliteFailure;
    return .{
        .validation_current_year = @intCast(current_year),
        .spouse_tin_checksum = spouse_tin_checksum,
    };
}

fn readExactValidationStatus(
    row: *sqlite.sqlite3_stmt,
    first_column: c_int,
) !exact_draft.ValidationStatus {
    const save_text = columnText(row, first_column) orelse
        return Error.SqliteFailure;
    const save_code_column = first_column + 1;
    const save_gate: exact_draft.SaveGateStatus =
        if (std.mem.eql(u8, save_text, "not_run")) blk: {
            if (sqlite.sqlite3_column_type(row, save_code_column) !=
                sqlite.SQLITE_NULL)
            {
                return Error.SqliteFailure;
            }
            break :blk .not_run;
        } else if (std.mem.eql(u8, save_text, "passed")) blk: {
            if (sqlite.sqlite3_column_type(row, save_code_column) !=
                sqlite.SQLITE_NULL)
            {
                return Error.SqliteFailure;
            }
            break :blk .passed;
        } else if (std.mem.eql(u8, save_text, "failed")) blk: {
            const raw = sqlite.sqlite3_column_int64(row, save_code_column);
            const rule = enumFromIntChecked(
                exact_validation.SaveRuleId,
                raw,
            ) orelse return Error.SqliteFailure;
            break :blk .{ .failed = rule };
        } else return Error.SqliteFailure;

    const full_text = columnText(row, first_column + 2) orelse
        return Error.SqliteFailure;
    const full_code_column = first_column + 3;
    const full_validation: exact_draft.FullValidationStatus =
        if (std.mem.eql(u8, full_text, "not_run")) blk: {
            if (sqlite.sqlite3_column_type(row, full_code_column) !=
                sqlite.SQLITE_NULL)
            {
                return Error.SqliteFailure;
            }
            break :blk .not_run;
        } else if (std.mem.eql(u8, full_text, "passed")) blk: {
            if (sqlite.sqlite3_column_type(row, full_code_column) !=
                sqlite.SQLITE_NULL)
            {
                return Error.SqliteFailure;
            }
            break :blk .passed;
        } else if (std.mem.eql(u8, full_text, "failed")) blk: {
            const raw = sqlite.sqlite3_column_int64(row, full_code_column);
            const rule = enumFromIntChecked(
                exact_validation.FullRuleId,
                raw,
            ) orelse return Error.SqliteFailure;
            break :blk .{ .failed = rule };
        } else if (std.mem.eql(u8, full_text, "blocked")) blk: {
            const raw = sqlite.sqlite3_column_int64(row, full_code_column);
            const block = enumFromIntChecked(
                exact_validation.ValidationBlock,
                raw,
            ) orelse return Error.SqliteFailure;
            break :blk .{ .blocked = block };
        } else return Error.SqliteFailure;

    return .{
        .save_gate = save_gate,
        .full_validation = full_validation,
    };
}

fn readExactArtifactStatus(
    row: *sqlite.sqlite3_stmt,
    first_column: c_int,
) !exact_draft.ArtifactStatus {
    const status = columnText(row, first_column) orelse
        return Error.SqliteFailure;
    if (std.mem.eql(u8, status, "not_generated")) {
        if (sqlite.sqlite3_column_type(row, first_column + 1) !=
            sqlite.SQLITE_NULL or
            sqlite.sqlite3_column_type(row, first_column + 2) !=
                sqlite.SQLITE_NULL or
            sqlite.sqlite3_column_type(row, first_column + 3) !=
                sqlite.SQLITE_NULL)
        {
            return Error.SqliteFailure;
        }
        return .not_generated;
    }

    const marker_text = columnText(row, first_column + 1) orelse
        return Error.SqliteFailure;
    const marker = parseEnumText(
        exact_document.Marker,
        marker_text,
    ) orelse return Error.SqliteFailure;
    const byte_length_raw = sqlite.sqlite3_column_int64(
        row,
        first_column + 2,
    );
    if (byte_length_raw < 0 or byte_length_raw > std.math.maxInt(u32)) {
        return Error.SqliteFailure;
    }
    const receipt: exact_draft.PlaintextReceipt = .{
        .marker = marker,
        .byte_length = @intCast(byte_length_raw),
        .sha256 = try readDigest(row, first_column + 3),
    };
    if (std.mem.eql(u8, status, "plaintext_candidate")) {
        return .{ .plaintext_candidate = receipt };
    }
    if (std.mem.eql(u8, status, "plaintext_exact")) {
        return .{ .plaintext_exact = receipt };
    }
    return Error.SqliteFailure;
}

fn readProfileSummary(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
) !OwnedProfileSummary {
    const id = try dupColumn(allocator, row, 0);
    errdefer allocator.free(id);
    const status_text = columnText(row, 1) orelse return Error.SqliteFailure;
    const status = parseProfileStatus(status_text) orelse return Error.SqliteFailure;
    const current_revision_id = try dupColumn(allocator, row, 2);
    errdefer allocator.free(current_revision_id);
    const sequence_raw = sqlite.sqlite3_column_int64(row, 3);
    if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
        return Error.SqliteFailure;
    }
    const display_name = try dupColumn(allocator, row, 4);
    errdefer allocator.free(display_name);
    const tin = try dupColumn(allocator, row, 5);
    errdefer allocator.free(tin);
    const subject_kind_text = columnText(row, 6) orelse return Error.SqliteFailure;
    const subject_kind = parseSubjectKind(subject_kind_text) orelse
        return Error.SqliteFailure;
    return .{
        .id = id,
        .status = status,
        .current_revision_id = current_revision_id,
        .current_revision_sequence = @intCast(sequence_raw),
        .display_name = display_name,
        .tin = tin,
        .subject_kind = subject_kind,
    };
}

fn readRevisionSource(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    tag_column: c_int,
    reference_column: c_int,
) !OwnedRevisionSource {
    const tag_text = columnText(row, tag_column) orelse
        return Error.SqliteFailure;
    const tag = parseRevisionSourceTag(tag_text) orelse
        return Error.SqliteFailure;
    return switch (tag) {
        .manual_entry => {
            if (sqlite.sqlite3_column_type(row, reference_column) !=
                sqlite.SQLITE_NULL)
            {
                return Error.SqliteFailure;
            }
            return .{ .manual_entry = {} };
        },
        .imported => .{
            .imported = try dupColumn(allocator, row, reference_column),
        },
        .migrated => .{
            .migrated = try dupColumn(allocator, row, reference_column),
        },
    };
}

fn readIdentityAnchor(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
) !OwnedTaxpayerIdentityAnchor {
    const profile_id = try dupColumn(allocator, row, 0);
    errdefer allocator.free(profile_id);
    const sequence_raw = sqlite.sqlite3_column_int64(row, 1);
    if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
        return Error.SqliteFailure;
    }
    const jurisdiction_text = columnText(row, 2) orelse
        return Error.SqliteFailure;
    const jurisdiction = parseJurisdiction(jurisdiction_text) orelse
        return Error.SqliteFailure;
    const authority_text = columnText(row, 3) orelse
        return Error.SqliteFailure;
    const authority = parseTaxAuthority(authority_text) orelse
        return Error.SqliteFailure;
    const canonical_tin = try dupColumn(allocator, row, 4);
    errdefer allocator.free(canonical_tin);
    const class_text = columnText(row, 5) orelse
        return Error.SqliteFailure;
    const class = parseLegalPersonClass(class_text) orelse
        return Error.SqliteFailure;
    const established_from_revision_id = try dupOptionalColumn(
        allocator,
        row,
        6,
    );
    errdefer freeOptional(allocator, established_from_revision_id);
    const identity_correction_id = try dupOptionalColumn(allocator, row, 7);
    errdefer freeOptional(allocator, identity_correction_id);
    return .{
        .profile_id = profile_id,
        .sequence = @intCast(sequence_raw),
        .jurisdiction = jurisdiction,
        .tax_authority = authority,
        .canonical_tin = canonical_tin,
        .legal_person_class = class,
        .established_from_revision_id = established_from_revision_id,
        .identity_correction_id = identity_correction_id,
    };
}

fn readCivilStatusRevision(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
) !OwnedCivilStatusRevision {
    const profile_id = try dupColumn(allocator, row, 0);
    errdefer allocator.free(profile_id);
    const sequence_raw = sqlite.sqlite3_column_int64(row, 1);
    if (sequence_raw <= 0 or sequence_raw > std.math.maxInt(u32)) {
        return Error.SqliteFailure;
    }
    const effective_from = try dupColumn(allocator, row, 2);
    errdefer allocator.free(effective_from);
    const effective_until = try dupOptionalColumn(allocator, row, 3);
    errdefer freeOptional(allocator, effective_until);
    const status_text = columnText(row, 4) orelse
        return Error.SqliteFailure;
    const status = parseCivilStatus(status_text) orelse
        return Error.SqliteFailure;
    var source = try readRevisionSource(allocator, row, 5, 6);
    errdefer source.deinit(allocator);
    return .{
        .profile_id = profile_id,
        .sequence = @intCast(sequence_raw),
        .effective_from = effective_from,
        .effective_until = effective_until,
        .status = status,
        .source = source,
    };
}

fn readProfileRelationship(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
) !OwnedProfileRelationship {
    const id = try dupColumn(allocator, row, 0);
    errdefer allocator.free(id);
    const from_profile_id = try dupColumn(allocator, row, 1);
    errdefer allocator.free(from_profile_id);
    const to_profile_id = try dupColumn(allocator, row, 2);
    errdefer allocator.free(to_profile_id);
    const kind_text = columnText(row, 3) orelse
        return Error.SqliteFailure;
    const kind = parseRelationshipKind(kind_text) orelse
        return Error.SqliteFailure;
    const effective_from = try dupColumn(allocator, row, 4);
    errdefer allocator.free(effective_from);
    const effective_until = try dupOptionalColumn(allocator, row, 5);
    errdefer freeOptional(allocator, effective_until);
    const provenance = try dupColumn(allocator, row, 6);
    errdefer allocator.free(provenance);
    return .{
        .id = id,
        .from_profile_id = from_profile_id,
        .to_profile_id = to_profile_id,
        .kind = kind,
        .effective_from = effective_from,
        .effective_until = effective_until,
        .provenance = provenance,
    };
}

fn readIdentityCorrection(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
) !OwnedIdentityCorrection {
    const id = try dupColumn(allocator, row, 0);
    errdefer allocator.free(id);
    const profile_id = try dupColumn(allocator, row, 1);
    errdefer allocator.free(profile_id);
    const old_sequence_raw = sqlite.sqlite3_column_int64(row, 2);
    const new_sequence_raw = sqlite.sqlite3_column_int64(row, 3);
    if (old_sequence_raw <= 0 or
        new_sequence_raw <= 0 or
        old_sequence_raw > std.math.maxInt(u32) or
        new_sequence_raw > std.math.maxInt(u32))
    {
        return Error.SqliteFailure;
    }
    const old_tin = try dupColumn(allocator, row, 4);
    errdefer allocator.free(old_tin);
    const new_tin = try dupColumn(allocator, row, 5);
    errdefer allocator.free(new_tin);
    const old_class_text = columnText(row, 6) orelse
        return Error.SqliteFailure;
    const old_class = parseLegalPersonClass(old_class_text) orelse
        return Error.SqliteFailure;
    const new_class_text = columnText(row, 7) orelse
        return Error.SqliteFailure;
    const new_class = parseLegalPersonClass(new_class_text) orelse
        return Error.SqliteFailure;
    const reason = try dupColumn(allocator, row, 8);
    errdefer allocator.free(reason);
    const actor_reference = try dupColumn(allocator, row, 9);
    errdefer allocator.free(actor_reference);
    const recorded_at = sqlite.sqlite3_column_int64(row, 10);
    const provenance = try dupColumn(allocator, row, 11);
    errdefer allocator.free(provenance);
    return .{
        .id = id,
        .profile_id = profile_id,
        .old_anchor_sequence = @intCast(old_sequence_raw),
        .new_anchor_sequence = @intCast(new_sequence_raw),
        .old_canonical_tin = old_tin,
        .new_canonical_tin = new_tin,
        .old_legal_person_class = old_class,
        .new_legal_person_class = new_class,
        .reason = reason,
        .actor_reference = actor_reference,
        .recorded_at_unix_seconds = recorded_at,
        .provenance = provenance,
    };
}

fn readSubject(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    kind_column: c_int,
) !OwnedSubject {
    const kind_text = columnText(row, kind_column) orelse
        return Error.SqliteFailure;
    const kind = parseSubjectKind(kind_text) orelse return Error.SqliteFailure;
    const taxpayer_name_column = kind_column + 1;
    const registered_name_column = kind_column + 2;
    const birth_date_column = kind_column + 3;
    const citizenship_column = kind_column + 4;
    const foreign_tax_number_column = kind_column + 5;

    switch (kind) {
        .individual, .sole_proprietor => {
            const name = try dupColumn(allocator, row, taxpayer_name_column);
            errdefer allocator.free(name);
            const date_of_birth = try dupOptionalColumn(
                allocator,
                row,
                birth_date_column,
            );
            errdefer freeOptional(allocator, date_of_birth);
            const citizenship = try dupOptionalColumn(
                allocator,
                row,
                citizenship_column,
            );
            errdefer freeOptional(allocator, citizenship);
            const foreign_tax_number = try dupOptionalColumn(
                allocator,
                row,
                foreign_tax_number_column,
            );
            errdefer freeOptional(allocator, foreign_tax_number);
            const person: OwnedIndividual = .{
                .name = name,
                .date_of_birth = date_of_birth,
                .citizenship = citizenship,
                .foreign_tax_number = foreign_tax_number,
            };
            if (kind == .individual) {
                if (sqlite.sqlite3_column_type(row, registered_name_column) !=
                    sqlite.SQLITE_NULL)
                {
                    return Error.SqliteFailure;
                }
                return .{ .individual = person };
            }
            const trade_name = try dupOptionalColumn(
                allocator,
                row,
                registered_name_column,
            );
            return .{ .sole_proprietor = .{
                .person = person,
                .trade_name = trade_name,
            } };
        },
        .corporation,
        .partnership,
        .estate,
        .trust,
        .other_legal_entity,
        => {
            const registered_name = try dupColumn(
                allocator,
                row,
                registered_name_column,
            );
            errdefer allocator.free(registered_name);
            return .{ .legal_entity = .{
                .registered_name = registered_name,
                .kind = switch (kind) {
                    .corporation => .corporation,
                    .partnership => .partnership,
                    .estate => .estate,
                    .trust => .trust,
                    .other_legal_entity => .other,
                    else => unreachable,
                },
            } };
        },
    }
}

fn readRegistrationFactValue(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    kind_column: c_int,
    value_column: c_int,
) !OwnedRegistrationFactValue {
    const kind_text = columnText(row, kind_column) orelse
        return Error.SqliteFailure;
    const kind = parseRegistrationFactKind(kind_text) orelse
        return Error.SqliteFailure;
    return switch (kind) {
        .tax_type => .{
            .tax_type = try dupColumn(allocator, row, value_column),
        },
        .government_withholding_agent => blk: {
            const value_text = columnText(row, value_column) orelse
                return Error.SqliteFailure;
            const value = parseGovernmentWithholdingAgent(value_text) orelse
                return Error.SqliteFailure;
            break :blk .{ .government_withholding_agent = value };
        },
        .special_rate_basis => .{
            .special_rate_basis = try dupColumn(
                allocator,
                row,
                value_column,
            ),
        },
    };
}

fn columnByteLengthCapped(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
    expected_type: c_int,
    maximum: usize,
) !usize {
    if (sqlite.sqlite3_column_type(row, column) != expected_type) {
        return Error.SqliteFailure;
    }
    const length = sqlite.sqlite3_column_bytes(row, column);
    if (length < 0) return Error.SqliteFailure;
    const length_usize: usize = @intCast(length);
    if (length_usize > maximum) return Error.SqliteFailure;
    return length_usize;
}

fn textColumnCapped(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
    maximum: usize,
) ![]const u8 {
    const length = try columnByteLengthCapped(
        row,
        column,
        sqlite.SQLITE_TEXT,
        maximum,
    );
    if (length == 0) return "";
    const raw = sqlite.sqlite3_column_text(row, column) orelse
        return Error.SqliteFailure;
    const bytes: [*]const u8 = @ptrCast(raw);
    return bytes[0..length];
}

fn optionalTextColumnCapped(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
    maximum: usize,
) !?[]const u8 {
    if (sqlite.sqlite3_column_type(row, column) == sqlite.SQLITE_NULL) {
        return null;
    }
    return try textColumnCapped(row, column, maximum);
}

fn blobColumnCapped(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
    maximum: usize,
) ![]const u8 {
    const length = try columnByteLengthCapped(
        row,
        column,
        sqlite.SQLITE_BLOB,
        maximum,
    );
    if (length == 0) return "";
    const raw = sqlite.sqlite3_column_blob(row, column) orelse
        return Error.SqliteFailure;
    const bytes: [*]const u8 = @ptrCast(raw);
    return bytes[0..length];
}

fn dupTextColumnCapped(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    column: c_int,
    maximum: usize,
) ![]u8 {
    return allocator.dupe(
        u8,
        try textColumnCapped(row, column, maximum),
    );
}

fn dupBlobColumnCapped(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    column: c_int,
    maximum: usize,
) ![]u8 {
    return allocator.dupe(
        u8,
        try blobColumnCapped(row, column, maximum),
    );
}

fn dupColumn(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) ![]u8 {
    const text = columnText(row, column) orelse return Error.SqliteFailure;
    return allocator.dupe(u8, text);
}

fn dupBlobColumn(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) ![]u8 {
    if (sqlite.sqlite3_column_type(row, column) != sqlite.SQLITE_BLOB) {
        return Error.SqliteFailure;
    }
    const length = sqlite.sqlite3_column_bytes(row, column);
    if (length < 0) return Error.SqliteFailure;
    if (length == 0) return allocator.alloc(u8, 0);
    const raw = sqlite.sqlite3_column_blob(row, column) orelse
        return Error.SqliteFailure;
    const bytes: [*]const u8 = @ptrCast(raw);
    return allocator.dupe(u8, bytes[0..@intCast(length)]);
}

fn dupOptionalColumn(
    allocator: std.mem.Allocator,
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) !?[]u8 {
    if (sqlite.sqlite3_column_type(row, column) == sqlite.SQLITE_NULL) return null;
    return try dupColumn(allocator, row, column);
}

fn columnText(row: *sqlite.sqlite3_stmt, column: c_int) ?[]const u8 {
    const raw = sqlite.sqlite3_column_text(row, column) orelse return null;
    const length = sqlite.sqlite3_column_bytes(row, column);
    if (length < 0) return null;
    const bytes: [*]const u8 = @ptrCast(raw);
    return bytes[0..@intCast(length)];
}

fn columnTextEql(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
    expected: []const u8,
) bool {
    const actual = columnText(row, column) orelse return false;
    return std.mem.eql(u8, actual, expected);
}

fn readDigest(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) !exact_identity.Sha256Digest {
    if (sqlite.sqlite3_column_type(row, column) != sqlite.SQLITE_BLOB or
        sqlite.sqlite3_column_bytes(row, column) != 32)
    {
        return Error.SqliteFailure;
    }
    const raw = sqlite.sqlite3_column_blob(row, column) orelse
        return Error.SqliteFailure;
    const bytes: *const [32]u8 = @ptrCast(@alignCast(raw));
    return .{ .bytes = bytes.* };
}

fn readOptionalDigest(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) !?exact_identity.Sha256Digest {
    if (sqlite.sqlite3_column_type(row, column) == sqlite.SQLITE_NULL) {
        return null;
    }
    return try readDigest(row, column);
}

fn readDraftWorkspaceId(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) !DraftWorkspaceId {
    if (sqlite.sqlite3_column_type(row, column) != sqlite.SQLITE_BLOB or
        sqlite.sqlite3_column_bytes(row, column) != 16)
    {
        return Error.SqliteFailure;
    }
    const raw = sqlite.sqlite3_column_blob(row, column) orelse
        return Error.SqliteFailure;
    const bytes: *const [16]u8 = @ptrCast(@alignCast(raw));
    return DraftWorkspaceId.init(bytes.*) catch Error.SqliteFailure;
}

fn readStrictBool(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
) !bool {
    if (sqlite.sqlite3_column_type(row, column) != sqlite.SQLITE_INTEGER) {
        return Error.SqliteFailure;
    }
    return switch (sqlite.sqlite3_column_int(row, column)) {
        0 => false,
        1 => true,
        else => Error.SqliteFailure,
    };
}

fn mapResult(rc: c_int) Error {
    const primary = rc & 0xff;
    return switch (primary) {
        sqlite.SQLITE_BUSY, sqlite.SQLITE_LOCKED => Error.SqliteBusy,
        sqlite.SQLITE_CONSTRAINT => Error.SqliteConstraint,
        else => Error.SqliteFailure,
    };
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]u8) void {
    if (value) |bytes| allocator.free(bytes);
}

fn secureFreeOwned(allocator: std.mem.Allocator, value: []u8) void {
    sensitive_memory.wipeAndFreeDefaultAligned(u8, allocator, value);
}

fn optionalDateSlice(value: *const ?DateText) ?[]const u8 {
    if (value.*) |*date| return date[0..];
    return null;
}

fn parseProfileStatus(value: []const u8) ?ProfileStatus {
    inline for (std.meta.fields(ProfileStatus)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseJurisdiction(value: []const u8) ?Jurisdiction {
    inline for (std.meta.fields(Jurisdiction)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseTaxAuthority(value: []const u8) ?TaxAuthority {
    inline for (std.meta.fields(TaxAuthority)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseLegalPersonClass(value: []const u8) ?LegalPersonClass {
    inline for (std.meta.fields(LegalPersonClass)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn legalPersonClassText(value: LegalPersonClass) []const u8 {
    return @tagName(value);
}

fn legalPersonClassForSubjectKind(value: SubjectKind) LegalPersonClass {
    return switch (value) {
        .individual, .sole_proprietor => .natural_person,
        .corporation, .partnership => .juridical_person,
        .estate => .estate,
        .trust => .trust,
        .other_legal_entity => .reviewed_other,
    };
}

fn parseCivilStatus(value: []const u8) ?CivilStatus {
    inline for (std.meta.fields(CivilStatus)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn civilStatusText(value: CivilStatus) []const u8 {
    return @tagName(value);
}

fn parseRelationshipKind(value: []const u8) ?RelationshipKind {
    inline for (std.meta.fields(RelationshipKind)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn relationshipKindText(value: RelationshipKind) []const u8 {
    return @tagName(value);
}

fn relationshipClassesValid(
    kind: RelationshipKind,
    from: LegalPersonClass,
    to: LegalPersonClass,
) bool {
    return switch (kind) {
        .spouse_of => from == .natural_person and to == .natural_person,
        .business_converted_to => from == .natural_person and
            to == .juridical_person,
        .predecessor_of, .successor_of => true,
    };
}

fn parseSubjectKind(value: []const u8) ?SubjectKind {
    inline for (std.meta.fields(SubjectKind)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseRevisionSourceTag(value: []const u8) ?RevisionSourceTag {
    inline for (std.meta.fields(RevisionSourceTag)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseRegistrationFactKind(value: []const u8) ?RegistrationFactKind {
    inline for (std.meta.fields(RegistrationFactKind)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseGovernmentWithholdingAgent(
    value: []const u8,
) ?GovernmentWithholdingAgent {
    inline for (std.meta.fields(GovernmentWithholdingAgent)) |field| {
        if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn parseFilingIntent(value: []const u8) ?FilingIntent {
    return parseEnumText(FilingIntent, value);
}

fn exactDraftOriginText(value: ExactDraftOrigin) []const u8 {
    return @tagName(value);
}

fn parseExactDraftOrigin(value: []const u8) ?ExactDraftOrigin {
    return parseEnumText(ExactDraftOrigin, value);
}

fn parseEnumText(comptime Enum: type, value: []const u8) ?Enum {
    inline for (std.meta.fields(Enum)) |field| {
        if (std.mem.eql(u8, value, field.name)) {
            return @enumFromInt(field.value);
        }
    }
    return null;
}

fn enumFromIntChecked(comptime Enum: type, value: i64) ?Enum {
    inline for (std.meta.fields(Enum)) |field| {
        if (value == field.value) return @enumFromInt(field.value);
    }
    return null;
}

fn validateProfileCreate(value: ProfileCreate) Error!void {
    try validateIdText(value.id);
}

fn validateRevisionSource(value: RevisionSourceWrite) Error!void {
    switch (value) {
        .manual_entry => {},
        .imported => |reference| try validateEvolutionSourceReference(reference),
        .migrated => |reference| try validateEvolutionSourceReference(reference),
    }
}

fn validateEvolutionSourceReference(value: []const u8) Error!void {
    _ = profile_field.SourceReference.parse(value) catch
        return Error.InvalidValue;
}

fn validateRevision(
    value: RevisionWrite,
    components: RevisionComponentsWrite,
) Error!void {
    try validateIdText(value.id);
    try validateIdText(value.profile_id);
    if (value.sequence == 0) return Error.InvalidValue;
    try validatePeriod(value.effective);
    switch (value.source) {
        .manual_entry => {},
        .imported => |reference| try requireValue(reference),
        .migrated => |reference| try requireValue(reference),
    }
    _ = profile_field.Tin.parse(value.identity.tin) catch
        return Error.InvalidValue;
    try requireValue(value.identity.rdo_code);
    try requireValue(value.contact.registered_address);
    try validateOptionalValue(value.contact.zip_code);
    try validateOptionalValue(value.contact.contact_number);
    try validateOptionalValue(value.contact.email_address);
    switch (value.subject) {
        .individual => |person| try validateIndividual(person),
        .sole_proprietor => |proprietor| {
            try validateIndividual(proprietor.person);
            try validateOptionalValue(proprietor.trade_name);
        },
        .legal_entity => |entity| try requireValue(entity.registered_name),
    }
    for (components.business_activities, 0..) |activity, index| {
        try validateIdText(activity.id);
        try requireValue(activity.line_of_business);
        try validateOptionalValue(activity.atc);
        try validatePeriod(activity.effective);
        for (components.business_activities[index + 1 ..]) |other| {
            if (std.mem.eql(u8, activity.id, other.id)) {
                return Error.InvalidValue;
            }
        }
    }
    for (components.registration_facts, 0..) |fact, index| {
        try validateIdText(fact.id);
        try validatePeriod(fact.effective);
        switch (fact.value) {
            .tax_type => |text| try requireValue(text),
            .government_withholding_agent => {},
            .special_rate_basis => |text| try requireValue(text),
        }
        const kind: RegistrationFactKind = fact.value;
        for (components.registration_facts[index + 1 ..]) |other| {
            if (std.mem.eql(u8, fact.id, other.id)) {
                return Error.InvalidValue;
            }
            const other_kind: RegistrationFactKind = other.value;
            if (kind == other_kind and
                periodsOverlap(fact.effective, other.effective))
            {
                return Error.InvalidValue;
            }
        }
    }
}

fn validateIndividual(value: IndividualWrite) Error!void {
    try requireValue(value.name);
    if (value.date_of_birth) |date| try validateDate(date[0..]);
    try validateOptionalValue(value.citizenship);
    try validateOptionalValue(value.foreign_tax_number);
}

fn validatePeriod(value: EffectivePeriodWrite) Error!void {
    try validateDate(value.from[0..]);
    if (value.until) |until| {
        try validateDate(until[0..]);
        if (std.mem.order(u8, value.from[0..], until[0..]) == .gt) {
            return Error.InvalidDate;
        }
    }
}

fn periodsOverlap(
    left: EffectivePeriodWrite,
    right: EffectivePeriodWrite,
) bool {
    if (left.until) |last| {
        if (std.mem.order(u8, last[0..], right.from[0..]) == .lt) return false;
    }
    if (right.until) |last| {
        if (std.mem.order(u8, last[0..], left.from[0..]) == .lt) return false;
    }
    return true;
}

const ExactValidationColumns = struct {
    save_status: []const u8,
    save_code: ?i64,
    full_status: []const u8,
    full_code: ?i64,
};

fn exactValidationColumns(
    status: exact_draft.ValidationStatus,
) ExactValidationColumns {
    const save_status: []const u8, const save_code: ?i64 =
        switch (status.save_gate) {
            .not_run => .{ "not_run", null },
            .passed => .{ "passed", null },
            .failed => |rule| .{ "failed", @intFromEnum(rule) },
        };
    const full_status: []const u8, const full_code: ?i64 =
        switch (status.full_validation) {
            .not_run => .{ "not_run", null },
            .passed => .{ "passed", null },
            .failed => |rule| .{ "failed", @intFromEnum(rule) },
            .blocked => |block| .{ "blocked", @intFromEnum(block) },
        };
    return .{
        .save_status = save_status,
        .save_code = save_code,
        .full_status = full_status,
        .full_code = full_code,
    };
}

const ExactArtifactColumns = struct {
    status: []const u8,
    marker: ?[]const u8,
    byte_length: ?i64,
    sha256: ?exact_identity.Sha256Digest,
};

fn exactArtifactColumns(
    status: exact_draft.ArtifactStatus,
) ExactArtifactColumns {
    return switch (status) {
        .not_generated => .{
            .status = "not_generated",
            .marker = null,
            .byte_length = null,
            .sha256 = null,
        },
        .plaintext_candidate => |receipt| .{
            .status = "plaintext_candidate",
            .marker = @tagName(receipt.marker),
            .byte_length = receipt.byte_length,
            .sha256 = receipt.sha256,
        },
        .plaintext_exact => |receipt| .{
            .status = "plaintext_exact",
            .marker = @tagName(receipt.marker),
            .byte_length = receipt.byte_length,
            .sha256 = receipt.sha256,
        },
    };
}

fn validateExactDraftRevisionWrite(
    value: ExactDraftRevisionWrite,
) Error!void {
    try validateCanonicalFilingBusinessKey(value.filing_key);
    try validateDate(value.profile_as_of[0..]);
    if (value.recorded_at_unix_seconds <= 0) return Error.InvalidValue;

    const snapshot = value.snapshot;
    try validateDraftWorkspaceId(snapshot.draft_identity.workspace_id);
    if (snapshot.revision.value == 0 or
        checkedU64ToI64(snapshot.revision.value) == null)
    {
        return Error.InvalidValue;
    }
    if (snapshot.parent_revision) |parent| {
        if (parent.value == 0 or parent.value + 1 != snapshot.revision.value) {
            return Error.InvalidValue;
        }
    } else if (snapshot.revision.value != 1) {
        return Error.InvalidValue;
    }
    if (snapshot.revision.value >
        exact_draft.max_revisions_per_exact_shape_stream)
    {
        return Error.DraftRevisionLimitExceeded;
    }

    try validateExactSchemaBinding(snapshot.schema);
    if (!snapshot.draft_identity.exact_schema_digest.eql(
        &snapshot.schema.exact_schema_digest,
    )) {
        return Error.DraftSchemaMismatch;
    }
    if (!std.mem.eql(
        u8,
        snapshot.schema.package_key.revision.code.asSlice(),
        value.filing_key.form_code,
    ) or !std.mem.eql(
        u8,
        snapshot.schema.package_key.revision.revision.asSlice(),
        value.filing_key.form_revision,
    )) {
        return Error.DraftSchemaMismatch;
    }

    if (snapshot.occurrences.len != value.occurrence_contexts.len or
        snapshot.occurrences.len != snapshot.schema.occurrence_count)
    {
        return Error.InvalidValue;
    }
    const manifest = try exactManifestForShape(snapshot.schema.payload_shape);
    try validateExactStoredOccurrences(
        manifest,
        snapshot.occurrences,
        value.occurrence_contexts,
    );
    const computed_values_digest = exactStoredValuesDigest(
        snapshot.occurrences,
    );
    if (!computed_values_digest.eql(&snapshot.ordered_values_digest)) {
        return Error.DraftSchemaMismatch;
    }

    try validateExactBindings(value.filing_key, value.bindings);
    try validateExactArtifactStatus(
        snapshot.schema,
        snapshot.validation_status,
        snapshot.artifact_status,
    );
    try validateStoredExactArtifactReceipt(
        snapshot.schema.payload_shape,
        snapshot.occurrences,
        snapshot.artifact_status,
    );
}

fn validateCanonicalFilingBusinessKey(
    value: CanonicalFilingBusinessKeyWrite,
) Error!void {
    try validateIdText(value.filer_profile_id);
    try requireExactText(value.form_code);
    try requireExactText(value.form_revision);
    try requireExactText(value.period_key);
    _ = form_ids.FormCode.parse(value.form_code) catch
        return Error.InvalidValue;
    _ = form_ids.RevisionLabel.parse(value.form_revision) catch
        return Error.InvalidValue;
}

fn validateDraftWorkspaceId(workspace_id: DraftWorkspaceId) Error!void {
    _ = DraftWorkspaceId.init(workspace_id.bytes) catch
        return Error.InvalidValue;
}

fn validateExactSchemaBinding(
    schema: exact_draft.SchemaBinding,
) Error!void {
    schema.evidence_readiness.validateOfflineBoundary() catch
        return Error.InvalidValue;
    const computed_package_digest = schema.package_key.canonicalDigest();
    if (!computed_package_digest.eql(&schema.package_digest)) {
        return Error.DraftSchemaMismatch;
    }
    const computed_schema_digest = exactSchemaDigest(
        &schema.package_digest,
        &schema.occurrence_manifest_digest,
        schema.payload_shape,
        schema.occurrence_count,
    );
    if (!computed_schema_digest.eql(&schema.exact_schema_digest)) {
        return Error.DraftSchemaMismatch;
    }

    const manifest = try exactManifestForShape(schema.payload_shape);
    const manifest_digest = manifest.canonicalDigest();
    if (manifest.items.len != schema.occurrence_count or
        !manifest_digest.eql(&schema.occurrence_manifest_digest))
    {
        return Error.DraftSchemaMismatch;
    }
    const known_schema = exact_draft.SchemaBinding.exact1701Q(
        schema.payload_shape,
    ) catch return Error.DraftSchemaMismatch;
    // Persisted readiness columns are historical metadata, never current
    // authorization. Until readiness has its own versioned schema identity,
    // fail closed when it differs: replay and the built-in evidence manifest
    // remain the authority and must not be silently upgraded by SQLite.
    if (!known_schema.package_key.eql(&schema.package_key) or
        !std.meta.eql(
            known_schema.evidence_readiness,
            schema.evidence_readiness,
        ))
    {
        return Error.DraftSchemaMismatch;
    }
}

fn exactManifestForShape(
    shape: exact_draft.PayloadShape,
) Error!exact_occurrence.OrderedOccurrenceManifest {
    return switch (shape) {
        .editable_save => exact_form_occurrences.editableManifest() catch
            return Error.DraftSchemaMismatch,
        .final_copy_plaintext => exact_form_occurrences.finalCopyManifest() catch
            return Error.DraftSchemaMismatch,
    };
}

fn validateExactBindings(
    filing_key: CanonicalFilingBusinessKeyWrite,
    bindings: []const ExactDraftRoleBindingWrite,
) Error!void {
    var filer_count: usize = 0;
    var spouse_count: usize = 0;
    var filer_profile: ?[]const u8 = null;
    var spouse_profile: ?[]const u8 = null;
    for (bindings, 0..) |binding, index| {
        try validateIdText(binding.role);
        try validateIdText(binding.instance_id);
        try validateIdText(binding.profile_id);
        try validateIdText(binding.profile_revision_id);
        if (binding.profile_revision_sequence == 0) {
            return Error.InvalidValue;
        }
        if (binding.business_activity_id) |id| try validateIdText(id);
        try validateExactProvenance(binding.provenance);

        if (std.mem.eql(u8, binding.role, "filer")) {
            filer_count += 1;
            filer_profile = binding.profile_id;
        } else if (std.mem.eql(u8, binding.role, "spouse")) {
            spouse_count += 1;
            spouse_profile = binding.profile_id;
        } else {
            return Error.InvalidValue;
        }
        for (bindings[index + 1 ..]) |other| {
            if (std.mem.eql(u8, binding.role, other.role) and
                std.mem.eql(u8, binding.instance_id, other.instance_id))
            {
                return Error.InvalidValue;
            }
        }
    }
    if (filer_count != 1 or spouse_count > 1) return Error.InvalidValue;
    if (!std.mem.eql(
        u8,
        filer_profile.?,
        filing_key.filer_profile_id,
    )) {
        return Error.InvalidValue;
    }
    if (spouse_profile) |spouse| {
        if (std.mem.eql(u8, spouse, filer_profile.?)) {
            return Error.InvalidValue;
        }
    }
}

fn validateExactStoredOccurrences(
    manifest: exact_occurrence.OrderedOccurrenceManifest,
    values: []const exact_draft.StoredOccurrenceValue,
    contexts: []const ExactDraftOccurrenceContextWrite,
) Error!void {
    if (values.len != manifest.items.len or contexts.len != manifest.items.len) {
        return Error.InvalidValue;
    }
    var total_value_bytes: usize = 0;
    for (manifest.items, values, contexts) |metadata, value, context| {
        if (value.ordinal != metadata.ordinal or
            context.ordinal != value.ordinal or
            value.serialized_key.len > exact_document.max_key_bytes or
            !std.mem.eql(
                u8,
                value.serialized_key,
                metadata.serialized_key,
            ) or
            value.same_key_occurrence != metadata.same_key_occurrence)
        {
            return Error.InvalidValue;
        }
        try validateExactOccurrenceProvenance(
            metadata,
            context.origin,
            context.provenance,
        );
        if (!std.unicode.utf8ValidateSlice(value.raw_value) or
            !std.unicode.utf8ValidateSlice(value.normalized_value) or
            value.raw_value.len > exact_document.max_value_bytes or
            value.normalized_value.len > exact_document.max_value_bytes)
        {
            return Error.InvalidValue;
        }
        try validateExactEmittedValue(value.emitted_value);
        total_value_bytes = addExactValueLength(
            total_value_bytes,
            value.raw_value.len,
        ) orelse return Error.InvalidValue;
        total_value_bytes = addExactValueLength(
            total_value_bytes,
            value.normalized_value.len,
        ) orelse return Error.InvalidValue;
        total_value_bytes = addExactValueLength(
            total_value_bytes,
            value.emitted_value.len,
        ) orelse return Error.InvalidValue;
    }
}

fn expectedExactOccurrenceOrigin(
    metadata: exact_occurrence.OccurrenceMetadata,
) Error!ExactDraftOrigin {
    var result: ?ExactDraftOrigin = null;
    for (0..metadata.source_controls.len()) |source_index| {
        const control_id = metadata.source_controls.at(
            @intCast(source_index),
        ) orelse return Error.InvalidValue;
        const candidate = exact_transaction.classifyControl(control_id) orelse
            return Error.InvalidValue;
        if (candidate == .unreviewed) return Error.InvalidValue;
        if (result) |prior| {
            if (prior != candidate) return Error.InvalidValue;
        } else {
            result = candidate;
        }
    }
    const expected = result orelse return Error.InvalidValue;
    if (metadata.origin != .unreviewed and metadata.origin != expected) {
        return Error.InvalidValue;
    }
    return expected;
}

fn validateExactOccurrenceProvenance(
    metadata: exact_occurrence.OccurrenceMetadata,
    origin: ExactDraftOrigin,
    provenance: []const u8,
) Error!void {
    try validateExactProvenance(provenance);
    const expected_origin = try expectedExactOccurrenceOrigin(metadata);
    if (origin != expected_origin or
        !std.mem.eql(
            u8,
            provenance,
            exactOccurrenceProvenance(expected_origin),
        ))
    {
        return Error.InvalidValue;
    }
}

fn exactOccurrenceProvenance(origin: ExactDraftOrigin) []const u8 {
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

fn validateExactProvenance(value: []const u8) Error!void {
    try requireExactText(value);
    if (value.len > max_exact_provenance_bytes or
        !std.unicode.utf8ValidateSlice(value))
    {
        return Error.InvalidValue;
    }
}

fn validateExactEmittedValue(value: []const u8) Error!void {
    if (value.len > exact_document.max_value_bytes) {
        return Error.InvalidValue;
    }
    for (value) |byte| {
        if (byte > 0x7f or byte < 0x20 or byte == 0x7f or byte == '<') {
            return Error.InvalidValue;
        }
    }
}

fn addExactValueLength(current: usize, additional: usize) ?usize {
    const result = std.math.add(usize, current, additional) catch return null;
    if (result > exact_draft.max_total_draft_value_bytes) return null;
    return result;
}

fn addExactRetainedValueLength(
    current: usize,
    additional: usize,
) Error!usize {
    const result = std.math.add(usize, current, additional) catch
        return Error.DraftRetainedValueLimitExceeded;
    if (result > exact_draft.max_retained_exact_value_bytes) {
        return Error.DraftRetainedValueLimitExceeded;
    }
    return result;
}

fn exactStoredRetainedValueBytes(
    values: []const exact_draft.StoredOccurrenceValue,
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

fn validateExactArtifactStatus(
    schema: exact_draft.SchemaBinding,
    validation_status: exact_draft.ValidationStatus,
    artifact_status: exact_draft.ArtifactStatus,
) Error!void {
    switch (artifact_status) {
        .not_generated => return,
        .plaintext_candidate => |receipt| {
            if (!exactArtifactAuthorized(
                schema.payload_shape,
                validation_status,
            ) or exactPlaintextIsExact(schema)) {
                return Error.InvalidValue;
            }
            if (receipt.marker != schema.payload_shape.marker() or
                receipt.byte_length == 0)
            {
                return Error.InvalidValue;
            }
        },
        .plaintext_exact => |receipt| {
            if (!exactArtifactAuthorized(
                schema.payload_shape,
                validation_status,
            ) or !exactPlaintextIsExact(schema)) {
                return Error.InvalidValue;
            }
            if (receipt.marker != schema.payload_shape.marker() or
                receipt.byte_length == 0)
            {
                return Error.InvalidValue;
            }
        },
    }
}

fn validateStoredExactArtifactReceipt(
    shape: exact_draft.PayloadShape,
    values: []const exact_draft.StoredOccurrenceValue,
    status: exact_draft.ArtifactStatus,
) Error!void {
    const persisted = status.receipt() orelse return;
    const computed = try exactStoredRenderedReceipt(shape, values);
    if (persisted.marker != computed.marker or
        persisted.byte_length != computed.byte_length or
        !persisted.sha256.eql(&computed.sha256))
    {
        return Error.InvalidValue;
    }
}

fn validateOwnedExactArtifactReceipt(
    shape: exact_draft.PayloadShape,
    values: []const OwnedExactDraftOccurrence,
    status: exact_draft.ArtifactStatus,
) Error!void {
    const persisted = status.receipt() orelse return;
    const computed = exactOwnedRenderedReceipt(shape, values) catch
        return Error.SqliteFailure;
    if (persisted.marker != computed.marker or
        persisted.byte_length != computed.byte_length or
        !persisted.sha256.eql(&computed.sha256))
    {
        return Error.SqliteFailure;
    }
}

fn exactStoredRenderedReceipt(
    shape: exact_draft.PayloadShape,
    values: []const exact_draft.StoredOccurrenceValue,
) Error!exact_draft.PlaintextReceipt {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var total: usize = 0;
    try updateExactRenderedBytes(
        &hash,
        &total,
        exact_document.document_prefix,
    );
    for (values) |value| {
        try updateExactRenderedOccurrence(
            &hash,
            &total,
            value.serialized_key,
            value.emitted_value,
        );
    }
    try updateExactRenderedBytes(
        &hash,
        &total,
        exactDocumentTail(shape),
    );
    return finishExactRenderedReceipt(&hash, total, shape);
}

fn exactOwnedRenderedReceipt(
    shape: exact_draft.PayloadShape,
    values: []const OwnedExactDraftOccurrence,
) Error!exact_draft.PlaintextReceipt {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var total: usize = 0;
    try updateExactRenderedBytes(
        &hash,
        &total,
        exact_document.document_prefix,
    );
    for (values) |value| {
        try updateExactRenderedOccurrence(
            &hash,
            &total,
            value.serialized_key,
            value.emitted_value,
        );
    }
    try updateExactRenderedBytes(
        &hash,
        &total,
        exactDocumentTail(shape),
    );
    return finishExactRenderedReceipt(&hash, total, shape);
}

fn updateExactRenderedOccurrence(
    hash: *std.crypto.hash.sha2.Sha256,
    total: *usize,
    key: []const u8,
    emitted_value: []const u8,
) Error!void {
    try updateExactRenderedBytes(hash, total, "<div>");
    try updateExactRenderedBytes(hash, total, key);
    try updateExactRenderedBytes(hash, total, "=");
    try updateExactRenderedBytes(hash, total, emitted_value);
    try updateExactRenderedBytes(hash, total, key);
    try updateExactRenderedBytes(hash, total, "=</div>");
    try updateExactRenderedBytes(hash, total, exact_document.separator);
}

fn updateExactRenderedBytes(
    hash: *std.crypto.hash.sha2.Sha256,
    total: *usize,
    bytes: []const u8,
) Error!void {
    total.* = std.math.add(usize, total.*, bytes.len) catch
        return Error.InvalidValue;
    if (total.* > exact_document.max_document_bytes) {
        return Error.InvalidValue;
    }
    hash.update(bytes);
}

fn finishExactRenderedReceipt(
    hash: *std.crypto.hash.sha2.Sha256,
    total: usize,
    shape: exact_draft.PayloadShape,
) Error!exact_draft.PlaintextReceipt {
    if (total > std.math.maxInt(u32)) return Error.InvalidValue;
    var digest: exact_identity.Sha256Digest = .{ .bytes = undefined };
    hash.final(&digest.bytes);
    return .{
        .marker = shape.marker(),
        .byte_length = @intCast(total),
        .sha256 = digest,
    };
}

fn exactDocumentTail(shape: exact_draft.PayloadShape) []const u8 {
    return switch (shape) {
        .editable_save => exact_document.editable_tail,
        .final_copy_plaintext => exact_document.final_tail,
    };
}

fn exactArtifactAuthorized(
    shape: exact_draft.PayloadShape,
    status: exact_draft.ValidationStatus,
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

fn exactPlaintextIsExact(schema: exact_draft.SchemaBinding) bool {
    if (schema.package_key.codec_version == null or
        !schema.evidence_readiness.identityReady() or
        !schema.evidence_readiness.profile_mapping_reviewed or
        !schema.evidence_readiness.calculation_reconciled or
        !schema.evidence_readiness.validation_reconciled)
    {
        return false;
    }
    return switch (schema.payload_shape) {
        .editable_save => schema.evidence_readiness.editable_serializer_exact,
        .final_copy_plaintext => schema.evidence_readiness.final_plaintext_serializer_exact,
    };
}

fn validateOwnedExactDraftRevisionIntegrity(
    value: *const OwnedExactDraftRevision,
) Error!void {
    try validateExactSchemaBinding(value.schema);
    if (value.parent_revision) |parent| {
        if (parent.value + 1 != value.revision.value) {
            return Error.SqliteFailure;
        }
    } else if (value.revision.value != 1) {
        return Error.SqliteFailure;
    }
    const manifest = try exactManifestForShape(value.schema.payload_shape);
    if (value.occurrences.len != value.schema.occurrence_count or
        value.occurrences.len != manifest.items.len)
    {
        return Error.SqliteFailure;
    }
    var total_value_bytes: usize = 0;
    for (manifest.items, value.occurrences) |metadata, occurrence_value| {
        if (occurrence_value.ordinal != metadata.ordinal or
            occurrence_value.serialized_key.len >
                exact_document.max_key_bytes or
            !std.mem.eql(
                u8,
                occurrence_value.serialized_key,
                metadata.serialized_key,
            ) or
            occurrence_value.same_key_occurrence !=
                metadata.same_key_occurrence or
            occurrence_value.raw_value.len >
                exact_document.max_value_bytes or
            occurrence_value.normalized_value.len >
                exact_document.max_value_bytes or
            !std.unicode.utf8ValidateSlice(occurrence_value.raw_value) or
            !std.unicode.utf8ValidateSlice(
                occurrence_value.normalized_value,
            ))
        {
            return Error.SqliteFailure;
        }
        validateExactEmittedValue(occurrence_value.emitted_value) catch
            return Error.SqliteFailure;
        validateExactOccurrenceProvenance(
            metadata,
            occurrence_value.origin,
            occurrence_value.provenance,
        ) catch
            return Error.SqliteFailure;
        total_value_bytes = addExactValueLength(
            total_value_bytes,
            occurrence_value.raw_value.len,
        ) orelse return Error.SqliteFailure;
        total_value_bytes = addExactValueLength(
            total_value_bytes,
            occurrence_value.normalized_value.len,
        ) orelse return Error.SqliteFailure;
        total_value_bytes = addExactValueLength(
            total_value_bytes,
            occurrence_value.emitted_value.len,
        ) orelse return Error.SqliteFailure;
    }
    const digest = exactOwnedValuesDigest(value.occurrences);
    if (!digest.eql(&value.ordered_values_digest)) {
        return Error.SqliteFailure;
    }
    try validateExactArtifactStatus(
        value.schema,
        value.validation_status,
        value.artifact_status,
    );
    try validateOwnedExactArtifactReceipt(
        value.schema.payload_shape,
        value.occurrences,
        value.artifact_status,
    );
}

fn exactStoredValuesDigest(
    values: []const exact_draft.StoredOccurrenceValue,
) exact_identity.Sha256Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.ordered-draft-values.v1");
    updateDigestU32(&hash, @intCast(values.len));
    for (values) |value| {
        updateDigestU16(&hash, value.ordinal);
        updateDigestLengthPrefixed(&hash, value.serialized_key);
        updateDigestU16(&hash, value.same_key_occurrence);
        updateDigestLengthPrefixed(&hash, value.raw_value);
        updateDigestLengthPrefixed(&hash, value.normalized_value);
        updateDigestLengthPrefixed(&hash, value.emitted_value);
    }
    var result: exact_identity.Sha256Digest = .{ .bytes = undefined };
    hash.final(&result.bytes);
    return result;
}

fn exactOwnedValuesDigest(
    values: []const OwnedExactDraftOccurrence,
) exact_identity.Sha256Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.ordered-draft-values.v1");
    updateDigestU32(&hash, @intCast(values.len));
    for (values) |value| {
        updateDigestU16(&hash, value.ordinal);
        updateDigestLengthPrefixed(&hash, value.serialized_key);
        updateDigestU16(&hash, value.same_key_occurrence);
        updateDigestLengthPrefixed(&hash, value.raw_value);
        updateDigestLengthPrefixed(&hash, value.normalized_value);
        updateDigestLengthPrefixed(&hash, value.emitted_value);
    }
    var result: exact_identity.Sha256Digest = .{ .bytes = undefined };
    hash.final(&result.bytes);
    return result;
}

fn exactSchemaDigest(
    package_digest: *const exact_identity.Sha256Digest,
    manifest_digest: *const exact_identity.Sha256Digest,
    shape: exact_draft.PayloadShape,
    count: u16,
) exact_identity.Sha256Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.ordered-draft-schema.v1");
    hash.update(package_digest.asBytes());
    hash.update(manifest_digest.asBytes());
    hash.update(&.{@intFromEnum(shape)});
    updateDigestU16(&hash, count);
    var result: exact_identity.Sha256Digest = .{ .bytes = undefined };
    hash.final(&result.bytes);
    return result;
}

fn updateDigestLengthPrefixed(
    hash: *std.crypto.hash.sha2.Sha256,
    bytes: []const u8,
) void {
    std.debug.assert(bytes.len <= std.math.maxInt(u32));
    updateDigestU32(hash, @intCast(bytes.len));
    hash.update(bytes);
}

fn updateDigestU16(
    hash: *std.crypto.hash.sha2.Sha256,
    value: u16,
) void {
    hash.update(&.{
        @intCast(value >> 8),
        @intCast(value & 0xff),
    });
}

fn updateDigestU32(
    hash: *std.crypto.hash.sha2.Sha256,
    value: u32,
) void {
    hash.update(&.{
        @intCast(value >> 24),
        @intCast((value >> 16) & 0xff),
        @intCast((value >> 8) & 0xff),
        @intCast(value & 0xff),
    });
}

fn checkedU64ToI64(value: u64) ?i64 {
    if (value > std.math.maxInt(i64)) return null;
    return @intCast(value);
}

fn requireExactText(value: []const u8) Error!void {
    try requireValue(value);
    if (std.mem.indexOfScalar(u8, value, 0) != null) {
        return Error.InvalidValue;
    }
}

fn validateDraft(
    draft: DraftWrite,
    bindings: []const RoleBindingWrite,
    snapshots: []const SnapshotFieldWrite,
    values: []const DraftValueWrite,
) Error!void {
    try validateOpaqueText(draft.id);
    try requireValue(draft.form_code);
    try requireValue(draft.form_revision);
    try requireValue(draft.period_key);
    try validateDate(draft.profile_as_of[0..]);
    try requireValue(draft.mapping_revision);
    if (!validLifecycle(draft.lifecycle)) return Error.InvalidTransition;
    if (std.mem.eql(u8, draft.intent, "original")) {
        if (draft.amendment_of != null) return Error.InvalidAmendment;
    } else if (std.mem.eql(u8, draft.intent, "amended")) {
        const prior = draft.amendment_of orelse return Error.InvalidAmendment;
        try validateOpaqueText(prior);
    } else {
        return Error.InvalidAmendment;
    }
    for (bindings) |binding| {
        try requireValue(binding.role);
        try validateIdText(binding.profile_id);
        try validateIdText(binding.profile_revision_id);
        if (binding.profile_revision_sequence == 0) return Error.InvalidValue;
        if (binding.business_activity_id) |id| try validateIdText(id);
    }
    for (snapshots) |snapshot| {
        try requireValue(snapshot.role);
        try requireValue(snapshot.field_id);
        try requireValue(snapshot.reusable_field);
        try requireValue(snapshot.value_type);
        try requireValue(snapshot.provenance);
        try validateIdText(snapshot.profile_revision_id);
        if (snapshot.profile_revision_sequence == 0) return Error.InvalidValue;
        switch (snapshot.revision_source) {
            .manual_entry => {},
            .imported => |reference| try requireValue(reference),
            .migrated => |reference| try requireValue(reference),
        }
        if (snapshot.business_activity_id) |id| try validateIdText(id);
        if (snapshot.registration_fact_id) |id| try validateIdText(id);
        const binding = findBinding(bindings, snapshot.role) orelse
            return Error.InvalidValue;
        if (snapshot.business_activity_id) |activity_id| {
            const selected = binding.business_activity_id orelse
                return Error.InvalidValue;
            if (!std.mem.eql(u8, activity_id, selected)) {
                return Error.InvalidValue;
            }
        }
    }
    try validateDraftValues(values);
}

fn validateDraftValues(values: []const DraftValueWrite) Error!void {
    for (values, 0..) |value, index| {
        try requireValue(value.field_id);
        try requireValue(value.provenance);
        for (values[index + 1 ..]) |other| {
            if (std.mem.eql(u8, value.field_id, other.field_id)) {
                return Error.InvalidValue;
            }
        }
    }
}

fn findBinding(
    bindings: []const RoleBindingWrite,
    role: []const u8,
) ?RoleBindingWrite {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.role, role)) return binding;
    }
    return null;
}

fn validLifecycle(value: []const u8) bool {
    const allowed = [_][]const u8{
        "editing",
        "prepared",
        "queued",
        "submitted",
        "confirmed",
        "paid",
        "cancelled",
    };
    for (allowed) |candidate| {
        if (std.mem.eql(u8, value, candidate)) return true;
    }
    return false;
}

fn lifecycleTransitionAllowed(current: []const u8, next: []const u8) bool {
    if (std.mem.eql(u8, current, "editing")) {
        return std.mem.eql(u8, next, "prepared") or
            std.mem.eql(u8, next, "cancelled");
    }
    if (std.mem.eql(u8, current, "prepared")) {
        return std.mem.eql(u8, next, "editing") or
            std.mem.eql(u8, next, "queued") or
            std.mem.eql(u8, next, "cancelled");
    }
    if (std.mem.eql(u8, current, "queued")) {
        return std.mem.eql(u8, next, "submitted") or
            std.mem.eql(u8, next, "cancelled");
    }
    if (std.mem.eql(u8, current, "submitted")) {
        return std.mem.eql(u8, next, "confirmed");
    }
    if (std.mem.eql(u8, current, "confirmed")) {
        return std.mem.eql(u8, next, "paid");
    }
    return false;
}

fn validateOptionalValue(value: ?[]const u8) Error!void {
    if (value) |text| try requireValue(text);
}

fn validateIdText(value: []const u8) Error!void {
    const normalized = trimmed(value);
    if (normalized.len == 0 or normalized.len > 64) return Error.InvalidValue;
    if (normalized.len != value.len) return Error.InvalidValue;
    for (normalized) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and
            byte != '-' and byte != '_' and byte != '.' and byte != ':')
        {
            return Error.InvalidValue;
        }
    }
}

fn validateOpaqueText(value: []const u8) Error!void {
    try validateIdText(value);
}

fn validateLocalOwnerId(value: []const u8) Error!void {
    if (value.len != 32) return Error.InvalidValue;
    for (value) |byte| {
        if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) {
            return Error.InvalidValue;
        }
    }
}

fn validateTaxYear(value: i32) Error!void {
    if (value < 1 or value > 9999) return Error.InvalidValue;
}

fn requireValue(value: []const u8) Error!void {
    if (trimmed(value).len == 0) return Error.InvalidValue;
}

fn trimmed(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn validateDate(value: []const u8) Error!void {
    if (value.len != 10 or value[4] != '-' or value[7] != '-') {
        return Error.InvalidDate;
    }
    for (value, 0..) |byte, index| {
        if (index == 4 or index == 7) continue;
        if (!std.ascii.isDigit(byte)) return Error.InvalidDate;
    }
    const year = parseDigits(value[0..4]);
    const month = parseDigits(value[5..7]);
    const day = parseDigits(value[8..10]);
    if (year == 0 or month < 1 or month > 12) return Error.InvalidDate;
    const month_days = [_]u8{
        31,
        if (isLeapYear(year)) 29 else 28,
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    };
    if (day < 1 or day > month_days[month - 1]) return Error.InvalidDate;
}

fn parseDigits(value: []const u8) u16 {
    var result: u16 = 0;
    for (value) |byte| result = result * 10 + (byte - '0');
    return result;
}

fn isLeapYear(year: u16) bool {
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
}

const schema_v1 =
    \\CREATE TABLE tax_profiles (
    \\    id TEXT PRIMARY KEY
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    status TEXT NOT NULL DEFAULT 'active'
    \\        CHECK (status IN ('active', 'archived')),
    \\    current_revision_id TEXT,
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    FOREIGN KEY (id, current_revision_id)
    \\        REFERENCES tax_profile_revisions(profile_id, id)
    \\        ON UPDATE RESTRICT ON DELETE RESTRICT
    \\        DEFERRABLE INITIALLY DEFERRED
    \\);
    \\
    \\CREATE TABLE tax_profile_revisions (
    \\    storage_rowid INTEGER PRIMARY KEY,
    \\    id TEXT NOT NULL
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE CASCADE,
    \\    sequence INTEGER NOT NULL CHECK (
    \\        sequence > 0 AND sequence <= 4294967295
    \\    ),
    \\    effective_from TEXT NOT NULL,
    \\    effective_until TEXT,
    \\    source_tag TEXT NOT NULL
    \\        CHECK (source_tag IN ('manual_entry', 'imported', 'migrated')),
    \\    source_reference TEXT,
    \\    tin TEXT NOT NULL CHECK (length(trim(tin)) > 0),
    \\    rdo_code TEXT NOT NULL CHECK (length(trim(rdo_code)) > 0),
    \\    registered_address TEXT NOT NULL
    \\        CHECK (length(trim(registered_address)) > 0),
    \\    zip_code TEXT,
    \\    contact_number TEXT,
    \\    email_address TEXT,
    \\    subject_kind TEXT NOT NULL
    \\        CHECK (subject_kind IN (
    \\            'individual', 'sole_proprietor', 'corporation',
    \\            'partnership', 'estate', 'trust', 'other_legal_entity'
    \\        )),
    \\    taxpayer_name TEXT,
    \\    registered_name TEXT,
    \\    date_of_birth TEXT,
    \\    citizenship TEXT,
    \\    foreign_tax_number TEXT,
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    UNIQUE (profile_id, id),
    \\    UNIQUE (profile_id, sequence),
    \\    UNIQUE (profile_id, id, sequence),
    \\    CHECK (
    \\        effective_until IS NULL OR effective_from <= effective_until
    \\    ),
    \\    CHECK (
    \\        (source_tag = 'manual_entry' AND source_reference IS NULL) OR
    \\        (source_tag IN ('imported', 'migrated') AND
    \\            length(trim(source_reference)) > 0)
    \\    ),
    \\    CHECK (
    \\        (subject_kind = 'individual' AND
    \\            length(trim(taxpayer_name)) > 0 AND
    \\            registered_name IS NULL) OR
    \\        (subject_kind = 'sole_proprietor' AND
    \\            length(trim(taxpayer_name)) > 0) OR
    \\        (subject_kind IN (
    \\            'corporation', 'partnership', 'estate', 'trust',
    \\            'other_legal_entity'
    \\        ) AND
    \\            taxpayer_name IS NULL AND
    \\            length(trim(registered_name)) > 0 AND
    \\            date_of_birth IS NULL AND citizenship IS NULL AND
    \\            foreign_tax_number IS NULL)
    \\    )
    \\);
    \\CREATE INDEX tax_profile_revisions_effective_idx
    \\    ON tax_profile_revisions(profile_id, effective_from, effective_until);
    \\
    \\CREATE TRIGGER tax_profile_revisions_immutable
    \\BEFORE UPDATE ON tax_profile_revisions
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'tax profile revisions are append-only');
    \\END;
    \\
    \\CREATE TABLE tax_profile_business_activities (
    \\    profile_id TEXT NOT NULL,
    \\    revision_id TEXT NOT NULL,
    \\    id TEXT NOT NULL
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    line_of_business TEXT NOT NULL
    \\        CHECK (length(trim(line_of_business)) > 0),
    \\    atc TEXT,
    \\    effective_from TEXT NOT NULL,
    \\    effective_until TEXT,
    \\    ordinal INTEGER NOT NULL DEFAULT 0 CHECK (ordinal >= 0),
    \\    PRIMARY KEY (profile_id, revision_id, id),
    \\    FOREIGN KEY (profile_id, revision_id)
    \\        REFERENCES tax_profile_revisions(profile_id, id)
    \\        ON DELETE CASCADE,
    \\    CHECK (
    \\        effective_until IS NULL OR effective_from <= effective_until
    \\    )
    \\);
    \\CREATE INDEX tax_profile_business_activities_order_idx
    \\    ON tax_profile_business_activities(
    \\        profile_id, revision_id, ordinal, id
    \\    );
    \\
    \\CREATE TRIGGER tax_profile_business_activities_immutable
    \\BEFORE UPDATE ON tax_profile_business_activities
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'business activities are immutable');
    \\END;
    \\
    \\CREATE TABLE tax_profile_registration_facts (
    \\    profile_id TEXT NOT NULL,
    \\    revision_id TEXT NOT NULL,
    \\    id TEXT NOT NULL
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    kind TEXT NOT NULL CHECK (kind IN (
    \\        'tax_type', 'government_withholding_agent',
    \\        'special_rate_basis'
    \\    )),
    \\    value_text TEXT NOT NULL CHECK (length(trim(value_text)) > 0),
    \\    effective_from TEXT NOT NULL,
    \\    effective_until TEXT,
    \\    ordinal INTEGER NOT NULL DEFAULT 0 CHECK (ordinal >= 0),
    \\    PRIMARY KEY (profile_id, revision_id, id),
    \\    FOREIGN KEY (profile_id, revision_id)
    \\        REFERENCES tax_profile_revisions(profile_id, id)
    \\        ON DELETE CASCADE,
    \\    CHECK (
    \\        effective_until IS NULL OR effective_from <= effective_until
    \\    ),
    \\    CHECK (
    \\        kind <> 'government_withholding_agent' OR
    \\        value_text IN ('no', 'yes')
    \\    )
    \\);
    \\CREATE INDEX tax_profile_registration_facts_order_idx
    \\    ON tax_profile_registration_facts(
    \\        profile_id, revision_id, ordinal, id
    \\    );
    \\
    \\CREATE TRIGGER tax_profile_registration_facts_immutable
    \\BEFORE UPDATE ON tax_profile_registration_facts
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'registration facts are immutable');
    \\END;
    \\
    \\CREATE TABLE tax_profile_form_sets (
    \\    profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE CASCADE,
    \\    tax_year INTEGER NOT NULL CHECK (tax_year BETWEEN 1 AND 9999),
    \\    configured_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (profile_id, tax_year)
    \\);
    \\
    \\CREATE TABLE tax_profile_form_set_entries (
    \\    profile_id TEXT NOT NULL,
    \\    tax_year INTEGER NOT NULL,
    \\    form_code TEXT NOT NULL CHECK (length(trim(form_code)) > 0),
    \\    form_revision TEXT NOT NULL
    \\        CHECK (length(trim(form_revision)) > 0),
    \\    PRIMARY KEY (profile_id, tax_year, form_code, form_revision),
    \\    FOREIGN KEY (profile_id, tax_year)
    \\        REFERENCES tax_profile_form_sets(profile_id, tax_year)
    \\        ON DELETE CASCADE
    \\);
    \\
    \\CREATE TABLE tax_form_drafts (
    \\    id TEXT PRIMARY KEY
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    form_code TEXT NOT NULL CHECK (length(trim(form_code)) > 0),
    \\    form_revision TEXT NOT NULL
    \\        CHECK (length(trim(form_revision)) > 0),
    \\    period_key TEXT NOT NULL CHECK (length(trim(period_key)) > 0),
    \\    profile_as_of TEXT NOT NULL,
    \\    lifecycle TEXT NOT NULL CHECK (lifecycle IN (
    \\        'editing', 'prepared', 'queued', 'submitted', 'confirmed',
    \\        'paid', 'cancelled'
    \\    )),
    \\    intent TEXT NOT NULL CHECK (intent IN ('original', 'amended')),
    \\    mapping_revision TEXT NOT NULL
    \\        CHECK (length(trim(mapping_revision)) > 0),
    \\    amendment_of TEXT
    \\        REFERENCES tax_form_drafts(id) ON DELETE RESTRICT,
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    CHECK (amendment_of IS NULL OR amendment_of <> id),
    \\    CHECK (
    \\        (intent = 'original' AND amendment_of IS NULL) OR
    \\        (intent = 'amended' AND amendment_of IS NOT NULL)
    \\    )
    \\);
    \\
    \\CREATE TABLE tax_form_draft_role_bindings (
    \\    draft_id TEXT NOT NULL
    \\        REFERENCES tax_form_drafts(id) ON DELETE CASCADE,
    \\    role TEXT NOT NULL CHECK (length(trim(role)) > 0),
    \\    profile_id TEXT NOT NULL,
    \\    profile_revision_id TEXT NOT NULL,
    \\    profile_revision_sequence INTEGER NOT NULL CHECK (
    \\        profile_revision_sequence > 0 AND
    \\        profile_revision_sequence <= 4294967295
    \\    ),
    \\    business_activity_id TEXT,
    \\    PRIMARY KEY (draft_id, role),
    \\    UNIQUE (
    \\        draft_id, role, profile_revision_id, profile_revision_sequence
    \\    ),
    \\    FOREIGN KEY (
    \\        profile_id, profile_revision_id, profile_revision_sequence
    \\    ) REFERENCES tax_profile_revisions(profile_id, id, sequence)
    \\        ON DELETE RESTRICT,
    \\    FOREIGN KEY (
    \\        profile_id, profile_revision_id, business_activity_id
    \\    ) REFERENCES tax_profile_business_activities(
    \\        profile_id, revision_id, id
    \\    )
    \\        ON DELETE RESTRICT
    \\);
    \\CREATE INDEX tax_form_draft_role_profile_idx
    \\    ON tax_form_draft_role_bindings(
    \\        profile_id, profile_revision_id, profile_revision_sequence
    \\    );
    \\
    \\CREATE TABLE tax_form_draft_snapshot_fields (
    \\    draft_id TEXT NOT NULL,
    \\    role TEXT NOT NULL,
    \\    field_id TEXT NOT NULL CHECK (length(trim(field_id)) > 0),
    \\    reusable_field TEXT NOT NULL
    \\        CHECK (length(trim(reusable_field)) > 0),
    \\    value_type TEXT NOT NULL CHECK (length(trim(value_type)) > 0),
    \\    value_text TEXT NOT NULL,
    \\    provenance TEXT NOT NULL CHECK (length(trim(provenance)) > 0),
    \\    profile_revision_id TEXT NOT NULL,
    \\    profile_revision_sequence INTEGER NOT NULL CHECK (
    \\        profile_revision_sequence > 0 AND
    \\        profile_revision_sequence <= 4294967295
    \\    ),
    \\    revision_source_tag TEXT NOT NULL CHECK (
    \\        revision_source_tag IN ('manual_entry', 'imported', 'migrated')
    \\    ),
    \\    revision_source_reference TEXT,
    \\    business_activity_id TEXT,
    \\    registration_fact_id TEXT,
    \\    overridden INTEGER NOT NULL DEFAULT 0
    \\        CHECK (overridden IN (0, 1)),
    \\    PRIMARY KEY (draft_id, field_id),
    \\    FOREIGN KEY (
    \\        draft_id, role, profile_revision_id, profile_revision_sequence
    \\    )
    \\        REFERENCES tax_form_draft_role_bindings(
    \\            draft_id, role, profile_revision_id,
    \\            profile_revision_sequence
    \\        ) ON DELETE CASCADE
    \\    ,
    \\    CHECK (
    \\        (revision_source_tag = 'manual_entry' AND
    \\            revision_source_reference IS NULL) OR
    \\        (revision_source_tag IN ('imported', 'migrated') AND
    \\            length(trim(revision_source_reference)) > 0)
    \\    )
    \\);
    \\
    \\CREATE TRIGGER tax_form_draft_snapshot_fields_immutable
    \\BEFORE UPDATE ON tax_form_draft_snapshot_fields
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'prefill snapshots are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_form_draft_snapshot_activity_valid
    \\BEFORE INSERT ON tax_form_draft_snapshot_fields
    \\WHEN NEW.business_activity_id IS NOT NULL AND NOT EXISTS (
    \\    SELECT 1
    \\    FROM tax_form_draft_role_bindings AS b
    \\    JOIN tax_profile_business_activities AS a
    \\      ON a.profile_id = b.profile_id
    \\     AND a.revision_id = b.profile_revision_id
    \\     AND a.id = NEW.business_activity_id
    \\    WHERE b.draft_id = NEW.draft_id
    \\      AND b.role = NEW.role
    \\      AND b.profile_revision_id = NEW.profile_revision_id
    \\      AND b.profile_revision_sequence =
    \\          NEW.profile_revision_sequence
    \\      AND b.business_activity_id = NEW.business_activity_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'invalid snapshot business activity');
    \\END;
    \\
    \\CREATE TRIGGER tax_form_draft_snapshot_fact_valid
    \\BEFORE INSERT ON tax_form_draft_snapshot_fields
    \\WHEN NEW.registration_fact_id IS NOT NULL AND NOT EXISTS (
    \\    SELECT 1
    \\    FROM tax_form_draft_role_bindings AS b
    \\    JOIN tax_profile_registration_facts AS f
    \\      ON f.profile_id = b.profile_id
    \\     AND f.revision_id = b.profile_revision_id
    \\     AND f.id = NEW.registration_fact_id
    \\    WHERE b.draft_id = NEW.draft_id
    \\      AND b.role = NEW.role
    \\      AND b.profile_revision_id = NEW.profile_revision_id
    \\      AND b.profile_revision_sequence =
    \\          NEW.profile_revision_sequence
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'invalid snapshot registration fact');
    \\END;
    \\
    \\CREATE TABLE tax_form_draft_values (
    \\    draft_id TEXT NOT NULL
    \\        REFERENCES tax_form_drafts(id) ON DELETE CASCADE,
    \\    field_id TEXT NOT NULL CHECK (length(trim(field_id)) > 0),
    \\    value_text TEXT NOT NULL,
    \\    provenance TEXT NOT NULL CHECK (length(trim(provenance)) > 0),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (draft_id, field_id)
    \\);
;

const schema_v2 =
    \\CREATE TRIGGER tax_profile_revisions_delete_guard
    \\BEFORE DELETE ON tax_profile_revisions
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'tax profile revisions are append-only');
    \\END;
    \\
    \\CREATE TRIGGER tax_profile_business_activities_delete_guard
    \\BEFORE DELETE ON tax_profile_business_activities
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'business activities are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_profile_registration_facts_delete_guard
    \\BEFORE DELETE ON tax_profile_registration_facts
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'registration facts are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_form_draft_role_bindings_update_guard
    \\BEFORE UPDATE ON tax_form_draft_role_bindings
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'profile role bindings are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_form_draft_role_bindings_delete_guard
    \\BEFORE DELETE ON tax_form_draft_role_bindings
    \\WHEN EXISTS (
    \\    SELECT 1 FROM tax_form_drafts WHERE id = OLD.draft_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'profile role bindings are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_form_draft_snapshot_fields_delete_guard
    \\BEFORE DELETE ON tax_form_draft_snapshot_fields
    \\WHEN EXISTS (
    \\    SELECT 1 FROM tax_form_drafts WHERE id = OLD.draft_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'prefill snapshots are immutable');
    \\END;
;

const schema_v3 =
    \\CREATE TABLE IF NOT EXISTS tax_profile_identity_anchors (
    \\    profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE RESTRICT,
    \\    sequence INTEGER NOT NULL CHECK (
    \\        sequence > 0 AND sequence <= 4294967295
    \\    ),
    \\    jurisdiction TEXT NOT NULL
    \\        CHECK (jurisdiction = 'philippines'),
    \\    tax_authority TEXT NOT NULL
    \\        CHECK (tax_authority = 'bureau_of_internal_revenue'),
    \\    canonical_tin TEXT NOT NULL CHECK (
    \\        length(canonical_tin) IN (9, 12, 13, 14) AND
    \\        canonical_tin NOT GLOB '*[^0-9]*'
    \\    ),
    \\    legal_person_class TEXT NOT NULL CHECK (
    \\        legal_person_class IN (
    \\            'natural_person', 'juridical_person', 'estate', 'trust',
    \\            'reviewed_other'
    \\        )
    \\    ),
    \\    established_from_revision_id TEXT,
    \\    identity_correction_id TEXT,
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (profile_id, sequence),
    \\    UNIQUE (identity_correction_id),
    \\    FOREIGN KEY (profile_id, established_from_revision_id)
    \\        REFERENCES tax_profile_revisions(profile_id, id)
    \\        ON DELETE RESTRICT,
    \\    FOREIGN KEY (profile_id, identity_correction_id)
    \\        REFERENCES tax_profile_identity_corrections(profile_id, id)
    \\        ON DELETE RESTRICT
    \\        DEFERRABLE INITIALLY DEFERRED,
    \\    CHECK (
    \\        (sequence = 1 AND
    \\            established_from_revision_id IS NOT NULL AND
    \\            identity_correction_id IS NULL) OR
    \\        (sequence > 1 AND
    \\            established_from_revision_id IS NULL AND
    \\            identity_correction_id IS NOT NULL)
    \\    )
    \\);
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_identity_anchors_update_guard
    \\BEFORE UPDATE ON tax_profile_identity_anchors
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'taxpayer identity anchors are immutable');
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_identity_anchors_delete_guard
    \\BEFORE DELETE ON tax_profile_identity_anchors
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'taxpayer identity anchors are immutable');
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_revision_first_anchor_guard
    \\BEFORE INSERT ON tax_profile_revisions
    \\WHEN NOT EXISTS (
    \\    SELECT 1 FROM tax_profile_identity_anchors
    \\    WHERE profile_id = NEW.profile_id
    \\) AND NEW.sequence <> 1
    \\BEGIN
    \\    SELECT RAISE(
    \\        ABORT,
    \\        'first profile revision must establish identity at sequence 1'
    \\    );
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_revision_identity_guard
    \\BEFORE INSERT ON tax_profile_revisions
    \\WHEN EXISTS (
    \\    SELECT 1 FROM tax_profile_identity_anchors
    \\    WHERE profile_id = NEW.profile_id
    \\) AND (
    \\    replace(replace(replace(replace(replace(replace(replace(
    \\        NEW.tin, '-', ''), ' ', ''), char(9), ''),
    \\        char(10), ''), char(11), ''), char(12), ''),
    \\        char(13), '') <> (
    \\        SELECT canonical_tin
    \\        FROM tax_profile_identity_anchors
    \\        WHERE profile_id = NEW.profile_id
    \\        ORDER BY sequence DESC
    \\        LIMIT 1
    \\    ) OR
    \\    CASE
    \\        WHEN NEW.subject_kind IN (
    \\            'individual', 'sole_proprietor'
    \\        ) THEN 'natural_person'
    \\        WHEN NEW.subject_kind IN (
    \\            'corporation', 'partnership'
    \\        ) THEN 'juridical_person'
    \\        WHEN NEW.subject_kind = 'estate' THEN 'estate'
    \\        WHEN NEW.subject_kind = 'trust' THEN 'trust'
    \\        ELSE 'reviewed_other'
    \\    END <> (
    \\        SELECT legal_person_class
    \\        FROM tax_profile_identity_anchors
    \\        WHERE profile_id = NEW.profile_id
    \\        ORDER BY sequence DESC
    \\        LIMIT 1
    \\    )
    \\)
    \\BEGIN
    \\    SELECT RAISE(
    \\        ABORT,
    \\        'ordinary revision changes canonical taxpayer identity'
    \\    );
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_revision_anchor_initialize
    \\AFTER INSERT ON tax_profile_revisions
    \\WHEN NOT EXISTS (
    \\    SELECT 1 FROM tax_profile_identity_anchors
    \\    WHERE profile_id = NEW.profile_id
    \\)
    \\BEGIN
    \\    INSERT INTO tax_profile_identity_anchors (
    \\        profile_id, sequence, jurisdiction, tax_authority,
    \\        canonical_tin, legal_person_class,
    \\        established_from_revision_id, identity_correction_id
    \\    ) VALUES (
    \\        NEW.profile_id, 1, 'philippines',
    \\        'bureau_of_internal_revenue',
    \\        replace(replace(replace(replace(replace(replace(replace(
    \\            NEW.tin, '-', ''), ' ', ''), char(9), ''),
    \\            char(10), ''), char(11), ''), char(12), ''),
    \\            char(13), ''),
    \\        CASE
    \\            WHEN NEW.subject_kind IN (
    \\                'individual', 'sole_proprietor'
    \\            ) THEN 'natural_person'
    \\            WHEN NEW.subject_kind IN (
    \\                'corporation', 'partnership'
    \\            ) THEN 'juridical_person'
    \\            WHEN NEW.subject_kind = 'estate' THEN 'estate'
    \\            WHEN NEW.subject_kind = 'trust' THEN 'trust'
    \\            ELSE 'reviewed_other'
    \\        END,
    \\        NEW.id, NULL
    \\    );
    \\END;
    \\
    \\CREATE TABLE IF NOT EXISTS tax_profile_identity_corrections (
    \\    id TEXT PRIMARY KEY
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE RESTRICT,
    \\    old_anchor_sequence INTEGER NOT NULL,
    \\    new_anchor_sequence INTEGER NOT NULL,
    \\    old_canonical_tin TEXT NOT NULL,
    \\    new_canonical_tin TEXT NOT NULL,
    \\    old_legal_person_class TEXT NOT NULL,
    \\    new_legal_person_class TEXT NOT NULL,
    \\    reason TEXT NOT NULL CHECK (length(trim(reason)) > 0),
    \\    actor_reference TEXT NOT NULL
    \\        CHECK (length(trim(actor_reference)) > 0),
    \\    recorded_at_unix_seconds INTEGER NOT NULL,
    \\    provenance TEXT NOT NULL CHECK (length(trim(provenance)) > 0),
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    UNIQUE (profile_id, id),
    \\    UNIQUE (profile_id, new_anchor_sequence),
    \\    FOREIGN KEY (profile_id, old_anchor_sequence)
    \\        REFERENCES tax_profile_identity_anchors(profile_id, sequence)
    \\        ON DELETE RESTRICT,
    \\    FOREIGN KEY (profile_id, new_anchor_sequence)
    \\        REFERENCES tax_profile_identity_anchors(profile_id, sequence)
    \\        ON DELETE RESTRICT,
    \\    CHECK (new_anchor_sequence = old_anchor_sequence + 1),
    \\    CHECK (
    \\        old_canonical_tin <> new_canonical_tin OR
    \\        old_legal_person_class <> new_legal_person_class
    \\    )
    \\);
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_identity_correction_match
    \\BEFORE INSERT ON tax_profile_identity_corrections
    \\WHEN NOT EXISTS (
    \\    SELECT 1
    \\    FROM tax_profile_identity_anchors AS old_anchor
    \\    JOIN tax_profile_identity_anchors AS new_anchor
    \\      ON new_anchor.profile_id = old_anchor.profile_id
    \\    WHERE old_anchor.profile_id = NEW.profile_id
    \\      AND old_anchor.sequence = NEW.old_anchor_sequence
    \\      AND new_anchor.sequence = NEW.new_anchor_sequence
    \\      AND old_anchor.canonical_tin = NEW.old_canonical_tin
    \\      AND new_anchor.canonical_tin = NEW.new_canonical_tin
    \\      AND old_anchor.legal_person_class =
    \\          NEW.old_legal_person_class
    \\      AND new_anchor.legal_person_class =
    \\          NEW.new_legal_person_class
    \\      AND new_anchor.identity_correction_id = NEW.id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'identity correction does not match anchors');
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_identity_corrections_update_guard
    \\BEFORE UPDATE ON tax_profile_identity_corrections
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'identity corrections are immutable');
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_identity_corrections_delete_guard
    \\BEFORE DELETE ON tax_profile_identity_corrections
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'identity corrections are immutable');
    \\END;
    \\
    \\CREATE TABLE IF NOT EXISTS tax_profile_civil_status_revisions (
    \\    profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE RESTRICT,
    \\    sequence INTEGER NOT NULL CHECK (
    \\        sequence > 0 AND sequence <= 4294967295
    \\    ),
    \\    effective_from TEXT NOT NULL,
    \\    effective_until TEXT,
    \\    status TEXT NOT NULL CHECK (status IN ('single', 'married')),
    \\    source_tag TEXT NOT NULL CHECK (
    \\        source_tag IN ('manual_entry', 'imported', 'migrated')
    \\    ),
    \\    source_reference TEXT,
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (profile_id, sequence),
    \\    CHECK (
    \\        effective_until IS NULL OR effective_from <= effective_until
    \\    ),
    \\    CHECK (
    \\        (source_tag = 'manual_entry' AND
    \\            source_reference IS NULL) OR
    \\        (source_tag IN ('imported', 'migrated') AND
    \\            length(trim(source_reference)) > 0)
    \\    )
    \\);
    \\CREATE INDEX IF NOT EXISTS tax_profile_civil_status_effective_idx
    \\    ON tax_profile_civil_status_revisions(
    \\        profile_id, effective_from, effective_until, sequence
    \\    );
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_civil_status_anchor_guard
    \\BEFORE INSERT ON tax_profile_civil_status_revisions
    \\WHEN NOT EXISTS (
    \\    SELECT 1 FROM tax_profile_identity_anchors
    \\    WHERE profile_id = NEW.profile_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'civil status requires identity anchor');
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_civil_status_sequence_guard
    \\BEFORE INSERT ON tax_profile_civil_status_revisions
    \\WHEN NEW.sequence <> (
    \\    SELECT COALESCE(MAX(sequence), 0) + 1
    \\    FROM tax_profile_civil_status_revisions
    \\    WHERE profile_id = NEW.profile_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'civil status sequence must be contiguous');
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_civil_status_update_guard
    \\BEFORE UPDATE ON tax_profile_civil_status_revisions
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'civil status revisions are immutable');
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_civil_status_delete_guard
    \\BEFORE DELETE ON tax_profile_civil_status_revisions
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'civil status revisions are immutable');
    \\END;
    \\
    \\CREATE TABLE IF NOT EXISTS tax_profile_relationships (
    \\    id TEXT PRIMARY KEY
    \\        CHECK (length(id) BETWEEN 1 AND 64 AND id = trim(id)),
    \\    from_profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE RESTRICT,
    \\    to_profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE RESTRICT,
    \\    kind TEXT NOT NULL CHECK (kind IN (
    \\        'spouse_of', 'predecessor_of', 'successor_of',
    \\        'business_converted_to'
    \\    )),
    \\    effective_from TEXT NOT NULL,
    \\    effective_until TEXT,
    \\    provenance TEXT NOT NULL CHECK (length(trim(provenance)) > 0),
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    CHECK (from_profile_id <> to_profile_id),
    \\    CHECK (
    \\        effective_until IS NULL OR effective_from <= effective_until
    \\    )
    \\);
    \\CREATE INDEX IF NOT EXISTS tax_profile_relationships_from_idx
    \\    ON tax_profile_relationships(
    \\        from_profile_id, effective_from, effective_until
    \\    );
    \\CREATE INDEX IF NOT EXISTS tax_profile_relationships_to_idx
    \\    ON tax_profile_relationships(
    \\        to_profile_id, effective_from, effective_until
    \\    );
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_relationship_anchor_guard
    \\BEFORE INSERT ON tax_profile_relationships
    \\WHEN NOT EXISTS (
    \\    SELECT 1 FROM tax_profile_identity_anchors
    \\    WHERE profile_id = NEW.from_profile_id
    \\) OR NOT EXISTS (
    \\    SELECT 1 FROM tax_profile_identity_anchors
    \\    WHERE profile_id = NEW.to_profile_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'relationship requires identity anchors');
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_relationship_class_guard
    \\BEFORE INSERT ON tax_profile_relationships
    \\WHEN (
    \\    NEW.kind = 'spouse_of' AND (
    \\        (SELECT legal_person_class
    \\         FROM tax_profile_identity_anchors
    \\         WHERE profile_id = NEW.from_profile_id
    \\         ORDER BY sequence DESC LIMIT 1) <> 'natural_person' OR
    \\        (SELECT legal_person_class
    \\         FROM tax_profile_identity_anchors
    \\         WHERE profile_id = NEW.to_profile_id
    \\         ORDER BY sequence DESC LIMIT 1) <> 'natural_person'
    \\    )
    \\) OR (
    \\    NEW.kind = 'business_converted_to' AND (
    \\        (SELECT legal_person_class
    \\         FROM tax_profile_identity_anchors
    \\         WHERE profile_id = NEW.from_profile_id
    \\         ORDER BY sequence DESC LIMIT 1) <> 'natural_person' OR
    \\        (SELECT legal_person_class
    \\         FROM tax_profile_identity_anchors
    \\         WHERE profile_id = NEW.to_profile_id
    \\         ORDER BY sequence DESC LIMIT 1) <> 'juridical_person'
    \\    )
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'invalid relationship identity classes');
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_relationships_update_guard
    \\BEFORE UPDATE ON tax_profile_relationships
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'profile relationships are immutable');
    \\END;
    \\
    \\CREATE TRIGGER IF NOT EXISTS tax_profile_relationships_delete_guard
    \\BEFORE DELETE ON tax_profile_relationships
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'profile relationships are immutable');
    \\END;
;

// The exact-draft portion of v4 is still unreleased. Its validation-evidence
// columns are therefore part of the original v4 contract, not a post-release
// ALTER migration. Any pre-release database created from an older draft of
// v4 must be recreated rather than silently accepting provenance-incomplete
// rows.
const schema_v4 =
    \\CREATE TABLE tax_exact_draft_streams (
    \\    workspace_id BLOB NOT NULL CHECK (
    \\        typeof(workspace_id) = 'blob' AND
    \\        length(workspace_id) = 16 AND
    \\        workspace_id <> zeroblob(16)
    \\    ),
    \\    filing_business_key_digest BLOB NOT NULL CHECK (
    \\        typeof(filing_business_key_digest) = 'blob' AND
    \\        length(filing_business_key_digest) = 32
    \\    ),
    \\    filer_profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE RESTRICT,
    \\    form_code TEXT NOT NULL CHECK (length(trim(form_code)) > 0),
    \\    form_revision TEXT NOT NULL CHECK (
    \\        length(trim(form_revision)) > 0
    \\    ),
    \\    period_key TEXT NOT NULL CHECK (length(trim(period_key)) > 0),
    \\    filing_intent TEXT NOT NULL CHECK (
    \\        filing_intent IN ('original', 'amended')
    \\    ),
    \\    exact_schema_digest BLOB NOT NULL CHECK (
    \\        typeof(exact_schema_digest) = 'blob' AND
    \\        length(exact_schema_digest) = 32
    \\    ),
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (workspace_id, exact_schema_digest)
    \\);
    \\CREATE INDEX tax_exact_draft_filing_key_idx
    \\    ON tax_exact_draft_streams(
    \\        filing_business_key_digest, filer_profile_id, form_code,
    \\        form_revision, period_key, filing_intent
    \\    );
    \\
    \\CREATE TRIGGER tax_exact_draft_streams_identity_guard
    \\BEFORE INSERT ON tax_exact_draft_streams
    \\WHEN EXISTS (
    \\    SELECT 1
    \\    FROM tax_exact_draft_streams AS existing
    \\    WHERE existing.workspace_id = NEW.workspace_id
    \\      AND (
    \\          existing.filing_business_key_digest <>
    \\              NEW.filing_business_key_digest OR
    \\          existing.filer_profile_id <> NEW.filer_profile_id OR
    \\          existing.form_code <> NEW.form_code OR
    \\          existing.form_revision <> NEW.form_revision OR
    \\          existing.period_key <> NEW.period_key OR
    \\          existing.filing_intent <> NEW.filing_intent
    \\      )
    \\)
    \\BEGIN
    \\    SELECT RAISE(
    \\        ABORT,
    \\        'one draft workspace cannot represent different filings'
    \\    );
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_streams_update_guard
    \\BEFORE UPDATE ON tax_exact_draft_streams
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft streams are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_streams_delete_guard
    \\BEFORE DELETE ON tax_exact_draft_streams
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft streams are immutable');
    \\END;
    \\
    \\CREATE TABLE tax_exact_draft_revisions (
    \\    workspace_id BLOB NOT NULL,
    \\    revision INTEGER NOT NULL CHECK (
    \\        revision BETWEEN 1 AND 64
    \\    ),
    \\    parent_revision INTEGER,
    \\    profile_as_of TEXT NOT NULL,
    \\    recorded_at_unix_seconds INTEGER NOT NULL CHECK (
    \\        recorded_at_unix_seconds > 0
    \\    ),
    \\    package_form_code TEXT NOT NULL CHECK (
    \\        length(trim(package_form_code)) > 0
    \\    ),
    \\    package_form_revision TEXT NOT NULL CHECK (
    \\        length(trim(package_form_revision)) > 0
    \\    ),
    \\    locale TEXT NOT NULL CHECK (locale = 'en_PH'),
    \\    offline_package_version TEXT NOT NULL CHECK (
    \\        offline_package_version = 'ebirforms_7_9_6'
    \\    ),
    \\    payload_schema_token TEXT NOT NULL CHECK (
    \\        payload_schema_token = 'form_1701q_v2018'
    \\    ),
    \\    offline_package_sha256 BLOB NOT NULL CHECK (
    \\        typeof(offline_package_sha256) = 'blob' AND
    \\        length(offline_package_sha256) = 32
    \\    ),
    \\    primary_source_sha256 BLOB NOT NULL CHECK (
    \\        typeof(primary_source_sha256) = 'blob' AND
    \\        length(primary_source_sha256) = 32
    \\    ),
    \\    dependency_manifest_sha256 BLOB NOT NULL CHECK (
    \\        typeof(dependency_manifest_sha256) = 'blob' AND
    \\        length(dependency_manifest_sha256) = 32
    \\    ),
    \\    official_pdf_sha256 BLOB CHECK (
    \\        official_pdf_sha256 IS NULL OR (
    \\            typeof(official_pdf_sha256) = 'blob' AND
    \\            length(official_pdf_sha256) = 32
    \\        )
    \\    ),
    \\    official_guide_sha256 BLOB CHECK (
    \\        official_guide_sha256 IS NULL OR (
    \\            typeof(official_guide_sha256) = 'blob' AND
    \\            length(official_guide_sha256) = 32
    \\        )
    \\    ),
    \\    codec_version TEXT CHECK (
    \\        codec_version IS NULL OR
    \\        codec_version = 'legacy_1701q_v2018_v1'
    \\    ),
    \\    package_digest BLOB NOT NULL CHECK (
    \\        typeof(package_digest) = 'blob' AND
    \\        length(package_digest) = 32
    \\    ),
    \\    occurrence_manifest_digest BLOB NOT NULL CHECK (
    \\        typeof(occurrence_manifest_digest) = 'blob' AND
    \\        length(occurrence_manifest_digest) = 32
    \\    ),
    \\    exact_schema_digest BLOB NOT NULL CHECK (
    \\        typeof(exact_schema_digest) = 'blob' AND
    \\        length(exact_schema_digest) = 32
    \\    ),
    \\    payload_shape TEXT NOT NULL CHECK (
    \\        payload_shape IN ('editable_save', 'final_copy_plaintext')
    \\    ),
    \\    occurrence_count INTEGER NOT NULL CHECK (
    \\        occurrence_count > 0 AND occurrence_count <= 65535
    \\    ),
    \\    readiness_identity_resolved INTEGER NOT NULL CHECK (
    \\        readiness_identity_resolved IN (0, 1)
    \\    ),
    \\    readiness_dependency_closure INTEGER NOT NULL CHECK (
    \\        readiness_dependency_closure IN (0, 1)
    \\    ),
    \\    readiness_profile_mapping_reviewed INTEGER NOT NULL CHECK (
    \\        readiness_profile_mapping_reviewed IN (0, 1)
    \\    ),
    \\    readiness_calculation_reconciled INTEGER NOT NULL CHECK (
    \\        readiness_calculation_reconciled IN (0, 1)
    \\    ),
    \\    readiness_validation_reconciled INTEGER NOT NULL CHECK (
    \\        readiness_validation_reconciled IN (0, 1)
    \\    ),
    \\    readiness_editable_serializer_exact INTEGER NOT NULL CHECK (
    \\        readiness_editable_serializer_exact IN (0, 1)
    \\    ),
    \\    readiness_final_plaintext_serializer_exact INTEGER NOT NULL CHECK (
    \\        readiness_final_plaintext_serializer_exact IN (0, 1)
    \\    ),
    \\    readiness_decrypt_codec_qualified INTEGER NOT NULL CHECK (
    \\        readiness_decrypt_codec_qualified IN (0, 1)
    \\    ),
    \\    readiness_encrypt_codec_qualified INTEGER NOT NULL CHECK (
    \\        readiness_encrypt_codec_qualified IN (0, 1)
    \\    ),
    \\    readiness_persistence_integrated INTEGER NOT NULL CHECK (
    \\        readiness_persistence_integrated IN (0, 1)
    \\    ),
    \\    readiness_ui_integrated INTEGER NOT NULL CHECK (
    \\        readiness_ui_integrated IN (0, 1)
    \\    ),
    \\    readiness_offline_package_verified INTEGER NOT NULL CHECK (
    \\        readiness_offline_package_verified IN (0, 1)
    \\    ),
    \\    profile_snapshot_digest BLOB NOT NULL CHECK (
    \\        typeof(profile_snapshot_digest) = 'blob' AND
    \\        length(profile_snapshot_digest) = 32
    \\    ),
    \\    transaction_state_digest BLOB NOT NULL CHECK (
    \\        typeof(transaction_state_digest) = 'blob' AND
    \\        length(transaction_state_digest) = 32
    \\    ),
    \\    ordered_values_digest BLOB NOT NULL CHECK (
    \\        typeof(ordered_values_digest) = 'blob' AND
    \\        length(ordered_values_digest) = 32
    \\    ),
    \\    validation_current_year INTEGER NOT NULL CHECK (
    \\        validation_current_year BETWEEN -2147483648 AND 2147483647
    \\    ),
    \\    spouse_tin_checksum TEXT NOT NULL CHECK (
    \\        spouse_tin_checksum IN (
    \\            'not_evaluated', 'valid', 'invalid'
    \\        )
    \\    ),
    \\    save_gate_status TEXT NOT NULL CHECK (
    \\        save_gate_status IN ('not_run', 'failed', 'passed')
    \\    ),
    \\    save_gate_rule INTEGER,
    \\    full_validation_status TEXT NOT NULL CHECK (
    \\        full_validation_status IN (
    \\            'not_run', 'blocked', 'failed', 'passed'
    \\        )
    \\    ),
    \\    full_validation_code INTEGER,
    \\    artifact_status TEXT NOT NULL CHECK (
    \\        artifact_status IN (
    \\            'not_generated', 'plaintext_candidate', 'plaintext_exact'
    \\        )
    \\    ),
    \\    artifact_marker TEXT CHECK (
    \\        artifact_marker IS NULL OR
    \\        artifact_marker IN ('editable', 'final')
    \\    ),
    \\    artifact_byte_length INTEGER CHECK (
    \\        artifact_byte_length IS NULL OR
    \\        artifact_byte_length BETWEEN 1 AND 4294967295
    \\    ),
    \\    artifact_sha256 BLOB CHECK (
    \\        artifact_sha256 IS NULL OR (
    \\            typeof(artifact_sha256) = 'blob' AND
    \\            length(artifact_sha256) = 32
    \\        )
    \\    ),
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (workspace_id, exact_schema_digest, revision),
    \\    FOREIGN KEY (workspace_id, exact_schema_digest)
    \\        REFERENCES tax_exact_draft_streams(
    \\            workspace_id, exact_schema_digest
    \\        ) ON DELETE RESTRICT,
    \\    FOREIGN KEY (
    \\        workspace_id, exact_schema_digest, parent_revision
    \\    )
    \\        REFERENCES tax_exact_draft_revisions(
    \\            workspace_id, exact_schema_digest, revision
    \\        )
    \\        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    \\    CHECK (
    \\        (revision = 1 AND parent_revision IS NULL) OR
    \\        (revision > 1 AND parent_revision = revision - 1)
    \\    ),
    \\    CHECK (
    \\        (save_gate_status IN ('not_run', 'passed') AND
    \\            save_gate_rule IS NULL) OR
    \\        (save_gate_status = 'failed' AND
    \\            save_gate_rule BETWEEN 1 AND 4)
    \\    ),
    \\    CHECK (
    \\        (full_validation_status IN ('not_run', 'passed') AND
    \\            full_validation_code IS NULL) OR
    \\        (full_validation_status = 'failed' AND
    \\            full_validation_code BETWEEN 1 AND 25) OR
    \\        (full_validation_status = 'blocked' AND
    \\            full_validation_code = 0)
    \\    ),
    \\    CHECK (
    \\        (artifact_status = 'not_generated' AND
    \\            artifact_marker IS NULL AND
    \\            artifact_byte_length IS NULL AND
    \\            artifact_sha256 IS NULL) OR
    \\        (artifact_status IN (
    \\            'plaintext_candidate', 'plaintext_exact'
    \\        ) AND artifact_marker IS NOT NULL AND
    \\            artifact_byte_length IS NOT NULL AND
    \\            artifact_sha256 IS NOT NULL)
    \\    )
    \\);
    \\
    \\CREATE TABLE tax_exact_draft_revision_bindings (
    \\    workspace_id BLOB NOT NULL,
    \\    exact_schema_digest BLOB NOT NULL CHECK (
    \\        typeof(exact_schema_digest) = 'blob' AND
    \\        length(exact_schema_digest) = 32
    \\    ),
    \\    revision INTEGER NOT NULL,
    \\    role TEXT NOT NULL CHECK (role IN ('filer', 'spouse')),
    \\    instance_id TEXT NOT NULL CHECK (
    \\        length(instance_id) BETWEEN 1 AND 64 AND
    \\        instance_id = trim(instance_id)
    \\    ),
    \\    profile_id TEXT NOT NULL,
    \\    profile_revision_id TEXT NOT NULL,
    \\    profile_revision_sequence INTEGER NOT NULL CHECK (
    \\        profile_revision_sequence > 0 AND
    \\        profile_revision_sequence <= 4294967295
    \\    ),
    \\    business_activity_id TEXT,
    \\    provenance TEXT NOT NULL CHECK (
    \\        length(trim(provenance)) > 0 AND
    \\        length(CAST(provenance AS BLOB)) <= 4096
    \\    ),
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (
    \\        workspace_id, exact_schema_digest, revision, role, instance_id
    \\    ),
    \\    FOREIGN KEY (workspace_id, exact_schema_digest, revision)
    \\        REFERENCES tax_exact_draft_revisions(
    \\            workspace_id, exact_schema_digest, revision
    \\        )
    \\        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    \\    FOREIGN KEY (
    \\        profile_id, profile_revision_id, profile_revision_sequence
    \\    ) REFERENCES tax_profile_revisions(profile_id, id, sequence)
    \\        ON DELETE RESTRICT,
    \\    FOREIGN KEY (
    \\        profile_id, profile_revision_id, business_activity_id
    \\    ) REFERENCES tax_profile_business_activities(
    \\        profile_id, revision_id, id
    \\    ) ON DELETE RESTRICT
    \\);
    \\CREATE INDEX tax_exact_draft_binding_profile_idx
    \\    ON tax_exact_draft_revision_bindings(
    \\        profile_id, profile_revision_id, profile_revision_sequence
    \\    );
    \\
    \\CREATE TABLE tax_exact_draft_occurrences (
    \\    workspace_id BLOB NOT NULL,
    \\    exact_schema_digest BLOB NOT NULL CHECK (
    \\        typeof(exact_schema_digest) = 'blob' AND
    \\        length(exact_schema_digest) = 32
    \\    ),
    \\    revision INTEGER NOT NULL,
    \\    ordinal INTEGER NOT NULL CHECK (
    \\        ordinal > 0 AND ordinal <= 65535
    \\    ),
    \\    serialized_key BLOB NOT NULL CHECK (
    \\        typeof(serialized_key) = 'blob' AND
    \\        length(serialized_key) BETWEEN 1 AND 256
    \\    ),
    \\    same_key_occurrence INTEGER NOT NULL CHECK (
    \\        same_key_occurrence > 0 AND same_key_occurrence <= 65535
    \\    ),
    \\    raw_value BLOB NOT NULL CHECK (
    \\        typeof(raw_value) = 'blob' AND
    \\        length(raw_value) <= 1048576
    \\    ),
    \\    normalized_value BLOB NOT NULL CHECK (
    \\        typeof(normalized_value) = 'blob' AND
    \\        length(normalized_value) <= 1048576
    \\    ),
    \\    emitted_value BLOB NOT NULL CHECK (
    \\        typeof(emitted_value) = 'blob' AND
    \\        length(emitted_value) <= 1048576
    \\    ),
    \\    origin TEXT NOT NULL CHECK (origin IN (
    \\        'profile', 'transaction', 'preparer', 'filing_context',
    \\        'external_evidence', 'derived', 'system'
    \\    )),
    \\    provenance TEXT NOT NULL CHECK (
    \\        length(trim(provenance)) > 0 AND
    \\        length(CAST(provenance AS BLOB)) <= 4096
    \\    ),
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (
    \\        workspace_id, exact_schema_digest, revision, ordinal
    \\    ),
    \\    FOREIGN KEY (workspace_id, exact_schema_digest, revision)
    \\        REFERENCES tax_exact_draft_revisions(
    \\            workspace_id, exact_schema_digest, revision
    \\        )
    \\        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
    \\);
    \\
    \\CREATE TRIGGER tax_exact_draft_revision_sequence_guard
    \\BEFORE INSERT ON tax_exact_draft_revisions
    \\WHEN NEW.revision <> (
    \\    SELECT COALESCE(MAX(revision), 0) + 1
    \\    FROM tax_exact_draft_revisions
    \\    WHERE workspace_id = NEW.workspace_id
    \\      AND exact_schema_digest = NEW.exact_schema_digest
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft revision must be contiguous');
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_revision_schema_guard
    \\BEFORE INSERT ON tax_exact_draft_revisions
    \\WHEN NOT EXISTS (
    \\    SELECT 1
    \\    FROM tax_exact_draft_streams AS w
    \\    WHERE w.workspace_id = NEW.workspace_id
    \\      AND w.exact_schema_digest = NEW.exact_schema_digest
    \\      AND w.form_code = NEW.package_form_code
    \\      AND w.form_revision = NEW.package_form_revision
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft schema does not match workspace');
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_revision_occurrence_guard
    \\BEFORE INSERT ON tax_exact_draft_revisions
    \\WHEN (
    \\    SELECT COUNT(*)
    \\    FROM tax_exact_draft_occurrences AS o
    \\    WHERE o.workspace_id = NEW.workspace_id
    \\      AND o.exact_schema_digest = NEW.exact_schema_digest
    \\      AND o.revision = NEW.revision
    \\) <> NEW.occurrence_count OR (
    \\    SELECT COALESCE(MIN(ordinal), 0)
    \\    FROM tax_exact_draft_occurrences AS o
    \\    WHERE o.workspace_id = NEW.workspace_id
    \\      AND o.exact_schema_digest = NEW.exact_schema_digest
    \\      AND o.revision = NEW.revision
    \\) <> 1 OR (
    \\    SELECT COALESCE(MAX(ordinal), 0)
    \\    FROM tax_exact_draft_occurrences AS o
    \\    WHERE o.workspace_id = NEW.workspace_id
    \\      AND o.exact_schema_digest = NEW.exact_schema_digest
    \\      AND o.revision = NEW.revision
    \\) <> NEW.occurrence_count
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft occurrences are incomplete');
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_revision_binding_guard
    \\BEFORE INSERT ON tax_exact_draft_revisions
    \\WHEN (
    \\    SELECT COUNT(*)
    \\    FROM tax_exact_draft_revision_bindings AS b
    \\    WHERE b.workspace_id = NEW.workspace_id
    \\      AND b.exact_schema_digest = NEW.exact_schema_digest
    \\      AND b.revision = NEW.revision
    \\      AND b.role = 'filer'
    \\) <> 1 OR (
    \\    SELECT COUNT(*)
    \\    FROM tax_exact_draft_revision_bindings AS b
    \\    WHERE b.workspace_id = NEW.workspace_id
    \\      AND b.exact_schema_digest = NEW.exact_schema_digest
    \\      AND b.revision = NEW.revision
    \\      AND b.role = 'spouse'
    \\) > 1 OR EXISTS (
    \\    SELECT 1
    \\    FROM tax_exact_draft_revision_bindings AS filer
    \\    JOIN tax_exact_draft_streams AS w
    \\      ON w.workspace_id = filer.workspace_id
    \\     AND w.exact_schema_digest = filer.exact_schema_digest
    \\    WHERE filer.workspace_id = NEW.workspace_id
    \\      AND filer.exact_schema_digest = NEW.exact_schema_digest
    \\      AND filer.revision = NEW.revision
    \\      AND filer.role = 'filer'
    \\      AND filer.profile_id <> w.filer_profile_id
    \\) OR EXISTS (
    \\    SELECT 1
    \\    FROM tax_exact_draft_revision_bindings AS filer
    \\    JOIN tax_exact_draft_revision_bindings AS spouse
    \\      ON spouse.workspace_id = filer.workspace_id
    \\     AND spouse.exact_schema_digest = filer.exact_schema_digest
    \\     AND spouse.revision = filer.revision
    \\    WHERE filer.workspace_id = NEW.workspace_id
    \\      AND filer.exact_schema_digest = NEW.exact_schema_digest
    \\      AND filer.revision = NEW.revision
    \\      AND filer.role = 'filer'
    \\      AND spouse.role = 'spouse'
    \\      AND filer.profile_id = spouse.profile_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'invalid exact draft role bindings');
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_revisions_update_guard
    \\BEFORE UPDATE ON tax_exact_draft_revisions
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft revisions are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_revisions_delete_guard
    \\BEFORE DELETE ON tax_exact_draft_revisions
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft revisions are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_bindings_update_guard
    \\BEFORE UPDATE ON tax_exact_draft_revision_bindings
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft bindings are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_bindings_delete_guard
    \\BEFORE DELETE ON tax_exact_draft_revision_bindings
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft bindings are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_occurrences_update_guard
    \\BEFORE UPDATE ON tax_exact_draft_occurrences
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft occurrences are immutable');
    \\END;
    \\
    \\CREATE TRIGGER tax_exact_draft_occurrences_delete_guard
    \\BEFORE DELETE ON tax_exact_draft_occurrences
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'exact draft occurrences are immutable');
    \\END;
;

const schema_v5 =
    \\CREATE TABLE tax_profile_calendar_form_selections (
    \\    profile_id TEXT PRIMARY KEY
    \\        REFERENCES tax_profiles(id) ON DELETE CASCADE,
    \\    configured_at INTEGER NOT NULL DEFAULT (unixepoch())
    \\);
    \\
    \\CREATE TABLE tax_profile_calendar_form_selection_entries (
    \\    profile_id TEXT NOT NULL,
    \\    form_code TEXT NOT NULL CHECK (length(trim(form_code)) > 0),
    \\    PRIMARY KEY (profile_id, form_code),
    \\    FOREIGN KEY (profile_id)
    \\        REFERENCES tax_profile_calendar_form_selections(profile_id)
    \\        ON DELETE CASCADE
    \\);
;

/// Existing profiles retain the historical catalog fallback explicitly.
/// Profiles created after this migration default to needs-configuration.
/// Existing configured rows are classified without changing their entries.
const schema_v6 =
    \\CREATE TABLE tax_profile_local_owner (
    \\    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    \\    id TEXT NOT NULL UNIQUE CHECK (
    \\        length(id) = 32 AND id = lower(id)
    \\    ),
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch())
    \\);
    \\INSERT INTO tax_profile_local_owner(singleton, id)
    \\VALUES (1, lower(hex(randomblob(16))));
    \\ALTER TABLE tax_profiles ADD COLUMN owner_id TEXT;
    \\UPDATE tax_profiles
    \\SET owner_id = (SELECT id FROM tax_profile_local_owner
    \\                WHERE singleton = 1);
    \\CREATE INDEX tax_profiles_owner_idx ON tax_profiles(owner_id, id);
    \\CREATE TRIGGER tax_profiles_owner_insert_guard
    \\BEFORE INSERT ON tax_profiles
    \\WHEN NEW.owner_id IS NULL OR NEW.owner_id <> (
    \\    SELECT id FROM tax_profile_local_owner WHERE singleton = 1
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'profile owner is outside local scope');
    \\END;
    \\CREATE TRIGGER tax_profiles_owner_update_guard
    \\BEFORE UPDATE OF owner_id ON tax_profiles
    \\WHEN NEW.owner_id IS NULL OR NEW.owner_id <> OLD.owner_id
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'profile owner is immutable');
    \\END;
    \\ALTER TABLE tax_profiles ADD COLUMN
    \\    legacy_catalog_eligible INTEGER NOT NULL DEFAULT 0
    \\    CHECK (legacy_catalog_eligible IN (0, 1));
    \\UPDATE tax_profiles SET legacy_catalog_eligible = 1;
    \\ALTER TABLE tax_profile_form_sets ADD COLUMN
    \\    state TEXT NOT NULL DEFAULT 'active_nonempty';
    \\UPDATE tax_profile_form_sets
    \\SET state = CASE WHEN EXISTS (
    \\    SELECT 1 FROM tax_profile_form_set_entries AS entry
    \\    WHERE entry.profile_id = tax_profile_form_sets.profile_id
    \\      AND entry.tax_year = tax_profile_form_sets.tax_year
    \\) THEN 'active_nonempty' ELSE 'active_empty' END;
;

/// A durable reservation is required because calculating `MAX(period_key)`
/// and returning it without a write allows two processes to claim the same
/// occurrence. The profile FK owns deletion, while triggers enforce the
/// owner/profile scope and monotonic counter invariant.
const schema_v7 =
    \\CREATE TABLE tax_form_on_demand_occurrence_counters (
    \\    owner_id TEXT NOT NULL
    \\        REFERENCES tax_profile_local_owner(id) ON DELETE RESTRICT,
    \\    profile_id TEXT NOT NULL
    \\        REFERENCES tax_profiles(id) ON DELETE CASCADE,
    \\    form_code TEXT NOT NULL CHECK (length(trim(form_code)) > 0),
    \\    form_revision TEXT NOT NULL CHECK (
    \\        length(trim(form_revision)) > 0
    \\    ),
    \\    tax_year INTEGER NOT NULL CHECK (tax_year BETWEEN 1 AND 9999),
    \\    last_occurrence INTEGER NOT NULL CHECK (
    \\        last_occurrence BETWEEN 1 AND 999
    \\    ),
    \\    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch()),
    \\    PRIMARY KEY (
    \\        owner_id, profile_id, form_code, form_revision, tax_year
    \\    )
    \\);
    \\CREATE TRIGGER tax_form_on_demand_counter_owner_insert_guard
    \\BEFORE INSERT ON tax_form_on_demand_occurrence_counters
    \\WHEN NOT EXISTS (
    \\    SELECT 1 FROM tax_profiles AS profile
    \\    WHERE profile.id = NEW.profile_id
    \\      AND profile.owner_id = NEW.owner_id
    \\)
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'on-demand counter owner mismatch');
    \\END;
    \\CREATE TRIGGER tax_form_on_demand_counter_update_guard
    \\BEFORE UPDATE ON tax_form_on_demand_occurrence_counters
    \\WHEN NEW.owner_id <> OLD.owner_id
    \\  OR NEW.profile_id <> OLD.profile_id
    \\  OR NEW.form_code <> OLD.form_code
    \\  OR NEW.form_revision <> OLD.form_revision
    \\  OR NEW.tax_year <> OLD.tax_year
    \\  OR NEW.last_occurrence <= OLD.last_occurrence
    \\  OR NOT EXISTS (
    \\      SELECT 1 FROM tax_profiles AS profile
    \\      WHERE profile.id = NEW.profile_id
    \\        AND profile.owner_id = NEW.owner_id
    \\  )
    \\BEGIN
    \\    SELECT RAISE(ABORT, 'invalid on-demand counter update');
    \\END;
;

test "tax profile migration is namespaced idempotent and preserves user_version" {
    var store = try Store.openMemory(std.testing.allocator);
    defer store.close();

    try std.testing.expect(try store.foreignKeysEnabled());
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
    try store.exec("PRAGMA user_version = 73;");
    try store.migrate();
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());

    var user_version = try store.prepare("PRAGMA user_version;");
    defer user_version.deinit();
    try std.testing.expectEqual(StepResult.row, try user_version.step());
    try std.testing.expectEqual(
        @as(i64, 73),
        sqlite.sqlite3_column_int64(user_version.raw, 0),
    );
}

test "local owner is opaque stable and attached to new profiles" {
    var store = try Store.openMemory(std.testing.allocator);
    defer store.close();
    const before = try store.localOwnerId();
    try store.migrate();
    const after = try store.localOwnerId();
    try std.testing.expectEqualSlices(u8, &before, &after);

    const profile_id = "tax-profile-owned";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Owned Profile", "2026-01-01"),
        .{},
    );
    var owner = try store.prepare(
        "SELECT owner_id FROM tax_profiles WHERE id = ?;",
    );
    defer owner.deinit();
    try owner.bindText(1, profile_id);
    try std.testing.expectEqual(StepResult.row, try owner.step());
    try std.testing.expectEqualStrings(
        &before,
        columnText(owner.raw, 0).?,
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\INSERT INTO tax_profiles(id, status, owner_id)
            \\VALUES ('foreign-owner-profile', 'active',
            \\        'ffffffffffffffffffffffffffffffff');
        ),
    );
}

test "on-demand occurrence allocation is scoped monotonic and legacy aware" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();
    const owner = try store.localOwnerId();
    const profile_id = "tax-profile-on-demand-counter";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "On-demand Counter", "2026-01-01"),
        .{},
    );

    const base_scope: OnDemandOccurrenceScope = .{
        .owner_id = &owner,
        .profile_id = profile_id,
        .form_code = "0605",
        .form_revision = "2002-01",
        .tax_year = 2026,
    };
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.allocateOnDemandOccurrence(base_scope),
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        try store.allocateOnDemandOccurrence(base_scope),
    );

    var independent = base_scope;
    independent.tax_year = 2027;
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.allocateOnDemandOccurrence(independent),
    );
    independent = base_scope;
    independent.form_revision = "2026-01";
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.allocateOnDemandOccurrence(independent),
    );
    independent = base_scope;
    independent.form_code = "1905";
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.allocateOnDemandOccurrence(independent),
    );

    // A canonical draft created before the counter existed remains reserved.
    try store.createDraft(
        .{
            .id = "legacy-on-demand-seven",
            .form_code = "legacy-on-demand",
            .form_revision = "2018-01",
            .period_key = "2026-O007",
            .profile_as_of = testDate("2026-12-31"),
            .mapping_revision = "mapping-v1",
        },
        &.{.{
            .role = "filer",
            .profile_id = profile_id,
            .profile_revision_id = "revision-1",
            .profile_revision_sequence = 1,
        }},
        &.{},
        &.{},
    );
    try std.testing.expectEqual(
        @as(u32, 8),
        try store.allocateOnDemandOccurrence(.{
            .owner_id = &owner,
            .profile_id = profile_id,
            .form_code = "legacy-on-demand",
            .form_revision = "2018-01",
            .tax_year = 2026,
        }),
    );

    // A failed reservation rolls back instead of consuming a number.
    try store.exec(
        \\CREATE TRIGGER synthetic_on_demand_reservation_failure
        \\BEFORE INSERT ON tax_form_on_demand_occurrence_counters
        \\WHEN NEW.form_code = 'FAIL'
        \\BEGIN
        \\    SELECT RAISE(ABORT, 'synthetic reservation failure');
        \\END;
    );
    const failing_scope: OnDemandOccurrenceScope = .{
        .owner_id = &owner,
        .profile_id = profile_id,
        .form_code = "FAIL",
        .form_revision = "2018-01",
        .tax_year = 2026,
    };
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.allocateOnDemandOccurrence(failing_scope),
    );
    try store.exec("DROP TRIGGER synthetic_on_demand_reservation_failure;");
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.allocateOnDemandOccurrence(failing_scope),
    );

    try store.createDraft(
        .{
            .id = "legacy-on-demand-limit",
            .form_code = "MAX",
            .form_revision = "2018-01",
            .period_key = "2026-O999",
            .profile_as_of = testDate("2026-12-31"),
            .mapping_revision = "mapping-v1",
        },
        &.{.{
            .role = "filer",
            .profile_id = profile_id,
            .profile_revision_id = "revision-1",
            .profile_revision_sequence = 1,
        }},
        &.{},
        &.{},
    );
    try std.testing.expectError(
        Error.OnDemandOccurrenceLimitExceeded,
        store.allocateOnDemandOccurrence(.{
            .owner_id = &owner,
            .profile_id = profile_id,
            .form_code = "MAX",
            .form_revision = "2018-01",
            .tax_year = 2026,
        }),
    );

    try std.testing.expectError(
        Error.NotFound,
        store.allocateOnDemandOccurrence(.{
            .owner_id = "ffffffffffffffffffffffffffffffff",
            .profile_id = profile_id,
            .form_code = "0605",
            .form_revision = "2002-01",
            .tax_year = 2026,
        }),
    );
    try std.testing.expectError(
        Error.InvalidValue,
        store.allocateOnDemandOccurrence(.{
            .owner_id = "INVALID-OWNER",
            .profile_id = profile_id,
            .form_code = "0605",
            .form_revision = "2002-01",
            .tax_year = 2026,
        }),
    );
}

test "schema v6 upgrades to durable on-demand occurrence counters" {
    var store = try openLegacyStoreForTest(6);
    defer store.close();
    try std.testing.expectEqual(@as(u32, 6), try store.schemaVersion());
    try std.testing.expect(!(try tableExistsForTest(
        &store,
        "tax_form_on_demand_occurrence_counters",
    )));
    try store.migrate();
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
    try std.testing.expect(try tableExistsForTest(
        &store,
        "tax_form_on_demand_occurrence_counters",
    ));
    try store.migrate();
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());
}

test "schema version one upgrades append-only delete guards atomically" {
    var store = try openLegacyStoreForTest(1);
    defer store.close();
    try std.testing.expectEqual(@as(u32, 1), try store.schemaVersion());
    try store.migrate();
    try std.testing.expectEqual(latest_schema_version, try store.schemaVersion());

    const profile_id = "tax-profile-v1-upgrade";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Upgrade Guard", "2026-01-01"),
        .{},
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_profile_revisions
            \\WHERE profile_id = 'tax-profile-v1-upgrade';
        ),
    );
}

test "schema v3 creates immutable identity anchor on first revision" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-anchor";
    var first = testRevision(
        profile_id,
        0,
        "Anchor Person",
        "2026-01-01",
    );
    first.identity.tin = "123-456-789-000";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        first,
        .{},
    );
    var anchor = (try store.getIdentityAnchor(allocator, profile_id)).?;
    defer anchor.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), anchor.sequence);
    try std.testing.expectEqual(Jurisdiction.philippines, anchor.jurisdiction);
    try std.testing.expectEqual(
        TaxAuthority.bureau_of_internal_revenue,
        anchor.tax_authority,
    );
    try std.testing.expectEqualStrings("123456789000", anchor.canonical_tin);
    try std.testing.expectEqual(
        LegalPersonClass.natural_person,
        anchor.legal_person_class,
    );
    try std.testing.expectEqualStrings(
        "revision-1",
        anchor.established_from_revision_id.?,
    );

    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\UPDATE tax_profile_identity_anchors
            \\SET canonical_tin = '999888777000'
            \\WHERE profile_id = 'tax-profile-anchor';
        ),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_profile_identity_anchors
            \\WHERE profile_id = 'tax-profile-anchor';
        ),
    );
}

test "evolution writes fail closed for a revision-less profile shell" {
    var store = try Store.openMemory(std.testing.allocator);
    defer store.close();

    const profile_id = "tax-profile-shell-without-anchor";
    try store.createProfile(.{ .id = profile_id });
    try std.testing.expectError(
        Error.MissingIdentityAnchor,
        store.appendCivilStatusRevision(.{
            .profile_id = profile_id,
            .sequence = 1,
            .expected_current_sequence = 0,
            .effective = testPeriod("2026-01-01", null),
            .status = .single,
            .source = .manual_entry,
        }),
    );
    try std.testing.expectError(
        Error.MissingIdentityAnchor,
        store.recordIdentityCorrection(.{
            .id = "identity-correction-without-anchor",
            .profile_id = profile_id,
            .expected_anchor_sequence = 1,
            .new_canonical_tin = "123456789000",
            .new_legal_person_class = .natural_person,
            .reason = "synthetic invalid correction",
            .actor_reference = "operator:test-reviewer",
            .recorded_at_unix_seconds = 1_785_369_600,
            .provenance = "synthetic reviewed identity source",
        }),
    );
}

test "individual and sole proprietor share identity but corporation does not" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const natural_id = "tax-profile-natural-evolution";
    var individual = testRevision(
        natural_id,
        0,
        "Natural Person",
        "2025-01-01",
    );
    individual.subject = .{ .individual = .{
        .name = "Natural Person",
        .date_of_birth = testDate("1990-01-01"),
        .citizenship = "PH",
    } };
    try store.createProfileWithRevision(
        .{ .id = natural_id },
        individual,
        .{},
    );
    try store.appendRevision(
        testRevision(
            natural_id,
            1,
            "Natural Person",
            "2026-01-01",
        ),
        .{},
    );

    var changed_tin = testRevision(
        natural_id,
        2,
        "Natural Person",
        "2027-01-01",
    );
    changed_tin.identity.tin = "999888777000";
    try std.testing.expectError(
        Error.CanonicalTaxpayerIdentifierChanged,
        store.appendRevision(changed_tin, .{}),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.insertRevisionRows(changed_tin, .{}),
    );

    var corporation_in_same_profile = testRevision(
        natural_id,
        2,
        "Ignored",
        "2027-01-01",
    );
    corporation_in_same_profile.subject = .{ .legal_entity = .{
        .registered_name = "Natural Person Corporation",
        .kind = .corporation,
    } };
    try std.testing.expectError(
        Error.LegalPersonClassChanged,
        store.appendRevision(corporation_in_same_profile, .{}),
    );
    var still_natural = (try store.getCurrentRevision(
        allocator,
        natural_id,
    )).?;
    defer still_natural.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 2), still_natural.sequence);

    const corporation_id = "tax-profile-converted-corporation";
    var corporation = testRevision(
        corporation_id,
        0,
        "Ignored",
        "2027-01-01",
    );
    corporation.identity.tin = "987654321000";
    corporation.subject = .{ .legal_entity = .{
        .registered_name = "Natural Person Corporation",
        .kind = .corporation,
    } };
    try store.createProfileWithRevision(
        .{ .id = corporation_id },
        corporation,
        .{},
    );
    try std.testing.expectError(
        Error.InvalidRelationship,
        store.addProfileRelationship(.{
            .id = "relationship-invalid-spouse",
            .from_profile_id = natural_id,
            .to_profile_id = corporation_id,
            .kind = .spouse_of,
            .effective = testPeriod("2027-01-01", null),
            .provenance = "invalid synthetic relationship",
        }),
    );
    try store.addProfileRelationship(.{
        .id = "relationship-business-conversion",
        .from_profile_id = natural_id,
        .to_profile_id = corporation_id,
        .kind = .business_converted_to,
        .effective = testPeriod("2027-01-01", null),
        .provenance = "reviewed synthetic conversion evidence",
    });

    var before = try store.listProfileRelationshipsAsOf(
        allocator,
        natural_id,
        "2026-12-31",
    );
    defer before.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), before.items.len);
    var after = try store.listProfileRelationshipsAsOf(
        allocator,
        natural_id,
        "2027-01-01",
    );
    defer after.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), after.items.len);
    try std.testing.expectEqual(
        RelationshipKind.business_converted_to,
        after.items[0].kind,
    );
}

test "relationship vocabulary is effective dated and class checked" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const first_id = "tax-profile-relationship-first";
    const second_id = "tax-profile-relationship-second";
    try store.createProfileWithRevision(
        .{ .id = first_id },
        testRevision(first_id, 0, "First Person", "2025-01-01"),
        .{},
    );
    var second = testRevision(
        second_id,
        0,
        "Second Person",
        "2025-01-01",
    );
    second.identity.tin = "222333444000";
    try store.createProfileWithRevision(.{ .id = second_id }, second, .{});

    try store.addProfileRelationship(.{
        .id = "relationship-spouse",
        .from_profile_id = first_id,
        .to_profile_id = second_id,
        .kind = .spouse_of,
        .effective = testPeriod("2026-06-01", null),
        .provenance = "reviewed synthetic marriage record",
    });
    try store.addProfileRelationship(.{
        .id = "relationship-predecessor",
        .from_profile_id = first_id,
        .to_profile_id = second_id,
        .kind = .predecessor_of,
        .effective = testPeriod("2027-01-01", null),
        .provenance = "reviewed synthetic succession record",
    });
    try store.addProfileRelationship(.{
        .id = "relationship-successor",
        .from_profile_id = second_id,
        .to_profile_id = first_id,
        .kind = .successor_of,
        .effective = testPeriod("2027-01-01", null),
        .provenance = "reviewed synthetic succession record",
    });

    var before = try store.listProfileRelationshipsAsOf(
        allocator,
        first_id,
        "2026-05-31",
    );
    defer before.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), before.items.len);
    var married = try store.listProfileRelationshipsAsOf(
        allocator,
        first_id,
        "2026-06-01",
    );
    defer married.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), married.items.len);
    try std.testing.expectEqual(RelationshipKind.spouse_of, married.items[0].kind);
    var succession = try store.listProfileRelationshipsAsOf(
        allocator,
        first_id,
        "2027-01-01",
    );
    defer succession.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), succession.items.len);

    try std.testing.expectError(
        Error.InvalidRelationship,
        store.addProfileRelationship(.{
            .id = "relationship-self",
            .from_profile_id = first_id,
            .to_profile_id = first_id,
            .kind = .spouse_of,
            .effective = testPeriod("2026-06-01", null),
            .provenance = "invalid synthetic relationship",
        }),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\UPDATE tax_profile_relationships
            \\SET provenance = 'mutated'
            \\WHERE id = 'relationship-spouse';
        ),
    );
}

test "civil status revisions resolve future single to married transition" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-civil-status";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Civil Status", "2025-01-01"),
        .{},
    );
    try store.appendCivilStatusRevision(.{
        .profile_id = profile_id,
        .sequence = 1,
        .expected_current_sequence = 0,
        .effective = testPeriod("2025-01-01", null),
        .status = .single,
        .source = .manual_entry,
    });
    try store.appendCivilStatusRevision(.{
        .profile_id = profile_id,
        .sequence = 2,
        .expected_current_sequence = 1,
        .effective = testPeriod("2027-06-01", null),
        .status = .married,
        .source = .{ .imported = "reviewed civil registry record" },
    });

    var before = (try store.getCivilStatusAsOf(
        allocator,
        profile_id,
        "2027-05-31",
    )).?;
    defer before.deinit(allocator);
    try std.testing.expectEqual(CivilStatus.single, before.status);
    var after = (try store.getCivilStatusAsOf(
        allocator,
        profile_id,
        "2027-06-01",
    )).?;
    defer after.deinit(allocator);
    try std.testing.expectEqual(CivilStatus.married, after.status);
    try std.testing.expectEqualStrings(
        "reviewed civil registry record",
        after.source.imported,
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\UPDATE tax_profile_civil_status_revisions
            \\SET status = 'single'
            \\WHERE profile_id = 'tax-profile-civil-status'
            \\  AND sequence = 2;
        ),
    );

    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\INSERT INTO tax_profile_civil_status_revisions (
            \\    profile_id, sequence, effective_from, status,
            \\    source_tag
            \\) VALUES (
            \\    'tax-profile-civil-status', 3, '2028-01-01',
            \\    'unsupported_status', 'manual_entry'
            \\);
        ),
    );
}

test "identity correction is audited and failed event rolls back anchor" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-correction";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Correction Person", "2026-01-01"),
        .{},
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        try store.recordIdentityCorrection(.{
            .id = "identity-correction-1",
            .profile_id = profile_id,
            .expected_anchor_sequence = 1,
            .new_canonical_tin = "987-654-321-000",
            .new_legal_person_class = .natural_person,
            .reason = "clerical correction confirmed by source record",
            .actor_reference = "operator:test-reviewer",
            .recorded_at_unix_seconds = 1_785_369_600,
            .provenance = "synthetic reviewed identity source",
        }),
    );
    var event = (try store.getIdentityCorrection(
        allocator,
        "identity-correction-1",
    )).?;
    defer event.deinit(allocator);
    try std.testing.expectEqualStrings(
        "123456789000",
        event.old_canonical_tin,
    );
    try std.testing.expectEqualStrings(
        "987654321000",
        event.new_canonical_tin,
    );
    try std.testing.expectEqualStrings(
        "operator:test-reviewer",
        event.actor_reference,
    );
    try std.testing.expectEqual(
        @as(i64, 1_785_369_600),
        event.recorded_at_unix_seconds,
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\UPDATE tax_profile_identity_corrections
            \\SET reason = 'mutated'
            \\WHERE id = 'identity-correction-1';
        ),
    );

    var revised = testRevision(
        profile_id,
        1,
        "Correction Person",
        "2026-07-01",
    );
    revised.identity.tin = "987654321000";
    try store.appendRevision(revised, .{});

    try store.exec(
        \\CREATE TRIGGER synthetic_identity_event_failure
        \\BEFORE INSERT ON tax_profile_identity_corrections
        \\WHEN NEW.id = 'identity-correction-rollback'
        \\BEGIN
        \\    SELECT RAISE(ABORT, 'synthetic event write failure');
        \\END;
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.recordIdentityCorrection(.{
            .id = "identity-correction-rollback",
            .profile_id = profile_id,
            .expected_anchor_sequence = 2,
            .new_canonical_tin = "555444333000",
            .new_legal_person_class = .natural_person,
            .reason = "synthetic rollback exercise",
            .actor_reference = "operator:test-reviewer",
            .recorded_at_unix_seconds = 1_785_369_601,
            .provenance = "synthetic reviewed identity source",
        }),
    );
    try store.exec("DROP TRIGGER synthetic_identity_event_failure;");
    var original_anchor = (try store.getIdentityAnchorAtSequence(
        allocator,
        profile_id,
        1,
    )).?;
    defer original_anchor.deinit(allocator);
    try std.testing.expectEqualStrings(
        "123456789000",
        original_anchor.canonical_tin,
    );
    try std.testing.expect(original_anchor.identity_correction_id == null);
    var anchor = (try store.getIdentityAnchor(allocator, profile_id)).?;
    defer anchor.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 2), anchor.sequence);
    try std.testing.expectEqualStrings("987654321000", anchor.canonical_tin);
    try std.testing.expectEqualStrings(
        "identity-correction-1",
        anchor.identity_correction_id.?,
    );
    try std.testing.expectError(
        Error.NoIdentityCorrection,
        store.recordIdentityCorrection(.{
            .id = "identity-correction-noop",
            .profile_id = profile_id,
            .expected_anchor_sequence = 2,
            .new_canonical_tin = "987654321000",
            .new_legal_person_class = .natural_person,
            .reason = "synthetic no-op",
            .actor_reference = "operator:test-reviewer",
            .recorded_at_unix_seconds = 1_785_369_602,
            .provenance = "synthetic reviewed identity source",
        }),
    );
    var foreign_key_check = try store.prepare("PRAGMA foreign_key_check;");
    defer foreign_key_check.deinit();
    try std.testing.expectEqual(
        StepResult.done,
        try foreign_key_check.step(),
    );
}

test "v1 and v2 histories migrate to v3 deterministically and idempotently" {
    const allocator = std.testing.allocator;
    for ([_]u32{ 1, 2 }) |legacy_version| {
        var store = try openLegacyStoreForTest(legacy_version);
        defer store.close();

        const profile_id = if (legacy_version == 1)
            "tax-profile-legacy-v1"
        else
            "tax-profile-legacy-v2";
        var first = testRevision(
            profile_id,
            0,
            "Legacy Person",
            "2025-01-01",
        );
        first.identity.tin = "123-456-789-000";
        first.subject = .{ .individual = .{
            .name = "Legacy Person",
            .date_of_birth = testDate("1990-01-01"),
            .citizenship = "PH",
        } };
        try store.createProfileWithRevision(
            .{ .id = profile_id },
            first,
            .{},
        );
        const second = testRevision(
            profile_id,
            1,
            "Legacy Person Updated",
            "2026-01-01",
        );
        try store.insertRevisionRows(second, .{});
        {
            var advance = try store.prepare(
                \\UPDATE tax_profiles
                \\SET current_revision_id = 'revision-2'
                \\WHERE id = ?;
            );
            defer advance.deinit();
            try advance.bindText(1, profile_id);
            try advance.expectDone();
        }

        try store.migrate();
        try std.testing.expectEqual(
            latest_schema_version,
            try store.schemaVersion(),
        );
        var anchor = (try store.getIdentityAnchor(
            allocator,
            profile_id,
        )).?;
        defer anchor.deinit(allocator);
        try std.testing.expectEqualStrings(
            "123456789000",
            anchor.canonical_tin,
        );
        try std.testing.expectEqualStrings(
            "revision-1",
            anchor.established_from_revision_id.?,
        );

        try store.migrate();
        try std.testing.expectEqual(
            latest_schema_version,
            try store.schemaVersion(),
        );
        var count = try store.prepare(
            \\SELECT COUNT(*)
            \\FROM tax_profile_identity_anchors
            \\WHERE profile_id = ?;
        );
        defer count.deinit();
        try count.bindText(1, profile_id);
        try std.testing.expectEqual(StepResult.row, try count.step());
        try std.testing.expectEqual(
            @as(i64, 1),
            sqlite.sqlite3_column_int64(count.raw, 0),
        );
        var foreign_key_check = try store.prepare(
            "PRAGMA foreign_key_check;",
        );
        defer foreign_key_check.deinit();
        try std.testing.expectEqual(
            StepResult.done,
            try foreign_key_check.step(),
        );
    }
}

test "v3 migration rejects contradictory legacy identity histories atomically" {
    const cases = [_]struct {
        legacy_version: u32,
        change_class: bool,
    }{
        .{ .legacy_version = 1, .change_class = false },
        .{ .legacy_version = 2, .change_class = true },
    };
    for (cases) |case| {
        var store = try openLegacyStoreForTest(case.legacy_version);
        defer store.close();

        const profile_id = if (case.change_class)
            "legacy-inconsistent-class"
        else
            "legacy-inconsistent-tin";
        try store.createProfileWithRevision(
            .{ .id = profile_id },
            testRevision(profile_id, 0, "Legacy Person", "2025-01-01"),
            .{},
        );
        var second = testRevision(
            profile_id,
            1,
            "Legacy Person Updated",
            "2026-01-01",
        );
        if (case.change_class) {
            second.subject = .{ .legal_entity = .{
                .registered_name = "Legacy Corporation",
                .kind = .corporation,
            } };
        } else {
            second.identity.tin = "987654321000";
        }
        try store.insertRevisionRows(second, .{});

        try std.testing.expectError(
            Error.InconsistentIdentityHistory,
            store.migrate(),
        );
        try std.testing.expectEqual(
            case.legacy_version,
            try store.schemaVersion(),
        );
        var revision_count = try store.prepare(
            \\SELECT COUNT(*)
            \\FROM tax_profile_revisions
            \\WHERE profile_id = ?;
        );
        defer revision_count.deinit();
        try revision_count.bindText(1, profile_id);
        try std.testing.expectEqual(
            StepResult.row,
            try revision_count.step(),
        );
        try std.testing.expectEqual(
            @as(i64, 2),
            sqlite.sqlite3_column_int64(revision_count.raw, 0),
        );
        var v3_table = try store.prepare(
            \\SELECT COUNT(*)
            \\FROM sqlite_master
            \\WHERE type = 'table'
            \\  AND name = 'tax_profile_identity_anchors';
        );
        defer v3_table.deinit();
        try std.testing.expectEqual(StepResult.row, try v3_table.step());
        try std.testing.expectEqual(
            @as(i64, 0),
            sqlite.sqlite3_column_int64(v3_table.raw, 0),
        );
    }
}

test "atomic first revision and optimistic append maintain current revision" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-test-0001";
    const activities = [_]BusinessActivityWrite{.{
        .id = "business-main",
        .line_of_business = "Professional services",
        .atc = "PT010",
        .effective = testPeriod("2026-01-01", null),
    }};
    const facts = [_]RegistrationFactWrite{.{
        .id = "tax-type-main",
        .effective = testPeriod("2026-01-01", null),
        .value = .{ .tax_type = "Percentage Tax" },
    }};
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Juan Dela Cruz", "2026-01-01"),
        .{
            .business_activities = &activities,
            .registration_facts = &facts,
        },
    );

    var first = (try store.getCurrentRevision(allocator, profile_id)).?;
    defer first.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), first.sequence);
    try std.testing.expectEqualStrings("revision-1", first.id);
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        first.subject.sole_proprietor.person.name,
    );
    try std.testing.expectEqual(@as(usize, 1), first.business_activities.len);
    try std.testing.expectEqualStrings(
        "PT010",
        first.business_activities[0].atc.?,
    );
    try std.testing.expectEqual(@as(usize, 1), first.registration_facts.len);
    try std.testing.expectEqualStrings(
        "Percentage Tax",
        first.registration_facts[0].value.tax_type,
    );

    try std.testing.expectError(
        Error.RevisionConflict,
        store.appendRevision(
            testRevision(profile_id, 0, "Juan Updated", "2026-07-01"),
            .{},
        ),
    );
    try store.appendRevision(
        testRevision(profile_id, 1, "Juan Updated", "2026-07-01"),
        .{},
    );

    var current = (try store.getCurrentRevision(allocator, profile_id)).?;
    defer current.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 2), current.sequence);
    try std.testing.expectEqualStrings("revision-2", current.id);
    try std.testing.expectEqualStrings(
        "Juan Updated",
        current.subject.sole_proprietor.person.name,
    );

    var historical = (try store.getRevision(
        allocator,
        profile_id,
        "revision-1",
    )).?;
    defer historical.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        historical.subject.sole_proprietor.person.name,
    );

    try store.appendRevision(
        testRevision(
            profile_id,
            2,
            "Juan Retroactive",
            "2026-06-01",
        ),
        .{},
    );
    var retroactive = (try store.getEffectiveRevision(
        allocator,
        profile_id,
        "2026-08-01",
    )).?;
    defer retroactive.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 3), retroactive.sequence);
    try std.testing.expectEqualStrings(
        "Juan Retroactive",
        retroactive.subject.sole_proprietor.person.name,
    );

    var effective = (try store.getEffectiveRevision(
        allocator,
        profile_id,
        "2026-03-31",
    )).?;
    defer effective.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), effective.sequence);

    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_profile_business_activities
            \\WHERE profile_id = 'tax-profile-test-0001'
            \\  AND revision_id = 'revision-1';
        ),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_profile_registration_facts
            \\WHERE profile_id = 'tax-profile-test-0001'
            \\  AND revision_id = 'revision-1';
        ),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_profile_revisions
            \\WHERE profile_id = 'tax-profile-test-0001'
            \\  AND id = 'revision-1';
        ),
    );
}

test "Forms Set distinguishes unconfigured configured-empty and populated" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-test-forms";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Forms Profile", "2026-01-01"),
        .{},
    );

    try std.testing.expect(
        try store.getFormSet(allocator, profile_id, 2026) == null,
    );
    try store.replaceFormSet(profile_id, 2026, &.{});
    var empty = (try store.getFormSet(allocator, profile_id, 2026)).?;
    defer empty.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), empty.items.len);

    const forms = [_]FormRegistrationWrite{
        .{ .form_code = "2551Q", .form_revision = "2018-01-ENCS" },
        .{ .form_code = "1701Q", .form_revision = "2018-01-ENCS" },
    };
    try store.replaceFormSet(profile_id, 2026, &forms);
    var populated = (try store.getFormSet(allocator, profile_id, 2026)).?;
    defer populated.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), populated.items.len);
    try std.testing.expectEqualStrings("1701Q", populated.items[0].form_code);
    try std.testing.expectEqualStrings("2551Q", populated.items[1].form_code);

    try std.testing.expect(try store.clearFormSet(profile_id, 2026));
    try std.testing.expect(
        try store.getFormSet(allocator, profile_id, 2026) == null,
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.replaceFormSet("missing-profile", 2026, &forms),
    );
}

test "Forms Set resolution distinguishes new legacy empty and nonempty" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-form-state";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "New Forms Profile", "2026-01-01"),
        .{},
    );
    var needs = try store.resolveFormSet(allocator, profile_id, 2026);
    defer needs.deinit(allocator);
    try std.testing.expectEqual(FormSetState.needs_configuration, needs.state);
    try std.testing.expectEqual(@as(usize, 0), needs.forms.items.len);
    try std.testing.expectError(
        Error.InvalidValue,
        store.resetToLegacyCatalogDefault(profile_id, 2026),
    );

    try store.replaceFormSet(profile_id, 2026, &.{});
    var empty = try store.resolveFormSet(allocator, profile_id, 2026);
    defer empty.deinit(allocator);
    try std.testing.expectEqual(FormSetState.active_empty, empty.state);

    const forms = [_]FormRegistrationWrite{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }};
    try store.replaceFormSet(profile_id, 2026, &forms);
    var active = try store.resolveFormSet(allocator, profile_id, 2026);
    defer active.deinit(allocator);
    try std.testing.expectEqual(FormSetState.active_nonempty, active.state);
    try std.testing.expectEqual(@as(usize, 1), active.forms.items.len);
}

test "schema v5 missing Forms Sets migrate to explicit legacy fallback" {
    const allocator = std.testing.allocator;
    var store = try openLegacyStoreForTest(5);
    defer store.close();
    const profile_id = "tax-profile-legacy-forms";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Legacy Forms Profile", "2026-01-01"),
        .{},
    );
    try store.exec(
        \\INSERT INTO tax_profile_form_sets(profile_id, tax_year)
        \\VALUES ('tax-profile-legacy-forms', 2025),
        \\       ('tax-profile-legacy-forms', 2024);
        \\INSERT INTO tax_profile_form_set_entries(
        \\    profile_id, tax_year, form_code, form_revision
        \\) VALUES (
        \\    'tax-profile-legacy-forms', 2024, '2551Q', '2018-01-ENCS'
        \\);
    );

    try store.migrate();
    var legacy = try store.resolveFormSet(allocator, profile_id, 2026);
    defer legacy.deinit(allocator);
    try std.testing.expectEqual(
        FormSetState.legacy_catalog_default,
        legacy.state,
    );
    var migrated_empty = try store.resolveFormSet(allocator, profile_id, 2025);
    defer migrated_empty.deinit(allocator);
    try std.testing.expectEqual(FormSetState.active_empty, migrated_empty.state);
    var migrated_active = try store.resolveFormSet(allocator, profile_id, 2024);
    defer migrated_active.deinit(allocator);
    try std.testing.expectEqual(
        FormSetState.active_nonempty,
        migrated_active.state,
    );
    try store.replaceFormSet(profile_id, 2026, &.{});
    try store.resetToLegacyCatalogDefault(profile_id, 2026);
    var reset = try store.resolveFormSet(allocator, profile_id, 2026);
    defer reset.deinit(allocator);
    try std.testing.expectEqual(
        FormSetState.legacy_catalog_default,
        reset.state,
    );
}

test "profile calendar selection distinguishes all none and subsets" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-calendar-selection";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Calendar Profile", "2026-01-01"),
        .{},
    );

    try std.testing.expect(
        try store.getCalendarFormSelection(allocator, profile_id) == null,
    );

    try store.replaceCalendarFormSelection(profile_id, &.{});
    var empty = (try store.getCalendarFormSelection(
        allocator,
        profile_id,
    )).?;
    defer empty.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), empty.form_codes.len);

    const subset = [_][]const u8{ "2551Q", "1701Q" };
    try store.replaceCalendarFormSelection(profile_id, &subset);
    var populated = (try store.getCalendarFormSelection(
        allocator,
        profile_id,
    )).?;
    defer populated.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), populated.form_codes.len);
    try std.testing.expectEqualStrings("1701Q", populated.form_codes[0]);
    try std.testing.expectEqualStrings("2551Q", populated.form_codes[1]);

    const duplicate = [_][]const u8{ "2551Q", "2551Q" };
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.replaceCalendarFormSelection(profile_id, &duplicate),
    );
    var preserved = (try store.getCalendarFormSelection(
        allocator,
        profile_id,
    )).?;
    defer preserved.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), preserved.form_codes.len);

    try std.testing.expect(
        try store.clearCalendarFormSelection(profile_id),
    );
    try std.testing.expect(
        try store.getCalendarFormSelection(allocator, profile_id) == null,
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.replaceCalendarFormSelection("missing-profile", &subset),
    );
}

test "profile calendar selection cascades with a deleted profile" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "revisionless-calendar-profile";
    try store.createProfile(.{ .id = profile_id });
    try store.replaceCalendarFormSelection(
        profile_id,
        &.{ "1701Q", "2551Q" },
    );
    try store.exec(
        \\DELETE FROM tax_profiles
        \\WHERE id = 'revisionless-calendar-profile';
    );
    try std.testing.expect(
        try store.getCalendarFormSelection(allocator, profile_id) == null,
    );
}

test "draft summaries belong only to the filer profile and track lifecycle" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const filer_id = "draft-summary-filer";
    const spouse_id = "draft-summary-spouse";
    try store.createProfileWithRevision(
        .{ .id = filer_id },
        testRevision(filer_id, 0, "Calendar Filer", "2026-01-01"),
        .{},
    );
    var spouse = testRevision(
        spouse_id,
        0,
        "Calendar Spouse",
        "2026-01-01",
    );
    spouse.identity.tin = "987654321000";
    try store.createProfileWithRevision(.{ .id = spouse_id }, spouse, .{});

    try store.createDraft(
        .{
            .id = "draft-summary-q3",
            .form_code = "2551Q",
            .form_revision = "2018-01-ENCS",
            .period_key = "2026-Q3",
            .profile_as_of = "2026-09-30".*,
            .mapping_revision = "tax-profile-snapshot-v1",
        },
        &.{
            .{
                .role = "filer",
                .profile_id = filer_id,
                .profile_revision_id = "revision-1",
                .profile_revision_sequence = 1,
            },
            .{
                .role = "spouse",
                .profile_id = spouse_id,
                .profile_revision_id = "revision-1",
                .profile_revision_sequence = 1,
            },
        },
        &.{},
        &.{},
    );

    try store.createDraft(
        .{
            .id = "draft-summary-prior-year",
            .form_code = "1701Q",
            .form_revision = "2018-01-ENCS",
            .period_key = "2025-Q4",
            .profile_as_of = "2026-01-01".*,
            .mapping_revision = "tax-profile-snapshot-v1",
        },
        &.{.{
            .role = "filer",
            .profile_id = filer_id,
            .profile_revision_id = "revision-1",
            .profile_revision_sequence = 1,
        }},
        &.{},
        &.{},
    );
    try store.createDraft(
        .{
            .id = "draft-summary-old-history",
            .form_code = "1701Q",
            .form_revision = "2018-01-ENCS",
            .period_key = "2024-Q4",
            .profile_as_of = "2026-01-01".*,
            .mapping_revision = "tax-profile-snapshot-v1",
        },
        &.{.{
            .role = "filer",
            .profile_id = filer_id,
            .profile_revision_id = "revision-1",
            .profile_revision_sequence = 1,
        }},
        &.{},
        &.{},
    );

    var filer_summaries = try store.listDraftSummariesForProfile(
        allocator,
        filer_id,
        2026,
    );
    defer filer_summaries.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), filer_summaries.items.len);
    try std.testing.expectEqualStrings(
        "2026-Q3",
        filer_summaries.items[0].period_key,
    );
    try std.testing.expectEqualStrings(
        "2025-Q4",
        filer_summaries.items[1].period_key,
    );
    try std.testing.expectEqualStrings(
        "editing",
        filer_summaries.items[0].lifecycle,
    );

    var spouse_summaries = try store.listDraftSummariesForProfile(
        allocator,
        spouse_id,
        2026,
    );
    defer spouse_summaries.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), spouse_summaries.items.len);

    try store.transitionDraft("draft-summary-q3", "editing", "prepared");
    var updated = try store.listDraftSummariesForProfile(
        allocator,
        filer_id,
        2026,
    );
    defer updated.deinit(allocator);
    try std.testing.expectEqualStrings("prepared", updated.items[0].lifecycle);
}

test "draft role bindings are named and snapshots survive profile revision changes" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const employer_id = "tax-profile-employer";
    const employee_id = "tax-profile-employee";
    try store.createProfileWithRevision(
        .{ .id = employer_id },
        testRevision(employer_id, 0, "ACME OPC", "2026-01-01"),
        .{},
    );
    const employee_activities = [_]BusinessActivityWrite{.{
        .id = "activity-employment",
        .line_of_business = "Employment",
        .effective = testPeriod("2026-01-01", null),
    }};
    const employee_facts = [_]RegistrationFactWrite{.{
        .id = "fact-withholding-agent",
        .effective = testPeriod("2026-01-01", null),
        .value = .{ .government_withholding_agent = .yes },
    }};
    try store.createProfileWithRevision(
        .{ .id = employee_id },
        testRevision(employee_id, 0, "Juan Dela Cruz", "2026-01-01"),
        .{
            .business_activities = &employee_activities,
            .registration_facts = &employee_facts,
        },
    );
    const revision_id = "revision-1";

    const bindings = [_]RoleBindingWrite{
        .{
            .role = "employer",
            .profile_id = employer_id,
            .profile_revision_id = revision_id,
            .profile_revision_sequence = 1,
        },
        .{
            .role = "employee",
            .profile_id = employee_id,
            .profile_revision_id = revision_id,
            .profile_revision_sequence = 1,
            .business_activity_id = "activity-employment",
        },
    };
    const snapshots = [_]SnapshotFieldWrite{
        .{
            .role = "employee",
            .field_id = "employee.registered_name",
            .reusable_field = "registered_name",
            .value_type = "text",
            .value_text = "Juan Dela Cruz",
            .provenance = "tax_profile",
            .profile_revision_id = revision_id,
            .profile_revision_sequence = 1,
            .revision_source = .{ .imported = "test fixture" },
            .business_activity_id = "activity-employment",
            .registration_fact_id = "fact-withholding-agent",
        },
        .{
            .role = "employer",
            .field_id = "employer.registered_name",
            .reusable_field = "registered_name",
            .value_type = "text",
            .value_text = "ACME OPC",
            .provenance = "tax_profile",
            .profile_revision_id = revision_id,
            .profile_revision_sequence = 1,
            .revision_source = .{ .imported = "test fixture" },
        },
    };
    const values = [_]DraftValueWrite{.{
        .field_id = "gross_compensation",
        .value_text = "60000000",
    }};
    const draft_id = "draft-2316-original";
    try store.createDraft(
        .{
            .id = draft_id,
            .form_code = "2316",
            .form_revision = "2026-test",
            .period_key = "2026",
            .profile_as_of = testDate("2026-12-31"),
            .mapping_revision = "mapping-v1",
        },
        &bindings,
        &snapshots,
        &values,
    );

    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\UPDATE tax_form_draft_role_bindings
            \\SET role = role
            \\WHERE draft_id = 'draft-2316-original';
        ),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_form_draft_snapshot_fields
            \\WHERE draft_id = 'draft-2316-original';
        ),
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\DELETE FROM tax_form_draft_role_bindings
            \\WHERE draft_id = 'draft-2316-original';
        ),
    );

    const disposable_draft_id = "draft-2316-disposable";
    try store.createDraft(
        .{
            .id = disposable_draft_id,
            .form_code = "2316",
            .form_revision = "2026-test",
            .period_key = "2026-disposable",
            .profile_as_of = testDate("2026-12-31"),
            .mapping_revision = "mapping-v1",
        },
        &bindings,
        &snapshots,
        &values,
    );
    try store.exec(
        \\DELETE FROM tax_form_drafts
        \\WHERE id = 'draft-2316-disposable';
    );
    try std.testing.expect(
        try store.getDraft(allocator, disposable_draft_id) == null,
    );

    const replacement_values = [_]DraftValueWrite{
        .{
            .field_id = "gross_compensation",
            .value_text = "61000000",
        },
        .{
            .field_id = "filing_note",
            .value_text = "reviewed",
            .provenance = "transaction",
        },
    };
    try store.replaceDraftValues(draft_id, &replacement_values);
    try std.testing.expectError(
        Error.InvalidValue,
        store.replaceDraftValues(draft_id, &.{
            .{ .field_id = "duplicate", .value_text = "one" },
            .{ .field_id = "duplicate", .value_text = "two" },
        }),
    );

    var original = (try store.getDraft(allocator, draft_id)).?;
    defer original.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), original.bindings.len);
    try std.testing.expectEqualStrings("employee", original.bindings[0].role);
    try std.testing.expectEqualStrings("employer", original.bindings[1].role);
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        original.snapshots[0].value_text,
    );
    try std.testing.expectEqual(@as(usize, 2), original.values.len);
    var found_replaced_gross = false;
    for (original.values) |value| {
        if (!std.mem.eql(u8, value.field_id, "gross_compensation")) continue;
        try std.testing.expectEqualStrings("61000000", value.value_text);
        found_replaced_gross = true;
    }
    try std.testing.expect(found_replaced_gross);
    try std.testing.expectEqualStrings(
        "2026-12-31",
        original.profile_as_of,
    );
    try std.testing.expectEqualStrings(
        "test fixture",
        original.snapshots[0].revision_source.imported,
    );
    try std.testing.expectEqualStrings(
        "activity-employment",
        original.snapshots[0].business_activity_id.?,
    );
    try std.testing.expectEqualStrings(
        "fact-withholding-agent",
        original.snapshots[0].registration_fact_id.?,
    );

    try store.appendRevision(
        testRevision(employee_id, 1, "Juan Dela Cruz Updated", "2027-01-01"),
        .{},
    );
    var after_revision = (try store.getDraft(allocator, draft_id)).?;
    defer after_revision.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        after_revision.snapshots[0].value_text,
    );
    try std.testing.expectEqualStrings(
        revision_id,
        after_revision.snapshots[0].profile_revision_id,
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        after_revision.snapshots[0].profile_revision_sequence,
    );

    try store.putDraftValue(draft_id, .{
        .field_id = "tax_withheld",
        .value_text = "3500000",
    });
    try store.transitionDraft(draft_id, "editing", "prepared");
    try std.testing.expectError(
        Error.InvalidTransition,
        store.replaceDraftValues(draft_id, &replacement_values),
    );
    try std.testing.expectError(
        Error.InvalidTransition,
        store.putDraftValue(draft_id, .{
            .field_id = "tax_withheld",
            .value_text = "3600000",
        }),
    );
    try store.transitionDraft(draft_id, "prepared", "editing");
    try store.putDraftValue(draft_id, .{
        .field_id = "tax_withheld",
        .value_text = "3600000",
    });
    try store.transitionDraft(draft_id, "editing", "prepared");
    try store.transitionDraft(draft_id, "prepared", "queued");

    const amendment_id = "draft-2316-amendment";
    try store.createDraft(
        .{
            .id = amendment_id,
            .form_code = "2316",
            .form_revision = "2026-test",
            .period_key = "2026",
            .profile_as_of = testDate("2026-12-31"),
            .intent = "amended",
            .mapping_revision = "mapping-v1",
            .amendment_of = draft_id,
        },
        &bindings,
        &snapshots,
        &.{},
    );
    var amendment = (try store.getDraft(allocator, amendment_id)).?;
    defer amendment.deinit(allocator);
    try std.testing.expectEqualStrings(draft_id, amendment.amendment_of.?);
}

test "foreign keys reject role bindings to missing profile revisions" {
    var store = try Store.openMemory(std.testing.allocator);
    defer store.close();

    const missing_bindings = [_]RoleBindingWrite{.{
        .role = "filer",
        .profile_id = "tax-profile-missing",
        .profile_revision_id = "revision-missing",
        .profile_revision_sequence = 999,
    }};
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.createDraft(
            .{
                .id = "draft-missing-profile",
                .form_code = "2551Q",
                .form_revision = "2018-01-ENCS",
                .period_key = "2026-Q1",
                .profile_as_of = testDate("2026-03-31"),
                .mapping_revision = "mapping-v1",
            },
            &missing_bindings,
            &.{},
            &.{},
        ),
    );
}

test "failed first save rolls back and immutable rows reject updates" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-rollback";
    var invalid_revision = testRevision(
        profile_id,
        0,
        "Rollback",
        "2026-01-01",
    );
    invalid_revision.source = .{ .imported = "\x00" };
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.createProfileWithRevision(
            .{ .id = profile_id },
            invalid_revision,
            .{},
        ),
    );
    try std.testing.expect(!(try store.profileExists(profile_id)));

    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Immutable", "2026-01-01"),
        .{},
    );
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\UPDATE tax_profile_revisions
            \\SET taxpayer_name = 'Mutated'
            \\WHERE profile_id = 'tax-profile-rollback';
        ),
    );
    var current = (try store.getCurrentRevision(allocator, profile_id)).?;
    defer current.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Immutable",
        current.subject.sole_proprietor.person.name,
    );
}

test "file store reopens with revisions Forms Set and drafts intact" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory_len = try tmp.dir.realPath(
        std.testing.io,
        &directory_buffer,
    );
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const database_path = try std.fmt.bufPrint(
        &path_buffer,
        "{s}/profiles.sqlite3",
        .{directory_buffer[0..directory_len]},
    );

    const profile_id = "tax-profile-reopen";
    const draft_id = "draft-reopen-2551q";
    var owner_before: OpaqueId = undefined;
    {
        var store = try Store.openDevelopmentPlaintext(
            developmentPlaintextStorageCapability(),
            allocator,
            database_path,
        );
        defer store.close();
        owner_before = try store.localOwnerId();
        try store.createProfileWithRevision(
            .{ .id = profile_id },
            testRevision(profile_id, 0, "Reopen Profile", "2026-01-01"),
            .{},
        );
        const revision_id = "revision-1";
        try store.replaceFormSet(profile_id, 2026, &.{.{
            .form_code = "2551Q",
            .form_revision = "2018-01-ENCS",
        }});
        try store.replaceCalendarFormSelection(
            profile_id,
            &.{ "1701Q", "2551Q" },
        );
        try store.createDraft(
            .{
                .id = draft_id,
                .form_code = "2551Q",
                .form_revision = "2018-01-ENCS",
                .period_key = "2026-Q1",
                .profile_as_of = testDate("2026-03-31"),
                .mapping_revision = "mapping-v1",
            },
            &.{.{
                .role = "filer",
                .profile_id = profile_id,
                .profile_revision_id = revision_id,
                .profile_revision_sequence = 1,
            }},
            &.{.{
                .role = "filer",
                .field_id = "filer.tin",
                .reusable_field = "tin",
                .value_type = "tin",
                .value_text = "123456789000",
                .provenance = "tax_profile",
                .profile_revision_id = revision_id,
                .profile_revision_sequence = 1,
                .revision_source = .{ .imported = "test fixture" },
            }},
            &.{},
        );
    }

    {
        var reopened = try Store.openDevelopmentPlaintext(
            developmentPlaintextStorageCapability(),
            allocator,
            database_path,
        );
        defer reopened.close();
        try std.testing.expectEqual(
            latest_schema_version,
            try reopened.schemaVersion(),
        );
        const owner_after = try reopened.localOwnerId();
        try std.testing.expectEqualSlices(u8, &owner_before, &owner_after);
        var revision = (try reopened.getCurrentRevision(
            allocator,
            profile_id,
        )).?;
        defer revision.deinit(allocator);
        try std.testing.expectEqualStrings(
            "Reopen Profile",
            revision.subject.sole_proprietor.person.name,
        );

        var form_set = (try reopened.getFormSet(allocator, profile_id, 2026)).?;
        defer form_set.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 1), form_set.items.len);

        var calendar_selection = (try reopened.getCalendarFormSelection(
            allocator,
            profile_id,
        )).?;
        defer calendar_selection.deinit(allocator);
        try std.testing.expectEqual(
            @as(usize, 2),
            calendar_selection.form_codes.len,
        );

        var draft = (try reopened.getDraft(allocator, draft_id)).?;
        defer draft.deinit(allocator);
        try std.testing.expectEqualStrings("123456789000", draft.snapshots[0].value_text);
    }
}

test "latest schema migrates every prior version idempotently and keeps legacy drafts" {
    for ([_]u32{ 1, 2, 3, 4, 5, 6 }) |legacy_version| {
        var store = try openLegacyStoreForTest(legacy_version);
        defer store.close();
        try std.testing.expectEqual(
            legacy_version,
            try store.schemaVersion(),
        );
        try store.migrate();
        try std.testing.expectEqual(
            latest_schema_version,
            try store.schemaVersion(),
        );
        try std.testing.expect(try tableExistsForTest(
            &store,
            "tax_exact_draft_streams",
        ));
        try std.testing.expect(try tableExistsForTest(
            &store,
            "tax_exact_draft_revisions",
        ));
        try std.testing.expect(try tableExistsForTest(
            &store,
            "tax_exact_draft_occurrences",
        ));
        try std.testing.expect(try tableExistsForTest(
            &store,
            "tax_form_drafts",
        ));
        try std.testing.expect(try tableExistsForTest(
            &store,
            "tax_profile_calendar_form_selections",
        ));
        try std.testing.expect(try tableExistsForTest(
            &store,
            "tax_form_on_demand_occurrence_counters",
        ));
        try store.migrate();
        try std.testing.expectEqual(
            latest_schema_version,
            try store.schemaVersion(),
        );
    }
}

test "schema v4 rejects future versions and rolls back a failed migration" {
    {
        var future = try openLegacyStoreForTest(3);
        defer future.close();
        try future.exec(
            \\UPDATE app_component_migrations
            \\SET version = 99
            \\WHERE component = 'tax_profile';
        );
        try std.testing.expectError(Error.SchemaTooNew, future.migrate());
        try std.testing.expect(!(try tableExistsForTest(
            &future,
            "tax_exact_draft_streams",
        )));
    }

    var store = try openLegacyStoreForTest(3);
    defer store.close();
    try store.exec(
        \\CREATE TABLE tax_exact_draft_revisions (
        \\    injected_failure INTEGER
        \\);
    );
    try std.testing.expectError(Error.SqliteFailure, store.migrate());
    try std.testing.expectEqual(@as(u32, 3), try store.schemaVersion());
    try std.testing.expect(!(try tableExistsForTest(
        &store,
        "tax_exact_draft_streams",
    )));
    try store.exec("DROP TABLE tax_exact_draft_revisions;");
    try store.migrate();
    try std.testing.expectEqual(
        latest_schema_version,
        try store.schemaVersion(),
    );
}

test "schema v4 occurrence rows preserve duplicate keys and value stages" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    // The reviewed 1701Q manifests currently happen to use unique serialized
    // keys. Exercise the persistence identity independently so a future form
    // with repeated keys cannot be collapsed by a uniqueness constraint.
    try store.beginImmediate();
    var transaction_active = true;
    defer if (transaction_active) store.rollbackNoFail();

    const workspace_id = try testDraftWorkspaceId(29);
    const exact_schema_digest = testSha256(29);
    const rows = [_]struct {
        ordinal: i64,
        same_key_occurrence: i64,
        raw_value: []const u8,
        normalized_value: []const u8,
        emitted_value: []const u8,
        origin: []const u8,
        provenance: []const u8,
    }{
        .{
            .ordinal = 1,
            .same_key_occurrence = 1,
            .raw_value = " duplicate raw one ",
            .normalized_value = "duplicate-one",
            .emitted_value = "duplicate-one",
            .origin = "profile",
            .provenance = "first duplicate occurrence",
        },
        .{
            .ordinal = 2,
            .same_key_occurrence = 2,
            .raw_value = " duplicate raw two ",
            .normalized_value = "duplicate-two",
            .emitted_value = "duplicate-two",
            .origin = "transaction",
            .provenance = "second duplicate occurrence",
        },
    };

    var insert = try store.prepare(
        \\INSERT INTO tax_exact_draft_occurrences (
        \\    workspace_id, exact_schema_digest, revision, ordinal,
        \\    serialized_key, same_key_occurrence, raw_value,
        \\    normalized_value, emitted_value, origin, provenance
        \\) VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?);
    );
    defer insert.deinit();
    for (rows) |row| {
        try insert.bindBlob(1, &workspace_id.bytes);
        try insert.bindBlob(2, exact_schema_digest.asBytes());
        try insert.bindInt64(3, row.ordinal);
        try insert.bindBlob(4, "repeated-serialized-key");
        try insert.bindInt64(5, row.same_key_occurrence);
        try insert.bindBlob(6, row.raw_value);
        try insert.bindBlob(7, row.normalized_value);
        try insert.bindBlob(8, row.emitted_value);
        try insert.bindText(9, row.origin);
        try insert.bindText(10, row.provenance);
        try insert.expectDone();
        try insert.reset();
    }

    var read = try store.prepare(
        \\SELECT ordinal, serialized_key, same_key_occurrence, raw_value,
        \\       normalized_value, emitted_value, origin, provenance
        \\FROM tax_exact_draft_occurrences
        \\WHERE workspace_id = ? AND exact_schema_digest = ? AND revision = 1
        \\ORDER BY ordinal;
    );
    defer read.deinit();
    try read.bindBlob(1, &workspace_id.bytes);
    try read.bindBlob(2, exact_schema_digest.asBytes());
    for (rows) |expected| {
        try std.testing.expect(try read.step() == .row);
        try std.testing.expectEqual(
            expected.ordinal,
            sqlite.sqlite3_column_int64(read.raw, 0),
        );
        try expectBlobColumnForTest(
            read.raw,
            1,
            "repeated-serialized-key",
        );
        try std.testing.expectEqual(
            expected.same_key_occurrence,
            sqlite.sqlite3_column_int64(read.raw, 2),
        );
        try expectBlobColumnForTest(read.raw, 3, expected.raw_value);
        try expectBlobColumnForTest(read.raw, 4, expected.normalized_value);
        try expectBlobColumnForTest(read.raw, 5, expected.emitted_value);
        try std.testing.expectEqualStrings(
            expected.origin,
            columnText(read.raw, 6) orelse return Error.SqliteFailure,
        );
        try std.testing.expectEqualStrings(
            expected.provenance,
            columnText(read.raw, 7) orelse return Error.SqliteFailure,
        );
    }
    try std.testing.expect(try read.step() == .done);

    try store.exec("ROLLBACK;");
    transaction_active = false;
}

test "forged synthetic plaintext capability cannot access or mutate exact drafts" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-forged-plaintext-authority";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(
            profile_id,
            0,
            "Forged Plaintext Authority",
            "2026-01-01",
        ),
        .{},
    );

    var forged_token: u8 = 0;
    const forged: *const key_custody.SyntheticPlaintextTestCapability =
        @ptrCast(&forged_token);
    const workspace_seed: u8 = 0x7e;
    try std.testing.expectError(
        error.InvalidSyntheticPlaintextTestCapability,
        persistTestExactRevisionWithCapability(
            forged,
            &store,
            allocator,
            profile_id,
            workspace_seed,
            .editable_save,
        ),
    );

    const schema = try exact_draft.SchemaBinding.exact1701Q(
        .editable_save,
    );
    const identity: ExactDraftIdentity = .{
        .workspace_id = try testDraftWorkspaceId(workspace_seed),
        .exact_schema_digest = schema.exact_schema_digest,
    };
    try std.testing.expectEqual(
        @as(i64, 0),
        try exactRevisionCountForTest(&store, identity),
    );
    try std.testing.expectEqual(
        @as(i64, 0),
        try exactWorkspaceCountForTest(
            &store,
            testFilingKey(profile_id),
        ),
    );

    try std.testing.expectError(
        error.InvalidSyntheticPlaintextTestCapability,
        store.getExactDraftHistory(forged, allocator, identity),
    );
    try std.testing.expectError(
        error.InvalidSyntheticPlaintextTestCapability,
        store.getExactDraftRevision(
            forged,
            allocator,
            identity,
            try DraftRevision.init(1),
        ),
    );
    try std.testing.expectError(
        error.InvalidSyntheticPlaintextTestCapability,
        store.listExactDraftAlternates(
            forged,
            allocator,
            testFilingKey(profile_id),
            null,
        ),
    );
}

test "forged public exact snapshots fail closed atomically for both shapes" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-forged-exact-snapshot";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Forged Snapshot", "2026-01-01"),
        .{},
    );

    const oversized_value = try allocator.alloc(
        u8,
        exact_document.max_value_bytes + 1,
    );
    defer allocator.free(oversized_value);
    @memset(oversized_value, 'x');
    const invalid_utf8 = [_]u8{0xff};
    const mutations = [_]ExactSnapshotForgery{
        .ordinal,
        .serialized_key,
        .same_key_occurrence,
        .origin,
        .provenance,
        .raw_utf8,
        .normalized_oversize,
        .emitted_grammar,
        .ordered_digest,
        .artifact_receipt,
    };
    const shapes = [_]exact_draft.PayloadShape{
        .editable_save,
        .final_copy_plaintext,
    };

    for (shapes, 0..) |shape, shape_index| {
        const manifest = try exactManifestForShape(shape);
        const values = try testExactValues(
            allocator,
            manifest,
            @intCast(shape_index + 1),
        );
        defer allocator.free(values);
        const contexts = try testExactContexts(allocator, manifest);
        defer allocator.free(contexts);

        var engine_history = try exact_draft.DraftHistory.initExact1701Q(
            allocator,
            try testDraftWorkspaceId(@intCast(50 + shape_index)),
            shape,
        );
        defer engine_history.deinit();
        var validation_status: exact_draft.ValidationStatus = .{
            .save_gate = .passed,
        };
        if (shape == .final_copy_plaintext) {
            validation_status.full_validation = .passed;
        }
        const base_snapshot = try engine_history.appendRevision(.create, .{
            .package_key = engine_history.schema.package_key,
            .payload_shape = shape,
            .occurrence_manifest = manifest,
            .occurrences = values,
            .profile_snapshot_digest = testSha256(80),
            .transaction_state_digest = testSha256(81),
            .validation_status = validation_status,
            .artifact_request = .plaintext,
        });
        const filing_key = testFilingKey(profile_id);
        const bindings = [_]ExactDraftRoleBindingWrite{.{
            .role = "filer",
            .instance_id = "primary",
            .profile_id = profile_id,
            .profile_revision_id = "revision-1",
            .profile_revision_sequence = 1,
            .provenance = "forged snapshot rejection fixture",
        }};

        for (mutations, 0..) |mutation, mutation_index| {
            const forged_values = try allocator.dupe(
                exact_draft.StoredOccurrenceValue,
                base_snapshot.occurrences,
            );
            defer allocator.free(forged_values);
            const forged_contexts = try allocator.dupe(
                ExactDraftOccurrenceContextWrite,
                contexts,
            );
            defer allocator.free(forged_contexts);

            var forged = base_snapshot.*;
            forged.draft_identity.workspace_id = try testDraftWorkspaceId(
                @intCast(70 + shape_index * mutations.len + mutation_index),
            );
            forged.occurrences = forged_values;

            switch (mutation) {
                .ordinal => forged_values[0].ordinal += 1,
                .serialized_key => {
                    forged_values[0].serialized_key = "forged-key";
                },
                .same_key_occurrence => {
                    forged_values[0].same_key_occurrence =
                        if (forged_values[0].same_key_occurrence == 1)
                            2
                        else
                            1;
                },
                .origin => {
                    forged_contexts[0].origin =
                        if (forged_contexts[0].origin == .profile)
                            .transaction
                        else
                            .profile;
                },
                .provenance => {
                    forged_contexts[0].provenance =
                        "forged_occurrence_provenance";
                },
                .raw_utf8 => {
                    forged_values[0].raw_value = &invalid_utf8;
                },
                .normalized_oversize => {
                    forged_values[0].normalized_value = oversized_value;
                },
                .emitted_grammar => {
                    forged_values[0].emitted_value = "<forged>";
                },
                .ordered_digest => {
                    forged.ordered_values_digest = testSha256(82);
                },
                .artifact_receipt => {
                    forged.artifact_status = switch (base_snapshot.artifact_status) {
                        .not_generated => unreachable,
                        .plaintext_candidate => |receipt| .{
                            .plaintext_candidate = .{
                                .marker = receipt.marker,
                                .byte_length = receipt.byte_length,
                                .sha256 = testSha256(83),
                            },
                        },
                        .plaintext_exact => |receipt| .{
                            .plaintext_exact = .{
                                .marker = receipt.marker,
                                .byte_length = receipt.byte_length,
                                .sha256 = testSha256(83),
                            },
                        },
                    };
                },
            }
            if (mutation != .ordered_digest) {
                forged.ordered_values_digest = exactStoredValuesDigest(
                    forged_values,
                );
            }

            const expected_error: anyerror = switch (mutation) {
                .ordered_digest => Error.DraftSchemaMismatch,
                else => Error.InvalidValue,
            };
            try std.testing.expectError(
                expected_error,
                store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
                    .filing_key = filing_key,
                    .profile_as_of = testDate("2026-03-31"),
                    .recorded_at_unix_seconds = 1_775_100_001,
                    .validation_evidence = testExactValidationEvidence(),
                    .snapshot = &forged,
                    .bindings = &bindings,
                    .occurrence_contexts = forged_contexts,
                }),
            );
            var persisted = try store.getExactDraftHistory(
                syntheticPlaintextTestCapability(),
                allocator,
                forged.draft_identity,
            );
            defer if (persisted) |*history| history.deinit(allocator);
            try std.testing.expect(persisted == null);
        }
    }
}

test "exact draft reads cap corrupted columns before large allocation" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-corrupt-exact-caps";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Corrupt Caps", "2026-01-01"),
        .{},
    );
    const editable_identity = try persistTestExactRevision(
        &store,
        allocator,
        profile_id,
        100,
        .editable_save,
    );
    const final_identity = try persistTestExactRevision(
        &store,
        allocator,
        profile_id,
        101,
        .final_copy_plaintext,
    );

    try store.exec(
        "DROP TRIGGER tax_exact_draft_occurrences_update_guard;",
    );
    try store.exec(
        "DROP TRIGGER tax_exact_draft_bindings_update_guard;",
    );

    {
        var blocked = try store.prepare(
            \\UPDATE tax_exact_draft_occurrences
            \\SET raw_value = zeroblob(?)
            \\WHERE workspace_id = ? AND exact_schema_digest = ?
            \\  AND revision = 1 AND ordinal = 1;
        );
        defer blocked.deinit();
        try blocked.bindInt64(
            1,
            @intCast(exact_document.max_value_bytes + 1),
        );
        try blocked.bindBlob(2, &editable_identity.workspace_id.bytes);
        try blocked.bindBlob(
            3,
            editable_identity.exact_schema_digest.asBytes(),
        );
        try std.testing.expectError(
            Error.SqliteConstraint,
            blocked.expectDone(),
        );
    }
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.exec(
            \\UPDATE tax_exact_draft_occurrences
            \\SET origin = 'unreviewed'
            \\WHERE ordinal = 1;
        ),
    );
    {
        var blocked = try store.prepare(
            \\UPDATE tax_exact_draft_revision_bindings
            \\SET provenance = CAST(zeroblob(?) AS TEXT)
            \\WHERE workspace_id = ? AND exact_schema_digest = ?
            \\  AND revision = 1 AND role = 'filer';
        );
        defer blocked.deinit();
        try blocked.bindInt64(1, max_exact_provenance_bytes + 1);
        try blocked.bindBlob(2, &final_identity.workspace_id.bytes);
        try blocked.bindBlob(
            3,
            final_identity.exact_schema_digest.asBytes(),
        );
        try std.testing.expectError(
            Error.SqliteConstraint,
            blocked.expectDone(),
        );
    }

    try store.exec("PRAGMA ignore_check_constraints = ON;");
    {
        var corrupt = try store.prepare(
            \\UPDATE tax_exact_draft_occurrences
            \\SET raw_value = zeroblob(?)
            \\WHERE workspace_id = ? AND exact_schema_digest = ?
            \\  AND revision = 1 AND ordinal = 1;
        );
        defer corrupt.deinit();
        try corrupt.bindInt64(
            1,
            @intCast(exact_document.max_value_bytes + 1),
        );
        try corrupt.bindBlob(2, &editable_identity.workspace_id.bytes);
        try corrupt.bindBlob(
            3,
            editable_identity.exact_schema_digest.asBytes(),
        );
        try corrupt.expectDone();
    }
    {
        var corrupt = try store.prepare(
            \\UPDATE tax_exact_draft_revision_bindings
            \\SET provenance = CAST(zeroblob(?) AS TEXT)
            \\WHERE workspace_id = ? AND exact_schema_digest = ?
            \\  AND revision = 1 AND role = 'filer';
        );
        defer corrupt.deinit();
        try corrupt.bindInt64(1, max_exact_provenance_bytes + 1);
        try corrupt.bindBlob(2, &final_identity.workspace_id.bytes);
        try corrupt.bindBlob(
            3,
            final_identity.exact_schema_digest.asBytes(),
        );
        try corrupt.expectDone();
    }
    try store.exec("PRAGMA ignore_check_constraints = OFF;");

    var editable_backing: [64 * 1024]u8 = undefined;
    var editable_fixed = std.heap.FixedBufferAllocator.init(
        &editable_backing,
    );
    try std.testing.expectError(
        Error.SqliteFailure,
        store.getExactDraftHistory(
            syntheticPlaintextTestCapability(),
            editable_fixed.allocator(),
            editable_identity,
        ),
    );

    var final_backing: [64 * 1024]u8 = undefined;
    var final_fixed = std.heap.FixedBufferAllocator.init(&final_backing);
    try std.testing.expectError(
        Error.SqliteFailure,
        store.getExactDraftHistory(
            syntheticPlaintextTestCapability(),
            final_fixed.allocator(),
            final_identity,
        ),
    );
}

test "validation evidence receipt is typed immutable and preflighted" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-validation-evidence";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Validation Evidence", "2026-01-01"),
        .{},
    );
    const editable_identity = try persistTestExactRevision(
        &store,
        allocator,
        profile_id,
        116,
        .editable_save,
    );
    const final_identity = try persistTestExactRevision(
        &store,
        allocator,
        profile_id,
        117,
        .final_copy_plaintext,
    );

    try store.exec(
        "DROP TRIGGER tax_exact_draft_revisions_update_guard;",
    );
    try store.exec("PRAGMA ignore_check_constraints = ON;");
    {
        var corrupt = try store.prepare(
            \\UPDATE tax_exact_draft_revisions
            \\SET validation_current_year = 2147483648
            \\WHERE workspace_id = ? AND exact_schema_digest = ?;
        );
        defer corrupt.deinit();
        try corrupt.bindBlob(1, &editable_identity.workspace_id.bytes);
        try corrupt.bindBlob(
            2,
            editable_identity.exact_schema_digest.asBytes(),
        );
        try corrupt.expectDone();
    }
    {
        var corrupt = try store.prepare(
            \\UPDATE tax_exact_draft_revisions
            \\SET spouse_tin_checksum = 'caller_reconstructed'
            \\WHERE workspace_id = ? AND exact_schema_digest = ?;
        );
        defer corrupt.deinit();
        try corrupt.bindBlob(1, &final_identity.workspace_id.bytes);
        try corrupt.bindBlob(
            2,
            final_identity.exact_schema_digest.asBytes(),
        );
        try corrupt.expectDone();
    }
    try store.exec("PRAGMA ignore_check_constraints = OFF;");

    var no_backing: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_backing);
    try std.testing.expectError(
        Error.SqliteFailure,
        store.getExactDraftHistory(
            syntheticPlaintextTestCapability(),
            fixed.allocator(),
            editable_identity,
        ),
    );
    try std.testing.expectError(
        Error.SqliteFailure,
        store.getExactDraftHistory(
            syntheticPlaintextTestCapability(),
            fixed.allocator(),
            final_identity,
        ),
    );
}

test "exact draft reads reject extra persisted rows for both shapes" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();

    const profile_id = "tax-profile-extra-exact-row";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Extra Row", "2026-01-01"),
        .{},
    );
    const shapes = [_]exact_draft.PayloadShape{
        .editable_save,
        .final_copy_plaintext,
    };
    for (shapes, 0..) |shape, index| {
        const identity = try persistTestExactRevision(
            &store,
            allocator,
            profile_id,
            @intCast(110 + index),
            shape,
        );
        const manifest = try exactManifestForShape(shape);
        var inject = try store.prepare(
            \\INSERT INTO tax_exact_draft_occurrences (
            \\    workspace_id, exact_schema_digest, revision, ordinal,
            \\    serialized_key, same_key_occurrence, raw_value,
            \\    normalized_value, emitted_value, origin, provenance
            \\) VALUES (?, ?, 1, ?, ?, 1, ?, ?, ?, ?, ?);
        );
        defer inject.deinit();
        try inject.bindBlob(1, &identity.workspace_id.bytes);
        try inject.bindBlob(2, identity.exact_schema_digest.asBytes());
        try inject.bindInt64(3, @intCast(manifest.items.len + 1));
        try inject.bindBlob(4, "unexpected-row");
        try inject.bindBlob(5, "");
        try inject.bindBlob(6, "");
        try inject.bindBlob(7, "");
        try inject.bindText(8, "profile");
        try inject.bindText(9, "immutable_profile_revision_binding");
        try inject.expectDone();

        var backing: [64 * 1024]u8 = undefined;
        var fixed = std.heap.FixedBufferAllocator.init(&backing);
        try std.testing.expectError(
            Error.SqliteFailure,
            store.getExactDraftHistory(
                syntheticPlaintextTestCapability(),
                fixed.allocator(),
                identity,
            ),
        );
    }
}

test "exact history aggregate preflight and append fail before allocation" {
    const allocator = std.testing.allocator;
    const shapes = [_]exact_draft.PayloadShape{
        .editable_save,
        .final_copy_plaintext,
    };
    for (shapes, 0..) |shape, shape_index| {
        var store = try Store.openMemory(allocator);
        defer store.close();
        const profile_id = switch (shape) {
            .editable_save => "tax-profile-history-bytes-editable",
            .final_copy_plaintext => "tax-profile-history-bytes-final",
        };
        try store.createProfileWithRevision(
            .{ .id = profile_id },
            testRevision(profile_id, 0, "History Bytes", "2026-01-01"),
            .{},
        );
        const manifest = try exactManifestForShape(shape);
        const values = try testExactValues(
            allocator,
            manifest,
            @intCast(shape_index + 1),
        );
        defer allocator.free(values);
        const contexts = try testExactContexts(allocator, manifest);
        defer allocator.free(contexts);
        var engine_history = try exact_draft.DraftHistory.initExact1701Q(
            allocator,
            try testDraftWorkspaceId(@intCast(130 + shape_index)),
            shape,
        );
        defer engine_history.deinit();
        const first = try engine_history.appendRevision(.create, .{
            .package_key = engine_history.schema.package_key,
            .payload_shape = shape,
            .occurrence_manifest = manifest,
            .occurrences = values,
            .profile_snapshot_digest = testSha256(130),
            .transaction_state_digest = testSha256(131),
        });
        const second = try engine_history.appendRevision(
            .{ .match = first.revision },
            .{
                .package_key = engine_history.schema.package_key,
                .payload_shape = shape,
                .occurrence_manifest = manifest,
                .occurrences = values,
                .profile_snapshot_digest = testSha256(132),
                .transaction_state_digest = testSha256(133),
            },
        );
        const bindings = [_]ExactDraftRoleBindingWrite{.{
            .role = "filer",
            .instance_id = "primary",
            .profile_id = profile_id,
            .profile_revision_id = "revision-1",
            .profile_revision_sequence = 1,
            .provenance = "bounded exact history fixture",
        }};
        const filing_key = testFilingKey(profile_id);
        try store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
            .filing_key = filing_key,
            .profile_as_of = testDate("2026-03-31"),
            .recorded_at_unix_seconds = 1_775_300_001,
            .validation_evidence = testExactValidationEvidence(),
            .snapshot = first,
            .bindings = &bindings,
            .occurrence_contexts = contexts,
        });

        try store.exec(
            "DROP TRIGGER tax_exact_draft_occurrences_update_guard;",
        );
        var corrupt = try store.prepare(
            \\UPDATE tax_exact_draft_occurrences
            \\SET raw_value = zeroblob(400000)
            \\WHERE workspace_id = ? AND exact_schema_digest = ?;
        );
        defer corrupt.deinit();
        try corrupt.bindBlob(1, &first.draft_identity.workspace_id.bytes);
        try corrupt.bindBlob(
            2,
            first.draft_identity.exact_schema_digest.asBytes(),
        );
        try corrupt.expectDone();

        var no_backing: [0]u8 = .{};
        var fixed = std.heap.FixedBufferAllocator.init(&no_backing);
        try std.testing.expectError(
            Error.DraftRetainedValueLimitExceeded,
            store.getExactDraftHistory(
                syntheticPlaintextTestCapability(),
                fixed.allocator(),
                first.draft_identity,
            ),
        );
        try std.testing.expectError(
            Error.DraftRetainedValueLimitExceeded,
            store.appendExactDraftRevision(
                syntheticPlaintextTestCapability(),
                .{ .match = first.revision },
                .{
                    .filing_key = filing_key,
                    .profile_as_of = testDate("2026-03-31"),
                    .recorded_at_unix_seconds = 1_775_300_002,
                    .validation_evidence = testExactValidationEvidence(),
                    .snapshot = second,
                    .bindings = &bindings,
                    .occurrence_contexts = contexts,
                },
            ),
        );
        try std.testing.expectEqual(
            @as(i64, 1),
            try exactRevisionCountForTest(
                &store,
                first.draft_identity,
            ),
        );
    }
}

test "exact history revision cap is atomic and full reads use cap plus one" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();
    const profile_id = "tax-profile-history-revision-cap";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "History Revision Cap", "2026-01-01"),
        .{},
    );
    const manifest = try exactManifestForShape(.editable_save);
    const values = try testExactValues(allocator, manifest, 1);
    defer allocator.free(values);
    const contexts = try testExactContexts(allocator, manifest);
    defer allocator.free(contexts);
    var engine_history = try exact_draft.DraftHistory.initExact1701Q(
        allocator,
        try testDraftWorkspaceId(140),
        .editable_save,
    );
    defer engine_history.deinit();
    const first = try engine_history.appendRevision(.create, .{
        .package_key = engine_history.schema.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = manifest,
        .occurrences = values,
        .profile_snapshot_digest = testSha256(140),
        .transaction_state_digest = testSha256(141),
    });
    const bindings = [_]ExactDraftRoleBindingWrite{.{
        .role = "filer",
        .instance_id = "primary",
        .profile_id = profile_id,
        .profile_revision_id = "revision-1",
        .profile_revision_sequence = 1,
        .provenance = "revision limit fixture",
    }};
    try store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
        .filing_key = testFilingKey(profile_id),
        .profile_as_of = testDate("2026-03-31"),
        .recorded_at_unix_seconds = 1_775_400_001,
        .validation_evidence = testExactValidationEvidence(),
        .snapshot = first,
        .bindings = &bindings,
        .occurrence_contexts = contexts,
    });

    try store.exec(
        "DROP TRIGGER tax_exact_draft_revision_occurrence_guard;",
    );
    try store.exec(
        "DROP TRIGGER tax_exact_draft_revision_binding_guard;",
    );
    try store.exec(
        \\CREATE TEMP TABLE injected_exact_revision AS
        \\SELECT *
        \\FROM tax_exact_draft_revisions
        \\WHERE revision = 1;
    );
    var update_clone = try store.prepare(
        \\UPDATE injected_exact_revision
        \\SET revision = ?, parent_revision = ?;
    );
    defer update_clone.deinit();
    for (2..exact_draft.max_revisions_per_exact_shape_stream + 1) |revision| {
        try update_clone.bindInt64(1, @intCast(revision));
        try update_clone.bindInt64(2, @intCast(revision - 1));
        try update_clone.expectDone();
        try update_clone.reset();
        try store.exec(
            \\INSERT INTO tax_exact_draft_revisions
            \\SELECT * FROM injected_exact_revision;
        );
    }
    try std.testing.expectEqual(
        @as(i64, @intCast(
            exact_draft.max_revisions_per_exact_shape_stream,
        )),
        try exactRevisionCountForTest(&store, first.draft_identity),
    );

    var over_limit = first.*;
    over_limit.revision = try DraftRevision.init(
        exact_draft.max_revisions_per_exact_shape_stream + 1,
    );
    over_limit.parent_revision = try DraftRevision.init(
        exact_draft.max_revisions_per_exact_shape_stream,
    );
    try std.testing.expectError(
        Error.DraftRevisionLimitExceeded,
        store.appendExactDraftRevision(
            syntheticPlaintextTestCapability(),
            .{
                .match = try DraftRevision.init(
                    exact_draft.max_revisions_per_exact_shape_stream,
                ),
            },
            .{
                .filing_key = testFilingKey(profile_id),
                .profile_as_of = testDate("2026-03-31"),
                .recorded_at_unix_seconds = 1_775_400_002,
                .validation_evidence = testExactValidationEvidence(),
                .snapshot = &over_limit,
                .bindings = &bindings,
                .occurrence_contexts = contexts,
            },
        ),
    );
    try std.testing.expectEqual(
        @as(i64, @intCast(
            exact_draft.max_revisions_per_exact_shape_stream,
        )),
        try exactRevisionCountForTest(&store, first.draft_identity),
    );

    try store.exec("PRAGMA ignore_check_constraints = ON;");
    try update_clone.bindInt64(
        1,
        @intCast(
            exact_draft.max_revisions_per_exact_shape_stream + 1,
        ),
    );
    try update_clone.bindInt64(
        2,
        @intCast(exact_draft.max_revisions_per_exact_shape_stream),
    );
    try update_clone.expectDone();
    try update_clone.reset();
    try store.exec(
        \\INSERT INTO tax_exact_draft_revisions
        \\SELECT * FROM injected_exact_revision;
    );
    try store.exec("PRAGMA ignore_check_constraints = OFF;");

    var no_backing: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_backing);
    try std.testing.expectError(
        Error.DraftRevisionLimitExceeded,
        store.getExactDraftHistory(
            syntheticPlaintextTestCapability(),
            fixed.allocator(),
            first.draft_identity,
        ),
    );
    var bounded_single = (try store.getExactDraftRevision(
        syntheticPlaintextTestCapability(),
        allocator,
        first.draft_identity,
        try DraftRevision.init(1),
    )).?;
    defer bounded_single.deinit(allocator);
    try std.testing.expectEqual(
        @as(usize, manifest.items.len),
        bounded_single.occurrences.len,
    );
}

test "alternate listing succeeds at its cap and rejects cap plus one" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();
    const profile_id = "tax-profile-alternate-cap";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Alternate Cap", "2026-01-01"),
        .{},
    );
    const base_identity = try persistTestExactRevision(
        &store,
        allocator,
        profile_id,
        180,
        .editable_save,
    );
    try store.exec(
        \\CREATE TEMP TABLE injected_exact_stream AS
        \\SELECT *
        \\FROM tax_exact_draft_streams
        \\WHERE workspace_id IS NOT NULL
        \\LIMIT 1;
    );
    var update_workspace = try store.prepare(
        \\UPDATE injected_exact_stream
        \\SET workspace_id = ?;
    );
    defer update_workspace.deinit();
    for (1..max_returned_exact_draft_alternates + 1) |index| {
        const workspace_id = try testDraftWorkspaceId(@intCast(index));
        try update_workspace.bindBlob(1, &workspace_id.bytes);
        try update_workspace.expectDone();
        try update_workspace.reset();
        try store.exec(
            \\INSERT INTO tax_exact_draft_streams
            \\SELECT * FROM injected_exact_stream;
        );
    }
    var at_boundary = try store.listExactDraftAlternates(
        syntheticPlaintextTestCapability(),
        allocator,
        testFilingKey(profile_id),
        base_identity.workspace_id,
    );
    defer at_boundary.deinit(allocator);
    try std.testing.expectEqual(
        max_returned_exact_draft_alternates,
        at_boundary.items.len,
    );

    const extra_workspace = try testDraftWorkspaceId(
        max_returned_exact_draft_alternates + 1,
    );
    try update_workspace.bindBlob(1, &extra_workspace.bytes);
    try update_workspace.expectDone();
    try update_workspace.reset();
    try store.exec(
        \\INSERT INTO tax_exact_draft_streams
        \\SELECT * FROM injected_exact_stream;
    );
    try std.testing.expectError(
        Error.DraftAlternateLimitExceeded,
        store.listExactDraftAlternates(
            syntheticPlaintextTestCapability(),
            allocator,
            testFilingKey(profile_id),
            base_identity.workspace_id,
        ),
    );
}

test "workspace creation cap is transactional and permits sibling shape" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();
    const profile_id = "tax-profile-workspace-cap";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Workspace Cap", "2026-01-01"),
        .{},
    );
    _ = try persistTestExactRevision(
        &store,
        allocator,
        profile_id,
        200,
        .editable_save,
    );
    try store.exec(
        \\CREATE TEMP TABLE capped_exact_stream AS
        \\SELECT *
        \\FROM tax_exact_draft_streams
        \\LIMIT 1;
    );
    var update_workspace = try store.prepare(
        \\UPDATE capped_exact_stream
        \\SET workspace_id = ?;
    );
    defer update_workspace.deinit();
    for (1..max_exact_workspaces_per_filing_business_key - 1) |index| {
        const workspace_id = try testDraftWorkspaceId(@intCast(index));
        try update_workspace.bindBlob(1, &workspace_id.bytes);
        try update_workspace.expectDone();
        try update_workspace.reset();
        try store.exec(
            \\INSERT INTO tax_exact_draft_streams
            \\SELECT * FROM capped_exact_stream;
        );
    }
    try std.testing.expectEqual(
        @as(i64, @intCast(
            max_exact_workspaces_per_filing_business_key - 1,
        )),
        try exactWorkspaceCountForTest(
            &store,
            testFilingKey(profile_id),
        ),
    );

    const editable_manifest = try exactManifestForShape(.editable_save);
    const editable_values = try testExactValues(
        allocator,
        editable_manifest,
        1,
    );
    defer allocator.free(editable_values);
    const editable_contexts = try testExactContexts(
        allocator,
        editable_manifest,
    );
    defer allocator.free(editable_contexts);
    const accepted_workspace = try testDraftWorkspaceId(201);
    var editable_history = try exact_draft.DraftHistory.initExact1701Q(
        allocator,
        accepted_workspace,
        .editable_save,
    );
    defer editable_history.deinit();
    const accepted = try editable_history.appendRevision(.create, .{
        .package_key = editable_history.schema.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = editable_manifest,
        .occurrences = editable_values,
        .profile_snapshot_digest = testSha256(201),
        .transaction_state_digest = testSha256(202),
    });
    const bindings = [_]ExactDraftRoleBindingWrite{.{
        .role = "filer",
        .instance_id = "primary",
        .profile_id = profile_id,
        .profile_revision_id = "revision-1",
        .profile_revision_sequence = 1,
        .provenance = "workspace cap fixture",
    }};
    const filing_key = testFilingKey(profile_id);
    try store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
        .filing_key = filing_key,
        .profile_as_of = testDate("2026-03-31"),
        .recorded_at_unix_seconds = 1_775_500_001,
        .validation_evidence = testExactValidationEvidence(),
        .snapshot = accepted,
        .bindings = &bindings,
        .occurrence_contexts = editable_contexts,
    });
    try std.testing.expectEqual(
        @as(i64, @intCast(
            max_exact_workspaces_per_filing_business_key,
        )),
        try exactWorkspaceCountForTest(&store, filing_key),
    );

    var rejected = accepted.*;
    rejected.draft_identity.workspace_id = try testDraftWorkspaceId(202);
    try std.testing.expectError(
        Error.DraftWorkspaceLimitExceeded,
        store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
            .filing_key = filing_key,
            .profile_as_of = testDate("2026-03-31"),
            .recorded_at_unix_seconds = 1_775_500_002,
            .validation_evidence = testExactValidationEvidence(),
            .snapshot = &rejected,
            .bindings = &bindings,
            .occurrence_contexts = editable_contexts,
        }),
    );
    try std.testing.expectEqual(
        @as(i64, @intCast(
            max_exact_workspaces_per_filing_business_key,
        )),
        try exactWorkspaceCountForTest(&store, filing_key),
    );
    var rejected_history = try store.getExactDraftHistory(
        syntheticPlaintextTestCapability(),
        allocator,
        rejected.draft_identity,
    );
    defer if (rejected_history) |*history| history.deinit(allocator);
    try std.testing.expect(rejected_history == null);

    const final_manifest = try exactManifestForShape(
        .final_copy_plaintext,
    );
    const final_values = try testExactValues(allocator, final_manifest, 2);
    defer allocator.free(final_values);
    const final_contexts = try testExactContexts(
        allocator,
        final_manifest,
    );
    defer allocator.free(final_contexts);
    var final_history = try exact_draft.DraftHistory.initExact1701Q(
        allocator,
        accepted_workspace,
        .final_copy_plaintext,
    );
    defer final_history.deinit();
    const final_snapshot = try final_history.appendRevision(.create, .{
        .package_key = final_history.schema.package_key,
        .payload_shape = .final_copy_plaintext,
        .occurrence_manifest = final_manifest,
        .occurrences = final_values,
        .profile_snapshot_digest = testSha256(203),
        .transaction_state_digest = testSha256(204),
    });
    var conflicting_key = filing_key;
    conflicting_key.period_key = "2026-Q2";
    try std.testing.expectError(
        Error.DraftSchemaMismatch,
        store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
            .filing_key = conflicting_key,
            .profile_as_of = testDate("2026-03-31"),
            .recorded_at_unix_seconds = 1_775_500_003,
            .validation_evidence = testExactValidationEvidence(),
            .snapshot = final_snapshot,
            .bindings = &bindings,
            .occurrence_contexts = final_contexts,
        }),
    );
    try std.testing.expectEqual(
        @as(i64, @intCast(
            max_exact_workspaces_per_filing_business_key,
        )),
        try exactWorkspaceCountForTest(&store, filing_key),
    );
    var rejected_sibling = try store.getExactDraftHistory(
        syntheticPlaintextTestCapability(),
        allocator,
        final_snapshot.draft_identity,
    );
    defer if (rejected_sibling) |*history| history.deinit(allocator);
    try std.testing.expect(rejected_sibling == null);
    try store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
        .filing_key = filing_key,
        .profile_as_of = testDate("2026-03-31"),
        .recorded_at_unix_seconds = 1_775_500_004,
        .validation_evidence = testExactValidationEvidence(),
        .snapshot = final_snapshot,
        .bindings = &bindings,
        .occurrence_contexts = final_contexts,
    });
    try std.testing.expectEqual(
        @as(i64, @intCast(
            max_exact_workspaces_per_filing_business_key,
        )),
        try exactWorkspaceCountForTest(&store, filing_key),
    );
}

test "persisted readiness is metadata and cannot override built-in evidence" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();
    const profile_id = "tax-profile-readiness-authority";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Readiness Authority", "2026-01-01"),
        .{},
    );
    const identity = try persistTestExactRevision(
        &store,
        allocator,
        profile_id,
        181,
        .editable_save,
    );
    try store.exec(
        "DROP TRIGGER tax_exact_draft_revisions_update_guard;",
    );
    try store.exec(
        \\UPDATE tax_exact_draft_revisions
        \\SET readiness_ui_integrated =
        \\    CASE readiness_ui_integrated WHEN 0 THEN 1 ELSE 0 END;
    );
    try std.testing.expectError(
        Error.DraftSchemaMismatch,
        store.getExactDraftHistory(
            syntheticPlaintextTestCapability(),
            allocator,
            identity,
        ),
    );
}

test "exact draft revisions reopen byte-for-byte and retain old profile bindings" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory_len = try tmp.dir.realPath(
        std.testing.io,
        &directory_buffer,
    );
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const database_path = try std.fmt.bufPrint(
        &path_buffer,
        "{s}/exact-drafts.sqlite3",
        .{directory_buffer[0..directory_len]},
    );

    const profile_id = "tax-profile-exact-reopen";
    const workspace_id = try testDraftWorkspaceId(31);
    var before_reopen: ?OwnedExactDraftHistory = null;
    defer if (before_reopen) |*history| history.deinit(allocator);

    {
        var store = try Store.openDevelopmentPlaintext(
            developmentPlaintextStorageCapability(),
            allocator,
            database_path,
        );
        defer store.close();
        try store.createProfileWithRevision(
            .{ .id = profile_id },
            testRevision(profile_id, 0, "Original Profile", "2026-01-01"),
            .{},
        );

        const manifest = try exact_form_occurrences.editableManifest();
        const values = try testExactValues(allocator, manifest, 1);
        defer allocator.free(values);
        const contexts = try testExactContexts(allocator, manifest);
        defer allocator.free(contexts);
        var engine_history = try exact_draft.DraftHistory.initExact1701Q(
            allocator,
            workspace_id,
            .editable_save,
        );
        defer engine_history.deinit();

        const first_snapshot = try engine_history.appendRevision(.create, .{
            .package_key = engine_history.schema.package_key,
            .payload_shape = .editable_save,
            .occurrence_manifest = manifest,
            .occurrences = values,
            .profile_snapshot_digest = testSha256(1),
            .transaction_state_digest = testSha256(2),
        });
        const filing_key = testFilingKey(profile_id);
        const first_bindings = [_]ExactDraftRoleBindingWrite{.{
            .role = "filer",
            .instance_id = "primary",
            .profile_id = profile_id,
            .profile_revision_id = "revision-1",
            .profile_revision_sequence = 1,
            .provenance = "profile snapshot revision 1",
        }};
        try store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
            .filing_key = filing_key,
            .profile_as_of = testDate("2026-03-31"),
            .recorded_at_unix_seconds = 1_775_000_001,
            .validation_evidence = testExactValidationEvidence(),
            .snapshot = first_snapshot,
            .bindings = &first_bindings,
            .occurrence_contexts = contexts,
        });

        try store.appendRevision(
            testRevision(profile_id, 1, "Evolved Profile", "2026-04-01"),
            .{},
        );
        seedTestExactValues(values, manifest, 2);
        const second_snapshot = try engine_history.appendRevision(
            .{ .match = first_snapshot.revision },
            .{
                .package_key = engine_history.schema.package_key,
                .payload_shape = .editable_save,
                .occurrence_manifest = manifest,
                .occurrences = values,
                .profile_snapshot_digest = testSha256(3),
                .transaction_state_digest = testSha256(4),
                .validation_status = .{ .save_gate = .passed },
                .artifact_request = .plaintext,
            },
        );
        const second_bindings = [_]ExactDraftRoleBindingWrite{.{
            .role = "filer",
            .instance_id = "primary",
            .profile_id = profile_id,
            .profile_revision_id = "revision-2",
            .profile_revision_sequence = 2,
            .provenance = "accepted profile refresh revision 2",
        }};
        try store.appendExactDraftRevision(
            syntheticPlaintextTestCapability(),
            .{ .match = first_snapshot.revision },
            .{
                .filing_key = filing_key,
                .profile_as_of = testDate("2026-06-30"),
                .recorded_at_unix_seconds = 1_775_000_002,
                .validation_evidence = .{
                    .validation_current_year = 2027,
                    .spouse_tin_checksum = .valid,
                },
                .snapshot = second_snapshot,
                .bindings = &second_bindings,
                .occurrence_contexts = contexts,
            },
        );

        seedTestExactValues(values, manifest, 3);
        const uncommitted_third = try engine_history.appendRevision(
            .{ .match = second_snapshot.revision },
            .{
                .package_key = engine_history.schema.package_key,
                .payload_shape = .editable_save,
                .occurrence_manifest = manifest,
                .occurrences = values,
                .profile_snapshot_digest = testSha256(5),
                .transaction_state_digest = testSha256(6),
            },
        );
        try std.testing.expectError(
            Error.DraftStaleRevision,
            store.appendExactDraftRevision(
                syntheticPlaintextTestCapability(),
                .{ .match = first_snapshot.revision },
                .{
                    .filing_key = filing_key,
                    .profile_as_of = testDate("2026-06-30"),
                    .recorded_at_unix_seconds = 1_775_000_003,
                    .validation_evidence = testExactValidationEvidence(),
                    .snapshot = uncommitted_third,
                    .bindings = &second_bindings,
                    .occurrence_contexts = contexts,
                },
            ),
        );

        const draft_identity = first_snapshot.draft_identity;
        before_reopen = (try store.getExactDraftHistory(
            syntheticPlaintextTestCapability(),
            allocator,
            draft_identity,
        )).?;
        try std.testing.expectEqual(
            @as(usize, 2),
            before_reopen.?.revisions.len,
        );
        try std.testing.expectEqualStrings(
            "revision-1",
            before_reopen.?.revisions[0].bindings[0].profile_revision_id,
        );
        try std.testing.expectEqualStrings(
            "revision-2",
            before_reopen.?.revisions[1].bindings[0].profile_revision_id,
        );
        try std.testing.expectEqual(
            @as(i32, 2026),
            before_reopen.?.revisions[0]
                .validation_evidence.validation_current_year,
        );
        try std.testing.expectEqual(
            exact_validation.TinChecksumStatus.not_evaluated,
            before_reopen.?.revisions[0]
                .validation_evidence.spouse_tin_checksum,
        );
        try std.testing.expectEqual(
            @as(i32, 2027),
            before_reopen.?.revisions[1]
                .validation_evidence.validation_current_year,
        );
        try std.testing.expectEqual(
            exact_validation.TinChecksumStatus.valid,
            before_reopen.?.revisions[1]
                .validation_evidence.spouse_tin_checksum,
        );
        try expectSeededExactOccurrenceRoundTrip(
            &before_reopen.?.revisions[0],
        );
        try std.testing.expectError(
            Error.SqliteConstraint,
            store.exec(
                \\UPDATE tax_exact_draft_occurrences
                \\SET raw_value = raw_value;
            ),
        );
        try std.testing.expectError(
            Error.SqliteConstraint,
            store.exec(
                \\UPDATE tax_exact_draft_revisions
                \\SET validation_current_year = 2028;
            ),
        );
        try std.testing.expectError(
            Error.SqliteConstraint,
            store.exec(
                \\DELETE FROM tax_exact_draft_revisions;
            ),
        );
    }

    {
        var reopened = try Store.openDevelopmentPlaintext(
            developmentPlaintextStorageCapability(),
            allocator,
            database_path,
        );
        defer reopened.close();
        const editable_schema = try exact_draft.SchemaBinding.exact1701Q(
            .editable_save,
        );
        const identity: ExactDraftIdentity = .{
            .workspace_id = workspace_id,
            .exact_schema_digest = editable_schema.exact_schema_digest,
        };
        var after_reopen = (try reopened.getExactDraftHistory(
            syntheticPlaintextTestCapability(),
            allocator,
            identity,
        )).?;
        defer after_reopen.deinit(allocator);
        try expectExactDraftHistoriesEqual(
            &before_reopen.?,
            &after_reopen,
        );

        const sensitive_backing = try allocator.alloc(u8, 256 * 1024);
        defer allocator.free(sensitive_backing);
        @memset(sensitive_backing, 0xaa);
        var fixed = std.heap.FixedBufferAllocator.init(sensitive_backing);
        var wipe_history = (try reopened.getExactDraftHistory(
            syntheticPlaintextTestCapability(),
            fixed.allocator(),
            identity,
        )).?;
        const first_value = wipe_history.revisions[0].occurrences[0];
        const raw_offset =
            @intFromPtr(first_value.raw_value.ptr) -
            @intFromPtr(sensitive_backing.ptr);
        const normalized_offset =
            @intFromPtr(first_value.normalized_value.ptr) -
            @intFromPtr(sensitive_backing.ptr);
        const emitted_offset =
            @intFromPtr(first_value.emitted_value.ptr) -
            @intFromPtr(sensitive_backing.ptr);
        const raw_len = first_value.raw_value.len;
        const normalized_len = first_value.normalized_value.len;
        const emitted_len = first_value.emitted_value.len;
        wipe_history.deinit(fixed.allocator());
        try expectAllZero(
            sensitive_backing[raw_offset .. raw_offset + raw_len],
        );
        try expectAllZero(
            sensitive_backing[normalized_offset .. normalized_offset + normalized_len],
        );
        try expectAllZero(
            sensitive_backing[emitted_offset .. emitted_offset + emitted_len],
        );
    }
}

test "exact draft transaction rollback removes a failed new stream" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();
    const profile_id = "tax-profile-exact-rollback";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Rollback Profile", "2026-01-01"),
        .{},
    );

    const workspace_id = try testDraftWorkspaceId(41);
    const manifest = try exact_form_occurrences.editableManifest();
    const values = try testExactValues(allocator, manifest, 1);
    defer allocator.free(values);
    const contexts = try testExactContexts(allocator, manifest);
    defer allocator.free(contexts);
    var engine_history = try exact_draft.DraftHistory.initExact1701Q(
        allocator,
        workspace_id,
        .editable_save,
    );
    defer engine_history.deinit();
    const snapshot = try engine_history.appendRevision(.create, .{
        .package_key = engine_history.schema.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = manifest,
        .occurrences = values,
        .profile_snapshot_digest = testSha256(7),
        .transaction_state_digest = testSha256(8),
    });
    const invalid_bindings = [_]ExactDraftRoleBindingWrite{.{
        .role = "filer",
        .instance_id = "primary",
        .profile_id = profile_id,
        .profile_revision_id = "missing-revision",
        .profile_revision_sequence = 1,
        .provenance = "synthetic rollback fixture",
    }};
    try std.testing.expectError(
        Error.SqliteConstraint,
        store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
            .filing_key = testFilingKey(profile_id),
            .profile_as_of = testDate("2026-03-31"),
            .recorded_at_unix_seconds = 1_775_000_010,
            .validation_evidence = testExactValidationEvidence(),
            .snapshot = snapshot,
            .bindings = &invalid_bindings,
            .occurrence_contexts = contexts,
        }),
    );
    try std.testing.expect(
        try store.getExactDraftHistory(
            syntheticPlaintextTestCapability(),
            allocator,
            snapshot.draft_identity,
        ) == null,
    );
}

test "editable and Final Copy share a workspace without becoming alternates" {
    const allocator = std.testing.allocator;
    var store = try Store.openMemory(allocator);
    defer store.close();
    const random_workspace_one = try store.generateDraftWorkspaceId();
    const random_workspace_two = try store.generateDraftWorkspaceId();
    try std.testing.expect(!random_workspace_one.eql(&random_workspace_two));
    const profile_id = "tax-profile-exact-shapes";
    try store.createProfileWithRevision(
        .{ .id = profile_id },
        testRevision(profile_id, 0, "Two Shapes", "2026-01-01"),
        .{},
    );
    const filing_key = testFilingKey(profile_id);
    const bindings = [_]ExactDraftRoleBindingWrite{.{
        .role = "filer",
        .instance_id = "primary",
        .profile_id = profile_id,
        .profile_revision_id = "revision-1",
        .profile_revision_sequence = 1,
        .provenance = "shape sharing fixture",
    }};
    const shared_workspace = try testDraftWorkspaceId(51);

    const editable_manifest = try exact_form_occurrences.editableManifest();
    const editable_values = try testExactValues(
        allocator,
        editable_manifest,
        1,
    );
    defer allocator.free(editable_values);
    const editable_contexts = try testExactContexts(
        allocator,
        editable_manifest,
    );
    defer allocator.free(editable_contexts);
    var editable_history = try exact_draft.DraftHistory.initExact1701Q(
        allocator,
        shared_workspace,
        .editable_save,
    );
    defer editable_history.deinit();
    const editable = try editable_history.appendRevision(.create, .{
        .package_key = editable_history.schema.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = editable_manifest,
        .occurrences = editable_values,
        .profile_snapshot_digest = testSha256(9),
        .transaction_state_digest = testSha256(10),
    });
    try store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
        .filing_key = filing_key,
        .profile_as_of = testDate("2026-03-31"),
        .recorded_at_unix_seconds = 1_775_000_020,
        .validation_evidence = testExactValidationEvidence(),
        .snapshot = editable,
        .bindings = &bindings,
        .occurrence_contexts = editable_contexts,
    });

    const final_manifest = try exact_form_occurrences.finalCopyManifest();
    const final_values = try testExactValues(allocator, final_manifest, 4);
    defer allocator.free(final_values);
    const final_contexts = try testExactContexts(allocator, final_manifest);
    defer allocator.free(final_contexts);
    var final_history = try exact_draft.DraftHistory.initExact1701Q(
        allocator,
        shared_workspace,
        .final_copy_plaintext,
    );
    defer final_history.deinit();
    const final_snapshot = try final_history.appendRevision(.create, .{
        .package_key = final_history.schema.package_key,
        .payload_shape = .final_copy_plaintext,
        .occurrence_manifest = final_manifest,
        .occurrences = final_values,
        .profile_snapshot_digest = testSha256(11),
        .transaction_state_digest = testSha256(12),
    });
    try store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
        .filing_key = filing_key,
        .profile_as_of = testDate("2026-03-31"),
        .recorded_at_unix_seconds = 1_775_000_021,
        .validation_evidence = testExactValidationEvidence(),
        .snapshot = final_snapshot,
        .bindings = &bindings,
        .occurrence_contexts = final_contexts,
    });
    var loaded_editable = (try store.getExactDraftHistory(
        syntheticPlaintextTestCapability(),
        allocator,
        editable.draft_identity,
    )).?;
    defer loaded_editable.deinit(allocator);
    var loaded_final = (try store.getExactDraftHistory(
        syntheticPlaintextTestCapability(),
        allocator,
        final_snapshot.draft_identity,
    )).?;
    defer loaded_final.deinit(allocator);
    try std.testing.expectEqual(
        exact_draft.PayloadShape.final_copy_plaintext,
        loaded_final.revisions[0].schema.payload_shape,
    );

    var only_siblings = try store.listExactDraftAlternates(
        syntheticPlaintextTestCapability(),
        allocator,
        filing_key,
        null,
    );
    defer only_siblings.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), only_siblings.items.len);
    try std.testing.expectEqual(
        @as(u32, 2),
        only_siblings.items[0].schema_stream_count,
    );
    var excluding_shared = try store.listExactDraftAlternates(
        syntheticPlaintextTestCapability(),
        allocator,
        filing_key,
        shared_workspace,
    );
    defer excluding_shared.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), excluding_shared.items.len);

    const alternate_workspace = try testDraftWorkspaceId(52);
    var alternate_history = try exact_draft.DraftHistory.initExact1701Q(
        allocator,
        alternate_workspace,
        .editable_save,
    );
    defer alternate_history.deinit();
    const alternate = try alternate_history.appendRevision(.create, .{
        .package_key = alternate_history.schema.package_key,
        .payload_shape = .editable_save,
        .occurrence_manifest = editable_manifest,
        .occurrences = editable_values,
        .profile_snapshot_digest = testSha256(13),
        .transaction_state_digest = testSha256(14),
    });
    try store.appendExactDraftRevision(syntheticPlaintextTestCapability(), .create, .{
        .filing_key = filing_key,
        .profile_as_of = testDate("2026-03-31"),
        .recorded_at_unix_seconds = 1_775_000_022,
        .validation_evidence = testExactValidationEvidence(),
        .snapshot = alternate,
        .bindings = &bindings,
        .occurrence_contexts = editable_contexts,
    });
    var alternates = try store.listExactDraftAlternates(
        syntheticPlaintextTestCapability(),
        allocator,
        filing_key,
        shared_workspace,
    );
    defer alternates.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), alternates.items.len);
    try std.testing.expect(
        alternates.items[0].workspace_id.eql(&alternate_workspace),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        alternates.items[0].schema_stream_count,
    );
}

fn tableExistsForTest(store: *Store, name: []const u8) !bool {
    var statement = try store.prepare(
        \\SELECT 1
        \\FROM sqlite_master
        \\WHERE type = 'table' AND name = ?;
    );
    defer statement.deinit();
    try statement.bindText(1, name);
    return try statement.step() == .row;
}

fn exactRevisionCountForTest(
    store: *Store,
    identity: ExactDraftIdentity,
) !i64 {
    var statement = try store.prepare(
        \\SELECT COUNT(*)
        \\FROM tax_exact_draft_revisions
        \\WHERE workspace_id = ? AND exact_schema_digest = ?;
    );
    defer statement.deinit();
    try statement.bindBlob(1, &identity.workspace_id.bytes);
    try statement.bindBlob(2, identity.exact_schema_digest.asBytes());
    if (try statement.step() != .row) return Error.SqliteFailure;
    return sqlite.sqlite3_column_int64(statement.raw, 0);
}

fn exactWorkspaceCountForTest(
    store: *Store,
    filing_key: CanonicalFilingBusinessKeyWrite,
) !i64 {
    const digest = filing_key.canonicalDigest();
    var statement = try store.prepare(
        \\SELECT COUNT(DISTINCT workspace_id)
        \\FROM tax_exact_draft_streams
        \\WHERE filing_business_key_digest = ?
        \\  AND filer_profile_id = ?
        \\  AND form_code = ?
        \\  AND form_revision = ?
        \\  AND period_key = ?
        \\  AND filing_intent = ?;
    );
    defer statement.deinit();
    try statement.bindBlob(1, digest.asBytes());
    try statement.bindText(2, filing_key.filer_profile_id);
    try statement.bindText(3, filing_key.form_code);
    try statement.bindText(4, filing_key.form_revision);
    try statement.bindText(5, filing_key.period_key);
    try statement.bindText(6, filing_key.intent.text());
    if (try statement.step() != .row) return Error.SqliteFailure;
    return sqlite.sqlite3_column_int64(statement.raw, 0);
}

fn expectBlobColumnForTest(
    row: *sqlite.sqlite3_stmt,
    column: c_int,
    expected: []const u8,
) !void {
    try std.testing.expectEqual(
        sqlite.SQLITE_BLOB,
        sqlite.sqlite3_column_type(row, column),
    );
    const length = sqlite.sqlite3_column_bytes(row, column);
    try std.testing.expectEqual(
        @as(c_int, @intCast(expected.len)),
        length,
    );
    if (expected.len == 0) return;
    const raw = sqlite.sqlite3_column_blob(row, column) orelse
        return Error.SqliteFailure;
    const bytes: [*]const u8 = @ptrCast(raw);
    try std.testing.expectEqualSlices(
        u8,
        expected,
        bytes[0..expected.len],
    );
}

fn testDraftWorkspaceId(last_byte: u8) !DraftWorkspaceId {
    var bytes = [_]u8{0} ** 16;
    bytes[15] = last_byte;
    return DraftWorkspaceId.init(bytes);
}

fn developmentPlaintextStorageCapability() *const key_custody.DevelopmentPlaintextStorageCapability {
    return key_custody.bootstrapCurrentArtifactStorage().development_plaintext;
}

fn syntheticPlaintextTestCapability() *const key_custody.SyntheticPlaintextTestCapability {
    return key_custody.acquireSyntheticPlaintextForTest();
}

fn testSha256(byte: u8) exact_identity.Sha256Digest {
    return .{ .bytes = [_]u8{byte} ** 32 };
}

fn testFilingKey(
    filer_profile_id: []const u8,
) CanonicalFilingBusinessKeyWrite {
    return .{
        .filer_profile_id = filer_profile_id,
        .form_code = "1701Q",
        .form_revision = "2018-01-ENCS",
        .period_key = "2026-Q1",
    };
}

fn testExactValidationEvidence() ExactDraftValidationEvidenceReceipt {
    return .{
        .validation_current_year = 2026,
        .spouse_tin_checksum = .not_evaluated,
    };
}

fn testExactValues(
    allocator: std.mem.Allocator,
    manifest: exact_occurrence.OrderedOccurrenceManifest,
    variant: u8,
) ![]exact_draft.OccurrenceValue {
    const values = try allocator.alloc(
        exact_draft.OccurrenceValue,
        manifest.items.len,
    );
    seedTestExactValues(values, manifest, variant);
    return values;
}

fn seedTestExactValues(
    values: []exact_draft.OccurrenceValue,
    manifest: exact_occurrence.OrderedOccurrenceManifest,
    variant: u8,
) void {
    std.debug.assert(values.len == manifest.items.len);
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
    const first_values: [3][]const u8 = switch (variant) {
        1 => .{ " raw one ", "raw-one", "raw-one" },
        2 => .{ " raw two ", "raw-two", "raw-two" },
        3 => .{ " raw three ", "raw-three", "raw-three" },
        else => .{ " raw final ", "raw-final", "raw-final" },
    };
    values[0].raw_value = first_values[0];
    values[0].normalized_value = first_values[1];
    values[0].emitted_value = first_values[2];

    for (manifest.items, 0..) |metadata, index| {
        if (metadata.same_key_occurrence <= 1) continue;
        for (manifest.items[0..index], 0..) |prior, prior_index| {
            if (!std.mem.eql(
                u8,
                prior.serialized_key,
                metadata.serialized_key,
            )) continue;
            values[prior_index].raw_value = " duplicate raw one ";
            values[prior_index].normalized_value = "duplicate-one";
            values[prior_index].emitted_value = "duplicate-one";
            values[index].raw_value = " duplicate raw two ";
            values[index].normalized_value = "duplicate-two";
            values[index].emitted_value = "duplicate-two";
            return;
        }
    }
}

fn testExactContexts(
    allocator: std.mem.Allocator,
    manifest: exact_occurrence.OrderedOccurrenceManifest,
) ![]ExactDraftOccurrenceContextWrite {
    const contexts = try allocator.alloc(
        ExactDraftOccurrenceContextWrite,
        manifest.items.len,
    );
    for (manifest.items, 0..) |metadata, index| {
        const origin = try expectedExactOccurrenceOrigin(metadata);
        contexts[index] = .{
            .ordinal = metadata.ordinal,
            .origin = origin,
            .provenance = exactOccurrenceProvenance(origin),
        };
    }
    return contexts;
}

const ExactSnapshotForgery = enum {
    ordinal,
    serialized_key,
    same_key_occurrence,
    origin,
    provenance,
    raw_utf8,
    normalized_oversize,
    emitted_grammar,
    ordered_digest,
    artifact_receipt,
};

fn persistTestExactRevision(
    store: *Store,
    allocator: std.mem.Allocator,
    profile_id: []const u8,
    workspace_seed: u8,
    shape: exact_draft.PayloadShape,
) !ExactDraftIdentity {
    return persistTestExactRevisionWithCapability(
        syntheticPlaintextTestCapability(),
        store,
        allocator,
        profile_id,
        workspace_seed,
        shape,
    );
}

fn persistTestExactRevisionWithCapability(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    store: *Store,
    allocator: std.mem.Allocator,
    profile_id: []const u8,
    workspace_seed: u8,
    shape: exact_draft.PayloadShape,
) !ExactDraftIdentity {
    const manifest = try exactManifestForShape(shape);
    const values = try testExactValues(allocator, manifest, workspace_seed);
    defer allocator.free(values);
    const contexts = try testExactContexts(allocator, manifest);
    defer allocator.free(contexts);

    var engine_history = try exact_draft.DraftHistory.initExact1701Q(
        allocator,
        try testDraftWorkspaceId(workspace_seed),
        shape,
    );
    defer engine_history.deinit();
    const snapshot = try engine_history.appendRevision(.create, .{
        .package_key = engine_history.schema.package_key,
        .payload_shape = shape,
        .occurrence_manifest = manifest,
        .occurrences = values,
        .profile_snapshot_digest = testSha256(workspace_seed),
        .transaction_state_digest = testSha256(workspace_seed +% 1),
    });
    const bindings = [_]ExactDraftRoleBindingWrite{.{
        .role = "filer",
        .instance_id = "primary",
        .profile_id = profile_id,
        .profile_revision_id = "revision-1",
        .profile_revision_sequence = 1,
        .provenance = "persisted exact draft corruption fixture",
    }};
    try store.appendExactDraftRevision(plaintext_capability, .create, .{
        .filing_key = testFilingKey(profile_id),
        .profile_as_of = testDate("2026-03-31"),
        .recorded_at_unix_seconds = 1_775_200_000 + @as(i64, workspace_seed),
        .validation_evidence = testExactValidationEvidence(),
        .snapshot = snapshot,
        .bindings = &bindings,
        .occurrence_contexts = contexts,
    });
    return snapshot.draft_identity;
}

fn expectSeededExactOccurrenceRoundTrip(
    revision: *const OwnedExactDraftRevision,
) !void {
    for (revision.occurrences, 0..) |value, index| {
        if (value.same_key_occurrence <= 1) continue;
        for (revision.occurrences[0..index]) |prior| {
            if (!std.mem.eql(
                u8,
                prior.serialized_key,
                value.serialized_key,
            )) continue;
            try std.testing.expectEqual(@as(u16, 1), prior.same_key_occurrence);
            try std.testing.expectEqual(@as(u16, 2), value.same_key_occurrence);
            try std.testing.expectEqualStrings(
                " duplicate raw one ",
                prior.raw_value,
            );
            try std.testing.expectEqualStrings(
                "duplicate-one",
                prior.normalized_value,
            );
            try std.testing.expectEqualStrings(
                "duplicate-one",
                prior.emitted_value,
            );
            try std.testing.expectEqualStrings(
                " duplicate raw two ",
                value.raw_value,
            );
            try std.testing.expectEqualStrings(
                "duplicate-two",
                value.normalized_value,
            );
            try std.testing.expectEqualStrings(
                "duplicate-two",
                value.emitted_value,
            );
            return;
        }
    }

    // The current reviewed 1701Q manifests have no repeated serialized key.
    // The schema-level duplicate-key test above covers that future-facing
    // property while this path verifies the official manifest byte-for-byte.
    for (revision.occurrences) |value| {
        try std.testing.expectEqual(
            @as(u16, 1),
            value.same_key_occurrence,
        );
    }
    try std.testing.expect(revision.occurrences.len > 0);
    const first = revision.occurrences[0];
    try std.testing.expectEqualStrings(" raw one ", first.raw_value);
    try std.testing.expectEqualStrings("raw-one", first.normalized_value);
    try std.testing.expectEqualStrings("raw-one", first.emitted_value);
}

fn expectExactDraftHistoriesEqual(
    expected: *const OwnedExactDraftHistory,
    actual: *const OwnedExactDraftHistory,
) !void {
    try std.testing.expect(expected.draft_identity.eql(
        &actual.draft_identity,
    ));
    try std.testing.expectEqualStrings(
        expected.filing_key.filer_profile_id,
        actual.filing_key.filer_profile_id,
    );
    try std.testing.expectEqualStrings(
        expected.filing_key.form_code,
        actual.filing_key.form_code,
    );
    try std.testing.expectEqualStrings(
        expected.filing_key.form_revision,
        actual.filing_key.form_revision,
    );
    try std.testing.expectEqualStrings(
        expected.filing_key.period_key,
        actual.filing_key.period_key,
    );
    try std.testing.expectEqual(expected.filing_key.intent, actual.filing_key.intent);
    try std.testing.expectEqual(expected.revisions.len, actual.revisions.len);
    for (expected.revisions, actual.revisions) |left, right| {
        try std.testing.expect(left.revision.eql(right.revision));
        if (left.parent_revision) |left_parent| {
            try std.testing.expect(right.parent_revision != null);
            try std.testing.expect(left_parent.eql(right.parent_revision.?));
        } else {
            try std.testing.expect(right.parent_revision == null);
        }
        try std.testing.expectEqualStrings(left.profile_as_of, right.profile_as_of);
        try std.testing.expectEqual(
            left.recorded_at_unix_seconds,
            right.recorded_at_unix_seconds,
        );
        try std.testing.expect(left.schema.package_key.eql(
            &right.schema.package_key,
        ));
        try std.testing.expect(left.schema.package_digest.eql(
            &right.schema.package_digest,
        ));
        try std.testing.expect(left.schema.occurrence_manifest_digest.eql(
            &right.schema.occurrence_manifest_digest,
        ));
        try std.testing.expect(left.schema.exact_schema_digest.eql(
            &right.schema.exact_schema_digest,
        ));
        try std.testing.expectEqual(
            left.schema.payload_shape,
            right.schema.payload_shape,
        );
        try std.testing.expectEqual(
            left.schema.occurrence_count,
            right.schema.occurrence_count,
        );
        try std.testing.expect(std.meta.eql(
            left.schema.evidence_readiness,
            right.schema.evidence_readiness,
        ));
        try std.testing.expect(left.profile_snapshot_digest.eql(
            &right.profile_snapshot_digest,
        ));
        try std.testing.expect(left.transaction_state_digest.eql(
            &right.transaction_state_digest,
        ));
        try std.testing.expect(left.ordered_values_digest.eql(
            &right.ordered_values_digest,
        ));
        try std.testing.expect(std.meta.eql(
            left.validation_evidence,
            right.validation_evidence,
        ));
        try std.testing.expect(std.meta.eql(
            left.validation_status,
            right.validation_status,
        ));
        try std.testing.expect(std.meta.eql(
            left.artifact_status,
            right.artifact_status,
        ));
        try std.testing.expectEqual(left.bindings.len, right.bindings.len);
        for (left.bindings, right.bindings) |left_binding, right_binding| {
            try std.testing.expectEqualStrings(
                left_binding.role,
                right_binding.role,
            );
            try std.testing.expectEqualStrings(
                left_binding.instance_id,
                right_binding.instance_id,
            );
            try std.testing.expectEqualStrings(
                left_binding.profile_id,
                right_binding.profile_id,
            );
            try std.testing.expectEqualStrings(
                left_binding.profile_revision_id,
                right_binding.profile_revision_id,
            );
            try std.testing.expectEqual(
                left_binding.profile_revision_sequence,
                right_binding.profile_revision_sequence,
            );
            try expectOptionalStringsEqual(
                left_binding.business_activity_id,
                right_binding.business_activity_id,
            );
            try std.testing.expectEqualStrings(
                left_binding.provenance,
                right_binding.provenance,
            );
        }
        try std.testing.expectEqual(left.occurrences.len, right.occurrences.len);
        for (left.occurrences, right.occurrences) |left_value, right_value| {
            try std.testing.expectEqual(left_value.ordinal, right_value.ordinal);
            try std.testing.expectEqualStrings(
                left_value.serialized_key,
                right_value.serialized_key,
            );
            try std.testing.expectEqual(
                left_value.same_key_occurrence,
                right_value.same_key_occurrence,
            );
            try std.testing.expectEqualStrings(
                left_value.raw_value,
                right_value.raw_value,
            );
            try std.testing.expectEqualStrings(
                left_value.normalized_value,
                right_value.normalized_value,
            );
            try std.testing.expectEqualStrings(
                left_value.emitted_value,
                right_value.emitted_value,
            );
            try std.testing.expectEqual(left_value.origin, right_value.origin);
            try std.testing.expectEqualStrings(
                left_value.provenance,
                right_value.provenance,
            );
        }
    }
}

fn expectOptionalStringsEqual(
    expected: ?[]const u8,
    actual: ?[]const u8,
) !void {
    if (expected) |value| {
        try std.testing.expect(actual != null);
        try std.testing.expectEqualStrings(value, actual.?);
    } else {
        try std.testing.expect(actual == null);
    }
}

fn expectAllZero(bytes: []const u8) !void {
    for (bytes) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

fn openLegacyStoreForTest(version: u32) !Store {
    std.debug.assert(version >= 1 and version <= 6);
    var raw: ?*sqlite.sqlite3 = null;
    const flags = sqlite.SQLITE_OPEN_READWRITE |
        sqlite.SQLITE_OPEN_CREATE |
        sqlite.SQLITE_OPEN_FULLMUTEX;
    const rc = sqlite.sqlite3_open_v2(":memory:", &raw, flags, null);
    if (rc != sqlite.SQLITE_OK or raw == null) {
        if (raw) |db| _ = sqlite.sqlite3_close_v2(db);
        return mapResult(rc);
    }
    var store: Store = .{ .db = raw.? };
    errdefer store.close();
    _ = sqlite.sqlite3_extended_result_codes(store.db.?, 1);
    try store.exec("PRAGMA foreign_keys = ON;");
    try store.exec(
        \\CREATE TABLE app_component_migrations (
        \\    component TEXT PRIMARY KEY,
        \\    version INTEGER NOT NULL CHECK (version >= 0),
        \\    updated_at INTEGER NOT NULL DEFAULT (unixepoch())
        \\);
    );
    try store.exec(schema_v1);
    if (version >= 2) try store.exec(schema_v2);
    if (version >= 3) {
        try store.validateLegacyIdentityHistories();
        try store.exec(schema_v3);
        try store.backfillIdentityAnchors();
    }
    if (version >= 4) try store.exec(schema_v4);
    if (version >= 5) try store.exec(schema_v5);
    if (version >= 6) try store.exec(schema_v6);
    var set_version = try store.prepare(
        \\INSERT INTO app_component_migrations(component, version)
        \\VALUES ('tax_profile', ?);
    );
    defer set_version.deinit();
    try set_version.bindInt64(1, version);
    try set_version.expectDone();
    return store;
}

fn testRevision(
    profile_id: []const u8,
    expected_current_sequence: u32,
    display_name: []const u8,
    effective_from: []const u8,
) RevisionWrite {
    return .{
        .id = switch (expected_current_sequence) {
            0 => "revision-1",
            1 => "revision-2",
            2 => "revision-3",
            else => "revision-later",
        },
        .profile_id = profile_id,
        .sequence = expected_current_sequence + 1,
        .expected_current_sequence = expected_current_sequence,
        .effective = testPeriod(effective_from, null),
        .source = .{ .imported = "test fixture" },
        .identity = .{
            .tin = "123456789000",
            .rdo_code = "040",
        },
        .contact = .{
            .registered_address = "123 Sample Street",
            .zip_code = "1100",
            .contact_number = "+639000000000",
            .email_address = "demo@example.test",
        },
        .subject = .{ .sole_proprietor = .{
            .person = .{
                .name = display_name,
                .date_of_birth = testDate("1990-01-01"),
                .citizenship = "PH",
            },
            .trade_name = "Sample Trade",
        } },
    };
}

fn testPeriod(
    from: []const u8,
    until: ?[]const u8,
) EffectivePeriodWrite {
    return .{
        .from = testDate(from),
        .until = if (until) |date| testDate(date) else null,
    };
}

fn testDate(value: []const u8) DateText {
    std.debug.assert(value.len == 10);
    return value[0..10].*;
}
