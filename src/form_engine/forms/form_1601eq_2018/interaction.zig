//! HTA-local 1601EQ interaction: over-remittance exclusive choice and the
//! amended-return gate for Item 22.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601EQ.hta`
//! - SHA-256:
//!   `cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96`
//! - `optAmend:Y` onclick line 311 (enable Item 22)
//! - `optAmend:N` onclick line 312 (disable, zero, `computeTotalTaxCredit`)
//! - `checkRefund` lines 3116-3121
//! - `checkIssueCert` lines 3124-3129
//! - `checkCarriedOver` lines 3132-3137
//! - `computeOfTotalAmtDue` else-branch uncheck, lines 3088-3094
//!
//! Checking one over-remittance mark unchecks the other two. Unchecking a
//! mark does not check another. When choices are not enabled (Item 30 is
//! not negative), every mark is cleared. Amended Yes enables Item 22
//! without recomputing. Amended No disables Item 22, zeros it, and reruns
//! remittance totals. This is not a handler implementation:
//! `handlers_implemented` stays false.

const std = @import("std");
const calculations = @import("calculations.zig");
const control_contract = @import("control_contract.zig");
const evidence = @import("evidence.zig");
const event_contract = @import("event_contract.zig");

/// Full UI interaction is not ready. Exclusive choice and Item 22's
/// amended-return gate are.
pub const ready = false;
pub const exclusive_choice_ready = true;
pub const amended_item22_ready = true;

pub const Mark = enum {
    refund,
    issue_cert,
    carried_over,
};

pub const OverRemittanceMarks = struct {
    refund: bool = false,
    issue_cert: bool = false,
    carried_over: bool = false,

    pub const none: OverRemittanceMarks = .{};

    pub fn isChecked(self: OverRemittanceMarks, mark: Mark) bool {
        return switch (mark) {
            .refund => self.refund,
            .issue_cert => self.issue_cert,
            .carried_over => self.carried_over,
        };
    }
};

/// Post-click exclusive choice. `marks` is the post-toggle checkbox state.
/// Disabled choices follow `computeOfTotalAmtDue`: all three unchecked.
pub fn applyClickedMark(
    enabled: bool,
    clicked: Mark,
    marks: OverRemittanceMarks,
) OverRemittanceMarks {
    if (!enabled) return OverRemittanceMarks.none;
    if (!marks.isChecked(clicked)) return marks;
    return switch (clicked) {
        .refund => .{ .refund = true },
        .issue_cert => .{ .issue_cert = true },
        .carried_over => .{ .carried_over = true },
    };
}

/// HTA `checkRefund` lines 3116-3121.
pub fn applyCheckRefund(enabled: bool, marks: OverRemittanceMarks) OverRemittanceMarks {
    return applyClickedMark(enabled, .refund, marks);
}

/// HTA `checkIssueCert` lines 3124-3129.
pub fn applyCheckIssueCert(enabled: bool, marks: OverRemittanceMarks) OverRemittanceMarks {
    return applyClickedMark(enabled, .issue_cert, marks);
}

/// HTA `checkCarriedOver` lines 3132-3137.
pub fn applyCheckCarriedOver(enabled: bool, marks: OverRemittanceMarks) OverRemittanceMarks {
    return applyClickedMark(enabled, .carried_over, marks);
}

pub const AmendReturn = enum { no, yes };

pub const AmendedItem22 = struct {
    amended: AmendReturn,
    item_22_enabled: bool,
    item_22: calculations.Money,
    /// Set only for Amend No, whose onclick calls `computeTotalTaxCredit`.
    derived: ?calculations.Derived = null,
    over_remittance_marks: OverRemittanceMarks = OverRemittanceMarks.none,
};

/// `optAmend:Y` onclick line 311: enable Item 22. Value, totals, and marks
/// are unchanged.
pub fn applyAmendYes(
    item_22: calculations.Money,
    marks: OverRemittanceMarks,
) AmendedItem22 {
    return .{
        .amended = .yes,
        .item_22_enabled = true,
        .item_22 = item_22,
        .over_remittance_marks = marks,
    };
}

/// `optAmend:N` onclick line 312: disable Item 22, set it to 0.00, recompute
/// remittance totals. `computeOfTotalAmtDue` then clears over-remittance
/// marks when Item 30 is not negative.
pub fn applyAmendNo(
    inputs: calculations.Inputs,
    marks: OverRemittanceMarks,
) calculations.CalculationError!AmendedItem22 {
    var next = inputs;
    next.item_22 = calculations.Money.zero;
    const derived = try calculations.computeRemittanceTotals(next);
    return .{
        .amended = .no,
        .item_22_enabled = false,
        .item_22 = calculations.Money.zero,
        .derived = derived,
        .over_remittance_marks = if (derived.over_remittance_choices_enabled)
            marks
        else
            OverRemittanceMarks.none,
    };
}

