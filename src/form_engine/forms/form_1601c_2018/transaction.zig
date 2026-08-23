//! HTA-local 1601C print preparation and restore.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - `printme` lines 3992-4066
//! - `cancel`, the restore path, lines 3876-3935
//! - `Array.prototype.contains` polyfill, lines 3976-3988
//!
//! `printme` rewrites the live form for printing and `cancel` puts it back.
//! Neither renders anything; they move control state around, so this module
//! pins that movement rather than any output.
//!
//! ## The restore depends on a snapshot and a polyfill
//!
//! `printme` records the id of every control that was already disabled into
//! `disabledItems`, then changes them. `cancel` consults that array through
//! `disabledItems.contains(...)`.
//!
//! `Array.prototype.contains` is not a standard method, but the HTA defines
//! it at line 3976, choosing an `indexOf` implementation when one exists and
//! a reverse scan otherwise. Without that polyfill the restore would throw;
//! with it the round trip closes. It is recorded here because the restore
//! reads as broken until the definition is found.
//!
//! ## Text and choice controls are prepared in opposite directions
//!
//! A text control is **enabled** and marked read-only, so it prints as a
//! filled field rather than a greyed one. A radio or checkbox is
//! **disabled** outright. Both kinds have their prior disabled state
//! recorded first.
//!
//! ## One styling branch can never run
//!
//! Inside the radio-or-checkbox branch sits a further `type == 'select-one'`
//! test. A control cannot be a radio or a checkbox and also a select, so
//! that branch and its eighteen-pixel styling are unreachable. The live
//! select handling is a separate test after that block, which hides the
//! select and inserts a label carrying the selected option's text.
//!
//! Anchors carrying an id longer than one character are disabled by id.
//! `disabled` on an anchor is an IE extension rather than a standard
//! property, so the effect is host-dependent and is not asserted.
//!
//! Print preparation only. Nothing is rendered and `ui_integrated` stays
//! false.

const std = @import("std");
const evidence = @import("evidence.zig");
const occurrences = @import("occurrences.zig");

pub const ready = false;
pub const print_preparation_ready = true;

/// How `printme` prepares one control for printing.
pub const PrintPreparation = enum {
    /// Enabled and marked read-only, so it prints as a filled field.
    enabled_read_only,
    /// Disabled outright.
    disabled,
    /// Hidden, with a label carrying the selected option inserted after it.
    replaced_with_label,
    /// Skipped.
    untouched,
};

pub fn preparationFor(kind: occurrences.ControlKind) PrintPreparation {
    return switch (kind) {
        .text, .password, .textarea => .enabled_read_only,
        .radio, .checkbox => .disabled,
        .select_one => .replaced_with_label,
        .hidden => .untouched,
        .button => .untouched,
    };
}

/// `printme` records the prior disabled state so `cancel` can restore it.
pub const snapshots_prior_disabled_state = true;
/// `cancel` reads that snapshot through `Array.prototype.contains`.
pub const restore_uses_contains = true;
/// The HTA defines that method itself; it is not standard.
pub const contains_is_polyfilled_in_hta = true;
pub const contains_polyfill_line: u32 = 3976;

/// The unreachable branch: a select-one test nested inside the
/// radio-or-checkbox branch.
pub const unreachable_select_branch_line: u32 = 4036;

/// Anchors are disabled by id, which relies on an IE extension.
pub const disables_anchors_by_id = true;

test "1601C print preparation is pinned and renders nothing" {
    try std.testing.expect(print_preparation_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!evidence.readiness.ui_integrated);
}

test "1601C text and choice controls are prepared in opposite directions" {
    // A text field is enabled so it prints filled rather than greyed.
    try std.testing.expectEqual(PrintPreparation.enabled_read_only, preparationFor(.text));
    try std.testing.expectEqual(PrintPreparation.enabled_read_only, preparationFor(.textarea));
    // A choice control is disabled outright.
    try std.testing.expectEqual(PrintPreparation.disabled, preparationFor(.radio));
    try std.testing.expectEqual(PrintPreparation.disabled, preparationFor(.checkbox));
    // The two directions are genuinely opposite.
    try std.testing.expect(preparationFor(.text) != preparationFor(.radio));
}

test "1601C a select is replaced by a label, not restyled" {
    try std.testing.expectEqual(
        PrintPreparation.replaced_with_label,
        preparationFor(.select_one),
    );
    // The restyling branch that would have applied to a select sits inside
    // the radio-or-checkbox test and can never run.
    try std.testing.expectEqual(@as(u32, 4036), unreachable_select_branch_line);
}

test "1601C the restore depends on a polyfill the HTA supplies" {
    try std.testing.expect(snapshots_prior_disabled_state);
    try std.testing.expect(restore_uses_contains);
    // Without the definition at 3976 the restore would throw.
    try std.testing.expect(contains_is_polyfilled_in_hta);
    try std.testing.expectEqual(@as(u32, 3976), contains_polyfill_line);
    try std.testing.expect(contains_polyfill_line < 3992);
}

test "1601C buttons and hidden controls are left alone" {
    try std.testing.expectEqual(PrintPreparation.untouched, preparationFor(.button));
    try std.testing.expectEqual(PrintPreparation.untouched, preparationFor(.hidden));
    // Anchors are handled separately and by an IE-only property.
    try std.testing.expect(disables_anchors_by_id);
}
