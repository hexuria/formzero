//! Immutable provenance captured when a form draft is created.
//!
//! A filing composes several independently versioned sources.  This module
//! records their exact identities and copies the values used by the draft so
//! later taxpayer, registration, taxpayer-year, or Tax Form Profile edits
//! cannot rewrite history.  Transaction defaults are deliberately kept in a
//! seed-provenance collection; the editable filing-owned values created from
//! those seeds live in `FilingOwnedValues`, outside this snapshot.

const std = @import("std");
const catalog = @import("generated/catalog.zig");
const model = @import("../tax_profile/model.zig");
const registration = @import("../tax_profile/registration.zig");
const annual_profile = @import("../tax_profile/tax_form_profile.zig");
const year_settings = @import("../tax_profile/taxpayer_year_settings.zig");

pub const max_taxpayer_roles = 10;
pub const max_component_bindings = 32;
pub const max_source_snapshots = 96;
pub const max_transaction_seeds = 32;

pub const Error = error{
    InvalidTaxYear,
    InvalidRevisionSequence,
    UnsupportedCalendarOnlyForm,
    WrongForm,
    WrongFormRevision,
    MissingFormRevision,
    MissingSetupSpecIdentity,
    WrongSetupSpecRevision,
    WrongSetupSpecHash,
    TooManyTaxpayerRoles,
    TooManyComponentBindings,
    TooManySourceSnapshots,
    TooManyTransactionSeeds,
    WrongProfileRole,
    DuplicateProfileRole,
    MissingRequiredProfileRole,
    WrongFilerOwner,
    ProfileRolesMustBeDistinct,
    WrongTaxpayerYearOwner,
    WrongTaxpayerYear,
    UnexpectedTaxFormProfileRevision,
    MissingTaxFormProfileRevision,
    WrongTaxFormProfileOwner,
    WrongTaxFormProfileYear,
    WrongTaxFormProfileForm,
    WrongTaxFormProfileFormRevision,
    WrongTaxFormProfileSpecRevision,
    WrongTaxFormProfileSpecHash,
    WrongComponentRole,
    WrongComponentOwner,
    DuplicateComponentAnchor,
    MissingComponentBinding,
    DuplicateSourceKey,
    DuplicateFilingField,
    MissingSourceRevision,
    UnknownTaxFormProfileSource,
    UnavailableTaxFormProfileSource,
    WrongSourceValueType,
    WrongBoundProfile,
    WrongBoundAnchor,
    TransactionDefaultMustBeSeed,
    NonTransactionValueCannotBeSeed,
    WrongTransactionSeedRevision,
    WrongTransactionSeedCatalog,
    WrongTransactionSeedSourceKind,
    UnknownFilingField,
    WrongFilingValueType,
};

pub const ParseError = error{
    EmptyIdentifier,
    IdentifierTooLong,
    InvalidIdentifier,
    InvalidSha256,
    TextTooLong,
};

fn Identifier(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        bytes: [capacity]u8 = undefined,
        len: u8 = 0,

        pub fn parse(raw: []const u8) ParseError!Self {
            const value = std.mem.trim(u8, raw, " \t\r\n");
            if (value.len == 0) return error.EmptyIdentifier;
            if (value.len > capacity or value.len > std.math.maxInt(u8)) {
                return error.IdentifierTooLong;
            }
            for (value) |byte| {
                if (!std.ascii.isAlphanumeric(byte) and
                    byte != '-' and byte != '_' and byte != '.' and
                    byte != ':' and byte != '/')
                {
                    return error.InvalidIdentifier;
                }
            }
            var result: Self = .{};
            @memcpy(result.bytes[0..value.len], value);
            result.len = @intCast(value.len);
            return result;
        }

        pub fn asSlice(self: *const Self) []const u8 {
            return self.bytes[0..self.len];
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            return std.mem.eql(u8, self.asSlice(), other.asSlice());
        }
    };
}

/// A repository/catalog build identity.  The generated catalog currently
/// exposes per-form setup hashes but no aggregate hash, so the composer passes
/// its exact build revision and digest into the capture boundary.
pub const CatalogRevision = Identifier(64);
pub const DraftFieldKey = Identifier(96);

pub const Sha256 = struct {
    bytes: [64]u8,

    pub fn parse(raw: []const u8) ParseError!Sha256 {
        const value = std.mem.trim(u8, raw, " \t\r\n");
        if (value.len != 64) return error.InvalidSha256;
        var result: Sha256 = undefined;
        for (value, 0..) |byte, index| {
            if (!std.ascii.isHex(byte)) return error.InvalidSha256;
            result.bytes[index] = std.ascii.toLower(byte);
        }
        return result;
    }

    pub fn asSlice(self: *const Sha256) []const u8 {
        return &self.bytes;
    }

    pub fn eql(self: *const Sha256, other: *const Sha256) bool {
        return std.mem.eql(u8, self.asSlice(), other.asSlice());
    }
};

