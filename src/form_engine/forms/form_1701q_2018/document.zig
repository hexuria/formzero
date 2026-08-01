//! Strict, lossless byte document for the 1701Q January 2018 legacy
//! pseudo-XML envelope.
//!
//! Evidence anchors in the verified 7.9.6 HTA:
//! - `xmlFormat` / `xmlClose`: lines 2008-2012;
//! - editable writer envelope and tail: lines 2771-2775, 2897-2911;
//! - Final Copy plaintext envelope and tail: lines 2463-2487.
//!
//! A controlled Windows MSHTML observation of the exact `xmlFormat` source
//! fragment establishes that `innerHTML` normalizes its source LF to CRLF,
//! yielding `"\t\r\n            "`. `TextStream.Write` adds no newline.
//!
//! `Scripting.FileSystemObject.CreateTextFile` still uses the machine ANSI
//! code page. That code page is not an invariant of the form package, so this
//! module deliberately accepts only the code-page-independent ASCII byte
//! subset. The public readiness fact remains false until paired official
//! captures qualify the complete encoding behavior.

const std = @import("std");

pub const prolog = "<?xml version='1.0'?>";
pub const separator = "\t\r\n            ";
pub const rights_notice = "All Rights Reserved BIR 2012.";
pub const document_prefix = prolog ++ separator;
pub const editable_tail = separator ++ rights_notice;
pub const final_tail = separator ++ rights_notice ++ "0";

pub const max_document_bytes: usize = 8 * 1024 * 1024;
pub const max_occurrences: usize = 4096;
pub const max_key_bytes: usize = 256;
pub const max_value_bytes: usize = 1024 * 1024;

/// Delimiters, the MSHTML-normalized separator, and ASCII output are grounded.
/// Complete machine-ANSI behavior is intentionally not claimed.
pub const exact_complete_byte_encoding_ready = false;
pub const ascii_byte_layer_exact = true;

pub const Marker = enum {
    editable,
    final,
};

pub const Occurrence = struct {
    key: []const u8,
    encoded_value: []const u8,
};

/// Live form controls are supplied in the frozen `frmMain.elements` order.
/// The tagged value prevents text/select values from being confused with the
/// lower-case JavaScript Boolean emitted for radio controls.
pub const ControlValue = union(enum) {
    text: []const u8,
    checked: bool,
};

pub const ControlInput = struct {
    id: []const u8,
    value: ControlValue,
};

pub const ParsedOccurrence = struct {
    source_order: u16,
    same_key_occurrence: u16,
    key: []const u8,
    encoded_value: []const u8,
};

pub const ParseError = std.mem.Allocator.Error || error{
    DocumentTooLarge,
    UnqualifiedByteEncoding,
    InvalidProlog,
    InvalidTail,
    InvalidSeparator,
    TooManyOccurrences,
    UnterminatedField,
    EmptyFieldKey,
    FieldKeyTooLong,
    InvalidFieldKey,
    MissingFieldDelimiter,
    MissingRepeatedFieldDelimiter,
    ValueTooLong,
    InvalidValueByte,
    ValueContainsMarkup,
};

pub const RenderError = std.mem.Allocator.Error || error{
    DocumentTooLarge,
    UnqualifiedByteEncoding,
    TooManyOccurrences,
    EmptyFieldKey,
    FieldKeyTooLong,
    InvalidFieldKey,
    ValueTooLong,
    InvalidValueByte,
    ValueContainsMarkup,
};

pub const ExactShapeError = error{
    WrongMarker,
    UnexpectedOccurrenceCount,
    UnexpectedOccurrenceKey,
};

