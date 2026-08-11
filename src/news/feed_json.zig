//! Bounded adapter for the compiled BIR news feed (`schema_version` 1).
//!
//! The feed carries two independent payloads: public notices for the Important
//! News pane and deadline-override records for the calendar policy store. Both
//! are validated fail-closed here, because everything downstream of this
//! boundary treats the values as trusted: notices go through
//! `domain.NoticeWrite.validate`, every collection has an explicit maximum, and
//! oversized bodies are refused before a single byte is allocated.
//!
//! Unknown object fields are ignored so the publisher can extend the feed
//! without breaking installed builds. Unknown *shapes* — a string where an
//! integer belongs, a missing required field — are refused.
//!
//! Override dates are carried as validated `YYYY-MM-DD` strings rather than
//! calendar values: the news boundary must not depend on `src/calendar/`. The
//! strings are proven to be real civil dates before they leave this module.

const std = @import("std");
const domain = @import("domain.zig");

pub const supported_schema_version: i64 = 1;

pub const max_overrides: usize = 64;
pub const max_form_codes: usize = 32;
pub const max_rdo_codes: usize = 200;
pub const max_external_ref_bytes: usize = 512;
pub const max_source_reference_bytes: usize = 256;
pub const max_channel_bytes: usize = 32;
pub const max_scope_value_bytes: usize = 32;
/// A Revenue District Office code, and never a district name: every code in
/// the canonical reference is three characters (`039`, `17A`, `53B`). The
/// bound is held well below `max_scope_value_bytes` because the calendar
/// reserves storage for `max_rdo_codes` of them on every override row, so a
/// generous scope bound here costs kilobytes there for values that cannot
/// occur. A longer value is refused rather than stored as an unmatchable
/// scope.
pub const max_rdo_code_bytes: usize = 8;

const date_length: usize = 10;

pub const Error = domain.Error || std.mem.Allocator.Error || error{
    FeedTooLarge,
    InvalidJson,
    InvalidFeed,
    UnsupportedSchemaVersion,
    TooManyEntries,
    TooManyOverrides,
    TooManyScopeValues,
    EmptyRdoScope,
    InvalidDate,
    DeadlineOutOfOrder,
};

/// Allocator-owned deadline override published alongside the notices.
///
/// `original_deadline` and `adjusted_deadline` are validated civil dates in
/// `YYYY-MM-DD` form with `adjusted_deadline` never earlier than
/// `original_deadline`. `rdo_codes` is never empty: an override with no scope
/// would silently become a nationwide rule.
pub const OverrideRecord = struct {
    external_ref: []u8,
    title: []u8,
    source_reference: []u8,
    original_deadline: []u8,
    adjusted_deadline: []u8,
    channel: []u8,
    notice_external_id: []u8,
    form_codes: [][]u8,
    rdo_codes: [][]u8,

    pub fn deinit(self: *OverrideRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.external_ref);
        allocator.free(self.title);
        allocator.free(self.source_reference);
        allocator.free(self.original_deadline);
        allocator.free(self.adjusted_deadline);
        allocator.free(self.channel);
        allocator.free(self.notice_external_id);
        freeTextList(allocator, self.form_codes);
        freeTextList(allocator, self.rdo_codes);
        self.* = undefined;
    }
};

