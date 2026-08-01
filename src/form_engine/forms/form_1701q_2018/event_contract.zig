//! Exact, value-free event-attribute inventory for the 173 eligible controls
//! in Offline eBIRForms 7.9.6 Form 1701Q January 2018 (ENCS).
//!
//! This is a declaration contract, not copied JavaScript. Each fact names the
//! observable handler pipeline attached in the verified HTA. Empty attributes
//! are retained deliberately: excluding them changes the evidence count from
//! 184 bindings on 123 controls to 172 non-empty bindings on 117 controls.

const std = @import("std");
const control_contract = @import("control_contract.zig");
const occurrences = @import("occurrences.zig");

pub const evidence_id = control_contract.evidence_id;
pub const observed_binding_count: usize = 184;
pub const observed_control_count: usize = 123;
pub const non_empty_binding_count: usize = 172;
pub const empty_binding_count: usize = 12;

pub const arbitrary_pre_blur_money_grammar_qualified = false;
pub const key_by_key_filtering_qualified = false;
pub const date_key_masking_qualified = false;
pub const current_page_navigation_qualified = false;

pub const EventKind = enum {
    blur,
    click,
    key_down,
    key_press,
    key_up,
};

/// A semantic fingerprint of the complete inline attribute. Repeated facts
/// mean the source attached the same pipeline to each listed control.
pub const HandlerFact = enum {
    empty_attribute,
    blur_year_normalize_compute46_validate_compute46,
    blur_global_uppercase,
    blur_round,
    blur_round_compute38_filer,
    blur_round_compute38_compute40_filer,
    blur_round_compute38_spouse,
    blur_round_compute38_compute40_spouse,
    blur_round_compute41_filer,
    blur_round_compute41_spouse,
    blur_round_compute45_filer,
    blur_round_compute45_spouse,
    blur_round_compute49_filer,
    blur_round_compute49_spouse,
    blur_round_compute51_filer,
    blur_round_compute51_spouse,
    blur_round_compute62_filer,
    blur_round_compute62_spouse,
    blur_round_compute67_filer,
    blur_round_compute67_spouse,
    blur_round_validate_item52_compute53_filer,
    blur_round_validate_item52_compute53_spouse,
    blur_validate_date,
    click_spouse_type_1_clear_then_process,
    click_spouse_type_2_clear_then_process,
    click_spouse_type_3_clear_then_process,
    click_enable_schedule1_then_itemized_filer,
    click_enable_schedule1_then_itemized_spouse,
    click_enable_schedule2_filer,
    click_enable_schedule2_spouse,
    click_itemized_filer,
    click_itemized_spouse,
    click_optional_filer,
    click_optional_spouse,
    click_process_amend,
    click_process_atc_filer,
    click_process_atc_spouse,
    click_process_tax_type_filer,
    key_down_date_mask,
    key_press_date_only,
    key_press_letter_number,
    key_press_numbers_only,
    key_press_numbers_with_negative,
    key_press_whole_number,
    key_up_go_to_page,
};

pub const Binding = struct {
    control_id: []const u8,
    source_line: u32,
    event: EventKind,
    fact: HandlerFact,
};

const FactGroup = struct {
    event: EventKind,
    fact: HandlerFact,
    control_ids: []const []const u8,
};

