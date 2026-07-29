//! Pure BIR tax-calendar domain.
//!
//! Recurring rules are compiled into this module. Runtime configuration is
//! limited to an explicitly supplied business-day calendar and sourced
//! deadline overrides. The module performs no I/O, owns no global mutable
//! state, and returns a single allocator-owned result slice.

const std = @import("std");

pub const unknown_form_code = "UNKNOWN";

pub const DateError = error{
    InvalidYear,
    InvalidMonth,
    InvalidDay,
    InvalidIsoDate,
};

/// Gregorian civil date. Years are intentionally bounded to the four-digit
/// range used by persisted ISO dates and calendar-provider payloads.
pub const Date = struct {
    year: i32,
    month: u8,
    day: u8,

    pub fn init(year: i32, month: u8, day: u8) DateError!Date {
        if (year < 1 or year > 9999) return error.InvalidYear;
        if (month < 1 or month > 12) return error.InvalidMonth;
        if (day < 1 or day > daysInMonth(year, month)) return error.InvalidDay;
        return .{ .year = year, .month = month, .day = day };
    }

    pub fn parseIso(value: []const u8) DateError!Date {
        if (value.len != 10 or value[4] != '-' or value[7] != '-') {
            return error.InvalidIsoDate;
        }
        const year = parseDigits(value[0..4]) orelse return error.InvalidIsoDate;
        const month = parseDigits(value[5..7]) orelse return error.InvalidIsoDate;
        const day = parseDigits(value[8..10]) orelse return error.InvalidIsoDate;
        return init(
            @intCast(year),
            std.math.cast(u8, month) orelse return error.InvalidIsoDate,
            std.math.cast(u8, day) orelse return error.InvalidIsoDate,
        ) catch return error.InvalidIsoDate;
    }

    /// Writes `YYYY-MM-DD` without allocating.
    pub fn writeIso(self: Date, buffer: *[10]u8) []const u8 {
        const year: u16 = @intCast(self.year);
        buffer[0] = digit(year / 1000);
        buffer[1] = digit((year / 100) % 10);
        buffer[2] = digit((year / 10) % 10);
        buffer[3] = digit(year % 10);
        buffer[4] = '-';
        buffer[5] = digit(self.month / 10);
        buffer[6] = digit(self.month % 10);
        buffer[7] = '-';
        buffer[8] = digit(self.day / 10);
        buffer[9] = digit(self.day % 10);
        return buffer;
    }

    pub fn compare(a: Date, b: Date) std.math.Order {
        if (a.year != b.year) return if (a.year < b.year) .lt else .gt;
        if (a.month != b.month) return if (a.month < b.month) .lt else .gt;
        if (a.day != b.day) return if (a.day < b.day) .lt else .gt;
        return .eq;
    }

    pub fn addDays(self: Date, count: i32) DateError!Date {
        return fromSerialDay(toSerialDay(self) + count);
    }

    pub fn weekday(self: Date) Weekday {
        // 1970-01-01 was Thursday. `toSerialDay` uses that date as day zero.
        return @enumFromInt(@as(u3, @intCast(@mod(toSerialDay(self) + 3, 7))));
    }

    pub fn isWeekend(self: Date) bool {
        return switch (self.weekday()) {
            .saturday, .sunday => true,
            else => false,
        };
    }

    pub fn isLeapYear(year: i32) bool {
        return @mod(year, 4) == 0 and
            (@mod(year, 100) != 0 or @mod(year, 400) == 0);
    }

    pub fn daysInMonth(year: i32, month: u8) u8 {
        return switch (month) {
            1, 3, 5, 7, 8, 10, 12 => 31,
            4, 6, 9, 11 => 30,
            2 => if (isLeapYear(year)) 29 else 28,
            else => 0,
        };
    }

    fn toSerialDay(self: Date) i64 {
        var year: i64 = self.year;
        const month: i64 = self.month;
        const day: i64 = self.day;
        year -= if (month <= 2) 1 else 0;
        const era = @divFloor(year, 400);
        const year_of_era = year - era * 400;
        const shifted_month = month + (if (month > 2) @as(i64, -3) else 9);
        const day_of_year = @divFloor(153 * shifted_month + 2, 5) + day - 1;
        const day_of_era = year_of_era * 365 +
            @divFloor(year_of_era, 4) -
            @divFloor(year_of_era, 100) +
            day_of_year;
        return era * 146_097 + day_of_era - 719_468;
    }

    fn fromSerialDay(serial: i64) DateError!Date {
        const shifted = serial + 719_468;
        const era = @divFloor(shifted, 146_097);
        const day_of_era = shifted - era * 146_097;
        const year_of_era = @divFloor(
            day_of_era -
                @divFloor(day_of_era, 1_460) +
                @divFloor(day_of_era, 36_524) -
                @divFloor(day_of_era, 146_096),
            365,
        );
        var year = year_of_era + era * 400;
        const day_of_year = day_of_era -
            (365 * year_of_era +
                @divFloor(year_of_era, 4) -
                @divFloor(year_of_era, 100));
        const shifted_month = @divFloor(5 * day_of_year + 2, 153);
        const day = day_of_year - @divFloor(153 * shifted_month + 2, 5) + 1;
        const month = shifted_month +
            (if (shifted_month < 10) @as(i64, 3) else -9);
        year += if (month <= 2) 1 else 0;
        return init(
            std.math.cast(i32, year) orelse return error.InvalidYear,
            std.math.cast(u8, month) orelse return error.InvalidMonth,
            std.math.cast(u8, day) orelse return error.InvalidDay,
        );
    }

    fn parseDigits(value: []const u8) ?u32 {
        var result: u32 = 0;
        for (value) |character| {
            if (character < '0' or character > '9') return null;
            result = result * 10 + character - '0';
        }
        return result;
    }

    fn digit(value: anytype) u8 {
        return @as(u8, @intCast(value)) + '0';
    }
};

pub const Weekday = enum(u3) {
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
    sunday,
};

pub const Period = union(enum) {
    monthly: struct {
        taxable_year: i32,
        month: u8,
    },
    quarterly: struct {
        taxable_year: i32,
        quarter: u8,
    },
    annual: struct {
        taxable_year: i32,
    },
    event_based,

    pub fn taxableYear(self: Period) ?i32 {
        return switch (self) {
            .monthly => |period| period.taxable_year,
            .quarterly => |period| period.taxable_year,
            .annual => |period| period.taxable_year,
            .event_based => null,
        };
    }

    pub fn quarter(self: Period) ?u8 {
        return switch (self) {
            .monthly => |period| ((period.month - 1) / 3) + 1,
            .quarterly => |period| period.quarter,
            .annual, .event_based => null,
        };
    }

    pub fn month(self: Period) ?u8 {
        return switch (self) {
            .monthly => |period| period.month,
            .quarterly, .annual, .event_based => null,
        };
    }

    fn matchesMonthFilter(self: Period, months: []const u8) bool {
        return switch (self) {
            .monthly => |period| containsU8(months, period.month),
            .quarterly => |period| blk: {
                const first_month = (period.quarter - 1) * 3 + 1;
                const last_month = first_month + 2;
                for (months) |candidate| {
                    if (candidate >= first_month and candidate <= last_month) break :blk true;
                }
                break :blk false;
            },
            .annual, .event_based => false,
        };
    }
};

pub const DeadlineKind = union(enum) {
    dated: struct {
        original_deadline: Date,
        final_deadline: Date,
    },
    event_based: struct {
        trigger: []const u8,
        statutory_window: []const u8,
    },
};

pub const DeadlineStatus = enum {
    normal,
    weekend_adjusted,
    holiday_adjusted,
    non_working_day_adjusted,
    extended,
    event_based,

    pub fn label(self: DeadlineStatus) []const u8 {
        return switch (self) {
            .normal => "Normal",
            .weekend_adjusted => "Weekend Adjusted",
            .holiday_adjusted => "Holiday Adjusted",
            .non_working_day_adjusted => "Non-working Day Adjusted",
            .extended => "Extended",
            .event_based => "Event Based",
        };
    }
};

pub const NonWorkingDayKind = enum {
    regular_holiday,
    local_holiday,
    special_non_working_day,
    other_closure,
};

