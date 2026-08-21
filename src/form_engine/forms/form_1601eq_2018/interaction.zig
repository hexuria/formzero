//! HTA-local 1601EQ interaction: over-remittance exclusive choice, the
//! amended-return gate for Item 22, and the Validate/Edit lock.
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
//! - `cmdValidate` onclick line 1002, `cmdEdit` onclick line 1003
//! - `disableAllControl` lines 3295-3352
//! - `enableAllControl` lines 3353-3406
//! - `changeCategory` lines 3411-3448, `optCategory` onclick lines 521-522
//! - `changeTaxWithheldNO` lines 3449-3483, `optWithheld:N` onclick 337
//!
//! Checking one over-remittance mark unchecks the other two. Unchecking a
//! mark does not check another. When choices are not enabled (Item 30 is
//! not negative), every mark is cleared. Amended Yes enables Item 22
//! without recomputing. Amended No disables Item 22, zeros it, and reruns
//! remittance totals. This is not a handler implementation:
//! `handlers_implemented` stays false.
//!
//! Validate and Edit are not inverses. `enableAllControl` never re-enables
//! the Background Information section: it re-disables `txtTIN1`, `txtTIN2`,
//! `txtTIN3` and `txtBranchCode` on its last statement and omits the other
//! seven controls entirely. `txtTax19` is touched by neither transition, so
//! Item 19 is never locked. `btnOtherTax` is enabled by Edit but never
//! disabled by Validate. Both transitions also walk a `txtTaxBase` loop
//! whose bound is a live row count over rows added by absent scripts; that
//! loop and the `qs('xmlFileName')` Import branch are not pinned.
//!
//! Switching Item 4 to No or changing Item 11 clears Items 19-30 behind a
//! `confirm()`, but only when an ATC is already chosen. Cancelling undoes
//! the click: Item 4 returns to Yes, and Item 11 flips to the category that
//! was not clicked. The ATC table teardown those pipelines also perform
//! (`populateAtcPart2`, `changedrpATCList`, the `AtcCode` checkbox sweep and
//! `lblOtherTax`) reads the ATC catalog and is not pinned.

const std = @import("std");
const calculations = @import("calculations.zig");
const control_contract = @import("control_contract.zig");
const evidence = @import("evidence.zig");
const event_contract = @import("event_contract.zig");
const validation = @import("validation.zig");

/// Full UI interaction is not ready. Exclusive choice and Item 22's
/// amended-return gate are.
pub const ready = false;
pub const exclusive_choice_ready = true;
pub const amended_item22_ready = true;
pub const validate_lock_ready = true;
pub const computation_reset_ready = true;

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

/// One `element.disabled = <bool>` statement, in HTA source order.
pub const ControlDisable = struct {
    id: []const u8,
    source_line: u32,
    disabled: bool,
};

