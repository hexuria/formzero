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
pub const form_1601eq_2018 = @import("forms/form_1601eq_2018/mod.zig");

/// Every exact form package this build knows about.
///
/// 1701Q January 2018 (ENCS) is identity-ready. 1601EQ January 2018 (ENCS) is
/// registered with pinned identity and incomplete script closure; that is not
/// a runtime-parity claim.
pub const registry = .{
    form_1701q_2018,
    form_1601eq_2018,
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
    try std.testing.expectEqual(@as(usize, 2), registered_count);
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
    try std.testing.expect(form_1701q_2018.evidence.readiness.identityReady());
}

test "the registered 1601EQ package reports its printed identity and is not identity-ready" {
    const revision = package.revisionOf(form_1601eq_2018);
    try std.testing.expectEqualStrings("1601EQ", revision.code.asSlice());
    try std.testing.expectEqualStrings("2018-01-ENCS", revision.revision.asSlice());
    try std.testing.expect(!form_1601eq_2018.evidence.readiness.identityReady());
    try std.testing.expect(!form_1601eq_2018.evidence.readiness.dependency_closure);
    try std.testing.expect(!form_1701q_2018.package_key.eql(
        &form_1601eq_2018.package_key,
    ));
    try std.testing.expectEqual(
        @as(usize, 98),
        form_1601eq_2018.occurrences.control_seeds.len,
    );
    try std.testing.expectEqual(
        form_1601eq_2018.occurrences.control_seeds.len,
        form_1601eq_2018.control_contract.contracts.len,
    );
    try std.testing.expectEqual(
        @as(usize, 67),
        form_1601eq_2018.event_contract.observed_binding_count,
    );
    try std.testing.expect(!form_1601eq_2018.event_contract.handlers_implemented);
    try std.testing.expect(!form_1601eq_2018.occurrences.serializer_reviewed);
    try std.testing.expect(form_1601eq_2018.calculations.remittance_totals_ready);
    try std.testing.expect(!form_1601eq_2018.calculations.atc_lookup_ready);
    try std.testing.expect(!form_1601eq_2018.calculations.ready);
    try std.testing.expect(!form_1601eq_2018.evidence.readiness.calculation_reconciled);
    try std.testing.expect(form_1601eq_2018.interaction.exclusive_choice_ready);
    try std.testing.expect(form_1601eq_2018.interaction.amended_item22_ready);
    try std.testing.expect(!form_1601eq_2018.interaction.ready);
    try std.testing.expect(form_1601eq_2018.validation.year_quarter_ready);
    try std.testing.expect(form_1601eq_2018.validation.identity_required_ready);
    try std.testing.expect(!form_1601eq_2018.validation.ready);
}
