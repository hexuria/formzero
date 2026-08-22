//! Exact, value-free HTML control declarations for the 136 static controls
//! in Offline eBIRForms 7.9.6 Form 1601C January 2018 (ENCS).
//!
//! Declaration facts from the HTA identified by `evidence.primary_source`:
//! source line, kind, `maxlength`, declared value, markup-disabled state,
//! and radio or checkbox checked attributes. Nothing here claims
//! script-driven runtime state or serializer eligibility.
//!
//! `disabled` is read as a boolean attribute, not as a substring. A
//! substring match reports 52 disabled controls; the real count is 51. The
//! extra one is `frm1601c:txtLineBus` at line 1567, whose class list
//! contains `disabled-dis` while the control itself is not disabled. The
//! same trap appears in 1601EQ and on the same field.
//!
//! Radio ids in this form append the value with an underscore, as in
//! `frm1601c:AmendedRtn_1`, where 1601EQ separates it with a colon. Group
//! membership therefore comes from `name`, never from the id shape.

const std = @import("std");
const occurrences = @import("occurrences.zig");
const evidence = @import("evidence.zig");

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
    .{ .id = null, .source_line = 212, .kind = .button, .max_length = null, .declared_value = "Main Menu", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = null, .source_line = 213, .kind = .button, .max_length = null, .declared_value = "Save", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = null, .source_line = 214, .kind = .button, .max_length = null, .declared_value = "Print", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = null, .source_line = 215, .kind = .button, .max_length = null, .declared_value = "Exit", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "paymentOptionCloseBtn", .source_line = 231, .kind = .button, .max_length = null, .declared_value = "Close", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtMonth", .source_line = 293, .kind = .select_one, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtYear", .source_line = 308, .kind = .text, .max_length = 4, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:AmendedRtn_1", .source_line = 327, .kind = .radio, .max_length = null, .declared_value = "Y", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601c:AmendedRtn", .value = "Y", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601c:AmendedRtn_2", .source_line = 328, .kind = .radio, .max_length = null, .declared_value = "N", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601c:AmendedRtn", .value = "N", .checked = true }, .checkbox_checked = false },
    .{ .id = "frm1601c:TaxWithheld_1", .source_line = 351, .kind = .radio, .max_length = null, .declared_value = "Y", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601c:TaxWithheld", .value = "Y", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601c:TaxWithheld_2", .source_line = 352, .kind = .radio, .max_length = null, .declared_value = "N", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601c:TaxWithheld", .value = "N", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601c:txtSheets", .source_line = 369, .kind = .text, .max_length = 2, .declared_value = "0", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtATC", .source_line = 381, .kind = .text, .max_length = 20, .declared_value = "WW010", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTIN1", .source_line = 417, .kind = .text, .max_length = 3, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTIN2", .source_line = 418, .kind = .text, .max_length = 3, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTIN3", .source_line = 419, .kind = .text, .max_length = 3, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtBranchCode", .source_line = 420, .kind = .text, .max_length = 3, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTaxpayerName", .source_line = 461, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtAddress", .source_line = 494, .kind = .text, .max_length = 100, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtAddress2", .source_line = 508, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtZipCode", .source_line = 522, .kind = .text, .max_length = 12, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTelNum", .source_line = 542, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:CatAgent_P", .source_line = 561, .kind = .radio, .max_length = null, .declared_value = "P", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601c:CatAgent", .value = "P", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601c:CatAgent_G", .source_line = 562, .kind = .radio, .max_length = null, .declared_value = "G", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601c:CatAgent", .value = "G", .checked = false }, .checkbox_checked = false },
    .{ .id = "txtEmail", .source_line = 585, .kind = .text, .max_length = 60, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:SpecialTax_1", .source_line = 608, .kind = .radio, .max_length = null, .declared_value = "Y", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601c:SpecialTax", .value = "Y", .checked = false }, .checkbox_checked = false },
    .{ .id = "frm1601c:SpecialTax_2", .source_line = 609, .kind = .radio, .max_length = null, .declared_value = "N", .disabled_in_markup = false, .radio_declaration = .{ .name = "frm1601c:SpecialTax", .value = "N", .checked = true }, .checkbox_checked = false },
    .{ .id = "frm1601c:selTreaty", .source_line = 621, .kind = .select_one, .max_length = null, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax14", .source_line = 667, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax15", .source_line = 689, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax16", .source_line = 702, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax17", .source_line = 715, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax18", .source_line = 728, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax19", .source_line = 741, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txt20Other", .source_line = 748, .kind = .text, .max_length = 25, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax20", .source_line = 755, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax21", .source_line = 768, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax22", .source_line = 781, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax23", .source_line = 794, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax24", .source_line = 807, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax25", .source_line = 820, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax26", .source_line = 833, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax27", .source_line = 846, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax28", .source_line = 859, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txt29Other", .source_line = 866, .kind = .text, .max_length = 25, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax29", .source_line = 873, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax30", .source_line = 886, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax31", .source_line = 899, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax32", .source_line = 921, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax33", .source_line = 941, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax34", .source_line = 961, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax35", .source_line = 981, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtTax36", .source_line = 994, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "txtTaxAgentNo", .source_line = 1042, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "txtDateIssue", .source_line = 1055, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "txtDateExpiry", .source_line = 1068, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtAgency37", .source_line = 1110, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtNumber37", .source_line = 1111, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtDate37", .source_line = 1112, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtAmount37", .source_line = 1113, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtAgency38", .source_line = 1117, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtNumber38", .source_line = 1118, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtDate38", .source_line = 1119, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtAmount38", .source_line = 1120, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtNumber39", .source_line = 1124, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtDate39", .source_line = 1125, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtAmount39", .source_line = 1126, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtParticular40", .source_line = 1132, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtAgency40", .source_line = 1133, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtNumber40", .source_line = 1134, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtDate40", .source_line = 1135, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtAmount40", .source_line = 1136, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtPg2TIN1", .source_line = 1200, .kind = .text, .max_length = 3, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtPg2TIN2", .source_line = 1201, .kind = .text, .max_length = 3, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtPg2TIN3", .source_line = 1202, .kind = .text, .max_length = 3, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtPg2BranchCode", .source_line = 1203, .kind = .text, .max_length = 5, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtPg2TaxpayerName", .source_line = 1206, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "chkScheduleDelete0", .source_line = 1248, .kind = .checkbox, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtMonthYear0", .source_line = 1249, .kind = .text, .max_length = 7, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtDatePaid0", .source_line = 1250, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtBankCode0", .source_line = 1251, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtNumber0", .source_line = 1252, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtTaxPaid0", .source_line = 1253, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "chkScheduleDelete1", .source_line = 1256, .kind = .checkbox, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtMonthYear1", .source_line = 1257, .kind = .text, .max_length = 7, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtDatePaid1", .source_line = 1258, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtBankCode1", .source_line = 1259, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtNumber1", .source_line = 1260, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtTaxPaid1", .source_line = 1261, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "chkScheduleDelete2", .source_line = 1264, .kind = .checkbox, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtMonthYear2", .source_line = 1265, .kind = .text, .max_length = 7, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtDatePaid2", .source_line = 1266, .kind = .text, .max_length = 10, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtBankCode2", .source_line = 1267, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtNumber2", .source_line = 1268, .kind = .text, .max_length = 20, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtTaxPaid2", .source_line = 1269, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtShouldTaxDue0", .source_line = 1283, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtAdjustments0", .source_line = 1284, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtShouldTaxDue1", .source_line = 1288, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtAdjustments1", .source_line = 1289, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtShouldTaxDue2", .source_line = 1293, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtAdjustments2", .source_line = 1294, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:sched1:txtTotal1", .source_line = 1309, .kind = .text, .max_length = 25, .declared_value = "0.00", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:btnAdd", .source_line = 1316, .kind = .button, .max_length = null, .declared_value = "Add", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:btnDelete", .source_line = 1317, .kind = .button, .max_length = null, .declared_value = "Delete", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:btnPrevPage", .source_line = 1531, .kind = .button, .max_length = null, .declared_value = "Prev", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtCurrentPage", .source_line = 1533, .kind = .text, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtMaxPage", .source_line = 1534, .kind = .text, .max_length = null, .declared_value = "2", .disabled_in_markup = true, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:btnNextPage", .source_line = 1535, .kind = .button, .max_length = null, .declared_value = "Next", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:btnValidate", .source_line = 1544, .kind = .button, .max_length = null, .declared_value = "Validate", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:btnEdit", .source_line = 1545, .kind = .button, .max_length = null, .declared_value = "Edit", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnUpload", .source_line = 1547, .kind = .hidden, .max_length = null, .declared_value = "Submit", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnSave", .source_line = 1548, .kind = .button, .max_length = null, .declared_value = "Save", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnPrint", .source_line = 1549, .kind = .button, .max_length = null, .declared_value = "Print", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:btnFinalCopy", .source_line = 1550, .kind = .button, .max_length = null, .declared_value = "Submit / Final Copy", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "frm1601c:txtLineBus", .source_line = 1567, .kind = .text, .max_length = 60, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnOkImport", .source_line = 1586, .kind = .button, .max_length = null, .declared_value = "OK", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnCancelImport", .source_line = 1587, .kind = .button, .max_length = null, .declared_value = "CANCEL", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "txtFinalFlag", .source_line = 1593, .kind = .text, .max_length = 60, .declared_value = "0", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "txtEnroll", .source_line = 1594, .kind = .text, .max_length = 60, .declared_value = "N", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineConfirmUsername", .source_line = 1611, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineConfirmPassword", .source_line = 1619, .kind = .password, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineConfirmSubmit", .source_line = 1625, .kind = .button, .max_length = null, .declared_value = "Submit", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineConfirmCancel", .source_line = 1628, .kind = .button, .max_length = null, .declared_value = "Cancel", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirEnrollYes", .source_line = 1650, .kind = .button, .max_length = null, .declared_value = "  Ok  ", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirEnrollNo", .source_line = 1653, .kind = .button, .max_length = null, .declared_value = "Cancel", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "isregistered", .source_line = 1671, .kind = .button, .max_length = null, .declared_value = "YES", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "notregistered", .source_line = 1674, .kind = .button, .max_length = null, .declared_value = "NO", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineUsername", .source_line = 1697, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlinePassword", .source_line = 1705, .kind = .password, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineSecret", .source_line = 1706, .kind = .text, .max_length = 50, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineSubmit", .source_line = 1712, .kind = .button, .max_length = null, .declared_value = "Submit", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "ebirOnlineCancel", .source_line = 1715, .kind = .button, .max_length = null, .declared_value = "Cancel", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "driveSelectTPExport", .source_line = 1741, .kind = .select_one, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnOkExport", .source_line = 1750, .kind = .button, .max_length = null, .declared_value = "OK", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "btnCancelExport", .source_line = 1751, .kind = .button, .max_length = null, .declared_value = "CANCEL", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
    .{ .id = "responsetext", .source_line = 1757, .kind = .textarea, .max_length = null, .declared_value = "", .disabled_in_markup = false, .radio_declaration = null, .checkbox_checked = false },
};

