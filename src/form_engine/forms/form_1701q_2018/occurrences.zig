//! Ordered, value-free occurrence manifests derived from the verified
//! `frmMain.elements` traversal in the 7.9.6 1701Qv2018 HTA.
//!
//! These manifests record source control order and observed emission branches.
//! Canonical product-field and origin mappings remain explicitly unreviewed.
//! No payload value or byte serializer is implemented here.

const std = @import("std");
const occurrence = @import("../../occurrence.zig");

const evidence_id = "desktop-7.9.6-1701qv2018-hta";

pub const ControlKind = enum {
    text,
    radio,
    select_one,
};

pub const ControlSeed = struct {
    /// Static `frmMain.elements` ordinal before `getRdo()` runs. Runtime
    /// injected controls use zero and expose their exact live ordinal through
    /// `runtimeFormElementOrdinal()`.
    form_element_ordinal: u16,
    source_line: u32,
    kind: ControlKind,
    id: []const u8,

    pub fn runtimeFormElementOrdinal(self: ControlSeed) u16 {
        if (self.form_element_ordinal == 0) {
            if (std.mem.eql(u8, self.id, "frm1701q:txtRDOCode")) return 12;
            if (std.mem.eql(
                u8,
                self.id,
                "frm1701q:txtSpouseRDOCode",
            )) return 43;
            unreachable;
        }

        var ordinal = self.form_element_ordinal;
        if (self.form_element_ordinal >= 12) ordinal += 1;
        if (self.form_element_ordinal >= 42) ordinal += 1;
        return ordinal;
    }
};

