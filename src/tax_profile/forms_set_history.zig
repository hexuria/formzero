//! Allocation-free, append-only Forms Set decision history.
//!
//! A decision stream is keyed by the exact taxpayer profile, tax year, form
//! code, and form revision. One confirmed whole-year decision supplies the
//! baseline. Confirmed interval decisions may override that baseline, but may
//! not overlap each other: every date must have at most one interval answer.
//!
//! Imported and Certificate of Registration (COR) decisions are proposals.
//! They require review and never become authoritative merely because they were
//! appended. Confirming or rejecting a proposal appends a manual decision that
//! supersedes it. Correcting a confirmed manual decision follows the same
//! append-only rule; no record is edited or deleted.

const std = @import("std");
const date_domain = @import("../domain/date.zig");
const profile_model = @import("model.zig");

pub const Date = date_domain.Date;
pub const EffectivePeriod = date_domain.EffectivePeriod;
pub const ProfileId = profile_model.ProfileId;
pub const DecisionId = profile_model.RevisionId;

pub const Error = error{
    InvalidTaxYear,
    InvalidFormIdentity,
    InvalidDate,
    EffectiveDateOutsideTaxYear,
    InvalidEffectiveRange,
    InvalidScope,
    InvalidEvidenceReference,
    SourceRequiresReview,
    InvalidManualReviewState,
    DuplicateDecisionId,
    DecisionNotFound,
    WrongSupersessionIdentity,
    WrongSupersessionPeriod,
    AlreadySuperseded,
    InvalidSupersessionTransition,
    DuplicateWholeYearDecision,
    OverlappingIntervalDecision,
    ConflictingIntervalDecision,
    BufferFull,
    SequenceOverflow,
    TaxYearMismatch,
};

pub const FormIdentity = struct {
    code: []const u8,
    revision: []const u8,

    pub fn eql(self: FormIdentity, other: FormIdentity) bool {
        return std.mem.eql(u8, self.code, other.code) and
            std.mem.eql(u8, self.revision, other.revision);
    }

    fn validate(self: FormIdentity) Error!void {
        if (std.mem.trim(u8, self.code, " \t\r\n").len == 0 or
            std.mem.trim(u8, self.revision, " \t\r\n").len == 0)
        {
            return error.InvalidFormIdentity;
        }
    }
};

/// Exact decision-stream identity. Form revisions are deliberately part of
/// the key: a decision for 1701Q:2018 says nothing about a later revision.
pub const StreamIdentity = struct {
    profile_id: ProfileId,
    tax_year: u16,
    form: FormIdentity,

    pub fn eql(self: *const StreamIdentity, other: *const StreamIdentity) bool {
        return self.profile_id.eql(&other.profile_id) and
            self.tax_year == other.tax_year and
            self.form.eql(other.form);
    }

    fn validate(self: StreamIdentity) Error!void {
        if (self.tax_year == 0) return error.InvalidTaxYear;
        try self.form.validate();
    }
};

pub const DecisionState = enum {
    active,
    inactive,
};

pub const DecisionScope = enum {
    /// The baseline for dates not covered by a confirmed interval decision.
    whole_year,
    /// A bounded or rest-of-year override of the whole-year baseline.
    interval,
};

pub const DecisionSource = enum {
    manual,
    imported,
    cor,
};

pub const ReviewState = enum {
    /// Authoritative for availability resolution.
    confirmed,
    /// A non-authoritative proposal awaiting a manual decision.
    review_required,
    /// A retained manual rejection of a proposal.
    rejected,
};

/// Borrowed append command. The caller retains ownership of form strings and
/// the optional evidence reference for as long as the history is used.
pub const DecisionInput = struct {
    id: DecisionId,
    stream: StreamIdentity,
    state: DecisionState,
    scope: DecisionScope,
    effective: EffectivePeriod,
    source: DecisionSource,
    evidence_reference: ?[]const u8 = null,
    review: ReviewState,
    supersedes: ?DecisionId = null,
};

