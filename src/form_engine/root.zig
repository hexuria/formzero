//! Exact-form engine foundation.
//!
//! Only 1701Q January 2018 (ENCS) is registered. UI, outbound encryption, and
//! transport remain outside this module and fail closed.

pub const identity = @import("identity.zig");
pub const evidence = @import("evidence.zig");
pub const occurrence = @import("occurrence.zig");
pub const draft = @import("draft.zig");
pub const form_1701q_2018_evidence =
    @import("forms/form_1701q_2018/evidence.zig");
pub const form_1701q_2018_occurrences =
    @import("forms/form_1701q_2018/occurrences.zig");
pub const form_1701q_2018_control_contract =
    @import("forms/form_1701q_2018/control_contract.zig");
pub const form_1701q_2018_event_contract =
    @import("forms/form_1701q_2018/event_contract.zig");
pub const form_1701q_2018_calculations =
    @import("forms/form_1701q_2018/calculations.zig");
pub const form_1701q_2018_validation =
    @import("forms/form_1701q_2018/validation.zig");
pub const form_1701q_2018_document =
    @import("forms/form_1701q_2018/document.zig");
pub const form_1701q_2018_editable_codec =
    @import("forms/form_1701q_2018/editable_codec.zig");
pub const form_1701q_2018_final_copy_codec =
    @import("forms/form_1701q_2018/final_copy_codec.zig");
pub const form_1701q_2018_rdo_options =
    @import("forms/form_1701q_2018/rdo_options.zig");
pub const form_1701q_2018_profile_mapping =
    @import("forms/form_1701q_2018/profile_mapping.zig");
pub const form_1701q_2018_transaction =
    @import("forms/form_1701q_2018/transaction.zig");
pub const form_1701q_2018_workflow =
    @import("forms/form_1701q_2018/workflow.zig");
pub const form_1701q_2018_interaction =
    @import("forms/form_1701q_2018/interaction.zig");

test {
    _ = identity;
    _ = evidence;
    _ = occurrence;
    _ = draft;
    _ = form_1701q_2018_evidence;
    _ = form_1701q_2018_occurrences;
    _ = form_1701q_2018_control_contract;
    _ = form_1701q_2018_event_contract;
    _ = form_1701q_2018_calculations;
    _ = form_1701q_2018_validation;
    _ = form_1701q_2018_document;
    _ = form_1701q_2018_editable_codec;
    _ = form_1701q_2018_final_copy_codec;
    _ = form_1701q_2018_rdo_options;
    _ = form_1701q_2018_profile_mapping;
    _ = form_1701q_2018_transaction;
    _ = form_1701q_2018_workflow;
    _ = form_1701q_2018_interaction;
}
