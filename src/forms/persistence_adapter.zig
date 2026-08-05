//! Persistence bridge for immutable profile-prefill form drafts.
//!
//! Runtime composition deliberately knows nothing about SQLite. This adapter
//! turns its named role bindings and owned projection snapshot into the store
//! write vocabulary, while keeping transaction values in their separate
//! table. Existing deterministic original drafts are resumed as-is: a newer
//! profile revision or mapping revision never refreshes their snapshot.

const std = @import("std");
const ids = @import("id.zig");
const runtime = @import("runtime.zig");
const spec = @import("spec.zig");
const form_1701q = @import("form_1701q.zig");
const form_2551q = @import("form_2551q.zig");
const form_catalog = @import("generated/catalog.zig");
const filing_period = @import("filing_period.zig");
const catalog_projection = @import("catalog_projection.zig");
const draft_provenance = @import("draft_provenance.zig");
const field = @import("../tax_profile/field.zig");
const forms_set_history = @import("../tax_profile/forms_set_history.zig");
const model = @import("../tax_profile/model.zig");
const projection = @import("../tax_profile/projection.zig");
const registration = @import("../tax_profile/registration.zig");
const annual_profile = @import("../tax_profile/tax_form_profile.zig");
const year_settings = @import("../tax_profile/taxpayer_year_settings.zig");
const profile_persistence = @import("../tax_profile/persistence_adapter.zig");
const store_module = @import("../tax_profile/store.zig");

pub const mapping_revision_v1 = "tax-profile-snapshot-v1";
pub const max_serialized_value_len = 255;
pub const canonical_period_key_len = 7;
pub const filing_period_key_capacity = filing_period.key_capacity;

pub const Error = error{
    DuplicateSnapshotTarget,
    DuplicateRoleBinding,
    ExistingDraftMismatch,
    FormSnapshotMismatch,
    InvalidPeriod,
    InvalidRoleBindingCount,
    InvalidSnapshotEntryCount,
    MissingFilerBinding,
    MissingRequiredRoleBinding,
    MissingRequiredSnapshotField,
    OutputTooSmall,
    RoleProfilesMustBeDistinct,
    SnapshotBindingMismatch,
    SnapshotFieldTypeMismatch,
    SnapshotProvenanceMismatch,
    SnapshotRoleMismatch,
    UnexpectedSnapshotTarget,
    UnexpectedRoleBinding,
    UnsupportedFormRevision,
    UnsupportedSnapshotOverride,
};

/// Original IDs are derived by this adapter. Amendment IDs are deliberately
/// supplied by the caller, which must generate a fresh opaque/random ID.
pub const DraftMode = union(enum) {
    original,
    amendment: struct {
        caller_supplied_id: ids.DraftId,
        amendment_of: ids.DraftId,
    },
};

pub const OpenDisposition = enum {
    created,
    resumed,
};

pub const OpenedDraft = struct {
    disposition: OpenDisposition,
    draft: store_module.OwnedDraft,

    pub fn deinit(
        self: *OpenedDraft,
        allocator: std.mem.Allocator,
    ) void {
        self.draft.deinit(allocator);
        self.* = undefined;
    }
};

