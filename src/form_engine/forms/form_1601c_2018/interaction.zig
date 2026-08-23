//! HTA-local 1601C Validate and Edit control lock.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - `enableAllControl` lines 3144-3209
//! - `disableAllControl` lines 3228-3295
//!
//! Both transitions are transcribed as ordered tables of
//! `element.disabled` statements. HTA statements run in sequence, so a
//! control assigned twice settles on its last write.
//!
//! JavaScript line comments are removed before extraction. Two assignments
//! naming `btnSectionAMore`, one in each function, exist only behind `//`
//! and are excluded; a parse that keeps them reports 40 and 36
//! statements instead of 39 and 35.
//!
//! The two are not inverses. Ten Background Information controls are
//! disabled by Validate and never reopened by Edit, so that section is shut
//! for the rest of the form's life.
//!
//! Three controls are touched by neither transition and therefore stay
//! editable after a successful validation: the second address line, the
//! email address, and the ATC. 1601EQ locks its email and second address
//! line, so this is a difference between the forms rather than a shared
//! shape.
//!
//! Unlike 1601EQ there is no control that Edit enables and Validate never
//! disables; the asymmetry runs one way only here.
//!
//! This is a declaration transcription. No handler is executed.

const std = @import("std");
const evidence = @import("evidence.zig");
const occurrences = @import("occurrences.zig");

pub const ready = false;
pub const validate_lock_ready = true;

/// Assignments excluded because they sit behind a `//` comment.
pub const commented_out_assignments: usize = 2;

/// One `element.disabled = <bool>` statement, in HTA source order.
pub const ControlDisable = struct {
    id: []const u8,
    source_line: u32,
    disabled: bool,
};

/// `disableAllControl`, in source order.
pub const validate_lock = [_]ControlDisable{
    .{ .id = "frm1601c:txtSheets", .source_line = 3230, .disabled = true },
    .{ .id = "frm1601c:txtTIN1", .source_line = 3231, .disabled = true },
    .{ .id = "frm1601c:txtTIN2", .source_line = 3232, .disabled = true },
    .{ .id = "frm1601c:txtTIN3", .source_line = 3233, .disabled = true },
    .{ .id = "frm1601c:txtBranchCode", .source_line = 3234, .disabled = true },
    .{ .id = "frm1601c:txtRDOCode", .source_line = 3235, .disabled = true },
    .{ .id = "frm1601c:txtLineBus", .source_line = 3236, .disabled = true },
    .{ .id = "frm1601c:txtTaxpayerName", .source_line = 3237, .disabled = true },
    .{ .id = "frm1601c:txtTelNum", .source_line = 3238, .disabled = true },
    .{ .id = "frm1601c:txtAddress", .source_line = 3239, .disabled = true },
    .{ .id = "frm1601c:txtZipCode", .source_line = 3240, .disabled = true },
    .{ .id = "frm1601c:SpecialTax_1", .source_line = 3241, .disabled = true },
    .{ .id = "frm1601c:SpecialTax_2", .source_line = 3242, .disabled = true },
    .{ .id = "frm1601c:txtMonth", .source_line = 3243, .disabled = true },
    .{ .id = "frm1601c:txtYear", .source_line = 3244, .disabled = true },
    .{ .id = "frm1601c:TaxWithheld_1", .source_line = 3245, .disabled = true },
    .{ .id = "frm1601c:TaxWithheld_2", .source_line = 3246, .disabled = true },
    .{ .id = "frm1601c:AmendedRtn_1", .source_line = 3247, .disabled = true },
    .{ .id = "frm1601c:AmendedRtn_2", .source_line = 3248, .disabled = true },
    .{ .id = "frm1601c:CatAgent_P", .source_line = 3249, .disabled = true },
    .{ .id = "frm1601c:CatAgent_G", .source_line = 3250, .disabled = true },
    .{ .id = "frm1601c:txtTax14", .source_line = 3251, .disabled = true },
    .{ .id = "frm1601c:txtTax15", .source_line = 3252, .disabled = true },
    .{ .id = "frm1601c:txtTax16", .source_line = 3253, .disabled = true },
    .{ .id = "frm1601c:txtTax17", .source_line = 3254, .disabled = true },
    .{ .id = "frm1601c:txtTax18", .source_line = 3255, .disabled = true },
    .{ .id = "frm1601c:txtTax19", .source_line = 3256, .disabled = true },
    .{ .id = "frm1601c:txtTax20", .source_line = 3257, .disabled = true },
    .{ .id = "frm1601c:txtTax23", .source_line = 3258, .disabled = true },
    .{ .id = "frm1601c:txtTax25", .source_line = 3259, .disabled = true },
    .{ .id = "frm1601c:txtTax29", .source_line = 3260, .disabled = true },
    .{ .id = "frm1601c:btnAdd", .source_line = 3280, .disabled = true },
    .{ .id = "frm1601c:btnDelete", .source_line = 3281, .disabled = true },
    .{ .id = "frm1601c:txtCurrentPage", .source_line = 3287, .disabled = true },
    .{ .id = "frm1601c:btnValidate", .source_line = 3288, .disabled = true },
    .{ .id = "frm1601c:btnEdit", .source_line = 3289, .disabled = false },
    .{ .id = "btnPrint", .source_line = 3290, .disabled = false },
    .{ .id = "frm1601c:btnFinalCopy", .source_line = 3291, .disabled = false },
    .{ .id = "btnUpload", .source_line = 3292, .disabled = false },
};

