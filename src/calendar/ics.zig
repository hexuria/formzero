//! RFC 5545 calendar export for the provider-neutral "Add to calendar"
//! path. An exported file is a user-confirmed handoff, not a promise of
//! managed synchronization: calendar applications are free to treat later
//! imports as duplicates even when UIDs are stable.

const std = @import("std");

pub const Date = struct {
    year: i32,
    month: u8,
    day: u8,

    pub fn validate(self: Date) !void {
        if (self.year < 1 or self.year > 9999) return error.InvalidDate;
        if (self.month < 1 or self.month > 12) return error.InvalidDate;
        if (self.day < 1 or self.day > daysInMonth(self.year, self.month)) {
            return error.InvalidDate;
        }
    }

    pub fn next(self: Date) !Date {
        try self.validate();
        if (self.day < daysInMonth(self.year, self.month)) {
            return .{ .year = self.year, .month = self.month, .day = self.day + 1 };
        }
        if (self.month < 12) {
            return .{ .year = self.year, .month = self.month + 1, .day = 1 };
        }
        if (self.year == 9999) return error.InvalidDate;
        return .{ .year = self.year + 1, .month = 1, .day = 1 };
    }
};

pub const Event = struct {
    /// Stable application identity, for example `2026:2551Q:q1`.
    obligation_key: []const u8,
    date: Date,
    summary: []const u8,
    description: []const u8,
    reminders: bool = true,
};

pub const Options = struct {
    calendar_name: []const u8 = "eBIRForms Tax Deadlines",
    prod_id: []const u8 = "-//Goldcoders//eBIRForms Tax Calendar//EN",
    uid_domain: []const u8 = "ebirforms.goldcoders.dev",
    /// Deterministic UTC export stamp. Keeping this caller-owned makes the
    /// renderer fully testable and avoids hidden clock access.
    dtstamp_utc: []const u8,
};

pub fn generate(
    allocator: std.mem.Allocator,
    events: []const Event,
    options: Options,
) ![]u8 {
    try validateUtcStamp(options.dtstamp_utc);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try appendRawLine(allocator, &out, "BEGIN:VCALENDAR");
    try appendRawLine(allocator, &out, "VERSION:2.0");
    try appendProperty(allocator, &out, "PRODID", options.prod_id);
    try appendRawLine(allocator, &out, "CALSCALE:GREGORIAN");
    try appendProperty(allocator, &out, "X-WR-CALNAME", options.calendar_name);

    var seen_obligation_keys = std.StringHashMap(void).init(allocator);
    defer seen_obligation_keys.deinit();
    for (events) |event| {
        try event.date.validate();
        if (event.obligation_key.len == 0) return error.InvalidEvent;
        const seen = try seen_obligation_keys.getOrPut(event.obligation_key);
        if (seen.found_existing) return error.DuplicateObligationKey;

        try appendRawLine(allocator, &out, "BEGIN:VEVENT");
        try appendUid(allocator, &out, event.obligation_key, options.uid_domain);
        try appendRawProperty(allocator, &out, "DTSTAMP", options.dtstamp_utc);
        try appendDateProperty(allocator, &out, "DTSTART;VALUE=DATE", event.date);
        try appendDateProperty(allocator, &out, "DTEND;VALUE=DATE", try event.date.next());
        try appendProperty(allocator, &out, "SUMMARY", event.summary);
        try appendProperty(allocator, &out, "DESCRIPTION", event.description);
        try appendRawLine(allocator, &out, "STATUS:CONFIRMED");
        try appendRawLine(allocator, &out, "TRANSP:TRANSPARENT");
        try appendProperty(allocator, &out, "X-EBIRFORMS-OBLIGATION-KEY", event.obligation_key);

        if (event.reminders) {
            try appendAlarm(allocator, &out, "-P7D", "BIR deadline in 7 days");
            try appendAlarm(allocator, &out, "-P1D", "BIR deadline tomorrow");
        }

        try appendRawLine(allocator, &out, "END:VEVENT");
    }

    try appendRawLine(allocator, &out, "END:VCALENDAR");
    return out.toOwnedSlice(allocator);
}