pub const contract_count: usize = contracts.len;
pub const markup_disabled_count: usize = 51;
/// A substring match on `disabled` would report this many.
pub const naive_disabled_count: usize = 52;
pub const declared_maxlength_count: usize = 92;

pub fn find(id: []const u8) ?*const Contract {
    for (&contracts) |*entry| {
        const entry_id = entry.id orelse continue;
        if (std.mem.eql(u8, entry_id, id)) return entry;
    }
    return null;
}

pub fn radioGroupSize(name: []const u8) usize {
    var total: usize = 0;
    for (contracts) |entry| {
        const declaration = entry.radio_declaration orelse continue;
        if (std.mem.eql(u8, declaration.name, name)) total += 1;
    }
    return total;
}

test "1601C contract covers the inventory one for one" {
    try std.testing.expectEqual(occurrences.control_count, contract_count);
    for (contracts, occurrences.control_seeds) |entry, seed| {
        try std.testing.expectEqual(seed.source_line, entry.source_line);
        try std.testing.expectEqual(seed.kind, entry.kind);
        if (seed.id) |seed_id| {
            try std.testing.expectEqualStrings(seed_id, entry.id.?);
        } else {
            try std.testing.expect(entry.id == null);
        }
    }
    try std.testing.expect(evidence.readiness.dependency_closure);
}