/// `enableAllControl`, in source order.
pub const edit_unlock = [_]ControlDisable{
    .{ .id = "frm1601c:txtSheets", .source_line = 3146, .disabled = false },
    .{ .id = "frm1601c:SpecialTax_1", .source_line = 3147, .disabled = false },
    .{ .id = "frm1601c:SpecialTax_2", .source_line = 3148, .disabled = false },
    .{ .id = "frm1601c:txtMonth", .source_line = 3150, .disabled = false },
    .{ .id = "frm1601c:txtYear", .source_line = 3151, .disabled = false },
    .{ .id = "frm1601c:TaxWithheld_1", .source_line = 3152, .disabled = false },
    .{ .id = "frm1601c:TaxWithheld_2", .source_line = 3153, .disabled = false },
    .{ .id = "frm1601c:AmendedRtn_1", .source_line = 3154, .disabled = false },
    .{ .id = "frm1601c:AmendedRtn_2", .source_line = 3155, .disabled = false },
    .{ .id = "frm1601c:CatAgent_P", .source_line = 3156, .disabled = false },
    .{ .id = "frm1601c:CatAgent_G", .source_line = 3157, .disabled = false },
    .{ .id = "frm1601c:txtTax14", .source_line = 3158, .disabled = false },
    .{ .id = "frm1601c:txtTax15", .source_line = 3159, .disabled = false },
    .{ .id = "frm1601c:txtTax16", .source_line = 3160, .disabled = false },
    .{ .id = "frm1601c:txtTax17", .source_line = 3161, .disabled = false },
    .{ .id = "frm1601c:txtTax18", .source_line = 3162, .disabled = false },
    .{ .id = "frm1601c:txtTax19", .source_line = 3163, .disabled = false },
    .{ .id = "frm1601c:txtTax20", .source_line = 3164, .disabled = false },
    .{ .id = "frm1601c:txtTax23", .source_line = 3165, .disabled = false },
    .{ .id = "frm1601c:txtTax25", .source_line = 3166, .disabled = false },
    .{ .id = "frm1601c:txtTax29", .source_line = 3167, .disabled = false },
    .{ .id = "frm1601c:btnAdd", .source_line = 3188, .disabled = false },
    .{ .id = "frm1601c:btnDelete", .source_line = 3189, .disabled = false },
    .{ .id = "frm1601c:txtMonth", .source_line = 3196, .disabled = true },
    .{ .id = "frm1601c:txtYear", .source_line = 3197, .disabled = true },
    .{ .id = "frm1601c:txtCurrentPage", .source_line = 3200, .disabled = false },
    .{ .id = "frm1601c:btnValidate", .source_line = 3201, .disabled = false },
    .{ .id = "frm1601c:btnEdit", .source_line = 3202, .disabled = true },
    .{ .id = "btnPrint", .source_line = 3203, .disabled = true },
    .{ .id = "frm1601c:btnFinalCopy", .source_line = 3204, .disabled = true },
    .{ .id = "btnUpload", .source_line = 3205, .disabled = true },
    .{ .id = "frm1601c:txtTIN1", .source_line = 3208, .disabled = true },
    .{ .id = "frm1601c:txtTIN2", .source_line = 3208, .disabled = true },
    .{ .id = "frm1601c:txtTIN3", .source_line = 3208, .disabled = true },
    .{ .id = "frm1601c:txtBranchCode", .source_line = 3208, .disabled = true },
};

