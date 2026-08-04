//! Typed, append-only settings shared by forms for one taxpayer and tax year.
//!
//! Only the two settings established by the ownership audit live here. They
//! are owned once by `(profile_id, tax_year)`; form codes and form revisions
//! deliberately do not exist in this domain. A form may consume a confirmed
//! value, but it may not copy that value into its Tax Form Profile.

const std = @import("std");
const date = @import("../domain/date.zig");
const field = @import("field.zig");
const model = @import("model.zig");

pub const Date = date.Date;
pub const EffectivePeriod = date.EffectivePeriod;

pub const Error = error{
    EmptyIdentifier,
    IdentifierTooLong,
    InvalidIdentifier,
    InvalidTaxYear,
    InvalidSequence,
    EffectivePeriodOutsideTaxYear,
    DuplicateSettingKey,
    DeductionMethodRequiresGraduatedRate,
    InvalidConfirmation,
    InvalidCopySource,
    WrongOwner,
    DuplicateRevisionId,
    DuplicateSequence,
    OverlappingEffectivePeriods,
    NoEffectiveRevision,
    EffectiveRevisionRequiresReview,
    MissingSetting,
    InvalidCandidateSequence,
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

/// Stable identity of an immutable taxpayer-year settings revision.
pub const RevisionId = Identifier(64);

/// The only owner of this aggregate. There is intentionally no form
/// dimension: 1701, 1701Q, and any other proven consumer resolve the same
/// stream for the taxpayer and year.
pub const StreamKey = struct {
    profile_id: model.ProfileId,
    tax_year: u16,

    pub fn validate(self: StreamKey) Error!void {
        if (self.tax_year == 0) return error.InvalidTaxYear;
    }

    pub fn eql(self: *const StreamKey, other: *const StreamKey) bool {
        return self.profile_id.eql(&other.profile_id) and
            self.tax_year == other.tax_year;
    }
};

/// Evidence-approved yearly tax-rate choices for natural-person income tax.
pub const IncomeTaxRateElection = enum {
    graduated,
    eight_percent,
};

/// A deduction method is meaningful only with the graduated-rate election.
pub const DeductionMethod = enum {
    itemized_deduction,
    optional_standard_deduction,
};

/// Closed ownership vocabulary from the form-profile ownership audit.
pub const SettingKey = enum {
    income_tax_rate_election,
    deduction_method,
};

pub const SettingValue = union(SettingKey) {
    income_tax_rate_election: IncomeTaxRateElection,
    deduction_method: DeductionMethod,

    pub fn key(self: SettingValue) SettingKey {
        return switch (self) {
            .income_tax_rate_election => .income_tax_rate_election,
            .deduction_method => .deduction_method,
        };
    }
};

pub const ReviewState = enum {
    requires_review,
    confirmed,
};

/// Explicit provenance for a copied proposal. The complete source stream and
/// exact immutable revision are retained; a year number alone is not enough.
pub const PriorYearCopySource = struct {
    stream: StreamKey,
    revision_id: RevisionId,
    revision_sequence: u32,
};

pub const RevisionSource = union(enum) {
    manual_entry,
    imported: field.SourceReference,
    migrated: field.SourceReference,
    copied_from_prior_year: PriorYearCopySource,
};

pub const Revision = struct {
    id: RevisionId,
    stream: StreamKey,
    sequence: u32,
    effective: EffectivePeriod,
    review_state: ReviewState,
    confirmed_at_unix_seconds: ?i64 = null,
    source: RevisionSource,
    values: []const SettingValue,

    pub fn validate(self: *const Revision) Error!void {
        try self.stream.validate();
        if (self.sequence == 0) return error.InvalidSequence;
        if (!periodWithinTaxYear(self.effective, self.stream.tax_year)) {
            return error.EffectivePeriodOutsideTaxYear;
        }

        switch (self.review_state) {
            .requires_review => if (self.confirmed_at_unix_seconds != null) {
                return error.InvalidConfirmation;
            },
            .confirmed => {
                const confirmed_at = self.confirmed_at_unix_seconds orelse
                    return error.InvalidConfirmation;
                if (confirmed_at <= 0) return error.InvalidConfirmation;
            },
        }

        switch (self.source) {
            .manual_entry, .imported, .migrated => {},
            .copied_from_prior_year => |copy| {
                if (!copy.stream.profile_id.eql(&self.stream.profile_id)) {
                    return error.WrongOwner;
                }
                if (copy.stream.tax_year == 0 or
                    @as(u32, copy.stream.tax_year) + 1 != self.stream.tax_year or
                    copy.revision_sequence == 0)
                {
                    return error.InvalidCopySource;
                }
                // `copyFromPriorYear` below always creates a review-only
                // proposal. Once the page has explicitly staged and
                // acknowledged that proposal, persistence appends a new
                // confirmed revision with this same exact provenance. The
                // source therefore remains valid in both lifecycle states;
                // the UI state machine owns the review transition instead of
                // forcing callers to erase the source at confirmation time.
            },
        }

        var income_tax_rate: ?IncomeTaxRateElection = null;
        var deduction_method: ?DeductionMethod = null;
        for (self.values, 0..) |value, index| {
            for (self.values[index + 1 ..]) |other| {
                if (value.key() == other.key()) {
                    return error.DuplicateSettingKey;
                }
            }
            switch (value) {
                .income_tax_rate_election => |election| {
                    income_tax_rate = election;
                },
                .deduction_method => |method| deduction_method = method,
            }
        }
        if (deduction_method != null and income_tax_rate != .graduated) {
            return error.DeductionMethodRequiresGraduatedRate;
        }
    }

    pub fn effectiveOn(self: *const Revision, on: Date) bool {
        return on.year == self.stream.tax_year and self.effective.contains(on);
    }

    pub fn find(self: *const Revision, key: SettingKey) ?*const SettingValue {
        for (self.values) |*value| {
            if (value.key() == key) return value;
        }
        return null;
    }
};

pub const ResolvedSetting = struct {
    revision: *const Revision,
    value: *const SettingValue,
};

/// Validation and exact-date resolution over one append-only stream.
pub const History = struct {
    stream: StreamKey,
    revisions: []const Revision,

    pub fn validate(self: *const History) Error!void {
        try self.stream.validate();
        for (self.revisions, 0..) |*revision, index| {
            if (!revision.stream.eql(&self.stream)) return error.WrongOwner;
            try revision.validate();
            for (self.revisions[index + 1 ..]) |*other| {
                if (revision.id.eql(&other.id)) {
                    return error.DuplicateRevisionId;
                }
                if (revision.sequence == other.sequence) {
                    return error.DuplicateSequence;
                }
                // Exact same-period rows are immutable corrections ordered by
                // sequence. Partial overlaps still describe two competing
                // effective ranges and remain invalid.
                if (revision.effective.overlaps(other.effective) and
                    !revision.effective.eql(other.effective))
                {
                    return error.OverlappingEffectivePeriods;
                }
            }
        }
    }

    /// Resolves the one revision whose closed interval contains `on` exactly.
    /// Review state is returned, not hidden: callers that consume a filing
    /// value must use `confirmedEffectiveOn` or `resolveSetting` below.
    pub fn effectiveOn(
        self: *const History,
        on: Date,
    ) Error!*const Revision {
        try self.validate();
        if (on.year != self.stream.tax_year) {
            return error.NoEffectiveRevision;
        }
        var found: ?*const Revision = null;
        for (self.revisions) |*revision| {
            if (!revision.effectiveOn(on)) continue;
            if (found == null or revision.sequence > found.?.sequence) {
                found = revision;
            }
        }
        return found orelse error.NoEffectiveRevision;
    }

    pub fn confirmedEffectiveOn(
        self: *const History,
        on: Date,
    ) Error!*const Revision {
        const revision = try self.effectiveOn(on);
        if (revision.review_state != .confirmed) {
            return error.EffectiveRevisionRequiresReview;
        }
        return revision;
    }

    pub fn resolveSetting(
        self: *const History,
        on: Date,
        key: SettingKey,
    ) Error!ResolvedSetting {
        const revision = try self.confirmedEffectiveOn(on);
        return .{
            .revision = revision,
            .value = revision.find(key) orelse return error.MissingSetting,
        };
    }

    pub fn currentSequence(self: *const History) u32 {
        var current: u32 = 0;
        for (self.revisions) |revision| {
            current = @max(current, revision.sequence);
        }
        return current;
    }

    pub fn assertExpectedSequence(
        self: *const History,
        expected_current_sequence: u32,
    ) Error!void {
        try self.validate();
        if (self.currentSequence() != expected_current_sequence) {
            return error.StaleExpectedSequence;
        }
    }

    /// Pure optimistic append contract. A stale result returns the caller's
    /// exact candidate pointer and never edits it, so UI/store adapters can
    /// preserve the unsaved draft while presenting the current sequence.
    pub fn checkAppend(
        self: *const History,
        expected_current_sequence: u32,
        candidate: *const Revision,
    ) Error!AppendCheck {
        try self.validate();
        const actual_sequence = self.currentSequence();
        if (actual_sequence != expected_current_sequence) {
            return .{ .stale = .{
                .expected_sequence = expected_current_sequence,
                .actual_sequence = actual_sequence,
                .candidate = candidate,
            } };
        }

        if (!candidate.stream.eql(&self.stream)) return error.WrongOwner;
        try candidate.validate();
        if (actual_sequence == std.math.maxInt(u32) or
            candidate.sequence != actual_sequence + 1)
        {
            return error.InvalidCandidateSequence;
        }
        for (self.revisions) |*revision| {
            if (revision.id.eql(&candidate.id)) {
                return error.DuplicateRevisionId;
            }
            if (revision.sequence == candidate.sequence) {
                return error.DuplicateSequence;
            }
            if (revision.effective.overlaps(candidate.effective) and
                !revision.effective.eql(candidate.effective))
            {
                return error.OverlappingEffectivePeriods;
            }
        }
        return .{ .ready = candidate };
    }
};

pub const StaleAppendConflict = struct {
    expected_sequence: u32,
    actual_sequence: u32,
    candidate: *const Revision,
};

pub const AppendCheck = union(enum) {
    ready: *const Revision,
    stale: StaleAppendConflict,
};

/// Creates a closed interval covering exactly one calendar tax year.
pub fn fullTaxYearPeriod(tax_year: u16) Error!EffectivePeriod {
    if (tax_year == 0) return error.InvalidTaxYear;
    const first = Date.init(tax_year, 1, 1) catch
        return error.InvalidTaxYear;
    const last = Date.init(tax_year, 12, 31) catch unreachable;
    return EffectivePeriod.init(first, last) catch unreachable;
}

/// Builds a review-only proposal that borrows the exact values of a confirmed
/// prior-year revision and records its stable identity. No implicit fallback
/// to "the latest prior year" exists.
pub fn copyFromPriorYear(
    id: RevisionId,
    target_stream: StreamKey,
    sequence: u32,
    effective: EffectivePeriod,
    source_revision: *const Revision,
) Error!Revision {
    try target_stream.validate();
    try source_revision.validate();
    if (!source_revision.stream.profile_id.eql(&target_stream.profile_id)) {
        return error.WrongOwner;
    }
    if (@as(u32, source_revision.stream.tax_year) + 1 !=
        target_stream.tax_year)
    {
        return error.InvalidCopySource;
    }
    if (source_revision.review_state != .confirmed) {
        return error.InvalidCopySource;
    }

    const copied: Revision = .{
        .id = id,
        .stream = target_stream,
        .sequence = sequence,
        .effective = effective,
        .review_state = .requires_review,
        .confirmed_at_unix_seconds = null,
        .source = .{ .copied_from_prior_year = .{
            .stream = source_revision.stream,
            .revision_id = source_revision.id,
            .revision_sequence = source_revision.sequence,
        } },
        .values = source_revision.values,
    };
    try copied.validate();
    return copied;
}

fn periodWithinTaxYear(period: EffectivePeriod, tax_year: u16) bool {
    if (period.from.year != tax_year) return false;
    const until = period.until orelse return false;
    return until.year == tax_year;
}

fn confirmedFixture(
    profile_id: []const u8,
    tax_year: u16,
    revision_id: []const u8,
    sequence: u32,
    effective: EffectivePeriod,
    values: []const SettingValue,
) !Revision {
    return .{
        .id = try RevisionId.parse(revision_id),
        .stream = .{
            .profile_id = try model.ProfileId.parse(profile_id),
            .tax_year = tax_year,
        },
        .sequence = sequence,
        .effective = effective,
        .review_state = .confirmed,
        .confirmed_at_unix_seconds = 1,
        .source = .manual_entry,
        .values = values,
    };
}

test "2025 and 2026 streams resolve independently" {
    const values_2025 = [_]SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .itemized_deduction },
    };
    const values_2026 = [_]SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const revision_2025 = try confirmedFixture(
        "profile-maria",
        2025,
        "year-settings-2025-1",
        1,
        try fullTaxYearPeriod(2025),
        &values_2025,
    );
    const revision_2026 = try confirmedFixture(
        "profile-maria",
        2026,
        "year-settings-2026-1",
        1,
        try fullTaxYearPeriod(2026),
        &values_2026,
    );
    const revisions_2025 = [_]Revision{revision_2025};
    const revisions_2026 = [_]Revision{revision_2026};
    const history_2025: History = .{
        .stream = revision_2025.stream,
        .revisions = &revisions_2025,
    };
    const history_2026: History = .{
        .stream = revision_2026.stream,
        .revisions = &revisions_2026,
    };

    const resolved_2025 = try history_2025.resolveSetting(
        try Date.parseIso("2025-09-30"),
        .income_tax_rate_election,
    );
    try std.testing.expectEqual(
        IncomeTaxRateElection.graduated,
        resolved_2025.value.income_tax_rate_election,
    );
    const resolved_2026 = try history_2026.resolveSetting(
        try Date.parseIso("2026-09-30"),
        .income_tax_rate_election,
    );
    try std.testing.expectEqual(
        IncomeTaxRateElection.eight_percent,
        resolved_2026.value.income_tax_rate_election,
    );
    try std.testing.expectError(
        error.NoEffectiveRevision,
        history_2025.effectiveOn(try Date.parseIso("2026-01-01")),
    );
}

