//! Bounded, persistence-neutral model for public Important News notices.
//!
//! Notice identity is the stable `(source, external_id)` pair. Feed adapters
//! must never use a title or publication timestamp as the external id: those
//! values are routinely corrected by publishers and would create duplicates.

const std = @import("std");

pub const max_notices: usize = 25;
pub const max_feed_bytes: usize = 1024 * 1024;
pub const max_feed_entries: usize = 100;
pub const max_source_bytes: usize = 96;
pub const max_external_id_bytes: usize = 512;
pub const max_title_bytes: usize = 512;
pub const max_summary_bytes: usize = 4096;
pub const max_url_bytes: usize = 2048;

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