const blur_empty = [_][]const u8{
    "frm1701q:txtForeignTaxNumber",
    "frm1701q:txtSpouseForeignTaxNum",
    "txtFinalFlag",
    "txtEnroll",
};
const blur_year = [_][]const u8{"frm1701q:txtYear"};
const blur_uppercase = [_][]const u8{
    "frm1701q:txtTaxpayerName",
    "frm1701q:txtAddress",
    "frm1701q:txtAddress2",
    "frm1701q:txtCitizenship",
    "frm1701q:txtSpouseName",
    "frm1701q:txtSpouseCitizenship",
    "frm1701q:txtPg2TaxpayerName",
    "frm1701q:txtLOB",
};
const blur_round = [_][]const u8{
    "frm1701q:txtAmount32",
    "frm1701q:txtAmount33",
    "frm1701q:txtAmount34",
    "frm1701q:txtAmount35",
    "frm1701q:txt40A",
    "frm1701q:txt40B",
};
const blur_37a = [_][]const u8{"frm1701q:txt37A"};
const blur_36a = [_][]const u8{"frm1701q:txt36A"};
const blur_37b = [_][]const u8{"frm1701q:txt37B"};
const blur_36b = [_][]const u8{"frm1701q:txt36B"};
const blur_39a = [_][]const u8{"frm1701q:txt39A"};
const blur_39b = [_][]const u8{"frm1701q:txt39B"};
const blur_45a = [_][]const u8{
    "frm1701q:txt42A",
    "frm1701q:txt43A",
    "frm1701q:txt44A",
};
const blur_45b = [_][]const u8{
    "frm1701q:txt42B",
    "frm1701q:txt43B",
    "frm1701q:txt44B",
};
const blur_49a = [_][]const u8{
    "frm1701q:txt47A",
    "frm1701q:txt48A",
};
const blur_49b = [_][]const u8{
    "frm1701q:txt47B",
    "frm1701q:txt48B",
};
const blur_50a = [_][]const u8{"frm1701q:txt50A"};
const blur_50b = [_][]const u8{"frm1701q:txt50B"};
const blur_62a = [_][]const u8{
    "frm1701q:txt55A",
    "frm1701q:txt56A",
    "frm1701q:txt57A",
    "frm1701q:txt58A",
    "frm1701q:txt59A",
    "frm1701q:txt60A",
    "frm1701q:txt61A",
};
const blur_62b = [_][]const u8{
    "frm1701q:txt55B",
    "frm1701q:txt56B",
    "frm1701q:txt57B",
    "frm1701q:txt58B",
    "frm1701q:txt59B",
    "frm1701q:txt60B",
    "frm1701q:txt61B",
};
const blur_67a = [_][]const u8{
    "frm1701q:txt64A",
    "frm1701q:txt65A",
    "frm1701q:txt66A",
};
const blur_67b = [_][]const u8{
    "frm1701q:txt64B",
    "frm1701q:txt65B",
    "frm1701q:txt66B",
};
const blur_52a = [_][]const u8{"frm1701q:txt52A"};
const blur_52b = [_][]const u8{"frm1701q:txt52B"};
const dates = [_][]const u8{
    "frm1701q:txtDate32",
    "frm1701q:txtDate33",
    "frm1701q:txtDate34",
    "frm1701q:txtDate35",
};

const click_empty = [_][]const u8{
    "frm1701q:optForeignTaxCredits_1",
    "frm1701q:optForeignTaxCredits_2",
    "frm1701q:optSpouseForeignTaxCred_1",
    "frm1701q:optSpouseForeignTaxCred_2",
};
const spouse_type_1 = [_][]const u8{"frm1701q:optSpouseType_1"};
const spouse_type_2 = [_][]const u8{"frm1701q:optSpouseType_2"};
const spouse_type_3 = [_][]const u8{"frm1701q:optSpouseType_3"};
const graduated_filer = [_][]const u8{"frm1701q:optTaxRate_1"};
const graduated_spouse = [_][]const u8{"frm1701q:optSpouseTaxRate_1"};
const percentage_filer = [_][]const u8{"frm1701q:optTaxRate_2"};
const percentage_spouse = [_][]const u8{"frm1701q:optSpouseTaxRate_2"};
const itemized_filer = [_][]const u8{"frm1701q:optMethodOfDeduction:_1"};
const itemized_spouse = [_][]const u8{"frm1701q:optSpouseMethod:_1"};
const optional_filer = [_][]const u8{"frm1701q:optMethodOfDeduction:_2"};
const optional_spouse = [_][]const u8{"frm1701q:optSpouseMethod:_2"};
const amended = [_][]const u8{
    "frm1701q:AmendedRtn_1",
    "frm1701q:AmendedRtn_2",
};
const filer_atc = [_][]const u8{
    "frm1701q:optATC_1",
    "frm1701q:optATC_2",
    "frm1701q:optATC_3",
    "frm1701q:optATC_4",
    "frm1701q:optATC_5",
    "frm1701q:optATC_6",
};
const spouse_atc = [_][]const u8{
    "frm1701q:optSpouseATC_1",
    "frm1701q:optSpouseATC_2",
    "frm1701q:optSpouseATC_3",
    "frm1701q:optSpouseATC_4",
    "frm1701q:optSpouseATC_5",
    "frm1701q:optSpouseATC_6",
    "frm1701q:optSpouseATC_7",
};
const filer_type = [_][]const u8{
    "frm1701q:optType_1",
    "frm1701q:optType_2",
    "frm1701q:optType_3",
    "frm1701q:optType_4",
};