pub const OverrideRecordList = struct {
    items: []OverrideRecord,

    pub fn deinit(self: *OverrideRecordList, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Parsed = struct {
    notices: domain.NoticeList,
    overrides: OverrideRecordList,

    pub fn deinit(self: *Parsed, allocator: std.mem.Allocator) void {
        self.notices.deinit(allocator);
        self.overrides.deinit(allocator);
        self.* = undefined;
    }
};

/// Parses one compiled feed document. `source_label` becomes the notice source
/// half of the `(source, external_id)` identity; the feed's own `source_label`
/// field is advisory and never overrides the caller.
pub fn parse(
    allocator: std.mem.Allocator,
    source_label: []const u8,
    body: []const u8,
    fetched_at_unix: i64,
) Error!Parsed {
    if (body.len > domain.max_feed_bytes) return Error.FeedTooLarge;
    if (!std.unicode.utf8ValidateSlice(body)) return Error.InvalidJson;
    if (domain.trim(source_label).len == 0) return Error.EmptySource;
    if (source_label.len > domain.max_source_bytes) return Error.FieldTooLong;
    if (fetched_at_unix < 0) return Error.InvalidTimestamp;

    // The scratch arena holds the decoded document only; every value handed
    // back to the caller is duplicated into the caller's allocator.
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();

    const document = std.json.parseFromSliceLeaky(
        std.json.Value,
        scratch.allocator(),
        body,
        .{ .duplicate_field_behavior = .@"error" },
    ) catch |err| switch (err) {
        error.OutOfMemory => return Error.OutOfMemory,
        else => return Error.InvalidJson,
    };

    const root = try expectObject(document);
    if (try requiredInteger(root, "schema_version") != supported_schema_version) {
        return Error.UnsupportedSchemaVersion;
    }

    const notice_values = try requiredArray(root, "notices");
    if (notice_values.len > domain.max_notices) return Error.TooManyEntries;
    const override_values = try requiredArray(root, "overrides");
    if (override_values.len > max_overrides) return Error.TooManyOverrides;

    var notices: std.ArrayList(domain.OwnedNotice) = .empty;
    errdefer {
        for (notices.items) |*notice| notice.deinit(allocator);
        notices.deinit(allocator);
    }
    try notices.ensureTotalCapacityPrecise(allocator, notice_values.len);
    for (notice_values) |value| {
        var notice = try parseNotice(
            allocator,
            source_label,
            try expectObject(value),
            fetched_at_unix,
        );
        errdefer notice.deinit(allocator);

        // A publisher correction can restate the same identity; the later
        // entry wins so the batch never carries two rows of one identity.
        if (findIdentity(notices.items, notice.write())) |index| {
            notices.items[index].deinit(allocator);
            notices.items[index] = notice;
        } else {
            notices.appendAssumeCapacity(notice);
        }
    }

    var overrides: std.ArrayList(OverrideRecord) = .empty;
    errdefer {
        for (overrides.items) |*record| record.deinit(allocator);
        overrides.deinit(allocator);
    }
    try overrides.ensureTotalCapacityPrecise(allocator, override_values.len);
    for (override_values) |value| {
        overrides.appendAssumeCapacity(
            try parseOverride(allocator, try expectObject(value)),
        );
    }

    const owned_notices = try notices.toOwnedSlice(allocator);
    errdefer {
        for (owned_notices) |*notice| notice.deinit(allocator);
        allocator.free(owned_notices);
    }
    return .{
        .notices = .{ .items = owned_notices },
        .overrides = .{ .items = try overrides.toOwnedSlice(allocator) },
    };
}

fn parseNotice(
    allocator: std.mem.Allocator,
    source_label: []const u8,
    object: std.json.ObjectMap,
    fetched_at_unix: i64,
) Error!domain.OwnedNotice {
    // Absent identity and title reach `NoticeWrite.validate` as empty strings
    // so the rejection carries the same named error as a blank one.
    return domain.OwnedNotice.init(allocator, .{
        .source = source_label,
        .external_id = try optionalString(object, "external_id") orelse "",
        .title = try optionalString(object, "title") orelse "",
        .summary = try optionalString(object, "summary") orelse "",
        .url = try optionalString(object, "url"),
        .published_at_unix = try requiredInteger(object, "published_at_unix"),
        .fetched_at_unix = fetched_at_unix,
    });
}

fn parseOverride(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
) Error!OverrideRecord {
    // `parseCivilDate` is its own bound: it accepts exactly ten ASCII bytes,
    // so no length or encoding check has to precede it.
    const original_text = domain.trim(
        try requiredString(object, "original_deadline"),
    );
    const adjusted_text = domain.trim(
        try requiredString(object, "adjusted_deadline"),
    );
    const original_date = try parseCivilDate(original_text);
    const adjusted_date = try parseCivilDate(adjusted_text);
    if (adjusted_date.isBefore(original_date)) return Error.DeadlineOutOfOrder;

    const external_ref = try dupeRequiredText(
        allocator,
        object,
        "external_ref",
        max_external_ref_bytes,
    );
    errdefer allocator.free(external_ref);
    const title = try dupeRequiredText(
        allocator,
        object,
        "title",
        domain.max_title_bytes,
    );
    errdefer allocator.free(title);
    const source_reference = try dupeRequiredText(
        allocator,
        object,
        "source_reference",
        max_source_reference_bytes,
    );
    errdefer allocator.free(source_reference);
    const original_deadline = try allocator.dupe(u8, original_text);
    errdefer allocator.free(original_deadline);
    const adjusted_deadline = try allocator.dupe(u8, adjusted_text);
    errdefer allocator.free(adjusted_deadline);
    const channel = try dupeRequiredText(
        allocator,
        object,
        "channel",
        max_channel_bytes,
    );
    errdefer allocator.free(channel);
    const notice_external_id = try dupeRequiredText(
        allocator,
        object,
        "notice_external_id",
        domain.max_external_id_bytes,
    );
    errdefer allocator.free(notice_external_id);
    const form_codes = try dupeScopeList(
        allocator,
        object,
        "form_codes",
        max_form_codes,
        max_scope_value_bytes,
    );
    errdefer freeTextList(allocator, form_codes);
    const rdo_codes = try dupeScopeList(
        allocator,
        object,
        "rdo_codes",
        max_rdo_codes,
        max_rdo_code_bytes,
    );
    errdefer freeTextList(allocator, rdo_codes);
    if (rdo_codes.len == 0) return Error.EmptyRdoScope;

    return .{
        .external_ref = external_ref,
        .title = title,
        .source_reference = source_reference,
        .original_deadline = original_deadline,
        .adjusted_deadline = adjusted_deadline,
        .channel = channel,
        .notice_external_id = notice_external_id,
        .form_codes = form_codes,
        .rdo_codes = rdo_codes,
    };
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

fn expectObject(value: std.json.Value) Error!std.json.ObjectMap {
    return switch (value) {
        .object => |object| object,
        else => Error.InvalidFeed,
    };
}

fn requiredInteger(object: std.json.ObjectMap, name: []const u8) Error!i64 {
    return switch (object.get(name) orelse return Error.InvalidFeed) {
        .integer => |value| value,
        else => Error.InvalidFeed,
    };
}

fn requiredArray(
    object: std.json.ObjectMap,
    name: []const u8,
) Error![]const std.json.Value {
    return switch (object.get(name) orelse return Error.InvalidFeed) {
        .array => |value| value.items,
        else => Error.InvalidFeed,
    };
}

fn requiredString(
    object: std.json.ObjectMap,
    name: []const u8,
) Error![]const u8 {
    return switch (object.get(name) orelse return Error.InvalidFeed) {
        .string => |text| text,
        else => Error.InvalidFeed,
    };
}

/// An absent field and an explicit `null` are the same absence; any other type
/// is a contract violation rather than a missing value.
fn optionalString(
    object: std.json.ObjectMap,
    name: []const u8,
) Error!?[]const u8 {
    return switch (object.get(name) orelse return null) {
        .string => |text| text,
        .null => null,
        else => Error.InvalidFeed,
    };
}

fn boundedText(raw: []const u8, maximum: usize) Error![]const u8 {
    const text = domain.trim(raw);
    if (text.len == 0) return Error.InvalidFeed;
    if (text.len > maximum) return Error.FieldTooLong;
    if (!std.unicode.utf8ValidateSlice(text)) return Error.InvalidUtf8;
    return text;
}

fn dupeRequiredText(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    name: []const u8,
    maximum: usize,
) Error![]u8 {
    const text = try boundedText(try requiredString(object, name), maximum);
    return allocator.dupe(u8, text);
}

fn dupeScopeList(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    name: []const u8,
    maximum: usize,
    value_maximum: usize,
) Error![][]u8 {
    const values = try requiredArray(object, name);
    if (values.len > maximum) return Error.TooManyScopeValues;

    const items = try allocator.alloc([]u8, values.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |item| allocator.free(item);
        allocator.free(items);
    }
    for (values) |value| {
        const raw = switch (value) {
            .string => |text| text,
            else => return Error.InvalidFeed,
        };
        items[filled] = try allocator.dupe(
            u8,
            try boundedText(raw, value_maximum),
        );
        filled += 1;
    }
    return items;
}

fn freeTextList(allocator: std.mem.Allocator, items: [][]u8) void {
    for (items) |item| allocator.free(item);
    allocator.free(items);
}

const CivilDate = struct {
    year: u16,
    month: u8,
    day: u8,

    fn isBefore(self: CivilDate, other: CivilDate) bool {
        if (self.year != other.year) return self.year < other.year;
        if (self.month != other.month) return self.month < other.month;
        return self.day < other.day;
    }
};

/// Strict `YYYY-MM-DD`. Nothing shorter, longer, or differently punctuated is
/// accepted: a partially parsed date would silently move a deadline marker.
fn parseCivilDate(text: []const u8) Error!CivilDate {
    if (text.len != date_length or text[4] != '-' or text[7] != '-') {
        return Error.InvalidDate;
    }
    const year = try parseDateDigits(u16, text[0..4]);
    const month = try parseDateDigits(u8, text[5..7]);
    const day = try parseDateDigits(u8, text[8..10]);
    if (month < 1 or month > 12) return Error.InvalidDate;
    if (day < 1 or day > daysInMonth(year, month)) return Error.InvalidDate;
    return .{ .year = year, .month = month, .day = day };
}

fn parseDateDigits(comptime T: type, text: []const u8) Error!T {
    for (text) |byte| if (!std.ascii.isDigit(byte)) return Error.InvalidDate;
    return std.fmt.parseInt(T, text, 10) catch Error.InvalidDate;
}

fn daysInMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0))
            29
        else
            28,
        else => 0,
    };
}

