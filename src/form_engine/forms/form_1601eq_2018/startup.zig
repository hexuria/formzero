//! HTA-local 1601EQ startup state.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601EQ.hta`
//! - SHA-256:
//!   `cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96`
//! - `init` lines 1579-1612, called at line 1523
//!
//! `init` stamps Item 1 with the year the script loaded, sets the control
//! states below, and then loads the RDO file, builds the Item 7 select and
//! lays out the six Part II rows, in that order.
//!
//! The Background Information controls are disabled here, at load, and
//! `enableAllControl` never reopens them. Together those two facts explain
//! the asymmetry pinned in the Validate/Edit lock: the section is not closed
//! by validation, it was never open.
//!
//! `txtRDOCode` is absent from this table because `getRdo` emits the select
//! already carrying `disabled="true"`, so Item 7 is closed by construction
//! rather than by assignment.
//!
//! Item 4 and Item 11 are likewise absent, so both radio groups start
//! enabled, and only `txtTax23` among the Part II amounts is explicitly
//! opened.

const std = @import("std");
const interaction = @import("interaction.zig");
const rdo_options = @import("rdo_options.zig");

/// One `element.disabled = <bool>` statement, in `init` source order.
pub const ControlDisable = interaction.ControlDisable;

pub const initial_state = [_]ControlDisable{
    .{ .id = "frm1601EQ:optQuarter:1", .source_line = 1584, .disabled = false },
    .{ .id = "frm1601EQ:optQuarter:2", .source_line = 1585, .disabled = false },
    .{ .id = "frm1601EQ:optQuarter:3", .source_line = 1586, .disabled = false },
    .{ .id = "frm1601EQ:optQuarter:4", .source_line = 1587, .disabled = false },
    .{ .id = "frm1601EQ:optAmend:Y", .source_line = 1588, .disabled = false },
    .{ .id = "frm1601EQ:optAmend:N", .source_line = 1589, .disabled = false },
    .{ .id = "frm1601EQ:txtNoSheets", .source_line = 1590, .disabled = false },
    .{ .id = "frm1601EQ:txtTIN1", .source_line = 1591, .disabled = true },
    .{ .id = "frm1601EQ:txtTIN2", .source_line = 1592, .disabled = true },
    .{ .id = "frm1601EQ:txtTIN3", .source_line = 1593, .disabled = true },
    .{ .id = "frm1601EQ:txtBranchCode", .source_line = 1594, .disabled = true },
    .{ .id = "frm1601EQ:txtTaxpayerName", .source_line = 1595, .disabled = true },
    .{ .id = "frm1601EQ:txtAddress", .source_line = 1596, .disabled = true },
    .{ .id = "frm1601EQ:txtAddress2", .source_line = 1597, .disabled = true },
    .{ .id = "frm1601EQ:txtTelNum", .source_line = 1598, .disabled = true },
    .{ .id = "frm1601EQ:txtZipCode", .source_line = 1599, .disabled = true },
    .{ .id = "txtEmail", .source_line = 1600, .disabled = true },
    .{ .id = "frm1601EQ:cmdEdit", .source_line = 1602, .disabled = true },
    .{ .id = "frm1601EQ:btnFinalCopy", .source_line = 1603, .disabled = true },
    .{ .id = "menuPrintPreview", .source_line = 1604, .disabled = true },
    .{ .id = "btnPrint", .source_line = 1605, .disabled = true },
    .{ .id = "frm1601EQ:txtTax23", .source_line = 1608, .disabled = false },
};

/// `init` reads a fresh `Date` and writes its year into Item 1, so a new
/// form always opens on the year the script loaded.
pub const stamps_current_year_into_item_1 = true;

/// The load steps `init` runs after setting control state, in order.
pub const LoadStep = enum { load_rdo_file, build_rdo_select, lay_out_part_ii_rows };

pub const load_order = [_]LoadStep{ .load_rdo_file, .build_rdo_select, .lay_out_part_ii_rows };

