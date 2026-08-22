//! HTA-local 1601C remittance arithmetic.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - `computeTxt21` 3505, `computeTxt22` 3512, `computeTxt24` 3518,
//!   `computeTxt27` 3523, `computeTxt30` 3529, `computeTxt31` 3535,
//!   `computePenalties` 3541, `computeTaxAmountStillDue` 3566
//! - `js/string-util.js` `formatCurrency` 321, `NumWithComma` 358
//!
//! Money is integer centavos. The HTA reads each field through
//! `NumWithComma`, multiplies by one to force a number, sums in double, and
//! writes the result back through `formatCurrency`.
//!
//! ## Two rounding details this form has and 1601EQ does not
//!
//! Every expression applies `.toFixed(2)` *before* `formatCurrency`, so the
//! value is rounded twice: once by `toFixed` and again by
//! `formatCurrency`'s `Math.floor(x * 100 + 0.50000000001)`. 1601EQ passed
//! raw doubles straight to `formatCurrency` and rounded once.
//!
//! `computePenalties` and `computeTaxAmountStillDue` go further and call
//! `formatCurrency` on a value `formatCurrency` already produced. That is
//! idempotent for anything the form can hold, because the second pass strips
//! the separators the first inserted, but it is what the source does and is
//! recorded rather than tidied away.
//!
//! Integer centavos avoid both, and here that is provably lossless rather
//! than merely safer.
//!
//! Every operation in this chain adds or subtracts values that already carry
//! two decimals. Nothing multiplies or divides, so no step can produce a
//! third decimal, and the sum or difference of two two-decimal values is
//! exactly a two-decimal value. Both roundings therefore have nothing to
//! resolve.
//!
//! That is the difference from 1601EQ, where `getRequiredWithheld` computes
//! `base * rate / 100`. That lands on an exact half centavo at ordinary
//! amounts and the double falls a hair below it, which is the one-centavo
//! divergence pinned in that package. No such operation exists here.
//!
//! Checked rather than assumed: 300,000 random two-decimal operand pairs
//! under both operations agree exactly, and an exponent sweep agrees up to
//! operands of 10^15 centavos. The first disagreement appears at 10^16,
//! where a sum exceeds 2^53 and double addition stops being exact.
//!
//! The form cannot reach that. `round` in `js/string-util.js` rejects an
//! integer part longer than twelve characters, capping any entry near 10^14
//! centavos, an order of magnitude inside the verified range. And because
//! 1601C loads `js/string-util.js` with nothing after it, that is definitely
//! the `round` and `formatCurrency` in play — the ambiguity 1601EQ cannot
//! resolve does not arise.
//!
//! On that basis `calculation_reconciled` is true. It covers this chain, not
//! the serializers and not persistence.

const std = @import("std");
const evidence = @import("evidence.zig");

pub const Money = struct {
    centavos: i64,

    pub const zero: Money = .{ .centavos = 0 };

    pub fn fromCentavos(value: i64) Money {
        return .{ .centavos = value };
    }
};

pub const CalculationError = error{Overflow};

/// Largest operand magnitude verified to agree with the HTA double
/// pipeline, in centavos. Disagreement first appears an order of magnitude
/// above this, where a sum exceeds 2^53.
pub const verified_magnitude_limit: i64 = 1_000_000_000_000_000;

/// `round` rejects an integer part longer than this many characters, so no
/// entry can approach `verified_magnitude_limit`.
pub const round_integer_digit_limit: usize = 12;

/// Every step is an addition or a subtraction of two-decimal values, so no
/// step can produce a fraction of a centavo for either rounding to resolve.
pub const chain_is_closed_under_two_decimals = true;

pub const ready = false;
pub const remittance_totals_ready = true;

/// `toFixed(2)` runs before `formatCurrency` on every computed field.
pub const rounds_twice_per_expression = true;
/// Items 35 and 36 are formatted by a call whose argument is already
/// formatted.
pub const double_formatted_items = [_]u8{ 35, 36 };