pub const ParsedDocument = struct {
    const Self = @This();

    source: []u8,
    occurrences: []ParsedOccurrence,
    marker: Marker,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        wipeAndFreeParsedOccurrences(allocator, self.occurrences);
        wipeAndFreeBytes(allocator, self.source);
        self.* = undefined;
    }

    /// Reconstructs from parsed structure rather than echoing `source`, which
    /// proves that the parser retained every byte-bearing occurrence.
    pub fn renderAlloc(
        self: *const Self,
        allocator: std.mem.Allocator,
    ) RenderError![]u8 {
        var views: std.ArrayList(Occurrence) = .empty;
        defer wipeAndDeinitOccurrenceViews(allocator, &views);
        try views.ensureTotalCapacityPrecise(
            allocator,
            self.occurrences.len,
        );
        for (self.occurrences) |item| {
            views.appendAssumeCapacity(.{
                .key = item.key,
                .encoded_value = item.encoded_value,
            });
        }
        return renderOccurrencesAlloc(
            allocator,
            views.items,
            self.marker,
        );
    }

    pub fn occurrence(
        self: *const Self,
        key: []const u8,
        same_key_occurrence: u16,
    ) ?*const ParsedOccurrence {
        for (self.occurrences) |*item| {
            if (item.same_key_occurrence == same_key_occurrence and
                std.mem.eql(u8, item.key, key))
            {
                return item;
            }
        }
        return null;
    }

    /// Exact-form consumers call this after the lossless grammar parse.
    /// Generic parsing retains repeated and unknown well-formed `<div>`
    /// occurrences because the legacy loader ignores keys it does not query.
    pub fn validateExactKeys(
        self: *const Self,
        expected_keys: []const []const u8,
        expected_marker: Marker,
    ) ExactShapeError!void {
        if (self.marker != expected_marker) return error.WrongMarker;
        if (self.occurrences.len != expected_keys.len) {
            return error.UnexpectedOccurrenceCount;
        }
        for (self.occurrences, expected_keys) |actual, expected| {
            if (!std.mem.eql(u8, actual.key, expected)) {
                return error.UnexpectedOccurrenceKey;
            }
        }
    }
};

pub fn parse(
    allocator: std.mem.Allocator,
    input: []const u8,
) ParseError!ParsedDocument {
    if (input.len > max_document_bytes) return error.DocumentTooLarge;
    try validateAscii(input);
    if (!std.mem.startsWith(u8, input, document_prefix)) {
        return error.InvalidProlog;
    }

    const marker: Marker = if (std.mem.endsWith(u8, input, final_tail))
        .final
    else if (std.mem.endsWith(u8, input, editable_tail))
        .editable
    else
        return error.InvalidTail;
    const tail = switch (marker) {
        .editable => editable_tail,
        .final => final_tail,
    };
    if (input.len < document_prefix.len + tail.len) {
        return error.InvalidTail;
    }

    const owned = try allocator.dupe(u8, input);
    errdefer wipeAndFreeBytes(allocator, owned);

    const body_end = owned.len - tail.len;
    const body = owned[document_prefix.len..body_end];
    var parsed: std.ArrayList(ParsedOccurrence) = .empty;
    errdefer wipeAndDeinitParsedOccurrences(allocator, &parsed);

    var cursor: usize = 0;
    while (cursor < body.len) {
        if (parsed.items.len == max_occurrences) {
            return error.TooManyOccurrences;
        }
        if (!std.mem.startsWith(u8, body[cursor..], "<div>")) {
            return error.InvalidSeparator;
        }
        const content_start = cursor + "<div>".len;
        const close_relative = std.mem.indexOf(
            u8,
            body[content_start..],
            "</div>",
        ) orelse return error.UnterminatedField;
        const close_start = content_start + close_relative;
        const content = body[content_start..close_start];

        const first_equals = std.mem.indexOfScalar(u8, content, '=') orelse
            return error.MissingFieldDelimiter;
        const key = content[0..first_equals];
        try validateKey(key);

        const repeated_delimiter_len = key.len + 1;
        const remainder = content[first_equals + 1 ..];
        const repeated_delimiter_start =
            remainder.len -| repeated_delimiter_len;
        if (remainder.len < repeated_delimiter_len or
            !std.mem.eql(
                u8,
                remainder[repeated_delimiter_start .. repeated_delimiter_start + key.len],
                key,
            ) or
            remainder[remainder.len - 1] != '=')
        {
            return error.MissingRepeatedFieldDelimiter;
        }
        const encoded_value =
            remainder[0 .. remainder.len - repeated_delimiter_len];
        try validateValue(encoded_value);

        const after_close = close_start + "</div>".len;
        if (!std.mem.startsWith(u8, body[after_close..], separator)) {
            return error.InvalidSeparator;
        }

        var same_key_occurrence: u16 = 1;
        for (parsed.items) |earlier| {
            if (std.mem.eql(u8, earlier.key, key)) {
                same_key_occurrence = std.math.add(
                    u16,
                    same_key_occurrence,
                    1,
                ) catch return error.TooManyOccurrences;
            }
        }
        try parsed.append(allocator, .{
            .source_order = @intCast(parsed.items.len),
            .same_key_occurrence = same_key_occurrence,
            .key = key,
            .encoded_value = encoded_value,
        });
        cursor = after_close + separator.len;
    }

    const occurrences = try allocator.dupe(
        ParsedOccurrence,
        parsed.items,
    );
    wipeAndDeinitParsedOccurrences(allocator, &parsed);
    return .{
        .source = owned,
        .occurrences = occurrences,
        .marker = marker,
    };
}

