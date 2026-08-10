//! SQLite-linked test root for the shared calendar and tax-profile stores.
//!
//! Keep this separate from `core_logic_test.zig`: importing the store requires
//! a linked SQLite amalgamation and libc, while the pure core suite must remain
//! free of persistence dependencies.

const std = @import("std");
const builtin = @import("builtin");
const calendar_store = @import("calendar/store.zig");
const key_custody = @import("security/key_custody.zig");
const news_store = @import("news/store.zig");
const registration_evidence_store =
    @import("tax_profile/registration_evidence_store.zig");
const repository_opening = @import("security/repository_opening.zig");
const tax_profile_store = @import("tax_profile/store.zig");

const fixture_lock_name = ".ebirforms-fixture-lock";
const fixture_marker_name = ".ebirforms-fixture-owner";

const posix_fixture_test = if (builtin.os.tag == .windows) struct {} else @cImport({
    @cInclude("sys/stat.h");
});

fn fixtureMarker(
    state: tax_profile_store.RegistrationFixtureDirectoryState,
    claim_id: []const u8,
    buffer: []u8,
) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "component={s}\nversion={d}\nstate={s}\nclaim_nonce={s}\n",
        .{
            tax_profile_store.registration_fixture_binding.component,
            tax_profile_store.registration_fixture_binding.version,
            @tagName(state),
            claim_id,
        },
    );
}

fn createFixtureChildWithLock(parent: std.Io.Dir) !std.Io.Dir {
    try parent.createDir(
        std.testing.io,
        tax_profile_store.registration_fixture_directory_name,
        .default_dir,
    );
    var child = try parent.openDir(
        std.testing.io,
        tax_profile_store.registration_fixture_directory_name,
        .{ .iterate = true, .follow_symlinks = false },
    );
    errdefer child.close(std.testing.io);
    try child.writeFile(std.testing.io, .{
        .sub_path = fixture_lock_name,
        .data = "",
    });
    return child;
}

fn createNamedPipe(path: []const u8) !void {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const path_z = try std.testing.allocator.dupeZ(u8, path);
    defer std.testing.allocator.free(path_z);
    if (posix_fixture_test.mkfifo(path_z.ptr, 0o600) != 0) {
        return error.SkipZigTest;
    }
}

test "fixture directory lock contention fails closed then reopens" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    const first_identity = blk: {
        var first = try tax_profile_store.openRegistrationFixturePreviewDirectory(
            temporary.dir,
            std.testing.io,
        );
        defer first.close(std.testing.io);

        try std.testing.expectError(
            tax_profile_store.Error.RegistrationFixtureDirectoryUnowned,
            tax_profile_store.openRegistrationFixturePreviewDirectory(
                temporary.dir,
                std.testing.io,
            ),
        );
        break :blk first.identity;
    };

    var reopened = try tax_profile_store.openRegistrationFixturePreviewDirectory(
        temporary.dir,
        std.testing.io,
    );
    defer reopened.close(std.testing.io);
    try std.testing.expectEqual(first_identity.state, reopened.identity.state);
    try std.testing.expectEqualSlices(
        u8,
        &first_identity.claim_id,
        &reopened.identity.claim_id,
    );
}

test "fixture marker parser rejects partial oversized and uppercase markers behind a valid lock" {
    const lowercase_claim: tax_profile_store.RegistrationFixtureClaimId =
        @splat('0');
    const uppercase_claim: tax_profile_store.RegistrationFixtureClaimId =
        @splat('A');
    var valid_buffer: [256]u8 = undefined;
    const valid_marker = try fixtureMarker(.claiming, &lowercase_claim, &valid_buffer);
    var uppercase_buffer: [256]u8 = undefined;
    const uppercase_marker = try fixtureMarker(
        .claiming,
        &uppercase_claim,
        &uppercase_buffer,
    );
    var oversized_buffer: [320]u8 = undefined;
    const oversized_marker = try std.fmt.bufPrint(
        &oversized_buffer,
        "{s}unexpected=true\n",
        .{valid_marker},
    );
    const invalid_markers = [_][]const u8{
        "component=tin-branch-fixture-preview\nversion=2\nstate=claiming\n",
        oversized_marker,
        uppercase_marker,
    };

    for (invalid_markers) |invalid_marker| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        {
            var child = try createFixtureChildWithLock(temporary.dir);
            defer child.close(std.testing.io);
            try child.writeFile(std.testing.io, .{
                .sub_path = fixture_marker_name,
                .data = invalid_marker,
            });
        }

        try std.testing.expectError(
            tax_profile_store.Error.RegistrationFixtureDirectoryUnowned,
            tax_profile_store.openRegistrationFixturePreviewDirectory(
                temporary.dir,
                std.testing.io,
            ),
        );
    }
}

test "fixture lock rejects nonempty directory hard-link symlink and FIFO entries" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const EntryShape = enum { nonempty, directory, hard_link, symlink, fifo };
    const claim: tax_profile_store.RegistrationFixtureClaimId = @splat('1');
    var marker_buffer: [256]u8 = undefined;
    const marker = try fixtureMarker(.claiming, &claim, &marker_buffer);

    inline for ([_]EntryShape{
        .nonempty,
        .directory,
        .hard_link,
        .symlink,
        .fifo,
    }) |shape| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        try temporary.dir.createDir(
            std.testing.io,
            tax_profile_store.registration_fixture_directory_name,
            .default_dir,
        );
        var child = try temporary.dir.openDir(
            std.testing.io,
            tax_profile_store.registration_fixture_directory_name,
            .{ .iterate = true, .follow_symlinks = false },
        );
        defer child.close(std.testing.io);
        try child.writeFile(std.testing.io, .{
            .sub_path = fixture_marker_name,
            .data = marker,
        });

        switch (shape) {
            .nonempty => try child.writeFile(std.testing.io, .{
                .sub_path = fixture_lock_name,
                .data = "not empty",
            }),
            .directory => try child.createDir(
                std.testing.io,
                fixture_lock_name,
                .default_dir,
            ),
            .hard_link => {
                try temporary.dir.writeFile(std.testing.io, .{
                    .sub_path = "external-fixture-lock",
                    .data = "",
                });
                try temporary.dir.hardLink(
                    "external-fixture-lock",
                    child,
                    fixture_lock_name,
                    std.testing.io,
                    .{},
                );
            },
            .symlink => try child.symLink(
                std.testing.io,
                "../external-fixture-lock",
                fixture_lock_name,
                .{},
            ),
            .fifo => {
                var child_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
                const child_path_len = try child.realPath(
                    std.testing.io,
                    &child_path_buffer,
                );
                var fifo_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
                const fifo_path = try std.fmt.bufPrint(
                    &fifo_path_buffer,
                    "{s}{c}{s}",
                    .{
                        child_path_buffer[0..child_path_len],
                        std.fs.path.sep,
                        fixture_lock_name,
                    },
                );
                try createNamedPipe(fifo_path);
            },
        }
        try std.testing.expectError(
            tax_profile_store.Error.RegistrationFixtureDirectoryUnowned,
            tax_profile_store.openRegistrationFixturePreviewDirectory(
                temporary.dir,
                std.testing.io,
            ),
        );
    }
}

test "fixture marker rejects directory hard-link symlink and FIFO entries" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const EntryShape = enum { directory, hard_link, symlink, fifo };
    const claim: tax_profile_store.RegistrationFixtureClaimId = @splat('2');
    var marker_buffer: [256]u8 = undefined;
    const marker = try fixtureMarker(.claiming, &claim, &marker_buffer);

    inline for ([_]EntryShape{ .directory, .hard_link, .symlink, .fifo }) |shape| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var child = try createFixtureChildWithLock(temporary.dir);
        defer child.close(std.testing.io);

        switch (shape) {
            .directory => try child.createDir(
                std.testing.io,
                fixture_marker_name,
                .default_dir,
            ),
            .hard_link => {
                try temporary.dir.writeFile(std.testing.io, .{
                    .sub_path = "external-fixture-marker",
                    .data = marker,
                });
                try temporary.dir.hardLink(
                    "external-fixture-marker",
                    child,
                    fixture_marker_name,
                    std.testing.io,
                    .{},
                );
            },
            .symlink => {
                try temporary.dir.writeFile(std.testing.io, .{
                    .sub_path = "external-fixture-marker",
                    .data = marker,
                });
                try child.symLink(
                    std.testing.io,
                    "../external-fixture-marker",
                    fixture_marker_name,
                    .{},
                );
            },
            .fifo => {
                var child_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
                const child_path_len = try child.realPath(
                    std.testing.io,
                    &child_path_buffer,
                );
                var fifo_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
                const fifo_path = try std.fmt.bufPrint(
                    &fifo_path_buffer,
                    "{s}{c}{s}",
                    .{
                        child_path_buffer[0..child_path_len],
                        std.fs.path.sep,
                        fixture_marker_name,
                    },
                );
                try createNamedPipe(fifo_path);
            },
        }
        try std.testing.expectError(
            tax_profile_store.Error.RegistrationFixtureDirectoryUnowned,
            tax_profile_store.openRegistrationFixturePreviewDirectory(
                temporary.dir,
                std.testing.io,
            ),
        );
    }
}

