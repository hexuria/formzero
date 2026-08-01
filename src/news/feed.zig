//! Small, bounded RSS 2.0 and Atom feed adapter for Important News.
//!
//! This is intentionally not a general-purpose XML implementation. It accepts
//! the element shapes used by RSS/Atom feeds, rejects oversized input before
//! allocating, and requires every entry to provide a stable id (or a canonical
//! HTTP(S) link used as that id).

const std = @import("std");
const domain = @import("domain.zig");

pub const Error = domain.Error || std.mem.Allocator.Error || error{
    FeedTooLarge,
    TooManyEntries,
    InvalidFeed,
    InvalidXml,
    MissingStableIdentity,
};

pub const ParsedFeed = domain.NoticeList;

const FeedKind = enum { rss, atom };

pub fn parse(
    allocator: std.mem.Allocator,
    source: []const u8,
    body: []const u8,
    fetched_at_unix: i64,
) Error!ParsedFeed {
    if (body.len > domain.max_feed_bytes) return Error.FeedTooLarge;
    if (!std.unicode.utf8ValidateSlice(body)) return Error.InvalidXml;
    if (domain.trim(source).len == 0) return Error.EmptySource;
    if (source.len > domain.max_source_bytes) return Error.FieldTooLong;
    if (fetched_at_unix < 0) return Error.InvalidTimestamp;

    const kind: FeedKind = if (findOpenTag(body, 0, "rss") != null or
        findOpenTag(body, 0, "channel") != null)
        .rss
    else if (findOpenTag(body, 0, "feed") != null)
        .atom
    else
        return Error.InvalidFeed;
    const entry_tag = if (kind == .rss) "item" else "entry";

    var notices: std.ArrayList(domain.OwnedNotice) = .empty;
    errdefer {
        for (notices.items) |*notice| notice.deinit(allocator);
        notices.deinit(allocator);
    }

    var cursor: usize = 0;
    var observed_entries: usize = 0;
    while (try nextElement(body, cursor, entry_tag)) |entry| {
        cursor = entry.after;
        observed_entries += 1;
        if (observed_entries > domain.max_feed_entries) {
            return Error.TooManyEntries;
        }

        var notice = try parseEntry(
            allocator,
            source,
            entry.inner,
            kind,
            fetched_at_unix,
        );
        errdefer notice.deinit(allocator);

        if (findIdentity(notices.items, notice.write())) |index| {
            notices.items[index].deinit(allocator);
            notices.items[index] = notice;
        } else {
            try notices.append(allocator, notice);
        }
    }

    return .{ .items = try notices.toOwnedSlice(allocator) };
}

fn parseEntry(
    allocator: std.mem.Allocator,
    source: []const u8,
    entry: []const u8,
    kind: FeedKind,
    fetched_at_unix: i64,
) Error!domain.OwnedNotice {
    const title = (try normalizedElement(
        allocator,
        entry,
        &.{"title"},
        domain.max_title_bytes,
    )) orelse return Error.EmptyTitle;
    defer allocator.free(title);

    const summary = (try normalizedElement(
        allocator,
        entry,
        if (kind == .rss)
            &.{ "description", "content:encoded", "summary" }
        else
            &.{ "summary", "content" },
        domain.max_summary_bytes,
    )) orelse try allocator.dupe(u8, "");
    defer allocator.free(summary);

    const explicit_id = try normalizedElement(
        allocator,
        entry,
        if (kind == .rss) &.{"guid"} else &.{"id"},
        domain.max_external_id_bytes,
    );
    defer if (explicit_id) |value| allocator.free(value);

    const url = try parseLink(allocator, entry, kind);
    defer if (url) |value| allocator.free(value);

    const external_id = explicit_id orelse url orelse
        return Error.MissingStableIdentity;

    const timestamp_text = try normalizedElement(
        allocator,
        entry,
        if (kind == .rss)
            &.{ "pubDate", "dc:date", "published", "updated" }
        else
            &.{ "published", "updated" },
        128,
    );
    defer if (timestamp_text) |value| allocator.free(value);
    const published_at_unix = if (timestamp_text) |value|
        parseTimestamp(value) catch fetched_at_unix
    else
        fetched_at_unix;

    return domain.OwnedNotice.init(allocator, .{
        .source = source,
        .external_id = external_id,
        .title = title,
        .summary = summary,
        .url = url,
        .published_at_unix = published_at_unix,
        .fetched_at_unix = fetched_at_unix,
    });
}

