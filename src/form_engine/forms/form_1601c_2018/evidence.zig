//! Exact package identity for BIR Form 1601C January 2018 (ENCS).
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`, resource 148, 275,902 bytes
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//!
//! This is the first form in this build whose script closure is complete.
//! The HTA declares eight `<script src>` tags and every one resolves to a
//! file the package contains, at the path the tag names. There are no absent
//! scripts and no path-placement variants, so `dependency_closure` is true
//! and `identityReady()` holds.
//!
//! That matters beyond bookkeeping. 1601EQ can never reconcile its
//! calculations because `bir-formatter.js` and `formatter/forms/1601EQ.js`
//! load after `js/string-util.js` and might redefine its money primitives,
//! and neither ships in 7.9.5 or 7.9.6. 1601C loads `js/string-util.js` with
//! nothing after it that could override, so `formatCurrency`, `NumWithComma`
//! and `round` are unambiguous here.
//!
//! No official form PDF is pinned for this revision, so
//! `official_pdf_sha256` is null rather than a guess. Identity rests on the
//! package and its source set.
//!
//! Every part other than this one is fail-closed. Closure establishes that
//! the sources are all present; it does not transcribe them.

const std = @import("std");
const identity = @import("../../identity.zig");
const engine_evidence = @import("../../evidence.zig");

pub const package_key: identity.ExactFormPackageKey = .{
    .revision = identity.FormRevision.initComptime(
        "1601C",
        "2018-01-ENCS",
    ),
    .locale = .en_PH,
    .offline_package_version = .ebirforms_7_9_6,
    .payload_schema_or_form_token = .form_1601c_v2018,
    .offline_package_sha256 = identity.Sha256Digest.initComptime(
        "de8ef0815509d65189e6794e1f8135a5ecf5f2800005d1fc5c87043efd96dbca",
    ),
    .primary_source_sha256 = identity.Sha256Digest.initComptime(
        "3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879",
    ),
    .dependency_manifest_sha256 = identity.Sha256Digest.initComptime(
        "4fcb90648f25e437609139f8f0ef05ae3cd1fac243634136068b5e02ffe511cc",
    ),
    .official_pdf_sha256 = null,
    .official_guide_sha256 = null,
    .codec_version = null,
};

pub const official_documents =
    [_]engine_evidence.OfficialDocumentEvidence{};

pub const primary_source: engine_evidence.SourceEvidence = .{
    .role = .form_source,
    .normalized_relative_path = "forms/BIR-Form1601Cv2018.hta",
    .resource_id = 148,
    .byte_length = 275_902,
    .sha256 = identity.Sha256Digest.initComptime(
        "3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879",
    ),
    .exact_resource_match = true,
};

/// Canonical path order. Official `<script>` order is `script_load_order`.
pub const dependencies = [_]engine_evidence.SourceEvidence{
    .{
        .role = .script_dependency,
        .normalized_relative_path = "jq/jquery-1.7.1.min.js",
        .resource_id = 553,
        .byte_length = 93_868,
        .sha256 = identity.Sha256Digest.initComptime(
            "88171413fc76dda23ab32baa17b11e4fff89141c633ece737852445f1ba6c1bd",
        ),
        .exact_resource_match = true,
        .script_load_order = 1,
        .script_tag_line = 19,
    },
    .{
        .role = .script_dependency,
        .normalized_relative_path = "jq/jquery-ui-1.8.18.custom.min.js",
        .resource_id = 554,
        .byte_length = 210_423,
        .sha256 = identity.Sha256Digest.initComptime(
            "f38f53a28fe9992933dbc4ba83a76eb55e7c30c6fe84981df683ace83735ad43",
        ),
        .exact_resource_match = true,
        .script_load_order = 2,
        .script_tag_line = 20,
    },
    .{
        .role = .script_dependency,
        .normalized_relative_path = "js/aes.js",
        .resource_id = 555,
        .byte_length = 19_841,
        .sha256 = identity.Sha256Digest.initComptime(
            "177f098b1540af2a3fee43c15956a40b2021dd98c0dbec20efa8f8a2d1e4ed7e",
        ),
        .exact_resource_match = true,
        .script_load_order = 6,
        .script_tag_line = 26,
    },
    .{
        .role = .script_dependency,
        .normalized_relative_path = "js/environment.js",
        .resource_id = 558,
        .byte_length = 11_556,
        .sha256 = identity.Sha256Digest.initComptime(
            "53f86a9e4def3955950ade2b452c722b22236d3e3d5e51f767f32d1fff555c4c",
        ),
        .exact_resource_match = true,
        .script_load_order = 3,
        .script_tag_line = 23,
    },
    .{
        .role = .script_dependency,
        .normalized_relative_path = "js/lz-string-1.0.2.js",
        .resource_id = 568,
        .byte_length = 5_350,
        .sha256 = identity.Sha256Digest.initComptime(
            "58a7a887090cd33e763d470bd9558f177f4b2c52de99e01fabf0339a44c9f150",
        ),
        .exact_resource_match = true,
        .script_load_order = 8,
        .script_tag_line = 28,
    },
    .{
        .role = .script_dependency,
        .normalized_relative_path = "js/rijndael.js",
        .resource_id = 569,
        .byte_length = 7_045,
        .sha256 = identity.Sha256Digest.initComptime(
            "f1eda7677447fcab29e3c26ea7054800cc43a4b436c40e71102fb97d9faaab06",
        ),
        .exact_resource_match = true,
        .script_load_order = 7,
        .script_tag_line = 27,
    },
    .{
        .role = .script_dependency,
        .normalized_relative_path = "js/string-util.js",
        .resource_id = 570,
        .byte_length = 54_582,
        .sha256 = identity.Sha256Digest.initComptime(
            "bc7f86f70bf993389a3a0135dcbd76c3e370c49d2eb95e2fc66ff318a2ebe43c",
        ),
        .exact_resource_match = true,
        .script_load_order = 4,
        .script_tag_line = 24,
    },
    .{
        .role = .script_dependency,
        .normalized_relative_path = "js/string-util2014.js",
        .resource_id = 571,
        .byte_length = 15_980,
        .sha256 = identity.Sha256Digest.initComptime(
            "ca42592694e7416a15eca97fa25491c01da17e383038fc97dd9d6261e67bcf7d",
        ),
        .exact_resource_match = true,
        .script_load_order = 5,
        .script_tag_line = 25,
    },
};

/// Nothing is unresolved: every declared script resolves at its declared
/// path. This array is empty by evidence, not by omission.
pub const unresolved_scripts = [_]engine_evidence.UnresolvedScriptEvidence{};

pub const readiness: engine_evidence.EvidenceReadiness = .{
    .identity_resolved = true,
    // Eight declared scripts, eight resolved, none unresolved.
    .dependency_closure = true,
    // Reconciled by profile_mapping.zig against the 136-control static
    // occurrence inventory in live document order, the Item 7 injection
    // point, the 138-value RDO domain, and the typed form contract.
    .profile_mapping_reviewed = true,
    // Reconciled by calculations.zig: the chain only adds and subtracts
    // two-decimal values, so neither toFixed nor formatCurrency has a
    // fraction of a centavo to resolve. Verified to operand magnitudes an
    // order of magnitude above anything round's twelve-digit gate admits.
    .calculation_reconciled = true,
    // Reconciled by validation.zig: the ordered gates, the Item 3 amount
    // conditions, both Schedule 1 date columns and the success path cover
    // validate in full.
    .validation_reconciled = true,
    .editable_serializer_exact = false,
    .final_plaintext_serializer_exact = false,
    .decrypt_codec_qualified = false,
    .encrypt_codec_qualified = false,
    .persistence_integrated = false,
    .ui_integrated = false,
    .offline_package_verified = false,
    .transport_enabled = false,
};

pub const manifest: engine_evidence.EvidenceManifest = .{
    .package_key = package_key,
    .primary_source = primary_source,
    .dependencies = &dependencies,
    .unresolved_scripts = &unresolved_scripts,
    .readiness = readiness,
};

pub const expected_source_set_sha256 =
    identity.Sha256Digest.initComptime(
        "f25bb97e08be21636e800c1b042907317526769c54896cf16fbb8c0b8c531a47",
    );

pub const declared_script_count: usize = 8;
pub const unresolved_script_count: usize = 0;

test "1601C identity validates with complete script closure" {
    try manifest.validate();
    try std.testing.expectEqual(declared_script_count, dependencies.len);
    try std.testing.expectEqual(unresolved_script_count, unresolved_scripts.len);
    try std.testing.expect(readiness.identity_resolved);
    try std.testing.expect(readiness.dependency_closure);
    try std.testing.expect(readiness.identityReady());
    try readiness.validateOfflineBoundary();

    const computed_dependencies = engine_evidence.dependencyDigest(&dependencies);
    try std.testing.expect(computed_dependencies.eql(
        &package_key.dependency_manifest_sha256,
    ));
    const computed_source_set = engine_evidence.sourceSetDigest(&manifest);
    try std.testing.expect(computed_source_set.eql(&expected_source_set_sha256));
}

test "1601C pins no official document and claims no codec" {
    try std.testing.expectEqual(@as(usize, 0), official_documents.len);
    try std.testing.expect(package_key.official_pdf_sha256 == null);
    try std.testing.expect(package_key.official_guide_sha256 == null);
    try std.testing.expect(package_key.codec_version == null);
    try std.testing.expectEqual(
        identity.PayloadSchemaToken.form_1601c_v2018,
        package_key.payload_schema_or_form_token,
    );
}

test "1601C script load order is complete and contiguous" {
    var seen = [_]bool{false} ** (declared_script_count + 1);
    for (dependencies) |dependency| {
        const order = dependency.script_load_order.?;
        try std.testing.expect(order >= 1 and order <= declared_script_count);
        try std.testing.expect(!seen[order]);
        seen[order] = true;
        try std.testing.expect(dependency.exact_resource_match);
    }
    for (seen[1..]) |present| try std.testing.expect(present);
}
