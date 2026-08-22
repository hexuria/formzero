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
//! This module covers the ordered gates through Item 11 and the Item 3
//! amount conditions. Schedule 1 date validation is not pinned here, so
//! `validation_reconciled` stays false.

const std = @import("std");
const evidence = @import("evidence.zig");

pub const ready = false;
pub const identity_gates_ready = true;

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

test "1601C identity gates are pinned but validation is not reconciled" {
    try std.testing.expect(identity_gates_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!evidence.readiness.validation_reconciled);
    try std.testing.expectEqual(@as(usize, 12), gate_order.len);
    // Calculations reconcile; validation does not yet.
    try std.testing.expect(evidence.readiness.calculation_reconciled);
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
