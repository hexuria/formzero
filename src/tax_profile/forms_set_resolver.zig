//! Pure date-effective Forms Set policy.
//!
//! A filing is governed by the Forms Set effective at the end of its taxable
//! period, not by whichever set happens to be open in the UI. Monthly filings
//! resolve on month-end, quarterly filings on quarter-end, annual filings on
//! December 31, and on-demand filings on their explicit occurrence date.
//!
//! This module deliberately performs no persistence. Store adapters supply a
//! whole-year base set and zero or more append-only From-date intervals; every
//! card, launch guard, calendar adapter, and export guard can then consume the
//! same `resolveAvailability` result. The persisted store's
//! `resolveFormSetOn` API can also consume `applicabilityDate` directly.

const std = @import("std");
const date_domain = @import("../domain/date.zig");
const filing_period = @import("../forms/filing_period.zig");
const catalog = @import("../forms/generated/catalog.zig");

pub const Date = date_domain.Date;
pub const EffectivePeriod = date_domain.EffectivePeriod;
pub const FilingPeriod = filing_period.FilingPeriod;

/// Persisted sentinel already used for catalog entries without a Native
/// editor revision.
pub const calendar_only_revision = "calendar-only";

pub const Error = date_domain.Error || filing_period.Error || error{
    UnknownForm,
    FormRevisionMismatch,
    CadenceMismatch,
    PeriodOutsideCatalogPolicy,
    MissingOccurrenceDate,
    OccurrenceDateOutsideTaxYear,
    TaxYearMismatch,
    InvalidFormSetShape,
    InvalidFormRegistration,
    DuplicateFormRegistration,
    InvalidIntervalSequence,
    DuplicateIntervalSequence,
    InvalidIntervalYear,
    InvalidIntervalRange,
    InvalidIntervalState,
};

/// Names intentionally match `tax_profile.store.FormSetState`; adapters must
/// map exhaustively rather than treating a missing or empty set as all forms.
pub const FormSetState = enum {
    needs_configuration,
    legacy_catalog_default,
    active_empty,
    active_nonempty,
};

pub const FormRegistration = struct {
    form_code: []const u8,
    form_revision: []const u8,

    pub fn eql(self: FormRegistration, other: FormRegistration) bool {
        return std.mem.eql(u8, self.form_code, other.form_code) and
            std.mem.eql(u8, self.form_revision, other.form_revision);
    }
};

/// Borrowed view of one exact Forms Set. Both an explicit empty set and an
/// unreviewed legacy catalog default stay fail-closed. Only a saved explicit
/// non-empty set can make a filing actionable.
pub const FormSet = struct {
    state: FormSetState,
    forms: []const FormRegistration,

    pub fn validate(self: FormSet) Error!void {
        switch (self.state) {
            .needs_configuration,
            .legacy_catalog_default,
            .active_empty,
            => if (self.forms.len != 0) return error.InvalidFormSetShape,
            .active_nonempty => if (self.forms.len == 0)
                return error.InvalidFormSetShape,
        }
        for (self.forms, 0..) |form, index| {
            if (std.mem.trim(u8, form.form_code, " \t\r\n").len == 0 or
                std.mem.trim(u8, form.form_revision, " \t\r\n").len == 0)
            {
                return error.InvalidFormRegistration;
            }
            for (self.forms[index + 1 ..]) |other| {
                if (form.eql(other)) return error.DuplicateFormRegistration;
            }
        }
    }

    pub fn containsExact(
        self: FormSet,
        form: FormRegistration,
    ) bool {
        return switch (self.state) {
            .needs_configuration,
            .legacy_catalog_default,
            .active_empty,
            => false,
            .active_nonempty => blk: {
                for (self.forms) |candidate| {
                    if (candidate.eql(form)) break :blk true;
                }
                break :blk false;
            },
        };
    }
};

pub const WholeYearFormSet = struct {
    tax_year: u16,
    form_set: FormSet,
};

