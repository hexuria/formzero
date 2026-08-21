//! 1601EQ January 2018 (ENCS) editable codec.
//!
//! Fail-closed until the five absent active scripts and two path-placement
//! variants are recovered or independently reconstructed with provenance.
//! This module must not invent an editable-save codec.

const std = @import("std");
const evidence = @import("evidence.zig");

pub const ready = false;

test "1601EQ editable codec stay fail-closed" {
    try std.testing.expect(!ready);
    try std.testing.expect(!evidence.readiness.dependency_closure);
    try std.testing.expect(!evidence.readiness.identityReady());
}
