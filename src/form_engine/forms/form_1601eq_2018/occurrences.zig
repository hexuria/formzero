//! Static HTA control inventory for 1601EQ January 2018 (ENCS).
//!
//! Derived from the verified 7.9.6 `forms/BIR-Form1601EQ.hta` after
//! removing script/style inner HTML. This is markup declaration order,
//! not a live `frmMain.elements` capture and not a serializer occurrence
//! stream. Dynamic ATC rows and runtime-created controls are unobserved.

const std = @import("std");
const evidence = @import("evidence.zig");

pub const evidence_id = "desktop-7.9.6-1601eq-hta";
pub const form_id = "frmMain";
pub const form_first_line: u32 = 220;
pub const form_last_line: u32 = 1429;

pub const static_document_control_count: u16 = 98;
pub const static_controls_with_id_count: u16 = 93;
pub const static_controls_without_id_count: u16 = 5;
pub const frm_main_static_control_count: u16 = 92;
pub const runtime_created_form_controls: u16 = 0;
pub const runtime_control_creation_observed = false;
pub const serializer_reviewed = false;

pub const ControlKind = enum {
    text,
    radio,
    checkbox,
    hidden,
    password,
    button,
    select_one,
    textarea,
};

pub const ControlSeed = struct {
    /// One-based order of static input/select/textarea tags in the HTA.
    ordinal: u16,
    source_line: u32,
    kind: ControlKind,
    id: ?[]const u8,
    name: ?[]const u8,
    declared_value: []const u8,
    inside_frm_main: bool,
};