/// A persisted From-date override. `effective.until == null` means the end of
/// `tax_year`, never an unbounded cross-year interval.
pub const Interval = struct {
    sequence: u32,
    tax_year: u16,
    effective: EffectivePeriod,
    form_set: FormSet,

    pub fn validate(self: Interval) Error!void {
        if (self.sequence == 0) return error.InvalidIntervalSequence;
        if (self.tax_year == 0 or self.effective.from.year != self.tax_year) {
            return error.InvalidIntervalYear;
        }
        if (self.effective.until) |until| {
            if (until.year != self.tax_year) return error.InvalidIntervalYear;
            if (until.isBefore(self.effective.from)) {
                return error.InvalidIntervalRange;
            }
        }
        switch (self.form_set.state) {
            .active_empty, .active_nonempty => {},
            .needs_configuration, .legacy_catalog_default => return error.InvalidIntervalState,
        }
        try self.form_set.validate();
    }

    pub fn contains(self: Interval, on: Date) bool {
        if (on.year != self.tax_year) return false;
        if (on.isBefore(self.effective.from)) return false;
        if (self.effective.until) |until| return !on.isAfter(until);
        return true;
    }
};

pub const FilingQuery = struct {
    form: FormRegistration,
    period: FilingPeriod,
    /// Required only for `.on_demand`; ignored for recurring periods.
    occurrence_date: ?Date = null,
};

pub const ResolutionSource = union(enum) {
    whole_year,
    interval: u32,
};

pub const Resolution = struct {
    applicability_date: Date,
    source: ResolutionSource,
    form_set: FormSet,
};

pub const Availability = struct {
    applicability_date: Date,
    source: ResolutionSource,
    form_set_state: FormSetState,
    active: bool,
};

/// Convert a filing period to the one date on which Forms Set membership is
/// resolved. This is the policy boundary callers must use before invoking
/// `Store.resolveFormSetOn`.
pub fn applicabilityDate(query: FilingQuery) Error!Date {
    const definition = catalog.findForm(query.form.form_code) orelse
        return error.UnknownForm;
    if (catalogRegistration(query.form) == null) {
        return error.FormRevisionMismatch;
    }
    try query.period.validate();
    if (query.period.cadence() != definition.cadence) {
        return error.CadenceMismatch;
    }
    try validateCatalogPeriod(definition, query.period);

    return switch (query.period) {
        .monthly => |period| Date.init(
            period.tax_year,
            period.month,
            daysInMonth(period.tax_year, period.month),
        ),
        .quarterly => |period| blk: {
            const month: u8 = period.quarter * 3;
            break :blk Date.init(
                period.tax_year,
                month,
                daysInMonth(period.tax_year, month),
            );
        },
        .annual => |period| Date.init(period.tax_year, 12, 31),
        .on_demand => |period| blk: {
            const occurrence = query.occurrence_date orelse
                return error.MissingOccurrenceDate;
            if (occurrence.year != period.tax_year) {
                return error.OccurrenceDateOutsideTaxYear;
            }
            break :blk occurrence;
        },
    };
}

/// Resolve a whole-year base and its From-date overrides on one civil date.
/// The highest sequence covering the date wins, matching the persisted query;
/// equal covering sequences are rejected as ambiguous corruption. Valid store
/// writes already reject overlapping intervals.
pub fn resolveOnDate(
    base: WholeYearFormSet,
    intervals: []const Interval,
    on: Date,
) Error!Resolution {
    if (base.tax_year == 0 or base.tax_year != on.year) {
        return error.TaxYearMismatch;
    }
    try base.form_set.validate();

    var selected: ?*const Interval = null;
    for (intervals) |*interval| {
        try interval.validate();
        if (!interval.contains(on)) continue;
        if (selected) |current| {
            if (current.sequence == interval.sequence) {
                return error.DuplicateIntervalSequence;
            }
            if (interval.sequence > current.sequence) selected = interval;
        } else {
            selected = interval;
        }
    }

    if (selected) |interval| {
        return .{
            .applicability_date = on,
            .source = .{ .interval = interval.sequence },
            .form_set = interval.form_set,
        };
    }
    return .{
        .applicability_date = on,
        .source = .whole_year,
        .form_set = base.form_set,
    };
}

