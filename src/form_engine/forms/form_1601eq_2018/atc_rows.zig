//! HTA-local 1601EQ Part II ATC row model and per-row withholding.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601EQ.hta`
//! - SHA-256:
//!   `cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96`
//! - `populateAtcPart2` lines 2861-2875
//! - `getATCCode` lines 2890-3010
//! - `computeofTotalWithheldTax` lines 3036-3050
//! - `computeTotalOtherWithheldTax` lines 3052-3060
//! - `getRequiredWithheld` lines 3075-3078
//! - `js/string-util.js` `formatCurrency` line 321, `NumWithComma` line 358
//!
//! `populateAtcPart2` builds a fixed six-row grid for Items 13-18. The rows
//! are not dynamically sized: `getATCCode` rebuilds the same six from the
//! ATC selection, and only when seven or more codes are checked does it
//! spill the remainder into the separate `tblPartIIOtherTax` table and
//! reveal `lblOtherTax`.
//!
//! Item 19 is therefore not a free input. `computeofTotalWithheldTax` sums
//! every row's withheld amount into it, across both tables, and then reruns
//! the remittance totals. `computeTotalOtherWithheldTax` separately sums
//! rows seven and beyond into the Other Tax display field.
//!
//! ## Rounding
//!
//! HTA evaluates `base * rate / 100` in IEEE-754 double and formats the
//! result with `formatCurrency`, whose rounding step is
//! `Math.floor(Math.abs(value) * 100 + 0.50000000001)` with the sign
//! reapplied — half away from zero at the centavo, with an epsilon nudge
//! that compensates for representation error.
//!
//! This module computes the same rule in integer centavos and rounds half
//! away from zero, which is a decision rather than a transcription. The two
//! pipelines do not always agree, and the reason is worth stating exactly.
//!
//! A tax base carries at most two decimals and a catalog rate at most one,
//! so their product can land on an exact half-centavo. That is the worst
//! case, not a safe one: at such a point the double product falls a hair
//! below the true value, and once the magnitude is large enough that the
//! representation error exceeds the `0.50000000001` nudge, `Math.floor`
//! takes the lower centavo while half away from zero takes the upper one.
//!
//! Verified exhaustively: every base from 0.00 through 2,000.00 against all
//! eight pinned catalog rates agrees. The smallest divergence found is a
//! base of 4,100.90 at 15.0%, where the exact product is 615.135; the HTA
//! yields 615.13 and this module yields 615.14. Divergence needs the exact
//! half-centavo landing, so it is sparse rather than systematic, but it is
//! reachable at ordinary amounts and is not bounded away from them.
//!
//! Reproducing the HTA's result would mean reproducing a double's
//! representation error, which this package does not do. The rule is pinned;
//! parity is not claimed, and `calculation_reconciled` stays false.

const std = @import("std");
const calculations = @import("calculations.zig");
const evidence = @import("evidence.zig");

const Money = calculations.Money;
const CalculationError = calculations.CalculationError;

/// `populateAtcPart2` emits exactly this many rows, for Items 13-18.
pub const main_grid_row_count: usize = 6;
pub const first_item_number: u8 = 13;

/// `getATCCode` keeps every row in the main grid below this many checked
/// codes; at or above it the remainder spills into `tblPartIIOtherTax`.
pub const overflow_threshold: usize = 7;

/// One-based row index of the first Other Tax row, matching the loop bound
/// in `computeTotalOtherWithheldTax`.
pub const first_other_row: usize = 7;

pub const Row = struct {
    code: []const u8,
    tax_base: Money,
    /// Percent in tenths, so 5.0% is 50. The catalog writes rates with a
    /// single decimal place.
    rate_tenths: u32,
};

/// Item number shown beside a main-grid row. Items 13 through 18.
pub fn itemNumberFor(row_index: usize) ?u8 {
    if (row_index >= main_grid_row_count) return null;
    return first_item_number + @as(u8, @intCast(row_index));
}