pub const control_seeds = [_]ControlSeed{
    .{ .ordinal = 1, .source_line = 196, .kind = .button, .id = null, .name = null, .declared_value = "Main Menu", .inside_frm_main = false },
    .{ .ordinal = 2, .source_line = 197, .kind = .button, .id = null, .name = null, .declared_value = "Save", .inside_frm_main = false },
    .{ .ordinal = 3, .source_line = 198, .kind = .button, .id = null, .name = null, .declared_value = "Print", .inside_frm_main = false },
    .{ .ordinal = 4, .source_line = 199, .kind = .button, .id = null, .name = null, .declared_value = "Exit", .inside_frm_main = false },
    .{ .ordinal = 5, .source_line = 216, .kind = .button, .id = "paymentOptionCloseBtn", .name = null, .declared_value = "Close", .inside_frm_main = false },
    .{ .ordinal = 6, .source_line = 276, .kind = .text, .id = "frm1601EQ:txtYear", .name = "frm1601EQ:txtYear", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 7, .source_line = 289, .kind = .radio, .id = "frm1601EQ:optQuarter:1", .name = "frm1601EQ:optQuarter", .declared_value = "1", .inside_frm_main = true },
    .{ .ordinal = 8, .source_line = 290, .kind = .radio, .id = "frm1601EQ:optQuarter:2", .name = "frm1601EQ:optQuarter", .declared_value = "2", .inside_frm_main = true },
    .{ .ordinal = 9, .source_line = 291, .kind = .radio, .id = "frm1601EQ:optQuarter:3", .name = "frm1601EQ:optQuarter", .declared_value = "3", .inside_frm_main = true },
    .{ .ordinal = 10, .source_line = 292, .kind = .radio, .id = "frm1601EQ:optQuarter:4", .name = "frm1601EQ:optQuarter", .declared_value = "4", .inside_frm_main = true },
    .{ .ordinal = 11, .source_line = 311, .kind = .radio, .id = "frm1601EQ:optAmend:Y", .name = "frm1601EQ:optAmend", .declared_value = "Y", .inside_frm_main = true },
    .{ .ordinal = 12, .source_line = 312, .kind = .radio, .id = "frm1601EQ:optAmend:N", .name = "frm1601EQ:optAmend", .declared_value = "N", .inside_frm_main = true },
    .{ .ordinal = 13, .source_line = 336, .kind = .radio, .id = "frm1601EQ:optWithheld:Y", .name = "frm1601EQ:optWithheld", .declared_value = "Y", .inside_frm_main = true },
    .{ .ordinal = 14, .source_line = 337, .kind = .radio, .id = "frm1601EQ:optWithheld:N", .name = "frm1601EQ:optWithheld", .declared_value = "N", .inside_frm_main = true },
    .{ .ordinal = 15, .source_line = 355, .kind = .text, .id = "frm1601EQ:txtNoSheets", .name = "frm1601EQ:txtNoSheets", .declared_value = "0", .inside_frm_main = true },
    .{ .ordinal = 16, .source_line = 391, .kind = .text, .id = "frm1601EQ:txtTIN1", .name = "frm1601EQ:txtTIN1", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 17, .source_line = 392, .kind = .text, .id = "frm1601EQ:txtTIN2", .name = "frm1601EQ:txtTIN2", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 18, .source_line = 393, .kind = .text, .id = "frm1601EQ:txtTIN3", .name = "frm1601EQ:txtTIN3", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 19, .source_line = 394, .kind = .text, .id = "frm1601EQ:txtBranchCode", .name = "frm1601EQ:txtBranchCode", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 20, .source_line = 435, .kind = .text, .id = "frm1601EQ:txtTaxpayerName", .name = "frm1601EQ:txtTaxpayerName", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 21, .source_line = 448, .kind = .text, .id = "frm1601EQ:txtLineBus", .name = "frm1601EQ:txtLineBus", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 22, .source_line = 472, .kind = .text, .id = "frm1601EQ:txtAddress", .name = "frm1601EQ:txtAddress", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 23, .source_line = 488, .kind = .text, .id = "frm1601EQ:txtAddress2", .name = "frm1601EQ:txtAddress2", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 24, .source_line = 495, .kind = .text, .id = "frm1601EQ:txtZipCode", .name = "frm1601EQ:txtZipCode", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 25, .source_line = 513, .kind = .text, .id = "frm1601EQ:txtTelNum", .name = "frm1601EQ:txtTelNum", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 26, .source_line = 521, .kind = .radio, .id = "frm1601EQ:optCategory:P", .name = "frm1601EQ:optCategory", .declared_value = "P", .inside_frm_main = true },
    .{ .ordinal = 27, .source_line = 522, .kind = .radio, .id = "frm1601EQ:optCategory:G", .name = "frm1601EQ:optCategory", .declared_value = "G", .inside_frm_main = true },
    .{ .ordinal = 28, .source_line = 539, .kind = .text, .id = "txtEmail", .name = "txtEmail", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 29, .source_line = 587, .kind = .text, .id = "frm1601EQ:txtTotalOtherTax", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 30, .source_line = 619, .kind = .text, .id = "frm1601EQ:txtTax19", .name = "frm1601EQ:txtTax19", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 31, .source_line = 638, .kind = .text, .id = "frm1601EQ:txtTax20", .name = "frm1601EQ:txtTax20", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 32, .source_line = 657, .kind = .text, .id = "frm1601EQ:txtTax21", .name = "frm1601EQ:txtTax21", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 33, .source_line = 676, .kind = .text, .id = "frm1601EQ:txtTax22", .name = "frm1601EQ:txtTax22", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 34, .source_line = 695, .kind = .text, .id = "frm1601EQ:txtTax23", .name = "frm1601EQ:txtTax23", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 35, .source_line = 713, .kind = .text, .id = "frm1601EQ:txtTax24", .name = "frm1601EQ:txtTax24", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 36, .source_line = 731, .kind = .text, .id = "frm1601EQ:txtTax25", .name = "frm1601EQ:txtTax25", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 37, .source_line = 746, .kind = .text, .id = "frm1601EQ:txtTax26", .name = "frm1601EQ:txtTax26", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 38, .source_line = 747, .kind = .hidden, .id = "frm1601EQ:inputSurcharge", .name = "frm1601EQ:inputSurcharge", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 39, .source_line = 763, .kind = .text, .id = "frm1601EQ:txtTax27", .name = "frm1601EQ:txtTax27", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 40, .source_line = 779, .kind = .text, .id = "frm1601EQ:txtTax28", .name = "frm1601EQ:txtTax28", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 41, .source_line = 795, .kind = .text, .id = "frm1601EQ:txtTax29", .name = "frm1601EQ:txtTax29", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 42, .source_line = 812, .kind = .text, .id = "frm1601EQ:txtTax30", .name = "frm1601EQ:txtTax30", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 43, .source_line = 829, .kind = .checkbox, .id = "frm1601EQ:ifRefund", .name = "frm1601EQ:ifRefund", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 44, .source_line = 830, .kind = .checkbox, .id = "frm1601EQ:ifIssueCert", .name = "frm1601EQ:ifIssueCert", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 45, .source_line = 831, .kind = .checkbox, .id = "frm1601EQ:ifCarriedOver", .name = "frm1601EQ:ifCarriedOver", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 46, .source_line = 871, .kind = .text, .id = "txtTaxAgentNo", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 47, .source_line = 884, .kind = .text, .id = "txtDateIssue", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 48, .source_line = 897, .kind = .text, .id = "txtDateExpiry", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 49, .source_line = 938, .kind = .text, .id = "frm1601EQ:txtAgency33", .name = "frm1601EQ:txtAgency33", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 50, .source_line = 939, .kind = .text, .id = "frm1601EQ:txtNumber33", .name = "frm1601EQ:txtNumber33", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 51, .source_line = 940, .kind = .text, .id = "frm1601EQ:txtDate33", .name = "frm1601EQ:txtDate33", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 52, .source_line = 941, .kind = .text, .id = "frm1601EQ:txtAmount33", .name = "frm1601EQ:txtAmount33", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 53, .source_line = 945, .kind = .text, .id = "frm1601EQ:txtAgency34", .name = "frm1601EQ:txtAgency34", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 54, .source_line = 946, .kind = .text, .id = "frm1601EQ:txtNumber34", .name = "frm1601EQ:txtNumber34", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 55, .source_line = 947, .kind = .text, .id = "frm1601EQ:txtDate34", .name = "frm1601EQ:txtDate34", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 56, .source_line = 948, .kind = .text, .id = "frm1601EQ:txtAmount34", .name = "frm1601EQ:txtAmount34", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 57, .source_line = 952, .kind = .text, .id = "frm1601EQ:txtAgency35", .name = "frm1601EQ:txtAgency35", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 58, .source_line = 953, .kind = .text, .id = "frm1601EQ:txtNumber35", .name = "frm1601EQ:txtNumber35", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 59, .source_line = 954, .kind = .text, .id = "frm1601EQ:txtDate35", .name = "frm1601EQ:txtDate35", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 60, .source_line = 955, .kind = .text, .id = "frm1601EQ:txtAmount35", .name = "frm1601EQ:txtAmount35", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 61, .source_line = 961, .kind = .text, .id = "frm1601EQ:txtParticular36", .name = "frm1601EQ:txtParticular36", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 62, .source_line = 962, .kind = .text, .id = "frm1601EQ:txtAgency36", .name = "frm1601EQ:txtAgency36", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 63, .source_line = 963, .kind = .text, .id = "frm1601EQ:txtNumber36", .name = "frm1601EQ:txtNumber36", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 64, .source_line = 964, .kind = .text, .id = "frm1601EQ:txtDate36", .name = "frm1601EQ:txtDate36", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 65, .source_line = 965, .kind = .text, .id = "frm1601EQ:txtAmount36", .name = "frm1601EQ:txtAmount36", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 66, .source_line = 1002, .kind = .button, .id = "frm1601EQ:cmdValidate", .name = "frm1601EQ:cmdValidate", .declared_value = "Validate", .inside_frm_main = true },
    .{ .ordinal = 67, .source_line = 1003, .kind = .button, .id = "frm1601EQ:cmdEdit", .name = "frm1601EQ:cmdEdit", .declared_value = "Edit", .inside_frm_main = true },
    .{ .ordinal = 68, .source_line = 1004, .kind = .hidden, .id = "btnUpload", .name = "btnUpload", .declared_value = "Submit", .inside_frm_main = true },
    .{ .ordinal = 69, .source_line = 1005, .kind = .button, .id = "btnSave", .name = "btnSave", .declared_value = "Save", .inside_frm_main = true },
    .{ .ordinal = 70, .source_line = 1006, .kind = .button, .id = "btnPrint", .name = "btnPrint", .declared_value = "Print", .inside_frm_main = true },
    .{ .ordinal = 71, .source_line = 1007, .kind = .button, .id = "frm1601EQ:btnFinalCopy", .name = "frm1601EQ:btnFinalCopy", .declared_value = "Submit / Final Copy", .inside_frm_main = true },
    .{ .ordinal = 72, .source_line = 1058, .kind = .button, .id = "btnOkPop", .name = "btnOkPop", .declared_value = "OK", .inside_frm_main = true },
    .{ .ordinal = 73, .source_line = 1065, .kind = .text, .id = "hPartIITableSize", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 74, .source_line = 1091, .kind = .button, .id = "btnPrintOtherAtc", .name = null, .declared_value = " Print ", .inside_frm_main = true },
    .{ .ordinal = 75, .source_line = 1092, .kind = .button, .id = null, .name = null, .declared_value = " Close ", .inside_frm_main = true },
    .{ .ordinal = 76, .source_line = 1093, .kind = .button, .id = "btnClearOtherAtc", .name = null, .declared_value = " Clear ", .inside_frm_main = true },
    .{ .ordinal = 77, .source_line = 1120, .kind = .button, .id = "btnOkImport", .name = "btnOkImport", .declared_value = "OK", .inside_frm_main = true },
    .{ .ordinal = 78, .source_line = 1121, .kind = .button, .id = "btnCancelImport", .name = "btnCancelImport", .declared_value = "CANCEL", .inside_frm_main = true },
    .{ .ordinal = 79, .source_line = 1129, .kind = .text, .id = "txtFinalFlag", .name = "txtFinalFlag", .declared_value = "0", .inside_frm_main = true },
    .{ .ordinal = 80, .source_line = 1130, .kind = .text, .id = "txtEnroll", .name = "txtEnroll", .declared_value = "N", .inside_frm_main = true },
    .{ .ordinal = 81, .source_line = 1148, .kind = .text, .id = "ebirOnlineConfirmUsername", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 82, .source_line = 1156, .kind = .password, .id = "ebirOnlineConfirmPassword", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 83, .source_line = 1161, .kind = .button, .id = "ebirOnlineConfirmSubmit", .name = null, .declared_value = "Submit", .inside_frm_main = true },
    .{ .ordinal = 84, .source_line = 1164, .kind = .button, .id = "ebirOnlineConfirmCancel", .name = null, .declared_value = "Cancel", .inside_frm_main = true },
    .{ .ordinal = 85, .source_line = 1303, .kind = .button, .id = "btnAgree", .name = null, .declared_value = "Agree", .inside_frm_main = true },
    .{ .ordinal = 86, .source_line = 1323, .kind = .button, .id = "ebirEnrollYes", .name = null, .declared_value = "  Ok  ", .inside_frm_main = true },
    .{ .ordinal = 87, .source_line = 1326, .kind = .button, .id = "ebirEnrollNo", .name = null, .declared_value = "Cancel", .inside_frm_main = true },
    .{ .ordinal = 88, .source_line = 1345, .kind = .button, .id = "isregistered", .name = null, .declared_value = "YES", .inside_frm_main = true },
    .{ .ordinal = 89, .source_line = 1348, .kind = .button, .id = "notregistered", .name = null, .declared_value = "NO", .inside_frm_main = true },
    .{ .ordinal = 90, .source_line = 1370, .kind = .text, .id = "ebirOnlineUsername", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 91, .source_line = 1378, .kind = .password, .id = "ebirOnlinePassword", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 92, .source_line = 1379, .kind = .text, .id = "ebirOnlineSecret", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 93, .source_line = 1384, .kind = .button, .id = "ebirOnlineSubmit", .name = null, .declared_value = "Submit", .inside_frm_main = true },
    .{ .ordinal = 94, .source_line = 1387, .kind = .button, .id = "ebirOnlineCancel", .name = null, .declared_value = "Cancel", .inside_frm_main = true },
    .{ .ordinal = 95, .source_line = 1414, .kind = .select_one, .id = "driveSelectTPExport", .name = "driveSelectTPExport", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 96, .source_line = 1423, .kind = .button, .id = "btnOkExport", .name = "btnOk", .declared_value = "OK", .inside_frm_main = true },
    .{ .ordinal = 97, .source_line = 1424, .kind = .button, .id = "btnCancelExport", .name = "btnCancel", .declared_value = "CANCEL", .inside_frm_main = true },
    .{ .ordinal = 98, .source_line = 1430, .kind = .textarea, .id = "responsetext", .name = null, .declared_value = "", .inside_frm_main = false },
};

