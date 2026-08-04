//! Append-only annual income-tax-rate election lifecycle.
//!
//! The election is owned once by `(profile_id, tax_year)`.  Form 1701Q and
//! Form 2551Q are evidence sources for the same stream; neither form owns a
//! private copy.  Draft editing may append candidates, queueing reserves one
//! value, successful submission confirms it, and only a pre-transmission
//! cancellation may release the reservation.
//!
//! This module is deliberately pure.  SQLite owns atomic draft/election
//! transitions in `store.zig`; UI code must not manufacture a confirmed event.

const std = @import("std");
const date = @import("../domain/date.zig");
const field = @import("field.zig");
const model = @import("model.zig");

pub const Date = date.Date;

pub const Error = error{
    EmptyIdentifier,
    IdentifierTooLong,
    InvalidIdentifier,
    InvalidTaxYear,
    InvalidQuarter,
    InvalidSequence,
    InvalidTimestamp,
    InvalidStateShape,
    WrongOwner,
    NonContiguousSequence,
    InvalidTransition,
    StaleExpectedSequence,
    BusinessCommencementNotKnown,
    BusinessCommencesAfterTaxYear,
    FilingBeforeBusinessCommencement,
    NotInitialApplicableQuarter,
    UnsupportedFilingSource,
    ElectionConflict,
    ElectionUnresolved,
    ElectionTaxYearMismatch,
    ElectionNotConfirmedForLaterQuarter,
    ReservationOwnedByAnotherDraft,
    ReservationNotFound,
    ReviewRequired,
    ConfirmedElectionImmutable,
    MigrationEvidenceRequired,
};

