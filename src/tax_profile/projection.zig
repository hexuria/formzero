//! Runtime qualification and owned form-prefill snapshots.
//!
//! Static form specs are compiler-checked, but profiles arrive from SQLite at
//! runtime. Qualification bridges those two worlds and reports domain-level
//! reasons instead of substituting defaults.

const std = @import("std");
const ids = @import("../forms/id.zig");
const spec = @import("../forms/spec.zig");
const field = @import("field.zig");
const model = @import("model.zig");
const capability = @import("capability.zig");

pub const max_qualification_issues = 32;
pub const max_snapshot_entries = 64;

pub const Binding = struct {
    role: ids.Role,
    revision: *const model.ProfileRevision,
    selection: capability.Selection = .{},

    pub fn fromHistory(
        role: ids.Role,
        history: *const model.History,
        on: model.Date,
        selection: capability.Selection,
    ) model.HistoryError!Binding {
        return .{
            .role = role,
            .revision = try history.resolve(on),
            .selection = selection,
        };
    }
};

pub const QualificationIssue = union(enum) {
    role_mismatch: struct {
        expected: ids.Role,
        actual: ids.Role,
    },
    invalid_revision: model.RevisionError,
    revision_not_effective: struct {
        role: ids.Role,
        revision_id: model.RevisionId,
    },
    subject_not_allowed: struct {
        role: ids.Role,
        subject: model.SubjectKind,
    },
    missing_required_field: struct {
        role: ids.Role,
        reusable_field: field.ReusableField,
    },
    business_activity_selection_required: ids.Role,
    unknown_business_activity: ids.Role,
    inactive_business_activity: ids.Role,
};

pub const Qualification = struct {
    issues: [max_qualification_issues]QualificationIssue = undefined,
    len: u8 = 0,
    truncated: bool = false,

    pub fn accepted(self: *const Qualification) bool {
        return self.len == 0 and !self.truncated;
    }

    pub fn slice(self: *const Qualification) []const QualificationIssue {
        return self.issues[0..self.len];
    }

    fn add(self: *Qualification, issue: QualificationIssue) void {
        if (self.len == self.issues.len) {
            self.truncated = true;
            return;
        }
        self.issues[self.len] = issue;
        self.len += 1;
    }
};

pub fn qualify(
    role_spec: spec.RoleSpec,
    binding: Binding,
    on: model.Date,
) Qualification {
    var result: Qualification = .{};
    if (binding.role != role_spec.role) {
        result.add(.{ .role_mismatch = .{
            .expected = role_spec.role,
            .actual = binding.role,
        } });
        return result;
    }
    binding.revision.validate() catch |err| {
        result.add(.{ .invalid_revision = err });
        return result;
    };
    if (!binding.revision.isEffective(on)) {
        result.add(.{ .revision_not_effective = .{
            .role = binding.role,
            .revision_id = binding.revision.id,
        } });
        return result;
    }
    if (!role_spec.accepts(binding.revision.subject.kind())) {
        result.add(.{ .subject_not_allowed = .{
            .role = binding.role,
            .subject = binding.revision.subject.kind(),
        } });
    }

    for (role_spec.requirements) |requirement| {
        const value = capability.valueFor(
            binding.revision,
            requirement.source,
            on,
            binding.selection,
        ) catch |err| {
            result.add(switch (err) {
                error.BusinessActivitySelectionRequired => .{ .business_activity_selection_required = binding.role },
                error.UnknownBusinessActivity => .{ .unknown_business_activity = binding.role },
                error.InactiveBusinessActivity => .{ .inactive_business_activity = binding.role },
            });
            continue;
        };
        if (value == null and requirement.presence == .required) {
            result.add(.{ .missing_required_field = .{
                .role = binding.role,
                .reusable_field = requirement.source,
            } });
        }
    }
    return result;
}

pub const Provenance = struct {
    profile_id: model.ProfileId,
    revision_id: model.RevisionId,
    revision_sequence: u32,
    revision_source: model.RevisionSource,
    business_activity_id: ?model.BusinessActivityId = null,
    registration_fact_id: ?model.RegistrationFactId = null,
};