pub const Decision = struct {
    id: DecisionId,
    sequence: u32,
    stream: StreamIdentity,
    state: DecisionState,
    scope: DecisionScope,
    effective: EffectivePeriod,
    source: DecisionSource,
    evidence_reference: ?[]const u8,
    review: ReviewState,
    supersedes: ?DecisionId,

    pub fn authoritative(self: *const Decision) bool {
        return self.review == .confirmed;
    }

    pub fn appliesOn(self: *const Decision, on: Date) bool {
        if (on.year != self.stream.tax_year) return false;
        if (on.isBefore(self.effective.from)) return false;
        return !on.isAfter(effectiveEnd(self.effective, self.stream.tax_year));
    }
};

pub const Availability = enum {
    unconfigured,
    active,
    inactive,
};

pub const Resolution = struct {
    availability: Availability,
    /// The confirmed current decision that supplied `availability`.
    decision: ?*const Decision,
    /// True when at least one current proposal covers this date. The proposal
    /// never changes the authoritative answer.
    review_required: bool,
};

/// One contiguous, fully confirmed active segment selected for a page or
/// other year-level action. `viewed_on` is guaranteed to lie inside
/// `effective`; callers must use that same date for Registration, profile,
/// readiness, and setup resolution instead of silently substituting year-end.
pub const ActiveSegment = struct {
    viewed_on: Date,
    effective: EffectivePeriod,
};

/// The selected active segment plus its immediately adjacent active segments.
/// Segment ordinals are deliberately not persisted: inserting or reviewing a
/// Forms Set interval can change their order. Callers route with the returned
/// date and persist only the exact derived effective period.
pub const ActiveSegmentWindow = struct {
    selected: ActiveSegment,
    previous: ?ActiveSegment,
    next: ?ActiveSegment,
};

