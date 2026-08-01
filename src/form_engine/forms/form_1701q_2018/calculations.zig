//! Exact, fixed-point calculation core for BIR Form 1701Q January 2018 ENCS.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1701Qv2018.hta`
//! - SHA-256:
//!   `5f164dde6154b96f28e23656ed2ef29406010ee3f94333e88ea6eb107fe589a0`
//! - Stable symbols/lines: `computePartIII` and `computetxt26` through
//!   `computetxt68`, HTA lines 4245-4586.
//! - Numeric helpers: `js/string-util.js` SHA-256
//!   `bc7f86f70bf993389a3a0135dcbd76c3e370c49d2eb95e2fc66ff318a2ebe43c`,
//!   `formatCurrency` lines 321-356 and `NumWithComma` lines 358-362.
//!
//! This is a clean-room transcription of observable rules, not copied
//! implementation source. All repository fixtures below are synthetic. Money
//! is integer centavos; no tax calculation uses binary floating point.

const std = @import("std");

pub const Money = struct {
    centavos: i64,

    pub const zero: Money = .{ .centavos = 0 };

    pub fn fromCentavos(value: i64) Money {
        return .{ .centavos = value };
    }
};

pub const CalculationError = error{Overflow};

pub const Person = enum(u1) {
    taxpayer,
    spouse,
};

pub const SelectionState = struct {
    /// The legacy branch tests only the graduated-rate radio. If it is false,
    /// `computetxt26`/`computetxt63` use the eight-percent result even when the
    /// second radio is also false.
    graduated_rate_checked: bool = false,
    eight_percent_rate_checked: bool = false,
    /// The legacy branch tests only the itemized radio. If it is false,
    /// `computetxt41` uses Item 40 even when the OSD radio is also false.
    itemized_deduction_checked: bool = false,
    optional_deduction_checked: bool = false,
};

pub const PersonInputs = struct {
    txt36: Money = Money.zero,
    txt37: Money = Money.zero,
    txt39: Money = Money.zero,
    txt42: Money = Money.zero,
    txt43: Money = Money.zero,
    txt44: Money = Money.zero,
    txt47: Money = Money.zero,
    txt48: Money = Money.zero,
    txt50: Money = Money.zero,
    txt52: Money = Money.zero,
    txt55_through_61: [7]Money = [_]Money{Money.zero} ** 7,
    txt64_through_66: [3]Money = [_]Money{Money.zero} ** 3,
};

pub const PersonDerived = struct {
    txt26: Money = Money.zero,
    txt27: Money = Money.zero,
    txt28: Money = Money.zero,
    txt29: Money = Money.zero,
    txt30: Money = Money.zero,
    txt38: Money = Money.zero,
    txt40: Money = Money.zero,
    txt41: Money = Money.zero,
    txt45: Money = Money.zero,
    txt46: Money = Money.zero,
    txt49: Money = Money.zero,
    txt51: Money = Money.zero,
    txt53: Money = Money.zero,
    txt54: Money = Money.zero,
    txt62: Money = Money.zero,
    txt63: Money = Money.zero,
    txt67: Money = Money.zero,
    txt68: Money = Money.zero,
};

pub const PersonState = struct {
    selections: SelectionState = .{},
    inputs: PersonInputs = .{},
    derived: PersonDerived = .{},
};

pub const FormState = struct {
    year: i32,
    taxpayer: PersonState = .{},
    spouse: PersonState = .{},
    txt31: Money = Money.zero,

    pub fn person(self: *FormState, which: Person) *PersonState {
        return switch (which) {
            .taxpayer => &self.taxpayer,
            .spouse => &self.spouse,
        };
    }

    pub fn personConst(self: *const FormState, which: Person) *const PersonState {
        return switch (which) {
            .taxpayer => &self.taxpayer,
            .spouse => &self.spouse,
        };
    }
};

/// JavaScript `Math.round(x)` is `floor(x + 0.5)`, including for negative
/// halves. `formatCurrency(Math.round(...))` then renders whole pesos.
fn roundCentavosToWholePesos(value_centavos: i128) CalculationError!Money {
    const whole_pesos = @divFloor(value_centavos + 50, 100);
    return moneyFromWide(whole_pesos * 100);
}

/// Rounds a rational value expressed in pesos with JavaScript `Math.round`
/// semantics. `denominator` is always positive in the grounded rules.
fn roundPesoRatio(
    numerator: i128,
    denominator: i128,
) CalculationError!Money {
    std.debug.assert(denominator > 0);
    const whole_pesos = @divFloor(numerator + @divFloor(denominator, 2), denominator);
    return moneyFromWide(whole_pesos * 100);
}

