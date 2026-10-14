//! Exact Windows-1252 Final Copy plaintext codec for 1701Q January 2018.
//!
//! Evidence anchors in the verified 7.9.6 HTA:
//! - Final Copy plaintext writer loop: lines 2463-2487;
//! - external container hand-off: lines 2489-2490.
//!
//! This path is intentionally distinct from the editable-save writer. It
//! emits all 173 eligible controls, leaves text/select values raw, preserves
//! the two address controls as separate occurrences, does not reset the
//! current page, and always appends the final `0` sentinel.

const std = @import("std");
const occurrence = @import("../../occurrence.zig");
const occurrences = @import("occurrences.zig");
const document = @import("document.zig");
const sensitive_memory = @import("../../../security/sensitive_memory.zig");

pub const ControlInput = document.ControlInput;
pub const ControlValue = document.ControlValue;
pub const ParsedDocument = document.ParsedDocument;

/// Delimiters, ASCII, and Windows-1252 raw values are exact. Characters
/// outside ACP 1252 stay fail-closed; Windows best-fit is not reproduced.
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
        InvalidCheckedBoolean,
    };

pub fn serializeAsciiExactAlloc(
    allocator: std.mem.Allocator,
    controls: []const ControlInput,
) Error![]u8 {
    try validateControls(controls);
    const manifest = try occurrences.finalCopyManifest();

    var temporary_buffers: [occurrences.final_copy_occurrence_items.len][]u8 = undefined;
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
            [occurrences.final_copy_occurrence_items.len][]u8,
            &temporary_buffers,
        );
    }

    var emitted: [occurrences.final_copy_occurrence_items.len]document.Occurrence =
        undefined;
    for (manifest.items, controls, 0..) |metadata, input, index| {
        if (metadata.source_controls.len() != 1 or
            !std.mem.eql(
                u8,
                metadata.source_controls.at(0).?,
                input.id,
            ))
        {
            return error.ManifestSourceMismatch;
        }
        emitted[index] = .{
            .key = metadata.serialized_key,
            .encoded_value = switch (metadata.emission) {
                .raw => switch (input.value) {
                    .text => |value| blk: {
                        const encoded = try document.encodeRawUtf8Alloc(
                            allocator,
                            value,
                        );
                        temporary_buffers[temporary_count] = encoded;
                        temporary_count += 1;
                        break :blk encoded;
                    },
                    .checked => return error.InputKindMismatch,
                },
                .checked_boolean => switch (input.value) {
                    .checked => |checked| if (checked) "true" else "false",
                    .text => return error.InputKindMismatch,
                },
                else => return error.UnsupportedEmission,
            },
        };
    }
    return document.renderOccurrencesAlloc(
        allocator,
        &emitted,
        .final,
    );
}