test "1601EQ over-remittance exclusive choice stays unreconciled and unimplemented as handlers" {
    try std.testing.expect(exclusive_choice_ready);
    try std.testing.expect(amended_item22_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!event_contract.handlers_implemented);
    try std.testing.expect(!evidence.readiness.identityReady());
    try std.testing.expect(!evidence.readiness.dependency_closure);
}

test "1601EQ checking one over-remittance mark unchecks the other two" {
    const from_issue_cert = applyCheckRefund(true, .{
        .refund = true,
        .issue_cert = true,
        .carried_over = false,
    });
    try std.testing.expect(from_issue_cert.refund);
    try std.testing.expect(!from_issue_cert.issue_cert);
    try std.testing.expect(!from_issue_cert.carried_over);

    const from_refund = applyCheckIssueCert(true, .{
        .refund = true,
        .issue_cert = true,
        .carried_over = true,
    });
    try std.testing.expect(!from_refund.refund);
    try std.testing.expect(from_refund.issue_cert);
    try std.testing.expect(!from_refund.carried_over);

    const from_both = applyCheckCarriedOver(true, .{
        .refund = true,
        .issue_cert = true,
        .carried_over = true,
    });
    try std.testing.expect(!from_both.refund);
    try std.testing.expect(!from_both.issue_cert);
    try std.testing.expect(from_both.carried_over);
}

test "1601EQ unchecking an over-remittance mark does not check another" {
    const marks = applyCheckRefund(true, .{
        .refund = false,
        .issue_cert = false,
        .carried_over = false,
    });
    try std.testing.expectEqual(OverRemittanceMarks.none, marks);
}

test "1601EQ disabled over-remittance choices clear every mark" {
    const marks = applyCheckRefund(false, .{
        .refund = true,
        .issue_cert = true,
        .carried_over = true,
    });
    try std.testing.expectEqual(OverRemittanceMarks.none, marks);
    try std.testing.expectEqual(
        OverRemittanceMarks.none,
        applyCheckIssueCert(false, .{ .issue_cert = true }),
    );
    try std.testing.expectEqual(
        OverRemittanceMarks.none,
        applyCheckCarriedOver(false, .{ .carried_over = true }),
    );
}

test "1601EQ amended Yes enables Item 22 without zeroing or recomputing" {
    try std.testing.expect(!control_contract.find("frm1601EQ:txtTax22").?.disabled_in_markup);
    const marks: OverRemittanceMarks = .{ .refund = true };
    const result = applyAmendYes(calculations.Money.fromCentavos(250_00), marks);
    try std.testing.expectEqual(AmendReturn.yes, result.amended);
    try std.testing.expect(result.item_22_enabled);
    try std.testing.expectEqual(@as(i64, 250_00), result.item_22.centavos);
    try std.testing.expect(result.derived == null);
    try std.testing.expect(result.over_remittance_marks.refund);
    try std.testing.expect(!result.over_remittance_marks.issue_cert);
}

test "1601EQ amended No zeros Item 22 and reruns remittance totals" {
    const result = try applyAmendNo(.{
        .item_19 = calculations.Money.fromCentavos(10_000_00),
        .item_20 = calculations.Money.fromCentavos(1_000_00),
        .item_22 = calculations.Money.fromCentavos(3_000_00),
        .item_23 = calculations.Money.fromCentavos(400_00),
    }, .{ .refund = true });
    try std.testing.expectEqual(AmendReturn.no, result.amended);
    try std.testing.expect(!result.item_22_enabled);
    try std.testing.expectEqual(@as(i64, 0), result.item_22.centavos);
    const derived = result.derived.?;
    try std.testing.expectEqual(@as(i64, 1_400_00), derived.item_24.centavos);
    try std.testing.expectEqual(@as(i64, 8_600_00), derived.item_25.centavos);
    try std.testing.expectEqual(@as(i64, 8_600_00), derived.item_30.centavos);
    try std.testing.expect(!derived.over_remittance_choices_enabled);
    try std.testing.expectEqual(OverRemittanceMarks.none, result.over_remittance_marks);
}

test "1601EQ amended No keeps over-remittance marks when Item 30 stays negative" {
    const result = try applyAmendNo(.{
        .item_19 = calculations.Money.fromCentavos(100_00),
        .item_20 = calculations.Money.fromCentavos(250_00),
        .item_22 = calculations.Money.fromCentavos(10_00),
    }, .{ .carried_over = true });
    const derived = result.derived.?;
    try std.testing.expectEqual(@as(i64, 250_00), derived.item_24.centavos);
    try std.testing.expectEqual(@as(i64, -150_00), derived.item_30.centavos);
    try std.testing.expect(derived.over_remittance_choices_enabled);
    try std.testing.expect(result.over_remittance_marks.carried_over);
    try std.testing.expect(!result.over_remittance_marks.refund);
}