const key_press_empty = [_][]const u8{
    "frm1701q:txtCitizenship",
    "frm1701q:txtSpouseCitizenship",
    "txtFinalFlag",
    "txtEnroll",
};
const key_press_letter_number = [_][]const u8{
    "frm1701q:txtBranchCode",
    "frm1701q:txtForeignTaxNumber",
    "frm1701q:txtSpouseBranchCode",
    "frm1701q:txtSpouseForeignTaxNum",
    "frm1701q:txtPg2BranchCode",
};
const key_press_numbers_only = [_][]const u8{
    "frm1701q:txtAmount32",
    "frm1701q:txtAmount33",
    "frm1701q:txtAmount34",
    "frm1701q:txtAmount35",
};
const key_press_negative = [_][]const u8{
    "frm1701q:txt42A",
    "frm1701q:txt42B",
    "frm1701q:txt50A",
    "frm1701q:txt50B",
};
const key_press_whole = [_][]const u8{
    "frm1701q:txtYear",
    "frm1701q:txtSheets",
    "frm1701q:txtTIN1",
    "frm1701q:txtTIN2",
    "frm1701q:txtTIN3",
    "frm1701q:txtZipCode",
    "frm1701q:txtBirthMonth",
    "frm1701q:txtBirthDay",
    "frm1701q:txtBirthYear",
    "frm1701q:txtSpouseTIN1",
    "frm1701q:txtSpouseTIN2",
    "frm1701q:txtSpouseTIN3",
    "frm1701q:txt26A",
    "frm1701q:txt26B",
    "frm1701q:txt27A",
    "frm1701q:txt27B",
    "frm1701q:txt29A",
    "frm1701q:txt29B",
    "frm1701q:txt31",
    "frm1701q:txtPg2TIN1",
    "frm1701q:txtPg2TIN2",
    "frm1701q:txtPg2TIN3",
    "frm1701q:txt36A",
    "frm1701q:txt36B",
    "frm1701q:txt37A",
    "frm1701q:txt37B",
    "frm1701q:txt39A",
    "frm1701q:txt39B",
    "frm1701q:txt40A",
    "frm1701q:txt40B",
    "frm1701q:txt43A",
    "frm1701q:txt43B",
    "frm1701q:txt44A",
    "frm1701q:txt44B",
    "frm1701q:txt47A",
    "frm1701q:txt47B",
    "frm1701q:txt48A",
    "frm1701q:txt48B",
    "frm1701q:txt52A",
    "frm1701q:txt52B",
    "frm1701q:txt55A",
    "frm1701q:txt55B",
    "frm1701q:txt56A",
    "frm1701q:txt56B",
    "frm1701q:txt57A",
    "frm1701q:txt57B",
    "frm1701q:txt58A",
    "frm1701q:txt58B",
    "frm1701q:txt59A",
    "frm1701q:txt59B",
    "frm1701q:txt60A",
    "frm1701q:txt60B",
    "frm1701q:txt61A",
    "frm1701q:txt61B",
    "frm1701q:txt64A",
    "frm1701q:txt64B",
    "frm1701q:txt65A",
    "frm1701q:txt65B",
    "frm1701q:txt66A",
    "frm1701q:txt66B",
    "frm1701q:txtTelno",
};
const current_page = [_][]const u8{"frm1701q:txtCurrentPage"};