test "fixture claiming crash resumes same nonce and publishes ready" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const capability =
        key_custody.bootstrapCurrentArtifactStorage().development_plaintext;
    var database_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var database_path_len: usize = undefined;

    const claiming_identity = blk: {
        var fixture = try tax_profile_store.openRegistrationFixturePreviewDirectory(
            temporary.dir,
            std.testing.io,
        );
        defer fixture.close(std.testing.io);
        var fixture_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const fixture_path_len = try fixture.realPath(
            std.testing.io,
            &fixture_path_buffer,
        );
        const database_path = try std.fmt.bufPrint(
            &database_path_buffer,
            "{s}{c}calendar.sqlite3",
            .{ fixture_path_buffer[0..fixture_path_len], std.fs.path.sep },
        );
        database_path_len = database_path.len;
        try std.testing.expectEqual(
            tax_profile_store.RegistrationFixtureOwnershipResult
                .claimed_empty_ledger,
            try tax_profile_store.Store
                .testingEstablishRegistrationFixturePreviewDatabaseOwnership(
                capability,
                std.testing.allocator,
                database_path,
                fixture.databaseOrigin(),
            ),
        );
        break :blk fixture.identity;
    };

    const ready_identity = blk: {
        var resumed = try tax_profile_store.openRegistrationFixturePreviewDirectory(
            temporary.dir,
            std.testing.io,
        );
        defer resumed.close(std.testing.io);
        try std.testing.expectEqual(
            tax_profile_store.RegistrationFixtureDirectoryState.claiming,
            resumed.identity.state,
        );
        try std.testing.expectEqualSlices(
            u8,
            &claiming_identity.claim_id,
            &resumed.identity.claim_id,
        );
        try std.testing.expectEqual(
            tax_profile_store.RegistrationFixtureOwnershipResult.already_claimed,
            try tax_profile_store.Store
                .testingEstablishRegistrationFixturePreviewDatabaseOwnership(
                capability,
                std.testing.allocator,
                database_path_buffer[0..database_path_len],
                resumed.databaseOrigin(),
            ),
        );
        try resumed.publishReady(std.testing.io);
        break :blk resumed.identity;
    };

    var reopened = try tax_profile_store.Store.testingOpenFixturePreviewDevelopmentPlaintext(
        capability,
        std.testing.allocator,
        database_path_buffer[0..database_path_len],
        ready_identity,
    );
    defer reopened.close();
    try std.testing.expect(try reopened.registrationFixturePreviewOwnershipPresent());
}

test "ready fixture never creates a missing database" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const capability =
        key_custody.bootstrapCurrentArtifactStorage().development_plaintext;
    var database_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var database_path_len: usize = undefined;

    const ready_identity = blk: {
        var fixture = try tax_profile_store.openRegistrationFixturePreviewDirectory(
            temporary.dir,
            std.testing.io,
        );
        defer fixture.close(std.testing.io);
        var fixture_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const fixture_path_len = try fixture.realPath(
            std.testing.io,
            &fixture_path_buffer,
        );
        const database_path = try std.fmt.bufPrint(
            &database_path_buffer,
            "{s}{c}missing.sqlite3",
            .{ fixture_path_buffer[0..fixture_path_len], std.fs.path.sep },
        );
        database_path_len = database_path.len;
        try fixture.publishReady(std.testing.io);
        break :blk fixture.identity;
    };

    try std.testing.expectError(
        tax_profile_store.Error.SqliteFailure,
        tax_profile_store.Store.testingOpenFixturePreviewDevelopmentPlaintext(
            capability,
            std.testing.allocator,
            database_path_buffer[0..database_path_len],
            ready_identity,
        ),
    );
    var fixture = try temporary.dir.openDir(
        std.testing.io,
        tax_profile_store.registration_fixture_directory_name,
        .{},
    );
    defer fixture.close(std.testing.io);
    try std.testing.expectError(
        error.FileNotFound,
        fixture.statFile(
            std.testing.io,
            "missing.sqlite3",
            .{ .follow_symlinks = false },
        ),
    );
}

test "fixture database ownership rejects claiming and ready nonce mismatch" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const capability =
        key_custody.bootstrapCurrentArtifactStorage().development_plaintext;
    var database_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var database_path_len: usize = undefined;

    {
        var fixture = try tax_profile_store.openRegistrationFixturePreviewDirectory(
            temporary.dir,
            std.testing.io,
        );
        defer fixture.close(std.testing.io);
        var fixture_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const fixture_path_len = try fixture.realPath(
            std.testing.io,
            &fixture_path_buffer,
        );
        const database_path = try std.fmt.bufPrint(
            &database_path_buffer,
            "{s}{c}calendar.sqlite3",
            .{ fixture_path_buffer[0..fixture_path_len], std.fs.path.sep },
        );
        database_path_len = database_path.len;
        try std.testing.expectEqual(
            tax_profile_store.RegistrationFixtureOwnershipResult
                .claimed_empty_ledger,
            try tax_profile_store.Store
                .testingEstablishRegistrationFixturePreviewDatabaseOwnership(
                capability,
                std.testing.allocator,
                database_path,
                fixture.databaseOrigin(),
            ),
        );
    }

    const replacement_claim: tax_profile_store.RegistrationFixtureClaimId =
        @splat('b');
    var claiming_marker_buffer: [256]u8 = undefined;
    const claiming_marker = try fixtureMarker(
        .claiming,
        &replacement_claim,
        &claiming_marker_buffer,
    );
    {
        var fixture = try temporary.dir.openDir(
            std.testing.io,
            tax_profile_store.registration_fixture_directory_name,
            .{},
        );
        defer fixture.close(std.testing.io);
        try fixture.writeFile(std.testing.io, .{
            .sub_path = fixture_marker_name,
            .data = claiming_marker,
        });
    }
    {
        var mismatched =
            try tax_profile_store.openRegistrationFixturePreviewDirectory(
                temporary.dir,
                std.testing.io,
            );
        defer mismatched.close(std.testing.io);
        try std.testing.expectEqual(
            tax_profile_store.RegistrationFixtureOwnershipResult
                .unowned_existing_database,
            try tax_profile_store.Store
                .testingEstablishRegistrationFixturePreviewDatabaseOwnership(
                capability,
                std.testing.allocator,
                database_path_buffer[0..database_path_len],
                mismatched.databaseOrigin(),
            ),
        );
    }

    var ready_marker_buffer: [256]u8 = undefined;
    const ready_marker = try fixtureMarker(
        .ready,
        &replacement_claim,
        &ready_marker_buffer,
    );
    {
        var fixture = try temporary.dir.openDir(
            std.testing.io,
            tax_profile_store.registration_fixture_directory_name,
            .{},
        );
        defer fixture.close(std.testing.io);
        try fixture.writeFile(std.testing.io, .{
            .sub_path = fixture_marker_name,
            .data = ready_marker,
        });
    }
    try std.testing.expectError(
        tax_profile_store.Error.RegistrationFixtureDirectoryUnowned,
        tax_profile_store.Store.testingOpenFixturePreviewDevelopmentPlaintext(
            capability,
            std.testing.allocator,
            database_path_buffer[0..database_path_len],
            .{ .state = .ready, .claim_id = replacement_claim },
        ),
    );
}

