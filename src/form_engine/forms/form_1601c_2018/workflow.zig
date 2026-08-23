//! HTA-local 1601C save lifecycle.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - `enableSaveButton` lines 4610-4622
//! - `initialValidateBeforeSave` lines 3672-3698
//! - `saveBeforeExit` lines 4235-4248
//!
//! Three gates stand between a form and a saved file, and they do not agree
//! with each other or with `validate`.
//!
//! `enableSaveButton` is a live gate on the Save button itself. It requires
//! the month, the year and all four TIN parts, and nothing else. It runs
//! from field handlers, so the button flickers between states as those
//! fields are filled.
//!
//! `initialValidateBeforeSave` runs on the save path and re-checks the same
//! fields, then adds the RDO code and the withholding agent's name. Every
//! failure returns false, unlike `validate`, whose gates return nothing.
//!
//! ## The two validators disagree on two points
//!
//! `validate` rejects Item 7 by `selectedIndex == 0`, the placeholder's
//! position. `initialValidateBeforeSave` rejects it by `value == "000"`,
//! the placeholder's value. Those coincide only while the placeholder holds
//! that exact value at that exact index.
//!
//! `validate` names Item 8 with `Witholding`, misspelled.
//! `initialValidateBeforeSave` names the same field with `Withholding`,
//! spelled correctly. Both strings are reproduced as written.
//!
//! The same split appears in 1601EQ between `validateForm` and its own
//! `initialValidateBeforeSave`, so it is a family trait rather than a
//! one-form slip.
//!
//! ## Exiting saves without asking what kind
//!
//! `saveBeforeExit` confirms the exit, then calls `saveXML(false)` — an
//! editable save, never a Final Copy — before closing the window. The
//! taxpayer is asked whether to exit, not whether to save or how.
//!
//! Lifecycle rules only. Nothing here writes a file and
//! `persistence_integrated` stays false.

const std = @import("std");
const document = @import("document.zig");
const evidence = @import("evidence.zig");
const validation = @import("validation.zig");

pub const ready = false;
pub const save_lifecycle_ready = true;

pub const alert_month_required = "Please enter Month on Item 1.";
pub const alert_year_required = "Please enter Year on Item 1.";
pub const alert_tin_required = "Please enter a valid TIN number on Item 6.";
pub const alert_rdo_required = "Please enter a valid RDO Code on Item 7.";
/// Spelled correctly here, unlike `validation.alert_item_8_name`.
pub const alert_name_required = "Please enter a valid Withholding Agent's Name on Item 8.";

/// The value `initialValidateBeforeSave` rejects Item 7 by.
pub const rdo_placeholder_value = "000";

pub const SaveButtonInput = struct {
    month: []const u8 = "1",
    year: []const u8 = "2026",
    tin_part_1: []const u8 = "123",
    tin_part_2: []const u8 = "456",
    tin_part_3: []const u8 = "789",
    branch_code: []const u8 = "000",
};

/// `enableSaveButton`: the Save button is enabled only once the period and
/// the whole TIN are present.
pub fn saveButtonEnabled(input: SaveButtonInput) bool {
    if (input.month.len == 0 or input.year.len == 0) return false;
    if (input.tin_part_1.len == 0 or input.tin_part_2.len == 0 or
        input.tin_part_3.len == 0 or input.branch_code.len == 0)
    {
        return false;
    }
    return true;
}

pub const SaveGate = enum {
    month,
    year,
    tin,
    rdo_code,
    withholding_agent_name,
};

/// Source order of `initialValidateBeforeSave`.
pub const save_gate_order = [_]SaveGate{ .month, .year, .tin, .rdo_code, .withholding_agent_name };

pub const SaveCheckInput = struct {
    button: SaveButtonInput = .{},
    /// Compared against `"000"` by value, not by index.
    rdo_value: []const u8 = "001",
    withholding_agent_name: []const u8 = "SYNTHETIC AGENT",
};

pub const SaveOutcome = struct {
    accepted: bool,
    failed_gate: ?SaveGate,
    alert: ?[]const u8,
};

fn rejectSave(gate: SaveGate, alert: []const u8) SaveOutcome {
    return .{ .accepted = false, .failed_gate = gate, .alert = alert };
}