pub const groups = [_]FactGroup{
    .{ .event = .blur, .fact = .empty_attribute, .control_ids = &blur_empty },
    .{ .event = .blur, .fact = .blur_year_normalize_compute46_validate_compute46, .control_ids = &blur_year },
    .{ .event = .blur, .fact = .blur_global_uppercase, .control_ids = &blur_uppercase },
    .{ .event = .blur, .fact = .blur_round, .control_ids = &blur_round },
    .{ .event = .blur, .fact = .blur_round_compute38_filer, .control_ids = &blur_37a },
    .{ .event = .blur, .fact = .blur_round_compute38_compute40_filer, .control_ids = &blur_36a },
    .{ .event = .blur, .fact = .blur_round_compute38_spouse, .control_ids = &blur_37b },
    .{ .event = .blur, .fact = .blur_round_compute38_compute40_spouse, .control_ids = &blur_36b },
    .{ .event = .blur, .fact = .blur_round_compute41_filer, .control_ids = &blur_39a },
    .{ .event = .blur, .fact = .blur_round_compute41_spouse, .control_ids = &blur_39b },
    .{ .event = .blur, .fact = .blur_round_compute45_filer, .control_ids = &blur_45a },
    .{ .event = .blur, .fact = .blur_round_compute45_spouse, .control_ids = &blur_45b },
    .{ .event = .blur, .fact = .blur_round_compute49_filer, .control_ids = &blur_49a },
    .{ .event = .blur, .fact = .blur_round_compute49_spouse, .control_ids = &blur_49b },
    .{ .event = .blur, .fact = .blur_round_compute51_filer, .control_ids = &blur_50a },
    .{ .event = .blur, .fact = .blur_round_compute51_spouse, .control_ids = &blur_50b },
    .{ .event = .blur, .fact = .blur_round_compute62_filer, .control_ids = &blur_62a },
    .{ .event = .blur, .fact = .blur_round_compute62_spouse, .control_ids = &blur_62b },
    .{ .event = .blur, .fact = .blur_round_compute67_filer, .control_ids = &blur_67a },
    .{ .event = .blur, .fact = .blur_round_compute67_spouse, .control_ids = &blur_67b },
    .{ .event = .blur, .fact = .blur_round_validate_item52_compute53_filer, .control_ids = &blur_52a },
    .{ .event = .blur, .fact = .blur_round_validate_item52_compute53_spouse, .control_ids = &blur_52b },
    .{ .event = .blur, .fact = .blur_validate_date, .control_ids = &dates },

    .{ .event = .click, .fact = .empty_attribute, .control_ids = &click_empty },
    .{ .event = .click, .fact = .click_spouse_type_1_clear_then_process, .control_ids = &spouse_type_1 },
    .{ .event = .click, .fact = .click_spouse_type_2_clear_then_process, .control_ids = &spouse_type_2 },
    .{ .event = .click, .fact = .click_spouse_type_3_clear_then_process, .control_ids = &spouse_type_3 },
    .{ .event = .click, .fact = .click_enable_schedule1_then_itemized_filer, .control_ids = &graduated_filer },
    .{ .event = .click, .fact = .click_enable_schedule1_then_itemized_spouse, .control_ids = &graduated_spouse },
    .{ .event = .click, .fact = .click_enable_schedule2_filer, .control_ids = &percentage_filer },
    .{ .event = .click, .fact = .click_enable_schedule2_spouse, .control_ids = &percentage_spouse },
    .{ .event = .click, .fact = .click_itemized_filer, .control_ids = &itemized_filer },
    .{ .event = .click, .fact = .click_itemized_spouse, .control_ids = &itemized_spouse },
    .{ .event = .click, .fact = .click_optional_filer, .control_ids = &optional_filer },
    .{ .event = .click, .fact = .click_optional_spouse, .control_ids = &optional_spouse },
    .{ .event = .click, .fact = .click_process_amend, .control_ids = &amended },
    .{ .event = .click, .fact = .click_process_atc_filer, .control_ids = &filer_atc },
    .{ .event = .click, .fact = .click_process_atc_spouse, .control_ids = &spouse_atc },
    .{ .event = .click, .fact = .click_process_tax_type_filer, .control_ids = &filer_type },

    .{ .event = .key_down, .fact = .key_down_date_mask, .control_ids = &dates },
    .{ .event = .key_press, .fact = .empty_attribute, .control_ids = &key_press_empty },
    .{ .event = .key_press, .fact = .key_press_date_only, .control_ids = &dates },
    .{ .event = .key_press, .fact = .key_press_letter_number, .control_ids = &key_press_letter_number },
    .{ .event = .key_press, .fact = .key_press_numbers_only, .control_ids = &key_press_numbers_only },
    .{ .event = .key_press, .fact = .key_press_numbers_with_negative, .control_ids = &key_press_negative },
    .{ .event = .key_press, .fact = .key_press_whole_number, .control_ids = &key_press_whole },
    .{ .event = .key_up, .fact = .key_up_go_to_page, .control_ids = &current_page },
};