test "profile calendar and news databases reject final-component symlinks" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const capability =
        key_custody.bootstrapCurrentArtifactStorage().development_plaintext;
    var directory_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const directory_path_len = try temporary.dir.realPath(
        std.testing.io,
        &directory_path_buffer,
    );
    const directory_path = directory_path_buffer[0..directory_path_len];

    var profile_real_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const profile_real = try std.fmt.bufPrint(
        &profile_real_buffer,
        "{s}{c}profile-real.sqlite3",
        .{ directory_path, std.fs.path.sep },
    );
    {
        var real = try tax_profile_store.Store.openDevelopmentPlaintext(
            capability,
            std.testing.allocator,
            profile_real,
        );
        real.close();
    }
    try temporary.dir.symLink(
        std.testing.io,
        "profile-real.sqlite3",
        "profile-link.sqlite3",
        .{},
    );
    var profile_link_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const profile_link = try std.fmt.bufPrint(
        &profile_link_buffer,
        "{s}{c}profile-link.sqlite3",
        .{ directory_path, std.fs.path.sep },
    );
    try std.testing.expectError(
        tax_profile_store.Error.SqliteFailure,
        tax_profile_store.Store.openDevelopmentPlaintext(
            capability,
            std.testing.allocator,
            profile_link,
        ),
    );

    var calendar_real_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const calendar_real = try std.fmt.bufPrint(
        &calendar_real_buffer,
        "{s}{c}calendar-real.sqlite3",
        .{ directory_path, std.fs.path.sep },
    );
    {
        var real = try calendar_store.Store.openDevelopmentPlaintext(
            capability,
            std.testing.allocator,
            calendar_real,
        );
        real.close();
    }
    try temporary.dir.symLink(
        std.testing.io,
        "calendar-real.sqlite3",
        "calendar-link.sqlite3",
        .{},
    );
    var calendar_link_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const calendar_link = try std.fmt.bufPrint(
        &calendar_link_buffer,
        "{s}{c}calendar-link.sqlite3",
        .{ directory_path, std.fs.path.sep },
    );
    try std.testing.expectError(
        calendar_store.Error.SqliteFailure,
        calendar_store.Store.openDevelopmentPlaintext(
            capability,
            std.testing.allocator,
            calendar_link,
        ),
    );

    var news_real_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const news_real = try std.fmt.bufPrint(
        &news_real_buffer,
        "{s}{c}news-real.sqlite3",
        .{ directory_path, std.fs.path.sep },
    );
    {
        var real = try news_store.Store.openFile(
            std.testing.allocator,
            news_real,
        );
        real.close();
    }
    try temporary.dir.symLink(
        std.testing.io,
        "news-real.sqlite3",
        "news-link.sqlite3",
        .{},
    );
    var news_link_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const news_link = try std.fmt.bufPrint(
        &news_link_buffer,
        "{s}{c}news-link.sqlite3",
        .{ directory_path, std.fs.path.sep },
    );
    try std.testing.expectError(
        news_store.Error.SqliteFailure,
        news_store.Store.openFile(std.testing.allocator, news_link),
    );
}

test "fixture child replacement is rejected by retained directory identity" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var fixture = try tax_profile_store.openRegistrationFixturePreviewDirectory(
        temporary.dir,
        std.testing.io,
    );
    defer fixture.close(std.testing.io);

    try temporary.dir.rename(
        tax_profile_store.registration_fixture_directory_name,
        temporary.dir,
        "detached-fixture-child",
        std.testing.io,
    );
    try temporary.dir.createDir(
        std.testing.io,
        tax_profile_store.registration_fixture_directory_name,
        .default_dir,
    );
    try std.testing.expectError(
        tax_profile_store.Error.RegistrationFixtureDirectoryUnowned,
        fixture.verifyMounted(std.testing.io),
    );
}

test "retained fixture parent capability does not redirect after path replacement" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(
        std.testing.io,
        "fixture-parent",
        .default_dir,
    );
    var retained_parent = try temporary.dir.openDir(
        std.testing.io,
        "fixture-parent",
        .{ .iterate = true },
    );
    defer retained_parent.close(std.testing.io);
    var fixture = try tax_profile_store.openRegistrationFixturePreviewDirectory(
        retained_parent,
        std.testing.io,
    );
    defer fixture.close(std.testing.io);

    try temporary.dir.rename(
        "fixture-parent",
        temporary.dir,
        "detached-fixture-parent",
        std.testing.io,
    );
    try temporary.dir.createDir(
        std.testing.io,
        "fixture-parent",
        .default_dir,
    );
    var replacement_parent = try temporary.dir.openDir(
        std.testing.io,
        "fixture-parent",
        .{},
    );
    defer replacement_parent.close(std.testing.io);
    try replacement_parent.createDir(
        std.testing.io,
        tax_profile_store.registration_fixture_directory_name,
        .default_dir,
    );

    var retained_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const retained_path_len = try fixture.realPath(
        std.testing.io,
        &retained_path_buffer,
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        retained_path_buffer[0..retained_path_len],
        "detached-fixture-parent",
    ) != null);
}

test "registration evidence stays inside claimed fixture child" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "registration.pdf",
        .data = "%PDF-1.4 fixture evidence containment",
    });
    var source_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const temporary_path_len = try temporary.dir.realPath(
        std.testing.io,
        &source_path_buffer,
    );
    const source_path = try std.fmt.bufPrint(
        source_path_buffer[temporary_path_len..],
        "{c}registration.pdf",
        .{std.fs.path.sep},
    );
    const full_source_path =
        source_path_buffer[0 .. temporary_path_len + source_path.len];
    const fingerprint = try registration_evidence_store.inspect(
        std.testing.io,
        full_source_path,
    );

    var fixture = try tax_profile_store.openRegistrationFixturePreviewDirectory(
        temporary.dir,
        std.testing.io,
    );
    defer fixture.close(std.testing.io);
    var fixture_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const fixture_path_len = try fixture.realPath(
        std.testing.io,
        &fixture_path_buffer,
    );
    var protected_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const protected_path = try registration_evidence_store.protectInDirectory(
        std.testing.io,
        fixture.dir,
        full_source_path,
        &fingerprint.sha256,
        fingerprint.byte_size,
        &protected_path_buffer,
    );
    var expected_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const expected_path = try std.fmt.bufPrint(
        &expected_path_buffer,
        "{s}{c}{s}{c}{s}",
        .{
            fixture_path_buffer[0..fixture_path_len],
            std.fs.path.sep,
            registration_evidence_store.directory_name,
            std.fs.path.sep,
            &fingerprint.sha256,
        },
    );
    try std.testing.expectEqualStrings(expected_path, protected_path);
    try registration_evidence_store.verifyProtectedInDirectory(
        std.testing.io,
        fixture.dir,
        protected_path,
        &fingerprint.sha256,
        fingerprint.byte_size,
    );
    try std.testing.expectError(
        error.FileNotFound,
        temporary.dir.statFile(
            std.testing.io,
            registration_evidence_store.directory_name,
            .{ .follow_symlinks = false },
        ),
    );
}

test "registration migration inventory module compiles in SQLite-linked root" {
    _ = @import("tax_profile/registration_migration_inventory.zig");
}

test "registration ledger module compiles in SQLite-linked root" {
    _ = @import("tax_profile/registration_ledger.zig");
}

test "registration workspace module compiles in SQLite-linked root" {
    _ = @import("tax_profile/registration_workspace.zig");
}

test "shared plaintext development stores remain in their SQLite-linked root" {
    try std.testing.expectEqual(
        repository_opening
            .LegacyPlaintextRepositoryClassification
            .development_only_plaintext_not_production,
        calendar_store.storage_classification,
    );
    try std.testing.expectEqual(
        calendar_store.storage_classification,
        tax_profile_store.storage_classification,
    );
    try std.testing.expectEqual(
        repository_opening
            .ProductionRepositoryIntegrationState
            .unavailable_development_plaintext_artifact_only,
        calendar_store.production_repository_integration_state,
    );
    try std.testing.expectEqual(
        calendar_store.production_repository_integration_state,
        tax_profile_store.production_repository_integration_state,
    );
    try std.testing.expectEqual(
        repository_opening.ProductionRepositoryScope
            .shared_calendar_tax_profile_database,
        calendar_store.production_repository_scope,
    );
    try std.testing.expectEqual(
        calendar_store.production_repository_scope,
        tax_profile_store.production_repository_scope,
    );
}

