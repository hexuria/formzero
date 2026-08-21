//! Exact, value-free event-attribute inventory for the 98 static controls
//! in Offline eBIRForms 7.9.6 Form 1601EQ January 2018 (ENCS).
//!
//! This is a declaration contract, not copied JavaScript and not a
//! handler implementation. Each fact names the observable inline
//! pipeline attached in the verified HTA. Empty attributes are retained
//! deliberately: excluding them changes the evidence count from 67
//! bindings on 59 controls to 58 non-empty bindings on 52 controls.

const std = @import("std");
const control_contract = @import("control_contract.zig");
const occurrences = @import("occurrences.zig");
const evidence = @import("evidence.zig");

pub const evidence_id = control_contract.evidence_id;
pub const observed_binding_count: usize = 67;
pub const observed_control_count: usize = 59;
pub const non_empty_binding_count: usize = 58;
pub const empty_binding_count: usize = 9;
pub const handlers_implemented = false;

pub const EventKind = enum {
    blur,
    click,
    change,
    key_press,
};

/// A semantic fingerprint of the complete inline attribute. Repeated
/// facts mean the source attached the same pipeline to each listed control.
pub const HandlerFact = enum {
    empty_attribute,
    click_navigate_bir_forms,
    click_save_xml_false,
    click_window_print,
    click_window_close,
    key_press_whole_number_semicolon,
    change_year,
    click_enable_item22,
    click_zero_item22_compute_total_tax_credit,
    click_tax_withheld_yes_flag,
    click_tax_withheld_no,
    key_press_whole_number,
    key_press_letter_number,
    blur_global_uppercase,
    click_change_category,
    key_press_numbers_only,
    blur_round_compute_total_tax_credit,
    blur_round_compute_penalties,
    click_check_refund,
    click_check_issue_cert,
    click_check_carried_over,
    click_validate_form,
    click_enable_all_control,
    click_printme,
    click_open_alert_email,
    click_get_atc_code,
    click_print_modal,
    click_close_other_selected_tax,
    click_clear_part2,
    click_import_files,
    click_cancel_import_modal,
    click_send_email,
    click_hide_confirm_online,
    click_hide_tosa_disable_dropdown,
    click_send_email_hide_enroll,
    click_hide_enroll,
    click_show_ebir_online,
    click_show_ebir_enroll,
    click_validate_user_pass,
    click_hide_ebir_online,
    click_export_tp_files_check_final_copy,
    click_cancel_export_check_final_copy,
};

pub const Binding = struct {
    ordinal: u16,
    control_id: ?[]const u8,
    source_line: u32,
    event: EventKind,
    fact: HandlerFact,
};

const FactGroup = struct {
    event: EventKind,
    fact: HandlerFact,
    ordinals: []const u16,
};

const g1_click_click_navigate_bir_forms = [_]u16{
    1,
};

const g2_click_click_save_xml_false = [_]u16{
    2, 69,
};

const g3_click_click_window_print = [_]u16{
    3,
};

const g4_click_click_window_close = [_]u16{
    4,
};

const g5_key_press_key_press_whole_number_semicolon = [_]u16{
    6,
};

const g6_change_change_year = [_]u16{
    6,
};

const g7_blur_empty_attribute = [_]u16{
    6, 79, 80,
};

const g8_click_empty_attribute = [_]u16{
    7, 8, 9, 10,
};

const g9_click_click_enable_item22 = [_]u16{
    11,
};

const g10_click_click_zero_item22_compute_total_tax_credit = [_]u16{
    12,
};

const g11_click_click_tax_withheld_yes_flag = [_]u16{
    13,
};

const g12_click_click_tax_withheld_no = [_]u16{
    14,
};

const g13_key_press_key_press_whole_number = [_]u16{
    15, 16, 17, 18, 24, 25,
};

const g14_key_press_key_press_letter_number = [_]u16{
    19,
};

const g15_blur_blur_global_uppercase = [_]u16{
    20, 22, 23,
};

const g16_click_click_change_category = [_]u16{
    26, 27,
};

