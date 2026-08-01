//! Exact RDO option values available to 1701Q January 2018.
//!
//! Grounding:
//! - Offline eBIRForms 7.9.6 `xml/rdo.xml`, 40,317 bytes,
//!   SHA-256 `17c85ca0ae23dd096c28a240fcfaf047c9244b041d8bae65352a9260f6c8c925`;
//! - the HTA loads and filters that file for the `1701Q` token at lines
//!   3151-3203;
//! - all 138 source records include `1701Q`, and `getRdo()` injects their
//!   values into both RDO selects at lines 3707-3719.
//!
//! `000` is the blank placeholder, not an accepted profile value.

const std = @import("std");
const field = @import("../../../tax_profile/field.zig");

pub const source_byte_length: usize = 40_317;
pub const source_sha256 =
    "17c85ca0ae23dd096c28a240fcfaf047c9244b041d8bae65352a9260f6c8c925";

pub const values = [_][]const u8{
    "001", "002", "003", "004", "005", "006", "007", "008",
    "009", "010", "011", "012", "013", "014", "015", "016",
    "17A", "17B", "018", "019", "020", "21A", "21B", "21C",
    "022", "23A", "23B", "024", "25A", "25B", "026", "027",
    "028", "029", "030", "031", "032", "033", "034", "035",
    "036", "037", "038", "039", "040", "041", "042", "043",
    "43A", "43B", "044", "045", "046", "047", "048", "049",
    "050", "051", "052", "53A", "53B", "54A", "54B", "055",
    "056", "057", "058", "059", "060", "061", "062", "063",
    "064", "065", "066", "067", "068", "069", "070", "071",
    "072", "073", "074", "075", "076", "077", "078", "079",
    "080", "081", "082", "083", "084", "085", "086", "087",
    "088", "089", "090", "091", "092", "93A", "93B", "094",
    "095", "096", "097", "098", "099", "100", "101", "102",
    "103", "104", "105", "106", "107", "108", "109", "110",
    "111", "112", "113", "114", "115", "116", "117", "118",
    "119", "120", "121", "122", "123", "124", "125", "126",
    "127", "132",
};

pub fn contains(value: *const field.RdoCode) bool {
    for (values) |candidate| {
        if (std.mem.eql(u8, candidate, value.asSlice())) return true;
    }
    return false;
}

test "1701Q RDO option domain is exact, unique, and excludes placeholder" {
    try std.testing.expectEqual(@as(usize, 138), values.len);
    for (values, 0..) |raw, index| {
        const parsed = try field.RdoCode.parse(raw);
        try std.testing.expectEqualStrings(raw, parsed.asSlice());
        for (values[0..index]) |earlier| {
            try std.testing.expect(!std.mem.eql(u8, earlier, raw));
        }
    }

    const numeric = try field.RdoCode.parse("019");
    const alpha = try field.RdoCode.parse("17A");
    const final = try field.RdoCode.parse("132");
    const placeholder = try field.RdoCode.parse("000");
    const unknown = try field.RdoCode.parse("ABC");
    try std.testing.expect(contains(&numeric));
    try std.testing.expect(contains(&alpha));
    try std.testing.expect(contains(&final));
    try std.testing.expect(!contains(&placeholder));
    try std.testing.expect(!contains(&unknown));
}