test "file-backed plaintext stores require source-minted development authority" {
    try std.testing.expect(!@hasDecl(calendar_store.Store, "open"));
    try std.testing.expect(!@hasDecl(tax_profile_store.Store, "open"));

    const calendar_open = @typeInfo(
        @TypeOf(calendar_store.Store.openDevelopmentPlaintext),
    ).@"fn";
    const profile_open = @typeInfo(
        @TypeOf(tax_profile_store.Store.openDevelopmentPlaintext),
    ).@"fn";
    try std.testing.expectEqual(@as(usize, 3), calendar_open.params.len);
    try std.testing.expectEqual(@as(usize, 3), profile_open.params.len);
    try std.testing.expect(
        calendar_open.params[0].type.? ==
            *const key_custody.DevelopmentPlaintextStorageCapability,
    );
    try std.testing.expect(
        profile_open.params[0].type.? ==
            *const key_custody.DevelopmentPlaintextStorageCapability,
    );

    var forged_token: u8 = 0;
    const forged: *const key_custody.DevelopmentPlaintextStorageCapability =
        @ptrCast(&forged_token);
    try std.testing.expectError(
        error.InvalidDevelopmentPlaintextStorageCapability,
        calendar_store.Store.openDevelopmentPlaintext(
            forged,
            std.testing.allocator,
            "forged-calendar-plaintext-authority.sqlite3",
        ),
    );
    try std.testing.expectError(
        error.InvalidDevelopmentPlaintextStorageCapability,
        tax_profile_store.Store.openDevelopmentPlaintext(
            forged,
            std.testing.allocator,
            "forged-tax-profile-plaintext-authority.sqlite3",
        ),
    );
}

test "v28 registration evidence digest is lowercase canonical under direct SQL" {
    var store = try tax_profile_store.Store.openMemory(std.testing.allocator);
    defer store.close();

    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_evidence (
            \\  id, source_kind, sha256, display_name, byte_size, captured_on,
            \\  storage_reference_kind, storage_reference
            \\) VALUES (
            \\  'uppercase-digest-evidence', 'cor',
            \\  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            \\  'Uppercase digest must fail', 0, '2026-01-01',
            \\  'protected_local_path', '/protected/test/uppercase-digest.pdf'
            \\);
        ),
    );
}

test "v28 registration civil dates are canonical under direct SQL" {
    var store = try tax_profile_store.Store.openMemory(std.testing.allocator);
    defer store.close();

    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_evidence (
            \\  id, source_kind, sha256, display_name, byte_size, captured_on,
            \\  storage_reference_kind, storage_reference
            \\) VALUES (
            \\  'invalid-capture-date', 'cor',
            \\  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
            \\  'Impossible capture date', 0, '2026-02-30',
            \\  'protected_local_path', '/protected/test/invalid-date.pdf'
            \\);
        ),
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_taxpayers (id)
        \\VALUES ('invalid-date-taxpayer');
    );
    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_taxpayer_revisions (
            \\  id, taxpayer_id, sequence, effective_from, tin9
            \\) VALUES (
            \\  'year-zero-revision', 'invalid-date-taxpayer', 1,
            \\  '0000-01-01', '123456789'
            \\);
        ),
    );
    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_taxpayer_revisions (
            \\  id, taxpayer_id, sequence, effective_from, effective_until,
            \\  tin9
            \\) VALUES (
            \\  'invalid-until-revision', 'invalid-date-taxpayer', 1,
            \\  '2026-01-01', '2026-02-30', '123456789'
            \\);
        ),
    );
}

test "v28 taxpayer root correction is append-only reviewed and collision safe" {
    var store = try tax_profile_store.Store.openMemory(std.testing.allocator);
    defer store.close();

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_taxpayers (id) VALUES
        \\  ('root-taxpayer-a'), ('root-taxpayer-b');
        \\INSERT INTO taxpayer_registration_taxpayer_revisions (
        \\  id, taxpayer_id, sequence, effective_from, tin9
        \\) VALUES
        \\  ('root-a-revision-1', 'root-taxpayer-a', 1, '2026-01-01', '123456789'),
        \\  ('root-b-revision-1', 'root-taxpayer-b', 1, '2026-01-01', '987654321');
        \\INSERT INTO taxpayer_registration_evidence (
        \\  id, source_kind, sha256, display_name, byte_size, captured_on,
        \\  storage_reference_kind, storage_reference
        \\) VALUES
        \\  ('root-evidence-a', 'cor',
        \\   '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        \\   'A corrected COR', 0, '2026-02-01',
        \\   'protected_local_path', '/protected/test/root-a-cor.pdf'),
        \\  ('root-evidence-b', 'cor',
        \\   'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        \\   'B corrected COR', 0, '2026-02-01',
        \\   'protected_local_path', '/protected/test/root-b-cor.pdf');
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\  id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\  fact_kind, tin9
        \\) VALUES
        \\  ('root-assertion-a', 'root-evidence-a', 'root-taxpayer-a', NULL,
        \\   '2026-02-01', 'taxpayer_tin_root', '111111111'),
        \\  ('root-assertion-b', 'root-evidence-b', 'root-taxpayer-b', NULL,
        \\   '2026-02-01', 'taxpayer_tin_root', '111111111');
        \\INSERT INTO taxpayer_registration_evidence_review_decisions (
        \\  id, evidence_id, sequence, review_state,
        \\  reviewer_kind, reviewer_local_owner_id, reviewer_service_actor_id,
        \\  reviewed_at, review_reason
        \\) VALUES
        \\  ('root-review-a', 'root-evidence-a', 1, 'accepted',
        \\   'service', NULL, 'root-test-reviewer', 1, 'Correction A accepted'),
        \\  ('root-review-b', 'root-evidence-b', 1, 'accepted',
        \\   'service', NULL, 'root-test-reviewer', 1, 'Correction B accepted');
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_taxpayer_revisions (
        \\  id, taxpayer_id, sequence, effective_from, tin9, evidence_id
        \\) VALUES (
        \\  'root-a-revision-2', 'root-taxpayer-a', 2, '2026-02-01',
        \\  '111111111', 'root-evidence-a'
        \\);
    );

    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_taxpayer_revisions (
            \\  id, taxpayer_id, sequence, effective_from, tin9, evidence_id
            \\) VALUES (
            \\  'root-a-stale-revision', 'root-taxpayer-a', 2, '2026-03-01',
            \\  '222222222', 'root-evidence-a'
            \\);
        ),
    );
    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_taxpayer_revisions (
            \\  id, taxpayer_id, sequence, effective_from, tin9, evidence_id
            \\) VALUES (
            \\  'root-b-revision-2', 'root-taxpayer-b', 2, '2026-02-01',
            \\  '111111111', 'root-evidence-b'
            \\);
        ),
    );
}

test "v28 TIN roots are unique only across overlapping effective intervals" {
    var store = try tax_profile_store.Store.openMemory(std.testing.allocator);
    defer store.close();

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_taxpayers (id) VALUES
        \\  ('effective-root-taxpayer-a'), ('effective-root-taxpayer-b');
        \\INSERT INTO taxpayer_registration_taxpayer_revisions (
        \\  id, taxpayer_id, sequence, effective_from, tin9
        \\) VALUES (
        \\  'effective-root-a-revision-1', 'effective-root-taxpayer-a', 1,
        \\  '2026-01-01', '123456789'
        \\);
    );

    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_taxpayer_revisions (
            \\  id, taxpayer_id, sequence, effective_from, tin9
            \\) VALUES (
            \\  'effective-root-b-overlap', 'effective-root-taxpayer-b', 1,
            \\  '2026-01-15', '123456789'
            \\);
        ),
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_evidence (
        \\  id, source_kind, sha256, display_name, byte_size, captured_on,
        \\  storage_reference_kind, storage_reference
        \\) VALUES (
        \\  'effective-root-correction-evidence', 'cor',
        \\  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        \\  'Effective root correction', 0, '2026-02-01',
        \\  'protected_local_path', '/protected/test/effective-root-cor.pdf'
        \\);
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\  id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\  fact_kind, tin9
        \\) VALUES (
        \\  'effective-root-correction-assertion',
        \\  'effective-root-correction-evidence', 'effective-root-taxpayer-a',
        \\  NULL, '2026-02-01', 'taxpayer_tin_root', '987654321'
        \\);
        \\INSERT INTO taxpayer_registration_evidence_review_decisions (
        \\  id, evidence_id, sequence, review_state,
        \\  reviewer_kind, reviewer_local_owner_id, reviewer_service_actor_id,
        \\  reviewed_at, review_reason
        \\) VALUES (
        \\  'effective-root-correction-review',
        \\  'effective-root-correction-evidence', 1, 'accepted',
        \\  'service', NULL, 'effective-root-reviewer', 1,
        \\  'Corrected root accepted'
        \\);
        \\INSERT INTO taxpayer_registration_taxpayer_revisions (
        \\  id, taxpayer_id, sequence, effective_from, tin9, evidence_id
        \\) VALUES (
        \\  'effective-root-a-revision-2', 'effective-root-taxpayer-a', 2,
        \\  '2026-02-01', '987654321', 'effective-root-correction-evidence'
        \\);
        \\INSERT INTO taxpayer_registration_taxpayer_revisions (
        \\  id, taxpayer_id, sequence, effective_from, tin9
        \\) VALUES (
        \\  'effective-root-b-revision-1', 'effective-root-taxpayer-b', 1,
        \\  '2026-02-01', '123456789'
        \\);
    );
}

