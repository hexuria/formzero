//! Clean-room, decrypt-only compatibility boundary for the observed legacy
//! eBIRForms container.
//!
//! This module is implemented from the project's value-free behavioral
//! specification and independent synthetic known-answer vectors. It does not
//! contain or expose an outbound encryption operation, a protocol secret,
//! artifact values, filenames, endpoints, or logging.
//!
//! The container has no authentication tag. Successful decryption therefore
//! proves only structural compatibility. A caller must additionally run the
//! strict lossless payload parser and verify the expected exact form-package
//! identity before treating the returned bytes as an imported Final Copy.

const std = @import("std");
const sensitive_memory = @import("../security/sensitive_memory.zig");

const Allocator = std.mem.Allocator;
const Aes256 = std.crypto.core.aes.Aes256;
const Sha256 = std.crypto.hash.sha2.Sha256;

const cipher_block_bytes = 16;
const minimum_zlib_stream_bytes = 8;

/// The complete, fixed, value-free diagnostic surface of this module.
pub const Error = error{
    OutOfMemory,
    EmptyProtocolSecret,
    InvalidLimits,
    TruncatedContainer,
    CiphertextTooLarge,
    DecryptFailure,
    InflateFailure,
    TrailingCompressedData,
    PlaintextTooLarge,
    InvalidUtf8,
    MalformedPayloadStructure,
};

/// Stable diagnostic identifiers suitable for value-free logs and UI.
pub const DiagnosticCode = enum {
    out_of_memory,
    empty_protocol_secret,
    invalid_limits,
    truncated_container,
    ciphertext_too_large,
    decrypt_failure,
    inflate_failure,
    trailing_compressed_data,
    plaintext_too_large,
    invalid_utf8,
    malformed_payload_structure,
};

pub fn diagnosticCode(err: Error) DiagnosticCode {
    return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.EmptyProtocolSecret => .empty_protocol_secret,
        error.InvalidLimits => .invalid_limits,
        error.TruncatedContainer => .truncated_container,
        error.CiphertextTooLarge => .ciphertext_too_large,
        error.DecryptFailure => .decrypt_failure,
        error.InflateFailure => .inflate_failure,
        error.TrailingCompressedData => .trailing_compressed_data,
        error.PlaintextTooLarge => .plaintext_too_large,
        error.InvalidUtf8 => .invalid_utf8,
        error.MalformedPayloadStructure => .malformed_payload_structure,
    };
}

pub const absolute_max_ciphertext_bytes: usize = 32 * 1024 * 1024;
pub const absolute_max_plaintext_bytes: usize = 16 * 1024 * 1024;

pub const Limits = struct {
    /// Applied before allocating the decrypted compressed stream.
    max_ciphertext_bytes: usize = absolute_max_ciphertext_bytes,
    /// Applied while inflating unauthenticated bytes.
    max_plaintext_bytes: usize = absolute_max_plaintext_bytes,

    pub fn validate(self: Limits) error{InvalidLimits}!void {
        if (self.max_ciphertext_bytes == 0 or
            self.max_ciphertext_bytes > absolute_max_ciphertext_bytes or
            self.max_plaintext_bytes == 0 or
            self.max_plaintext_bytes > absolute_max_plaintext_bytes)
        {
            return error.InvalidLimits;
        }
    }
};

/// There is deliberately no qualified state in this build. Adding one must be
/// an evidence-backed source change, not a caller-provided flag.
pub const QualificationState = enum {
    private_vector_record_absent,
};

pub const QualificationSummary = struct {
    state: QualificationState,
    required_decrypt_vectors: u16,
    verified_decrypt_vectors: u16,
    required_exact_encrypt_vectors: u16,
    verified_exact_encrypt_vectors: u16,
    outbound_encryption_available: bool,
};

pub fn qualificationSummary() QualificationSummary {
    return .{
        .state = .private_vector_record_absent,
        .required_decrypt_vectors = 67,
        .verified_decrypt_vectors = 0,
        .required_exact_encrypt_vectors = 67,
        .verified_exact_encrypt_vectors = 0,
        .outbound_encryption_available = false,
    };
}