/// Caller-owned fixed-capacity history. `init` never allocates, and `append`
/// performs every validation before modifying `storage` or `len`.
pub const History = struct {
    storage: []Decision,
    len: usize = 0,

    pub fn init(storage: []Decision) History {
        return .{ .storage = storage };
    }

    pub fn records(self: *const History) []const Decision {
        return self.storage[0..self.len];
    }

    pub fn append(self: *History, input: DecisionInput) Error!*const Decision {
        if (self.len == self.storage.len) return error.BufferFull;
        if (self.len >= std.math.maxInt(u32)) return error.SequenceOverflow;
        try validateInput(input);

        for (self.records()) |*record| {
            if (record.id.eql(&input.id)) return error.DuplicateDecisionId;
        }

        const superseded_index = if (input.supersedes) |id|
            try self.validateSupersession(input, id)
        else
            null;

        if (input.review == .confirmed) {
            try self.validateAuthoritativePlacement(input, superseded_index);
        }

        const index = self.len;
        self.storage[index] = .{
            .id = input.id,
            .sequence = @intCast(index + 1),
            .stream = input.stream,
            .state = input.state,
            .scope = input.scope,
            .effective = input.effective,
            .source = input.source,
            .evidence_reference = input.evidence_reference,
            .review = input.review,
            .supersedes = input.supersedes,
        };
        self.len += 1;
        return &self.storage[index];
    }

    /// Resolves only the exact stream supplied by the caller. A current
    /// interval wins over the whole-year baseline; proposals merely set the
    /// independent `review_required` flag.
    pub fn resolve(
        self: *const History,
        stream: StreamIdentity,
        on: Date,
    ) Error!Resolution {
        try stream.validate();
        try validateDate(on);
        if (on.year != stream.tax_year) return error.TaxYearMismatch;

        var baseline: ?*const Decision = null;
        var interval: ?*const Decision = null;
        var review_required = false;

        for (self.records(), 0..) |*record, index| {
            if (!record.stream.eql(&stream) or
                self.isSupersededIndex(index) or
                !record.appliesOn(on))
            {
                continue;
            }
            switch (record.review) {
                .review_required => review_required = true,
                .rejected => {},
                .confirmed => switch (record.scope) {
                    .whole_year => baseline = record,
                    .interval => interval = record,
                },
            }
        }

        const selected = interval orelse baseline;
        return .{
            .availability = if (selected) |decision|
                switch (decision.state) {
                    .active => .active,
                    .inactive => .inactive,
                }
            else
                .unconfigured,
            .decision = selected,
            .review_required = review_required,
        };
    }

    /// Prefer an exact requested date when it is authoritatively active.
    /// Otherwise select the latest confirmed active day in the tax year.
    /// The returned interval is the maximal contiguous active segment around
    /// that day after all whole-year and interval decisions are resolved.
    pub fn preferredActiveSegment(
        self: *const History,
        stream: StreamIdentity,
        preferred: ?Date,
    ) Error!?ActiveSegment {
        try stream.validate();
        if (preferred) |date| {
            try validateDate(date);
            if (date.year != stream.tax_year) return error.TaxYearMismatch;
        }

        var viewed_on = preferred orelse yearEnd(stream.tax_year);
        if (!try self.authoritativelyActiveOn(stream, viewed_on)) {
            viewed_on = yearEnd(stream.tax_year);
            while (!try self.authoritativelyActiveOn(stream, viewed_on)) {
                viewed_on = previousDate(viewed_on) orelse return null;
            }
        }

        return try self.activeSegmentAround(stream, viewed_on);
    }

    /// Resolves the preferred segment and the prior/next fully confirmed
    /// active segments in the same exact stream. Historical active intervals
    /// remain reachable without manufacturing a segment ID or widening the
    /// form-revision identity.
    pub fn activeSegmentWindow(
        self: *const History,
        stream: StreamIdentity,
        preferred: ?Date,
    ) Error!?ActiveSegmentWindow {
        const selected = (try self.preferredActiveSegment(
            stream,
            preferred,
        )) orelse return null;
        return .{
            .selected = selected,
            .previous = try self.activeSegmentBefore(stream, selected),
            .next = try self.activeSegmentAfter(stream, selected),
        };
    }

    fn activeSegmentBefore(
        self: *const History,
        stream: StreamIdentity,
        selected: ActiveSegment,
    ) Error!?ActiveSegment {
        var candidate = previousDate(selected.effective.from);
        while (candidate) |date| {
            if (try self.authoritativelyActiveOn(stream, date)) {
                return try self.activeSegmentAround(stream, date);
            }
            candidate = previousDate(date);
        }
        return null;
    }

    fn activeSegmentAfter(
        self: *const History,
        stream: StreamIdentity,
        selected: ActiveSegment,
    ) Error!?ActiveSegment {
        const selected_end = selected.effective.until orelse
            yearEnd(stream.tax_year);
        var candidate = nextDate(selected_end);
        while (candidate) |date| {
            if (try self.authoritativelyActiveOn(stream, date)) {
                return try self.activeSegmentAround(stream, date);
            }
            candidate = nextDate(date);
        }
        return null;
    }

    fn activeSegmentAround(
        self: *const History,
        stream: StreamIdentity,
        viewed_on: Date,
    ) Error!ActiveSegment {
        if (!try self.authoritativelyActiveOn(stream, viewed_on)) {
            return error.InvalidEffectiveRange;
        }
        var first = viewed_on;
        while (previousDate(first)) |candidate| {
            if (!try self.authoritativelyActiveOn(stream, candidate)) break;
            first = candidate;
        }
        var last = viewed_on;
        while (nextDate(last)) |candidate| {
            if (!try self.authoritativelyActiveOn(stream, candidate)) break;
            last = candidate;
        }
        return .{
            .viewed_on = viewed_on,
            // Expansion moves monotonically away from `viewed_on`, so this
            // range is already ordered and needs no second fallible parse.
            .effective = .{ .from = first, .until = last },
        };
    }

    fn authoritativelyActiveOn(
        self: *const History,
        stream: StreamIdentity,
        on: Date,
    ) Error!bool {
        const resolution = try self.resolve(stream, on);
        return resolution.availability == .active and
            !resolution.review_required;
    }

    pub fn isSuperseded(self: *const History, id: DecisionId) bool {
        const index = self.findIndex(id) orelse return false;
        return self.isSupersededIndex(index);
    }

    fn validateSupersession(
        self: *const History,
        input: DecisionInput,
        supersedes: DecisionId,
    ) Error!usize {
        const target_index = self.findIndex(supersedes) orelse
            return error.DecisionNotFound;
        const target = &self.storage[target_index];
        if (self.isSupersededIndex(target_index)) {
            return error.AlreadySuperseded;
        }
        if (!target.stream.eql(&input.stream)) {
            return error.WrongSupersessionIdentity;
        }
        if (target.scope != input.scope or
            !periodsEqualWithinYear(
                target.effective,
                input.effective,
                input.stream.tax_year,
            ))
        {
            return error.WrongSupersessionPeriod;
        }
        if (input.source != .manual) {
            return error.InvalidSupersessionTransition;
        }

        switch (target.review) {
            .review_required => {
                if (input.review != .confirmed and input.review != .rejected) {
                    return error.InvalidSupersessionTransition;
                }
                // Review confirms or rejects the proposal as recorded; a user
                // choosing another answer rejects it and appends that answer
                // as a separate manual decision.
                if (input.state != target.state) {
                    return error.InvalidSupersessionTransition;
                }
            },
            .confirmed => if (input.review != .confirmed)
                return error.InvalidSupersessionTransition,
            .rejected => return error.InvalidSupersessionTransition,
        }
        return target_index;
    }

    fn validateAuthoritativePlacement(
        self: *const History,
        input: DecisionInput,
        superseded_index: ?usize,
    ) Error!void {
        for (self.records(), 0..) |*record, index| {
            if (superseded_index != null and superseded_index.? == index) {
                continue;
            }
            if (!record.authoritative() or self.isSupersededIndex(index) or
                !record.stream.eql(&input.stream))
            {
                continue;
            }

            if (input.scope == .whole_year and record.scope == .whole_year) {
                return error.DuplicateWholeYearDecision;
            }
            if (input.scope != .interval or record.scope != .interval) {
                // A baseline and an interval intentionally overlap; the
                // interval is the more specific answer.
                continue;
            }
            if (!periodsOverlapWithinYear(
                input.effective,
                record.effective,
                input.stream.tax_year,
            )) {
                continue;
            }
            if (input.state == record.state) {
                return error.OverlappingIntervalDecision;
            }
            return error.ConflictingIntervalDecision;
        }
    }

    fn findIndex(self: *const History, id: DecisionId) ?usize {
        for (self.records(), 0..) |*record, index| {
            if (record.id.eql(&id)) return index;
        }
        return null;
    }

    fn isSupersededIndex(self: *const History, target_index: usize) bool {
        const target = &self.storage[target_index];
        for (self.records()) |*record| {
            const supersedes = record.supersedes orelse continue;
            if (supersedes.eql(&target.id)) return true;
        }
        return false;
    }
};

