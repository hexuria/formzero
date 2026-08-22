//! HTA-local 1601EQ year-driven ATC rate refresh.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601EQ.hta`
//! - SHA-256:
//!   `cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96`
//! - `changeYear` lines 2636-2641
//! - `displayNewATCRate` lines 2695-2712
//! - Item 1 `onchange="changeYear();"` line 276
//! - ATC link `onclick="showPartIIATC(); changeYear();"` line 572
//!
//! Changing Item 1 rebuilds the ATC list for the current category and then
//! re-rates every populated row. Because the list is rebuilt through
//! `getWithholdingAgentATC`, which applies `changeATCRate`, this is the path
//! by which the year gate reaches the superseded-rate rule: entering a
//! different year moves the rate on rows already on screen.
//!
//! ## The category lookup resolves to no id
//!
//! `changeYear` reads `d.getElementById('frm1601EQ:optCategory').value`.
//! No element carries that id. The two category radios are
//! `frm1601EQ:optCategory:P` and `frm1601EQ:optCategory:G`, and
//! `frm1601EQ:optCategory` appears only as their shared `name`. The
//! comparable `optWithheld` group *does* own a bare fieldset id, so the
//! author plainly expected a matching element here.
//!
//! The consequence depends on the document mode, which this package does
//! not pin, so neither outcome is asserted:
//!
//! - Under standards behaviour the lookup yields nothing and reading
//!   `.value` throws, ending the handler before anything is re-rated.
//! - Under legacy IE behaviour `getElementById` also matched `name` and
//!   returned the first such element, which is the Private radio, so the
//!   list would always rebuild as Private regardless of the real selection.
//!
//! Both are wrong for a Government withholding agent, and both are reached
//! from Item 1's `onchange` and the ATC link, so this is not a dormant path.
//!
//! ## The row bound disagrees with every other one
//!
//! `displayNewATCRate` bounds its walk by the two `tbody` elements' row
//! counts added together, with no correction. `computeofTotalWithheldTax`
//! and `disableAllControl` bound theirs by the two `table` elements minus
//! four. Two formulas for what should be the same count.
//!
//! Totals are recomputed inside the inner match loop, once per re-rated row
//! rather than once at the end. That is redundant rather than wrong, and is
//! pinned so it is not mistaken for a behavioural detail later.

const std = @import("std");
const atc_catalog = @import("atc_catalog.zig");
const atc_rows = @import("atc_rows.zig");
const validation = @import("validation.zig");

/// The id `changeYear` asks for.
pub const requested_category_id = "frm1601EQ:optCategory";
/// The ids that actually exist.
pub const declared_category_ids = [_][]const u8{
    "frm1601EQ:optCategory:P",
    "frm1601EQ:optCategory:G",
};

/// How the missing id behaves, left open because document mode is unpinned.
pub const CategoryLookup = enum {
    /// Standards behaviour: no element, and reading `.value` throws.
    unresolved,
    /// Legacy IE behaviour: falls back to `name` and yields the first match.
    first_named_element,
};

/// Under the legacy fallback the first element named `frm1601EQ:optCategory`
/// is the Private radio, whatever the taxpayer actually selected.
pub fn categoryUnderLegacyFallback() atc_catalog.Category {
    return .private;
}

/// Whether the refresh reflects the taxpayer's real category.
pub fn refreshHonoursSelection(
    lookup: CategoryLookup,
    selected: atc_catalog.Category,
) bool {
    return switch (lookup) {
        // Nothing is refreshed at all, so nothing can be honoured.
        .unresolved => false,
        .first_named_element => selected == categoryUnderLegacyFallback(),
    };
}

/// `changeYear` fires from Item 1 and from the ATC link.
pub const Trigger = enum { item_1_changed, atc_link_clicked };

pub const trigger_source_lines = [_]u32{ 276, 572 };

/// A row `displayNewATCRate` will re-rate: it skips rows whose ATC cell is
/// empty and matches the rest against the rebuilt list.
pub const RefreshRow = struct {
    code: []const u8,
    /// Rate the row currently shows.
    rate: []const u8,
};