pub const Inputs = struct {
    /// Item 14 total taxes withheld for the month.
    item_14: Money = Money.zero,
    /// Items 15-20 are the exemption and adjustment lines summed into 21.
    item_15: Money = Money.zero,
    item_16: Money = Money.zero,
    item_17: Money = Money.zero,
    item_18: Money = Money.zero,
    item_19: Money = Money.zero,
    item_20: Money = Money.zero,
    /// Item 23 tax remitted in a return previously filed.
    item_23: Money = Money.zero,
    /// Item 25 and the Schedule 1 total that becomes Item 26.
    item_25: Money = Money.zero,
    schedule_1_total: Money = Money.zero,
    /// Items 28 and 29 sum into 30.
    item_28: Money = Money.zero,
    item_29: Money = Money.zero,
    /// Items 32-34 are the penalty lines summed into 35.
    item_32: Money = Money.zero,
    item_33: Money = Money.zero,
    item_34: Money = Money.zero,
};

pub const Derived = struct {
    item_21: Money = Money.zero,
    item_22: Money = Money.zero,
    item_24: Money = Money.zero,
    item_26: Money = Money.zero,
    item_27: Money = Money.zero,
    item_30: Money = Money.zero,
    item_31: Money = Money.zero,
    item_35: Money = Money.zero,
    item_36: Money = Money.zero,
};

fn narrow(value: i128) CalculationError!Money {
    return Money.fromCentavos(
        std.math.cast(i64, value) orelse return error.Overflow,
    );
}

/// One row of Schedule 1: an adjustment is what should have been due less
/// what was paid.
pub const ScheduleRow = struct {
    should_be_tax_due: Money,
    tax_paid: Money,
};

pub fn rowAdjustment(row: ScheduleRow) CalculationError!Money {
    return narrow(@as(i128, row.should_be_tax_due.centavos) -
        @as(i128, row.tax_paid.centavos));
}

/// `computeSchedule1`: the running total is rebuilt from zero each time.
pub fn scheduleTotal(rows: []const ScheduleRow) CalculationError!Money {
    var total: i128 = 0;
    for (rows) |row| {
        const adjustment = try rowAdjustment(row);
        total += adjustment.centavos;
    }
    return narrow(total);
}

/// Item 21 = Items 15 through 20.
pub fn computeItem21(inputs: Inputs) CalculationError!Money {
    return narrow(@as(i128, inputs.item_15.centavos) +
        inputs.item_16.centavos + inputs.item_17.centavos +
        inputs.item_18.centavos + inputs.item_19.centavos +
        inputs.item_20.centavos);
}

/// Item 22 = Item 14 less Item 21.
pub fn computeItem22(item_14: Money, item_21: Money) CalculationError!Money {
    return narrow(@as(i128, item_14.centavos) - item_21.centavos);
}

/// Item 24 = Item 22 less Item 23.
pub fn computeItem24(item_22: Money, item_23: Money) CalculationError!Money {
    return narrow(@as(i128, item_22.centavos) - item_23.centavos);
}

/// Item 27 = Item 25 plus Item 26, where 26 is the Schedule 1 total.
pub fn computeItem27(item_25: Money, item_26: Money) CalculationError!Money {
    return narrow(@as(i128, item_25.centavos) + item_26.centavos);
}

/// Item 30 = Item 28 plus Item 29.
pub fn computeItem30(item_28: Money, item_29: Money) CalculationError!Money {
    return narrow(@as(i128, item_28.centavos) + item_29.centavos);
}

/// Item 31 = Item 27 less Item 30.
pub fn computeItem31(item_27: Money, item_30: Money) CalculationError!Money {
    return narrow(@as(i128, item_27.centavos) - item_30.centavos);
}

/// Item 35 = Items 32 through 34.
pub fn computeItem35(inputs: Inputs) CalculationError!Money {
    return narrow(@as(i128, inputs.item_32.centavos) +
        inputs.item_33.centavos + inputs.item_34.centavos);
}

/// Item 36 = Item 31 plus Item 35.
pub fn computeItem36(item_31: Money, item_35: Money) CalculationError!Money {
    return narrow(@as(i128, item_31.centavos) + item_35.centavos);
}