test "closed effective intervals do not overlap and resolve exact boundaries" {
    const values = [_]SettingValue{
        .{ .income_tax_rate_election = .graduated },
    };
    const first = try confirmedFixture(
        "profile-maria",
        2026,
        "year-settings-1",
        1,
        try EffectivePeriod.init(
            try Date.parseIso("2026-01-01"),
            try Date.parseIso("2026-06-30"),
        ),
        &values,
    );
    var second = try confirmedFixture(
        "profile-maria",
        2026,
        "year-settings-2",
        2,
        try EffectivePeriod.init(
            try Date.parseIso("2026-07-01"),
            try Date.parseIso("2026-12-31"),
        ),
        &values,
    );
    const revisions = [_]Revision{ first, second };
    const history: History = .{
        .stream = first.stream,
        .revisions = &revisions,
    };
    try history.validate();
    try std.testing.expectEqual(
        @as(u32, 1),
        (try history.effectiveOn(try Date.parseIso("2026-06-30"))).sequence,
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        (try history.effectiveOn(try Date.parseIso("2026-07-01"))).sequence,
    );

    second.effective = try EffectivePeriod.init(
        try Date.parseIso("2026-06-30"),
        try Date.parseIso("2026-12-31"),
    );
    const overlapping = [_]Revision{ first, second };
    try std.testing.expectError(
        error.OverlappingEffectivePeriods,
        (History{
            .stream = first.stream,
            .revisions = &overlapping,
        }).validate(),
    );
}