fn moneyFromWide(value_centavos: i128) CalculationError!Money {
    return Money.fromCentavos(
        std.math.cast(i64, value_centavos) orelse return error.Overflow,
    );
}

fn addMany(values: []const Money) CalculationError!i128 {
    var total: i128 = 0;
    for (values) |value| {
        total += value.centavos;
    }
    return total;
}

/// Grounded in `computePartIII`, HTA lines 4245-4260. Its final call to
/// `computetxt31` intentionally observes the other person's current (possibly
/// stale) Item 30, matching the stateful Desktop event chain.
pub fn computePartIII(
    state: *FormState,
    which: Person,
) CalculationError!void {
    try computeTxt26(state, which);
    const selected = state.person(which);
    selected.derived.txt27 = selected.derived.txt62;
    selected.derived.txt28 = try moneyFromWide(
        @as(i128, selected.derived.txt26.centavos) -
            selected.derived.txt27.centavos,
    );
    selected.derived.txt29 = selected.derived.txt67;
    selected.derived.txt30 = try moneyFromWide(
        @as(i128, selected.derived.txt28.centavos) +
            selected.derived.txt29.centavos,
    );
    try computeTxt31(state);
}

/// Grounded in `computetxt26`, HTA lines 4262-4278.
pub fn computeTxt26(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    selected.derived.txt26 = if (selected.selections.graduated_rate_checked)
        selected.derived.txt46
    else
        selected.derived.txt54;
}

/// Grounded in `computetxt31`, HTA lines 4280-4283.
pub fn computeTxt31(state: *FormState) CalculationError!void {
    state.txt31 = try moneyFromWide(
        @as(i128, state.taxpayer.derived.txt30.centavos) +
            state.spouse.derived.txt30.centavos,
    );
}

/// Grounded in `computetxt38`, HTA lines 4285-4294.
pub fn computeTxt38(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    selected.derived.txt38 = try roundCentavosToWholePesos(
        @as(i128, selected.inputs.txt36.centavos) -
            selected.inputs.txt37.centavos,
    );
    try computeTxt41(state, which);
}

/// Grounded in `computetxt40`, HTA lines 4296-4307.
///
/// The Desktop gate is deliberately form-wide: either person's OSD radio makes
/// this function mutate Item 40 for whichever `person` argument was supplied.
/// The boolean reports whether the legacy function performed that mutation.
pub fn computeTxt40(
    state: *FormState,
    which: Person,
) CalculationError!bool {
    if (!state.taxpayer.selections.optional_deduction_checked and
        !state.spouse.selections.optional_deduction_checked)
    {
        return false;
    }

    const selected = state.person(which);
    selected.derived.txt40 = try roundPesoRatio(
        @as(i128, selected.inputs.txt36.centavos) * 40,
        10_000,
    );
    try computeTxt41(state, which);
    return true;
}

/// Grounded in `computetxt41`, HTA lines 4310-4331.
pub fn computeTxt41(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    const deduction = if (selected.selections.itemized_deduction_checked)
        selected.inputs.txt39
    else
        selected.derived.txt40;
    selected.derived.txt41 = try roundCentavosToWholePesos(
        @as(i128, selected.derived.txt38.centavos) - deduction.centavos,
    );
    try computeTxt45(state, which);
}

/// Grounded in `computetxt45`, HTA lines 4333-4342.
pub fn computeTxt45(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    const values = [_]Money{
        selected.derived.txt41,
        selected.inputs.txt42,
        selected.inputs.txt43,
        selected.inputs.txt44,
    };
    selected.derived.txt45 = try roundCentavosToWholePesos(
        try addMany(&values),
    );
    try computeTxt46(state, which);
}

/// Grounded in `computetxt46`, HTA lines 4344-4479.
pub fn computeTxt46(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    selected.derived.txt46 = try graduatedIncomeTax(
        state.year,
        selected.derived.txt45,
    );
    try computeTxt63(state, which);
}

