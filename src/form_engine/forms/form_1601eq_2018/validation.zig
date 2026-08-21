//! HTA-local `validateForm` gates for BIR Form 1601EQ January 2018 ENCS:
//! Item 1 year, Item 2 quarter, and the identity required-field gates.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601EQ.hta`
//! - SHA-256:
//!   `cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96`
//! - `var dt = new Date()` line 3140 (script-load snapshot, not per call)
//! - `validateForm` year gate lines 3143-3159
//! - `validateForm` quarter gate lines 3161-3209
//! - `validateForm` identity gates lines 3211-3249
//!
//! Clock is injected. `Date.getMonth()` is 0-based: April is 3, July is 6,
//! October is 9. Fourth quarter of the clock year is never accepted — HTA
//! has no month check for Q4.
//!
//! The identity gates are emptiness checks only; HTA compares `value == ""`
//! and never trims, so a single space passes every text gate. Their HTA
//! evaluation order is 4, 11, 6, 7, 8, 10, 9, 9A, 12 — not numeric order —
//! and the first failure wins.
//!
//! Two other HTA functions carry overlapping messages and are NOT pinned
//! here, because they are different code paths with different predicates:
//! - `checkiftaxwheldisYes` lines 2840-2857 repeats the Item 4 and Item 11
//!   gates, but reads `frm1601EQ:optcategory:G` with a lowercase `c` where
//!   the control is `optCategory:G`. That id does not resolve.
//! - `initialValidateBeforeSave` lines 3485-3501 is a narrower save-path
//!   gate: it tests the RDO by `value == "000"` rather than by
//!   `selectedIndex`, and names Item 8 "Withholding Agent's Name". Save is
//!   fail-closed, so it stays unimplemented.
//!
//! Gates after Item 12 — the Item-4-Yes Part II ATC branch, the Item 30
//! over-remittance choice gate, and the success path — are not implemented.
//! ATC lookup depends on absent scripts. `ready` stays false.

const std = @import("std");
const evidence = @import("evidence.zig");

pub const ready = false;
pub const year_quarter_ready = true;
pub const identity_required_ready = true;

pub const alert_year_required = "Please enter a valid year on Item 1.";
pub const alert_year_future = "Invalid entry on Item 1. Entry should not be a future Date.";
pub const alert_year_before_2018 = "Invalid entry on Item 1. Entry should not be a previous year from 2018.";
pub const alert_quarter_required = "Please select Quarter on Item 2";
pub const alert_quarter_1 = "Unable to select first Quarter due to the current date. Payment should be made after the Quarter";
pub const alert_quarter_2 = "Unable to select second Quarter due to the current date. Payment should be made after the Quarter";
pub const alert_quarter_3 = "Unable to select third Quarter due to the current date. Payment should be made after the Quarter";
pub const alert_quarter_4 = "Unable to select fourth Quarter due to the current date. Payment should be made after the Quarter";

/// 0-based month from HTA `Date.getMonth()`.
pub const JsMonth = enum(u4) {
    january = 0,
    february = 1,
    march = 2,
    april = 3,
    may = 4,
    june = 5,
    july = 6,
    august = 7,
    september = 8,
    october = 9,
    november = 10,
    december = 11,
};

/// Script-load `dt` from HTA line 3140.
pub const Clock = struct {
    year: i32,
    month: JsMonth,
};

pub const Year = union(enum) {
    empty,
    value: i32,
};

pub const Quarter = enum(u3) {
    none,
    q1,
    q2,
    q3,
    q4,
};

pub const Outcome = struct {
    accepted: bool,
    year: Year,
    quarter: Quarter,
    alert: ?[]const u8,
    focus_year: bool,
};

fn accept(year: Year, quarter: Quarter) Outcome {
    return .{
        .accepted = true,
        .year = year,
        .quarter = quarter,
        .alert = null,
        .focus_year = false,
    };
}

fn rejectYear(year: Year, quarter: Quarter, alert: []const u8) Outcome {
    return .{
        .accepted = false,
        .year = year,
        .quarter = quarter,
        .alert = alert,
        .focus_year = true,
    };
}

fn rejectQuarter(year: Year, alert: []const u8) Outcome {
    return .{
        .accepted = false,
        .year = year,
        .quarter = .none,
        .alert = alert,
        .focus_year = false,
    };
}

