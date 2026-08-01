//! Ordered, value-free occurrence metadata.
//!
//! This type deliberately accepts only an ordered slice. A map may be
//! derived for UI lookup later, but cannot become serialization authority.
//! Payload values and byte serialization do not belong in this foundation.

const std = @import("std");
const ids = @import("../forms/id.zig");
const identity = @import("identity.zig");

pub const OriginKind = enum(u8) {
    profile = 1,
    transaction = 2,
    preparer = 3,
    filing_context = 4,
    external_evidence = 5,
    derived = 6,
    system = 7,
    unreviewed = 8,
};

pub const EmissionKind = enum(u8) {
    unreviewed = 1,
    raw = 2,
    legacy_escape = 3,
    concatenated_legacy_escape = 4,
    checked_boolean = 5,
    constant = 6,
};

pub const ArtifactInclusion = packed struct(u8) {
    editable_save: bool = false,
    final_copy_plaintext: bool = false,
    _reserved: u6 = 0,
};

pub const EvidenceSpan = struct {
    evidence_id: []const u8,
    first_line: u32,
    last_line: u32,
};

/// The field mapping remains explicitly unreviewed until Phase B reconciles
/// the source control with the canonical product catalog.
pub const CanonicalField = union(enum) {
    mapped: ids.FieldId,
    unreviewed_source_control: []const u8,
};

pub const SourceControls = union(enum) {
    one: []const u8,
    two: [2][]const u8,

    pub fn len(self: SourceControls) u8 {
        return switch (self) {
            .one => 1,
            .two => 2,
        };
    }

    pub fn at(self: SourceControls, index: u8) ?[]const u8 {
        return switch (self) {
            .one => |control| if (index == 0) control else null,
            .two => |controls| if (index < controls.len)
                controls[index]
            else
                null,
        };
    }
};

pub const OccurrenceMetadata = struct {
    /// One-based and contiguous in the artifact occurrence stream.
    ordinal: u16,
    canonical_field: CanonicalField,
    serialized_key: []const u8,
    /// One-based counter among occurrences with the same serialized key.
    same_key_occurrence: u16,
    source_controls: SourceControls,
    source_control_first_line: u32,
    source_control_last_line: u32,
    origin: OriginKind,
    inclusion: ArtifactInclusion,
    emission: EmissionKind,
    evidence: EvidenceSpan,
};

pub const InventorySummary = struct {
    form_id: []const u8,
    form_first_line: u32,
    form_last_line: u32,
    static_form_controls: u16,
    runtime_created_form_controls: u16 = 0,
    serializer_eligible_controls: u16,
    editable_occurrences: u16,
    final_copy_occurrences: u16,
    runtime_control_creation_observed: bool,
    evidence_id: []const u8,

    pub fn validate(self: InventorySummary) error{
        InvalidFormSpan,
        InvalidInventoryCount,
        EmptyEvidenceId,
    }!void {
        if (self.form_first_line == 0 or
            self.form_last_line < self.form_first_line)
        {
            return error.InvalidFormSpan;
        }
        const total_form_controls = std.math.add(
            u16,
            self.static_form_controls,
            self.runtime_created_form_controls,
        ) catch return error.InvalidInventoryCount;
        if (self.serializer_eligible_controls > total_form_controls or
            self.editable_occurrences > self.serializer_eligible_controls or
            self.final_copy_occurrences > self.serializer_eligible_controls)
        {
            return error.InvalidInventoryCount;
        }
        if (self.runtime_control_creation_observed !=
            (self.runtime_created_form_controls != 0))
        {
            return error.InvalidInventoryCount;
        }
        if (self.evidence_id.len == 0) return error.EmptyEvidenceId;
    }
};

pub const ManifestError = error{
    EmptyManifest,
    NonContiguousOrdinal,
    EmptySerializedKey,
    InvalidSameKeyOccurrence,
    EmptySourceControlSet,
    EmptySourceControlId,
    EmptyEvidenceId,
    InvalidEvidenceSpan,
};