/// Eligible controls in live `frmMain.elements` order. `getRdo()` inserts the
/// two select-one entries at their form placeholders before any load/save
/// action. Buttons, the one hidden input, and two password inputs are retained
/// in the 193-static-control inventory but excluded by the emission branches.
pub const control_seeds = [_]ControlSeed{
    .{ .form_element_ordinal = 1, .source_line = 271, .kind = .text, .id = "frm1701q:txtYear" },
    .{ .form_element_ordinal = 2, .source_line = 286, .kind = .radio, .id = "frm1701q:DateQuarter_1" },
    .{ .form_element_ordinal = 3, .source_line = 289, .kind = .radio, .id = "frm1701q:DateQuarter_2" },
    .{ .form_element_ordinal = 4, .source_line = 292, .kind = .radio, .id = "frm1701q:DateQuarter_3" },
    .{ .form_element_ordinal = 5, .source_line = 312, .kind = .radio, .id = "frm1701q:AmendedRtn_1" },
    .{ .form_element_ordinal = 6, .source_line = 315, .kind = .radio, .id = "frm1701q:AmendedRtn_2" },
    .{ .form_element_ordinal = 7, .source_line = 330, .kind = .text, .id = "frm1701q:txtSheets" },
    .{ .form_element_ordinal = 8, .source_line = 370, .kind = .text, .id = "frm1701q:txtTIN1" },
    .{ .form_element_ordinal = 9, .source_line = 371, .kind = .text, .id = "frm1701q:txtTIN2" },
    .{ .form_element_ordinal = 10, .source_line = 372, .kind = .text, .id = "frm1701q:txtTIN3" },
    .{ .form_element_ordinal = 11, .source_line = 373, .kind = .text, .id = "frm1701q:txtBranchCode" },
    .{ .form_element_ordinal = 0, .source_line = 3708, .kind = .select_one, .id = "frm1701q:txtRDOCode" },
    .{ .form_element_ordinal = 12, .source_line = 408, .kind = .radio, .id = "frm1701q:optType_1" },
    .{ .form_element_ordinal = 13, .source_line = 411, .kind = .radio, .id = "frm1701q:optType_2" },
    .{ .form_element_ordinal = 14, .source_line = 414, .kind = .radio, .id = "frm1701q:optType_3" },
    .{ .form_element_ordinal = 15, .source_line = 417, .kind = .radio, .id = "frm1701q:optType_4" },
    .{ .form_element_ordinal = 16, .source_line = 441, .kind = .radio, .id = "frm1701q:optATC_1" },
    .{ .form_element_ordinal = 17, .source_line = 444, .kind = .radio, .id = "frm1701q:optATC_2" },
    .{ .form_element_ordinal = 18, .source_line = 447, .kind = .radio, .id = "frm1701q:optATC_3" },
    .{ .form_element_ordinal = 19, .source_line = 454, .kind = .radio, .id = "frm1701q:optATC_4" },
    .{ .form_element_ordinal = 20, .source_line = 457, .kind = .radio, .id = "frm1701q:optATC_5" },
    .{ .form_element_ordinal = 21, .source_line = 460, .kind = .radio, .id = "frm1701q:optATC_6" },
    .{ .form_element_ordinal = 22, .source_line = 482, .kind = .text, .id = "frm1701q:txtTaxpayerName" },
    .{ .form_element_ordinal = 23, .source_line = 511, .kind = .text, .id = "frm1701q:txtAddress" },
    .{ .form_element_ordinal = 24, .source_line = 525, .kind = .text, .id = "frm1701q:txtAddress2" },
    .{ .form_element_ordinal = 25, .source_line = 539, .kind = .text, .id = "frm1701q:txtZipCode" },
    .{ .form_element_ordinal = 26, .source_line = 563, .kind = .text, .id = "frm1701q:txtBirthMonth" },
    .{ .form_element_ordinal = 27, .source_line = 564, .kind = .text, .id = "frm1701q:txtBirthDay" },
    .{ .form_element_ordinal = 28, .source_line = 565, .kind = .text, .id = "frm1701q:txtBirthYear" },
    .{ .form_element_ordinal = 29, .source_line = 580, .kind = .text, .id = "txtEmail" },
    .{ .form_element_ordinal = 30, .source_line = 602, .kind = .text, .id = "frm1701q:txtCitizenship" },
    .{ .form_element_ordinal = 31, .source_line = 616, .kind = .text, .id = "frm1701q:txtForeignTaxNumber" },
    .{ .form_element_ordinal = 32, .source_line = 633, .kind = .radio, .id = "frm1701q:optForeignTaxCredits_1" },
    .{ .form_element_ordinal = 33, .source_line = 636, .kind = .radio, .id = "frm1701q:optForeignTaxCredits_2" },
    .{ .form_element_ordinal = 34, .source_line = 665, .kind = .radio, .id = "frm1701q:optTaxRate_1" },
    .{ .form_element_ordinal = 35, .source_line = 677, .kind = .radio, .id = "frm1701q:optMethodOfDeduction:_1" },
    .{ .form_element_ordinal = 36, .source_line = 681, .kind = .radio, .id = "frm1701q:optMethodOfDeduction:_2" },
    .{ .form_element_ordinal = 37, .source_line = 693, .kind = .radio, .id = "frm1701q:optTaxRate_2" },
    .{ .form_element_ordinal = 38, .source_line = 734, .kind = .text, .id = "frm1701q:txtSpouseTIN1" },
    .{ .form_element_ordinal = 39, .source_line = 735, .kind = .text, .id = "frm1701q:txtSpouseTIN2" },
    .{ .form_element_ordinal = 40, .source_line = 736, .kind = .text, .id = "frm1701q:txtSpouseTIN3" },
    .{ .form_element_ordinal = 41, .source_line = 737, .kind = .text, .id = "frm1701q:txtSpouseBranchCode" },
    .{ .form_element_ordinal = 0, .source_line = 3709, .kind = .select_one, .id = "frm1701q:txtSpouseRDOCode" },
    .{ .form_element_ordinal = 42, .source_line = 772, .kind = .radio, .id = "frm1701q:optSpouseType_1" },
    .{ .form_element_ordinal = 43, .source_line = 775, .kind = .radio, .id = "frm1701q:optSpouseType_2" },
    .{ .form_element_ordinal = 44, .source_line = 778, .kind = .radio, .id = "frm1701q:optSpouseType_3" },
    .{ .form_element_ordinal = 45, .source_line = 802, .kind = .radio, .id = "frm1701q:optSpouseATC_1" },
    .{ .form_element_ordinal = 46, .source_line = 805, .kind = .radio, .id = "frm1701q:optSpouseATC_2" },
    .{ .form_element_ordinal = 47, .source_line = 808, .kind = .radio, .id = "frm1701q:optSpouseATC_3" },
    .{ .form_element_ordinal = 48, .source_line = 811, .kind = .radio, .id = "frm1701q:optSpouseATC_4" },
    .{ .form_element_ordinal = 49, .source_line = 818, .kind = .radio, .id = "frm1701q:optSpouseATC_5" },
    .{ .form_element_ordinal = 50, .source_line = 821, .kind = .radio, .id = "frm1701q:optSpouseATC_6" },
    .{ .form_element_ordinal = 51, .source_line = 824, .kind = .radio, .id = "frm1701q:optSpouseATC_7" },
    .{ .form_element_ordinal = 52, .source_line = 846, .kind = .text, .id = "frm1701q:txtSpouseName" },
    .{ .form_element_ordinal = 53, .source_line = 867, .kind = .text, .id = "frm1701q:txtSpouseCitizenship" },
    .{ .form_element_ordinal = 54, .source_line = 881, .kind = .text, .id = "frm1701q:txtSpouseForeignTaxNum" },
    .{ .form_element_ordinal = 55, .source_line = 898, .kind = .radio, .id = "frm1701q:optSpouseForeignTaxCred_1" },
    .{ .form_element_ordinal = 56, .source_line = 901, .kind = .radio, .id = "frm1701q:optSpouseForeignTaxCred_2" },
    .{ .form_element_ordinal = 57, .source_line = 930, .kind = .radio, .id = "frm1701q:optSpouseTaxRate_1" },
    .{ .form_element_ordinal = 58, .source_line = 942, .kind = .radio, .id = "frm1701q:optSpouseMethod:_1" },
    .{ .form_element_ordinal = 59, .source_line = 946, .kind = .radio, .id = "frm1701q:optSpouseMethod:_2" },
    .{ .form_element_ordinal = 60, .source_line = 958, .kind = .radio, .id = "frm1701q:optSpouseTaxRate_2" },
    .{ .form_element_ordinal = 61, .source_line = 1002, .kind = .text, .id = "frm1701q:txt26A" },
    .{ .form_element_ordinal = 62, .source_line = 1006, .kind = .text, .id = "frm1701q:txt26B" },
    .{ .form_element_ordinal = 63, .source_line = 1013, .kind = .text, .id = "frm1701q:txt27A" },
    .{ .form_element_ordinal = 64, .source_line = 1016, .kind = .text, .id = "frm1701q:txt27B" },
    .{ .form_element_ordinal = 65, .source_line = 1023, .kind = .text, .id = "frm1701q:txt28A" },
    .{ .form_element_ordinal = 66, .source_line = 1026, .kind = .text, .id = "frm1701q:txt28B" },
    .{ .form_element_ordinal = 67, .source_line = 1033, .kind = .text, .id = "frm1701q:txt29A" },
    .{ .form_element_ordinal = 68, .source_line = 1036, .kind = .text, .id = "frm1701q:txt29B" },
    .{ .form_element_ordinal = 69, .source_line = 1043, .kind = .text, .id = "frm1701q:txt30A" },
    .{ .form_element_ordinal = 70, .source_line = 1046, .kind = .text, .id = "frm1701q:txt30B" },
    .{ .form_element_ordinal = 71, .source_line = 1053, .kind = .text, .id = "frm1701q:txt31" },
    .{ .form_element_ordinal = 72, .source_line = 1116, .kind = .text, .id = "frm1701q:txtAgency32" },
    .{ .form_element_ordinal = 73, .source_line = 1117, .kind = .text, .id = "frm1701q:txtNumber32" },
    .{ .form_element_ordinal = 74, .source_line = 1118, .kind = .text, .id = "frm1701q:txtDate32" },
    .{ .form_element_ordinal = 75, .source_line = 1119, .kind = .text, .id = "frm1701q:txtAmount32" },
    .{ .form_element_ordinal = 76, .source_line = 1123, .kind = .text, .id = "frm1701q:txtAgency33" },
    .{ .form_element_ordinal = 77, .source_line = 1124, .kind = .text, .id = "frm1701q:txtNumber33" },
    .{ .form_element_ordinal = 78, .source_line = 1125, .kind = .text, .id = "frm1701q:txtDate33" },
    .{ .form_element_ordinal = 79, .source_line = 1126, .kind = .text, .id = "frm1701q:txtAmount33" },
    .{ .form_element_ordinal = 80, .source_line = 1130, .kind = .text, .id = "frm1701q:txtNumber34" },
    .{ .form_element_ordinal = 81, .source_line = 1131, .kind = .text, .id = "frm1701q:txtDate34" },
    .{ .form_element_ordinal = 82, .source_line = 1132, .kind = .text, .id = "frm1701q:txtAmount34" },
    .{ .form_element_ordinal = 83, .source_line = 1138, .kind = .text, .id = "frm1701q:txtParticular35" },
    .{ .form_element_ordinal = 84, .source_line = 1139, .kind = .text, .id = "frm1701q:txtAgency35" },
    .{ .form_element_ordinal = 85, .source_line = 1140, .kind = .text, .id = "frm1701q:txtNumber35" },
    .{ .form_element_ordinal = 86, .source_line = 1141, .kind = .text, .id = "frm1701q:txtDate35" },
    .{ .form_element_ordinal = 87, .source_line = 1142, .kind = .text, .id = "frm1701q:txtAmount35" },
    .{ .form_element_ordinal = 88, .source_line = 1220, .kind = .text, .id = "frm1701q:txtPg2TIN1" },
    .{ .form_element_ordinal = 89, .source_line = 1221, .kind = .text, .id = "frm1701q:txtPg2TIN2" },
    .{ .form_element_ordinal = 90, .source_line = 1222, .kind = .text, .id = "frm1701q:txtPg2TIN3" },
    .{ .form_element_ordinal = 91, .source_line = 1223, .kind = .text, .id = "frm1701q:txtPg2BranchCode" },
    .{ .form_element_ordinal = 92, .source_line = 1226, .kind = .text, .id = "frm1701q:txtPg2TaxpayerName" },
    .{ .form_element_ordinal = 93, .source_line = 1277, .kind = .text, .id = "frm1701q:txt36A" },
    .{ .form_element_ordinal = 94, .source_line = 1281, .kind = .text, .id = "frm1701q:txt36B" },
    .{ .form_element_ordinal = 95, .source_line = 1288, .kind = .text, .id = "frm1701q:txt37A" },
    .{ .form_element_ordinal = 96, .source_line = 1291, .kind = .text, .id = "frm1701q:txt37B" },
    .{ .form_element_ordinal = 97, .source_line = 1298, .kind = .text, .id = "frm1701q:txt38A" },
    .{ .form_element_ordinal = 98, .source_line = 1301, .kind = .text, .id = "frm1701q:txt38B" },
    .{ .form_element_ordinal = 99, .source_line = 1312, .kind = .text, .id = "frm1701q:txt39A" },
    .{ .form_element_ordinal = 100, .source_line = 1315, .kind = .text, .id = "frm1701q:txt39B" },
    .{ .form_element_ordinal = 101, .source_line = 1330, .kind = .text, .id = "frm1701q:txt40A" },
    .{ .form_element_ordinal = 102, .source_line = 1333, .kind = .text, .id = "frm1701q:txt40B" },
    .{ .form_element_ordinal = 103, .source_line = 1340, .kind = .text, .id = "frm1701q:txt41A" },
    .{ .form_element_ordinal = 104, .source_line = 1343, .kind = .text, .id = "frm1701q:txt41B" },
    .{ .form_element_ordinal = 105, .source_line = 1350, .kind = .text, .id = "frm1701q:txt42A" },
    .{ .form_element_ordinal = 106, .source_line = 1353, .kind = .text, .id = "frm1701q:txt42B" },
    .{ .form_element_ordinal = 107, .source_line = 1363, .kind = .text, .id = "frm1701q:txt43Desc" },
    .{ .form_element_ordinal = 108, .source_line = 1369, .kind = .text, .id = "frm1701q:txt43A" },
    .{ .form_element_ordinal = 109, .source_line = 1372, .kind = .text, .id = "frm1701q:txt43B" },
    .{ .form_element_ordinal = 110, .source_line = 1386, .kind = .text, .id = "frm1701q:txt44A" },
    .{ .form_element_ordinal = 111, .source_line = 1389, .kind = .text, .id = "frm1701q:txt44B" },
    .{ .form_element_ordinal = 112, .source_line = 1396, .kind = .text, .id = "frm1701q:txt45A" },
    .{ .form_element_ordinal = 113, .source_line = 1399, .kind = .text, .id = "frm1701q:txt45B" },
    .{ .form_element_ordinal = 114, .source_line = 1406, .kind = .text, .id = "frm1701q:txt46A" },
    .{ .form_element_ordinal = 115, .source_line = 1409, .kind = .text, .id = "frm1701q:txt46B" },
    .{ .form_element_ordinal = 116, .source_line = 1421, .kind = .text, .id = "frm1701q:txt47A" },
    .{ .form_element_ordinal = 117, .source_line = 1425, .kind = .text, .id = "frm1701q:txt47B" },
    .{ .form_element_ordinal = 118, .source_line = 1431, .kind = .text, .id = "frm1701q:txt48Desc" },
    .{ .form_element_ordinal = 119, .source_line = 1434, .kind = .text, .id = "frm1701q:txt48A" },
    .{ .form_element_ordinal = 120, .source_line = 1437, .kind = .text, .id = "frm1701q:txt48B" },
    .{ .form_element_ordinal = 121, .source_line = 1444, .kind = .text, .id = "frm1701q:txt49A" },
    .{ .form_element_ordinal = 122, .source_line = 1447, .kind = .text, .id = "frm1701q:txt49B" },
    .{ .form_element_ordinal = 123, .source_line = 1454, .kind = .text, .id = "frm1701q:txt50A" },
    .{ .form_element_ordinal = 124, .source_line = 1458, .kind = .text, .id = "frm1701q:txt50B" },
    .{ .form_element_ordinal = 125, .source_line = 1465, .kind = .text, .id = "frm1701q:txt51A" },
    .{ .form_element_ordinal = 126, .source_line = 1468, .kind = .text, .id = "frm1701q:txt51B" },
    .{ .form_element_ordinal = 127, .source_line = 1482, .kind = .text, .id = "frm1701q:txt52A" },
    .{ .form_element_ordinal = 128, .source_line = 1486, .kind = .text, .id = "frm1701q:txt52B" },
    .{ .form_element_ordinal = 129, .source_line = 1493, .kind = .text, .id = "frm1701q:txt53A" },
    .{ .form_element_ordinal = 130, .source_line = 1496, .kind = .text, .id = "frm1701q:txt53B" },
    .{ .form_element_ordinal = 131, .source_line = 1503, .kind = .text, .id = "frm1701q:txt54A" },
    .{ .form_element_ordinal = 132, .source_line = 1506, .kind = .text, .id = "frm1701q:txt54B" },
    .{ .form_element_ordinal = 133, .source_line = 1518, .kind = .text, .id = "frm1701q:txt55A" },
    .{ .form_element_ordinal = 134, .source_line = 1522, .kind = .text, .id = "frm1701q:txt55B" },
    .{ .form_element_ordinal = 135, .source_line = 1529, .kind = .text, .id = "frm1701q:txt56A" },
    .{ .form_element_ordinal = 136, .source_line = 1533, .kind = .text, .id = "frm1701q:txt56B" },
    .{ .form_element_ordinal = 137, .source_line = 1540, .kind = .text, .id = "frm1701q:txt57A" },
    .{ .form_element_ordinal = 138, .source_line = 1544, .kind = .text, .id = "frm1701q:txt57B" },
    .{ .form_element_ordinal = 139, .source_line = 1551, .kind = .text, .id = "frm1701q:txt58A" },
    .{ .form_element_ordinal = 140, .source_line = 1555, .kind = .text, .id = "frm1701q:txt58B" },
    .{ .form_element_ordinal = 141, .source_line = 1562, .kind = .text, .id = "frm1701q:txt59A" },
    .{ .form_element_ordinal = 142, .source_line = 1566, .kind = .text, .id = "frm1701q:txt59B" },
    .{ .form_element_ordinal = 143, .source_line = 1573, .kind = .text, .id = "frm1701q:txt60A" },
    .{ .form_element_ordinal = 144, .source_line = 1577, .kind = .text, .id = "frm1701q:txt60B" },
    .{ .form_element_ordinal = 145, .source_line = 1582, .kind = .text, .id = "frm1701q:txt61Desc" },
    .{ .form_element_ordinal = 146, .source_line = 1584, .kind = .text, .id = "frm1701q:txt61A" },
    .{ .form_element_ordinal = 147, .source_line = 1588, .kind = .text, .id = "frm1701q:txt61B" },
    .{ .form_element_ordinal = 148, .source_line = 1595, .kind = .text, .id = "frm1701q:txt62A" },
    .{ .form_element_ordinal = 149, .source_line = 1598, .kind = .text, .id = "frm1701q:txt62B" },
    .{ .form_element_ordinal = 150, .source_line = 1608, .kind = .text, .id = "frm1701q:txt63A" },
    .{ .form_element_ordinal = 151, .source_line = 1611, .kind = .text, .id = "frm1701q:txt63B" },
    .{ .form_element_ordinal = 152, .source_line = 1626, .kind = .text, .id = "frm1701q:txt64A" },
    .{ .form_element_ordinal = 153, .source_line = 1630, .kind = .text, .id = "frm1701q:txt64B" },
    .{ .form_element_ordinal = 154, .source_line = 1637, .kind = .text, .id = "frm1701q:txt65A" },
    .{ .form_element_ordinal = 155, .source_line = 1641, .kind = .text, .id = "frm1701q:txt65B" },
    .{ .form_element_ordinal = 156, .source_line = 1648, .kind = .text, .id = "frm1701q:txt66A" },
    .{ .form_element_ordinal = 157, .source_line = 1652, .kind = .text, .id = "frm1701q:txt66B" },
    .{ .form_element_ordinal = 158, .source_line = 1659, .kind = .text, .id = "frm1701q:txt67A" },
    .{ .form_element_ordinal = 159, .source_line = 1662, .kind = .text, .id = "frm1701q:txt67B" },
    .{ .form_element_ordinal = 160, .source_line = 1672, .kind = .text, .id = "frm1701q:txt68A" },
    .{ .form_element_ordinal = 161, .source_line = 1675, .kind = .text, .id = "frm1701q:txt68B" },
    .{ .form_element_ordinal = 163, .source_line = 1780, .kind = .text, .id = "frm1701q:txtCurrentPage" },
    .{ .form_element_ordinal = 164, .source_line = 1781, .kind = .text, .id = "frm1701q:txtMaxPage" },
    .{ .form_element_ordinal = 174, .source_line = 1837, .kind = .text, .id = "txtFinalFlag" },
    .{ .form_element_ordinal = 175, .source_line = 1838, .kind = .text, .id = "txtEnroll" },
    .{ .form_element_ordinal = 176, .source_line = 1855, .kind = .text, .id = "ebirOnlineConfirmUsername" },
    .{ .form_element_ordinal = 184, .source_line = 1942, .kind = .text, .id = "ebirOnlineUsername" },
    .{ .form_element_ordinal = 186, .source_line = 1951, .kind = .text, .id = "ebirOnlineSecret" },
    .{ .form_element_ordinal = 189, .source_line = 1967, .kind = .text, .id = "frm1701q:txtLOB" },
    .{ .form_element_ordinal = 190, .source_line = 1968, .kind = .text, .id = "frm1701q:txtTelno" },
    .{ .form_element_ordinal = 191, .source_line = 1990, .kind = .select_one, .id = "driveSelectTPExport" },
};