/// `disableAllControl` lines 3295-3352, static statements in source order.
/// Its `txtTaxBase` loop is excluded: the bound is a live row count and the
/// rows it walks are added by absent scripts.
pub const validate_lock = [_]ControlDisable{
    .{ .id = "frm1601EQ:btnFinalCopy", .source_line = 3298, .disabled = false },
    .{ .id = "frm1601EQ:txtYear", .source_line = 3301, .disabled = true },
    .{ .id = "frm1601EQ:optQuarter:1", .source_line = 3302, .disabled = true },
    .{ .id = "frm1601EQ:optQuarter:2", .source_line = 3303, .disabled = true },
    .{ .id = "frm1601EQ:optQuarter:3", .source_line = 3304, .disabled = true },
    .{ .id = "frm1601EQ:optQuarter:4", .source_line = 3305, .disabled = true },
    .{ .id = "frm1601EQ:optAmend:Y", .source_line = 3306, .disabled = true },
    .{ .id = "frm1601EQ:optAmend:N", .source_line = 3307, .disabled = true },
    .{ .id = "frm1601EQ:optWithheld:Y", .source_line = 3308, .disabled = true },
    .{ .id = "frm1601EQ:optWithheld:N", .source_line = 3309, .disabled = true },
    .{ .id = "frm1601EQ:txtNoSheets", .source_line = 3310, .disabled = true },
    .{ .id = "frm1601EQ:txtTIN1", .source_line = 3313, .disabled = true },
    .{ .id = "frm1601EQ:txtTIN2", .source_line = 3314, .disabled = true },
    .{ .id = "frm1601EQ:txtTIN3", .source_line = 3315, .disabled = true },
    .{ .id = "frm1601EQ:txtBranchCode", .source_line = 3316, .disabled = true },
    .{ .id = "frm1601EQ:txtRDOCode", .source_line = 3317, .disabled = true },
    .{ .id = "frm1601EQ:txtTaxpayerName", .source_line = 3318, .disabled = true },
    .{ .id = "frm1601EQ:txtAddress", .source_line = 3319, .disabled = true },
    .{ .id = "frm1601EQ:txtAddress2", .source_line = 3320, .disabled = true },
    .{ .id = "frm1601EQ:txtZipCode", .source_line = 3321, .disabled = true },
    .{ .id = "frm1601EQ:txtTelNum", .source_line = 3322, .disabled = true },
    .{ .id = "txtEmail", .source_line = 3323, .disabled = true },
    .{ .id = "frm1601EQ:optCategory:P", .source_line = 3324, .disabled = true },
    .{ .id = "frm1601EQ:optCategory:G", .source_line = 3325, .disabled = true },
    .{ .id = "frm1601EQ:txtTax20", .source_line = 3328, .disabled = true },
    .{ .id = "frm1601EQ:txtTax21", .source_line = 3329, .disabled = true },
    .{ .id = "frm1601EQ:txtTax22", .source_line = 3330, .disabled = true },
    .{ .id = "frm1601EQ:txtTax23", .source_line = 3331, .disabled = true },
    .{ .id = "frm1601EQ:txtTax26", .source_line = 3332, .disabled = true },
    .{ .id = "frm1601EQ:txtTax27", .source_line = 3333, .disabled = true },
    .{ .id = "frm1601EQ:txtTax28", .source_line = 3334, .disabled = true },
    .{ .id = "btnClearOtherAtc", .source_line = 3343, .disabled = true },
    .{ .id = "btnAddATCPartII", .source_line = 3344, .disabled = true },
    .{ .id = "btnPrintOtherAtc", .source_line = 3345, .disabled = false },
    .{ .id = "menuPrintPreview", .source_line = 3346, .disabled = false },
    .{ .id = "btnPrint", .source_line = 3347, .disabled = false },
};