fn currentYearQuarterOpen(quarter: Quarter, month: JsMonth) bool {
    const month_index = @intFromEnum(month);
    return switch (quarter) {
        .none => false,
        .q1 => month_index >= 3,
        .q2 => month_index >= 6,
        .q3 => month_index >= 9,
        // HTA Q4 current-year branch has no month check; it always fails.
        .q4 => false,
    };
}

fn quarterClosedAlert(quarter: Quarter) []const u8 {
    return switch (quarter) {
        .none => alert_quarter_required,
        .q1 => alert_quarter_1,
        .q2 => alert_quarter_2,
        .q3 => alert_quarter_3,
        .q4 => alert_quarter_4,
    };
}

/// Year then quarter, in `validateForm` order. Does not run later rules.
pub fn validateYearAndQuarter(year: Year, quarter: Quarter, clock: Clock) Outcome {
    const entered = switch (year) {
        .empty => return rejectYear(.empty, quarter, alert_year_required),
        .value => |value| value,
    };
    if (entered > clock.year) {
        return rejectYear(.{ .value = clock.year }, quarter, alert_year_future);
    }
    if (entered < 2018) {
        return rejectYear(.empty, quarter, alert_year_before_2018);
    }

    const accepted_year: Year = .{ .value = entered };
    if (quarter == .none) {
        return .{
            .accepted = false,
            .year = accepted_year,
            .quarter = .none,
            .alert = alert_quarter_required,
            .focus_year = false,
        };
    }

    const prior_year = entered < clock.year;
    if (prior_year or currentYearQuarterOpen(quarter, clock.month)) {
        return accept(accepted_year, quarter);
    }
    return rejectQuarter(accepted_year, quarterClosedAlert(quarter));
}

pub const alert_item_4_required = "Please select an option for Item 4.";
pub const alert_item_11_required = "Please select an option for Item 11.";
pub const alert_item_6_tin = "Please enter a valid TIN number on Item 6.";
pub const alert_item_7_rdo = "Please enter a valid RDO Code on Item 7.";
pub const alert_item_8_name = "Please enter a valid Taxpayer Name on Item 8.";
pub const alert_item_10_telephone = "Please enter a valid Telephone Number on Item 10.";
pub const alert_item_9_address = "Please enter Taxpayer's Registered Address on Item 9.";
pub const alert_item_9a_zip = "Please enter Taxpayer's Zip Code on Item 9A.";
pub const alert_item_12_email = "Please enter valid Email Address on Item 12.";

/// `optWithheld:Y` / `optWithheld:N`. Neither is markup-checked.
pub const Withheld = enum { none, yes, no };

/// `optCategory:P` / `optCategory:G`. Neither is markup-checked.
pub const Category = enum { none, private, government };

pub const IdentityGate = enum {
    item_4_withheld,
    item_11_category,
    item_6_tin,
    item_7_rdo,
    item_8_taxpayer_name,
    item_10_telephone,
    item_9_address,
    item_9a_zip,
    item_12_email,
};

/// HTA evaluation order inside `validateForm`, which is not numeric order:
/// Item 11 precedes Item 6, and Item 10 precedes Item 9.
pub const identity_gate_order = [_]IdentityGate{
    .item_4_withheld,
    .item_11_category,
    .item_6_tin,
    .item_7_rdo,
    .item_8_taxpayer_name,
    .item_10_telephone,
    .item_9_address,
    .item_9a_zip,
    .item_12_email,
};

pub const IdentityInputs = struct {
    withheld: Withheld,
    category: Category,
    /// `txtTIN1`, `txtTIN2`, `txtTIN3`, `txtBranchCode`. All four share the
    /// Item 6 gate; any one empty fails it.
    tin_part_1: []const u8,
    tin_part_2: []const u8,
    tin_part_3: []const u8,
    branch_code: []const u8,
    /// `txtRDOCode` is a select; HTA tests `selectedIndex == 0`, the
    /// placeholder row, not the option value.
    rdo_selected_index: usize,
    taxpayer_name: []const u8,
    telephone_number: []const u8,
    registered_address: []const u8,
    zip_code: []const u8,
    /// Item 12 is the only gate whose control id carries no `frm1601EQ:`
    /// prefix: HTA reads `d.getElementById('txtEmail')`.
    email: []const u8,
};

pub const IdentityOutcome = struct {
    /// Every implemented identity gate passed. HTA would next evaluate the
    /// Part II ATC branch, which is not implemented here.
    accepted: bool,
    failed_gate: ?IdentityGate,
    alert: ?[]const u8,
};