pub fn parseAsciiExact(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) Error!ParsedDocument {
    var parsed = try document.parse(allocator, bytes);
    errdefer parsed.deinit(allocator);

    const manifest = try occurrences.finalCopyManifest();
    var expected_keys: [occurrences.final_copy_occurrence_items.len][]const u8 = undefined;
    for (manifest.items, 0..) |item, index| {
        expected_keys[index] = item.serialized_key;
    }
    try parsed.validateExactKeys(&expected_keys, .final);

    for (parsed.occurrences, manifest.items) |actual, metadata| {
        switch (metadata.emission) {
            .raw => {},
            .checked_boolean => {
                if (!std.mem.eql(u8, actual.encoded_value, "true") and
                    !std.mem.eql(u8, actual.encoded_value, "false"))
                {
                    return error.InvalidCheckedBoolean;
                }
            },
            else => return error.UnsupportedEmission,
        }
    }
    return parsed;
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

test "Final Copy keeps raw separate addresses and live current page" {
    var controls = blankControls();
    setText(&controls, "frm1701q:txtYear", "2026");
    setChecked(&controls, "frm1701q:DateQuarter_1", true);
    setText(&controls, "frm1701q:txtRDOCode", "000");
    setText(&controls, "frm1701q:txtSpouseRDOCode", "000");
    setText(
        &controls,
        "frm1701q:txtTaxpayerName",
        "A B&RAW%20",
    );
    setText(&controls, "frm1701q:txtAddress", "ONE");
    setText(&controls, "frm1701q:txtAddress2", "TWO");
    setText(&controls, "frm1701q:txtCurrentPage", "3");

    const bytes = try serializeAsciiExactAlloc(
        std.testing.allocator,
        &controls,
    );
    defer std.testing.allocator.free(bytes);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const expected_digest = [_]u8{
        0x15, 0x8e, 0x98, 0x3d, 0xa9, 0x20, 0x16, 0x5b,
        0xae, 0xb4, 0xa0, 0xa2, 0xd5, 0x7d, 0x0b, 0xf6,
        0x32, 0x65, 0xdf, 0xaa, 0x6d, 0x16, 0xec, 0xb4,
        0x7c, 0x7a, 0x06, 0xc9, 0xa7, 0x07, 0x8b, 0x7c,
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
        document.final_tail,
    ));

    var parsed = try parseAsciiExact(std.testing.allocator, bytes);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 173), parsed.occurrences.len);
    try std.testing.expectEqualStrings(
        "A B&RAW%20",
        parsed.occurrence(
            "frm1701q:txtTaxpayerName",
            1,
        ).?.encoded_value,
    );
    try std.testing.expectEqualStrings(
        "ONE",
        parsed.occurrence(
            "frm1701q:txtAddress",
            1,
        ).?.encoded_value,
    );
    try std.testing.expectEqualStrings(
        "TWO",
        parsed.occurrence(
            "frm1701q:txtAddress2",
            1,
        ).?.encoded_value,
    );
    try std.testing.expectEqualStrings(
        "3",
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
        @as(u16, 42),
        parsed.occurrence(
            "frm1701q:txtSpouseRDOCode",
            1,
        ).?.source_order,
    );

    const rendered = try parsed.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, bytes, rendered);
}

test "Final Copy rejects wrong marker duplicate key and invalid Boolean" {
    var controls = blankControls();
    const bytes = try serializeAsciiExactAlloc(
        std.testing.allocator,
        &controls,
    );
    defer std.testing.allocator.free(bytes);
    var parsed = try parseAsciiExact(std.testing.allocator, bytes);
    defer parsed.deinit(std.testing.allocator);

    var altered: [occurrences.final_copy_occurrence_items.len]document.Occurrence =
        undefined;
    for (parsed.occurrences, 0..) |item, index| {
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
    defer std.testing.allocator.free(duplicate);
    try std.testing.expectError(
        error.UnexpectedOccurrenceKey,
        parseAsciiExact(std.testing.allocator, duplicate),
    );

    altered[0] = .{
        .key = parsed.occurrences[0].key,
        .encoded_value = parsed.occurrences[0].encoded_value,
    };
    altered[1].encoded_value = "1";
    const invalid_boolean = try document.renderOccurrencesAlloc(
        std.testing.allocator,
        &altered,
        .final,
    );
    defer std.testing.allocator.free(invalid_boolean);
    try std.testing.expectError(
        error.InvalidCheckedBoolean,
        parseAsciiExact(std.testing.allocator, invalid_boolean),
    );

    const editable_marker = try document.renderOccurrencesAlloc(
        std.testing.allocator,
        &altered,
        .editable,
    );
    defer std.testing.allocator.free(editable_marker);
    try std.testing.expectError(
        error.WrongMarker,
        parseAsciiExact(std.testing.allocator, editable_marker),
    );
}

test "Final Copy byte output is fail-closed beyond proven ASCII" {
    var controls = blankControls();
    setText(
        &controls,
        "frm1701q:txtTaxpayerName",
        "\xE2\x82\xB1",
    );
    try std.testing.expectError(
        error.UnqualifiedByteEncoding,
        serializeAsciiExactAlloc(std.testing.allocator, &controls),
    );

    controls = blankControls();
    setText(&controls, "frm1701q:txtTaxpayerName", "\xC3\xA9");
    const encoded = try serializeAsciiExactAlloc(
        std.testing.allocator,
        &controls,
    );
    defer std.testing.allocator.free(encoded);
    var parsed = try parseAsciiExact(std.testing.allocator, encoded);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(
        "\xE9",
        parsed.occurrence("frm1701q:txtTaxpayerName", 1).?.encoded_value,
    );

    controls = blankControls();
    controls[0].value = .{ .checked = false };
    try std.testing.expectError(
        error.InputKindMismatch,
        serializeAsciiExactAlloc(std.testing.allocator, &controls),
    );
}