fn Identifier(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const Length = std.math.IntFittingRange(0, capacity);

        bytes: [capacity]u8 = undefined,
        len: Length = 0,

        pub fn parse(raw: []const u8) Error!Self {
            const value = std.mem.trim(u8, raw, " \t\r\n");
            if (value.len == 0) return error.EmptyIdentifier;
            if (value.len > capacity) return error.IdentifierTooLong;
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

pub const FormRevision = Identifier(64);
pub const DraftId = Identifier(64);

pub const StreamKey = struct {
    profile_id: model.ProfileId,
    tax_year: u16,

    // Form activation, filing period, and amendment identity deliberately do
    // not participate in ownership. Deactivating or amending a form therefore
    // cannot replace the taxpayer's already confirmed annual choice.

    pub fn validate(self: StreamKey) Error!void {
        if (self.tax_year == 0 or self.tax_year > 9999) {
            return error.InvalidTaxYear;
        }
    }

    pub fn eql(self: *const StreamKey, other: *const StreamKey) bool {
        return self.profile_id.eql(&other.profile_id) and
            self.tax_year == other.tax_year;
    }
};

pub const Choice = enum {
    graduated,
    eight_percent,
};

pub const State = enum {
    candidate,
    reserved,
    confirmed,
    review_required,
};

pub const SourceKind = enum {
    statutory_default,
    form_1901,
    form_1905,
    form_1701q,
    form_2551q,
    migration,
    statutory_disqualification,

    pub fn isQuarterlyFiling(self: SourceKind) bool {
        return self == .form_1701q or self == .form_2551q;
    }
};

/// The tax year either begins with an already operating business, or with a
/// known commencement date.  There is no `null means January` fallback: a
/// caller that has not resolved Registration evidence must fail closed.
pub const BusinessCommencement = union(enum) {
    existing_before_tax_year,
    commenced_on: Date,
    unknown,
};

pub const Provenance = struct {
    kind: SourceKind,
    form_revision: ?FormRevision = null,
    filing_quarter: ?u8 = null,
    draft_id: ?DraftId = null,
    evidence_reference: ?field.SourceReference = null,

    pub fn validate(self: *const Provenance, state: State) Error!void {
        if (self.filing_quarter) |quarter| try validateQuarter(quarter);
        if (self.kind.isQuarterlyFiling()) {
            if (self.form_revision == null or self.filing_quarter == null) {
                return error.InvalidStateShape;
            }
            if ((state == .reserved or state == .confirmed) and
                self.draft_id == null)
            {
                return error.InvalidStateShape;
            }
            return;
        }
        if (self.form_revision != null or self.filing_quarter != null or
            self.draft_id != null)
        {
            return error.InvalidStateShape;
        }
        switch (self.kind) {
            .form_1901,
            .form_1905,
            .migration,
            .statutory_disqualification,
            => if (self.evidence_reference == null) {
                return error.MigrationEvidenceRequired;
            },
            .statutory_default => {},
            .form_1701q, .form_2551q => unreachable,
        }
    }

    pub fn eql(self: *const Provenance, other: *const Provenance) bool {
        if (self.kind != other.kind or
            !optionalIdentifierEql(FormRevision, self.form_revision, other.form_revision) or
            self.filing_quarter != other.filing_quarter or
            !optionalIdentifierEql(DraftId, self.draft_id, other.draft_id))
        {
            return false;
        }
        if (self.evidence_reference) |*left| {
            const right = other.evidence_reference orelse return false;
            return left.eql(&right);
        }
        return other.evidence_reference == null;
    }
};

pub const Event = struct {
    stream: StreamKey,
    sequence: u32,
    state: State,
    choice: ?Choice,
    initial_applicable_quarter: u8,
    provenance: Provenance,
    occurred_at_unix_seconds: i64,

    pub fn validate(self: *const Event) Error!void {
        try self.stream.validate();
        if (self.sequence == 0) return error.InvalidSequence;
        try validateQuarter(self.initial_applicable_quarter);
        if (self.occurred_at_unix_seconds <= 0) return error.InvalidTimestamp;
        if (self.state != .review_required and self.choice == null) {
            return error.InvalidStateShape;
        }
        if (self.state == .review_required and self.provenance.kind != .migration) {
            return error.InvalidStateShape;
        }
        try self.provenance.validate(self.state);
        if (self.provenance.kind == .statutory_disqualification and
            self.sequence == 1)
        {
            return error.InvalidTransition;
        }
        if ((self.state == .reserved or self.state == .confirmed) and
            self.provenance.kind.isQuarterlyFiling() and
            self.provenance.filing_quarter.? != self.initial_applicable_quarter)
        {
            return error.NotInitialApplicableQuarter;
        }
    }
};

pub const History = struct {
    stream: StreamKey,
    events: []const Event,

    pub fn validate(self: *const History) Error!void {
        try self.stream.validate();
        for (self.events, 0..) |*event, index| {
            if (!event.stream.eql(&self.stream)) return error.WrongOwner;
            try event.validate();
            if (event.sequence != index + 1) return error.NonContiguousSequence;
            if (index != 0) try validateTransition(&self.events[index - 1], event);
        }
    }

    pub fn current(self: *const History) Error!?*const Event {
        try self.validate();
        if (self.events.len == 0) return null;
        return &self.events[self.events.len - 1];
    }

    pub fn currentSequence(self: *const History) Error!u32 {
        const event = (try self.current()) orelse return 0;
        return event.sequence;
    }
};

pub const TransitionResult = union(enum) {
    append: Event,
    idempotent: Event,
};

/// Official 2551Q Item 13 is present only on the initial applicable quarter.
/// Later-quarter screens may still explain the inherited annual choice, but
/// the form payload must omit the field itself.
pub const Item13Projection = union(enum) {
    include: Choice,
    omit_inherited: Choice,

    pub fn choice(self: Item13Projection) Choice {
        return switch (self) {
            .include, .omit_inherited => |value| value,
        };
    }

    pub fn included(self: Item13Projection) bool {
        return switch (self) {
            .include => true,
            .omit_inherited => false,
        };
    }
};

pub const CandidateInput = struct {
    stream: StreamKey,
    expected_current_sequence: u32,
    choice: Choice,
    commencement: BusinessCommencement,
    provenance: Provenance,
    occurred_at_unix_seconds: i64,
};

pub const ReservationInput = CandidateInput;

pub const ReservationFinalizationInput = struct {
    stream: StreamKey,
    expected_current_sequence: u32,
    draft_id: DraftId,
    occurred_at_unix_seconds: i64,
};

pub const EvidenceInput = struct {
    stream: StreamKey,
    expected_current_sequence: u32,
    choice: Choice,
    initial_applicable_quarter: u8,
    provenance: Provenance,
    occurred_at_unix_seconds: i64,
};

/// Evidence that the taxpayer can no longer retain an 8% election, for
/// example because the statutory VAT threshold was crossed.  This is not an
/// editable replacement: it appends a new confirmed event while retaining the
/// original election and its complete provenance in history.
pub const StatutoryDisqualificationInput = struct {
    stream: StreamKey,
    expected_current_sequence: u32,
    initial_applicable_quarter: u8,
    evidence_reference: field.SourceReference,
    occurred_at_unix_seconds: i64,
};

pub const MigrationDisposition = enum {
    unfiled_setting,
    submitted_filing,
    confirmed_filing,
    conflicting_history,
};

pub const MigrationInput = struct {
    stream: StreamKey,
    expected_current_sequence: u32,
    choice: ?Choice,
    initial_applicable_quarter: u8,
    evidence_reference: field.SourceReference,
    disposition: MigrationDisposition,
    occurred_at_unix_seconds: i64,
};

pub fn initialApplicableQuarter(
    stream: StreamKey,
    commencement: BusinessCommencement,
) Error!u8 {
    try stream.validate();
    return switch (commencement) {
        .unknown => error.BusinessCommencementNotKnown,
        .existing_before_tax_year => 1,
        .commenced_on => |value| blk: {
            if (value.year > stream.tax_year) {
                return error.BusinessCommencesAfterTaxYear;
            }
            if (value.year < stream.tax_year) break :blk 1;
            break :blk @as(u8, @intCast((value.month - 1) / 3 + 1));
        },
    };
}

/// Stages an editable value.  A quarterly form may stage it only for the
/// initial applicable quarter; later quarters inherit a confirmed choice.
pub fn stageCandidate(
    current: ?*const Event,
    input: CandidateInput,
) Error!TransitionResult {
    const initial_quarter = try initialApplicableQuarter(
        input.stream,
        input.commencement,
    );
    if (input.provenance.kind.isQuarterlyFiling()) {
        const filing_quarter = input.provenance.filing_quarter orelse
            return error.InvalidStateShape;
        if (filing_quarter < initial_quarter) {
            return error.FilingBeforeBusinessCommencement;
        }
        if (filing_quarter != initial_quarter) {
            return error.NotInitialApplicableQuarter;
        }
    }
    try input.provenance.validate(.candidate);
    if (input.occurred_at_unix_seconds <= 0) return error.InvalidTimestamp;

    if (current) |event| {
        try requireCurrent(input.stream, input.expected_current_sequence, event);
        switch (event.state) {
            .candidate => {},
            .reserved => return error.ReservationOwnedByAnotherDraft,
            .confirmed => return error.ConfirmedElectionImmutable,
            .review_required => return error.ReviewRequired,
        }
    } else try requireEmptyExpected(input.expected_current_sequence);

    const event = Event{
        .stream = input.stream,
        .sequence = input.expected_current_sequence + 1,
        .state = .candidate,
        .choice = input.choice,
        .initial_applicable_quarter = initial_quarter,
        .provenance = input.provenance,
        .occurred_at_unix_seconds = input.occurred_at_unix_seconds,
    };
    try event.validate();
    return .{ .append = event };
}

/// Reserves the election at the queue boundary.  A later-quarter draft may
/// rely on an already confirmed same-value election, but it cannot establish
/// one merely because it was filed first.
pub fn reserve(
    current: ?*const Event,
    input: ReservationInput,
) Error!TransitionResult {
    try input.stream.validate();
    try input.provenance.validate(.reserved);
    if (input.occurred_at_unix_seconds <= 0) return error.InvalidTimestamp;

    if (current) |event| {
        try requireCurrent(input.stream, input.expected_current_sequence, event);
        switch (event.state) {
            .confirmed => {
                if (event.choice != input.choice) return error.ElectionConflict;
                return .{ .idempotent = event.* };
            },
            .reserved => {
                if (event.choice != input.choice) return error.ElectionConflict;
                const requested_draft = input.provenance.draft_id.?;
                const owner_draft = event.provenance.draft_id orelse
                    return error.InvalidStateShape;
                if (!owner_draft.eql(&requested_draft)) {
                    return error.ReservationOwnedByAnotherDraft;
                }
                return .{ .idempotent = event.* };
            },
            .review_required => return error.ReviewRequired,
            .candidate => {},
        }
    } else try requireEmptyExpected(input.expected_current_sequence);

    const initial_quarter = try initialApplicableQuarter(
        input.stream,
        input.commencement,
    );
    const filing_quarter = input.provenance.filing_quarter.?;
    if (filing_quarter < initial_quarter) {
        return error.FilingBeforeBusinessCommencement;
    }
    if (filing_quarter != initial_quarter) {
        return error.NotInitialApplicableQuarter;
    }
    const event = Event{
        .stream = input.stream,
        .sequence = input.expected_current_sequence + 1,
        .state = .reserved,
        .choice = input.choice,
        .initial_applicable_quarter = initial_quarter,
        .provenance = input.provenance,
        .occurred_at_unix_seconds = input.occurred_at_unix_seconds,
    };
    try event.validate();
    return .{ .append = event };
}

pub fn confirmReservation(
    current: ?*const Event,
    input: ReservationFinalizationInput,
) Error!TransitionResult {
    const event = current orelse return error.ReservationNotFound;
    try requireCurrent(input.stream, input.expected_current_sequence, event);
    if (event.state == .confirmed) {
        const owner = event.provenance.draft_id orelse
            return error.InvalidStateShape;
        if (!owner.eql(&input.draft_id)) return error.ElectionConflict;
        return .{ .idempotent = event.* };
    }
    if (event.state == .review_required) return error.ReviewRequired;
    if (event.state != .reserved) return error.ReservationNotFound;
    const owner = event.provenance.draft_id orelse
        return error.InvalidStateShape;
    if (!owner.eql(&input.draft_id)) {
        return error.ReservationOwnedByAnotherDraft;
    }
    var confirmed = event.*;
    confirmed.sequence += 1;
    confirmed.state = .confirmed;
    confirmed.occurred_at_unix_seconds = input.occurred_at_unix_seconds;
    try confirmed.validate();
    return .{ .append = confirmed };
}

/// Returns the stream to an editable candidate.  Persistence may call this
/// only while atomically transitioning the owning queued draft to cancelled.
pub fn releaseReservation(
    current: ?*const Event,
    input: ReservationFinalizationInput,
) Error!TransitionResult {
    const event = current orelse return error.ReservationNotFound;
    try requireCurrent(input.stream, input.expected_current_sequence, event);
    if (event.state == .confirmed) return error.ConfirmedElectionImmutable;
    if (event.state == .review_required) return error.ReviewRequired;
    if (event.state != .reserved) return error.ReservationNotFound;
    const owner = event.provenance.draft_id orelse
        return error.InvalidStateShape;
    if (!owner.eql(&input.draft_id)) {
        return error.ReservationOwnedByAnotherDraft;
    }
    var candidate = event.*;
    candidate.sequence += 1;
    candidate.state = .candidate;
    candidate.occurred_at_unix_seconds = input.occurred_at_unix_seconds;
    try candidate.validate();
    return .{ .append = candidate };
}

/// Records reviewed 1901/1905 evidence.  Quarterly filing sources must pass
/// through reservation/confirmation so the draft and election are atomic.
pub fn confirmEvidence(
    current: ?*const Event,
    input: EvidenceInput,
) Error!TransitionResult {
    try validateQuarter(input.initial_applicable_quarter);
    if (input.provenance.kind != .form_1901 and
        input.provenance.kind != .form_1905 and
        input.provenance.kind != .statutory_default)
    {
        return error.UnsupportedFilingSource;
    }
    try input.provenance.validate(.confirmed);
    if (current) |event| {
        try requireCurrent(input.stream, input.expected_current_sequence, event);
        if (event.state == .confirmed) {
            if (event.choice != input.choice) return error.ElectionConflict;
            return .{ .idempotent = event.* };
        }
        if (event.state == .reserved) {
            return error.ReservationOwnedByAnotherDraft;
        }
    } else try requireEmptyExpected(input.expected_current_sequence);
    const event = Event{
        .stream = input.stream,
        .sequence = input.expected_current_sequence + 1,
        .state = .confirmed,
        .choice = input.choice,
        .initial_applicable_quarter = input.initial_applicable_quarter,
        .provenance = input.provenance,
        .occurred_at_unix_seconds = input.occurred_at_unix_seconds,
    };
    try event.validate();
    return .{ .append = event };
}

/// Appends a statutory disqualification backed by reviewed evidence.  An
/// active reservation must first be cancelled through its owning draft, and a
/// review-required history must be resolved explicitly. It cannot originate a
/// choice or promote an unlocked candidate: its predecessor must be a
/// confirmed 8% election. Replaying the exact resulting event is idempotent;
/// every other confirmed stream remains immutable.
pub fn recordStatutoryDisqualification(
    current: ?*const Event,
    input: StatutoryDisqualificationInput,
) Error!TransitionResult {
    try input.stream.validate();
    try validateQuarter(input.initial_applicable_quarter);
    if (input.occurred_at_unix_seconds <= 0) return error.InvalidTimestamp;

    const provenance = Provenance{
        .kind = .statutory_disqualification,
        .evidence_reference = input.evidence_reference,
    };
    try provenance.validate(.confirmed);

    const current_event = current orelse return error.ElectionUnresolved;
    try requireCurrent(
        input.stream,
        input.expected_current_sequence,
        current_event,
    );
    if (current_event.state == .confirmed and
        current_event.choice == .graduated and
        current_event.provenance.kind == .statutory_disqualification and
        current_event.provenance.eql(&provenance))
    {
        return .{ .idempotent = current_event.* };
    }
    switch (current_event.state) {
        .candidate => return error.ElectionUnresolved,
        .reserved => return error.ReservationOwnedByAnotherDraft,
        .review_required => return error.ReviewRequired,
        .confirmed => {},
    }
    if (current_event.choice != .eight_percent) return error.ElectionConflict;

    const event = Event{
        .stream = input.stream,
        .sequence = input.expected_current_sequence + 1,
        .state = .confirmed,
        .choice = .graduated,
        .initial_applicable_quarter = current_event.initial_applicable_quarter,
        .provenance = provenance,
        .occurred_at_unix_seconds = input.occurred_at_unix_seconds,
    };
    try event.validate();
    return .{ .append = event };
}

/// Migration is explicit about the historical evidence classification.
/// Merely finding an old settings row can produce only a candidate; it can
/// never be promoted to an immutable lock by this API.
pub fn migrate(
    current: ?*const Event,
    input: MigrationInput,
) Error!TransitionResult {
    try validateQuarter(input.initial_applicable_quarter);
    if (current) |event| {
        try requireCurrent(input.stream, input.expected_current_sequence, event);
        if (event.state == .confirmed) return error.ConfirmedElectionImmutable;
        if (event.state == .reserved) {
            return error.ReservationOwnedByAnotherDraft;
        }
    } else try requireEmptyExpected(input.expected_current_sequence);

    const state: State = switch (input.disposition) {
        .unfiled_setting => .candidate,
        .submitted_filing, .confirmed_filing => .confirmed,
        .conflicting_history => .review_required,
    };
    if (state == .review_required) {
        if (input.choice != null) return error.InvalidStateShape;
    } else if (input.choice == null) return error.InvalidStateShape;
    const event = Event{
        .stream = input.stream,
        .sequence = input.expected_current_sequence + 1,
        .state = state,
        .choice = input.choice,
        .initial_applicable_quarter = input.initial_applicable_quarter,
        .provenance = .{
            .kind = .migration,
            .evidence_reference = input.evidence_reference,
        },
        .occurred_at_unix_seconds = input.occurred_at_unix_seconds,
    };
    try event.validate();
    return .{ .append = event };
}

/// A confirmed 8% election removes only later 2551Q obligations in the same
/// tax year.  The initial applicable return and all historical filings remain.
pub fn percentageTaxReturnRequired(
    current: ?*const Event,
    quarter: u8,
) Error!bool {
    try validateQuarter(quarter);
    const event = current orelse return true;
    try event.validate();
    if (event.state != .confirmed or event.choice != .eight_percent) return true;
    return quarter <= event.initial_applicable_quarter;
}

/// Resolves the exact 2551Q Item 13 payload behavior for one filing period.
///
/// An absent or review-required stream cannot produce a return. Candidate and
/// reserved values may appear on the initial applicable quarter, but cannot
/// authorize a later-quarter filing. Only a confirmed annual value may be
/// inherited by a later quarter, where it remains available for display while
/// being explicitly omitted from the official form payload.
pub fn project2551qItem13(
    current: ?*const Event,
    tax_year: u16,
    quarter: u8,
) Error!Item13Projection {
    if (tax_year == 0 or tax_year > 9999) return error.InvalidTaxYear;
    try validateQuarter(quarter);
    const event = current orelse return error.ElectionUnresolved;
    try event.validate();
    if (event.stream.tax_year != tax_year) {
        return error.ElectionTaxYearMismatch;
    }
    if (event.state == .review_required) return error.ReviewRequired;
    const choice = event.choice orelse return error.ElectionUnresolved;
    if (quarter < event.initial_applicable_quarter) {
        return error.FilingBeforeBusinessCommencement;
    }
    if (quarter == event.initial_applicable_quarter) {
        return .{ .include = choice };
    }
    if (event.state != .confirmed) {
        return error.ElectionNotConfirmedForLaterQuarter;
    }
    return .{ .omit_inherited = choice };
}

fn requireCurrent(
    stream: StreamKey,
    expected_sequence: u32,
    current: *const Event,
) Error!void {
    try current.validate();
    if (!current.stream.eql(&stream)) return error.WrongOwner;
    if (current.sequence != expected_sequence) {
        return error.StaleExpectedSequence;
    }
}

fn requireEmptyExpected(expected_sequence: u32) Error!void {
    if (expected_sequence != 0) return error.StaleExpectedSequence;
}

fn validateTransition(previous: *const Event, next: *const Event) Error!void {
    if (!previous.stream.eql(&next.stream)) return error.WrongOwner;
    if (next.sequence != previous.sequence + 1) {
        return error.NonContiguousSequence;
    }
    switch (previous.state) {
        .candidate => if (next.state != .candidate and
            next.state != .reserved and
            next.state != .confirmed and
            next.state != .review_required)
        {
            return error.InvalidTransition;
        },
        .reserved => {
            if (next.state != .candidate and next.state != .confirmed) {
                return error.InvalidTransition;
            }
            if (next.choice != previous.choice or
                !next.provenance.eql(&previous.provenance))
            {
                return error.ElectionConflict;
            }
        },
        .confirmed => {
            const statutory_disqualification =
                previous.choice == .eight_percent and
                next.state == .confirmed and
                next.choice == .graduated and
                next.initial_applicable_quarter ==
                    previous.initial_applicable_quarter and
                next.provenance.kind == .statutory_disqualification;
            if (!statutory_disqualification) {
                return error.ConfirmedElectionImmutable;
            }
        },
        .review_required => if (next.state != .confirmed) {
            return error.ReviewRequired;
        },
    }
}

fn validateQuarter(quarter: u8) Error!void {
    if (quarter < 1 or quarter > 4) return error.InvalidQuarter;
}

fn optionalIdentifierEql(
    comptime T: type,
    left: ?T,
    right: ?T,
) bool {
    if (left) |*left_value| {
        const right_value = right orelse return false;
        return left_value.eql(&right_value);
    }
    return right == null;
}

fn testStream(profile: []const u8, year: u16) !StreamKey {
    return .{
        .profile_id = try model.ProfileId.parse(profile),
        .tax_year = year,
    };
}

fn filingProvenance(
    kind: SourceKind,
    quarter: u8,
    draft: []const u8,
) !Provenance {
    return .{
        .kind = kind,
        .form_revision = try FormRevision.parse("2018-01-ENCS"),
        .filing_quarter = quarter,
        .draft_id = try DraftId.parse(draft),
    };
}

test "initial applicable quarter fails closed and follows commencement" {
    const stream = try testStream("annual-quarter-profile", 2026);
    try std.testing.expectError(
        error.BusinessCommencementNotKnown,
        initialApplicableQuarter(stream, .unknown),
    );
    try std.testing.expectEqual(
        @as(u8, 1),
        try initialApplicableQuarter(stream, .existing_before_tax_year),
    );
    try std.testing.expectEqual(
        @as(u8, 2),
        try initialApplicableQuarter(stream, .{
            .commenced_on = try Date.parseIso("2026-05-10"),
        }),
    );
}

test "existing taxpayer cannot establish election from Q2" {
    const stream = try testStream("annual-existing-profile", 2026);
    try std.testing.expectError(
        error.NotInitialApplicableQuarter,
        stageCandidate(null, .{
            .stream = stream,
            .expected_current_sequence = 0,
            .choice = .eight_percent,
            .commencement = .existing_before_tax_year,
            .provenance = try filingProvenance(
                .form_2551q,
                2,
                "draft-q2-candidate",
            ),
            .occurred_at_unix_seconds = 1,
        }),
    );
    try std.testing.expectError(
        error.NotInitialApplicableQuarter,
        reserve(null, .{
            .stream = stream,
            .expected_current_sequence = 0,
            .choice = .eight_percent,
            .commencement = .existing_before_tax_year,
            .provenance = try filingProvenance(
                .form_2551q,
                2,
                "draft-q2-first",
            ),
            .occurred_at_unix_seconds = 1,
        }),
    );
}

test "Q2 commencement can reserve then confirm a shared annual election" {
    const stream = try testStream("annual-new-business", 2026);
    const reserved = (try reserve(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .eight_percent,
        .commencement = .{
            .commenced_on = try Date.parseIso("2026-04-02"),
        },
        .provenance = try filingProvenance(
            .form_2551q,
            2,
            "draft-new-q2",
        ),
        .occurred_at_unix_seconds = 1,
    })).append;
    const confirmed = (try confirmReservation(&reserved, .{
        .stream = stream,
        .expected_current_sequence = 1,
        .draft_id = try DraftId.parse("draft-new-q2"),
        .occurred_at_unix_seconds = 2,
    })).append;
    try std.testing.expectEqual(State.confirmed, confirmed.state);
    try std.testing.expectEqual(@as(u8, 2), confirmed.initial_applicable_quarter);

    const inherited = try reserve(&confirmed, .{
        .stream = stream,
        .expected_current_sequence = 2,
        .choice = .eight_percent,
        .commencement = .{
            .commenced_on = try Date.parseIso("2026-04-02"),
        },
        .provenance = try filingProvenance(
            .form_1701q,
            3,
            "draft-1701q-q3",
        ),
        .occurred_at_unix_seconds = 3,
    });
    try std.testing.expectEqual(State.confirmed, inherited.idempotent.state);
}

test "1701Q and 2551Q cannot lock conflicting choices" {
    const stream = try testStream("annual-shared-lock", 2026);
    const reserved = (try reserve(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .eight_percent,
        .commencement = .existing_before_tax_year,
        .provenance = try filingProvenance(
            .form_2551q,
            1,
            "draft-2551q-q1",
        ),
        .occurred_at_unix_seconds = 1,
    })).append;
    try std.testing.expectError(
        error.ElectionConflict,
        reserve(&reserved, .{
            .stream = stream,
            .expected_current_sequence = 1,
            .choice = .graduated,
            .commencement = .existing_before_tax_year,
            .provenance = try filingProvenance(
                .form_1701q,
                1,
                "draft-1701q-q1",
            ),
            .occurred_at_unix_seconds = 2,
        }),
    );

    const confirmed = (try confirmReservation(&reserved, .{
        .stream = stream,
        .expected_current_sequence = 1,
        .draft_id = try DraftId.parse("draft-2551q-q1"),
        .occurred_at_unix_seconds = 3,
    })).append;
    try std.testing.expectError(
        error.ElectionConflict,
        reserve(&confirmed, .{
            .stream = stream,
            .expected_current_sequence = 2,
            .choice = .graduated,
            .commencement = .existing_before_tax_year,
            .provenance = try filingProvenance(
                .form_1701q,
                2,
                "draft-1701q-amendment",
            ),
            .occurred_at_unix_seconds = 4,
        }),
    );
}