test "v28 rejects branch-code lineage that does not exactly match its confirmed revision" {
    var store = try tax_profile_store.Store.openMemory(std.testing.allocator);
    defer store.close();

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_taxpayers (id) VALUES
        \\  ('lineage-taxpayer-a'), ('lineage-taxpayer-b');
    );
    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_evidence (
        \\  id, source_kind, sha256, display_name, byte_size, captured_on,
        \\  storage_reference_kind, storage_reference
        \\) VALUES
        \\  ('lineage-evidence-a1', 'cor',
        \\   '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        \\   'A1 COR', 0, '2026-01-01',
        \\   'protected_local_path', '/protected/test/lineage-a1-cor.pdf'),
        \\  ('lineage-evidence-a2', 'cor',
        \\   'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        \\   'A2 COR', 0, '2026-01-01',
        \\   'protected_local_path', '/protected/test/lineage-a2-cor.pdf'),
        \\  ('lineage-evidence-b', 'cor',
        \\   '1111111111111111111111111111111111111111111111111111111111111111',
        \\   'B COR', 0, '2026-01-01',
        \\   'protected_local_path', '/protected/test/lineage-b-cor.pdf');
    );
    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_units (id, taxpayer_id) VALUES
        \\  ('lineage-unit-a1', 'lineage-taxpayer-a'),
        \\  ('lineage-unit-a2', 'lineage-taxpayer-a'),
        \\  ('lineage-unit-b', 'lineage-taxpayer-b');
    );
    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\  id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\  fact_kind, branch_code, registration_unit_status
        \\) VALUES
        \\  ('lineage-assertion-a1', 'lineage-evidence-a1', 'lineage-taxpayer-a',
        \\   'lineage-unit-a1', '2026-01-01', 'registration_unit', '00001',
        \\   'confirmed_active'),
        \\  ('lineage-assertion-a2', 'lineage-evidence-a2', 'lineage-taxpayer-a',
        \\   'lineage-unit-a2', '2026-01-01', 'registration_unit', '00002',
        \\   'confirmed_active'),
        \\  ('lineage-assertion-b', 'lineage-evidence-b', 'lineage-taxpayer-b',
        \\   'lineage-unit-b', '2026-01-01', 'registration_unit', '00003',
        \\   'confirmed_active');
    );
    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_evidence_review_decisions (
        \\  id, evidence_id, sequence, review_state,
        \\  reviewer_kind, reviewer_local_owner_id, reviewer_service_actor_id,
        \\  reviewed_at, review_reason
        \\) VALUES
        \\  ('lineage-review-a1', 'lineage-evidence-a1', 1, 'accepted',
        \\   'service', NULL, 'lineage-test-reviewer', 1, 'A1 COR accepted'),
        \\  ('lineage-review-a2', 'lineage-evidence-a2', 1, 'accepted',
        \\   'service', NULL, 'lineage-test-reviewer', 1, 'A2 COR accepted'),
        \\  ('lineage-review-b', 'lineage-evidence-b', 1, 'accepted',
        \\   'service', NULL, 'lineage-test-reviewer', 1, 'B COR accepted');
    );
    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_unit_revisions (
        \\  id, taxpayer_id, registration_unit_id, sequence, effective_from,
        \\  effective_until, kind, branch_code_state, branch_code, legacy_suffix, status,
        \\  branch_code_evidence_id, lifecycle_evidence_id
        \\) VALUES
        \\  ('lineage-revision-a1', 'lineage-taxpayer-a', 'lineage-unit-a1',
        \\   1, '2026-01-01', '2026-01-31', 'branch', 'confirmed', '00001', NULL,
        \\   'confirmed_active', 'lineage-evidence-a1', 'lineage-evidence-a1'),
        \\  ('lineage-revision-a2', 'lineage-taxpayer-a', 'lineage-unit-a2',
        \\   1, '2026-01-01', NULL, 'branch', 'confirmed', '00002', NULL,
        \\   'confirmed_active', 'lineage-evidence-a2', 'lineage-evidence-a2'),
        \\  ('lineage-revision-b', 'lineage-taxpayer-b', 'lineage-unit-b',
        \\   1, '2026-01-01', NULL, 'branch', 'confirmed', '00003', NULL,
        \\   'confirmed_active', 'lineage-evidence-b', 'lineage-evidence-b');
    );

    // Direct SQL and future migration code cannot commit a confirmed unit
    // revision without its permanent branch-code lineage being materialized.
    try std.testing.expectEqual(
        @as(i64, 3),
        try tax_profile_store.testing.scalarIntConstraintFixture(&store,
            \\SELECT COUNT(*)
            \\FROM taxpayer_registration_branch_code_lineage;
        ),
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_evidence (
        \\  id, source_kind, sha256, display_name, byte_size, captured_on,
        \\  storage_reference_kind, storage_reference
        \\) VALUES (
        \\  'lineage-evidence-a3', 'cor',
        \\  '2222222222222222222222222222222222222222222222222222222222222222',
        \\  'A3 COR', 0, '2026-02-01',
        \\  'protected_local_path', '/protected/test/lineage-a3-cor.pdf'
        \\);
        \\INSERT INTO taxpayer_registration_units (id, taxpayer_id)
        \\VALUES ('lineage-unit-a3', 'lineage-taxpayer-a');
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\  id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\  fact_kind, branch_code, registration_unit_status
        \\) VALUES (
        \\  'lineage-assertion-a3', 'lineage-evidence-a3',
        \\  'lineage-taxpayer-a', 'lineage-unit-a3', '2026-02-01',
        \\  'registration_unit', '00001', 'confirmed_active'
        \\);
        \\INSERT INTO taxpayer_registration_evidence_review_decisions (
        \\  id, evidence_id, sequence, review_state, reviewer_kind,
        \\  reviewer_local_owner_id, reviewer_service_actor_id,
        \\  reviewed_at, review_reason
        \\) VALUES (
        \\  'lineage-review-a3', 'lineage-evidence-a3', 1, 'accepted',
        \\  'service', NULL, 'lineage-test-reviewer', 2,
        \\  'A3 COR accepted'
        \\);
    );
    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_unit_revisions (
            \\  id, taxpayer_id, registration_unit_id, sequence, effective_from,
            \\  kind, branch_code_state, branch_code, legacy_suffix, status,
            \\  branch_code_evidence_id, lifecycle_evidence_id
            \\) VALUES (
            \\  'lineage-revision-a3', 'lineage-taxpayer-a', 'lineage-unit-a3',
            \\  1, '2026-02-01', 'branch', 'confirmed', '00001', NULL,
            \\  'confirmed_active', 'lineage-evidence-a3', 'lineage-evidence-a3'
            \\);
        ),
    );

    for ([_][:0]const u8{
        \\INSERT INTO taxpayer_registration_branch_code_lineage (
        \\  taxpayer_id, branch_code, registration_unit_id, evidence_id, unit_revision_id
        \\) VALUES (
        \\  'lineage-taxpayer-a', '00003', 'lineage-unit-b',
        \\  'lineage-evidence-b', 'lineage-revision-b'
        \\);
        ,
        \\INSERT INTO taxpayer_registration_branch_code_lineage (
        \\  taxpayer_id, branch_code, registration_unit_id, evidence_id, unit_revision_id
        \\) VALUES (
        \\  'lineage-taxpayer-a', '00001', 'lineage-unit-a2',
        \\  'lineage-evidence-a1', 'lineage-revision-a1'
        \\);
        ,
        \\INSERT INTO taxpayer_registration_branch_code_lineage (
        \\  taxpayer_id, branch_code, registration_unit_id, evidence_id, unit_revision_id
        \\) VALUES (
        \\  'lineage-taxpayer-a', '00004', 'lineage-unit-a1',
        \\  'lineage-evidence-a1', 'lineage-revision-a1'
        \\);
        ,
        \\INSERT INTO taxpayer_registration_branch_code_lineage (
        \\  taxpayer_id, branch_code, registration_unit_id, evidence_id, unit_revision_id
        \\) VALUES (
        \\  'lineage-taxpayer-a', '00001', 'lineage-unit-a1',
        \\  'lineage-evidence-a2', 'lineage-revision-a1'
        \\);
    }) |sql| {
        try std.testing.expectError(
            tax_profile_store.Error.SqliteConstraint,
            tax_profile_store.testing.execConstraintFixture(&store, sql),
        );
    }
}

