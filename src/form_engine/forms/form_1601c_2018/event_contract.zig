//! Static event-attribute inventory for BIR Form 1601C January 2018 (ENCS).
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//!
//! Every `on*` attribute declared on a static control, with the control it
//! sits on and the attribute text verbatim. Comment regions are removed
//! first, so nothing here comes from markup the browser never parses.
//!
//! Six bindings declare an empty attribute. Two of them are the category
//! radios: `frm1601c:CatAgent_P` and `frm1601c:CatAgent_G` both carry
//! `onclick=""`. The comparable control in 1601EQ calls `changeCategory`,
//! which clears the computation behind a confirm. Changing category on this
//! form does nothing at all. The other four sit on `txtFinalFlag` and
//! `txtEnroll`.
//!
//! This records what the markup declares. It is not a handler
//! implementation: `handlers_implemented` is false, and no behaviour of the
//! named functions is claimed here.

const std = @import("std");
const occurrences = @import("occurrences.zig");
const evidence = @import("evidence.zig");

pub const EventKind = enum {
    click,
    change,
    key_press,
    blur,
    key_down,
    key_up,
};

pub const Binding = struct {
    control_id: ?[]const u8,
    source_line: u32,
    event: EventKind,
    /// Attribute text exactly as declared, empty string included.
    attribute: []const u8,
};

pub const handlers_implemented = false;