const g17_key_press_key_press_numbers_only = [_]u16{
    31, 32, 33, 34,
};

const g18_blur_blur_round_compute_total_tax_credit = [_]u16{
    31, 32, 33, 34,
};

const g19_blur_blur_round_compute_penalties = [_]u16{
    37, 39, 40,
};

const g20_click_click_check_refund = [_]u16{
    43,
};

const g21_click_click_check_issue_cert = [_]u16{
    44,
};

const g22_click_click_check_carried_over = [_]u16{
    45,
};

const g23_click_click_validate_form = [_]u16{
    66,
};

const g24_click_click_enable_all_control = [_]u16{
    67,
};

const g25_click_click_printme = [_]u16{
    70,
};

const g26_click_click_open_alert_email = [_]u16{
    71,
};

const g27_click_click_get_atc_code = [_]u16{
    72,
};

const g28_click_click_print_modal = [_]u16{
    74,
};

const g29_click_click_close_other_selected_tax = [_]u16{
    75,
};

const g30_click_click_clear_part2 = [_]u16{
    76,
};

const g31_click_click_import_files = [_]u16{
    77,
};

const g32_click_click_cancel_import_modal = [_]u16{
    78,
};

const g33_key_press_empty_attribute = [_]u16{
    79, 80,
};

const g34_click_click_send_email = [_]u16{
    83,
};

const g35_click_click_hide_confirm_online = [_]u16{
    84,
};

const g36_click_click_hide_tosa_disable_dropdown = [_]u16{
    85,
};

const g37_click_click_send_email_hide_enroll = [_]u16{
    86,
};

const g38_click_click_hide_enroll = [_]u16{
    87,
};

const g39_click_click_show_ebir_online = [_]u16{
    88,
};

const g40_click_click_show_ebir_enroll = [_]u16{
    89,
};

const g41_click_click_validate_user_pass = [_]u16{
    93,
};

const g42_click_click_hide_ebir_online = [_]u16{
    94,
};

const g43_click_click_export_tp_files_check_final_copy = [_]u16{
    96,
};

const g44_click_click_cancel_export_check_final_copy = [_]u16{
    97,
};

