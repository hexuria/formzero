//! Windows-1252 as used by `Scripting.FileSystemObject.CreateTextFile`
//! when the machine ANSI code page is 1252.
//!
//! Grounded by the 2026-08-23 offline eBIRForms 7.9.6.1 1601C Save capture on
//! a Windows VM with `HKLM\...\Nls\CodePage\ACP = 1252`:
//! - `é` U+00E9 / `É` U+00C9 round-trip as single bytes `0xE9` / `0xC9`;
//! - `Ñ` U+00D1 round-trips as `0xD1`;
//! - characters outside 1252 (`Ω`, U+2011) are best-fit substituted by Windows.
//!
//! This module does **not** reproduce best-fit substitution. Unmapped
//! scalars fail closed so an exact serializer cannot silently write `O` for
//! `Ω`. Philippine offline eBIRForms is pinned to ACP 1252; a different ACP
//! is out of scope.

const std = @import("std");

pub const Error = std.mem.Allocator.Error || error{
    InvalidUtf8,
    UnmappedCodepoint,
};

/// 0x80-0x9F. Unused slots (0x81, 0x8D, 0x8F, 0x90, 0x9D) stay as C1 controls.
const c1_codepoints = [32]u21{
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
};

pub fn fromCodepoint(codepoint: u21) ?u8 {
    if (codepoint <= 0x7f) return @intCast(codepoint);
    if (codepoint >= 0xa0 and codepoint <= 0xff) return @intCast(codepoint);
    for (c1_codepoints, 0..) |mapped, index| {
        if (mapped == codepoint) return @intCast(0x80 + index);
    }
    return null;
}

pub fn toCodepoint(byte: u8) u21 {
    if (byte <= 0x7f or byte >= 0xa0) return byte;
    return c1_codepoints[byte - 0x80];
}

fn iterate(utf8: []const u8) std.unicode.Utf8Iterator {
    return .{ .bytes = utf8, .i = 0 };
}

pub fn utf8IsEncodable(utf8: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(utf8)) return false;
    var iterator = iterate(utf8);
    while (iterator.nextCodepoint()) |codepoint| {
        if (fromCodepoint(codepoint) == null) return false;
    }
    return true;
}

pub fn utf8CodepointCount(utf8: []const u8) error{InvalidUtf8}!usize {
    if (!std.unicode.utf8ValidateSlice(utf8)) return error.InvalidUtf8;
    var count: usize = 0;
    var iterator = iterate(utf8);
    while (iterator.nextCodepoint()) |_| count += 1;
    return count;
}

pub fn utf8ByteIndexAfterCodepoints(
    utf8: []const u8,
    n: usize,
) error{InvalidUtf8}!usize {
    if (!std.unicode.utf8ValidateSlice(utf8)) return error.InvalidUtf8;
    var iterator = iterate(utf8);
    var remaining = n;
    while (remaining > 0) {
        if (iterator.nextCodepoint() == null) break;
        remaining -= 1;
    }
    return iterator.i;
}

pub fn utf8ToAnsiAlloc(
    allocator: std.mem.Allocator,
    utf8: []const u8,
) Error![]u8 {
    if (!std.unicode.utf8ValidateSlice(utf8)) return error.InvalidUtf8;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var iterator = iterate(utf8);
    while (iterator.nextCodepoint()) |codepoint| {
        const byte = fromCodepoint(codepoint) orelse
            return error.UnmappedCodepoint;
        try output.append(allocator, byte);
    }
    return output.toOwnedSlice(allocator);
}

pub fn ansiToUtf8Alloc(
    allocator: std.mem.Allocator,
    ansi: []const u8,
) std.mem.Allocator.Error![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var encoded: [4]u8 = undefined;
    for (ansi) |byte| {
        const n = std.unicode.utf8Encode(toCodepoint(byte), &encoded) catch
            unreachable;
        try output.appendSlice(allocator, encoded[0..n]);
    }
    return output.toOwnedSlice(allocator);
}

test "windows-1252 round-trips capture characters and rejects omega" {
    const allocator = std.testing.allocator;
    const e_acute = try utf8ToAnsiAlloc(allocator, "\u{00E9}");
    defer allocator.free(e_acute);
    try std.testing.expectEqualSlices(u8, &.{0xE9}, e_acute);

    const e_acute_cap = try utf8ToAnsiAlloc(allocator, "\u{00C9}");
    defer allocator.free(e_acute_cap);
    try std.testing.expectEqualSlices(u8, &.{0xC9}, e_acute_cap);

    const n_tilde = try utf8ToAnsiAlloc(allocator, "\u{00D1}");
    defer allocator.free(n_tilde);
    try std.testing.expectEqualSlices(u8, &.{0xD1}, n_tilde);

    try std.testing.expectError(
        error.UnmappedCodepoint,
        utf8ToAnsiAlloc(allocator, "\u{03A9}"),
    );
    try std.testing.expectError(
        error.UnmappedCodepoint,
        utf8ToAnsiAlloc(allocator, "\u{2011}"),
    );

    const decoded = try ansiToUtf8Alloc(allocator, &.{ 0xE9, 0xC9, 0xD1 });
    defer allocator.free(decoded);
    try std.testing.expectEqualStrings("\u{00E9}\u{00C9}\u{00D1}", decoded);

    try std.testing.expectEqual(
        @as(usize, 2),
        try utf8ByteIndexAfterCodepoints("\u{00D1}X", 1),
    );
}
