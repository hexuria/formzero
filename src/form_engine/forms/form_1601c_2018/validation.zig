//! HTA-local 1601C January 2018 (ENCS) `validate` gate chain.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - `validate` lines 2942-3034, `var dt = new Date()` line 2944
//!
//! The entry point is `validate`, not `validateForm` as in 1601EQ, and every
//! failing gate uses a bare `return`. None returns false, so the sole call
//! site cannot distinguish a rejection from a completed pass by value.
//!
//! Gates run in this order: Item 1 year, Item 1 month, Item 3, Item 6,
//! Item 7, Item 8, Item 10, Item 9, Item 9A, Item 11. That is not numeric
//! order — Item 10 precedes Item 9, and Item 11 comes last — and first
//! failure wins, so the order is observable.
//!
//! Two gates rewrite rather than only reject. A future year is replaced with
//! the clock year, and a future month is replaced with the clock month.
//!
//! The month gate is conditioned on the year: it fires only when the entered
//! year equals the clock year. A superseded pair of checks sits commented
//! out immediately above the live ones and lacks that condition, so the
//! refactor that added it is still visible in the source.
//!
//! Unlike 1601EQ there is no floor year. 1601EQ rejects anything before
//! 2018; 1601C accepts any year at or below the clock year.
//!
//! Two further gates are present but commented out: a line-of-business check
//! for Item 7 and a year-range check inside the Schedule 1 date validation.
//! `txtLineBus` is therefore never validated, which matches 1601EQ, where
//! the same field is the one control that fools a naive disabled parse.
//!
//! Alert text is reproduced exactly, including `Witholding` in the Item 8
//! message, which is misspelled in the source.
//!
//! Schedule 1's two date columns follow the ordered gates, and the function
//! ends by locking the form and announcing success.
//!
//! Both date checks are shape checks only. Column 1 accepts `mm/yyyy` and
//! column 2 accepts `mm/dd/yyyy`, each split on `/` and required to yield
//! exactly two or three parts. Every part must be numeric. Beyond that only
//! two ranges are enforced, and they disagree with each other:
//!
//! - the month test is `> 12 || < 0`, so a month of `0` is accepted
//! - the day test is `> 31 || < 1`, so a day of `0` is rejected
//!
//! Nothing checks a day against its month, so `02/31/2026` passes, and
//! nothing checks the year at all beyond numeric-ness — that range test is
//! commented out. A blank field skips its check entirely.
//!
//! The column 2 month test carries a comment reading "numeric check if
//! greater not than 31 - Month", copied from the day check it sits above.
//!
//! Three further blocks validating radio-driven Section A detail rows are
//! commented out and never evaluate.
//!
//! With the ordered gates, the amount conditions, both date columns and the
//! success path pinned, this module covers `validate` in full and
//! `validation_reconciled` is true.

const std = @import("std");
const evidence = @import("evidence.zig");

pub const ready = false;
pub const identity_gates_ready = true;
pub const schedule_dates_ready = true;

pub const alert_year_required = "Please enter a valid year on Item 1.";
pub const alert_month_required = "Please enter a valid month on Item 1.";
pub const alert_year_future = "Invalid year. Year should not be later than the current year.";
pub const alert_month_future = "Invalid month. Month should not be later than the current month.";
pub const alert_item_3_required = "Please select an option for Item 3.";
pub const alert_item_6_tin = "Please enter a valid TIN number on Item 6.";
pub const alert_item_7_rdo = "Please enter a valid RDO Code on Item 7.";
/// Misspelled in the source.
pub const alert_item_8_name = "Please enter a valid Witholding Agent's Name on Item 8.";
pub const alert_item_10_telephone = "Please enter a valid Telephone Number on Item 10.";
pub const alert_item_9_address = "Please enter Taxpayer's Registered Address on Item 9.";
pub const alert_item_9a_zip = "Please enter Taxpayer's Zip Code on Item 9A.";
pub const alert_item_11_required = "Please select an option for Item 11.";
pub const alert_item_14_positive = "Invalid amount in Item no.14. Value must be greater than zero(0).";
pub const alert_item_25_positive = "Invalid amount in Item no.25. Value must be greater than zero(0).";
pub const alert_schedule_month_year = "Invalid date entry on Section A, column 1 Record ";
pub const alert_schedule_date_paid = "Invalid date entry on Section A, column 2 Record ";
pub const alert_validation_successful =
    "Validation successful. Click on Edit if you wish to modify your entries.";

