const std = @import("std");
const native_sdk = @import("native_sdk");
const storage_policy = @import("src/security/key_custody.zig");

pub fn build(b: *std.Build) void {
    const production_release_requested = b.option(
        bool,
        "production-release",
        "Request the unavailable fail-closed production release",
    ) orelse false;
    // This branch returns before Native SDK constructs an executable, test
    // artifact, install step, or package input.
    if (production_release_requested) {
        const production_release_failure = b.addFail(
            storage_policy.production_release_unavailable_reason,
        );
        b.getInstallStep().dependOn(&production_release_failure.step);
        return;
    }

    const artifacts = native_sdk.addAppArtifacts(
        b,
        b.dependency("native_sdk", .{}),
        .{ .name = "ebirforms-zero" },
    );
    const sqlite = b.dependency("sqlite", .{});

    // Reviewed release-shaped setting: retain only the reproducible PE debug
    // marker and omit the unstable CodeView/RSDS record.
    artifacts.exe.root_module.strip = true;
    // Native SDK 0.6.1 creates its install step before callers can adjust the
    // returned executable module. At that point Zig predicts a PDB and records
    // it in the install action; stripping removes the PDB, so leave only the
    // emitted executable in the install contract.
    artifacts.install.pdb_dir = null;
    artifacts.install.emitted_pdb = null;

    addSqlite(artifacts.exe.root_module, sqlite);
    if (artifacts.tests.root_module != artifacts.exe.root_module) {
        addSqlite(artifacts.tests.root_module, sqlite);
    }

    addSqliteLinkedTestRoots(b, sqlite, artifacts.tests.root_module);
    addProductionReleaseGateRegression(b);
    addWindowsPackagePeParserRegression(b);
}

fn addSqlite(module: *std.Build.Module, sqlite: *std.Build.Dependency) void {
    // SQLite is C, and Native SDK's null/model-contract modules do not
    // otherwise opt into a C runtime. Without this, Windows test builds invoke
    // Clang without Zig's libc headers and fail at sqlite3.c's <stdio.h>.
    module.link_libc = true;
    module.addIncludePath(sqlite.path(""));
    module.addCSourceFile(.{
        .file = sqlite.path("sqlite3.c"),
        .flags = &.{
            "-std=c99",
            "-DSQLITE_THREADSAFE=1",
            "-DSQLITE_DEFAULT_FOREIGN_KEYS=1",
            "-DSQLITE_DQS=0",
            "-DSQLITE_OMIT_DEPRECATED",
        },
    });
}

fn addSqliteLinkedTestRoots(
    b: *std.Build,
    sqlite: *std.Build.Dependency,
    app_test_module: *std.Build.Module,
) void {
    const target = app_test_module.resolved_target orelse
        @panic("Native SDK test module has no resolved target");
    const optimize = app_test_module.optimize orelse .Debug;
    const roots = [_]struct {
        name: []const u8,
        path: []const u8,
    }{
        .{
            .name = "tax-profile-store-linked-tests",
            .path = "src/tax_profile_store_test_root.zig",
        },
        .{
            .name = "form-1701q-exact-persistence-linked-tests",
            .path = "src/form_1701q_exact_persistence_test_root.zig",
        },
    };

    const linked_step = b.step(
        "test-storage-linked",
        "Run linked storage roots on the build host; compile them when cross-targeting",
    );
    const native_test_top = b.top_level_steps.get("test") orelse
        @panic("Native SDK did not register its standard test step");
    const native_test_step = &native_test_top.step;
    const runnable = targetRunsOnBuildHost(b, target);

    for (roots) |root| {
        const module = b.createModule(.{
            .root_source_file = b.path(root.path),
            .target = target,
            .optimize = optimize,
        });
        addSqlite(module, sqlite);
        const tests = b.addTest(.{
            .name = root.name,
            .root_module = module,
        });
        if (runnable) {
            const run = b.addRunArtifact(tests);
            linked_step.dependOn(&run.step);
            native_test_step.dependOn(&run.step);
        } else {
            // Zig's build host identity cannot safely assume OS-level
            // cross-architecture execution or emulation. Cross targets still
            // compile both roots; their execution remains an explicit
            // target-native qualification command.
            linked_step.dependOn(&tests.step);
            native_test_step.dependOn(&tests.step);
        }
    }
}

fn targetRunsOnBuildHost(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
) bool {
    const host = b.graph.host.result;
    return target.result.os.tag == host.os.tag and
        target.result.cpu.arch == host.cpu.arch;
}

fn addProductionReleaseGateRegression(b: *std.Build) void {
    const step = b.step(
        "test-production-release-gate",
        "Prove the production release option fails before producing output",
    );
    if (b.graph.host.result.os.tag != .windows) {
        const unsupported = b.addFail(
            "test-production-release-gate currently requires Windows PowerShell",
        );
        step.dependOn(&unsupported.step);
        return;
    }

    const command = b.addSystemCommand(&.{
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
    });
    command.addFileArg(b.path("scripts/test-production-release-gate.ps1"));
    command.addArg("-ZigExecutable");
    command.addArg(b.graph.zig_exe);
    command.addArg("-RepositoryRoot");
    command.addArg(b.build_root.path orelse ".");
    step.dependOn(&command.step);
}

fn addWindowsPackagePeParserRegression(b: *std.Build) void {
    const step = b.step(
        "test-windows-package-pe-parser",
        "Run synthetic PE parser acceptance and malformed-image regressions",
    );
    if (b.graph.host.result.os.tag != .windows) {
        const unsupported = b.addFail(
            "test-windows-package-pe-parser currently requires Windows PowerShell",
        );
        step.dependOn(&unsupported.step);
        return;
    }

    const command = b.addSystemCommand(&.{
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
    });
    command.addFileArg(b.path("scripts/verify-windows-package.ps1"));
    command.addArg("-RunPeParserSelfTests");
    step.dependOn(&command.step);
}
