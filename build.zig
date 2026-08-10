const std = @import("std");
const native_sdk = @import("native_sdk");
const storage_policy = @import("src/security/key_custody.zig");

const AppIdentity = struct {
    slug: []const u8,
    app_name: []const u8,
    display_name: []const u8,
    bundle_id: []const u8,
    shell_role: []const u8,
    app_root: []const u8,
    manifest_path: []const u8,
    is_main: bool,
};

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

    const identity = resolveAppIdentity(b);
    const artifacts = native_sdk.addAppArtifacts(
        b,
        b.dependency("native_sdk", .{}),
        .{
            .name = identity.app_name,
            .app_root = identity.app_root,
        },
    );
    if (!identity.is_main) disableUnsafeNativePackageStep(b);
    const sqlite = b.dependency("sqlite", .{});

    const identity_options = b.addOptions();
    identity_options.addOption([]const u8, "slug", identity.slug);
    identity_options.addOption([]const u8, "app_name", identity.app_name);
    identity_options.addOption([]const u8, "display_name", identity.display_name);
    identity_options.addOption([]const u8, "bundle_id", identity.bundle_id);
    identity_options.addOption([]const u8, "shell_role", identity.shell_role);
    identity_options.addOption([]const u8, "manifest_path", identity.manifest_path);
    identity_options.addOption(bool, "is_main", identity.is_main);
    const identity_module = identity_options.createModule();
    artifacts.exe.root_module.addImport("app_identity", identity_module);
    if (artifacts.tests.root_module != artifacts.exe.root_module) {
        artifacts.tests.root_module.addImport("app_identity", identity_module);
    }

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

fn disableUnsafeNativePackageStep(b: *std.Build) void {
    const package_top = b.top_level_steps.get("package") orelse
        @panic("Native SDK did not register its standard package step");
    package_top.step.dependencies.clearRetainingCapacity();
    const failure = b.addFail(
        "zig build package cannot use the static root app.zon for a branch " ++
            "identity; use `just package`, which supplies the resolved manifest",
    );
    package_top.step.dependOn(&failure.step);
}

fn resolveAppIdentity(b: *std.Build) AppIdentity {
    const node = b.graph.environ_map.get("BUWIZ_NODE") orelse "node";
    const script = b.pathFromRoot("scripts/app-identity.mjs");
    const result = std.process.run(b.allocator, b.graph.io, .{
        .argv = &.{ node, script, "prepare", "--format", "json" },
        .stdout_limit = .limited(16 * 1024),
        .stderr_limit = .limited(16 * 1024),
    }) catch |err| std.debug.panic(
        "failed to resolve Buwiz app identity: {s}",
        .{@errorName(err)},
    );
    if (result.term != .exited or result.term.exited != 0) {
        std.debug.panic(
            "failed to resolve Buwiz app identity:\n{s}",
            .{std.mem.trimEnd(u8, result.stderr, "\r\n")},
        );
    }

    const JsonIdentity = struct {
        ref: []const u8,
        slug: []const u8,
        isMain: bool,
        appName: []const u8,
        displayName: []const u8,
        bundleId: []const u8,
        shellRole: []const u8,
        appRoot: []const u8,
        manifestPath: []const u8,
    };
    const parsed = std.json.parseFromSliceLeaky(
        JsonIdentity,
        b.allocator,
        result.stdout,
        .{},
    ) catch identityOutputPanic();

    return .{
        .slug = parsed.slug,
        .app_name = parsed.appName,
        .display_name = parsed.displayName,
        .bundle_id = parsed.bundleId,
        .shell_role = parsed.shellRole,
        .app_root = parsed.appRoot,
        .manifest_path = parsed.manifestPath,
        .is_main = parsed.isMain,
    };
}

fn identityOutputPanic() noreturn {
    @panic("scripts/app-identity.mjs returned an invalid build identity");
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
