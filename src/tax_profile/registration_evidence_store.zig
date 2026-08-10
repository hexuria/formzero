//! Bounded inspection, verification, and protected storage for registration
//! evidence bytes.
//!
//! Selection records a source fingerprint. Confirmation never refreshes that
//! fingerprint: it verifies the exact digest and size, then atomically links a
//! digest-addressed private copy beneath an explicitly configured data root.

const std = @import("std");
const domain = @import("registration_domain.zig");
const storage_contract = @import("registration_storage_contract.zig");

pub const max_document_bytes: u64 = 16 * 1024 * 1024;
pub const directory_name = "registration-evidence";

pub const Fingerprint = struct {
    sha256: [64]u8,
    byte_size: u64,
};

pub const InspectError = error{
    SourceMissing,
    SourceUnreadable,
    Empty,
    TooLarge,
    Unsupported,
};

pub const VerifyError = InspectError || error{
    InvalidExpectedDigest,
    InvalidProtectedReference,
    SizeChanged,
    DigestChanged,
};

pub const ProtectError = VerifyError || error{
    DataDirectoryRequired,
    PathTooLong,
    StorageUnavailable,
    InvalidDestination,
};

const InspectFileError = InspectError || error{StorageUnavailable};

/// Reads a supported PDF, PNG, or JPEG at most once into bounded chunks and
/// returns its lowercase SHA-256 plus exact size.
pub fn inspect(io: std.Io, path: []const u8) InspectError!Fingerprint {
    var file = std.Io.Dir.cwd().openFile(io, path, .{
        .allow_directory = false,
    }) catch |err| return mapOpenSourceError(err);
    defer file.close(io);
    return inspectFile(io, file, null) catch |err| switch (err) {
        error.StorageUnavailable => unreachable,
        else => |source_err| source_err,
    };
}

/// Read-only callback-shaped verification seam for future ledger use.
/// Success means the referenced bytes still match both immutable metadata
/// fields. It never returns a refreshed fingerprint.
pub fn verify(
    io: std.Io,
    path: []const u8,
    expected_digest: []const u8,
    expected_size: u64,
) VerifyError!void {
    const digest = domain.Sha256Digest.parse(expected_digest) catch
        return error.InvalidExpectedDigest;
    const actual = try inspect(io, path);
    try compareFingerprint(actual, digest, expected_size);
}