/// The three tax-table branches and every threshold are exact transcriptions
/// of `computetxt46`. Item 45 is already whole-peso-rounded by the preceding
/// legacy function.
pub fn graduatedIncomeTax(
    year: i32,
    item45: Money,
) CalculationError!Money {
    const value: i128 = item45.centavos;
    if (value <= 0) return Money.zero;

    var numerator: i128 = 0;
    if (year >= 2018 and year <= 2022) {
        if (value <= 250_000 * 100) {
            return Money.zero;
        } else if (value <= 400_000 * 100) {
            numerator = (value - 250_000 * 100) * 20;
        } else if (value <= 800_000 * 100) {
            numerator = (value - 400_000 * 100) * 25 + 30_000 * 10_000;
        } else if (value <= 2_000_000 * 100) {
            numerator = (value - 800_000 * 100) * 30 + 130_000 * 10_000;
        } else if (value <= 8_000_000 * 100) {
            numerator = (value - 2_000_000 * 100) * 32 + 490_000 * 10_000;
        } else {
            numerator = (value - 8_000_000 * 100) * 35 + 2_410_000 * 10_000;
        }
    } else if (year > 2022) {
        if (value <= 250_000 * 100) {
            return Money.zero;
        } else if (value <= 400_000 * 100) {
            numerator = (value - 250_000 * 100) * 15;
        } else if (value <= 800_000 * 100) {
            numerator = (value - 400_000 * 100) * 20 + 22_500 * 10_000;
        } else if (value <= 2_000_000 * 100) {
            numerator = (value - 800_000 * 100) * 25 + 102_500 * 10_000;
        } else if (value <= 8_000_000 * 100) {
            numerator = (value - 2_000_000 * 100) * 30 + 402_500 * 10_000;
        } else {
            numerator = (value - 8_000_000 * 100) * 35 + 2_202_500 * 10_000;
        }
    } else {
        if (value < 10_000 * 100) {
            numerator = value * 5;
        } else if (value < 30_000 * 100) {
            numerator = (value - 10_000 * 100) * 10 + 500 * 10_000;
        } else if (value < 70_000 * 100) {
            numerator = (value - 30_000 * 100) * 15 + 2_500 * 10_000;
        } else if (value < 140_000 * 100) {
            numerator = (value - 70_000 * 100) * 20 + 8_500 * 10_000;
        } else if (value < 250_000 * 100) {
            numerator = (value - 140_000 * 100) * 25 + 22_500 * 10_000;
        } else if (value < 500_000 * 100) {
            numerator = (value - 250_000 * 100) * 30 + 50_000 * 10_000;
        } else {
            numerator = (value - 500_000 * 100) * 32 + 125_000 * 10_000;
        }
    }
    return roundPesoRatio(numerator, 10_000);
}

/// Grounded in `computetxt49`, HTA lines 4481-4490.
pub fn computeTxt49(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    selected.derived.txt49 = try roundCentavosToWholePesos(
        @as(i128, selected.inputs.txt47.centavos) +
            selected.inputs.txt48.centavos,
    );
    try computeTxt51(state, which);
}

/// Grounded in `computetxt51`, HTA lines 4492-4501.
pub fn computeTxt51(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    selected.derived.txt51 = try roundCentavosToWholePesos(
        @as(i128, selected.derived.txt49.centavos) +
            selected.inputs.txt50.centavos,
    );
    try computeTxt53(state, which);
}

/// Grounded in `computetxt53`, HTA lines 4503-4512.
pub fn computeTxt53(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    selected.derived.txt53 = try roundCentavosToWholePesos(
        @as(i128, selected.derived.txt51.centavos) -
            selected.inputs.txt52.centavos,
    );
    try computeTxt54(state, which);
}

/// Grounded in `computetxt54`, HTA lines 4514-4530.
pub fn computeTxt54(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    selected.derived.txt54 = try roundPesoRatio(
        @as(i128, selected.derived.txt53.centavos) * 8,
        10_000,
    );
    if (selected.derived.txt54.centavos < 0) {
        selected.derived.txt54 = Money.zero;
    }
    try computeTxt63(state, which);
}

/// Grounded in `computetxt62`, HTA lines 4532-4541.
pub fn computeTxt62(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    selected.derived.txt62 = try roundCentavosToWholePesos(
        try addMany(&selected.inputs.txt55_through_61),
    );
    try computeTxt63(state, which);
}

/// Grounded in `computetxt63`, HTA lines 4543-4564.
pub fn computeTxt63(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    const tax = if (selected.selections.graduated_rate_checked)
        selected.derived.txt46
    else
        selected.derived.txt54;
    selected.derived.txt63 = try roundCentavosToWholePesos(
        @as(i128, tax.centavos) - selected.derived.txt62.centavos,
    );
    try computeTxt68(state, which);
}

/// Grounded in `computetxt67`, HTA lines 4566-4575.
pub fn computeTxt67(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    selected.derived.txt67 = try roundCentavosToWholePesos(
        try addMany(&selected.inputs.txt64_through_66),
    );
    try computeTxt68(state, which);
}

/// Grounded in `computetxt68`, HTA lines 4577-4586.
pub fn computeTxt68(
    state: *FormState,
    which: Person,
) CalculationError!void {
    const selected = state.person(which);
    selected.derived.txt68 = try roundCentavosToWholePesos(
        @as(i128, selected.derived.txt63.centavos) +
            selected.derived.txt67.centavos,
    );
    try computePartIII(state, which);
}