test "tax-type shell lifecycle and sequences fail closed under direct SQL" {
    var store = try tax_profile_store.Store.openMemory(std.testing.allocator);
    defer store.close();

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_taxpayers (id)
        \\VALUES ('sequence-taxpayer');
        \\INSERT INTO taxpayer_registration_units (id, taxpayer_id)
        \\VALUES ('sequence-unit', 'sequence-taxpayer');
        \\INSERT INTO taxpayer_registration_unit_revisions (
        \\  id, taxpayer_id, registration_unit_id, sequence, effective_from,
        \\  kind, branch_code_state, branch_code, status
        \\) VALUES (
        \\  'sequence-unit-revision-1', 'sequence-taxpayer', 'sequence-unit',
        \\  1, '2026-01-01', 'branch', 'unconfirmed', '00001',
        \\  'pending_evidence'
        \\);
        \\INSERT INTO taxpayer_registration_tax_type_registrations (
        \\  id, taxpayer_id, registration_unit_id
        \\) VALUES (
        \\  'sequence-tax-registration', 'sequence-taxpayer', 'sequence-unit'
        \\);
        \\INSERT INTO taxpayer_registration_tax_type_registration_revisions (
        \\  id, registration_id, sequence, effective_from, tax_type, status
        \\) VALUES (
        \\  'sequence-tax-revision-1', 'sequence-tax-registration', 1,
        \\  '2026-01-01', 'vat', 'pending_evidence'
        \\);
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_tax_type_registrations (
        \\  id, taxpayer_id, registration_unit_id
        \\) VALUES (
        \\  'sequence-duplicate-tax-registration',
        \\  'sequence-taxpayer', 'sequence-unit'
        \\);
    );
    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_tax_type_registration_revisions (
            \\  id, registration_id, sequence, effective_from, tax_type, status
            \\) VALUES (
            \\  'sequence-duplicate-tax-revision-1',
            \\  'sequence-duplicate-tax-registration', 1,
            \\  '2026-01-01', 'vat', 'pending_evidence'
            \\);
        ),
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_evidence (
        \\  id, source_kind, sha256, display_name, byte_size, captured_on,
        \\  storage_reference_kind, storage_reference
        \\) VALUES (
        \\  'sequence-active-tax-evidence', 'cor',
        \\  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        \\  'Sequence active tax evidence', 0, '2026-03-01',
        \\  'protected_local_path', '/protected/test/sequence-active-tax.pdf'
        \\);
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\  id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\  fact_kind, tax_type, tax_type_status
        \\) VALUES (
        \\  'sequence-active-tax-assertion', 'sequence-active-tax-evidence',
        \\  'sequence-taxpayer', 'sequence-unit', '2026-03-01',
        \\  'tax_type_registration', 'vat', 'confirmed_active'
        \\);
        \\INSERT INTO taxpayer_registration_evidence_review_decisions (
        \\  id, evidence_id, sequence, review_state, reviewer_kind,
        \\  reviewer_service_actor_id, reviewed_at, review_reason
        \\) VALUES (
        \\  'sequence-active-tax-review', 'sequence-active-tax-evidence', 1,
        \\  'accepted', 'service', 'sequence-test-reviewer', 1,
        \\  'Accepted for active-unit invariant regression'
        \\);
    );
    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_tax_type_registration_revisions (
            \\  id, registration_id, sequence, effective_from, tax_type, status,
            \\  evidence_id
            \\) VALUES (
            \\  'sequence-active-tax-revision', 'sequence-tax-registration', 2,
            \\  '2026-03-01', 'vat', 'confirmed_active',
            \\  'sequence-active-tax-evidence'
            \\);
        ),
    );

    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_unit_revisions (
            \\  id, taxpayer_id, registration_unit_id, sequence, effective_from,
            \\  kind, branch_code_state, branch_code, status
            \\) VALUES (
            \\  'sequence-unit-revision-3', 'sequence-taxpayer', 'sequence-unit',
            \\  3, '2026-03-01', 'branch', 'unconfirmed', '00002',
            \\  'pending_evidence'
            \\);
        ),
    );
    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_tax_type_registration_revisions (
            \\  id, registration_id, sequence, effective_from, tax_type, status
            \\) VALUES (
            \\  'sequence-tax-revision-3', 'sequence-tax-registration', 3,
            \\  '2026-03-01', 'vat', 'pending_evidence'
            \\);
        ),
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_unit_revisions (
        \\  id, taxpayer_id, registration_unit_id, sequence, effective_from,
        \\  kind, branch_code_state, branch_code, status
        \\) VALUES (
        \\  'sequence-unit-revision-2', 'sequence-taxpayer', 'sequence-unit',
        \\  2, '2026-02-01', 'branch', 'unconfirmed', '00002',
        \\  'pending_evidence'
        \\);
        \\INSERT INTO taxpayer_registration_tax_type_registration_revisions (
        \\  id, registration_id, sequence, effective_from, tax_type, status
        \\) VALUES (
        \\  'sequence-tax-revision-2', 'sequence-tax-registration', 2,
        \\  '2026-02-01', 'vat', 'pending_evidence'
        \\);
    );
}

