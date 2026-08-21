//! Exact, value-free HTML control declarations for the 98 static controls
//! in Offline eBIRForms 7.9.6 Form 1601EQ January 2018 (ENCS).
//!
//! These are declaration facts from the verified HTA identified by
//! `evidence.primary_source`: source line, kind, `maxlength`, declared
//! value, markup-disabled state, and radio/checkbox checked attributes.
//! They do not claim script-driven runtime state, serializer eligibility,
//! or live `frmMain.elements` order after dynamic ATC rows are created.

const std = @import("std");
const occurrences = @import("occurrences.zig");
const evidence = @import("evidence.zig");

pub const evidence_id = occurrences.evidence_id;

pub const RadioDeclaration = struct {
    name: []const u8,
    value: []const u8,
    checked: bool,
};

pub const Contract = struct {
    id: ?[]const u8,
    source_line: u32,
    kind: occurrences.ControlKind,
    max_length: ?u16,
    declared_value: []const u8,
    disabled_in_markup: bool,
    radio_declaration: ?RadioDeclaration,
    checkbox_checked: bool = false,
};

/// Same order as `occurrences.control_seeds`.
pub const contracts = [_]Contract{
    .{ .id = null, .source_line = 196, .kind = .button, .max_length = null, .declared_value = "Main Menu", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = null, .source_line = 197, .kind = .button, .max_length = null, .declared_value = "Save", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = null, .source_line = 198, .kind = .button, .max_length = null, .declared_value = "Print", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = null, .source_line = 199, .kind = .button, .max_length = null, .declared_value = "Exit", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "paymentOptionCloseBtn", .source_line = 216, .kind = .button, .max_length = null, .declared_value = "Close", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtYear", .source_line = 276, .kind = .text, .max_length = 4, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:optQuarter:1", .source_line = 289, .kind = .radio, .max_length = null, .declared_value = "1", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601EQ:optQuarter", .value = "1", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601EQ:optQuarter:2", .source_line = 290, .kind = .radio, .max_length = null, .declared_value = "2", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601EQ:optQuarter", .value = "2", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601EQ:optQuarter:3", .source_line = 291, .kind = .radio, .max_length = null, .declared_value = "3", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601EQ:optQuarter", .value = "3", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601EQ:optQuarter:4", .source_line = 292, .kind = .radio, .max_length = null, .declared_value = "4", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601EQ:optQuarter", .value = "4", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601EQ:optAmend:Y", .source_line = 311, .kind = .radio, .max_length = null, .declared_value = "Y", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601EQ:optAmend", .value = "Y", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601EQ:optAmend:N", .source_line = 312, .kind = .radio, .max_length = null, .declared_value = "N", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601EQ:optAmend", .value = "N", .checked = true }, .checkbox_checked = false },
    .{ .id = "frm1601EQ:optWithheld:Y", .source_line = 336, .kind = .radio, .max_length = null, .declared_value = "Y", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601EQ:optWithheld", .value = "Y", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601EQ:optWithheld:N", .source_line = 337, .kind = .radio, .max_length = null, .declared_value = "N", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601EQ:optWithheld", .value = "N", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtNoSheets", .source_line = 355, .kind = .text, .max_length = 2, .declared_value = "0", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTIN1", .source_line = 391, .kind = .text, .max_length = 3, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTIN2", .source_line = 392, .kind = .text, .max_length = 3, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTIN3", .source_line = 393, .kind = .text, .max_length = 3, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtBranchCode", .source_line = 394, .kind = .text, .max_length = 5, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTaxpayerName", .source_line = 435, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtLineBus", .source_line = 448, .kind = .text, .max_length = 150, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtAddress", .source_line = 472, .kind = .text, .max_length = 150, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtAddress2", .source_line = 488, .kind = .text, .max_length = 150, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtZipCode", .source_line = 495, .kind = .text, .max_length = 12, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTelNum", .source_line = 513, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:optCategory:P", .source_line = 521, .kind = .radio, .max_length = null, .declared_value = "P", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601EQ:optCategory", .value = "P", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601EQ:optCategory:G", .source_line = 522, .kind = .radio, .max_length = null, .declared_value = "G", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601EQ:optCategory", .value = "G", .checked = false }, .checkbox_checked = false },
    .{ .id = "txtEmail", .source_line = 539, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTotalOtherTax", .source_line = 587, .kind = .text, .max_length = null, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax19", .source_line = 619, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax20", .source_line = 638, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax21", .source_line = 657, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax22", .source_line = 676, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax23", .source_line = 695, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax24", .source_line = 713, .kind = .text, .max_length = 15, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax25", .source_line = 731, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax26", .source_line = 746, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:inputSurcharge", .source_line = 747, .kind = .hidden, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax27", .source_line = 763, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax28", .source_line = 779, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax29", .source_line = 795, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtTax30", .source_line = 812, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:ifRefund", .source_line = 829, .kind = .checkbox, .max_length = null, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:ifIssueCert", .source_line = 830, .kind = .checkbox, .max_length = null, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:ifCarriedOver", .source_line = 831, .kind = .checkbox, .max_length = null, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "txtTaxAgentNo", .source_line = 871, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "txtDateIssue", .source_line = 884, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "txtDateExpiry", .source_line = 897, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtAgency33", .source_line = 938, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtNumber33", .source_line = 939, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtDate33", .source_line = 940, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtAmount33", .source_line = 941, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtAgency34", .source_line = 945, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtNumber34", .source_line = 946, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtDate34", .source_line = 947, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtAmount34", .source_line = 948, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtAgency35", .source_line = 952, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtNumber35", .source_line = 953, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtDate35", .source_line = 954, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtAmount35", .source_line = 955, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtParticular36", .source_line = 961, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtAgency36", .source_line = 962, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtNumber36", .source_line = 963, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtDate36", .source_line = 964, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:txtAmount36", .source_line = 965, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:cmdValidate", .source_line = 1002, .kind = .button, .max_length = null, .declared_value = "Validate", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:cmdEdit", .source_line = 1003, .kind = .button, .max_length = null, .declared_value = "Edit", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnUpload", .source_line = 1004, .kind = .hidden, .max_length = null, .declared_value = "Submit", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnSave", .source_line = 1005, .kind = .button, .max_length = null, .declared_value = "Save", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnPrint", .source_line = 1006, .kind = .button, .max_length = null, .declared_value = "Print", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601EQ:btnFinalCopy", .source_line = 1007, .kind = .button, .max_length = null, .declared_value = "Submit / Final Copy", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnOkPop", .source_line = 1058, .kind = .button, .max_length = null, .declared_value = "OK", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "hPartIITableSize", .source_line = 1065, .kind = .text, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnPrintOtherAtc", .source_line = 1091, .kind = .button, .max_length = null, .declared_value = " Print ", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = null, .source_line = 1092, .kind = .button, .max_length = null, .declared_value = " Close ", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnClearOtherAtc", .source_line = 1093, .kind = .button, .max_length = null, .declared_value = " Clear ", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnOkImport", .source_line = 1120, .kind = .button, .max_length = null, .declared_value = "OK", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnCancelImport", .source_line = 1121, .kind = .button, .max_length = null, .declared_value = "CANCEL", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "txtFinalFlag", .source_line = 1129, .kind = .text, .max_length = 60, .declared_value = "0", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "txtEnroll", .source_line = 1130, .kind = .text, .max_length = 60, .declared_value = "N", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineConfirmUsername", .source_line = 1148, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineConfirmPassword", .source_line = 1156, .kind = .password, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineConfirmSubmit", .source_line = 1161, .kind = .button, .max_length = null, .declared_value = "Submit", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineConfirmCancel", .source_line = 1164, .kind = .button, .max_length = null, .declared_value = "Cancel", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnAgree", .source_line = 1303, .kind = .button, .max_length = null, .declared_value = "Agree", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirEnrollYes", .source_line = 1323, .kind = .button, .max_length = null, .declared_value = "  Ok  ", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirEnrollNo", .source_line = 1326, .kind = .button, .max_length = null, .declared_value = "Cancel", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "isregistered", .source_line = 1345, .kind = .button, .max_length = null, .declared_value = "YES", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "notregistered", .source_line = 1348, .kind = .button, .max_length = null, .declared_value = "NO", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineUsername", .source_line = 1370, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlinePassword", .source_line = 1378, .kind = .password, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineSecret", .source_line = 1379, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineSubmit", .source_line = 1384, .kind = .button, .max_length = null, .declared_value = "Submit", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineCancel", .source_line = 1387, .kind = .button, .max_length = null, .declared_value = "Cancel", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "driveSelectTPExport", .source_line = 1414, .kind = .select_one, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnOkExport", .source_line = 1423, .kind = .button, .max_length = null, .declared_value = "OK", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnCancelExport", .source_line = 1424, .kind = .button, .max_length = null, .declared_value = "CANCEL", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "responsetext", .source_line = 1430, .kind = .textarea, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
};

comptime {
    if (contracts.len != occurrences.control_seeds.len) {
        @compileError("1601EQ control contracts must match static control seeds");
    }
}

pub fn find(id: []const u8) ?*const Contract {
    for (&contracts) |*contract| {
        if (contract.id) |contract_id| {
            if (std.mem.eql(u8, contract_id, id)) return contract;
        }
    }
    return null;
}

test "1601EQ control declarations cover all 98 static controls in seed order" {
    try std.testing.expectEqual(occurrences.control_seeds.len, contracts.len);

    var text_count: usize = 0;
    var radio_count: usize = 0;
    var checkbox_count: usize = 0;
    var button_count: usize = 0;
    var hidden_count: usize = 0;
    var password_count: usize = 0;
    var select_count: usize = 0;
    var textarea_count: usize = 0;
    var disabled_count: usize = 0;
    for (contracts, occurrences.control_seeds) |contract, seed| {
        if (seed.id) |seed_id| {
            try std.testing.expectEqualStrings(seed_id, contract.id.?);
        } else {
            try std.testing.expect(contract.id == null);
        }
        try std.testing.expectEqual(seed.source_line, contract.source_line);
        try std.testing.expectEqual(seed.kind, contract.kind);
        try std.testing.expectEqualStrings(seed.declared_value, contract.declared_value);
        if (contract.disabled_in_markup) disabled_count += 1;
        switch (contract.kind) {
            .text => {
                text_count += 1;
                try std.testing.expect(contract.radio_declaration == null);
                try std.testing.expect(!contract.checkbox_checked);
            },
            .radio => {
                radio_count += 1;
                const declaration = contract.radio_declaration orelse
                    return error.MissingRadioDeclaration;
                try std.testing.expectEqualStrings(contract.declared_value, declaration.value);
                try std.testing.expect(contract.max_length == null);
                try std.testing.expect(!contract.checkbox_checked);
            },
            .checkbox => {
                checkbox_count += 1;
                try std.testing.expect(contract.radio_declaration == null);
            },
            .button => {
                button_count += 1;
                try std.testing.expect(contract.radio_declaration == null);
                try std.testing.expect(contract.max_length == null);
            },
            .hidden => {
                hidden_count += 1;
                try std.testing.expect(contract.radio_declaration == null);
            },
            .password => {
                password_count += 1;
                try std.testing.expect(contract.radio_declaration == null);
            },
            .select_one => {
                select_count += 1;
                try std.testing.expect(contract.radio_declaration == null);
                try std.testing.expect(contract.max_length == null);
            },
            .textarea => {
                textarea_count += 1;
                try std.testing.expect(contract.radio_declaration == null);
            },
        }
    }

    try std.testing.expectEqual(@as(usize, 52), text_count);
    try std.testing.expectEqual(@as(usize, 10), radio_count);
    try std.testing.expectEqual(@as(usize, 3), checkbox_count);
    try std.testing.expectEqual(@as(usize, 27), button_count);
    try std.testing.expectEqual(@as(usize, 2), hidden_count);
    try std.testing.expectEqual(@as(usize, 2), password_count);
    try std.testing.expectEqual(@as(usize, 1), select_count);
    try std.testing.expectEqual(@as(usize, 1), textarea_count);
    try std.testing.expectEqual(@as(usize, 30), disabled_count);
    try std.testing.expect(!occurrences.serializer_reviewed);
    try std.testing.expect(!evidence.readiness.identityReady());
}

test "1601EQ text maxlength and declaration defaults match the verified HTA" {
    const year = find("frm1601EQ:txtYear").?;
    try std.testing.expectEqual(@as(?u16, 4), year.max_length);
    try std.testing.expectEqualStrings("", year.declared_value);
    try std.testing.expect(!year.disabled_in_markup);

    const sheets = find("frm1601EQ:txtNoSheets").?;
    try std.testing.expectEqual(@as(?u16, 2), sheets.max_length);
    try std.testing.expectEqualStrings("0", sheets.declared_value);

    try std.testing.expectEqual(@as(?u16, 3), find("frm1601EQ:txtTIN1").?.max_length);
    try std.testing.expectEqual(@as(?u16, 5), find("frm1601EQ:txtBranchCode").?.max_length);
    try std.testing.expectEqual(@as(?u16, 50), find("frm1601EQ:txtTaxpayerName").?.max_length);
    try std.testing.expectEqual(@as(?u16, 150), find("frm1601EQ:txtAddress").?.max_length);
    try std.testing.expect(!find("frm1601EQ:txtAddress").?.disabled_in_markup);
    try std.testing.expectEqualStrings("0.00", find("frm1601EQ:txtTax19").?.declared_value);
    try std.testing.expect(find("frm1601EQ:txtTax19").?.disabled_in_markup);
}

test "1601EQ radio grouping keeps amended No checked in markup" {
    const yes = find("frm1601EQ:optAmend:Y").?;
    const no = find("frm1601EQ:optAmend:N").?;
    try std.testing.expectEqualStrings("frm1601EQ:optAmend", yes.radio_declaration.?.name);
    try std.testing.expectEqualStrings("Y", yes.radio_declaration.?.value);
    try std.testing.expect(!yes.radio_declaration.?.checked);
    try std.testing.expect(!yes.disabled_in_markup);
    try std.testing.expectEqualStrings("N", no.radio_declaration.?.value);
    try std.testing.expect(no.radio_declaration.?.checked);
    try std.testing.expect(!no.disabled_in_markup);

    var checked_radios: usize = 0;
    for (contracts) |contract| {
        if (contract.radio_declaration) |declaration| {
            if (declaration.checked) checked_radios += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), checked_radios);
}

test "1601EQ over-remittance checkboxes are present and markup-disabled" {
    for ([_][]const u8{
        "frm1601EQ:ifRefund",
        "frm1601EQ:ifIssueCert",
        "frm1601EQ:ifCarriedOver",
    }) |id| {
        const contract = find(id).?;
        try std.testing.expectEqual(occurrences.ControlKind.checkbox, contract.kind);
        try std.testing.expect(contract.disabled_in_markup);
        try std.testing.expect(!contract.checkbox_checked);
    }
}