pub fn resolveForFiling(
    base: WholeYearFormSet,
    intervals: []const Interval,
    query: FilingQuery,
) Error!Resolution {
    return resolveOnDate(base, intervals, try applicabilityDate(query));
}

/// Single availability query intended for Registration cards, editor launch,
/// calendar generation, export, and new-draft guards.
pub fn resolveAvailability(
    base: WholeYearFormSet,
    intervals: []const Interval,
    query: FilingQuery,
) Error!Availability {
    const resolution = try resolveForFiling(base, intervals, query);
    return .{
        .applicability_date = resolution.applicability_date,
        .source = resolution.source,
        .form_set_state = resolution.form_set.state,
        .active = resolution.form_set.containsExact(query.form),
    };
}

fn catalogRegistration(
    form: FormRegistration,
) ?*const catalog.FormDefinition {
    const definition = catalog.findForm(form.form_code) orelse return null;
    const revision = definition.revision orelse calendar_only_revision;
    if (!std.mem.eql(u8, form.form_revision, revision)) return null;
    return definition;
}

fn validateCatalogPeriod(
    definition: *const catalog.FormDefinition,
    period: FilingPeriod,
) Error!void {
    const slot: ?u8 = switch (period) {
        .monthly => |value| value.month,
        .quarterly => |value| value.quarter,
        .annual, .on_demand => null,
    };
    if (slot) |value| {
        if (definition.min_period) |minimum| {
            if (value < minimum) return error.PeriodOutsideCatalogPolicy;
        }
        if (definition.max_period) |maximum| {
            if (value > maximum) return error.PeriodOutsideCatalogPolicy;
        }
    }
}

fn isLeapYear(year: u16) bool {
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
}

fn daysInMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

fn registered(code: []const u8, revision: []const u8) FormRegistration {
    return .{ .form_code = code, .form_revision = revision };
}

fn makeQuery(
    code: []const u8,
    revision: []const u8,
    period: FilingPeriod,
) FilingQuery {
    return .{ .form = registered(code, revision), .period = period };
}

fn date(year: u16, month: u8, day: u8) Date {
    return Date.init(year, month, day) catch unreachable;
}

test "every catalog cadence has one deterministic applicability-date policy" {
    for (catalog.forms) |definition| {
        const period: FilingPeriod = switch (definition.cadence) {
            .monthly => .{ .monthly = .{
                .tax_year = 2026,
                .month = definition.min_period orelse 1,
            } },
            .quarterly => .{ .quarterly = .{
                .tax_year = 2026,
                .quarter = definition.min_period orelse 1,
            } },
            .annual => .{ .annual = .{ .tax_year = 2026 } },
            .on_demand => .{ .on_demand = .{
                .tax_year = 2026,
                .occurrence = 1,
            } },
        };
        const revision = definition.revision orelse calendar_only_revision;
        var filing = makeQuery(definition.code, revision, period);
        if (definition.cadence == .on_demand) {
            filing.occurrence_date = date(2026, 5, 17);
        }
        const resolved = try applicabilityDate(filing);
        try std.testing.expectEqual(@as(u16, 2026), resolved.year);
        switch (definition.cadence) {
            .monthly => try std.testing.expectEqual(
                daysInMonth(2026, period.month().?),
                resolved.day,
            ),
            .quarterly => try std.testing.expectEqual(
                @as(u8, period.quarter().? * 3),
                resolved.month,
            ),
            .annual => {
                try std.testing.expectEqual(@as(u8, 12), resolved.month);
                try std.testing.expectEqual(@as(u8, 31), resolved.day);
            },
            .on_demand => try std.testing.expect(resolved.eql(date(2026, 5, 17))),
        }
    }
}

