const std = @import("std");
const native_sdk = @import("native_sdk");

pub fn build(b: *std.Build) void {
    const artifacts = native_sdk.addAppArtifacts(
        b,
        b.dependency("native_sdk", .{}),
        .{ .name = "ebirforms-zero" },
    );
    const sqlite = b.dependency("sqlite", .{});

    addSqlite(artifacts.exe.root_module, sqlite);
    if (artifacts.tests.root_module != artifacts.exe.root_module) {
        addSqlite(artifacts.tests.root_module, sqlite);
    }
}

fn addSqlite(module: *std.Build.Module, sqlite: *std.Build.Dependency) void {
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