pub const OrderedOccurrenceManifest = struct {
    const Self = @This();

    items: []const OccurrenceMetadata,

    pub fn init(items: []const OccurrenceMetadata) ManifestError!Self {
        if (items.len == 0) return error.EmptyManifest;
        for (items, 0..) |item, index| {
            if (item.ordinal != index + 1) {
                return error.NonContiguousOrdinal;
            }
            if (item.serialized_key.len == 0) {
                return error.EmptySerializedKey;
            }
            for (0..item.source_controls.len()) |control_index| {
                const control_id = item.source_controls.at(
                    @intCast(control_index),
                ).?;
                if (control_id.len == 0) return error.EmptySourceControlId;
            }
            if (item.source_control_first_line == 0 or
                item.source_control_last_line <
                    item.source_control_first_line)
            {
                return error.InvalidEvidenceSpan;
            }
            if (item.evidence.evidence_id.len == 0) {
                return error.EmptyEvidenceId;
            }
            if (item.evidence.first_line == 0 or
                item.evidence.last_line < item.evidence.first_line)
            {
                return error.InvalidEvidenceSpan;
            }

            var expected_same_key: u16 = 1;
            for (items[0..index]) |earlier| {
                if (std.mem.eql(
                    u8,
                    earlier.serialized_key,
                    item.serialized_key,
                )) {
                    expected_same_key += 1;
                }
            }
            if (item.same_key_occurrence != expected_same_key) {
                return error.InvalidSameKeyOccurrence;
            }
        }
        return .{ .items = items };
    }

    pub fn findKeyOccurrence(
        self: Self,
        serialized_key: []const u8,
        same_key_occurrence: u16,
    ) ?*const OccurrenceMetadata {
        for (self.items) |*item| {
            if (item.same_key_occurrence == same_key_occurrence and
                std.mem.eql(u8, item.serialized_key, serialized_key))
            {
                return item;
            }
        }
        return null;
    }

    /// Digest iteration is the stored slice order. It never sorts or builds a
    /// key map, so repeated occurrences remain distinct.
    pub fn canonicalDigest(self: Self) identity.Sha256Digest {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update("ebirforms.ordered-occurrence-metadata.v1");
        updateU32(&hash, @intCast(self.items.len));
        for (self.items) |item| {
            updateU16(&hash, item.ordinal);
            switch (item.canonical_field) {
                .mapped => |field_id| {
                    hash.update(&.{1});
                    updateLengthPrefixed(&hash, field_id.asSlice());
                },
                .unreviewed_source_control => |control_id| {
                    hash.update(&.{2});
                    updateLengthPrefixed(&hash, control_id);
                },
            }
            updateLengthPrefixed(&hash, item.serialized_key);
            updateU16(&hash, item.same_key_occurrence);
            hash.update(&.{item.source_controls.len()});
            for (0..item.source_controls.len()) |control_index| {
                updateLengthPrefixed(
                    &hash,
                    item.source_controls.at(@intCast(control_index)).?,
                );
            }
            updateU32(&hash, item.source_control_first_line);
            updateU32(&hash, item.source_control_last_line);
            hash.update(&.{@intFromEnum(item.origin)});
            hash.update(&.{@bitCast(item.inclusion)});
            hash.update(&.{@intFromEnum(item.emission)});
            updateLengthPrefixed(&hash, item.evidence.evidence_id);
            updateU32(&hash, item.evidence.first_line);
            updateU32(&hash, item.evidence.last_line);
        }
        var result: identity.Sha256Digest = .{ .bytes = undefined };
        hash.final(&result.bytes);
        return result;
    }
};

fn updateLengthPrefixed(
    hash: *std.crypto.hash.sha2.Sha256,
    value: []const u8,
) void {
    std.debug.assert(value.len <= std.math.maxInt(u16));
    updateU16(hash, @intCast(value.len));
    hash.update(value);
}