test "monthly applicability uses every Gregorian month end including leap day" {
    const month_ends = [_]u8{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    for (month_ends, 1..) |expected_day, month| {
        const resolved = try applicabilityDate(makeQuery(
            "2550M",
            calendar_only_revision,
            .{ .monthly = .{ .tax_year = 2024, .month = @intCast(month) } },
        ));
        try std.testing.expectEqual(expected_day, resolved.day);
    }
    const non_leap = try applicabilityDate(makeQuery(
        "2550M",
        calendar_only_revision,
        .{ .monthly = .{ .tax_year = 2026, .month = 2 } },
    ));
    try std.testing.expect(non_leap.eql(date(2026, 2, 28)));
}

test "quarterly annual and on-demand filings use their authoritative dates" {
    const quarter_ends = [_]Date{
        date(2026, 3, 31),
        date(2026, 6, 30),
        date(2026, 9, 30),
        date(2026, 12, 31),
    };
    for (quarter_ends, 1..) |expected, quarter| {
        const resolved = try applicabilityDate(makeQuery(
            "2550Q",
            "2024-04-ENCS",
            .{ .quarterly = .{
                .tax_year = 2026,
                .quarter = @intCast(quarter),
            } },
        ));
        try std.testing.expect(resolved.eql(expected));
    }

    const annual = try applicabilityDate(makeQuery(
        "1701",
        "2018-01-ENCS",
        .{ .annual = .{ .tax_year = 2026 } },
    ));
    try std.testing.expect(annual.eql(date(2026, 12, 31)));

    var event = makeQuery(
        "0605",
        "1999-07-ENCS",
        .{ .on_demand = .{ .tax_year = 2026, .occurrence = 4 } },
    );
    event.occurrence_date = date(2026, 8, 14);
    try std.testing.expect((try applicabilityDate(event)).eql(date(2026, 8, 14)));
}

test "applicability rejects cadence revision period and occurrence ambiguity" {
    try std.testing.expectError(
        error.CadenceMismatch,
        applicabilityDate(makeQuery(
            "2550Q",
            "2024-04-ENCS",
            .{ .annual = .{ .tax_year = 2026 } },
        )),
    );
    try std.testing.expectError(
        error.PeriodOutsideCatalogPolicy,
        applicabilityDate(makeQuery(
            "1701Q",
            "2018-01-ENCS",
            .{ .quarterly = .{ .tax_year = 2026, .quarter = 4 } },
        )),
    );
    try std.testing.expectError(
        error.FormRevisionMismatch,
        applicabilityDate(makeQuery(
            "2550Q",
            "wrong-revision",
            .{ .quarterly = .{ .tax_year = 2026, .quarter = 1 } },
        )),
    );

    var event = makeQuery(
        "0605",
        "1999-07-ENCS",
        .{ .on_demand = .{ .tax_year = 2026, .occurrence = 1 } },
    );
    try std.testing.expectError(
        error.MissingOccurrenceDate,
        applicabilityDate(event),
    );
    event.occurrence_date = date(2027, 1, 1);
    try std.testing.expectError(
        error.OccurrenceDateOutsideTaxYear,
        applicabilityDate(event),
    );
}

test "From-date activation and deactivation resolve at filing-period end" {
    const monthly_form = registered("2550M", calendar_only_revision);
    const base_forms = [_]FormRegistration{registered(
        "1601C",
        "2018-01-ENCS",
    )};
    const active_forms = [_]FormRegistration{
        base_forms[0],
        monthly_form,
    };
    const inactive_again = [_]FormRegistration{base_forms[0]};
    const base: WholeYearFormSet = .{
        .tax_year = 2026,
        .form_set = .{ .state = .active_nonempty, .forms = &base_forms },
    };
    const intervals = [_]Interval{
        .{
            .sequence = 1,
            .tax_year = 2026,
            .effective = EffectivePeriod.init(
                date(2026, 7, 1),
                date(2026, 8, 31),
            ) catch unreachable,
            .form_set = .{ .state = .active_nonempty, .forms = &active_forms },
        },
        .{
            .sequence = 2,
            .tax_year = 2026,
            .effective = EffectivePeriod.init(
                date(2026, 9, 1),
                null,
            ) catch unreachable,
            .form_set = .{ .state = .active_nonempty, .forms = &inactive_again },
        },
    };

    const june = try resolveAvailability(base, &intervals, makeQuery(
        monthly_form.form_code,
        monthly_form.form_revision,
        .{ .monthly = .{ .tax_year = 2026, .month = 6 } },
    ));
    try std.testing.expect(!june.active);
    try std.testing.expectEqual(ResolutionSource.whole_year, june.source);

    const july = try resolveAvailability(base, &intervals, makeQuery(
        monthly_form.form_code,
        monthly_form.form_revision,
        .{ .monthly = .{ .tax_year = 2026, .month = 7 } },
    ));
    try std.testing.expect(july.active);
    try std.testing.expectEqual(@as(u32, 1), july.source.interval);

    const september = try resolveAvailability(base, &intervals, makeQuery(
        monthly_form.form_code,
        monthly_form.form_revision,
        .{ .monthly = .{ .tax_year = 2026, .month = 9 } },
    ));
    try std.testing.expect(!september.active);
    try std.testing.expectEqual(@as(u32, 2), september.source.interval);
}

test "annual and quarterly queries honor the same date-effective intervals" {
    const quarterly_form = registered("2550Q", "2024-04-ENCS");
    const annual_form = registered("1701", "2018-01-ENCS");
    const interval_forms = [_]FormRegistration{ quarterly_form, annual_form };
    const base: WholeYearFormSet = .{
        .tax_year = 2026,
        .form_set = .{ .state = .active_empty, .forms = &.{} },
    };
    const intervals = [_]Interval{.{
        .sequence = 1,
        .tax_year = 2026,
        .effective = EffectivePeriod.init(date(2026, 7, 1), null) catch unreachable,
        .form_set = .{ .state = .active_nonempty, .forms = &interval_forms },
    }};

    const q2 = try resolveAvailability(base, &intervals, makeQuery(
        quarterly_form.form_code,
        quarterly_form.form_revision,
        .{ .quarterly = .{ .tax_year = 2026, .quarter = 2 } },
    ));
    try std.testing.expect(!q2.active);
    const q3 = try resolveAvailability(base, &intervals, makeQuery(
        quarterly_form.form_code,
        quarterly_form.form_revision,
        .{ .quarterly = .{ .tax_year = 2026, .quarter = 3 } },
    ));
    try std.testing.expect(q3.active);
    const annual = try resolveAvailability(base, &intervals, makeQuery(
        annual_form.form_code,
        annual_form.form_revision,
        .{ .annual = .{ .tax_year = 2026 } },
    ));
    try std.testing.expect(annual.active);
}

test "on-demand activation resolves on the actual occurrence date" {
    const event_form = registered("0605", "1999-07-ENCS");
    const interval_forms = [_]FormRegistration{event_form};
    const base: WholeYearFormSet = .{
        .tax_year = 2026,
        .form_set = .{ .state = .active_empty, .forms = &.{} },
    };
    const intervals = [_]Interval{.{
        .sequence = 1,
        .tax_year = 2026,
        .effective = EffectivePeriod.init(date(2026, 8, 10), null) catch unreachable,
        .form_set = .{ .state = .active_nonempty, .forms = &interval_forms },
    }};

    var before_query = makeQuery(
        event_form.form_code,
        event_form.form_revision,
        .{ .on_demand = .{ .tax_year = 2026, .occurrence = 1 } },
    );
    before_query.occurrence_date = date(2026, 8, 9);
    try std.testing.expect(!(try resolveAvailability(
        base,
        &intervals,
        before_query,
    )).active);

    var on_query = makeQuery(
        event_form.form_code,
        event_form.form_revision,
        .{ .on_demand = .{ .tax_year = 2026, .occurrence = 2 } },
    );
    on_query.occurrence_date = date(2026, 8, 10);
    try std.testing.expect((try resolveAvailability(
        base,
        &intervals,
        on_query,
    )).active);
}

test "all downstream consumers receive one identical availability answer" {
    const form = registered("2551Q", "2018-01-ENCS");
    const forms = [_]FormRegistration{form};
    const base: WholeYearFormSet = .{
        .tax_year = 2026,
        .form_set = .{ .state = .active_nonempty, .forms = &forms },
    };
    const filing = makeQuery(
        form.form_code,
        form.form_revision,
        .{ .quarterly = .{ .tax_year = 2026, .quarter = 3 } },
    );

    // Cards, launch, calendar, and export deliberately have no independent
    // policy input: each repeats this same central query.
    var answers: [4]Availability = undefined;
    for (&answers) |*answer| {
        answer.* = try resolveAvailability(base, &.{}, filing);
    }
    for (answers[1..]) |answer| {
        try std.testing.expectEqual(answers[0].active, answer.active);
        try std.testing.expect(answers[0].applicability_date.eql(
            answer.applicability_date,
        ));
        try std.testing.expectEqual(answers[0].source, answer.source);
    }
}

test "explicit empty stays fail closed and overlapping history uses sequence" {
    const form = registered("2551Q", "2018-01-ENCS");
    const forms = [_]FormRegistration{form};
    const base: WholeYearFormSet = .{
        .tax_year = 2026,
        .form_set = .{ .state = .active_nonempty, .forms = &forms },
    };
    const intervals = [_]Interval{
        .{
            .sequence = 1,
            .tax_year = 2026,
            .effective = EffectivePeriod.init(date(2026, 7, 1), null) catch unreachable,
            .form_set = .{ .state = .active_nonempty, .forms = &forms },
        },
        .{
            .sequence = 2,
            .tax_year = 2026,
            .effective = EffectivePeriod.init(date(2026, 8, 1), null) catch unreachable,
            .form_set = .{ .state = .active_empty, .forms = &.{} },
        },
    };
    const resolved = try resolveAvailability(base, &intervals, makeQuery(
        form.form_code,
        form.form_revision,
        .{ .quarterly = .{ .tax_year = 2026, .quarter = 3 } },
    ));
    try std.testing.expectEqual(@as(u32, 2), resolved.source.interval);
    try std.testing.expectEqual(FormSetState.active_empty, resolved.form_set_state);
    try std.testing.expect(!resolved.active);
}

test "invalid set and interval shapes are rejected without fallback" {
    const form = registered("2551Q", "2018-01-ENCS");
    const forms = [_]FormRegistration{form};
    const invalid_base: WholeYearFormSet = .{
        .tax_year = 2026,
        .form_set = .{ .state = .active_empty, .forms = &forms },
    };
    try std.testing.expectError(
        error.InvalidFormSetShape,
        resolveOnDate(invalid_base, &.{}, date(2026, 1, 1)),
    );

    const valid_base: WholeYearFormSet = .{
        .tax_year = 2026,
        .form_set = .{ .state = .active_empty, .forms = &.{} },
    };
    const invalid_interval = [_]Interval{.{
        .sequence = 0,
        .tax_year = 2026,
        .effective = EffectivePeriod.init(date(2026, 7, 1), null) catch unreachable,
        .form_set = .{ .state = .active_nonempty, .forms = &forms },
    }};
    try std.testing.expectError(
        error.InvalidIntervalSequence,
        resolveOnDate(valid_base, &invalid_interval, date(2026, 7, 1)),
    );
}
