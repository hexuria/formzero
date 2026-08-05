//! Native-SDK-independent test root for domain, profile, exact-form, and
//! container logic. Run with:
//!
//!   zig test src/core_logic_test.zig
//!
//! Keeping this root at `src/` allows the existing relative imports to remain
//! inside one Zig module while avoiding the GUI and SQLite build cost.

test "core logic modules remain in the headless test root" {
    _ = @import("domain/date.zig");
    _ = @import("domain/money.zig");
    _ = @import("tax_profile/field.zig");
    _ = @import("tax_profile/model.zig");
    _ = @import("tax_profile/capability.zig");
    _ = @import("tax_profile/projection.zig");
    _ = @import("tax_profile/editor.zig");
    _ = @import("tax_profile/evolution.zig");
    _ = @import("calendar/domain.zig");
    _ = @import("forms/id.zig");
    _ = @import("forms/spec.zig");
    _ = @import("forms/compose.zig");
    _ = @import("forms/lifecycle.zig");
    _ = @import("forms/form_1701q.zig");
    _ = @import("forms/form_1701q_exact_ui_state.zig");
    _ = @import("form_engine/root.zig");
    _ = @import("container_codec/legacy.zig");
    _ = @import("artifact_lab/session.zig");
    _ = @import("security/key_custody.zig");
    _ = @import("security/production_storage_evidence.zig");
    _ = @import("security/repository_opening.zig");
}
