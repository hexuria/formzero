//! Exact executable-contract identity for a form package.
//!
//! `forms/id.zig.FormRevision` remains the semantic printed-form identity.
//! This module adds the package and source identities needed to distinguish
//! executable contracts that share the same printed revision.

const std = @import("std");
const ids = @import("../forms/id.zig");

pub const FormRevision = ids.FormRevision;

pub const DigestError = error{
    InvalidLength,
    InvalidHexCharacter,
};

pub const Sha256Digest = struct {
    const Self = @This();

    bytes: [std.crypto.hash.sha2.Sha256.digest_length]u8,

    pub fn parseHex(raw: []const u8) DigestError!Self {
        if (raw.len != std.crypto.hash.sha2.Sha256.digest_length * 2) {
            return error.InvalidLength;
        }

        var result: Self = .{ .bytes = undefined };
        for (0..result.bytes.len) |index| {
            const high = try hexNibble(raw[index * 2]);
            const low = try hexNibble(raw[index * 2 + 1]);
            result.bytes[index] = (high << 4) | low;
        }
        return result;
    }

    pub fn initComptime(comptime raw: []const u8) Self {
        return comptime parseHex(raw) catch {
            @compileError("invalid 64-character SHA-256 literal");
        };
    }

    pub fn eql(self: *const Self, other: *const Self) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn asBytes(self: *const Self) *const [32]u8 {
        return &self.bytes;
    }
};

fn hexNibble(byte: u8) DigestError!u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => error.InvalidHexCharacter,
    };
}

/// The first exact engine intentionally exposes only reviewed vocabulary.
/// Adding another value requires adding another independently evidenced
/// package rather than accepting an arbitrary string.
pub const Locale = enum(u8) {
    en_PH = 1,
};

pub const OfflinePackageVersion = enum(u8) {
    ebirforms_7_9_6 = 1,
};

pub const PayloadSchemaToken = enum(u8) {
    form_1701q_v2018 = 1,
};

/// A codec version is absent until exact editable and Final Copy codecs have
/// been qualified. `null` is materially different from a candidate version.
pub const CodecVersion = enum(u8) {
    legacy_1701q_v2018_v1 = 1,
};

pub const ExactFormPackageKey = struct {
    const Self = @This();

    revision: FormRevision,
    locale: Locale,
    offline_package_version: OfflinePackageVersion,
    payload_schema_or_form_token: PayloadSchemaToken,
    offline_package_sha256: Sha256Digest,
    primary_source_sha256: Sha256Digest,
    dependency_manifest_sha256: Sha256Digest,
    official_pdf_sha256: ?Sha256Digest = null,
    official_guide_sha256: ?Sha256Digest = null,
    codec_version: ?CodecVersion = null,

    pub fn eql(self: *const Self, other: *const Self) bool {
        return self.revision.eql(&other.revision) and
            self.locale == other.locale and
            self.offline_package_version == other.offline_package_version and
            self.payload_schema_or_form_token ==
                other.payload_schema_or_form_token and
            self.offline_package_sha256.eql(&other.offline_package_sha256) and
            self.primary_source_sha256.eql(&other.primary_source_sha256) and
            self.dependency_manifest_sha256.eql(
                &other.dependency_manifest_sha256,
            ) and
            optionalDigestEql(
                self.official_pdf_sha256,
                other.official_pdf_sha256,
            ) and
            optionalDigestEql(
                self.official_guide_sha256,
                other.official_guide_sha256,
            ) and
            self.codec_version == other.codec_version;
    }

    /// Stable across CPU endianness and independent of struct memory layout.
    pub fn canonicalDigest(self: *const Self) Sha256Digest {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update("ebirforms.exact-form-package-key.v1");
        updateLengthPrefixed(&hash, self.revision.code.asSlice());
        updateLengthPrefixed(&hash, self.revision.revision.asSlice());
        hash.update(&.{@intFromEnum(self.locale)});
        hash.update(&.{@intFromEnum(self.offline_package_version)});
        hash.update(&.{@intFromEnum(self.payload_schema_or_form_token)});
        hash.update(self.offline_package_sha256.asBytes());
        hash.update(self.primary_source_sha256.asBytes());
        hash.update(self.dependency_manifest_sha256.asBytes());
        updateOptionalDigest(&hash, self.official_pdf_sha256);
        updateOptionalDigest(&hash, self.official_guide_sha256);
        if (self.codec_version) |version| {
            hash.update(&.{ 1, @intFromEnum(version) });
        } else {
            hash.update(&.{0});
        }

        var result: Sha256Digest = .{ .bytes = undefined };
        hash.final(&result.bytes);
        return result;
    }
};

fn optionalDigestEql(
    left: ?Sha256Digest,
    right: ?Sha256Digest,
) bool {
    if (left) |left_digest| {
        if (right) |right_digest| {
            return left_digest.eql(&right_digest);
        }
        return false;
    }
    return right == null;
}

fn updateOptionalDigest(
    hash: *std.crypto.hash.sha2.Sha256,
    digest: ?Sha256Digest,
) void {
    if (digest) |present| {
        hash.update(&.{1});
        hash.update(present.asBytes());
    } else {
        hash.update(&.{0});
    }
}

fn updateLengthPrefixed(
    hash: *std.crypto.hash.sha2.Sha256,
    value: []const u8,
) void {
    std.debug.assert(value.len <= std.math.maxInt(u16));
    const len: u16 = @intCast(value.len);
    hash.update(&.{
        @intCast(len >> 8),
        @intCast(len & 0xff),
    });
    hash.update(value);
}

test "SHA-256 literals are exact and case insensitive" {
    const lower = Sha256Digest.initComptime(
        "5f164dde6154b96f28e23656ed2ef29406010ee3f94333e88ea6eb107fe589a0",
    );
    const upper = try Sha256Digest.parseHex(
        "5F164DDE6154B96F28E23656ED2EF29406010EE3F94333E88EA6EB107FE589A0",
    );
    try std.testing.expect(lower.eql(&upper));
    try std.testing.expectError(
        error.InvalidLength,
        Sha256Digest.parseHex("5f16"),
    );
    try std.testing.expectError(
        error.InvalidHexCharacter,
        Sha256Digest.parseHex(
            "zf164dde6154b96f28e23656ed2ef29406010ee3f94333e88ea6eb107fe589a0",
        ),
    );
}

test "exact identity changes when executable evidence changes" {
    const base: ExactFormPackageKey = .{
        .revision = FormRevision.initComptime("1701Q", "2018-01-ENCS"),
        .locale = .en_PH,
        .offline_package_version = .ebirforms_7_9_6,
        .payload_schema_or_form_token = .form_1701q_v2018,
        .offline_package_sha256 = Sha256Digest.initComptime(
            "de8ef0815509d65189e6794e1f8135a5ecf5f2800005d1fc5c87043efd96dbca",
        ),
        .primary_source_sha256 = Sha256Digest.initComptime(
            "5f164dde6154b96f28e23656ed2ef29406010ee3f94333e88ea6eb107fe589a0",
        ),
        .dependency_manifest_sha256 = Sha256Digest.initComptime(
            "c8b1bf48efca97afebae61b2abe31f6fda9c9efbb3ca448dbc4e6ee802a631ea",
        ),
    };
    var changed = base;
    changed.codec_version = .legacy_1701q_v2018_v1;

    try std.testing.expect(base.eql(&base));
    try std.testing.expect(!base.eql(&changed));
    const base_digest = base.canonicalDigest();
    const changed_digest = changed.canonicalDigest();
    try std.testing.expect(!base_digest.eql(&changed_digest));
}
