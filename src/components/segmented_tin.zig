//! Allocation-free state for a 3-3-3-5 TIN input.
//!
//! This module owns only text normalization and segment distribution. Native
//! views remain responsible for focus and rendering, while the validated tax
//! profile field remains responsible for deciding whether a value can be
//! saved. In particular, 12- and 13-digit legacy values remain visible exactly
//! as stored and are never padded into a new 14-digit identity.

const std = @import("std");

pub const segment_count: usize = 4;
pub const maximum_digit_count: usize = 14;
pub const segment_capacities = [segment_count]u8{ 3, 3, 3, 5 };

pub const InputResult = struct {
    accepted_digits: usize,
    dropped_digits: usize,
    /// Suggested segment for the view to focus after the edit.
    focus_segment: usize,
};

pub const SegmentedTin = struct {
    const Self = @This();

    buffers: [segment_count][5]u8 = undefined,
    lengths: [segment_count]u8 = [_]u8{0} ** segment_count,

    pub fn fromText(raw: []const u8) Self {
        var result = Self{};
        _ = result.replaceFromText(raw);
        return result;
    }

    /// Replaces all segments with the first 14 ASCII digits found in `raw`.
    /// Separators, labels, and other non-digit bytes are ignored.
    pub fn replaceFromText(self: *Self, raw: []const u8) InputResult {
        self.clear();
        return self.distributeFrom(0, raw);
    }

    /// Replaces one segment, or distributes a paste through later segments.
    ///
    /// Ordinary edits that fit the selected segment leave later segments
    /// unchanged. If the input contains more digits than that segment can
    /// hold, the operation is treated as a paste: the selected and all later
    /// segments are cleared, then filled from left to right.
    pub fn replaceSegment(
        self: *Self,
        index: usize,
        raw: []const u8,
    ) ?InputResult {
        if (index >= segment_count) return null;

        const digit_count = countDigits(raw);
        const capacity: usize = segment_capacities[index];
        if (digit_count <= capacity) {
            self.lengths[index] = 0;
            for (raw) |byte| {
                if (!std.ascii.isDigit(byte)) continue;
                const offset: usize = self.lengths[index];
                self.buffers[index][offset] = byte;
                self.lengths[index] += 1;
            }
            return .{
                .accepted_digits = digit_count,
                .dropped_digits = 0,
                .focus_segment = if (digit_count == capacity and
                    index + 1 < segment_count)
                    index + 1
                else
                    index,
            };
        }

        self.clearFrom(index);
        return self.distributeFrom(index, raw);
    }

    pub fn clear(self: *Self) void {
        self.lengths = [_]u8{0} ** segment_count;
    }

    pub fn clearFrom(self: *Self, start: usize) void {
        if (start >= segment_count) return;
        for (self.lengths[start..]) |*length| length.* = 0;
    }

    pub fn segmentText(self: *const Self, index: usize) ?[]const u8 {
        if (index >= segment_count) return null;
        return self.buffers[index][0..self.lengths[index]];
    }

    pub fn digitCount(self: *const Self) usize {
        var count: usize = 0;
        for (self.lengths) |length| count += length;
        return count;
    }

    /// True only for the required new 3-3-3-5 profile format.
    pub fn isComplete(self: *const Self) bool {
        return std.mem.eql(u8, &self.lengths, &segment_capacities);
    }

    /// True for a previously stored 3-3-3-(3..5) TIN.
    ///
    /// This permits the editor to show legacy values without manufacturing
    /// branch-code zeroes. It is not permission to save a new short TIN.
    pub fn hasLegacyStoredLength(self: *const Self) bool {
        return self.lengths[0] == 3 and
            self.lengths[1] == 3 and
            self.lengths[2] == 3 and
            self.lengths[3] >= 3 and
            self.lengths[3] <= 5;
    }

    pub fn writeDigits(
        self: *const Self,
        output: []u8,
    ) error{NoSpaceLeft}![]const u8 {
        const needed = self.digitCount();
        if (output.len < needed) return error.NoSpaceLeft;

        var offset: usize = 0;
        for (0..segment_count) |index| {
            const segment = self.segmentText(index).?;
            @memcpy(output[offset .. offset + segment.len], segment);
            offset += segment.len;
        }
        return output[0..offset];
    }

    pub fn writeFormatted(
        self: *const Self,
        output: []u8,
    ) error{NoSpaceLeft}![]const u8 {
        const digit_count = self.digitCount();
        var populated_segments: usize = 0;
        for (self.lengths) |length| {
            if (length != 0) populated_segments += 1;
        }
        const separator_count = populated_segments -| 1;
        if (output.len < digit_count + separator_count) {
            return error.NoSpaceLeft;
        }

        var offset: usize = 0;
        var wrote_segment = false;
        for (0..segment_count) |index| {
            const segment = self.segmentText(index).?;
            if (segment.len == 0) continue;
            if (wrote_segment) {
                output[offset] = '-';
                offset += 1;
            }
            @memcpy(output[offset .. offset + segment.len], segment);
            offset += segment.len;
            wrote_segment = true;
        }
        return output[0..offset];
    }

    fn distributeFrom(
        self: *Self,
        start: usize,
        raw: []const u8,
    ) InputResult {
        var segment_index = start;
        var accepted: usize = 0;
        var dropped: usize = 0;
        var last_written = if (start < segment_count) start else segment_count - 1;

        for (raw) |byte| {
            if (!std.ascii.isDigit(byte)) continue;
            while (segment_index < segment_count and
                self.lengths[segment_index] == segment_capacities[segment_index])
            {
                segment_index += 1;
            }
            if (segment_index == segment_count) {
                dropped += 1;
                continue;
            }

            const offset: usize = self.lengths[segment_index];
            self.buffers[segment_index][offset] = byte;
            self.lengths[segment_index] += 1;
            accepted += 1;
            last_written = segment_index;
        }

        const focus_segment = if (last_written + 1 < segment_count and
            self.lengths[last_written] == segment_capacities[last_written])
            last_written + 1
        else
            last_written;
        return .{
            .accepted_digits = accepted,
            .dropped_digits = dropped,
            .focus_segment = focus_segment,
        };
    }
};