pub const NonWorkingDay = struct {
    date: Date,
    name: []const u8,
    kind: NonWorkingDayKind,
    regions: []const []const u8 = &.{},
    source_reference: ?[]const u8 = null,

    fn adjustmentStatus(self: NonWorkingDay) DeadlineStatus {
        return switch (self.kind) {
            .regular_holiday, .local_holiday => .holiday_adjusted,
            .special_non_working_day, .other_closure => .non_working_day_adjusted,
        };
    }
};

pub const BusinessDayAdjustment = struct {
    date: Date,
    status: DeadlineStatus,
};

pub const BusinessDayCalendar = struct {
    non_working_days: []const NonWorkingDay = &.{},

    pub fn isNonWorkingDay(self: BusinessDayCalendar, date: Date) bool {
        return self.nonWorkingReason(date) != null;
    }

    pub fn isBusinessDay(self: BusinessDayCalendar, date: Date) bool {
        return self.nonWorkingReason(date) == null;
    }

    pub fn adjustToNextBusinessDay(
        self: BusinessDayCalendar,
        date: Date,
    ) DateError!BusinessDayAdjustment {
        const status = self.nonWorkingReason(date) orelse {
            return .{ .date = date, .status = .normal };
        };

        var adjusted = try date.addDays(1);
        while (self.isNonWorkingDay(adjusted)) {
            adjusted = try adjusted.addDays(1);
        }
        return .{ .date = adjusted, .status = status };
    }

    fn nonWorkingReason(
        self: BusinessDayCalendar,
        date: Date,
    ) ?DeadlineStatus {
        if (date.isWeekend()) return .weekend_adjusted;
        for (self.non_working_days) |day| {
            if (Date.compare(day.date, date) == .eq) return day.adjustmentStatus();
        }
        return null;
    }
};

pub const DeadlineOverride = struct {
    id: []const u8,
    title: []const u8,
    /// Blank sources are rejected by the resolver. A deadline change must
    /// remain attributable to a BIR issuance or other official authority.
    source_reference: []const u8,
    /// Canonical application form codes, such as `1601C` or `1701Q`.
    affected_form_codes: []const []const u8,
    original_deadline: Date,
    adjusted_deadline: Date,
    affected_regions: []const []const u8 = &.{},
    affected_taxpayer_types: []const []const u8 = &.{},
    effective_from: ?Date = null,
    effective_until: ?Date = null,
    expires_at: ?Date = null,
};

pub const ResolvedDeadline = struct {
    /// Stable identity of the compiled rule that produced this obligation.
    rule_id: []const u8,
    form_code: []const u8,
    display_form_no: []const u8,
    form_name: []const u8,
    period: Period,
    period_start: ?Date,
    period_end: ?Date,
    deadline: DeadlineKind,
    status: DeadlineStatus,
    description: []const u8,
    source_reference: ?[]const u8 = null,

    pub fn finalDeadlineDate(self: ResolvedDeadline) ?Date {
        return switch (self.deadline) {
            .dated => |dated| dated.final_deadline,
            .event_based => null,
        };
    }

    pub fn originalDeadlineDate(self: ResolvedDeadline) ?Date {
        return switch (self.deadline) {
            .dated => |dated| dated.original_deadline,
            .event_based => null,
        };
    }

    pub fn matchesPeriodFilter(
        self: ResolvedDeadline,
        months: []const u8,
        quarters: []const u8,
    ) bool {
        if (months.len == 0 and quarters.len == 0) return true;
        const month_match = months.len != 0 and self.period.matchesMonthFilter(months);
        const quarter_match = quarters.len != 0 and
            if (self.period.quarter()) |quarter|
                containsU8(quarters, quarter)
            else
                false;
        return month_match or quarter_match;
    }

    /// Filters on the actual due date rather than the underlying tax period.
    pub fn matchesDeadlineDateFilter(
        self: ResolvedDeadline,
        months: []const u8,
        quarters: []const u8,
    ) bool {
        const date = self.finalDeadlineDate() orelse
            return months.len == 0 and quarters.len == 0;
        const deadline_quarter = ((date.month - 1) / 3) + 1;
        const month_match = months.len == 0 or containsU8(months, date.month);
        const quarter_match = quarters.len == 0 or
            containsU8(quarters, deadline_quarter);
        return month_match and quarter_match;
    }

    fn applyBusinessDayCalendar(
        self: *ResolvedDeadline,
        calendar: BusinessDayCalendar,
    ) DateError!void {
        switch (self.deadline) {
            .dated => |*dated| {
                const adjustment = try calendar.adjustToNextBusinessDay(
                    dated.original_deadline,
                );
                dated.final_deadline = adjustment.date;
                self.status = adjustment.status;
            },
            .event_based => {},
        }
    }

    fn applyOverride(
        self: *ResolvedDeadline,
        deadline_override: DeadlineOverride,
        calendar: BusinessDayCalendar,
    ) DateError!bool {
        var matches_form = false;
        for (deadline_override.affected_form_codes) |form_code| {
            if (std.mem.eql(u8, form_code, self.form_code)) {
                matches_form = true;
                break;
            }
        }
        if (!matches_form) return false;

        switch (self.deadline) {
            .dated => |*dated| {
                if (Date.compare(
                    dated.original_deadline,
                    deadline_override.original_deadline,
                ) != .eq and Date.compare(
                    dated.final_deadline,
                    deadline_override.original_deadline,
                ) != .eq) {
                    return false;
                }
                const adjustment = try calendar.adjustToNextBusinessDay(
                    deadline_override.adjusted_deadline,
                );
                dated.final_deadline = adjustment.date;
                self.status = .extended;
                self.source_reference = deadline_override.source_reference;
                return true;
            },
            .event_based => return false,
        }
    }
};

pub const Frequency = enum {
    monthly,
    quarterly,
    annual,
    as_needed,
};

const Generation = enum {
    monthly_following_fifth,
    monthly_following_tenth,
    monthly_following_twentieth,
    monthly_first_two_quarter_months_following_tenth,
    monthly_withholding,
    quarterly_following_month_end,
    quarterly_1701q,
    quarterly_1702q,
    quarterly_following_twenty_fifth,
    quarterly_2550ds,
    quarterly_2200m,
    annual_january_thirty_first,
    annual_march_first,
    annual_april_fifteenth,
    annual_2316_bir_submission,
    event_based,
};

pub const OfficialRule = struct {
    rule_id: []const u8,
    form_nos: []const []const u8,
    form_name: []const u8,
    frequency: Frequency,
    description: []const u8,
    generation: Generation,
};

const monthly_tenth_forms = [_][]const u8{
    "1600-VT", "1600-PT", "2200-C",
};
const monthly_fifth_forms = [_][]const u8{"2000"};
const monthly_0620_forms = [_][]const u8{"0620"};
const monthly_0619_forms = [_][]const u8{ "0619-E", "0619-F" };
const monthly_1600wp_forms = [_][]const u8{"1600-WP"};
const monthly_1606_forms = [_][]const u8{"1606"};
const monthly_withholding_forms = [_][]const u8{"1601-C"};
const monthly_2200m_forms = [_][]const u8{"2200-M"};
const quarterly_withholding_forms = [_][]const u8{
    "1601-EQ", "1601-FQ", "1602Q", "1603Q", "1621",
};
const quarterly_1701q_forms = [_][]const u8{"1701Q"};
const quarterly_1702q_forms = [_][]const u8{"1702Q"};
const quarterly_indirect_tax_forms = [_][]const u8{
    "2550Q", "2551Q",
};
const quarterly_2550ds_forms = [_][]const u8{"2550-DS"};
const quarterly_2200m_forms = [_][]const u8{"2200-M"};
const annual_1604cf_forms = [_][]const u8{ "1604-C", "1604-F" };
const annual_1604e_forms = [_][]const u8{"1604-E"};
const annual_income_tax_forms = [_][]const u8{
    "1700",
    "1701",
    "1701A",
    "1701-MS",
    "1702-EX",
    "1702-MX",
    "1702-RT",
    "1707-A",
};
const annual_2316_forms = [_][]const u8{"2316"};
const event_based_forms = [_][]const u8{
    "2552",
    "1706",
    "1707",
    "1800",
    "1801",
    "0605",
    "0611-A",
    "0613",
    "1905",
    "2200-A",
    "2200-AN",
    "2200-M",
    "2200-P",
    "2200-S",
    "2200-T",
    "2553",
};

