//! Static control inventory for BIR Form 1601C January 2018 (ENCS).
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//!
//! Every `input`, `select` and `textarea` tag present in the markup, in
//! source order, after removing `script`, `style` and HTML comment regions.
//!
//! Removing comments matters: a naive parse finds 138 tags and reports
//! `txtEmail` and `btnUpload` as duplicate ids. Both extra tags sit inside
//! `<!-- -->`, and the real inventory is 136 with every id unique. The
//! commented pair is recorded here as a count rather than as controls.
//!
//! Attribute quoting is not uniform either. Every id in this file is double
//! quoted except `responsetext` at line 1757, which is single quoted. A
//! parse that only accepts double quotes reports 131 identified controls and
//! four anonymous ones; the file actually carries 132 and four.
//!
//! `inside_frm_main` marks the controls the submitted form element encloses.
//! `frmMain` opens at line 234 and closes at line 1569; the chrome buttons above
//! it and the export dialog below it are outside.
//!
//! This is a static census. It does not cover controls built at runtime, and
//! nothing here is a serializer contract: `serializer_reviewed` is false.

const std = @import("std");
const evidence = @import("evidence.zig");

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
    /// One-based order of static tags in the HTA.
    ordinal: u16,
    source_line: u32,
    kind: ControlKind,
    id: ?[]const u8,
    name: ?[]const u8,
    declared_value: []const u8,
    inside_frm_main: bool,
};

pub const frm_main_open_line: u32 = 234;
pub const frm_main_close_line: u32 = 1569;

/// Tags found only inside HTML comments, excluded from the inventory.
pub const commented_out_control_count: usize = 2;

pub const serializer_reviewed = false;

