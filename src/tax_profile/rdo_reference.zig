//! Canonical Revenue District Office reference data used by profile editors.
//!
//! The 138 rows were imported from the previous application's checked-in
//! `crates/bir-core/data/rdo.json` (8,743 bytes, SHA-256
//! `7d03ff6e6444c56ae26bccfe5db52439f36b5bd99cb44b69dde2be5afddd41c0`).
//! Profile revisions persist only `Entry.code`; `Entry.name` is reference
//! presentation data and can be revised independently of stored profiles.

const std = @import("std");

pub const source_sha256 =
    "7d03ff6e6444c56ae26bccfe5db52439f36b5bd99cb44b69dde2be5afddd41c0";
pub const source_byte_length: usize = 8_743;
pub const default_result_limit: usize = 5;

pub const Entry = struct {
    code: []const u8,
    name: []const u8,
};

pub const entries = [_]Entry{
    .{ .code = "001", .name = "Laoag City" },
    .{ .code = "002", .name = "Vigan City" },
    .{ .code = "003", .name = "San Fernando, La Union" },
    .{ .code = "004", .name = "Calasiao, Pangasinan" },
    .{ .code = "005", .name = "Alaminos City" },
    .{ .code = "006", .name = "Urdaneta City" },
    .{ .code = "007", .name = "Bangued, Abra" },
    .{ .code = "008", .name = "Baguio City" },
    .{ .code = "009", .name = "La Trinidad, Benguet" },
    .{ .code = "010", .name = "Lagawe, Ifugao" },
    .{ .code = "011", .name = "Tabuk City, Kalinga" },
    .{ .code = "012", .name = "Lagawe, Ifugao" },
    .{ .code = "013", .name = "Tuguegarao City" },
    .{ .code = "014", .name = "Bayombong, Nueva Vizcaya" },
    .{ .code = "015", .name = "Ilagan, Isabela" },
    .{ .code = "016", .name = "Cabarroguis, Quirino" },
    .{ .code = "17A", .name = "Tarlac City" },
    .{ .code = "17B", .name = "Paniqui, Tarlac" },
    .{ .code = "018", .name = "Olongapo City" },
    .{ .code = "019", .name = "Subic Bay Freeport Zone" },
    .{ .code = "020", .name = "Balanga City, Bataan" },
    .{ .code = "21A", .name = "North Pampanga" },
    .{ .code = "21B", .name = "South Pampanga" },
    .{ .code = "21C", .name = "Clark Freeport Zone" },
    .{ .code = "022", .name = "Baler, Aurora" },
    .{ .code = "23A", .name = "North Nueva Ecija" },
    .{ .code = "23B", .name = "South Nueva Ecija" },
    .{ .code = "024", .name = "Valenzuela City" },
    .{ .code = "25A", .name = "West Bulacan" },
    .{ .code = "25B", .name = "East Bulacan" },
    .{ .code = "026", .name = "Malabon and Navotas" },
    .{ .code = "027", .name = "Caloocan City" },
    .{ .code = "028", .name = "Novaliches" },
    .{ .code = "029", .name = "San Nicolas" },
    .{ .code = "030", .name = "Binondo" },
    .{ .code = "031", .name = "Sta. Cruz" },
    .{ .code = "032", .name = "Quiapo, Sampaloc" },
    .{ .code = "033", .name = "Intramuros, Ermita, Malate" },
    .{ .code = "034", .name = "Paco, Pandacan, Sta. Ana" },
    .{ .code = "035", .name = "RDO 035" },
    .{ .code = "036", .name = "RDO 036" },
    .{ .code = "037", .name = "RDO 037" },
    .{ .code = "038", .name = "North Quezon City" },
    .{ .code = "039", .name = "South Quezon City" },
    .{ .code = "040", .name = "Cubao" },
    .{ .code = "041", .name = "Mandaluyong City" },
    .{ .code = "042", .name = "San Juan City" },
    .{ .code = "043", .name = "RDO 043" },
    .{ .code = "43A", .name = "East Pasig" },
    .{ .code = "43B", .name = "West Pasig" },
    .{ .code = "044", .name = "Taguig and Pateros" },
    .{ .code = "045", .name = "Marikina City" },
    .{ .code = "046", .name = "Cainta and Taytay" },
    .{ .code = "047", .name = "East Makati" },
    .{ .code = "048", .name = "West Makati" },
    .{ .code = "049", .name = "North Makati" },
    .{ .code = "050", .name = "South Makati" },
    .{ .code = "051", .name = "Pasay City" },
    .{ .code = "052", .name = "Parañaque City" },
    .{ .code = "53A", .name = "Las Piñas City" },
    .{ .code = "53B", .name = "Muntinlupa City" },
    .{ .code = "54A", .name = "Trece Martires City" },
    .{ .code = "54B", .name = "Bacoor City" },
    .{ .code = "055", .name = "San Pablo City" },
    .{ .code = "056", .name = "Calamba City" },
    .{ .code = "057", .name = "Biñan City" },
    .{ .code = "058", .name = "Batangas City" },
    .{ .code = "059", .name = "Lipa City" },
    .{ .code = "060", .name = "Lucena City" },
    .{ .code = "061", .name = "Gumaca, Quezon" },
    .{ .code = "062", .name = "Boac, Marinduque" },
    .{ .code = "063", .name = "Calapan City" },
    .{ .code = "064", .name = "San Jose, Occidental Mindoro" },
    .{ .code = "065", .name = "Naga City" },
    .{ .code = "066", .name = "Iriga City" },
    .{ .code = "067", .name = "Legazpi City" },
    .{ .code = "068", .name = "Sorsogon City" },
    .{ .code = "069", .name = "Virac, Catanduanes" },
    .{ .code = "070", .name = "Masbate City" },
    .{ .code = "071", .name = "Kalibo, Aklan" },
    .{ .code = "072", .name = "Roxas City" },
    .{ .code = "073", .name = "San Jose, Antique" },
    .{ .code = "074", .name = "Iloilo City" },
    .{ .code = "075", .name = "Zarraga, Iloilo" },
    .{ .code = "076", .name = "Victorias City" },
    .{ .code = "077", .name = "Bacolod City" },
    .{ .code = "078", .name = "Binalbagan, Negros Occidental" },
    .{ .code = "079", .name = "Dumaguete City" },
    .{ .code = "080", .name = "Mandaue City" },
    .{ .code = "081", .name = "Cebu City North" },
    .{ .code = "082", .name = "Cebu City South" },
    .{ .code = "083", .name = "Talisay City" },
    .{ .code = "084", .name = "Tagbilaran City" },
    .{ .code = "085", .name = "Catarman, Northern Samar" },
    .{ .code = "086", .name = "Borongan City" },
    .{ .code = "087", .name = "Catbalogan City" },
    .{ .code = "088", .name = "Tacloban City" },
    .{ .code = "089", .name = "Ormoc City" },
    .{ .code = "090", .name = "Maasin City" },
    .{ .code = "091", .name = "Dipolog City" },
    .{ .code = "092", .name = "Pagadian City" },
    .{ .code = "93A", .name = "Zamboanga City" },
    .{ .code = "93B", .name = "Zamboanga Sibugay" },
    .{ .code = "094", .name = "Isabela City" },
    .{ .code = "095", .name = "Jolo, Sulu" },
    .{ .code = "096", .name = "Bongao, Tawi-Tawi" },
    .{ .code = "097", .name = "Gingoog City" },
    .{ .code = "098", .name = "Cagayan de Oro City" },
    .{ .code = "099", .name = "Malaybalay City" },
    .{ .code = "100", .name = "Ozamiz City" },
    .{ .code = "101", .name = "Iligan City" },
    .{ .code = "102", .name = "Marawi City" },
    .{ .code = "103", .name = "Butuan City" },
    .{ .code = "104", .name = "Bayugan City" },
    .{ .code = "105", .name = "Surigao City" },
    .{ .code = "106", .name = "Tandag City" },
    .{ .code = "107", .name = "Cotabato City" },
    .{ .code = "108", .name = "Kidapawan City" },
    .{ .code = "109", .name = "Tacurong City" },
    .{ .code = "110", .name = "General Santos City" },
    .{ .code = "111", .name = "Koronadal City" },
    .{ .code = "112", .name = "Tagum City" },
    .{ .code = "113", .name = "Davao City" },
    .{ .code = "114", .name = "Mati City" },
    .{ .code = "115", .name = "Digos City" },
    .{ .code = "116", .name = "Bislig City" },
    .{ .code = "117", .name = "RDO 117" },
    .{ .code = "118", .name = "RDO 118" },
    .{ .code = "119", .name = "RDO 119" },
    .{ .code = "120", .name = "RDO 120" },
    .{ .code = "121", .name = "RDO 121" },
    .{ .code = "122", .name = "RDO 122" },
    .{ .code = "123", .name = "RDO 123" },
    .{ .code = "124", .name = "RDO 124" },
    .{ .code = "125", .name = "RDO 125" },
    .{ .code = "126", .name = "RDO 126" },
    .{ .code = "127", .name = "RDO 127" },
    .{ .code = "132", .name = "RDO 132" },
};

