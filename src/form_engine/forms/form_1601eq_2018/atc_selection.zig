//! HTA-local 1601EQ Part II ATC selection: what `getATCCode` builds from a
//! set of checked ATC codes.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601EQ.hta`
//! - SHA-256:
//!   `cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96`
//! - `getATCCode` lines 2890-3034, `showPartIIATC` lines 2801-2824
//! - `setInputTextControl_NumberFormatter` lines 2883-2886
//! - `enabletaxrate` lines 3422-3428, `disabletaxrate` lines 3430-3436
//! - `clearpart2` lines 3438-3447
//!
//! Checked codes fill the main grid as Items 13-18 and, from the seventh
//! onward, the separate Other Tax table under its own counter starting at
//! one. A selection therefore produces two independently numbered
//! sequences, not one continuous list.
//!
//! `showPartIIATC` snapshots the current codes and tax bases into `tempATC`
//! and `tempATCTaxbase` before opening the picker, and `getATCCode` looks
//! each rebuilt row up in that snapshot, so a tax base survives deselecting
//! and reselecting the same code.
//!
//! A row whose code is `N/A` has its rate re-enabled after render, where
//! every other row's rate is disabled. That re-enable appears only on the
//! main-grid path: the same code placed in the Other Tax table keeps a
//! disabled rate, so position changes behaviour.
//!
//! Main-grid rows recompute `getRequiredWithheld` then
//! `computeofTotalWithheldTax` on blur. Other Tax rows append
//! `computeTotalOtherWithheldTax`.
//!
//! The main grid is always padded back to six rows with empty disabled
//! ones, so Items 13-18 exist regardless of how few codes are checked.
//!
//! Rows are rendered through `setInputTextControl_NumberFormatter(id, 15,
//! 2)`, which is `parseFloat(value).toFixed(2)` — a third rounding path,
//! distinct from `round` and from `formatCurrency`. Only its two-decimal
//! shape is pinned here; `calculation_reconciled` stays false.
//!
//! The bulk rate helpers are asymmetric in the same way the render path is.
//! `enabletaxrate` reopens a rate only where the row's ATC is `N/A`, while
//! `disabletaxrate` closes every rate unconditionally. Both walk
//! `tblPartIIComputeTax` alone, so a rate in the Other Tax table is beyond
//! either of them.
//!
//! `clearpart2` is likewise one-sided: it empties the Other Tax rows and
//! their total and then reruns Item 19, leaving the main grid untouched.

const std = @import("std");
const atc_rows = @import("atc_rows.zig");
const calculations = @import("calculations.zig");
const evidence = @import("evidence.zig");

const Money = calculations.Money;

/// The code the picker offers when no schedule rate applies.
pub const not_applicable_code = "N/A";

/// Where a checked code lands, by its position in the selection.
pub const Placement = enum { main_grid, other_tax };

/// First Item number of the main grid, matching `itemNum` starting at 12
/// and being incremented before the row is written.
pub const first_main_item: u8 = atc_rows.first_item_number;

/// `getATCCode` fills the six main rows first, then spills.
pub fn placementFor(ordinal: usize) Placement {
    std.debug.assert(ordinal >= 1);
    return if (ordinal <= atc_rows.main_grid_row_count) .main_grid else .other_tax;
}

/// Item number shown beside a row. The main grid continues the form's own
/// numbering; the Other Tax table restarts at one under `itemNum2`.
pub fn itemNumberFor(ordinal: usize) u8 {
    return switch (placementFor(ordinal)) {
        .main_grid => first_main_item + @as(u8, @intCast(ordinal - 1)),
        .other_tax => @intCast(ordinal - atc_rows.main_grid_row_count),
    };
}

/// Only an `N/A` row in the main grid has its rate re-enabled after render.
pub fn rateEditable(code: []const u8, placement: Placement) bool {
    return placement == .main_grid and std.mem.eql(u8, code, not_applicable_code);
}

/// Recomputations wired to a row's blur handler.
pub const BlurRecompute = struct {
    /// Always present: `round(this, 2)` then `getRequiredWithheld`.
    required_withheld: bool = true,
    /// Always present: Item 19 across every row.
    total_withheld: bool = true,
    /// Other Tax rows only.
    total_other_withheld: bool,
};

pub fn blurRecomputeFor(placement: Placement) BlurRecompute {
    return .{ .total_other_withheld = placement == .other_tax };
}

