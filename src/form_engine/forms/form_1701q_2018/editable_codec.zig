//! Exact proven-ASCII editable-save codec for 1701Q January 2018.
//!
//! Evidence anchors in the verified 7.9.6 HTA:
//! - `saveXML(isFinalCopy)`: lines 2605-2920;
//! - occurrence loop and selective branches: lines 2782-2896;
//! - editable/finalized local tails: lines 2900-2905;
//! - `loadData`: lines 2264-2319.
//!
//! The ordered occurrence manifest is the serialization authority. No map is
//! built, and the two address controls are consumed consecutively into the
//! one legacy `frm1701q:txtAddress` occurrence.

const std = @import("std");
const occurrence = @import("../../occurrence.zig");
const occurrences = @import("occurrences.zig");
const document = @import("document.zig");
const sensitive_memory = @import("../../../security/sensitive_memory.zig");

pub const ControlInput = document.ControlInput;
pub const ControlValue = document.ControlValue;
pub const ParsedDocument = document.ParsedDocument;

pub const SaveStatus = enum {
    editable,
    finalized_local,

    fn marker(self: SaveStatus) document.Marker {
        return switch (self) {
            .editable => .editable,
            .finalized_local => .final,
        };
    }
};

/// Delimiters and ASCII bytes are exact. Full machine-ANSI output remains
/// fail-closed pending the paired official Windows capture gate.
pub const exact_complete_byte_encoding_ready =
    document.exact_complete_byte_encoding_ready;
pub const ascii_byte_layer_exact = document.ascii_byte_layer_exact;

pub const Error = std.mem.Allocator.Error ||
    occurrence.ManifestError ||
    document.RenderError ||
    document.ParseError ||
    document.ExactShapeError ||
    error{
        InputCountMismatch,
        InputIdMismatch,
        InputKindMismatch,
        ManifestSourceMismatch,
        UnsupportedEmission,
        InvalidUtf8,
        EscapedValueTooLong,
        InvalidLegacyEscape,
        NonCanonicalLegacyEscape,
        InvalidCheckedBoolean,
        InvalidConstant,
    };

pub fn serializeAsciiExactAlloc(
    allocator: std.mem.Allocator,
    controls: []const ControlInput,
    status: SaveStatus,
) Error![]u8 {
    try validateControls(controls);
    const manifest = try occurrences.editableManifest();

    var temporary_buffers: [occurrences.editable_occurrence_items.len * 3][]u8 = undefined;
    var temporary_count: usize = 0;
    defer {
        for (temporary_buffers[0..temporary_count]) |buffer| {
            sensitive_memory.wipeAndFreeDefaultAligned(
                u8,
                allocator,
                buffer,
            );
        }
        sensitive_memory.wipeValue(
            [occurrences.editable_occurrence_items.len * 3][]u8,
            &temporary_buffers,
        );
    }

    var emitted: [occurrences.editable_occurrence_items.len]document.Occurrence =
        undefined;
    defer sensitive_memory.wipeValue(
        [occurrences.editable_occurrence_items.len]document.Occurrence,
        &emitted,
    );
    var control_index: usize = 0;
    for (manifest.items, 0..) |metadata, output_index| {
        const source_count = metadata.source_controls.len();
        if (source_count == 0 or
            control_index + source_count > controls.len)
        {
            return error.ManifestSourceMismatch;
        }
        for (0..source_count) |source_index| {
            if (!std.mem.eql(
                u8,
                controls[control_index + source_index].id,
                metadata.source_controls.at(@intCast(source_index)).?,
            )) {
                return error.ManifestSourceMismatch;
            }
        }

        const encoded_value: []const u8 = switch (metadata.emission) {
            .raw => textValue(controls[control_index]) orelse
                return error.InputKindMismatch,
            .legacy_escape => blk: {
                const value = textValue(controls[control_index]) orelse
                    return error.InputKindMismatch;
                const escaped = try legacyEscapeAlloc(allocator, value);
                temporary_buffers[temporary_count] = escaped;
                temporary_count += 1;
                break :blk escaped;
            },
            .concatenated_legacy_escape => blk: {
                if (source_count != 2) {
                    return error.ManifestSourceMismatch;
                }
                const first = textValue(controls[control_index]) orelse
                    return error.InputKindMismatch;
                const second =
                    textValue(controls[control_index + 1]) orelse
                    return error.InputKindMismatch;
                const escaped_first =
                    try legacyEscapeAlloc(allocator, first);
                temporary_buffers[temporary_count] = escaped_first;
                temporary_count += 1;
                const escaped_second =
                    try legacyEscapeAlloc(allocator, second);
                temporary_buffers[temporary_count] = escaped_second;
                temporary_count += 1;
                const joined_len = std.math.add(
                    usize,
                    escaped_first.len,
                    escaped_second.len,
                ) catch return error.DocumentTooLarge;
                const joined = try allocator.alloc(
                    u8,
                    joined_len,
                );
                temporary_buffers[temporary_count] = joined;
                temporary_count += 1;
                @memcpy(joined[0..escaped_first.len], escaped_first);
                @memcpy(joined[escaped_first.len..], escaped_second);
                break :blk joined;
            },
            .checked_boolean => switch (controls[control_index].value) {
                .checked => |checked| if (checked) "true" else "false",
                .text => return error.InputKindMismatch,
            },
            .constant => blk: {
                if (textValue(controls[control_index]) == null or
                    !std.mem.eql(
                        u8,
                        metadata.serialized_key,
                        "frm1701q:txtCurrentPage",
                    ))
                {
                    return error.ManifestSourceMismatch;
                }
                break :blk "1";
            },
            .unreviewed => return error.UnsupportedEmission,
        };

        emitted[output_index] = .{
            .key = metadata.serialized_key,
            .encoded_value = encoded_value,
        };
        control_index += source_count;
    }
    if (control_index != controls.len) {
        return error.ManifestSourceMismatch;
    }
    return document.renderOccurrencesAlloc(
        allocator,
        &emitted,
        status.marker(),
    );
}

