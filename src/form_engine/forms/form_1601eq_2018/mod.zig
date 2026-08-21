//! 1601EQ January 2018 (ENCS) exact form package.
//!
//! Identity is pinned. The static HTA control inventory, declaration
//! contract, event-attribute inventory, HTA-local remittance totals
//! (Items 24, 25, 29, 30), over-remittance exclusive choice, and the
//! amended-return gate for Item 22 are pinned. Script closure and ATC
//! lookup are not. Remaining parts stay fail-closed until the five absent
//! active scripts and two path-placement variants are recovered or
//! independently reconstructed with provenance.

pub const evidence = @import("evidence.zig");
pub const occurrences = @import("occurrences.zig");
pub const control_contract = @import("control_contract.zig");
pub const event_contract = @import("event_contract.zig");
pub const calculations = @import("calculations.zig");
pub const validation = @import("validation.zig");
pub const document = @import("document.zig");
pub const editable_codec = @import("editable_codec.zig");
pub const final_copy_codec = @import("final_copy_codec.zig");
pub const rdo_options = @import("rdo_options.zig");
pub const profile_mapping = @import("profile_mapping.zig");
pub const transaction = @import("transaction.zig");
pub const workflow = @import("workflow.zig");
pub const interaction = @import("interaction.zig");

/// Frozen identity for this package. The registry keys off this rather than a
/// separately maintained code/revision pair, so identity cannot drift from the
/// evidence that establishes it.
pub const package_key = evidence.package_key;

test {
    _ = evidence;
    _ = occurrences;
    _ = control_contract;
    _ = event_contract;
    _ = calculations;
    _ = validation;
    _ = document;
    _ = editable_codec;
    _ = final_copy_codec;
    _ = rdo_options;
    _ = profile_mapping;
    _ = transaction;
    _ = workflow;
    _ = interaction;
}
