//! Exact-form engine foundation.
//!
//! UI, outbound encryption, and transport remain outside this module and fail
//! closed.
//!
//! Forms are registered in `registry` as whole packages rather than as loose
//! per-part aliases. Adding a form means creating its directory with a
//! `mod.zig` and adding one line below; `package.verify` then names any part
//! the new package has not yet provided.

const std = @import("std");
const package = @import("package.zig");

pub const identity = @import("identity.zig");
pub const evidence = @import("evidence.zig");
pub const occurrence = @import("occurrence.zig");
pub const draft = @import("draft.zig");
pub const contract = package;

pub const form_1701q_2018 = @import("forms/form_1701q_2018/mod.zig");

/// Every exact form package this build knows about.
///
/// Only 1701Q January 2018 (ENCS) is registered today. The remaining catalog
/// forms stay calendar-only until their package exists.
pub const registry = .{
    form_1701q_2018,
};

/// Number of registered exact form packages.
pub const registered_count: usize = registry.len;

comptime {
    for (registry) |Package| package.verify(Package);
}

test {
    _ = identity;
    _ = evidence;
    _ = occurrence;
    _ = draft;
    _ = package;
    inline for (registry) |Package| _ = Package;
}

test "every registered package satisfies the structural contract" {
    try std.testing.expect(registered_count >= 1);
    inline for (registry) |Package| {
        // Reading identity through the contract also proves it is reachable
        // without importing the package's internals.
        const revision = package.revisionOf(Package);
        try std.testing.expect(revision.code.asSlice().len > 0);
        try std.testing.expect(revision.revision.asSlice().len > 0);
    }
}

test "the registered 1701Q package reports its printed identity" {
    const revision = package.revisionOf(form_1701q_2018);
    try std.testing.expectEqualStrings("1701Q", revision.code.asSlice());
    try std.testing.expectEqualStrings("2018-01-ENCS", revision.revision.asSlice());
}
