//! HTA-local 1601C encryption path and saved-file naming.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - `encrypt` lines 4126-4133
//! - commented call sites at lines 2084 and 2247
//! - `createEncXMLFileName` lines 1975-1992, used at line 2207
//!
//! ## The codec is complete and never runs
//!
//! `encrypt` calls `Aes.Ctr.encrypt(val, aesPW, 256)`. Both halves are
//! present: `js/aes.js` is a resolved dependency, and `aesPW` is defined in
//! `js/string-util.js`, which this form loads. Nothing is missing.
//!
//! Both call sites are commented out. The save path assigns `allXML`
//! straight to the file, so **the document written to disk is the plaintext
//! this package pins elsewhere**, not a ciphertext.
//!
//! A disused Blowfish call sits commented above the AES one, so the file
//! records two abandoned encryption attempts rather than one.
//!
//! ## The filename says otherwise
//!
//! `createEncXMLFileName` is live and is what the Final Copy path uses. It
//! builds `IAF_RDO_Copy/{TIN}{branch}-1601Cv2018-{MMYYYY}.xml`, so the
//! taxpayer identification number is placed **in the file name**, and the
//! folder and the `Enc` in the function name both suggest an encrypted
//! artefact that is not produced.
//!
//! That combination is recorded because it is easy to read the naming as
//! evidence of encryption. It is not.
//!
//! ## Why no codec flag moves
//!
//! `encrypt_codec_qualified` and `decrypt_codec_qualified` stay false. The
//! codec exists but no path reaches it, so qualifying it would be a claim
//! about code that does not execute.
//!
//! `ui_integrated` also stays false, for a different reason: no criterion
//! for it is defined anywhere in the engine, and 1701Q, which carries far
//! more integration work, does not claim it either. Flipping it here would
//! invent a standard rather than meet one.

const std = @import("std");
const document = @import("document.zig");
const evidence = @import("evidence.zig");

pub const ready = false;
pub const encryption_path_ready = true;

/// `encrypt` is defined and its dependencies resolve.
pub const cipher_call = "Aes.Ctr.encrypt(val, aesPW, 256)";
pub const cipher_key_bits: u16 = 256;
/// `js/aes.js` supplies the cipher.
pub const cipher_source = "js/aes.js";
/// `js/string-util.js` supplies the key.
pub const key_source = "js/string-util.js";

/// Neither call site is live, so nothing is ever enciphered.
pub const live_call_sites: usize = 0;
pub const commented_call_sites = [_]u32{ 2084, 2247 };
/// A disused Blowfish attempt sits commented above the AES one.
pub const abandoned_cipher_attempts: usize = 2;

/// What the save path actually writes.
pub const WrittenForm = enum { plaintext, ciphertext };
pub const written_form: WrittenForm = .plaintext;

/// `createEncXMLFileName`, which the Final Copy path uses.
pub const saved_folder = "IAF_RDO_Copy/";
pub const filename_infix = "-1601Cv2018-";
pub const filename_extension = ".xml";
/// The file name is built from the TIN parts, the branch code and the
/// return period.
pub const filename_embeds_tin = true;

test "1601C the cipher is complete and its dependencies resolve" {
    try std.testing.expect(encryption_path_ready);
    try std.testing.expectEqual(@as(u16, 256), cipher_key_bits);
    try std.testing.expect(std.mem.indexOf(u8, cipher_call, "Aes.Ctr.encrypt") != null);
    try std.testing.expectEqualStrings("js/aes.js", cipher_source);
    try std.testing.expectEqualStrings("js/string-util.js", key_source);
    // Both are loaded by this form, so nothing about the cipher is missing.
    try std.testing.expect(evidence.readiness.dependency_closure);
}

test "1601C nothing is ever enciphered" {
    try std.testing.expectEqual(@as(usize, 0), live_call_sites);
    try std.testing.expectEqual(@as(usize, 2), commented_call_sites.len);
    try std.testing.expectEqual(WrittenForm.plaintext, written_form);
    // Two abandoned attempts, Blowfish and AES.
    try std.testing.expectEqual(@as(usize, 2), abandoned_cipher_attempts);
}

test "1601C the file written is the plaintext this package pins" {
    // The save path writes allXML unchanged, so the bytes on disk are the
    // envelope and occurrences already pinned in document.zig.
    try std.testing.expectEqual(WrittenForm.plaintext, written_form);
    try std.testing.expect(document.ascii_byte_layer_exact);
    try std.testing.expectEqualStrings("<?xml version='1.0'?>", document.prolog);
}

test "1601C the saved name implies an encryption that does not happen" {
    try std.testing.expectEqualStrings("IAF_RDO_Copy/", saved_folder);
    try std.testing.expectEqualStrings("-1601Cv2018-", filename_infix);
    try std.testing.expect(filename_embeds_tin);
    // The name and folder suggest a protected artefact; the content is not.
    try std.testing.expectEqual(WrittenForm.plaintext, written_form);
}

test "1601C no codec flag is claimed for a path that never runs" {
    try std.testing.expect(!evidence.readiness.encrypt_codec_qualified);
    try std.testing.expect(!evidence.readiness.decrypt_codec_qualified);
    // And ui_integrated has no defined criterion to meet.
    try std.testing.expect(!evidence.readiness.ui_integrated);
    try std.testing.expect(!ready);
}