fn parseLink(
    allocator: std.mem.Allocator,
    entry: []const u8,
    kind: FeedKind,
) Error!?[]u8 {
    if (kind == .rss) {
        return normalizedElement(
            allocator,
            entry,
            &.{"link"},
            domain.max_url_bytes,
        );
    }

    var cursor: usize = 0;
    while (findOpenTag(entry, cursor, "link")) |open| {
        const tag_end = std.mem.indexOfScalarPos(u8, entry, open, '>') orelse
            return Error.InvalidXml;
        const opening = entry[open .. tag_end + 1];
        cursor = tag_end + 1;
        const relation = attributeValue(opening, "rel");
        if (relation != null and
            !std.ascii.eqlIgnoreCase(domain.trim(relation.?), "alternate"))
        {
            continue;
        }
        const href = attributeValue(opening, "href") orelse continue;
        return try normalizeAttribute(
            allocator,
            href,
            domain.max_url_bytes,
        );
    }

    return normalizedElement(
        allocator,
        entry,
        &.{"link"},
        domain.max_url_bytes,
    );
}

fn findIdentity(
    items: []const domain.OwnedNotice,
    candidate: domain.NoticeWrite,
) ?usize {
    for (items, 0..) |*item, index| {
        if (domain.identityEqual(item.write(), candidate)) return index;
    }
    return null;
}

const Element = struct {
    inner: []const u8,
    after: usize,
};

fn nextElement(
    xml: []const u8,
    from: usize,
    tag: []const u8,
) Error!?Element {
    const open = findOpenTag(xml, from, tag) orelse return null;
    const open_end = std.mem.indexOfScalarPos(u8, xml, open, '>') orelse
        return Error.InvalidXml;
    if (open_end > open and xml[open_end - 1] == '/') {
        return .{ .inner = "", .after = open_end + 1 };
    }

    var closing_buffer: [96]u8 = undefined;
    const closing = std.fmt.bufPrint(&closing_buffer, "</{s}>", .{tag}) catch
        return Error.InvalidXml;
    const close = std.mem.indexOfPos(u8, xml, open_end + 1, closing) orelse
        return Error.InvalidXml;
    return .{
        .inner = xml[open_end + 1 .. close],
        .after = close + closing.len,
    };
}

fn findOpenTag(
    xml: []const u8,
    from: usize,
    tag: []const u8,
) ?usize {
    var cursor = from;
    while (std.mem.indexOfScalarPos(u8, xml, cursor, '<')) |index| {
        const name_start = index + 1;
        if (name_start + tag.len <= xml.len and
            std.mem.eql(u8, xml[name_start .. name_start + tag.len], tag))
        {
            const after = name_start + tag.len;
            if (after < xml.len and isTagDelimiter(xml[after])) return index;
        }
        cursor = index + 1;
    }
    return null;
}

fn isTagDelimiter(byte: u8) bool {
    return byte == '>' or byte == '/' or std.ascii.isWhitespace(byte);
}

fn normalizedElement(
    allocator: std.mem.Allocator,
    xml: []const u8,
    tags: []const []const u8,
    maximum: usize,
) Error!?[]u8 {
    for (tags) |tag| {
        const element = try nextElement(xml, 0, tag) orelse continue;
        return try normalizeXmlText(allocator, element.inner, maximum);
    }
    return null;
}

fn attributeValue(tag: []const u8, wanted: []const u8) ?[]const u8 {
    var cursor: usize = 1;
    while (cursor < tag.len) {
        while (cursor < tag.len and
            (std.ascii.isWhitespace(tag[cursor]) or tag[cursor] == '/'))
        {
            cursor += 1;
        }
        const name_start = cursor;
        while (cursor < tag.len and
            (std.ascii.isAlphanumeric(tag[cursor]) or
                tag[cursor] == '_' or tag[cursor] == '-' or
                tag[cursor] == ':'))
        {
            cursor += 1;
        }
        if (cursor == name_start) {
            cursor += 1;
            continue;
        }
        const name = tag[name_start..cursor];
        while (cursor < tag.len and std.ascii.isWhitespace(tag[cursor])) {
            cursor += 1;
        }
        if (cursor >= tag.len or tag[cursor] != '=') continue;
        cursor += 1;
        while (cursor < tag.len and std.ascii.isWhitespace(tag[cursor])) {
            cursor += 1;
        }
        if (cursor >= tag.len or (tag[cursor] != '\'' and tag[cursor] != '"')) {
            continue;
        }
        const quote = tag[cursor];
        cursor += 1;
        const value_start = cursor;
        const value_end = std.mem.indexOfScalarPos(u8, tag, cursor, quote) orelse
            return null;
        cursor = value_end + 1;
        if (std.ascii.eqlIgnoreCase(name, wanted)) {
            return tag[value_start..value_end];
        }
    }
    return null;
}

