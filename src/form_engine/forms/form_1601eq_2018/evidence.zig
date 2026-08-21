//! Frozen, value-free evidence identity for 1601EQ January 2018 (ENCS) as
//! shipped in Offline eBIRForms 7.9.6.
//!
//! The HTA identity is exact. Script closure is not: five active `<script src>`
//! paths are absent from the 7.9.6 package, and two more are path-placement
//! variants. This file records those gaps. It does not invent calculations,
//! ATC lookup, codecs, or runtime parity.
//!
//! This file contains no taxpayer values, payload bytes, endpoint, secret, or
//! copied legacy implementation source.

const std = @import("std");
const identity = @import("../../identity.zig");
const engine_evidence = @import("../../evidence.zig");

pub const package_key: identity.ExactFormPackageKey = .{
    .revision = identity.FormRevision.initComptime(
        "1601EQ",
        "2018-01-ENCS",
    ),
    .locale = .en_PH,
    .offline_package_version = .ebirforms_7_9_6,
    .payload_schema_or_form_token = .form_1601eq_v2018,
    .offline_package_sha256 = identity.Sha256Digest.initComptime(
        "de8ef0815509d65189e6794e1f8135a5ecf5f2800005d1fc5c87043efd96dbca",
    ),
    .primary_source_sha256 = identity.Sha256Digest.initComptime(
        "cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96",
    ),
    .dependency_manifest_sha256 = identity.Sha256Digest.initComptime(
        "f002fb4875bdd885b108a7d34a377fd8488f857dc84ac200ae410e7b4690bfc5",
    ),
    .official_pdf_sha256 = identity.Sha256Digest.initComptime(
        "60034ceb199ebfed1b8e63a858c1a05c1331d68f81eaefadc27fa76b301f1c5c",
    ),
    // No January 2018 official guide PDF is pinned for this revision. The
    // January 2019 guide is a comparator for a different printed form.
    .official_guide_sha256 = null,
    .codec_version = null,
};

pub const official_documents =
    [_]engine_evidence.OfficialDocumentEvidence{
        .{
            .kind = .form_pdf,
            .evidence_id = "bir-1601eq-january-2018-form-pdf",
            .byte_length = 902_380,
            .sha256 = identity.Sha256Digest.initComptime(
                "60034ceb199ebfed1b8e63a858c1a05c1331d68f81eaefadc27fa76b301f1c5c",
            ),
        },
    };

pub const primary_source: engine_evidence.SourceEvidence = .{
    .role = .form_source,
    .normalized_relative_path = "forms/BIR-Form1601EQ.hta",
    .resource_id = 150,
    .byte_length = 268_182,
    .sha256 = identity.Sha256Digest.initComptime(
        "cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96",
    ),
    .exact_resource_match = true,
};

/// Recovered scripts whose referenced paths exist in the 7.9.6 package.
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
        .script_tag_line = 20,
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
        .script_tag_line = 21,
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
        .script_load_order = 5,
        .script_tag_line = 26,
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
        .script_load_order = 8,
        .script_tag_line = 29,
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
        .script_tag_line = 24,
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
        .script_load_order = 7,
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
        .script_load_order = 6,
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
        .script_tag_line = 25,
    },
};

/// Active HTA script references that are not exact recovered package paths.
/// Canonical path order. Load order is the HTA `<script>` order.
pub const unresolved_scripts = [_]engine_evidence.UnresolvedScriptEvidence{
    .{
        .kind = .absent_from_package,
        .normalized_relative_path = "js/api-environment.js",
        .script_load_order = 15,
        .script_tag_line = 36,
    },
    .{
        .kind = .absent_from_package,
        .normalized_relative_path = "js/bir-formatter.js",
        .script_load_order = 11,
        .script_tag_line = 32,
    },
    .{
        .kind = .absent_from_package,
        .normalized_relative_path = "js/formatter/SoapFormat/1601EQ-SoapFormat.js",
        .script_load_order = 12,
        .script_tag_line = 33,
    },
    .{
        .kind = .absent_from_package,
        .normalized_relative_path = "js/formatter/forms/1601EQ.js",
        .script_load_order = 13,
        .script_tag_line = 34,
    },
    .{
        .kind = .path_placement_variant,
        .normalized_relative_path = "js/formatter/string-util2014.js",
        .script_load_order = 14,
        .script_tag_line = 35,
        .recovered_relative_path = "js/string-util2014.js",
        .recovered_sha256 = identity.Sha256Digest.initComptime(
            "ca42592694e7416a15eca97fa25491c01da17e383038fc97dd9d6261e67bcf7d",
        ),
    },
    .{
        .kind = .path_placement_variant,
        .normalized_relative_path = "js/json3.min.js",
        .script_load_order = 10,
        .script_tag_line = 31,
        .recovered_relative_path = "js/lib/json3.min.js",
        .recovered_sha256 = identity.Sha256Digest.initComptime(
            "7c3e64ef84e5290feef3e6e6943c4618cd3b609995b6d7bde6e898b06bbf5d5a",
        ),
    },
    .{
        .kind = .absent_from_package,
        .normalized_relative_path = "js/lz-string-1.3.4.js",
        .script_load_order = 9,
        .script_tag_line = 30,
    },
};

pub const readiness: engine_evidence.EvidenceReadiness = .{
    .identity_resolved = true,
    .dependency_closure = false,
    .profile_mapping_reviewed = false,
    .calculation_reconciled = false,
    .validation_reconciled = false,
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
        "731c8f964cfaf4f6cb0b5748b3df1c683580075821ef0e3d51221ef072886dd2",
    );

pub const absent_active_script_count: usize = 5;
pub const path_placement_variant_count: usize = 2;

fn unresolvedKindCount(kind: engine_evidence.UnresolvedScriptKind) usize {
    var count: usize = 0;
    for (unresolved_scripts) |script| {
        if (script.kind == kind) count += 1;
    }
    return count;
}

test "1601EQ exact package identity validates and does not claim script closure" {
    try manifest.validate();
    try std.testing.expectEqual(@as(usize, 8), dependencies.len);
    try std.testing.expectEqual(@as(usize, 7), unresolved_scripts.len);
    try std.testing.expectEqual(
        absent_active_script_count,
        unresolvedKindCount(.absent_from_package),
    );
    try std.testing.expectEqual(
        path_placement_variant_count,
        unresolvedKindCount(.path_placement_variant),
    );
    try std.testing.expectEqualStrings(
        "1601EQ",
        package_key.revision.code.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "2018-01-ENCS",
        package_key.revision.revision.asSlice(),
    );
    try std.testing.expectEqual(
        identity.PayloadSchemaToken.form_1601eq_v2018,
        package_key.payload_schema_or_form_token,
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
    try std.testing.expect(package_key.official_guide_sha256 == null);
    try std.testing.expect(package_key.codec_version == null);
}

test "1601EQ readiness is truthful and transport remains denied" {
    try std.testing.expect(readiness.identity_resolved);
    try std.testing.expect(!readiness.dependency_closure);
    try std.testing.expect(!readiness.identityReady());
    try std.testing.expect(!readiness.plaintextCodecsReady());
    try std.testing.expect(!readiness.encrypt_codec_qualified);
    try std.testing.expect(!readiness.transport_enabled);
    try readiness.validateOfflineBoundary();
}

test "1601EQ cannot claim dependency closure while scripts are unresolved" {
    var claimed = manifest;
    claimed.readiness.dependency_closure = true;
    try std.testing.expectError(
        error.DependencyReadinessMismatch,
        claimed.validate(),
    );
}