test "1601C disabled is a boolean attribute, not a substring" {
    var disabled: usize = 0;
    for (contracts) |entry| {
        if (entry.disabled_in_markup) disabled += 1;
    }
    try std.testing.expectEqual(markup_disabled_count, disabled);
    try std.testing.expectEqual(@as(usize, 51), disabled);
    // The naive count is one higher, and this is the control it adds.
    try std.testing.expectEqual(naive_disabled_count, markup_disabled_count + 1);
    const line_of_business = find("frm1601c:txtLineBus").?;
    try std.testing.expect(!line_of_business.disabled_in_markup);
    try std.testing.expectEqual(@as(u32, 1567), line_of_business.source_line);
}

test "1601C radio groups are keyed by name, not by id shape" {
    try std.testing.expectEqual(@as(usize, 2), radioGroupSize("frm1601c:AmendedRtn"));
    try std.testing.expectEqual(@as(usize, 2), radioGroupSize("frm1601c:TaxWithheld"));
    try std.testing.expectEqual(@as(usize, 2), radioGroupSize("frm1601c:CatAgent"));
    try std.testing.expectEqual(@as(usize, 2), radioGroupSize("frm1601c:SpecialTax"));

    // Ids append the value with an underscore rather than a colon.
    const amended_no = find("frm1601c:AmendedRtn_2").?;
    try std.testing.expectEqualStrings("N", amended_no.radio_declaration.?.value);
    try std.testing.expectEqualStrings(
        "frm1601c:AmendedRtn",
        amended_no.radio_declaration.?.name,
    );
}

