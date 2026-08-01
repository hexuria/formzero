//! Exact, value-free HTML control declarations for the 173 serializer-eligible
//! controls in Offline eBIRForms 7.9.6 Form 1701Q January 2018 (ENCS).
//!
//! These are declaration facts from the verified HTA identified by
//! `evidence.primary_source`: source line, kind, `maxlength`, declared/default
//! value, markup-disabled state, and radio name/value/checked attributes.
//! They do not claim that script-driven runtime state is unchanged from the
//! declaration. In particular, UI initialization and blur/click mutations are
//! modeled separately and must cite their own evidence.

const std = @import("std");
const occurrences = @import("occurrences.zig");

pub const evidence_id = "desktop-7.9.6-1701qv2018-hta";

pub const RadioDeclaration = struct {
    name: []const u8,
    value: []const u8,
    checked: bool,
};

pub const Contract = struct {
    id: []const u8,
    source_line: u32,
    kind: occurrences.ControlKind,
    max_length: ?u16,
    declared_value: []const u8,
    disabled_in_markup: bool,
    radio_declaration: ?RadioDeclaration,
};

fn text(
    comptime id: []const u8,
    comptime source_line: u32,
    comptime max_length: ?u16,
    comptime declared_value: []const u8,
    comptime disabled: bool,
) Contract {
    return .{
        .id = id,
        .source_line = source_line,
        .kind = .text,
        .max_length = max_length,
        .declared_value = declared_value,
        .disabled_in_markup = disabled,
        .radio_declaration = null,
    };
}

fn radio(
    comptime id: []const u8,
    comptime source_line: u32,
    comptime name: []const u8,
    comptime value: []const u8,
    comptime disabled: bool,
    comptime checked: bool,
) Contract {
    return .{
        .id = id,
        .source_line = source_line,
        .kind = .radio,
        .max_length = null,
        .declared_value = value,
        .disabled_in_markup = disabled,
        .radio_declaration = .{
            .name = name,
            .value = value,
            .checked = checked,
        },
    };
}

fn select(
    comptime id: []const u8,
    comptime source_line: u32,
    comptime declared_value: []const u8,
    comptime disabled: bool,
) Contract {
    return .{
        .id = id,
        .source_line = source_line,
        .kind = .select_one,
        .max_length = null,
        .declared_value = declared_value,
        .disabled_in_markup = disabled,
        .radio_declaration = null,
    };
}