test "statutory disqualification appends evidence without rewriting election" {
    const stream = try testStream("annual-statutory-disqualification", 2026);
    const evidence = try field.SourceReference.parse("VAT threshold evidence");
    const fabricated_origin = Event{
        .stream = stream,
        .sequence = 1,
        .state = .confirmed,
        .choice = .graduated,
        .initial_applicable_quarter = 1,
        .provenance = .{
            .kind = .statutory_disqualification,
            .evidence_reference = evidence,
        },
        .occurred_at_unix_seconds = 1,
    };
    try std.testing.expectError(
        error.InvalidTransition,
        fabricated_origin.validate(),
    );
    try std.testing.expectError(
        error.ElectionUnresolved,
        recordStatutoryDisqualification(null, .{
            .stream = stream,
            .expected_current_sequence = 0,
            .initial_applicable_quarter = 1,
            .evidence_reference = evidence,
            .occurred_at_unix_seconds = 1,
        }),
    );
    const unlocked = (try stageCandidate(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .eight_percent,
        .commencement = .existing_before_tax_year,
        .provenance = try filingProvenance(
            .form_2551q,
            1,
            "draft-unlocked-threshold",
        ),
        .occurred_at_unix_seconds = 1,
    })).append;
    try std.testing.expectError(
        error.ElectionUnresolved,
        recordStatutoryDisqualification(&unlocked, .{
            .stream = stream,
            .expected_current_sequence = 1,
            .initial_applicable_quarter = 1,
            .evidence_reference = evidence,
            .occurred_at_unix_seconds = 2,
        }),
    );
    const reserved = (try reserve(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .eight_percent,
        .commencement = .existing_before_tax_year,
        .provenance = try filingProvenance(
            .form_2551q,
            1,
            "draft-before-threshold",
        ),
        .occurred_at_unix_seconds = 1,
    })).append;
    try std.testing.expectError(
        error.ReservationOwnedByAnotherDraft,
        recordStatutoryDisqualification(&reserved, .{
            .stream = stream,
            .expected_current_sequence = 1,
            .initial_applicable_quarter = 1,
            .evidence_reference = evidence,
            .occurred_at_unix_seconds = 2,
        }),
    );
    const confirmed = (try confirmReservation(&reserved, .{
        .stream = stream,
        .expected_current_sequence = 1,
        .draft_id = try DraftId.parse("draft-before-threshold"),
        .occurred_at_unix_seconds = 3,
    })).append;
    const disqualified = (try recordStatutoryDisqualification(&confirmed, .{
        .stream = stream,
        .expected_current_sequence = 2,
        .initial_applicable_quarter = 4,
        .evidence_reference = evidence,
        .occurred_at_unix_seconds = 4,
    })).append;
    try std.testing.expectEqual(State.confirmed, disqualified.state);
    try std.testing.expectEqual(Choice.graduated, disqualified.choice.?);
    try std.testing.expectEqual(
        SourceKind.statutory_disqualification,
        disqualified.provenance.kind,
    );
    try std.testing.expectEqual(
        confirmed.initial_applicable_quarter,
        disqualified.initial_applicable_quarter,
    );
    const history = History{
        .stream = stream,
        .events = &.{ reserved, confirmed, disqualified },
    };
    try history.validate();

    const replay = try recordStatutoryDisqualification(&disqualified, .{
        .stream = stream,
        .expected_current_sequence = 3,
        .initial_applicable_quarter = 4,
        .evidence_reference = evidence,
        .occurred_at_unix_seconds = 5,
    });
    try std.testing.expectEqual(@as(u32, 3), replay.idempotent.sequence);
}