test "same-period correction remains append-only and newest sequence resolves" {
    const original_values = [_]SettingValue{
        .{ .income_tax_rate_election = .graduated },
    };
    const corrected_values = [_]SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const first = try confirmedFixture(
        "profile-correction",
        2026,
        "year-correction-1",
        1,
        try fullTaxYearPeriod(2026),
        &original_values,
    );
    const corrected = try confirmedFixture(
        "profile-correction",
        2026,
        "year-correction-2",
        2,
        try fullTaxYearPeriod(2026),
        &corrected_values,
    );
    const revisions = [_]Revision{ first, corrected };
    const history: History = .{
        .stream = first.stream,
        .revisions = &revisions,
    };
    try history.validate();
    const resolved = try history.resolveSetting(
        try Date.parseIso("2026-08-04"),
        .income_tax_rate_election,
    );
    try std.testing.expectEqual(@as(u32, 2), resolved.revision.sequence);
    try std.testing.expectEqual(
        IncomeTaxRateElection.eight_percent,
        resolved.value.income_tax_rate_election,
    );
}

test "stale optimistic conflict preserves the exact candidate" {
    const values = [_]SettingValue{
        .{ .income_tax_rate_election = .graduated },
    };
    const current = try confirmedFixture(
        "profile-maria",
        2026,
        "year-settings-1",
        1,
        try EffectivePeriod.init(
            try Date.parseIso("2026-01-01"),
            try Date.parseIso("2026-06-30"),
        ),
        &values,
    );
    const revisions = [_]Revision{current};
    const history: History = .{
        .stream = current.stream,
        .revisions = &revisions,
    };
    const candidate = try confirmedFixture(
        "profile-maria",
        2026,
        "year-settings-2",
        2,
        try EffectivePeriod.init(
            try Date.parseIso("2026-07-01"),
            try Date.parseIso("2026-12-31"),
        ),
        &values,
    );

    const result = try history.checkAppend(0, &candidate);
    switch (result) {
        .ready => return error.TestExpectedEqual,
        .stale => |conflict| {
            try std.testing.expect(conflict.candidate == &candidate);
            try std.testing.expectEqual(@as(u32, 0), conflict.expected_sequence);
            try std.testing.expectEqual(@as(u32, 1), conflict.actual_sequence);
            try std.testing.expectEqual(@as(u32, 2), conflict.candidate.sequence);
            try std.testing.expectEqualStrings(
                "year-settings-2",
                conflict.candidate.id.asSlice(),
            );
        },
    }
    try std.testing.expectError(
        error.StaleExpectedSequence,
        history.assertExpectedSequence(0),
    );
}