pub fn parseAsciiExact(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    status: SaveStatus,
) Error!ParsedDocument {
    var parsed = try document.parse(allocator, bytes);
    errdefer parsed.deinit(allocator);

    const manifest = try occurrences.editableManifest();
    var expected_keys: [occurrences.editable_occurrence_items.len][]const u8 =
        undefined;
    for (manifest.items, 0..) |item, index| {
        expected_keys[index] = item.serialized_key;
    }
    try parsed.validateExactKeys(&expected_keys, status.marker());

    for (parsed.occurrences, manifest.items) |actual, metadata| {
        switch (metadata.emission) {
            .raw => {},
            .legacy_escape, .concatenated_legacy_escape => try validateLegacyEscape(actual.encoded_value),
            .checked_boolean => {
                if (!std.mem.eql(u8, actual.encoded_value, "true") and
                    !std.mem.eql(u8, actual.encoded_value, "false"))
                {
                    return error.InvalidCheckedBoolean;
                }
            },
            .constant => {
                if (!std.mem.eql(u8, actual.encoded_value, "1")) {
                    return error.InvalidConstant;
                }
            },
            .unreviewed => return error.UnsupportedEmission,
        }
    }
    return parsed;
}

/// Reproduces the legacy JavaScript `escape()` transform over UTF-16 code
/// units. Its output is always ASCII and therefore independent of the Windows
/// ANSI code page used by `CreateTextFile`.
pub fn legacyEscapeAlloc(
    allocator: std.mem.Allocator,
    utf8: []const u8,
) Error![]u8 {
    if (!std.unicode.utf8ValidateSlice(utf8)) return error.InvalidUtf8;

    var output: std.ArrayList(u8) = .empty;
    errdefer sensitive_memory.wipeAndDeinitArrayList(
        u8,
        allocator,
        &output,
    );
    var iterator: std.unicode.Utf8Iterator = .{
        .bytes = utf8,
        .i = 0,
    };
    while (iterator.nextCodepoint()) |codepoint| {
        if (codepoint <= 0x7f and isEscapeSafe(@intCast(codepoint))) {
            try appendBoundedByte(&output, allocator, @intCast(codepoint));
        } else if (codepoint <= 0xff) {
            try appendPercentByte(&output, allocator, @intCast(codepoint));
        } else if (codepoint <= 0xffff) {
            try appendPercentCodeUnit(
                &output,
                allocator,
                @intCast(codepoint),
            );
        } else {
            const scalar: u32 = @intCast(codepoint);
            const adjusted = scalar - 0x10000;
            const high: u16 = @intCast(0xd800 + (adjusted >> 10));
            const low: u16 = @intCast(0xdc00 + (adjusted & 0x3ff));
            try appendPercentCodeUnit(&output, allocator, high);
            try appendPercentCodeUnit(&output, allocator, low);
        }
    }
    return sensitive_memory.toOwnedSlice(u8, allocator, &output);
}