/// Result of resuming the independent v17 provenance stream. The legacy tag
/// is explicit and never fabricates an annual/profile binding for an older
/// coarse draft. Exact decision strings borrow `storage` until `deinit`.
pub const LoadedDraftProvenance = union(enum) {
    provenance_legacy_absent,
    /// Persisted provenance rows exist but fail semantic or storage decoding.
    /// Resume callers must block rather than replacing them from current
    /// mutable profile state.
    corrupt: anyerror,
    exact: struct {
        provenance_snapshot: draft_provenance.DraftProvenance,
        forms_set_decision: forms_set_history.Decision,
        applicability_date: model.Date,
        storage: store_module.OwnedDraftProvenance,
    },

    pub fn deinit(
        self: *LoadedDraftProvenance,
        allocator: std.mem.Allocator,
    ) void {
        switch (self.*) {
            .provenance_legacy_absent => {},
            .corrupt => {},
            .exact => |*exact| exact.storage.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const ExactProvenanceInput = struct {
    applicability_date: model.Date,
    forms_set_decision: *const forms_set_history.Decision,
    snapshot: *const draft_provenance.DraftProvenance,
};

/// Coarse draft plus the immutable provenance state that controls whether the
/// draft may be safely resumed. New results are always `.exact`; existing
/// pre-v17 drafts remain explicitly legacy and corrupt rows remain blocked.
pub const OpenedDraftWithProvenance = struct {
    disposition: OpenDisposition,
    draft: store_module.OwnedDraft,
    provenance: LoadedDraftProvenance,

    pub fn deinit(
        self: *OpenedDraftWithProvenance,
        allocator: std.mem.Allocator,
    ) void {
        self.provenance.deinit(allocator);
        self.draft.deinit(allocator);
        self.* = undefined;
    }
};

/// Typed runtime state reconstructed from a persisted immutable snapshot.
/// Transaction values remain in `OwnedDraft.values` and are intentionally not
/// folded into this profile projection.
pub const RehydratedDraft = struct {
    form: ids.FormRevision,
    period: filing_period.FilingPeriod,
    role_bindings: runtime.RoleBindings,
    snapshot: projection.Snapshot,
};

pub const OpenInput = struct {
    mode: DraftMode = .original,
    period: runtime.RecurringQuarter,
    /// Set for monthly, annual, and on-demand opens. When omitted, the
    /// legacy recurring-quarter value above is converted to a quarterly
    /// FilingPeriod.
    filing_period: ?filing_period.FilingPeriod = null,
    role_bindings: *const runtime.RoleBindings,
    snapshot: *const projection.Snapshot,
    mapping_revision: []const u8 = mapping_revision_v1,
    transaction_values: []const store_module.DraftValueWrite = &.{},
};

/// Canonical recurring-quarter key shared by persistence and deterministic
/// identity. It is always exactly `YYYY-QN`.
pub fn canonicalPeriodKey(
    period: runtime.RecurringQuarter,
    output: *[canonical_period_key_len]u8,
) Error![]const u8 {
    if (period.tax_year == 0 or
        period.tax_year > 9999 or
        period.quarter < 1 or
        period.quarter > 4)
    {
        return error.InvalidPeriod;
    }
    return std.fmt.bufPrint(
        output,
        "{d:0>4}-Q{d}",
        .{ period.tax_year, period.quarter },
    ) catch unreachable;
}

/// Canonical key for every catalog cadence. The store already allows period
/// keys up to 64 bytes; this bounded representation keeps the identity stable
/// and leaves room for future period policies without truncation.
pub fn canonicalFilingPeriodKey(
    form: *const ids.FormRevision,
    period: filing_period.FilingPeriod,
    output: *[filing_period_key_capacity]u8,
) Error![]const u8 {
    const definition = form_catalog.findForm(form.code.asSlice()) orelse
        return error.UnsupportedFormRevision;
    const revision = definition.revision orelse
        return error.UnsupportedFormRevision;
    if (!std.mem.eql(u8, revision, form.revision.asSlice())) {
        return error.UnsupportedFormRevision;
    }
    if (period.taxYear() == 0) return error.InvalidPeriod;
    if (period.cadence() != definition.cadence) return error.InvalidPeriod;
    const slot = switch (period) {
        .monthly => |value| value.month,
        .quarterly => |value| value.quarter,
        .annual, .on_demand => null,
    };
    if (slot) |value| {
        if (definition.min_period) |minimum| if (value < minimum)
            return error.InvalidPeriod;
        if (definition.max_period) |maximum| if (value > maximum)
            return error.InvalidPeriod;
    }
    return period.key(output) catch return error.InvalidPeriod;
}

/// Derives the stable identity for one original recurring draft.
///
/// Length-delimited zero bytes make the hash input unambiguous. The complete
/// form code and revision label are included, so a form revision can never
/// silently reuse an older draft.
pub fn originalDraftId(
    filer_profile_id: model.ProfileId,
    period: runtime.RecurringQuarter,
) Error!ids.DraftId {
    const generic_period: filing_period.FilingPeriod = .{ .quarterly = .{
        .tax_year = period.tax_year,
        .quarter = period.quarter,
    } };
    return originalDraftIdForFilingPeriod(
        filer_profile_id,
        &period.form,
        generic_period,
    );
}

pub fn originalDraftIdForFilingPeriod(
    filer_profile_id: model.ProfileId,
    form: *const ids.FormRevision,
    period: filing_period.FilingPeriod,
) Error!ids.DraftId {
    var period_buffer: [filing_period_key_capacity]u8 = undefined;
    const period_key = try canonicalFilingPeriodKey(form, period, &period_buffer);

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("ebirforms.tax-draft.v1");
    hash.update(&.{0});
    hash.update(filer_profile_id.asSlice());
    hash.update(&.{0});
    hash.update(form.code.asSlice());
    hash.update(&.{0});
    hash.update(form.revision.asSlice());
    hash.update(&.{0});
    hash.update(period_key);
    hash.final(&digest);

    const encoded = std.fmt.bytesToHex(digest, .lower);
    comptime {
        std.debug.assert(encoded.len <= 64);
    }
    return ids.DraftId.parse(&encoded) catch unreachable;
}

const NamedRoleIdentity = struct {
    role: ids.Role,
    profile_id: model.ProfileId,
};

fn supportedProfileSpec(
    form: *const ids.FormRevision,
) Error!spec.FormSpec {
    if (form.eql(&form_2551q.revision)) return form_2551q.profile_spec;
    if (form.eql(&form_1701q.revision)) return form_1701q.profile_spec;
    return error.UnsupportedFormRevision;
}

fn catalogDefinition(
    form: *const ids.FormRevision,
) Error!*const form_catalog.FormDefinition {
    const definition = form_catalog.findForm(form.code.asSlice()) orelse
        return error.UnsupportedFormRevision;
    const revision = definition.revision orelse
        return error.UnsupportedFormRevision;
    if (!std.mem.eql(u8, revision, form.revision.asSlice()) or
        definition.status != .static_layout)
    {
        return error.UnsupportedFormRevision;
    }
    return definition;
}

fn catalogRole(
    role: ids.Role,
) ?form_catalog.Role {
    return std.meta.stringToEnum(form_catalog.Role, @tagName(role));
}

fn catalogProfileRole(
    definition: *const form_catalog.FormDefinition,
    role: ids.Role,
) ?*const form_catalog.ProfileRoleDefinition {
    const wanted = catalogRole(role) orelse return null;
    for (definition.profile_roles) |*policy| {
        if (policy.role == wanted) return policy;
    }
    return null;
}

fn validateCatalogRoleIdentities(
    form: *const ids.FormRevision,
    identities: []const NamedRoleIdentity,
) Error!void {
    const definition = try catalogDefinition(form);
    for (identities, 0..) |identity, index| {
        for (identities[index + 1 ..]) |other| {
            if (identity.role == other.role) return error.DuplicateRoleBinding;
        }
        if (catalogProfileRole(definition, identity.role) == null) {
            return error.UnexpectedRoleBinding;
        }
    }

    for (definition.profile_roles) |policy| {
        const role = catalog_projection.domainRole(policy.role) orelse
            return error.UnsupportedFormRevision;
        var count: usize = 0;
        for (identities) |identity| {
            if (identity.role == role) count += 1;
        }
        switch (policy.cardinality) {
            .exactly_one => if (count != 1) {
                if (role == .filer) return error.MissingFilerBinding;
                return error.MissingRequiredRoleBinding;
            },
            .zero_or_one => if (count > 1) return error.DuplicateRoleBinding,
        }
    }

    for (definition.profile_roles) |policy| {
        const left = catalog_projection.domainRole(policy.role) orelse
            return error.UnsupportedFormRevision;
        const left_identity = findIdentity(identities, left) orelse continue;
        for (policy.distinct_from) |other_catalog_role| {
            const right = catalog_projection.domainRole(other_catalog_role) orelse
                return error.UnsupportedFormRevision;
            const right_identity = findIdentity(identities, right) orelse continue;
            if (left_identity.profile_id.eql(&right_identity.profile_id)) {
                return error.RoleProfilesMustBeDistinct;
            }
        }
    }
}

fn findIdentity(
    identities: []const NamedRoleIdentity,
    role: ids.Role,
) ?*const NamedRoleIdentity {
    for (identities) |*identity| {
        if (identity.role == role) return identity;
    }
    return null;
}

fn validateNamedRoleIdentities(
    form_spec: spec.FormSpec,
    identities: []const NamedRoleIdentity,
) Error!void {
    for (identities, 0..) |identity, index| {
        for (identities[index + 1 ..]) |other| {
            if (identity.role == other.role) {
                return error.DuplicateRoleBinding;
            }
        }
        if (form_spec.role(identity.role) == null) {
            return error.UnexpectedRoleBinding;
        }
    }

    for (form_spec.roles) |role_spec| {
        var count: usize = 0;
        for (identities) |identity| {
            if (identity.role == role_spec.role) count += 1;
        }
        switch (role_spec.cardinality) {
            .exactly_one => if (count != 1) {
                if (role_spec.role == .filer) {
                    return error.MissingFilerBinding;
                }
                return error.MissingRequiredRoleBinding;
            },
            .zero_or_one => if (count > 1) {
                return error.DuplicateRoleBinding;
            },
        }
    }

    for (form_spec.distinct_profile_roles) |constraint| {
        var left: ?*const NamedRoleIdentity = null;
        var right: ?*const NamedRoleIdentity = null;
        for (identities) |*identity| {
            if (identity.role == constraint.left) left = identity;
            if (identity.role == constraint.right) right = identity;
        }
        if (left != null and right != null and
            left.?.profile_id.eql(&right.?.profile_id))
        {
            return error.RoleProfilesMustBeDistinct;
        }
    }
}

fn validateRuntimeRoleBindings(
    form: *const ids.FormRevision,
    bindings: *const runtime.RoleBindings,
) Error!void {
    if (@as(usize, bindings.len) > bindings.entries.len) {
        return error.InvalidRoleBindingCount;
    }
    var identities: [runtime.max_role_bindings]NamedRoleIdentity = undefined;
    for (bindings.entries[0..bindings.len], 0..) |*binding, index| {
        identities[index] = .{
            .role = binding.role,
            .profile_id = binding.profile_id,
        };
    }
    if (supportedProfileSpec(form)) |form_spec| {
        try validateNamedRoleIdentities(form_spec, identities[0..bindings.len]);
    } else |err| switch (err) {
        error.UnsupportedFormRevision => try validateCatalogRoleIdentities(form, identities[0..bindings.len]),
        else => return err,
    }
}

fn validateOwnedRoleBindings(
    form: *const ids.FormRevision,
    bindings: []const store_module.OwnedRoleBinding,
) !void {
    if (bindings.len > runtime.max_role_bindings) {
        return error.InvalidRoleBindingCount;
    }
    var identities: [runtime.max_role_bindings]NamedRoleIdentity = undefined;
    for (bindings, 0..) |*binding, index| {
        identities[index] = .{
            .role = std.meta.stringToEnum(
                ids.Role,
                binding.role,
            ) orelse return error.UnexpectedRoleBinding,
            .profile_id = try model.ProfileId.parse(binding.profile_id),
        };
    }
    if (supportedProfileSpec(form)) |form_spec| {
        try validateNamedRoleIdentities(form_spec, identities[0..bindings.len]);
    } else |err| switch (err) {
        error.UnsupportedFormRevision => try validateCatalogRoleIdentities(form, identities[0..bindings.len]),
        else => return err,
    }
}

const RequirementMatch = struct {
    role: ids.Role,
    requirement: *const spec.Requirement,
};

const CatalogRequirementMatch = struct {
    role: ids.Role,
    source: field.ReusableField,
    presence: form_catalog.ProfilePresence,
};

fn requirementForTarget(
    form_spec: spec.FormSpec,
    target: *const ids.FieldId,
) ?RequirementMatch {
    for (form_spec.roles) |*role_spec| {
        for (role_spec.requirements) |*requirement| {
            if (requirement.target.eql(target)) {
                return .{
                    .role = role_spec.role,
                    .requirement = requirement,
                };
            }
        }
    }
    return null;
}

fn catalogRequirementForTarget(
    definition: *const form_catalog.FormDefinition,
    target: *const ids.FieldId,
) ?CatalogRequirementMatch {
    for (definition.fields) |catalog_field| {
        if (catalog_field.provenance != .profile) continue;
        if (!std.mem.eql(u8, catalog_field.id, target.asSlice())) continue;
        const role = catalog_projection.domainRole(catalog_field.role) orelse
            return null;
        const source = catalog_projection.reusableField(
            catalog_field.profile_key orelse return null,
        ) orelse return null;
        return .{
            .role = role,
            .source = source,
            .presence = catalog_field.profile_presence orelse return null,
        };
    }
    return null;
}

fn validateSnapshotEntryProvenance(
    bindings: *const runtime.RoleBindings,
    entry: *const projection.SnapshotEntry,
) Error!void {
    const binding = bindings.get(entry.role) orelse
        return error.SnapshotBindingMismatch;
    if (!binding.profile_id.eql(&entry.provenance.profile_id) or
        !binding.revision_id.eql(&entry.provenance.revision_id) or
        binding.revision_sequence != entry.provenance.revision_sequence or
        !revisionSourcesEqual(
            &binding.revision_source,
            &entry.provenance.revision_source,
        ))
    {
        return error.SnapshotProvenanceMismatch;
    }
    if (binding.business_activity_id) |selected| {
        if (entry.provenance.business_activity_id) |projected| {
            if (!selected.eql(&projected)) {
                return error.SnapshotProvenanceMismatch;
            }
        }
    }
}

fn validateSnapshotShape(
    form: *const ids.FormRevision,
    bindings: *const runtime.RoleBindings,
    snapshot: *const projection.Snapshot,
) Error!void {
    try validateRuntimeRoleBindings(form, bindings);
    if (!snapshot.form.eql(form)) return error.FormSnapshotMismatch;
    if (@as(usize, snapshot.len) > snapshot.entries.len) {
        return error.InvalidSnapshotEntryCount;
    }
    const form_spec = supportedProfileSpec(form) catch |err| switch (err) {
        error.UnsupportedFormRevision => return validateCatalogSnapshotShape(
            form,
            bindings,
            snapshot,
        ),
        else => return err,
    };
    const entries = snapshot.entries[0..snapshot.len];

    for (entries, 0..) |*entry, index| {
        for (entries[index + 1 ..]) |*other| {
            if (entry.target.eql(&other.target)) {
                return error.DuplicateSnapshotTarget;
            }
        }
        const matched = requirementForTarget(
            form_spec,
            &entry.target,
        ) orelse return error.UnexpectedSnapshotTarget;
        if (entry.role != matched.role) {
            return error.SnapshotRoleMismatch;
        }
        if (bindings.get(entry.role) == null) {
            return error.SnapshotBindingMismatch;
        }
        if (entry.value.field() != matched.requirement.source) {
            return error.SnapshotFieldTypeMismatch;
        }
        try validateSnapshotEntryProvenance(bindings, entry);
    }

    for (bindings.slice()) |*binding| {
        const role_spec = form_spec.role(binding.role) orelse
            unreachable;
        for (role_spec.requirements) |*requirement| {
            var count: usize = 0;
            for (entries) |*entry| {
                if (entry.role == binding.role and
                    entry.target.eql(&requirement.target))
                {
                    count += 1;
                }
            }
            switch (requirement.presence) {
                .required => if (count != 1) {
                    return error.MissingRequiredSnapshotField;
                },
                .optional => if (count > 1) {
                    return error.DuplicateSnapshotTarget;
                },
            }
        }
    }

    for (bindings.slice()) |*binding| {
        var activity_id = binding.business_activity_id;
        for (entries) |*entry| {
            if (entry.role != binding.role) continue;
            const projected =
                entry.provenance.business_activity_id orelse continue;
            if (activity_id) |selected| {
                if (!selected.eql(&projected)) {
                    return error.SnapshotProvenanceMismatch;
                }
            } else {
                activity_id = projected;
            }
        }
    }
}

fn validateCatalogSnapshotShape(
    form: *const ids.FormRevision,
    bindings: *const runtime.RoleBindings,
    snapshot: *const projection.Snapshot,
) Error!void {
    const definition = try catalogDefinition(form);
    const entries = snapshot.entries[0..snapshot.len];

    for (entries, 0..) |*entry, index| {
        for (entries[index + 1 ..]) |*other| {
            if (entry.target.eql(&other.target)) {
                return error.DuplicateSnapshotTarget;
            }
        }
        const matched = catalogRequirementForTarget(definition, &entry.target) orelse
            return error.UnexpectedSnapshotTarget;
        if (entry.role != matched.role) return error.SnapshotRoleMismatch;
        if (bindings.get(entry.role) == null) {
            return error.SnapshotBindingMismatch;
        }
        if (entry.value.field() != matched.source) {
            return error.SnapshotFieldTypeMismatch;
        }
        try validateSnapshotEntryProvenance(bindings, entry);
    }

    for (definition.fields) |catalog_field| {
        if (catalog_field.provenance != .profile) continue;
        const role = catalog_projection.domainRole(catalog_field.role) orelse
            return error.UnexpectedRoleBinding;
        const role_policy = catalogProfileRole(definition, role) orelse
            return error.MissingRequiredRoleBinding;
        // Optional roles have no projected profile fields when the role is
        // absent. This mirrors catalog_projection, which only emits fields
        // for a bound role; required fields become mandatory once that role
        // is actually selected.
        if (bindings.get(role) == null) {
            if (role_policy.cardinality == .zero_or_one) continue;
            return error.MissingRequiredRoleBinding;
        }
        const presence = catalog_field.profile_presence orelse
            return error.MissingRequiredSnapshotField;
        const target = catalog_field.id;
        var count: usize = 0;
        for (entries) |*entry| {
            if (entry.role == role and
                std.mem.eql(u8, entry.target.asSlice(), target))
            {
                count += 1;
            }
        }
        switch (presence) {
            .required => if (count != 1) return error.MissingRequiredSnapshotField,
            .optional => if (count > 1) return error.DuplicateSnapshotTarget,
        }
    }
}

/// Converts named runtime bindings to store writes. A business activity
/// resolved implicitly by projection is materialized into the binding so the
/// persisted snapshot identifies the exact component it used.
pub fn roleBindingWrites(
    bindings: *const runtime.RoleBindings,
    snapshot: *const projection.Snapshot,
    output: []store_module.RoleBindingWrite,
) Error![]const store_module.RoleBindingWrite {
    try validateSnapshotShape(&snapshot.form, bindings, snapshot);
    const source = bindings.slice();
    if (output.len < source.len) return error.OutputTooSmall;

    for (source, 0..) |*binding, index| {
        for (source[index + 1 ..]) |*other| {
            if (binding.role == other.role) {
                return error.DuplicateRoleBinding;
            }
        }

        var activity_id: ?[]const u8 =
            if (binding.business_activity_id) |*id| id.asSlice() else null;
        for (snapshot.slice()) |*entry| {
            if (entry.role != binding.role) continue;
            if (entry.provenance.business_activity_id) |*projected_activity| {
                if (activity_id) |selected| {
                    if (!std.mem.eql(
                        u8,
                        selected,
                        projected_activity.asSlice(),
                    )) {
                        return error.SnapshotProvenanceMismatch;
                    }
                } else {
                    // Keep the slice backed by the caller-owned snapshot;
                    // never point at a copied optional payload on the stack.
                    activity_id = projected_activity.asSlice();
                }
            }
        }

        output[index] = .{
            .role = @tagName(binding.role),
            .profile_id = binding.profile_id.asSlice(),
            .profile_revision_id = binding.revision_id.asSlice(),
            .profile_revision_sequence = binding.revision_sequence,
            .business_activity_id = activity_id,
        };
    }
    return output[0..source.len];
}

/// Converts an owned runtime snapshot to store writes without dropping its
/// source revision or component-level provenance.
pub fn snapshotFieldWrites(
    bindings: *const runtime.RoleBindings,
    snapshot: *const projection.Snapshot,
    output: []store_module.SnapshotFieldWrite,
    value_buffers: [][max_serialized_value_len]u8,
) Error![]const store_module.SnapshotFieldWrite {
    try validateSnapshotShape(&snapshot.form, bindings, snapshot);
    const entries = snapshot.slice();
    if (output.len < entries.len or value_buffers.len < entries.len) {
        return error.OutputTooSmall;
    }

    for (entries, 0..) |*entry, index| {
        try validateSnapshotEntryProvenance(bindings, entry);

        const serialized = profile_persistence.serializeValue(
            &entry.value,
            &value_buffers[index],
        );
        output[index] = .{
            .role = @tagName(entry.role),
            .field_id = entry.target.asSlice(),
            .reusable_field = @tagName(entry.value.field()),
            .value_type = serialized.value_type,
            .value_text = serialized.text,
            .provenance = "tax_profile",
            .profile_revision_id = entry.provenance.revision_id.asSlice(),
            .profile_revision_sequence = entry.provenance.revision_sequence,
            .revision_source = revisionSourceWrite(
                &entry.provenance.revision_source,
            ),
            .business_activity_id = if (entry.provenance.business_activity_id) |*id|
                id.asSlice()
            else
                null,
            .registration_fact_id = if (entry.provenance.registration_fact_id) |*id|
                id.asSlice()
            else
                null,
            .overridden = false,
        };
    }
    return output[0..entries.len];
}

/// Normalized Registration activities are not children of the immutable Base
/// Tax Profile revision. The v1 coarse-draft tables can therefore persist only
/// legacy profile-owned activity IDs; exact provenance owns Registration
/// anchors and their component revisions. Strip those normalized anchor IDs
/// from compatibility rows while retaining copied values and the authoritative
/// exact provenance sidecar.
fn removeRegistrationActivitiesFromCoarseWrites(
    exact: *const draft_provenance.DraftProvenance,
    bindings: []store_module.RoleBindingWrite,
    snapshots: []store_module.SnapshotFieldWrite,
) void {
    for (exact.components()) |*component| switch (component.*) {
        .business_activity => |*activity| {
            const role = catalog_projection.domainRole(activity.role) orelse
                continue;
            const role_text = @tagName(role);
            const anchor_text = activity.anchor.id.asSlice();
            for (bindings) |*binding| {
                const selected = binding.business_activity_id orelse continue;
                if (!std.mem.eql(u8, binding.role, role_text) or
                    !std.mem.eql(u8, selected, anchor_text)) continue;
                binding.business_activity_id = null;
            }
            for (snapshots) |*snapshot| {
                const selected = snapshot.business_activity_id orelse continue;
                if (!std.mem.eql(u8, snapshot.role, role_text) or
                    !std.mem.eql(u8, selected, anchor_text)) continue;
                snapshot.business_activity_id = null;
            }
        },
        .registration_obligation => {},
    };
}

/// Creates a new persisted draft or resumes the matching existing draft.
///
/// The existence check intentionally precedes write conversion. On resume,
/// newly composed role bindings, snapshot values, mapping revisions, and
/// transaction defaults are ignored. A concurrent creator is handled by
/// reading after the uniqueness conflict and applying the same identity
/// checks.
pub fn createOrLoad(
    allocator: std.mem.Allocator,
    store: *store_module.Store,
    input: OpenInput,
) !OpenedDraft {
    try validateInput(input);
    const identity = try resolveIdentity(input);
    const period = try inputFilingPeriod(input);

    if (try store.getDraft(allocator, identity.id.asSlice())) |existing| {
        return try resumeChecked(
            allocator,
            existing,
            input,
            identity,
        );
    }

    var role_writes: [runtime.max_role_bindings]store_module.RoleBindingWrite =
        undefined;
    const persisted_bindings = try roleBindingWrites(
        input.role_bindings,
        input.snapshot,
        &role_writes,
    );
    var snapshot_writes: [projection.max_snapshot_entries]store_module.SnapshotFieldWrite =
        undefined;
    var value_buffers: [projection.max_snapshot_entries][max_serialized_value_len]u8 =
        undefined;
    const persisted_snapshots = try snapshotFieldWrites(
        input.role_bindings,
        input.snapshot,
        &snapshot_writes,
        &value_buffers,
    );
    var period_buffer: [filing_period_key_capacity]u8 = undefined;
    const period_key = try canonicalFilingPeriodKey(
        &input.period.form,
        period,
        &period_buffer,
    );
    var date_buffer: store_module.DateText = undefined;
    _ = input.snapshot.effective_on.writeIso(&date_buffer);

    store.createDraft(
        .{
            .id = identity.id.asSlice(),
            .form_code = input.period.form.code.asSlice(),
            .form_revision = input.period.form.revision.asSlice(),
            .period_key = period_key,
            .profile_as_of = date_buffer,
            .intent = identity.intent,
            .mapping_revision = input.mapping_revision,
            .amendment_of = if (identity.amendment_of) |*id|
                id.asSlice()
            else
                null,
        },
        persisted_bindings,
        persisted_snapshots,
        input.transaction_values,
    ) catch |err| {
        if (err != error.SqliteConstraint) return err;
        if (try store.getDraft(
            allocator,
            identity.id.asSlice(),
        )) |existing| {
            return try resumeChecked(
                allocator,
                existing,
                input,
                identity,
            );
        }
        return err;
    };

    const created = (try store.getDraft(
        allocator,
        identity.id.asSlice(),
    )) orelse return error.ExistingDraftMismatch;
    return .{ .disposition = .created, .draft = created };
}

/// Creates a new coarse draft together with its full immutable provenance in
/// one transaction, or resumes the existing deterministic identity without
/// composing replacement provenance from today's mutable profile state.
pub fn createOrLoadWithProvenance(
    allocator: std.mem.Allocator,
    store: *store_module.Store,
    input: OpenInput,
    exact: ExactProvenanceInput,
) !OpenedDraftWithProvenance {
    try validateInput(input);
    const identity = try resolveIdentity(input);
    const period = try inputFilingPeriod(input);

    if (try store.getDraft(allocator, identity.id.asSlice())) |existing| {
        var opened = try resumeChecked(allocator, existing, input, identity);
        errdefer opened.deinit(allocator);
        const persisted = try loadDraftProvenanceForResume(
            store,
            allocator,
            identity.id,
        );
        return .{
            .disposition = opened.disposition,
            .draft = opened.draft,
            .provenance = persisted,
        };
    }

    var role_writes: [runtime.max_role_bindings]store_module.RoleBindingWrite =
        undefined;
    const persisted_bindings = try roleBindingWrites(
        input.role_bindings,
        input.snapshot,
        &role_writes,
    );
    var snapshot_writes: [projection.max_snapshot_entries]store_module.SnapshotFieldWrite =
        undefined;
    var value_buffers: [projection.max_snapshot_entries][max_serialized_value_len]u8 =
        undefined;
    const persisted_snapshots = try snapshotFieldWrites(
        input.role_bindings,
        input.snapshot,
        &snapshot_writes,
        &value_buffers,
    );
    var period_buffer: [filing_period_key_capacity]u8 = undefined;
    const period_key = try canonicalFilingPeriodKey(
        &input.period.form,
        period,
        &period_buffer,
    );
    var date_buffer: store_module.DateText = undefined;
    _ = input.snapshot.effective_on.writeIso(&date_buffer);
    const draft_write: store_module.DraftWrite = .{
        .id = identity.id.asSlice(),
        .form_code = input.period.form.code.asSlice(),
        .form_revision = input.period.form.revision.asSlice(),
        .period_key = period_key,
        .profile_as_of = date_buffer,
        .intent = identity.intent,
        .mapping_revision = input.mapping_revision,
        .amendment_of = if (identity.amendment_of) |*id|
            id.asSlice()
        else
            null,
    };
    removeRegistrationActivitiesFromCoarseWrites(
        exact.snapshot,
        role_writes[0..persisted_bindings.len],
        snapshot_writes[0..persisted_snapshots.len],
    );
    var provenance_buffers: DraftProvenanceWriteBuffers = .{};
    const provenance_write = try draftProvenanceWrite(
        identity.id,
        0,
        exact,
        &provenance_buffers,
    );

    _ = store.createDraftWithProvenance(
        draft_write,
        persisted_bindings,
        persisted_snapshots,
        input.transaction_values,
        provenance_write,
    ) catch |err| {
        if (err != error.SqliteConstraint) return err;
        if (try store.getDraft(
            allocator,
            identity.id.asSlice(),
        )) |existing| {
            var opened = try resumeChecked(
                allocator,
                existing,
                input,
                identity,
            );
            errdefer opened.deinit(allocator);
            const persisted = try loadDraftProvenanceForResume(
                store,
                allocator,
                identity.id,
            );
            return .{
                .disposition = opened.disposition,
                .draft = opened.draft,
                .provenance = persisted,
            };
        }
        return err;
    };

    const created = (try store.getDraft(
        allocator,
        identity.id.asSlice(),
    )) orelse return error.ExistingDraftMismatch;
    errdefer {
        var owned = created;
        owned.deinit(allocator);
    }
    const persisted = try loadDraftProvenanceForResume(
        store,
        allocator,
        identity.id,
    );
    if (persisted != .exact) {
        var unexpected = persisted;
        unexpected.deinit(allocator);
        return error.ExistingDraftMismatch;
    }
    return .{
        .disposition = .created,
        .draft = created,
        .provenance = persisted,
    };
}

const DraftProvenanceWriteBuffers = struct {
    taxpayers: [draft_provenance.max_taxpayer_roles]store_module.DraftProvenanceTaxpayerRevisionWrite = undefined,
    components: [draft_provenance.max_component_bindings]store_module.DraftProvenanceComponentWrite = undefined,
    sources: [draft_provenance.max_source_snapshots]store_module.DraftProvenanceSourceSnapshotWrite = undefined,
    seeds: [draft_provenance.max_transaction_seeds]store_module.DraftProvenanceTransactionSeedWrite = undefined,
    applicability_text: store_module.DateText = undefined,
};

fn draftProvenanceWrite(
    draft_id: ids.DraftId,
    expected_current_sequence: u32,
    exact: ExactProvenanceInput,
    buffers: *DraftProvenanceWriteBuffers,
) !store_module.DraftProvenanceWrite {
    const snapshot = exact.snapshot;
    const definition = form_catalog.findForm(
        snapshot.identity.form_code.asSlice(),
    ) orelse return error.UnsupportedFormRevision;
    const capture_input: draft_provenance.CaptureInput = .{
        .identity = snapshot.identity,
        .taxpayer_revisions = snapshot.taxpayerRevisions(),
        .taxpayer_year_revision = snapshot.taxpayer_year_revision,
        .tax_form_profile_revision = snapshot.tax_form_profile_revision,
        .components = snapshot.components(),
        .source_snapshots = snapshot.sourceSnapshots(),
        .transaction_seeds = snapshot.transactionSeeds(),
    };
    _ = try draft_provenance.DraftProvenance.capture(
        &capture_input,
        definition,
    );
    try validateDraftFormsSetDecision(
        &snapshot.identity,
        exact.applicability_date,
        exact.forms_set_decision,
    );

    for (snapshot.taxpayerRevisions(), 0..) |*binding, index| {
        buffers.taxpayers[index] = .{
            .role = binding.role,
            .profile_id = binding.profile_id.asSlice(),
            .revision_id = binding.revision_id.asSlice(),
            .revision_sequence = binding.revision_sequence,
        };
    }
    for (snapshot.components(), 0..) |*component, index| {
        buffers.components[index] = draftProvenanceComponentToWrite(component);
    }
    for (snapshot.sourceSnapshots(), 0..) |*source, index| {
        buffers.sources[index] = .{
            .key = draftProvenanceSourceKeyToWrite(&source.key),
            .copied_value = draftProvenanceValueToWrite(
                &source.copied_value,
            ),
        };
    }
    for (snapshot.transactionSeeds(), 0..) |*seed, index| {
        buffers.seeds[index] = .{
            .filing_field = seed.filing_field.asSlice(),
            .source_key = draftProvenanceSourceKeyToWrite(&seed.source_key),
            .source = switch (seed.source) {
                .tax_form_profile_revision => |*revision_id| .{
                    .tax_form_profile_revision = revision_id.asSlice(),
                },
                .catalog_default => |*catalog_binding| .{ .catalog_default = .{
                    .revision = catalog_binding.revision.asSlice(),
                    .sha256 = catalog_binding.sha256.asSlice(),
                } },
            },
            .copied_seed_value = draftProvenanceValueToWrite(
                &seed.copied_seed_value,
            ),
        };
    }
    _ = exact.applicability_date.writeIso(&buffers.applicability_text);
    return .{
        .draft_id = draft_id.asSlice(),
        .expected_current_sequence = expected_current_sequence,
        .owner_profile_id = snapshot.identity.owner_profile_id.asSlice(),
        .tax_year = snapshot.identity.tax_year,
        .form_code = snapshot.identity.form_code.asSlice(),
        .form_revision = snapshot.identity.form_revision.asSlice(),
        .catalog_revision = snapshot.identity.catalog.revision.asSlice(),
        .catalog_sha256 = snapshot.identity.catalog.sha256.asSlice(),
        .setup_spec_revision = snapshot.identity.setup_spec_revision,
        .setup_spec_hash = snapshot.identity.setup_spec_hash.asSlice(),
        .forms_set_decision = .{
            .id = exact.forms_set_decision.id.asSlice(),
            .sequence = exact.forms_set_decision.sequence,
            .source = switch (exact.forms_set_decision.source) {
                .manual => .manual,
                .imported => .imported,
                .cor => .cor,
            },
            .evidence_reference = exact.forms_set_decision.evidence_reference,
            .applicability_date = buffers.applicability_text,
        },
        .taxpayer_revisions = buffers.taxpayers[0..snapshot.taxpayerRevisions().len],
        .taxpayer_year_revision = if (snapshot.taxpayer_year_revision) |*binding|
            .{
                .profile_id = binding.stream.profile_id.asSlice(),
                .tax_year = binding.stream.tax_year,
                .revision_id = binding.revision_id.asSlice(),
                .revision_sequence = binding.revision_sequence,
            }
        else
            null,
        .tax_form_profile_revision = if (snapshot.tax_form_profile_revision) |*binding|
            .{
                .profile_id = binding.stream.profile_id.asSlice(),
                .tax_year = binding.stream.tax_year,
                .form_code = binding.stream.form_code.asSlice(),
                .form_revision = binding.stream.form_revision.asSlice(),
                .revision_id = binding.revision_id.asSlice(),
                .revision_sequence = binding.revision_sequence,
                .spec_revision = binding.spec_revision,
                .spec_hash = binding.spec_hash.asSlice(),
            }
        else
            null,
        .components = buffers.components[0..snapshot.components().len],
        .source_snapshots = buffers.sources[0..snapshot.sourceSnapshots().len],
        .transaction_seeds = buffers.seeds[0..snapshot.transactionSeeds().len],
    };
}

/// Appends the exact provenance produced by `draft_provenance_adapter.compose`
/// to an already-created coarse draft. The store commits the parent and every
/// ordered binding/source/seed row atomically; the only legal optimistic head
/// for a new exact snapshot is zero.
pub fn appendDraftProvenance(
    store: *store_module.Store,
    draft_id: ids.DraftId,
    expected_current_sequence: u32,
    applicability_date: model.Date,
    decision: *const forms_set_history.Decision,
    snapshot: *const draft_provenance.DraftProvenance,
) !u32 {
    const definition = form_catalog.findForm(
        snapshot.identity.form_code.asSlice(),
    ) orelse return error.UnsupportedFormRevision;
    const capture_input: draft_provenance.CaptureInput = .{
        .identity = snapshot.identity,
        .taxpayer_revisions = snapshot.taxpayerRevisions(),
        .taxpayer_year_revision = snapshot.taxpayer_year_revision,
        .tax_form_profile_revision = snapshot.tax_form_profile_revision,
        .components = snapshot.components(),
        .source_snapshots = snapshot.sourceSnapshots(),
        .transaction_seeds = snapshot.transactionSeeds(),
    };
    _ = try draft_provenance.DraftProvenance.capture(
        &capture_input,
        definition,
    );
    try validateDraftFormsSetDecision(
        &snapshot.identity,
        applicability_date,
        decision,
    );

    var taxpayer_rows: [draft_provenance.max_taxpayer_roles]store_module.DraftProvenanceTaxpayerRevisionWrite =
        undefined;
    for (snapshot.taxpayerRevisions(), 0..) |*binding, index| {
        taxpayer_rows[index] = .{
            .role = binding.role,
            .profile_id = binding.profile_id.asSlice(),
            .revision_id = binding.revision_id.asSlice(),
            .revision_sequence = binding.revision_sequence,
        };
    }
    var component_rows: [draft_provenance.max_component_bindings]store_module.DraftProvenanceComponentWrite =
        undefined;
    for (snapshot.components(), 0..) |*component, index| {
        component_rows[index] = draftProvenanceComponentToWrite(component);
    }
    var source_rows: [draft_provenance.max_source_snapshots]store_module.DraftProvenanceSourceSnapshotWrite =
        undefined;
    for (snapshot.sourceSnapshots(), 0..) |*source, index| {
        source_rows[index] = .{
            .key = draftProvenanceSourceKeyToWrite(&source.key),
            .copied_value = draftProvenanceValueToWrite(
                &source.copied_value,
            ),
        };
    }
    var seed_rows: [draft_provenance.max_transaction_seeds]store_module.DraftProvenanceTransactionSeedWrite =
        undefined;
    for (snapshot.transactionSeeds(), 0..) |*seed, index| {
        seed_rows[index] = .{
            .filing_field = seed.filing_field.asSlice(),
            .source_key = draftProvenanceSourceKeyToWrite(&seed.source_key),
            .source = switch (seed.source) {
                .tax_form_profile_revision => |*revision_id| .{
                    .tax_form_profile_revision = revision_id.asSlice(),
                },
                .catalog_default => |*catalog| .{ .catalog_default = .{
                    .revision = catalog.revision.asSlice(),
                    .sha256 = catalog.sha256.asSlice(),
                } },
            },
            .copied_seed_value = draftProvenanceValueToWrite(
                &seed.copied_seed_value,
            ),
        };
    }
    var applicability_text: store_module.DateText = undefined;
    _ = applicability_date.writeIso(&applicability_text);
    return store.appendDraftProvenance(.{
        .draft_id = draft_id.asSlice(),
        .expected_current_sequence = expected_current_sequence,
        .owner_profile_id = snapshot.identity.owner_profile_id.asSlice(),
        .tax_year = snapshot.identity.tax_year,
        .form_code = snapshot.identity.form_code.asSlice(),
        .form_revision = snapshot.identity.form_revision.asSlice(),
        .catalog_revision = snapshot.identity.catalog.revision.asSlice(),
        .catalog_sha256 = snapshot.identity.catalog.sha256.asSlice(),
        .setup_spec_revision = snapshot.identity.setup_spec_revision,
        .setup_spec_hash = snapshot.identity.setup_spec_hash.asSlice(),
        .forms_set_decision = .{
            .id = decision.id.asSlice(),
            .sequence = decision.sequence,
            .source = switch (decision.source) {
                .manual => .manual,
                .imported => .imported,
                .cor => .cor,
            },
            .evidence_reference = decision.evidence_reference,
            .applicability_date = applicability_text,
        },
        .taxpayer_revisions = taxpayer_rows[0..snapshot.taxpayerRevisions().len],
        .taxpayer_year_revision = if (snapshot.taxpayer_year_revision) |*binding|
            .{
                .profile_id = binding.stream.profile_id.asSlice(),
                .tax_year = binding.stream.tax_year,
                .revision_id = binding.revision_id.asSlice(),
                .revision_sequence = binding.revision_sequence,
            }
        else
            null,
        .tax_form_profile_revision = if (snapshot.tax_form_profile_revision) |*binding|
            .{
                .profile_id = binding.stream.profile_id.asSlice(),
                .tax_year = binding.stream.tax_year,
                .form_code = binding.stream.form_code.asSlice(),
                .form_revision = binding.stream.form_revision.asSlice(),
                .revision_id = binding.revision_id.asSlice(),
                .revision_sequence = binding.revision_sequence,
                .spec_revision = binding.spec_revision,
                .spec_hash = binding.spec_hash.asSlice(),
            }
        else
            null,
        .components = component_rows[0..snapshot.components().len],
        .source_snapshots = source_rows[0..snapshot.sourceSnapshots().len],
        .transaction_seeds = seed_rows[0..snapshot.transactionSeeds().len],
    });
}

/// Rehydrates exactly the snapshot captured at draft creation. Newly added
/// profile, registration, taxpayer-year, form-profile, or catalog revisions
/// are never consulted. A real pre-v17 draft returns the explicit legacy tag.
pub fn loadDraftProvenance(
    store: *store_module.Store,
    allocator: std.mem.Allocator,
    draft_id: ids.DraftId,
) !LoadedDraftProvenance {
    const loaded = try store.getDraftProvenance(
        allocator,
        draft_id.asSlice(),
    );
    return switch (loaded) {
        .provenance_legacy_absent => .provenance_legacy_absent,
        .exact => |raw| blk: {
            var storage = raw;
            errdefer storage.deinit(allocator);
            const snapshot = try draftProvenanceFromOwned(&storage);
            const applicability_date = try model.Date.parseIso(
                storage.forms_set_applicability_date,
            );
            const decision = try formsSetDecisionFromOwned(
                &storage.forms_set_decision,
            );
            try validateDraftFormsSetDecision(
                &snapshot.identity,
                applicability_date,
                &decision,
            );
            break :blk .{ .exact = .{
                .provenance_snapshot = snapshot,
                .forms_set_decision = decision,
                .applicability_date = applicability_date,
                .storage = storage,
            } };
        },
    };
}

fn loadDraftProvenanceForResume(
    store: *store_module.Store,
    allocator: std.mem.Allocator,
    draft_id: ids.DraftId,
) !LoadedDraftProvenance {
    return loadDraftProvenance(store, allocator, draft_id) catch |err| switch (err) {
        error.OutOfMemory,
        error.Closed,
        error.SqliteBusy,
        error.NotFound,
        => return err,
        else => .{ .corrupt = err },
    };
}

/// Reconstructs the allocation-free runtime binding/snapshot types from one
/// store-owned draft. Every persisted semantic field is parsed through the
/// same validated profile codec used for profile revision persistence.
pub fn rehydrate(
    draft: *const store_module.OwnedDraft,
) !RehydratedDraft {
    const form: ids.FormRevision = .{
        .code = try ids.FormCode.parse(draft.form_code),
        .revision = try ids.RevisionLabel.parse(draft.form_revision),
    };
    const period = try parsePeriodKey(form, draft.period_key);
    const effective_on = try model.Date.parseIso(draft.profile_as_of);

    try validateOwnedRoleBindings(&form, draft.bindings);
    if (draft.snapshots.len > projection.max_snapshot_entries) {
        return error.OutputTooSmall;
    }

    var bindings: runtime.RoleBindings = .{};
    for (draft.bindings, 0..) |*stored, index| {
        const role = std.meta.stringToEnum(ids.Role, stored.role) orelse
            return error.SnapshotBindingMismatch;
        if (bindings.get(role) != null) return error.DuplicateRoleBinding;
        bindings.entries[index] = .{
            .role = role,
            .profile_id = try model.ProfileId.parse(stored.profile_id),
            .revision_id = try model.RevisionId.parse(
                stored.profile_revision_id,
            ),
            .revision_sequence = stored.profile_revision_sequence,
            .revision_source = try sourceForRole(draft, stored.role),
            .business_activity_id = if (stored.business_activity_id) |activity_id|
                try model.BusinessActivityId.parse(activity_id)
            else
                null,
        };
        bindings.len += 1;
    }

    var snapshot = projection.Snapshot.init(form, effective_on);
    for (draft.snapshots) |*stored| {
        if (!std.mem.eql(u8, stored.provenance, "tax_profile")) {
            return error.SnapshotProvenanceMismatch;
        }
        if (stored.overridden) return error.UnsupportedSnapshotOverride;

        const role = std.meta.stringToEnum(ids.Role, stored.role) orelse
            return error.SnapshotBindingMismatch;
        const binding = bindings.get(role) orelse
            return error.SnapshotBindingMismatch;
        if (!std.mem.eql(
            u8,
            binding.revision_id.asSlice(),
            stored.profile_revision_id,
        ) or
            binding.revision_sequence != stored.profile_revision_sequence)
        {
            return error.SnapshotProvenanceMismatch;
        }

        const reusable_field = std.meta.stringToEnum(
            field.ReusableField,
            stored.reusable_field,
        ) orelse return error.SnapshotProvenanceMismatch;
        const value = try profile_persistence.parseValue(
            reusable_field,
            stored.value_type,
            stored.value_text,
        );
        const revision_source = try revisionSourceFromOwned(
            &stored.revision_source,
        );
        if (!revisionSourcesEqual(
            &binding.revision_source,
            &revision_source,
        )) {
            return error.SnapshotProvenanceMismatch;
        }

        const activity_id = if (stored.business_activity_id) |id|
            try model.BusinessActivityId.parse(id)
        else
            null;
        if (activity_id) |projected| {
            const selected = binding.business_activity_id orelse
                return error.SnapshotProvenanceMismatch;
            if (!selected.eql(&projected)) {
                return error.SnapshotProvenanceMismatch;
            }
        }

        try snapshot.append(.{
            .role = role,
            .target = try ids.FieldId.parse(stored.field_id),
            .value = value,
            .provenance = .{
                .profile_id = binding.profile_id,
                .revision_id = binding.revision_id,
                .revision_sequence = binding.revision_sequence,
                .revision_source = revision_source,
                .business_activity_id = activity_id,
                .registration_fact_id = if (stored.registration_fact_id) |id|
                    try model.RegistrationFactId.parse(id)
                else
                    null,
            },
        });
    }
    try validateSnapshotShape(&form, &bindings, &snapshot);
    return .{
        .form = form,
        .period = period,
        .role_bindings = bindings,
        .snapshot = snapshot,
    };
}

const ResolvedIdentity = struct {
    id: ids.DraftId,
    intent: []const u8,
    amendment_of: ?ids.DraftId,
};

fn resolveIdentity(input: OpenInput) Error!ResolvedIdentity {
    const period = inputFilingPeriod(input) catch return error.InvalidPeriod;
    return switch (input.mode) {
        .original => .{
            .id = try originalDraftIdForFilingPeriod(
                input.role_bindings.get(.filer).?.profile_id,
                &input.period.form,
                period,
            ),
            .intent = "original",
            .amendment_of = null,
        },
        .amendment => |amendment| .{
            .id = amendment.caller_supplied_id,
            .intent = "amended",
            .amendment_of = amendment.amendment_of,
        },
    };
}

fn parsePeriodKey(
    form: ids.FormRevision,
    text: []const u8,
) !filing_period.FilingPeriod {
    const definition = try catalogDefinition(&form);
    const parsed = filing_period.FilingPeriod.parseKey(definition.cadence, text) catch
        return error.InvalidPeriod;
    var canonical: [filing_period_key_capacity]u8 = undefined;
    const checked = try canonicalFilingPeriodKey(&form, parsed, &canonical);
    if (!std.mem.eql(u8, text, checked)) return error.InvalidPeriod;
    return parsed;
}

fn validateInput(input: OpenInput) Error!void {
    const period = try inputFilingPeriod(input);
    var period_buffer: [filing_period_key_capacity]u8 = undefined;
    _ = try canonicalFilingPeriodKey(
        &input.period.form,
        period,
        &period_buffer,
    );
    try validateSnapshotShape(
        &input.period.form,
        input.role_bindings,
        input.snapshot,
    );
}

fn resumeChecked(
    allocator: std.mem.Allocator,
    existing: store_module.OwnedDraft,
    input: OpenInput,
    identity: ResolvedIdentity,
) !OpenedDraft {
    var draft = existing;
    errdefer draft.deinit(allocator);

    const period = try inputFilingPeriod(input);
    var period_buffer: [filing_period_key_capacity]u8 = undefined;
    const period_key = try canonicalFilingPeriodKey(
        &input.period.form,
        period,
        &period_buffer,
    );
    if (!std.mem.eql(u8, draft.form_code, input.period.form.code.asSlice()) or
        !std.mem.eql(
            u8,
            draft.form_revision,
            input.period.form.revision.asSlice(),
        ) or
        !std.mem.eql(u8, draft.period_key, period_key) or
        !std.mem.eql(u8, draft.intent, identity.intent) or
        !optionalTextEqual(
            draft.amendment_of,
            if (identity.amendment_of) |*id| id.asSlice() else null,
        ))
    {
        return error.ExistingDraftMismatch;
    }

    _ = try rehydrate(&draft);

    const filer_profile_id =
        input.role_bindings.get(.filer).?.profile_id.asSlice();
    var filer_matches = false;
    for (draft.bindings) |binding| {
        if (std.mem.eql(u8, binding.role, "filer") and
            std.mem.eql(u8, binding.profile_id, filer_profile_id))
        {
            filer_matches = true;
            break;
        }
    }
    if (!filer_matches) return error.ExistingDraftMismatch;

    return .{ .disposition = .resumed, .draft = draft };
}

fn inputFilingPeriod(input: OpenInput) Error!filing_period.FilingPeriod {
    if (input.filing_period) |period| return period;
    return .{ .quarterly = .{
        .tax_year = input.period.tax_year,
        .quarter = input.period.quarter,
    } };
}

fn revisionSourceWrite(
    source: *const model.RevisionSource,
) store_module.RevisionSourceWrite {
    return switch (source.*) {
        .manual_entry => .{ .manual_entry = {} },
        .imported => |*reference| .{ .imported = reference.asSlice() },
        .migrated => |*reference| .{ .migrated = reference.asSlice() },
    };
}

fn revisionSourceFromOwned(
    source: *const store_module.OwnedRevisionSource,
) !model.RevisionSource {
    return switch (source.*) {
        .manual_entry => .manual_entry,
        .imported => |reference| .{
            .imported = try field.SourceReference.parse(reference),
        },
        .migrated => |reference| .{
            .migrated = try field.SourceReference.parse(reference),
        },
    };
}

fn sourceForRole(
    draft: *const store_module.OwnedDraft,
    role: []const u8,
) !model.RevisionSource {
    var found: ?model.RevisionSource = null;
    for (draft.snapshots) |*snapshot| {
        if (!std.mem.eql(u8, snapshot.role, role)) continue;
        const source = try revisionSourceFromOwned(
            &snapshot.revision_source,
        );
        if (found) |*existing| {
            if (!revisionSourcesEqual(existing, &source)) {
                return error.SnapshotProvenanceMismatch;
            }
        } else {
            found = source;
        }
    }
    return found orelse error.SnapshotProvenanceMismatch;
}

fn revisionSourcesEqual(
    left: *const model.RevisionSource,
    right: *const model.RevisionSource,
) bool {
    if (std.meta.activeTag(left.*) != std.meta.activeTag(right.*)) {
        return false;
    }
    return switch (left.*) {
        .manual_entry => true,
        .imported => |*reference| reference.eql(&right.imported),
        .migrated => |*reference| reference.eql(&right.migrated),
    };
}

fn optionalTextEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn validateDraftFormsSetDecision(
    identity: *const draft_provenance.FilingIdentity,
    applicability_date: model.Date,
    decision: *const forms_set_history.Decision,
) !void {
    if (decision.review != .confirmed or decision.state != .active or
        decision.sequence == 0 or
        !decision.stream.profile_id.eql(&identity.owner_profile_id) or
        decision.stream.tax_year != identity.tax_year or
        !std.mem.eql(
            u8,
            decision.stream.form.code,
            identity.form_code.asSlice(),
        ) or !std.mem.eql(
        u8,
        decision.stream.form.revision,
        identity.form_revision.asSlice(),
    ) or !decision.appliesOn(applicability_date)) {
        return error.InvalidDraftProvenance;
    }
}

fn draftProvenanceComponentToWrite(
    component: *const draft_provenance.ComponentBinding,
) store_module.DraftProvenanceComponentWrite {
    return switch (component.*) {
        .business_activity => |*binding| .{ .business_activity = .{
            .role = binding.role,
            .profile_id = binding.anchor.owner_profile_id.asSlice(),
            .anchor_id = binding.anchor.id.asSlice(),
            .revision_id = binding.component_revision_id.asSlice(),
            .revision_sequence = binding.component_revision_sequence,
        } },
        .registration_obligation => |*binding| .{
            .registration_obligation = .{
                .role = binding.role,
                .profile_id = binding.anchor.owner_profile_id.asSlice(),
                .anchor_id = binding.anchor.id.asSlice(),
                .revision_id = binding.component_revision_id.asSlice(),
                .revision_sequence = binding.component_revision_sequence,
            },
        },
    };
}

fn draftProvenanceSourceKeyToWrite(
    key: *const draft_provenance.SourceKey,
) store_module.DraftProvenanceSourceKeyWrite {
    return switch (key.*) {
        .taxpayer_fact => |value| .{ .taxpayer_fact = .{
            .role = value.role,
            .key = std.meta.stringToEnum(
                store_module.DraftProvenanceTaxpayerFactKey,
                @tagName(value.key),
            ).?,
        } },
        .taxpayer_year_setting => |value| .{ .taxpayer_year_setting = .{
            .role = value.role,
            .key = std.meta.stringToEnum(
                store_module.DraftProvenanceTaxpayerYearSettingKey,
                @tagName(value.key),
            ).?,
        } },
        .tax_form_profile_value => |*value| .{ .tax_form_profile_value = .{
            .role = value.role,
            .key = value.key,
        } },
        .business_activity_fact => |*value| .{
            .business_activity_fact = .{
                .role = value.role,
                .anchor_id = value.anchor_id.asSlice(),
                .key = std.meta.stringToEnum(
                    store_module.DraftProvenanceActivityFactKey,
                    @tagName(value.key),
                ).?,
            },
        },
        .registration_obligation_fact => |*value| .{
            .registration_obligation_fact = .{
                .role = value.role,
                .anchor_id = value.anchor_id.asSlice(),
                .key = std.meta.stringToEnum(
                    store_module.DraftProvenanceObligationFactKey,
                    @tagName(value.key),
                ).?,
            },
        },
    };
}

fn draftProvenanceValueToWrite(
    value: *const draft_provenance.SnapshotValue,
) store_module.DraftProvenanceValueWrite {
    return switch (value.*) {
        .text => |*text| .{ .text = text.asSlice() },
        .choice => |*choice| .{ .choice = choice.asSlice() },
        .boolean => |boolean| .{ .boolean = boolean },
        .integer => |integer| .{ .integer = integer },
        .date => |date| blk: {
            var serialized: store_module.DateText = undefined;
            _ = date.writeIso(&serialized);
            break :blk .{ .date = serialized };
        },
        .year => |year| .{ .year = year },
        .profile_id => |*id| .{ .profile_id = id.asSlice() },
        .business_activity_anchor_id => |*id| .{
            .business_activity_anchor_id = id.asSlice(),
        },
        .registration_obligation_anchor_id => |*id| .{
            .registration_obligation_anchor_id = id.asSlice(),
        },
        .income_tax_rate_election => |election| .{
            .income_tax_rate_election = switch (election) {
                .graduated => .graduated,
                .eight_percent => .eight_percent,
            },
        },
        .deduction_method => |deduction| .{
            .deduction_method = switch (deduction) {
                .itemized_deduction => .itemized_deduction,
                .optional_standard_deduction => .optional_standard_deduction,
            },
        },
    };
}

fn draftProvenanceFromOwned(
    raw: *const store_module.OwnedDraftProvenance,
) !draft_provenance.DraftProvenance {
    if (raw.taxpayer_revisions.len > draft_provenance.max_taxpayer_roles or
        raw.components.len > draft_provenance.max_component_bindings or
        raw.source_snapshots.len > draft_provenance.max_source_snapshots or
        raw.transaction_seeds.len > draft_provenance.max_transaction_seeds)
    {
        return error.InvalidDraftProvenance;
    }
    const identity: draft_provenance.FilingIdentity = .{
        .owner_profile_id = try model.ProfileId.parse(raw.owner_profile_id),
        .tax_year = raw.tax_year,
        .form_code = try annual_profile.FormCode.parse(raw.form_code),
        .form_revision = try annual_profile.FormRevision.parse(
            raw.form_revision,
        ),
        .catalog = .{
            .revision = try draft_provenance.CatalogRevision.parse(
                raw.catalog_revision,
            ),
            .sha256 = try draft_provenance.Sha256.parse(raw.catalog_sha256),
        },
        .setup_spec_revision = raw.setup_spec_revision,
        .setup_spec_hash = try draft_provenance.Sha256.parse(
            raw.setup_spec_hash,
        ),
    };

    var taxpayer_revisions: [draft_provenance.max_taxpayer_roles]draft_provenance.TaxpayerRevisionBinding =
        undefined;
    for (raw.taxpayer_revisions, 0..) |binding, index| {
        taxpayer_revisions[index] = .{
            .role = binding.role,
            .profile_id = try model.ProfileId.parse(binding.profile_id),
            .revision_id = try model.RevisionId.parse(binding.revision_id),
            .revision_sequence = binding.revision_sequence,
        };
    }
    var components: [draft_provenance.max_component_bindings]draft_provenance.ComponentBinding =
        undefined;
    for (raw.components, 0..) |component, index| {
        components[index] = switch (component.kind) {
            .business_activity => .{ .business_activity = .{
                .role = component.role,
                .anchor = .{
                    .owner_profile_id = try model.ProfileId.parse(
                        component.profile_id,
                    ),
                    .id = try registration.ActivityAnchorId.parse(
                        component.anchor_id,
                    ),
                },
                .component_revision_id = try registration.ComponentRevisionId.parse(
                    component.revision_id,
                ),
                .component_revision_sequence = component.revision_sequence,
            } },
            .registration_obligation => .{ .registration_obligation = .{
                .role = component.role,
                .anchor = .{
                    .owner_profile_id = try model.ProfileId.parse(
                        component.profile_id,
                    ),
                    .id = try registration.ObligationAnchorId.parse(
                        component.anchor_id,
                    ),
                },
                .component_revision_id = try registration.ComponentRevisionId.parse(
                    component.revision_id,
                ),
                .component_revision_sequence = component.revision_sequence,
            } },
            else => return error.InvalidDraftProvenance,
        };
    }
    var sources: [draft_provenance.max_source_snapshots]draft_provenance.SourceSnapshot =
        undefined;
    for (raw.source_snapshots, 0..) |*source, index| {
        sources[index] = .{
            .key = try draftProvenanceSourceKeyFromOwned(&source.key),
            .copied_value = try draftProvenanceValueFromOwned(
                &source.copied_value,
            ),
        };
    }
    var seeds: [draft_provenance.max_transaction_seeds]draft_provenance.TransactionDefaultSeed =
        undefined;
    for (raw.transaction_seeds, 0..) |*seed, index| {
        seeds[index] = .{
            .filing_field = try draft_provenance.DraftFieldKey.parse(
                seed.filing_field,
            ),
            .source_key = try draftProvenanceSourceKeyFromOwned(
                &seed.source_key,
            ),
            .source = switch (seed.source) {
                .tax_form_profile_revision => |revision_id| .{
                    .tax_form_profile_revision = try annual_profile.RevisionId.parse(
                        revision_id,
                    ),
                },
                .catalog_default => |catalog| .{ .catalog_default = .{
                    .revision = try draft_provenance.CatalogRevision.parse(
                        catalog.revision,
                    ),
                    .sha256 = try draft_provenance.Sha256.parse(
                        catalog.sha256,
                    ),
                } },
            },
            .copied_seed_value = try draftProvenanceValueFromOwned(
                &seed.copied_seed_value,
            ),
        };
    }

    const taxpayer_year_revision: ?draft_provenance.TaxpayerYearRevisionBinding =
        if (raw.taxpayer_year_revision) |binding| .{
            .stream = .{
                .profile_id = try model.ProfileId.parse(binding.profile_id),
                .tax_year = binding.tax_year,
            },
            .revision_id = try year_settings.RevisionId.parse(
                binding.revision_id,
            ),
            .revision_sequence = binding.revision_sequence,
        } else null;
    const tax_form_profile_revision: ?draft_provenance.TaxFormProfileRevisionBinding =
        if (raw.tax_form_profile_revision) |binding| .{
            .stream = .{
                .profile_id = try model.ProfileId.parse(binding.profile_id),
                .tax_year = binding.tax_year,
                .form_code = try annual_profile.FormCode.parse(
                    binding.form_code,
                ),
                .form_revision = try annual_profile.FormRevision.parse(
                    binding.form_revision,
                ),
            },
            .revision_id = try annual_profile.RevisionId.parse(
                binding.revision_id,
            ),
            .revision_sequence = binding.revision_sequence,
            .spec_revision = binding.spec_revision,
            .spec_hash = try annual_profile.SpecHash.parse(binding.spec_hash),
        } else null;
    const input: draft_provenance.CaptureInput = .{
        .identity = identity,
        .taxpayer_revisions = taxpayer_revisions[0..raw.taxpayer_revisions.len],
        .taxpayer_year_revision = taxpayer_year_revision,
        .tax_form_profile_revision = tax_form_profile_revision,
        .components = components[0..raw.components.len],
        .source_snapshots = sources[0..raw.source_snapshots.len],
        .transaction_seeds = seeds[0..raw.transaction_seeds.len],
    };
    const definition = form_catalog.findForm(raw.form_code) orelse
        return error.UnsupportedFormRevision;
    return draft_provenance.DraftProvenance.capture(&input, definition);
}

fn draftProvenanceSourceKeyFromOwned(
    key: *const store_module.OwnedDraftProvenanceSourceKey,
) !draft_provenance.SourceKey {
    return switch (key.*) {
        .taxpayer_fact => |value| .{ .taxpayer_fact = .{
            .role = value.role,
            .key = std.meta.stringToEnum(
                draft_provenance.TaxpayerFactKey,
                @tagName(value.key),
            ) orelse return error.InvalidDraftProvenance,
        } },
        .taxpayer_year_setting => |value| .{ .taxpayer_year_setting = .{
            .role = value.role,
            .key = std.meta.stringToEnum(
                year_settings.SettingKey,
                @tagName(value.key),
            ) orelse return error.InvalidDraftProvenance,
        } },
        .tax_form_profile_value => |value| .{ .tax_form_profile_value = .{
            .role = value.role,
            .key = value.key,
        } },
        .business_activity_fact => |value| .{
            .business_activity_fact = .{
                .role = value.role,
                .anchor_id = try registration.ActivityAnchorId.parse(
                    value.anchor_id,
                ),
                .key = std.meta.stringToEnum(
                    draft_provenance.ActivityFactKey,
                    @tagName(value.key),
                ) orelse return error.InvalidDraftProvenance,
            },
        },
        .registration_obligation_fact => |value| .{
            .registration_obligation_fact = .{
                .role = value.role,
                .anchor_id = try registration.ObligationAnchorId.parse(
                    value.anchor_id,
                ),
                .key = std.meta.stringToEnum(
                    draft_provenance.ObligationFactKey,
                    @tagName(value.key),
                ) orelse return error.InvalidDraftProvenance,
            },
        },
    };
}

fn draftProvenanceValueFromOwned(
    value: *const store_module.OwnedDraftProvenanceValue,
) !draft_provenance.SnapshotValue {
    return switch (value.*) {
        .text => |text| .{ .text = try draft_provenance.OwnedText.copy(text) },
        .choice => |choice| .{
            .choice = try draft_provenance.OwnedText.copy(choice),
        },
        .boolean => |boolean| .{ .boolean = boolean },
        .integer => |integer| .{ .integer = integer },
        .date => |date| .{ .date = try model.Date.parseIso(date) },
        .year => |year| .{ .year = year },
        .profile_id => |id| .{ .profile_id = try model.ProfileId.parse(id) },
        .business_activity_anchor_id => |id| .{
            .business_activity_anchor_id = try registration.ActivityAnchorId.parse(
                id,
            ),
        },
        .registration_obligation_anchor_id => |id| .{
            .registration_obligation_anchor_id = try registration.ObligationAnchorId.parse(
                id,
            ),
        },
        .income_tax_rate_election => |election| .{
            .income_tax_rate_election = switch (election) {
                .graduated => .graduated,
                .eight_percent => .eight_percent,
            },
        },
        .deduction_method => |deduction| .{
            .deduction_method = switch (deduction) {
                .itemized_deduction => .itemized_deduction,
                .optional_standard_deduction => .optional_standard_deduction,
            },
        },
    };
}

fn formsSetDecisionFromOwned(
    row: *const store_module.OwnedFormSetDecision,
) !forms_set_history.Decision {
    const from = try model.Date.parseIso(row.effective_from);
    const until = if (row.effective_until) |date|
        try model.Date.parseIso(date)
    else
        null;
    return .{
        .id = try forms_set_history.DecisionId.parse(row.id),
        .sequence = row.sequence,
        .stream = .{
            .profile_id = try model.ProfileId.parse(row.profile_id),
            .tax_year = row.tax_year,
            .form = .{
                .code = row.form_code,
                .revision = row.form_revision,
            },
        },
        .state = switch (row.state) {
            .active => .active,
            .inactive => .inactive,
        },
        .scope = switch (row.scope) {
            .whole_year => .whole_year,
            .interval => .interval,
        },
        .effective = try model.EffectivePeriod.init(from, until),
        .source = switch (row.source) {
            .manual => .manual,
            .imported => .imported,
            .cor => .cor,
        },
        .evidence_reference = row.evidence_reference,
        .review = switch (row.review_state) {
            .confirmed => .confirmed,
            .review_required => .review_required,
            .rejected => .rejected,
        },
        .supersedes = if (row.supersedes_id) |id|
            try forms_set_history.DecisionId.parse(id)
        else
            null,
    };
}

test "v17 draft provenance adapter resumes exact capture after later profile edits" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    const profile_id = "v17-adapter-profile";
    const revision_id = "v17-adapter-revision-1";
    const first_revision = try testRevision(.{
        .profile_id = profile_id,
        .revision_id = revision_id,
        .name = "Captured Taxpayer",
        .tin = "123456789000",
    });
    try persistTestRevision(&store, &first_revision);
    try store.createFormSet(profile_id, 2026, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});

    var decisions = try store.listFormSetDecisions(
        allocator,
        profile_id,
        2026,
        "2551Q",
        "2018-01-ENCS",
    );
    defer decisions.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), decisions.items.len);
    const decision = try formsSetDecisionFromOwned(&decisions.items[0]);

    const draft_id = try ids.DraftId.parse("v17-adapter-draft");
    try store.createDraft(
        .{
            .id = draft_id.asSlice(),
            .form_code = "2551Q",
            .form_revision = "2018-01-ENCS",
            .period_key = "2026-Q1",
            .profile_as_of = "2026-03-31".*,
            .mapping_revision = mapping_revision_v1,
        },
        &.{.{
            .role = "filer",
            .profile_id = profile_id,
            .profile_revision_id = revision_id,
            .profile_revision_sequence = 1,
        }},
        &.{},
        &.{},
    );

    const definition = form_catalog.findForm("2551Q").?;
    const exact_bytes = [_]u8{ 'A', 0, 'B', 0xff };
    const taxpayer_bindings = [_]draft_provenance.TaxpayerRevisionBinding{.{
        .role = .filer,
        .profile_id = first_revision.profile_id,
        .revision_id = first_revision.id,
        .revision_sequence = first_revision.sequence,
    }};
    const source_snapshots = [_]draft_provenance.SourceSnapshot{.{
        .key = .{ .taxpayer_fact = .{
            .role = .filer,
            .key = .taxpayer_name,
        } },
        .copied_value = .{
            .text = try draft_provenance.OwnedText.copy(&exact_bytes),
        },
    }};
    const identity: draft_provenance.FilingIdentity = .{
        .owner_profile_id = first_revision.profile_id,
        .tax_year = 2026,
        .form_code = try annual_profile.FormCode.parse(definition.code),
        .form_revision = try annual_profile.FormRevision.parse(
            definition.revision.?,
        ),
        .catalog = .{
            .revision = try draft_provenance.CatalogRevision.parse(
                "catalog/v17-adapter-test",
            ),
            .sha256 = try draft_provenance.Sha256.parse(
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
        },
        .setup_spec_revision = definition.tax_form_profile.spec_revision.?,
        .setup_spec_hash = try draft_provenance.Sha256.parse(
            definition.tax_form_profile.spec_hash.?,
        ),
    };
    const capture_input: draft_provenance.CaptureInput = .{
        .identity = identity,
        .taxpayer_revisions = &taxpayer_bindings,
        .source_snapshots = &source_snapshots,
    };
    const captured = try draft_provenance.DraftProvenance.capture(
        &capture_input,
        definition,
    );
    const applicability_date = try model.Date.parseIso("2026-03-31");
    try std.testing.expectEqual(
        @as(u32, 1),
        try appendDraftProvenance(
            &store,
            draft_id,
            0,
            applicability_date,
            &decision,
            &captured,
        ),
    );
    var raw_loaded = try store.getDraftProvenance(
        allocator,
        draft_id.asSlice(),
    );
    defer raw_loaded.deinit(allocator);
    try std.testing.expectEqualSlices(
        u8,
        &exact_bytes,
        raw_loaded.exact.source_snapshots[0].copied_value.text,
    );

    const later_revision = try testRevision(.{
        .profile_id = profile_id,
        .revision_id = "v17-adapter-revision-2",
        .sequence = 2,
        .name = "Later Taxpayer Name",
        .tin = "123456789000",
        .effective_from = "2026-04-01",
    });
    try persistTestRevision(&store, &later_revision);

    var loaded = try loadDraftProvenance(&store, allocator, draft_id);
    defer loaded.deinit(allocator);
    switch (loaded) {
        .provenance_legacy_absent => return error.TestExpectedEqual,
        .corrupt => return error.TestExpectedEqual,
        .exact => |*exact| {
            try std.testing.expectEqual(
                @as(u32, 1),
                exact.provenance_snapshot.taxpayerRevisions()[0].revision_sequence,
            );
            try std.testing.expectEqualStrings(
                revision_id,
                exact.provenance_snapshot.taxpayerRevisions()[0].revision_id.asSlice(),
            );
            try std.testing.expectEqualSlices(
                u8,
                &exact_bytes,
                exact.provenance_snapshot.sourceSnapshots()[0].copied_value.text.asSlice(),
            );
            try std.testing.expect(
                exact.forms_set_decision.id.eql(&decision.id),
            );
            try std.testing.expect(
                exact.applicability_date.eql(applicability_date),
            );
        },
    }

    try std.testing.expectError(
        error.DraftProvenanceConflict,
        appendDraftProvenance(
            &store,
            draft_id,
            0,
            applicability_date,
            &decision,
            &captured,
        ),
    );

    const legacy_id = try ids.DraftId.parse("v17-adapter-legacy-draft");
    try store.createDraft(
        .{
            .id = legacy_id.asSlice(),
            .form_code = "2551Q",
            .form_revision = "2018-01-ENCS",
            .period_key = "2026-Q2",
            .profile_as_of = "2026-06-30".*,
            .mapping_revision = mapping_revision_v1,
        },
        &.{.{
            .role = "filer",
            .profile_id = profile_id,
            .profile_revision_id = later_revision.id.asSlice(),
            .profile_revision_sequence = later_revision.sequence,
        }},
        &.{},
        &.{},
    );
    var legacy = try loadDraftProvenance(&store, allocator, legacy_id);
    defer legacy.deinit(allocator);
    try std.testing.expect(legacy == .provenance_legacy_absent);
}