/// `enableAllControl` lines 3353-3406, unconditional static statements in
/// source order. Excluded: the Item 22 if/else at 3383/3385, which
/// `editUnlockItem22` models; the `qs('xmlFileName')` year re-disable at
/// 3398, which is the Import path and out of scope; and the guarded
/// `txtTaxBase` loop. The four TIN re-disables at 3403 are unconditional
/// and are kept.
pub const edit_unlock = [_]ControlDisable{
    .{ .id = "frm1601EQ:txtYear", .source_line = 3354, .disabled = false },
    .{ .id = "frm1601EQ:optQuarter:1", .source_line = 3355, .disabled = false },
    .{ .id = "frm1601EQ:optQuarter:2", .source_line = 3356, .disabled = false },
    .{ .id = "frm1601EQ:optQuarter:3", .source_line = 3357, .disabled = false },
    .{ .id = "frm1601EQ:optQuarter:4", .source_line = 3358, .disabled = false },
    .{ .id = "frm1601EQ:optAmend:Y", .source_line = 3359, .disabled = false },
    .{ .id = "frm1601EQ:optAmend:N", .source_line = 3360, .disabled = false },
    .{ .id = "frm1601EQ:optWithheld:Y", .source_line = 3361, .disabled = false },
    .{ .id = "frm1601EQ:optWithheld:N", .source_line = 3362, .disabled = false },
    .{ .id = "frm1601EQ:txtNoSheets", .source_line = 3363, .disabled = false },
    .{ .id = "frm1601EQ:optCategory:P", .source_line = 3365, .disabled = false },
    .{ .id = "frm1601EQ:optCategory:G", .source_line = 3366, .disabled = false },
    .{ .id = "frm1601EQ:txtTax20", .source_line = 3368, .disabled = false },
    .{ .id = "frm1601EQ:txtTax21", .source_line = 3369, .disabled = false },
    .{ .id = "frm1601EQ:txtTax23", .source_line = 3370, .disabled = false },
    .{ .id = "frm1601EQ:txtTax26", .source_line = 3371, .disabled = false },
    .{ .id = "frm1601EQ:txtTax27", .source_line = 3372, .disabled = false },
    .{ .id = "frm1601EQ:txtTax28", .source_line = 3373, .disabled = false },
    .{ .id = "btnPrintOtherAtc", .source_line = 3387, .disabled = true },
    .{ .id = "btnClearOtherAtc", .source_line = 3388, .disabled = false },
    .{ .id = "btnOtherTax", .source_line = 3389, .disabled = false },
    .{ .id = "btnAddATCPartII", .source_line = 3390, .disabled = false },
    .{ .id = "frm1601EQ:cmdValidate", .source_line = 3391, .disabled = false },
    .{ .id = "menuPrintPreview", .source_line = 3392, .disabled = true },
    .{ .id = "frm1601EQ:cmdEdit", .source_line = 3393, .disabled = true },
    .{ .id = "frm1601EQ:btnFinalCopy", .source_line = 3394, .disabled = true },
    .{ .id = "btnPrint", .source_line = 3395, .disabled = true },
    .{ .id = "frm1601EQ:txtTIN1", .source_line = 3403, .disabled = true },
    .{ .id = "frm1601EQ:txtTIN2", .source_line = 3403, .disabled = true },
    .{ .id = "frm1601EQ:txtTIN3", .source_line = 3403, .disabled = true },
    .{ .id = "frm1601EQ:txtBranchCode", .source_line = 3403, .disabled = true },
};

/// Controls that Validate disables and Edit never re-enables: the entire
/// Background Information section. `txtTIN1`, `txtTIN2`, `txtTIN3` and
/// `txtBranchCode` are explicitly re-disabled on the last statement of
/// `enableAllControl`; the other seven are simply omitted from it. Item 22
/// is not here because Edit restores it conditionally.
pub const never_reenabled_by_edit = [_][]const u8{
    "frm1601EQ:txtAddress",
    "frm1601EQ:txtAddress2",
    "frm1601EQ:txtBranchCode",
    "frm1601EQ:txtRDOCode",
    "frm1601EQ:txtTIN1",
    "frm1601EQ:txtTIN2",
    "frm1601EQ:txtTIN3",
    "frm1601EQ:txtTaxpayerName",
    "frm1601EQ:txtTelNum",
    "frm1601EQ:txtZipCode",
    "txtEmail",
};

/// Item 22, HTA lines 3382-3386: Edit reopens it only for an amended
/// return, and otherwise re-disables it. This mirrors the amend gate.
pub fn editUnlockItem22(amend: AmendReturn) bool {
    return amend != .yes;
}

/// Disabled state after `disableAllControl`, or null when the transition
/// does not touch the control. Item 19 and Part III are untouched.
pub fn disabledAfterValidate(id: []const u8) ?bool {
    return lastAssignment(&validate_lock, id);
}

/// Disabled state after `enableAllControl`, or null when the transition
/// does not touch the control. Item 22 is conditional, so it is answered
/// from `editUnlockItem22` rather than from the table.
pub fn disabledAfterEdit(id: []const u8, amend: AmendReturn) ?bool {
    if (std.mem.eql(u8, id, "frm1601EQ:txtTax22")) return editUnlockItem22(amend);
    return lastAssignment(&edit_unlock, id);
}

/// HTA statements run in order, so a repeated id settles on its last write.
fn lastAssignment(table: []const ControlDisable, id: []const u8) ?bool {
    var found: ?bool = null;
    for (table) |entry| {
        if (std.mem.eql(u8, entry.id, id)) found = entry.disabled;
    }
    return found;
}