/// Same order as `occurrences.control_seeds`, which is live
/// `frmMain.elements` order after the two RDO selects are injected.
pub const contracts = [_]Contract{
    text("frm1701q:txtYear", 271, 4, "", false),
    radio("frm1701q:DateQuarter_1", 286, "frm1701q:DateQuarter", "1", false, false),
    radio("frm1701q:DateQuarter_2", 289, "frm1701q:DateQuarter", "2", false, false),
    radio("frm1701q:DateQuarter_3", 292, "frm1701q:DateQuarter", "3", false, false),
    radio("frm1701q:AmendedRtn_1", 312, "frm1701q:AmendedRtn", "Y", true, false),
    radio("frm1701q:AmendedRtn_2", 315, "frm1701q:AmendedRtn", "N", true, true),
    text("frm1701q:txtSheets", 330, 2, "0", false),
    text("frm1701q:txtTIN1", 370, 3, "", false),
    text("frm1701q:txtTIN2", 371, 3, "", false),
    text("frm1701q:txtTIN3", 372, 3, "", false),
    text("frm1701q:txtBranchCode", 373, 3, "", false),
    select("frm1701q:txtRDOCode", 3708, "000", true),
    radio("frm1701q:optType_1", 408, "frm1701q:optTaxpayerType", "Single", false, false),
    radio("frm1701q:optType_2", 411, "frm1701q:optTaxpayerType", "Professional", false, false),
    radio("frm1701q:optType_3", 414, "frm1701q:optTaxpayerType", "Estate", false, false),
    radio("frm1701q:optType_4", 417, "frm1701q:optTaxpayerType", "Trust", false, false),
    radio("frm1701q:optATC_1", 441, "frm1701q:optATC", "II012", false, false),
    radio("frm1701q:optATC_2", 444, "frm1701q:optATC", "II014", false, false),
    radio("frm1701q:optATC_3", 447, "frm1701q:optATC", "II013", false, false),
    radio("frm1701q:optATC_4", 454, "frm1701q:optATC", "II015", false, false),
    radio("frm1701q:optATC_5", 457, "frm1701q:optATC", "II017", false, false),
    radio("frm1701q:optATC_6", 460, "frm1701q:optATC", "II016", false, false),
    text("frm1701q:txtTaxpayerName", 482, 50, "", true),
    text("frm1701q:txtAddress", 511, 100, "", true),
    text("frm1701q:txtAddress2", 525, 50, "", true),
    text("frm1701q:txtZipCode", 539, 4, "", true),
    text("frm1701q:txtBirthMonth", 563, 2, "", false),
    text("frm1701q:txtBirthDay", 564, 2, "", false),
    text("frm1701q:txtBirthYear", 565, 4, "", false),
    text("txtEmail", 580, 60, "", true),
    text("frm1701q:txtCitizenship", 602, 20, "", false),
    text("frm1701q:txtForeignTaxNumber", 616, 20, "", false),
    radio("frm1701q:optForeignTaxCredits_1", 633, "frm1701q:optForeignTaxCredits", "Y", false, false),
    radio("frm1701q:optForeignTaxCredits_2", 636, "frm1701q:optForeignTaxCredits", "N", false, false),
    radio("frm1701q:optTaxRate_1", 665, "frm1701q:optTaxRate", "Graduated", false, false),
    radio("frm1701q:optMethodOfDeduction:_1", 677, "frm1701q:optMethodOfDeduction", "I", false, false),
    radio("frm1701q:optMethodOfDeduction:_2", 681, "frm1701q:optMethodOfDeduction", "O", false, false),
    radio("frm1701q:optTaxRate_2", 693, "frm1701q:optTaxRate", "Percentage", false, false),
    text("frm1701q:txtSpouseTIN1", 734, 3, "", false),
    text("frm1701q:txtSpouseTIN2", 735, 3, "", false),
    text("frm1701q:txtSpouseTIN3", 736, 3, "", false),
    text("frm1701q:txtSpouseBranchCode", 737, 5, "", false),
    select("frm1701q:txtSpouseRDOCode", 3709, "000", false),
    radio("frm1701q:optSpouseType_1", 772, "frm1701q:optSpouseType_1", "Single", false, false),
    radio("frm1701q:optSpouseType_2", 775, "frm1701q:optSpouseType_2", "Professional", false, false),
    radio("frm1701q:optSpouseType_3", 778, "frm1701q:optSpouseType_3", "Compensation", false, false),
    radio("frm1701q:optSpouseATC_1", 802, "frm1701q:optSpouseATC", "II012", false, false),
    radio("frm1701q:optSpouseATC_2", 805, "frm1701q:optSpouseATC", "II014", false, false),
    radio("frm1701q:optSpouseATC_3", 808, "frm1701q:optSpouseATC", "II013", false, false),
    radio("frm1701q:optSpouseATC_4", 811, "frm1701q:optSpouseATC", "II011", false, false),
    radio("frm1701q:optSpouseATC_5", 818, "frm1701q:optSpouseATC", "II015", false, false),
    radio("frm1701q:optSpouseATC_6", 821, "frm1701q:optSpouseATC", "II017", false, false),
    radio("frm1701q:optSpouseATC_7", 824, "frm1701q:optSpouseATC", "II016", false, false),
    text("frm1701q:txtSpouseName", 846, 50, "", false),
    text("frm1701q:txtSpouseCitizenship", 867, 20, "", false),
    text("frm1701q:txtSpouseForeignTaxNum", 881, 20, "", false),
    radio("frm1701q:optSpouseForeignTaxCred_1", 898, "frm1701q:optSpouseForeignTaxCred", "Y", false, false),
    radio("frm1701q:optSpouseForeignTaxCred_2", 901, "frm1701q:optSpouseForeignTaxCred", "N", false, false),
    radio("frm1701q:optSpouseTaxRate_1", 930, "frm1701q:optSpouseTaxRate", "Graduated", false, false),
    radio("frm1701q:optSpouseMethod:_1", 942, "frm1701q:optSpouseMethod", "I", false, false),
    radio("frm1701q:optSpouseMethod:_2", 946, "frm1701q:optSpouseMethod", "O", false, false),
    radio("frm1701q:optSpouseTaxRate_2", 958, "frm1701q:optSpouseTaxRate", "Percentage", false, false),
    text("frm1701q:txt26A", 1002, 25, "0.00", true),
    text("frm1701q:txt26B", 1006, 25, "0.00", true),
    text("frm1701q:txt27A", 1013, 25, "0.00", true),
    text("frm1701q:txt27B", 1016, 25, "0.00", true),
    text("frm1701q:txt28A", 1023, 25, "0.00", true),
    text("frm1701q:txt28B", 1026, 25, "0.00", true),
    text("frm1701q:txt29A", 1033, 25, "0.00", true),
    text("frm1701q:txt29B", 1036, 25, "0.00", true),
    text("frm1701q:txt30A", 1043, 25, "0.00", true),
    text("frm1701q:txt30B", 1046, 25, "0.00", true),
    text("frm1701q:txt31", 1053, 25, "0.00", true),
    text("frm1701q:txtAgency32", 1116, 50, "", true),
    text("frm1701q:txtNumber32", 1117, 50, "", true),
    text("frm1701q:txtDate32", 1118, 10, "", true),
    text("frm1701q:txtAmount32", 1119, 50, "", true),
    text("frm1701q:txtAgency33", 1123, 50, "", true),
    text("frm1701q:txtNumber33", 1124, 50, "", true),
    text("frm1701q:txtDate33", 1125, 10, "", true),
    text("frm1701q:txtAmount33", 1126, 50, "", true),
    text("frm1701q:txtNumber34", 1130, 50, "", true),
    text("frm1701q:txtDate34", 1131, 10, "", true),
    text("frm1701q:txtAmount34", 1132, 50, "", true),
    text("frm1701q:txtParticular35", 1138, 50, "", true),
    text("frm1701q:txtAgency35", 1139, 50, "", true),
    text("frm1701q:txtNumber35", 1140, 50, "", true),
    text("frm1701q:txtDate35", 1141, 10, "", true),
    text("frm1701q:txtAmount35", 1142, 50, "", true),
    text("frm1701q:txtPg2TIN1", 1220, 3, "", true),
    text("frm1701q:txtPg2TIN2", 1221, 3, "", true),
    text("frm1701q:txtPg2TIN3", 1222, 3, "", true),
    text("frm1701q:txtPg2BranchCode", 1223, 5, "", true),
    text("frm1701q:txtPg2TaxpayerName", 1226, 50, "", true),
    text("frm1701q:txt36A", 1277, 25, "0.00", true),
    text("frm1701q:txt36B", 1281, 25, "0.00", true),
    text("frm1701q:txt37A", 1288, 25, "0.00", true),
    text("frm1701q:txt37B", 1291, 25, "0.00", true),
    text("frm1701q:txt38A", 1298, 25, "0.00", true),
    text("frm1701q:txt38B", 1301, 25, "0.00", true),
    text("frm1701q:txt39A", 1312, 25, "0.00", true),
    text("frm1701q:txt39B", 1315, 25, "0.00", true),
    text("frm1701q:txt40A", 1330, 25, "0.00", true),
    text("frm1701q:txt40B", 1333, 25, "0.00", true),
    text("frm1701q:txt41A", 1340, 25, "0.00", true),
    text("frm1701q:txt41B", 1343, 25, "0.00", true),
    text("frm1701q:txt42A", 1350, 25, "0.00", true),
    text("frm1701q:txt42B", 1353, 25, "0.00", true),
    text("frm1701q:txt43Desc", 1363, 25, "", true),
    text("frm1701q:txt43A", 1369, 25, "0.00", true),
    text("frm1701q:txt43B", 1372, 25, "0.00", true),
    text("frm1701q:txt44A", 1386, 25, "0.00", true),
    text("frm1701q:txt44B", 1389, 25, "0.00", true),
    text("frm1701q:txt45A", 1396, 25, "0.00", true),
    text("frm1701q:txt45B", 1399, 25, "0.00", true),
    text("frm1701q:txt46A", 1406, 25, "0.00", true),
    text("frm1701q:txt46B", 1409, 25, "0.00", true),
    text("frm1701q:txt47A", 1421, 25, "0.00", true),
    text("frm1701q:txt47B", 1425, 25, "0.00", true),
    text("frm1701q:txt48Desc", 1431, 25, "", true),
    text("frm1701q:txt48A", 1434, 25, "0.00", true),
    text("frm1701q:txt48B", 1437, 25, "0.00", true),
    text("frm1701q:txt49A", 1444, 25, "0.00", true),
    text("frm1701q:txt49B", 1447, 25, "0.00", true),
    text("frm1701q:txt50A", 1454, 25, "0.00", true),
    text("frm1701q:txt50B", 1458, 25, "0.00", true),
    text("frm1701q:txt51A", 1465, 25, "0.00", true),
    text("frm1701q:txt51B", 1468, 25, "0.00", true),
    text("frm1701q:txt52A", 1482, 25, "0.00", true),
    text("frm1701q:txt52B", 1486, 25, "0.00", true),
    text("frm1701q:txt53A", 1493, 25, "0.00", true),
    text("frm1701q:txt53B", 1496, 25, "0.00", true),
    text("frm1701q:txt54A", 1503, 25, "0.00", true),
    text("frm1701q:txt54B", 1506, 25, "0.00", true),
    text("frm1701q:txt55A", 1518, 25, "0.00", false),
    text("frm1701q:txt55B", 1522, 25, "0.00", false),
    text("frm1701q:txt56A", 1529, 25, "0.00", false),
    text("frm1701q:txt56B", 1533, 25, "0.00", false),
    text("frm1701q:txt57A", 1540, 25, "0.00", false),
    text("frm1701q:txt57B", 1544, 25, "0.00", false),
    text("frm1701q:txt58A", 1551, 25, "0.00", false),
    text("frm1701q:txt58B", 1555, 25, "0.00", false),
    text("frm1701q:txt59A", 1562, 25, "0.00", false),
    text("frm1701q:txt59B", 1566, 25, "0.00", false),
    text("frm1701q:txt60A", 1573, 25, "0.00", false),
    text("frm1701q:txt60B", 1577, 25, "0.00", false),
    text("frm1701q:txt61Desc", 1582, 25, "", false),
    text("frm1701q:txt61A", 1584, 25, "0.00", false),
    text("frm1701q:txt61B", 1588, 25, "0.00", false),
    text("frm1701q:txt62A", 1595, 25, "0.00", true),
    text("frm1701q:txt62B", 1598, 25, "0.00", true),
    text("frm1701q:txt63A", 1608, 25, "0.00", true),
    text("frm1701q:txt63B", 1611, 25, "0.00", true),
    text("frm1701q:txt64A", 1626, 25, "0.00", false),
    text("frm1701q:txt64B", 1630, 25, "0.00", false),
    text("frm1701q:txt65A", 1637, 25, "0.00", false),
    text("frm1701q:txt65B", 1641, 25, "0.00", false),
    text("frm1701q:txt66A", 1648, 25, "0.00", false),
    text("frm1701q:txt66B", 1652, 25, "0.00", false),
    text("frm1701q:txt67A", 1659, 25, "0.00", true),
    text("frm1701q:txt67B", 1662, 25, "0.00", true),
    text("frm1701q:txt68A", 1672, 25, "0.00", true),
    text("frm1701q:txt68B", 1675, 25, "0.00", true),
    text("frm1701q:txtCurrentPage", 1780, null, "", false),
    text("frm1701q:txtMaxPage", 1781, null, "2", true),
    text("txtFinalFlag", 1837, 60, "0", false),
    text("txtEnroll", 1838, 60, "N", false),
    text("ebirOnlineConfirmUsername", 1855, 50, "", false),
    text("ebirOnlineUsername", 1942, 50, "", false),
    text("ebirOnlineSecret", 1951, 50, "", false),
    text("frm1701q:txtLOB", 1967, 50, "", false),
    text("frm1701q:txtTelno", 1968, 7, "", false),
    select("driveSelectTPExport", 1990, "", false),
};