/// Verifies the selected source and returns a caller-buffered path to an
/// immutable, digest-addressed protected copy. Existing destinations are
/// reusable only when their bytes and regular-file identity verify exactly;
/// an invalid destination is never overwritten.
pub fn protect(
    io: std.Io,
    data_dir: []const u8,
    source_path: []const u8,
    expected_digest: []const u8,
    expected_size: u64,
    protected_path_buffer: []u8,
) ProtectError![]const u8 {
    if (data_dir.len == 0) return error.DataDirectoryRequired;
    _ = domain.Sha256Digest.parse(expected_digest) catch
        return error.InvalidExpectedDigest;
    const protected_suffix_len =
        1 + directory_name.len + 1 + expected_digest.len;
    if (protected_path_buffer.len < protected_suffix_len or
        data_dir.len > protected_path_buffer.len - protected_suffix_len)
    {
        return error.PathTooLong;
    }
    var root = std.Io.Dir.cwd().openDir(io, data_dir, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch return error.StorageUnavailable;
    defer root.close(io);
    return protectInDirectory(
        io,
        root,
        source_path,
        expected_digest,
        expected_size,
        protected_path_buffer,
    );
}

/// Capability-relative protected storage. The retained data-root handle, not
/// a recomputed path, owns every directory and digest-file operation. The
/// returned absolute reference is derived from that same handle only after the
/// destination has been verified.
pub fn protectInDirectory(
    io: std.Io,
    data_directory: std.Io.Dir,
    source_path: []const u8,
    expected_digest: []const u8,
    expected_size: u64,
    protected_path_buffer: []u8,
) ProtectError![]const u8 {
    const digest = domain.Sha256Digest.parse(expected_digest) catch
        return error.InvalidExpectedDigest;

    // This is intentionally a distinct first operation. A source that changed
    // after selection is rejected before any protected-store mutation.
    try verify(io, source_path, expected_digest, expected_size);

    var data_dir_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const data_dir_path_len = data_directory.realPath(
        io,
        &data_dir_path_buffer,
    ) catch return error.StorageUnavailable;
    const data_dir_path = data_dir_path_buffer[0..data_dir_path_len];
    var evidence_dir_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const evidence_dir_path = std.fmt.bufPrint(
        &evidence_dir_path_buffer,
        "{s}{c}{s}",
        .{ data_dir_path, std.fs.path.sep, directory_name },
    ) catch return error.PathTooLong;

    const protected_path = std.fmt.bufPrint(
        protected_path_buffer,
        "{s}{c}{s}",
        .{ evidence_dir_path, std.fs.path.sep, expected_digest },
    ) catch return error.PathTooLong;
    if (protected_path.len >
        storage_contract.max_evidence_storage_reference_bytes)
    {
        // Reject before stat/create/copy so the ledger and SQLite length
        // boundary cannot leave an unreferenced protected file behind.
        return error.PathTooLong;
    }

    data_directory.createDir(
        io,
        directory_name,
        privateDirectoryPermissions(),
    ) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return error.StorageUnavailable,
    };
    var evidence_dir = data_directory.openDir(io, directory_name, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch return error.StorageUnavailable;
    defer evidence_dir.close(io);
    evidence_dir.setPermissions(io, privateDirectoryPermissions()) catch
        return error.StorageUnavailable;

    const destination_stat = evidence_dir.statFile(
        io,
        expected_digest,
        .{ .follow_symlinks = false },
    ) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return error.StorageUnavailable,
    };
    if (destination_stat) |stat| {
        if (stat.kind != .file or stat.nlink != 1) {
            return error.InvalidDestination;
        }
        verifyDigestFile(
            io,
            evidence_dir,
            expected_digest,
            digest,
            expected_size,
        ) catch
            return error.InvalidDestination;
        setProtectedFilePermissions(io, evidence_dir, expected_digest) catch
            return error.StorageUnavailable;
        return protected_path;
    }

    var atomic = evidence_dir.createFileAtomic(io, expected_digest, .{
        .permissions = privateFilePermissions(),
    }) catch return error.StorageUnavailable;
    defer atomic.deinit(io);

    var source = std.Io.Dir.cwd().openFile(io, source_path, .{
        .allow_directory = false,
    }) catch |err| return mapOpenSourceError(err);
    defer source.close(io);

    // Re-check while copying as well, closing the verification/copy race. A
    // mutation between the first verification and this read deletes the
    // temporary file and leaves no destination.
    const copied = try inspectFile(io, source, atomic.file);
    try compareFingerprint(copied, digest, expected_size);
    atomic.file.setPermissions(io, privateFilePermissions()) catch
        return error.StorageUnavailable;
    atomic.file.sync(io) catch return error.StorageUnavailable;

    atomic.link(io) catch |err| switch (err) {
        error.PathAlreadyExists => {
            const raced_stat = evidence_dir.statFile(
                io,
                expected_digest,
                .{ .follow_symlinks = false },
            ) catch return error.InvalidDestination;
            if (raced_stat.kind != .file or raced_stat.nlink != 1) {
                return error.InvalidDestination;
            }
            verifyDigestFile(
                io,
                evidence_dir,
                expected_digest,
                digest,
                expected_size,
            ) catch
                return error.InvalidDestination;
        },
        else => return error.StorageUnavailable,
    };

    setProtectedFilePermissions(io, evidence_dir, expected_digest) catch
        return error.StorageUnavailable;
    syncDirectory(evidence_dir, io) catch return error.StorageUnavailable;
    verifyDigestFile(
        io,
        evidence_dir,
        expected_digest,
        digest,
        expected_size,
    ) catch
        return error.InvalidDestination;
    return protected_path;
}

