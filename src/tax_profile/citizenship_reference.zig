//! Local, searchable country-or-area reference for the Tax Profile editor's
//! citizenship control.
//!
//! Source: UN Statistics Division M49 country or area standard, downloaded
//! 2026-08-11 from https://unstats.un.org/unsd/methodology/m49/overview/.
//! M49 is a country/area vocabulary, not a legal-nationality registry. It is
//! used here to constrain selection without inventing a jurisdiction-specific
//! demonym list. The existing text persistence contract remains intact: the
//! Philippines is rendered as the BIR-facing citizenship word "Filipino".

const std = @import("std");

pub const default_result_limit: usize = 5;

pub const Entry = struct {
    code: []const u8,
    name: []const u8,

    pub fn value(self: *const Entry) []const u8 {
        return if (std.mem.eql(u8, self.code, "PH")) "Filipino" else self.name;
    }

    pub fn label(self: *const Entry) []const u8 {
        if (std.mem.eql(u8, self.code, "PH")) return "Filipino · Philippines";
        return self.name;
    }
};

pub const entries = [_]Entry{
    .{ .code = "AF", .name = "Afghanistan" },
    .{ .code = "AL", .name = "Albania" },
    .{ .code = "DZ", .name = "Algeria" },
    .{ .code = "AS", .name = "American Samoa" },
    .{ .code = "AD", .name = "Andorra" },
    .{ .code = "AO", .name = "Angola" },
    .{ .code = "AI", .name = "Anguilla" },
    .{ .code = "AQ", .name = "Antarctica" },
    .{ .code = "AG", .name = "Antigua and Barbuda" },
    .{ .code = "AR", .name = "Argentina" },
    .{ .code = "AM", .name = "Armenia" },
    .{ .code = "AW", .name = "Aruba" },
    .{ .code = "AU", .name = "Australia" },
    .{ .code = "AT", .name = "Austria" },
    .{ .code = "AZ", .name = "Azerbaijan" },
    .{ .code = "BS", .name = "Bahamas" },
    .{ .code = "BH", .name = "Bahrain" },
    .{ .code = "BD", .name = "Bangladesh" },
    .{ .code = "BB", .name = "Barbados" },
    .{ .code = "BY", .name = "Belarus" },
    .{ .code = "BE", .name = "Belgium" },
    .{ .code = "BZ", .name = "Belize" },
    .{ .code = "BJ", .name = "Benin" },
    .{ .code = "BM", .name = "Bermuda" },
    .{ .code = "BT", .name = "Bhutan" },
    .{ .code = "BO", .name = "Bolivia (Plurinational State of)" },
    .{ .code = "BQ", .name = "Bonaire, Sint Eustatius and Saba" },
    .{ .code = "BA", .name = "Bosnia and Herzegovina" },
    .{ .code = "BW", .name = "Botswana" },
    .{ .code = "BV", .name = "Bouvet Island" },
    .{ .code = "BR", .name = "Brazil" },
    .{ .code = "IO", .name = "British Indian Ocean Territory" },
    .{ .code = "VG", .name = "British Virgin Islands" },
    .{ .code = "BN", .name = "Brunei Darussalam" },
    .{ .code = "BG", .name = "Bulgaria" },
    .{ .code = "BF", .name = "Burkina Faso" },
    .{ .code = "BI", .name = "Burundi" },
    .{ .code = "CV", .name = "Cabo Verde" },
    .{ .code = "KH", .name = "Cambodia" },
    .{ .code = "CM", .name = "Cameroon" },
    .{ .code = "CA", .name = "Canada" },
    .{ .code = "KY", .name = "Cayman Islands" },
    .{ .code = "CF", .name = "Central African Republic" },
    .{ .code = "TD", .name = "Chad" },
    .{ .code = "CL", .name = "Chile" },
    .{ .code = "CN", .name = "China" },
    .{ .code = "HK", .name = "China, Hong Kong Special Administrative Region" },
    .{ .code = "MO", .name = "China, Macao Special Administrative Region" },
    .{ .code = "CX", .name = "Christmas Island" },
    .{ .code = "CC", .name = "Cocos (Keeling) Islands" },
    .{ .code = "CO", .name = "Colombia" },
    .{ .code = "KM", .name = "Comoros" },
    .{ .code = "CG", .name = "Congo" },
    .{ .code = "CK", .name = "Cook Islands" },
    .{ .code = "CR", .name = "Costa Rica" },
    .{ .code = "HR", .name = "Croatia" },
    .{ .code = "CU", .name = "Cuba" },
    .{ .code = "CW", .name = "Curaçao" },
    .{ .code = "CY", .name = "Cyprus" },
    .{ .code = "CZ", .name = "Czechia" },
    .{ .code = "CI", .name = "Côte d’Ivoire" },
    .{ .code = "KP", .name = "Democratic People's Republic of Korea" },
    .{ .code = "CD", .name = "Democratic Republic of the Congo" },
    .{ .code = "DK", .name = "Denmark" },
    .{ .code = "DJ", .name = "Djibouti" },
    .{ .code = "DM", .name = "Dominica" },
    .{ .code = "DO", .name = "Dominican Republic" },
    .{ .code = "EC", .name = "Ecuador" },
    .{ .code = "EG", .name = "Egypt" },
    .{ .code = "SV", .name = "El Salvador" },
    .{ .code = "GQ", .name = "Equatorial Guinea" },
    .{ .code = "ER", .name = "Eritrea" },
    .{ .code = "EE", .name = "Estonia" },
    .{ .code = "SZ", .name = "Eswatini" },
    .{ .code = "ET", .name = "Ethiopia" },
    .{ .code = "FK", .name = "Falkland Islands (Malvinas)" },
    .{ .code = "FO", .name = "Faroe Islands" },
    .{ .code = "FJ", .name = "Fiji" },
    .{ .code = "FI", .name = "Finland" },
    .{ .code = "FR", .name = "France" },
    .{ .code = "GF", .name = "French Guiana" },
    .{ .code = "PF", .name = "French Polynesia" },
    .{ .code = "TF", .name = "French Southern Territories" },
    .{ .code = "GA", .name = "Gabon" },
    .{ .code = "GM", .name = "Gambia" },
    .{ .code = "GE", .name = "Georgia" },
    .{ .code = "DE", .name = "Germany" },
    .{ .code = "GH", .name = "Ghana" },
    .{ .code = "GI", .name = "Gibraltar" },
    .{ .code = "GR", .name = "Greece" },
    .{ .code = "GL", .name = "Greenland" },
    .{ .code = "GD", .name = "Grenada" },
    .{ .code = "GP", .name = "Guadeloupe" },
    .{ .code = "GU", .name = "Guam" },
    .{ .code = "GT", .name = "Guatemala" },
    .{ .code = "GG", .name = "Guernsey" },
    .{ .code = "GN", .name = "Guinea" },
    .{ .code = "GW", .name = "Guinea-Bissau" },
    .{ .code = "GY", .name = "Guyana" },
    .{ .code = "HT", .name = "Haiti" },
    .{ .code = "HM", .name = "Heard Island and McDonald Islands" },
    .{ .code = "VA", .name = "Holy See" },
    .{ .code = "HN", .name = "Honduras" },
    .{ .code = "HU", .name = "Hungary" },
    .{ .code = "IS", .name = "Iceland" },
    .{ .code = "IN", .name = "India" },
    .{ .code = "ID", .name = "Indonesia" },
    .{ .code = "IR", .name = "Iran (Islamic Republic of)" },
    .{ .code = "IQ", .name = "Iraq" },
    .{ .code = "IE", .name = "Ireland" },
    .{ .code = "IM", .name = "Isle of Man" },
    .{ .code = "IL", .name = "Israel" },
    .{ .code = "IT", .name = "Italy" },
    .{ .code = "JM", .name = "Jamaica" },
    .{ .code = "JP", .name = "Japan" },
    .{ .code = "JE", .name = "Jersey" },
    .{ .code = "JO", .name = "Jordan" },
    .{ .code = "KZ", .name = "Kazakhstan" },
    .{ .code = "KE", .name = "Kenya" },
    .{ .code = "KI", .name = "Kiribati" },
    .{ .code = "KW", .name = "Kuwait" },
    .{ .code = "KG", .name = "Kyrgyzstan" },
    .{ .code = "LA", .name = "Lao People's Democratic Republic" },
    .{ .code = "LV", .name = "Latvia" },
    .{ .code = "LB", .name = "Lebanon" },
    .{ .code = "LS", .name = "Lesotho" },
    .{ .code = "LR", .name = "Liberia" },
    .{ .code = "LY", .name = "Libya" },
    .{ .code = "LI", .name = "Liechtenstein" },
    .{ .code = "LT", .name = "Lithuania" },
    .{ .code = "LU", .name = "Luxembourg" },
    .{ .code = "MG", .name = "Madagascar" },
    .{ .code = "MW", .name = "Malawi" },
    .{ .code = "MY", .name = "Malaysia" },
    .{ .code = "MV", .name = "Maldives" },
    .{ .code = "ML", .name = "Mali" },
    .{ .code = "MT", .name = "Malta" },
    .{ .code = "MH", .name = "Marshall Islands" },
    .{ .code = "MQ", .name = "Martinique" },
    .{ .code = "MR", .name = "Mauritania" },
    .{ .code = "MU", .name = "Mauritius" },
    .{ .code = "YT", .name = "Mayotte" },
    .{ .code = "MX", .name = "Mexico" },
    .{ .code = "FM", .name = "Micronesia (Federated States of)" },
    .{ .code = "MC", .name = "Monaco" },
    .{ .code = "MN", .name = "Mongolia" },
    .{ .code = "ME", .name = "Montenegro" },
    .{ .code = "MS", .name = "Montserrat" },
    .{ .code = "MA", .name = "Morocco" },
    .{ .code = "MZ", .name = "Mozambique" },
    .{ .code = "MM", .name = "Myanmar" },
    .{ .code = "NA", .name = "Namibia" },
    .{ .code = "NR", .name = "Nauru" },
    .{ .code = "NP", .name = "Nepal" },
    .{ .code = "NL", .name = "Netherlands (Kingdom of the)" },
    .{ .code = "NC", .name = "New Caledonia" },
    .{ .code = "NZ", .name = "New Zealand" },
    .{ .code = "NI", .name = "Nicaragua" },
    .{ .code = "NE", .name = "Niger" },
    .{ .code = "NG", .name = "Nigeria" },
    .{ .code = "NU", .name = "Niue" },
    .{ .code = "NF", .name = "Norfolk Island" },
    .{ .code = "MK", .name = "North Macedonia" },
    .{ .code = "MP", .name = "Northern Mariana Islands" },
    .{ .code = "NO", .name = "Norway" },
    .{ .code = "OM", .name = "Oman" },
    .{ .code = "PK", .name = "Pakistan" },
    .{ .code = "PW", .name = "Palau" },
    .{ .code = "PA", .name = "Panama" },
    .{ .code = "PG", .name = "Papua New Guinea" },
    .{ .code = "PY", .name = "Paraguay" },
    .{ .code = "PE", .name = "Peru" },
    .{ .code = "PH", .name = "Philippines" },
    .{ .code = "PN", .name = "Pitcairn" },
    .{ .code = "PL", .name = "Poland" },
    .{ .code = "PT", .name = "Portugal" },
    .{ .code = "PR", .name = "Puerto Rico" },
    .{ .code = "QA", .name = "Qatar" },
    .{ .code = "KR", .name = "Republic of Korea" },
    .{ .code = "MD", .name = "Republic of Moldova" },
    .{ .code = "RO", .name = "Romania" },
    .{ .code = "RU", .name = "Russian Federation" },
    .{ .code = "RW", .name = "Rwanda" },
    .{ .code = "RE", .name = "Réunion" },
    .{ .code = "BL", .name = "Saint Barthélemy" },
    .{ .code = "SH", .name = "Saint Helena" },
    .{ .code = "KN", .name = "Saint Kitts and Nevis" },
    .{ .code = "LC", .name = "Saint Lucia" },
    .{ .code = "MF", .name = "Saint Martin (French Part)" },
    .{ .code = "PM", .name = "Saint Pierre and Miquelon" },
    .{ .code = "VC", .name = "Saint Vincent and the Grenadines" },
    .{ .code = "WS", .name = "Samoa" },
    .{ .code = "SM", .name = "San Marino" },
    .{ .code = "ST", .name = "Sao Tome and Principe" },
    .{ .code = "SA", .name = "Saudi Arabia" },
    .{ .code = "SN", .name = "Senegal" },
    .{ .code = "RS", .name = "Serbia" },
    .{ .code = "SC", .name = "Seychelles" },
    .{ .code = "SL", .name = "Sierra Leone" },
    .{ .code = "SG", .name = "Singapore" },
    .{ .code = "SX", .name = "Sint Maarten (Dutch part)" },
    .{ .code = "SK", .name = "Slovakia" },
    .{ .code = "SI", .name = "Slovenia" },
    .{ .code = "SB", .name = "Solomon Islands" },
    .{ .code = "SO", .name = "Somalia" },
    .{ .code = "ZA", .name = "South Africa" },
    .{ .code = "GS", .name = "South Georgia and the South Sandwich Islands" },
    .{ .code = "SS", .name = "South Sudan" },
    .{ .code = "ES", .name = "Spain" },
    .{ .code = "LK", .name = "Sri Lanka" },
    .{ .code = "PS", .name = "State of Palestine" },
    .{ .code = "SD", .name = "Sudan" },
    .{ .code = "SR", .name = "Suriname" },
    .{ .code = "SJ", .name = "Svalbard and Jan Mayen Islands" },
    .{ .code = "SE", .name = "Sweden" },
    .{ .code = "CH", .name = "Switzerland" },
    .{ .code = "SY", .name = "Syrian Arab Republic" },
    .{ .code = "TJ", .name = "Tajikistan" },
    .{ .code = "TH", .name = "Thailand" },
    .{ .code = "TL", .name = "Timor-Leste" },
    .{ .code = "TG", .name = "Togo" },
    .{ .code = "TK", .name = "Tokelau" },
    .{ .code = "TO", .name = "Tonga" },
    .{ .code = "TT", .name = "Trinidad and Tobago" },
    .{ .code = "TN", .name = "Tunisia" },
    .{ .code = "TM", .name = "Turkmenistan" },
    .{ .code = "TC", .name = "Turks and Caicos Islands" },
    .{ .code = "TV", .name = "Tuvalu" },
    .{ .code = "TR", .name = "Türkiye" },
    .{ .code = "UG", .name = "Uganda" },
    .{ .code = "UA", .name = "Ukraine" },
    .{ .code = "AE", .name = "United Arab Emirates" },
    .{ .code = "GB", .name = "United Kingdom of Great Britain and Northern Ireland" },
    .{ .code = "TZ", .name = "United Republic of Tanzania" },
    .{ .code = "UM", .name = "United States Minor Outlying Islands" },
    .{ .code = "US", .name = "United States of America" },
    .{ .code = "VI", .name = "United States Virgin Islands" },
    .{ .code = "UY", .name = "Uruguay" },
    .{ .code = "UZ", .name = "Uzbekistan" },
    .{ .code = "VU", .name = "Vanuatu" },
    .{ .code = "VE", .name = "Venezuela (Bolivarian Republic of)" },
    .{ .code = "VN", .name = "Viet Nam" },
    .{ .code = "WF", .name = "Wallis and Futuna Islands" },
    .{ .code = "EH", .name = "Western Sahara" },
    .{ .code = "YE", .name = "Yemen" },
    .{ .code = "ZM", .name = "Zambia" },
    .{ .code = "ZW", .name = "Zimbabwe" },
    .{ .code = "AX", .name = "Åland Islands" },
};