/// Owned sensitive plaintext. Call `deinit` as soon as inspection or parsing
/// completes; it wipes the allocation before releasing it.
pub const DecryptedPlaintext = struct {
    allocator: Allocator,
    storage: []u8,

    pub fn bytes(self: *const DecryptedPlaintext) []const u8 {
        return self.storage;
    }

    pub fn deinit(self: *DecryptedPlaintext) void {
        wipeAndFree(self.allocator, self.storage);
        sensitive_memory.wipeValue(DecryptedPlaintext, self);
    }
};

/// Decrypt, strictly inflate, bound, checksum, and UTF-8 validate a container.
///
/// This function does not authenticate the bytes or establish form identity.
pub fn decryptAlloc(
    allocator: Allocator,
    ciphertext: []const u8,
    protocol_secret: []const u8,
    limits: Limits,
) Error!DecryptedPlaintext {
    try limits.validate();
    if (protocol_secret.len == 0) return error.EmptyProtocolSecret;
    if (ciphertext.len < minimum_zlib_stream_bytes) {
        return error.TruncatedContainer;
    }
    if (ciphertext.len > limits.max_ciphertext_bytes) {
        return error.CiphertextTooLarge;
    }

    const compressed = allocator.alloc(u8, ciphertext.len) catch
        return error.OutOfMemory;
    defer wipeAndFree(allocator, compressed);

    decryptCipherStream(compressed, ciphertext, protocol_secret);

    const plaintext = try inflateStrictAlloc(
        allocator,
        compressed,
        limits.max_plaintext_bytes,
    );
    errdefer wipeAndFree(allocator, plaintext);

    if (!std.unicode.utf8ValidateSlice(plaintext)) return error.InvalidUtf8;

    return .{
        .allocator = allocator,
        .storage = plaintext,
    };
}

/// Apply a strict, caller-owned lossless-document/form-identity predicate after
/// the cryptographic and byte-level checks.
pub fn decryptAndValidateAlloc(
    allocator: Allocator,
    ciphertext: []const u8,
    protocol_secret: []const u8,
    limits: Limits,
    validator: *const fn ([]const u8) bool,
) Error!DecryptedPlaintext {
    var plaintext = try decryptAlloc(
        allocator,
        ciphertext,
        protocol_secret,
        limits,
    );
    errdefer plaintext.deinit();

    if (!validator(plaintext.bytes())) {
        return error.MalformedPayloadStructure;
    }
    return plaintext;
}

fn wipeAndFree(allocator: Allocator, bytes: []u8) void {
    sensitive_memory.wipeAndFreeDefaultAligned(u8, allocator, bytes);
}

fn inflateStrictAlloc(
    allocator: Allocator,
    compressed: []const u8,
    plaintext_limit: usize,
) Error![]u8 {
    var source: std.Io.Reader = .fixed(compressed);
    defer sensitive_memory.wipeValue(std.Io.Reader, &source);
    var inflater_buffer: [std.compress.flate.max_window_len]u8 = undefined;
    defer std.crypto.secureZero(u8, &inflater_buffer);
    var inflater: std.compress.flate.Decompress = .init(
        &source,
        .zlib,
        &inflater_buffer,
    );
    defer sensitive_memory.wipeValue(
        std.compress.flate.Decompress,
        &inflater,
    );

    var accumulated: std.ArrayList(u8) = .empty;
    errdefer sensitive_memory.wipeAndDeinitArrayList(
        u8,
        allocator,
        &accumulated,
    );
    var chunk: [16 * 1024]u8 = undefined;
    defer std.crypto.secureZero(u8, &chunk);

    while (true) {
        const read_count = inflater.reader.readSliceShort(&chunk) catch {
            if (inflater.err) |cause| {
                if (cause == error.EndOfStream) {
                    return error.TruncatedContainer;
                }
            }
            return error.InflateFailure;
        };
        if (read_count == 0) break;
        if (read_count > plaintext_limit or
            accumulated.items.len > plaintext_limit - read_count)
        {
            return error.PlaintextTooLarge;
        }
        sensitive_memory.appendSlice(
            u8,
            allocator,
            &accumulated,
            chunk[0..read_count],
        ) catch return error.OutOfMemory;
    }

    const plaintext = sensitive_memory.toOwnedSlice(
        u8,
        allocator,
        &accumulated,
    ) catch return error.OutOfMemory;
    errdefer wipeAndFree(allocator, plaintext);

    if (source.seek != source.end) return error.TrailingCompressedData;

    const recorded_adler = std.mem.readInt(
        u32,
        compressed[compressed.len - 4 ..][0..4],
        .big,
    );
    if (std.hash.Adler32.hash(plaintext) != recorded_adler) {
        return error.InflateFailure;
    }

    return plaintext;
}