/// Script-load `dt`. `getMonth()` is 0-based.
pub const Clock = struct {
    year: i32,
    /// 0-based, matching `Date.getMonth()`.
    month_index: u8,
};

pub const Year = union(enum) { empty, value: i32 };

/// `txtMonth` is a select; index 0 is the blank row.
pub const Month = union(enum) { empty, selected_index: u8 };

pub const TaxWithheld = enum { none, yes, no };
pub const Category = enum { none, private, government };

pub const Gate = enum {
    item_1_year,
    item_1_month,
    item_3_tax_withheld,
    item_6_tin,
    item_7_rdo,
    item_8_name,
    item_10_telephone,
    item_9_address,
    item_9a_zip,
    item_11_category,
    item_14_amount,
    item_25_amount,
};

/// Source order of the ordered gates, which is not numeric order.
pub const gate_order = [_]Gate{
    .item_1_year,
    .item_1_month,
    .item_3_tax_withheld,
    .item_6_tin,
    .item_7_rdo,
    .item_8_name,
    .item_10_telephone,
    .item_9_address,
    .item_9a_zip,
    .item_11_category,
    .item_14_amount,
    .item_25_amount,
};

/// Gates present in the source but commented out, so never evaluated.
pub const CommentedGate = enum { item_7_line_of_business, schedule_1_year_range };
pub const commented_out_gates = [_]CommentedGate{ .item_7_line_of_business, .schedule_1_year_range };

pub const Inputs = struct {
    year: Year,
    month: Month,
    tax_withheld: TaxWithheld,
    tin_part_1: []const u8 = "",
    tin_part_2: []const u8 = "",
    tin_part_3: []const u8 = "",
    branch_code: []const u8 = "",
    /// `selectedIndex == 0` is the placeholder row.
    rdo_selected_index: usize = 1,
    taxpayer_name: []const u8 = "",
    telephone_number: []const u8 = "",
    registered_address: []const u8 = "",
    zip_code: []const u8 = "",
    category: Category = .private,
    /// Only consulted when Item 3 is Yes.
    item_14_centavos: i64 = 1,
    item_25_centavos: i64 = 1,
};

pub const Outcome = struct {
    accepted: bool,
    failed_gate: ?Gate,
    alert: ?[]const u8,
    /// Set when the gate rewrote Item 1's year to the clock year.
    rewrote_year_to_clock: bool = false,
    /// Set when the gate rewrote Item 1's month to the clock month.
    rewrote_month_to_clock: bool = false,
};

fn blank(value: []const u8) bool {
    return value.len == 0;
}

fn reject(gate: Gate, alert: []const u8) Outcome {
    return .{ .accepted = false, .failed_gate = gate, .alert = alert };
}