/// Controls Validate disables and Edit never reopens: the Background
/// Information block.
pub const never_reenabled_by_edit = [_][]const u8{
    "frm1601c:txtAddress",
    "frm1601c:txtBranchCode",
    "frm1601c:txtLineBus",
    "frm1601c:txtRDOCode",
    "frm1601c:txtTIN1",
    "frm1601c:txtTIN2",
    "frm1601c:txtTIN3",
    "frm1601c:txtTaxpayerName",
    "frm1601c:txtTelNum",
    "frm1601c:txtZipCode",
};

/// Controls neither transition touches, so they remain editable after a
/// successful validation.
pub const untouched_by_both = [_][]const u8{
    "frm1601c:txtAddress2",
    "txtEmail",
    "frm1601c:txtATC",
};

fn lastAssignment(table: []const ControlDisable, id: []const u8) ?bool {
    var found: ?bool = null;
    for (table) |entry| {
        if (std.mem.eql(u8, entry.id, id)) found = entry.disabled;
    }
    return found;
}

pub fn disabledAfterValidate(id: []const u8) ?bool {
    return lastAssignment(&validate_lock, id);
}

pub fn disabledAfterEdit(id: []const u8) ?bool {
    return lastAssignment(&edit_unlock, id);
}

test "1601C both transitions are transcribed and claim no runtime state" {
    try std.testing.expect(validate_lock_ready);
    try std.testing.expect(!ready);
    try std.testing.expectEqual(@as(usize, 39), validate_lock.len);
    try std.testing.expectEqual(@as(usize, 35), edit_unlock.len);
    try std.testing.expectEqual(@as(usize, 2), commented_out_assignments);
    try std.testing.expect(evidence.readiness.dependency_closure);
}

test "1601C every named control is a real one, and none is commented out" {
    for (validate_lock) |entry| {
        // txtRDOCode is built by getRdo, so it has no static seed.
        if (std.mem.eql(u8, entry.id, "frm1601c:txtRDOCode")) continue;
        try std.testing.expect(occurrences.find(entry.id) != null);
    }
    for (edit_unlock) |entry| {
        if (std.mem.eql(u8, entry.id, "frm1601c:txtRDOCode")) continue;
        try std.testing.expect(occurrences.find(entry.id) != null);
    }
    // The excluded pair would fail the check above if it leaked back in.
    try std.testing.expect(disabledAfterValidate("btnSectionAMore") == null);
    try std.testing.expect(disabledAfterEdit("btnSectionAMore") == null);
}

test "1601C Edit never reopens the background information block" {
    try std.testing.expectEqual(@as(usize, 10), never_reenabled_by_edit.len);
    for (never_reenabled_by_edit) |id| {
        try std.testing.expect(disabledAfterValidate(id).?);
        const after_edit = disabledAfterEdit(id);
        if (after_edit) |state| try std.testing.expect(state);
    }
}

test "1601C never_reenabled_by_edit matches the two tables" {
    for (validate_lock) |locked| {
        if (!locked.disabled) continue;
        var reopened = false;
        for (edit_unlock) |unlocked| {
            if (std.mem.eql(u8, unlocked.id, locked.id) and !unlocked.disabled) {
                reopened = true;
            }
        }
        var listed = false;
        for (never_reenabled_by_edit) |id| {
            if (std.mem.eql(u8, id, locked.id)) listed = true;
        }
        try std.testing.expectEqual(!reopened, listed);
    }
}

test "1601C email and the second address line stay editable after validation" {
    for (untouched_by_both) |id| {
        try std.testing.expect(disabledAfterValidate(id) == null);
        try std.testing.expect(disabledAfterEdit(id) == null);
    }
    try std.testing.expectEqual(@as(usize, 3), untouched_by_both.len);
    // The first address line is locked; the second is not.
    try std.testing.expect(disabledAfterValidate("frm1601c:txtAddress").?);
    try std.testing.expect(disabledAfterValidate("frm1601c:txtAddress2") == null);
}

test "1601C has no control that Edit enables and Validate never disables" {
    for (edit_unlock) |unlocked| {
        if (unlocked.disabled) continue;
        var locked_by_validate = false;
        for (validate_lock) |locked| {
            if (std.mem.eql(u8, locked.id, unlocked.id) and locked.disabled) {
                locked_by_validate = true;
            }
        }
        try std.testing.expect(locked_by_validate);
    }
}