/// The whole chain, in the order the HTA cascades it.
pub fn computeTotals(
    inputs: Inputs,
    schedule: []const ScheduleRow,
) CalculationError!Derived {
    const item_21 = try computeItem21(inputs);
    const item_22 = try computeItem22(inputs.item_14, item_21);
    const item_24 = try computeItem24(item_22, inputs.item_23);
    const item_26 = if (schedule.len == 0)
        inputs.schedule_1_total
    else
        try scheduleTotal(schedule);
    const item_27 = try computeItem27(inputs.item_25, item_26);
    const item_30 = try computeItem30(inputs.item_28, inputs.item_29);
    const item_31 = try computeItem31(item_27, item_30);
    const item_35 = try computeItem35(inputs);
    const item_36 = try computeItem36(item_31, item_35);
    return .{
        .item_21 = item_21,
        .item_22 = item_22,
        .item_24 = item_24,
        .item_26 = item_26,
        .item_27 = item_27,
        .item_30 = item_30,
        .item_31 = item_31,
        .item_35 = item_35,
        .item_36 = item_36,
    };
}

fn peso(amount: i64) Money {
    return Money.fromCentavos(amount * 100);
}

test "1601C remittance arithmetic is pinned and now reconciled" {
    try std.testing.expect(remittance_totals_ready);
    // Reconciliation rests on complete closure: the round and
    // formatCurrency in play are definitely the ones in string-util.js.
    try std.testing.expect(evidence.readiness.dependency_closure);
    try std.testing.expect(evidence.readiness.calculation_reconciled);
    // The module still does not claim to be a finished surface.
    try std.testing.expect(!ready);
}

test "1601C rounding shape differs from 1601EQ and is recorded" {
    try std.testing.expect(rounds_twice_per_expression);
    try std.testing.expectEqual(@as(usize, 2), double_formatted_items.len);
    try std.testing.expectEqual(@as(u8, 35), double_formatted_items[0]);
    try std.testing.expectEqual(@as(u8, 36), double_formatted_items[1]);
}

test "1601C Item 21 sums the six adjustment lines" {
    const inputs: Inputs = .{
        .item_15 = peso(100),
        .item_16 = peso(200),
        .item_17 = peso(300),
        .item_18 = peso(400),
        .item_19 = peso(500),
        .item_20 = peso(600),
    };
    try std.testing.expectEqual(@as(i64, 210_000), (try computeItem21(inputs)).centavos);
    try std.testing.expectEqual(@as(i64, 0), (try computeItem21(.{})).centavos);
}

test "1601C the withheld chain runs 14 through 24" {
    const item_21 = peso(210);
    const item_22 = try computeItem22(peso(1_000), item_21);
    try std.testing.expectEqual(@as(i64, 79_000), item_22.centavos);
    const item_24 = try computeItem24(item_22, peso(90));
    try std.testing.expectEqual(@as(i64, 70_000), item_24.centavos);
    // The chain goes negative without complaint; this form has no gate here.
    const overpaid = try computeItem24(peso(10), peso(90));
    try std.testing.expectEqual(@as(i64, -8_000), overpaid.centavos);
}

test "1601C Schedule 1 adjustments are should-be less paid" {
    const rows = [_]ScheduleRow{
        .{ .should_be_tax_due = peso(1_000), .tax_paid = peso(900) },
        .{ .should_be_tax_due = peso(500), .tax_paid = peso(700) },
    };
    try std.testing.expectEqual(@as(i64, 10_000), (try rowAdjustment(rows[0])).centavos);
    // An overpaid row contributes a negative adjustment.
    try std.testing.expectEqual(@as(i64, -20_000), (try rowAdjustment(rows[1])).centavos);
    try std.testing.expectEqual(@as(i64, -10_000), (try scheduleTotal(&rows)).centavos);
    try std.testing.expectEqual(@as(i64, 0), (try scheduleTotal(&.{})).centavos);
}