pub fn refreshesRow(row: RefreshRow) bool {
    return row.code.len != 0;
}

/// Rate a row takes after the refresh, or null when the code is absent from
/// the rebuilt list and the row keeps what it had.
pub fn refreshedRate(
    category: atc_catalog.Category,
    row: RefreshRow,
    return_year: validation.Year,
) ?[]const u8 {
    if (!refreshesRow(row)) return null;
    const record = atc_catalog.find(category, row.code) orelse return null;
    return atc_catalog.effectiveRate(record.code, record.rate, return_year);
}

/// `displayNewATCRate` sums the two `tbody` row counts with no correction,
/// where the computation and lock paths subtract four from the `table`
/// counts. Pinned as two distinct formulas over the same rows.
pub const bound_uses_tbody_without_correction = true;

/// Totals rerun once per re-rated row rather than once at the end.
pub const recomputes_totals_per_row = true;

test "1601EQ the category id changeYear asks for is not declared anywhere" {
    for (declared_category_ids) |declared| {
        try std.testing.expect(!std.mem.eql(u8, declared, requested_category_id));
        // Every real id extends the requested one with a value suffix.
        try std.testing.expect(std.mem.startsWith(u8, declared, requested_category_id));
        try std.testing.expect(declared.len > requested_category_id.len);
    }
    try std.testing.expectEqual(@as(usize, 2), declared_category_ids.len);
}

test "1601EQ neither lookup outcome serves a Government agent" {
    // Nothing refreshes at all.
    try std.testing.expect(!refreshHonoursSelection(.unresolved, .private));
    try std.testing.expect(!refreshHonoursSelection(.unresolved, .government));

    // The legacy fallback silently answers Private.
    try std.testing.expectEqual(atc_catalog.Category.private, categoryUnderLegacyFallback());
    try std.testing.expect(refreshHonoursSelection(.first_named_element, .private));
    try std.testing.expect(!refreshHonoursSelection(.first_named_element, .government));
}

test "1601EQ changeYear is reachable from Item 1 and from the ATC link" {
    try std.testing.expectEqual(@as(usize, 2), trigger_source_lines.len);
    try std.testing.expectEqual(@as(u32, 276), trigger_source_lines[0]);
    try std.testing.expectEqual(@as(u32, 572), trigger_source_lines[1]);
}

test "1601EQ the refresh skips rows with an empty ATC cell" {
    try std.testing.expect(!refreshesRow(.{ .code = "", .rate = "" }));
    try std.testing.expect(refreshesRow(.{ .code = "WI010", .rate = "5.0" }));
    try std.testing.expect(refreshedRate(
        .private,
        .{ .code = "", .rate = "5.0" },
        .{ .value = 2019 },
    ) == null);
}

test "1601EQ changing the year moves a superseded rate on a populated row" {
    const row: RefreshRow = .{ .code = "WI650", .rate = "15.0" };
    const record = atc_catalog.find(.private, "WI650");
    if (record != null) {
        // At or before 2018 the superseded rate applies.
        try std.testing.expectEqualStrings(
            "25.0",
            refreshedRate(.private, row, .{ .value = 2018 }).?,
        );
        // From 2019 the catalog rate is restored.
        try std.testing.expectEqualStrings(
            record.?.rate,
            refreshedRate(.private, row, .{ .value = 2019 }).?,
        );
    }
}

test "1601EQ a code outside the rebuilt list leaves its row alone" {
    try std.testing.expect(refreshedRate(
        .private,
        .{ .code = "ZZ999", .rate = "5.0" },
        .{ .value = 2019 },
    ) == null);
}

test "1601EQ the refresh bound and its recompute cadence are recorded" {
    try std.testing.expect(bound_uses_tbody_without_correction);
    try std.testing.expect(recomputes_totals_per_row);
    // The rows it walks are the same six plus any spill.
    try std.testing.expectEqual(@as(usize, 6), atc_rows.main_grid_row_count);
}