fn validateInput(input: DecisionInput) Error!void {
    try input.stream.validate();
    try validateDate(input.effective.from);
    if (input.effective.until) |until| try validateDate(until);
    if (input.effective.from.year != input.stream.tax_year or
        (input.effective.until != null and
            input.effective.until.?.year != input.stream.tax_year))
    {
        return error.EffectiveDateOutsideTaxYear;
    }
    if (input.effective.until) |until| {
        if (until.isBefore(input.effective.from)) {
            return error.InvalidEffectiveRange;
        }
    }

    const year_start = Date{
        .year = input.stream.tax_year,
        .month = 1,
        .day = 1,
    };
    const whole_year = input.effective.from.eql(year_start) and
        effectiveEnd(input.effective, input.stream.tax_year).eql(
            yearEnd(input.stream.tax_year),
        );
    switch (input.scope) {
        .whole_year => if (!whole_year) return error.InvalidScope,
        .interval => if (whole_year) return error.InvalidScope,
    }

    if (input.evidence_reference) |reference| {
        if (std.mem.trim(u8, reference, " \t\r\n").len == 0) {
            return error.InvalidEvidenceReference;
        }
    }
    switch (input.source) {
        .manual => if (input.review == .review_required)
            return error.InvalidManualReviewState,
        .imported, .cor => if (input.review != .review_required)
            return error.SourceRequiresReview,
    }
    if (input.review == .rejected and input.supersedes == null) {
        return error.InvalidSupersessionTransition;
    }
}