pub fn legacyUnescapeAlloc(
    allocator: std.mem.Allocator,
    escaped: []const u8,
) Error![]u8 {
    try validateLegacyEscape(escaped);

    var output: std.ArrayList(u8) = .empty;
    errdefer sensitive_memory.wipeAndDeinitArrayList(
        u8,
        allocator,
        &output,
    );
    var cursor: usize = 0;
    while (cursor < escaped.len) {
        if (escaped[cursor] != '%') {
            try sensitive_memory.append(
                u8,
                allocator,
                &output,
                escaped[cursor],
            );
            cursor += 1;
            continue;
        }

        var codepoint: u21 = undefined;
        if (escaped[cursor + 1] == 'u') {
            const first = decodeHex4(escaped[cursor + 2 .. cursor + 6]);
            cursor += 6;
            if (first >= 0xd800 and first <= 0xdbff) {
                const second = decodeHex4(
                    escaped[cursor + 2 .. cursor + 6],
                );
                cursor += 6;
                codepoint = @intCast(
                    0x10000 +
                        ((@as(u32, first) - 0xd800) << 10) +
                        (@as(u32, second) - 0xdc00),
                );
            } else {
                codepoint = @intCast(first);
            }
        } else {
            codepoint = @intCast(
                decodeHex2(escaped[cursor + 1 .. cursor + 3]),
            );
            cursor += 3;
        }

        var encoded: [4]u8 = undefined;
        defer sensitive_memory.wipeValue([4]u8, &encoded);
        const encoded_len = std.unicode.utf8Encode(
            codepoint,
            &encoded,
        ) catch unreachable;
        try sensitive_memory.appendSlice(
            u8,
            allocator,
            &output,
            encoded[0..encoded_len],
        );
    }
    return sensitive_memory.toOwnedSlice(u8, allocator, &output);
}

pub fn validateLegacyEscape(
    escaped: []const u8,
) error{
    InvalidLegacyEscape,
    NonCanonicalLegacyEscape,
}!void {
    var cursor: usize = 0;
    while (cursor < escaped.len) {
        const byte = escaped[cursor];
        if (byte != '%') {
            if (byte > 0x7f or !isEscapeSafe(byte)) {
                return error.InvalidLegacyEscape;
            }
            cursor += 1;
            continue;
        }

        if (cursor + 3 > escaped.len) return error.InvalidLegacyEscape;
        if (escaped[cursor + 1] != 'u') {
            const decoded = decodeCanonicalHex2(
                escaped[cursor + 1 .. cursor + 3],
            ) orelse return error.InvalidLegacyEscape;
            if (isEscapeSafe(decoded)) {
                return error.NonCanonicalLegacyEscape;
            }
            cursor += 3;
            continue;
        }

        if (cursor + 6 > escaped.len) return error.InvalidLegacyEscape;
        const first = decodeCanonicalHex4(
            escaped[cursor + 2 .. cursor + 6],
        ) orelse return error.InvalidLegacyEscape;
        if (first < 0x100) return error.NonCanonicalLegacyEscape;
        cursor += 6;

        if (first >= 0xd800 and first <= 0xdbff) {
            if (cursor + 6 > escaped.len or
                escaped[cursor] != '%' or
                escaped[cursor + 1] != 'u')
            {
                return error.InvalidLegacyEscape;
            }
            const second = decodeCanonicalHex4(
                escaped[cursor + 2 .. cursor + 6],
            ) orelse return error.InvalidLegacyEscape;
            if (second < 0xdc00 or second > 0xdfff) {
                return error.InvalidLegacyEscape;
            }
            cursor += 6;
        } else if (first >= 0xdc00 and first <= 0xdfff) {
            return error.InvalidLegacyEscape;
        }
    }
}