pub const bindings = [_]Binding{
    .{ .control_id = null, .source_line = 212, .event = .click, .attribute = "window.location = '../BIRForms.hta';" },
    .{ .control_id = "frm1601c:txtMonth", .source_line = 293, .event = .change, .attribute = "validateRtnPeriod();enableSaveButton();" },
    .{ .control_id = "frm1601c:txtYear", .source_line = 308, .event = .key_press, .attribute = "return wholenumber(this, event);enableSaveButton();" },
    .{ .control_id = "frm1601c:txtYear", .source_line = 308, .event = .blur, .attribute = "validateRtnPeriod();enableSaveButton();" },
    .{ .control_id = "frm1601c:AmendedRtn_1", .source_line = 327, .event = .click, .attribute = "changeAmended()" },
    .{ .control_id = "frm1601c:AmendedRtn_2", .source_line = 328, .event = .click, .attribute = "changeAmended()" },
    .{ .control_id = "frm1601c:TaxWithheld_1", .source_line = 351, .event = .click, .attribute = "disableTaxdue(false);" },
    .{ .control_id = "frm1601c:TaxWithheld_2", .source_line = 352, .event = .click, .attribute = "cancelAllCompute();" },
    .{ .control_id = "frm1601c:txtSheets", .source_line = 369, .event = .key_press, .attribute = "return wholenumber(this, event)" },
    .{ .control_id = "frm1601c:txtTIN1", .source_line = 417, .event = .key_press, .attribute = "return wholenumber(this, event); enableSaveButton();" },
    .{ .control_id = "frm1601c:txtTIN2", .source_line = 418, .event = .key_press, .attribute = "return wholenumber(this, event); enableSaveButton();" },
    .{ .control_id = "frm1601c:txtTIN3", .source_line = 419, .event = .key_press, .attribute = "return wholenumber(this, event);enableSaveButton();" },
    .{ .control_id = "frm1601c:txtBranchCode", .source_line = 420, .event = .key_press, .attribute = "return letternumber(event); enableSaveButton();" },
    .{ .control_id = "frm1601c:txtTaxpayerName", .source_line = 461, .event = .blur, .attribute = "return capital(this, event)" },
    .{ .control_id = "frm1601c:txtAddress", .source_line = 494, .event = .blur, .attribute = "return capital(this, event)" },
    .{ .control_id = "frm1601c:txtAddress2", .source_line = 508, .event = .blur, .attribute = "return capital(this, event)" },
    .{ .control_id = "frm1601c:txtZipCode", .source_line = 522, .event = .key_press, .attribute = "return wholenumber(this, event)" },
    .{ .control_id = "frm1601c:txtTelNum", .source_line = 542, .event = .key_press, .attribute = "return wholenumber(this, event)" },
    .{ .control_id = "frm1601c:CatAgent_P", .source_line = 561, .event = .click, .attribute = "" },
    .{ .control_id = "frm1601c:CatAgent_G", .source_line = 562, .event = .click, .attribute = "" },
    .{ .control_id = "frm1601c:SpecialTax_1", .source_line = 608, .event = .click, .attribute = "enableSelTreaty()" },
    .{ .control_id = "frm1601c:SpecialTax_2", .source_line = 609, .event = .click, .attribute = "disableSelTreaty()" },
    .{ .control_id = "frm1601c:txtTax14", .source_line = 667, .event = .blur, .attribute = "round(this,2);computeTxt22();" },
    .{ .control_id = "frm1601c:txtTax14", .source_line = 667, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax15", .source_line = 689, .event = .blur, .attribute = "round(this,2);computeTxt21();" },
    .{ .control_id = "frm1601c:txtTax15", .source_line = 689, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax16", .source_line = 702, .event = .blur, .attribute = "round(this,2);computeTxt21();" },
    .{ .control_id = "frm1601c:txtTax16", .source_line = 702, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax17", .source_line = 715, .event = .blur, .attribute = "round(this,2);computeTxt21();" },
    .{ .control_id = "frm1601c:txtTax17", .source_line = 715, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax18", .source_line = 728, .event = .blur, .attribute = "round(this,2);computeTxt21();" },
    .{ .control_id = "frm1601c:txtTax18", .source_line = 728, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax19", .source_line = 741, .event = .blur, .attribute = "round(this,2);computeTxt21();" },
    .{ .control_id = "frm1601c:txtTax19", .source_line = 741, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax20", .source_line = 755, .event = .blur, .attribute = "round(this,2);computeTxt21();" },
    .{ .control_id = "frm1601c:txtTax20", .source_line = 755, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax23", .source_line = 794, .event = .blur, .attribute = "round(this,2);computeTxt24();" },
    .{ .control_id = "frm1601c:txtTax23", .source_line = 794, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax25", .source_line = 820, .event = .blur, .attribute = "round(this,2);computeTxt27();" },
    .{ .control_id = "frm1601c:txtTax25", .source_line = 820, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax28", .source_line = 859, .event = .blur, .attribute = "round(this,2);computeTxt30();" },
    .{ .control_id = "frm1601c:txtTax28", .source_line = 859, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax29", .source_line = 873, .event = .blur, .attribute = "round(this,2);computeTxt30();" },
    .{ .control_id = "frm1601c:txtTax29", .source_line = 873, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax32", .source_line = 921, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax32", .source_line = 921, .event = .blur, .attribute = "round(this,2);computePenalties()" },
    .{ .control_id = "frm1601c:txtTax33", .source_line = 941, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax33", .source_line = 941, .event = .blur, .attribute = "round(this,2);computePenalties()" },
    .{ .control_id = "frm1601c:txtTax34", .source_line = 961, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtTax34", .source_line = 961, .event = .blur, .attribute = "round(this,2);computePenalties()" },
    .{ .control_id = "txtDateIssue", .source_line = 1055, .event = .key_press, .attribute = "return dateOnly(event, false);" },
    .{ .control_id = "txtDateIssue", .source_line = 1055, .event = .key_down, .attribute = "dateMasking(this);" },
    .{ .control_id = "txtDateIssue", .source_line = 1055, .event = .blur, .attribute = "validateDate(this);" },
    .{ .control_id = "txtDateExpiry", .source_line = 1068, .event = .key_press, .attribute = "return dateOnly(event, false);" },
    .{ .control_id = "txtDateExpiry", .source_line = 1068, .event = .key_down, .attribute = "dateMasking(this);" },
    .{ .control_id = "txtDateExpiry", .source_line = 1068, .event = .blur, .attribute = "validateDate(this);" },
    .{ .control_id = "frm1601c:txtDate37", .source_line = 1112, .event = .key_press, .attribute = "return dateOnly(event, false);" },
    .{ .control_id = "frm1601c:txtDate37", .source_line = 1112, .event = .key_down, .attribute = "dateMasking(this);" },
    .{ .control_id = "frm1601c:txtDate37", .source_line = 1112, .event = .blur, .attribute = "validateDate(this);" },
    .{ .control_id = "frm1601c:txtAmount37", .source_line = 1113, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtAmount37", .source_line = 1113, .event = .blur, .attribute = "round(this,2);" },
    .{ .control_id = "frm1601c:txtDate38", .source_line = 1119, .event = .key_press, .attribute = "return dateOnly(event, false);" },
    .{ .control_id = "frm1601c:txtDate38", .source_line = 1119, .event = .key_down, .attribute = "dateMasking(this);" },
    .{ .control_id = "frm1601c:txtDate38", .source_line = 1119, .event = .blur, .attribute = "validateDate(this);" },
    .{ .control_id = "frm1601c:txtAmount38", .source_line = 1120, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtAmount38", .source_line = 1120, .event = .blur, .attribute = "round(this,2);" },
    .{ .control_id = "frm1601c:txtDate39", .source_line = 1125, .event = .key_press, .attribute = "return dateOnly(event, false);" },
    .{ .control_id = "frm1601c:txtDate39", .source_line = 1125, .event = .key_down, .attribute = "dateMasking(this);" },
    .{ .control_id = "frm1601c:txtDate39", .source_line = 1125, .event = .blur, .attribute = "validateDate(this);" },
    .{ .control_id = "frm1601c:txtAmount39", .source_line = 1126, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtAmount39", .source_line = 1126, .event = .blur, .attribute = "round(this,2);" },
    .{ .control_id = "frm1601c:txtDate40", .source_line = 1135, .event = .key_press, .attribute = "return dateOnly(event, false);" },
    .{ .control_id = "frm1601c:txtDate40", .source_line = 1135, .event = .key_down, .attribute = "dateMasking(this);" },
    .{ .control_id = "frm1601c:txtDate40", .source_line = 1135, .event = .blur, .attribute = "validateDate(this);" },
    .{ .control_id = "frm1601c:txtAmount40", .source_line = 1136, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:txtAmount40", .source_line = 1136, .event = .blur, .attribute = "round(this,2);" },
    .{ .control_id = "frm1601c:txtPg2TIN1", .source_line = 1200, .event = .key_press, .attribute = "return wholenumber(this, event)" },
    .{ .control_id = "frm1601c:txtPg2TIN2", .source_line = 1201, .event = .key_press, .attribute = "return wholenumber(this, event)" },
    .{ .control_id = "frm1601c:txtPg2TIN3", .source_line = 1202, .event = .key_press, .attribute = "return wholenumber(this, event)" },
    .{ .control_id = "frm1601c:txtPg2BranchCode", .source_line = 1203, .event = .key_press, .attribute = "return letternumber(event)" },
    .{ .control_id = "frm1601c:txtPg2TaxpayerName", .source_line = 1206, .event = .blur, .attribute = "return capital(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtMonthYear0", .source_line = 1249, .event = .key_press, .attribute = "return dateOnly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtMonthYear0", .source_line = 1249, .event = .key_down, .attribute = "dateMaskingMonthYear(this);" },
    .{ .control_id = "frm1601c:sched1:txtMonthYear0", .source_line = 1249, .event = .blur, .attribute = "validateMonthYear(this);" },
    .{ .control_id = "frm1601c:sched1:txtDatePaid0", .source_line = 1250, .event = .key_press, .attribute = "return dateOnly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtDatePaid0", .source_line = 1250, .event = .key_down, .attribute = "dateMasking(this);" },
    .{ .control_id = "frm1601c:sched1:txtDatePaid0", .source_line = 1250, .event = .blur, .attribute = "validateDate(this);" },
    .{ .control_id = "frm1601c:sched1:txtBankCode0", .source_line = 1251, .event = .key_press, .attribute = "return letternumber(event)" },
    .{ .control_id = "frm1601c:sched1:txtNumber0", .source_line = 1252, .event = .key_press, .attribute = "return letternumber(event)" },
    .{ .control_id = "frm1601c:sched1:txtTaxPaid0", .source_line = 1253, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtTaxPaid0", .source_line = 1253, .event = .blur, .attribute = "round(this,2);computeSchedule1();" },
    .{ .control_id = "frm1601c:sched1:txtMonthYear1", .source_line = 1257, .event = .key_press, .attribute = "return dateOnly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtMonthYear1", .source_line = 1257, .event = .key_down, .attribute = "dateMaskingMonthYear(this);" },
    .{ .control_id = "frm1601c:sched1:txtMonthYear1", .source_line = 1257, .event = .blur, .attribute = "validateMonthYear(this);" },
    .{ .control_id = "frm1601c:sched1:txtDatePaid1", .source_line = 1258, .event = .key_press, .attribute = "return dateOnly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtDatePaid1", .source_line = 1258, .event = .key_down, .attribute = "dateMasking(this);" },
    .{ .control_id = "frm1601c:sched1:txtDatePaid1", .source_line = 1258, .event = .blur, .attribute = "validateDate(this);" },
    .{ .control_id = "frm1601c:sched1:txtBankCode1", .source_line = 1259, .event = .key_press, .attribute = "return letternumber(event)" },
    .{ .control_id = "frm1601c:sched1:txtNumber1", .source_line = 1260, .event = .key_press, .attribute = "return letternumber(event)" },
    .{ .control_id = "frm1601c:sched1:txtTaxPaid1", .source_line = 1261, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtTaxPaid1", .source_line = 1261, .event = .blur, .attribute = "round(this,2);computeSchedule1();" },
    .{ .control_id = "frm1601c:sched1:txtMonthYear2", .source_line = 1265, .event = .key_press, .attribute = "return dateOnly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtMonthYear2", .source_line = 1265, .event = .key_down, .attribute = "dateMaskingMonthYear(this);" },
    .{ .control_id = "frm1601c:sched1:txtMonthYear2", .source_line = 1265, .event = .blur, .attribute = "validateMonthYear(this);" },
    .{ .control_id = "frm1601c:sched1:txtDatePaid2", .source_line = 1266, .event = .key_press, .attribute = "return dateOnly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtDatePaid2", .source_line = 1266, .event = .key_down, .attribute = "dateMasking(this);" },
    .{ .control_id = "frm1601c:sched1:txtDatePaid2", .source_line = 1266, .event = .blur, .attribute = "validateDate(this);" },
    .{ .control_id = "frm1601c:sched1:txtBankCode2", .source_line = 1267, .event = .key_press, .attribute = "return letternumber(event)" },
    .{ .control_id = "frm1601c:sched1:txtNumber2", .source_line = 1268, .event = .key_press, .attribute = "return letternumber(event)" },
    .{ .control_id = "frm1601c:sched1:txtTaxPaid2", .source_line = 1269, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtTaxPaid2", .source_line = 1269, .event = .blur, .attribute = "round(this,2);computeSchedule1();" },
    .{ .control_id = "frm1601c:sched1:txtShouldTaxDue0", .source_line = 1283, .event = .blur, .attribute = "round(this,2);computeSchedule1();" },
    .{ .control_id = "frm1601c:sched1:txtShouldTaxDue0", .source_line = 1283, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtShouldTaxDue1", .source_line = 1288, .event = .blur, .attribute = "round(this,2);computeSchedule1();" },
    .{ .control_id = "frm1601c:sched1:txtShouldTaxDue1", .source_line = 1288, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:sched1:txtShouldTaxDue2", .source_line = 1293, .event = .blur, .attribute = "round(this,2);computeSchedule1();" },
    .{ .control_id = "frm1601c:sched1:txtShouldTaxDue2", .source_line = 1293, .event = .key_press, .attribute = "return numbersonly(this, event)" },
    .{ .control_id = "frm1601c:btnAdd", .source_line = 1316, .event = .click, .attribute = "addSchedule()" },
    .{ .control_id = "frm1601c:btnDelete", .source_line = 1317, .event = .click, .attribute = "deleteSchedule()" },
    .{ .control_id = "frm1601c:btnPrevPage", .source_line = 1531, .event = .click, .attribute = "processPrev();" },
    .{ .control_id = "frm1601c:txtCurrentPage", .source_line = 1533, .event = .key_up, .attribute = "goToPage();" },
    .{ .control_id = "frm1601c:btnNextPage", .source_line = 1535, .event = .click, .attribute = "processNext();" },
    .{ .control_id = "frm1601c:btnValidate", .source_line = 1544, .event = .click, .attribute = "validate();" },
    .{ .control_id = "frm1601c:btnEdit", .source_line = 1545, .event = .click, .attribute = "enableAllControl()" },
    .{ .control_id = "btnSave", .source_line = 1548, .event = .click, .attribute = "saveXML(false);" },
    .{ .control_id = "btnPrint", .source_line = 1549, .event = .click, .attribute = "printme();" },
    .{ .control_id = "frm1601c:btnFinalCopy", .source_line = 1550, .event = .click, .attribute = "openAlertEmail();" },
    .{ .control_id = "frm1601c:txtLineBus", .source_line = 1567, .event = .blur, .attribute = "return capital(this, event)" },
    .{ .control_id = "btnOkImport", .source_line = 1586, .event = .click, .attribute = "importFiles()" },
    .{ .control_id = "btnCancelImport", .source_line = 1587, .event = .click, .attribute = "cancelImportModal()" },
    .{ .control_id = "txtFinalFlag", .source_line = 1593, .event = .blur, .attribute = "" },
    .{ .control_id = "txtFinalFlag", .source_line = 1593, .event = .key_press, .attribute = "" },
    .{ .control_id = "txtEnroll", .source_line = 1594, .event = .blur, .attribute = "" },
    .{ .control_id = "txtEnroll", .source_line = 1594, .event = .key_press, .attribute = "" },
    .{ .control_id = "ebirOnlineConfirmSubmit", .source_line = 1625, .event = .click, .attribute = "sendEmail(this);" },
    .{ .control_id = "ebirOnlineConfirmCancel", .source_line = 1628, .event = .click, .attribute = "SetFinalFlagTo0();HideContainer('ebirConfirmOnline'); ShowContainer('container');" },
    .{ .control_id = "ebirEnrollYes", .source_line = 1650, .event = .click, .attribute = "sendEmail(this); HideContainer('ebirEnroll');" },
    .{ .control_id = "ebirEnrollNo", .source_line = 1653, .event = .click, .attribute = "SetFinalFlagTo0();HideContainer('ebirEnroll'); ShowContainer('container');" },
    .{ .control_id = "isregistered", .source_line = 1671, .event = .click, .attribute = "HideContainer('isRegister'); ShowContainer('ebirOnline')" },
    .{ .control_id = "notregistered", .source_line = 1674, .event = .click, .attribute = "HideContainer('isRegister');ShowContainer('ebirEnroll');" },
    .{ .control_id = "ebirOnlineSubmit", .source_line = 1712, .event = .click, .attribute = "ValidateUserPass();" },
    .{ .control_id = "ebirOnlineCancel", .source_line = 1715, .event = .click, .attribute = "SetFinalFlagTo0();HideContainer('ebirOnline'); ShowContainer('container');" },
    .{ .control_id = "btnOkExport", .source_line = 1750, .event = .click, .attribute = "exportTPFiles(fileNameToExport); checkFinalCopyBtn('1601Cv2018');" },
    .{ .control_id = "btnCancelExport", .source_line = 1751, .event = .click, .attribute = "cancelExportModal(); checkFinalCopyBtn('1601Cv2018');" },
};

pub const observed_binding_count: usize = 144;
pub const empty_attribute_count: usize = 6;

pub const bound_control_count: usize = 93;

pub fn bindingsFor(control_id: []const u8) usize {
    var total: usize = 0;
    for (bindings) |binding| {
        const id = binding.control_id orelse continue;
        if (std.mem.eql(u8, id, control_id)) total += 1;
    }
    return total;
}

pub fn countEvent(event: EventKind) usize {
    var total: usize = 0;
    for (bindings) |binding| {
        if (binding.event == event) total += 1;
    }
    return total;
}

test "1601C event inventory is declarative and implements nothing" {
    try std.testing.expectEqual(@as(usize, 144), observed_binding_count);
    try std.testing.expectEqual(observed_binding_count, bindings.len);
    try std.testing.expect(!handlers_implemented);
    try std.testing.expect(evidence.readiness.dependency_closure);
}

test "1601C every binding sits on a control the inventory carries" {
    var bound: usize = 0;
    var previous_line: u32 = 0;
    for (bindings) |binding| {
        try std.testing.expect(binding.source_line >= previous_line);
        previous_line = binding.source_line;
        const id = binding.control_id orelse continue;
        bound += 1;
        const seed = occurrences.find(id) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(seed.source_line, binding.source_line);
    }
    try std.testing.expect(bound > 0);
}

test "1601C bindings are spread across the declared event kinds" {
    try std.testing.expectEqual(@as(usize, 30), countEvent(.click));
    try std.testing.expectEqual(@as(usize, 56), countEvent(.key_press));
    try std.testing.expectEqual(@as(usize, 44), countEvent(.blur));
    try std.testing.expectEqual(@as(usize, 12), countEvent(.key_down));
    try std.testing.expectEqual(@as(usize, 1), countEvent(.change));
    try std.testing.expectEqual(@as(usize, 1), countEvent(.key_up));

    var total: usize = 0;
    inline for (std.meta.tags(EventKind)) |kind| total += countEvent(kind);
    try std.testing.expectEqual(observed_binding_count, total);
}

test "1601C changing the withholding agent category does nothing" {
    // Both category radios declare an empty onclick, where the comparable
    // 1601EQ control calls changeCategory and clears the computation.
    for ([_][]const u8{ "frm1601c:CatAgent_P", "frm1601c:CatAgent_G" }) |id| {
        try std.testing.expectEqual(@as(usize, 1), bindingsFor(id));
        var found = false;
        for (bindings) |binding| {
            const bound_id = binding.control_id orelse continue;
            if (!std.mem.eql(u8, bound_id, id)) continue;
            found = true;
            try std.testing.expectEqual(EventKind.click, binding.event);
            try std.testing.expectEqual(@as(usize, 0), binding.attribute.len);
        }
        try std.testing.expect(found);
    }
}

test "1601C six bindings declare an empty attribute" {
    var empty: usize = 0;
    for (bindings) |binding| {
        if (binding.attribute.len == 0) empty += 1;
    }
    try std.testing.expectEqual(empty_attribute_count, empty);
    try std.testing.expectEqual(@as(usize, 6), empty);
    // Two are the category radios; the rest sit on these two controls.
    try std.testing.expectEqual(@as(usize, 2), bindingsFor("txtFinalFlag"));
    try std.testing.expectEqual(@as(usize, 2), bindingsFor("txtEnroll"));
}