fn validateDate(date: Date) Error!void {
    _ = Date.init(date.year, date.month, date.day) catch
        return error.InvalidDate;
}

fn yearEnd(tax_year: u16) Date {
    return .{ .year = tax_year, .month = 12, .day = 31 };
}

fn effectiveEnd(period: EffectivePeriod, tax_year: u16) Date {
    return period.until orelse yearEnd(tax_year);
}

fn previousDate(value: Date) ?Date {
    if (value.day > 1) {
        return Date.init(value.year, value.month, value.day - 1) catch null;
    }
    if (value.month == 1) return null;
    const month = value.month - 1;
    return Date.init(value.year, month, daysInMonth(value.year, month)) catch
        null;
}

fn nextDate(value: Date) ?Date {
    const last_day = daysInMonth(value.year, value.month);
    if (value.day < last_day) {
        return Date.init(value.year, value.month, value.day + 1) catch null;
    }
    if (value.month == 12) return null;
    return Date.init(value.year, value.month + 1, 1) catch null;
}

fn daysInMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

fn isLeapYear(year: u16) bool {
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
}

fn periodsEqualWithinYear(
    left: EffectivePeriod,
    right: EffectivePeriod,
    tax_year: u16,
) bool {
    return left.from.eql(right.from) and
        effectiveEnd(left, tax_year).eql(effectiveEnd(right, tax_year));
}

fn periodsOverlapWithinYear(
    left: EffectivePeriod,
    right: EffectivePeriod,
    tax_year: u16,
) bool {
    return !effectiveEnd(left, tax_year).isBefore(right.from) and
        !effectiveEnd(right, tax_year).isBefore(left.from);
}

fn profileId(raw: []const u8) !ProfileId {
    return ProfileId.parse(raw);
}

fn decisionId(raw: []const u8) !DecisionId {
    return DecisionId.parse(raw);
}

fn testStream(
    profile: ProfileId,
    tax_year: u16,
    form_code: []const u8,
    form_revision: []const u8,
) StreamIdentity {
    return .{
        .profile_id = profile,
        .tax_year = tax_year,
        .form = .{ .code = form_code, .revision = form_revision },
    };
}

fn testPeriod(from: []const u8, until: ?[]const u8) !EffectivePeriod {
    return .{
        .from = try Date.parseIso(from),
        .until = if (until) |value| try Date.parseIso(value) else null,
    };
}

fn testInput(
    id: []const u8,
    identity: StreamIdentity,
    state: DecisionState,
    scope: DecisionScope,
    effective: EffectivePeriod,
) !DecisionInput {
    return .{
        .id = try decisionId(id),
        .stream = identity,
        .state = state,
        .scope = scope,
        .effective = effective,
        .source = .manual,
        .review = .confirmed,
    };
}