test "canonical period keys and deterministic original IDs are exact" {
    const base = runtime.RecurringQuarter{
        .form = ids.FormRevision.initComptime("2551Q", "2018-01-ENCS"),
        .tax_year = 2026,
        .quarter = 1,
    };
    var period_buffer: [canonical_period_key_len]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2026-Q1",
        try canonicalPeriodKey(base, &period_buffer),
    );

    const filer = try model.ProfileId.parse("profile-filer");
    const same = try originalDraftId(filer, base);
    const same_again = try originalDraftId(filer, base);
    try std.testing.expectEqual(@as(usize, 64), same.asSlice().len);
    try std.testing.expectEqualStrings(
        same.asSlice(),
        same_again.asSlice(),
    );

    var other_quarter = base;
    other_quarter.quarter = 2;
    const quarter_id = try originalDraftId(filer, other_quarter);
    try std.testing.expect(!same.eql(&quarter_id));

    var other_form = base;
    other_form.form =
        ids.FormRevision.initComptime("1701Q", "2018-01-ENCS");
    const form_id = try originalDraftId(filer, other_form);
    try std.testing.expect(!same.eql(&form_id));

    const other_profile = try originalDraftId(
        try model.ProfileId.parse("profile-other"),
        base,
    );
    try std.testing.expect(!same.eql(&other_profile));
}