pub fn find(id: []const u8) ?*const Contract {
    for (&contracts) |*contract| {
        if (std.mem.eql(u8, contract.id, id)) return contract;
    }
    return null;
}

test "control declarations cover all 173 eligible controls in exact order" {
    try std.testing.expectEqual(occurrences.control_seeds.len, contracts.len);

    var text_count: usize = 0;
    var radio_count: usize = 0;
    var select_count: usize = 0;
    var disabled_count: usize = 0;
    for (contracts, occurrences.control_seeds) |contract, seed| {
        try std.testing.expectEqualStrings(seed.id, contract.id);
        try std.testing.expectEqual(seed.source_line, contract.source_line);
        try std.testing.expectEqual(seed.kind, contract.kind);
        if (contract.disabled_in_markup) disabled_count += 1;
        switch (contract.kind) {
            .text => {
                text_count += 1;
                try std.testing.expect(contract.radio_declaration == null);
            },
            .radio => {
                radio_count += 1;
                const declaration = contract.radio_declaration orelse
                    return error.MissingRadioDeclaration;
                try std.testing.expectEqualStrings(
                    contract.declared_value,
                    declaration.value,
                );
                try std.testing.expect(contract.max_length == null);
            },
            .select_one => {
                select_count += 1;
                try std.testing.expect(contract.radio_declaration == null);
                try std.testing.expect(contract.max_length == null);
            },
        }
    }

    try std.testing.expectEqual(@as(usize, 133), text_count);
    try std.testing.expectEqual(@as(usize, 37), radio_count);
    try std.testing.expectEqual(@as(usize, 3), select_count);
    try std.testing.expectEqual(@as(usize, 89), disabled_count);
}

