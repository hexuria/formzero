//! Frozen, value-free evidence identity for 1701Q January 2018 (ENCS) as
//! shipped in Offline eBIRForms 7.9.6.
//!
//! This file contains no taxpayer values, payload bytes, endpoint, secret, or
//! copied legacy implementation source.

const std = @import("std");
const identity = @import("../../identity.zig");
const engine_evidence = @import("../../evidence.zig");
const occurrence = @import("../../occurrence.zig");

pub const package_key: identity.ExactFormPackageKey = .{
    .revision = identity.FormRevision.initComptime(
        "1701Q",
        "2018-01-ENCS",
    ),
    .locale = .en_PH,
    .offline_package_version = .ebirforms_7_9_6,
    .payload_schema_or_form_token = .form_1701q_v2018,
    .offline_package_sha256 = identity.Sha256Digest.initComptime(
        "de8ef0815509d65189e6794e1f8135a5ecf5f2800005d1fc5c87043efd96dbca",
    ),
    .primary_source_sha256 = identity.Sha256Digest.initComptime(
        "5f164dde6154b96f28e23656ed2ef29406010ee3f94333e88ea6eb107fe589a0",
    ),
    .dependency_manifest_sha256 = identity.Sha256Digest.initComptime(
        "c8b1bf48efca97afebae61b2abe31f6fda9c9efbb3ca448dbc4e6ee802a631ea",
    ),
    .official_pdf_sha256 = identity.Sha256Digest.initComptime(
        "fdcce0ff83660bb831e8d95a5054a0fc7b924f049097b2ece6667318baaa49f5",
    ),
    .official_guide_sha256 = identity.Sha256Digest.initComptime(
        "ff07962229015a50b0aa169f91fa32e10c534f6730de5bf59263e22d34e270bc",
    ),
    // Exact editable and Final Copy codecs have not yet been qualified.
    .codec_version = null,
};

pub const official_documents =
    [_]engine_evidence.OfficialDocumentEvidence{
        .{
            .kind = .form_pdf,
            .evidence_id = "bir-1701q-january-2018-form-pdf",
            .byte_length = 1_109_208,
            .sha256 = identity.Sha256Digest.initComptime(
                "fdcce0ff83660bb831e8d95a5054a0fc7b924f049097b2ece6667318baaa49f5",
            ),
        },
        .{
            .kind = .filing_guide,
            .evidence_id = "bir-1701q-january-2018-guide-pdf",
            .byte_length = 152_170,
            .sha256 = identity.Sha256Digest.initComptime(
                "ff07962229015a50b0aa169f91fa32e10c534f6730de5bf59263e22d34e270bc",
            ),
        },
    };

pub const primary_source: engine_evidence.SourceEvidence = .{
    .role = .form_source,
    .normalized_relative_path = "forms/BIR-Form1701Qv2018.hta",
    .resource_id = 170,
    .byte_length = 372_180,
    .sha256 = identity.Sha256Digest.initComptime(
        "5f164dde6154b96f28e23656ed2ef29406010ee3f94333e88ea6eb107fe589a0",
    ),
    .exact_resource_match = true,
};

/// Canonical path order. Official execution order is retained separately in
/// `script_load_order`.
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
        .script_tag_line = 18,
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
        .script_tag_line = 19,
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
        .script_tag_line = 25,
    },
    .{
        .role = .script_dependency,
        .normalized_relative_path = "js/eBIRTools.vbs",
        .resource_id = 557,
        .byte_length = 7_557,
        .sha256 = identity.Sha256Digest.initComptime(
            "7d0ceb5aad2c0eb90aeca189d6104ff05163ecd1820379f456125634ff7460f7",
        ),
        .exact_resource_match = true,
        .script_load_order = 9,
        .script_tag_line = 28,
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
        .script_tag_line = 22,
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
        .script_tag_line = 27,
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
        .script_tag_line = 26,
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
        .script_tag_line = 23,
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
        .script_tag_line = 24,
    },
};

pub const readiness: engine_evidence.EvidenceReadiness = .{
    .identity_resolved = true,
    .dependency_closure = true,
    // Reconciled by profile_mapping.zig against the exact 173-control live
    // occurrence order, the 138-value RDO domain, and the typed form contract.
    .profile_mapping_reviewed = true,
    .calculation_reconciled = false,
    .validation_reconciled = false,
    // Grounded by the 2026-08-23 1601C ACP-1252 Save capture. Artifacts stay
    // candidate until calculation and validation are also reconciled.
    .editable_serializer_exact = true,
    .final_plaintext_serializer_exact = true,
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
    .readiness = readiness,
};

/// Static inventory plus the two select-one controls unconditionally injected
/// by `init()` -> `getRdo()` at HTA lines 2114-2117 and 3708-3719.
/// This summary cannot replace the reviewed per-occurrence manifest.
pub const inventory_summary: occurrence.InventorySummary = .{
    .form_id = "frmMain",
    .form_first_line = 217,
    .form_last_line = 2005,
    .static_form_controls = 193,
    .runtime_created_form_controls = 2,
    .serializer_eligible_controls = 173,
    .editable_occurrences = 172,
    .final_copy_occurrences = 173,
    .runtime_control_creation_observed = true,
    .evidence_id = "desktop-7.9.6-1701qv2018-hta",
};

pub const expected_source_set_sha256 =
    identity.Sha256Digest.initComptime(
        "9d129c83cdf32ebea58291d36bc2b3e09a5fc40061ab072a6de6b0d51ecff917",
    );

test "1701Q exact package and dependency hashes validate" {
    try manifest.validate();
    try std.testing.expectEqual(@as(usize, 9), dependencies.len);
    try std.testing.expectEqualStrings(
        "1701Q",
        package_key.revision.code.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "2018-01-ENCS",
        package_key.revision.revision.asSlice(),
    );

    const computed_dependencies =
        engine_evidence.dependencyDigest(&dependencies);
    try std.testing.expect(computed_dependencies.eql(
        &package_key.dependency_manifest_sha256,
    ));
    const computed_source_set = engine_evidence.sourceSetDigest(&manifest);
    try std.testing.expect(computed_source_set.eql(
        &expected_source_set_sha256,
    ));
    try std.testing.expect(
        package_key.official_pdf_sha256.?.eql(
            &official_documents[0].sha256,
        ),
    );
    try std.testing.expect(
        package_key.official_guide_sha256.?.eql(
            &official_documents[1].sha256,
        ),
    );
}

test "1701Q readiness is truthful and transport remains denied" {
    try std.testing.expect(readiness.identityReady());
    try std.testing.expect(!readiness.plaintextCodecsReady());
    try std.testing.expect(!readiness.encrypt_codec_qualified);
    try std.testing.expect(!readiness.transport_enabled);
    try readiness.validateOfflineBoundary();
}

test "1701Q inventory summary is value-free and not a serializer claim" {
    try inventory_summary.validate();
    try std.testing.expectEqual(
        @as(u16, 173),
        inventory_summary.serializer_eligible_controls,
    );
    try std.testing.expectEqual(
        @as(u16, 172),
        inventory_summary.editable_occurrences,
    );
    try std.testing.expectEqual(
        @as(u16, 173),
        inventory_summary.final_copy_occurrences,
    );
    try std.testing.expectEqual(
        @as(u16, 2),
        inventory_summary.runtime_created_form_controls,
    );
    try std.testing.expect(inventory_summary.runtime_control_creation_observed);
}
