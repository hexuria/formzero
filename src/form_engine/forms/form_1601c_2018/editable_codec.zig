//! Occurrence rules for the 1601C January 2018 editable save.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - write side, `saveXML` occurrence loop, lines 2217-2241
//! - read side, `loadData`, lines 1907-1960
//!
//! The writer walks `frmMain.elements` in live order and skips `button`,
//! `hidden` and `undefined` types. Text and select-one controls, radios and
//! checkboxes each produce one `<div>{id}={value}{id}=</div>` occurrence
//! followed by the separator. Radios and checkboxes write `checked` rather
//! than a value.
//!
//! ## Only four ids are escaped
//!
//! `escape()` is applied to `txtTaxpayerName`, `txtLineBus`, `txtAddress`
//! and `txtAddress2`. Every other value is written raw, so a value carrying
//! `<`, `&` or the literal key terminator goes into the document unencoded.
//! That is what the source does; this module records it rather than
//! repairing it.
//!
//! ## The two address lines share one occurrence
//!
//! `txtAddress` opens a `<div>` and writes its escaped value without
//! closing. `txtAddress2` then appends its own escaped value and closes the
//! div under `frm1601c:txtAddress=`. There is **no delimiter between them**.
//!
//! `loadData` splits them back apart at a **fixed offset of 100 escaped
//! characters**, matching `txtAddress`'s declared maximum. Below that
//! offset the whole string becomes line one and line two is set to the
//! empty string.
//!
//! That makes the round trip lossy in two directions, both recorded here as
//! `AddressRoundTrip`:
//!
//! - when the two escaped values together run to 100 characters or fewer,
//!   line two is absorbed into line one and lost;
//! - when line one alone escapes to more than 100 characters, the split
//!   lands inside it and the remainder is misfiled as line two.
//!
//! `escape()` percent-encodes, so a value well under the declared maximum
//! can still exceed 100 escaped characters.
//!
//! This module pins the rules. It does not serialize, and
//! `editable_serializer_exact` stays false pending the encoding captures
//! `document.zig` describes.

const std = @import("std");
const document = @import("document.zig");
const evidence = @import("evidence.zig");
const occurrences = @import("occurrences.zig");

pub const ready = false;

/// Control types the writer skips entirely.
pub const skipped_types = [_][]const u8{ "button", "hidden", "undefined" };

/// Ids whose value passes through `escape()` on write and `unescape()` on
/// read. Everything else is written raw.
pub const escaped_control_ids = [_][]const u8{
    "frm1601c:txtTaxpayerName",
    "frm1601c:txtLineBus",
    "frm1601c:txtAddress",
    "frm1601c:txtAddress2",
};

/// Offset, in escaped characters, where `loadData` splits the fused address
/// occurrence. Equal to `txtAddress`'s declared maximum length.
pub const address_split_offset: usize = 100;

/// The single occurrence key both address lines are stored under.
pub const fused_address_key = "frm1601c:txtAddress";

pub fn isEscaped(control_id: []const u8) bool {
    for (escaped_control_ids) |id| {
        if (std.mem.eql(u8, id, control_id)) return true;
    }
    return false;
}

pub fn isSkippedType(control_type: []const u8) bool {
    for (skipped_types) |skipped| {
        if (std.mem.eql(u8, skipped, control_type)) return true;
    }
    return false;
}

/// What a control contributes to the document.
pub const Emission = enum {
    /// `<div>{id}={value}{id}=</div>`
    own_occurrence,
    /// Opens the fused address occurrence and does not close it.
    opens_fused_address,
    /// Closes the fused address occurrence under the other line's key.
    closes_fused_address,
    /// Written as `checked` rather than as a value.
    checked_state,
    /// Skipped by type.
    none,
};

pub fn emissionFor(control_id: []const u8, control_kind: occurrences.ControlKind) Emission {
    return switch (control_kind) {
        .button, .hidden => .none,
        .radio, .checkbox => .checked_state,
        else => blk: {
            if (std.mem.eql(u8, control_id, "frm1601c:txtAddress")) {
                break :blk .opens_fused_address;
            }
            if (std.mem.eql(u8, control_id, "frm1601c:txtAddress2")) {
                break :blk .closes_fused_address;
            }
            break :blk .own_occurrence;
        },
    };
}

/// How the fixed-offset split resolves for a given fused length.
pub const AddressRoundTrip = enum {
    /// Both lines survive: the split lands exactly at the boundary.
    lossless,
    /// Line two is absorbed into line one and lost.
    second_line_absorbed,
    /// The split lands inside line one; its remainder is misfiled.
    first_line_split,
};