/// A code and tax base captured by `showPartIIATC` before the picker opens.
pub const PreservedEntry = struct {
    code: []const u8,
    tax_base: Money,
};

/// `getATCCode` scans `tempATC` for the row's code and restores the matching
/// tax base, so reselecting a code recovers what was typed against it. A
/// code absent from the snapshot starts empty, which is zero.
pub fn preservedTaxBase(snapshot: []const PreservedEntry, code: []const u8) Money {
    for (snapshot) |entry| {
        if (std.mem.eql(u8, entry.code, code)) return entry.tax_base;
    }
    return Money.zero;
}

/// Empty disabled rows appended so the main grid always shows six.
pub fn paddingRowCount(selected_count: usize) usize {
    if (selected_count >= atc_rows.main_grid_row_count) return 0;
    return atc_rows.main_grid_row_count - selected_count;
}

/// Rows written into the Other Tax table for a selection.
pub fn otherTaxRowCount(selected_count: usize) usize {
    if (selected_count <= atc_rows.main_grid_row_count) return 0;
    return selected_count - atc_rows.main_grid_row_count;
}

/// `lblOtherTax` is revealed only when the selection spills.
pub fn showsOtherTaxLabel(selected_count: usize) bool {
    return atc_rows.usesOverflow(selected_count);
}

/// `enabletaxrate` reopens a rate only for an `N/A` row; `disabletaxrate`
/// closes every rate. Neither reaches past the main grid.
pub const RateSweep = enum { enable, disable };

pub fn rateDisabledAfterSweep(sweep: RateSweep, code: []const u8, placement: Placement) ?bool {
    // Both loops are bounded by the main grid's own table.
    if (placement != .main_grid) return null;
    return switch (sweep) {
        .disable => true,
        .enable => !std.mem.eql(u8, code, not_applicable_code),
    };
}

/// `clearpart2` empties the Other Tax rows and their total, then reruns
/// Item 19. Main-grid rows keep their values.
pub const ClearPart2 = struct {
    clears_other_tax_rows: bool = true,
    clears_other_tax_total: bool = true,
    clears_main_grid: bool = false,
    recomputes_item_19: bool = true,
};

pub const clear_part_2: ClearPart2 = .{};

/// The one-based row indices `clearpart2` walks for a given selection.
pub fn clearedRowRange(selected_count: usize) struct { first: usize, count: usize } {
    return .{
        .first = atc_rows.first_other_row,
        .count = otherTaxRowCount(selected_count),
    };
}

test "1601EQ selection placement fills the main grid before spilling" {
    try std.testing.expectEqual(Placement.main_grid, placementFor(1));
    try std.testing.expectEqual(Placement.main_grid, placementFor(6));
    try std.testing.expectEqual(Placement.other_tax, placementFor(7));
    try std.testing.expectEqual(Placement.other_tax, placementFor(30));
    try std.testing.expect(!evidence.readiness.calculation_reconciled);
}

test "1601EQ the two tables number their rows independently" {
    // Main grid continues the form's numbering.
    try std.testing.expectEqual(@as(u8, 13), itemNumberFor(1));
    try std.testing.expectEqual(@as(u8, 18), itemNumberFor(6));
    // Other Tax restarts at one under its own counter.
    try std.testing.expectEqual(@as(u8, 1), itemNumberFor(7));
    try std.testing.expectEqual(@as(u8, 2), itemNumberFor(8));
    try std.testing.expectEqual(@as(u8, 4), itemNumberFor(10));
}

test "1601EQ an N/A rate is editable only in the main grid" {
    try std.testing.expect(rateEditable(not_applicable_code, .main_grid));
    // The same code past the sixth row keeps a disabled rate.
    try std.testing.expect(!rateEditable(not_applicable_code, .other_tax));
    // Any schedule code keeps a disabled rate wherever it lands.
    try std.testing.expect(!rateEditable("WI010", .main_grid));
    try std.testing.expect(!rateEditable("WI010", .other_tax));
}

test "1601EQ Other Tax rows recompute one total more than main grid rows" {
    const main = blurRecomputeFor(.main_grid);
    try std.testing.expect(main.required_withheld);
    try std.testing.expect(main.total_withheld);
    try std.testing.expect(!main.total_other_withheld);

    const other = blurRecomputeFor(.other_tax);
    try std.testing.expect(other.required_withheld);
    try std.testing.expect(other.total_withheld);
    try std.testing.expect(other.total_other_withheld);
}

