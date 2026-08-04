//! Typed, append-only annual Tax Form Profile domain.
//!
//! The generated catalog is the only authority for which setup values exist.
//! Base taxpayer facts never enter this aggregate; values are annual binding
//! selections or catalog-approved yearly/default values. `no_setup` and
//! calendar-only forms deliberately have no revision stream.

const std = @import("std");
const catalog = @import("../forms/generated/catalog.zig");
const date = @import("../domain/date.zig");
const model = @import("model.zig");

pub const Date = date.Date;
pub const EffectivePeriod = date.EffectivePeriod;

pub const Error = error{
    EmptyIdentifier,
    IdentifierTooLong,
    InvalidIdentifier,
    InvalidTaxYear,
    InvalidSequence,
    WrongForm,
    WrongFormRevision,
    NoSetupContract,
    SpecRevisionMismatch,
    SpecHashMismatch,
    EffectivePeriodOutsideTaxYear,
    EmptySetupRevision,
    DuplicateValue,
    UnknownSemanticKey,
    WrongRole,
    WrongValueType,
    UnsupportedOwnership,
    EvidenceRequired,
    MissingRequiredValue,
    InvalidConfirmation,
    InvalidCopySource,
    WrongStream,
    DuplicateRevisionId,
    DuplicateSequence,
    OverlappingEffectivePeriods,
    NoEffectiveRevision,
    StaleExpectedSequence,
};

