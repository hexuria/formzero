//! Byte envelope for the 1601C January 2018 legacy pseudo-XML document.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - `xmlFormat` and `xmlClose` markup, lines 1760-1762
//! - envelope assembly in `saveXML`, lines 2213-2243
//! - final tails at lines 2080, 2243, 2471, 2679
//! - editable tails at lines 2474, 2681, 3865
//!
//! The envelope is byte-for-byte the same as 1701Q's: the same prolog, the
//! same separator, the same rights notice, and the same pair of tails. A
//! test asserts that against `form_1701q_2018.document` rather than
//! restating it, so a divergence in either form surfaces.
//!
//! `xmlFormat` carries a tab, a line feed and twelve spaces in source. The
//! controlled MSHTML observation recorded for 1701Q establishes that
//! `innerHTML` normalizes that line feed to CRLF, so the separator read at
//! runtime is tab, CR, LF, twelve spaces. That observation is inherited
//! rather than repeated here.
//!
//! The two tails differ by a single trailing `0`. Seven call sites assemble
//! a tail: four append the `0` and three do not, which is what distinguishes
//! a Final Copy from an editable save.
//!
//! ## Encoding
//!
//! `Scripting.FileSystemObject.CreateTextFile` writes through the machine
//! ANSI code page, which is not an invariant of the form package. This
//! module therefore accepts only the code-page-independent ASCII byte
//! subset, exactly as 1701Q's does. `ascii_byte_layer_exact` is true and
//! `exact_complete_byte_encoding_ready` stays false until paired official
//! captures qualify the complete encoding behaviour.

const std = @import("std");
const evidence = @import("evidence.zig");

pub const prolog = "<?xml version='1.0'?>";
/// Tab, CR, LF, twelve spaces, after MSHTML normalizes the source line feed.
pub const separator = "\t\r\n            ";
pub const rights_notice = "All Rights Reserved BIR 2012.";
pub const document_prefix = prolog ++ separator;
pub const editable_tail = separator ++ rights_notice;
pub const final_tail = separator ++ rights_notice ++ "0";

/// Occurrence delimiters. Each occurrence is written as
/// `<div>{id}={value}{id}=</div>` and followed by the separator.
pub const occurrence_open = "<div>";
pub const occurrence_close = "</div>";
pub const key_terminator = "=";

pub const max_document_bytes: usize = 8 * 1024 * 1024;
pub const max_occurrences: usize = 4096;
pub const max_key_bytes: usize = 256;
pub const max_value_bytes: usize = 1024 * 1024;

/// Delimiters, the MSHTML-normalized separator and ASCII output are
/// grounded. Complete machine-ANSI behaviour is intentionally not claimed.
pub const exact_complete_byte_encoding_ready = false;
pub const ascii_byte_layer_exact = true;

/// Call sites that assemble each tail in the HTA.
pub const final_tail_call_sites = [_]u32{ 2080, 2243, 2471, 2679 };
pub const editable_tail_call_sites = [_]u32{ 2474, 2681, 3865 };

pub const Marker = enum {
    editable,
    final,

    pub fn tail(self: Marker) []const u8 {
        return switch (self) {
            .editable => editable_tail,
            .final => final_tail,
        };
    }
};

pub const EnvelopeError = error{
    DocumentTooLarge,
    MissingPrologue,
    MissingTail,
    NonAsciiByte,
    EmptyDocument,
};

fn isAscii(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte > 0x7F) return false;
    }
    return true;
}

/// Which tail a document carries. The final tail extends the editable one,
/// so it must be tested first.
pub fn markerOf(document: []const u8) EnvelopeError!Marker {
    if (document.len == 0) return error.EmptyDocument;
    if (document.len > max_document_bytes) return error.DocumentTooLarge;
    if (!isAscii(document)) return error.NonAsciiByte;
    if (!std.mem.startsWith(u8, document, document_prefix)) {
        return error.MissingPrologue;
    }
    if (std.mem.endsWith(u8, document, final_tail)) return .final;
    if (std.mem.endsWith(u8, document, editable_tail)) return .editable;
    return error.MissingTail;
}