test "only owning pre-transmission draft can release reservation" {
    const stream = try testStream("annual-release", 2026);
    const reserved = (try reserve(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .graduated,
        .commencement = .existing_before_tax_year,
        .provenance = try filingProvenance(
            .form_1701q,
            1,
            "draft-owner",
        ),
        .occurred_at_unix_seconds = 1,
    })).append;
    try std.testing.expectError(
        error.ReservationOwnedByAnotherDraft,
        releaseReservation(&reserved, .{
            .stream = stream,
            .expected_current_sequence = 1,
            .draft_id = try DraftId.parse("draft-other"),
            .occurred_at_unix_seconds = 2,
        }),
    );
    const released = (try releaseReservation(&reserved, .{
        .stream = stream,
        .expected_current_sequence = 1,
        .draft_id = try DraftId.parse("draft-owner"),
        .occurred_at_unix_seconds = 2,
    })).append;
    try std.testing.expectEqual(State.candidate, released.state);

    const confirmed = (try confirmReservation(&reserved, .{
        .stream = stream,
        .expected_current_sequence = 1,
        .draft_id = try DraftId.parse("draft-owner"),
        .occurred_at_unix_seconds = 3,
    })).append;
    try std.testing.expectError(
        error.ConfirmedElectionImmutable,
        releaseReservation(&confirmed, .{
            .stream = stream,
            .expected_current_sequence = 2,
            .draft_id = try DraftId.parse("draft-owner"),
            .occurred_at_unix_seconds = 4,
        }),
    );
}