fn validateControls(controls: []const ControlInput) Error!void {
    if (controls.len != occurrences.control_seeds.len) {
        return error.InputCountMismatch;
    }
    for (controls, occurrences.control_seeds) |input, seed| {
        if (!std.mem.eql(u8, input.id, seed.id)) {
            return error.InputIdMismatch;
        }
        switch (seed.kind) {
            .text, .select_one => switch (input.value) {
                .text => {},
                .checked => return error.InputKindMismatch,
            },
            .radio => switch (input.value) {
                .checked => {},
                .text => return error.InputKindMismatch,
            },
        }
    }
}

fn textValue(input: ControlInput) ?[]const u8 {
    return switch (input.value) {
        .text => |value| value,
        .checked => null,
    };
}

fn isEscapeSafe(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or
        byte == '@' or
        byte == '*' or
        byte == '_' or
        byte == '+' or
        byte == '-' or
        byte == '.' or
        byte == '/';
}

const uppercase_hex = "0123456789ABCDEF";

fn appendBoundedByte(
    output: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    byte: u8,
) Error!void {
    if (output.items.len == document.max_value_bytes) {
        return error.EscapedValueTooLong;
    }
    try sensitive_memory.append(u8, allocator, output, byte);
}

fn appendPercentByte(
    output: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: u8,
) Error!void {
    if (output.items.len > document.max_value_bytes - 3) {
        return error.EscapedValueTooLong;
    }
    try sensitive_memory.appendSlice(
        u8,
        allocator,
        output,
        &.{
            '%',
            uppercase_hex[value >> 4],
            uppercase_hex[value & 0x0f],
        },
    );
}

fn appendPercentCodeUnit(
    output: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: u16,
) Error!void {
    if (output.items.len > document.max_value_bytes - 6) {
        return error.EscapedValueTooLong;
    }
    try sensitive_memory.appendSlice(
        u8,
        allocator,
        output,
        &.{
            '%',
            'u',
            uppercase_hex[(value >> 12) & 0x0f],
            uppercase_hex[(value >> 8) & 0x0f],
            uppercase_hex[(value >> 4) & 0x0f],
            uppercase_hex[value & 0x0f],
        },
    );
}

fn decodeCanonicalHex2(bytes: []const u8) ?u8 {
    if (bytes.len != 2) return null;
    const high = decodeCanonicalHexDigit(bytes[0]) orelse return null;
    const low = decodeCanonicalHexDigit(bytes[1]) orelse return null;
    return (high << 4) | low;
}

fn decodeCanonicalHex4(bytes: []const u8) ?u16 {
    if (bytes.len != 4) return null;
    var value: u16 = 0;
    for (bytes) |byte| {
        value = (value << 4) |
            (decodeCanonicalHexDigit(byte) orelse return null);
    }
    return value;
}