// Shapes below are copied from the compiled feed at
// scripts/news-sync/feed/feed.json; only the value lists are trimmed.
const feed_fixture =
    \\{
    \\  "schema_version": 1,
    \\  "generated_at_unix": 1786752000,
    \\  "source_label": "BIR",
    \\  "notices": [
    \\    {
    \\      "external_id": "bir:rmo:2026:019",
    \\      "kind": "RMO",
    \\      "title": "RMO No. 19-2026",
    \\      "summary": "policies, guidelines, and procedures for the Availment of a One-Time Abatement of Taxes and/or Penalties for Micro Taxpayers.",
    \\      "url": "https://bir-cdn.bir.gov.ph/BIR/pdf/RMO%20No.%2019-2026_Redacted.pdf",
    \\      "published_at_unix": 1786752000,
    \\      "month_bucket": "2026-08"
    \\    },
    \\    {
    \\      "external_id": "bir:rmc:2026:089",
    \\      "kind": "RMC",
    \\      "title": "RMC No. 89-2026",
    \\      "summary": "Providing Extension of the Deadlines for the Filing of Tax Retums and Payment of Conesponding Taxes Due Thereon.",
    \\      "url": "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
    \\      "published_at_unix": 1786291200,
    \\      "month_bucket": "2026-08"
    \\    }
    \\  ],
    \\  "overrides": [
    \\    {
    \\      "external_ref": "bir:rmc:2026:089/2026-08-10/nonefps",
    \\      "title": "RMC 89-2026 extension (due 2026-08-10)",
    \\      "source_reference": "RMC No. 89-2026",
    \\      "original_deadline": "2026-08-10",
    \\      "adjusted_deadline": "2026-08-17",
    \\      "form_codes": ["0619E", "0619F", "1601C"],
    \\      "rdo_codes": ["039", "17A", "43B"],
    \\      "channel": "nonefps",
    \\      "notice_external_id": "bir:rmc:2026:089"
    \\    }
    \\  ]
    \\}