/// Verifies an immutable protected reference through the retained data-root
/// capability. The persisted path must name the expected digest, but it is not
/// trusted to select the directory that is opened.
pub fn verifyProtectedInDirectory(
    io: std.Io,
    data_directory: std.Io.Dir,
    protected_path: []const u8,
    expected_digest: []const u8,
    expected_size: u64,
) VerifyError!void {
    const digest = domain.Sha256Digest.parse(expected_digest) catch
        return error.InvalidExpectedDigest;
    if (!std.mem.eql(
        u8,
        std.fs.path.basename(protected_path),
        expected_digest,
    )) return error.InvalidProtectedReference;

    var evidence_dir = data_directory.openDir(io, directory_name, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch |err| return switch (err) {
        error.FileNotFound => error.SourceMissing,
        else => error.SourceUnreadable,
    };
    defer evidence_dir.close(io);
    return verifyDigestFile(
        io,
        evidence_dir,
        expected_digest,
        digest,
        expected_size,
    );
}

fn verifyDigestFile(
    io: std.Io,
    evidence_dir: std.Io.Dir,
    basename: []const u8,
    expected_digest: domain.Sha256Digest,
    expected_size: u64,
) VerifyError!void {
    const before = evidence_dir.statFile(
        io,
        basename,
        .{ .follow_symlinks = false },
    ) catch |err| return switch (err) {
        error.FileNotFound => error.SourceMissing,
        else => error.SourceUnreadable,
    };
    if (before.kind != .file or before.nlink != 1) {
        return error.SourceUnreadable;
    }
    var file = evidence_dir.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch |err| return mapOpenSourceError(err);
    defer file.close(io);
    const after = file.stat(io) catch return error.SourceUnreadable;
    if (after.kind != .file or
        after.nlink != 1 or
        after.inode != before.inode)
    {
        return error.SourceUnreadable;
    }
    const actual = inspectFile(io, file, null) catch |err| switch (err) {
        error.StorageUnavailable => return error.SourceUnreadable,
        else => |source_err| return source_err,
    };
    try compareFingerprint(actual, expected_digest, expected_size);
}

fn syncDirectory(directory: std.Io.Dir, io: std.Io) !void {
    if (@import("builtin").os.tag == .windows) return;
    const directory_file: std.Io.File = .{
        .handle = directory.handle,
        .flags = .{ .nonblocking = false },
    };
    try directory_file.sync(io);
}

fn inspectFile(
    io: std.Io,
    source: std.Io.File,
    destination: ?std.Io.File,
) InspectFileError!Fingerprint {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [64 * 1024]u8 = undefined;
    var total: u64 = 0;
    var signature: [8]u8 = undefined;
    var signature_len: usize = 0;

    while (true) {
        const read = source.readPositionalAll(io, &buffer, total) catch |err| {
            if (err == error.EndOfStream) break;
            return error.SourceUnreadable;
        };
        if (read == 0) break;
        if (signature_len < signature.len) {
            const take = @min(signature.len - signature_len, read);
            @memcpy(signature[signature_len..][0..take], buffer[0..take]);
            signature_len += take;
        }
        hasher.update(buffer[0..read]);
        total += read;
        if (total > max_document_bytes) return error.TooLarge;
        if (destination) |file| {
            file.writeStreamingAll(io, buffer[0..read]) catch
                return error.StorageUnavailable;
        }
        if (read < buffer.len) break;
    }

    if (total == 0) return error.Empty;
    if (!supportedSignature(signature[0..signature_len])) {
        return error.Unsupported;
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    var digest_text: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&digest_text, "{x}", .{&digest}) catch unreachable;
    return .{ .sha256 = digest_text, .byte_size = total };
}

fn compareFingerprint(
    actual: Fingerprint,
    expected_digest: domain.Sha256Digest,
    expected_size: u64,
) VerifyError!void {
    if (actual.byte_size != expected_size) return error.SizeChanged;
    if (!std.mem.eql(u8, &actual.sha256, expected_digest.asSlice())) {
        return error.DigestChanged;
    }
}

fn supportedSignature(signature: []const u8) bool {
    if (std.mem.startsWith(u8, signature, "%PDF-")) return true;
    if (std.mem.startsWith(u8, signature, "\x89PNG\r\n\x1a\n")) return true;
    return signature.len >= 3 and
        std.mem.startsWith(u8, signature, "\xff\xd8\xff");
}

fn mapOpenSourceError(err: std.Io.File.OpenError) InspectError {
    return switch (err) {
        error.FileNotFound => error.SourceMissing,
        else => error.SourceUnreadable,
    };
}

fn privateDirectoryPermissions() std.Io.File.Permissions {
    if (comptime std.Io.File.Permissions.has_executable_bit) {
        return @enumFromInt(0o700);
    }
    return .default_dir;
}

fn privateFilePermissions() std.Io.File.Permissions {
    if (comptime std.Io.File.Permissions.has_executable_bit) {
        return @enumFromInt(0o600);
    }
    return .default_file;
}

fn setProtectedFilePermissions(
    io: std.Io,
    evidence_dir: std.Io.Dir,
    basename: []const u8,
) !void {
    var file = try evidence_dir.openFile(io, basename, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer file.close(io);
    try file.setPermissions(io, privateFilePermissions());
}

fn fixturePath(
    buffer: []u8,
    sub_path: []const u8,
    basename: []const u8,
) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        ".zig-cache/tmp/{s}/{s}",
        .{ sub_path, basename },
    );
}