test "text maxlength and declaration defaults match the verified HTA" {
    const LengthCount = struct { length: ?u16, count: usize };
    const expected_lengths = [_]LengthCount{
        .{ .length = null, .count = 2 },
        .{ .length = 2, .count = 3 },
        .{ .length = 3, .count = 10 },
        .{ .length = 4, .count = 3 },
        .{ .length = 5, .count = 2 },
        .{ .length = 7, .count = 1 },
        .{ .length = 10, .count = 4 },
        .{ .length = 20, .count = 4 },
        .{ .length = 25, .count = 80 },
        .{ .length = 50, .count = 20 },
        .{ .length = 60, .count = 3 },
        .{ .length = 100, .count = 1 },
    };
    for (expected_lengths) |expected| {
        var count: usize = 0;
        for (contracts) |contract| {
            if (contract.kind == .text and
                contract.max_length == expected.length)
            {
                count += 1;
            }
        }
        try std.testing.expectEqual(expected.count, count);
    }

    var empty_count: usize = 0;
    var money_zero_count: usize = 0;
    for (contracts) |contract| {
        if (contract.kind != .text) continue;
        if (contract.declared_value.len == 0) empty_count += 1;
        if (std.mem.eql(u8, contract.declared_value, "0.00")) {
            money_zero_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 52), empty_count);
    try std.testing.expectEqual(@as(usize, 77), money_zero_count);
    try std.testing.expectEqualStrings(
        "0",
        find("frm1701q:txtSheets").?.declared_value,
    );
    try std.testing.expectEqualStrings(
        "2",
        find("frm1701q:txtMaxPage").?.declared_value,
    );
    try std.testing.expectEqualStrings(
        "0",
        find("txtFinalFlag").?.declared_value,
    );
    try std.testing.expectEqualStrings(
        "N",
        find("txtEnroll").?.declared_value,
    );
}