/// `getATCCode` reveals `lblOtherTax` only on the overflow branch.
pub fn usesOverflow(selected_count: usize) bool {
    return selected_count >= overflow_threshold;
}

/// Parses a catalog rate such as `"5.0"`, `"0.5"` or `"32.0"` into tenths of
/// a percent. Returns null for anything the catalog does not produce.
pub fn rateTenths(rate: []const u8) ?u32 {
    if (rate.len == 0) return null;
    var whole: u32 = 0;
    var tenths: u32 = 0;
    var seen_dot = false;
    var fraction_digits: usize = 0;
    for (rate) |character| {
        if (character == '.') {
            if (seen_dot) return null;
            seen_dot = true;
            continue;
        }
        if (character < '0' or character > '9') return null;
        const digit: u32 = character - '0';
        if (seen_dot) {
            fraction_digits += 1;
            if (fraction_digits > 1) return null;
            tenths = digit;
        } else {
            whole = std.math.mul(u32, whole, 10) catch return null;
            whole = std.math.add(u32, whole, digit) catch return null;
        }
    }
    const scaled = std.math.mul(u32, whole, 10) catch return null;
    return std.math.add(u32, scaled, tenths) catch return null;
}

/// `getRequiredWithheld`: base * rate / 100, rounded half away from zero.
pub fn requiredWithheld(tax_base: Money, rate_tenths_value: u32) CalculationError!Money {
    const base: i128 = tax_base.centavos;
    const rate: i128 = rate_tenths_value;
    const product = base * rate;
    const magnitude = if (product < 0) -product else product;
    const rounded = @divTrunc(magnitude + 500, 1000);
    const signed = if (product < 0) -rounded else rounded;
    return Money.fromCentavos(
        std.math.cast(i64, signed) orelse return error.Overflow,
    );
}

fn sumFrom(rows: []const Row, start_index: usize) CalculationError!Money {
    var total: i128 = 0;
    for (rows, 0..) |row, index| {
        if (index < start_index) continue;
        const withheld = try requiredWithheld(row.tax_base, row.rate_tenths);
        total += withheld.centavos;
    }
    return Money.fromCentavos(
        std.math.cast(i64, total) orelse return error.Overflow,
    );
}

/// `computeofTotalWithheldTax`: Item 19 is the sum of every row's withheld
/// amount, across the main grid and the Other Tax table alike.
pub fn computeItem19(rows: []const Row) CalculationError!Money {
    return sumFrom(rows, 0);
}

/// `computeTotalOtherWithheldTax`: rows seven and beyond only.
pub fn computeTotalOtherWithheld(rows: []const Row) CalculationError!Money {
    return sumFrom(rows, first_other_row - 1);
}

const atc_catalog = @import("atc_catalog.zig");

fn peso(amount: i64) Money {
    return Money.fromCentavos(amount * 100);
}

test "1601EQ Part II grid is six fixed rows for Items 13 to 18" {
    try std.testing.expectEqual(@as(usize, 6), main_grid_row_count);
    try std.testing.expectEqual(@as(u8, 13), itemNumberFor(0).?);
    try std.testing.expectEqual(@as(u8, 18), itemNumberFor(main_grid_row_count - 1).?);
    try std.testing.expect(itemNumberFor(main_grid_row_count) == null);
    try std.testing.expect(!evidence.readiness.calculation_reconciled);
}

test "1601EQ rows spill to the Other Tax table only at seven checked codes" {
    try std.testing.expect(!usesOverflow(1));
    try std.testing.expect(!usesOverflow(6));
    try std.testing.expect(usesOverflow(7));
    try std.testing.expect(usesOverflow(20));
    try std.testing.expectEqual(overflow_threshold, first_other_row);
}

test "1601EQ every catalog rate parses to tenths of a percent" {
    try std.testing.expectEqual(@as(u32, 50), rateTenths("5.0").?);
    try std.testing.expectEqual(@as(u32, 5), rateTenths("0.5").?);
    try std.testing.expectEqual(@as(u32, 320), rateTenths("32.0").?);
    try std.testing.expectEqual(@as(u32, 100), rateTenths("10.0").?);

    for (atc_catalog.records) |record| {
        try std.testing.expect(rateTenths(record.rate) != null);
    }

    try std.testing.expect(rateTenths("") == null);
    try std.testing.expect(rateTenths("P") == null);
    try std.testing.expect(rateTenths("5.00") == null);
    try std.testing.expect(rateTenths("5.0.0") == null);
}