/// Compiled global calendar-year rule catalog. Each formula is valid for its
/// stated filer scope, but callers must still select the taxpayer's applicable
/// forms, fiscal year, and filing channel before treating it as a filing plan.
/// It is immutable and contains no year-specific holiday or extension guesses.
pub const OFFICIAL_RULES = [_]OfficialRule{
    .{
        .rule_id = "2000-monthly-following-5",
        .form_nos = &monthly_fifth_forms,
        .form_name = "Monthly Documentary Stamp Tax Return",
        .frequency = .monthly,
        .description = "Within 5 days after the close of the month",
        .generation = .monthly_following_fifth,
    },
    .{
        .rule_id = "monthly-remittance-following-10",
        .form_nos = &monthly_tenth_forms,
        .form_name = "Monthly Remittance / Excise Tax",
        .frequency = .monthly,
        .description = "10th day of the following month",
        .generation = .monthly_following_tenth,
    },
    .{
        .rule_id = "0620-first-two-quarter-months-following-10",
        .form_nos = &monthly_0620_forms,
        .form_name = "Monthly Remittance of Tax Withheld on Decedent Deposits",
        .frequency = .monthly,
        .description = "First two months of each quarter; 10th day of the following month",
        .generation = .monthly_first_two_quarter_months_following_tenth,
    },
    .{
        .rule_id = "0619-first-two-quarter-months-following-10",
        .form_nos = &monthly_0619_forms,
        .form_name = "Monthly Withholding Tax Remittance",
        .frequency = .monthly,
        .description = "First two months of each quarter; 10th day of following month (Non-eFPS)",
        .generation = .monthly_first_two_quarter_months_following_tenth,
    },
    .{
        .rule_id = "1600wp-monthly-following-20",
        .form_nos = &monthly_1600wp_forms,
        .form_name = "Monthly Remittance Return of Percentage Tax on Winnings and Prizes",
        .frequency = .monthly,
        .description = "20th day of the following month",
        .generation = .monthly_following_twentieth,
    },
    .{
        .rule_id = "1606-conditional-monthly-following-10",
        .form_nos = &monthly_1606_forms,
        .form_name = "Withholding Tax Remittance on Real Property Transactions",
        .frequency = .monthly,
        .description = "Conditional reminder for months with a real-property transaction or installment; actual filing cardinality is per transaction/installment, due on the 10th day of the following month",
        .generation = .monthly_following_tenth,
    },
    .{
        .rule_id = "1601c-following-10-december-15",
        .form_nos = &monthly_withholding_forms,
        .form_name = "Withholding Tax Remittance",
        .frequency = .monthly,
        .description = "10th day of the following month (Non-eFPS) / 15th for Dec",
        .generation = .monthly_withholding,
    },
    .{
        .rule_id = "2200m-qualified-monthly-following-10",
        .form_nos = &monthly_2200m_forms,
        .form_name = "Monthly Excise Tax Return — Metallic Mineral Collections",
        .frequency = .monthly,
        .description = "Only for excise tax collected from payments made to sellers of metallic minerals; 10th day of the following month",
        .generation = .monthly_following_tenth,
    },
    .{
        .rule_id = "quarterly-withholding-following-month-end",
        .form_nos = &quarterly_withholding_forms,
        .form_name = "Quarterly Withholding Tax",
        .frequency = .quarterly,
        .description = "Last day of the month following the close of the quarter",
        .generation = .quarterly_following_month_end,
    },
    .{
        .rule_id = "1701q-fixed-quarterly",
        .form_nos = &quarterly_1701q_forms,
        .form_name = "Quarterly Income Tax Return (Individual)",
        .frequency = .quarterly,
        .description = "Q1: May 15, Q2: Aug 15, Q3: Nov 15",
        .generation = .quarterly_1701q,
    },
    .{
        .rule_id = "1702q-quarter-end-plus-60-days",
        .form_nos = &quarterly_1702q_forms,
        .form_name = "Quarterly Income Tax Return (Corporate)",
        .frequency = .quarterly,
        .description = "60 days after the end of each quarter",
        .generation = .quarterly_1702q,
    },
    .{
        .rule_id = "quarterly-indirect-tax-following-25",
        .form_nos = &quarterly_indirect_tax_forms,
        .form_name = "Quarterly Percentage/Value-Added Tax",
        .frequency = .quarterly,
        .description = "25th day following the close of taxable quarter",
        .generation = .quarterly_following_twenty_fifth,
    },
    .{
        .rule_id = "2550ds-quarterly-following-25",
        .form_nos = &quarterly_2550ds_forms,
        .form_name = "VAT on Digital Services by Nonresident Digital Service Providers",
        .frequency = .quarterly,
        .description = "Effective June 2, 2025; 25th day following the close of taxable quarter",
        .generation = .quarterly_2550ds,
    },
    .{
        .rule_id = "2200m-quarterly-following-15",
        .form_nos = &quarterly_2200m_forms,
        .form_name = "Quarterly Excise Tax Return (Minerals)",
        .frequency = .quarterly,
        .description = "15th day following the close of calendar quarter",
        .generation = .quarterly_2200m,
    },
    .{
        .rule_id = "1604cf-annual-january-31",
        .form_nos = &annual_1604cf_forms,
        .form_name = "Annual Information Return",
        .frequency = .annual,
        .description = "January 31 following the calendar year",
        .generation = .annual_january_thirty_first,
    },
    .{
        .rule_id = "1604e-annual-march-1",
        .form_nos = &annual_1604e_forms,
        .form_name = "Annual Information Return",
        .frequency = .annual,
        .description = "March 1 following the calendar year",
        .generation = .annual_march_first,
    },
    .{
        .rule_id = "annual-income-tax-april-15",
        .form_nos = &annual_income_tax_forms,
        .form_name = "Annual Income Tax Return",
        .frequency = .annual,
        .description = "April 15 / 15th day of 4th month following taxable year",
        .generation = .annual_april_fifteenth,
    },
    .{
        .rule_id = "2316-employee-furnishing-january-31",
        .form_nos = &annual_2316_forms,
        .form_name = "Certificate of Compensation Payment — Employee Copy",
        .frequency = .annual,
        .description = "January 31 (furnish the certificate to the employee)",
        .generation = .annual_january_thirty_first,
    },
    .{
        .rule_id = "2316-bir-submission-february-28",
        .form_nos = &annual_2316_forms,
        .form_name = "Certificate of Compensation Payment — BIR Submission",
        .frequency = .annual,
        .description = "February 28 (submission to BIR)",
        .generation = .annual_2316_bir_submission,
    },
    .{
        .rule_id = "event-based-special-obligation",
        .form_nos = &event_based_forms,
        .form_name = "As Needed / Special / Event-Based",
        .frequency = .as_needed,
        .description = "Based on Special Law / Upon transaction",
        .generation = .event_based,
    },
};

pub const ResolveOptions = struct {
    calendar: BusinessDayCalendar = .{},
    overrides: []const DeadlineOverride = &.{},
};

/// Resolves obligations for a tax period year. Like the reference subsystem,
/// this includes event-based obligations after all dated deadlines.
pub fn resolveTaxableYear(
    allocator: std.mem.Allocator,
    taxable_year: i32,
    options: ResolveOptions,
) ![]ResolvedDeadline {
    var deadlines: std.ArrayList(ResolvedDeadline) = .empty;
    defer deadlines.deinit(allocator);

    for (OFFICIAL_RULES) |rule| {
        try generateRule(allocator, &deadlines, taxable_year, rule);
    }
    try applyBusinessDayCalendar(deadlines.items, options.calendar);
    try applyOverrides(deadlines.items, options.overrides, options.calendar);
    sortDeadlines(deadlines.items);
    return deadlines.toOwnedSlice(allocator);
}

/// Projects deadlines onto the year in which their final adjusted due date
/// occurs. Prior-December and prior-tax-year annual filings are included.
pub fn resolveCalendarYear(
    allocator: std.mem.Allocator,
    calendar_year: i32,
    options: ResolveOptions,
) ![]ResolvedDeadline {
    if (calendar_year <= 1 or calendar_year >= 9998) return error.InvalidYear;

    var projected: std.ArrayList(ResolvedDeadline) = .empty;
    defer projected.deinit(allocator);

    const taxable_years = [_]i32{
        calendar_year - 1,
        calendar_year,
        calendar_year + 1,
    };
    for (taxable_years) |taxable_year| {
        const taxable_deadlines = try resolveTaxableYear(
            allocator,
            taxable_year,
            options,
        );
        defer allocator.free(taxable_deadlines);
        for (taxable_deadlines) |deadline| {
            if (deadline.finalDeadlineDate()) |date| {
                if (date.year == calendar_year) {
                    try projected.append(allocator, deadline);
                }
            }
        }
    }

    sortDeadlines(projected.items);
    return projected.toOwnedSlice(allocator);
}

