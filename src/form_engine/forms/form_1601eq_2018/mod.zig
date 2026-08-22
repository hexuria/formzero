//! 1601EQ January 2018 (ENCS) exact form package.
//!
//! Identity is pinned. The static HTA control inventory, declaration
//! contract, event-attribute inventory, HTA-local remittance totals
//! (Items 24, 25, 29, 30), over-remittance exclusive choice, the
//! amended-return gate for Item 22, the Item 1/2 year-quarter gates, and
//! the `validateForm` identity required-field gates (Items 4, 11, 6, 7, 8,
//! 10, 9, 9A, 12), the Part II ATC entry gate, and the Validate/Edit lock
//! the confirm-guarded computation reset, and the Item 7 RDO option domain
//! are pinned, as are the ATC lookup domain, the Part II row model and its
//! per-row withholding, the ATC selection placement, and the HTA money text
//! rules and keypress filter behind them, and the year-driven ATC rate
//! refresh, the startup control state, and the profile-to-control mapping. Script closure and ATC lookup are not.
//! Remaining parts stay fail-closed until the five absent active scripts
//! and two path-placement variants are recovered or independently
//! reconstructed with provenance.

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
pub const atc_catalog = @import("atc_catalog.zig");
pub const atc_rows = @import("atc_rows.zig");
pub const money_text = @import("money_text.zig");
pub const atc_selection = @import("atc_selection.zig");
pub const year_rate_refresh = @import("year_rate_refresh.zig");
pub const startup = @import("startup.zig");
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
    _ = atc_catalog;
    _ = atc_rows;
    _ = money_text;
    _ = atc_selection;
    _ = year_rate_refresh;
    _ = startup;
    _ = profile_mapping;
    _ = transaction;
    _ = workflow;
    _ = interaction;
}