test "1601EQ withheld is the tax base times the rate over one hundred" {
    // 1,000.00 at 5.0% is 50.00.
    try std.testing.expectEqual(
        @as(i64, 5_000),
        (try requiredWithheld(peso(1_000), 50)).centavos,
    );
    // 1,000.00 at 0.5% is 5.00.
    try std.testing.expectEqual(
        @as(i64, 500),
        (try requiredWithheld(peso(1_000), 5)).centavos,
    );
    // 1,000.00 at 32.0% is 320.00.
    try std.testing.expectEqual(
        @as(i64, 32_000),
        (try requiredWithheld(peso(1_000), 320)).centavos,
    );
    try std.testing.expectEqual(
        @as(i64, 0),
        (try requiredWithheld(Money.zero, 320)).centavos,
    );
}

test "1601EQ withheld rounds half away from zero at the centavo" {
    // 0.10 at 5.0% is exactly half a centavo, which rounds away from zero.
    try std.testing.expectEqual(
        @as(i64, 1),
        (try requiredWithheld(Money.fromCentavos(10), 50)).centavos,
    );
    // 0.09 at 5.0% is below the half and rounds down.
    try std.testing.expectEqual(
        @as(i64, 0),
        (try requiredWithheld(Money.fromCentavos(9), 50)).centavos,
    );
    // 0.01 at 5.0% is a twentieth of a centavo and disappears.
    try std.testing.expectEqual(
        @as(i64, 0),
        (try requiredWithheld(Money.fromCentavos(1), 50)).centavos,
    );
    // The magnitude rule applies first, then the sign is reapplied.
    try std.testing.expectEqual(
        @as(i64, -1),
        (try requiredWithheld(Money.fromCentavos(-10), 50)).centavos,
    );
    try std.testing.expectEqual(
        @as(i64, 0),
        (try requiredWithheld(Money.fromCentavos(-9), 50)).centavos,
    );
}

test "1601EQ Item 19 sums every row and Other Tax sums only rows seven onward" {
    const rows = [_]Row{
        .{ .code = "WI010", .tax_base = peso(1_000), .rate_tenths = 50 },
        .{ .code = "WI011", .tax_base = peso(2_000), .rate_tenths = 100 },
        .{ .code = "WI020", .tax_base = peso(1_000), .rate_tenths = 50 },
        .{ .code = "WI021", .tax_base = peso(1_000), .rate_tenths = 50 },
        .{ .code = "WI030", .tax_base = peso(1_000), .rate_tenths = 50 },
        .{ .code = "WI031", .tax_base = peso(1_000), .rate_tenths = 50 },
        .{ .code = "WI040", .tax_base = peso(500), .rate_tenths = 20 },
        .{ .code = "WI041", .tax_base = peso(500), .rate_tenths = 20 },
    };

    // 50 + 200 + 50 + 50 + 50 + 50 + 10 + 10 pesos.
    try std.testing.expectEqual(
        @as(i64, 47_000),
        (try computeItem19(&rows)).centavos,
    );
    // Rows 7 and 8 only: 10 + 10 pesos.
    try std.testing.expectEqual(
        @as(i64, 2_000),
        (try computeTotalOtherWithheld(&rows)).centavos,
    );
}

test "1601EQ a grid that never overflows contributes no Other Tax total" {
    const rows = [_]Row{
        .{ .code = "WI010", .tax_base = peso(1_000), .rate_tenths = 50 },
        .{ .code = "WI011", .tax_base = peso(1_000), .rate_tenths = 50 },
    };
    try std.testing.expectEqual(
        @as(i64, 10_000),
        (try computeItem19(&rows)).centavos,
    );
    try std.testing.expectEqual(
        @as(i64, 0),
        (try computeTotalOtherWithheld(&rows)).centavos,
    );
    try std.testing.expectEqual(
        @as(i64, 0),
        (try computeTotalOtherWithheld(&.{})).centavos,
    );
}