;

const notice_fixture =
    \\{"external_id":"bir:rmc:2026:089","title":"RMC No. 89-2026",
    \\ "published_at_unix":1786291200}
;

fn buildFeed(
    allocator: std.mem.Allocator,
    notices_json: []const u8,
    overrides_json: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"schema_version\":1,\"source_label\":\"BIR\"," ++
            "\"notices\":[{s}],\"overrides\":[{s}]}}",
        .{ notices_json, overrides_json },
    );
}

fn buildOverride(
    allocator: std.mem.Allocator,
    original_deadline: []const u8,
    adjusted_deadline: []const u8,
    form_codes_json: []const u8,
    rdo_codes_json: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"external_ref\":\"ref-1\",\"title\":\"Override\"," ++
            "\"source_reference\":\"RMC No. 89-2026\"," ++
            "\"original_deadline\":\"{s}\",\"adjusted_deadline\":\"{s}\"," ++
            "\"form_codes\":[{s}],\"rdo_codes\":[{s}]," ++
            "\"channel\":\"nonefps\"," ++
            "\"notice_external_id\":\"bir:rmc:2026:089\"}}",
        .{
            original_deadline,
            adjusted_deadline,
            form_codes_json,
            rdo_codes_json,
        },
    );
}

fn buildRepeatedJson(
    allocator: std.mem.Allocator,
    element: []const u8,
    times: usize,
) ![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);
    var index: usize = 0;
    while (index < times) : (index += 1) {
        if (index != 0) try buffer.append(allocator, ',');
        try buffer.appendSlice(allocator, element);
    }
    return buffer.toOwnedSlice(allocator);
}

