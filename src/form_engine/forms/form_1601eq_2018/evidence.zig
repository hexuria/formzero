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

/// Scripts whose `<script src>` resolves to a path this package does not
/// contain, counting both unresolved kinds. `path_placement_variant` is not
/// a lesser failure than `absent_from_package`: the HTA's `src` resolves to
/// `normalized_relative_path`, and that path is absent, so the script does
/// not load. The identical bytes recorded at `recovered_relative_path` are
/// never fetched by this form.
///
/// 1701Q is the contrast: its HTA references `js/string-util2014.js`, the
/// path that exists, so the same file is a resolved dependency there while
/// 1601EQ's `js/formatter/string-util2014.js` reference is not.
pub const non_loading_script_count: usize =
    absent_active_script_count + path_placement_variant_count;

test "1601EQ path placement variants are recoverable bytes, not loadable scripts" {
    try std.testing.expectEqual(@as(usize, 7), non_loading_script_count);
    try std.testing.expectEqual(non_loading_script_count, unresolved_scripts.len);

    var absent: usize = 0;
    var variants: usize = 0;
    for (unresolved_scripts) |entry| {
        // Nothing unresolved may also appear as a resolved dependency.
        for (dependencies) |dependency| {
            try std.testing.expect(!std.mem.eql(
                u8,
                dependency.normalized_relative_path,
                entry.normalized_relative_path,
            ));
        }
        switch (entry.kind) {
            .absent_from_package => {
                absent += 1;
                // Nothing was recovered, so there is nothing to point at.
                try std.testing.expect(entry.recovered_relative_path == null);
                try std.testing.expect(entry.recovered_sha256 == null);
            },
            .path_placement_variant => {
                variants += 1;
                // Bytes were found, but under a path the HTA never requests.
                const recovered = entry.recovered_relative_path.?;
                try std.testing.expect(entry.recovered_sha256 != null);
                try std.testing.expect(!std.mem.eql(
                    u8,
                    recovered,
                    entry.normalized_relative_path,
                ));
            },
        }
    }
    try std.testing.expectEqual(absent_active_script_count, absent);
    try std.testing.expectEqual(path_placement_variant_count, variants);

    // Recovered bytes do not shorten the path to closure.
    try std.testing.expect(!readiness.dependency_closure);
    try std.testing.expect(!readiness.identityReady());
}

/// `isItAFinalCopy` decides whether a saved XML is a Final Copy by looking
/// for this literal anywhere in the file, rather than by parsing it. The
/// stamp reads 2012.0 inside a 7.9.6 package, so it tracks the document
/// format rather than the application version.
///
/// Recorded as format evidence only. No codec is enabled by it and
/// `final_plaintext_serializer_exact` stays false.
pub const final_copy_marker = "All Rights Reserved BIR 2012.0";

test "1601EQ Final Copy detection is a substring sniff, not a parse" {
    try std.testing.expect(final_copy_marker.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, final_copy_marker, "2012.0") != null);
    try std.testing.expect(!readiness.final_plaintext_serializer_exact);
    try std.testing.expect(!readiness.editable_serializer_exact);
}

/// What a non-loading script's absence actually costs this form.
///
/// `unresolved_scripts` records that seven scripts never load. It does not
/// say whether that matters, and the seven are not equivalent: a swept
/// comparison of every live call site in the HTA against everything defined
/// by the HTA and by the scripts that do load leaves only two open.
pub const ScriptImpact = enum {
    /// Every call site is commented out, so the script is never invoked.
    no_live_call_site,
    /// Reached only from save, submit, upload or email, which stay closed.
    out_of_scope_path_only,
    /// A polyfill for something the host engine supplies natively.
    superseded_by_host,
    /// The same file is present at another path and loads from there.
    recovered_at_other_path,
    /// Loads after `js/string-util.js` and may redefine the money
    /// primitives it provides. Unresolvable from this package.
    may_override_money_primitives,
};

pub const ScriptImpactEntry = struct {
    normalized_relative_path: []const u8,
    impact: ScriptImpact,
};

/// One entry per `unresolved_scripts` path.
pub const script_impacts = [_]ScriptImpactEntry{
    .{
        // `getFtpFolder`, `importFiles`, `buildSuccessMessage`, `emailResend`.
        .normalized_relative_path = "js/api-environment.js",
        .impact = .out_of_scope_path_only,
    },
    .{
        .normalized_relative_path = "js/bir-formatter.js",
        .impact = .may_override_money_primitives,
    },
    .{
        .normalized_relative_path = "js/formatter/SoapFormat/1601EQ-SoapFormat.js",
        .impact = .out_of_scope_path_only,
    },
    .{
        .normalized_relative_path = "js/formatter/forms/1601EQ.js",
        .impact = .may_override_money_primitives,
    },
    .{
        // `LZString.compress` at HTA lines 1966 and 2148 and
        // `LZString134.compressToBase64` at line 4304 are all commented out.
        .normalized_relative_path = "js/lz-string-1.3.4.js",
        .impact = .no_live_call_site,
    },
    .{
        .normalized_relative_path = "js/formatter/string-util2014.js",
        .impact = .recovered_at_other_path,
    },
    .{
        .normalized_relative_path = "js/json3.min.js",
        .impact = .superseded_by_host,
    },
};

/// Scripts whose absence can still change a pinned in-scope behaviour.
pub const open_question_script_count: usize = 2;

pub fn impactOf(path: []const u8) ?ScriptImpact {
    for (script_impacts) |entry| {
        if (std.mem.eql(u8, entry.normalized_relative_path, path)) return entry.impact;
    }
    return null;
}

test "1601EQ every non-loading script is classified exactly once" {
    try std.testing.expectEqual(unresolved_scripts.len, script_impacts.len);
    for (unresolved_scripts) |script| {
        try std.testing.expect(impactOf(script.normalized_relative_path) != null);
    }
    for (script_impacts, 0..) |entry, index| {
        for (script_impacts[index + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(
                u8,
                entry.normalized_relative_path,
                other.normalized_relative_path,
            ));
        }
    }
}

test "1601EQ only two absences can still change pinned behaviour" {
    var open: usize = 0;
    for (script_impacts) |entry| {
        if (entry.impact == .may_override_money_primitives) open += 1;
    }
    try std.testing.expectEqual(open_question_script_count, open);
    try std.testing.expectEqual(@as(usize, 2), open);

    try std.testing.expectEqual(
        ScriptImpact.may_override_money_primitives,
        impactOf("js/bir-formatter.js").?,
    );
    try std.testing.expectEqual(
        ScriptImpact.may_override_money_primitives,
        impactOf("js/formatter/forms/1601EQ.js").?,
    );
}

test "1601EQ the compression dependency has no live call site" {
    try std.testing.expectEqual(
        ScriptImpact.no_live_call_site,
        impactOf("js/lz-string-1.3.4.js").?,
    );
    // The version that does load is a resolved dependency.
    var present = false;
    for (dependencies) |dependency| {
        if (std.mem.eql(u8, dependency.normalized_relative_path, "js/lz-string-1.0.2.js")) {
            present = true;
        }
    }
    try std.testing.expect(present);
}

test "1601EQ classification does not soften closure or reconciliation" {
    // Knowing an absence is harmless does not make the script load.
    try std.testing.expectEqual(@as(usize, 7), non_loading_script_count);
    try std.testing.expect(!readiness.dependency_closure);
    // The two open questions are exactly why this stays false.
    try std.testing.expect(!readiness.calculation_reconciled);
}