test "1601EQ a tax base survives deselecting and reselecting its code" {
    const snapshot = [_]PreservedEntry{
        .{ .code = "WI010", .tax_base = Money.fromCentavos(123_456) },
        .{ .code = "WC030", .tax_base = Money.fromCentavos(50_000) },
    };
    try std.testing.expectEqual(
        @as(i64, 123_456),
        preservedTaxBase(&snapshot, "WI010").centavos,
    );
    try std.testing.expectEqual(
        @as(i64, 50_000),
        preservedTaxBase(&snapshot, "WC030").centavos,
    );
    // A code absent from the snapshot starts empty, which reads as zero.
    try std.testing.expectEqual(
        @as(i64, 0),
        preservedTaxBase(&snapshot, "WI020").centavos,
    );
    try std.testing.expectEqual(
        @as(i64, 0),
        preservedTaxBase(&.{}, "WI010").centavos,
    );
}

test "1601EQ the main grid is always padded back to six rows" {
    try std.testing.expectEqual(@as(usize, 6), paddingRowCount(0));
    try std.testing.expectEqual(@as(usize, 5), paddingRowCount(1));
    try std.testing.expectEqual(@as(usize, 0), paddingRowCount(6));
    try std.testing.expectEqual(@as(usize, 0), paddingRowCount(9));

    // Rendered main rows plus padding is always the fixed grid.
    var selected: usize = 0;
    while (selected <= 6) : (selected += 1) {
        try std.testing.expectEqual(
            atc_rows.main_grid_row_count,
            selected + paddingRowCount(selected),
        );
    }
}

test "1601EQ the Other Tax table and its label appear together" {
    try std.testing.expectEqual(@as(usize, 0), otherTaxRowCount(6));
    try std.testing.expect(!showsOtherTaxLabel(6));

    try std.testing.expectEqual(@as(usize, 1), otherTaxRowCount(7));
    try std.testing.expect(showsOtherTaxLabel(7));

    try std.testing.expectEqual(@as(usize, 4), otherTaxRowCount(10));
    try std.testing.expect(showsOtherTaxLabel(10));

    // Every selected code is placed exactly once across the two tables.
    var selected: usize = 1;
    while (selected <= 20) : (selected += 1) {
        const in_main = @min(selected, atc_rows.main_grid_row_count);
        try std.testing.expectEqual(selected, in_main + otherTaxRowCount(selected));
    }
}

test "1601EQ the bulk rate sweeps are asymmetric" {
    // Disabling is unconditional.
    try std.testing.expect(rateDisabledAfterSweep(.disable, "WI010", .main_grid).?);
    try std.testing.expect(rateDisabledAfterSweep(.disable, not_applicable_code, .main_grid).?);

    // Enabling reopens only the N/A rows.
    try std.testing.expect(!rateDisabledAfterSweep(.enable, not_applicable_code, .main_grid).?);
    try std.testing.expect(rateDisabledAfterSweep(.enable, "WI010", .main_grid).?);
}

test "1601EQ neither rate sweep reaches the Other Tax table" {
    try std.testing.expect(rateDisabledAfterSweep(.enable, not_applicable_code, .other_tax) == null);
    try std.testing.expect(rateDisabledAfterSweep(.disable, "WI010", .other_tax) == null);

    // An N/A row past the sixth is unreachable by the render path too.
    try std.testing.expect(!rateEditable(not_applicable_code, .other_tax));
}

test "1601EQ clearpart2 empties only the Other Tax side" {
    try std.testing.expect(clear_part_2.clears_other_tax_rows);
    try std.testing.expect(clear_part_2.clears_other_tax_total);
    try std.testing.expect(!clear_part_2.clears_main_grid);
    try std.testing.expect(clear_part_2.recomputes_item_19);

    // With no spill there is nothing for it to clear.
    const none = clearedRowRange(6);
    try std.testing.expectEqual(@as(usize, 7), none.first);
    try std.testing.expectEqual(@as(usize, 0), none.count);

    const spilled = clearedRowRange(10);
    try std.testing.expectEqual(@as(usize, 7), spilled.first);
    try std.testing.expectEqual(@as(usize, 4), spilled.count);
    // It starts exactly where the Other Tax numbering starts.
    try std.testing.expectEqual(atc_rows.first_other_row, spilled.first);
}