test "compiled feed yields caller-sourced notices and scoped overrides" {
    const allocator = std.testing.allocator;
    var parsed = try parse(allocator, "BIR", feed_fixture, 1_786_760_000);
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), parsed.notices.items.len);
    const notice = parsed.notices.items[1];
    try std.testing.expectEqualStrings("BIR", notice.source);
    try std.testing.expectEqualStrings("bir:rmc:2026:089", notice.external_id);
    try std.testing.expectEqualStrings("RMC No. 89-2026", notice.title);
    try std.testing.expectEqualStrings(
        "https://bir-cdn.bir.gov.ph/BIR/pdf/RMC%20No.%2089-2026_redacted.pdf",
        notice.url.?,
    );
    try std.testing.expectEqual(@as(i64, 1_786_291_200), notice.published_at_unix);
    try std.testing.expectEqual(@as(i64, 1_786_760_000), notice.fetched_at_unix);

    try std.testing.expectEqual(@as(usize, 1), parsed.overrides.items.len);
    const record = parsed.overrides.items[0];
    try std.testing.expectEqualStrings(
        "bir:rmc:2026:089/2026-08-10/nonefps",
        record.external_ref,
    );
    try std.testing.expectEqualStrings("RMC No. 89-2026", record.source_reference);
    try std.testing.expectEqualStrings("2026-08-10", record.original_deadline);
    try std.testing.expectEqualStrings("2026-08-17", record.adjusted_deadline);
    try std.testing.expectEqualStrings("nonefps", record.channel);
    try std.testing.expectEqualStrings(
        "bir:rmc:2026:089",
        record.notice_external_id,
    );
    try std.testing.expectEqual(@as(usize, 3), record.form_codes.len);
    try std.testing.expectEqualStrings("1601C", record.form_codes[2]);
    try std.testing.expectEqual(@as(usize, 3), record.rdo_codes.len);
    try std.testing.expectEqualStrings("17A", record.rdo_codes[1]);
}

test "parser accepts only the schema version it was written against" {
    const allocator = std.testing.allocator;
    const body = try buildFeed(allocator, "", "");
    defer allocator.free(body);
    var empty = try parse(allocator, "BIR", body, 1);
    empty.deinit(allocator);

    for ([_][]const u8{
        "{\"schema_version\":2,\"notices\":[],\"overrides\":[]}",
        "{\"schema_version\":0,\"notices\":[],\"overrides\":[]}",
    }) |unsupported| {
        try std.testing.expectError(
            Error.UnsupportedSchemaVersion,
            parse(allocator, "BIR", unsupported, 1),
        );
    }
    try std.testing.expectError(
        Error.InvalidFeed,
        parse(allocator, "BIR", "{\"notices\":[],\"overrides\":[]}", 1),
    );
    try std.testing.expectError(
        Error.InvalidJson,
        parse(allocator, "BIR", "not json", 1),
    );
}

test "oversized bodies are refused and every notice needs a stable identity" {
    const allocator = std.testing.allocator;
    const oversized = try allocator.alloc(u8, domain.max_feed_bytes + 1);
    defer allocator.free(oversized);
    @memset(oversized, 'x');
    try std.testing.expectError(
        Error.FeedTooLarge,
        parse(allocator, "BIR", oversized, 1),
    );

    const anonymous = try buildFeed(
        allocator,
        "{\"title\":\"No identity\",\"published_at_unix\":0}",
        "",
    );
    defer allocator.free(anonymous);
    try std.testing.expectError(
        Error.EmptyExternalId,
        parse(allocator, "BIR", anonymous, 1),
    );

    const untitled = try buildFeed(
        allocator,
        "{\"external_id\":\"n-1\",\"published_at_unix\":0}",
        "",
    );
    defer allocator.free(untitled);
    try std.testing.expectError(
        Error.EmptyTitle,
        parse(allocator, "BIR", untitled, 1),
    );

    try std.testing.expectError(
        Error.EmptySource,
        parse(allocator, "  ", feed_fixture, 1),
    );
}