pub fn alertFor(gate: IdentityGate) []const u8 {
    return switch (gate) {
        .item_4_withheld => alert_item_4_required,
        .item_11_category => alert_item_11_required,
        .item_6_tin => alert_item_6_tin,
        .item_7_rdo => alert_item_7_rdo,
        .item_8_taxpayer_name => alert_item_8_name,
        .item_10_telephone => alert_item_10_telephone,
        .item_9_address => alert_item_9_address,
        .item_9a_zip => alert_item_9a_zip,
        .item_12_email => alert_item_12_email,
    };
}

/// HTA compares `value == ""` and never trims, so whitespace is a value.
fn blank(value: []const u8) bool {
    return value.len == 0;
}

fn gateFails(gate: IdentityGate, inputs: IdentityInputs) bool {
    return switch (gate) {
        .item_4_withheld => inputs.withheld == .none,
        .item_11_category => inputs.category == .none,
        .item_6_tin => blank(inputs.tin_part_1) or
            blank(inputs.tin_part_2) or
            blank(inputs.tin_part_3) or
            blank(inputs.branch_code),
        .item_7_rdo => inputs.rdo_selected_index == 0,
        .item_8_taxpayer_name => blank(inputs.taxpayer_name),
        .item_10_telephone => blank(inputs.telephone_number),
        .item_9_address => blank(inputs.registered_address),
        .item_9a_zip => blank(inputs.zip_code),
        .item_12_email => blank(inputs.email),
    };
}

/// Identity required-field gates in `validateForm` order. First failure wins.
/// Does not run the Part II ATC branch or any later rule.
pub fn validateIdentity(inputs: IdentityInputs) IdentityOutcome {
    for (identity_gate_order) |gate| {
        if (gateFails(gate, inputs)) {
            return .{
                .accepted = false,
                .failed_gate = gate,
                .alert = alertFor(gate),
            };
        }
    }
    return .{ .accepted = true, .failed_gate = null, .alert = null };
}

pub const FormOutcome = struct {
    year_quarter: Outcome,
    /// Null when the year or quarter gate already returned.
    identity: ?IdentityOutcome,
    /// Every gate implemented so far passed. This is not `validateForm`
    /// success: the Part II ATC branch, the Item 30 over-remittance choice
    /// gate, and the success path are still unimplemented.
    reached_part_ii_atc_gate: bool,
    alert: ?[]const u8,
};

/// `validateForm` from Item 1 through Item 12, stopping before the
/// Item-4-Yes Part II ATC branch.
pub fn validateThroughIdentity(
    year: Year,
    quarter: Quarter,
    clock: Clock,
    inputs: IdentityInputs,
) FormOutcome {
    const year_quarter = validateYearAndQuarter(year, quarter, clock);
    if (!year_quarter.accepted) {
        return .{
            .year_quarter = year_quarter,
            .identity = null,
            .reached_part_ii_atc_gate = false,
            .alert = year_quarter.alert,
        };
    }

    const identity = validateIdentity(inputs);
    return .{
        .year_quarter = year_quarter,
        .identity = identity,
        .reached_part_ii_atc_gate = identity.accepted,
        .alert = identity.alert,
    };
}

const april_2026: Clock = .{ .year = 2026, .month = .april };
const december_2026: Clock = .{ .year = 2026, .month = .december };

test "1601EQ year and quarter gates stay unreconciled and skip the rest of validateForm" {
    try std.testing.expect(year_quarter_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!evidence.readiness.identityReady());
    try std.testing.expect(!evidence.readiness.dependency_closure);
}

test "1601EQ empty year fails and keeps the quarter" {
    const result = validateYearAndQuarter(.empty, .q1, april_2026);
    try std.testing.expect(!result.accepted);
    try std.testing.expect(result.year == .empty);
    try std.testing.expectEqual(Quarter.q1, result.quarter);
    try std.testing.expectEqualStrings(alert_year_required, result.alert.?);
    try std.testing.expect(result.focus_year);
}

test "1601EQ future year rewrites to the clock year" {
    const result = validateYearAndQuarter(.{ .value = 2027 }, .q2, april_2026);
    try std.testing.expect(!result.accepted);
    try std.testing.expectEqual(Year{ .value = 2026 }, result.year);
    try std.testing.expectEqual(Quarter.q2, result.quarter);
    try std.testing.expectEqualStrings(alert_year_future, result.alert.?);
    try std.testing.expect(result.focus_year);
}

