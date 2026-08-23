//! Final Copy rules for 1601C January 2018 (ENCS).
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - the `isFinalCopy` branch at lines 2470-2476
//! - detection on load, lines 1890-1896
//! - detection from a file, line 2147
//! - read-only consequences at lines 1853, 1894, 2205, 3838, 4462
//!
//! ## One byte separates the two documents
//!
//! The writer branches only at the tail:
//!
//! - Final Copy appends the rights notice and a trailing `0`
//! - an editable save appends the rights notice alone
//!
//! Nothing else about the occurrence body differs, so a Final Copy is an
//! editable document plus one byte. `document.Marker` already carries that
//! distinction; this module names its consequences.
//!
//! ## Detection is a substring sniff
//!
//! Both call sites test `indexOf("All Rights Reserved BIR 2012.0") >= 0`
//! against the whole document rather than parsing the tail. A document
//! carrying that literal anywhere in a value would be read as final. The
//! same sniff is pinned for 1601EQ in its evidence module.
//!
//! ## Finality is a latch, not a document property
//!
//! Setting the flag disables Validate and Save, disables every element after
//! a delay while re-enabling Upload and the page navigation, and blocks the
//! profile save entirely. Once set on load or by writing a Final Copy,
//! nothing in the form clears it.
//!
//! Rules only. `final_plaintext_serializer_exact` stays false pending the
//! encoding captures `document.zig` describes.

const std = @import("std");
const document = @import("document.zig");
const evidence = @import("evidence.zig");

pub const ready = false;

/// The literal both detection sites search for.
pub const final_copy_marker = "All Rights Reserved BIR 2012.0";

/// Detection reads the whole document, not just its tail.
pub const detection_is_substring_search = true;

/// Lines where the marker is searched for.
pub const detection_call_sites = [_]u32{ 1890, 2147 };

/// What setting the read-only latch changes.
pub const ReadOnlyEffect = enum {
    disables_validate,
    disables_save,
    disables_every_element,
    enables_upload,
    enables_page_navigation,
    blocks_profile_save,
};

pub const read_only_effects = [_]ReadOnlyEffect{
    .disables_validate,
    .disables_save,
    .disables_every_element,
    .enables_upload,
    .enables_page_navigation,
    .blocks_profile_save,
};

/// Nothing in the form clears the latch once it is set.
pub const read_only_is_cleared_anywhere = false;

/// Byte difference between the two documents.
pub fn tailFor(marker: document.Marker) []const u8 {
    return marker.tail();
}

pub fn isFinalCopy(text: []const u8) bool {
    return std.mem.indexOf(u8, text, final_copy_marker) != null;
}

test "1601C a Final Copy is an editable document plus one byte" {
    try std.testing.expectEqual(
        document.editable_tail.len + 1,
        document.final_tail.len,
    );
    try std.testing.expect(std.mem.startsWith(
        u8,
        document.final_tail,
        document.editable_tail,
    ));
    try std.testing.expectEqualStrings(document.final_tail, tailFor(.final));
    try std.testing.expectEqualStrings(document.editable_tail, tailFor(.editable));
}

test "1601C the marker is the rights notice plus the trailing zero" {
    try std.testing.expectEqualStrings(
        document.rights_notice ++ "0",
        final_copy_marker,
    );
    try std.testing.expect(std.mem.endsWith(u8, document.final_tail, final_copy_marker));
    try std.testing.expect(!std.mem.endsWith(u8, document.editable_tail, final_copy_marker));
}

test "1601C detection searches the whole document, not the tail" {
    try std.testing.expect(detection_is_substring_search);
    try std.testing.expectEqual(@as(usize, 2), detection_call_sites.len);

    const final = document.document_prefix ++ "<div>a=1a=</div>" ++ document.final_tail;
    const editable = document.document_prefix ++ "<div>a=1a=</div>" ++ document.editable_tail;
    try std.testing.expect(isFinalCopy(final));
    try std.testing.expect(!isFinalCopy(editable));

    // A value carrying the literal is read as final wherever it appears.
    const spoofed = document.document_prefix ++
        "<div>a=" ++ final_copy_marker ++ "a=</div>" ++ document.editable_tail;
    try std.testing.expect(isFinalCopy(spoofed));
    // The envelope still classifies it by its tail, so the two disagree.
    try std.testing.expectEqual(document.Marker.editable, try document.markerOf(spoofed));
}

test "1601C finality latches and is never cleared" {
    try std.testing.expectEqual(@as(usize, 6), read_only_effects.len);
    try std.testing.expect(!read_only_is_cleared_anywhere);

    var disables: usize = 0;
    var enables: usize = 0;
    for (read_only_effects) |effect| {
        switch (effect) {
            .disables_validate, .disables_save, .disables_every_element, .blocks_profile_save => disables += 1,
            .enables_upload, .enables_page_navigation => enables += 1,
        }
    }
    // It closes editing and opens the upload path in the same step.
    try std.testing.expectEqual(@as(usize, 4), disables);
    try std.testing.expectEqual(@as(usize, 2), enables);
}

test "1601C the codec pins rules without claiming an exact serializer" {
    try std.testing.expect(!ready);
    try std.testing.expect(!evidence.readiness.final_plaintext_serializer_exact);
    try std.testing.expect(!document.exact_complete_byte_encoding_ready);
    try std.testing.expect(document.ascii_byte_layer_exact);
}
