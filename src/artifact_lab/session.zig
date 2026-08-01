//! Masked-by-default, offline artifact inspection state.
//!
//! This module has no filesystem, network, queue, submission, or outbound
//! encryption operation. It owns sensitive buffers, wipes them on replacement
//! and teardown, and reveals bytes only after an explicit per-slot action.

const std = @import("std");
const legacy_container = @import("../container_codec/legacy.zig");
const sensitive_memory = @import("../security/sensitive_memory.zig");

const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;

pub const Error = legacy_container.Error || error{
    OutOfMemory,
    EmptyArtifact,
    StrictPayloadRejected,
    MissingGeneratedPlaintext,
    MissingImportedCiphertext,
    MissingDecryptedPlaintext,
};

pub const ArtifactSlot = enum {
    generated_plaintext,
    imported_ciphertext,
    decrypted_plaintext,
};

pub const MaskedSummary = struct {
    byte_length: usize,
    sha256: [Sha256.digest_length]u8,
};

pub const DisplayValue = union(enum) {
    masked: MaskedSummary,
    revealed: []const u8,
};

pub const DiffSummary = struct {
    equal: bool,
    generated: MaskedSummary,
    decrypted: MaskedSummary,
    first_difference_index: ?usize,
};

const SensitiveBuffer = struct {
    allocator: Allocator,
    storage: []u8,

    fn init(
        allocator: Allocator,
        source: []const u8,
    ) Error!SensitiveBuffer {
        if (source.len == 0) return error.EmptyArtifact;
        const storage = allocator.dupe(u8, source) catch
            return error.OutOfMemory;
        return .{ .allocator = allocator, .storage = storage };
    }

    fn bytes(self: *const SensitiveBuffer) []const u8 {
        return self.storage;
    }

    fn summary(self: *const SensitiveBuffer) MaskedSummary {
        return summarize(self.storage);
    }

    fn deinit(self: *SensitiveBuffer) void {
        sensitive_memory.wipeAndFreeDefaultAligned(
            u8,
            self.allocator,
            self.storage,
        );
        sensitive_memory.wipeValue(SensitiveBuffer, self);
    }
};