test "verification rejects uppercase SHA-256 before reading a source" {
    try std.testing.expectError(
        error.InvalidExpectedDigest,
        verify(
            std.testing.io,
            "source-must-not-be-read.pdf",
            "ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
            1,
        ),
    );
}

test "unchanged verification succeeds" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = "%PDF-1.4 unchanged evidence",
    });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = try fixturePath(&path_buffer, &tmp.sub_path, "registration.pdf");
    const fingerprint = try inspect(std.testing.io, path);
    try verify(std.testing.io, path, &fingerprint.sha256, fingerprint.byte_size);
}

test "same-size replacement fails digest verification" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const first = "%PDF-1.4 evidence alpha";
    const replacement = "%PDF-1.4 evidence bravo";
    try std.testing.expectEqual(first.len, replacement.len);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = first,
    });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = try fixturePath(&path_buffer, &tmp.sub_path, "registration.pdf");
    const fingerprint = try inspect(std.testing.io, path);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = replacement,
    });
    try std.testing.expectError(
        error.DigestChanged,
        verify(std.testing.io, path, &fingerprint.sha256, fingerprint.byte_size),
    );
}

test "size replacement and missing source fail explicitly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = "%PDF-1.4 evidence",
    });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = try fixturePath(&path_buffer, &tmp.sub_path, "registration.pdf");
    const fingerprint = try inspect(std.testing.io, path);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = "%PDF-1.4 evidence with different size",
    });
    try std.testing.expectError(
        error.SizeChanged,
        verify(std.testing.io, path, &fingerprint.sha256, fingerprint.byte_size),
    );
    try tmp.dir.deleteFile(std.testing.io, "registration.pdf");
    try std.testing.expectError(
        error.SourceMissing,
        verify(std.testing.io, path, &fingerprint.sha256, fingerprint.byte_size),
    );
}

test "protected copy rejects a ledger-incompatible destination before mutation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = "%PDF-1.4 protected evidence",
    });
    var source_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const source_path = try fixturePath(
        &source_path_buffer,
        &tmp.sub_path,
        "registration.pdf",
    );
    const fingerprint = try inspect(std.testing.io, source_path);
    var protected_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;

    try std.testing.expectError(
        error.PathTooLong,
        protect(
            std.testing.io,
            "a/" ** 1000,
            source_path,
            &fingerprint.sha256,
            fingerprint.byte_size,
            &protected_path_buffer,
        ),
    );
}

test "protected copy is digest addressed reusable private and source independent" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const original = "%PDF-1.4 protected evidence";
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = original,
    });
    var source_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const source_path = try fixturePath(
        &source_path_buffer,
        &tmp.sub_path,
        "registration.pdf",
    );
    var data_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const data_path = try fixturePath(&data_path_buffer, &tmp.sub_path, "data");
    try tmp.dir.createDir(std.testing.io, "data", .default_dir);
    const fingerprint = try inspect(std.testing.io, source_path);
    var protected_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const protected_path = try protect(
        std.testing.io,
        data_path,
        source_path,
        &fingerprint.sha256,
        fingerprint.byte_size,
        &protected_path_buffer,
    );
    try std.testing.expect(std.mem.endsWith(u8, protected_path, &fingerprint.sha256));

    var reused_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const reused_path = try protect(
        std.testing.io,
        data_path,
        source_path,
        &fingerprint.sha256,
        fingerprint.byte_size,
        &reused_path_buffer,
    );
    try std.testing.expectEqualStrings(protected_path, reused_path);

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = "%PDF-1.4 mutated source bytes",
    });
    try verify(
        std.testing.io,
        protected_path,
        &fingerprint.sha256,
        fingerprint.byte_size,
    );

    if (comptime std.Io.File.Permissions.has_executable_bit) {
        var evidence_dir_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const evidence_dir_path = try std.fmt.bufPrint(
            &evidence_dir_path_buffer,
            "{s}{c}{s}",
            .{ data_path, std.fs.path.sep, directory_name },
        );
        const dir_stat = try std.Io.Dir.cwd().statFile(
            std.testing.io,
            evidence_dir_path,
            .{},
        );
        const file_stat = try std.Io.Dir.cwd().statFile(
            std.testing.io,
            protected_path,
            .{},
        );
        try std.testing.expectEqual(
            @as(std.posix.mode_t, 0o700),
            dir_stat.permissions.toMode() & 0o777,
        );
        try std.testing.expectEqual(
            @as(std.posix.mode_t, 0o600),
            file_stat.permissions.toMode() & 0o777,
        );
    }
}