fn seedById(id: []const u8) ?ControlSeed {
    for (control_seeds) |seed| {
        if (seed.id) |seed_id| {
            if (std.mem.eql(u8, seed_id, id)) return seed;
        }
    }
    return null;
}

test "1601EQ static HTA inventory is 98 controls with Save and Print in markup" {
    try std.testing.expectEqual(
        @as(usize, static_document_control_count),
        control_seeds.len,
    );
    try std.testing.expectEqual(
        static_document_control_count,
        static_controls_with_id_count + static_controls_without_id_count,
    );

    var with_id: u16 = 0;
    var without_id: u16 = 0;
    var inside: u16 = 0;
    var previous_line: u32 = 0;
    for (control_seeds, 0..) |seed, index| {
        try std.testing.expectEqual(@as(u16, @intCast(index + 1)), seed.ordinal);
        try std.testing.expect(seed.source_line >= previous_line);
        previous_line = seed.source_line;
        if (seed.id) |_| {
            with_id += 1;
        } else {
            without_id += 1;
        }
        if (seed.inside_frm_main) inside += 1;
    }
    try std.testing.expectEqual(static_controls_with_id_count, with_id);
    try std.testing.expectEqual(static_controls_without_id_count, without_id);
    try std.testing.expectEqual(frm_main_static_control_count, inside);

    try std.testing.expectEqualStrings("frmMain", form_id);
    try std.testing.expectEqual(@as(u32, 220), form_first_line);
    try std.testing.expectEqual(@as(u32, 1429), form_last_line);
    try std.testing.expect(!runtime_control_creation_observed);
    try std.testing.expectEqual(@as(u16, 0), runtime_created_form_controls);
    try std.testing.expect(!serializer_reviewed);
    try std.testing.expect(!evidence.readiness.dependency_closure);
    try std.testing.expect(!evidence.readiness.identityReady());
}

