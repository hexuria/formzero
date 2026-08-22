//! 1601C January 2018 (ENCS) exact form package.
//!
//! Identity is pinned and script closure is complete: eight declared
//! dependencies, eight resolved, none unresolved. Every other part is
//! fail-closed and awaits transcription.

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