/// Produces a deterministic, fully converged state from current inputs. The
/// order follows the Desktop dependency/event chains and starts all derived
/// controls at their HTA default `0.00`.
pub fn recalculate(initial: FormState) CalculationError!FormState {
    var state = initial;
    state.taxpayer.derived = .{};
    state.spouse.derived = .{};
    state.txt31 = Money.zero;

    try recalculatePerson(&state, .taxpayer);
    try recalculatePerson(&state, .spouse);
    return state;
}

fn recalculatePerson(
    state: *FormState,
    which: Person,
) CalculationError!void {
    try computeTxt38(state, which);
    _ = try computeTxt40(state, which);
    try computeTxt49(state, which);
    try computeTxt62(state, which);
    try computeTxt67(state, which);
}

fn pesos(value: i64) Money {
    return Money.fromCentavos(value * 100);
}

fn cents(value: i64) Money {
    return Money.fromCentavos(value);
}

test "Math.round whole-peso parity includes negative half behavior" {
    try std.testing.expectEqual(@as(i64, 100), (try roundCentavosToWholePesos(149)).centavos);
    try std.testing.expectEqual(@as(i64, 200), (try roundCentavosToWholePesos(150)).centavos);
    try std.testing.expectEqual(@as(i64, -100), (try roundCentavosToWholePesos(-149)).centavos);
    try std.testing.expectEqual(@as(i64, -100), (try roundCentavosToWholePesos(-150)).centavos);
    try std.testing.expectEqual(@as(i64, -200), (try roundCentavosToWholePesos(-151)).centavos);
}

test "Items 38, 41, and 45 preserve sequential whole-peso rounding" {
    var state: FormState = .{ .year = 2020 };
    state.taxpayer.selections = .{
        .graduated_rate_checked = true,
        .itemized_deduction_checked = true,
    };
    state.taxpayer.inputs.txt36 = cents(100_050);
    state.taxpayer.inputs.txt37 = cents(49_900);
    state.taxpayer.inputs.txt39 = cents(49);
    state.taxpayer.inputs.txt42 = cents(49);
    state.taxpayer.inputs.txt43 = cents(50);
    state.taxpayer.inputs.txt44 = cents(50);

    try computeTxt38(&state, .taxpayer);
    try std.testing.expectEqual(@as(i64, 50_200), state.taxpayer.derived.txt38.centavos);
    try std.testing.expectEqual(@as(i64, 50_200), state.taxpayer.derived.txt41.centavos);
    try std.testing.expectEqual(@as(i64, 50_300), state.taxpayer.derived.txt45.centavos);
}

test "Item 40 retains the legacy cross-person optional-deduction gate" {
    var state: FormState = .{ .year = 2020 };
    state.taxpayer.inputs.txt36 = pesos(100);
    state.taxpayer.derived.txt40 = pesos(777);

    try std.testing.expect(!try computeTxt40(&state, .taxpayer));
    try std.testing.expectEqual(@as(i64, 77_700), state.taxpayer.derived.txt40.centavos);

    state.spouse.selections.optional_deduction_checked = true;
    try std.testing.expect(try computeTxt40(&state, .taxpayer));
    try std.testing.expectEqual(@as(i64, 4_000), state.taxpayer.derived.txt40.centavos);
}

test "2018 through 2022 graduated table boundaries and rounding" {
    const cases = [_]struct { income: i64, tax: i64 }{
        .{ .income = -1, .tax = 0 },
        .{ .income = 250_000, .tax = 0 },
        .{ .income = 250_001, .tax = 0 },
        .{ .income = 250_003, .tax = 1 },
        .{ .income = 400_000, .tax = 30_000 },
        .{ .income = 800_000, .tax = 130_000 },
        .{ .income = 2_000_000, .tax = 490_000 },
        .{ .income = 8_000_000, .tax = 2_410_000 },
        .{ .income = 8_000_100, .tax = 2_410_035 },
    };
    for ([_]i32{ 2018, 2022 }) |year| {
        for (cases) |case| {
            const actual = try graduatedIncomeTax(year, pesos(case.income));
            try std.testing.expectEqual(case.tax * 100, actual.centavos);
        }
    }
}