pub const SearchResult = struct {
    matches: [default_result_limit]*const Entry = undefined,
    len: usize = 0,

    pub fn items(self: *const SearchResult) []const *const Entry {
        return self.matches[0..self.len];
    }
};

/// An empty query starts with Filipino, then the first four catalogue entries.
/// A query matches the country name, persisted citizenship value, or the
/// display label currently shown in the combobox control.
pub fn search(query: []const u8) SearchResult {
    const needle = std.mem.trim(u8, query, " \t\r\n");
    var result = SearchResult{};
    if (needle.len == 0) {
        append(&result, findByCode("PH").?);
    }
    for (&entries) |*entry| {
        if (result.len == result.matches.len) break;
        if (std.mem.eql(u8, entry.code, "PH") and needle.len == 0) continue;
        if (!containsAsciiInsensitive(entry.name, needle) and
            !containsAsciiInsensitive(entry.value(), needle) and
            !containsAsciiInsensitive(entry.label(), needle)) continue;
        append(&result, entry);
    }
    return result;
}

pub fn findByValue(value: []const u8) ?*const Entry {
    const needle = std.mem.trim(u8, value, " \t\r\n");
    for (&entries) |*entry| {
        // Older profile revisions may have persisted the ISO country code
        // rather than this editor's current display/persistence value. Keep
        // those records editable and canonicalize them through `value()` on
        // the next save instead of rejecting an unrelated correction.
        if (eqlAsciiInsensitive(entry.value(), needle) or
            eqlAsciiInsensitive(entry.name, needle) or
            eqlAsciiInsensitive(entry.code, needle)) return entry;
    }
    return null;
}