fn decodeCanonicalHexDigit(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

fn decodeHex2(bytes: []const u8) u8 {
    return decodeCanonicalHex2(bytes).?;
}

fn decodeHex4(bytes: []const u8) u16 {
    return decodeCanonicalHex4(bytes).?;
}

fn blankControls() [occurrences.control_seeds.len]ControlInput {
    var result: [occurrences.control_seeds.len]ControlInput = undefined;
    for (occurrences.control_seeds, 0..) |seed, index| {
        result[index] = .{
            .id = seed.id,
            .value = switch (seed.kind) {
                .text, .select_one => .{ .text = "" },
                .radio => .{ .checked = false },
            },
        };
    }
    return result;
}

fn setText(
    controls: []ControlInput,
    id: []const u8,
    value: []const u8,
) void {
    for (controls) |*control| {
        if (std.mem.eql(u8, control.id, id)) {
            control.value = .{ .text = value };
            return;
        }
    }
    unreachable;
}

fn setChecked(
    controls: []ControlInput,
    id: []const u8,
    value: bool,
) void {
    for (controls) |*control| {
        if (std.mem.eql(u8, control.id, id)) {
            control.value = .{ .checked = value };
            return;
        }
    }
    unreachable;
}

fn exerciseSensitiveCodecAllocationPaths(
    allocator: std.mem.Allocator,
) !void {
    const source = "A B&\xC3\xB1\xF0\x9F\x98\x80";
    const escaped = try legacyEscapeAlloc(allocator, source);
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        u8,
        allocator,
        escaped,
    );
    const decoded = try legacyUnescapeAlloc(allocator, escaped);
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        u8,
        allocator,
        decoded,
    );
    try std.testing.expectEqualStrings(source, decoded);

    var controls = blankControls();
    setText(&controls, "frm1701q:txtTaxpayerName", source);
    setText(&controls, "frm1701q:txtAddress", "FIRST ");
    setText(&controls, "frm1701q:txtAddress2", "SECOND");
    const bytes = try serializeAsciiExactAlloc(
        allocator,
        &controls,
        .editable,
    );
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        u8,
        allocator,
        bytes,
    );
    try std.testing.expect(std.mem.startsWith(
        u8,
        bytes,
        document.document_prefix,
    ));
}

test "all sensitive codec allocation failures erase partial values" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exerciseSensitiveCodecAllocationPaths,
        .{},
    );
}

test "legacy escape is canonical over UTF-16 code units" {
    const source = "Az09@*_+-./ ~!\xC3\xB1\xE2\x82\xB1\xF0\x9F\x98\x80";
    const expected =
        "Az09@*_+-./%20%7E%21%F1%u20B1%uD83D%uDE00";
    const escaped = try legacyEscapeAlloc(std.testing.allocator, source);
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        u8,
        std.testing.allocator,
        escaped,
    );
    try std.testing.expectEqualStrings(expected, escaped);
    try validateLegacyEscape(escaped);

    const decoded = try legacyUnescapeAlloc(
        std.testing.allocator,
        escaped,
    );
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        u8,
        std.testing.allocator,
        decoded,
    );
    try std.testing.expectEqualStrings(source, decoded);

    try std.testing.expectError(
        error.NonCanonicalLegacyEscape,
        validateLegacyEscape("%41"),
    );
    try std.testing.expectError(
        error.InvalidLegacyEscape,
        validateLegacyEscape("%uD83D"),
    );
    try std.testing.expectError(
        error.InvalidLegacyEscape,
        validateLegacyEscape("%f1"),
    );
}

test "editable serializer collapses address escapes selected values and resets page" {
    var controls = blankControls();
    setText(&controls, "frm1701q:txtYear", "2026");
    setChecked(&controls, "frm1701q:DateQuarter_1", true);
    setText(&controls, "frm1701q:txtRDOCode", "000");
    setText(&controls, "frm1701q:txtSpouseRDOCode", "000");
    setText(
        &controls,
        "frm1701q:txtTaxpayerName",
        "A B&\xC3\xB1\xF0\x9F\x98\x80",
    );
    setText(&controls, "frm1701q:txtAddress", "ONE ");
    setText(&controls, "frm1701q:txtAddress2", "TWO");
    setText(&controls, "frm1701q:txtCurrentPage", "9");
    setText(&controls, "frm1701q:txtLOB", "+/@*_.-");

    const bytes = try serializeAsciiExactAlloc(
        std.testing.allocator,
        &controls,
        .editable,
    );
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        u8,
        std.testing.allocator,
        bytes,
    );
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const expected_digest = [_]u8{
        0x3e, 0xf8, 0x2a, 0xf9, 0x18, 0x99, 0x05, 0x55,
        0xef, 0x12, 0xc4, 0xf7, 0xd5, 0x83, 0x16, 0x5a,
        0xe4, 0x69, 0x41, 0x1c, 0xc0, 0x2d, 0x71, 0xfa,
        0xf5, 0xdb, 0xc2, 0xc6, 0x7e, 0x0a, 0x45, 0xcc,
    };
    try std.testing.expectEqualSlices(u8, &expected_digest, &digest);
    try std.testing.expect(std.mem.startsWith(
        u8,
        bytes,
        document.document_prefix,
    ));
    try std.testing.expect(std.mem.endsWith(
        u8,
        bytes,
        document.editable_tail,
    ));

    var parsed = try parseAsciiExact(
        std.testing.allocator,
        bytes,
        .editable,
    );
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 172), parsed.occurrences.len);
    try std.testing.expectEqualStrings(
        "A%20B%26%F1%uD83D%uDE00",
        parsed.occurrence(
            "frm1701q:txtTaxpayerName",
            1,
        ).?.encoded_value,
    );
    try std.testing.expectEqualStrings(
        "ONE%20TWO",
        parsed.occurrence(
            "frm1701q:txtAddress",
            1,
        ).?.encoded_value,
    );
    try std.testing.expect(
        parsed.occurrence("frm1701q:txtAddress2", 1) == null,
    );
    try std.testing.expectEqualStrings(
        "1",
        parsed.occurrence(
            "frm1701q:txtCurrentPage",
            1,
        ).?.encoded_value,
    );
    try std.testing.expectEqualStrings(
        "true",
        parsed.occurrence(
            "frm1701q:DateQuarter_1",
            1,
        ).?.encoded_value,
    );
    try std.testing.expectEqual(
        @as(u16, 11),
        parsed.occurrence(
            "frm1701q:txtRDOCode",
            1,
        ).?.source_order,
    );
    try std.testing.expectEqual(
        @as(u16, 41),
        parsed.occurrence(
            "frm1701q:txtSpouseRDOCode",
            1,
        ).?.source_order,
    );

    const rendered = try parsed.renderAlloc(std.testing.allocator);
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        u8,
        std.testing.allocator,
        rendered,
    );
    try std.testing.expectEqualSlices(u8, bytes, rendered);
}