fn deriveCipherKey(protocol_secret: []const u8) [Sha256.digest_length]u8 {
    var key: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(protocol_secret, &key, .{});
    return key;
}

fn decryptCipherStream(
    output: []u8,
    input: []const u8,
    protocol_secret: []const u8,
) void {
    std.debug.assert(output.len == input.len);

    var key = deriveCipherKey(protocol_secret);
    defer std.crypto.secureZero(u8, &key);

    var block_encryptor = Aes256.initEnc(key);
    defer std.crypto.secureZero(
        @TypeOf(block_encryptor),
        (&block_encryptor)[0..1],
    );
    var block_decryptor = Aes256.initDec(key);
    defer std.crypto.secureZero(
        @TypeOf(block_decryptor),
        (&block_decryptor)[0..1],
    );

    const zero_block = [_]u8{0} ** cipher_block_bytes;
    var chain: [cipher_block_bytes]u8 = undefined;
    defer std.crypto.secureZero(u8, &chain);
    block_encryptor.encrypt(&chain, &zero_block);

    var cursor: usize = 0;
    while (cursor + cipher_block_bytes <= input.len) : (cursor += cipher_block_bytes) {
        const encrypted_block: [cipher_block_bytes]u8 =
            input[cursor..][0..cipher_block_bytes].*;
        var decoded_block: [cipher_block_bytes]u8 = undefined;
        defer std.crypto.secureZero(u8, &decoded_block);

        block_decryptor.decrypt(&decoded_block, &encrypted_block);
        for (&decoded_block, chain) |*byte, chain_byte| {
            byte.* ^= chain_byte;
        }
        output[cursor..][0..cipher_block_bytes].* = decoded_block;
        chain = encrypted_block;
    }

    const partial = input[cursor..];
    if (partial.len != 0) {
        var key_stream: [cipher_block_bytes]u8 = undefined;
        defer std.crypto.secureZero(u8, &key_stream);
        block_encryptor.encrypt(&key_stream, &chain);

        for (partial, 0..) |encrypted_byte, index| {
            output[cursor + index] = encrypted_byte ^ key_stream[index];
        }
    }
}

fn decodeSyntheticHex(comptime encoded: []const u8) [encoded.len / 2]u8 {
    var decoded: [encoded.len / 2]u8 = undefined;
    _ = std.fmt.hexToBytes(&decoded, encoded) catch unreachable;
    return decoded;
}

fn isSyntheticDocument(bytes: []const u8) bool {
    return std.mem.startsWith(u8, bytes, "<s ") and
        std.mem.endsWith(u8, bytes, "</s>\r\n");
}

fn exerciseDecryptAllocationPaths(allocator: Allocator) !void {
    const ciphertext = decodeSyntheticHex(
        "fd36392320a2f11c1afee6e0ee1ac1ff" ++
            "63fd0111eb753a4d3f1cfe518849da4f",
    );
    var plaintext = try decryptAndValidateAlloc(
        allocator,
        &ciphertext,
        "synthetic-legacy-codec-test-key-v2",
        .{},
        isSyntheticDocument,
    );
    defer plaintext.deinit();
    try std.testing.expectEqualStrings(
        "<s c=\"10\">jCjXz32%</s>\r\n",
        plaintext.bytes(),
    );
}

test "all decrypt allocation failures erase and release partial values" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exerciseDecryptAllocationPaths,
        .{},
    );
}

test "strict inflate handles zero-length plaintext ownership" {
    const empty_zlib = [_]u8{
        0x78, 0x9c, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01,
    };
    const plaintext = try inflateStrictAlloc(
        std.testing.allocator,
        &empty_zlib,
        0,
    );
    defer wipeAndFree(std.testing.allocator, plaintext);
    try std.testing.expectEqual(@as(usize, 0), plaintext.len);
}