pub const SearchResult = struct {
    matches: [default_result_limit]*const Entry = undefined,
    len: usize = 0,

    pub fn items(self: *const SearchResult) []const *const Entry {
        return self.matches[0..self.len];
    }
};

/// Returns the first five RDOs whose code or name contains `query`.
///
/// Matching is ASCII case-insensitive and allocation-free. An empty query
/// intentionally returns the first five catalog rows for the combobox's
/// initial open state.
pub fn search(query: []const u8) SearchResult {
    const needle = std.mem.trim(u8, query, " \t\r\n");
    var result = SearchResult{};
    for (&entries) |*entry| {
        if (!containsAsciiInsensitive(entry.code, needle) and
            !containsAsciiInsensitive(entry.name, needle))
        {
            continue;
        }
        result.matches[result.len] = entry;
        result.len += 1;
        if (result.len == result.matches.len) break;
    }
    return result;
}

/// Resolves an exact RDO code to its canonical catalog row.
///
/// Case is ignored for the alphanumeric RDO variants, but partial codes,
/// labels, and arbitrary free text are rejected.
pub fn findByCode(code: []const u8) ?*const Entry {
    for (&entries) |*entry| {
        if (eqlAsciiInsensitive(entry.code, code)) return entry;
    }
    return null;
}