pub const groups = [_]FactGroup{
    .{ .event = .click, .fact = .click_navigate_bir_forms, .ordinals = &g1_click_click_navigate_bir_forms },
    .{ .event = .click, .fact = .click_save_xml_false, .ordinals = &g2_click_click_save_xml_false },
    .{ .event = .click, .fact = .click_window_print, .ordinals = &g3_click_click_window_print },
    .{ .event = .click, .fact = .click_window_close, .ordinals = &g4_click_click_window_close },
    .{ .event = .key_press, .fact = .key_press_whole_number_semicolon, .ordinals = &g5_key_press_key_press_whole_number_semicolon },
    .{ .event = .change, .fact = .change_year, .ordinals = &g6_change_change_year },
    .{ .event = .blur, .fact = .empty_attribute, .ordinals = &g7_blur_empty_attribute },
    .{ .event = .click, .fact = .empty_attribute, .ordinals = &g8_click_empty_attribute },
    .{ .event = .click, .fact = .click_enable_item22, .ordinals = &g9_click_click_enable_item22 },
    .{ .event = .click, .fact = .click_zero_item22_compute_total_tax_credit, .ordinals = &g10_click_click_zero_item22_compute_total_tax_credit },
    .{ .event = .click, .fact = .click_tax_withheld_yes_flag, .ordinals = &g11_click_click_tax_withheld_yes_flag },
    .{ .event = .click, .fact = .click_tax_withheld_no, .ordinals = &g12_click_click_tax_withheld_no },
    .{ .event = .key_press, .fact = .key_press_whole_number, .ordinals = &g13_key_press_key_press_whole_number },
    .{ .event = .key_press, .fact = .key_press_letter_number, .ordinals = &g14_key_press_key_press_letter_number },
    .{ .event = .blur, .fact = .blur_global_uppercase, .ordinals = &g15_blur_blur_global_uppercase },
    .{ .event = .click, .fact = .click_change_category, .ordinals = &g16_click_click_change_category },
    .{ .event = .key_press, .fact = .key_press_numbers_only, .ordinals = &g17_key_press_key_press_numbers_only },
    .{ .event = .blur, .fact = .blur_round_compute_total_tax_credit, .ordinals = &g18_blur_blur_round_compute_total_tax_credit },
    .{ .event = .blur, .fact = .blur_round_compute_penalties, .ordinals = &g19_blur_blur_round_compute_penalties },
    .{ .event = .click, .fact = .click_check_refund, .ordinals = &g20_click_click_check_refund },
    .{ .event = .click, .fact = .click_check_issue_cert, .ordinals = &g21_click_click_check_issue_cert },
    .{ .event = .click, .fact = .click_check_carried_over, .ordinals = &g22_click_click_check_carried_over },
    .{ .event = .click, .fact = .click_validate_form, .ordinals = &g23_click_click_validate_form },
    .{ .event = .click, .fact = .click_enable_all_control, .ordinals = &g24_click_click_enable_all_control },
    .{ .event = .click, .fact = .click_printme, .ordinals = &g25_click_click_printme },
    .{ .event = .click, .fact = .click_open_alert_email, .ordinals = &g26_click_click_open_alert_email },
    .{ .event = .click, .fact = .click_get_atc_code, .ordinals = &g27_click_click_get_atc_code },
    .{ .event = .click, .fact = .click_print_modal, .ordinals = &g28_click_click_print_modal },
    .{ .event = .click, .fact = .click_close_other_selected_tax, .ordinals = &g29_click_click_close_other_selected_tax },
    .{ .event = .click, .fact = .click_clear_part2, .ordinals = &g30_click_click_clear_part2 },
    .{ .event = .click, .fact = .click_import_files, .ordinals = &g31_click_click_import_files },
    .{ .event = .click, .fact = .click_cancel_import_modal, .ordinals = &g32_click_click_cancel_import_modal },
    .{ .event = .key_press, .fact = .empty_attribute, .ordinals = &g33_key_press_empty_attribute },
    .{ .event = .click, .fact = .click_send_email, .ordinals = &g34_click_click_send_email },
    .{ .event = .click, .fact = .click_hide_confirm_online, .ordinals = &g35_click_click_hide_confirm_online },
    .{ .event = .click, .fact = .click_hide_tosa_disable_dropdown, .ordinals = &g36_click_click_hide_tosa_disable_dropdown },
    .{ .event = .click, .fact = .click_send_email_hide_enroll, .ordinals = &g37_click_click_send_email_hide_enroll },
    .{ .event = .click, .fact = .click_hide_enroll, .ordinals = &g38_click_click_hide_enroll },
    .{ .event = .click, .fact = .click_show_ebir_online, .ordinals = &g39_click_click_show_ebir_online },
    .{ .event = .click, .fact = .click_show_ebir_enroll, .ordinals = &g40_click_click_show_ebir_enroll },
    .{ .event = .click, .fact = .click_validate_user_pass, .ordinals = &g41_click_click_validate_user_pass },
    .{ .event = .click, .fact = .click_hide_ebir_online, .ordinals = &g42_click_click_hide_ebir_online },
    .{ .event = .click, .fact = .click_export_tp_files_check_final_copy, .ordinals = &g43_click_click_export_tp_files_check_final_copy },
    .{ .event = .click, .fact = .click_cancel_export_check_final_copy, .ordinals = &g44_click_click_cancel_export_check_final_copy },
};

pub fn isEmpty(fact: HandlerFact) bool {
    return fact == .empty_attribute;
}

pub fn find(ordinal: u16, event: EventKind) ?Binding {
    for (groups) |group| {
        if (group.event != event) continue;
        for (group.ordinals) |candidate| {
            if (candidate != ordinal) continue;
            const seed = occurrences.control_seeds[ordinal - 1];
            return .{
                .ordinal = ordinal,
                .control_id = seed.id,
                .source_line = seed.source_line,
                .event = event,
                .fact = group.fact,
            };
        }
    }
    return null;
}