pub fn findByCode(code: []const u8) ?*const Entry {
    for (&entries) |*entry| {
        if (eqlAsciiInsensitive(entry.code, code)) return entry;
    }
    return null;
}

fn append(result: *SearchResult, entry: *const Entry) void {
    if (result.len == result.matches.len) return;
    result.matches[result.len] = entry;
    result.len += 1;
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

test "catalogue includes every local UN M49 country or area row" {
    try std.testing.expectEqual(@as(usize, 248), entries.len);
    try std.testing.expectEqualStrings("Filipino", findByCode("PH").?.value());
    try std.testing.expect(findByValue("Filipino") != null);
    try std.testing.expectEqualStrings("Filipino", findByValue("ph").?.value());
}

test "citizenship search starts small and filters the full catalogue" {
    const initial = search("");
    try std.testing.expectEqual(default_result_limit, initial.len);
    try std.testing.expectEqualStrings("PH", initial.items()[0].code);

    const japan = search("japan");
    try std.testing.expectEqual(@as(usize, 1), japan.len);
    try std.testing.expectEqualStrings("JP", japan.items()[0].code);

    const selected_philippines = search("Filipino · Philippines");
    try std.testing.expectEqual(@as(usize, 1), selected_philippines.len);
    try std.testing.expectEqualStrings("PH", selected_philippines.items()[0].code);
}