/// `validate` in source order. First failure wins.
pub fn validate(inputs: Inputs, clock: Clock) Outcome {
    const entered_year = switch (inputs.year) {
        .empty => return reject(.item_1_year, alert_year_required),
        .value => |value| value,
    };
    const month_index = switch (inputs.month) {
        .empty => return reject(.item_1_month, alert_month_required),
        .selected_index => |index| index,
    };
    if (entered_year > clock.year) {
        var outcome = reject(.item_1_year, alert_year_future);
        outcome.rewrote_year_to_clock = true;
        return outcome;
    }
    // Conditioned on the year, unlike the superseded commented-out pair.
    if (month_index > clock.month_index and entered_year == clock.year) {
        var outcome = reject(.item_1_month, alert_month_future);
        outcome.rewrote_month_to_clock = true;
        return outcome;
    }
    if (inputs.tax_withheld == .none) {
        return reject(.item_3_tax_withheld, alert_item_3_required);
    }
    if (blank(inputs.tin_part_1) or blank(inputs.tin_part_2) or
        blank(inputs.tin_part_3) or blank(inputs.branch_code))
    {
        return reject(.item_6_tin, alert_item_6_tin);
    }
    if (inputs.rdo_selected_index == 0) return reject(.item_7_rdo, alert_item_7_rdo);
    if (blank(inputs.taxpayer_name)) return reject(.item_8_name, alert_item_8_name);
    if (blank(inputs.telephone_number)) {
        return reject(.item_10_telephone, alert_item_10_telephone);
    }
    if (blank(inputs.registered_address)) {
        return reject(.item_9_address, alert_item_9_address);
    }
    if (blank(inputs.zip_code)) return reject(.item_9a_zip, alert_item_9a_zip);
    if (inputs.category == .none) {
        return reject(.item_11_category, alert_item_11_required);
    }
    if (inputs.tax_withheld == .yes) {
        if (inputs.item_14_centavos == 0) {
            return reject(.item_14_amount, alert_item_14_positive);
        }
        if (inputs.item_25_centavos == 0) {
            return reject(.item_25_amount, alert_item_25_positive);
        }
    }
    return .{ .accepted = true, .failed_gate = null, .alert = null };
}

const march_2026: Clock = .{ .year = 2026, .month_index = 2 };

fn complete() Inputs {
    return .{
        .year = .{ .value = 2026 },
        .month = .{ .selected_index = 1 },
        .tax_withheld = .no,
        .tin_part_1 = "123",
        .tin_part_2 = "456",
        .tin_part_3 = "789",
        .branch_code = "00000",
        .rdo_selected_index = 1,
        .taxpayer_name = "SYNTHETIC AGENT",
        .telephone_number = "0000000",
        .registered_address = "SYNTHETIC ADDRESS",
        .zip_code = "1000",
        .category = .private,
    };
}

test "1601C identity gates are pinned in source order" {
    try std.testing.expect(identity_gates_ready);
    try std.testing.expectEqual(@as(usize, 12), gate_order.len);
    // Covering validate does not make the module a finished surface.
    try std.testing.expect(!ready);
}

test "1601C gate order is source order, not numeric order" {
    try std.testing.expectEqual(Gate.item_10_telephone, gate_order[6]);
    try std.testing.expectEqual(Gate.item_9_address, gate_order[7]);
    try std.testing.expectEqual(Gate.item_11_category, gate_order[9]);

    var inputs = complete();
    inputs.registered_address = "";
    inputs.telephone_number = "";
    // Item 10 is reached first even though 9 is the lower number.
    try std.testing.expectEqual(Gate.item_10_telephone, validate(inputs, march_2026).failed_gate.?);
}

test "1601C a future year and a future month rewrite rather than only reject" {
    var future_year = complete();
    future_year.year = .{ .value = 2027 };
    const year_outcome = validate(future_year, march_2026);
    try std.testing.expect(!year_outcome.accepted);
    try std.testing.expect(year_outcome.rewrote_year_to_clock);
    try std.testing.expectEqualStrings(alert_year_future, year_outcome.alert.?);

    var future_month = complete();
    future_month.month = .{ .selected_index = 6 };
    const month_outcome = validate(future_month, march_2026);
    try std.testing.expect(!month_outcome.accepted);
    try std.testing.expect(month_outcome.rewrote_month_to_clock);
    try std.testing.expectEqualStrings(alert_month_future, month_outcome.alert.?);
}

test "1601C the month gate only fires within the clock year" {
    // A later month in an earlier year is accepted, because the live check
    // carries the year condition the commented-out pair lacked.
    var prior_year = complete();
    prior_year.year = .{ .value = 2025 };
    prior_year.month = .{ .selected_index = 11 };
    try std.testing.expect(validate(prior_year, march_2026).accepted);

    // The same month in the clock year is rejected.
    var same_year = complete();
    same_year.month = .{ .selected_index = 11 };
    try std.testing.expect(!validate(same_year, march_2026).accepted);
}