test "all reusable values have canonical non-default serialization" {
    const values = [_]field.Value{
        .{ .tin = try field.Tin.parse("123456789000") },
        .{ .rdo_code = try field.RdoCode.parse("019") },
        .{ .taxpayer_name = try field.TaxpayerName.parse("JUAN DELA CRUZ") },
        .{ .registered_name = try field.RegisteredName.parse("JUAN STORE") },
        .{ .registered_address = try field.RegisteredAddress.parse(
            "1 Taxpayer Street",
        ) },
        .{ .zip_code = try field.ZipCode.parse("1000") },
        .{ .contact_number = try field.ContactNumber.parse(
            "+63 (917) 123-4567",
        ) },
        .{ .email_address = try field.EmailAddress.parse(
            "taxpayer@example.ph",
        ) },
        .{ .date_of_birth = try model.Date.parseIso("1995-06-01") },
        .{ .citizenship = try field.Citizenship.parse("Filipino") },
        .{ .foreign_tax_number = try field.ForeignTaxNumber.parse("FTN-1") },
        .{ .line_of_business = try field.LineOfBusiness.parse("Retail") },
        .{ .atc = try field.Atc.parse("PT 010") },
        .{ .tax_type = try field.TaxType.parse("Percentage Tax") },
        .{ .government_withholding_agent = .yes },
        .{ .special_rate_basis = try field.SpecialRateBasis.parse(
            "Treaty Article 7",
        ) },
    };
    const expected = [_][]const u8{
        "123456789000",
        "019",
        "JUAN DELA CRUZ",
        "JUAN STORE",
        "1 Taxpayer Street",
        "1000",
        "+639171234567",
        "taxpayer@example.ph",
        "1995-06-01",
        "Filipino",
        "FTN-1",
        "Retail",
        "PT010",
        "Percentage Tax",
        "yes",
        "Treaty Article 7",
    };
    for (&values, expected) |*value, expected_text| {
        var buffer: [max_serialized_value_len]u8 = undefined;
        const serialized = profile_persistence.serializeValue(value, &buffer);
        const parsed = try profile_persistence.parseValue(
            value.field(),
            serialized.value_type,
            serialized.text,
        );
        try std.testing.expect(serialized.value_type.len != 0);
        try std.testing.expectEqualStrings(expected_text, serialized.text);
        try std.testing.expect(value.eql(&parsed));
    }
}