pub fn resolveEventBased(
    allocator: std.mem.Allocator,
) ![]ResolvedDeadline {
    var events: std.ArrayList(ResolvedDeadline) = .empty;
    defer events.deinit(allocator);
    for (OFFICIAL_RULES) |rule| {
        if (rule.frequency == .as_needed) {
            try generateRule(allocator, &events, 0, rule);
        }
    }
    sortDeadlines(events.items);
    return events.toOwnedSlice(allocator);
}

/// Resolves only obligations backed by compiled rules and selected by the
/// caller's canonical form-code set.
pub fn deadlinesForForms(
    allocator: std.mem.Allocator,
    form_codes: []const []const u8,
    taxable_year: i32,
    options: ResolveOptions,
) ![]ResolvedDeadline {
    const all = try resolveTaxableYear(allocator, taxable_year, options);
    defer allocator.free(all);

    var selected: std.ArrayList(ResolvedDeadline) = .empty;
    defer selected.deinit(allocator);
    for (all) |deadline| {
        for (form_codes) |form_code| {
            if (std.mem.eql(u8, deadline.form_code, form_code)) {
                try selected.append(allocator, deadline);
                break;
            }
        }
    }
    return selected.toOwnedSlice(allocator);
}

const CanonicalAlias = struct {
    display: []const u8,
    canonical: []const u8,
};

const canonical_aliases = [_]CanonicalAlias{
    .{ .display = "0619-E", .canonical = "0619E" },
    .{ .display = "0619E", .canonical = "0619E" },
    .{ .display = "0619-F", .canonical = "0619F" },
    .{ .display = "0619F", .canonical = "0619F" },
    .{ .display = "1600-WP", .canonical = "1600WP" },
    .{ .display = "1600WP", .canonical = "1600WP" },
    .{ .display = "1601-C", .canonical = "1601C" },
    .{ .display = "1601C", .canonical = "1601C" },
    .{ .display = "1601-EQ", .canonical = "1601EQ" },
    .{ .display = "1601EQ", .canonical = "1601EQ" },
    .{ .display = "1601-FQ", .canonical = "1601FQ" },
    .{ .display = "1601FQ", .canonical = "1601FQ" },
    .{ .display = "1604-C", .canonical = "1604C" },
    .{ .display = "1604-F", .canonical = "1604F" },
    .{ .display = "1604C", .canonical = "1604C" },
    .{ .display = "1604F", .canonical = "1604F" },
    .{ .display = "1604CF", .canonical = "1604CF" },
    .{ .display = "1604-E", .canonical = "1604E" },
    .{ .display = "1604E", .canonical = "1604E" },
    .{ .display = "1701-MS", .canonical = "1701MS" },
    .{ .display = "1701MS", .canonical = "1701MS" },
    .{ .display = "1702-EX", .canonical = "1702EX" },
    .{ .display = "1702EX", .canonical = "1702EX" },
    .{ .display = "1702-MX", .canonical = "1702MX" },
    .{ .display = "1702MX", .canonical = "1702MX" },
    .{ .display = "1702-RT", .canonical = "1702RT" },
    .{ .display = "1702RT", .canonical = "1702RT" },
    .{ .display = "1707-A", .canonical = "1707A" },
    .{ .display = "1707A", .canonical = "1707A" },
    .{ .display = "2000-OT", .canonical = "2000OT" },
    .{ .display = "2000OT", .canonical = "2000OT" },
    .{ .display = "2200-A", .canonical = "2200A" },
    .{ .display = "2200A", .canonical = "2200A" },
    .{ .display = "2200-AN", .canonical = "2200AN" },
    .{ .display = "2200AN", .canonical = "2200AN" },
    .{ .display = "2200-M", .canonical = "2200M" },
    .{ .display = "2200M", .canonical = "2200M" },
    .{ .display = "2200-S", .canonical = "2200S" },
    .{ .display = "2200S", .canonical = "2200S" },
    .{ .display = "2200-T", .canonical = "2200T" },
    .{ .display = "2200T", .canonical = "2200T" },
    .{ .display = "2550-DS", .canonical = "2550DS" },
    .{ .display = "2550DS", .canonical = "2550DS" },
    .{ .display = "1600-VT", .canonical = "1600VT" },
    .{ .display = "1600VT", .canonical = "1600VT" },
    .{ .display = "1600-PT", .canonical = "1600PT" },
    .{ .display = "1600PT", .canonical = "1600PT" },
    .{ .display = "2200-C", .canonical = "2200C" },
    .{ .display = "2200C", .canonical = "2200C" },
    .{ .display = "0611-A", .canonical = "0611A" },
    .{ .display = "0611A", .canonical = "0611A" },
    .{ .display = "0605", .canonical = "0605" },
    .{ .display = "0613", .canonical = "0613" },
    .{ .display = "0620", .canonical = "0620" },
    .{ .display = "1606", .canonical = "1606" },
    .{ .display = "1602Q", .canonical = "1602Q" },
    .{ .display = "1603Q", .canonical = "1603Q" },
    .{ .display = "1621", .canonical = "1621" },
    .{ .display = "1700", .canonical = "1700" },
    .{ .display = "1701", .canonical = "1701" },
    .{ .display = "1701A", .canonical = "1701A" },
    .{ .display = "1701Q", .canonical = "1701Q" },
    .{ .display = "1702Q", .canonical = "1702Q" },
    .{ .display = "1706", .canonical = "1706" },
    .{ .display = "1707", .canonical = "1707" },
    .{ .display = "1800", .canonical = "1800" },
    .{ .display = "1801", .canonical = "1801" },
    .{ .display = "1905", .canonical = "1905" },
    .{ .display = "2000", .canonical = "2000" },
    .{ .display = "2200-P", .canonical = "2200P" },
    .{ .display = "2200P", .canonical = "2200P" },
    .{ .display = "2316", .canonical = "2316" },
    .{ .display = "2550Q", .canonical = "2550Q" },
    .{ .display = "2551Q", .canonical = "2551Q" },
    .{ .display = "2552", .canonical = "2552" },
    .{ .display = "2553", .canonical = "2553" },
};

pub fn canonicalFormCode(display_form_no: []const u8) []const u8 {
    for (canonical_aliases) |alias| {
        if (std.mem.eql(u8, display_form_no, alias.display)) return alias.canonical;
    }
    return unknown_form_code;
}