pub const SnapshotEntry = struct {
    role: ids.Role,
    target: ids.FieldId,
    value: field.Value,
    provenance: Provenance,
};

pub const SnapshotError = error{
    TooManyEntries,
    DuplicateTarget,
};

/// Entirely owned by value: no entry borrows a profile revision. Historical
/// drafts therefore remain stable when a newer profile revision is appended.
pub const Snapshot = struct {
    form: ids.FormRevision,
    effective_on: model.Date,
    entries: [max_snapshot_entries]SnapshotEntry = undefined,
    len: u8 = 0,

    pub fn init(form: ids.FormRevision, effective_on: model.Date) Snapshot {
        return .{ .form = form, .effective_on = effective_on };
    }

    pub fn slice(self: *const Snapshot) []const SnapshotEntry {
        return self.entries[0..self.len];
    }

    pub fn get(
        self: *const Snapshot,
        target: ids.FieldId,
    ) ?*const SnapshotEntry {
        for (self.slice()) |*entry| {
            if (entry.target.eql(&target)) return entry;
        }
        return null;
    }

    pub fn append(self: *Snapshot, entry: SnapshotEntry) SnapshotError!void {
        if (self.get(entry.target) != null) return error.DuplicateTarget;
        if (self.len == self.entries.len) return error.TooManyEntries;
        self.entries[self.len] = entry;
        self.len += 1;
    }

    pub fn appendSnapshot(
        self: *Snapshot,
        other: *const Snapshot,
    ) SnapshotError!void {
        for (other.slice()) |entry| try self.append(entry);
    }
};

pub const ProjectError = SnapshotError || error{QualificationFailed};

pub fn projectRole(
    form: ids.FormRevision,
    role_spec: spec.RoleSpec,
    binding: Binding,
    on: model.Date,
) ProjectError!Snapshot {
    const qualification = qualify(role_spec, binding, on);
    if (!qualification.accepted()) return error.QualificationFailed;

    var snapshot = Snapshot.init(form, on);
    for (role_spec.requirements) |requirement| {
        const value = (capability.valueFor(
            binding.revision,
            requirement.source,
            on,
            binding.selection,
        ) catch unreachable) orelse continue;
        var activity_id: ?model.BusinessActivityId = null;
        var registration_fact_id: ?model.RegistrationFactId = null;
        if (requirement.source == .atc or
            requirement.source == .line_of_business)
        {
            const activity = capability.resolveBusinessActivity(
                binding.revision,
                on,
                binding.selection,
            ) catch unreachable;
            if (activity) |selected| activity_id = selected.id;
        }
        const fact_kind: ?model.RegistrationFactKind =
            switch (requirement.source) {
                .tax_type => .tax_type,
                .government_withholding_agent => .government_withholding_agent,
                .special_rate_basis => .special_rate_basis,
                else => null,
            };
        if (fact_kind) |kind| {
            if (binding.revision.registrationFact(kind, on)) |fact| {
                registration_fact_id = fact.id;
            }
        }
        try snapshot.append(.{
            .role = binding.role,
            .target = requirement.target,
            .value = value,
            .provenance = .{
                .profile_id = binding.revision.profile_id,
                .revision_id = binding.revision.id,
                .revision_sequence = binding.revision.sequence,
                .revision_source = binding.revision.source,
                .business_activity_id = activity_id,
                .registration_fact_id = registration_fact_id,
            },
        });
    }
    return snapshot;
}

fn exampleRevision(
    activities: []const model.BusinessActivity,
) !model.ProfileRevision {
    return .{
        .profile_id = try model.ProfileId.parse("profile-maria"),
        .id = try model.RevisionId.parse("revision-1"),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("1 Taxpayer Street"),
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse("maria@example.ph"),
        },
        .subject = .{ .sole_proprietor = .{
            .person = .{
                .name = try field.TaxpayerName.parse("MARIA SANTOS"),
                .date_of_birth = try model.Date.parseIso("1995-06-01"),
                .citizenship = try field.Citizenship.parse("Filipino"),
            },
        } },
        .business_activities = activities,
    };
}

