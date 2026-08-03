//! The structural contract every exact form package must satisfy.
//!
//! 1701Q was built as fifteen loose modules named by hand in `root.zig`. That
//! shape does not survive the remaining form queue: each new form would add
//! fifteen more hand-maintained aliases, with nothing stating what a form is
//! actually required to provide.
//!
//! A package is a namespace exposing every part in `required_parts` plus a
//! `package_key`. `verify` turns a missing part into a compile error that
//! names the package and the part, so adding a form becomes: create the
//! directory, add one registry line, and let the compiler enumerate the work.
//!
//! This pins the *shape* of a package, not the signatures inside each part.
//! Those are still specific to 1701Q; generalising them needs a second real
//! form to compare against, and guessing now would encode one form's accidents
//! as the contract.

const std = @import("std");
const identity = @import("identity.zig");

/// Every part an exact form package must expose, in the order a form is
/// normally built: what it is, what occurrences it has, what controls and
/// events it declares, how it computes and validates, how it renders and
/// serialises, and how it binds to a profile and a workflow.
pub const required_parts = [_][]const u8{
    "evidence",
    "occurrences",
    "control_contract",
    "event_contract",
    "calculations",
    "validation",
    "document",
    "editable_codec",
    "final_copy_codec",
    "rdo_options",
    "profile_mapping",
    "transaction",
    "workflow",
    "interaction",
};

/// Compile-time structural check. Call this for every registered package.
pub fn verify(comptime Package: type) void {
    comptime {
        if (!@hasDecl(Package, "package_key")) {
            @compileError(
                "exact form package '" ++ @typeName(Package) ++
                    "' is missing `package_key`. Re-export it from the " ++
                    "package's evidence module so identity cannot drift from " ++
                    "the evidence that establishes it.",
            );
        }
        if (@TypeOf(Package.package_key) != identity.ExactFormPackageKey) {
            @compileError(
                "exact form package '" ++ @typeName(Package) ++
                    "' declares `package_key` of the wrong type; it must be " ++
                    "`identity.ExactFormPackageKey`.",
            );
        }
        for (required_parts) |part| {
            if (!@hasDecl(Package, part)) {
                @compileError(
                    "exact form package '" ++ @typeName(Package) ++
                        "' is missing the required part '" ++ part ++
                        "'. Every registered form must expose all " ++
                        std.fmt.comptimePrint("{d}", .{required_parts.len}) ++
                        " parts listed in form_engine/package.zig.",
                );
            }
        }
    }
}

/// The printed-form identity of a registered package.
pub fn revisionOf(comptime Package: type) identity.FormRevision {
    comptime verify(Package);
    return Package.package_key.revision;
}

test "the contract lists every part exactly once" {
    for (required_parts, 0..) |part, index| {
        for (required_parts[index + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, part, other));
        }
    }
}