test "v28 registration unit contact revisions fail closed under direct SQL" {
    var store = try tax_profile_store.Store.openMemory(std.testing.allocator);
    defer store.close();

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_taxpayers (id)
        \\VALUES ('contact-sql-taxpayer');
        \\INSERT INTO taxpayer_registration_units (id, taxpayer_id)
        \\VALUES ('contact-sql-unit', 'contact-sql-taxpayer');
        \\INSERT INTO taxpayer_registration_evidence (
        \\    id, source_kind, sha256, display_name, byte_size, captured_on,
        \\    storage_reference_kind, storage_reference
        \\) VALUES
        \\    ('contact-accepted-evidence', 'cor',
        \\        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        \\        'Accepted contact COR', 0, '2026-01-01',
        \\        'protected_local_path', '/protected/test/contact-accepted-cor.pdf'),
        \\    ('contact-rejected-evidence', 'cor',
        \\        'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        \\        'Rejected contact COR', 0, '2026-03-15',
        \\        'metadata_only_non_authoritative', NULL);
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\    id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\    fact_kind, registered_address, zip_code, contact_number, email_address
        \\) VALUES
        \\    ('contact-assertion-1', 'contact-accepted-evidence',
        \\        'contact-sql-taxpayer', 'contact-sql-unit', '2026-01-02',
        \\        'registration_unit_contact', 'First registered address',
        \\        NULL, NULL, NULL),
        \\    ('contact-assertion-2', 'contact-accepted-evidence',
        \\        'contact-sql-taxpayer', 'contact-sql-unit', '2026-02-01',
        \\        'registration_unit_contact', 'Second registered address',
        \\        '1000', '+639171234567', 'unit@example.test'),
        \\    ('contact-backdated-assertion', 'contact-accepted-evidence',
        \\        'contact-sql-taxpayer', 'contact-sql-unit', '2026-01-15',
        \\        'registration_unit_contact', 'Backdated registered address',
        \\        NULL, NULL, NULL),
        \\    ('contact-assertion-3', 'contact-accepted-evidence',
        \\        'contact-sql-taxpayer', 'contact-sql-unit', '2026-03-01',
        \\        'registration_unit_contact', 'Third registered address',
        \\        NULL, NULL, NULL),
        \\    ('contact-rejected-assertion', 'contact-rejected-evidence',
        \\        'contact-sql-taxpayer', 'contact-sql-unit', '2026-03-15',
        \\        'registration_unit_contact', 'Rejected evidence address',
        \\        NULL, NULL, NULL),
        \\    ('contact-invalid-interval-assertion', 'contact-accepted-evidence',
        \\        'contact-sql-taxpayer', 'contact-sql-unit', '2026-05-01',
        \\        'registration_unit_contact', 'Invalid interval address',
        \\        NULL, NULL, NULL);
    );

    for ([_][*:0]const u8{
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\    id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\    fact_kind, registered_address
        \\) VALUES (
        \\    'contact-shape-missing-address', 'contact-accepted-evidence',
        \\    'contact-sql-taxpayer', 'contact-sql-unit', '2026-04-01',
        \\    'registration_unit_contact', NULL
        \\);
        ,
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\    id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\    fact_kind, branch_code, registration_unit_status, registered_address
        \\) VALUES (
        \\    'contact-shape-extra-contact', 'contact-accepted-evidence',
        \\    'contact-sql-taxpayer', 'contact-sql-unit', '2026-04-02',
        \\    'registration_unit', '00001', 'confirmed_active', 'Must be null'
        \\);
        ,
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\    id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\    fact_kind, branch_code, registered_address
        \\) VALUES (
        \\    'contact-shape-extra-unit-fact', 'contact-accepted-evidence',
        \\    'contact-sql-taxpayer', 'contact-sql-unit', '2026-04-03',
        \\    'registration_unit_contact', '00001', 'Must not carry branch facts'
        \\);
        ,
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\    id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\    fact_kind, registered_address
        \\) VALUES (
        \\    'contact-invalid-address', 'contact-accepted-evidence',
        \\    'contact-sql-taxpayer', 'contact-sql-unit', '2026-04-04',
        \\    'registration_unit_contact', ' Padded address'
        \\);
        ,
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\    id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\    fact_kind, registered_address, zip_code
        \\) VALUES (
        \\    'contact-invalid-zip', 'contact-accepted-evidence',
        \\    'contact-sql-taxpayer', 'contact-sql-unit', '2026-04-05',
        \\    'registration_unit_contact', 'Valid address', '10A0'
        \\);
        ,
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\    id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\    fact_kind, registered_address, contact_number
        \\) VALUES (
        \\    'contact-invalid-phone', 'contact-accepted-evidence',
        \\    'contact-sql-taxpayer', 'contact-sql-unit', '2026-04-06',
        \\    'registration_unit_contact', 'Valid address', '0917-123-4567'
        \\);
        ,
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\    id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\    fact_kind, registered_address, email_address
        \\) VALUES (
        \\    'contact-invalid-email', 'contact-accepted-evidence',
        \\    'contact-sql-taxpayer', 'contact-sql-unit', '2026-04-07',
        \\    'registration_unit_contact', 'Valid address', 'owner@example'
        \\);
    }) |sql| {
        try std.testing.expectError(
            tax_profile_store.Error.SqliteConstraint,
            tax_profile_store.testing.execConstraintFixture(&store, sql),
        );
    }

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_evidence_review_decisions (
        \\    id, evidence_id, sequence, review_state,
        \\    reviewer_kind, reviewer_local_owner_id, reviewer_service_actor_id,
        \\    reviewed_at, review_reason
        \\) VALUES
        \\    ('contact-accepted-review', 'contact-accepted-evidence',
        \\        1, 'accepted', 'service', NULL, 'contact-test-reviewer', 1,
        \\        'Contact evidence accepted'),
        \\    ('contact-rejected-review', 'contact-rejected-evidence',
        \\        1, 'rejected', 'service', NULL, 'contact-test-reviewer', 1,
        \\        'Contact evidence rejected');
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_unit_contact_revisions (
        \\    id, taxpayer_id, registration_unit_id, sequence,
        \\    effective_from, effective_until, registered_address,
        \\    zip_code, contact_number, email_address, evidence_id
        \\) VALUES (
        \\    'contact-revision-1', 'contact-sql-taxpayer', 'contact-sql-unit', 1,
        \\    '2026-01-02', NULL, 'First registered address',
        \\    NULL, NULL, NULL, 'contact-accepted-evidence'
        \\);
    );

    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_unit_contact_revisions (
            \\    id, taxpayer_id, registration_unit_id, sequence,
            \\    effective_from, effective_until, registered_address,
            \\    zip_code, contact_number, email_address, evidence_id
            \\) VALUES (
            \\    'contact-revision-2-null-mismatch',
            \\    'contact-sql-taxpayer', 'contact-sql-unit', 2,
            \\    '2026-02-01', NULL, 'Second registered address',
            \\    NULL, '+639171234567', 'unit@example.test',
            \\    'contact-accepted-evidence'
            \\);
        ),
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_unit_contact_revisions (
        \\    id, taxpayer_id, registration_unit_id, sequence,
        \\    effective_from, effective_until, registered_address,
        \\    zip_code, contact_number, email_address, evidence_id
        \\) VALUES (
        \\    'contact-revision-2', 'contact-sql-taxpayer', 'contact-sql-unit', 2,
        \\    '2026-02-01', NULL, 'Second registered address',
        \\    '1000', '+639171234567', 'unit@example.test',
        \\    'contact-accepted-evidence'
        \\);
    );

    for ([_][*:0]const u8{
        \\INSERT INTO taxpayer_registration_unit_contact_revisions (
        \\    id, taxpayer_id, registration_unit_id, sequence,
        \\    effective_from, effective_until, registered_address,
        \\    zip_code, contact_number, email_address, evidence_id
        \\) VALUES (
        \\    'contact-rejected-revision', 'contact-sql-taxpayer',
        \\    'contact-sql-unit', 3, '2026-03-15', NULL,
        \\    'Rejected evidence address', NULL, NULL, NULL,
        \\    'contact-rejected-evidence'
        \\);
        ,
        \\INSERT INTO taxpayer_registration_unit_contact_revisions (
        \\    id, taxpayer_id, registration_unit_id, sequence,
        \\    effective_from, effective_until, registered_address,
        \\    zip_code, contact_number, email_address, evidence_id
        \\) VALUES (
        \\    'contact-invalid-interval-revision', 'contact-sql-taxpayer',
        \\    'contact-sql-unit', 3, '2026-05-01', '2026-04-30',
        \\    'Invalid interval address', NULL, NULL, NULL,
        \\    'contact-accepted-evidence'
        \\);
        ,
        \\INSERT INTO taxpayer_registration_unit_contact_revisions (
        \\    id, taxpayer_id, registration_unit_id, sequence,
        \\    effective_from, effective_until, registered_address,
        \\    zip_code, contact_number, email_address, evidence_id
        \\) VALUES (
        \\    'contact-stale-revision', 'contact-sql-taxpayer',
        \\    'contact-sql-unit', 4, '2026-03-01', NULL,
        \\    'Third registered address', NULL, NULL, NULL,
        \\    'contact-accepted-evidence'
        \\);
    }) |sql| {
        try std.testing.expectError(
            tax_profile_store.Error.SqliteConstraint,
            tax_profile_store.testing.execConstraintFixture(&store, sql),
        );
    }

    // A correction appended on the same civil day is valid history. Sequence
    // resolves which immutable fact is effective; the older row remains as
    // audit evidence and must not create an overlapping current interval.
    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_unit_contact_revisions (
        \\    id, taxpayer_id, registration_unit_id, sequence,
        \\    effective_from, effective_until, registered_address,
        \\    zip_code, contact_number, email_address, evidence_id
        \\) VALUES (
        \\    'contact-same-day-correction-revision', 'contact-sql-taxpayer',
        \\    'contact-sql-unit', 3, '2026-02-01', NULL,
        \\    'Second registered address', '1000', '+639171234567',
        \\    'unit@example.test', 'contact-accepted-evidence'
        \\);
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_unit_contact_revisions (
        \\    id, taxpayer_id, registration_unit_id, sequence,
        \\    effective_from, effective_until, registered_address,
        \\    zip_code, contact_number, email_address, evidence_id
        \\) VALUES (
        \\    'contact-backdated-revision', 'contact-sql-taxpayer',
        \\    'contact-sql-unit', 4, '2026-01-15', NULL,
        \\    'Backdated registered address', NULL, NULL, NULL,
        \\    'contact-accepted-evidence'
        \\);
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_unit_contact_revisions (
        \\    id, taxpayer_id, registration_unit_id, sequence,
        \\    effective_from, effective_until, registered_address,
        \\    zip_code, contact_number, email_address, evidence_id
        \\) VALUES (
        \\    'contact-revision-5', 'contact-sql-taxpayer', 'contact-sql-unit', 5,
        \\    '2026-03-01', NULL, 'Third registered address',
        \\    NULL, NULL, NULL, 'contact-accepted-evidence'
        \\);
    );

    const derived_overlap_count = try tax_profile_store.testing.scalarIntConstraintFixture(&store,
        \\WITH current_rows AS (
        \\    SELECT candidate.*
        \\    FROM taxpayer_registration_unit_contact_revisions AS candidate
        \\    WHERE candidate.registration_unit_id = 'contact-sql-unit'
        \\      AND NOT EXISTS (
        \\        SELECT 1
        \\        FROM taxpayer_registration_unit_contact_revisions AS later
        \\        WHERE later.registration_unit_id = candidate.registration_unit_id
        \\          AND later.effective_from = candidate.effective_from
        \\          AND later.sequence > candidate.sequence
        \\      )
        \\),
        \\resolved_intervals AS (
        \\    SELECT current.id, current.sequence, current.effective_from,
        \\      MIN(
        \\        COALESCE(current.effective_until, '9999-12-31'),
        \\        COALESCE(date((
        \\            SELECT MIN(next.effective_from)
        \\            FROM current_rows AS next
        \\            WHERE next.registration_unit_id = current.registration_unit_id
        \\              AND next.effective_from > current.effective_from
        \\        ), '-1 day'), '9999-12-31')
        \\      ) AS resolved_until
        \\    FROM current_rows AS current
        \\)
        \\SELECT COUNT(*)
        \\FROM resolved_intervals AS left_interval
        \\JOIN resolved_intervals AS right_interval
        \\  ON left_interval.sequence < right_interval.sequence
        \\WHERE left_interval.effective_from <= right_interval.resolved_until
        \\  AND right_interval.effective_from <= left_interval.resolved_until;
    );
    try std.testing.expectEqual(@as(i64, 0), derived_overlap_count);

    const exact_interval_count = try tax_profile_store.testing.scalarIntConstraintFixture(&store,
        \\WITH current_rows AS (
        \\    SELECT candidate.*
        \\    FROM taxpayer_registration_unit_contact_revisions AS candidate
        \\    WHERE candidate.registration_unit_id = 'contact-sql-unit'
        \\      AND NOT EXISTS (
        \\        SELECT 1
        \\        FROM taxpayer_registration_unit_contact_revisions AS later
        \\        WHERE later.registration_unit_id = candidate.registration_unit_id
        \\          AND later.effective_from = candidate.effective_from
        \\          AND later.sequence > candidate.sequence
        \\      )
        \\),
        \\resolved_intervals AS (
        \\    SELECT current.id,
        \\      MIN(
        \\        COALESCE(current.effective_until, '9999-12-31'),
        \\        COALESCE(date((
        \\            SELECT MIN(next.effective_from)
        \\            FROM current_rows AS next
        \\            WHERE next.registration_unit_id = current.registration_unit_id
        \\              AND next.effective_from > current.effective_from
        \\        ), '-1 day'), '9999-12-31')
        \\      ) AS resolved_until
        \\    FROM current_rows AS current
        \\)
        \\SELECT COUNT(*)
        \\FROM resolved_intervals
        \\WHERE (id = 'contact-revision-1' AND resolved_until = '2026-01-14')
        \\   OR (id = 'contact-backdated-revision' AND resolved_until = '2026-01-31')
        \\   OR (id = 'contact-same-day-correction-revision' AND resolved_until = '2026-02-28')
        \\   OR (id = 'contact-revision-5' AND resolved_until = '9999-12-31');
    );
    try std.testing.expectEqual(@as(i64, 4), exact_interval_count);

    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\UPDATE taxpayer_registration_unit_contact_revisions
            \\SET registered_address = 'Rewritten address'
            \\WHERE id = 'contact-revision-5';
        ),
    );
    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\DELETE FROM taxpayer_registration_unit_contact_revisions
            \\WHERE id = 'contact-revision-5';
        ),
    );
}