test "invalid existing digest destination fails closed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = "%PDF-1.4 selected evidence",
    });
    var source_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const source_path = try fixturePath(
        &source_path_buffer,
        &tmp.sub_path,
        "registration.pdf",
    );
    var data_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const data_path = try fixturePath(&data_path_buffer, &tmp.sub_path, "data");
    const fingerprint = try inspect(std.testing.io, source_path);

    var evidence_dir_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const evidence_dir_path = try std.fmt.bufPrint(
        &evidence_dir_path_buffer,
        "{s}{c}{s}",
        .{ data_path, std.fs.path.sep, directory_name },
    );
    try std.Io.Dir.cwd().createDirPath(std.testing.io, evidence_dir_path);
    var destination_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const destination_path = try std.fmt.bufPrint(
        &destination_path_buffer,
        "{s}{c}{s}",
        .{ evidence_dir_path, std.fs.path.sep, &fingerprint.sha256 },
    );
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = destination_path,
        .data = "%PDF-1.4 corrupt destination",
    });

    var protected_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try std.testing.expectError(
        error.InvalidDestination,
        protect(
            std.testing.io,
            data_path,
            source_path,
            &fingerprint.sha256,
            fingerprint.byte_size,
            &protected_path_buffer,
        ),
    );
}

test "protected copy rejects a symlinked evidence directory" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = "%PDF-1.4 selected evidence",
    });
    try tmp.dir.createDir(std.testing.io, "data", .default_dir);
    try tmp.dir.createDir(std.testing.io, "outside", .default_dir);

    var data_dir = try tmp.dir.openDir(std.testing.io, "data", .{ .iterate = true });
    defer data_dir.close(std.testing.io);
    data_dir.symLink(
        std.testing.io,
        "../outside",
        directory_name,
        .{ .is_directory = true },
    ) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };

    var source_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const source_path = try fixturePath(
        &source_path_buffer,
        &tmp.sub_path,
        "registration.pdf",
    );
    const fingerprint = try inspect(std.testing.io, source_path);
    var protected_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try std.testing.expectError(
        error.StorageUnavailable,
        protectInDirectory(
            std.testing.io,
            data_dir,
            source_path,
            &fingerprint.sha256,
            fingerprint.byte_size,
            &protected_path_buffer,
        ),
    );

    var outside = try tmp.dir.openDir(std.testing.io, "outside", .{});
    defer outside.close(std.testing.io);
    try std.testing.expectError(
        error.FileNotFound,
        outside.statFile(
            std.testing.io,
            &fingerprint.sha256,
            .{ .follow_symlinks = false },
        ),
    );
}

test "protected copy and verification reject a symlinked digest file" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = "%PDF-1.4 selected evidence",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside.pdf",
        .data = "%PDF-1.4 outside evidence",
    });
    try tmp.dir.createDir(std.testing.io, "data", .default_dir);
    var data_dir = try tmp.dir.openDir(std.testing.io, "data", .{ .iterate = true });
    defer data_dir.close(std.testing.io);
    try data_dir.createDir(std.testing.io, directory_name, .default_dir);

    var source_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const source_path = try fixturePath(
        &source_path_buffer,
        &tmp.sub_path,
        "registration.pdf",
    );
    const fingerprint = try inspect(std.testing.io, source_path);
    var evidence_dir = try data_dir.openDir(
        std.testing.io,
        directory_name,
        .{ .iterate = true },
    );
    evidence_dir.symLink(
        std.testing.io,
        "../../outside.pdf",
        &fingerprint.sha256,
        .{},
    ) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    evidence_dir.close(std.testing.io);

    var protected_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try std.testing.expectError(
        error.InvalidDestination,
        protectInDirectory(
            std.testing.io,
            data_dir,
            source_path,
            &fingerprint.sha256,
            fingerprint.byte_size,
            &protected_path_buffer,
        ),
    );
    try std.testing.expectError(
        error.SourceUnreadable,
        verifyProtectedInDirectory(
            std.testing.io,
            data_dir,
            &fingerprint.sha256,
            &fingerprint.sha256,
            fingerprint.byte_size,
        ),
    );

    var outside_buffer: [64]u8 = undefined;
    const outside = try tmp.dir.readFile(std.testing.io, "outside.pdf", &outside_buffer);
    try std.testing.expectEqualStrings("%PDF-1.4 outside evidence", outside);
}