test "independent synthetic answers cover full blocks and two tail sizes" {
    const protocol_secret = "synthetic-legacy-codec-test-key-v2";
    const vectors = .{
        .{
            .ciphertext = decodeSyntheticHex(
                "fd36392320a2f11c1afee6e0ee1ac1ff" ++
                    "63fd0111eb753a4d3f1cfe518849da4f",
            ),
            .expected = "<s c=\"10\">jCjXz32%</s>\r\n",
            .compressed_tail = 0,
        },
        .{
            .ciphertext = decodeSyntheticHex(
                "fd36392320a2f11c1afee6e0ee1ac1ff" ++
                    "f6bdd47fe7e20736bf24df95f5660aee0a",
            ),
            .expected = "<s c=\"10\">jCjXz32%n</s>\r\n",
            .compressed_tail = 1,
        },
        .{
            .ciphertext = decodeSyntheticHex(
                "fd36392320a2f11c1afee6e0ee1ac1ff" ++
                    "5c9169f0f62e18c7a024a6d6c6c475",
            ),
            .expected = "<s c=\"10\">jCjXz32</s>\r\n",
            .compressed_tail = 15,
        },
    };

    inline for (vectors) |vector| {
        try std.testing.expectEqual(
            @as(usize, vector.compressed_tail),
            vector.ciphertext.len % cipher_block_bytes,
        );
        var plaintext = try decryptAndValidateAlloc(
            std.testing.allocator,
            &vector.ciphertext,
            protocol_secret,
            .{},
            isSyntheticDocument,
        );
        defer plaintext.deinit();

        try std.testing.expectEqualStrings(
            vector.expected,
            plaintext.bytes(),
        );
    }
}

test "bounds and empty secret fail before value-bearing output exists" {
    const ciphertext = decodeSyntheticHex(
        "fd36392320a2f11c1afee6e0ee1ac1ff" ++
            "63fd0111eb753a4d3f1cfe518849da4f",
    );

    try std.testing.expectError(
        error.EmptyProtocolSecret,
        decryptAlloc(std.testing.allocator, &ciphertext, "", .{}),
    );
    try std.testing.expectError(
        error.TruncatedContainer,
        decryptAlloc(
            std.testing.allocator,
            ciphertext[0 .. minimum_zlib_stream_bytes - 1],
            "synthetic-legacy-codec-test-key-v2",
            .{},
        ),
    );
    try std.testing.expectError(
        error.CiphertextTooLarge,
        decryptAlloc(
            std.testing.allocator,
            &ciphertext,
            "synthetic-legacy-codec-test-key-v2",
            .{ .max_ciphertext_bytes = ciphertext.len - 1 },
        ),
    );
    try std.testing.expectError(
        error.PlaintextTooLarge,
        decryptAlloc(
            std.testing.allocator,
            &ciphertext,
            "synthetic-legacy-codec-test-key-v2",
            .{ .max_plaintext_bytes = 4 },
        ),
    );
}

test "invalid UTF-8 checksum damage and trailing bytes are rejected" {
    const protocol_secret = "synthetic-legacy-codec-test-key-v2";
    const invalid_utf8 = decodeSyntheticHex(
        "06ad6f6505dfecaecb59ef",
    );
    const trailing_stream = decodeSyntheticHex(
        "defba97d1f520aa8a43d36980886be3e240b43885c2f",
    );
    const bad_adler = decodeSyntheticHex(
        "defba97d1f520aa8a43d36980886be3e240b43885d",
    );

    try std.testing.expectError(
        error.InvalidUtf8,
        decryptAlloc(
            std.testing.allocator,
            &invalid_utf8,
            protocol_secret,
            .{},
        ),
    );
    try std.testing.expectError(
        error.TrailingCompressedData,
        decryptAlloc(
            std.testing.allocator,
            &trailing_stream,
            protocol_secret,
            .{},
        ),
    );
    try std.testing.expectError(
        error.InflateFailure,
        decryptAlloc(
            std.testing.allocator,
            &bad_adler,
            protocol_secret,
            .{},
        ),
    );
}