fn normalizeAttribute(
    allocator: std.mem.Allocator,
    raw: []const u8,
    maximum: usize,
) Error![]u8 {
    return normalizeText(allocator, raw, maximum, false);
}

fn normalizeXmlText(
    allocator: std.mem.Allocator,
    raw_value: []const u8,
    maximum: usize,
) Error![]u8 {
    var raw = domain.trim(raw_value);
    if (std.mem.startsWith(u8, raw, "<![CDATA[") and
        std.mem.endsWith(u8, raw, "]]>") and raw.len >= 12)
    {
        raw = raw[9 .. raw.len - 3];
    }
    return normalizeText(allocator, raw, maximum, true);
}

fn normalizeText(
    allocator: std.mem.Allocator,
    raw: []const u8,
    maximum: usize,
    strip_tags: bool,
) Error![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var cursor: usize = 0;
    var pending_space = false;
    while (cursor < raw.len) {
        if (strip_tags and raw[cursor] == '<') {
            const end = std.mem.indexOfScalarPos(u8, raw, cursor, '>') orelse
                return Error.InvalidXml;
            cursor = end + 1;
            pending_space = output.items.len != 0;
            continue;
        }

        if (std.ascii.isWhitespace(raw[cursor])) {
            pending_space = output.items.len != 0;
            cursor += 1;
            continue;
        }

        if (pending_space) {
            try appendBounded(allocator, &output, " ", maximum);
            pending_space = false;
        }

        if (raw[cursor] == '&') {
            if (std.mem.indexOfScalarPos(u8, raw, cursor + 1, ';')) |end| {
                if (try decodeEntity(
                    allocator,
                    &output,
                    raw[cursor + 1 .. end],
                    maximum,
                )) {
                    cursor = end + 1;
                    continue;
                }
            }
        }

        try appendBounded(allocator, &output, raw[cursor .. cursor + 1], maximum);
        cursor += 1;
    }

    return output.toOwnedSlice(allocator);
}

fn decodeEntity(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    entity: []const u8,
    maximum: usize,
) Error!bool {
    const replacement: ?[]const u8 = if (std.mem.eql(u8, entity, "amp"))
        "&"
    else if (std.mem.eql(u8, entity, "lt"))
        "<"
    else if (std.mem.eql(u8, entity, "gt"))
        ">"
    else if (std.mem.eql(u8, entity, "quot"))
        "\""
    else if (std.mem.eql(u8, entity, "apos"))
        "'"
    else
        null;
    if (replacement) |bytes| {
        try appendBounded(allocator, output, bytes, maximum);
        return true;
    }

    if (entity.len >= 2 and entity[0] == '#') {
        const hexadecimal = entity.len >= 3 and
            (entity[1] == 'x' or entity[1] == 'X');
        const digits = if (hexadecimal) entity[2..] else entity[1..];
        if (digits.len == 0) return false;
        const codepoint = std.fmt.parseInt(
            u21,
            digits,
            if (hexadecimal) 16 else 10,
        ) catch return false;
        var encoded: [4]u8 = undefined;
        const encoded_len = std.unicode.utf8Encode(codepoint, &encoded) catch
            return false;
        try appendBounded(
            allocator,
            output,
            encoded[0..encoded_len],
            maximum,
        );
        return true;
    }
    return false;
}

fn appendBounded(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    bytes: []const u8,
    maximum: usize,
) Error!void {
    if (output.items.len > maximum or bytes.len > maximum - output.items.len) {
        return Error.FieldTooLong;
    }
    try output.appendSlice(allocator, bytes);
}

pub fn parseTimestamp(value: []const u8) error{InvalidTimestamp}!i64 {
    const text = domain.trim(value);
    if (text.len >= 10 and text[4] == '-' and text[7] == '-') {
        return parseIso8601(text);
    }
    return parseRfc822(text);
}

fn parseIso8601(text: []const u8) error{InvalidTimestamp}!i64 {
    if (text.len < 10) return error.InvalidTimestamp;
    const year = try parseDecimal(u16, text[0..4]);
    const month = try parseDecimal(u8, text[5..7]);
    const day = try parseDecimal(u8, text[8..10]);
    if (text.len == 10) return civilToUnix(year, month, day, 0, 0, 0, 0);
    if (text.len < 19 or (text[10] != 'T' and text[10] != 't' and
        text[10] != ' ')) return error.InvalidTimestamp;
    const hour = try parseDecimal(u8, text[11..13]);
    const minute = try parseDecimal(u8, text[14..16]);
    const second = try parseDecimal(u8, text[17..19]);

    var zone_index: usize = 19;
    if (zone_index < text.len and text[zone_index] == '.') {
        zone_index += 1;
        const fraction_start = zone_index;
        while (zone_index < text.len and std.ascii.isDigit(text[zone_index])) {
            zone_index += 1;
        }
        if (zone_index == fraction_start) return error.InvalidTimestamp;
    }
    const offset = try parseZone(text[zone_index..]);
    return civilToUnix(year, month, day, hour, minute, second, offset);
}