test "post-2022 graduated table boundaries" {
    const cases = [_]struct { income: i64, tax: i64 }{
        .{ .income = 250_000, .tax = 0 },
        .{ .income = 400_000, .tax = 22_500 },
        .{ .income = 800_000, .tax = 102_500 },
        .{ .income = 2_000_000, .tax = 402_500 },
        .{ .income = 8_000_000, .tax = 2_202_500 },
        .{ .income = 8_000_100, .tax = 2_202_535 },
    };
    for (cases) |case| {
        const actual = try graduatedIncomeTax(2023, pesos(case.income));
        try std.testing.expectEqual(case.tax * 100, actual.centavos);
    }
}

test "pre-2018 graduated table boundaries" {
    const cases = [_]struct { income: i64, tax: i64 }{
        .{ .income = 0, .tax = 0 },
        .{ .income = 9_999, .tax = 500 },
        .{ .income = 10_000, .tax = 500 },
        .{ .income = 30_000, .tax = 2_500 },
        .{ .income = 70_000, .tax = 8_500 },
        .{ .income = 140_000, .tax = 22_500 },
        .{ .income = 250_000, .tax = 50_000 },
        .{ .income = 500_000, .tax = 125_000 },
        .{ .income = 500_100, .tax = 125_032 },
    };
    for (cases) |case| {
        const actual = try graduatedIncomeTax(2017, pesos(case.income));
        try std.testing.expectEqual(case.tax * 100, actual.centavos);
    }
}

test "Items 49, 51, 53, and 54 round at every legacy node and floor tax at zero" {
    var state: FormState = .{ .year = 2023 };
    state.taxpayer.inputs.txt47 = cents(149);
    state.taxpayer.inputs.txt48 = Money.zero;
    state.taxpayer.inputs.txt50 = cents(-50);
    state.taxpayer.inputs.txt52 = pesos(2);

    try computeTxt49(&state, .taxpayer);
    try std.testing.expectEqual(@as(i64, 100), state.taxpayer.derived.txt49.centavos);
    try std.testing.expectEqual(@as(i64, 100), state.taxpayer.derived.txt51.centavos);
    try std.testing.expectEqual(@as(i64, -100), state.taxpayer.derived.txt53.centavos);
    try std.testing.expectEqual(@as(i64, 0), state.taxpayer.derived.txt54.centavos);
}

test "withholding and penalty sums feed Part III and aggregate spouses" {
    var state: FormState = .{ .year = 2023 };
    state.taxpayer.selections.eight_percent_rate_checked = true;
    state.spouse.selections.eight_percent_rate_checked = true;
    state.taxpayer.derived.txt54 = pesos(1_000);
    state.spouse.derived.txt54 = pesos(2_000);
    state.taxpayer.inputs.txt55_through_61[0] = pesos(100);
    state.spouse.inputs.txt55_through_61[0] = pesos(200);
    state.taxpayer.inputs.txt64_through_66[0] = pesos(10);
    state.spouse.inputs.txt64_through_66[0] = pesos(20);

    try computeTxt62(&state, .taxpayer);
    try computeTxt67(&state, .taxpayer);
    try computeTxt62(&state, .spouse);
    try computeTxt67(&state, .spouse);

    try std.testing.expectEqual(@as(i64, 91_000), state.taxpayer.derived.txt30.centavos);
    try std.testing.expectEqual(@as(i64, 182_000), state.spouse.derived.txt30.centavos);
    try std.testing.expectEqual(@as(i64, 273_000), state.txt31.centavos);
}

test "full recalculation converges both rate branches deterministically" {
    var input: FormState = .{ .year = 2023 };
    input.taxpayer.selections = .{
        .graduated_rate_checked = true,
        .itemized_deduction_checked = true,
    };
    input.taxpayer.inputs.txt36 = pesos(500_000);
    input.taxpayer.inputs.txt55_through_61[0] = pesos(1_000);
    input.taxpayer.inputs.txt64_through_66[0] = pesos(100);

    input.spouse.selections = .{
        .eight_percent_rate_checked = true,
        .optional_deduction_checked = true,
    };
    input.spouse.inputs.txt47 = pesos(300_000);
    input.spouse.inputs.txt52 = pesos(250_000);

    const first = try recalculate(input);
    const second = try recalculate(first);
    try std.testing.expectEqualDeep(first, second);
    try std.testing.expectEqual(first.taxpayer.derived.txt46, first.taxpayer.derived.txt26);
    try std.testing.expectEqual(first.spouse.derived.txt54, first.spouse.derived.txt26);
}

test "fixed-point core fails closed on unrepresentable output" {
    var state: FormState = .{ .year = 2023 };
    state.taxpayer.derived.txt30 = Money.fromCentavos(std.math.maxInt(i64));
    state.spouse.derived.txt30 = Money.fromCentavos(1);
    try std.testing.expectError(error.Overflow, computeTxt31(&state));
}