/// The occurrence region between the prologue and the tail.
pub fn bodyOf(document: []const u8) EnvelopeError![]const u8 {
    const marker = try markerOf(document);
    const tail = marker.tail();
    const start = document_prefix.len;
    const end = document.len - tail.len;
    if (end < start) return error.MissingTail;
    return document[start..end];
}

test "1601C envelope constants match 1701Q byte for byte" {
    const q = @import("../form_1701q_2018/document.zig");
    try std.testing.expectEqualStrings(q.prolog, prolog);
    try std.testing.expectEqualStrings(q.separator, separator);
    try std.testing.expectEqualStrings(q.rights_notice, rights_notice);
    try std.testing.expectEqualStrings(q.editable_tail, editable_tail);
    try std.testing.expectEqualStrings(q.final_tail, final_tail);
}

test "1601C the separator is the MSHTML-normalized form" {
    // Tab, CR, LF, then twelve spaces.
    try std.testing.expectEqual(@as(usize, 15), separator.len);
    try std.testing.expectEqual(@as(u8, '\t'), separator[0]);
    try std.testing.expectEqual(@as(u8, '\r'), separator[1]);
    try std.testing.expectEqual(@as(u8, '\n'), separator[2]);
    for (separator[3..]) |byte| try std.testing.expectEqual(@as(u8, ' '), byte);
}

test "1601C the two tails differ only by a trailing zero" {
    try std.testing.expect(std.mem.startsWith(u8, final_tail, editable_tail));
    try std.testing.expectEqual(editable_tail.len + 1, final_tail.len);
    try std.testing.expectEqual(@as(u8, '0'), final_tail[final_tail.len - 1]);
    // Four call sites append it, three do not.
    try std.testing.expectEqual(@as(usize, 4), final_tail_call_sites.len);
    try std.testing.expectEqual(@as(usize, 3), editable_tail_call_sites.len);
}

test "1601C marker detection prefers the final tail" {
    const editable = document_prefix ++ "<div>a=1a=</div>" ++ editable_tail;
    const final = document_prefix ++ "<div>a=1a=</div>" ++ final_tail;
    try std.testing.expectEqual(Marker.editable, try markerOf(editable));
    try std.testing.expectEqual(Marker.final, try markerOf(final));
    // A final document also ends with the editable tail plus a zero, so
    // testing the editable tail first would misclassify it.
    try std.testing.expect(std.mem.endsWith(u8, final_tail, "0"));
}

test "1601C envelope failures are explicit" {
    try std.testing.expectError(error.EmptyDocument, markerOf(""));
    try std.testing.expectError(
        error.MissingPrologue,
        markerOf("<div>a=1a=</div>" ++ final_tail),
    );
    try std.testing.expectError(
        error.MissingTail,
        markerOf(document_prefix ++ "<div>a=1a=</div>"),
    );
    try std.testing.expectError(
        error.NonAsciiByte,
        markerOf(document_prefix ++ "\xC3\xA9" ++ final_tail),
    );
}

test "1601C the body excludes both the prologue and the tail" {
    const occurrences = "<div>a=1a=</div>" ++ separator;
    const document = document_prefix ++ occurrences ++ final_tail;
    try std.testing.expectEqualStrings(occurrences, try bodyOf(document));

    const empty = document_prefix ++ final_tail;
    try std.testing.expectEqualStrings("", try bodyOf(empty));
}

test "1601C claims the ASCII layer only" {
    try std.testing.expect(ascii_byte_layer_exact);
    try std.testing.expect(!exact_complete_byte_encoding_ready);
    // Closure is complete, so the gate here is encoding evidence rather
    // than a missing script.
    try std.testing.expect(evidence.readiness.dependency_closure);
    try std.testing.expect(!evidence.readiness.editable_serializer_exact);
    try std.testing.expect(!evidence.readiness.final_plaintext_serializer_exact);
}