fn countDigits(raw: []const u8) usize {
    var result: usize = 0;
    for (raw) |byte| {
        if (std.ascii.isDigit(byte)) result += 1;
    }
    return result;
}

test "TIN helper filters and distributes a full paste" {
    var tin = SegmentedTin{};
    const update = tin.replaceFromText("TIN: 123-456-789-00000 ext");

    try std.testing.expectEqual(@as(usize, 14), update.accepted_digits);
    try std.testing.expectEqual(@as(usize, 0), update.dropped_digits);
    try std.testing.expectEqual(@as(usize, 3), update.focus_segment);
    try std.testing.expectEqualStrings("123", tin.segmentText(0).?);
    try std.testing.expectEqualStrings("456", tin.segmentText(1).?);
    try std.testing.expectEqualStrings("789", tin.segmentText(2).?);
    try std.testing.expectEqualStrings("00000", tin.segmentText(3).?);
    try std.testing.expect(tin.isComplete());
}

test "TIN helper distributes paste from the edited segment" {
    var tin = SegmentedTin.fromText("12311122233333");
    const update = tin.replaceSegment(1, "456-789-00000").?;

    try std.testing.expectEqual(@as(usize, 11), update.accepted_digits);
    try std.testing.expectEqualStrings("123", tin.segmentText(0).?);
    try std.testing.expectEqualStrings("456", tin.segmentText(1).?);
    try std.testing.expectEqualStrings("789", tin.segmentText(2).?);
    try std.testing.expectEqualStrings("00000", tin.segmentText(3).?);
    try std.testing.expect(tin.isComplete());
}

test "ordinary segment edits filter characters and preserve later segments" {
    var tin = SegmentedTin.fromText("12345678900000");
    const update = tin.replaceSegment(1, "a9-8b7").?;

    try std.testing.expectEqual(@as(usize, 3), update.accepted_digits);
    try std.testing.expectEqual(@as(usize, 2), update.focus_segment);
    try std.testing.expectEqualStrings("987", tin.segmentText(1).?);
    try std.testing.expectEqualStrings("789", tin.segmentText(2).?);
    try std.testing.expectEqualStrings("00000", tin.segmentText(3).?);
}

test "legacy 12 through 14 digit TINs are preserved without padding" {
    const values = [_][]const u8{
        "123456789000",
        "1234567890000",
        "12345678900000",
    };
    const expected_branches = [_][]const u8{ "000", "0000", "00000" };
    const expected_formatted = [_][]const u8{
        "123-456-789-000",
        "123-456-789-0000",
        "123-456-789-00000",
    };

    for (values, expected_branches, expected_formatted) |
        raw,
        expected_branch,
        formatted,
    | {
        const tin = SegmentedTin.fromText(raw);
        try std.testing.expect(tin.hasLegacyStoredLength());
        try std.testing.expectEqualStrings(expected_branch, tin.segmentText(3).?);

        var digits_buffer: [maximum_digit_count]u8 = undefined;
        try std.testing.expectEqualStrings(
            raw,
            try tin.writeDigits(&digits_buffer),
        );
        var formatted_buffer: [maximum_digit_count + 3]u8 = undefined;
        try std.testing.expectEqualStrings(
            formatted,
            try tin.writeFormatted(&formatted_buffer),
        );
    }
}

test "TIN helper caps overlong pasted digits and reports invalid indices" {
    var tin = SegmentedTin{};
    const update = tin.replaceFromText("123456789000001234");
    try std.testing.expectEqual(@as(usize, 14), update.accepted_digits);
    try std.testing.expectEqual(@as(usize, 4), update.dropped_digits);
    try std.testing.expect(tin.isComplete());
    try std.testing.expect(tin.segmentText(4) == null);
    try std.testing.expect(tin.replaceSegment(4, "123") == null);
}