test "explicit prior-year copy starts review-only and confirms without losing source" {
    const values = [_]SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .optional_standard_deduction },
    };
    const source = try confirmedFixture(
        "profile-maria",
        2025,
        "year-settings-2025-1",
        1,
        try fullTaxYearPeriod(2025),
        &values,
    );
    const target_stream: StreamKey = .{
        .profile_id = source.stream.profile_id,
        .tax_year = 2026,
    };
    var copied = try copyFromPriorYear(
        try RevisionId.parse("year-settings-2026-copy-1"),
        target_stream,
        1,
        try fullTaxYearPeriod(2026),
        &source,
    );
    try std.testing.expectEqual(ReviewState.requires_review, copied.review_state);
    try std.testing.expect(copied.confirmed_at_unix_seconds == null);
    switch (copied.source) {
        .copied_from_prior_year => |copy| {
            try std.testing.expectEqual(@as(u16, 2025), copy.stream.tax_year);
            try std.testing.expectEqual(@as(u32, 1), copy.revision_sequence);
            try std.testing.expectEqualStrings(
                "year-settings-2025-1",
                copy.revision_id.asSlice(),
            );
        },
        else => return error.TestExpectedEqual,
    }

    const revisions = [_]Revision{copied};
    const history: History = .{
        .stream = target_stream,
        .revisions = &revisions,
    };
    try std.testing.expectError(
        error.EffectiveRevisionRequiresReview,
        history.confirmedEffectiveOn(try Date.parseIso("2026-03-31")),
    );

    copied.review_state = .confirmed;
    copied.confirmed_at_unix_seconds = 2;
    try copied.validate();
    const confirmed_revisions = [_]Revision{copied};
    const confirmed_history: History = .{
        .stream = target_stream,
        .revisions = &confirmed_revisions,
    };
    const resolved = try confirmed_history.resolveSetting(
        try Date.parseIso("2026-03-31"),
        .income_tax_rate_election,
    );
    try std.testing.expectEqual(ReviewState.confirmed, resolved.revision.review_state);
    switch (resolved.revision.source) {
        .copied_from_prior_year => |copy| {
            try std.testing.expectEqual(@as(u16, 2025), copy.stream.tax_year);
            try std.testing.expectEqual(@as(u32, 1), copy.revision_sequence);
            try std.testing.expectEqualStrings(
                "year-settings-2025-1",
                copy.revision_id.asSlice(),
            );
        },
        else => return error.TestExpectedEqual,
    }
}