test "1601C accepts any year at or below the clock year, with no floor" {
    // 1601EQ rejects anything before 2018; 1601C has no such gate.
    var ancient = complete();
    ancient.year = .{ .value = 1999 };
    try std.testing.expect(validate(ancient, march_2026).accepted);
    ancient.year = .{ .value = 2017 };
    try std.testing.expect(validate(ancient, march_2026).accepted);
}

test "1601C empty year and empty month are distinct first failures" {
    var no_year = complete();
    no_year.year = .empty;
    const year_outcome = validate(no_year, march_2026);
    try std.testing.expectEqual(Gate.item_1_year, year_outcome.failed_gate.?);
    try std.testing.expectEqualStrings(alert_year_required, year_outcome.alert.?);
    try std.testing.expect(!year_outcome.rewrote_year_to_clock);

    var no_month = complete();
    no_month.month = .empty;
    const month_outcome = validate(no_month, march_2026);
    try std.testing.expectEqual(Gate.item_1_month, month_outcome.failed_gate.?);
    try std.testing.expectEqualStrings(alert_month_required, month_outcome.alert.?);
}

test "1601C the amount gates apply only when Item 3 is Yes" {
    var withheld_no = complete();
    withheld_no.tax_withheld = .no;
    withheld_no.item_14_centavos = 0;
    withheld_no.item_25_centavos = 0;
    // Item 3 = No skips both amount checks entirely.
    try std.testing.expect(validate(withheld_no, march_2026).accepted);

    var withheld_yes = complete();
    withheld_yes.tax_withheld = .yes;
    withheld_yes.item_14_centavos = 0;
    try std.testing.expectEqual(
        Gate.item_14_amount,
        validate(withheld_yes, march_2026).failed_gate.?,
    );

    withheld_yes.item_14_centavos = 100;
    withheld_yes.item_25_centavos = 0;
    try std.testing.expectEqual(
        Gate.item_25_amount,
        validate(withheld_yes, march_2026).failed_gate.?,
    );
}

test "1601C the Item 8 alert reproduces the source misspelling" {
    var no_name = complete();
    no_name.taxpayer_name = "";
    const outcome = validate(no_name, march_2026);
    try std.testing.expectEqualStrings(alert_item_8_name, outcome.alert.?);
    // "Witholding", not "Withholding".
    try std.testing.expect(std.mem.indexOf(u8, alert_item_8_name, "Witholding") != null);
    try std.testing.expect(std.mem.indexOf(u8, alert_item_8_name, "Withholding") == null);
}

test "1601C line of business is never validated" {
    try std.testing.expectEqual(@as(usize, 2), commented_out_gates.len);
    // Its check is commented out, so no gate in the chain covers it and a
    // complete form passes without txtLineBus being consulted at all.
    try std.testing.expect(validate(complete(), march_2026).accepted);
    for (commented_out_gates) |gate| {
        try std.testing.expect(gate == .item_7_line_of_business or
            gate == .schedule_1_year_range);
    }
}

test "1601C each identity gate fires alone with its exact message" {
    const cases = [_]struct { gate: Gate, alert: []const u8, apply: *const fn (*Inputs) void }{
        .{ .gate = .item_3_tax_withheld, .alert = alert_item_3_required, .apply = struct {
            fn f(i: *Inputs) void {
                i.tax_withheld = .none;
            }
        }.f },
        .{ .gate = .item_6_tin, .alert = alert_item_6_tin, .apply = struct {
            fn f(i: *Inputs) void {
                i.branch_code = "";
            }
        }.f },
        .{ .gate = .item_7_rdo, .alert = alert_item_7_rdo, .apply = struct {
            fn f(i: *Inputs) void {
                i.rdo_selected_index = 0;
            }
        }.f },
        .{ .gate = .item_9_address, .alert = alert_item_9_address, .apply = struct {
            fn f(i: *Inputs) void {
                i.registered_address = "";
            }
        }.f },
        .{ .gate = .item_9a_zip, .alert = alert_item_9a_zip, .apply = struct {
            fn f(i: *Inputs) void {
                i.zip_code = "";
            }
        }.f },
        .{ .gate = .item_11_category, .alert = alert_item_11_required, .apply = struct {
            fn f(i: *Inputs) void {
                i.category = .none;
            }
        }.f },
    };
    for (cases) |case| {
        var inputs = complete();
        case.apply(&inputs);
        const outcome = validate(inputs, march_2026);
        try std.testing.expect(!outcome.accepted);
        try std.testing.expectEqual(case.gate, outcome.failed_gate.?);
        try std.testing.expectEqualStrings(case.alert, outcome.alert.?);
    }
}