pub fn findById(control_id: []const u8, event: EventKind) ?Binding {
    for (occurrences.control_seeds) |seed| {
        const id = seed.id orelse continue;
        if (!std.mem.eql(u8, id, control_id)) continue;
        return find(seed.ordinal, event);
    }
    return null;
}

test "all 67 observed attributes and 59 controls are covered exactly once" {
    var binding_count: usize = 0;
    var empty_count: usize = 0;
    var control_seen = [_]bool{false} ** occurrences.control_seeds.len;
    var event_counts = [_]usize{0} ** @typeInfo(EventKind).@"enum".fields.len;

    for (groups, 0..) |group, group_index| {
        for (group.ordinals) |ordinal| {
            if (ordinal == 0 or ordinal > occurrences.control_seeds.len) {
                return error.UnknownEventOrdinal;
            }
            binding_count += 1;
            event_counts[@intFromEnum(group.event)] += 1;
            if (isEmpty(group.fact)) empty_count += 1;
            control_seen[ordinal - 1] = true;
            for (groups[0..group_index]) |earlier| {
                if (earlier.event != group.event) continue;
                for (earlier.ordinals) |earlier_ordinal| {
                    try std.testing.expect(earlier_ordinal != ordinal);
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
    try std.testing.expectEqual(non_empty_binding_count, binding_count - empty_count);
    try std.testing.expectEqual(@as(usize, 13), event_counts[@intFromEnum(EventKind.blur)]);
    try std.testing.expectEqual(@as(usize, 39), event_counts[@intFromEnum(EventKind.click)]);
    try std.testing.expectEqual(@as(usize, 1), event_counts[@intFromEnum(EventKind.change)]);
    try std.testing.expectEqual(@as(usize, 14), event_counts[@intFromEnum(EventKind.key_press)]);
    try std.testing.expect(!handlers_implemented);
    try std.testing.expect(!occurrences.serializer_reviewed);
    try std.testing.expect(!evidence.readiness.identityReady());
}

test "1601EQ year control keeps change, whole-number keypress, and empty blur" {
    const year = occurrences.control_seeds[5];
    try std.testing.expectEqualStrings("frm1601EQ:txtYear", year.id.?);
    try std.testing.expectEqual(
        HandlerFact.key_press_whole_number_semicolon,
        find(year.ordinal, .key_press).?.fact,
    );
    try std.testing.expectEqual(HandlerFact.change_year, find(year.ordinal, .change).?.fact);
    try std.testing.expectEqual(HandlerFact.empty_attribute, find(year.ordinal, .blur).?.fact);
}

test "1601EQ chrome Save shares saveXML(false) with btnSave and Print stays window.print" {
    try std.testing.expectEqual(HandlerFact.click_save_xml_false, find(2, .click).?.fact);
    try std.testing.expectEqual(
        HandlerFact.click_save_xml_false,
        findById("btnSave", .click).?.fact,
    );
    try std.testing.expectEqual(HandlerFact.click_window_print, find(3, .click).?.fact);
    try std.testing.expectEqual(HandlerFact.click_printme, findById("btnPrint", .click).?.fact);
}

test "1601EQ amended radios and over-remittance clicks keep distinct pipelines" {
    try std.testing.expectEqual(
        HandlerFact.click_enable_item22,
        findById("frm1601EQ:optAmend:Y", .click).?.fact,
    );
    try std.testing.expectEqual(
        HandlerFact.click_zero_item22_compute_total_tax_credit,
        findById("frm1601EQ:optAmend:N", .click).?.fact,
    );
    try std.testing.expectEqual(
        HandlerFact.click_check_refund,
        findById("frm1601EQ:ifRefund", .click).?.fact,
    );
    try std.testing.expectEqual(
        HandlerFact.click_validate_form,
        findById("frm1601EQ:cmdValidate", .click).?.fact,
    );
    try std.testing.expect(findById("frm1601EQ:txtAtcCd1", .click) == null);
}