fn parseRfc822(text: []const u8) error{InvalidTimestamp}!i64 {
    var rest = text;
    if (std.mem.indexOfScalar(u8, rest, ',')) |comma| rest = rest[comma + 1 ..];
    rest = domain.trim(rest);

    var fields: [5][]const u8 = undefined;
    var count: usize = 0;
    var iterator = std.mem.tokenizeAny(u8, rest, " \t");
    while (iterator.next()) |field| {
        if (count == fields.len) return error.InvalidTimestamp;
        fields[count] = field;
        count += 1;
    }
    if (count != fields.len) return error.InvalidTimestamp;

    const day = try parseDecimal(u8, fields[0]);
    const month = parseMonth(fields[1]) orelse return error.InvalidTimestamp;
    const year = try parseDecimal(u16, fields[2]);

    var time_fields = std.mem.splitScalar(u8, fields[3], ':');
    const hour = try parseDecimal(u8, time_fields.next() orelse
        return error.InvalidTimestamp);
    const minute = try parseDecimal(u8, time_fields.next() orelse
        return error.InvalidTimestamp);
    const second = try parseDecimal(u8, time_fields.next() orelse
        return error.InvalidTimestamp);
    if (time_fields.next() != null) return error.InvalidTimestamp;

    return civilToUnix(
        year,
        month,
        day,
        hour,
        minute,
        second,
        try parseZone(fields[4]),
    );
}

fn parseZone(value: []const u8) error{InvalidTimestamp}!i32 {
    if (value.len == 0 or std.ascii.eqlIgnoreCase(value, "Z") or
        std.ascii.eqlIgnoreCase(value, "GMT") or
        std.ascii.eqlIgnoreCase(value, "UTC")) return 0;
    if (value[0] != '+' and value[0] != '-') return error.InvalidTimestamp;

    const sign: i32 = if (value[0] == '+') 1 else -1;
    const hour: u8 = if (value.len == 5)
        try parseDecimal(u8, value[1..3])
    else if (value.len == 6 and value[3] == ':')
        try parseDecimal(u8, value[1..3])
    else
        return error.InvalidTimestamp;
    const minute: u8 = if (value.len == 5)
        try parseDecimal(u8, value[3..5])
    else
        try parseDecimal(u8, value[4..6]);
    if (hour > 23 or minute > 59) return error.InvalidTimestamp;
    return sign * (@as(i32, hour) * 3600 + @as(i32, minute) * 60);
}

fn parseMonth(value: []const u8) ?u8 {
    const names = [_][]const u8{
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };
    for (names, 1..) |name, month| {
        if (std.ascii.eqlIgnoreCase(value, name)) return @intCast(month);
    }
    return null;
}

fn parseDecimal(comptime T: type, value: []const u8) error{InvalidTimestamp}!T {
    if (value.len == 0) return error.InvalidTimestamp;
    return std.fmt.parseInt(T, value, 10) catch error.InvalidTimestamp;
}

fn civilToUnix(
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    timezone_offset_seconds: i32,
) error{InvalidTimestamp}!i64 {
    if (year < 1970 or month < 1 or month > 12 or day < 1 or
        day > daysInMonth(year, month) or hour > 23 or minute > 59 or
        second > 60) return error.InvalidTimestamp;

    var adjusted_year: i64 = year;
    if (month <= 2) adjusted_year -= 1;
    const era = @divFloor(adjusted_year, 400);
    const year_of_era = adjusted_year - era * 400;
    const adjusted_month: i64 = @as(i64, month) +
        (if (month > 2) @as(i64, -3) else @as(i64, 9));
    const day_of_year = @divFloor(153 * adjusted_month + 2, 5) + day - 1;
    const day_of_era = year_of_era * 365 + @divFloor(year_of_era, 4) -
        @divFloor(year_of_era, 100) + day_of_year;
    const days = era * 146_097 + day_of_era - 719_468;
    return days * 86_400 + @as(i64, hour) * 3600 +
        @as(i64, minute) * 60 + second - timezone_offset_seconds;
}