pub const editable_occurrence_items = buildEditableOccurrences();
pub const final_copy_occurrence_items = buildFinalCopyOccurrences();

pub fn editableManifest() occurrence.ManifestError!occurrence.OrderedOccurrenceManifest {
    return occurrence.OrderedOccurrenceManifest.init(&editable_occurrence_items);
}

pub fn finalCopyManifest() occurrence.ManifestError!occurrence.OrderedOccurrenceManifest {
    return occurrence.OrderedOccurrenceManifest.init(&final_copy_occurrence_items);
}

fn buildEditableOccurrences() [control_seeds.len - 1]occurrence.OccurrenceMetadata {
    @setEvalBranchQuota(100_000);

    var result: [control_seeds.len - 1]occurrence.OccurrenceMetadata = undefined;
    var output_index: usize = 0;
    for (control_seeds) |control| {
        if (std.mem.eql(u8, control.id, "frm1701q:txtAddress2")) continue;

        var emission: occurrence.EmissionKind = switch (control.kind) {
            .radio => .checked_boolean,
            .text, .select_one => .raw,
        };
        var source_controls: occurrence.SourceControls = .{
            .one = control.id,
        };
        var source_last_line = control.source_line;
        if (std.mem.eql(u8, control.id, "frm1701q:txtTaxpayerName") or
            std.mem.eql(u8, control.id, "frm1701q:txtLOB"))
        {
            emission = .legacy_escape;
        } else if (std.mem.eql(u8, control.id, "frm1701q:txtAddress")) {
            emission = .concatenated_legacy_escape;
            source_controls = .{ .two = .{
                "frm1701q:txtAddress",
                "frm1701q:txtAddress2",
            } };
            source_last_line = 525;
        } else if (std.mem.eql(
            u8,
            control.id,
            "frm1701q:txtCurrentPage",
        )) {
            emission = .constant;
        }

        result[output_index] = .{
            .ordinal = @intCast(output_index + 1),
            .canonical_field = .{
                .unreviewed_source_control = control.id,
            },
            .serialized_key = control.id,
            .same_key_occurrence = 1,
            .source_controls = source_controls,
            .source_control_first_line = control.source_line,
            .source_control_last_line = source_last_line,
            .origin = .unreviewed,
            .inclusion = .{ .editable_save = true },
            .emission = emission,
            .evidence = .{
                .evidence_id = evidence_id,
                .first_line = 2782,
                .last_line = 2896,
            },
        };
        output_index += 1;
    }
    std.debug.assert(output_index == result.len);
    return result;
}