fn generateRule(
    allocator: std.mem.Allocator,
    deadlines: *std.ArrayList(ResolvedDeadline),
    taxable_year: i32,
    rule: OfficialRule,
) !void {
    switch (rule.generation) {
        .monthly_following_fifth => {
            for (rule.form_nos) |form_no| {
                for (1..13) |month_value| {
                    const month: u8 = @intCast(month_value);
                    const following = nextMonth(taxable_year, month);
                    try appendDated(
                        allocator,
                        deadlines,
                        rule,
                        form_no,
                        .{ .monthly = .{
                            .taxable_year = taxable_year,
                            .month = month,
                        } },
                        try Date.init(taxable_year, month, 1),
                        try lastDayOfMonth(taxable_year, month),
                        try Date.init(following.year, following.month, 5),
                    );
                }
            }
        },
        .monthly_following_tenth => {
            for (rule.form_nos) |form_no| {
                for (1..13) |month_value| {
                    const month: u8 = @intCast(month_value);
                    const following = nextMonth(taxable_year, month);
                    try appendDated(
                        allocator,
                        deadlines,
                        rule,
                        form_no,
                        .{ .monthly = .{
                            .taxable_year = taxable_year,
                            .month = month,
                        } },
                        try Date.init(taxable_year, month, 1),
                        try lastDayOfMonth(taxable_year, month),
                        try Date.init(following.year, following.month, 10),
                    );
                }
            }
        },
        .monthly_following_twentieth => {
            for (rule.form_nos) |form_no| {
                for (1..13) |month_value| {
                    const month: u8 = @intCast(month_value);
                    const following = nextMonth(taxable_year, month);
                    try appendDated(
                        allocator,
                        deadlines,
                        rule,
                        form_no,
                        .{ .monthly = .{
                            .taxable_year = taxable_year,
                            .month = month,
                        } },
                        try Date.init(taxable_year, month, 1),
                        try lastDayOfMonth(taxable_year, month),
                        try Date.init(following.year, following.month, 20),
                    );
                }
            }
        },
        .monthly_first_two_quarter_months_following_tenth => {
            const filing_months = [_]u8{ 1, 2, 4, 5, 7, 8, 10, 11 };
            for (rule.form_nos) |form_no| {
                for (filing_months) |month| {
                    const following = nextMonth(taxable_year, month);
                    try appendDated(
                        allocator,
                        deadlines,
                        rule,
                        form_no,
                        .{ .monthly = .{
                            .taxable_year = taxable_year,
                            .month = month,
                        } },
                        try Date.init(taxable_year, month, 1),
                        try lastDayOfMonth(taxable_year, month),
                        try Date.init(following.year, following.month, 10),
                    );
                }
            }
        },
        .monthly_withholding => {
            for (rule.form_nos) |form_no| {
                for (1..13) |month_value| {
                    const month: u8 = @intCast(month_value);
                    const following = nextMonth(taxable_year, month);
                    const due_day: u8 = if (month == 12) 15 else 10;
                    try appendDated(
                        allocator,
                        deadlines,
                        rule,
                        form_no,
                        .{ .monthly = .{
                            .taxable_year = taxable_year,
                            .month = month,
                        } },
                        try Date.init(taxable_year, month, 1),
                        try lastDayOfMonth(taxable_year, month),
                        try Date.init(following.year, following.month, due_day),
                    );
                }
            }
        },
        .quarterly_following_month_end,
        .quarterly_1702q,
        .quarterly_following_twenty_fifth,
        .quarterly_2550ds,
        .quarterly_2200m,
        => {
            if (rule.generation == .quarterly_2550ds and taxable_year < 2025) {
                return;
            }
            for (rule.form_nos) |form_no| {
                const quarter_start: usize =
                    if (rule.generation == .quarterly_2550ds and
                    taxable_year == 2025)
                        2
                    else
                        1;
                const quarter_end: usize =
                    if (rule.generation == .quarterly_1702q) 4 else 5;
                for (quarter_start..quarter_end) |quarter_value| {
                    const quarter: u8 = @intCast(quarter_value);
                    const start_month: u8 = (quarter - 1) * 3 + 1;
                    const period_start =
                        if (rule.generation == .quarterly_2550ds and
                        taxable_year == 2025 and quarter == 2)
                            try Date.init(2025, 6, 2)
                        else
                            try Date.init(taxable_year, start_month, 1);
                    const period_end = try lastDayOfMonth(
                        taxable_year,
                        start_month + 2,
                    );
                    const following = if (quarter == 4)
                        YearMonth{ .year = taxable_year + 1, .month = 1 }
                    else
                        YearMonth{
                            .year = taxable_year,
                            .month = quarter * 3 + 1,
                        };
                    const due_date = switch (rule.generation) {
                        .quarterly_following_month_end => try lastDayOfMonth(
                            following.year,
                            following.month,
                        ),
                        .quarterly_1702q => try period_end.addDays(60),
                        .quarterly_following_twenty_fifth => try Date.init(
                            following.year,
                            following.month,
                            25,
                        ),
                        .quarterly_2550ds => try Date.init(
                            following.year,
                            following.month,
                            25,
                        ),
                        .quarterly_2200m => try Date.init(
                            following.year,
                            following.month,
                            15,
                        ),
                        else => unreachable,
                    };
                    try appendDated(
                        allocator,
                        deadlines,
                        rule,
                        form_no,
                        .{ .quarterly = .{
                            .taxable_year = taxable_year,
                            .quarter = quarter,
                        } },
                        period_start,
                        period_end,
                        due_date,
                    );
                }
            }
        },
        .quarterly_1701q => {
            const due_dates = [_]struct {
                quarter: u8,
                month: u8,
                day: u8,
            }{
                .{ .quarter = 1, .month = 5, .day = 15 },
                .{ .quarter = 2, .month = 8, .day = 15 },
                .{ .quarter = 3, .month = 11, .day = 15 },
            };
            for (rule.form_nos) |form_no| {
                for (due_dates) |due| {
                    const end_month = due.quarter * 3;
                    try appendDated(
                        allocator,
                        deadlines,
                        rule,
                        form_no,
                        .{ .quarterly = .{
                            .taxable_year = taxable_year,
                            .quarter = due.quarter,
                        } },
                        try Date.init(taxable_year, end_month - 2, 1),
                        try lastDayOfMonth(taxable_year, end_month),
                        try Date.init(taxable_year, due.month, due.day),
                    );
                }
            }
        },
        .annual_january_thirty_first,
        .annual_march_first,
        .annual_april_fifteenth,
        .annual_2316_bir_submission,
        => {
            for (rule.form_nos) |form_no| {
                const due_date = switch (rule.generation) {
                    .annual_january_thirty_first => try Date.init(
                        taxable_year + 1,
                        1,
                        31,
                    ),
                    .annual_march_first => try Date.init(
                        taxable_year + 1,
                        3,
                        1,
                    ),
                    .annual_april_fifteenth => try Date.init(
                        taxable_year + 1,
                        4,
                        15,
                    ),
                    .annual_2316_bir_submission => try Date.init(
                        taxable_year + 1,
                        2,
                        28,
                    ),
                    else => unreachable,
                };
                try appendDated(
                    allocator,
                    deadlines,
                    rule,
                    form_no,
                    .{ .annual = .{ .taxable_year = taxable_year } },
                    try Date.init(taxable_year, 1, 1),
                    try Date.init(taxable_year, 12, 31),
                    due_date,
                );
            }
        },
        .event_based => {
            for (rule.form_nos) |form_no| {
                try deadlines.append(allocator, .{
                    .rule_id = rule.rule_id,
                    .form_code = canonicalFormCode(form_no),
                    .display_form_no = form_no,
                    .form_name = rule.form_name,
                    .period = .event_based,
                    .period_start = null,
                    .period_end = null,
                    .deadline = .{ .event_based = .{
                        .trigger = "Taxpayer transaction or statutory event",
                        .statutory_window = "Depends on the specific BIR form and triggering event",
                    } },
                    .status = .event_based,
                    .description = rule.description,
                });
            }
        },
    }
}

fn appendDated(
    allocator: std.mem.Allocator,
    deadlines: *std.ArrayList(ResolvedDeadline),
    rule: OfficialRule,
    display_form_no: []const u8,
    period: Period,
    period_start: Date,
    period_end: Date,
    original_deadline: Date,
) !void {
    try deadlines.append(allocator, .{
        .rule_id = rule.rule_id,
        .form_code = canonicalFormCode(display_form_no),
        .display_form_no = display_form_no,
        .form_name = rule.form_name,
        .period = period,
        .period_start = period_start,
        .period_end = period_end,
        .deadline = .{ .dated = .{
            .original_deadline = original_deadline,
            .final_deadline = original_deadline,
        } },
        .status = .normal,
        .description = rule.description,
    });
}

fn applyBusinessDayCalendar(
    deadlines: []ResolvedDeadline,
    calendar: BusinessDayCalendar,
) DateError!void {
    for (deadlines) |*deadline| {
        try deadline.applyBusinessDayCalendar(calendar);
    }
}

fn applyOverrides(
    deadlines: []ResolvedDeadline,
    overrides: []const DeadlineOverride,
    calendar: BusinessDayCalendar,
) DateError!void {
    for (overrides) |deadline_override| {
        if (std.mem.trim(
            u8,
            deadline_override.source_reference,
            " \t\r\n",
        ).len == 0) continue;

        for (deadlines) |*deadline| {
            _ = try deadline.applyOverride(deadline_override, calendar);
        }
    }
}

fn sortDeadlines(deadlines: []ResolvedDeadline) void {
    // Stable insertion sort keeps compiled-rule order when the reference sort
    // keys are equal. The schedule is bounded by the static rules (170 entries
    // for one taxable year), making this simple deterministic sort sufficient.
    var index: usize = 1;
    while (index < deadlines.len) : (index += 1) {
        const candidate = deadlines[index];
        var insertion = index;
        while (insertion > 0 and deadlineLess(candidate, deadlines[insertion - 1])) {
            deadlines[insertion] = deadlines[insertion - 1];
            insertion -= 1;
        }
        deadlines[insertion] = candidate;
    }
}