pub const control_seeds = [_]ControlSeed{
    .{ .ordinal = 1, .source_line = 212, .kind = .button, .id = null, .name = null, .declared_value = "Main Menu", .inside_frm_main = false },
    .{ .ordinal = 2, .source_line = 213, .kind = .button, .id = null, .name = null, .declared_value = "Save", .inside_frm_main = false },
    .{ .ordinal = 3, .source_line = 214, .kind = .button, .id = null, .name = null, .declared_value = "Print", .inside_frm_main = false },
    .{ .ordinal = 4, .source_line = 215, .kind = .button, .id = null, .name = null, .declared_value = "Exit", .inside_frm_main = false },
    .{ .ordinal = 5, .source_line = 231, .kind = .button, .id = "paymentOptionCloseBtn", .name = null, .declared_value = "Close", .inside_frm_main = false },
    .{ .ordinal = 6, .source_line = 293, .kind = .select_one, .id = "frm1601c:txtMonth", .name = "frm1601c:txtMonth", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 7, .source_line = 308, .kind = .text, .id = "frm1601c:txtYear", .name = "frm1601c:txtYear", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 8, .source_line = 327, .kind = .radio, .id = "frm1601c:AmendedRtn_1", .name = "frm1601c:AmendedRtn", .declared_value = "Y", .inside_frm_main = true },
    .{ .ordinal = 9, .source_line = 328, .kind = .radio, .id = "frm1601c:AmendedRtn_2", .name = "frm1601c:AmendedRtn", .declared_value = "N", .inside_frm_main = true },
    .{ .ordinal = 10, .source_line = 351, .kind = .radio, .id = "frm1601c:TaxWithheld_1", .name = "frm1601c:TaxWithheld", .declared_value = "Y", .inside_frm_main = true },
    .{ .ordinal = 11, .source_line = 352, .kind = .radio, .id = "frm1601c:TaxWithheld_2", .name = "frm1601c:TaxWithheld", .declared_value = "N", .inside_frm_main = true },
    .{ .ordinal = 12, .source_line = 369, .kind = .text, .id = "frm1601c:txtSheets", .name = "frm1601c:txtSheets", .declared_value = "0", .inside_frm_main = true },
    .{ .ordinal = 13, .source_line = 381, .kind = .text, .id = "frm1601c:txtATC", .name = "frm1601c:txtATC", .declared_value = "WW010", .inside_frm_main = true },
    .{ .ordinal = 14, .source_line = 417, .kind = .text, .id = "frm1601c:txtTIN1", .name = "frm1601c:txtTIN1", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 15, .source_line = 418, .kind = .text, .id = "frm1601c:txtTIN2", .name = "frm1601c:txtTIN2", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 16, .source_line = 419, .kind = .text, .id = "frm1601c:txtTIN3", .name = "frm1601c:txtTIN3", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 17, .source_line = 420, .kind = .text, .id = "frm1601c:txtBranchCode", .name = "frm1601c:txtBranchCode", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 18, .source_line = 461, .kind = .text, .id = "frm1601c:txtTaxpayerName", .name = "frm1601c:txtTaxpayerName", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 19, .source_line = 494, .kind = .text, .id = "frm1601c:txtAddress", .name = "frm1601c:txtAddress", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 20, .source_line = 508, .kind = .text, .id = "frm1601c:txtAddress2", .name = "frm1601c:txtAddress2", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 21, .source_line = 522, .kind = .text, .id = "frm1601c:txtZipCode", .name = "frm1601c:txtZipCode", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 22, .source_line = 542, .kind = .text, .id = "frm1601c:txtTelNum", .name = "frm1601c:txtTelNum", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 23, .source_line = 561, .kind = .radio, .id = "frm1601c:CatAgent_P", .name = "frm1601c:CatAgent", .declared_value = "P", .inside_frm_main = true },
    .{ .ordinal = 24, .source_line = 562, .kind = .radio, .id = "frm1601c:CatAgent_G", .name = "frm1601c:CatAgent", .declared_value = "G", .inside_frm_main = true },
    .{ .ordinal = 25, .source_line = 585, .kind = .text, .id = "txtEmail", .name = "txtEmail", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 26, .source_line = 608, .kind = .radio, .id = "frm1601c:SpecialTax_1", .name = "frm1601c:SpecialTax", .declared_value = "Y", .inside_frm_main = true },
    .{ .ordinal = 27, .source_line = 609, .kind = .radio, .id = "frm1601c:SpecialTax_2", .name = "frm1601c:SpecialTax", .declared_value = "N", .inside_frm_main = true },
    .{ .ordinal = 28, .source_line = 621, .kind = .select_one, .id = "frm1601c:selTreaty", .name = "frm1601c:selTreaty", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 29, .source_line = 667, .kind = .text, .id = "frm1601c:txtTax14", .name = "frm1601c:txtTax14", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 30, .source_line = 689, .kind = .text, .id = "frm1601c:txtTax15", .name = "frm1601c:txtTax15", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 31, .source_line = 702, .kind = .text, .id = "frm1601c:txtTax16", .name = "frm1601c:txtTax16", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 32, .source_line = 715, .kind = .text, .id = "frm1601c:txtTax17", .name = "frm1601c:txtTax17", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 33, .source_line = 728, .kind = .text, .id = "frm1601c:txtTax18", .name = "frm1601c:txtTax18", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 34, .source_line = 741, .kind = .text, .id = "frm1601c:txtTax19", .name = "frm1601c:txtTax19", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 35, .source_line = 748, .kind = .text, .id = "frm1601c:txt20Other", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 36, .source_line = 755, .kind = .text, .id = "frm1601c:txtTax20", .name = "frm1601c:txtTax20", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 37, .source_line = 768, .kind = .text, .id = "frm1601c:txtTax21", .name = "frm1601c:txtTax21", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 38, .source_line = 781, .kind = .text, .id = "frm1601c:txtTax22", .name = "frm1601c:txtTax22", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 39, .source_line = 794, .kind = .text, .id = "frm1601c:txtTax23", .name = "frm1601c:txtTax23", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 40, .source_line = 807, .kind = .text, .id = "frm1601c:txtTax24", .name = "frm1601c:txtTax24", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 41, .source_line = 820, .kind = .text, .id = "frm1601c:txtTax25", .name = "frm1601c:txtTax25", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 42, .source_line = 833, .kind = .text, .id = "frm1601c:txtTax26", .name = "frm1601c:txtTax26", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 43, .source_line = 846, .kind = .text, .id = "frm1601c:txtTax27", .name = "frm1601c:txtTax27", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 44, .source_line = 859, .kind = .text, .id = "frm1601c:txtTax28", .name = "frm1601c:txtTax28", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 45, .source_line = 866, .kind = .text, .id = "frm1601c:txt29Other", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 46, .source_line = 873, .kind = .text, .id = "frm1601c:txtTax29", .name = "frm1601c:txtTax29", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 47, .source_line = 886, .kind = .text, .id = "frm1601c:txtTax30", .name = "frm1601c:txtTax30", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 48, .source_line = 899, .kind = .text, .id = "frm1601c:txtTax31", .name = "frm1601c:txtTax31", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 49, .source_line = 921, .kind = .text, .id = "frm1601c:txtTax32", .name = "frm1601c:txtTax32", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 50, .source_line = 941, .kind = .text, .id = "frm1601c:txtTax33", .name = "frm1601c:txtTax33", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 51, .source_line = 961, .kind = .text, .id = "frm1601c:txtTax34", .name = "frm1601c:txtTax34", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 52, .source_line = 981, .kind = .text, .id = "frm1601c:txtTax35", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 53, .source_line = 994, .kind = .text, .id = "frm1601c:txtTax36", .name = "frm1601c:txtTax36", .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 54, .source_line = 1042, .kind = .text, .id = "txtTaxAgentNo", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 55, .source_line = 1055, .kind = .text, .id = "txtDateIssue", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 56, .source_line = 1068, .kind = .text, .id = "txtDateExpiry", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 57, .source_line = 1110, .kind = .text, .id = "frm1601c:txtAgency37", .name = "frm1601c:txtAgency37", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 58, .source_line = 1111, .kind = .text, .id = "frm1601c:txtNumber37", .name = "frm1601c:txtNumber37", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 59, .source_line = 1112, .kind = .text, .id = "frm1601c:txtDate37", .name = "frm1601c:txtDate37", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 60, .source_line = 1113, .kind = .text, .id = "frm1601c:txtAmount37", .name = "frm1601c:txtAmount37", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 61, .source_line = 1117, .kind = .text, .id = "frm1601c:txtAgency38", .name = "frm1601c:txtAgency38", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 62, .source_line = 1118, .kind = .text, .id = "frm1601c:txtNumber38", .name = "frm1601c:txtNumber38", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 63, .source_line = 1119, .kind = .text, .id = "frm1601c:txtDate38", .name = "frm1601c:txtDate38", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 64, .source_line = 1120, .kind = .text, .id = "frm1601c:txtAmount38", .name = "frm1601c:txtAmount38", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 65, .source_line = 1124, .kind = .text, .id = "frm1601c:txtNumber39", .name = "frm1601c:txtNumber39", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 66, .source_line = 1125, .kind = .text, .id = "frm1601c:txtDate39", .name = "frm1601c:txtDate39", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 67, .source_line = 1126, .kind = .text, .id = "frm1601c:txtAmount39", .name = "frm1601c:txtAmount39", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 68, .source_line = 1132, .kind = .text, .id = "frm1601c:txtParticular40", .name = "frm1601c:txtParticular40", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 69, .source_line = 1133, .kind = .text, .id = "frm1601c:txtAgency40", .name = "frm1601c:txtAgency40", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 70, .source_line = 1134, .kind = .text, .id = "frm1601c:txtNumber40", .name = "frm1601c:txtNumber40", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 71, .source_line = 1135, .kind = .text, .id = "frm1601c:txtDate40", .name = "frm1601c:txtDate40", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 72, .source_line = 1136, .kind = .text, .id = "frm1601c:txtAmount40", .name = "frm1601c:txtAmount40", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 73, .source_line = 1200, .kind = .text, .id = "frm1601c:txtPg2TIN1", .name = "frm1601c:txtPg2TIN1", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 74, .source_line = 1201, .kind = .text, .id = "frm1601c:txtPg2TIN2", .name = "frm1601c:txtPg2TIN2", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 75, .source_line = 1202, .kind = .text, .id = "frm1601c:txtPg2TIN3", .name = "frm1601c:txtPg2TIN3", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 76, .source_line = 1203, .kind = .text, .id = "frm1601c:txtPg2BranchCode", .name = "frm1601c:txtPg2BranchCode", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 77, .source_line = 1206, .kind = .text, .id = "frm1601c:txtPg2TaxpayerName", .name = "frm1601c:txtPg2TaxpayerName", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 78, .source_line = 1248, .kind = .checkbox, .id = "chkScheduleDelete0", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 79, .source_line = 1249, .kind = .text, .id = "frm1601c:sched1:txtMonthYear0", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 80, .source_line = 1250, .kind = .text, .id = "frm1601c:sched1:txtDatePaid0", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 81, .source_line = 1251, .kind = .text, .id = "frm1601c:sched1:txtBankCode0", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 82, .source_line = 1252, .kind = .text, .id = "frm1601c:sched1:txtNumber0", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 83, .source_line = 1253, .kind = .text, .id = "frm1601c:sched1:txtTaxPaid0", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 84, .source_line = 1256, .kind = .checkbox, .id = "chkScheduleDelete1", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 85, .source_line = 1257, .kind = .text, .id = "frm1601c:sched1:txtMonthYear1", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 86, .source_line = 1258, .kind = .text, .id = "frm1601c:sched1:txtDatePaid1", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 87, .source_line = 1259, .kind = .text, .id = "frm1601c:sched1:txtBankCode1", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 88, .source_line = 1260, .kind = .text, .id = "frm1601c:sched1:txtNumber1", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 89, .source_line = 1261, .kind = .text, .id = "frm1601c:sched1:txtTaxPaid1", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 90, .source_line = 1264, .kind = .checkbox, .id = "chkScheduleDelete2", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 91, .source_line = 1265, .kind = .text, .id = "frm1601c:sched1:txtMonthYear2", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 92, .source_line = 1266, .kind = .text, .id = "frm1601c:sched1:txtDatePaid2", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 93, .source_line = 1267, .kind = .text, .id = "frm1601c:sched1:txtBankCode2", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 94, .source_line = 1268, .kind = .text, .id = "frm1601c:sched1:txtNumber2", .name = null, .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 95, .source_line = 1269, .kind = .text, .id = "frm1601c:sched1:txtTaxPaid2", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 96, .source_line = 1283, .kind = .text, .id = "frm1601c:sched1:txtShouldTaxDue0", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 97, .source_line = 1284, .kind = .text, .id = "frm1601c:sched1:txtAdjustments0", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 98, .source_line = 1288, .kind = .text, .id = "frm1601c:sched1:txtShouldTaxDue1", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 99, .source_line = 1289, .kind = .text, .id = "frm1601c:sched1:txtAdjustments1", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 100, .source_line = 1293, .kind = .text, .id = "frm1601c:sched1:txtShouldTaxDue2", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 101, .source_line = 1294, .kind = .text, .id = "frm1601c:sched1:txtAdjustments2", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 102, .source_line = 1309, .kind = .text, .id = "frm1601c:sched1:txtTotal1", .name = null, .declared_value = "0.00", .inside_frm_main = true },
    .{ .ordinal = 103, .source_line = 1316, .kind = .button, .id = "frm1601c:btnAdd", .name = "frm1601c:btnAdd", .declared_value = "Add", .inside_frm_main = true },
    .{ .ordinal = 104, .source_line = 1317, .kind = .button, .id = "frm1601c:btnDelete", .name = "frm1601c:btnDelete", .declared_value = "Delete", .inside_frm_main = true },
    .{ .ordinal = 105, .source_line = 1531, .kind = .button, .id = "frm1601c:btnPrevPage", .name = "frm1601c:btnPrevPage", .declared_value = "Prev", .inside_frm_main = true },
    .{ .ordinal = 106, .source_line = 1533, .kind = .text, .id = "frm1601c:txtCurrentPage", .name = "frm1601c:txtCurrentPage", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 107, .source_line = 1534, .kind = .text, .id = "frm1601c:txtMaxPage", .name = null, .declared_value = "2", .inside_frm_main = true },
    .{ .ordinal = 108, .source_line = 1535, .kind = .button, .id = "frm1601c:btnNextPage", .name = "frm1601c:btnNextPage", .declared_value = "Next", .inside_frm_main = true },
    .{ .ordinal = 109, .source_line = 1544, .kind = .button, .id = "frm1601c:btnValidate", .name = "frm1601c:btnValidate", .declared_value = "Validate", .inside_frm_main = true },
    .{ .ordinal = 110, .source_line = 1545, .kind = .button, .id = "frm1601c:btnEdit", .name = "frm1601c:btnEdit", .declared_value = "Edit", .inside_frm_main = true },
    .{ .ordinal = 111, .source_line = 1547, .kind = .hidden, .id = "btnUpload", .name = "btnUpload", .declared_value = "Submit", .inside_frm_main = true },
    .{ .ordinal = 112, .source_line = 1548, .kind = .button, .id = "btnSave", .name = "btnSave", .declared_value = "Save", .inside_frm_main = true },
    .{ .ordinal = 113, .source_line = 1549, .kind = .button, .id = "btnPrint", .name = "btnPrint", .declared_value = "Print", .inside_frm_main = true },
    .{ .ordinal = 114, .source_line = 1550, .kind = .button, .id = "frm1601c:btnFinalCopy", .name = "frm1601c:btnFinalCopy", .declared_value = "Submit / Final Copy", .inside_frm_main = true },
    .{ .ordinal = 115, .source_line = 1567, .kind = .text, .id = "frm1601c:txtLineBus", .name = "frm1601c:txtLineBus", .declared_value = "", .inside_frm_main = true },
    .{ .ordinal = 116, .source_line = 1586, .kind = .button, .id = "btnOkImport", .name = "btnOkImport", .declared_value = "OK", .inside_frm_main = false },
    .{ .ordinal = 117, .source_line = 1587, .kind = .button, .id = "btnCancelImport", .name = "btnCancelImport", .declared_value = "CANCEL", .inside_frm_main = false },
    .{ .ordinal = 118, .source_line = 1593, .kind = .text, .id = "txtFinalFlag", .name = "txtFinalFlag", .declared_value = "0", .inside_frm_main = false },
    .{ .ordinal = 119, .source_line = 1594, .kind = .text, .id = "txtEnroll", .name = "txtEnroll", .declared_value = "N", .inside_frm_main = false },
    .{ .ordinal = 120, .source_line = 1611, .kind = .text, .id = "ebirOnlineConfirmUsername", .name = null, .declared_value = "", .inside_frm_main = false },
    .{ .ordinal = 121, .source_line = 1619, .kind = .password, .id = "ebirOnlineConfirmPassword", .name = null, .declared_value = "", .inside_frm_main = false },
    .{ .ordinal = 122, .source_line = 1625, .kind = .button, .id = "ebirOnlineConfirmSubmit", .name = null, .declared_value = "Submit", .inside_frm_main = false },
    .{ .ordinal = 123, .source_line = 1628, .kind = .button, .id = "ebirOnlineConfirmCancel", .name = null, .declared_value = "Cancel", .inside_frm_main = false },
    .{ .ordinal = 124, .source_line = 1650, .kind = .button, .id = "ebirEnrollYes", .name = null, .declared_value = "  Ok  ", .inside_frm_main = false },
    .{ .ordinal = 125, .source_line = 1653, .kind = .button, .id = "ebirEnrollNo", .name = null, .declared_value = "Cancel", .inside_frm_main = false },
    .{ .ordinal = 126, .source_line = 1671, .kind = .button, .id = "isregistered", .name = null, .declared_value = "YES", .inside_frm_main = false },
    .{ .ordinal = 127, .source_line = 1674, .kind = .button, .id = "notregistered", .name = null, .declared_value = "NO", .inside_frm_main = false },
    .{ .ordinal = 128, .source_line = 1697, .kind = .text, .id = "ebirOnlineUsername", .name = null, .declared_value = "", .inside_frm_main = false },
    .{ .ordinal = 129, .source_line = 1705, .kind = .password, .id = "ebirOnlinePassword", .name = null, .declared_value = "", .inside_frm_main = false },
    .{ .ordinal = 130, .source_line = 1706, .kind = .text, .id = "ebirOnlineSecret", .name = null, .declared_value = "", .inside_frm_main = false },
    .{ .ordinal = 131, .source_line = 1712, .kind = .button, .id = "ebirOnlineSubmit", .name = null, .declared_value = "Submit", .inside_frm_main = false },
    .{ .ordinal = 132, .source_line = 1715, .kind = .button, .id = "ebirOnlineCancel", .name = null, .declared_value = "Cancel", .inside_frm_main = false },
    .{ .ordinal = 133, .source_line = 1741, .kind = .select_one, .id = "driveSelectTPExport", .name = "driveSelectTPExport", .declared_value = "", .inside_frm_main = false },
    .{ .ordinal = 134, .source_line = 1750, .kind = .button, .id = "btnOkExport", .name = "btnOk", .declared_value = "OK", .inside_frm_main = false },
    .{ .ordinal = 135, .source_line = 1751, .kind = .button, .id = "btnCancelExport", .name = "btnCancel", .declared_value = "CANCEL", .inside_frm_main = false },
    .{ .ordinal = 136, .source_line = 1757, .kind = .textarea, .id = "responsetext", .name = null, .declared_value = "", .inside_frm_main = false },
};