fn buildFinalCopyOccurrences() [control_seeds.len]occurrence.OccurrenceMetadata {
    @setEvalBranchQuota(100_000);

    var result: [control_seeds.len]occurrence.OccurrenceMetadata = undefined;
    for (control_seeds, 0..) |control, index| {
        result[index] = .{
            .ordinal = @intCast(index + 1),
            .canonical_field = .{
                .unreviewed_source_control = control.id,
            },
            .serialized_key = control.id,
            .same_key_occurrence = 1,
            .source_controls = .{ .one = control.id },
            .source_control_first_line = control.source_line,
            .source_control_last_line = control.source_line,
            .origin = .unreviewed,
            .inclusion = .{ .final_copy_plaintext = true },
            .emission = switch (control.kind) {
                .radio => .checked_boolean,
                .text, .select_one => .raw,
            },
            .evidence = .{
                .evidence_id = evidence_id,
                .first_line = 2467,
                .last_line = 2478,
            },
        };
    }
    return result;
}

test "1701Q manifests preserve exact eligible and artifact counts" {
    const editable = try editableManifest();
    const final_copy = try finalCopyManifest();
    try std.testing.expectEqual(@as(usize, 173), control_seeds.len);
    try std.testing.expectEqual(@as(usize, 172), editable.items.len);
    try std.testing.expectEqual(@as(usize, 173), final_copy.items.len);
    try std.testing.expectEqualStrings(
        "frm1701q:txtRDOCode",
        control_seeds[11].id,
    );
    try std.testing.expectEqual(@as(u16, 12), control_seeds[11].runtimeFormElementOrdinal());
    try std.testing.expectEqualStrings(
        "frm1701q:txtSpouseRDOCode",
        control_seeds[42].id,
    );
    try std.testing.expectEqual(@as(u16, 43), control_seeds[42].runtimeFormElementOrdinal());
}