pub fn renderOccurrencesAlloc(
    allocator: std.mem.Allocator,
    occurrences: []const Occurrence,
    marker: Marker,
) RenderError![]u8 {
    if (occurrences.len > max_occurrences) {
        return error.TooManyOccurrences;
    }

    const tail = switch (marker) {
        .editable => editable_tail,
        .final => final_tail,
    };
    var total = document_prefix.len + tail.len;
    for (occurrences) |item| {
        try validateKey(item.key);
        try validateValue(item.encoded_value);
        total = std.math.add(
            usize,
            total,
            "<div>".len + "=".len + "=".len + "</div>".len +
                separator.len,
        ) catch return error.DocumentTooLarge;
        total = std.math.add(
            usize,
            total,
            item.key.len * 2,
        ) catch return error.DocumentTooLarge;
        total = std.math.add(
            usize,
            total,
            item.encoded_value.len,
        ) catch return error.DocumentTooLarge;
        if (total > max_document_bytes) return error.DocumentTooLarge;
    }

    var output: std.ArrayList(u8) = .empty;
    errdefer wipeAndDeinitBytes(allocator, &output);
    try output.ensureTotalCapacityPrecise(allocator, total);
    output.appendSliceAssumeCapacity(document_prefix);
    for (occurrences) |item| {
        output.appendSliceAssumeCapacity("<div>");
        output.appendSliceAssumeCapacity(item.key);
        output.appendAssumeCapacity('=');
        output.appendSliceAssumeCapacity(item.encoded_value);
        output.appendSliceAssumeCapacity(item.key);
        output.appendSliceAssumeCapacity("=</div>");
        output.appendSliceAssumeCapacity(separator);
    }
    output.appendSliceAssumeCapacity(tail);
    std.debug.assert(output.items.len == total);
    return output.toOwnedSliceAssert();
}

fn wipeAndFreeBytes(
    allocator: std.mem.Allocator,
    bytes: []u8,
) void {
    wipeAndRawFree(u8, allocator, bytes);
}

fn wipeAndFreeParsedOccurrences(
    allocator: std.mem.Allocator,
    items: []ParsedOccurrence,
) void {
    wipeAndRawFree(ParsedOccurrence, allocator, items);
}

fn wipeAndDeinitParsedOccurrences(
    allocator: std.mem.Allocator,
    items: *std.ArrayList(ParsedOccurrence),
) void {
    wipeAndRawFree(
        ParsedOccurrence,
        allocator,
        items.allocatedSlice(),
    );
    items.* = .empty;
}

fn wipeAndDeinitOccurrenceViews(
    allocator: std.mem.Allocator,
    items: *std.ArrayList(Occurrence),
) void {
    wipeAndRawFree(Occurrence, allocator, items.allocatedSlice());
    items.* = .empty;
}

fn wipeAndDeinitBytes(
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),
) void {
    wipeAndRawFree(u8, allocator, bytes.allocatedSlice());
    bytes.* = .empty;
}

/// `Allocator.free` deliberately writes `undefined` before `rawFree` in Zig
/// 0.16. Secure cleanup must therefore cross the raw allocator boundary
/// directly after the volatile zero fill, while retaining the allocation's
/// original element alignment and byte length.
fn wipeAndRawFree(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: []T,
) void {
    if (items.len == 0) return;
    const bytes = std.mem.sliceAsBytes(items);
    std.crypto.secureZero(u8, bytes);
    allocator.rawFree(
        bytes,
        .of(T),
        @returnAddress(),
    );
}

fn validateAscii(value: []const u8) error{UnqualifiedByteEncoding}!void {
    for (value) |byte| {
        if (byte > 0x7f) return error.UnqualifiedByteEncoding;
    }
}