pub const Session = struct {
    const Self = @This();

    allocator: Allocator,
    exact_form_package_digest: [Sha256.digest_length]u8,
    profile_snapshot_digest: [Sha256.digest_length]u8,
    generated_plaintext: ?SensitiveBuffer = null,
    imported_ciphertext: ?SensitiveBuffer = null,
    decrypted_plaintext: ?legacy_container.DecryptedPlaintext = null,
    reveal_generated: bool = false,
    reveal_ciphertext: bool = false,
    reveal_decrypted: bool = false,

    pub fn init(
        allocator: Allocator,
        exact_form_package_digest: [Sha256.digest_length]u8,
        profile_snapshot_digest: [Sha256.digest_length]u8,
    ) Self {
        return .{
            .allocator = allocator,
            .exact_form_package_digest = exact_form_package_digest,
            .profile_snapshot_digest = profile_snapshot_digest,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.generated_plaintext) |*value| value.deinit();
        if (self.imported_ciphertext) |*value| value.deinit();
        if (self.decrypted_plaintext) |*value| value.deinit();
        sensitive_memory.wipeValue(Self, self);
    }

    pub fn setGeneratedPlaintext(
        self: *Self,
        plaintext: []const u8,
        strict_validator: *const fn ([]const u8) bool,
    ) Error!void {
        if (plaintext.len > legacy_container.absolute_max_plaintext_bytes) {
            return error.PlaintextTooLarge;
        }
        if (!strict_validator(plaintext)) {
            return error.StrictPayloadRejected;
        }
        const replacement = try SensitiveBuffer.init(
            self.allocator,
            plaintext,
        );
        if (self.generated_plaintext) |*current| current.deinit();
        self.generated_plaintext = replacement;
        self.reveal_generated = false;
    }

    pub fn setImportedCiphertext(
        self: *Self,
        ciphertext: []const u8,
        limits: legacy_container.Limits,
    ) Error!void {
        try limits.validate();
        if (ciphertext.len > limits.max_ciphertext_bytes) {
            return error.CiphertextTooLarge;
        }
        const replacement = try SensitiveBuffer.init(
            self.allocator,
            ciphertext,
        );
        if (self.imported_ciphertext) |*current| current.deinit();
        if (self.decrypted_plaintext) |*current| {
            current.deinit();
            self.decrypted_plaintext = null;
        }
        self.imported_ciphertext = replacement;
        self.reveal_ciphertext = false;
        self.reveal_decrypted = false;
    }

    /// The protocol secret is borrowed only for this call and is never stored.
    /// The container result is accepted only after the strict payload/form
    /// predicate succeeds.
    pub fn decryptImported(
        self: *Self,
        protocol_secret: []const u8,
        limits: legacy_container.Limits,
        strict_validator: *const fn ([]const u8) bool,
    ) Error!void {
        const ciphertext = if (self.imported_ciphertext) |*value|
            value.bytes()
        else
            return error.MissingImportedCiphertext;

        var replacement = try legacy_container.decryptAndValidateAlloc(
            self.allocator,
            ciphertext,
            protocol_secret,
            limits,
            strict_validator,
        );
        errdefer replacement.deinit();

        if (self.decrypted_plaintext) |*current| current.deinit();
        self.decrypted_plaintext = replacement;
        self.reveal_decrypted = false;
    }

    pub fn setRevealed(
        self: *Self,
        slot: ArtifactSlot,
        revealed: bool,
    ) Error!void {
        switch (slot) {
            .generated_plaintext => {
                if (self.generated_plaintext == null) {
                    return error.MissingGeneratedPlaintext;
                }
                self.reveal_generated = revealed;
            },
            .imported_ciphertext => {
                if (self.imported_ciphertext == null) {
                    return error.MissingImportedCiphertext;
                }
                self.reveal_ciphertext = revealed;
            },
            .decrypted_plaintext => {
                if (self.decrypted_plaintext == null) {
                    return error.MissingDecryptedPlaintext;
                }
                self.reveal_decrypted = revealed;
            },
        }
    }

    pub fn display(
        self: *const Self,
        slot: ArtifactSlot,
    ) Error!DisplayValue {
        return switch (slot) {
            .generated_plaintext => if (self.generated_plaintext) |*value|
                displayBuffer(value.bytes(), self.reveal_generated)
            else
                error.MissingGeneratedPlaintext,
            .imported_ciphertext => if (self.imported_ciphertext) |*value|
                displayBuffer(value.bytes(), self.reveal_ciphertext)
            else
                error.MissingImportedCiphertext,
            .decrypted_plaintext => if (self.decrypted_plaintext) |*value|
                displayBuffer(value.bytes(), self.reveal_decrypted)
            else
                error.MissingDecryptedPlaintext,
        };
    }

    pub fn compareGeneratedToDecrypted(
        self: *const Self,
    ) Error!DiffSummary {
        const generated = if (self.generated_plaintext) |*value|
            value.bytes()
        else
            return error.MissingGeneratedPlaintext;
        const decrypted = if (self.decrypted_plaintext) |*value|
            value.bytes()
        else
            return error.MissingDecryptedPlaintext;

        const shared_len = @min(generated.len, decrypted.len);
        var first_difference: ?usize = null;
        for (generated[0..shared_len], decrypted[0..shared_len], 0..) |
            generated_byte,
            decrypted_byte,
            index,
        | {
            if (generated_byte != decrypted_byte) {
                first_difference = index;
                break;
            }
        }
        if (first_difference == null and generated.len != decrypted.len) {
            first_difference = shared_len;
        }

        return .{
            .equal = first_difference == null,
            .generated = summarize(generated),
            .decrypted = summarize(decrypted),
            .first_difference_index = first_difference,
        };
    }

    pub fn qualification(
        _: *const Self,
    ) legacy_container.QualificationSummary {
        return legacy_container.qualificationSummary();
    }

    pub fn transportEnabled(_: *const Self) bool {
        return false;
    }
};

fn displayBuffer(bytes: []const u8, revealed: bool) DisplayValue {
    if (revealed) return .{ .revealed = bytes };
    return .{ .masked = summarize(bytes) };
}

fn summarize(bytes: []const u8) MaskedSummary {
    var digest: [Sha256.digest_length]u8 = undefined;
    Sha256.hash(bytes, &digest, .{});
    return .{ .byte_length = bytes.len, .sha256 = digest };
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

fn exerciseSessionAllocationPaths(allocator: Allocator) !void {
    const ciphertext = decodeSyntheticHex(
        "fd36392320a2f11c1afee6e0ee1ac1ff" ++
            "63fd0111eb753a4d3f1cfe518849da4f",
    );
    var session = Session.init(
        allocator,
        [_]u8{0x77} ** Sha256.digest_length,
        [_]u8{0x88} ** Sha256.digest_length,
    );
    defer session.deinit();

    try session.setGeneratedPlaintext(
        "<s c=\"10\">first</s>\r\n",
        isSyntheticDocument,
    );
    try session.setGeneratedPlaintext(
        "<s c=\"10\">replacement</s>\r\n",
        isSyntheticDocument,
    );
    try session.setImportedCiphertext(&ciphertext, .{});
    try session.decryptImported(
        "synthetic-legacy-codec-test-key-v2",
        .{},
        isSyntheticDocument,
    );
    try session.setImportedCiphertext("replacement-ciphertext", .{});
}

test "all artifact session allocation failures erase partial values" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exerciseSessionAllocationPaths,
        .{},
    );
}