test "unfiled migration remains candidate and conflicts require review" {
    const stream = try testStream("annual-migration", 2026);
    const evidence = try field.SourceReference.parse("legacy settings row 17");
    const candidate = (try migrate(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .eight_percent,
        .initial_applicable_quarter = 1,
        .evidence_reference = evidence,
        .disposition = .unfiled_setting,
        .occurred_at_unix_seconds = 1,
    })).append;
    try std.testing.expectEqual(State.candidate, candidate.state);

    const review = (try migrate(&candidate, .{
        .stream = stream,
        .expected_current_sequence = 1,
        .choice = null,
        .initial_applicable_quarter = 1,
        .evidence_reference = try field.SourceReference.parse(
            "conflicting filed evidence",
        ),
        .disposition = .conflicting_history,
        .occurred_at_unix_seconds = 2,
    })).append;
    try std.testing.expectEqual(State.review_required, review.state);
}

test "confirmed eight percent suppresses only later 2551Q obligations" {
    const stream = try testStream("annual-suppression", 2026);
    const reserved = (try reserve(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .eight_percent,
        .commencement = .{
            .commenced_on = try Date.parseIso("2026-04-01"),
        },
        .provenance = try filingProvenance(
            .form_2551q,
            2,
            "draft-suppression",
        ),
        .occurred_at_unix_seconds = 1,
    })).append;
    const confirmed = (try confirmReservation(&reserved, .{
        .stream = stream,
        .expected_current_sequence = 1,
        .draft_id = try DraftId.parse("draft-suppression"),
        .occurred_at_unix_seconds = 2,
    })).append;
    try std.testing.expect(try percentageTaxReturnRequired(&confirmed, 2));
    try std.testing.expect(!try percentageTaxReturnRequired(&confirmed, 3));
    try std.testing.expect(!try percentageTaxReturnRequired(&confirmed, 4));

    var graduated = confirmed;
    graduated.choice = .graduated;
    try std.testing.expect(try percentageTaxReturnRequired(&graduated, 2));
    try std.testing.expect(try percentageTaxReturnRequired(&graduated, 3));
    try std.testing.expect(try percentageTaxReturnRequired(&graduated, 4));
}