test "v28 review stream and transfer destination fail closed under direct SQL" {
    var store = try tax_profile_store.Store.openMemory(std.testing.allocator);
    defer store.close();

    try std.testing.expectError(
        tax_profile_store.Error.SqliteFailure,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_evidence (
            \\ id, source_kind, sha256, display_name, byte_size, captured_on,
            \\ review_state
            \\) VALUES (
            \\ 'forged-accepted-evidence', 'cor',
            \\ '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
            \\ 'Forged accepted COR', 0, '2026-01-01', 'accepted'
            \\);
        ),
    );

    try tax_profile_store.testing.execConstraintFixture(&store,
        \\INSERT INTO taxpayer_registration_taxpayers (id)
        \\VALUES ('transfer-sql-taxpayer');
        \\INSERT INTO taxpayer_registration_units (id, taxpayer_id)
        \\VALUES ('transfer-sql-unit', 'transfer-sql-taxpayer');
        \\INSERT INTO taxpayer_registration_evidence (
        \\ id, source_kind, sha256, display_name, byte_size, captured_on,
        \\ storage_reference_kind, storage_reference
        \\) VALUES
        \\ ('transfer-confirmation-evidence', 'cor',
        \\  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        \\  'Confirmation COR', 0, '2026-01-01',
        \\  'protected_local_path', '/protected/test/transfer-confirmation-cor.pdf'),
        \\ ('transfer-destination-evidence', 'cor',
        \\  'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        \\  'Transfer COR', 0, '2026-02-01',
        \\  'protected_local_path', '/protected/test/transfer-destination-cor.pdf');
        \\INSERT INTO taxpayer_registration_evidence_assertions (
        \\ id, evidence_id, taxpayer_id, registration_unit_id, effective_from,
        \\ fact_kind, branch_code, registration_unit_status, rdo_code
        \\) VALUES
        \\ ('transfer-confirmation-assertion', 'transfer-confirmation-evidence',
        \\  'transfer-sql-taxpayer', 'transfer-sql-unit', '2026-01-01',
        \\  'registration_unit', '00001', 'confirmed_active', NULL),
        \\ ('transfer-missing-destination-assertion', 'transfer-destination-evidence',
        \\  'transfer-sql-taxpayer', 'transfer-sql-unit', '2026-02-01',
        \\  'registration_unit', '00001', 'confirmed_active', NULL),
        \\ ('transfer-destination-assertion', 'transfer-destination-evidence',
        \\  'transfer-sql-taxpayer', 'transfer-sql-unit', '2026-02-01',
        \\  'registration_unit', '00001', 'confirmed_active', '123');
        \\INSERT INTO taxpayer_registration_evidence_review_decisions (
        \\ id, evidence_id, sequence, review_state,
        \\ reviewer_kind, reviewer_local_owner_id, reviewer_service_actor_id,
        \\ reviewed_at, review_reason
        \\) VALUES
        \\ ('transfer-confirmation-review', 'transfer-confirmation-evidence',
        \\  1, 'accepted', 'service', NULL, 'transfer-test-reviewer', 1,
        \\  'Confirmation COR accepted'),
        \\ ('transfer-destination-review', 'transfer-destination-evidence',
        \\  1, 'accepted', 'service', NULL, 'transfer-test-reviewer', 1,
        \\  'Transfer COR accepted');
        \\INSERT INTO taxpayer_registration_unit_revisions (
        \\ id, taxpayer_id, registration_unit_id, sequence, effective_from,
        \\ kind, branch_code_state, branch_code, legacy_suffix, status, rdo_code,
        \\ branch_code_evidence_id, lifecycle_evidence_id
        \\) VALUES (
        \\ 'transfer-sql-revision-1', 'transfer-sql-taxpayer', 'transfer-sql-unit',
        \\ 1, '2026-01-01', 'branch', 'confirmed', '00001', NULL,
        \\ 'confirmed_active', NULL, 'transfer-confirmation-evidence',
        \\ 'transfer-confirmation-evidence'
        \\);
    );

    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_unit_revisions (
            \\ id, taxpayer_id, registration_unit_id, sequence, effective_from,
            \\ kind, branch_code_state, branch_code, legacy_suffix, status, rdo_code,
            \\ branch_code_evidence_id, lifecycle_evidence_id
            \\) VALUES (
            \\ 'transfer-sql-revision-2-missing-rdo', 'transfer-sql-taxpayer',
            \\ 'transfer-sql-unit', 2, '2026-02-01', 'branch', 'confirmed',
            \\ '00001', NULL, 'confirmed_active', NULL,
            \\ 'transfer-confirmation-evidence', 'transfer-destination-evidence'
            \\);
        ),
    );
    try std.testing.expectError(
        tax_profile_store.Error.SqliteConstraint,
        tax_profile_store.testing.execConstraintFixture(&store,
            \\INSERT INTO taxpayer_registration_unit_revisions (
            \\ id, taxpayer_id, registration_unit_id, sequence, effective_from,
            \\ kind, branch_code_state, branch_code, legacy_suffix, status, rdo_code,
            \\ branch_code_evidence_id, lifecycle_evidence_id
            \\) VALUES (
            \\ 'transfer-sql-revision-2-wrong-rdo', 'transfer-sql-taxpayer',
            \\ 'transfer-sql-unit', 2, '2026-02-01', 'branch', 'confirmed',
            \\ '00001', NULL, 'confirmed_active', '124',
            \\ 'transfer-confirmation-evidence', 'transfer-destination-evidence'
            \\);
        ),
    );
}