pub fn isValidCode(code: []const u8) bool {
    return findByCode(code) != null;
}

fn containsAsciiInsensitive(candidate: []const u8, query: []const u8) bool {
    if (query.len == 0) return true;
    if (query.len > candidate.len) return false;

    var start: usize = 0;
    while (start + query.len <= candidate.len) : (start += 1) {
        if (eqlAsciiInsensitive(candidate[start .. start + query.len], query)) {
            return true;
        }
    }
    return false;
}

fn eqlAsciiInsensitive(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_byte, right_byte| {
        if (std.ascii.toLower(left_byte) != std.ascii.toLower(right_byte)) {
            return false;
        }
    }
    return true;
}

test "RDO catalog preserves all 138 unique canonical codes" {
    try std.testing.expectEqual(@as(usize, 138), entries.len);
    for (entries, 0..) |entry, index| {
        try std.testing.expect(entry.code.len == 3);
        try std.testing.expect(entry.name.len != 0);
        for (entries[0..index]) |earlier| {
            try std.testing.expect(!std.mem.eql(u8, earlier.code, entry.code));
        }
    }
}

test "RDO search starts with five rows and matches code or city" {
    const initial = search("");
    try std.testing.expectEqual(default_result_limit, initial.len);
    try std.testing.expectEqualStrings("001", initial.items()[0].code);
    try std.testing.expectEqualStrings("005", initial.items()[4].code);

    const by_code = search("001");
    try std.testing.expectEqual(@as(usize, 1), by_code.len);
    try std.testing.expectEqualStrings("Laoag City", by_code.items()[0].name);

    const by_name = search("lAoAg");
    try std.testing.expectEqual(@as(usize, 1), by_name.len);
    try std.testing.expectEqualStrings("001", by_name.items()[0].code);

    const partial_city = search("longa");
    try std.testing.expectEqual(@as(usize, 1), partial_city.len);
    try std.testing.expectEqualStrings("018", partial_city.items()[0].code);
}

test "RDO exact-code validation rejects labels and arbitrary values" {
    try std.testing.expectEqualStrings("001", findByCode("001").?.code);
    try std.testing.expectEqualStrings("17A", findByCode("17a").?.code);
    try std.testing.expect(!isValidCode("01"));
    try std.testing.expect(!isValidCode("001 - Laoag City"));
    try std.testing.expect(!isValidCode("Laoag"));
    try std.testing.expect(!isValidCode("ABC"));
}
