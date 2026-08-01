//! SQLite-linked test root for the shared calendar and tax-profile stores.
//!
//! Keep this separate from `core_logic_test.zig`: importing the store requires
//! a linked SQLite amalgamation and libc, while the pure core suite must remain
//! free of persistence dependencies.

const std = @import("std");
const calendar_store = @import("calendar/store.zig");
const key_custody = @import("security/key_custody.zig");
const repository_opening = @import("security/repository_opening.zig");
const tax_profile_store = @import("tax_profile/store.zig");

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