test "confirmed choice is immutable while later amendment drafts inherit it" {
    const stream = try testStream("annual-confirmed-immutable", 2026);
    const reserved = (try reserve(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .graduated,
        .commencement = .existing_before_tax_year,
        .provenance = try filingProvenance(
            .form_2551q,
            1,
            "draft-original-q1",
        ),
        .occurred_at_unix_seconds = 1,
    })).append;
    const confirmed = (try confirmReservation(&reserved, .{
        .stream = stream,
        .expected_current_sequence = 1,
        .draft_id = try DraftId.parse("draft-original-q1"),
        .occurred_at_unix_seconds = 2,
    })).append;

    const inherited = try reserve(&confirmed, .{
        .stream = stream,
        .expected_current_sequence = 2,
        .choice = .graduated,
        .commencement = .existing_before_tax_year,
        .provenance = try filingProvenance(
            .form_1701q,
            2,
            "draft-amendment-q2",
        ),
        .occurred_at_unix_seconds = 3,
    });
    try std.testing.expectEqual(State.confirmed, inherited.idempotent.state);
    try std.testing.expect(
        inherited.idempotent.provenance.eql(&confirmed.provenance),
    );

    try std.testing.expectError(
        error.ConfirmedElectionImmutable,
        stageCandidate(&confirmed, .{
            .stream = stream,
            .expected_current_sequence = 2,
            .choice = .eight_percent,
            .commencement = .existing_before_tax_year,
            .provenance = try filingProvenance(
                .form_2551q,
                1,
                "draft-attempted-replacement",
            ),
            .occurred_at_unix_seconds = 4,
        }),
    );
    try std.testing.expectError(
        error.ConfirmedElectionImmutable,
        migrate(&confirmed, .{
            .stream = stream,
            .expected_current_sequence = 2,
            .choice = .eight_percent,
            .initial_applicable_quarter = 1,
            .evidence_reference = try field.SourceReference.parse(
                "deactivation-reactivation-import",
            ),
            .disposition = .confirmed_filing,
            .occurred_at_unix_seconds = 5,
        }),
    );
}