pub fn find(control_id: []const u8, event: EventKind) ?Binding {
    for (groups) |group| {
        if (group.event != event) continue;
        for (group.control_ids) |candidate| {
            if (!std.mem.eql(u8, candidate, control_id)) continue;
            const declaration = control_contract.find(control_id) orelse
                unreachable;
            return .{
                .control_id = candidate,
                .source_line = declaration.source_line,
                .event = event,
                .fact = group.fact,
            };
        }
    }
    return null;
}

pub fn isEmpty(fact: HandlerFact) bool {
    return fact == .empty_attribute;
}

test "all 184 observed attributes and 123 controls are covered exactly once" {
    var binding_count: usize = 0;
    var empty_count: usize = 0;
    var control_seen = [_]bool{false} ** occurrences.control_seeds.len;
    var event_counts = [_]usize{0} ** @typeInfo(EventKind).@"enum".fields.len;

    for (groups, 0..) |group, group_index| {
        for (group.control_ids) |control_id| {
            const declaration = control_contract.find(control_id) orelse
                return error.UnknownEventControl;
            _ = declaration;
            binding_count += 1;
            event_counts[@intFromEnum(group.event)] += 1;
            if (isEmpty(group.fact)) empty_count += 1;

            var occurrence_index: ?usize = null;
            for (occurrences.control_seeds, 0..) |seed, index| {
                if (std.mem.eql(u8, seed.id, control_id)) {
                    occurrence_index = index;
                    break;
                }
            }
            control_seen[
                occurrence_index orelse
                    return error.UnknownEventOccurrence
            ] = true;

            for (groups[0..group_index]) |earlier_group| {
                if (earlier_group.event != group.event) continue;
                for (earlier_group.control_ids) |earlier_id| {
                    try std.testing.expect(!std.mem.eql(
                        u8,
                        earlier_id,
                        control_id,
                    ));
                }
            }
        }
    }

    var observed_controls: usize = 0;
    for (control_seen) |seen| {
        if (seen) observed_controls += 1;
    }
    try std.testing.expectEqual(observed_binding_count, binding_count);
    try std.testing.expectEqual(observed_control_count, observed_controls);
    try std.testing.expectEqual(empty_binding_count, empty_count);
    try std.testing.expectEqual(
        non_empty_binding_count,
        binding_count - empty_count,
    );
    try std.testing.expectEqual(@as(usize, 63), event_counts[@intFromEnum(EventKind.blur)]);
    try std.testing.expectEqual(@as(usize, 34), event_counts[@intFromEnum(EventKind.click)]);
    try std.testing.expectEqual(@as(usize, 4), event_counts[@intFromEnum(EventKind.key_down)]);
    try std.testing.expectEqual(@as(usize, 82), event_counts[@intFromEnum(EventKind.key_press)]);
    try std.testing.expectEqual(@as(usize, 1), event_counts[@intFromEnum(EventKind.key_up)]);
}

test "lookup returns source lines and preserves intentional empty attributes" {
    const year = find("frm1701q:txtYear", .blur).?;
    try std.testing.expectEqual(@as(u32, 271), year.source_line);
    try std.testing.expectEqual(
        HandlerFact.blur_year_normalize_compute46_validate_compute46,
        year.fact,
    );

    const empty_click = find(
        "frm1701q:optForeignTaxCredits_1",
        .click,
    ).?;
    try std.testing.expectEqual(@as(u32, 633), empty_click.source_line);
    try std.testing.expect(isEmpty(empty_click.fact));
    try std.testing.expect(find("frm1701q:DateQuarter_1", .click) == null);
}

test "explicitly unqualified interactive grammars remain fail closed" {
    try std.testing.expect(!arbitrary_pre_blur_money_grammar_qualified);
    try std.testing.expect(!key_by_key_filtering_qualified);
    try std.testing.expect(!date_key_masking_qualified);
    try std.testing.expect(!current_page_navigation_qualified);
}