/// Disabled state after `init`, or null when `init` does not touch it.
pub fn disabledAfterInit(id: []const u8) ?bool {
    var found: ?bool = null;
    for (initial_state) |entry| {
        if (std.mem.eql(u8, entry.id, id)) found = entry.disabled;
    }
    return found;
}

/// Item 7 is closed by the markup `getRdo` emits, not by `init`.
pub const rdo_select_disabled_by_construction = true;

test "1601EQ init opens the period controls and closes the outputs" {
    try std.testing.expect(stamps_current_year_into_item_1);
    try std.testing.expect(!disabledAfterInit("frm1601EQ:optQuarter:1").?);
    try std.testing.expect(!disabledAfterInit("frm1601EQ:optQuarter:4").?);
    try std.testing.expect(!disabledAfterInit("frm1601EQ:optAmend:Y").?);
    try std.testing.expect(!disabledAfterInit("frm1601EQ:txtNoSheets").?);

    try std.testing.expect(disabledAfterInit("frm1601EQ:cmdEdit").?);
    try std.testing.expect(disabledAfterInit("frm1601EQ:btnFinalCopy").?);
    try std.testing.expect(disabledAfterInit("menuPrintPreview").?);
    try std.testing.expect(disabledAfterInit("btnPrint").?);
}

test "1601EQ the background information section is closed from load" {
    const background = [_][]const u8{
        "frm1601EQ:txtTIN1",       "frm1601EQ:txtTIN2",         "frm1601EQ:txtTIN3",
        "frm1601EQ:txtBranchCode", "frm1601EQ:txtTaxpayerName", "frm1601EQ:txtAddress",
        "frm1601EQ:txtAddress2",   "frm1601EQ:txtTelNum",       "frm1601EQ:txtZipCode",
        "txtEmail",
    };
    for (background) |id| {
        try std.testing.expect(disabledAfterInit(id).?);
        // And Edit never reopens it, so the section is closed for the whole
        // life of the form.
        const after_edit = interaction.disabledAfterEdit(id, .yes);
        if (after_edit) |state| try std.testing.expect(state);
    }
}

test "1601EQ every control init closes is one Edit never reopens" {
    for (initial_state) |entry| {
        if (!entry.disabled) continue;
        if (std.mem.eql(u8, entry.id, "frm1601EQ:cmdEdit")) continue;
        if (std.mem.eql(u8, entry.id, "frm1601EQ:btnFinalCopy")) continue;
        if (std.mem.eql(u8, entry.id, "menuPrintPreview")) continue;
        if (std.mem.eql(u8, entry.id, "btnPrint")) continue;
        // What remains is the background section.
        var listed = false;
        for (interaction.never_reenabled_by_edit) |id| {
            if (std.mem.eql(u8, id, entry.id)) listed = true;
        }
        try std.testing.expect(listed);
    }
}

test "1601EQ Item 4 and Item 11 start enabled and Item 7 is closed elsewhere" {
    // Neither radio group appears in init.
    try std.testing.expect(disabledAfterInit("frm1601EQ:optWithheld:Y") == null);
    try std.testing.expect(disabledAfterInit("frm1601EQ:optCategory:P") == null);
    // Item 7 is closed by the markup getRdo emits.
    try std.testing.expect(disabledAfterInit("frm1601EQ:txtRDOCode") == null);
    try std.testing.expect(rdo_select_disabled_by_construction);
    try std.testing.expectEqualStrings("000", rdo_options.placeholder_value);
}

test "1601EQ only Item 23 among the Part II amounts is opened by init" {
    try std.testing.expect(!disabledAfterInit("frm1601EQ:txtTax23").?);
    try std.testing.expect(disabledAfterInit("frm1601EQ:txtTax20") == null);
    try std.testing.expect(disabledAfterInit("frm1601EQ:txtTax19") == null);
}

test "1601EQ init loads the RDO file before building the select or the rows" {
    try std.testing.expectEqual(@as(usize, 3), load_order.len);
    try std.testing.expectEqual(LoadStep.load_rdo_file, load_order[0]);
    try std.testing.expectEqual(LoadStep.build_rdo_select, load_order[1]);
    try std.testing.expectEqual(LoadStep.lay_out_part_ii_rows, load_order[2]);
}