/// Answer to the HTA `confirm()` dialog raised by both reset pipelines.
pub const Confirm = enum { cancelled, confirmed };

/// The twelve money fields both pipelines set to `(0).toFixed(2)`, in HTA
/// statement order. Item 19 and the four derived totals are included: the
/// reset writes them directly rather than recomputing.
pub const reset_money_items = [_]u8{ 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30 };

/// Cleared money state. Zeroing every input leaves the derived totals at
/// zero too, so the direct writes agree with `computeRemittanceTotals`.
pub const cleared_inputs: calculations.Inputs = .{};

pub const WithheldReset = struct {
    /// HTA raised its confirm dialog.
    prompted: bool,
    /// Items 19-30 were written to zero.
    cleared: bool,
    /// Item 4 after the pipeline.
    withheld: validation.Withheld,
    /// Module-level `taxWheldFlag` after the pipeline.
    tax_wheld_flag: bool,
};

/// `changeTaxWithheldNO`, the `optWithheld:N` onclick at line 337.
///
/// The whole body is guarded by `taxWheldFlag`, which only `optWithheld:Y`'s
/// own onclick sets. Clicking No without having clicked Yes first does
/// nothing at all. Cancelling re-checks Yes, so the click is undone.
pub fn applyWithheldNo(
    tax_wheld_flag: bool,
    first_atc_code: []const u8,
    answer: Confirm,
) WithheldReset {
    if (!tax_wheld_flag) {
        return .{ .prompted = false, .cleared = false, .withheld = .no, .tax_wheld_flag = false };
    }
    if (first_atc_code.len == 0) {
        return .{ .prompted = false, .cleared = false, .withheld = .no, .tax_wheld_flag = false };
    }
    return switch (answer) {
        .confirmed => .{ .prompted = true, .cleared = true, .withheld = .no, .tax_wheld_flag = false },
        .cancelled => .{ .prompted = true, .cleared = false, .withheld = .yes, .tax_wheld_flag = true },
    };
}

pub const CategoryReset = struct {
    prompted: bool,
    cleared: bool,
    /// Item 11 after the pipeline.
    category: validation.Category,
    /// HTA calls `changedrpATCList` for the resulting category. The reload
    /// itself is not pinned: it reads the ATC catalog.
    reloads_atc_list: bool,
};