pub const control_count: usize = control_seeds.len;
pub const identified_control_count: usize = 132;
pub const unidentified_control_count: usize = 4;

pub fn find(id: []const u8) ?*const ControlSeed {
    for (&control_seeds) |*seed| {
        const seed_id = seed.id orelse continue;
        if (std.mem.eql(u8, seed_id, id)) return seed;
    }
    return null;
}

pub fn countInsideForm() usize {
    var total: usize = 0;
    for (control_seeds) |seed| {
        if (seed.inside_frm_main) total += 1;
    }
    return total;
}

test "1601C inventory is a static census and claims no serializer" {
    try std.testing.expectEqual(@as(usize, 136), control_count);
    try std.testing.expect(!serializer_reviewed);
    // Closure is complete for this form, so the inventory is not fail-closed
    // for the reason 1601EQ's parts are.
    try std.testing.expect(evidence.readiness.dependency_closure);
}

test "1601C ordinals are contiguous and lines never go backwards" {
    var previous_line: u32 = 0;
    for (control_seeds, 0..) |seed, index| {
        try std.testing.expectEqual(@as(u16, @intCast(index + 1)), seed.ordinal);
        try std.testing.expect(seed.source_line >= previous_line);
        previous_line = seed.source_line;
    }
}

test "1601C every declared id is unique once comments are removed" {
    var identified: usize = 0;
    for (control_seeds, 0..) |seed, index| {
        const id = seed.id orelse continue;
        identified += 1;
        for (control_seeds[index + 1 ..]) |other| {
            const other_id = other.id orelse continue;
            try std.testing.expect(!std.mem.eql(u8, id, other_id));
        }
    }
    try std.testing.expectEqual(identified_control_count, identified);
    try std.testing.expectEqual(unidentified_control_count, control_count - identified);
    // The two apparent duplicates are commented-out markup, not controls.
    try std.testing.expectEqual(@as(usize, 2), commented_out_control_count);
    try std.testing.expect(find("txtEmail") != null);
    try std.testing.expect(find("btnUpload") != null);
}