fn deadlineLess(a: ResolvedDeadline, b: ResolvedDeadline) bool {
    const a_date = a.finalDeadlineDate();
    const b_date = b.finalDeadlineDate();
    if (a_date) |left| {
        if (b_date) |right| {
            return switch (Date.compare(left, right)) {
                .lt => true,
                .gt => false,
                .eq => std.mem.order(u8, a.form_code, b.form_code) == .lt,
            };
        }
        return true;
    }
    if (b_date != null) return false;
    return std.mem.order(u8, a.form_code, b.form_code) == .lt;
}

const YearMonth = struct {
    year: i32,
    month: u8,
};

fn nextMonth(year: i32, month: u8) YearMonth {
    return if (month == 12)
        .{ .year = year + 1, .month = 1 }
    else
        .{ .year = year, .month = month + 1 };
}

fn lastDayOfMonth(year: i32, month: u8) DateError!Date {
    return Date.init(year, month, Date.daysInMonth(year, month));
}

fn containsU8(values: []const u8, wanted: u8) bool {
    for (values) |value| {
        if (value == wanted) return true;
    }
    return false;
}

fn findDeadline(
    deadlines: []const ResolvedDeadline,
    form_code: []const u8,
    period: Period,
) ?*const ResolvedDeadline {
    for (deadlines) |*deadline| {
        if (std.mem.eql(u8, deadline.form_code, form_code) and
            std.meta.eql(deadline.period, period))
        {
            return deadline;
        }
    }
    return null;
}

fn findDeadlineByRule(
    deadlines: []const ResolvedDeadline,
    rule_id: []const u8,
    form_code: []const u8,
    period: Period,
) ?*const ResolvedDeadline {
    for (deadlines) |*deadline| {
        if (std.mem.eql(u8, deadline.rule_id, rule_id) and
            std.mem.eql(u8, deadline.form_code, form_code) and
            std.meta.eql(deadline.period, period))
        {
            return deadline;
        }
    }
    return null;
}

test "Date validates, formats, parses, and crosses leap boundaries" {
    const leap_day = try Date.init(2024, 2, 29);
    try std.testing.expectEqual(Weekday.thursday, leap_day.weekday());
    try std.testing.expectEqual(
        try Date.init(2024, 3, 1),
        try leap_day.addDays(1),
    );
    try std.testing.expectError(error.InvalidDay, Date.init(2026, 2, 29));

    var buffer: [10]u8 = undefined;
    try std.testing.expectEqualStrings("2024-02-29", leap_day.writeIso(&buffer));
    try std.testing.expectEqual(leap_day, try Date.parseIso("2024-02-29"));
    try std.testing.expectError(error.InvalidIsoDate, Date.parseIso("2024-2-29"));
}