/// `initialValidateBeforeSave`. Every failure returns false.
pub fn validateBeforeSave(input: SaveCheckInput) SaveOutcome {
    if (input.button.month.len == 0) return rejectSave(.month, alert_month_required);
    if (input.button.year.len == 0) return rejectSave(.year, alert_year_required);
    if (input.button.tin_part_1.len == 0 or input.button.tin_part_2.len == 0 or
        input.button.tin_part_3.len == 0 or input.button.branch_code.len == 0)
    {
        return rejectSave(.tin, alert_tin_required);
    }
    if (std.mem.eql(u8, input.rdo_value, rdo_placeholder_value)) {
        return rejectSave(.rdo_code, alert_rdo_required);
    }
    if (input.withholding_agent_name.len == 0) {
        return rejectSave(.withholding_agent_name, alert_name_required);
    }
    return .{ .accepted = true, .failed_gate = null, .alert = null };
}

/// `saveBeforeExit` always takes the editable path.
pub const exit_save_marker: document.Marker = .editable;
pub const exit_confirms_before_saving = true;
pub const exit_offers_a_choice_of_marker = false;

test "1601C the save lifecycle is pinned but writes nothing" {
    try std.testing.expect(save_lifecycle_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!evidence.readiness.persistence_integrated);
    try std.testing.expectEqual(@as(usize, 5), save_gate_order.len);
}

test "1601C the Save button needs only the period and the TIN" {
    try std.testing.expect(saveButtonEnabled(.{}));
    try std.testing.expect(!saveButtonEnabled(.{ .month = "" }));
    try std.testing.expect(!saveButtonEnabled(.{ .year = "" }));
    try std.testing.expect(!saveButtonEnabled(.{ .branch_code = "" }));
    // It does not consider the RDO code or the agent name at all.
    try std.testing.expect(saveButtonEnabled(.{}));
}

test "1601C the save gate adds two checks the button never makes" {
    // The button is happy, but the save path is not.
    try std.testing.expect(saveButtonEnabled(.{}));
    const no_rdo = validateBeforeSave(.{ .rdo_value = rdo_placeholder_value });
    try std.testing.expectEqual(SaveGate.rdo_code, no_rdo.failed_gate.?);
    const no_name = validateBeforeSave(.{ .withholding_agent_name = "" });
    try std.testing.expectEqual(SaveGate.withholding_agent_name, no_name.failed_gate.?);
    try std.testing.expect(validateBeforeSave(.{}).accepted);
}

test "1601C the two validators reject Item 7 by different tests" {
    // The save path compares the value.
    try std.testing.expectEqualStrings("000", rdo_placeholder_value);
    const by_value = validateBeforeSave(.{ .rdo_value = "000" });
    try std.testing.expectEqual(SaveGate.rdo_code, by_value.failed_gate.?);
    // A non-placeholder value passes even at a low index.
    try std.testing.expect(validateBeforeSave(.{ .rdo_value = "001" }).accepted);
    // validate compares the index instead.
    var identity = validationInputs();
    identity.rdo_selected_index = 0;
    try std.testing.expectEqual(
        validation.Gate.item_7_rdo,
        validation.validate(identity, march_2026).failed_gate.?,
    );
}

test "1601C the same field is spelled two ways in one form" {
    // The save path spells it correctly.
    try std.testing.expect(std.mem.indexOf(u8, alert_name_required, "Withholding") != null);
    // validate does not.
    try std.testing.expect(
        std.mem.indexOf(u8, validation.alert_item_8_name, "Witholding") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, validation.alert_item_8_name, "Withholding") == null,
    );
    // Both name Item 8.
    try std.testing.expect(std.mem.indexOf(u8, alert_name_required, "Item 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, validation.alert_item_8_name, "Item 8") != null);
}

test "1601C exiting saves an editable copy without offering a choice" {
    try std.testing.expectEqual(document.Marker.editable, exit_save_marker);
    try std.testing.expect(exit_confirms_before_saving);
    try std.testing.expect(!exit_offers_a_choice_of_marker);
    // So an exit never produces the Final Copy tail.
    try std.testing.expectEqualStrings(document.editable_tail, exit_save_marker.tail());
}

const march_2026: validation.Clock = .{ .year = 2026, .month_index = 2 };

fn validationInputs() validation.Inputs {
    return .{
        .year = .{ .value = 2026 },
        .month = .{ .selected_index = 1 },
        .tax_withheld = .no,
        .tin_part_1 = "123",
        .tin_part_2 = "456",
        .tin_part_3 = "789",
        .branch_code = "000",
        .rdo_selected_index = 1,
        .taxpayer_name = "SYNTHETIC AGENT",
        .telephone_number = "0000000",
        .registered_address = "SYNTHETIC ADDRESS",
        .zip_code = "1000",
        .category = .private,
    };
}