test "1601EQ year before 2018 clears the year" {
    const result = validateYearAndQuarter(.{ .value = 2017 }, .q4, april_2026);
    try std.testing.expect(!result.accepted);
    try std.testing.expect(result.year == .empty);
    try std.testing.expectEqual(Quarter.q4, result.quarter);
    try std.testing.expectEqualStrings(alert_year_before_2018, result.alert.?);
    try std.testing.expect(result.focus_year);
}

test "1601EQ current-year quarters open only after the HTA month thresholds" {
    const year: Year = .{ .value = 2026 };
    try std.testing.expect(validateYearAndQuarter(year, .q1, april_2026).accepted);
    try std.testing.expect(!validateYearAndQuarter(year, .q1, .{ .year = 2026, .month = .march }).accepted);

    try std.testing.expect(validateYearAndQuarter(year, .q2, .{ .year = 2026, .month = .july }).accepted);
    const june_q2 = validateYearAndQuarter(year, .q2, .{ .year = 2026, .month = .june });
    try std.testing.expect(!june_q2.accepted);
    try std.testing.expectEqual(Quarter.none, june_q2.quarter);
    try std.testing.expectEqualStrings(alert_quarter_2, june_q2.alert.?);

    try std.testing.expect(validateYearAndQuarter(year, .q3, .{ .year = 2026, .month = .october }).accepted);
    try std.testing.expect(!validateYearAndQuarter(year, .q3, .{ .year = 2026, .month = .september }).accepted);
}

test "1601EQ current-year Q4 is never open even in December" {
    const result = validateYearAndQuarter(.{ .value = 2026 }, .q4, december_2026);
    try std.testing.expect(!result.accepted);
    try std.testing.expectEqual(Year{ .value = 2026 }, result.year);
    try std.testing.expectEqual(Quarter.none, result.quarter);
    try std.testing.expectEqualStrings(alert_quarter_4, result.alert.?);
    try std.testing.expect(!result.focus_year);
}

test "1601EQ prior-year Q4 is accepted and a missing quarter is not" {
    const prior = validateYearAndQuarter(.{ .value = 2025 }, .q4, april_2026);
    try std.testing.expect(prior.accepted);
    try std.testing.expectEqual(Quarter.q4, prior.quarter);
    try std.testing.expect(prior.alert == null);

    const missing = validateYearAndQuarter(.{ .value = 2018 }, .none, april_2026);
    try std.testing.expect(!missing.accepted);
    try std.testing.expectEqual(Year{ .value = 2018 }, missing.year);
    try std.testing.expectEqual(Quarter.none, missing.quarter);
    try std.testing.expectEqualStrings(alert_quarter_required, missing.alert.?);
    try std.testing.expect(!missing.focus_year);
}

const complete_identity: IdentityInputs = .{
    .withheld = .no,
    .category = .private,
    .tin_part_1 = "123",
    .tin_part_2 = "456",
    .tin_part_3 = "789",
    .branch_code = "00000",
    .rdo_selected_index = 1,
    .taxpayer_name = "SYNTHETIC TAXPAYER",
    .telephone_number = "0000000",
    .registered_address = "SYNTHETIC ADDRESS",
    .zip_code = "1000",
    .email = "synthetic@example.invalid",
};

test "1601EQ identity gates are pinned but validateForm stays unreconciled" {
    try std.testing.expect(identity_required_ready);
    try std.testing.expect(!ready);
    try std.testing.expectEqual(@as(usize, 9), identity_gate_order.len);
}

test "1601EQ identity gate order is HTA order, not numeric order" {
    // Item 11 is gated before Item 6, and Item 10 before Item 9.
    try std.testing.expectEqual(IdentityGate.item_11_category, identity_gate_order[1]);
    try std.testing.expectEqual(IdentityGate.item_6_tin, identity_gate_order[2]);
    try std.testing.expectEqual(IdentityGate.item_10_telephone, identity_gate_order[5]);
    try std.testing.expectEqual(IdentityGate.item_9_address, identity_gate_order[6]);

    var inputs = complete_identity;
    inputs.category = .none;
    inputs.tin_part_1 = "";
    const category_first = validateIdentity(inputs);
    try std.testing.expectEqual(IdentityGate.item_11_category, category_first.failed_gate.?);

    var later = complete_identity;
    later.registered_address = "";
    later.telephone_number = "";
    const telephone_first = validateIdentity(later);
    try std.testing.expectEqual(IdentityGate.item_10_telephone, telephone_first.failed_gate.?);
}