pub const OwnedText = struct {
    bytes: [255]u8 = undefined,
    len: u8 = 0,

    pub fn copy(raw: []const u8) ParseError!OwnedText {
        if (raw.len > 255) return error.TextTooLong;
        var result: OwnedText = .{};
        @memcpy(result.bytes[0..raw.len], raw);
        result.len = @intCast(raw.len);
        return result;
    }

    pub fn asSlice(self: *const OwnedText) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const CatalogBinding = struct {
    revision: CatalogRevision,
    sha256: Sha256,

    pub fn eql(self: *const CatalogBinding, other: *const CatalogBinding) bool {
        return self.revision.eql(&other.revision) and
            self.sha256.eql(&other.sha256);
    }
};

/// Stable filing identity plus the exact generated setup contract consumed by
/// composition.  `setup_spec_*` is recorded for `no_setup` too; that proves
/// the absence of a Tax Form Profile row was an explicit generated decision.
pub const FilingIdentity = struct {
    owner_profile_id: model.ProfileId,
    tax_year: u16,
    form_code: annual_profile.FormCode,
    form_revision: annual_profile.FormRevision,
    catalog: CatalogBinding,
    setup_spec_revision: u32,
    setup_spec_hash: Sha256,
};

/// Exact effective taxpayer revision selected for one named catalog role.
pub const TaxpayerRevisionBinding = struct {
    role: catalog.Role,
    profile_id: model.ProfileId,
    revision_id: model.RevisionId,
    revision_sequence: u32,
};

/// Optional exact shared taxpayer/year revision.  It has no form dimension by
/// design, so 1701 and 1701Q can consume the same election stream.
pub const TaxpayerYearRevisionBinding = struct {
    stream: year_settings.StreamKey,
    revision_id: year_settings.RevisionId,
    revision_sequence: u32,
};

/// Exact annual Tax Form Profile revision.  This binding is legal only for a
/// generated `.setup` contract and is mandatory for such a contract.
pub const TaxFormProfileRevisionBinding = struct {
    stream: annual_profile.StreamKey,
    revision_id: annual_profile.RevisionId,
    revision_sequence: u32,
    spec_revision: u32,
    spec_hash: annual_profile.SpecHash,
};

pub const ActivityComponentBinding = struct {
    role: catalog.Role,
    anchor: registration.ActivityAnchor,
    component_revision_id: registration.ComponentRevisionId,
    component_revision_sequence: u32,
};

pub const ObligationComponentBinding = struct {
    role: catalog.Role,
    anchor: registration.ObligationAnchor,
    component_revision_id: registration.ComponentRevisionId,
    component_revision_sequence: u32,
};

pub const ComponentBinding = union(enum) {
    business_activity: ActivityComponentBinding,
    registration_obligation: ObligationComponentBinding,
};

pub const TaxpayerFactKey = enum {
    tin,
    rdo_code,
    taxpayer_name,
    registered_name,
    trade_name,
    registered_address,
    zip_code,
    contact_number,
    email_address,
    subject_kind,
    natural_person_classification,
};

pub const ActivityFactKey = enum {
    line_of_business,
    atc,
};

pub const ObligationFactKey = enum {
    registration_kind,
};

/// Semantic identity of one copied source.  Equality is structural; two rows
/// cannot claim the same source key even if they carry equal values.
pub const SourceKey = union(enum) {
    taxpayer_fact: struct {
        role: catalog.Role,
        key: TaxpayerFactKey,
    },
    taxpayer_year_setting: struct {
        role: catalog.Role,
        key: year_settings.SettingKey,
    },
    tax_form_profile_value: struct {
        role: catalog.Role,
        key: catalog.TaxFormProfileSemanticKey,
    },
    business_activity_fact: struct {
        role: catalog.Role,
        anchor_id: registration.ActivityAnchorId,
        key: ActivityFactKey,
    },
    registration_obligation_fact: struct {
        role: catalog.Role,
        anchor_id: registration.ObligationAnchorId,
        key: ObligationFactKey,
    },

    pub fn role(self: SourceKey) catalog.Role {
        return switch (self) {
            inline else => |value| value.role,
        };
    }

    pub fn eql(self: SourceKey, other: SourceKey) bool {
        return switch (self) {
            .taxpayer_fact => |left| switch (other) {
                .taxpayer_fact => |right| left.role == right.role and
                    left.key == right.key,
                else => false,
            },
            .taxpayer_year_setting => |left| switch (other) {
                .taxpayer_year_setting => |right| left.role == right.role and
                    left.key == right.key,
                else => false,
            },
            .tax_form_profile_value => |left| switch (other) {
                .tax_form_profile_value => |right| left.role == right.role and
                    left.key == right.key,
                else => false,
            },
            .business_activity_fact => |left| switch (other) {
                .business_activity_fact => |right| left.role == right.role and
                    left.key == right.key and
                    left.anchor_id.eql(&right.anchor_id),
                else => false,
            },
            .registration_obligation_fact => |left| switch (other) {
                .registration_obligation_fact => |right| left.role == right.role and
                    left.key == right.key and
                    left.anchor_id.eql(&right.anchor_id),
                else => false,
            },
        };
    }
};

/// Values are owned buffers or value types, never caller slices.
pub const SnapshotValue = union(enum) {
    text: OwnedText,
    choice: OwnedText,
    boolean: bool,
    integer: i64,
    date: model.Date,
    year: u16,
    profile_id: model.ProfileId,
    business_activity_anchor_id: registration.ActivityAnchorId,
    registration_obligation_anchor_id: registration.ObligationAnchorId,
    income_tax_rate_election: year_settings.IncomeTaxRateElection,
    deduction_method: year_settings.DeductionMethod,

    fn formProfileValueType(self: SnapshotValue) ?catalog.TaxFormProfileValueType {
        return switch (self) {
            .text => .text,
            .choice => .choice,
            .boolean => .boolean,
            .integer => .integer,
            .date => .date,
            .year => .year,
            .profile_id => .profile_id,
            .business_activity_anchor_id => .business_activity_anchor_id,
            .registration_obligation_anchor_id => .registration_obligation_anchor_id,
            .income_tax_rate_election, .deduction_method => null,
        };
    }
};

pub const SourceSnapshot = struct {
    key: SourceKey,
    copied_value: SnapshotValue,
};

pub const TransactionSeedSource = union(enum) {
    tax_form_profile_revision: annual_profile.RevisionId,
    catalog_default: CatalogBinding,
};

/// Immutable record of what was copied into a filing-owned field initially.
pub const TransactionDefaultSeed = struct {
    filing_field: DraftFieldKey,
    source_key: SourceKey,
    source: TransactionSeedSource,
    copied_seed_value: SnapshotValue,
};

pub const CaptureInput = struct {
    identity: FilingIdentity,
    taxpayer_revisions: []const TaxpayerRevisionBinding,
    taxpayer_year_revision: ?TaxpayerYearRevisionBinding = null,
    tax_form_profile_revision: ?TaxFormProfileRevisionBinding = null,
    components: []const ComponentBinding = &.{},
    source_snapshots: []const SourceSnapshot = &.{},
    transaction_seeds: []const TransactionDefaultSeed = &.{},
};

/// Fully owned, fixed-capacity provenance snapshot.  Capturing performs all
/// cross-stream validation before copying any caller-provided collection.
pub const DraftProvenance = struct {
    identity: FilingIdentity,
    taxpayer_year_revision: ?TaxpayerYearRevisionBinding,
    tax_form_profile_revision: ?TaxFormProfileRevisionBinding,

    taxpayer_revisions_storage: [max_taxpayer_roles]TaxpayerRevisionBinding = undefined,
    taxpayer_revision_count: u8 = 0,
    components_storage: [max_component_bindings]ComponentBinding = undefined,
    component_count: u8 = 0,
    source_snapshots_storage: [max_source_snapshots]SourceSnapshot = undefined,
    source_snapshot_count: u8 = 0,
    transaction_seeds_storage: [max_transaction_seeds]TransactionDefaultSeed = undefined,
    transaction_seed_count: u8 = 0,

    pub fn capture(
        input: *const CaptureInput,
        form: *const catalog.FormDefinition,
    ) Error!DraftProvenance {
        try validateCapture(input, form);

        var result: DraftProvenance = .{
            .identity = input.identity,
            .taxpayer_year_revision = input.taxpayer_year_revision,
            .tax_form_profile_revision = input.tax_form_profile_revision,
        };
        result.taxpayer_revision_count = @intCast(input.taxpayer_revisions.len);
        result.component_count = @intCast(input.components.len);
        result.source_snapshot_count = @intCast(input.source_snapshots.len);
        result.transaction_seed_count = @intCast(input.transaction_seeds.len);
        @memcpy(
            result.taxpayer_revisions_storage[0..input.taxpayer_revisions.len],
            input.taxpayer_revisions,
        );
        @memcpy(
            result.components_storage[0..input.components.len],
            input.components,
        );
        @memcpy(
            result.source_snapshots_storage[0..input.source_snapshots.len],
            input.source_snapshots,
        );
        @memcpy(
            result.transaction_seeds_storage[0..input.transaction_seeds.len],
            input.transaction_seeds,
        );
        return result;
    }

    pub fn taxpayerRevisions(self: *const DraftProvenance) []const TaxpayerRevisionBinding {
        return self.taxpayer_revisions_storage[0..self.taxpayer_revision_count];
    }

    pub fn components(self: *const DraftProvenance) []const ComponentBinding {
        return self.components_storage[0..self.component_count];
    }

    pub fn sourceSnapshots(self: *const DraftProvenance) []const SourceSnapshot {
        return self.source_snapshots_storage[0..self.source_snapshot_count];
    }

    pub fn transactionSeeds(self: *const DraftProvenance) []const TransactionDefaultSeed {
        return self.transaction_seeds_storage[0..self.transaction_seed_count];
    }

    pub fn transactionSeedForField(
        self: *const DraftProvenance,
        field_key: *const DraftFieldKey,
    ) ?*const TransactionDefaultSeed {
        for (self.transactionSeeds()) |*seed| {
            if (seed.filing_field.eql(field_key)) return seed;
        }
        return null;
    }
};

/// Mutable transaction state initialized from immutable seed provenance.
/// Current filing values intentionally contain no profile revision pointer.
pub const FilingOwnedValue = struct {
    field: DraftFieldKey,
    value: SnapshotValue,
};

pub const FilingOwnedValues = struct {
    storage: [max_transaction_seeds]FilingOwnedValue = undefined,
    count: u8 = 0,

    pub fn fromProvenance(snapshot: *const DraftProvenance) FilingOwnedValues {
        var result: FilingOwnedValues = .{};
        for (snapshot.transactionSeeds(), 0..) |seed, index| {
            result.storage[index] = .{
                .field = seed.filing_field,
                .value = seed.copied_seed_value,
            };
        }
        result.count = snapshot.transaction_seed_count;
        return result;
    }

    pub fn values(self: *const FilingOwnedValues) []const FilingOwnedValue {
        return self.storage[0..self.count];
    }

    pub fn get(
        self: *const FilingOwnedValues,
        field_key: *const DraftFieldKey,
    ) ?*const FilingOwnedValue {
        for (self.values()) |*value| {
            if (value.field.eql(field_key)) return value;
        }
        return null;
    }

    pub fn set(
        self: *FilingOwnedValues,
        field_key: *const DraftFieldKey,
        value: SnapshotValue,
    ) Error!void {
        for (self.storage[0..self.count]) |*current| {
            if (!current.field.eql(field_key)) continue;
            if (std.meta.activeTag(current.value) != std.meta.activeTag(value)) {
                return error.WrongFilingValueType;
            }
            current.value = value;
            return;
        }
        return error.UnknownFilingField;
    }
};

pub fn validateCapture(
    input: *const CaptureInput,
    form: *const catalog.FormDefinition,
) Error!void {
    if (input.taxpayer_revisions.len > max_taxpayer_roles) {
        return error.TooManyTaxpayerRoles;
    }
    if (input.components.len > max_component_bindings) {
        return error.TooManyComponentBindings;
    }
    if (input.source_snapshots.len > max_source_snapshots) {
        return error.TooManySourceSnapshots;
    }
    if (input.transaction_seeds.len > max_transaction_seeds) {
        return error.TooManyTransactionSeeds;
    }

    try validateIdentity(&input.identity, form);
    try validateTaxpayerBindings(input, form);
    try validateTaxpayerYearBinding(input);
    try validateTaxFormProfileBinding(input, form);
    try validateComponents(input);
    try validateSources(input, form);
}

fn validateIdentity(
    identity: *const FilingIdentity,
    form: *const catalog.FormDefinition,
) Error!void {
    if (identity.tax_year == 0) return error.InvalidTaxYear;
    if (!std.mem.eql(u8, identity.form_code.asSlice(), form.code)) {
        return error.WrongForm;
    }
    const revision = form.revision orelse return error.MissingFormRevision;
    if (!std.mem.eql(u8, identity.form_revision.asSlice(), revision)) {
        return error.WrongFormRevision;
    }
    if (form.tax_form_profile.mode == .calendar_only) {
        return error.UnsupportedCalendarOnlyForm;
    }
    const spec_revision = form.tax_form_profile.spec_revision orelse
        return error.MissingSetupSpecIdentity;
    const spec_hash = form.tax_form_profile.spec_hash orelse
        return error.MissingSetupSpecIdentity;
    if (identity.setup_spec_revision != spec_revision) {
        return error.WrongSetupSpecRevision;
    }
    if (!std.mem.eql(u8, identity.setup_spec_hash.asSlice(), spec_hash)) {
        return error.WrongSetupSpecHash;
    }
}

fn validateTaxpayerBindings(
    input: *const CaptureInput,
    form: *const catalog.FormDefinition,
) Error!void {
    for (input.taxpayer_revisions, 0..) |*binding, index| {
        if (binding.revision_sequence == 0) return error.InvalidRevisionSequence;
        const definition = findProfileRole(form, binding.role) orelse
            return error.WrongProfileRole;
        _ = definition;
        for (input.taxpayer_revisions[index + 1 ..]) |*other| {
            if (binding.role == other.role) return error.DuplicateProfileRole;
        }
        if (binding.role == .filer and
            !binding.profile_id.eql(&input.identity.owner_profile_id))
        {
            return error.WrongFilerOwner;
        }
    }

    for (form.profile_roles) |*definition| {
        const binding = findTaxpayerBinding(input.taxpayer_revisions, definition.role);
        if (definition.cardinality == .exactly_one and binding == null) {
            return error.MissingRequiredProfileRole;
        }
        if (binding) |bound| {
            for (definition.distinct_from) |other_role| {
                if (findTaxpayerBinding(input.taxpayer_revisions, other_role)) |other| {
                    if (bound.profile_id.eql(&other.profile_id)) {
                        return error.ProfileRolesMustBeDistinct;
                    }
                }
            }
        }
    }
}

fn validateTaxpayerYearBinding(input: *const CaptureInput) Error!void {
    const binding = input.taxpayer_year_revision orelse return;
    if (binding.revision_sequence == 0) return error.InvalidRevisionSequence;
    if (!binding.stream.profile_id.eql(&input.identity.owner_profile_id)) {
        return error.WrongTaxpayerYearOwner;
    }
    if (binding.stream.tax_year != input.identity.tax_year) {
        return error.WrongTaxpayerYear;
    }
}

fn validateTaxFormProfileBinding(
    input: *const CaptureInput,
    form: *const catalog.FormDefinition,
) Error!void {
    switch (form.tax_form_profile.mode) {
        .calendar_only => return error.UnsupportedCalendarOnlyForm,
        .no_setup => if (input.tax_form_profile_revision != null) {
            return error.UnexpectedTaxFormProfileRevision;
        },
        .setup => {
            const binding = input.tax_form_profile_revision orelse {
                for (form.tax_form_profile.values) |definition| {
                    if (definition.availability == .supported and
                        definition.presence == .required)
                    {
                        return error.MissingTaxFormProfileRevision;
                    }
                }
                for (input.source_snapshots) |*source| switch (source.key) {
                    .tax_form_profile_value =>
                        return error.MissingTaxFormProfileRevision,
                    else => {},
                };
                for (input.transaction_seeds) |*seed| switch (seed.source) {
                    .tax_form_profile_revision =>
                        return error.MissingTaxFormProfileRevision,
                    .catalog_default => {},
                };
                return;
            };
            if (binding.revision_sequence == 0) return error.InvalidRevisionSequence;
            if (!binding.stream.profile_id.eql(&input.identity.owner_profile_id)) {
                return error.WrongTaxFormProfileOwner;
            }
            if (binding.stream.tax_year != input.identity.tax_year) {
                return error.WrongTaxFormProfileYear;
            }
            if (!std.mem.eql(
                u8,
                binding.stream.form_code.asSlice(),
                input.identity.form_code.asSlice(),
            )) return error.WrongTaxFormProfileForm;
            if (!std.mem.eql(
                u8,
                binding.stream.form_revision.asSlice(),
                input.identity.form_revision.asSlice(),
            )) return error.WrongTaxFormProfileFormRevision;
            if (binding.spec_revision != input.identity.setup_spec_revision) {
                return error.WrongTaxFormProfileSpecRevision;
            }
            if (!std.mem.eql(
                u8,
                binding.spec_hash.asSlice(),
                input.identity.setup_spec_hash.asSlice(),
            )) return error.WrongTaxFormProfileSpecHash;
        },
    }
}

fn validateComponents(input: *const CaptureInput) Error!void {
    for (input.components, 0..) |*component, index| {
        const role = componentRole(component);
        const role_binding = findTaxpayerBinding(input.taxpayer_revisions, role) orelse
            return error.WrongComponentRole;
        if (componentRevisionSequence(component) == 0) {
            return error.InvalidRevisionSequence;
        }
        if (!componentOwner(component).eql(&role_binding.profile_id)) {
            return error.WrongComponentOwner;
        }
        for (input.components[index + 1 ..]) |*other| {
            if (sameComponentAnchor(component, other)) {
                return error.DuplicateComponentAnchor;
            }
        }
    }
}

fn validateSources(
    input: *const CaptureInput,
    form: *const catalog.FormDefinition,
) Error!void {
    for (input.source_snapshots, 0..) |*source, index| {
        try validateSource(input, form, source, false);
        for (input.source_snapshots[index + 1 ..]) |*other| {
            if (source.key.eql(other.key)) return error.DuplicateSourceKey;
        }
        for (input.transaction_seeds) |*seed| {
            if (source.key.eql(seed.source_key)) return error.DuplicateSourceKey;
        }
    }

    for (input.transaction_seeds, 0..) |*seed, index| {
        try validateTransactionSeed(input, form, seed);
        for (input.transaction_seeds[index + 1 ..]) |*other| {
            if (seed.source_key.eql(other.source_key)) {
                return error.DuplicateSourceKey;
            }
            if (seed.filing_field.eql(&other.filing_field)) {
                return error.DuplicateFilingField;
            }
        }
    }
}

fn validateSource(
    input: *const CaptureInput,
    form: *const catalog.FormDefinition,
    source: *const SourceSnapshot,
    is_transaction_seed: bool,
) Error!void {
    switch (source.key) {
        .taxpayer_fact => |key| {
            if (findTaxpayerBinding(input.taxpayer_revisions, key.role) == null) {
                return error.MissingSourceRevision;
            }
        },
        .taxpayer_year_setting => |key| {
            const year_binding = input.taxpayer_year_revision orelse
                return error.MissingSourceRevision;
            const role_binding = findTaxpayerBinding(input.taxpayer_revisions, key.role) orelse
                return error.MissingSourceRevision;
            if (!role_binding.profile_id.eql(&year_binding.stream.profile_id)) {
                return error.WrongTaxpayerYearOwner;
            }
            switch (key.key) {
                .income_tax_rate_election => switch (source.copied_value) {
                    .income_tax_rate_election => {},
                    else => return error.WrongSourceValueType,
                },
                .deduction_method => switch (source.copied_value) {
                    .deduction_method => {},
                    else => return error.WrongSourceValueType,
                },
            }
        },
        .tax_form_profile_value => |key| {
            const definition = findSetupValue(form, key.role, key.key) orelse
                return error.UnknownTaxFormProfileSource;
            if (definition.availability != .supported) {
                return error.UnavailableTaxFormProfileSource;
            }
            if (input.tax_form_profile_revision == null and
                !(is_transaction_seed and
                    definition.ownership == .transaction_default and
                    definition.source_kind == .catalog_default))
            {
                return error.MissingSourceRevision;
            }
            if (is_transaction_seed) {
                if (definition.ownership != .transaction_default) {
                    return error.NonTransactionValueCannotBeSeed;
                }
            } else if (definition.ownership == .transaction_default) {
                return error.TransactionDefaultMustBeSeed;
            }
            if (source.copied_value.formProfileValueType() != definition.value_type) {
                return error.WrongSourceValueType;
            }
            try validateSelectedBinding(input, key.role, source.copied_value);
        },
        .business_activity_fact => |key| {
            if (findActivityComponent(input.components, key.role, &key.anchor_id) == null) {
                return error.MissingComponentBinding;
            }
        },
        .registration_obligation_fact => |key| {
            if (findObligationComponent(input.components, key.role, &key.anchor_id) == null) {
                return error.MissingComponentBinding;
            }
        },
    }
}

fn validateSelectedBinding(
    input: *const CaptureInput,
    role: catalog.Role,
    value: SnapshotValue,
) Error!void {
    switch (value) {
        .profile_id => |profile_id| {
            const binding = findTaxpayerBinding(input.taxpayer_revisions, role) orelse
                return error.MissingSourceRevision;
            if (!profile_id.eql(&binding.profile_id)) return error.WrongBoundProfile;
        },
        .business_activity_anchor_id => |anchor_id| {
            if (findActivityComponent(input.components, role, &anchor_id) == null) {
                return error.WrongBoundAnchor;
            }
        },
        .registration_obligation_anchor_id => |anchor_id| {
            if (findObligationComponent(input.components, role, &anchor_id) == null) {
                return error.WrongBoundAnchor;
            }
        },
        else => {},
    }
}

fn validateTransactionSeed(
    input: *const CaptureInput,
    form: *const catalog.FormDefinition,
    seed: *const TransactionDefaultSeed,
) Error!void {
    const synthetic = SourceSnapshot{
        .key = seed.source_key,
        .copied_value = seed.copied_seed_value,
    };
    try validateSource(input, form, &synthetic, true);
    const key = switch (seed.source_key) {
        .tax_form_profile_value => |value| value,
        else => return error.NonTransactionValueCannotBeSeed,
    };
    const definition = findSetupValue(form, key.role, key.key) orelse
        return error.UnknownTaxFormProfileSource;

    switch (seed.source) {
        .tax_form_profile_revision => |revision_id| {
            if (definition.source_kind == .catalog_default) {
                return error.WrongTransactionSeedSourceKind;
            }
            const binding = input.tax_form_profile_revision orelse
                return error.MissingSourceRevision;
            if (!revision_id.eql(&binding.revision_id)) {
                return error.WrongTransactionSeedRevision;
            }
        },
        .catalog_default => |catalog_source| {
            if (definition.source_kind != .catalog_default) {
                return error.WrongTransactionSeedSourceKind;
            }
            if (!catalog_source.eql(&input.identity.catalog)) {
                return error.WrongTransactionSeedCatalog;
            }
        },
    }
}

fn findProfileRole(
    form: *const catalog.FormDefinition,
    role: catalog.Role,
) ?*const catalog.ProfileRoleDefinition {
    for (form.profile_roles) |*definition| {
        if (definition.role == role) return definition;
    }
    return null;
}

fn findTaxpayerBinding(
    bindings: []const TaxpayerRevisionBinding,
    role: catalog.Role,
) ?*const TaxpayerRevisionBinding {
    for (bindings) |*binding| {
        if (binding.role == role) return binding;
    }
    return null;
}

fn findSetupValue(
    form: *const catalog.FormDefinition,
    role: catalog.Role,
    key: catalog.TaxFormProfileSemanticKey,
) ?*const catalog.TaxFormProfileValueDefinition {
    for (form.tax_form_profile.values) |*definition| {
        if (definition.role == role and definition.semantic_key == key) {
            return definition;
        }
    }
    return null;
}

fn componentRole(component: *const ComponentBinding) catalog.Role {
    return switch (component.*) {
        inline else => |value| value.role,
    };
}

fn componentOwner(component: *const ComponentBinding) *const model.ProfileId {
    return switch (component.*) {
        .business_activity => |*value| &value.anchor.owner_profile_id,
        .registration_obligation => |*value| &value.anchor.owner_profile_id,
    };
}

fn componentRevisionSequence(component: *const ComponentBinding) u32 {
    return switch (component.*) {
        inline else => |value| value.component_revision_sequence,
    };
}

fn sameComponentAnchor(
    left: *const ComponentBinding,
    right: *const ComponentBinding,
) bool {
    return switch (left.*) {
        .business_activity => |left_value| switch (right.*) {
            .business_activity => |right_value| left_value.anchor.id.eql(&right_value.anchor.id),
            else => false,
        },
        .registration_obligation => |left_value| switch (right.*) {
            .registration_obligation => |right_value| left_value.anchor.id.eql(&right_value.anchor.id),
            else => false,
        },
    };
}

fn findActivityComponent(
    components: []const ComponentBinding,
    role: catalog.Role,
    anchor_id: *const registration.ActivityAnchorId,
) ?*const ActivityComponentBinding {
    for (components) |*component| switch (component.*) {
        .business_activity => |*value| {
            if (value.role == role and value.anchor.id.eql(anchor_id)) return value;
        },
        else => {},
    };
    return null;
}

fn findObligationComponent(
    components: []const ComponentBinding,
    role: catalog.Role,
    anchor_id: *const registration.ObligationAnchorId,
) ?*const ObligationComponentBinding {
    for (components) |*component| switch (component.*) {
        .registration_obligation => |*value| {
            if (value.role == role and value.anchor.id.eql(anchor_id)) return value;
        },
        else => {},
    };
    return null;
}

fn fixtureCatalog() !CatalogBinding {
    return .{
        .revision = try CatalogRevision.parse("catalog-test-1"),
        .sha256 = try Sha256.parse("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    };
}

fn fixtureIdentity(
    form: *const catalog.FormDefinition,
    owner: model.ProfileId,
) !FilingIdentity {
    return .{
        .owner_profile_id = owner,
        .tax_year = 2026,
        .form_code = try annual_profile.FormCode.parse(form.code),
        .form_revision = try annual_profile.FormRevision.parse(form.revision.?),
        .catalog = try fixtureCatalog(),
        .setup_spec_revision = form.tax_form_profile.spec_revision.?,
        .setup_spec_hash = try Sha256.parse(form.tax_form_profile.spec_hash.?),
    };
}

fn fixtureRole(
    role: catalog.Role,
    profile: []const u8,
    revision: []const u8,
) !TaxpayerRevisionBinding {
    return .{
        .role = role,
        .profile_id = try model.ProfileId.parse(profile),
        .revision_id = try model.RevisionId.parse(revision),
        .revision_sequence = 1,
    };
}

fn fixtureFormProfile(
    identity: *const FilingIdentity,
    revision_id: []const u8,
) !TaxFormProfileRevisionBinding {
    return .{
        .stream = .{
            .profile_id = identity.owner_profile_id,
            .tax_year = identity.tax_year,
            .form_code = identity.form_code,
            .form_revision = identity.form_revision,
        },
        .revision_id = try annual_profile.RevisionId.parse(revision_id),
        .revision_sequence = 1,
        .spec_revision = identity.setup_spec_revision,
        .spec_hash = try annual_profile.SpecHash.parse(identity.setup_spec_hash.asSlice()),
    };
}

test "2551Q no_setup captures exact taxpayer provenance without fabricating annual revision" {
    const form = catalog.findForm("2551Q").?;
    const filer = try fixtureRole(.filer, "profile-filer", "profile-revision-7");
    const roles = [_]TaxpayerRevisionBinding{filer};
    const sources = [_]SourceSnapshot{.{
        .key = .{ .taxpayer_fact = .{ .role = .filer, .key = .tin } },
        .copied_value = .{ .text = try OwnedText.copy("123-456-789-000") },
    }};
    const input: CaptureInput = .{
        .identity = try fixtureIdentity(form, filer.profile_id),
        .taxpayer_revisions = &roles,
        .source_snapshots = &sources,
    };

    const snapshot = try DraftProvenance.capture(&input, form);
    try std.testing.expect(snapshot.tax_form_profile_revision == null);
    try std.testing.expectEqual(@as(usize, 1), snapshot.sourceSnapshots().len);
    try std.testing.expectEqualStrings(
        "profile-revision-7",
        snapshot.taxpayerRevisions()[0].revision_id.asSlice(),
    );

    var fabricated = input;
    fabricated.tax_form_profile_revision = try fixtureFormProfile(
        &input.identity,
        "fabricated-2551q-setup",
    );
    try std.testing.expectError(
        error.UnexpectedTaxFormProfileRevision,
        DraftProvenance.capture(&fabricated, form),
    );
}

test "1701Q keeps shared taxpayer-year election separate from form setup" {
    const form = catalog.findForm("1701Q").?;
    const filer = try fixtureRole(.filer, "profile-filer", "filer-revision-4");
    const spouse = try fixtureRole(.spouse, "profile-spouse", "spouse-revision-2");
    const roles = [_]TaxpayerRevisionBinding{ filer, spouse };
    const identity = try fixtureIdentity(form, filer.profile_id);
    const year_binding: TaxpayerYearRevisionBinding = .{
        .stream = .{ .profile_id = filer.profile_id, .tax_year = 2026 },
        .revision_id = try year_settings.RevisionId.parse("year-settings-3"),
        .revision_sequence = 3,
    };
    const form_binding = try fixtureFormProfile(&identity, "1701q-setup-2");
    const sources = [_]SourceSnapshot{
        .{
            .key = .{ .taxpayer_year_setting = .{
                .role = .filer,
                .key = .income_tax_rate_election,
            } },
            .copied_value = .{ .income_tax_rate_election = .eight_percent },
        },
        .{
            .key = .{ .tax_form_profile_value = .{
                .role = .spouse,
                .key = .spouse_profile_id,
            } },
            .copied_value = .{ .profile_id = spouse.profile_id },
        },
    };
    const input: CaptureInput = .{
        .identity = identity,
        .taxpayer_revisions = &roles,
        .taxpayer_year_revision = year_binding,
        .tax_form_profile_revision = form_binding,
        .source_snapshots = &sources,
    };

    const snapshot = try DraftProvenance.capture(&input, form);
    try std.testing.expect(snapshot.taxpayer_year_revision != null);
    try std.testing.expect(snapshot.tax_form_profile_revision != null);
    try std.testing.expect(
        std.meta.activeTag(snapshot.sourceSnapshots()[0].key) == .taxpayer_year_setting,
    );
    try std.testing.expect(
        std.meta.activeTag(snapshot.sourceSnapshots()[1].key) == .tax_form_profile_value,
    );
    try std.testing.expect(
        findSetupValue(form, .filer, .business_activity_anchor_id).?.ownership ==
            .binding_selection,
    );

    var missing_setup = input;
    missing_setup.tax_form_profile_revision = null;
    try std.testing.expectError(
        error.MissingTaxFormProfileRevision,
        DraftProvenance.capture(&missing_setup, form),
    );
}

test "profile year form and generated spec identities must match exactly" {
    const form = catalog.findForm("1701Q").?;
    const filer = try fixtureRole(.filer, "profile-filer", "filer-revision");
    const roles = [_]TaxpayerRevisionBinding{filer};
    var identity = try fixtureIdentity(form, filer.profile_id);
    var form_binding = try fixtureFormProfile(&identity, "form-profile-revision");
    var input: CaptureInput = .{
        .identity = identity,
        .taxpayer_revisions = &roles,
        .tax_form_profile_revision = form_binding,
    };
    _ = try DraftProvenance.capture(&input, form);

    identity.form_revision = try annual_profile.FormRevision.parse("wrong-revision");
    input.identity = identity;
    try std.testing.expectError(
        error.WrongFormRevision,
        DraftProvenance.capture(&input, form),
    );

    identity = try fixtureIdentity(form, filer.profile_id);
    identity.setup_spec_hash = try Sha256.parse(
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    );
    input.identity = identity;
    try std.testing.expectError(
        error.WrongSetupSpecHash,
        DraftProvenance.capture(&input, form),
    );

    identity = try fixtureIdentity(form, filer.profile_id);
    form_binding = try fixtureFormProfile(&identity, "form-profile-revision");
    form_binding.stream.tax_year = 2025;
    input.identity = identity;
    input.tax_form_profile_revision = form_binding;
    try std.testing.expectError(
        error.WrongTaxFormProfileYear,
        DraftProvenance.capture(&input, form),
    );

    const year_binding: TaxpayerYearRevisionBinding = .{
        .stream = .{
            .profile_id = try model.ProfileId.parse("wrong-owner"),
            .tax_year = 2026,
        },
        .revision_id = try year_settings.RevisionId.parse("year-revision"),
        .revision_sequence = 1,
    };
    input.tax_form_profile_revision = try fixtureFormProfile(
        &identity,
        "form-profile-revision",
    );
    input.taxpayer_year_revision = year_binding;
    try std.testing.expectError(
        error.WrongTaxpayerYearOwner,
        DraftProvenance.capture(&input, form),
    );
}

test "component anchors must belong to the profile bound to their exact role" {
    const form = catalog.findForm("1601C").?;
    const filer = try fixtureRole(.filer, "profile-filer", "filer-revision");
    const roles = [_]TaxpayerRevisionBinding{filer};
    const identity = try fixtureIdentity(form, filer.profile_id);
    const activity_id = try registration.ActivityAnchorId.parse("activity-main");
    const obligation_id = try registration.ObligationAnchorId.parse("obligation-income");
    var components = [_]ComponentBinding{
        .{ .business_activity = .{
            .role = .filer,
            .anchor = .{ .owner_profile_id = filer.profile_id, .id = activity_id },
            .component_revision_id = try registration.ComponentRevisionId.parse("activity-revision-2"),
            .component_revision_sequence = 2,
        } },
        .{ .registration_obligation = .{
            .role = .filer,
            .anchor = .{ .owner_profile_id = filer.profile_id, .id = obligation_id },
            .component_revision_id = try registration.ComponentRevisionId.parse("obligation-revision-3"),
            .component_revision_sequence = 3,
        } },
    };
    const sources = [_]SourceSnapshot{
        .{
            .key = .{ .tax_form_profile_value = .{
                .role = .filer,
                .key = .business_activity_anchor_id,
            } },
            .copied_value = .{ .business_activity_anchor_id = activity_id },
        },
        .{
            .key = .{ .registration_obligation_fact = .{
                .role = .filer,
                .anchor_id = obligation_id,
                .key = .registration_kind,
            } },
            .copied_value = .{ .choice = try OwnedText.copy("registered_income_tax") },
        },
    };
    const input: CaptureInput = .{
        .identity = identity,
        .taxpayer_revisions = &roles,
        .tax_form_profile_revision = try fixtureFormProfile(&identity, "1601c-setup"),
        .components = &components,
        .source_snapshots = &sources,
    };
    _ = try DraftProvenance.capture(&input, form);

    components[0].business_activity.anchor.owner_profile_id =
        try model.ProfileId.parse("another-profile");
    try std.testing.expectError(
        error.WrongComponentOwner,
        DraftProvenance.capture(&input, form),
    );

    components[0].business_activity.anchor.owner_profile_id = filer.profile_id;
    components[1].registration_obligation.role = .spouse;
    try std.testing.expectError(
        error.WrongComponentRole,
        DraftProvenance.capture(&input, form),
    );
}

test "duplicate source keys fail even when copied values differ" {
    const form = catalog.findForm("2551Q").?;
    const filer = try fixtureRole(.filer, "profile-filer", "filer-revision");
    const roles = [_]TaxpayerRevisionBinding{filer};
    const sources = [_]SourceSnapshot{
        .{
            .key = .{ .taxpayer_fact = .{ .role = .filer, .key = .tin } },
            .copied_value = .{ .text = try OwnedText.copy("123") },
        },
        .{
            .key = .{ .taxpayer_fact = .{ .role = .filer, .key = .tin } },
            .copied_value = .{ .text = try OwnedText.copy("456") },
        },
    };
    const input: CaptureInput = .{
        .identity = try fixtureIdentity(form, filer.profile_id),
        .taxpayer_revisions = &roles,
        .source_snapshots = &sources,
    };
    try std.testing.expectError(
        error.DuplicateSourceKey,
        DraftProvenance.capture(&input, form),
    );
}

test "capture owns copied values so later source edits cannot rewrite history" {
    const form = catalog.findForm("2551Q").?;
    const filer = try fixtureRole(.filer, "profile-filer", "filer-revision");
    const roles = [_]TaxpayerRevisionBinding{filer};
    var mutable_source = [_]u8{ 'O', 'R', 'I', 'G', 'I', 'N', 'A', 'L' };
    var sources = [_]SourceSnapshot{.{
        .key = .{ .taxpayer_fact = .{ .role = .filer, .key = .taxpayer_name } },
        .copied_value = .{ .text = try OwnedText.copy(&mutable_source) },
    }};
    const input: CaptureInput = .{
        .identity = try fixtureIdentity(form, filer.profile_id),
        .taxpayer_revisions = &roles,
        .source_snapshots = &sources,
    };
    const snapshot = try DraftProvenance.capture(&input, form);

    @memset(&mutable_source, 'X');
    sources[0].copied_value = .{ .text = try OwnedText.copy("CHANGED") };
    const copied = snapshot.sourceSnapshots()[0].copied_value.text;
    try std.testing.expectEqualStrings("ORIGINAL", copied.asSlice());
}

test "transaction seed provenance stays immutable after filing-owned edit" {
    const roles_fixture = [_]catalog.Role{ .filer, .filing };
    const profile_roles_fixture = [_]catalog.ProfileRoleDefinition{.{
        .role = .filer,
        .cardinality = .exactly_one,
        .allowed_subjects = &.{.individual},
        .distinct_from = &.{},
    }};
    const values_fixture = [_]catalog.TaxFormProfileValueDefinition{.{
        .semantic_key = .special_rate_obligation_anchor_id,
        .value_type = .choice,
        .role = .filer,
        .presence = .optional,
        .validation_rule = .catalog_choice,
        .ownership = .transaction_default,
        .source_kind = .user_entry,
        .availability = .supported,
        .source_evidence = "domain fixture for transaction-default separation",
        .evidence_gate = null,
    }};
    const form_fixture: catalog.FormDefinition = .{
        .code = "TDEF",
        .display_title = "Transaction default fixture",
        .tax_category = .income_tax,
        .revision = "fixture-1",
        .status = .static_layout,
        .cadence = .annual,
        .min_period = null,
        .max_period = null,
        .source_path = null,
        .roles = &roles_fixture,
        .profile_roles = &profile_roles_fixture,
        .tax_form_profile = .{
            .mode = .setup,
            .spec_revision = 1,
            .spec_hash = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            .source_evidence = "domain fixture",
            .values = &values_fixture,
        },
        .consumed_taxpayer_year_settings = &.{},
        .fields = &.{},
    };
    const filer = try fixtureRole(.filer, "profile-filer", "filer-revision");
    const roles = [_]TaxpayerRevisionBinding{filer};
    const identity = try fixtureIdentity(&form_fixture, filer.profile_id);
    const form_profile = try fixtureFormProfile(&identity, "fixture-setup-revision");
    const filing_field = try DraftFieldKey.parse("filing.special-rate-choice");
    const source_key: SourceKey = .{ .tax_form_profile_value = .{
        .role = .filer,
        .key = .special_rate_obligation_anchor_id,
    } };
    const seeds = [_]TransactionDefaultSeed{.{
        .filing_field = filing_field,
        .source_key = source_key,
        .source = .{ .tax_form_profile_revision = form_profile.revision_id },
        .copied_seed_value = .{ .choice = try OwnedText.copy("original-default") },
    }};
    const input: CaptureInput = .{
        .identity = identity,
        .taxpayer_revisions = &roles,
        .tax_form_profile_revision = form_profile,
        .transaction_seeds = &seeds,
    };
    const snapshot = try DraftProvenance.capture(&input, &form_fixture);
    var filing_values = FilingOwnedValues.fromProvenance(&snapshot);
    try filing_values.set(
        &filing_field,
        .{ .choice = try OwnedText.copy("edited-by-filer") },
    );

    const immutable_seed = snapshot.transactionSeedForField(&filing_field).?;
    try std.testing.expectEqualStrings(
        "original-default",
        immutable_seed.copied_seed_value.choice.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "edited-by-filer",
        filing_values.get(&filing_field).?.value.choice.asSlice(),
    );
}