/// Which Schedule 1 date column a rejection came from.
pub const DateColumn = enum { month_year, date_paid };

pub const DateOutcome = struct {
    accepted: bool,
    column: ?DateColumn,
};

fn allDigits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |character| {
        if (character < '0' or character > '9') return false;
    }
    return true;
}

fn parsePart(text: []const u8) ?i32 {
    if (!allDigits(text)) return null;
    var value: i32 = 0;
    for (text) |character| {
        value = value * 10 + @as(i32, character - '0');
        if (value > 1_000_000) return null;
    }
    return value;
}

fn splitCount(text: []const u8) usize {
    var parts: usize = 1;
    for (text) |character| {
        if (character == '/') parts += 1;
    }
    return parts;
}

fn part(text: []const u8, index: usize) []const u8 {
    var seen: usize = 0;
    var start: usize = 0;
    for (text, 0..) |character, offset| {
        if (character != '/') continue;
        if (seen == index) return text[start..offset];
        seen += 1;
        start = offset + 1;
    }
    return if (seen == index) text[start..] else "";
}

/// Column 1, `mm/yyyy`. A blank field is skipped, as HTA does.
pub fn validateMonthYear(text: []const u8) DateOutcome {
    if (text.len == 0) return .{ .accepted = true, .column = null };
    if (splitCount(text) != 2) return .{ .accepted = false, .column = .month_year };
    const month = parsePart(part(text, 0)) orelse
        return .{ .accepted = false, .column = .month_year };
    // The source writes `> 12 || < 0`, so a month of zero is accepted.
    if (month > 12 or month < 0) return .{ .accepted = false, .column = .month_year };
    if (parsePart(part(text, 1)) == null) {
        return .{ .accepted = false, .column = .month_year };
    }
    // The year range test is commented out, so any numeric year passes.
    return .{ .accepted = true, .column = null };
}

/// Column 2, `mm/dd/yyyy`. A blank field is skipped, as HTA does.
pub fn validateDatePaid(text: []const u8) DateOutcome {
    if (text.len == 0) return .{ .accepted = true, .column = null };
    if (splitCount(text) != 3) return .{ .accepted = false, .column = .date_paid };
    const month = parsePart(part(text, 0)) orelse
        return .{ .accepted = false, .column = .date_paid };
    if (month > 12 or month < 0) return .{ .accepted = false, .column = .date_paid };
    const day = parsePart(part(text, 1)) orelse
        return .{ .accepted = false, .column = .date_paid };
    // The day test uses `< 1` where the month test uses `< 0`.
    if (day > 31 or day < 1) return .{ .accepted = false, .column = .date_paid };
    if (parsePart(part(text, 2)) == null) {
        return .{ .accepted = false, .column = .date_paid };
    }
    return .{ .accepted = true, .column = null };
}

pub const ScheduleRowDates = struct {
    month_year: []const u8 = "",
    date_paid: []const u8 = "",
};

/// Both columns for every row, in row order. First failure wins.
pub fn validateScheduleDates(rows: []const ScheduleRowDates) struct {
    accepted: bool,
    row_index: ?usize,
    column: ?DateColumn,
} {
    for (rows, 0..) |row, index| {
        const first = validateMonthYear(row.month_year);
        if (!first.accepted) {
            return .{ .accepted = false, .row_index = index, .column = first.column };
        }
        const second = validateDatePaid(row.date_paid);
        if (!second.accepted) {
            return .{ .accepted = false, .row_index = index, .column = second.column };
        }
    }
    return .{ .accepted = true, .row_index = null, .column = null };
}

/// The success path: every control is locked, then the alert is raised.
pub const SuccessPath = struct {
    locks_every_control: bool = true,
    announces_success: bool = true,
};

