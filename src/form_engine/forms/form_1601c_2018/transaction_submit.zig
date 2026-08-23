//! HTA-local 1601C submit path, recorded as evidence only.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - `uploadMe` lines 4528 and 4532
//! - `uploadXMLFile` lines 4623-4660
//!
//! Nothing here transmits. `transport_enabled` is false for every package and
//! `EvidenceReadiness.validateOfflineBoundary` rejects it at nine call sites,
//! including the tax profile store, the draft system and every manifest
//! validation. This module pins what the shipped path *would* do.
//!
//! The narrative summary lives in `docs/submit-path-findings.md`. Literal
//! credential values are not reproduced here or there.
//!
//! ## `uploadMe` is declared twice
//!
//! Both declarations carry the same name, so the later one wins. The earlier
//! saves a Final Copy and opens the admin screen; the surviving one saves a
//! Final Copy and then issues a login request. The unreachable declaration is
//! recorded because reading the file top-down finds it first.
//!
//! ## Credentials travel as query parameters
//!
//! The surviving `uploadMe` builds a login URL carrying `loginName` and
//! `password` in the query string and issues it as a `GET`. A developer
//! comment directly above states the credentials should not be hard-coded and
//! that an existing session should be checked instead.
//!
//! Seventy-seven of the shipped form HTAs contain the same construction, so it
//! is a package-wide pattern rather than one form's slip.
//!
//! ## The return itself also travels in the URI
//!
//! `uploadXMLFile` chunks the saved return into fixed-size pieces and places
//! each chunk in the query string of a create request. The request method is
//! `POST`, but the payload is in the URI rather than the body. A commented-out
//! `GET` sits directly above the live `POST`, so the method changed without the
//! payload moving out of the URI.
//!
//! Before chunking, four substitutions are applied to the saved bytes, which
//! means the transmitted document is not byte-identical to the saved one.

const std = @import("std");
const evidence = @import("evidence.zig");

pub const ready = false;
pub const submit_path_ready = true;

/// Both declarations of `uploadMe`, in source order. The later wins.
pub const upload_entry_lines = [_]u32{ 4528, 4532 };
pub const surviving_upload_entry_line: u32 = 4532;

/// Where the login credentials are carried.
pub const CredentialCarrier = enum { query_string, request_body, header };
pub const login_credential_carrier: CredentialCarrier = .query_string;
pub const login_method = "GET";
/// Form HTAs in the package containing the same construction.
pub const forms_sharing_hardcoded_login: usize = 77;
/// A developer comment above it says the credentials should not be there.
pub const source_acknowledges_the_problem = true;

/// Where the return payload is carried.
pub const payload_carrier: CredentialCarrier = .query_string;
pub const upload_method = "POST";
/// A commented-out GET sits above the live POST.
pub const method_changed_without_moving_payload = true;

/// Bytes per chunk of the return.
pub const upload_chunk_bytes: usize = 1000;

/// Substitutions applied to the saved bytes before upload, so the transmitted
/// document differs from the saved one.
pub const pre_upload_substitution_count: usize = 4;

test "1601C the submit path is recorded and nothing is enabled" {
    try std.testing.expect(submit_path_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!evidence.readiness.transport_enabled);
    // The boundary still rejects transport for this package.
    try evidence.readiness.validateOfflineBoundary();
}

test "1601C the surviving upload entry is the later declaration" {
    try std.testing.expectEqual(@as(usize, 2), upload_entry_lines.len);
    try std.testing.expectEqual(surviving_upload_entry_line, upload_entry_lines[1]);
    try std.testing.expect(upload_entry_lines[0] < upload_entry_lines[1]);
    // Reading top-down finds the unreachable one first.
    try std.testing.expect(upload_entry_lines[0] != surviving_upload_entry_line);
}

test "1601C credentials and payload both travel in the URI" {
    try std.testing.expectEqual(CredentialCarrier.query_string, login_credential_carrier);
    try std.testing.expectEqual(CredentialCarrier.query_string, payload_carrier);
    // Neither uses a request body, so both are exposed to ordinary logging.
    try std.testing.expect(login_credential_carrier != .request_body);
    try std.testing.expect(payload_carrier != .request_body);
    try std.testing.expectEqualStrings("GET", login_method);
    try std.testing.expectEqualStrings("POST", upload_method);
    // The method changed without the payload leaving the URI.
    try std.testing.expect(method_changed_without_moving_payload);
}

test "1601C the hardcoded login is a package-wide pattern" {
    try std.testing.expectEqual(@as(usize, 77), forms_sharing_hardcoded_login);
    try std.testing.expect(forms_sharing_hardcoded_login > 1);
    try std.testing.expect(source_acknowledges_the_problem);
}

test "1601C the transmitted document is not the saved document" {
    try std.testing.expectEqual(@as(usize, 1000), upload_chunk_bytes);
    try std.testing.expectEqual(@as(usize, 4), pre_upload_substitution_count);
    // Substitutions run before chunking, so the bytes on the wire differ from
    // the bytes on disk that document.zig pins.
    try std.testing.expect(pre_upload_substitution_count > 0);
}