test "1601EQ unnamed chrome includes Save and Print buttons" {
    try std.testing.expect(control_seeds[0].id == null);
    try std.testing.expectEqualStrings("Main Menu", control_seeds[0].declared_value);
    try std.testing.expectEqual(@as(u32, 196), control_seeds[0].source_line);
    try std.testing.expect(!control_seeds[0].inside_frm_main);
    try std.testing.expectEqual(ControlKind.button, control_seeds[0].kind);

    try std.testing.expect(control_seeds[1].id == null);
    try std.testing.expectEqualStrings("Save", control_seeds[1].declared_value);
    try std.testing.expectEqual(@as(u32, 197), control_seeds[1].source_line);
    try std.testing.expectEqual(ControlKind.button, control_seeds[1].kind);

    try std.testing.expect(control_seeds[2].id == null);
    try std.testing.expectEqualStrings("Print", control_seeds[2].declared_value);
    try std.testing.expectEqual(@as(u32, 198), control_seeds[2].source_line);
    try std.testing.expectEqual(ControlKind.button, control_seeds[2].kind);

    try std.testing.expect(control_seeds[3].id == null);
    try std.testing.expectEqualStrings("Exit", control_seeds[3].declared_value);
}

test "1601EQ frmMain identity controls are present and ATC rows are not static" {
    const year = seedById("frm1601EQ:txtYear").?;
    try std.testing.expectEqual(@as(u32, 276), year.source_line);
    try std.testing.expect(year.inside_frm_main);
    try std.testing.expectEqual(ControlKind.text, year.kind);

    try std.testing.expect(seedById("frm1601EQ:optQuarter:1") != null);
    try std.testing.expect(seedById("frm1601EQ:txtTIN1") != null);
    try std.testing.expect(seedById("frm1601EQ:txtTaxpayerName") != null);
    try std.testing.expect(seedById("frm1601EQ:ifRefund") != null);
    try std.testing.expectEqual(ControlKind.checkbox, seedById("frm1601EQ:ifRefund").?.kind);
    try std.testing.expectEqual(ControlKind.button, seedById("btnAgree").?.kind);

    try std.testing.expect(seedById("frm1601EQ:txtAtcCd1") == null);
    try std.testing.expect(seedById("frm1601EQ:txtAtcCd2") == null);
    try std.testing.expect(seedById("AtcCode1") == null);
}

test "1601EQ static control ids that exist are unique" {
    for (control_seeds, 0..) |seed, index| {
        const id = seed.id orelse continue;
        for (control_seeds[index + 1 ..]) |other| {
            if (other.id) |other_id| {
                try std.testing.expect(!std.mem.eql(u8, id, other_id));
            }
        }
    }
}