test "missing setting is explicit and never inferred" {
    const values = [_]SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const revision = try confirmedFixture(
        "profile-maria",
        2026,
        "year-settings-1",
        1,
        try fullTaxYearPeriod(2026),
        &values,
    );
    const revisions = [_]Revision{revision};
    const history: History = .{
        .stream = revision.stream,
        .revisions = &revisions,
    };
    try std.testing.expect(revision.find(.deduction_method) == null);
    try std.testing.expectError(
        error.MissingSetting,
        history.resolveSetting(
            try Date.parseIso("2026-03-31"),
            .deduction_method,
        ),
    );
}

test "duplicate keys and wrong owners fail closed" {
    const duplicate_values = [_]SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .income_tax_rate_election = .eight_percent },
    };
    const duplicate = try confirmedFixture(
        "profile-maria",
        2026,
        "year-settings-1",
        1,
        try fullTaxYearPeriod(2026),
        &duplicate_values,
    );
    try std.testing.expectError(error.DuplicateSettingKey, duplicate.validate());

    const valid_values = [_]SettingValue{
        .{ .income_tax_rate_election = .graduated },
    };
    const owned_2025 = try confirmedFixture(
        "profile-maria",
        2025,
        "year-settings-2025-1",
        1,
        try fullTaxYearPeriod(2025),
        &valid_values,
    );
    const revisions = [_]Revision{owned_2025};
    const wrong_history: History = .{
        .stream = .{
            .profile_id = owned_2025.stream.profile_id,
            .tax_year = 2026,
        },
        .revisions = &revisions,
    };
    try std.testing.expectError(error.WrongOwner, wrong_history.validate());
}

test "taxpayer-year settings have no Tax Form Profile duplication axis" {
    const keys = std.meta.tags(SettingKey);
    try std.testing.expectEqual(@as(usize, 2), keys.len);
    try std.testing.expectEqualStrings(
        "income_tax_rate_election",
        @tagName(keys[0]),
    );
    try std.testing.expectEqualStrings("deduction_method", @tagName(keys[1]));
    try std.testing.expect(!@hasField(StreamKey, "form_code"));
    try std.testing.expect(!@hasField(StreamKey, "form_revision"));
    try std.testing.expect(!@hasField(Revision, "form_code"));
    try std.testing.expect(!@hasField(Revision, "form_revision"));
}