test "calendar year includes prior taxable year annual income tax" {
    const deadlines = try resolveCalendarYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    const annual = findDeadline(
        deadlines,
        "1701",
        .{ .annual = .{ .taxable_year = 2025 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2026, 4, 15),
        annual.finalDeadlineDate().?,
    );
    try std.testing.expectEqualStrings(
        "annual-income-tax-april-15",
        annual.rule_id,
    );
}

test "calendar year includes prior December monthly deadline" {
    const deadlines = try resolveCalendarYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    const december = findDeadline(
        deadlines,
        "1601C",
        .{ .monthly = .{ .taxable_year = 2025, .month = 12 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2026, 1, 15),
        december.finalDeadlineDate().?,
    );
}

test "calendar year excludes deadlines due in the next calendar year" {
    const deadlines = try resolveCalendarYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    try std.testing.expect(findDeadline(
        deadlines,
        "1701",
        .{ .annual = .{ .taxable_year = 2026 } },
    ) == null);
    for (deadlines) |deadline| {
        try std.testing.expectEqual(@as(i32, 2026), deadline.finalDeadlineDate().?.year);
    }
}

test "1701Q preserves quarterly metadata and period filtering" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    const q1 = findDeadline(
        deadlines,
        "1701Q",
        .{ .quarterly = .{ .taxable_year = 2026, .quarter = 1 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(try Date.init(2026, 5, 15), q1.finalDeadlineDate().?);
    try std.testing.expect(q1.matchesPeriodFilter(&.{}, &.{1}));
    try std.testing.expect(!q1.matchesPeriodFilter(&.{}, &.{2}));
    try std.testing.expect(q1.matchesPeriodFilter(&.{ 1, 2, 3 }, &.{}));
    try std.testing.expect(!q1.matchesPeriodFilter(&.{4}, &.{}));
    try std.testing.expect(!q1.matchesDeadlineDateFilter(&.{1}, &.{}));
    try std.testing.expect(q1.matchesDeadlineDateFilter(&.{5}, &.{}));
}

test "1701Q third quarter is due November 15" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    const q3 = findDeadline(
        deadlines,
        "1701Q",
        .{ .quarterly = .{ .taxable_year = 2026, .quarter = 3 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2026, 11, 15),
        q3.originalDeadlineDate().?,
    );
    try std.testing.expectEqual(
        try Date.init(2026, 11, 16),
        q3.finalDeadlineDate().?,
    );
    try std.testing.expectEqual(DeadlineStatus.weekend_adjusted, q3.status);
}

test "2316 has distinct employee furnishing and BIR submission duties" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2023,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    const employee_copy = findDeadlineByRule(
        deadlines,
        "2316-employee-furnishing-january-31",
        "2316",
        .{ .annual = .{ .taxable_year = 2023 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2024, 1, 31),
        employee_copy.originalDeadlineDate().?,
    );

    const bir_submission = findDeadlineByRule(
        deadlines,
        "2316-bir-submission-february-28",
        "2316",
        .{ .annual = .{ .taxable_year = 2023 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2024, 2, 28),
        bir_submission.originalDeadlineDate().?,
    );
    try std.testing.expectEqual(
        try Date.init(2024, 2, 28),
        bir_submission.finalDeadlineDate().?,
    );
}

test "weekend adjustment preserves original deadline" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    const q2 = findDeadline(
        deadlines,
        "1701Q",
        .{ .quarterly = .{ .taxable_year = 2026, .quarter = 2 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2026, 8, 15),
        q2.originalDeadlineDate().?,
    );
    try std.testing.expectEqual(
        try Date.init(2026, 8, 17),
        q2.finalDeadlineDate().?,
    );
    try std.testing.expectEqual(DeadlineStatus.weekend_adjusted, q2.status);
}

test "business calendar moves weekend through configured Monday holiday" {
    const days = [_]NonWorkingDay{.{
        .date = try Date.init(2026, 6, 1),
        .name = "Configured Monday holiday",
        .kind = .regular_holiday,
    }};
    const adjustment = try (BusinessDayCalendar{
        .non_working_days = &days,
    }).adjustToNextBusinessDay(try Date.init(2026, 5, 30));
    try std.testing.expectEqual(try Date.init(2026, 6, 2), adjustment.date);
    try std.testing.expectEqual(DeadlineStatus.weekend_adjusted, adjustment.status);
}

test "business calendar moves Friday holiday past weekend" {
    const days = [_]NonWorkingDay{.{
        .date = try Date.init(2026, 6, 12),
        .name = "Configured Friday holiday",
        .kind = .regular_holiday,
    }};
    const adjustment = try (BusinessDayCalendar{
        .non_working_days = &days,
    }).adjustToNextBusinessDay(try Date.init(2026, 6, 12));
    try std.testing.expectEqual(try Date.init(2026, 6, 15), adjustment.date);
    try std.testing.expectEqual(DeadlineStatus.holiday_adjusted, adjustment.status);
}

test "business calendar distinguishes special non-working day" {
    const days = [_]NonWorkingDay{.{
        .date = try Date.init(2026, 11, 2),
        .name = "Configured special non-working day",
        .kind = .special_non_working_day,
    }};
    const adjustment = try (BusinessDayCalendar{
        .non_working_days = &days,
    }).adjustToNextBusinessDay(try Date.init(2026, 11, 2));
    try std.testing.expectEqual(try Date.init(2026, 11, 3), adjustment.date);
    try std.testing.expectEqual(
        DeadlineStatus.non_working_day_adjusted,
        adjustment.status,
    );
}

test "1702Q is sixty days after quarter end before weekend adjustment" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    const q1 = findDeadline(
        deadlines,
        "1702Q",
        .{ .quarterly = .{ .taxable_year = 2026, .quarter = 1 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2026, 5, 30),
        q1.originalDeadlineDate().?,
    );
    try std.testing.expectEqual(
        try Date.init(2026, 6, 1),
        q1.finalDeadlineDate().?,
    );
    try std.testing.expectEqual(DeadlineStatus.weekend_adjusted, q1.status);
    try std.testing.expect(findDeadline(
        deadlines,
        "1702Q",
        .{ .quarterly = .{ .taxable_year = 2026, .quarter = 4 } },
    ) == null);
}

test "0619 forms cover only the first two months of each quarter" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    const included_months = [_]u8{ 1, 2, 4, 5, 7, 8, 10, 11 };
    const excluded_months = [_]u8{ 3, 6, 9, 12 };
    for ([_][]const u8{ "0619E", "0619F" }) |form_code| {
        for (included_months) |month| {
            try std.testing.expect(findDeadline(
                deadlines,
                form_code,
                .{ .monthly = .{
                    .taxable_year = 2026,
                    .month = month,
                } },
            ) != null);
        }
        for (excluded_months) |month| {
            try std.testing.expect(findDeadline(
                deadlines,
                form_code,
                .{ .monthly = .{
                    .taxable_year = 2026,
                    .month = month,
                } },
            ) == null);
        }
    }
}

test "0620 covers only the first two months of each quarter" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    const included_months = [_]u8{ 1, 2, 4, 5, 7, 8, 10, 11 };
    const excluded_months = [_]u8{ 3, 6, 9, 12 };
    for (included_months) |month| {
        const deadline = findDeadline(
            deadlines,
            "0620",
            .{ .monthly = .{
                .taxable_year = 2026,
                .month = month,
            } },
        ) orelse return error.TestExpectedEqual;
        const following = nextMonth(2026, month);
        try std.testing.expectEqual(
            try Date.init(following.year, following.month, 10),
            deadline.originalDeadlineDate().?,
        );
    }
    for (excluded_months) |month| {
        try std.testing.expect(findDeadline(
            deadlines,
            "0620",
            .{ .monthly = .{
                .taxable_year = 2026,
                .month = month,
            } },
        ) == null);
    }
}

test "1600-WP is monthly due on the twentieth and not a generic event" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    for (1..13) |month_value| {
        const month: u8 = @intCast(month_value);
        const deadline = findDeadline(
            deadlines,
            "1600WP",
            .{ .monthly = .{
                .taxable_year = 2026,
                .month = month,
            } },
        ) orelse return error.TestExpectedEqual;
        const following = nextMonth(2026, month);
        try std.testing.expectEqual(
            try Date.init(following.year, following.month, 20),
            deadline.originalDeadlineDate().?,
        );
    }

    const events = try resolveEventBased(std.testing.allocator);
    defer std.testing.allocator.free(events);
    for (events) |event| {
        try std.testing.expect(!std.mem.eql(u8, event.form_code, "1600WP"));
    }
}

test "2200-M retains qualified monthly, quarterly, and event obligations" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    var monthly_count: usize = 0;
    var quarterly_count: usize = 0;
    var event_count: usize = 0;
    for (deadlines) |deadline| {
        if (!std.mem.eql(u8, deadline.form_code, "2200M")) continue;
        switch (deadline.period) {
            .monthly => {
                monthly_count += 1;
                try std.testing.expectEqualStrings(
                    "2200m-qualified-monthly-following-10",
                    deadline.rule_id,
                );
                try std.testing.expect(std.mem.startsWith(
                    u8,
                    deadline.description,
                    "Only for excise tax collected from payments made to sellers of metallic minerals",
                ));
            },
            .quarterly => {
                quarterly_count += 1;
                try std.testing.expectEqualStrings(
                    "2200m-quarterly-following-15",
                    deadline.rule_id,
                );
            },
            .event_based => event_count += 1,
            .annual => return error.TestExpectedEqual,
        }
    }
    try std.testing.expectEqual(@as(usize, 12), monthly_count);
    try std.testing.expectEqual(@as(usize, 4), quarterly_count);
    try std.testing.expectEqual(@as(usize, 1), event_count);

    const january = findDeadlineByRule(
        deadlines,
        "2200m-qualified-monthly-following-10",
        "2200M",
        .{ .monthly = .{ .taxable_year = 2026, .month = 1 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2026, 2, 10),
        january.originalDeadlineDate().?,
    );
}

test "1606 monthly rows are explicitly conditional transaction reminders" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    var count: usize = 0;
    for (deadlines) |deadline| {
        if (!std.mem.eql(u8, deadline.form_code, "1606")) continue;
        count += 1;
        try std.testing.expectEqualStrings(
            "1606-conditional-monthly-following-10",
            deadline.rule_id,
        );
        try std.testing.expect(std.mem.indexOf(
            u8,
            deadline.description,
            "actual filing cardinality is per transaction/installment",
        ) != null);
    }
    try std.testing.expectEqual(@as(usize, 12), count);
}

test "2000 is monthly and absent from generic event obligations" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    for (1..13) |month_value| {
        const month: u8 = @intCast(month_value);
        const deadline = findDeadline(
            deadlines,
            "2000",
            .{ .monthly = .{
                .taxable_year = 2026,
                .month = month,
            } },
        ) orelse return error.TestExpectedEqual;
        const following = nextMonth(2026, month);
        try std.testing.expectEqual(
            try Date.init(following.year, following.month, 5),
            deadline.originalDeadlineDate().?,
        );
    }

    const events = try resolveEventBased(std.testing.allocator);
    defer std.testing.allocator.free(events);
    for (events) |event| {
        try std.testing.expect(!std.mem.eql(u8, event.form_code, "2000"));
    }
}

