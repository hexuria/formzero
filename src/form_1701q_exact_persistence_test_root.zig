//! SQLite-linked test root for the exact 1701Q persistence/reopen bridge.
//!
//! This remains separate from `core_logic_test.zig` so the pure headless
//! engine suite never acquires a SQLite link requirement.

test "exact 1701Q persistence adapter remains in its SQLite-linked root" {
    _ = @import("forms/form_1701q_exact_persistence.zig");
}