test "repeated notice identity keeps the corrected entry" {
    const allocator = std.testing.allocator;
    const body = try buildFeed(
        allocator,
        "{\"external_id\":\"n-1\",\"title\":\"Original\",\"published_at_unix\":10}," ++
            "{\"external_id\":\"n-1\",\"title\":\"Corrected\",\"published_at_unix\":11}",
        "",
    );
    defer allocator.free(body);

    var parsed = try parse(allocator, "BIR", body, 20);
    defer parsed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), parsed.notices.items.len);
    try std.testing.expectEqualStrings("Corrected", parsed.notices.items[0].title);
}

test "unsafe notice URLs are refused rather than stored" {
    const allocator = std.testing.allocator;
    const body = try buildFeed(
        allocator,
        "{\"external_id\":\"n-1\",\"title\":\"Notice\"," ++
            "\"url\":\"javascript:alert(1)\",\"published_at_unix\":0}",
        "",
    );
    defer allocator.free(body);
    try std.testing.expectError(
        Error.InvalidUrl,
        parse(allocator, "BIR", body, 1),
    );

    const without_url = try buildFeed(
        allocator,
        "{\"external_id\":\"n-1\",\"title\":\"Notice\",\"url\":null," ++
            "\"published_at_unix\":0}",
        "",
    );
    defer allocator.free(without_url);
    var parsed = try parse(allocator, "BIR", without_url, 1);
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.notices.items[0].url == null);
}

test "collections beyond their declared bounds are refused" {
    const allocator = std.testing.allocator;

    const notices = try buildRepeatedJson(
        allocator,
        notice_fixture,
        domain.max_notices + 1,
    );
    defer allocator.free(notices);
    const too_many_notices = try buildFeed(allocator, notices, "");
    defer allocator.free(too_many_notices);
    try std.testing.expectError(
        Error.TooManyEntries,
        parse(allocator, "BIR", too_many_notices, 1),
    );

    const one_override = try buildOverride(
        allocator,
        "2026-08-10",
        "2026-08-17",
        "\"1601C\"",
        "\"039\"",
    );
    defer allocator.free(one_override);
    const overrides = try buildRepeatedJson(
        allocator,
        one_override,
        max_overrides + 1,
    );
    defer allocator.free(overrides);
    const too_many_overrides = try buildFeed(allocator, "", overrides);
    defer allocator.free(too_many_overrides);
    try std.testing.expectError(
        Error.TooManyOverrides,
        parse(allocator, "BIR", too_many_overrides, 1),
    );

    const forms = try buildRepeatedJson(allocator, "\"1601C\"", max_form_codes + 1);
    defer allocator.free(forms);
    const too_many_forms_override = try buildOverride(
        allocator,
        "2026-08-10",
        "2026-08-17",
        forms,
        "\"039\"",
    );
    defer allocator.free(too_many_forms_override);
    const too_many_forms = try buildFeed(allocator, "", too_many_forms_override);
    defer allocator.free(too_many_forms);
    try std.testing.expectError(
        Error.TooManyScopeValues,
        parse(allocator, "BIR", too_many_forms, 1),
    );

    const rdos = try buildRepeatedJson(allocator, "\"039\"", max_rdo_codes + 1);
    defer allocator.free(rdos);
    const too_many_rdos_override = try buildOverride(
        allocator,
        "2026-08-10",
        "2026-08-17",
        "\"1601C\"",
        rdos,
    );
    defer allocator.free(too_many_rdos_override);
    const too_many_rdos = try buildFeed(allocator, "", too_many_rdos_override);
    defer allocator.free(too_many_rdos);
    try std.testing.expectError(
        Error.TooManyScopeValues,
        parse(allocator, "BIR", too_many_rdos, 1),
    );
}