test "2550-DS begins June 2 2025 and has no earlier obligations" {
    const before_effective = try resolveTaxableYear(
        std.testing.allocator,
        2024,
        .{},
    );
    defer std.testing.allocator.free(before_effective);
    for (before_effective) |deadline| {
        try std.testing.expect(!std.mem.eql(u8, deadline.form_code, "2550DS"));
    }

    const first_year = try resolveTaxableYear(
        std.testing.allocator,
        2025,
        .{},
    );
    defer std.testing.allocator.free(first_year);
    try std.testing.expect(findDeadline(
        first_year,
        "2550DS",
        .{ .quarterly = .{ .taxable_year = 2025, .quarter = 1 } },
    ) == null);

    const q2 = findDeadline(
        first_year,
        "2550DS",
        .{ .quarterly = .{ .taxable_year = 2025, .quarter = 2 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(try Date.init(2025, 6, 2), q2.period_start.?);
    try std.testing.expectEqual(try Date.init(2025, 6, 30), q2.period_end.?);
    try std.testing.expectEqual(
        try Date.init(2025, 7, 25),
        q2.originalDeadlineDate().?,
    );
    for ([_]u8{ 3, 4 }) |quarter| {
        try std.testing.expect(findDeadline(
            first_year,
            "2550DS",
            .{ .quarterly = .{
                .taxable_year = 2025,
                .quarter = quarter,
            } },
        ) != null);
    }

    const full_year = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(full_year);
    const q1 = findDeadline(
        full_year,
        "2550DS",
        .{ .quarterly = .{ .taxable_year = 2026, .quarter = 1 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(try Date.init(2026, 1, 1), q1.period_start.?);
}

test "generic 1702 annual row and alias are absent" {
    try std.testing.expectEqualStrings(
        unknown_form_code,
        canonicalFormCode("1702"),
    );

    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);
    try std.testing.expect(findDeadline(
        deadlines,
        "1702",
        .{ .annual = .{ .taxable_year = 2026 } },
    ) == null);
}

test "1604-C and 1604-F have distinct canonical identities" {
    try std.testing.expectEqualStrings("1604C", canonicalFormCode("1604-C"));
    try std.testing.expectEqualStrings("1604F", canonicalFormCode("1604-F"));

    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);
    try std.testing.expect(findDeadline(
        deadlines,
        "1604C",
        .{ .annual = .{ .taxable_year = 2026 } },
    ) != null);
    try std.testing.expect(findDeadline(
        deadlines,
        "1604F",
        .{ .annual = .{ .taxable_year = 2026 } },
    ) != null);
}

test "2200-P preserves hyphenated display and canonical identity" {
    try std.testing.expectEqualStrings("2200P", canonicalFormCode("2200-P"));

    const events = try resolveEventBased(std.testing.allocator);
    defer std.testing.allocator.free(events);
    const event = findDeadline(
        events,
        "2200P",
        .event_based,
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("2200-P", event.display_form_no);
}

test "event based obligations have stable rule and explanatory metadata" {
    const calendar = try resolveCalendarYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(calendar);
    for (calendar) |deadline| {
        try std.testing.expect(deadline.finalDeadlineDate() != null);
    }

    const events = try resolveEventBased(std.testing.allocator);
    defer std.testing.allocator.free(events);
    try std.testing.expectEqual(@as(usize, 16), events.len);

    var found_1800 = false;
    for (events) |event| {
        try std.testing.expect(event.finalDeadlineDate() == null);
        try std.testing.expectEqualStrings(
            "event-based-special-obligation",
            event.rule_id,
        );
        switch (event.deadline) {
            .event_based => |metadata| {
                try std.testing.expect(metadata.trigger.len != 0);
                try std.testing.expect(metadata.statutory_window.len != 0);
            },
            .dated => return error.TestExpectedEqual,
        }
        if (std.mem.eql(u8, event.form_code, "1800")) found_1800 = true;
    }
    try std.testing.expect(found_1800);
}

test "all official rule display codes canonicalize" {
    try std.testing.expectEqualStrings("1601C", canonicalFormCode("1601-C"));
    try std.testing.expectEqualStrings("0619E", canonicalFormCode("0619-E"));
    try std.testing.expectEqualStrings("1604C", canonicalFormCode("1604-C"));
    try std.testing.expectEqualStrings("1604F", canonicalFormCode("1604-F"));
    try std.testing.expectEqualStrings("1701MS", canonicalFormCode("1701-MS"));
    try std.testing.expectEqualStrings("1702RT", canonicalFormCode("1702-RT"));
    try std.testing.expectEqualStrings("2000OT", canonicalFormCode("2000-OT"));
    try std.testing.expectEqualStrings("2200P", canonicalFormCode("2200-P"));
    try std.testing.expectEqualStrings(unknown_form_code, canonicalFormCode("1702"));
    try std.testing.expectEqualStrings(unknown_form_code, canonicalFormCode("nope"));

    try std.testing.expectEqual(@as(usize, 20), OFFICIAL_RULES.len);
    for (OFFICIAL_RULES, 0..) |rule, index| {
        try std.testing.expect(rule.rule_id.len != 0);
        for (OFFICIAL_RULES[0..index]) |prior| {
            try std.testing.expect(!std.mem.eql(
                u8,
                prior.rule_id,
                rule.rule_id,
            ));
        }
        for (rule.form_nos) |form_no| {
            try std.testing.expect(!std.mem.eql(
                u8,
                unknown_form_code,
                canonicalFormCode(form_no),
            ));
        }
    }
}

test "taxable year has complete recurring and event-based rule coverage" {
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);
    try std.testing.expectEqual(@as(usize, 191), deadlines.len);

    var dated_count: usize = 0;
    var event_count: usize = 0;
    for (deadlines) |deadline| {
        if (deadline.finalDeadlineDate() == null)
            event_count += 1
        else
            dated_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 175), dated_count);
    try std.testing.expectEqual(@as(usize, 16), event_count);
}

test "sourced override applies after base adjustment and preserves original" {
    const affected = [_][]const u8{"1701Q"};
    const deadline_override = DeadlineOverride{
        .id = "test-extension",
        .title = "Test extension",
        .source_reference = "BIR test advisory",
        .affected_form_codes = &affected,
        .original_deadline = try Date.init(2026, 5, 15),
        .adjusted_deadline = try Date.init(2026, 6, 15),
    };
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{ .overrides = &.{deadline_override} },
    );
    defer std.testing.allocator.free(deadlines);

    const q1 = findDeadline(
        deadlines,
        "1701Q",
        .{ .quarterly = .{ .taxable_year = 2026, .quarter = 1 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2026, 5, 15),
        q1.originalDeadlineDate().?,
    );
    try std.testing.expectEqual(
        try Date.init(2026, 6, 15),
        q1.finalDeadlineDate().?,
    );
    try std.testing.expectEqual(DeadlineStatus.extended, q1.status);
    try std.testing.expectEqualStrings(
        "BIR test advisory",
        q1.source_reference.?,
    );
}

test "override adjusted date is itself moved to a business day" {
    const days = [_]NonWorkingDay{.{
        .date = try Date.init(2026, 6, 15),
        .name = "Configured extension-day holiday",
        .kind = .regular_holiday,
    }};
    const affected = [_][]const u8{"1701Q"};
    const deadline_override = DeadlineOverride{
        .id = "test-extension-holiday",
        .title = "Test extension onto holiday",
        .source_reference = "BIR test advisory",
        .affected_form_codes = &affected,
        .original_deadline = try Date.init(2026, 5, 15),
        .adjusted_deadline = try Date.init(2026, 6, 15),
    };
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{
            .calendar = .{ .non_working_days = &days },
            .overrides = &.{deadline_override},
        },
    );
    defer std.testing.allocator.free(deadlines);

    const q1 = findDeadline(
        deadlines,
        "1701Q",
        .{ .quarterly = .{ .taxable_year = 2026, .quarter = 1 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2026, 6, 16),
        q1.finalDeadlineDate().?,
    );
    try std.testing.expectEqual(DeadlineStatus.extended, q1.status);
}

test "override can match the deadline produced by base weekend adjustment" {
    const affected = [_][]const u8{"1701Q"};
    const deadline_override = DeadlineOverride{
        .id = "test-adjusted-match",
        .title = "Extension announced after weekend adjustment",
        .source_reference = "BIR test advisory",
        .affected_form_codes = &affected,
        // The statutory date is Saturday, August 15. Base adjustment runs
        // first, so an issuance may identify the operative Monday deadline.
        .original_deadline = try Date.init(2026, 8, 17),
        .adjusted_deadline = try Date.init(2026, 9, 15),
    };
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{ .overrides = &.{deadline_override} },
    );
    defer std.testing.allocator.free(deadlines);

    const q2 = findDeadline(
        deadlines,
        "1701Q",
        .{ .quarterly = .{ .taxable_year = 2026, .quarter = 2 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2026, 8, 15),
        q2.originalDeadlineDate().?,
    );
    try std.testing.expectEqual(
        try Date.init(2026, 9, 15),
        q2.finalDeadlineDate().?,
    );
    try std.testing.expectEqual(DeadlineStatus.extended, q2.status);
}

test "blank-source override is ignored" {
    const affected = [_][]const u8{"1701Q"};
    const deadline_override = DeadlineOverride{
        .id = "unsourced",
        .title = "Unsourced change",
        .source_reference = "  ",
        .affected_form_codes = &affected,
        .original_deadline = try Date.init(2026, 5, 15),
        .adjusted_deadline = try Date.init(2026, 6, 15),
    };
    const deadlines = try resolveTaxableYear(
        std.testing.allocator,
        2026,
        .{ .overrides = &.{deadline_override} },
    );
    defer std.testing.allocator.free(deadlines);

    const q1 = findDeadline(
        deadlines,
        "1701Q",
        .{ .quarterly = .{ .taxable_year = 2026, .quarter = 1 } },
    ) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(
        try Date.init(2026, 5, 15),
        q1.finalDeadlineDate().?,
    );
    try std.testing.expectEqual(DeadlineStatus.normal, q1.status);
    try std.testing.expect(q1.source_reference == null);
}

test "form set resolver returns only selected rule-backed forms" {
    const forms = [_][]const u8{ "1701Q", "2551Q", "CUSTOM" };
    const deadlines = try deadlinesForForms(
        std.testing.allocator,
        &forms,
        2026,
        .{},
    );
    defer std.testing.allocator.free(deadlines);

    try std.testing.expectEqual(@as(usize, 7), deadlines.len);
    for (deadlines) |deadline| {
        try std.testing.expect(
            std.mem.eql(u8, deadline.form_code, "1701Q") or
                std.mem.eql(u8, deadline.form_code, "2551Q"),
        );
    }
}