const TestRevisionOptions = struct {
    profile_id: []const u8,
    revision_id: []const u8,
    sequence: u32 = 1,
    name: []const u8,
    tin: []const u8,
    effective_from: []const u8 = "2026-01-01",
    source: model.RevisionSource = .manual_entry,
    business_activities: []const model.BusinessActivity = &.{},
    registration_facts: []const model.RegistrationFact = &.{},
};

fn testRevision(options: TestRevisionOptions) !model.ProfileRevision {
    return .{
        .profile_id = try model.ProfileId.parse(options.profile_id),
        .id = try model.RevisionId.parse(options.revision_id),
        .sequence = options.sequence,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso(options.effective_from),
            null,
        ),
        .source = options.source,
        .identity = .{
            .tin = try field.Tin.parse(options.tin),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse(
                "1 Taxpayer Street",
            ),
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse(
                "taxpayer@example.ph",
            ),
        },
        .subject = .{ .individual = .{
            .name = try field.TaxpayerName.parse(options.name),
            .date_of_birth = try model.Date.parseIso("1995-06-01"),
            .citizenship = try field.Citizenship.parse("Filipino"),
        } },
        .business_activities = options.business_activities,
        .registration_facts = options.registration_facts,
    };
}

fn persistencePeriod(
    value: model.EffectivePeriod,
) store_module.EffectivePeriodWrite {
    var from: store_module.DateText = undefined;
    _ = value.from.writeIso(&from);
    var until: ?store_module.DateText = null;
    if (value.until) |last| {
        var text: store_module.DateText = undefined;
        _ = last.writeIso(&text);
        until = text;
    }
    return .{ .from = from, .until = until };
}