fn appendAlarm(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    trigger: []const u8,
    description: []const u8,
) !void {
    try appendRawLine(allocator, out, "BEGIN:VALARM");
    try appendRawLine(allocator, out, "ACTION:DISPLAY");
    try appendRawProperty(allocator, out, "TRIGGER", trigger);
    try appendProperty(allocator, out, "DESCRIPTION", description);
    try appendRawLine(allocator, out, "END:VALARM");
}

fn appendUid(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    obligation_key: []const u8,
    domain: []const u8,
) !void {
    var value: std.ArrayList(u8) = .empty;
    defer value.deinit(allocator);
    try value.appendSlice(allocator, obligation_key);
    try value.append(allocator, '@');
    try value.appendSlice(allocator, domain);
    try appendProperty(allocator, out, "UID", value.items);
}

fn appendDateProperty(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    date: Date,
) !void {
    const year: u16 = @intCast(date.year);
    const buffer = [8]u8{
        @intCast('0' + (year / 1000) % 10),
        @intCast('0' + (year / 100) % 10),
        @intCast('0' + (year / 10) % 10),
        @intCast('0' + year % 10),
        @intCast('0' + (date.month / 10) % 10),
        @intCast('0' + date.month % 10),
        @intCast('0' + (date.day / 10) % 10),
        @intCast('0' + date.day % 10),
    };
    try appendRawProperty(allocator, out, name, &buffer);
}

fn appendProperty(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    value: []const u8,
) !void {
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(allocator);
    try line.appendSlice(allocator, name);
    try line.append(allocator, ':');
    try appendEscapedText(allocator, &line, value);
    try appendFoldedLine(allocator, out, line.items);
}

fn appendRawProperty(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    value: []const u8,
) !void {
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(allocator);
    try line.appendSlice(allocator, name);
    try line.append(allocator, ':');
    try line.appendSlice(allocator, value);
    try appendFoldedLine(allocator, out, line.items);
}

fn appendRawLine(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    line: []const u8,
) !void {
    if (std.mem.indexOfAny(u8, line, "\r\n") != null) return error.InvalidEvent;
    try appendFoldedLine(allocator, out, line);
}

fn appendEscapedText(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    value: []const u8,
) !void {
    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        switch (value[index]) {
            '\\' => try out.appendSlice(allocator, "\\\\"),
            ';' => try out.appendSlice(allocator, "\\;"),
            ',' => try out.appendSlice(allocator, "\\,"),
            '\r' => {
                if (index + 1 < value.len and value[index + 1] == '\n') index += 1;
                try out.appendSlice(allocator, "\\n");
            },
            '\n' => try out.appendSlice(allocator, "\\n"),
            else => try out.append(allocator, value[index]),
        }
    }
}

/// RFC 5545 content lines are limited to 75 octets. Continuation lines
/// begin with one space, leaving 74 payload octets. Never split a UTF-8
/// continuation byte from its leading code point.
fn appendFoldedLine(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    line: []const u8,
) !void {
    var offset: usize = 0;
    var first = true;
    while (offset < line.len) {
        if (!first) try out.append(allocator, ' ');
        const budget: usize = if (first) 75 else 74;
        var end = @min(offset + budget, line.len);
        while (end > offset and end < line.len and isUtf8Continuation(line[end])) {
            end -= 1;
        }
        if (end == offset) end = @min(offset + budget, line.len);
        try out.appendSlice(allocator, line[offset..end]);
        try out.appendSlice(allocator, "\r\n");
        offset = end;
        first = false;
    }
    if (line.len == 0) try out.appendSlice(allocator, "\r\n");
}

fn isUtf8Continuation(byte: u8) bool {
    return byte & 0b1100_0000 == 0b1000_0000;
}

fn validateUtcStamp(value: []const u8) !void {
    if (value.len != 16 or value[8] != 'T' or value[15] != 'Z') {
        return error.InvalidTimestamp;
    }
    for (value, 0..) |byte, index| {
        if (index == 8 or index == 15) continue;
        if (!std.ascii.isDigit(byte)) return error.InvalidTimestamp;
    }
    const year = parseDecimal(value[0..4]);
    const month = parseDecimal(value[4..6]);
    const day = parseDecimal(value[6..8]);
    const hour = parseDecimal(value[9..11]);
    const minute = parseDecimal(value[11..13]);
    const second = parseDecimal(value[13..15]);
    (Date{
        .year = @intCast(year),
        .month = @intCast(month),
        .day = @intCast(day),
    }).validate() catch return error.InvalidTimestamp;
    if (hour > 23 or minute > 59 or second > 59) {
        return error.InvalidTimestamp;
    }
}