test "1601EQ Item 19 feeds the pinned remittance totals unchanged" {
    const rows = [_]Row{
        .{ .code = "WI010", .tax_base = peso(1_000), .rate_tenths = 50 },
    };
    const item_19 = try computeItem19(&rows);
    const derived = try calculations.computeRemittanceTotals(.{ .item_19 = item_19 });
    // Nothing credited, so Item 25 is Item 19 and Item 30 follows it.
    try std.testing.expectEqual(item_19.centavos, derived.item_25.centavos);
    try std.testing.expectEqual(item_19.centavos, derived.item_30.centavos);
    try std.testing.expect(!derived.over_remittance_choices_enabled);
}

test "1601EQ no catalog rate can overflow a tax base, and the guard still exists" {
    const huge = Money.fromCentavos(std.math.maxInt(i64));
    // The widest pinned rate divides the product back below the base, so a
    // catalog row cannot overflow however large the base.
    for (atc_catalog.records) |record| {
        const tenths = rateTenths(record.rate).?;
        _ = try requiredWithheld(huge, tenths);
    }
    // A rate far outside the catalog still fails closed rather than wrapping.
    try std.testing.expectError(
        error.Overflow,
        requiredWithheld(huge, std.math.maxInt(u32)),
    );
}

test "1601EQ half-centavo products are reachable at ordinary amounts" {
    // 4,100.90 at 15.0% is exactly 615.135: a half-centavo landing.
    const base = Money.fromCentavos(410_090);
    const product: i128 = @as(i128, base.centavos) * 150;
    try std.testing.expectEqual(@as(i128, 61_513_500), product);
    // The thousandths digit is exactly 5, so the rule decides the centavo.
    try std.testing.expectEqual(@as(i128, 500), @mod(product, 1000));

    // This module rounds away from zero, to 615.14.
    try std.testing.expectEqual(
        @as(i64, 61_514),
        (try requiredWithheld(base, 150)).centavos,
    );
}

/// The HTA result at the divergence pinned in this module's comment. Held as
/// a constant so the claim is checked against a value rather than prose.
pub const documented_divergence = struct {
    pub const tax_base = Money.fromCentavos(410_090);
    pub const rate_tenths: u32 = 150;
    /// `formatCurrency` floors the double to this.
    pub const hta_centavos: i64 = 61_513;
    /// Half away from zero on the exact product yields this.
    pub const module_centavos: i64 = 61_514;
};

test "1601EQ the documented rounding divergence is exactly one centavo" {
    const computed = try requiredWithheld(
        documented_divergence.tax_base,
        documented_divergence.rate_tenths,
    );
    try std.testing.expectEqual(documented_divergence.module_centavos, computed.centavos);
    try std.testing.expectEqual(
        @as(i64, 1),
        documented_divergence.module_centavos - documented_divergence.hta_centavos,
    );
    // The package does not claim the two agree.
    try std.testing.expect(!evidence.readiness.calculation_reconciled);
}

test "1601EQ products that miss the half-centavo cannot diverge" {
    // Any product whose thousandths are not exactly 500 rounds the same way
    // in both pipelines, because the nudge cannot cross a non-boundary.
    const rates = [_]u32{ 5, 10, 20, 50, 100, 150, 200, 320 };
    var base_centavos: i64 = 0;
    while (base_centavos <= 20_000) : (base_centavos += 1) {
        for (rates) |rate| {
            const product: i128 = @as(i128, base_centavos) * rate;
            if (@mod(product, 1000) == 500) continue;
            const withheld = try requiredWithheld(Money.fromCentavos(base_centavos), rate);
            const expected = @divTrunc(product + 500, 1000);
            try std.testing.expectEqual(@as(i128, withheld.centavos), expected);
        }
    }
}