fn persistenceSubject(
    value: *const model.Subject,
) store_module.SubjectWrite {
    return switch (value.*) {
        .individual => |*person| .{ .individual = .{
            .name = person.name.asSlice(),
            .date_of_birth = if (person.date_of_birth) |date| blk: {
                var text: store_module.DateText = undefined;
                _ = date.writeIso(&text);
                break :blk text;
            } else null,
            .citizenship = if (person.citizenship) |*item|
                item.asSlice()
            else
                null,
            .foreign_tax_number = if (person.foreign_tax_number) |*item|
                item.asSlice()
            else
                null,
        } },
        .sole_proprietor => |*proprietor| .{ .sole_proprietor = .{
            .person = .{
                .name = proprietor.person.name.asSlice(),
                .date_of_birth = if (proprietor.person.date_of_birth) |date| blk: {
                    var text: store_module.DateText = undefined;
                    _ = date.writeIso(&text);
                    break :blk text;
                } else null,
                .citizenship = if (proprietor.person.citizenship) |*item|
                    item.asSlice()
                else
                    null,
                .foreign_tax_number = if (proprietor.person.foreign_tax_number) |*item|
                    item.asSlice()
                else
                    null,
            },
            .trade_name = if (proprietor.trade_name) |*item|
                item.asSlice()
            else
                null,
        } },
        .legal_entity => |*entity| .{ .legal_entity = .{
            .registered_name = entity.registered_name.asSlice(),
            .kind = switch (entity.kind) {
                .corporation => .corporation,
                .partnership => .partnership,
                .cooperative => .cooperative,
                .estate => .estate,
                .trust => .trust,
                .other => .other,
            },
        } },
    };
}

fn persistTestRevision(
    store: *store_module.Store,
    revision: *const model.ProfileRevision,
) !void {
    var tin_buffer: [24]u8 = undefined;
    const tin = try revision.identity.tin.write(&tin_buffer);

    var activity_writes: [projection.max_snapshot_entries]store_module.BusinessActivityWrite =
        undefined;
    for (revision.business_activities, 0..) |*activity, index| {
        activity_writes[index] = .{
            .id = activity.id.asSlice(),
            .line_of_business = activity.line_of_business.asSlice(),
            .atc = if (activity.atc) |*atc| atc.asSlice() else null,
            .effective = persistencePeriod(activity.effective),
            .ordinal = @intCast(index),
        };
    }

    var fact_writes: [projection.max_snapshot_entries]store_module.RegistrationFactWrite =
        undefined;
    for (revision.registration_facts, 0..) |*fact, index| {
        fact_writes[index] = .{
            .id = fact.id.asSlice(),
            .effective = persistencePeriod(fact.effective),
            .value = switch (fact.value) {
                .tax_type => |*item| .{
                    .tax_type = item.asSlice(),
                },
                .government_withholding_agent => |item| .{
                    .government_withholding_agent = switch (item) {
                        .no => .no,
                        .yes => .yes,
                    },
                },
                .special_rate_basis => |*item| .{
                    .special_rate_basis = item.asSlice(),
                },
            },
            .ordinal = @intCast(index),
        };
    }

    const write: store_module.RevisionWrite = .{
        .id = revision.id.asSlice(),
        .profile_id = revision.profile_id.asSlice(),
        .sequence = revision.sequence,
        .expected_current_sequence = if (revision.sequence == 1)
            0
        else
            revision.sequence - 1,
        .effective = persistencePeriod(revision.effective),
        .source = revisionSourceWrite(&revision.source),
        .identity = .{
            .tin = tin,
            .rdo_code = revision.identity.rdo_code.asSlice(),
        },
        .contact = .{
            .registered_address = revision.contact.address.asSlice(),
            .zip_code = if (revision.contact.zip_code) |*item|
                item.asSlice()
            else
                null,
            .contact_number = if (revision.contact.contact_number) |*item|
                item.asSlice()
            else
                null,
            .email_address = if (revision.contact.email_address) |*item|
                item.asSlice()
            else
                null,
        },
        .subject = persistenceSubject(&revision.subject),
    };
    const components: store_module.RevisionComponentsWrite = .{
        .business_activities = activity_writes[0..revision.business_activities.len],
        .registration_facts = fact_writes[0..revision.registration_facts.len],
    };

    if (revision.sequence == 1) {
        try store.createProfileWithRevision(
            .{ .id = revision.profile_id.asSlice() },
            write,
            components,
        );
    } else {
        try store.appendRevision(write, components);
    }
}