test "wrong secret corruption and structural rejection never return plaintext" {
    const protocol_secret = "synthetic-legacy-codec-test-key-v2";
    const ciphertext = decodeSyntheticHex(
        "fd36392320a2f11c1afee6e0ee1ac1ff" ++
            "63fd0111eb753a4d3f1cfe518849da4f",
    );

    if (decryptAlloc(
        std.testing.allocator,
        &ciphertext,
        "different-synthetic-key",
        .{},
    )) |unexpected_value| {
        var unexpected = unexpected_value;
        defer unexpected.deinit();
        return error.TestUnexpectedResult;
    } else |err| {
        try std.testing.expect(
            err == error.InflateFailure or
                err == error.TruncatedContainer or
                err == error.TrailingCompressedData or
                err == error.InvalidUtf8,
        );
    }

    var corrupted = ciphertext;
    corrupted[0] ^= 0x80;
    if (decryptAlloc(
        std.testing.allocator,
        &corrupted,
        protocol_secret,
        .{},
    )) |unexpected_value| {
        var unexpected = unexpected_value;
        defer unexpected.deinit();
        return error.TestUnexpectedResult;
    } else |_| {}

    try std.testing.expectError(
        error.MalformedPayloadStructure,
        decryptAndValidateAlloc(
            std.testing.allocator,
            &ciphertext,
            protocol_secret,
            .{},
            struct {
                fn reject(_: []const u8) bool {
                    return false;
                }
            }.reject,
        ),
    );
}

test "qualification and diagnostics remain fixed and fail closed" {
    const qualification = qualificationSummary();
    try std.testing.expectEqual(
        QualificationState.private_vector_record_absent,
        qualification.state,
    );
    try std.testing.expectEqual(@as(u16, 67), qualification.required_decrypt_vectors);
    try std.testing.expectEqual(@as(u16, 0), qualification.verified_decrypt_vectors);
    try std.testing.expectEqual(
        @as(u16, 67),
        qualification.required_exact_encrypt_vectors,
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        qualification.verified_exact_encrypt_vectors,
    );
    try std.testing.expect(!qualification.outbound_encryption_available);
    try std.testing.expectEqual(
        @as(usize, 1),
        @typeInfo(QualificationState).@"enum".fields.len,
    );

    const mappings = [_]struct {
        err: Error,
        code: DiagnosticCode,
    }{
        .{ .err = error.OutOfMemory, .code = .out_of_memory },
        .{ .err = error.EmptyProtocolSecret, .code = .empty_protocol_secret },
        .{ .err = error.InvalidLimits, .code = .invalid_limits },
        .{ .err = error.TruncatedContainer, .code = .truncated_container },
        .{ .err = error.CiphertextTooLarge, .code = .ciphertext_too_large },
        .{ .err = error.DecryptFailure, .code = .decrypt_failure },
        .{ .err = error.InflateFailure, .code = .inflate_failure },
        .{
            .err = error.TrailingCompressedData,
            .code = .trailing_compressed_data,
        },
        .{ .err = error.PlaintextTooLarge, .code = .plaintext_too_large },
        .{ .err = error.InvalidUtf8, .code = .invalid_utf8 },
        .{
            .err = error.MalformedPayloadStructure,
            .code = .malformed_payload_structure,
        },
    };

    try std.testing.expectEqual(
        mappings.len,
        @typeInfo(Error).error_set.?.len,
    );
    for (mappings) |mapping| {
        try std.testing.expectEqual(mapping.code, diagnosticCode(mapping.err));
    }
}

test "caller limits cannot raise the absolute allocation ceilings" {
    const ciphertext = [_]u8{0} ** minimum_zlib_stream_bytes;
    try std.testing.expectError(
        error.InvalidLimits,
        decryptAlloc(
            std.testing.allocator,
            &ciphertext,
            "synthetic-secret",
            .{
                .max_ciphertext_bytes = absolute_max_ciphertext_bytes + 1,
            },
        ),
    );
    try std.testing.expectError(
        error.InvalidLimits,
        decryptAlloc(
            std.testing.allocator,
            &ciphertext,
            "synthetic-secret",
            .{
                .max_plaintext_bytes = absolute_max_plaintext_bytes + 1,
            },
        ),
    );
    try std.testing.expectError(
        error.InvalidLimits,
        decryptAlloc(
            std.testing.allocator,
            &ciphertext,
            "synthetic-secret",
            .{ .max_ciphertext_bytes = 0 },
        ),
    );
}