fn validateKey(key: []const u8) error{
    UnqualifiedByteEncoding,
    EmptyFieldKey,
    FieldKeyTooLong,
    InvalidFieldKey,
}!void {
    if (key.len == 0) return error.EmptyFieldKey;
    if (key.len > max_key_bytes) return error.FieldKeyTooLong;
    try validateAscii(key);
    for (key) |byte| {
        if (!(std.ascii.isAlphanumeric(byte) or
            byte == ':' or
            byte == '_' or
            byte == '-' or
            byte == '.'))
        {
            return error.InvalidFieldKey;
        }
    }
}

fn validateValue(value: []const u8) error{
    UnqualifiedByteEncoding,
    ValueTooLong,
    InvalidValueByte,
    ValueContainsMarkup,
}!void {
    if (value.len > max_value_bytes) return error.ValueTooLong;
    try validateAscii(value);
    for (value) |byte| {
        if (byte < 0x20 or byte == 0x7f) {
            return error.InvalidValueByte;
        }
        // A `<` can introduce a nested or premature HTML node in the exact
        // legacy `response.innerHTML` loader and therefore cannot be parsed
        // losslessly as one field body.
        if (byte == '<') return error.ValueContainsMarkup;
    }
}

const ZeroOnFreeAllocator = struct {
    const Self = @This();

    backing: std.mem.Allocator,
    target_length: usize,
    tracked_pointer: ?[*]u8 = null,
    tracked_allocations: usize = 0,
    tracked_frees: usize = 0,
    tracked_frees_were_zeroed: bool = true,
    first_nonzero_index: ?usize = null,
    first_nonzero_byte: ?u8 = null,

    fn init(
        backing: std.mem.Allocator,
        target_length: usize,
    ) Self {
        return .{
            .backing = backing,
            .target_length = target_length,
        };
    }

    fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(
        context: *anyopaque,
        length: usize,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(context));
        const result = self.backing.rawAlloc(
            length,
            alignment,
            return_address,
        ) orelse return null;
        if (length == self.target_length and
            self.tracked_pointer == null)
        {
            self.tracked_pointer = result;
            self.tracked_allocations += 1;
        }
        return result;
    }

    fn resize(
        context: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_length: usize,
        return_address: usize,
    ) bool {
        const self: *Self = @ptrCast(@alignCast(context));
        if (self.isTracked(memory.ptr)) return false;
        return self.backing.rawResize(
            memory,
            alignment,
            new_length,
            return_address,
        );
    }

    fn remap(
        context: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_length: usize,
        return_address: usize,
    ) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(context));
        if (self.isTracked(memory.ptr)) return null;
        return self.backing.rawRemap(
            memory,
            alignment,
            new_length,
            return_address,
        );
    }

    fn free(
        context: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) void {
        const self: *Self = @ptrCast(@alignCast(context));
        if (self.isTracked(memory.ptr)) {
            self.tracked_frees += 1;
            for (memory, 0..) |byte, index| {
                if (byte != 0) {
                    self.tracked_frees_were_zeroed = false;
                    self.first_nonzero_index = index;
                    self.first_nonzero_byte = byte;
                    break;
                }
            }
            self.tracked_pointer = null;
        }
        self.backing.rawFree(memory, alignment, return_address);
    }

    fn isTracked(self: *const Self, pointer: [*]u8) bool {
        return if (self.tracked_pointer) |tracked|
            tracked == pointer
        else
            false;
    }
};

const erasure_test_document =
    document_prefix ++
    "<div>erase-field=VALUE-MUST-BE-ERASEDerase-field=</div>" ++
    separator ++
    editable_tail;

fn exerciseAllAllocationPaths(allocator: std.mem.Allocator) !void {
    var parsed = try parse(allocator, erasure_test_document);
    defer parsed.deinit(allocator);
    const rendered = try parsed.renderAlloc(allocator);
    defer wipeAndFreeBytes(allocator, rendered);
    try std.testing.expectEqualSlices(
        u8,
        erasure_test_document,
        rendered,
    );
}

test "normal deinit zeroes the owned document before allocator free" {
    var checking = ZeroOnFreeAllocator.init(
        std.testing.allocator,
        erasure_test_document.len,
    );
    const allocator = checking.allocator();
    var parsed = try parse(allocator, erasure_test_document);
    try std.testing.expectEqual(@as(usize, 1), checking.tracked_allocations);
    try std.testing.expectEqual(@as(usize, 0), checking.tracked_frees);

    parsed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), checking.tracked_frees);
    try std.testing.expectEqual(
        @as(?u8, null),
        checking.first_nonzero_byte,
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        checking.first_nonzero_index,
    );
    try std.testing.expect(checking.tracked_frees_were_zeroed);
    try std.testing.expect(checking.tracked_pointer == null);
}