test "1601C only the two default No answers are checked in markup" {
    var checked: usize = 0;
    for (contracts) |entry| {
        const declaration = entry.radio_declaration orelse continue;
        if (!declaration.checked) continue;
        checked += 1;
        try std.testing.expectEqualStrings("N", declaration.value);
    }
    try std.testing.expectEqual(@as(usize, 2), checked);
    try std.testing.expect(find("frm1601c:AmendedRtn_2").?.radio_declaration.?.checked);
    try std.testing.expect(find("frm1601c:SpecialTax_2").?.radio_declaration.?.checked);
    // Neither category nor tax-withheld carries a default.
    try std.testing.expect(!find("frm1601c:CatAgent_P").?.radio_declaration.?.checked);
    try std.testing.expect(!find("frm1601c:TaxWithheld_1").?.radio_declaration.?.checked);
}

test "1601C every declared maxlength is positive and only on entry controls" {
    var declared: usize = 0;
    for (contracts) |entry| {
        const length = entry.max_length orelse continue;
        declared += 1;
        try std.testing.expect(length > 0);
        try std.testing.expect(entry.kind == .text or entry.kind == .password or
            entry.kind == .textarea or entry.kind == .hidden);
    }
    try std.testing.expectEqual(declared_maxlength_count, declared);
}