test "same taxpayer begins each tax year on an independent stream" {
    const prior_stream = try testStream("annual-independent-year", 2026);
    const next_stream = try testStream("annual-independent-year", 2027);
    try std.testing.expect(!prior_stream.eql(&next_stream));

    const prior_reserved = (try reserve(null, .{
        .stream = prior_stream,
        .expected_current_sequence = 0,
        .choice = .eight_percent,
        .commencement = .existing_before_tax_year,
        .provenance = try filingProvenance(
            .form_2551q,
            1,
            "draft-2026",
        ),
        .occurred_at_unix_seconds = 1,
    })).append;
    const prior_confirmed = (try confirmReservation(&prior_reserved, .{
        .stream = prior_stream,
        .expected_current_sequence = 1,
        .draft_id = try DraftId.parse("draft-2026"),
        .occurred_at_unix_seconds = 2,
    })).append;

    const next_reserved = (try reserve(null, .{
        .stream = next_stream,
        .expected_current_sequence = 0,
        .choice = .graduated,
        .commencement = .existing_before_tax_year,
        .provenance = try filingProvenance(
            .form_1701q,
            1,
            "draft-2027",
        ),
        .occurred_at_unix_seconds = 3,
    })).append;
    try std.testing.expectEqual(Choice.eight_percent, prior_confirmed.choice.?);
    try std.testing.expectEqual(Choice.graduated, next_reserved.choice.?);
    try std.testing.expectError(
        error.ElectionTaxYearMismatch,
        project2551qItem13(&prior_confirmed, 2027, 1),
    );
}