test "1601C form membership follows the frmMain element bounds" {
    try std.testing.expect(frm_main_close_line > frm_main_open_line);
    for (control_seeds) |seed| {
        const inside = seed.source_line > frm_main_open_line and
            seed.source_line < frm_main_close_line;
        try std.testing.expectEqual(inside, seed.inside_frm_main);
    }
    // Chrome above and the export dialog below are outside it.
    try std.testing.expect(countInsideForm() < control_count);
    try std.testing.expect(countInsideForm() > 0);
}

test "1601C kinds cover the shapes the markup actually uses" {
    var text: usize = 0;
    var selects: usize = 0;
    var password: usize = 0;
    for (control_seeds) |seed| {
        switch (seed.kind) {
            .text => text += 1,
            .select_one => selects += 1,
            .password => password += 1,
            else => {},
        }
    }
    try std.testing.expectEqual(@as(usize, 92), text);
    // Three static selects, where 1601EQ builds its only one at runtime.
    try std.testing.expectEqual(@as(usize, 3), selects);
    try std.testing.expectEqual(@as(usize, 2), password);
}

test "1601C the single-quoted id is carried like any other" {
    const single_quoted = find("responsetext") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(ControlKind.textarea, single_quoted.kind);
    try std.testing.expectEqual(@as(u32, 1757), single_quoted.source_line);
    // It sits outside the submitted form.
    try std.testing.expect(!single_quoted.inside_frm_main);
}