const TestComposition = struct {
    period: runtime.RecurringQuarter,
    bindings: runtime.RoleBindings,
    snapshot: projection.Snapshot,
};

fn compose2551Q(
    filer: *const model.ProfileRevision,
    on: model.Date,
    year: u16,
    quarter: u8,
) !TestComposition {
    const source = [_]projection.Binding{
        .{ .role = .filer, .revision = filer },
    };
    const result = try form_2551q.composeProfiles(&source, on);
    return .{
        .period = runtime.RecurringQuarter.for2551Q(
            try field.Quarter.init(year, quarter),
        ),
        .bindings = try runtime.RoleBindings.from(&source),
        .snapshot = switch (result) {
            .accepted => |snapshot| snapshot,
            .rejected => return error.UnexpectedCompositionRejection,
        },
    };
}

fn compose1701Q(
    filer: *const model.ProfileRevision,
    spouse: ?*const model.ProfileRevision,
    on: model.Date,
    year: u16,
    quarter: u8,
) !TestComposition {
    var source: [2]projection.Binding = undefined;
    source[0] = .{ .role = .filer, .revision = filer };
    var len: usize = 1;
    if (spouse) |value| {
        source[1] = .{ .role = .spouse, .revision = value };
        len = 2;
    }
    const bindings = source[0..len];
    const result = try form_1701q.composeProfiles(bindings, on);
    return .{
        .period = runtime.RecurringQuarter.for1701Q(
            try form_1701q.FilingQuarter.init(year, quarter),
        ),
        .bindings = try runtime.RoleBindings.from(bindings),
        .snapshot = switch (result) {
            .accepted => |snapshot| snapshot,
            .rejected => return error.UnexpectedCompositionRejection,
        },
    };
}

const CatalogComposition = struct {
    form: ids.FormRevision,
    legacy_period: runtime.RecurringQuarter,
    filing_period: filing_period.FilingPeriod,
    bindings: runtime.RoleBindings,
    snapshot: projection.Snapshot,
};

fn composeCatalogForm(
    allocator: std.mem.Allocator,
    filer: *const model.ProfileRevision,
    code: []const u8,
    revision: []const u8,
    period: filing_period.FilingPeriod,
    effective_on: model.Date,
) !CatalogComposition {
    const form: ids.FormRevision = .{
        .code = try ids.FormCode.parse(code),
        .revision = try ids.RevisionLabel.parse(revision),
    };
    const source = [_]projection.Binding{
        .{ .role = .filer, .revision = filer },
    };
    var result = try catalog_projection.project(
        allocator,
        form,
        &source,
        effective_on,
    );
    defer result.deinit(allocator);

    var snapshot = projection.Snapshot.init(form, effective_on);
    switch (result) {
        .accepted => |accepted| {
            for (accepted.slice()) |entry| try snapshot.append(entry);
        },
        .rejected => return error.UnexpectedCompositionRejection,
    }
    return .{
        .form = form,
        .legacy_period = .{
            .form = form,
            .tax_year = period.taxYear(),
            .quarter = period.quarter() orelse 1,
        },
        .filing_period = period,
        .bindings = try runtime.RoleBindings.from(&source),
        .snapshot = snapshot,
    };
}

fn snapshotByField(
    draft: *const store_module.OwnedDraft,
    field_id: []const u8,
) ?*const store_module.OwnedSnapshotField {
    for (draft.snapshots) |*snapshot| {
        if (std.mem.eql(u8, snapshot.field_id, field_id)) return snapshot;
    }
    return null;
}

fn bindingByRole(
    draft: *const store_module.OwnedDraft,
    role: []const u8,
) ?*const store_module.OwnedRoleBinding {
    for (draft.bindings) |*binding| {
        if (std.mem.eql(u8, binding.role, role)) return binding;
    }
    return null;
}

test "2551Q exact seven-field snapshot and transaction values roundtrip" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    var revision = try testRevision(.{
        .profile_id = "profile-2551q-filer",
        .revision_id = "revision-1",
        .name = "JUAN DELA CRUZ",
        .tin = "123-456-789-000",
        .source = .{ .imported = try field.SourceReference.parse(
            "COR 2026-001",
        ) },
    });
    try persistTestRevision(&store, &revision);

    const on = try model.Date.parseIso("2026-03-31");
    var composition = try compose2551Q(&revision, on, 2026, 1);
    const values = [_]store_module.DraftValueWrite{.{
        .field_id = "2551Q.schedule.0.atc",
        .value_text = "PT010",
    }};
    var opened = try createOrLoad(allocator, &store, .{
        .period = composition.period,
        .role_bindings = &composition.bindings,
        .snapshot = &composition.snapshot,
        .transaction_values = &values,
    });
    defer opened.deinit(allocator);

    try std.testing.expectEqual(
        OpenDisposition.created,
        opened.disposition,
    );
    try std.testing.expectEqual(@as(usize, 7), opened.draft.snapshots.len);
    try std.testing.expectEqual(@as(usize, 1), opened.draft.values.len);
    try std.testing.expectEqualStrings(
        "PT010",
        opened.draft.values[0].value_text,
    );
    try std.testing.expectEqualStrings(
        "2026-03-31",
        opened.draft.profile_as_of,
    );
    for (opened.draft.snapshots) |*snapshot| {
        try std.testing.expectEqualStrings("filer", snapshot.role);
        try std.testing.expect(!std.mem.eql(
            u8,
            snapshot.reusable_field,
            "atc",
        ));
        try std.testing.expectEqualStrings(
            "COR 2026-001",
            snapshot.revision_source.imported,
        );
    }
    const tin = snapshotByField(
        &opened.draft,
        "2551Q.2018-01-ENCS.input.tin",
    ).?;
    try std.testing.expectEqualStrings("123456789000", tin.value_text);
    try std.testing.expectEqualStrings("tin", tin.reusable_field);
    const typed = try rehydrate(&opened.draft);
    try std.testing.expectEqual(@as(u8, 7), typed.snapshot.len);
    try std.testing.expectEqual(@as(u8, 1), typed.role_bindings.len);
    try std.testing.expectEqualStrings(
        "123456789000",
        typed.snapshot.get(
            ids.FieldId.initComptime("2551Q.2018-01-ENCS.input.tin"),
        ).?.value.tin.asDigits(),
    );

    var resumed = try createOrLoad(allocator, &store, .{
        .period = composition.period,
        .role_bindings = &composition.bindings,
        .snapshot = &composition.snapshot,
        .mapping_revision = "new-mapping-must-not-refresh",
        .transaction_values = &.{.{
            .field_id = "2551Q.schedule.0.atc",
            .value_text = "PT999",
        }},
    });
    defer resumed.deinit(allocator);
    try std.testing.expectEqual(
        OpenDisposition.resumed,
        resumed.disposition,
    );
    try std.testing.expectEqualStrings(
        mapping_revision_v1,
        resumed.draft.mapping_revision,
    );
    try std.testing.expectEqualStrings(
        "PT010",
        resumed.draft.values[0].value_text,
    );
}

test "1701Q named filer and spouse bindings roundtrip independently" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    var filer = try testRevision(.{
        .profile_id = "profile-1701q-filer",
        .revision_id = "revision-filer-1",
        .name = "JUAN DELA CRUZ",
        .tin = "123-456-789-000",
    });
    var spouse = try testRevision(.{
        .profile_id = "profile-1701q-spouse",
        .revision_id = "revision-spouse-1",
        .name = "ANA DELA CRUZ",
        .tin = "987-654-321-000",
    });
    try persistTestRevision(&store, &filer);
    try persistTestRevision(&store, &spouse);

    var composition = try compose1701Q(
        &filer,
        &spouse,
        try model.Date.parseIso("2026-03-31"),
        2026,
        1,
    );
    var opened = try createOrLoad(allocator, &store, .{
        .period = composition.period,
        .role_bindings = &composition.bindings,
        .snapshot = &composition.snapshot,
        .transaction_values = &.{.{
            .field_id = "1701Q.computation.tax_payable",
            .value_text = "500000",
        }},
    });
    defer opened.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), opened.draft.bindings.len);
    try std.testing.expectEqual(@as(usize, 12), opened.draft.snapshots.len);
    try std.testing.expectEqualStrings(
        "profile-1701q-filer",
        bindingByRole(&opened.draft, "filer").?.profile_id,
    );
    try std.testing.expectEqualStrings(
        "profile-1701q-spouse",
        bindingByRole(&opened.draft, "spouse").?.profile_id,
    );
    const filer_name = snapshotByField(
        &opened.draft,
        "1701Q.2018-01-ENCS.input.taxpayer_filer_name",
    ).?;
    const spouse_name = snapshotByField(
        &opened.draft,
        "1701Q.2018-01-ENCS.input.spouse_name",
    ).?;
    try std.testing.expectEqualStrings("filer", filer_name.role);
    try std.testing.expectEqualStrings("JUAN DELA CRUZ", filer_name.value_text);
    try std.testing.expectEqualStrings("spouse", spouse_name.role);
    try std.testing.expectEqualStrings("ANA DELA CRUZ", spouse_name.value_text);
    const spouse_citizenship = snapshotByField(
        &opened.draft,
        "1701Q.2018-01-ENCS.input.spouse_citizenship",
    ).?;
    try std.testing.expectEqualStrings("spouse", spouse_citizenship.role);
    try std.testing.expectEqualStrings(
        "Filipino",
        spouse_citizenship.value_text,
    );
    try std.testing.expect(snapshotByField(
        &opened.draft,
        "1701Q.2018-01-ENCS.input.spouse_foreign_tax_number",
    ) == null);
    const typed = try rehydrate(&opened.draft);
    try std.testing.expect(typed.role_bindings.get(.filer) != null);
    try std.testing.expect(typed.role_bindings.get(.spouse) != null);
    try std.testing.expectEqual(@as(u8, 12), typed.snapshot.len);
}

test "catalog editor drafts retain monthly annual and on-demand period identity" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    const effective = try model.EffectivePeriod.init(
        try model.Date.parseIso("2026-01-01"),
        null,
    );
    const activities = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("activity-catalog-period"),
        .line_of_business = try field.LineOfBusiness.parse("Retail"),
        .atc = try field.Atc.parse("PT010"),
        .effective = effective,
    }};
    const facts = [_]model.RegistrationFact{
        .{
            .id = try model.RegistrationFactId.parse("fact-catalog-tax-type"),
            .effective = effective,
            .value = .{ .tax_type = try field.TaxType.parse("Percentage Tax") },
        },
        .{
            .id = try model.RegistrationFactId.parse("fact-catalog-gwa"),
            .effective = effective,
            .value = .{ .government_withholding_agent = .yes },
        },
    };
    var filer = try testRevision(.{
        .profile_id = "profile-catalog-period",
        .revision_id = "revision-catalog-period",
        .name = "CATALOG PERIOD FILER",
        .tin = "123-456-789-000",
        .business_activities = &activities,
        .registration_facts = &facts,
    });
    try persistTestRevision(&store, &filer);
    const filer_id = filer.profile_id;
    const on = try model.Date.parseIso("2026-01-31");

    const periods = [_]CatalogComposition{
        try composeCatalogForm(
            allocator,
            &filer,
            "0619E",
            "2018-01-ENCS",
            .{ .monthly = .{ .tax_year = 2026, .month = 1 } },
            on,
        ),
        try composeCatalogForm(
            allocator,
            &filer,
            "1701",
            "2018-01-ENCS",
            .{ .annual = .{ .tax_year = 2026 } },
            try model.Date.parseIso("2026-12-31"),
        ),
        try composeCatalogForm(
            allocator,
            &filer,
            "0605",
            "1999-07-ENCS",
            .{ .on_demand = .{ .tax_year = 2026, .occurrence = 2 } },
            on,
        ),
    };

    const expected_keys = [_][]const u8{ "2026-M01", "2026-A", "2026-O002" };
    for (periods, expected_keys) |composition, expected_key| {
        var opened = try createOrLoad(allocator, &store, .{
            .period = composition.legacy_period,
            .filing_period = composition.filing_period,
            .role_bindings = &composition.bindings,
            .snapshot = &composition.snapshot,
        });
        defer opened.deinit(allocator);
        try std.testing.expectEqual(OpenDisposition.created, opened.disposition);
        try std.testing.expectEqualStrings(expected_key, opened.draft.period_key);
        const typed = try rehydrate(&opened.draft);
        try std.testing.expect(typed.form.eql(&composition.form));
        try std.testing.expect(typed.period.eql(composition.filing_period));
        try std.testing.expect(typed.role_bindings.get(.filer) != null);
        try std.testing.expect(typed.snapshot.len > 0);

        var resumed = try createOrLoad(allocator, &store, .{
            .period = composition.legacy_period,
            .filing_period = composition.filing_period,
            .role_bindings = &composition.bindings,
            .snapshot = &composition.snapshot,
        });
        defer resumed.deinit(allocator);
        try std.testing.expectEqual(OpenDisposition.resumed, resumed.disposition);
        try std.testing.expectEqualStrings(
            filer_id.asSlice(),
            bindingByRole(&resumed.draft, "filer").?.profile_id,
        );
    }
}