fn parseDecimal(value: []const u8) u16 {
    var result: u16 = 0;
    for (value) |byte| result = result * 10 + (byte - '0');
    return result;
}

fn daysInMonth(year: i32, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

fn isLeapYear(year: i32) bool {
    return @mod(year, 4) == 0 and
        (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

test "calendar export is all-day, escaped, reminded, and stable" {
    const allocator = std.testing.allocator;
    const bytes = try generate(allocator, &.{
        .{
            .obligation_key = "2026:2551Q:q1",
            .date = .{ .year = 2026, .month = 4, .day = 27 },
            .summary = "[BIR] 2551Q, Q1",
            .description = "Original: 2026-04-25\nFinal: 2026-04-27; weekend",
        },
    }, .{ .dtstamp_utc = "20260729T010203Z" });
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.startsWith(u8, bytes, "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "UID:2026:2551Q:q1@ebirforms.goldcoders.dev\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "DTSTART;VALUE=DATE:20260427\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "DTEND;VALUE=DATE:20260428\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "SUMMARY:[BIR] 2551Q\\, Q1\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "Original: 2026-04-25\\nFinal: 2026-04-27\\; weekend") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, bytes, "BEGIN:VALARM"));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "METHOD:") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "SEQUENCE:") == null);
    try std.testing.expect(std.mem.endsWith(u8, bytes, "END:VCALENDAR\r\n"));
}

test "duplicate obligation keys are rejected before import" {
    const allocator = std.testing.allocator;
    const duplicate = Event{
        .obligation_key = "2026:1604-C:annual",
        .date = .{ .year = 2026, .month = 1, .day = 31 },
        .summary = "Duplicate",
        .description = "Duplicate",
    };
    try std.testing.expectError(
        error.DuplicateObligationKey,
        generate(
            allocator,
            &.{ duplicate, duplicate },
            .{ .dtstamp_utc = "20260729T010203Z" },
        ),
    );
}

test "UTC stamp validates calendar and clock fields" {
    const allocator = std.testing.allocator;
    const event = Event{
        .obligation_key = "2026:1701:annual",
        .date = .{ .year = 2026, .month = 4, .day = 15 },
        .summary = "Annual",
        .description = "Annual",
    };
    try std.testing.expectError(
        error.InvalidTimestamp,
        generate(
            allocator,
            &.{event},
            .{ .dtstamp_utc = "20260230T010203Z" },
        ),
    );
    try std.testing.expectError(
        error.InvalidTimestamp,
        generate(
            allocator,
            &.{event},
            .{ .dtstamp_utc = "20260729T246000Z" },
        ),
    );
}

test "date rollover includes leap years" {
    try std.testing.expectEqualDeep(
        Date{ .year = 2024, .month = 2, .day = 29 },
        try (Date{ .year = 2024, .month = 2, .day = 28 }).next(),
    );
    try std.testing.expectEqualDeep(
        Date{ .year = 2027, .month = 1, .day = 1 },
        try (Date{ .year = 2026, .month = 12, .day = 31 }).next(),
    );
}

test "folding keeps content lines within 75 bytes" {
    const allocator = std.testing.allocator;
    const bytes = try generate(allocator, &.{
        .{
            .obligation_key = "2026:1701Q:q1",
            .date = .{ .year = 2026, .month = 5, .day = 15 },
            .summary = "A very long eBIRForms deadline summary that includes UTF-8: Pilipinas 🇵🇭 and more text",
            .description = "Long description",
        },
    }, .{ .dtstamp_utc = "20260729T010203Z" });
    defer allocator.free(bytes);

    var lines = std.mem.splitSequence(u8, bytes, "\r\n");
    while (lines.next()) |line| {
        try std.testing.expect(line.len <= 75);
        try std.testing.expect(std.unicode.utf8ValidateSlice(line));
    }
}