test "radio grouping preserves the spouse-type clearCheck quirk" {
    const amended_yes = find("frm1701q:AmendedRtn_1").?
        .radio_declaration.?;
    const amended_no = find("frm1701q:AmendedRtn_2").?
        .radio_declaration.?;
    try std.testing.expectEqualStrings(amended_yes.name, amended_no.name);
    try std.testing.expect(!amended_yes.checked);
    try std.testing.expect(amended_no.checked);

    const spouse_single = find("frm1701q:optSpouseType_1").?
        .radio_declaration.?;
    const spouse_professional = find("frm1701q:optSpouseType_2").?
        .radio_declaration.?;
    const spouse_compensation = find("frm1701q:optSpouseType_3").?
        .radio_declaration.?;
    try std.testing.expect(!std.mem.eql(
        u8,
        spouse_single.name,
        spouse_professional.name,
    ));
    try std.testing.expect(!std.mem.eql(
        u8,
        spouse_professional.name,
        spouse_compensation.name,
    ));
    try std.testing.expect(!std.mem.eql(
        u8,
        spouse_single.name,
        spouse_compensation.name,
    ));
}

test "runtime-created RDO selects retain declaration evidence" {
    const filer = find("frm1701q:txtRDOCode").?;
    const spouse = find("frm1701q:txtSpouseRDOCode").?;
    try std.testing.expectEqual(@as(u32, 3708), filer.source_line);
    try std.testing.expectEqual(@as(u32, 3709), spouse.source_line);
    try std.testing.expectEqualStrings("000", filer.declared_value);
    try std.testing.expectEqualStrings("000", spouse.declared_value);
    try std.testing.expect(filer.disabled_in_markup);
    try std.testing.expect(!spouse.disabled_in_markup);
}