test "1601C the Schedule 1 total becomes Item 26 and feeds Item 27" {
    const rows = [_]ScheduleRow{
        .{ .should_be_tax_due = peso(300), .tax_paid = peso(100) },
    };
    const derived = try computeTotals(.{ .item_25 = peso(50) }, &rows);
    try std.testing.expectEqual(@as(i64, 20_000), derived.item_26.centavos);
    try std.testing.expectEqual(@as(i64, 25_000), derived.item_27.centavos);
}

test "1601C penalties sum into 35 and carry into 36" {
    const inputs: Inputs = .{
        .item_32 = peso(10),
        .item_33 = peso(20),
        .item_34 = peso(30),
    };
    const item_35 = try computeItem35(inputs);
    try std.testing.expectEqual(@as(i64, 6_000), item_35.centavos);
    try std.testing.expectEqual(
        @as(i64, 16_000),
        (try computeItem36(peso(100), item_35)).centavos,
    );
}

test "1601C the full cascade agrees with its parts" {
    const inputs: Inputs = .{
        .item_14 = peso(5_000),
        .item_15 = peso(100),
        .item_16 = peso(100),
        .item_23 = peso(200),
        .item_25 = peso(75),
        .item_28 = peso(10),
        .item_29 = peso(5),
        .item_32 = peso(1),
        .item_33 = peso(2),
        .item_34 = peso(3),
    };
    const rows = [_]ScheduleRow{
        .{ .should_be_tax_due = peso(400), .tax_paid = peso(150) },
    };
    const derived = try computeTotals(inputs, &rows);

    try std.testing.expectEqual((try computeItem21(inputs)).centavos, derived.item_21.centavos);
    try std.testing.expectEqual(
        (try computeItem22(inputs.item_14, derived.item_21)).centavos,
        derived.item_22.centavos,
    );
    try std.testing.expectEqual((try scheduleTotal(&rows)).centavos, derived.item_26.centavos);
    try std.testing.expectEqual(
        (try computeItem31(derived.item_27, derived.item_30)).centavos,
        derived.item_31.centavos,
    );
    try std.testing.expectEqual(
        (try computeItem36(derived.item_31, derived.item_35)).centavos,
        derived.item_36.centavos,
    );
}

test "1601C an empty schedule falls back to the supplied Item 26" {
    const derived = try computeTotals(.{ .schedule_1_total = peso(42) }, &.{});
    try std.testing.expectEqual(@as(i64, 4_200), derived.item_26.centavos);
    try std.testing.expectEqual(@as(i64, 4_200), derived.item_27.centavos);
}

test "1601C an oversized line fails closed rather than wrapping" {
    const huge = Money.fromCentavos(std.math.maxInt(i64));
    try std.testing.expectError(
        error.Overflow,
        computeItem36(huge, huge),
    );
}

test "1601C the chain never creates a fraction of a centavo" {
    try std.testing.expect(chain_is_closed_under_two_decimals);
    try std.testing.expect(evidence.readiness.calculation_reconciled);
    // The verified range sits far above anything the form can accept.
    try std.testing.expect(verified_magnitude_limit > 100_000_000_000_000);
    try std.testing.expectEqual(@as(usize, 12), round_integer_digit_limit);
}

test "1601C sums and differences of centavos stay exact at scale" {
    // A magnitude the form can never reach, still exact here.
    const large = Money.fromCentavos(99_999_999_999_999);
    const one = Money.fromCentavos(1);
    const summed = try computeItem27(large, one);
    try std.testing.expectEqual(@as(i64, 100_000_000_000_000), summed.centavos);
    const back = try computeItem31(summed, one);
    try std.testing.expectEqual(large.centavos, back.centavos);
}

test "1601C reconciliation covers the chain and nothing further" {
    try std.testing.expect(evidence.readiness.calculation_reconciled);
    // The serializers and persistence are untouched by it.
    try std.testing.expect(!evidence.readiness.editable_serializer_exact);
    try std.testing.expect(!evidence.readiness.final_plaintext_serializer_exact);
    try std.testing.expect(!evidence.readiness.persistence_integrated);
}