/// `escaped_first` and `escaped_second` are lengths after `escape()`.
pub fn addressRoundTrip(escaped_first: usize, escaped_second: usize) AddressRoundTrip {
    if (escaped_first + escaped_second <= address_split_offset) {
        // Everything lands in line one; line two is set to the empty string.
        return if (escaped_second == 0) .lossless else .second_line_absorbed;
    }
    if (escaped_first == address_split_offset) return .lossless;
    if (escaped_first < address_split_offset) return .second_line_absorbed;
    return .first_line_split;
}

test "1601C only four ids are escaped" {
    try std.testing.expectEqual(@as(usize, 4), escaped_control_ids.len);
    try std.testing.expect(isEscaped("frm1601c:txtTaxpayerName"));
    try std.testing.expect(isEscaped("frm1601c:txtLineBus"));
    try std.testing.expect(isEscaped("frm1601c:txtAddress"));
    try std.testing.expect(isEscaped("frm1601c:txtAddress2"));
    // Everything else is written raw, including the email and the TIN.
    try std.testing.expect(!isEscaped("txtEmail"));
    try std.testing.expect(!isEscaped("frm1601c:txtTIN1"));
    try std.testing.expect(!isEscaped("frm1601c:txtZipCode"));
    for (escaped_control_ids) |id| {
        try std.testing.expect(occurrences.find(id) != null);
    }
}

test "1601C the writer skips three control types" {
    try std.testing.expectEqual(@as(usize, 3), skipped_types.len);
    try std.testing.expect(isSkippedType("button"));
    try std.testing.expect(isSkippedType("hidden"));
    try std.testing.expect(isSkippedType("undefined"));
    try std.testing.expect(!isSkippedType("text"));
    try std.testing.expect(!isSkippedType("radio"));
}

test "1601C the two address lines share one occurrence" {
    try std.testing.expectEqual(
        Emission.opens_fused_address,
        emissionFor("frm1601c:txtAddress", .text),
    );
    try std.testing.expectEqual(
        Emission.closes_fused_address,
        emissionFor("frm1601c:txtAddress2", .text),
    );
    // Both are stored under the first line's key.
    try std.testing.expectEqualStrings("frm1601c:txtAddress", fused_address_key);
    // Any other text control writes its own occurrence.
    try std.testing.expectEqual(
        Emission.own_occurrence,
        emissionFor("frm1601c:txtZipCode", .text),
    );
    try std.testing.expectEqual(
        Emission.checked_state,
        emissionFor("frm1601c:AmendedRtn_1", .radio),
    );
    try std.testing.expectEqual(Emission.none, emissionFor("btnPrint", .button));
}

test "1601C the address split offset is the declared maximum of line one" {
    const control_contract = @import("control_contract.zig");
    const first_line = control_contract.find("frm1601c:txtAddress").?;
    try std.testing.expectEqual(
        @as(u16, @intCast(address_split_offset)),
        first_line.max_length.?,
    );
}

test "1601C a short second address line is absorbed and lost" {
    // "MAIN ST" and "UNIT 5" together escape to well under 100 characters,
    // so the whole string becomes line one and line two is emptied.
    try std.testing.expectEqual(
        AddressRoundTrip.second_line_absorbed,
        addressRoundTrip(7, 6),
    );
    try std.testing.expectEqual(
        AddressRoundTrip.second_line_absorbed,
        addressRoundTrip(60, 30),
    );
    // With no second line there is nothing to lose.
    try std.testing.expectEqual(AddressRoundTrip.lossless, addressRoundTrip(7, 0));
}

test "1601C an over-long first address line is split mid-value" {
    // escape() percent-encodes, so a value inside the declared maximum can
    // still exceed 100 escaped characters.
    try std.testing.expectEqual(
        AddressRoundTrip.first_line_split,
        addressRoundTrip(140, 20),
    );
    try std.testing.expectEqual(
        AddressRoundTrip.first_line_split,
        addressRoundTrip(101, 0),
    );
}

test "1601C the split is lossless only at the exact boundary" {
    try std.testing.expectEqual(AddressRoundTrip.lossless, addressRoundTrip(100, 40));
    try std.testing.expectEqual(AddressRoundTrip.lossless, addressRoundTrip(100, 0));
    try std.testing.expectEqual(
        AddressRoundTrip.second_line_absorbed,
        addressRoundTrip(99, 40),
    );
    try std.testing.expectEqual(
        AddressRoundTrip.first_line_split,
        addressRoundTrip(101, 40),
    );
}

test "1601C the codec pins rules without claiming an exact serializer" {
    try std.testing.expect(!ready);
    try std.testing.expect(!evidence.readiness.editable_serializer_exact);
    try std.testing.expect(document.ascii_byte_layer_exact);
    try std.testing.expect(!document.exact_complete_byte_encoding_ready);
}
