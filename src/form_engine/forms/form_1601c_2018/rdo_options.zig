//! Exact RDO option values available to 1601C January 2018 (ENCS).
//!
//! Grounding:
//! - Offline eBIRForms 7.9.6 `xml/rdo.xml`, 40,317 bytes,
//!   SHA-256 `17c85ca0ae23dd096c28a240fcfaf047c9244b041d8bae65352a9260f6c8c925`;
//! - `loadXMLrdo` reads that file into the hidden `responseRdo` div,
//!   `loadRdo` keeps a record when it contains the substring `1601C` at
//!   line 2737, and `getRdo` injects the survivors into the Item 7 select;
//! - all 138 source records include `1601C`.
//!
//! `getRdo` emits the select carrying a bare `disabled` attribute, where
//! 1601EQ's emits `disabled='true'`. Both are markup-disabled; only the
//! spelling differs.
//!
//! `000` is the leading blank placeholder, so it is not an accepted value.
//! `validate` rejects Item 7 by `selectedIndex == 0`, which is that
//! placeholder's position.
//!
//! This list is derived independently of 1601EQ's and 1701Q's. All three
//! filter the same file for different form tokens and currently yield the
//! same 138 records; that is a property of this `rdo.xml`, not a guarantee,
//! so each is pinned separately and a test asserts they still agree.

const std = @import("std");
const field = @import("../../../tax_profile/field.zig");

pub const source_byte_length: usize = 40_317;
pub const source_sha256 =
    "17c85ca0ae23dd096c28a240fcfaf047c9244b041d8bae65352a9260f6c8c925";

pub const placeholder_value = "000";

/// The substring `loadRdo` tests each record against.
pub const filter_token = "1601C";

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

test "1601C RDO option domain is exact, unique, and excludes placeholder" {
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
    const placeholder = try field.RdoCode.parse(placeholder_value);
    try std.testing.expect(contains(&numeric));
    try std.testing.expect(contains(&alpha));
    try std.testing.expect(!contains(&placeholder));
}

test "1601C, 1601EQ and 1701Q still resolve rdo.xml to the same domain" {
    const eq = @import("../form_1601eq_2018/rdo_options.zig");
    const q = @import("../form_1701q_2018/rdo_options.zig");
    try std.testing.expectEqualStrings(source_sha256, eq.source_sha256);
    try std.testing.expectEqualStrings(source_sha256, q.source_sha256);
    try std.testing.expectEqual(eq.values.len, values.len);
    try std.testing.expectEqual(q.values.len, values.len);
    for (values, eq.values, q.values) |mine, theirs, ours| {
        try std.testing.expectEqualStrings(theirs, mine);
        try std.testing.expectEqualStrings(ours, mine);
    }
}

test "1601C's filter token cannot be confused with a sibling form code" {
    try std.testing.expectEqualStrings("1601C", filter_token);
    // loadRdo uses a substring test, so a sibling code that began with this
    // token would silently match. None does.
    // The 1601-family codes that actually appear in rdo.xml.
    for ([_][]const u8{ "1601E", "1601EQ", "1601F", "1601FQ" }) |sibling| {
        const collides = std.mem.startsWith(u8, sibling, filter_token) and
            !std.mem.eql(u8, sibling, filter_token);
        try std.testing.expect(!collides);
    }
}