test "1601EQ each identity gate fires alone with its HTA message" {
    const cases = [_]struct { gate: IdentityGate, apply: *const fn (*IdentityInputs) void }{
        .{ .gate = .item_4_withheld, .apply = struct {
            fn f(i: *IdentityInputs) void {
                i.withheld = .none;
            }
        }.f },
        .{ .gate = .item_11_category, .apply = struct {
            fn f(i: *IdentityInputs) void {
                i.category = .none;
            }
        }.f },
        .{ .gate = .item_6_tin, .apply = struct {
            fn f(i: *IdentityInputs) void {
                i.tin_part_2 = "";
            }
        }.f },
        .{ .gate = .item_7_rdo, .apply = struct {
            fn f(i: *IdentityInputs) void {
                i.rdo_selected_index = 0;
            }
        }.f },
        .{ .gate = .item_8_taxpayer_name, .apply = struct {
            fn f(i: *IdentityInputs) void {
                i.taxpayer_name = "";
            }
        }.f },
        .{ .gate = .item_10_telephone, .apply = struct {
            fn f(i: *IdentityInputs) void {
                i.telephone_number = "";
            }
        }.f },
        .{ .gate = .item_9_address, .apply = struct {
            fn f(i: *IdentityInputs) void {
                i.registered_address = "";
            }
        }.f },
        .{ .gate = .item_9a_zip, .apply = struct {
            fn f(i: *IdentityInputs) void {
                i.zip_code = "";
            }
        }.f },
        .{ .gate = .item_12_email, .apply = struct {
            fn f(i: *IdentityInputs) void {
                i.email = "";
            }
        }.f },
    };

    for (cases) |case| {
        var inputs = complete_identity;
        case.apply(&inputs);
        const result = validateIdentity(inputs);
        try std.testing.expect(!result.accepted);
        try std.testing.expectEqual(case.gate, result.failed_gate.?);
        try std.testing.expectEqualStrings(alertFor(case.gate), result.alert.?);
    }
}

test "1601EQ Item 6 covers the branch code and Item 7 keys off selectedIndex" {
    var branch = complete_identity;
    branch.branch_code = "";
    try std.testing.expectEqual(IdentityGate.item_6_tin, validateIdentity(branch).failed_gate.?);

    var rdo = complete_identity;
    rdo.rdo_selected_index = 0;
    try std.testing.expectEqual(IdentityGate.item_7_rdo, validateIdentity(rdo).failed_gate.?);
    rdo.rdo_selected_index = 1;
    try std.testing.expect(validateIdentity(rdo).accepted);
}

test "1601EQ identity gates do not trim, so a single space passes" {
    var spaced = complete_identity;
    spaced.taxpayer_name = " ";
    spaced.registered_address = " ";
    spaced.zip_code = " ";
    spaced.email = " ";
    spaced.telephone_number = " ";
    const result = validateIdentity(spaced);
    try std.testing.expect(result.accepted);
    try std.testing.expect(result.failed_gate == null);
}

test "1601EQ complete identity reaches the Part II ATC gate without claiming success" {
    const result = validateThroughIdentity(.{ .value = 2025 }, .q4, april_2026, complete_identity);
    try std.testing.expect(result.year_quarter.accepted);
    try std.testing.expect(result.identity.?.accepted);
    try std.testing.expect(result.reached_part_ii_atc_gate);
    try std.testing.expect(result.alert == null);
}

test "1601EQ a failed year or quarter gate never reaches the identity gates" {
    const bad_year = validateThroughIdentity(.empty, .q1, april_2026, complete_identity);
    try std.testing.expect(bad_year.identity == null);
    try std.testing.expect(!bad_year.reached_part_ii_atc_gate);
    try std.testing.expectEqualStrings(alert_year_required, bad_year.alert.?);

    var missing_email = complete_identity;
    missing_email.email = "";
    const closed_quarter = validateThroughIdentity(.{ .value = 2026 }, .q4, december_2026, missing_email);
    try std.testing.expect(closed_quarter.identity == null);
    try std.testing.expectEqualStrings(alert_quarter_4, closed_quarter.alert.?);
}