test "all artifact values are masked until their exact slot is revealed" {
    var session = Session.init(
        std.testing.allocator,
        [_]u8{0x11} ** Sha256.digest_length,
        [_]u8{0x22} ** Sha256.digest_length,
    );
    defer session.deinit();

    const plaintext = "<s c=\"10\">jCjXz32%</s>\r\n";
    try session.setGeneratedPlaintext(plaintext, isSyntheticDocument);

    switch (try session.display(.generated_plaintext)) {
        .masked => |summary| {
            try std.testing.expectEqual(plaintext.len, summary.byte_length);
        },
        .revealed => return error.TestUnexpectedResult,
    }
    try session.setRevealed(.generated_plaintext, true);
    switch (try session.display(.generated_plaintext)) {
        .revealed => |bytes| try std.testing.expectEqualStrings(
            plaintext,
            bytes,
        ),
        .masked => return error.TestUnexpectedResult,
    }
    try std.testing.expect(!session.transportEnabled());
    try std.testing.expect(!session.qualification().outbound_encryption_available);
}

test "strict synthetic decrypt compares hashes and bytes without auto reveal" {
    const ciphertext = decodeSyntheticHex(
        "fd36392320a2f11c1afee6e0ee1ac1ff" ++
            "63fd0111eb753a4d3f1cfe518849da4f",
    );
    const plaintext = "<s c=\"10\">jCjXz32%</s>\r\n";
    var session = Session.init(
        std.testing.allocator,
        [_]u8{0x33} ** Sha256.digest_length,
        [_]u8{0x44} ** Sha256.digest_length,
    );
    defer session.deinit();

    try session.setGeneratedPlaintext(plaintext, isSyntheticDocument);
    try session.setImportedCiphertext(&ciphertext, .{});
    try session.decryptImported(
        "synthetic-legacy-codec-test-key-v2",
        .{},
        isSyntheticDocument,
    );

    const comparison = try session.compareGeneratedToDecrypted();
    try std.testing.expect(comparison.equal);
    try std.testing.expect(comparison.first_difference_index == null);
    try std.testing.expectEqualSlices(
        u8,
        &comparison.generated.sha256,
        &comparison.decrypted.sha256,
    );
    switch (try session.display(.decrypted_plaintext)) {
        .masked => {},
        .revealed => return error.TestUnexpectedResult,
    }
}

test "strict validators and missing slots fail closed" {
    var session = Session.init(
        std.testing.allocator,
        [_]u8{0x55} ** Sha256.digest_length,
        [_]u8{0x66} ** Sha256.digest_length,
    );
    defer session.deinit();

    try std.testing.expectError(
        error.StrictPayloadRejected,
        session.setGeneratedPlaintext(
            "not-a-document",
            isSyntheticDocument,
        ),
    );
    try std.testing.expectError(
        error.MissingImportedCiphertext,
        session.decryptImported(
            "synthetic-secret",
            .{},
            isSyntheticDocument,
        ),
    );
    try std.testing.expectError(
        error.MissingGeneratedPlaintext,
        session.compareGeneratedToDecrypted(),
    );
    try session.setGeneratedPlaintext(
        "<s c=\"10\">synthetic</s>\r\n",
        isSyntheticDocument,
    );
    try std.testing.expectError(
        error.MissingDecryptedPlaintext,
        session.compareGeneratedToDecrypted(),
    );
}

test "ciphertext staging rejects limits before allocating" {
    var no_storage: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_storage);
    var session = Session.init(
        fixed.allocator(),
        [_]u8{0x91} ** Sha256.digest_length,
        [_]u8{0x92} ** Sha256.digest_length,
    );
    defer session.deinit();

    try std.testing.expectError(
        error.CiphertextTooLarge,
        session.setImportedCiphertext(
            "four",
            .{
                .max_ciphertext_bytes = 3,
                .max_plaintext_bytes = 1,
            },
        ),
    );
    try std.testing.expectError(
        error.InvalidLimits,
        session.setImportedCiphertext(
            "x",
            .{ .max_ciphertext_bytes = 0 },
        ),
    );
}

test "the lab API exposes no outbound or transport transition" {
    try std.testing.expect(!@hasDecl(Session, "encrypt"));
    try std.testing.expect(!@hasDecl(Session, "submit"));
    try std.testing.expect(!@hasDecl(Session, "queue"));
    try std.testing.expect(!@hasDecl(Session, "upload"));
}