test "editable address collapse and page reset remain explicit metadata" {
    const editable = try editableManifest();
    const address = editable.findKeyOccurrence(
        "frm1701q:txtAddress",
        1,
    ).?;
    try std.testing.expectEqual(
        occurrence.EmissionKind.concatenated_legacy_escape,
        address.emission,
    );
    try std.testing.expectEqual(@as(u8, 2), address.source_controls.len());
    try std.testing.expect(
        editable.findKeyOccurrence("frm1701q:txtAddress2", 1) == null,
    );
    const current_page = editable.findKeyOccurrence(
        "frm1701q:txtCurrentPage",
        1,
    ).?;
    try std.testing.expectEqual(
        occurrence.EmissionKind.constant,
        current_page.emission,
    );
}

test "Final Copy retains separate raw address occurrences" {
    const final_copy = try finalCopyManifest();
    const address = final_copy.findKeyOccurrence(
        "frm1701q:txtAddress",
        1,
    ).?;
    const address_2 = final_copy.findKeyOccurrence(
        "frm1701q:txtAddress2",
        1,
    ).?;
    try std.testing.expectEqual(occurrence.EmissionKind.raw, address.emission);
    try std.testing.expectEqual(
        occurrence.EmissionKind.raw,
        address_2.emission,
    );
    try std.testing.expectEqual(@as(u16, 24), address.ordinal);
    try std.testing.expectEqual(@as(u16, 25), address_2.ordinal);
}

test "ordered control seed IDs and emitted keys remain unique" {
    for (control_seeds, 0..) |control, index| {
        if (index != 0) {
            try std.testing.expect(
                control_seeds[index - 1].runtimeFormElementOrdinal() <
                    control.runtimeFormElementOrdinal(),
            );
        }
        for (control_seeds[0..index]) |earlier| {
            try std.testing.expect(
                !std.mem.eql(u8, earlier.id, control.id),
            );
        }
    }
    const editable = try editableManifest();
    for (editable.items, 0..) |item, index| {
        for (editable.items[0..index]) |earlier| {
            try std.testing.expect(
                !std.mem.eql(
                    u8,
                    earlier.serialized_key,
                    item.serialized_key,
                ),
            );
        }
    }
}