test "2551Q projection owns the exact header and revision provenance" {
    const form_2551q = @import("../forms/form_2551q.zig");
    const activities = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("activity-retail"),
        .line_of_business = try field.LineOfBusiness.parse("Retail"),
        .atc = try field.Atc.parse("PT010"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    }};
    var revision = try exampleRevision(&activities);
    const on = try model.Date.parseIso("2026-03-31");
    var snapshot = try projectRole(
        form_2551q.revision,
        form_2551q.roles[0],
        .{ .role = .filer, .revision = &revision },
        on,
    );

    try std.testing.expectEqual(@as(u8, 7), snapshot.len);
    const tin = snapshot.get(
        ids.FieldId.initComptime("2551Q.2018-01-ENCS.input.tin"),
    ).?;
    try std.testing.expectEqualStrings(
        "revision-1",
        tin.provenance.revision_id.asSlice(),
    );

    // A later mutation of the source memory cannot alter the copied snapshot.
    revision.identity.tin = try field.Tin.parse("999-888-777-000");
    const snap_tin = snapshot.get(
        ids.FieldId.initComptime("2551Q.2018-01-ENCS.input.tin"),
    ).?;
    try std.testing.expectEqualStrings(
        "123456789000",
        snap_tin.value.tin.asDigits(),
    );
}

test "qualification explains missing and ambiguous business activity" {
    const business_requirements = [_]spec.Requirement{.{
        .source = .atc,
        .target = ids.FieldId.initComptime("example.schedule.atc"),
    }};
    const role_spec: spec.RoleSpec = .{
        .role = .filer,
        .cardinality = .exactly_one,
        .allowed_subjects = model.SubjectKindSet.full,
        .requirements = &business_requirements,
    };
    var no_activity = try exampleRevision(&.{});
    const on = try model.Date.parseIso("2026-03-31");
    const missing = qualify(
        role_spec,
        .{ .role = .filer, .revision = &no_activity },
        on,
    );
    try std.testing.expect(!missing.accepted());
    try std.testing.expectEqual(
        field.ReusableField.atc,
        missing.slice()[0].missing_required_field.reusable_field,
    );

    const activities = [_]model.BusinessActivity{
        .{
            .id = try model.BusinessActivityId.parse("activity-one"),
            .line_of_business = try field.LineOfBusiness.parse("Retail"),
            .atc = try field.Atc.parse("PT010"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
        },
        .{
            .id = try model.BusinessActivityId.parse("activity-two"),
            .line_of_business = try field.LineOfBusiness.parse("Services"),
            .atc = try field.Atc.parse("PT040"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
        },
    };
    var ambiguous = try exampleRevision(&activities);
    const result = qualify(
        role_spec,
        .{ .role = .filer, .revision = &ambiguous },
        on,
    );
    try std.testing.expect(!result.accepted());
    try std.testing.expectEqual(
        @as(usize, 1),
        result.slice().len,
    );
    try std.testing.expectEqual(
        std.meta.activeTag(
            QualificationIssue{ .business_activity_selection_required = .filer },
        ),
        std.meta.activeTag(result.slice()[0]),
    );
}

test "2551Q rejects a profile missing a required contact capability" {
    const form_2551q = @import("../forms/form_2551q.zig");
    var revision = try exampleRevision(&.{});
    revision.contact.email_address = null;
    const result = qualify(
        form_2551q.roles[0],
        .{ .role = .filer, .revision = &revision },
        try model.Date.parseIso("2026-03-31"),
    );
    try std.testing.expectEqual(@as(usize, 1), result.slice().len);
    try std.testing.expectEqual(
        field.ReusableField.email_address,
        result.slice()[0].missing_required_field.reusable_field,
    );
}