test "parse error zeroes owned values and releases partial metadata" {
    const malformed =
        document_prefix ++
        "<div>first=VALUE-MUST-BE-ERASEDfirst=</div>" ++ separator ++
        "<div>broken=sensitiveother=</div>" ++ separator ++
        editable_tail;
    var checking = ZeroOnFreeAllocator.init(
        std.testing.allocator,
        malformed.len,
    );
    const allocator = checking.allocator();

    try std.testing.expectError(
        error.MissingRepeatedFieldDelimiter,
        parse(allocator, malformed),
    );
    try std.testing.expectEqual(@as(usize, 1), checking.tracked_allocations);
    try std.testing.expectEqual(@as(usize, 1), checking.tracked_frees);
    try std.testing.expectEqual(
        @as(?u8, null),
        checking.first_nonzero_byte,
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        checking.first_nonzero_index,
    );
    try std.testing.expect(checking.tracked_frees_were_zeroed);
    try std.testing.expect(checking.tracked_pointer == null);
}

test "all parser and renderer allocation failures are leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exerciseAllAllocationPaths,
        .{},
    );
}

test "golden envelope preserves duplicate and unknown div occurrences" {
    const source =
        document_prefix ++
        "<div>alpha=onealpha=</div>" ++ separator ++
        "<div>alpha=twoalpha=</div>" ++ separator ++
        "<div>unknown-key=unknown-key=</div>" ++ separator ++
        final_tail;

    var parsed = try parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(Marker.final, parsed.marker);
    try std.testing.expectEqual(@as(usize, 3), parsed.occurrences.len);
    try std.testing.expectEqual(
        @as(u16, 2),
        parsed.occurrence("alpha", 2).?.same_key_occurrence,
    );
    try std.testing.expectEqualStrings(
        "",
        parsed.occurrence("unknown-key", 1).?.encoded_value,
    );

    const rendered = try parsed.renderAlloc(std.testing.allocator);
    defer wipeAndFreeBytes(std.testing.allocator, rendered);
    try std.testing.expectEqualSlices(u8, source, rendered);
}

test "exact shape allows expected duplicates and rejects unexpected duplicates" {
    const source =
        document_prefix ++
        "<div>same=firstsame=</div>" ++ separator ++
        "<div>same=secondsame=</div>" ++ separator ++
        editable_tail;
    var parsed = try parse(std.testing.allocator, source);
    defer parsed.deinit(std.testing.allocator);

    try parsed.validateExactKeys(&.{ "same", "same" }, .editable);
    try std.testing.expectError(
        error.UnexpectedOccurrenceKey,
        parsed.validateExactKeys(&.{ "same", "different" }, .editable),
    );
    try std.testing.expectError(
        error.UnexpectedOccurrenceCount,
        parsed.validateExactKeys(&.{"same"}, .editable),
    );
    try std.testing.expectError(
        error.WrongMarker,
        parsed.validateExactKeys(&.{ "same", "same" }, .final),
    );
}

test "malformed trailing lossy and unqualified byte structures fail closed" {
    const valid =
        document_prefix ++
        "<div>field=valuefield=</div>" ++ separator ++
        editable_tail;
    const cases = [_]struct {
        bytes: []const u8,
        expected: ParseError,
    }{
        .{ .bytes = "not-a-document", .expected = error.InvalidProlog },
        .{ .bytes = valid ++ "x", .expected = error.InvalidTail },
        .{
            .bytes = prolog ++ "\n<div>field=valuefield=</div>" ++
                separator ++ editable_tail,
            .expected = error.InvalidProlog,
        },
        .{
            .bytes = document_prefix ++
                "<div>field=valueother=</div>" ++ separator ++
                editable_tail,
            .expected = error.MissingRepeatedFieldDelimiter,
        },
        .{
            .bytes = document_prefix ++
                "<div>field=<span>value</span>field=</div>" ++ separator ++
                editable_tail,
            .expected = error.ValueContainsMarkup,
        },
        .{
            .bytes = document_prefix ++
                "<div>field=\xC3\xA9field=</div>" ++ separator ++
                editable_tail,
            .expected = error.UnqualifiedByteEncoding,
        },
    };
    for (cases) |case| {
        try std.testing.expectError(
            case.expected,
            parse(std.testing.allocator, case.bytes),
        );
    }
}