test "deactivate and reactivate preserve all decisions and resolve intervals" {
    var storage: [8]Decision = undefined;
    var history = History.init(&storage);
    const identity = testStream(try profileId("profile-1"), 2026, "2551Q", "2018");

    _ = try history.append(try testInput(
        "base-active",
        identity,
        .active,
        .whole_year,
        try testPeriod("2026-01-01", null),
    ));
    _ = try history.append(try testInput(
        "deactivate-q3",
        identity,
        .inactive,
        .interval,
        try testPeriod("2026-07-01", "2026-09-30"),
    ));
    _ = try history.append(try testInput(
        "reactivate-q4",
        identity,
        .active,
        .interval,
        try testPeriod("2026-10-01", null),
    ));

    try std.testing.expectEqual(
        Availability.active,
        (try history.resolve(identity, try Date.parseIso("2026-06-30"))).availability,
    );
    try std.testing.expectEqual(
        Availability.inactive,
        (try history.resolve(identity, try Date.parseIso("2026-08-15"))).availability,
    );
    try std.testing.expectEqual(
        Availability.active,
        (try history.resolve(identity, try Date.parseIso("2026-12-31"))).availability,
    );
    try std.testing.expectEqual(@as(usize, 3), history.records().len);

    const first_segment = (try history.preferredActiveSegment(
        identity,
        try Date.parseIso("2026-06-15"),
    )).?;
    try std.testing.expect(
        first_segment.viewed_on.eql(try Date.parseIso("2026-06-15")),
    );
    try std.testing.expect(
        first_segment.effective.from.eql(try Date.parseIso("2026-01-01")),
    );
    try std.testing.expect(
        first_segment.effective.until.?.eql(
            try Date.parseIso("2026-06-30"),
        ),
    );

    const latest_segment = (try history.preferredActiveSegment(
        identity,
        try Date.parseIso("2026-08-15"),
    )).?;
    try std.testing.expect(
        latest_segment.viewed_on.eql(try Date.parseIso("2026-12-31")),
    );
    try std.testing.expect(
        latest_segment.effective.from.eql(try Date.parseIso("2026-10-01")),
    );
    try std.testing.expect(
        latest_segment.effective.until.?.eql(
            try Date.parseIso("2026-12-31"),
        ),
    );

    const first_window = (try history.activeSegmentWindow(
        identity,
        try Date.parseIso("2026-06-15"),
    )).?;
    try std.testing.expect(first_window.previous == null);
    try std.testing.expect(
        first_window.selected.effective.eql(first_segment.effective),
    );
    try std.testing.expect(
        first_window.next.?.effective.eql(latest_segment.effective),
    );

    const latest_window = (try history.activeSegmentWindow(
        identity,
        try Date.parseIso("2026-08-15"),
    )).?;
    try std.testing.expect(
        latest_window.previous.?.effective.eql(first_segment.effective),
    );
    try std.testing.expect(
        latest_window.selected.effective.eql(latest_segment.effective),
    );
    try std.testing.expect(latest_window.next == null);
}

test "midyear changes reject overlapping and conflicting intervals atomically" {
    var storage: [6]Decision = undefined;
    var history = History.init(&storage);
    const identity = testStream(try profileId("profile-1"), 2026, "1701Q", "2018");

    _ = try history.append(try testInput(
        "first-midyear",
        identity,
        .active,
        .interval,
        try testPeriod("2026-04-01", "2026-06-30"),
    ));
    try std.testing.expectError(
        error.OverlappingIntervalDecision,
        history.append(try testInput(
            "same-state-overlap",
            identity,
            .active,
            .interval,
            try testPeriod("2026-06-30", "2026-07-31"),
        )),
    );
    try std.testing.expectError(
        error.ConflictingIntervalDecision,
        history.append(try testInput(
            "different-state-overlap",
            identity,
            .inactive,
            .interval,
            try testPeriod("2026-06-01", "2026-08-31"),
        )),
    );
    try std.testing.expectEqual(@as(usize, 1), history.records().len);
}

test "pending import preserves confirmed manual decision" {
    var storage: [6]Decision = undefined;
    var history = History.init(&storage);
    const identity = testStream(try profileId("profile-1"), 2026, "2551Q", "2018");

    _ = try history.append(try testInput(
        "manual-active",
        identity,
        .active,
        .whole_year,
        try testPeriod("2026-01-01", null),
    ));
    const proposal_id = try decisionId("import-inactive");
    _ = try history.append(.{
        .id = proposal_id,
        .stream = identity,
        .state = .inactive,
        .scope = .whole_year,
        .effective = try testPeriod("2026-01-01", null),
        .source = .imported,
        .evidence_reference = "import:registration-2026.csv#row-2",
        .review = .review_required,
    });

    const resolved = try history.resolve(identity, try Date.parseIso("2026-08-01"));
    try std.testing.expectEqual(Availability.active, resolved.availability);
    try std.testing.expect(resolved.review_required);

    var confirmation = try testInput(
        "confirm-import",
        identity,
        .inactive,
        .whole_year,
        try testPeriod("2026-01-01", null),
    );
    confirmation.supersedes = proposal_id;
    try std.testing.expectError(
        error.DuplicateWholeYearDecision,
        history.append(confirmation),
    );
    try std.testing.expectEqual(@as(usize, 2), history.records().len);
}

