//! HTA-local remittance totals for BIR Form 1601EQ January 2018 ENCS.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601EQ.hta`
//! - SHA-256:
//!   `cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96`
//! - `computeTotalTaxCredit` lines 3099-3106 (Items 24 and 25)
//! - `computePenalties` lines 3109-3113 (Item 29)
//! - `computeOfTotalAmtDue` lines 3081-3096 (Item 30 and over-remittance gate)
//!
//! This is a clean-room transcription of those four sums/differences. Money
//! is integer centavos; no tax calculation uses binary floating point.
//! ATC rate lookup, dynamic ATC rows, and `formatCurrency` are not
//! implemented. `calculation_reconciled` stays false.

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

/// Full ATC/remittance calculation is not ready. These four totals are.
pub const ready = false;
pub const remittance_totals_ready = true;
pub const atc_lookup_ready = false;

pub const Inputs = struct {
    /// Item 19 Tax Withheld. An input here because ATC row summation is
    /// unobserved and not implemented.
    item_19: Money = Money.zero,
    item_20: Money = Money.zero,
    item_21: Money = Money.zero,
    item_22: Money = Money.zero,
    item_23: Money = Money.zero,
    item_26: Money = Money.zero,
    item_27: Money = Money.zero,
    item_28: Money = Money.zero,
};

pub const Derived = struct {
    item_24: Money = Money.zero,
    item_25: Money = Money.zero,
    item_29: Money = Money.zero,
    item_30: Money = Money.zero,
    /// `computeOfTotalAmtDue` enables the three over-remittance marks iff
    /// Item 30 is negative. This flag is the comparison only; it does not
    /// mutate markup.
    over_remittance_choices_enabled: bool = false,
};

fn moneyFromWide(value_centavos: i128) CalculationError!Money {
    return Money.fromCentavos(
        std.math.cast(i64, value_centavos) orelse return error.Overflow,
    );
}

/// Item 24 = Item 20 + Item 21 + Item 22 + Item 23.
/// HTA `computeTotalTaxCredit` line 3100.
pub fn computeItem24(inputs: Inputs) CalculationError!Money {
    return moneyFromWide(
        @as(i128, inputs.item_20.centavos) +
            inputs.item_21.centavos +
            inputs.item_22.centavos +
            inputs.item_23.centavos,
    );
}

/// Item 25 = Item 19 − Item 24. Negative is over-remittance.
/// HTA `computeTotalTaxCredit` line 3103.
pub fn computeItem25(item_19: Money, item_24: Money) CalculationError!Money {
    return moneyFromWide(
        @as(i128, item_19.centavos) - item_24.centavos,
    );
}

/// Item 29 = Item 26 + Item 27 + Item 28.
/// HTA `computePenalties` lines 3110-3111.
pub fn computeItem29(inputs: Inputs) CalculationError!Money {
    return moneyFromWide(
        @as(i128, inputs.item_26.centavos) +
            inputs.item_27.centavos +
            inputs.item_28.centavos,
    );
}

/// Item 30 = Item 25 + Item 29.
/// HTA `computeOfTotalAmtDue` line 3082.
pub fn computeItem30(item_25: Money, item_29: Money) CalculationError!Money {
    return moneyFromWide(
        @as(i128, item_25.centavos) + item_29.centavos,
    );
}

/// One remittance pass in HTA order: 24, 25, 29, then 30.
pub fn computeRemittanceTotals(inputs: Inputs) CalculationError!Derived {
    const item_24 = try computeItem24(inputs);
    const item_25 = try computeItem25(inputs.item_19, item_24);
    const item_29 = try computeItem29(inputs);
    const item_30 = try computeItem30(item_25, item_29);
    return .{
        .item_24 = item_24,
        .item_25 = item_25,
        .item_29 = item_29,
        .item_30 = item_30,
        .over_remittance_choices_enabled = item_30.centavos < 0,
    };
}

test "1601EQ remittance totals stay unreconciled and skip ATC lookup" {
    try std.testing.expect(remittance_totals_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!atc_lookup_ready);
    try std.testing.expect(!evidence.readiness.calculation_reconciled);
    try std.testing.expect(!evidence.readiness.identityReady());
    try std.testing.expect(!evidence.readiness.dependency_closure);
}

test "1601EQ Item 24 sums credits and Item 25 subtracts them from withheld" {
    const derived = try computeRemittanceTotals(.{
        .item_19 = Money.fromCentavos(10_000_00),
        .item_20 = Money.fromCentavos(1_000_00),
        .item_21 = Money.fromCentavos(2_000_00),
        .item_22 = Money.fromCentavos(3_000_00),
        .item_23 = Money.fromCentavos(400_00),
    });
    try std.testing.expectEqual(@as(i64, 6_400_00), derived.item_24.centavos);
    try std.testing.expectEqual(@as(i64, 3_600_00), derived.item_25.centavos);
    try std.testing.expectEqual(@as(i64, 0), derived.item_29.centavos);
    try std.testing.expectEqual(@as(i64, 3_600_00), derived.item_30.centavos);
    try std.testing.expect(!derived.over_remittance_choices_enabled);
}

test "1601EQ Item 25 preserves negative over-remittance" {
    const derived = try computeRemittanceTotals(.{
        .item_19 = Money.fromCentavos(100_00),
        .item_20 = Money.fromCentavos(250_00),
    });
    try std.testing.expectEqual(@as(i64, 250_00), derived.item_24.centavos);
    try std.testing.expectEqual(@as(i64, -150_00), derived.item_25.centavos);
    try std.testing.expectEqual(@as(i64, -150_00), derived.item_30.centavos);
    try std.testing.expect(derived.over_remittance_choices_enabled);
}

test "1601EQ Item 29 sums penalties into Item 30" {
    const derived = try computeRemittanceTotals(.{
        .item_19 = Money.fromCentavos(1_000_00),
        .item_26 = Money.fromCentavos(10_00),
        .item_27 = Money.fromCentavos(20_00),
        .item_28 = Money.fromCentavos(5_00),
    });
    try std.testing.expectEqual(@as(i64, 0), derived.item_24.centavos);
    try std.testing.expectEqual(@as(i64, 1_000_00), derived.item_25.centavos);
    try std.testing.expectEqual(@as(i64, 35_00), derived.item_29.centavos);
    try std.testing.expectEqual(@as(i64, 1_035_00), derived.item_30.centavos);
    try std.testing.expect(!derived.over_remittance_choices_enabled);
}

test "1601EQ remittance totals fail closed on overflow" {
    const huge = Money.fromCentavos(std.math.maxInt(i64));
    try std.testing.expectError(error.Overflow, computeItem24(.{
        .item_20 = huge,
        .item_21 = Money.fromCentavos(1),
    }));
    try std.testing.expectError(error.Overflow, computeItem29(.{
        .item_26 = huge,
        .item_27 = Money.fromCentavos(1),
    }));
}