test "finalized local marker and exact parser failures are explicit" {
    var controls = blankControls();
    const bytes = try serializeAsciiExactAlloc(
        std.testing.allocator,
        &controls,
        .finalized_local,
    );
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        u8,
        std.testing.allocator,
        bytes,
    );
    var finalized = try parseAsciiExact(
        std.testing.allocator,
        bytes,
        .finalized_local,
    );
    defer finalized.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.WrongMarker,
        parseAsciiExact(std.testing.allocator, bytes, .editable),
    );

    var altered: [occurrences.editable_occurrence_items.len]document.Occurrence =
        undefined;
    for (finalized.occurrences, 0..) |item, index| {
        altered[index] = .{
            .key = item.key,
            .encoded_value = item.encoded_value,
        };
    }
    altered[0].key = altered[1].key;
    const duplicate = try document.renderOccurrencesAlloc(
        std.testing.allocator,
        &altered,
        .final,
    );
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        u8,
        std.testing.allocator,
        duplicate,
    );
    try std.testing.expectError(
        error.UnexpectedOccurrenceKey,
        parseAsciiExact(
            std.testing.allocator,
            duplicate,
            .finalized_local,
        ),
    );

    altered[0] = .{
        .key = finalized.occurrences[0].key,
        .encoded_value = finalized.occurrences[0].encoded_value,
    };
    altered[1].encoded_value = "TRUE";
    const invalid_boolean = try document.renderOccurrencesAlloc(
        std.testing.allocator,
        &altered,
        .final,
    );
    defer sensitive_memory.wipeAndFreeDefaultAligned(
        u8,
        std.testing.allocator,
        invalid_boolean,
    );
    try std.testing.expectError(
        error.InvalidCheckedBoolean,
        parseAsciiExact(
            std.testing.allocator,
            invalid_boolean,
            .finalized_local,
        ),
    );
}

test "wrong control order and unqualified raw encoding fail closed" {
    var controls = blankControls();
    controls[1].id = controls[0].id;
    try std.testing.expectError(
        error.InputIdMismatch,
        serializeAsciiExactAlloc(
            std.testing.allocator,
            &controls,
            .editable,
        ),
    );

    controls = blankControls();
    setText(&controls, "frm1701q:txtYear", "\xC3\xA9");
    try std.testing.expectError(
        error.UnqualifiedByteEncoding,
        serializeAsciiExactAlloc(
            std.testing.allocator,
            &controls,
            .editable,
        ),
    );
}