test "import and COR decisions require review" {
    var storage: [4]Decision = undefined;
    var history = History.init(&storage);
    const identity = testStream(try profileId("profile-1"), 2026, "1701Q", "2018");
    const effective = try testPeriod("2026-01-01", null);

    var imported = try testInput(
        "invalid-import",
        identity,
        .active,
        .whole_year,
        effective,
    );
    imported.source = .imported;
    try std.testing.expectError(error.SourceRequiresReview, history.append(imported));

    _ = try history.append(.{
        .id = try decisionId("cor-proposal"),
        .stream = identity,
        .state = .active,
        .scope = .whole_year,
        .effective = effective,
        .source = .cor,
        .evidence_reference = "cor:sha256:abc123",
        .review = .review_required,
    });
    const resolved = try history.resolve(identity, try Date.parseIso("2026-03-31"));
    try std.testing.expectEqual(Availability.unconfigured, resolved.availability);
    try std.testing.expect(resolved.review_required);
}

test "manual supersession retains immutable decision history" {
    var storage: [4]Decision = undefined;
    var history = History.init(&storage);
    const identity = testStream(try profileId("profile-1"), 2026, "2551Q", "2018");
    const original_id = try decisionId("original-base");

    _ = try history.append(.{
        .id = original_id,
        .stream = identity,
        .state = .active,
        .scope = .whole_year,
        .effective = try testPeriod("2026-01-01", null),
        .source = .manual,
        .review = .confirmed,
    });
    var correction = try testInput(
        "corrected-base",
        identity,
        .inactive,
        .whole_year,
        try testPeriod("2026-01-01", "2026-12-31"),
    );
    correction.supersedes = original_id;
    _ = try history.append(correction);

    try std.testing.expect(history.isSuperseded(original_id));
    try std.testing.expectEqual(@as(usize, 2), history.records().len);
    try std.testing.expectEqual(
        Availability.inactive,
        (try history.resolve(identity, try Date.parseIso("2026-12-31"))).availability,
    );
    try std.testing.expectEqualStrings(
        "original-base",
        history.records()[0].id.asSlice(),
    );
}

test "exact form revision identity never widens availability" {
    var storage: [4]Decision = undefined;
    var history = History.init(&storage);
    const profile = try profileId("profile-1");
    const revision_2018 = testStream(profile, 2026, "1701Q", "2018");
    const revision_2024 = testStream(profile, 2026, "1701Q", "2024");

    _ = try history.append(try testInput(
        "active-2018",
        revision_2018,
        .active,
        .whole_year,
        try testPeriod("2026-01-01", null),
    ));
    try std.testing.expectEqual(
        Availability.active,
        (try history.resolve(revision_2018, try Date.parseIso("2026-03-31"))).availability,
    );
    try std.testing.expectEqual(
        Availability.unconfigured,
        (try history.resolve(revision_2024, try Date.parseIso("2026-03-31"))).availability,
    );
}

test "review resolution is append-only and can be rejected" {
    var storage: [4]Decision = undefined;
    var history = History.init(&storage);
    const identity = testStream(try profileId("profile-1"), 2026, "2551Q", "2018");
    const proposal_id = try decisionId("proposal");
    const effective = try testPeriod("2026-07-01", null);

    _ = try history.append(.{
        .id = proposal_id,
        .stream = identity,
        .state = .inactive,
        .scope = .interval,
        .effective = effective,
        .source = .imported,
        .review = .review_required,
    });
    _ = try history.append(.{
        .id = try decisionId("reject-proposal"),
        .stream = identity,
        .state = .inactive,
        .scope = .interval,
        .effective = effective,
        .source = .manual,
        .review = .rejected,
        .supersedes = proposal_id,
    });

    try std.testing.expectEqual(@as(usize, 2), history.records().len);
    try std.testing.expect(history.isSuperseded(proposal_id));
    const resolved = try history.resolve(identity, try Date.parseIso("2026-08-01"));
    try std.testing.expectEqual(Availability.unconfigured, resolved.availability);
    try std.testing.expect(!resolved.review_required);
}