fn Identifier(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        bytes: [capacity]u8 = undefined,
        len: u8 = 0,

        pub fn parse(raw: []const u8) Error!Self {
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

pub const RevisionId = Identifier(64);
pub const ComponentAnchorId = Identifier(64);
pub const FormCode = Identifier(16);
pub const FormRevision = Identifier(48);
pub const SpecHash = Identifier(64);
pub const TextValue = Identifier(255);

pub const StreamKey = struct {
    profile_id: model.ProfileId,
    tax_year: u16,
    form_code: FormCode,
    form_revision: FormRevision,

    pub fn eql(self: *const StreamKey, other: *const StreamKey) bool {
        return self.profile_id.eql(&other.profile_id) and
            self.tax_year == other.tax_year and
            self.form_code.eql(&other.form_code) and
            self.form_revision.eql(&other.form_revision);
    }
};

pub const ScalarValue = union(enum) {
    profile_id: model.ProfileId,
    business_activity_anchor_id: ComponentAnchorId,
    registration_obligation_anchor_id: ComponentAnchorId,
    text: TextValue,
    boolean: bool,
    integer: i64,
    date: Date,
    year: u16,
    choice: TextValue,

    pub fn valueType(self: ScalarValue) catalog.TaxFormProfileValueType {
        return switch (self) {
            .profile_id => .profile_id,
            .business_activity_anchor_id => .business_activity_anchor_id,
            .registration_obligation_anchor_id => .registration_obligation_anchor_id,
            .text => .text,
            .boolean => .boolean,
            .integer => .integer,
            .date => .date,
            .year => .year,
            .choice => .choice,
        };
    }
};

pub const ValueSource = union(enum) {
    manual_confirmation,
    copied_from_revision: RevisionId,
    migrated: TextValue,
};

pub const SetupValue = struct {
    semantic_key: catalog.TaxFormProfileSemanticKey,
    role: catalog.Role,
    value: ScalarValue,
    source: ValueSource = .manual_confirmation,
};

pub const ReviewState = enum {
    requires_review,
    confirmed,
};

pub const RevisionSource = union(enum) {
    manual_entry,
    copied_from_prior_year: struct {
        source_tax_year: u16,
        source_form_revision: FormRevision,
        source_spec_revision: u32,
        source_spec_hash: SpecHash,
        source_revision_id: RevisionId,
    },
    migrated: TextValue,
};

pub const Revision = struct {
    id: RevisionId,
    stream: StreamKey,
    sequence: u32,
    effective: EffectivePeriod,
    spec_revision: u32,
    spec_hash: SpecHash,
    review_state: ReviewState,
    confirmed_at_unix: ?i64 = null,
    source: RevisionSource,
    values: []const SetupValue,

    pub fn validate(
        self: *const Revision,
        form: *const catalog.FormDefinition,
    ) Error!void {
        if (self.stream.tax_year == 0) return error.InvalidTaxYear;
        if (self.sequence == 0) return error.InvalidSequence;
        if (!std.mem.eql(u8, self.stream.form_code.asSlice(), form.code)) {
            return error.WrongForm;
        }
        const form_revision = form.revision orelse return error.NoSetupContract;
        if (!std.mem.eql(
            u8,
            self.stream.form_revision.asSlice(),
            form_revision,
        )) return error.WrongFormRevision;

        const spec = &form.tax_form_profile;
        if (spec.mode != .setup) return error.NoSetupContract;
        if (self.spec_revision != (spec.spec_revision orelse
            return error.NoSetupContract)) return error.SpecRevisionMismatch;
        if (!std.mem.eql(
            u8,
            self.spec_hash.asSlice(),
            spec.spec_hash orelse return error.NoSetupContract,
        )) return error.SpecHashMismatch;
        if (!periodWithinTaxYear(self.effective, self.stream.tax_year)) {
            return error.EffectivePeriodOutsideTaxYear;
        }
        if (self.values.len == 0) return error.EmptySetupRevision;
        switch (self.review_state) {
            .requires_review => if (self.confirmed_at_unix != null) {
                return error.InvalidConfirmation;
            },
            .confirmed => if (self.confirmed_at_unix == null) {
                return error.InvalidConfirmation;
            },
        }
        switch (self.source) {
            .manual_entry, .migrated => {},
            .copied_from_prior_year => |copy| {
                if (copy.source_tax_year >= self.stream.tax_year) {
                    return error.InvalidCopySource;
                }
                if (copy.source_spec_revision == 0) {
                    return error.InvalidCopySource;
                }
            },
        }

        for (self.values, 0..) |value, index| {
            for (self.values[index + 1 ..]) |other| {
                if (value.role == other.role and
                    value.semantic_key == other.semantic_key)
                {
                    return error.DuplicateValue;
                }
            }
            const definition = findDefinition(
                spec,
                value.role,
                value.semantic_key,
            ) orelse return error.UnknownSemanticKey;
            if (definition.role != value.role) return error.WrongRole;
            if (definition.availability == .evidence_required) {
                return error.EvidenceRequired;
            }
            if (definition.ownership != .binding_selection and
                definition.ownership != .yearly_value and
                definition.ownership != .transaction_default)
            {
                return error.UnsupportedOwnership;
            }
            if (value.value.valueType() != definition.value_type) {
                return error.WrongValueType;
            }
        }

        for (spec.values) |definition| {
            if (definition.availability != .supported or
                definition.presence != .required)
            {
                continue;
            }
            if (findValue(
                self.values,
                definition.role,
                definition.semantic_key,
            ) == null) return error.MissingRequiredValue;
        }
    }

    pub fn effectiveOn(self: *const Revision, on: Date) bool {
        return on.year == self.stream.tax_year and self.effective.contains(on);
    }
};

pub const History = struct {
    stream: StreamKey,
    revisions: []const Revision,

    pub fn validate(
        self: *const History,
        form: *const catalog.FormDefinition,
    ) Error!void {
        for (self.revisions, 0..) |*revision, index| {
            if (!revision.stream.eql(&self.stream)) return error.WrongStream;
            try revision.validate(form);
            for (self.revisions[index + 1 ..]) |*other| {
                if (revision.id.eql(&other.id)) {
                    return error.DuplicateRevisionId;
                }
                if (revision.sequence == other.sequence) {
                    return error.DuplicateSequence;
                }
                // An exact same-period higher-sequence row is an immutable
                // correction of the annual setup. Partial overlaps remain
                // ambiguous and are rejected.
                if (revision.effective.overlaps(other.effective) and
                    !revision.effective.eql(other.effective))
                {
                    return error.OverlappingEffectivePeriods;
                }
            }
        }
    }

    pub fn effectiveOn(
        self: *const History,
        form: *const catalog.FormDefinition,
        on: Date,
    ) Error!*const Revision {
        try self.validate(form);
        var found: ?*const Revision = null;
        for (self.revisions) |*revision| {
            if (revision.review_state != .confirmed or
                !revision.effectiveOn(on)) continue;
            if (found == null or revision.sequence > found.?.sequence) {
                found = revision;
            }
        }
        return found orelse error.NoEffectiveRevision;
    }

    pub fn assertExpectedSequence(
        self: *const History,
        expected_current_sequence: u32,
    ) Error!void {
        if (self.currentSequence() != expected_current_sequence) {
            return error.StaleExpectedSequence;
        }
    }

    /// Optimistic concurrency belongs to the whole exact stream, not to one
    /// effective segment. A caller editing an older segment must still append
    /// after the newest revision saved for any other segment in the stream.
    pub fn currentSequence(self: *const History) u32 {
        var current: u32 = 0;
        for (self.revisions) |revision| {
            current = @max(current, revision.sequence);
        }
        return current;
    }
};

pub fn revisionStreamAllowed(form: *const catalog.FormDefinition) bool {
    return form.tax_form_profile.mode == .setup;
}

pub fn findValue(
    values: []const SetupValue,
    role: catalog.Role,
    key: catalog.TaxFormProfileSemanticKey,
) ?*const SetupValue {
    for (values) |*value| {
        if (value.role == role and value.semantic_key == key) return value;
    }
    return null;
}

fn findDefinition(
    spec: *const catalog.TaxFormProfileSpec,
    role: catalog.Role,
    key: catalog.TaxFormProfileSemanticKey,
) ?*const catalog.TaxFormProfileValueDefinition {
    for (spec.values) |*definition| {
        if (definition.role == role and definition.semantic_key == key) {
            return definition;
        }
    }
    return null;
}

fn periodWithinTaxYear(period: EffectivePeriod, tax_year: u16) bool {
    if (period.from.year != tax_year) return false;
    if (period.until) |until| return until.year == tax_year;
    // An open annual interval is interpreted only through `effectiveOn`,
    // which rejects dates outside the stream's tax year.
    return true;
}

fn fixtureRevision(
    id: []const u8,
    sequence: u32,
    from: []const u8,
    until: ?[]const u8,
) !Revision {
    const form = catalog.findForm("1601C").?;
    const activity = SetupValue{
        .semantic_key = .business_activity_anchor_id,
        .role = .filer,
        .value = .{ .business_activity_anchor_id = try ComponentAnchorId.parse("activity-primary") },
    };
    const values = try std.testing.allocator.alloc(SetupValue, 1);
    values[0] = activity;
    return .{
        .id = try RevisionId.parse(id),
        .stream = .{
            .profile_id = try model.ProfileId.parse("profile-one"),
            .tax_year = 2026,
            .form_code = try FormCode.parse(form.code),
            .form_revision = try FormRevision.parse(form.revision.?),
        },
        .sequence = sequence,
        .effective = try EffectivePeriod.init(
            try Date.parseIso(from),
            if (until) |last| try Date.parseIso(last) else null,
        ),
        .spec_revision = form.tax_form_profile.spec_revision.?,
        .spec_hash = try SpecHash.parse(form.tax_form_profile.spec_hash.?),
        .review_state = .confirmed,
        .confirmed_at_unix = 1,
        .source = .manual_entry,
        .values = values,
    };
}

test "no-setup and calendar-only forms cannot manufacture revision streams" {
    try std.testing.expect(!revisionStreamAllowed(catalog.findForm("2551Q").?));
    try std.testing.expect(!revisionStreamAllowed(catalog.findForm("0605").?));
    try std.testing.expect(!revisionStreamAllowed(catalog.findForm("1905").?));
    try std.testing.expect(revisionStreamAllowed(catalog.findForm("1601C").?));
}

test "generated setup contract validates exact typed binding" {
    var revision = try fixtureRevision("setup-1", 1, "2026-01-01", null);
    defer std.testing.allocator.free(revision.values);
    try revision.validate(catalog.findForm("1601C").?);

    var empty = revision;
    empty.values = &.{};
    try std.testing.expectError(
        error.EmptySetupRevision,
        empty.validate(catalog.findForm("1601C").?),
    );

    var wrong = revision;
    var wrong_values = [_]SetupValue{revision.values[0]};
    wrong_values[0].value = .{ .profile_id = try model.ProfileId.parse("another-profile") };
    wrong.values = &wrong_values;
    try std.testing.expectError(
        error.WrongValueType,
        wrong.validate(catalog.findForm("1601C").?),
    );
}

test "evidence-gated binding cannot become editable annual data" {
    const form = catalog.findForm("0619E").?;
    var revision = try fixtureRevision("setup-1", 1, "2026-01-01", null);
    defer std.testing.allocator.free(revision.values);
    revision.stream.form_code = try FormCode.parse(form.code);
    revision.stream.form_revision = try FormRevision.parse(form.revision.?);
    revision.spec_revision = form.tax_form_profile.spec_revision.?;
    revision.spec_hash = try SpecHash.parse(form.tax_form_profile.spec_hash.?);
    try std.testing.expectError(error.EvidenceRequired, revision.validate(form));
}

test "annual stream rejects overlap and resolves only confirmed effective row" {
    const first = try fixtureRevision(
        "setup-1",
        1,
        "2026-01-01",
        "2026-06-30",
    );
    defer std.testing.allocator.free(first.values);
    var second = try fixtureRevision("setup-2", 2, "2026-07-01", null);
    defer std.testing.allocator.free(second.values);
    const revisions = [_]Revision{ first, second };
    const history: History = .{
        .stream = first.stream,
        .revisions = &revisions,
    };
    const form = catalog.findForm("1601C").?;
    try history.validate(form);
    try std.testing.expectEqual(@as(u32, 2), history.currentSequence());
    try std.testing.expectEqual(
        @as(u32, 2),
        (try history.effectiveOn(form, try Date.parseIso("2026-08-01"))).sequence,
    );

    second.effective = try EffectivePeriod.init(
        try Date.parseIso("2026-06-30"),
        null,
    );
    const overlap = [_]Revision{ first, second };
    try std.testing.expectError(
        error.OverlappingEffectivePeriods,
        (History{ .stream = first.stream, .revisions = &overlap }).validate(form),
    );
}

test "annual stream keeps same-period corrections and resolves newest sequence" {
    const first = try fixtureRevision(
        "setup-correction-1",
        1,
        "2026-01-01",
        null,
    );
    defer std.testing.allocator.free(first.values);
    const corrected = try fixtureRevision(
        "setup-correction-2",
        2,
        "2026-01-01",
        null,
    );
    defer std.testing.allocator.free(corrected.values);
    const revisions = [_]Revision{ first, corrected };
    const history: History = .{
        .stream = first.stream,
        .revisions = &revisions,
    };
    const form = catalog.findForm("1601C").?;
    try history.validate(form);
    try std.testing.expectEqual(
        @as(u32, 2),
        (try history.effectiveOn(
            form,
            try Date.parseIso("2026-08-04"),
        )).sequence,
    );
}

test "copy provenance requires a prior year and survives confirmation" {
    var revision = try fixtureRevision("setup-copy", 1, "2026-01-01", null);
    defer std.testing.allocator.free(revision.values);
    revision.review_state = .requires_review;
    revision.confirmed_at_unix = null;
    revision.source = .{ .copied_from_prior_year = .{
        .source_tax_year = 2025,
        .source_form_revision = revision.stream.form_revision,
        .source_spec_revision = revision.spec_revision,
        .source_spec_hash = revision.spec_hash,
        .source_revision_id = try RevisionId.parse("setup-2025"),
    } };
    try revision.validate(catalog.findForm("1601C").?);

    revision.review_state = .confirmed;
    revision.confirmed_at_unix = 2;
    try revision.validate(catalog.findForm("1601C").?);

    revision.source.copied_from_prior_year.source_tax_year = 2026;
    try std.testing.expectError(
        error.InvalidCopySource,
        revision.validate(catalog.findForm("1601C").?),
    );
}

test "stale sequence check does not mutate candidate revision" {
    const first = try fixtureRevision("setup-1", 1, "2026-01-01", null);
    defer std.testing.allocator.free(first.values);
    const revisions = [_]Revision{first};
    const history: History = .{ .stream = first.stream, .revisions = &revisions };
    const candidate = try fixtureRevision("setup-2", 2, "2026-01-01", null);
    defer std.testing.allocator.free(candidate.values);
    const before = candidate.sequence;
    try std.testing.expectError(
        error.StaleExpectedSequence,
        history.assertExpectedSequence(0),
    );
    try std.testing.expectEqual(before, candidate.sequence);
}