fn daysInMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

fn isLeapYear(year: u16) bool {
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
}

test "RSS fixture parses CDATA entities stable ids and timezone" {
    const allocator = std.testing.allocator;
    const fixture =
        \\<?xml version="1.0"?>
        \\<rss version="2.0"><channel>
        \\  <item>
        \\    <guid isPermaLink="false">notice-1382</guid>
        \\    <title><![CDATA[Proclamation &amp; Notice]]></title>
        \\    <description><![CDATA[<p>Public&nbsp; update</p>]]></description>
        \\    <link>https://example.test/notices/1382</link>
        \\    <pubDate>Thu, 01 Jan 1970 08:00:00 +0800</pubDate>
        \\  </item>
        \\</channel></rss>
    ;
    var parsed = try parse(allocator, "Official Gazette", fixture, 100);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), parsed.items.len);
    try std.testing.expectEqualStrings("notice-1382", parsed.items[0].external_id);
    try std.testing.expectEqualStrings("Proclamation & Notice", parsed.items[0].title);
    // Unknown HTML entities remain visible rather than being silently dropped.
    try std.testing.expectEqualStrings("Public&nbsp; update", parsed.items[0].summary);
    try std.testing.expectEqual(@as(i64, 0), parsed.items[0].published_at_unix);
}

test "Atom fixture chooses alternate link and deduplicates repeated id" {
    const allocator = std.testing.allocator;
    const fixture =
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <entry>
        \\    <id>tag:example.test,2026:item-1</id>
        \\    <title>Original title</title>
        \\    <summary>First summary</summary>
        \\    <link rel="self" href="https://example.test/feed/item-1" />
        \\    <link rel="alternate" href="https://example.test/item-1?x=1&amp;y=2" />
        \\    <updated>1970-01-01T00:00:00Z</updated>
        \\  </entry>
        \\  <entry>
        \\    <id>tag:example.test,2026:item-1</id>
        \\    <title>Corrected title</title>
        \\    <link href="https://example.test/item-1" />
        \\    <updated>1970-01-01T00:00:01Z</updated>
        \\  </entry>
        \\</feed>
    ;
    var parsed = try parse(allocator, "Agency feed", fixture, 100);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), parsed.items.len);
    try std.testing.expectEqualStrings("Corrected title", parsed.items[0].title);
    try std.testing.expectEqualStrings("https://example.test/item-1", parsed.items[0].url.?);
    try std.testing.expectEqual(@as(i64, 1), parsed.items[0].published_at_unix);
}

test "parser rejects oversized feeds and entries without stable identity" {
    const allocator = std.testing.allocator;
    const oversized = try allocator.alloc(u8, domain.max_feed_bytes + 1);
    defer allocator.free(oversized);
    @memset(oversized, 'x');
    try std.testing.expectError(
        Error.FeedTooLarge,
        parse(allocator, "Agency", oversized, 1),
    );

    try std.testing.expectError(
        Error.MissingStableIdentity,
        parse(
            allocator,
            "Agency",
            "<rss><channel><item><title>No id</title></item></channel></rss>",
            1,
        ),
    );
}

test "parser rejects feeds beyond the bounded entry count" {
    const allocator = std.testing.allocator;
    var fixture: std.ArrayList(u8) = .empty;
    defer fixture.deinit(allocator);
    try fixture.appendSlice(allocator, "<rss><channel>");
    var index: usize = 0;
    while (index <= domain.max_feed_entries) : (index += 1) {
        const item = try std.fmt.allocPrint(
            allocator,
            "<item><guid>id-{d}</guid><title>Item {d}</title></item>",
            .{ index, index },
        );
        defer allocator.free(item);
        try fixture.appendSlice(allocator, item);
    }
    try fixture.appendSlice(allocator, "</channel></rss>");

    try std.testing.expectError(
        Error.TooManyEntries,
        parse(allocator, "Agency", fixture.items, 1),
    );
}

test "timestamp parser handles leap days and rejects impossible dates" {
    try std.testing.expectEqual(
        @as(i64, 0),
        try parseTimestamp("1970-01-01T00:00:00Z"),
    );
    try std.testing.expectEqual(
        try parseTimestamp("Thu, 01 Jan 1970 08:00:00 +0800"),
        try parseTimestamp("1970-01-01T00:00:00Z"),
    );
    _ = try parseTimestamp("2024-02-29T23:59:59+08:00");
    try std.testing.expectError(
        error.InvalidTimestamp,
        parseTimestamp("2026-02-29T00:00:00Z"),
    );
}
