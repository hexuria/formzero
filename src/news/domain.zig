//! Bounded, persistence-neutral model for public Important News notices.
//!
//! Notice identity is the stable `(source, external_id)` pair. Feed adapters
//! must never use a title or publication timestamp as the external id: those
//! values are routinely corrected by publishers and would create duplicates.

const std = @import("std");

pub const max_notices: usize = 120;
pub const max_feed_bytes: usize = 1024 * 1024;
// A single feed may legitimately fill the cache, so one document may carry as
// many entries as the cache retains.
pub const max_feed_entries: usize = max_notices;
pub const max_source_bytes: usize = 96;
pub const max_external_id_bytes: usize = 512;
pub const max_title_bytes: usize = 512;
pub const max_summary_bytes: usize = 4096;
pub const max_url_bytes: usize = 2048;

pub const manila_utc_offset_seconds: i64 = 8 * 3600;

pub const Error = error{
    EmptySource,
    EmptyExternalId,
    EmptyTitle,
    FieldTooLong,
    InvalidUtf8,
    InvalidUrl,
    InvalidTimestamp,
};

/// Borrowed value accepted by the feed and persistence boundaries.
pub const NoticeWrite = struct {
    source: []const u8,
    external_id: []const u8,
    title: []const u8,
    summary: []const u8 = "",
    url: ?[]const u8 = null,
    published_at_unix: i64,
    fetched_at_unix: i64,

    pub fn validate(self: NoticeWrite) Error!void {
        try requireText(self.source, max_source_bytes, Error.EmptySource);
        try requireText(
            self.external_id,
            max_external_id_bytes,
            Error.EmptyExternalId,
        );
        try requireText(self.title, max_title_bytes, Error.EmptyTitle);
        try requireBoundedUtf8(self.summary, max_summary_bytes);

        if (self.url) |url| {
            try requireBoundedUtf8(url, max_url_bytes);
            const trimmed_url = trim(url);
            if (trimmed_url.len == 0 or
                !(std.mem.startsWith(u8, trimmed_url, "https://") or
                    std.mem.startsWith(u8, trimmed_url, "http://")))
            {
                return Error.InvalidUrl;
            }
        }

        if (self.published_at_unix < 0 or self.fetched_at_unix < 0) {
            return Error.InvalidTimestamp;
        }
    }
};

/// Allocator-owned notice returned by parsers and repositories.
pub const OwnedNotice = struct {
    source: []u8,
    external_id: []u8,
    title: []u8,
    summary: []u8,
    url: ?[]u8,
    published_at_unix: i64,
    fetched_at_unix: i64,

    pub fn init(
        allocator: std.mem.Allocator,
        value: NoticeWrite,
    ) !OwnedNotice {
        try value.validate();

        const source = try allocator.dupe(u8, trim(value.source));
        errdefer allocator.free(source);
        const external_id = try allocator.dupe(u8, trim(value.external_id));
        errdefer allocator.free(external_id);
        const title = try allocator.dupe(u8, trim(value.title));
        errdefer allocator.free(title);
        const summary = try allocator.dupe(u8, trim(value.summary));
        errdefer allocator.free(summary);
        const url = if (value.url) |raw|
            try allocator.dupe(u8, trim(raw))
        else
            null;
        errdefer if (url) |bytes| allocator.free(bytes);

        return .{
            .source = source,
            .external_id = external_id,
            .title = title,
            .summary = summary,
            .url = url,
            .published_at_unix = value.published_at_unix,
            .fetched_at_unix = value.fetched_at_unix,
        };
    }

    pub fn write(self: *const OwnedNotice) NoticeWrite {
        return .{
            .source = self.source,
            .external_id = self.external_id,
            .title = self.title,
            .summary = self.summary,
            .url = self.url,
            .published_at_unix = self.published_at_unix,
            .fetched_at_unix = self.fetched_at_unix,
        };
    }

    pub fn deinit(self: *OwnedNotice, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        allocator.free(self.external_id);
        allocator.free(self.title);
        allocator.free(self.summary);
        if (self.url) |url| allocator.free(url);
        self.* = undefined;
    }
};

