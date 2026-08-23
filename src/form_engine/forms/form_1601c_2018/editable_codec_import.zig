//! HTA-local 1601C import paths.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - `loadXML` lines 1875-1905
//! - `loadBGXML` lines 3735-3752
//! - `showModalImport` and `cancelImportModal` lines 4162-4170
//!
//! Two readers bring a saved file back into the form, and both work the same
//! way: open through a FileSystemObject, read the whole file into a hidden
//! div's `innerHTML`, close, then walk the form pulling values out of that
//! div by splitting on each control's id.
//!
//! ## Both readers fail silently
//!
//! Each wraps its work in a `catch` whose only action is clearing a message
//! div. A missing file, an unreadable one, or a parse that throws produces
//! no error and no indication: the form simply stays as it was. The comment
//! beside `loadXML`'s catch says it will alert if the file does not exist.
//! It does not.
//!
//! ## Importing can silently lock the form
//!
//! `loadXML` checks the loaded text for the Final Copy marker and, if it is
//! present anywhere, latches the read-only flag and disables Validate and
//! Save. So importing a file decides whether the form can still be edited,
//! using the same whole-document substring search pinned in
//! `final_copy_codec` — including its disagreement with the tail.
//!
//! `loadBGXML` carries no such check. Background information can be
//! imported without affecting the latch.
//!
//! ## The two readers use different divs
//!
//! `loadXML` reads into `response` and `loadBGXML` into `responseBG`, so a
//! background import cannot disturb a return already loaded.
//!
//! The modal pair is presentation only: it shows and hides `#modalImport`
//! and reads nothing.
//!
//! Import rules only. Nothing here reads a file, and
//! `persistence_integrated` stays false.

const std = @import("std");
const evidence = @import("evidence.zig");
const final_copy_codec = @import("final_copy_codec.zig");

pub const ready = false;
pub const import_paths_ready = true;

pub const Reader = enum { return_document, background_information };

pub const ReaderFacts = struct {
    /// Hidden div the file is read into.
    sink_id: []const u8,
    /// Function that walks the form afterwards.
    loader: []const u8,
    /// Whether the reader can latch the read-only flag.
    can_latch_read_only: bool,
    /// Every failure is swallowed by a catch that clears a message div.
    fails_silently: bool,
};

pub fn factsFor(reader: Reader) ReaderFacts {
    return switch (reader) {
        .return_document => .{
            .sink_id = "response",
            .loader = "loadData",
            .can_latch_read_only = true,
            .fails_silently = true,
        },
        .background_information => .{
            .sink_id = "responseBG",
            .loader = "loadBGData",
            .can_latch_read_only = false,
            .fails_silently = true,
        },
    };
}

/// The marker `loadXML` searches the imported text for.
pub const read_only_latch_marker = final_copy_codec.final_copy_marker;

/// Whether importing this text leaves the form editable.
pub fn importLatchesReadOnly(reader: Reader, text: []const u8) bool {
    if (!factsFor(reader).can_latch_read_only) return false;
    return std.mem.indexOf(u8, text, read_only_latch_marker) != null;
}

/// Controls the latch disables on import.
pub const latched_disables = [_][]const u8{ "frm1601c:btnValidate", "btnSave" };

/// The modal pair only shows and hides; it reads nothing.
pub const modal_is_presentation_only = true;

test "1601C import paths are pinned and read nothing" {
    try std.testing.expect(import_paths_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!evidence.readiness.persistence_integrated);
    try std.testing.expect(modal_is_presentation_only);
}

test "1601C both readers swallow every failure" {
    try std.testing.expect(factsFor(.return_document).fails_silently);
    try std.testing.expect(factsFor(.background_information).fails_silently);
}

test "1601C the two readers use separate sinks" {
    try std.testing.expectEqualStrings("response", factsFor(.return_document).sink_id);
    try std.testing.expectEqualStrings("responseBG", factsFor(.background_information).sink_id);
    try std.testing.expect(!std.mem.eql(
        u8,
        factsFor(.return_document).sink_id,
        factsFor(.background_information).sink_id,
    ));
    try std.testing.expectEqualStrings("loadData", factsFor(.return_document).loader);
    try std.testing.expectEqualStrings("loadBGData", factsFor(.background_information).loader);
}

test "1601C importing a Final Copy locks the form" {
    const final = "<?xml version='1.0'?>...<div>a=1a=</div>..." ++ read_only_latch_marker;
    try std.testing.expect(importLatchesReadOnly(.return_document, final));
    try std.testing.expectEqual(@as(usize, 2), latched_disables.len);
}

test "1601C an editable import leaves the form editable" {
    const editable = "<?xml version='1.0'?>...<div>a=1a=</div>...All Rights Reserved BIR 2012.";
    try std.testing.expect(!importLatchesReadOnly(.return_document, editable));
    // The marker extends the editable notice by one byte.
    try std.testing.expect(std.mem.indexOf(u8, editable, read_only_latch_marker) == null);
}

test "1601C the latch inherits the substring search and its looseness" {
    // The same whole-document search final_copy_codec pins, so a value
    // carrying the literal locks the form on import.
    try std.testing.expectEqualStrings(
        final_copy_codec.final_copy_marker,
        read_only_latch_marker,
    );
    const spoofed = "<div>frm1601c:txtAddress=" ++ read_only_latch_marker ++
        "frm1601c:txtAddress=</div>All Rights Reserved BIR 2012.";
    try std.testing.expect(importLatchesReadOnly(.return_document, spoofed));
}

test "1601C a background import never touches the latch" {
    const final = "anything " ++ read_only_latch_marker;
    try std.testing.expect(!importLatchesReadOnly(.background_information, final));
    try std.testing.expect(!factsFor(.background_information).can_latch_read_only);
}