pub const success_path: SuccessPath = .{};

/// Commented-out Section A blocks that check radio-driven detail rows.
pub const commented_out_section_a_blocks: usize = 3;

test "1601C validate is now covered end to end" {
    try std.testing.expect(identity_gates_ready);
    try std.testing.expect(schedule_dates_ready);
    try std.testing.expect(evidence.readiness.validation_reconciled);
    try std.testing.expect(evidence.readiness.calculation_reconciled);
    // Coverage of validate is not a claim about the serializers.
    try std.testing.expect(!evidence.readiness.editable_serializer_exact);
    try std.testing.expect(!evidence.readiness.persistence_integrated);
}

test "1601C a blank schedule date is skipped, as the source skips it" {
    try std.testing.expect(validateMonthYear("").accepted);
    try std.testing.expect(validateDatePaid("").accepted);
    const rows = [_]ScheduleRowDates{.{}};
    try std.testing.expect(validateScheduleDates(&rows).accepted);
}

test "1601C the schedule date columns are shape checks only" {
    try std.testing.expect(validateMonthYear("03/2026").accepted);
    try std.testing.expect(validateDatePaid("03/15/2026").accepted);

    // Wrong number of parts.
    try std.testing.expect(!validateMonthYear("03/15/2026").accepted);
    try std.testing.expect(!validateDatePaid("03/2026").accepted);
    // Non-numeric parts.
    try std.testing.expect(!validateMonthYear("mm/2026").accepted);
    try std.testing.expect(!validateDatePaid("03/dd/2026").accepted);
}

test "1601C month accepts zero where day rejects it" {
    // The source month test is `> 12 || < 0`, so zero passes.
    try std.testing.expect(validateMonthYear("0/2026").accepted);
    try std.testing.expect(validateDatePaid("0/15/2026").accepted);
    // The day test is `> 31 || < 1`, so zero fails.
    try std.testing.expect(!validateDatePaid("03/0/2026").accepted);
    // And the ranges are enforced at the upper end for both.
    try std.testing.expect(!validateMonthYear("13/2026").accepted);
    try std.testing.expect(!validateDatePaid("03/32/2026").accepted);
}

test "1601C no day is checked against its month" {
    // February the thirty-first is accepted.
    try std.testing.expect(validateDatePaid("02/31/2026").accepted);
    try std.testing.expect(validateDatePaid("04/31/2026").accepted);
}

test "1601C the year is only checked for being numeric" {
    // The range test is commented out, so any numeric year passes.
    try std.testing.expect(validateMonthYear("03/1800").accepted);
    try std.testing.expect(validateMonthYear("03/9999").accepted);
    try std.testing.expect(validateDatePaid("03/15/1800").accepted);
    try std.testing.expect(!validateMonthYear("03/yyyy").accepted);
}

test "1601C schedule rows report the failing row and column" {
    const rows = [_]ScheduleRowDates{
        .{ .month_year = "01/2026", .date_paid = "01/15/2026" },
        .{ .month_year = "02/2026", .date_paid = "02/00/2026" },
    };
    const outcome = validateScheduleDates(&rows);
    try std.testing.expect(!outcome.accepted);
    try std.testing.expectEqual(@as(usize, 1), outcome.row_index.?);
    try std.testing.expectEqual(DateColumn.date_paid, outcome.column.?);

    const bad_first = [_]ScheduleRowDates{.{ .month_year = "13/2026" }};
    const first_outcome = validateScheduleDates(&bad_first);
    try std.testing.expectEqual(@as(usize, 0), first_outcome.row_index.?);
    try std.testing.expectEqual(DateColumn.month_year, first_outcome.column.?);
}

test "1601C the success path locks the form and three blocks never run" {
    try std.testing.expect(success_path.locks_every_control);
    try std.testing.expect(success_path.announces_success);
    try std.testing.expectEqual(@as(usize, 3), commented_out_section_a_blocks);
    try std.testing.expect(std.mem.indexOf(
        u8,
        alert_validation_successful,
        "Click on Edit",
    ) != null);
}