fn updateU16(hash: *std.crypto.hash.sha2.Sha256, value: u16) void {
    hash.update(&.{
        @intCast(value >> 8),
        @intCast(value & 0xff),
    });
}

fn updateU32(hash: *std.crypto.hash.sha2.Sha256, value: u32) void {
    hash.update(&.{
        @intCast(value >> 24),
        @intCast((value >> 16) & 0xff),
        @intCast((value >> 8) & 0xff),
        @intCast(value & 0xff),
    });
}

const ordered_fixture = [_]OccurrenceMetadata{
    .{
        .ordinal = 1,
        .canonical_field = .{
            .mapped = ids.FieldId.initComptime("test.field.a"),
        },
        .serialized_key = "repeated-key",
        .same_key_occurrence = 1,
        .source_controls = .{ .one = "frm1701q:test-a" },
        .source_control_first_line = 1,
        .source_control_last_line = 1,
        .origin = .unreviewed,
        .inclusion = .{ .editable_save = true },
        .emission = .unreviewed,
        .evidence = .{
            .evidence_id = "desktop-7.9.6-1701q",
            .first_line = 1,
            .last_line = 1,
        },
    },
    .{
        .ordinal = 2,
        .canonical_field = .{
            .mapped = ids.FieldId.initComptime("test.field.b"),
        },
        .serialized_key = "other-key",
        .same_key_occurrence = 1,
        .source_controls = .{ .one = "frm1701q:test-b" },
        .source_control_first_line = 2,
        .source_control_last_line = 2,
        .origin = .unreviewed,
        .inclusion = .{ .final_copy_plaintext = true },
        .emission = .unreviewed,
        .evidence = .{
            .evidence_id = "desktop-7.9.6-1701q",
            .first_line = 2,
            .last_line = 2,
        },
    },
    .{
        .ordinal = 3,
        .canonical_field = .{
            .mapped = ids.FieldId.initComptime("test.field.c"),
        },
        .serialized_key = "repeated-key",
        .same_key_occurrence = 2,
        .source_controls = .{ .one = "frm1701q:test-c" },
        .source_control_first_line = 3,
        .source_control_last_line = 3,
        .origin = .unreviewed,
        .inclusion = .{
            .editable_save = true,
            .final_copy_plaintext = true,
        },
        .emission = .unreviewed,
        .evidence = .{
            .evidence_id = "desktop-7.9.6-1701q",
            .first_line = 3,
            .last_line = 3,
        },
    },
};

test "ordered slice preserves repeated serialized keys" {
    const manifest = try OrderedOccurrenceManifest.init(&ordered_fixture);
    try std.testing.expectEqual(@as(usize, 3), manifest.items.len);
    const second = manifest.findKeyOccurrence("repeated-key", 2).?;
    try std.testing.expectEqual(@as(u16, 3), second.ordinal);
}

test "non-contiguous order and collapsed repeated keys are rejected" {
    var reordered = ordered_fixture;
    const swap = reordered[0];
    reordered[0] = reordered[1];
    reordered[1] = swap;
    try std.testing.expectError(
        error.NonContiguousOrdinal,
        OrderedOccurrenceManifest.init(&reordered),
    );

    var collapsed = ordered_fixture;
    collapsed[2].same_key_occurrence = 1;
    try std.testing.expectError(
        error.InvalidSameKeyOccurrence,
        OrderedOccurrenceManifest.init(&collapsed),
    );
}

test "occurrence digest changes when reviewed order changes" {
    const original = try OrderedOccurrenceManifest.init(&ordered_fixture);

    var reordered = ordered_fixture;
    reordered[0] = ordered_fixture[1];
    reordered[0].ordinal = 1;
    reordered[1] = ordered_fixture[0];
    reordered[1].ordinal = 2;
    reordered[2].same_key_occurrence = 2;
    const changed = try OrderedOccurrenceManifest.init(&reordered);

    const original_digest = original.canonicalDigest();
    const changed_digest = changed.canonicalDigest();
    try std.testing.expect(!original_digest.eql(&changed_digest));
}