/// `changeCategory`, the `optCategory:P` / `optCategory:G` onclick at lines
/// 521-522.
///
/// Cancelling reverts to the other category rather than restoring a
/// remembered one: HTA assumes exactly two, and flips to whichever was not
/// clicked.
pub fn applyCategoryChange(
    clicked: validation.Category,
    first_atc_code: []const u8,
    answer: Confirm,
) CategoryReset {
    if (first_atc_code.len == 0) {
        return .{ .prompted = false, .cleared = false, .category = clicked, .reloads_atc_list = true };
    }
    return switch (answer) {
        .confirmed => .{ .prompted = true, .cleared = true, .category = clicked, .reloads_atc_list = true },
        .cancelled => .{
            .prompted = true,
            .cleared = false,
            .category = switch (clicked) {
                .private => .government,
                .government => .private,
                .none => .none,
            },
            .reloads_atc_list = false,
        },
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

test "1601EQ Validate lock and Edit unlock are pinned but handlers are not" {
    try std.testing.expect(validate_lock_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!event_contract.handlers_implemented);
    try std.testing.expectEqual(@as(usize, 36), validate_lock.len);
}

test "1601EQ Validate locks Part I, background info and the Part II amount inputs" {
    try std.testing.expect(disabledAfterValidate("frm1601EQ:txtYear").?);
    try std.testing.expect(disabledAfterValidate("frm1601EQ:optWithheld:Y").?);
    try std.testing.expect(disabledAfterValidate("frm1601EQ:txtTIN1").?);
    try std.testing.expect(disabledAfterValidate("txtEmail").?);
    try std.testing.expect(disabledAfterValidate("frm1601EQ:txtTax20").?);
    try std.testing.expect(disabledAfterValidate("frm1601EQ:txtTax28").?);

    // Validate enables the outputs it gates.
    try std.testing.expect(!disabledAfterValidate("frm1601EQ:btnFinalCopy").?);
    try std.testing.expect(!disabledAfterValidate("btnPrint").?);
    try std.testing.expect(!disabledAfterValidate("menuPrintPreview").?);
    try std.testing.expect(disabledAfterValidate("btnAddATCPartII").?);
}

test "1601EQ Item 19 and Part III are untouched by both transitions" {
    try std.testing.expect(disabledAfterValidate("frm1601EQ:txtTax19") == null);
    try std.testing.expect(disabledAfterEdit("frm1601EQ:txtTax19", .no) == null);
    try std.testing.expect(disabledAfterValidate("frm1601EQ:txtTax33") == null);
}

test "1601EQ Edit never reopens the background information section" {
    try std.testing.expectEqual(@as(usize, 11), never_reenabled_by_edit.len);
    for (never_reenabled_by_edit) |id| {
        try std.testing.expect(disabledAfterValidate(id).?);
        // Either explicitly re-disabled or never mentioned by Edit.
        const after_edit = disabledAfterEdit(id, .yes);
        if (after_edit) |state| try std.testing.expect(state);
    }

    // The four TIN controls are the explicit re-disables, not omissions.
    try std.testing.expect(disabledAfterEdit("frm1601EQ:txtTIN1", .yes).?);
    try std.testing.expect(disabledAfterEdit("frm1601EQ:txtBranchCode", .yes).?);
    // The rest are simply absent from enableAllControl.
    try std.testing.expect(disabledAfterEdit("frm1601EQ:txtRDOCode", .yes) == null);
    try std.testing.expect(disabledAfterEdit("txtEmail", .yes) == null);
}

test "1601EQ never_reenabled_by_edit matches the two pinned tables" {
    for (validate_lock) |locked| {
        if (!locked.disabled) continue;
        if (std.mem.eql(u8, locked.id, "frm1601EQ:txtTax22")) continue;
        var reopened = false;
        for (edit_unlock) |unlocked| {
            if (std.mem.eql(u8, unlocked.id, locked.id) and !unlocked.disabled) reopened = true;
        }
        var listed = false;
        for (never_reenabled_by_edit) |id| {
            if (std.mem.eql(u8, id, locked.id)) listed = true;
        }
        try std.testing.expectEqual(!reopened, listed);
    }
}

test "1601EQ Edit restores Part I and returns the buttons to the editing state" {
    try std.testing.expect(!disabledAfterEdit("frm1601EQ:txtYear", .no).?);
    try std.testing.expect(!disabledAfterEdit("frm1601EQ:optQuarter:1", .no).?);
    try std.testing.expect(!disabledAfterEdit("frm1601EQ:optCategory:G", .no).?);
    try std.testing.expect(!disabledAfterEdit("frm1601EQ:cmdValidate", .no).?);
    try std.testing.expect(disabledAfterEdit("frm1601EQ:cmdEdit", .no).?);
    try std.testing.expect(disabledAfterEdit("frm1601EQ:btnFinalCopy", .no).?);
    try std.testing.expect(disabledAfterEdit("btnPrint", .no).?);
    try std.testing.expect(disabledAfterEdit("menuPrintPreview", .no).?);
}

test "1601EQ Edit restores Item 22 only for an amended return" {
    try std.testing.expect(!editUnlockItem22(.yes));
    try std.testing.expect(editUnlockItem22(.no));
    try std.testing.expect(!disabledAfterEdit("frm1601EQ:txtTax22", .yes).?);
    try std.testing.expect(disabledAfterEdit("frm1601EQ:txtTax22", .no).?);
}

test "1601EQ btnOtherTax is enabled by Edit but never disabled by Validate" {
    try std.testing.expect(disabledAfterValidate("btnOtherTax") == null);
    try std.testing.expect(!disabledAfterEdit("btnOtherTax", .no).?);
}

test "1601EQ computation reset is pinned but the ATC teardown is not" {
    try std.testing.expect(computation_reset_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!calculations.atc_lookup_ready);
    try std.testing.expectEqual(@as(usize, 12), reset_money_items.len);
    try std.testing.expectEqual(@as(u8, 19), reset_money_items[0]);
    try std.testing.expectEqual(@as(u8, 30), reset_money_items[11]);
}

test "1601EQ clearing every input leaves the derived totals at zero" {
    const derived = try calculations.computeRemittanceTotals(cleared_inputs);
    try std.testing.expectEqual(@as(i64, 0), derived.item_24.centavos);
    try std.testing.expectEqual(@as(i64, 0), derived.item_25.centavos);
    try std.testing.expectEqual(@as(i64, 0), derived.item_29.centavos);
    try std.testing.expectEqual(@as(i64, 0), derived.item_30.centavos);
    // Item 30 is not negative, so the over-remittance marks stay unavailable.
    try std.testing.expect(!derived.over_remittance_choices_enabled);
}

test "1601EQ Item 4 No does nothing when Yes was never clicked" {
    const result = applyWithheldNo(false, "WC010", .confirmed);
    try std.testing.expect(!result.prompted);
    try std.testing.expect(!result.cleared);
    try std.testing.expectEqual(validation.Withheld.no, result.withheld);
    try std.testing.expect(!result.tax_wheld_flag);
}

test "1601EQ Item 4 No skips the prompt when no ATC is chosen" {
    const result = applyWithheldNo(true, "", .confirmed);
    try std.testing.expect(!result.prompted);
    try std.testing.expect(!result.cleared);
    try std.testing.expectEqual(validation.Withheld.no, result.withheld);
    try std.testing.expect(!result.tax_wheld_flag);
}

test "1601EQ confirming Item 4 No clears the computation" {
    const result = applyWithheldNo(true, "WC010", .confirmed);
    try std.testing.expect(result.prompted);
    try std.testing.expect(result.cleared);
    try std.testing.expectEqual(validation.Withheld.no, result.withheld);
    try std.testing.expect(!result.tax_wheld_flag);
}

test "1601EQ cancelling Item 4 No undoes the click and keeps the computation" {
    const result = applyWithheldNo(true, "WC010", .cancelled);
    try std.testing.expect(result.prompted);
    try std.testing.expect(!result.cleared);
    try std.testing.expectEqual(validation.Withheld.yes, result.withheld);
    try std.testing.expect(result.tax_wheld_flag);
}

test "1601EQ changing category without an ATC reloads the list without prompting" {
    const result = applyCategoryChange(.government, "", .confirmed);
    try std.testing.expect(!result.prompted);
    try std.testing.expect(!result.cleared);
    try std.testing.expectEqual(validation.Category.government, result.category);
    try std.testing.expect(result.reloads_atc_list);
}

test "1601EQ confirming a category change clears the computation and reloads" {
    const result = applyCategoryChange(.government, "WC010", .confirmed);
    try std.testing.expect(result.prompted);
    try std.testing.expect(result.cleared);
    try std.testing.expectEqual(validation.Category.government, result.category);
    try std.testing.expect(result.reloads_atc_list);
}

test "1601EQ cancelling a category change flips to the category not clicked" {
    const to_government = applyCategoryChange(.government, "WC010", .cancelled);
    try std.testing.expect(to_government.prompted);
    try std.testing.expect(!to_government.cleared);
    try std.testing.expectEqual(validation.Category.private, to_government.category);
    try std.testing.expect(!to_government.reloads_atc_list);

    const to_private = applyCategoryChange(.private, "WC010", .cancelled);
    try std.testing.expectEqual(validation.Category.government, to_private.category);
    try std.testing.expect(!to_private.reloads_atc_list);
}

test "1601EQ neither reset trims, so a space counts as a chosen ATC" {
    try std.testing.expect(applyWithheldNo(true, " ", .confirmed).prompted);
    try std.testing.expect(applyCategoryChange(.private, " ", .confirmed).prompted);
}