test "an override without an RDO scope never becomes a nationwide rule" {
    const allocator = std.testing.allocator;
    const unscoped = try buildOverride(
        allocator,
        "2026-08-10",
        "2026-08-17",
        "\"1601C\"",
        "",
    );
    defer allocator.free(unscoped);
    const body = try buildFeed(allocator, "", unscoped);
    defer allocator.free(body);
    try std.testing.expectError(
        Error.EmptyRdoScope,
        parse(allocator, "BIR", body, 1),
    );
}

test "override dates must be real civil dates in strict YYYY-MM-DD form" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{
        "2026-08-1",
        "2026-8-10",
        "2026/08/10",
        "2026-13-01",
        "2026-02-29",
        "2026-08-00",
        "2026-08-10T00:00:00Z",
        "20260810",
    }) |malformed| {
        const record = try buildOverride(
            allocator,
            malformed,
            "2026-08-17",
            "\"1601C\"",
            "\"039\"",
        );
        defer allocator.free(record);
        const body = try buildFeed(allocator, "", record);
        defer allocator.free(body);
        try std.testing.expectError(
            Error.InvalidDate,
            parse(allocator, "BIR", body, 1),
        );
    }

    const leap_day = try buildOverride(
        allocator,
        "2024-02-29",
        "2024-03-01",
        "\"1601C\"",
        "\"039\"",
    );
    defer allocator.free(leap_day);
    const accepted = try buildFeed(allocator, "", leap_day);
    defer allocator.free(accepted);
    var parsed = try parse(allocator, "BIR", accepted, 1);
    defer parsed.deinit(allocator);
    try std.testing.expectEqualStrings(
        "2024-02-29",
        parsed.overrides.items[0].original_deadline,
    );
}

test "an adjusted deadline may not precede the original deadline" {
    const allocator = std.testing.allocator;
    const backwards = try buildOverride(
        allocator,
        "2026-08-17",
        "2026-08-10",
        "\"1601C\"",
        "\"039\"",
    );
    defer allocator.free(backwards);
    const body = try buildFeed(allocator, "", backwards);
    defer allocator.free(body);
    try std.testing.expectError(
        Error.DeadlineOutOfOrder,
        parse(allocator, "BIR", body, 1),
    );

    // An override that only restates the same day is legitimate: the feed
    // records rows whose printed extended date equals the original.
    const unchanged = try buildOverride(
        allocator,
        "2026-08-17",
        "2026-08-17",
        "\"1601C\"",
        "\"039\"",
    );
    defer allocator.free(unchanged);
    const same_day = try buildFeed(allocator, "", unchanged);
    defer allocator.free(same_day);
    var parsed = try parse(allocator, "BIR", same_day, 1);
    parsed.deinit(allocator);
}

test "unknown fields are ignored while unknown shapes are refused" {
    const allocator = std.testing.allocator;
    const body = try buildFeed(
        allocator,
        "{\"external_id\":\"n-1\",\"title\":\"Notice\"," ++
            "\"published_at_unix\":0,\"future_field\":{\"nested\":[1,2]}}",
        "{\"external_ref\":\"ref-1\",\"title\":\"Override\"," ++
            "\"source_reference\":\"RMC No. 89-2026\"," ++
            "\"original_deadline\":\"2026-08-10\"," ++
            "\"adjusted_deadline\":\"2026-08-17\"," ++
            "\"form_codes\":[\"1601C\"],\"rdo_codes\":[\"039\"]," ++
            "\"channel\":\"nonefps\"," ++
            "\"notice_external_id\":\"bir:rmc:2026:089\"," ++
            "\"confidence\":\"high\",\"notes\":[\"digit normalization\"]}",
    );
    defer allocator.free(body);
    var parsed = try parse(allocator, "BIR", body, 1);
    defer parsed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), parsed.notices.items.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.overrides.items.len);

    const wrong_shape = try buildFeed(
        allocator,
        "{\"external_id\":\"n-1\",\"title\":\"Notice\"," ++
            "\"published_at_unix\":\"0\"}",
        "",
    );
    defer allocator.free(wrong_shape);
    try std.testing.expectError(
        Error.InvalidFeed,
        parse(allocator, "BIR", wrong_shape, 1),
    );
}