pub const NoticeList = struct {
    items: []OwnedNotice,

    pub fn deinit(self: *NoticeList, allocator: std.mem.Allocator) void {
        for (self.items) |*item| item.deinit(allocator);
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub fn identityEqual(a: NoticeWrite, b: NoticeWrite) bool {
    return std.mem.eql(u8, trim(a.source), trim(b.source)) and
        std.mem.eql(u8, trim(a.external_id), trim(b.external_id));
}

/// Civil date of `unix_seconds` in Philippine Standard Time.
///
/// PST is a fixed UTC+8 with no daylight saving, so the whole conversion is one
/// floor division followed by the civil-from-days algorithm. Every surface that
/// shows or groups a notice by date must use this rather than a UTC calendar,
/// and never the host timezone: publishers stamp midnight Manila, which is the
/// previous afternoon in UTC, so a UTC reading is a day early and can file a
/// notice under the month before the one its own pane is showing. Two users in
/// different zones also have to see the same notice under the same month.
pub fn manilaCivilDate(unix_seconds: i64) struct {
    year: i32,
    month: u8,
    day: u8,
} {
    const days = @divFloor(unix_seconds + manila_utc_offset_seconds, 86_400);
    const shifted_days = days + 719_468;
    const era = @divFloor(shifted_days, 146_097);
    const day_of_era = shifted_days - era * 146_097;
    const year_of_era = @divFloor(
        day_of_era - @divFloor(day_of_era, 1_460) +
            @divFloor(day_of_era, 36_524) - @divFloor(day_of_era, 146_096),
        365,
    );
    const day_of_year = day_of_era - (365 * year_of_era +
        @divFloor(year_of_era, 4) - @divFloor(year_of_era, 100));
    const month_index = @divFloor(5 * day_of_year + 2, 153);
    const month = month_index + (if (month_index < 10)
        @as(i64, 3)
    else
        @as(i64, -9));
    const year = year_of_era + era * 400 + @as(i64, if (month <= 2) 1 else 0);
    const day = day_of_year - @divFloor(153 * month_index + 2, 5) + 1;
    return .{
        .year = @intCast(year),
        .month = @intCast(month),
        .day = @intCast(day),
    };
}

pub fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn requireText(
    value: []const u8,
    maximum: usize,
    empty_error: Error,
) Error!void {
    try requireBoundedUtf8(value, maximum);
    if (trim(value).len == 0) return empty_error;
}

fn requireBoundedUtf8(value: []const u8, maximum: usize) Error!void {
    if (value.len > maximum) return Error.FieldTooLong;
    if (!std.unicode.utf8ValidateSlice(value)) return Error.InvalidUtf8;
}

test "notice validation requires stable bounded identity and safe URLs" {
    const valid = NoticeWrite{
        .source = "Official Gazette",
        .external_id = "urn:notice:1382-2026",
        .title = "Proclamation No. 1382 s. 2026",
        .summary = "Public holiday announcement.",
        .url = "https://example.test/notices/1382",
        .published_at_unix = 1_785_433_200,
        .fetched_at_unix = 1_785_436_800,
    };
    try valid.validate();

    var missing_identity = valid;
    missing_identity.external_id = " \t";
    try std.testing.expectError(Error.EmptyExternalId, missing_identity.validate());

    var unsafe_url = valid;
    unsafe_url.url = "javascript:alert(1)";
    try std.testing.expectError(Error.InvalidUrl, unsafe_url.validate());
}

test "owned notice normalizes outer whitespace and preserves identity" {
    const allocator = std.testing.allocator;
    var owned = try OwnedNotice.init(allocator, .{
        .source = " Feed A ",
        .external_id = " item-1\n",
        .title = " Updated title ",
        .summary = " Summary ",
        .published_at_unix = 10,
        .fetched_at_unix = 20,
    });
    defer owned.deinit(allocator);

    try std.testing.expectEqualStrings("Feed A", owned.source);
    try std.testing.expectEqualStrings("item-1", owned.external_id);
    try std.testing.expect(identityEqual(owned.write(), .{
        .source = "Feed A",
        .external_id = "item-1",
        .title = "Another title",
        .published_at_unix = 30,
        .fetched_at_unix = 40,
    }));
}

test "Manila month bucketing follows UTC+8 across year and month boundaries" {
    // The epoch is already 08:00 of 1 January 1970 in Manila.
    try std.testing.expectEqual(@as(i32, 1970), manilaCivilDate(0).year);
    try std.testing.expectEqual(@as(u8, 1), manilaCivilDate(0).month);

    // 2026-12-31T16:00:00Z is 2027-01-01T00:00:00 in Manila.
    const manila_new_year: i64 = 1_798_732_800;
    try std.testing.expectEqual(
        @as(i32, 2026),
        manilaCivilDate(manila_new_year - 1).year,
    );
    try std.testing.expectEqual(
        @as(u8, 12),
        manilaCivilDate(manila_new_year - 1).month,
    );
    try std.testing.expectEqual(
        @as(i32, 2027),
        manilaCivilDate(manila_new_year).year,
    );
    try std.testing.expectEqual(@as(u8, 1), manilaCivilDate(manila_new_year).month);

    // 2024-02-29T16:00:00Z is 2024-03-01T00:00:00 in Manila: February 2024 is
    // one day longer than February of a common year.
    const manila_march_2024: i64 = 1_709_222_400;
    try std.testing.expectEqual(
        @as(u8, 2),
        manilaCivilDate(manila_march_2024 - 1).month,
    );
    try std.testing.expectEqual(
        @as(u8, 3),
        manilaCivilDate(manila_march_2024).month,
    );
    try std.testing.expectEqual(
        @as(u8, 29),
        manilaCivilDate(manila_march_2024 - 1).day,
    );
    try std.testing.expectEqual(
        @as(u8, 1),
        manilaCivilDate(manila_march_2024).day,
    );
}

test "a notice stamped midnight Manila keeps that day, not the UTC day before" {
    // The feed publishes midnight Manila, which is 16:00 the previous day in
    // UTC. Reading it as UTC dated every notice a day early and could file one
    // under the month before the pane it appears in: RMC 73-2026 is issued
    // 2026-07-01 in Manila and read as 2026-06-30 in UTC.
    const manila_july_first: i64 = 1_782_835_200;
    const civil = manilaCivilDate(manila_july_first);
    try std.testing.expectEqual(@as(i32, 2026), civil.year);
    try std.testing.expectEqual(@as(u8, 7), civil.month);
    try std.testing.expectEqual(@as(u8, 1), civil.day);

    // The label and the bucket are the same reading, so they cannot disagree.
    const utc_days = @divFloor(manila_july_first, 86_400);
    try std.testing.expect(
        utc_days != @divFloor(manila_july_first + manila_utc_offset_seconds, 86_400),
    );
}

test "Manila month bucketing stays correct before the epoch" {
    // -28800 is exactly 1970-01-01T00:00:00 in Manila; one second earlier is
    // still December 1969 there.
    try std.testing.expectEqual(@as(i32, 1970), manilaCivilDate(-28_800).year);
    try std.testing.expectEqual(@as(u8, 1), manilaCivilDate(-28_800).month);
    try std.testing.expectEqual(@as(i32, 1969), manilaCivilDate(-28_801).year);
    try std.testing.expectEqual(@as(u8, 12), manilaCivilDate(-28_801).month);

    // 1968 was a leap year, so 29 February exists: 1968-02-29T00:00:00+08:00.
    const manila_leap_1968: i64 = -58_089_600;
    try std.testing.expectEqual(@as(i32, 1968), manilaCivilDate(manila_leap_1968).year);
    try std.testing.expectEqual(@as(u8, 2), manilaCivilDate(manila_leap_1968).month);
}