test "input role contract rejects extras aliases and missing filer but keeps optional spouse" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    var filer = try testRevision(.{
        .profile_id = "profile-role-contract-filer",
        .revision_id = "revision-role-contract-filer",
        .name = "ROLE CONTRACT FILER",
        .tin = "123-456-789-000",
    });
    var spouse = try testRevision(.{
        .profile_id = "profile-role-contract-spouse",
        .revision_id = "revision-role-contract-spouse",
        .name = "ROLE CONTRACT SPOUSE",
        .tin = "987-654-321-000",
    });
    try persistTestRevision(&store, &filer);
    try persistTestRevision(&store, &spouse);
    const on = try model.Date.parseIso("2026-03-31");

    var percentage = try compose2551Q(&filer, on, 2026, 1);
    var extra = percentage.bindings;
    extra.entries[1] = extra.entries[0];
    extra.entries[1].role = .employer;
    extra.len = 2;
    try std.testing.expectError(
        error.UnexpectedRoleBinding,
        createOrLoad(allocator, &store, .{
            .period = percentage.period,
            .role_bindings = &extra,
            .snapshot = &percentage.snapshot,
        }),
    );

    var missing_filer = percentage.bindings;
    missing_filer.len = 0;
    try std.testing.expectError(
        error.MissingFilerBinding,
        createOrLoad(allocator, &store, .{
            .period = percentage.period,
            .role_bindings = &missing_filer,
            .snapshot = &percentage.snapshot,
        }),
    );

    var invalid_count = percentage.bindings;
    invalid_count.len = runtime.max_role_bindings + 1;
    try std.testing.expectError(
        error.InvalidRoleBindingCount,
        createOrLoad(allocator, &store, .{
            .period = percentage.period,
            .role_bindings = &invalid_count,
            .snapshot = &percentage.snapshot,
        }),
    );

    var unsupported_period = percentage.period;
    unsupported_period.form = ids.FormRevision.initComptime(
        "2551Q",
        "2099-UNSUPPORTED",
    );
    try std.testing.expectError(
        error.UnsupportedFormRevision,
        createOrLoad(allocator, &store, .{
            .period = unsupported_period,
            .role_bindings = &percentage.bindings,
            .snapshot = &percentage.snapshot,
        }),
    );

    var joint = try compose1701Q(&filer, &spouse, on, 2026, 1);
    joint.bindings.entries[1].profile_id =
        joint.bindings.entries[0].profile_id;
    try std.testing.expectError(
        error.RoleProfilesMustBeDistinct,
        createOrLoad(allocator, &store, .{
            .period = joint.period,
            .role_bindings = &joint.bindings,
            .snapshot = &joint.snapshot,
        }),
    );

    var filer_only = try compose1701Q(&filer, null, on, 2026, 1);
    var opened = try createOrLoad(allocator, &store, .{
        .period = filer_only.period,
        .role_bindings = &filer_only.bindings,
        .snapshot = &filer_only.snapshot,
    });
    defer opened.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), opened.draft.bindings.len);
    try std.testing.expect(
        bindingByRole(&opened.draft, "spouse") == null,
    );
}

test "input snapshot contract rejects partial extra duplicate wrong-role type and provenance" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    var filer = try testRevision(.{
        .profile_id = "profile-input-snapshot-contract",
        .revision_id = "revision-input-snapshot-contract",
        .name = "INPUT SNAPSHOT CONTRACT",
        .tin = "123-456-789-000",
    });
    var composition = try compose2551Q(
        &filer,
        try model.Date.parseIso("2026-03-31"),
        2026,
        1,
    );

    var partial = composition.snapshot;
    partial.len -= 1;
    try std.testing.expectError(
        error.MissingRequiredSnapshotField,
        createOrLoad(allocator, &store, .{
            .period = composition.period,
            .role_bindings = &composition.bindings,
            .snapshot = &partial,
        }),
    );

    var extra = composition.snapshot;
    var extra_entry = extra.entries[0];
    extra_entry.target = ids.FieldId.initComptime(
        "2551Q.2018-01-ENCS.input.unexpected_profile_field",
    );
    try extra.append(extra_entry);
    try std.testing.expectError(
        error.UnexpectedSnapshotTarget,
        createOrLoad(allocator, &store, .{
            .period = composition.period,
            .role_bindings = &composition.bindings,
            .snapshot = &extra,
        }),
    );

    var duplicate = composition.snapshot;
    duplicate.entries[duplicate.len] = duplicate.entries[0];
    duplicate.len += 1;
    try std.testing.expectError(
        error.DuplicateSnapshotTarget,
        createOrLoad(allocator, &store, .{
            .period = composition.period,
            .role_bindings = &composition.bindings,
            .snapshot = &duplicate,
        }),
    );

    var wrong_role = composition.snapshot;
    wrong_role.entries[0].role = .spouse;
    try std.testing.expectError(
        error.SnapshotRoleMismatch,
        createOrLoad(allocator, &store, .{
            .period = composition.period,
            .role_bindings = &composition.bindings,
            .snapshot = &wrong_role,
        }),
    );

    var wrong_type = composition.snapshot;
    wrong_type.entries[0].value = wrong_type.entries[1].value;
    try std.testing.expectError(
        error.SnapshotFieldTypeMismatch,
        createOrLoad(allocator, &store, .{
            .period = composition.period,
            .role_bindings = &composition.bindings,
            .snapshot = &wrong_type,
        }),
    );

    var wrong_provenance = composition.snapshot;
    wrong_provenance.entries[0].provenance.profile_id =
        try model.ProfileId.parse("profile-other");
    try std.testing.expectError(
        error.SnapshotProvenanceMismatch,
        createOrLoad(allocator, &store, .{
            .period = composition.period,
            .role_bindings = &composition.bindings,
            .snapshot = &wrong_provenance,
        }),
    );
}

test "rehydrate and resume reject malformed persisted named roles" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    var filer = try testRevision(.{
        .profile_id = "profile-stored-role-filer",
        .revision_id = "revision-stored-role-filer",
        .name = "STORED ROLE FILER",
        .tin = "123-456-789-000",
    });
    var spouse = try testRevision(.{
        .profile_id = "profile-stored-role-spouse",
        .revision_id = "revision-stored-role-spouse",
        .name = "STORED ROLE SPOUSE",
        .tin = "987-654-321-000",
    });
    try persistTestRevision(&store, &filer);
    try persistTestRevision(&store, &spouse);
    var composition = try compose1701Q(
        &filer,
        &spouse,
        try model.Date.parseIso("2026-03-31"),
        2026,
        1,
    );
    const input: OpenInput = .{
        .period = composition.period,
        .role_bindings = &composition.bindings,
        .snapshot = &composition.snapshot,
    };
    var opened = try createOrLoad(allocator, &store, input);
    const draft_id = try allocator.dupe(u8, opened.draft.id);
    defer allocator.free(draft_id);
    opened.deinit(allocator);

    var unexpected = (try store.getDraft(
        allocator,
        draft_id,
    )).?;
    defer unexpected.deinit(allocator);
    allocator.free(unexpected.bindings[1].role);
    unexpected.bindings[1].role = try allocator.dupe(u8, "employer");
    try std.testing.expectError(
        error.UnexpectedRoleBinding,
        rehydrate(&unexpected),
    );

    var aliased = (try store.getDraft(
        allocator,
        draft_id,
    )).?;
    allocator.free(aliased.bindings[1].profile_id);
    aliased.bindings[1].profile_id = try allocator.dupe(
        u8,
        aliased.bindings[0].profile_id,
    );
    try std.testing.expectError(
        error.RoleProfilesMustBeDistinct,
        resumeChecked(
            allocator,
            aliased,
            input,
            try resolveIdentity(input),
        ),
    );
}

test "rehydrate and resume reject partial extra and wrong-type persisted snapshots" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    var filer = try testRevision(.{
        .profile_id = "profile-stored-snapshot-contract",
        .revision_id = "revision-stored-snapshot-contract",
        .name = "STORED SNAPSHOT CONTRACT",
        .tin = "123-456-789-000",
    });
    try persistTestRevision(&store, &filer);
    var composition = try compose2551Q(
        &filer,
        try model.Date.parseIso("2026-03-31"),
        2026,
        1,
    );
    const input: OpenInput = .{
        .period = composition.period,
        .role_bindings = &composition.bindings,
        .snapshot = &composition.snapshot,
    };
    var opened = try createOrLoad(allocator, &store, input);
    const draft_id = try allocator.dupe(u8, opened.draft.id);
    defer allocator.free(draft_id);
    opened.deinit(allocator);

    var partial = (try store.getDraft(
        allocator,
        draft_id,
    )).?;
    defer partial.deinit(allocator);
    const complete_snapshots = partial.snapshots;
    partial.snapshots =
        complete_snapshots[0 .. complete_snapshots.len - 1];
    try std.testing.expectError(
        error.MissingRequiredSnapshotField,
        rehydrate(&partial),
    );
    partial.snapshots = complete_snapshots;

    var wrong_type = (try store.getDraft(
        allocator,
        draft_id,
    )).?;
    defer wrong_type.deinit(allocator);
    std.mem.swap(
        []u8,
        &wrong_type.snapshots[0].reusable_field,
        &wrong_type.snapshots[1].reusable_field,
    );
    std.mem.swap(
        []u8,
        &wrong_type.snapshots[0].value_type,
        &wrong_type.snapshots[1].value_type,
    );
    std.mem.swap(
        []u8,
        &wrong_type.snapshots[0].value_text,
        &wrong_type.snapshots[1].value_text,
    );
    try std.testing.expectError(
        error.SnapshotFieldTypeMismatch,
        rehydrate(&wrong_type),
    );

    var extra = (try store.getDraft(
        allocator,
        draft_id,
    )).?;
    allocator.free(extra.snapshots[0].field_id);
    extra.snapshots[0].field_id = try allocator.dupe(
        u8,
        "2551Q.2018-01-ENCS.input.unexpected_profile_field",
    );
    try std.testing.expectError(
        error.UnexpectedSnapshotTarget,
        resumeChecked(
            allocator,
            extra,
            input,
            try resolveIdentity(input),
        ),
    );
}

test "appending a profile revision cannot refresh a prior original draft" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    var first = try testRevision(.{
        .profile_id = "profile-stable-snapshot",
        .revision_id = "revision-stable-1",
        .name = "ORIGINAL NAME",
        .tin = "123-456-789-000",
    });
    try persistTestRevision(&store, &first);
    const on = try model.Date.parseIso("2026-03-31");
    var original_composition = try compose2551Q(&first, on, 2026, 1);
    var original = try createOrLoad(allocator, &store, .{
        .period = original_composition.period,
        .role_bindings = &original_composition.bindings,
        .snapshot = &original_composition.snapshot,
        .transaction_values = &.{.{
            .field_id = "2551Q.transaction.marker",
            .value_text = "original",
        }},
    });
    const stable_id = try allocator.dupe(u8, original.draft.id);
    defer allocator.free(stable_id);
    original.deinit(allocator);

    var second = try testRevision(.{
        .profile_id = "profile-stable-snapshot",
        .revision_id = "revision-stable-2",
        .sequence = 2,
        .name = "UPDATED NAME",
        .tin = "123-456-789-000",
        .source = .{ .migrated = try field.SourceReference.parse(
            "migration-2",
        ) },
    });
    try persistTestRevision(&store, &second);
    var newer_composition = try compose2551Q(&second, on, 2026, 1);
    var resumed = try createOrLoad(allocator, &store, .{
        .period = newer_composition.period,
        .role_bindings = &newer_composition.bindings,
        .snapshot = &newer_composition.snapshot,
        .transaction_values = &.{.{
            .field_id = "2551Q.transaction.marker",
            .value_text = "replacement",
        }},
    });
    defer resumed.deinit(allocator);

    try std.testing.expectEqual(
        OpenDisposition.resumed,
        resumed.disposition,
    );
    try std.testing.expectEqualStrings(stable_id, resumed.draft.id);
    const name = snapshotByField(
        &resumed.draft,
        "2551Q.2018-01-ENCS.input.taxpayers_name",
    ).?;
    try std.testing.expectEqualStrings("ORIGINAL NAME", name.value_text);
    try std.testing.expectEqualStrings(
        "revision-stable-1",
        name.profile_revision_id,
    );
    try std.testing.expectEqualStrings(
        "original",
        resumed.draft.values[0].value_text,
    );
}

test "profile as-of and revision source provenance roundtrip losslessly" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    var revision = try testRevision(.{
        .profile_id = "profile-provenance",
        .revision_id = "revision-provenance-1",
        .name = "PROVENANCE FILER",
        .tin = "123-456-789-000",
        .source = .{ .imported = try field.SourceReference.parse(
            "COR import batch 42",
        ) },
    });
    try persistTestRevision(&store, &revision);

    const on = try model.Date.parseIso("2026-06-30");
    var composition = try compose2551Q(&revision, on, 2026, 2);
    var opened = try createOrLoad(allocator, &store, .{
        .period = composition.period,
        .role_bindings = &composition.bindings,
        .snapshot = &composition.snapshot,
    });
    defer opened.deinit(allocator);

    try std.testing.expectEqualStrings("2026-06-30", opened.draft.profile_as_of);
    const persisted_binding = bindingByRole(&opened.draft, "filer").?;
    try std.testing.expect(persisted_binding.business_activity_id == null);
    const name = snapshotByField(
        &opened.draft,
        "2551Q.2018-01-ENCS.input.taxpayers_name",
    ).?;
    try std.testing.expectEqualStrings(
        "COR import batch 42",
        name.revision_source.imported,
    );
    const typed = try rehydrate(&opened.draft);
    const typed_name = typed.snapshot.get(
        ids.FieldId.initComptime(
            "2551Q.2018-01-ENCS.input.taxpayers_name",
        ),
    ).?;
    try std.testing.expectEqualStrings(
        "COR import batch 42",
        typed_name.provenance.revision_source.imported.asSlice(),
    );
}

test "amendment persistence keeps the caller-supplied opaque ID" {
    const allocator = std.testing.allocator;
    var store = try store_module.Store.openMemory(allocator);
    defer store.close();

    var revision = try testRevision(.{
        .profile_id = "profile-amendment",
        .revision_id = "revision-amendment-1",
        .name = "AMENDMENT FILER",
        .tin = "123-456-789-000",
    });
    try persistTestRevision(&store, &revision);
    var composition = try compose2551Q(
        &revision,
        try model.Date.parseIso("2026-03-31"),
        2026,
        1,
    );
    var original = try createOrLoad(allocator, &store, .{
        .period = composition.period,
        .role_bindings = &composition.bindings,
        .snapshot = &composition.snapshot,
    });
    const original_id = try ids.DraftId.parse(original.draft.id);
    original.deinit(allocator);

    const supplied = try ids.DraftId.parse(
        "c2eb7e930d7e4f94a01d0707e81a6624",
    );
    var amendment = try createOrLoad(allocator, &store, .{
        .mode = .{ .amendment = .{
            .caller_supplied_id = supplied,
            .amendment_of = original_id,
        } },
        .period = composition.period,
        .role_bindings = &composition.bindings,
        .snapshot = &composition.snapshot,
    });
    defer amendment.deinit(allocator);
    try std.testing.expectEqualStrings(
        supplied.asSlice(),
        amendment.draft.id,
    );
    try std.testing.expectEqualStrings(
        original_id.asSlice(),
        amendment.draft.amendment_of.?,
    );
}