test "late Q1 establishes Item 13 and later quarters inherit without projecting it" {
    const stream = try testStream("annual-late-q1-item-13", 2026);
    const reserved = (try reserve(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .eight_percent,
        .commencement = .existing_before_tax_year,
        .provenance = try filingProvenance(
            .form_2551q,
            1,
            "draft-late-q1",
        ),
        .occurred_at_unix_seconds = 1,
    })).append;
    const confirmed = (try confirmReservation(&reserved, .{
        .stream = stream,
        .expected_current_sequence = 1,
        .draft_id = try DraftId.parse("draft-late-q1"),
        .occurred_at_unix_seconds = 2,
    })).append;

    const q1 = try project2551qItem13(&confirmed, 2026, 1);
    try std.testing.expect(q1.included());
    try std.testing.expectEqual(Choice.eight_percent, q1.choice());

    const q2 = try project2551qItem13(&confirmed, 2026, 2);
    try std.testing.expect(!q2.included());
    try std.testing.expectEqual(Choice.eight_percent, q2.choice());

    const inherited = try reserve(&confirmed, .{
        .stream = stream,
        .expected_current_sequence = 2,
        .choice = .eight_percent,
        .commencement = .existing_before_tax_year,
        .provenance = try filingProvenance(
            .form_1701q,
            2,
            "draft-q2-after-late-q1",
        ),
        .occurred_at_unix_seconds = 3,
    });
    try std.testing.expectEqual(State.confirmed, inherited.idempotent.state);
}

test "Q2 commencement projects Item 13 in Q2 and fails closed later until confirmed" {
    const stream = try testStream("annual-q2-item-13", 2026);
    const candidate = (try stageCandidate(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .graduated,
        .commencement = .{
            .commenced_on = try Date.parseIso("2026-04-02"),
        },
        .provenance = try filingProvenance(
            .form_2551q,
            2,
            "draft-q2-candidate",
        ),
        .occurred_at_unix_seconds = 1,
    })).append;

    const q2 = try project2551qItem13(&candidate, 2026, 2);
    try std.testing.expect(q2.included());
    try std.testing.expectEqual(Choice.graduated, q2.choice());
    try std.testing.expectError(
        error.FilingBeforeBusinessCommencement,
        project2551qItem13(&candidate, 2026, 1),
    );
    try std.testing.expectError(
        error.ElectionNotConfirmedForLaterQuarter,
        project2551qItem13(&candidate, 2026, 3),
    );
}

test "unresolved annual election cannot manufacture Item 13" {
    try std.testing.expectError(
        error.ElectionUnresolved,
        project2551qItem13(null, 2026, 1),
    );
}
