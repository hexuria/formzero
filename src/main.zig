//! eBIRForms application state and Native SDK wiring.
//!
//! The screens remain declarative `.native` templates. Zig owns the small
//! application state: navigation, appearance and accessibility preferences,
//! plus the tested calendar resolver, SQLite policy store, and native
//! calendar-handoff effects.

const std = @import("std");
const builtin = @import("builtin");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const multi_select = @import("components/multi_select.zig");
const segmented_tin = @import("components/segmented_tin.zig");
const calendar_domain = @import("calendar/domain.zig");
const calendar_marker = @import("calendar/marker.zig");
const calendar_ui = @import("calendar/ui_state.zig");
const period_name = @import("domain/period_name.zig");
const global_dashboard_ui = @import("global_dashboard/ui_state.zig");
const news_domain = @import("news/domain.zig");
const news_feed = @import("news/feed.zig");
const news_store = @import("news/store.zig");
const news_ui = @import("news/ui_state.zig");
const profile_ui = @import("tax_profile/ui_state.zig");
const rdo_reference = @import("tax_profile/rdo_reference.zig");
const profile_store = @import("tax_profile/store.zig");
const profile_persistence = @import("tax_profile/persistence_adapter.zig");
const profile_editor = @import("tax_profile/editor.zig");
const profile_fields = @import("tax_profile/field.zig");
const profile_model = @import("tax_profile/model.zig");
const profile_projection = @import("tax_profile/projection.zig");
const profile_applicability = @import("tax_profile/applicability.zig");
const profile_registration = @import("tax_profile/registration.zig");
const profile_registration_adapter = @import(
    "tax_profile/registration_adapter.zig",
);
const profile_registration_ui = @import("tax_profile/registration_ui.zig");
const tax_form_profile_domain = @import("tax_profile/tax_form_profile.zig");
const tax_form_profile_binding_resolver = @import(
    "tax_profile/tax_form_profile_binding_resolver.zig",
);
const tax_form_profile_ui = @import(
    "tax_profile/tax_form_profile_ui.zig",
);
const forms_set_resolver = @import("tax_profile/forms_set_resolver.zig");
const taxpayer_year_settings_domain = @import(
    "tax_profile/taxpayer_year_settings.zig",
);
const taxpayer_year_ui = @import("tax_profile/taxpayer_year_ui.zig");
const annual_income_tax_election = @import(
    "tax_profile/annual_income_tax_election.zig",
);
const composed_tax_profile = @import(
    "tax_profile/composed_tax_profile.zig",
);
const forms_set_history = @import("tax_profile/forms_set_history.zig");
const form_ui = @import("forms/ui_state.zig");
const draft_provenance = @import("forms/draft_provenance.zig");
const draft_provenance_adapter = @import(
    "forms/draft_provenance_adapter.zig",
);
const draft_provenance_runtime = @import(
    "forms/draft_provenance_runtime.zig",
);
const form_ids = @import("forms/id.zig");
const form_persistence = @import("forms/persistence_adapter.zig");
const form_runtime = @import("forms/runtime.zig");
const form_period = @import("forms/filing_period.zig");
const form_catalog = @import("forms/generated/catalog.zig");
const library_view = @import("forms/library_view.zig");
const income_tax_ui = @import("forms/income_tax_ui_state.zig");
const key_custody = @import("security/key_custody.zig");
const exact_1701q_native = @import(
    "forms/form_1701q_exact_native_state.zig",
);
const exact_1701q_runtime = @import(
    "forms/form_1701q_exact_runtime.zig",
);
const exact_1701q_ui = @import(
    "forms/form_1701q_exact_ui_state.zig",
);
const percentage_tax_ui = @import("forms/percentage_tax_ui_state.zig");
const c_time = @cImport({
    @cInclude("time.h");
});

comptime {
    _ = profile_applicability;
    _ = profile_registration;
    _ = profile_registration_adapter;
    _ = profile_registration_ui;
    _ = tax_form_profile_domain;
    _ = tax_form_profile_binding_resolver;
    _ = tax_form_profile_ui;
    _ = forms_set_resolver;
    _ = taxpayer_year_settings_domain;
    _ = taxpayer_year_ui;
    _ = annual_income_tax_election;
    _ = composed_tax_profile;
    _ = forms_set_history;
    _ = draft_provenance;
    _ = draft_provenance_adapter;
    _ = draft_provenance_runtime;
}

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

// The tax form library's presentation vocabulary now lives in
// `forms/library_view.zig`, and calendar/date presentation in
// `calendar/marker.zig` and `domain/period_name.zig`. The row and cell types
// stay re-exported here because the model contract binds markup to them
// through this module.
pub const LibraryPeriodFilter = library_view.LibraryPeriodFilter;
pub const TaxFormLibraryPeriodCell = library_view.TaxFormLibraryPeriodCell;
pub const TaxFormLibraryRow = library_view.TaxFormLibraryRow;
pub const LibraryOnDemandFilterRow = library_view.LibraryOnDemandFilterRow;
pub const LibraryCategoryFilterRow = library_view.LibraryCategoryFilterRow;
pub const LibraryMonthFilterRow = library_view.LibraryMonthFilterRow;

const taxCategoryLabel = library_view.taxCategoryLabel;
const filingLifecycleLabel = library_view.filingLifecycleLabel;
const filingLifecycleTone = library_view.filingLifecycleTone;
const compactPeriodStatus = library_view.compactPeriodStatus;
const periodStatusColor = library_view.periodStatusColor;
const firstSelectedMonth = library_view.firstSelectedMonth;
const firstSelectedQuarter = library_view.firstSelectedQuarter;
const appendLibraryFilterLabelPart = library_view.appendLibraryFilterLabelPart;

const CalendarMarkerTone = calendar_marker.CalendarMarkerTone;
const deadlineMarker = calendar_marker.deadlineMarker;
const calendarMarkerTone = calendar_marker.calendarMarkerTone;

const fullMonthName = period_name.fullMonthName;
const shortMonthName = period_name.shortMonthName;
const shortQuarterName = period_name.shortQuarterName;

const calendar_icon = canvas.svg_icon.parseComptime(
    @embedFile("icons/calendar.svg"),
);
const mail_check_icon = canvas.svg_icon.parseComptime(
    @embedFile("icons/mail-check.svg"),
);
const printer_icon = canvas.svg_icon.parseComptime(
    @embedFile("icons/printer.svg"),
);
const upload_receipt_icon = canvas.svg_icon.parseComptime(
    @embedFile("icons/upload-receipt.svg"),
);
pub const app_icons = [_]canvas.icons.Entry{
    .{ .name = "calendar", .icon = &calendar_icon },
    .{ .name = "mail-check", .icon = &mail_check_icon },
    .{ .name = "printer", .icon = &printer_icon },
    .{ .name = "upload-receipt", .icon = &upload_receipt_icon },
};

const canvas_label = "main-canvas";
const window_width: f32 = 1225;
const window_height: f32 = 768;
/// Bounds the yearly setup combobox: every configured year plus the current
/// year, a short recent window, and one typed year.
const max_setup_year_options: usize = profile_ui.max_form_set_summaries + 8;
/// Unconfigured years offered without typing. Older years remain reachable by
/// typing a full year.
const setup_year_recent_window: i32 = 5;

/// Keeps the setup year list sorted newest-first without duplicates. The list
/// is short and bounded, so an insertion walk is cheaper than a sort plus a
/// separate dedupe pass.
fn insertYearDescending(list: []i32, count: *usize, year: i32) void {
    if (count.* == list.len) return;
    var index: usize = 0;
    while (index < count.*) : (index += 1) {
        if (list[index] == year) return;
        if (list[index] < year) break;
    }
    var shift = count.*;
    while (shift > index) : (shift -= 1) list[shift] = list[shift - 1];
    list[index] = year;
    count.* += 1;
}

const phone_breakpoint: f32 = 600;
const compact_shell_breakpoint: f32 = 768;
const rail_shell_breakpoint: f32 = 1320;
const taxpayer_two_lane_min_width: f32 = 740;
const taxpayer_three_lane_min_width: f32 = 974;
const global_calendar_lane_min_width: f32 = 320;
const global_calendar_lane_max_width: f32 = 560;
const profile_calendar_lane_max_width: f32 = 500;
const profile_deadline_table_min_width: f32 = 420;
const calendar_grid_gutters: f32 = 6;
const calendar_day_min_height: f32 = 44;
const global_calendar_two_column_day_max_height: f32 = 64;
const global_calendar_stacked_day_max_height: f32 = 56;
const profile_calendar_day_max_height: f32 = 72;
const compact_global_form_picker_width: f32 = 180;
const max_visible_global_form_rows: usize = 8;

const app_permissions = [_][]const u8{
    native_sdk.security.permission_command,
    native_sdk.security.permission_network,
    native_sdk.security.permission_view,
};
const shell_views = [_]native_sdk.ShellView{
    .{
        .label = canvas_label,
        .kind = .gpu_surface,
        .fill = true,
        .role = "eBIRForms application",
        .accessibility_label = "eBIRForms",
        .gpu_backend = .software,
        .gpu_pixel_format = .bgra8_unorm,
        .gpu_present_mode = .timer,
        .gpu_alpha_mode = .@"opaque",
        .gpu_color_space = .srgb,
        .gpu_vsync = true,
    },
};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = "main",
    .title = "eBIRForms",
    .width = window_width,
    .height = window_height,
    .min_width = 360,
    .min_height = 500,
    .restore_state = false,
    .restore_policy = .center_on_primary,
    .views = &shell_views,
}};
const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

pub const Page = enum {
    global_dashboard,
    taxpayer_dashboard,
    profile_setup,
    tax_form_profile,
    import_data,
    background_tasks,
    tax_calendar,
    settings,
    screen_gallery,
    form_0605,
    form_0619_e,
    form_0619_f,
    form_1601_c,
    form_1701,
    form_1701q,
    form_1702_rt,
    form_1702_mx,
    form_2550q,
    form_2551q,
    aux_lock_screen,
    aux_profile_auth,
    aux_admin_auth,
    aux_command_palette,
    aux_html_preview,
    aux_email_confirmation,
    aux_debug_log,
};

pub const ThemePreference = enum {
    system,
    light,
    dark,
};

pub const SidebarPreference = enum {
    expanded,
    rail,
    hidden,
};

pub const DashboardSection = enum {
    calendar,
    forms,
    profile_settings,
};

pub const ProfileSetupSection = enum {
    tax_profile,
    tax_forms,
    email,
};

const PendingProfileNavigation = union(enum) {
    page: Page,
    profile_section: ProfileSetupSection,
    dashboard_section: DashboardSection,
    taxpayer_slot: usize,
    new_taxpayer,
    add_branch,
};

const PendingTaxFormProfileNavigation = union(enum) {
    page: Page,
    return_context,
    taxpayer_slot: usize,
    new_taxpayer,
    add_branch,
    activation_segment: struct {
        form_index: usize,
        tax_year: u16,
        viewed_on: profile_model.Date,
        filing: ?form_period.FilingPeriod,
    },
};

const TaxpayerContextMutation = union(enum) {
    taxpayer_slot: usize,
    new_taxpayer,
    add_branch,
};

pub const TaxCalendarSection = enum {
    rules,
    overrides,
};

pub const BackgroundTasksSection = enum {
    jobs,
    logs,
};

pub const ViewportClass = enum {
    phone,
    compact,
    rail_narrow,
    rail_regular,
    desktop,
};

pub const TaxpayerDashboardLaneMode = enum {
    stacked,
    two_columns,
    three_columns,
};

const ProfileCalendarExportStatus = enum {
    idle,
    wrong_context,
    no_profile,
    unavailable,
    nothing_to_add,
    build_failed,
    writing,
    opening,
    opened,
    write_failed,
    opener_unavailable,
    unsupported_platform,
    open_failed,
};

const calendar_only_form_codes = [_][]const u8{
    "1606",
    "1621",
    "2550DS",
};

const calendar_form_codes = blk: {
    var codes: [
        form_catalog.forms.len +
            calendar_only_form_codes.len
    ][]const u8 = undefined;
    for (form_catalog.forms, 0..) |form, index| codes[index] = form.code;
    for (calendar_only_form_codes, 0..) |code, index| {
        codes[form_catalog.forms.len + index] = code;
    }
    break :blk codes;
};

fn calendarFormIndex(comptime wanted: []const u8) usize {
    inline for (calendar_form_codes, 0..) |code, index| {
        if (comptime std.mem.eql(u8, code, wanted)) return index;
    }
    @compileError("calendar selection references an unknown form code: " ++ wanted);
}

fn formCodesEquivalent(left: []const u8, right: []const u8) bool {
    var left_index: usize = 0;
    var right_index: usize = 0;
    while (true) {
        while (left_index < left.len and
            !std.ascii.isAlphanumeric(left[left_index]))
        {
            left_index += 1;
        }
        while (right_index < right.len and
            !std.ascii.isAlphanumeric(right[right_index]))
        {
            right_index += 1;
        }
        if (left_index == left.len or right_index == right.len) {
            return left_index == left.len and right_index == right.len;
        }
        if (std.ascii.toLower(left[left_index]) !=
            std.ascii.toLower(right[right_index])) return false;
        left_index += 1;
        right_index += 1;
    }
}

const max_rendered_form_options: usize = calendar_form_codes.len;
const GlobalDashboardState = global_dashboard_ui.State(
    calendar_form_codes.len,
    64,
);
const ProfileCalendarFormsState = multi_select.State(
    form_catalog.registry_count,
    96,
);

pub const CalendarFormOptionRow = struct {
    id: usize,
    label: []const u8,
    selected: bool,
};

pub const ProfileCalendarFormOptionRow = struct {
    id: usize,
    code: []const u8,
    title: []const u8,
    label: []const u8,
    selected: bool,
};

pub const ProfileCalendarDayCell = struct {
    id: usize,
    day: u8,
    deadline_count: usize,
    closed_flag: bool = false,
    overdue_flag: bool = false,
    due_soon_flag: bool = false,
    approaching_flag: bool = false,
    selected_flag: bool = false,

    pub fn blank(self: *const ProfileCalendarDayCell) bool {
        return self.day == 0;
    }

    pub fn dayLabel(
        self: *const ProfileCalendarDayCell,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.day == 0) return "";
        return std.fmt.allocPrint(arena, "{d}", .{self.day}) catch "";
    }

    pub fn actionLabel(
        self: *const ProfileCalendarDayCell,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.day == 0) return "Calendar padding day";
        if (self.deadline_count == 0) {
            return std.fmt.allocPrint(
                arena,
                "Day {d}, no deadlines",
                .{self.day},
            ) catch "Calendar day";
        }
        return std.fmt.allocPrint(
            arena,
            "Show {d} {s} for day {d}: {s}",
            .{
                self.deadline_count,
                deadlineNoun(self.deadline_count),
                self.day,
                self.markerStatusLabel(),
            },
        ) catch "Show deadlines";
    }

    fn markerStatusLabel(self: *const ProfileCalendarDayCell) []const u8 {
        if (self.closed_flag) return "paid";
        if (self.overdue_flag) return "overdue";
        if (self.due_soon_flag) return "due today or tomorrow";
        if (self.approaching_flag) return "due within seven days";
        return "due later";
    }

    pub fn marker(self: *const ProfileCalendarDayCell) []const u8 {
        return deadlineMarker(self.deadline_count);
    }

    pub fn hasDeadlines(self: *const ProfileCalendarDayCell) bool {
        return self.deadline_count != 0;
    }

    pub fn overdue(self: *const ProfileCalendarDayCell) bool {
        return self.overdue_flag;
    }

    pub fn closed(self: *const ProfileCalendarDayCell) bool {
        return self.closed_flag;
    }

    pub fn dueSoon(self: *const ProfileCalendarDayCell) bool {
        return self.due_soon_flag;
    }

    pub fn approaching(self: *const ProfileCalendarDayCell) bool {
        return self.approaching_flag;
    }

    pub fn selected(self: *const ProfileCalendarDayCell) bool {
        return self.selected_flag;
    }
};

pub const ProfileDeadlineTiming = enum {
    upcoming,
    due_today,
    overdue,
    closed,
};

pub const ProfileFilingState = enum {
    new,
    draft,
    queued,
    sent,
    confirmed,
    paid,
    calendar_only,
    unknown,

    fn isSavedOpen(self: ProfileFilingState) bool {
        return switch (self) {
            .draft, .queued, .sent, .confirmed => true,
            .new, .paid, .calendar_only, .unknown => false,
        };
    }

    fn needsAction(self: ProfileFilingState) bool {
        return switch (self) {
            .new, .draft, .queued, .sent, .confirmed => true,
            .paid, .calendar_only, .unknown => false,
        };
    }
};

pub const ProfileDeadlineAction = enum(u8) {
    none,
    start,
    continue_draft,
    submit,
    review_submission,
    check_confirmation,
    print,
    upload_receipt,
    pay_online,
    complete_profile,
};

const ProfileDeadlineDraftStage = enum {
    none,
    editing,
    prepared,
};

const ProfileDeadlineLane = enum(u2) {
    deadlines,
    action_required,
    overdue,
};

const max_profile_deadline_actions = 2;
const profile_deadline_action_kind_count: u64 =
    @intFromEnum(ProfileDeadlineAction.complete_profile) + 1;
const profile_deadline_dispatch_payload_bits = 32;
const profile_deadline_dispatch_payload_mask: u64 =
    (@as(u64, 1) << profile_deadline_dispatch_payload_bits) - 1;

pub const ProfileDeadlineActionSet = struct {
    items: [max_profile_deadline_actions]ProfileDeadlineAction =
        [_]ProfileDeadlineAction{.none} ** max_profile_deadline_actions,
    count: u8 = 0,

    fn add(
        self: *ProfileDeadlineActionSet,
        action: ProfileDeadlineAction,
    ) void {
        if (action == .none or self.count >= self.items.len) return;
        self.items[self.count] = action;
        self.count += 1;
    }

    fn at(
        self: *const ProfileDeadlineActionSet,
        index: usize,
    ) ProfileDeadlineAction {
        return if (index < self.count) self.items[index] else .none;
    }

    fn contains(
        self: *const ProfileDeadlineActionSet,
        action: ProfileDeadlineAction,
    ) bool {
        for (self.items[0..self.count]) |candidate| {
            if (candidate == action) return true;
        }
        return false;
    }
};

fn profileDeadlineActionLabel(action: ProfileDeadlineAction) []const u8 {
    return switch (action) {
        .none => "",
        .start => "Start Form",
        .continue_draft => "Continue Draft",
        .submit => "Submit Form",
        .review_submission => "Review Submission",
        .check_confirmation => "Check Confirmation",
        .print => "Print Form",
        .upload_receipt => "Upload Receipt",
        .pay_online => "Pay Online",
        .complete_profile => "Complete Profile",
    };
}

fn profileDeadlineActionIcon(action: ProfileDeadlineAction) []const u8 {
    return switch (action) {
        .none => "",
        .start => "plus",
        .continue_draft => "edit",
        .submit => "send",
        .review_submission => "eye",
        .check_confirmation => "app:mail-check",
        .print => "app:printer",
        .upload_receipt => "app:upload-receipt",
        .pay_online => "external-link",
        .complete_profile => "edit",
    };
}

fn profileDeadlineActionDispatchId(
    projection_generation: u32,
    deadline_id: u64,
    action: ProfileDeadlineAction,
) u64 {
    const payload = deadline_id * profile_deadline_action_kind_count +
        @intFromEnum(action);
    std.debug.assert(payload <= profile_deadline_dispatch_payload_mask);
    return (@as(u64, projection_generation) <<
        profile_deadline_dispatch_payload_bits) | payload;
}

fn profileDeadlineMenuId(
    projection_generation: u32,
    deadline_id: u64,
    lane: ProfileDeadlineLane,
) u64 {
    const payload = deadline_id * 4 + @intFromEnum(lane) + 1;
    std.debug.assert(payload <= profile_deadline_dispatch_payload_mask);
    return (@as(u64, projection_generation) <<
        profile_deadline_dispatch_payload_bits) | payload;
}

fn profileDeadlineAdjustmentDispatchId(
    projection_generation: u32,
    deadline_id: u64,
) u64 {
    std.debug.assert(deadline_id <= profile_deadline_dispatch_payload_mask);
    return (@as(u64, projection_generation) <<
        profile_deadline_dispatch_payload_bits) | deadline_id;
}

fn profileDeadlineActionsFor(
    filing_state: ProfileFilingState,
    draft_stage: ProfileDeadlineDraftStage,
    payment_provider_available: bool,
) ProfileDeadlineActionSet {
    var actions = ProfileDeadlineActionSet{};
    switch (filing_state) {
        .new => actions.add(.start),
        .draft => actions.add(if (draft_stage == .prepared)
            .submit
        else
            .continue_draft),
        .queued => {
            actions.add(.review_submission);
            actions.add(.print);
        },
        .sent => {
            actions.add(.check_confirmation);
            actions.add(.print);
        },
        .confirmed => {
            actions.add(if (payment_provider_available)
                .pay_online
            else
                .upload_receipt);
            actions.add(.print);
        },
        .paid => actions.add(.print),
        .calendar_only, .unknown => {},
    }
    return actions;
}

const ProfileDeadlineLaunchProjection = struct {
    assessment: form_ui.LaunchAssessment = .{},
    ready: bool = false,
};

/// A profile-scoped schedule row combines the resolved deadline with typed,
/// independent filing and timing state. The underlying deadline remains owned
/// by the calendar state; this wrapper owns only the presentation projection.
pub const ProfileCalendarDeadlineRow = struct {
    id: u64,
    deadline: calendar_ui.DeadlineRow,
    projection_generation: u32 = 0,
    filing_state: ProfileFilingState,
    timing: ProfileDeadlineTiming,
    draft_stage: ProfileDeadlineDraftStage = .none,
    draft_id: ?form_ids.DraftId = null,
    actions: ProfileDeadlineActionSet = .{},
    menu_id: u64 = 0,
    action_menu_open: bool = false,

    pub fn dateLabel(
        self: *const ProfileCalendarDeadlineRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.deadline.dateLabel(arena);
    }

    pub fn yearLabel(
        self: *const ProfileCalendarDeadlineRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.deadline.yearLabel(arena);
    }

    pub fn displayFormNo(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return self.deadline.display_form_no;
    }

    pub fn compactLabel(
        self: *const ProfileCalendarDeadlineRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return switch (self.deadline.period) {
            .monthly => |period| std.fmt.allocPrint(
                arena,
                "{s} {s}",
                .{ self.deadline.display_form_no, shortMonthName(period.month) },
            ) catch self.deadline.display_form_no,
            .quarterly => |period| std.fmt.allocPrint(
                arena,
                "{s} Q{d}",
                .{ self.deadline.display_form_no, period.quarter },
            ) catch self.deadline.display_form_no,
            .annual => |period| std.fmt.allocPrint(
                arena,
                "{s} {d}",
                .{ self.deadline.display_form_no, period.taxable_year },
            ) catch self.deadline.display_form_no,
            .event_based => self.deadline.display_form_no,
        };
    }

    pub fn formName(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return self.deadline.form_name;
    }

    pub fn periodLabel(
        self: *const ProfileCalendarDeadlineRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.deadline.periodLabel(arena);
    }

    pub fn dueLabel(
        self: *const ProfileCalendarDeadlineRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "Due {s} {d}, {d}",
            .{
                shortMonthName(self.deadline.final_deadline.month),
                self.deadline.final_deadline.day,
                self.deadline.final_deadline.year,
            },
        ) catch "Due date unavailable";
    }

    pub fn deadlineStatus(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return self.deadline.statusLabel();
    }

    pub fn deadlineTone(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return self.deadline.tone();
    }

    pub fn adjustmentVisible(self: *const ProfileCalendarDeadlineRow) bool {
        return self.deadline.adjustmentVisible() or
            self.deadline.status == .extended;
    }

    pub fn adjustmentActionLabel(
        self: *const ProfileCalendarDeadlineRow,
    ) []const u8 {
        _ = self;
        return "View deadline adjustment details";
    }

    pub fn adjustmentDispatchId(
        self: *const ProfileCalendarDeadlineRow,
    ) u64 {
        return profileDeadlineAdjustmentDispatchId(
            self.projection_generation,
            self.id,
        );
    }

    pub fn filingStatus(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return switch (self.filing_state) {
            .new => "New",
            .draft => "Draft",
            .queued => "Queued",
            .sent => "Sent",
            .confirmed => "Confirmed",
            .paid => "Paid",
            .calendar_only => "Calendar only",
            .unknown => "Status unavailable",
        };
    }

    pub fn filingIcon(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return switch (self.filing_state) {
            .new => "circle-dot",
            .draft => "file-text",
            .queued => "clock",
            .sent => "send",
            .confirmed, .paid => "check-circle",
            .calendar_only => "app:calendar",
            .unknown => "alert",
        };
    }

    pub fn filingTone(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return switch (self.filing_state) {
            .new, .calendar_only => "outline",
            .draft, .queued, .unknown => "secondary",
            .sent, .confirmed, .paid => "primary",
        };
    }

    pub fn timingLabel(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return switch (self.timing) {
            .upcoming => "Upcoming",
            .due_today => "Due today",
            .overdue => "Overdue",
            .closed => "Closed",
        };
    }

    pub fn timingIcon(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return switch (self.timing) {
            .upcoming, .due_today => "clock",
            .overdue => "alert",
            .closed => "check-circle",
        };
    }

    pub fn timingTone(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return switch (self.timing) {
            .upcoming => "secondary",
            .due_today, .closed => "primary",
            .overdue => "destructive",
        };
    }

    pub fn timingVisible(self: *const ProfileCalendarDeadlineRow) bool {
        return self.timing == .due_today or self.timing == .overdue;
    }

    pub fn primaryActionVisible(self: *const ProfileCalendarDeadlineRow) bool {
        return self.actions.count != 0;
    }

    fn needsAction(self: *const ProfileCalendarDeadlineRow) bool {
        return self.filing_state.needsAction() and self.actions.count != 0;
    }

    pub fn primaryActionLabel(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return profileDeadlineActionLabel(self.actions.at(0));
    }

    pub fn primaryActionIcon(self: *const ProfileCalendarDeadlineRow) []const u8 {
        return profileDeadlineActionIcon(self.actions.at(0));
    }

    pub fn primaryActionDispatchId(self: *const ProfileCalendarDeadlineRow) u64 {
        return profileDeadlineActionDispatchId(
            self.projection_generation,
            self.id,
            self.actions.at(0),
        );
    }

    pub fn multipleActions(self: *const ProfileCalendarDeadlineRow) bool {
        return self.actions.count > 1;
    }

    pub fn actionMenuLabel(self: *const ProfileCalendarDeadlineRow) []const u8 {
        _ = self;
        return "More filing actions";
    }

    pub fn actionMenuId(self: *const ProfileCalendarDeadlineRow) u64 {
        return self.menu_id;
    }

    pub fn actionMenuOpen(self: *const ProfileCalendarDeadlineRow) bool {
        return self.action_menu_open;
    }

    pub fn secondaryActionOneVisible(
        self: *const ProfileCalendarDeadlineRow,
    ) bool {
        return self.actions.count > 1;
    }

    pub fn secondaryActionOneLabel(
        self: *const ProfileCalendarDeadlineRow,
    ) []const u8 {
        return profileDeadlineActionLabel(self.actions.at(1));
    }

    pub fn secondaryActionOneIcon(
        self: *const ProfileCalendarDeadlineRow,
    ) []const u8 {
        return profileDeadlineActionIcon(self.actions.at(1));
    }

    pub fn secondaryActionOneDispatchId(
        self: *const ProfileCalendarDeadlineRow,
    ) u64 {
        return profileDeadlineActionDispatchId(
            self.projection_generation,
            self.id,
            self.actions.at(1),
        );
    }
};

pub const ProfileSetupChangeRow = struct {
    id: u64,
    effective_from: [10]u8,
    form_count: usize,
    covers_today: bool,

    pub fn rangeLabel(
        self: *const ProfileSetupChangeRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "From {s}",
            .{&self.effective_from},
        ) catch "Recorded change";
    }

    pub fn formsLabel(
        self: *const ProfileSetupChangeRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d} active {s}",
            .{
                self.form_count,
                if (self.form_count == 1) "form" else "forms",
            },
        ) catch "Forms unavailable";
    }

    pub fn todayBadgeVisible(self: *const ProfileSetupChangeRow) bool {
        return self.covers_today;
    }
};

pub const ProfileFormSetRow = struct {
    id: u64,
    tax_year: i32,
    state: profile_store.FormSetState,
    active_form_count: usize,

    pub fn yearLabel(self: *const ProfileFormSetRow) i32 {
        return self.tax_year;
    }

    pub fn stateLabel(self: *const ProfileFormSetRow) []const u8 {
        return switch (self.state) {
            .needs_configuration => "Needs configuration",
            .legacy_catalog_default => "Legacy catalog default",
            .active_empty => "No active forms",
            .active_nonempty => "Active",
        };
    }

    pub fn formsLabel(
        self: *const ProfileFormSetRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d} active {s}",
            .{
                self.active_form_count,
                if (self.active_form_count == 1) "form" else "forms",
            },
        ) catch "Forms unavailable";
    }

    pub fn editorLabel(self: *const ProfileFormSetRow) []const u8 {
        return if (self.active_form_count == 0) "Configure forms" else "Edit forms";
    }
};

pub const ProfileCalendarYearOption = struct {
    id: u64,
    year: i32,
    selected: bool,

    pub fn label(self: *const ProfileCalendarYearOption) i32 {
        return self.year;
    }

    pub fn accessibleLabel(self: *const ProfileCalendarYearOption) []const u8 {
        return if (self.selected) "Selected tax year" else "Select tax year";
    }
};

/// One row of the yearly setup combobox. Configured and unconfigured years
/// differ by icon and by their own words, never by color alone.
pub const ProfileSetupYearOption = struct {
    id: u64,
    year: i32,
    selected: bool,
    configured: bool,
    active_form_count: usize,

    pub fn label(self: *const ProfileSetupYearOption) i32 {
        return self.year;
    }

    pub fn missing(self: *const ProfileSetupYearOption) bool {
        return !self.configured;
    }

    pub fn metaLabel(
        self: *const ProfileSetupYearOption,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (!self.configured) {
            return std.fmt.allocPrint(
                arena,
                "Set up forms for {d}",
                .{self.year},
            ) catch "Set up forms";
        }
        return activeFormCountLabel(arena, self.active_form_count);
    }

    /// A configured year and one that still needs setup are told apart by
    /// their own words, never by color alone.
    pub fn rowLabel(
        self: *const ProfileSetupYearOption,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d} · {s}",
            .{ self.year, self.metaLabel(arena) },
        ) catch "Tax year";
    }

    pub fn accessibleLabel(
        self: *const ProfileSetupYearOption,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (!self.configured) {
            return std.fmt.allocPrint(
                arena,
                "{d}, not set up. Set up forms for {d}",
                .{ self.year, self.year },
            ) catch "Not set up";
        }
        return std.fmt.allocPrint(
            arena,
            "{d}, configured, {s}",
            .{ self.year, activeFormCountLabel(arena, self.active_form_count) },
        ) catch "Configured";
    }
};

/// A configured year offered as the starting point for a year being set up.
pub const ProfileSetupSourceOption = struct {
    id: u64,
    year: i32,
    active_form_count: usize,
    selected: bool,

    pub fn label(self: *const ProfileSetupSourceOption) i32 {
        return self.year;
    }

    pub fn metaLabel(
        self: *const ProfileSetupSourceOption,
        arena: std.mem.Allocator,
    ) []const u8 {
        return activeFormCountLabel(arena, self.active_form_count);
    }

    pub fn rowLabel(
        self: *const ProfileSetupSourceOption,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d} · {s}",
            .{ self.year, activeFormCountLabel(arena, self.active_form_count) },
        ) catch "Tax year";
    }

    pub fn accessibleLabel(
        self: *const ProfileSetupSourceOption,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "Use setup from {d}, {s}",
            .{ self.year, activeFormCountLabel(arena, self.active_form_count) },
        ) catch "Use this year's setup";
    }
};

fn activeFormCountLabel(
    arena: std.mem.Allocator,
    count: usize,
) []const u8 {
    if (count == 0) return "No active forms";
    if (count == 1) return "1 active form";
    return std.fmt.allocPrint(arena, "{d} active forms", .{count}) catch
        "Active forms";
}

/// One taxpayer detail that an active form requires and the profile does not
/// have yet, named alongside every active form that consumes it. Showing where
/// a detail is used is what makes it obvious the fix belongs to the taxpayer,
/// not to one form.
pub const ProfileMissingFactRow = struct {
    id: usize,
    field_label: []const u8,
    used_by: []const u8,

    pub fn fieldLabel(self: *const ProfileMissingFactRow) []const u8 {
        return self.field_label;
    }

    pub fn usedByLabel(self: *const ProfileMissingFactRow) []const u8 {
        return self.used_by;
    }
};

pub const ImportantNewsRow = struct {
    id: usize,
    notice: *const news_domain.OwnedNotice,

    pub fn title(
        self: *const ImportantNewsRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return compactNewsText(arena, self.notice.title, 150);
    }

    pub fn summary(
        self: *const ImportantNewsRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return compactNewsText(arena, self.notice.summary, 250);
    }

    pub fn source(self: *const ImportantNewsRow) []const u8 {
        return self.notice.source;
    }

    pub fn publishedLabel(
        self: *const ImportantNewsRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return formatNewsTimestamp(
            arena,
            self.notice.published_at_unix,
        );
    }
};

pub const FormProfileChoiceRow = struct {
    id: usize,
    stable_id: []const u8,
    name: []const u8,
    selected: bool,

    pub fn idLabel(self: *const FormProfileChoiceRow) []const u8 {
        return self.stable_id;
    }
};

pub const PendingProfileFormLaunch = struct {
    form_index: usize,
    tax_year: i32,
    quarter: u8,
    period_month: ?u8,
    spouse_profile_id: ?profile_model.ProfileId,
    filing: ?form_period.FilingPeriod,
};

const TaxFormProfileCardState = enum {
    unavailable,
    calendar_only,
    inherited_only_ready,
    needs_tax_profile,
    needs_registration,
    needs_year_settings,
    year_settings_reserved,
    year_settings_require_review,
    needs_setup,
    requires_review,
    needs_filing_context,
    ready,
    error_loading,

    fn label(self: TaxFormProfileCardState) []const u8 {
        return switch (self) {
            .unavailable => "Inactive for this tax year",
            .calendar_only => "Calendar only - no editor or Tax Form Profile",
            .inherited_only_ready => "Ready - uses saved Tax Profile details",
            .needs_tax_profile => "Needs Tax Profile details",
            .needs_registration => "Registration details incomplete",
            .needs_year_settings => "Annual income tax rate unresolved",
            .year_settings_reserved => "Annual income tax rate reserved",
            .year_settings_require_review => "Annual income tax rate requires review",
            .needs_setup => "Needs Tax Form Profile setup",
            .requires_review => "Tax Form Profile requires review",
            .needs_filing_context => "Filing context incomplete",
            .ready => "Tax Form Profile ready",
            .error_loading => "Tax Form Profile status unavailable",
        };
    }

    fn actionLabel(self: TaxFormProfileCardState) []const u8 {
        return switch (self) {
            .inherited_only_ready, .needs_tax_profile => "View Tax Form Profile",
            .needs_registration => "Review Tax Form Profile",
            .needs_year_settings => "Set income tax rate",
            .year_settings_reserved => "View reserved income tax rate",
            .year_settings_require_review => "Review income tax rate",
            .needs_setup => "Set up Tax Form Profile",
            .requires_review, .ready => "View Tax Form Profile",
            .needs_filing_context => "Review filing context",
            .unavailable, .calendar_only, .error_loading => "",
        };
    }

    fn actionVisible(self: TaxFormProfileCardState) bool {
        return switch (self) {
            .inherited_only_ready,
            .needs_tax_profile,
            .needs_registration,
            .needs_year_settings,
            .year_settings_reserved,
            .year_settings_require_review,
            .needs_setup,
            .requires_review,
            .needs_filing_context,
            .ready,
            => true,
            .unavailable, .calendar_only, .error_loading => false,
        };
    }
};

const TaxFormProfileChoiceCache = struct {
    field_index: usize = 0,
    stable_id: canvas.TextBuffer(64) = .{},
    label: canvas.TextBuffer(160) = .{},
};

const TaxFormProfileInheritedCache = struct {
    source_revision_id: canvas.TextBuffer(96) = .{},
    source_sequence: u32 = 0,
    tin: canvas.TextBuffer(16) = .{},
    rdo: canvas.TextBuffer(8) = .{},
    subject_kind: canvas.TextBuffer(40) = .{},
    name: canvas.TextBuffer(160) = .{},
    address: canvas.TextBuffer(320) = .{},
    zip: canvas.TextBuffer(16) = .{},
    contact: canvas.TextBuffer(64) = .{},
    email: canvas.TextBuffer(160) = .{},
};

const AnnualIncomeTaxEligibility = enum {
    unresolved,
    eligible,
    taxpayer_type_ineligible,
    classification_unresolved,
    business_commencement_unresolved,
    percentage_tax_registration_missing,
    vat_registered,
    registration_requires_review,
    load_failed,
};

/// Volatile composed state for the 2551Q pilot. The event itself remains
/// owned by the append-only `(taxpayer, tax year)` stream; this cache only
/// drives the read-only Tax Form Profile and its explicit candidate editor.
const AnnualIncomeTaxElectionCache = struct {
    current: ?annual_income_tax_election.Event = null,
    eligibility: AnnualIncomeTaxEligibility = .unresolved,
    commencement: annual_income_tax_election.BusinessCommencement = .unknown,
    filing_quarter: u8 = 1,
    initial_applicable_quarter: ?u8 = null,
    load_failed: bool = false,
};

/// Pointer-free copy of the composed profile result used by Native view
/// bindings. `compose` borrows owned persistence projections, so every slice
/// and pointer must be consumed before those projections are released.  The
/// readiness layers, annual event, derived period, and launch decision are
/// fixed-storage values and remain valid after the loader returns.
const RuntimeComposedSnapshot = struct {
    loaded: bool = false,
    readiness: composed_tax_profile.ComposedReadiness = .{},
    current_annual: ?annual_income_tax_election.Event = null,
    filing_context: ?composed_tax_profile.DerivedFilingContext = null,
    ready_for_new_filing: bool = false,
};

pub const TaxFormProfileInheritedRow = struct {
    id: usize,
    label: []const u8,
    value: []const u8,
};

const max_tax_form_profile_history_rows: usize = 24;

pub const TaxFormProfileHistoryRow = struct {
    id: usize = 0,
    sequence: u32 = 0,
    effective: canvas.TextBuffer(32) = .{},
    source: canvas.TextBuffer(128) = .{},
    current: bool = false,

    pub fn effectiveLabel(self: *const TaxFormProfileHistoryRow) []const u8 {
        return self.effective.text();
    }

    pub fn sourceLabel(self: *const TaxFormProfileHistoryRow) []const u8 {
        return self.source.text();
    }

    pub fn currentVisible(self: *const TaxFormProfileHistoryRow) bool {
        return self.current;
    }
};

pub const TaxFormProfileFieldRow = struct {
    id: usize,
    label: []const u8,
    value: []const u8,
    helper: []const u8,
    required: bool,
    evidence_required: bool,
    editable: bool,
    has_value: bool,
    picker_open: bool,

    pub fn requiredLabel(self: *const TaxFormProfileFieldRow) []const u8 {
        if (self.evidence_required) return "Evidence review required";
        return if (self.required) "Required" else "Optional";
    }

    pub fn pickerLabel(self: *const TaxFormProfileFieldRow) []const u8 {
        return if (self.has_value) "Change selection" else "Choose a value";
    }

    pub fn hasValue(self: *const TaxFormProfileFieldRow) bool {
        return self.has_value;
    }

    pub fn pickerOpen(self: *const TaxFormProfileFieldRow) bool {
        return self.picker_open;
    }
};

pub const TaxFormProfileChoiceRow = struct {
    id: usize,
    label: []const u8,
    selected: bool,
};

const RegistrationDialogMode = enum {
    none,
    add_activity,
    edit_activity,
    add_obligation,
    edit_obligation,
};

const RegistrationObligationDraftKind = enum {
    registered_income_tax,
    vat,
    percentage_tax,
    withholding_compensation,
    withholding_expanded,
    withholding_final,
    withholding_other,
};

pub const RegistrationActivityView = struct {
    id: usize,
    line_of_business: []const u8,
    atc: []const u8,
    effective: []const u8,

    pub fn lineOfBusiness(self: *const RegistrationActivityView) []const u8 {
        return self.line_of_business;
    }

    pub fn atcLabel(self: *const RegistrationActivityView) []const u8 {
        return self.atc;
    }

    pub fn effectiveLabel(self: *const RegistrationActivityView) []const u8 {
        return self.effective;
    }
};

pub const RegistrationObligationView = struct {
    id: usize,
    kind: []const u8,
    effective: []const u8,

    pub fn kindLabel(self: *const RegistrationObligationView) []const u8 {
        return self.kind;
    }

    pub fn effectiveLabel(
        self: *const RegistrationObligationView,
    ) []const u8 {
        return self.effective;
    }
};

pub const RegistrationFactView = struct {
    id: usize,
    fact_label: []const u8,
    detail: []const u8,

    pub fn label(self: *const RegistrationFactView) []const u8 {
        return self.fact_label;
    }

    pub fn value(self: *const RegistrationFactView) []const u8 {
        return self.detail;
    }
};

pub const ProfileRdoOptionRow = struct {
    id: usize,
    code: []const u8,
    name: []const u8,
    selected: bool,

    pub fn rowLabel(
        self: *const ProfileRdoOptionRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{s} - {s}",
            .{ self.code, self.name },
        ) catch self.code;
    }
};

/// The Tax Form Library's period picker is a display/opening context. It
/// never changes the authoritative Forms Set; it only narrows the cadence
/// cards shown for the selected taxpayer and tax year.
pub const Model = struct {
    page: Page = .global_dashboard,
    profileEditorOrigin: Page = .global_dashboard,
    overlayReturnPage: Page = .global_dashboard,
    dashboardSection: DashboardSection = .calendar,
    profileSetupSection: ProfileSetupSection = .tax_profile,
    pendingProfileNavigation: ?PendingProfileNavigation = null,
    taxCalendarSection: TaxCalendarSection = .rules,
    backgroundTasksSection: BackgroundTasksSection = .jobs,
    globalDashboard: GlobalDashboardState = .{},
    profileCalendarForms: ProfileCalendarFormsState = .{},
    themePreference: ThemePreference = .system,
    sidebarPreference: SidebarPreference = .expanded,
    sidebarOverlayOpen: bool = false,
    sidebarProfileSearchBuffer: canvas.TextBuffer(96) = .{},
    // Native list items retain pointer-selected state internally. Changing
    // this sibling-scoped key after a dock action remounts those rows so
    // their gray surface remains a hover affordance, never a selection.
    sidebarActionEpoch: u64 = 0,
    viewportClass: ViewportClass = viewportClassForWidth(window_width),
    viewportWidth: f32 = window_width,
    systemColorScheme: native_sdk.ColorScheme = .light,
    reduceMotion: bool = false,
    highContrast: bool = false,
    calendar: calendar_ui.State = .{},
    profileCalendar: calendar_ui.State = .{},
    news: news_ui.State = .{},
    newsStore: ?*news_store.Store = null,
    newsAllocator: ?std.mem.Allocator = null,
    newsNotices: ?news_domain.NoticeList = null,
    taxProfiles: profile_ui.State = .{},
    regPage: profile_registration_ui.State = .{},
    regLoaded: bool = false,
    regLoadFailed: bool = false,
    regDialogMode: RegistrationDialogMode = .none,
    regSelectedIndex: ?usize = null,
    regLineOfBusiness: canvas.TextBuffer(160) = .{},
    regAtc: canvas.TextBuffer(16) = .{},
    regEffectiveFrom: canvas.TextBuffer(10) = .{},
    regEffectiveUntil: canvas.TextBuffer(10) = .{},
    regOtherTaxType: canvas.TextBuffer(120) = .{},
    regObligationDraftKind: RegistrationObligationDraftKind =
        .registered_income_tax,
    regEditorError: canvas.TextBuffer(180) = .{},
    formProfiles: form_ui.State = .{},
    taxFormProfilePage: tax_form_profile_ui.State = .{},
    taxpayerYearPage: taxpayer_year_ui.State = .{},
    taxFormProfileFormIndex: ?usize = null,
    taxFormProfileViewedDate: ?profile_model.Date = null,
    taxFormProfilePreviousSegmentDate: ?profile_model.Date = null,
    taxFormProfileNextSegmentDate: ?profile_model.Date = null,
    taxFormProfileReturnPage: Page = .taxpayer_dashboard,
    taxFormProfileReturnDashboardSection: DashboardSection = .calendar,
    taxFormProfileReturnProfileSection: ProfileSetupSection = .tax_profile,
    taxFormProfilePendingNavigation: ?PendingTaxFormProfileNavigation = null,
    taxFormProfileDiscardPromptOpen: bool = false,
    taxFormProfileRegistrationReturnPending: bool = false,
    taxFormProfilePickerField: ?usize = null,
    taxFormProfileChoices: [128]TaxFormProfileChoiceCache = undefined,
    taxFormProfileChoiceCount: usize = 0,
    taxFormProfileInherited: TaxFormProfileInheritedCache = .{},
    annualIncomeTaxElection: AnnualIncomeTaxElectionCache = .{},
    taxFormProfileComposed: RuntimeComposedSnapshot = .{},
    taxFormProfileHistoryRowsCache: [max_tax_form_profile_history_rows]TaxFormProfileHistoryRow = undefined,
    taxFormProfileHistoryRowCount: usize = 0,
    taxFormProfileHistoryTruncated: bool = false,
    taxFormProfileCardStates: [form_catalog.registry_count]TaxFormProfileCardState =
        [_]TaxFormProfileCardState{.unavailable} ** form_catalog.registry_count,
    taxFormProfileHistoryAvailable: [form_catalog.registry_count]bool =
        [_]bool{false} ** form_catalog.registry_count,
    taxFormProfileCardStatesReady: bool = false,
    incomeTax: income_tax_ui.State = .{},
    exact1701Q: exact_1701q_native.State = .{},
    exact1701QDevelopmentPlaintext: ?*const key_custody.DevelopmentPlaintextStorageCapability = null,
    exact1701QFrozenProvenance: ?exact_1701q_runtime.FrozenExactProvenance = null,
    /// Exact saves and resumed revisions must use the same owned projection
    /// that minted or reopened the workspace. The mutable form-profile page
    /// may later point at a newer taxpayer revision.
    exact1701QHistoricalProfile: ?profile_projection.Snapshot = null,
    percentageTax: percentage_tax_ui.State = .{},
    calendarExportProfileRevision: ?profile_ui.RevisionContext = null,
    profileCalendarExportStatus: ProfileCalendarExportStatus = .idle,
    profileCalendarExportNoticeEpoch: u64 = 0,
    profileCalendarExportTimerKey: u64 = 0,
    profileSubjectPickerVisible: bool = false,
    profileClassificationPickerVisible: bool = false,
    profileEoptPickerVisible: bool = false,
    profilePrimaryLineOfBusiness: canvas.TextBuffer(160) = .{},
    profileCompletionTarget: ?profile_fields.ReusableField = null,
    profileCompletionFormIndex: ?usize = null,
    pendingProfileFormLaunch: ?PendingProfileFormLaunch = null,
    profileFormLaunchAssessments: [form_catalog.registry_count]form_ui.LaunchAssessment = undefined,
    profileFormLaunchAssessmentsReady: bool = false,
    profilePeriodLaunchAssessments: [form_catalog.registry_count][12]form_ui.LaunchAssessment = undefined,
    profilePeriodLaunchAssessmentsReady: [form_catalog.registry_count][12]bool =
        [_][12]bool{[_]bool{false} ** 12} ** form_catalog.registry_count,
    /// Date-effective Forms Set membership for the same period slots. These
    /// booleans are refreshed outside view bindings so cards and controls do
    /// not perform persistence I/O while rendering.
    profilePeriodAvailability: [form_catalog.registry_count][12]bool =
        [_][12]bool{[_]bool{false} ** 12} ** form_catalog.registry_count,
    profilePeriodAvailabilityReady: [form_catalog.registry_count][12]bool =
        [_][12]bool{[_]bool{false} ** 12} ** form_catalog.registry_count,
    profileFormAnyPeriodActive: [form_catalog.registry_count]bool =
        [_]bool{false} ** form_catalog.registry_count,
    profileFormActiveSegments: [form_catalog.registry_count]?profile_model.EffectivePeriod =
        [_]?profile_model.EffectivePeriod{null} ** form_catalog.registry_count,
    profileFormAvailabilityYear: i32 = 0,
    profileDeadlineLaunchAssessments: [calendar_ui.max_deadlines]form_ui.LaunchAssessment = undefined,
    profileDeadlineLaunchAssessmentsReady: [calendar_ui.max_deadlines]bool =
        [_]bool{false} ** calendar_ui.max_deadlines,
    libraryFilter: library_view.FilterState = .{},
    profileCalendarSelectedDate: ?calendar_domain.Date = null,
    profileCalendarYearPickerVisible: bool = false,
    profileCalendarYearQuery: canvas.TextBuffer(16) = .{},
    profileSetupYearPickerVisible: bool = false,
    profileSetupYearQuery: canvas.TextBuffer(4) = .{},
    profileSetupSourcePickerVisible: bool = false,
    profileSetupYearsExpanded: bool = false,
    profileSetupChangesExpanded: bool = false,
    profileAdvancedExpanded: bool = false,
    profileDeadlineProjectionGeneration: u32 = 0,
    profileDeadlineActionMenuId: ?u64 = null,
    profileDeadlineAdjustmentId: ?u64 = null,
    profileDeadlineStubAction: ProfileDeadlineAction = .none,
    profileDeadlineStubDeadlineId: ?u64 = null,
    profileNoticeTimerKey: u64 = 0,
    profileTinSegments: [segmented_tin.segment_count]canvas.TextBuffer(32) =
        [_]canvas.TextBuffer(32){.{}} ** segmented_tin.segment_count,
    profileTinFocusSegment: u8 = 0,
    profileTinFocusActive: bool = false,
    profileRdoPickerVisible: bool = false,
    profileRdoQuery: canvas.TextBuffer(128) = .{},
    calendarToday: calendar_domain.Date = .{
        .year = 2026,
        .month = 1,
        .day = 1,
    },

    // These values drive Zig-owned tokens rather than markup bindings.
    pub const view_unbound = .{
        "libraryFilter",
        "sidebarPreference",
        "sidebarOverlayOpen",
        "sidebarProfileSearchBuffer",
        "viewportClass",
        "viewportWidth",
        "profileEditorOrigin",
        "overlayReturnPage",
        "dashboardSection",
        "profileSetupSection",
        "taxCalendarSection",
        "backgroundTasksSection",
        "globalDashboard",
        "profileCalendarForms",
        "systemColorScheme",
        "reduceMotion",
        "highContrast",
        "calendar",
        "profileCalendar",
        "news",
        "newsStore",
        "newsAllocator",
        "newsNotices",
        "calendarToday",
        "profileSubjectPickerVisible",
        "profileClassificationPickerVisible",
        "profileEoptPickerVisible",
        "profilePrimaryLineOfBusiness",
        "profileTinSegments",
        "profileTinFocusSegment",
        "profileTinFocusActive",
        "profileRdoPickerVisible",
        "profileRdoQuery",
        "profileCompletionTarget",
        "profileCompletionFormIndex",
        "pendingProfileFormLaunch",
        "profileCalendarYearPickerVisible",
        "profileCalendarYearQuery",
        "profileSetupYearPickerVisible",
        "profileSetupYearQuery",
        "profileSetupSourcePickerVisible",
        "profileSetupYearsExpanded",
        "profileSetupChangesExpanded",
        "profileAdvancedExpanded",
        "profileDeadlineProjectionGeneration",
        "profileDeadlineActionMenuId",
        "profileDeadlineAdjustmentId",
        "profileDeadlineStubAction",
        "profileDeadlineStubDeadlineId",
        "profileFormLaunchAssessments",
        "profileFormLaunchAssessmentsReady",
        "profilePeriodLaunchAssessments",
        "profilePeriodLaunchAssessmentsReady",
        "profileDeadlineLaunchAssessments",
        "profileDeadlineLaunchAssessmentsReady",
        "profileFormPeriodCellTypeRows",
        // Compatibility/test-only helpers retained while older callers move
        // to the grouped Browse filters and exact period-tile action.
        "profileFormsHeading",
        "profileFormsModeDescription",
        "profileFormsIconAction",
        "profileFormsPeriodFilterPickerOpen",
        "profileFormsPeriodFilterLabel",
        "profileFormsPeriodFilterAccessibleLabel",
        "profileFormsFilterSummaryLabel",
        "profileFormsJanuarySelected",
        "profileFormsFebruarySelected",
        "profileFormsMarchSelected",
        "profileFormsAprilSelected",
        "profileFormsMaySelected",
        "profileFormsJuneSelected",
        "profileFormsJulySelected",
        "profileFormsAugustSelected",
        "profileFormsSeptemberSelected",
        "profileFormsOctoberSelected",
        "profileFormsNovemberSelected",
        "profileFormsDecemberSelected",
        "profileFormsQuarterOneSelected",
        "profileFormsQuarterTwoSelected",
        "profileFormsQuarterThreeSelected",
        "profileFormsQuarterFourSelected",
        "profileFormsShowMoreVisible",
        "profileFormsHasMoreRows",
        "profileFormsHasPreviousRows",
        "profileBrowseFormRows",
        "profileManageFormRows",
        "profile_forms_toggle_period_picker",
        "profile_forms_close_period_picker",
        "profile_forms_period_all",
        "profile_forms_period_january",
        "profile_forms_period_february",
        "profile_forms_period_march",
        "profile_forms_period_april",
        "profile_forms_period_may",
        "profile_forms_period_june",
        "profile_forms_period_july",
        "profile_forms_period_august",
        "profile_forms_period_september",
        "profile_forms_period_october",
        "profile_forms_period_november",
        "profile_forms_period_december",
        "profile_forms_period_quarter_one",
        "profile_forms_period_quarter_two",
        "profile_forms_period_quarter_three",
        "profile_forms_period_quarter_four",
        "profile_forms_period_annual",
        "profile_forms_period_on_demand",
        "open_library_form",
        "taxProfiles",
        "regPage",
        "regLoaded",
        "regLoadFailed",
        "regDialogMode",
        "regSelectedIndex",
        "regLineOfBusiness",
        "regAtc",
        "regEffectiveFrom",
        "regEffectiveUntil",
        "regOtherTaxType",
        "regObligationDraftKind",
        "regEditorError",
        "formProfiles",
        "annualIncomeTaxElection",
        "incomeTax",
        // Compatibility/test-only coarse 1701Q surface. It remains
        // deliberately unbound: the exact state is the only visible UI and
        // payload authority. Removing this obsolete model surface is tracked
        // as follow-up work; markup must never be resurrected to silence the
        // contract checker.
        "incomeTaxYear",
        "incomeTaxQuarter",
        "incomeTaxQuarterQ1Selected",
        "incomeTaxQuarterQ2Selected",
        "incomeTaxQuarterQ3Selected",
        "incomeTaxAmendedReturn",
        "incomeTaxSheetsAttached",
        "incomeTaxElection",
        "incomeTaxElectionGraduatedSelected",
        "incomeTaxElectionEightPercentSelected",
        "incomeTaxInputsDisabled",
        "incomeTaxGraduatedSales",
        "incomeTaxGraduatedCost",
        "incomeTaxGraduatedDeductions",
        "incomeTaxGraduatedTaxableIncome",
        "incomeTaxGraduatedTaxDue",
        "incomeTaxGraduatedInputsDisabled",
        "incomeTaxEightGrossSales",
        "incomeTaxEightNonOperatingIncome",
        "incomeTaxEightTaxDue",
        "incomeTaxEightPercentInputsDisabled",
        "incomeTaxPriorQuarterPayments",
        "incomeTaxWithheld2307",
        "incomeTaxOtherCredits",
        "incomeTaxPayableOrOverpayment",
        "incomeTaxSurcharge",
        "incomeTaxInterest",
        "incomeTaxCompromise",
        "incomeTaxPaymentAddDisabled",
        "incomeTaxPaymentRemoveDisabled",
        "incomeTaxPaymentEditorVisible",
        "incomeTaxPaymentMethod",
        "incomeTaxPaymentMethodCashSelected",
        "incomeTaxPaymentMethodCheckSelected",
        "incomeTaxPaymentMethodTaxDebitMemoSelected",
        "incomeTaxPaymentMethodOtherSelected",
        "incomeTaxPaymentBankOrAgency",
        "incomeTaxPaymentReference",
        "incomeTaxPaymentAmount",
        "incomeTaxNoticeVisible",
        "incomeTaxNotice",
        "incomeTaxNoticeTone",
        "incomeTaxTotalTaxPayable",
        "incomeTaxSaveDisabled",
        "incomeTaxPaymentRows",
        "income_tax_quarter_q1",
        "income_tax_quarter_q2",
        "income_tax_quarter_q3",
        "income_tax_sheets_attached_input",
        "income_tax_election_graduated",
        "income_tax_election_eight_percent",
        "income_tax_graduated_sales_input",
        "income_tax_graduated_cost_input",
        "income_tax_graduated_deductions_input",
        "income_tax_graduated_taxable_income_input",
        "income_tax_graduated_tax_due_input",
        "income_tax_eight_gross_sales_input",
        "income_tax_eight_non_operating_input",
        "income_tax_eight_tax_due_input",
        "income_tax_prior_payments_input",
        "income_tax_withheld_2307_input",
        "income_tax_other_credits_input",
        "income_tax_payable_input",
        "income_tax_surcharge_input",
        "income_tax_interest_input",
        "income_tax_compromise_input",
        "income_tax_add_payment",
        "income_tax_select_payment",
        "income_tax_remove_selected_payment",
        "income_tax_payment_method_cash",
        "income_tax_payment_method_check",
        "income_tax_payment_method_tax_debit_memo",
        "income_tax_payment_method_other",
        "income_tax_payment_bank_input",
        "income_tax_payment_reference_input",
        "income_tax_payment_amount_input",
        "exact1701Q",
        "exact1701QDevelopmentPlaintext",
        "exact1701QFrozenProvenance",
        "exact1701QHistoricalProfile",
        "taxFormProfileRegistrationReturnPending",
        "percentageTax",
        "calendarExportProfileRevision",
        "profileCalendarExportStatus",
        "profileCalendarExportNoticeEpoch",
        "profileCalendarExportTimerKey",
        "profileNoticeTimerKey",
        "profileCalendarSelectedDate",
        "selectedTaxpayerCalendarKey",
        "hasSelectedTaxpayer",
    };

    pub fn brandLogo(_: *const Model) u64 {
        return 1;
    }

    pub fn appIcon(_: *const Model) u64 {
        return 6;
    }

    pub fn bagongPilipinasLogo(_: *const Model) u64 {
        return 2;
    }

    pub fn birLogo(_: *const Model) u64 {
        return 3;
    }

    pub fn goldcodersLogo(_: *const Model) u64 {
        return 4;
    }

    pub fn darkThemeActive(self: *const Model) bool {
        return effectiveColorScheme(self) == .dark;
    }

    pub fn lightThemeActive(self: *const Model) bool {
        return effectiveColorScheme(self) == .light;
    }

    /// Desktop keeps the authoritative 280 px sidebar. Tablet widths use
    /// the 72 px rail automatically; phones move navigation out of flow.
    pub fn sidebarExpandedVisible(self: *const Model) bool {
        return self.viewportClass == .desktop and
            self.sidebarPreference == .expanded;
    }

    pub fn sidebarRailVisible(self: *const Model) bool {
        if (self.isConstrainedViewport()) return false;
        if (self.sidebarPreference == .hidden) return false;
        return self.viewportClass != .desktop or
            self.sidebarPreference == .rail;
    }

    pub fn sidebarLauncherVisible(self: *const Model) bool {
        return self.isConstrainedViewport() or
            self.sidebarPreference == .hidden;
    }

    pub fn sidebarOverlayVisible(self: *const Model) bool {
        return self.sidebarOverlayOpen;
    }

    pub fn compactFooter(self: *const Model) bool {
        return self.isConstrainedViewport();
    }

    pub fn regularFooter(self: *const Model) bool {
        return !self.isConstrainedViewport();
    }

    pub fn footerCopyrightVisible(self: *const Model) bool {
        return self.viewportClass == .rail_regular or
            self.viewportClass == .desktop;
    }

    pub fn artifactStorageClassification(self: *const Model) []const u8 {
        _ = self;
        return key_custody.current_artifact_storage_classification_text;
    }

    pub fn phoneLayout(self: *const Model) bool {
        return self.viewportClass == .phone;
    }

    pub fn constrainedLayout(self: *const Model) bool {
        return self.isConstrainedViewport();
    }

    pub fn tabletLayout(self: *const Model) bool {
        return self.viewportClass == .rail_narrow or
            self.viewportClass == .rail_regular;
    }

    pub fn desktopLayout(self: *const Model) bool {
        return self.viewportClass == .desktop;
    }

    fn taxpayerDashboardLaneMode(self: *const Model) TaxpayerDashboardLaneMode {
        return taxpayerDashboardLaneModeForWidth(self.effectiveDashboardWidth());
    }

    pub fn dashboardThreeColumnLayout(self: *const Model) bool {
        return self.taxpayerDashboardLaneMode() == .three_columns;
    }

    pub fn dashboardTwoColumnLayout(self: *const Model) bool {
        return self.taxpayerDashboardLaneMode() == .two_columns;
    }

    fn dashboardStackedLayout(self: *const Model) bool {
        return self.taxpayerDashboardLaneMode() == .stacked;
    }

    /// The legacy dashboard keeps two useful work lanes only while each lane
    /// can remain at least 320 points wide. Narrow rail and mobile layouts
    /// stack instead of squeezing the form picker and calendar grid.
    pub fn globalDashboardTwoColumnLayout(self: *const Model) bool {
        // With a 4:5 split and a 20-point gutter, 740 points leaves the
        // calendar lane 320 points wide and the news lane wider still.
        return self.effectiveDashboardWidth() >= taxpayer_two_lane_min_width;
    }

    pub fn globalDashboardPagePadding(self: *const Model) u16 {
        return switch (self.viewportClass) {
            .phone => 16,
            .desktop => 32,
            else => 24,
        };
    }

    pub fn taxpayerDashboardPagePadding(self: *const Model) u16 {
        return self.globalDashboardPagePadding();
    }

    fn dashboardControlHeight(self: *const Model) f32 {
        return if (self.isConstrainedViewport()) 44 else 36;
    }

    pub fn dashboardContentGap(self: *const Model) u16 {
        return if (self.isConstrainedViewport()) 16 else 24;
    }

    /// The calendar column has an explicit readable range. In a stacked
    /// dashboard it stops growing at the same maximum instead of turning each
    /// day into a wide strip; in two-column mode the 4:5 legacy split remains
    /// the preferred width until it reaches that cap.
    pub fn globalCalendarLaneWidth(self: *const Model) f32 {
        const content_width = self.effectiveDashboardWidth();
        const preferred = if (self.globalDashboardTwoColumnLayout())
            (content_width - 20) * 4 / 9
        else
            content_width;
        const clamped = std.math.clamp(
            preferred,
            global_calendar_lane_min_width,
            global_calendar_lane_max_width,
        );
        return @min(content_width, clamped);
    }

    pub fn globalCalendarHeaderStacked(self: *const Model) bool {
        return self.constrainedLayout() or
            self.globalCalendarLaneWidth() < 400;
    }

    /// Native markup has no aspect-ratio attribute. Derive a bounded day
    /// height from the lane that actually owns the calendar.
    pub fn globalCalendarDayHeight(self: *const Model) f32 {
        const maximum = if (self.globalDashboardTwoColumnLayout())
            global_calendar_two_column_day_max_height
        else
            global_calendar_stacked_day_max_height;
        return calendarDayHeight(self.globalCalendarLaneWidth(), maximum);
    }

    /// The taxpayer calendar is capped even when its surrounding lane stacks
    /// across the page. This keeps the calendar compact while the deadline
    /// rows beneath it can retain their natural readable width.
    pub fn profileCalendarLaneWidth(self: *const Model) f32 {
        const content_width = self.effectiveDashboardWidth();
        const preferred = switch (self.taxpayerDashboardLaneMode()) {
            .three_columns => (content_width - 32) / 3,
            .two_columns => (content_width - 16) / 2,
            .stacked => content_width,
        };
        return @min(content_width, @min(preferred, profile_calendar_lane_max_width));
    }

    /// Each deadline lane chooses its own dense representation from the
    /// width it actually receives, not from the window's coarse viewport
    /// class. This prevents a nominal desktop layout from squeezing table
    /// columns below their readable minimum.
    pub fn profileDeadlineTableLayout(self: *const Model) bool {
        return self.profileCalendarLaneWidth() >=
            profile_deadline_table_min_width;
    }

    pub fn profileDeadlineActionButtonSize(self: *const Model) f32 {
        return if (self.profileDeadlineTableLayout()) 36 else 44;
    }

    pub fn profileDeadlineActionColumnWidth(self: *const Model) f32 {
        return if (self.profileDeadlineTableLayout()) 82 else 98;
    }

    pub fn profileDeadlineDialogWidth(self: *const Model) f32 {
        const available = @max(@as(f32, 0), self.viewportWidth - 32);
        return @min(480, available);
    }

    pub fn profileCalendarDayHeight(self: *const Model) f32 {
        return calendarDayHeight(
            self.profileCalendarLaneWidth(),
            profile_calendar_day_max_height,
        );
    }

    fn dashboardAvailableWidth(self: *const Model) f32 {
        const navigation_width: f32 = if (self.sidebarExpandedVisible())
            280
        else if (self.sidebarRailVisible())
            72
        else
            0;
        const horizontal_padding: f32 = switch (self.viewportClass) {
            .phone => 32,
            .desktop => 64,
            else => 48,
        };
        return @max(@as(f32, 0), self.viewportWidth - navigation_width - horizontal_padding);
    }

    /// Automatic shell changes must never make dashboard layout decisions move
    /// backwards as the window gets wider. Before a wider shell class mounts
    /// more chrome, cap the effective width at that next class's entry width;
    /// the value then continues growing once the transition has completed.
    fn effectiveDashboardWidth(self: *const Model) f32 {
        const available = self.dashboardAvailableWidth();
        const continuity_cap: f32 = switch (self.viewportClass) {
            .phone => phone_breakpoint - 48,
            .compact => blk: {
                const rail_width: f32 = if (self.sidebarPreference == .hidden)
                    0
                else
                    72;
                break :blk compact_shell_breakpoint - rail_width - 48;
            },
            .rail_narrow => available,
            .rail_regular => blk: {
                const desktop_navigation_width: f32 = switch (self.sidebarPreference) {
                    .expanded => 280,
                    .rail => 72,
                    .hidden => 0,
                };
                break :blk rail_shell_breakpoint - desktop_navigation_width - 64;
            },
            .desktop => available,
        };
        return @min(available, continuity_cap);
    }

    /// Auxiliary surfaces sit above the shell while the page that opened
    /// them remains visible underneath.
    pub fn contentPage(self: *const Model) Page {
        return if (isAuxiliaryPage(self.page))
            self.overlayReturnPage
        else
            self.page;
    }

    /// Sidebar selection is context, not a permanent decoration. Global tools
    /// must not imply that their data is filtered by whichever profile was
    /// selected most recently.
    pub fn taxpayerNavigationSelectionVisible(self: *const Model) bool {
        return switch (self.contentPage()) {
            .taxpayer_dashboard,
            .tax_form_profile,
            .form_0605,
            .form_0619_e,
            .form_0619_f,
            .form_1601_c,
            .form_1701,
            .form_1701q,
            .form_1702_rt,
            .form_1702_mx,
            .form_2550q,
            .form_2551q,
            => true,
            .profile_setup => !self.taxProfiles.editing_new,
            else => false,
        };
    }

    pub fn shellVisible(self: *const Model) bool {
        return !isAuxiliaryPage(self.page);
    }

    fn isConstrainedViewport(self: *const Model) bool {
        return self.viewportClass == .phone or self.viewportClass == .compact;
    }

    pub fn currentPageTitle(self: *const Model) []const u8 {
        return switch (self.page) {
            .global_dashboard => "Global Dashboard",
            .taxpayer_dashboard => "Taxpayer Dashboard",
            .profile_setup => "Taxpayer Profile",
            .tax_form_profile => "Tax Form Profile",
            .import_data => "Import Data",
            .background_tasks => "Background Tasks",
            .tax_calendar => "Tax Calendars",
            .settings => "Settings",
            .screen_gallery => "Screen Gallery",
            .form_0605 => "BIR Form 0605",
            .form_0619_e => "BIR Form 0619-E",
            .form_0619_f => "BIR Form 0619-F",
            .form_1601_c => "BIR Form 1601-C",
            .form_1701 => "BIR Form 1701",
            .form_1701q => "BIR Form 1701Q",
            .form_1702_rt => "BIR Form 1702-RT",
            .form_1702_mx => "BIR Form 1702-MX",
            .form_2550q => "BIR Form 2550Q",
            .form_2551q => "BIR Form 2551Q",
            .aux_lock_screen => "Locked",
            .aux_profile_auth => "Profile Authentication",
            .aux_admin_auth => "Administrator Authentication",
            .aux_command_palette => "Command Palette",
            .aux_html_preview => "Print Preview",
            .aux_email_confirmation => "Email Confirmation",
            .aux_debug_log => "Background Task Log",
        };
    }

    pub fn sidebarProfileSearchValue(self: *const Model) []const u8 {
        return self.sidebarProfileSearchBuffer.text();
    }

    pub fn profileRows(self: *const Model) []const profile_ui.ProfileRow {
        return self.taxProfiles.rows();
    }

    /// Registrations of one taxpayer are listed together, head office first,
    /// so a branch reads as part of that taxpayer rather than as an unrelated
    /// entry that happens to share a name. Ordering is presentation only: each
    /// row keeps its own slot, and selection is unaffected.
    ///
    /// No filtering happens here: the loaded rows already ARE the search
    /// result, answered by the store. Re-filtering the text would disagree
    /// with the store about punctuation — a TIN typed as bare digits matches
    /// there but not against the dashed display text.
    pub fn visibleProfileRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const profile_ui.ProfileRow {
        const all = self.taxProfiles.rows();
        const rows = arena.alloc(profile_ui.ProfileRow, all.len) catch return &.{};
        @memcpy(rows[0..all.len], all);
        const visible = rows[0..all.len];
        std.mem.sort(profile_ui.ProfileRow, visible, {}, profileRowPrecedes);
        return visible;
    }

    pub fn visibleProfileRowsEmpty(
        self: *const Model,
        arena: std.mem.Allocator,
    ) bool {
        return self.visibleProfileRows(arena).len == 0;
    }

    pub fn profileRowsEmptyTitle(self: *const Model) []const u8 {
        // With store-backed search, an empty row set during a query means no
        // taxpayer matched — not that none exist.
        if (self.taxProfiles.sidebarQuery().len != 0) return "No matching profiles";
        return "No tax profiles yet";
    }

    pub fn profileRowsEmptyMessage(self: *const Model) []const u8 {
        if (self.taxProfiles.sidebarQuery().len != 0) {
            return "Try a taxpayer name or TIN, or clear the search field.";
        }
        return "Add a profile once, then reuse its qualified fields on recurring forms.";
    }

    pub fn profileListTruncatedVisible(self: *const Model) bool {
        return self.taxProfiles.profileListTruncated();
    }

    pub fn profileListTruncatedLabel(self: *const Model) []const u8 {
        _ = self;
        return "Showing the first 1024 taxpayers. Search finds the rest.";
    }

    pub fn selectedTaxpayerRdo(self: *const Model) []const u8 {
        return self.taxProfiles.rdo.text();
    }

    pub fn hasSelectedTaxpayer(self: *const Model) bool {
        return self.taxProfiles.selectedProfileId() != null;
    }

    pub fn selectedTaxpayerName(self: *const Model) []const u8 {
        return self.taxProfiles.selectedName();
    }

    pub fn selectedTaxpayerTin(self: *const Model) []const u8 {
        return self.taxProfiles.selectedTin();
    }

    pub fn selectedTaxpayerKind(self: *const Model) []const u8 {
        return self.taxProfiles.selectedKindLabel();
    }

    pub fn selectedTaxpayerInitials(self: *const Model) []const u8 {
        return self.taxProfiles.selectedInitials();
    }

    pub fn selectedTaxpayerTaxType(self: *const Model) []const u8 {
        return self.taxProfiles.selectedTaxTypeLabel();
    }

    pub fn selectedTaxpayerSummary(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "TIN: {s} - Type: {s} - Tax Year {d} - {s}",
            .{
                self.taxProfiles.selectedTin(),
                self.taxProfiles.selectedKindLabel(),
                self.calendar.selected_year,
                self.taxProfiles.selectedTaxTypeLabel(),
            },
        ) catch "Taxpayer details unavailable";
    }

    pub fn selectedTaxpayerCalendarKey(self: *const Model) []const u8 {
        return self.taxProfiles.selectedProfileId() orelse "";
    }

    fn taxpayerFormDisabled(
        self: *const Model,
        form_code: []const u8,
    ) bool {
        return self.taxpayerFormDisabledForYear(
            self.calendar.selected_year,
            form_code,
        );
    }

    fn taxpayerFormDisabledForYear(
        self: *const Model,
        tax_year: i32,
        form_code: []const u8,
    ) bool {
        if (!self.hasSelectedTaxpayer()) return true;
        return !self.taxProfiles.formAvailable(
            tax_year,
            form_code,
        );
    }

    fn taxpayerForm0605Disabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("0605");
    }

    fn taxpayerForm0619EDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("0619E");
    }

    fn taxpayerForm0619FDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("0619F");
    }

    fn taxpayerForm1601CDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("1601C");
    }

    fn taxpayerForm1701Disabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("1701");
    }

    fn taxpayerForm1701QDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("1701Q");
    }

    fn taxpayerForm1702RTDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("1702RT");
    }

    fn taxpayerForm1702MXDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("1702MX");
    }

    fn taxpayerForm2550QDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("2550Q");
    }

    fn taxpayerForm2551QDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("2551Q");
    }

    pub fn formFilerTin(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.renderedFormTin(.filer, arena);
    }

    pub fn formFilingPeriodLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const period = self.formProfiles.filingPeriod() orelse
            form_period.FilingPeriod{ .quarterly = .{
                .tax_year = self.formProfiles.taxYear(),
                .quarter = self.formProfiles.quarter(),
            } };
        var buffer: [48]u8 = undefined;
        const label = period.label(&buffer) catch return "Filing period unavailable";
        return arena.dupe(u8, label) catch label;
    }

    pub fn formFilingYear(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const period = self.formProfiles.filingPeriod() orelse return "";
        return std.fmt.allocPrint(arena, "{d}", .{period.taxYear()}) catch "";
    }

    pub fn formFilingMonthYear(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const period = self.formProfiles.filingPeriod() orelse return "";
        return switch (period) {
            .monthly => |value| std.fmt.allocPrint(
                arena,
                "{d:0>2} / {d:0>4}",
                .{ value.month, value.tax_year },
            ) catch "",
            else => "",
        };
    }

    pub fn formFilingPeriodStart(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const period = self.formProfiles.filingPeriod() orelse return "";
        const date = switch (period) {
            .monthly => |value| profile_model.Date.init(
                value.tax_year,
                value.month,
                1,
            ) catch return "",
            .quarterly => |value| profile_model.Date.init(
                value.tax_year,
                (value.quarter - 1) * 3 + 1,
                1,
            ) catch return "",
            .annual => |value| profile_model.Date.init(value.tax_year, 1, 1) catch return "",
            .on_demand => return "",
        };
        return formatFilingDate(arena, date);
    }

    pub fn formFilingPeriodEnd(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const period = self.formProfiles.filingPeriod() orelse return "";
        const date = switch (period) {
            .monthly => |value| monthEndDate(value.tax_year, value.month),
            .quarterly => |value| monthEndDate(value.tax_year, value.quarter * 3),
            .annual => |value| profile_model.Date.init(value.tax_year, 12, 31) catch return "",
            .on_demand => return "",
        };
        return formatFilingDate(arena, date);
    }

    pub fn formFilerRdo(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.rdo_code);
    }

    pub fn formFilerTaxpayerName(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.taxpayer_name);
    }

    pub fn formFilerRegisteredName(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.registered_name);
    }

    pub fn formFilerRegisteredAddress(self: *const Model) []const u8 {
        return self.filerContactText(.registered_address);
    }

    pub fn formFilerZipCode(self: *const Model) []const u8 {
        return self.filerContactText(.zip_code);
    }

    /// A filing shows the contact detail it was given, falling back to the one
    /// the taxpayer's profile supplied when the draft was composed.
    fn filerContactText(
        self: *const Model,
        contact_field: percentage_tax_ui.FilingContactField,
    ) []const u8 {
        if (self.percentageTax.contactOverridden(contact_field)) {
            return self.percentageTax.contactOverrideText(contact_field);
        }
        return self.formProfiles.filerText(contact_field.reusable());
    }

    pub fn formFilerContactNumber(self: *const Model) []const u8 {
        return self.filerContactText(.contact_number);
    }

    pub fn formFilingContactEditable(self: *const Model) bool {
        return self.percentageTax.editable;
    }

    /// Says where the contact details on this filing came from. Provenance is
    /// text, not a colour, because it is the fact that matters.
    pub fn formFilingContactProvenance(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const changed = self.percentageTax.overriddenContactCount();
        if (changed == 0) return "From profile";
        if (changed == 1) return "1 contact detail changed for this filing";
        return std.fmt.allocPrint(
            arena,
            "{d} contact details changed for this filing",
            .{changed},
        ) catch "Changed for this filing";
    }

    pub fn formFilingContactResetDisabled(self: *const Model) bool {
        return self.percentageTax.overriddenContactCount() == 0 or
            !self.percentageTax.editable;
    }

    pub fn formFilerEmailAddress(self: *const Model) []const u8 {
        return self.filerContactText(.email_address);
    }

    pub fn formFilerDateOfBirth(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const value = self.formProfiles.reusableValue(
            .filer,
            .date_of_birth,
        ) orelse return "";
        return switch (value.*) {
            .date_of_birth => |date| std.fmt.allocPrint(
                arena,
                "{d:0>2} / {d:0>2} / {d:0>4}",
                .{ date.month, date.day, date.year },
            ) catch "",
            else => unreachable,
        };
    }

    pub fn formFilerCitizenship(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.citizenship);
    }

    pub fn formFilerForeignTaxNumber(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.foreign_tax_number);
    }

    pub fn formFilerLineOfBusiness(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.line_of_business);
    }

    pub fn formFilerAtc(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.atc);
    }

    pub fn formFilerTaxType(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.tax_type);
    }

    pub fn formFilerGovernmentWithholdingAgent(
        self: *const Model,
    ) []const u8 {
        return self.formProfiles.filerText(
            .government_withholding_agent,
        );
    }

    pub fn formFilerSpecialRateBasis(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.special_rate_basis);
    }

    pub fn formSpouseTin(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.renderedFormTin(.spouse, arena);
    }

    pub fn formSpouseRdo(self: *const Model) []const u8 {
        return self.formProfiles.spouseText(.rdo_code);
    }

    pub fn formSpouseName(self: *const Model) []const u8 {
        return self.formProfiles.spouseText(.taxpayer_name);
    }

    fn renderedFormTin(
        self: *const Model,
        role: form_ids.Role,
        arena: std.mem.Allocator,
    ) []const u8 {
        const value = self.formProfiles.reusableValue(
            role,
            .tin,
        ) orelse return "";
        return switch (value.*) {
            .tin => |tin| blk: {
                const output = arena.alloc(u8, 24) catch break :blk "";
                break :blk tin.write(output) catch "";
            },
            else => unreachable,
        };
    }

    pub fn incomeTaxYear(self: *const Model) []const u8 {
        return self.incomeTax.value(.tax_year);
    }

    pub fn incomeTaxQuarter(self: *const Model) []const u8 {
        return self.incomeTax.quarterValue();
    }

    pub fn incomeTaxQuarterQ1Selected(self: *const Model) bool {
        return self.incomeTax.quarterSelected(1);
    }

    pub fn incomeTaxQuarterQ2Selected(self: *const Model) bool {
        return self.incomeTax.quarterSelected(2);
    }

    pub fn incomeTaxQuarterQ3Selected(self: *const Model) bool {
        return self.incomeTax.quarterSelected(3);
    }

    pub fn incomeTaxAmendedReturn(self: *const Model) []const u8 {
        return self.incomeTax.amendedReturnValue();
    }

    pub fn incomeTaxSheetsAttached(self: *const Model) []const u8 {
        return self.incomeTax.value(.sheets_attached);
    }

    pub fn incomeTaxElection(self: *const Model) []const u8 {
        return self.incomeTax.electionValue();
    }

    pub fn incomeTaxElectionGraduatedSelected(
        self: *const Model,
    ) bool {
        return self.incomeTax.electionSelected(.graduated);
    }

    pub fn incomeTaxElectionEightPercentSelected(
        self: *const Model,
    ) bool {
        return self.incomeTax.electionSelected(.eight_percent);
    }

    pub fn incomeTaxInputsDisabled(self: *const Model) bool {
        return self.incomeTax.inputsDisabled();
    }

    pub fn incomeTaxGraduatedSales(self: *const Model) []const u8 {
        return self.incomeTax.value(
            .graduated_sales_revenues_receipts,
        );
    }

    pub fn incomeTaxGraduatedCost(self: *const Model) []const u8 {
        return self.incomeTax.value(
            .graduated_cost_of_sales_or_services,
        );
    }

    pub fn incomeTaxGraduatedDeductions(self: *const Model) []const u8 {
        return self.incomeTax.value(
            .graduated_allowable_deductions,
        );
    }

    pub fn incomeTaxGraduatedTaxableIncome(
        self: *const Model,
    ) []const u8 {
        return self.incomeTax.value(.graduated_taxable_income);
    }

    pub fn incomeTaxGraduatedTaxDue(self: *const Model) []const u8 {
        return self.incomeTax.value(.graduated_income_tax_due);
    }

    pub fn incomeTaxGraduatedInputsDisabled(self: *const Model) bool {
        return self.incomeTax.graduatedInputsDisabled();
    }

    pub fn incomeTaxEightGrossSales(self: *const Model) []const u8 {
        return self.incomeTax.value(
            .eight_percent_gross_sales_or_receipts,
        );
    }

    pub fn incomeTaxEightNonOperatingIncome(
        self: *const Model,
    ) []const u8 {
        return self.incomeTax.value(
            .eight_percent_non_operating_income,
        );
    }

    pub fn incomeTaxEightTaxDue(self: *const Model) []const u8 {
        return self.incomeTax.value(.eight_percent_tax_due);
    }

    pub fn incomeTaxEightPercentInputsDisabled(
        self: *const Model,
    ) bool {
        return self.incomeTax.eightPercentInputsDisabled();
    }

    pub fn incomeTaxPriorQuarterPayments(self: *const Model) []const u8 {
        return self.incomeTax.value(.prior_quarter_income_tax_payments);
    }

    pub fn incomeTaxWithheld2307(self: *const Model) []const u8 {
        return self.incomeTax.value(.creditable_tax_withheld_2307);
    }

    pub fn incomeTaxOtherCredits(self: *const Model) []const u8 {
        return self.incomeTax.value(.other_tax_credits_or_payments);
    }

    pub fn incomeTaxPayableOrOverpayment(
        self: *const Model,
    ) []const u8 {
        return self.incomeTax.value(.tax_payable_or_overpayment);
    }

    pub fn incomeTaxSurcharge(self: *const Model) []const u8 {
        return self.incomeTax.value(.surcharge);
    }

    pub fn incomeTaxInterest(self: *const Model) []const u8 {
        return self.incomeTax.value(.interest);
    }

    pub fn incomeTaxCompromise(self: *const Model) []const u8 {
        return self.incomeTax.value(.compromise);
    }

    pub fn incomeTaxPaymentRows(
        self: *const Model,
    ) []const income_tax_ui.PaymentRow {
        return self.incomeTax.paymentRows();
    }

    pub fn incomeTaxPaymentAddDisabled(self: *const Model) bool {
        return self.incomeTax.paymentAddDisabled();
    }

    pub fn incomeTaxPaymentRemoveDisabled(self: *const Model) bool {
        return self.incomeTax.paymentRemoveDisabled();
    }

    pub fn incomeTaxPaymentEditorVisible(self: *const Model) bool {
        return self.incomeTax.paymentEditorVisible();
    }

    pub fn incomeTaxPaymentMethod(self: *const Model) []const u8 {
        return self.incomeTax.paymentMethodValue();
    }

    pub fn incomeTaxPaymentMethodCashSelected(
        self: *const Model,
    ) bool {
        return self.incomeTax.paymentMethodSelected(.cash);
    }

    pub fn incomeTaxPaymentMethodCheckSelected(
        self: *const Model,
    ) bool {
        return self.incomeTax.paymentMethodSelected(.check);
    }

    pub fn incomeTaxPaymentMethodTaxDebitMemoSelected(
        self: *const Model,
    ) bool {
        return self.incomeTax.paymentMethodSelected(.tax_debit_memo);
    }

    pub fn incomeTaxPaymentMethodOtherSelected(
        self: *const Model,
    ) bool {
        return self.incomeTax.paymentMethodSelected(.other);
    }

    pub fn incomeTaxPaymentBankOrAgency(self: *const Model) []const u8 {
        return self.incomeTax.paymentValue(.bank_or_agency);
    }

    pub fn incomeTaxPaymentReference(self: *const Model) []const u8 {
        return self.incomeTax.paymentValue(.reference);
    }

    pub fn incomeTaxPaymentAmount(self: *const Model) []const u8 {
        return self.incomeTax.paymentValue(.amount);
    }

    pub fn incomeTaxNoticeVisible(self: *const Model) bool {
        return self.incomeTax.noticeVisible();
    }

    pub fn incomeTaxNotice(self: *const Model) []const u8 {
        return self.incomeTax.noticeText();
    }

    pub fn incomeTaxNoticeTone(self: *const Model) []const u8 {
        return self.incomeTax.noticeTone();
    }

    pub fn incomeTaxTotalTaxPayable(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.incomeTax.totalTaxPayableText(arena);
    }

    pub fn incomeTaxSaveDisabled(self: *const Model) bool {
        return self.formProfiles.saveDisabled() or
            self.incomeTax.saveDisabled();
    }

    pub fn exact1701QReady(self: *const Model) bool {
        return self.exact1701Q.ready();
    }

    pub fn exact1701QRows(
        self: *const Model,
    ) []const exact_1701q_native.ControlRow {
        return self.exact1701Q.rows();
    }

    pub fn exact1701QPhase(self: *const Model) []const u8 {
        return self.exact1701Q.phaseLabel();
    }

    pub fn exact1701QFilingContext(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.exact1701Q.filingContextLabel(arena);
    }

    pub fn exact1701QHistory(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.exact1701Q.historyLabel(arena);
    }

    pub fn exact1701QNoticeVisible(self: *const Model) bool {
        return self.exact1701Q.noticeVisible();
    }

    pub fn exact1701QNotice(self: *const Model) []const u8 {
        return self.exact1701Q.noticeText();
    }

    pub fn exact1701QNoticeTone(self: *const Model) []const u8 {
        return self.exact1701Q.noticeTone();
    }

    pub fn exact1701QSelectedVisible(self: *const Model) bool {
        return self.exact1701Q.selectedVisible();
    }

    pub fn exact1701QSelectedId(self: *const Model) []const u8 {
        return self.exact1701Q.selectedId();
    }

    pub fn exact1701QSelectedMeta(self: *const Model) []const u8 {
        return self.exact1701Q.selectedMeta();
    }

    pub fn exact1701QSelectedValueLabel(
        self: *const Model,
    ) []const u8 {
        return self.exact1701Q.selectedValueLabel();
    }

    pub fn exact1701QSelectedIsRadio(self: *const Model) bool {
        return self.exact1701Q.selectedIsRadio();
    }

    pub fn exact1701QSelectedRadioLabel(self: *const Model) []const u8 {
        return self.exact1701Q.selectedRadioLabel();
    }

    pub fn exact1701QSelectedCanToggleRadio(
        self: *const Model,
    ) bool {
        return self.exact1701Q.selectedCanToggleRadio();
    }

    pub fn exact1701QSelectedCanReveal(self: *const Model) bool {
        return self.exact1701Q.selectedCanReveal();
    }

    pub fn exact1701QSelectedRevealLabel(
        self: *const Model,
    ) []const u8 {
        return self.exact1701Q.selectedRevealLabel();
    }

    pub fn exact1701QSelectedEditorText(
        self: *const Model,
    ) []const u8 {
        return self.exact1701Q.selectedEditorText();
    }

    pub fn exact1701QSelectedCanEdit(self: *const Model) bool {
        return self.exact1701Q.selectedCanEdit();
    }

    pub fn exact1701QCanCalculate(self: *const Model) bool {
        return self.exact1701Q.canCalculate();
    }

    pub fn exact1701QCanValidateSave(self: *const Model) bool {
        return self.exact1701Q.canValidateSave();
    }

    pub fn exact1701QCanGenerateEditableCandidate(
        self: *const Model,
    ) bool {
        return self.exact1701Q.canGenerateEditableCandidate();
    }

    pub fn exact1701QCanValidateFull(self: *const Model) bool {
        return self.exact1701Q.canValidateFull();
    }

    pub fn exact1701QCanGenerateFinalCandidate(
        self: *const Model,
    ) bool {
        return self.exact1701Q.canGenerateFinalCandidate();
    }

    pub fn exact1701QCandidateVisible(self: *const Model) bool {
        return self.exact1701Q.candidateVisible();
    }

    pub fn exact1701QCandidateLabel(self: *const Model) []const u8 {
        return self.exact1701Q.candidateLabel();
    }

    pub fn exact1701QCandidateQualification(
        self: *const Model,
    ) []const u8 {
        return self.exact1701Q.candidateQualificationLabel();
    }

    pub fn exact1701QCandidateShape(self: *const Model) []const u8 {
        return self.exact1701Q.candidateShapeLabel();
    }

    pub fn exact1701QCandidateMasked(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.exact1701Q.candidateMaskedLabel(arena);
    }

    pub fn exact1701QGeneratedRevealed(self: *const Model) bool {
        return self.exact1701Q.generatedArtifactRevealed();
    }

    pub fn exact1701QGeneratedRevealLabel(
        self: *const Model,
    ) []const u8 {
        return self.exact1701Q.generatedArtifactRevealLabel();
    }

    pub fn exact1701QGeneratedText(self: *const Model) []const u8 {
        return self.exact1701Q.generatedArtifactText();
    }

    pub fn percentageTaxEditable(self: *const Model) bool {
        return self.percentageTax.editable;
    }

    pub fn percentageTaxPeriodBasis(self: *const Model) []const u8 {
        return self.percentageTax.periodBasisText();
    }

    pub fn percentageTaxPeriodCalendarSelected(self: *const Model) bool {
        return self.percentageTax.periodCalendarSelected();
    }

    pub fn percentageTaxPeriodFiscalSelected(self: *const Model) bool {
        return self.percentageTax.periodFiscalSelected();
    }

    pub fn percentageTaxYearEndMonth(self: *const Model) []const u8 {
        return self.percentageTax.year_end_month.text();
    }

    pub fn percentageTaxQuarter(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.percentageTax.quarterText(arena);
    }

    pub fn percentageTaxYear(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.percentageTax.yearText(arena);
    }

    pub fn percentageTaxSheetsAttached(self: *const Model) []const u8 {
        return self.percentageTax.sheets_attached.text();
    }

    pub fn percentageTaxReturnOption(self: *const Model) []const u8 {
        return self.percentageTax.returnOptionText();
    }

    pub fn percentageTaxAmendedReturn(self: *const Model) []const u8 {
        return self.percentageTax.amendedReturnText();
    }

    pub fn percentageTaxRelief(self: *const Model) []const u8 {
        return self.percentageTax.taxReliefText();
    }

    pub fn percentageTaxReliefNoneSelected(self: *const Model) bool {
        return self.percentageTax.taxReliefNoneSelected();
    }

    pub fn percentageTaxReliefSpecifiedSelected(self: *const Model) bool {
        return self.percentageTax.taxReliefSpecifiedSelected();
    }

    pub fn percentageTaxReliefReference(self: *const Model) []const u8 {
        return self.percentageTax.tax_relief_reference.text();
    }

    pub fn percentageTaxElection(self: *const Model) []const u8 {
        return self.percentageTax.incomeTaxRateElectionText();
    }

    pub fn percentageTaxElectionGraduatedSelected(
        self: *const Model,
    ) bool {
        return self.percentageTax.graduatedElectionSelected();
    }

    pub fn percentageTaxElectionEightPercentSelected(
        self: *const Model,
    ) bool {
        return self.percentageTax.eightPercentElectionSelected();
    }

    pub fn percentageTaxLine1Atc(self: *const Model) []const u8 {
        return self.percentageTax.scheduleAtcText(0);
    }

    pub fn percentageTaxLine1Base(self: *const Model) []const u8 {
        return self.percentageTax.scheduleTaxBaseText(0);
    }

    pub fn percentageTaxLine1Rate(self: *const Model) []const u8 {
        return self.percentageTax.scheduleRateText(0);
    }

    pub fn percentageTaxLine1Due(self: *const Model) []const u8 {
        return self.percentageTax.scheduleDueText(0);
    }

    pub fn percentageTaxLine2Atc(self: *const Model) []const u8 {
        return self.percentageTax.scheduleAtcText(1);
    }

    pub fn percentageTaxLine2Base(self: *const Model) []const u8 {
        return self.percentageTax.scheduleTaxBaseText(1);
    }

    pub fn percentageTaxLine2Rate(self: *const Model) []const u8 {
        return self.percentageTax.scheduleRateText(1);
    }

    pub fn percentageTaxLine2Due(self: *const Model) []const u8 {
        return self.percentageTax.scheduleDueText(1);
    }

    pub fn percentageTaxTotalDue(self: *const Model) []const u8 {
        return self.percentageTax.totalDueText();
    }

    pub fn percentageTaxCreditableWithheld(
        self: *const Model,
    ) []const u8 {
        return self.percentageTax.creditable_percentage_tax_withheld.text();
    }

    pub fn percentageTaxPaidPrevious(self: *const Model) []const u8 {
        return self.percentageTax.paid_in_previous_return.text();
    }

    pub fn percentageTaxOtherCredit(self: *const Model) []const u8 {
        return self.percentageTax.other_credit_or_payment.text();
    }

    pub fn percentageTaxTotalCredits(self: *const Model) []const u8 {
        return self.percentageTax.totalCreditsText();
    }

    pub fn percentageTaxNetTax(self: *const Model) []const u8 {
        return self.percentageTax.netTaxText();
    }

    pub fn percentageTaxSurcharge(self: *const Model) []const u8 {
        return self.percentageTax.surcharge.text();
    }

    pub fn percentageTaxInterest(self: *const Model) []const u8 {
        return self.percentageTax.interest.text();
    }

    pub fn percentageTaxCompromise(self: *const Model) []const u8 {
        return self.percentageTax.compromise.text();
    }

    pub fn percentageTaxDisposition(self: *const Model) []const u8 {
        return self.percentageTax.dispositionText();
    }

    pub fn percentageTaxDispositionNotApplicableSelected(
        self: *const Model,
    ) bool {
        return self.percentageTax.dispositionSelected(.not_applicable);
    }

    pub fn percentageTaxDispositionRefundSelected(
        self: *const Model,
    ) bool {
        return self.percentageTax.dispositionSelected(.refund);
    }

    pub fn percentageTaxDispositionTaxCreditSelected(
        self: *const Model,
    ) bool {
        return self.percentageTax.dispositionSelected(
            .tax_credit_certificate,
        );
    }

    pub fn percentageTaxDispositionCarryOverSelected(
        self: *const Model,
    ) bool {
        return self.percentageTax.dispositionSelected(.carry_over);
    }

    pub fn percentageTaxTotalAmountPayable(
        self: *const Model,
    ) []const u8 {
        return self.percentageTax.totalAmountPayableText();
    }

    pub fn percentageTaxValidationStatus(self: *const Model) []const u8 {
        return self.percentageTax.validationText();
    }

    pub fn formProfileContextTitle(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const revision = self.formProfiles.formRevision() orelse
            return "Tax profile prefill";
        return std.fmt.allocPrint(
            arena,
            "Tax profile prefill · BIR Form {s}",
            .{revision.code.asSlice()},
        ) catch "Tax profile prefill";
    }

    pub fn formProfileStatus(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.formProfiles.draftStatus()) |status| {
            return std.fmt.allocPrint(
                arena,
                "Immutable profile snapshot · draft {s}",
                .{status.text()},
            ) catch "Immutable profile snapshot";
        }
        const effective_on = self.formProfiles.profileAsOf() orelse
            return "Select a taxpayer profile to qualify reusable fields.";
        var date_buffer: [10]u8 = undefined;
        const date = effective_on.writeIso(&date_buffer);
        if (self.formProfiles.projectionAccepted()) {
            return std.fmt.allocPrint(
                arena,
                "Qualified reusable fields as of {s}",
                .{date},
            ) catch "Reusable fields qualified";
        }
        return std.fmt.allocPrint(
            arena,
            "Profile qualification needs attention as of {s}",
            .{date},
        ) catch "Profile qualification needs attention";
    }

    pub fn formProfileNotice(self: *const Model) []const u8 {
        return self.formProfiles.noticeText();
    }

    pub fn formProfileCanSaveDraft(self: *const Model) bool {
        if (self.formProfiles.saveDisabled()) return false;
        const revision = self.formProfiles.formRevision() orelse return false;
        if (std.mem.eql(u8, revision.code.asSlice(), "2551Q")) {
            return self.percentageTax.canBuild();
        }
        if (std.mem.eql(u8, revision.code.asSlice(), "1701Q")) {
            // The exact occurrence persistence adapter is intentionally not
            // wired yet. Never authorize the older coarse 1701Q draft path.
            return false;
        }
        return true;
    }

    pub fn formProfileNeedsActivitySelection(self: *const Model) bool {
        const revision = self.formProfiles.formRevision() orelse return false;
        const definition = form_catalog.findForm(
            revision.code.asSlice(),
        ) orelse return false;
        var consumes_activity = false;
        for (definition.fields) |catalog_field| {
            if (catalog_field.provenance != .profile) continue;
            const key = catalog_field.profile_key orelse continue;
            if (std.mem.eql(u8, key, "atc") or
                std.mem.eql(u8, key, "line_of_business"))
            {
                consumes_activity = true;
                break;
            }
        }
        if (!consumes_activity) return false;
        const candidates = self.formProfiles.activityCandidates(.filer);
        var effective_count: usize = 0;
        for (candidates) |candidate| {
            if (!candidate.effective_on_profile_date) continue;
            effective_count += 1;
            if (candidate.selected) return false;
        }
        return effective_count > 1;
    }

    pub fn formProfileHasSpouseRole(self: *const Model) bool {
        const revision = self.formProfiles.formRevision() orelse return false;
        const definition = form_catalog.findForm(
            revision.code.asSlice(),
        ) orelse return false;
        for (definition.profile_roles) |role| {
            if (role.role == .spouse) return true;
        }
        return false;
    }

    pub fn formProfileHasSpouseBinding(self: *const Model) bool {
        for (self.formProfiles.spouseCandidates()) |candidate| {
            if (candidate.selected) return true;
        }
        return self.formProfiles.roleBinding(.spouse) != null;
    }

    pub fn formActivityRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const FormProfileChoiceRow {
        const candidates = self.formProfiles.activityCandidates(.filer);
        const rows = arena.alloc(FormProfileChoiceRow, candidates.len) catch
            return &.{};
        var row_count: usize = 0;
        for (candidates, 0..) |*candidate, index| {
            if (!candidate.effective_on_profile_date) continue;
            const atc = if (candidate.atc) |*value|
                value.asSlice()
            else
                "no ATC";
            rows[row_count] = .{
                .id = index,
                .stable_id = candidate.id.asSlice(),
                .name = std.fmt.allocPrint(
                    arena,
                    "{s} · {s}",
                    .{ candidate.line_of_business.asSlice(), atc },
                ) catch candidate.line_of_business.asSlice(),
                .selected = candidate.selected,
            };
            row_count += 1;
        }
        return rows[0..row_count];
    }

    pub fn formSpouseRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const FormProfileChoiceRow {
        const candidates = self.formProfiles.spouseCandidates();
        const rows = arena.alloc(FormProfileChoiceRow, candidates.len) catch
            return &.{};
        for (candidates, 0..) |*candidate, index| {
            const tin_buffer = arena.alloc(u8, 20) catch return &.{};
            const tin = candidate.tin.write(tin_buffer) catch
                candidate.tin.asDigits();
            rows[index] = .{
                .id = index,
                .stable_id = candidate.profile_id.asSlice(),
                .name = std.fmt.allocPrint(
                    arena,
                    "{s} · TIN {s}",
                    .{ candidate.name.asSlice(), tin },
                ) catch candidate.name.asSlice(),
                .selected = candidate.selected,
            };
        }
        return rows;
    }

    pub fn profileEditorTitle(self: *const Model) []const u8 {
        return switch (self.taxProfiles.profileMode()) {
            .creating => "Create Taxpayer Profile",
            .viewing => "Tax Profile",
            .editing => "Edit Tax Profile",
        };
    }

    pub fn editingNewProfile(self: *const Model) bool {
        return self.taxProfiles.editing_new;
    }

    pub fn profileInlineBackVisible(self: *const Model) bool {
        return self.page == .profile_setup and
            !self.sidebarLauncherVisible();
    }

    pub fn profileInlineBackDisabled(self: *const Model) bool {
        _ = self;
        return false;
    }

    pub fn profileBackLabel(self: *const Model) []const u8 {
        return if (self.profileEditorOrigin == .taxpayer_dashboard)
            "Back to tax profile"
        else
            "Back";
    }

    pub fn profileSaveLabel(self: *const Model) []const u8 {
        return if (self.taxProfiles.editing_new)
            "Create Profile"
        else
            "Save changes";
    }

    pub fn profileSaveDisabled(self: *const Model) bool {
        if (self.taxProfiles.editing_new) {
            if (self.taxProfiles.saveDisabled()) return true;
            if (!self.profileBusinessFieldsVisible()) return false;
            return !self.regLoaded or self.regLoadFailed or
                !self.regEditing() or
                self.profilePrimaryLineOfBusinessMissing() or
                self.profileEoptTierMissing() or
                !self.regPage.affordances().can_save;
        }
        if (!self.taxProfiles.profileEditing()) return true;
        const base_dirty = self.taxProfiles.profileDirty();
        const registration_dirty = self.regPage.dirty();
        if (!base_dirty and !registration_dirty) return true;
        if (!self.taxProfiles.profileDraftValid()) return true;
        if (self.profileBusinessFieldsVisible()) {
            if (!self.regLoaded or self.regLoadFailed or !self.regEditing()) {
                return true;
            }
            if (self.profilePrimaryLineOfBusinessMissing() or
                self.profileEoptTierMissing()) return true;
        }
        return registration_dirty and
            !self.regPage.affordances().can_save;
    }

    pub fn profileCancelDisabled(self: *const Model) bool {
        if (self.taxProfiles.editing_new) {
            return self.taxProfiles.cancelDisabled();
        }
        if (!self.taxProfiles.profileEditing()) return true;
        return !self.taxProfiles.profileDirty() and !self.regPage.dirty();
    }

    pub fn profileTaxViewing(self: *const Model) bool {
        return self.taxProfiles.profileViewing();
    }

    pub fn profileTaxEditorVisible(self: *const Model) bool {
        return !self.taxProfiles.profileViewing();
    }

    pub fn profileEditorActionsVisible(self: *const Model) bool {
        return (self.profileTaxActive() and self.profileTaxEditorVisible()) or
            self.profileEmailActive();
    }

    pub fn profileDirtyNavigationVisible(self: *const Model) bool {
        return self.pendingProfileNavigation != null;
    }

    pub fn profileDirtyNavigationTitle(self: *const Model) []const u8 {
        return if (self.regPage.dirty() and self.taxProfiles.profileDirty())
            "Discard unsaved Tax Profile and Registration changes?"
        else if (self.regPage.dirty())
            "Discard unsaved Registration changes?"
        else
            "Discard unsaved Tax Profile changes?";
    }

    pub fn profileDirtyNavigationBody(self: *const Model) []const u8 {
        return if (self.regPage.dirty() and self.taxProfiles.profileDirty())
            "Your unsaved Tax Profile and Registration changes will be discarded. Stay here to keep editing, or discard them and continue."
        else if (self.regPage.dirty())
            "Your unsaved Registration changes will be discarded. Stay here to keep editing, or discard them and continue."
        else
            "Your unsaved Tax Profile changes will be discarded. Stay here to keep editing, or discard them and continue.";
    }

    pub fn profileReadColumns(self: *const Model) u8 {
        return if (self.isConstrainedViewport()) 1 else 2;
    }

    pub fn profileNoticeVisible(self: *const Model) bool {
        return self.taxProfiles.noticeVisible();
    }

    pub fn profileNotice(self: *const Model) []const u8 {
        return self.taxProfiles.noticeText();
    }

    pub fn profileNoticeSuccess(self: *const Model) bool {
        return self.taxProfiles.noticeSuccess();
    }

    pub fn profileNoticeFailure(self: *const Model) bool {
        return self.taxProfiles.noticeFailure();
    }

    pub fn profileToastRegionVisible(self: *const Model) bool {
        return self.profileNoticeVisible() or
            self.profileCalendarExportNoticeVisible();
    }

    pub fn profileSubjectPickerOpen(self: *const Model) bool {
        return self.profileSubjectPickerVisible;
    }

    pub fn profileClassificationPickerOpen(self: *const Model) bool {
        return self.profileClassificationPickerVisible;
    }

    pub fn profileEoptPickerOpen(self: *const Model) bool {
        return self.profileEoptPickerVisible;
    }

    pub fn profileSubjectKindLabel(self: *const Model) []const u8 {
        return switch (self.taxProfiles.subject_kind) {
            .individual => "Individual",
            // Legacy rows normalize to an individual self-employed taxpayer;
            // the removed legal-type label must never leak back into the UI.
            .sole_proprietor => "Individual",
            .corporation => "Corporation",
            .partnership => "Partnership",
            .cooperative => "Cooperative",
            .estate => "Estate",
            .trust => "Trust",
            .other_legal_entity => "Other legal entity",
        };
    }

    pub fn profileIndividualSelected(self: *const Model) bool {
        return self.taxProfiles.subjectKindSelected(.individual);
    }

    pub fn profileSoleProprietorSelected(self: *const Model) bool {
        return self.taxProfiles.subjectKindSelected(.sole_proprietor);
    }

    pub fn profileNaturalPersonClassificationVisible(self: *const Model) bool {
        return self.taxProfiles.naturalPersonFieldsVisible();
    }

    pub fn profileNaturalPersonClassificationLabel(
        self: *const Model,
    ) []const u8 {
        return switch (self.taxProfiles.naturalPersonClassification()) {
            .classification_unknown => "Not yet recorded",
            .pure_compensation => "Purely Compensation",
            .self_employed => "Self-Employed / Professional",
            .mixed_income => "Mixed Income",
        };
    }

    pub fn profileClassificationUnknownSelected(self: *const Model) bool {
        return self.taxProfiles.classificationSelected(
            .classification_unknown,
        );
    }

    pub fn profilePureCompensationSelected(self: *const Model) bool {
        return self.taxProfiles.classificationSelected(.pure_compensation);
    }

    pub fn profileSelfEmployedSelected(self: *const Model) bool {
        return self.taxProfiles.classificationSelected(.self_employed);
    }

    pub fn profileMixedIncomeSelected(self: *const Model) bool {
        return self.taxProfiles.classificationSelected(.mixed_income);
    }

    pub fn profileCorporationSelected(self: *const Model) bool {
        return self.taxProfiles.subjectKindSelected(.corporation);
    }

    pub fn profilePartnershipSelected(self: *const Model) bool {
        return self.taxProfiles.subjectKindSelected(.partnership);
    }

    pub fn profileCooperativeSelected(self: *const Model) bool {
        return self.taxProfiles.subjectKindSelected(.cooperative);
    }

    pub fn profileEstateSelected(self: *const Model) bool {
        return self.taxProfiles.subjectKindSelected(.estate);
    }

    pub fn profileTrustSelected(self: *const Model) bool {
        return self.taxProfiles.subjectKindSelected(.trust);
    }

    pub fn profileOtherLegalSelected(self: *const Model) bool {
        return self.taxProfiles.subjectKindSelected(.other_legal_entity);
    }

    pub fn profileTradeNameVisible(self: *const Model) bool {
        return self.taxProfiles.tradeNameVisible();
    }

    pub fn profilePersonalFieldsVisible(self: *const Model) bool {
        return self.taxProfiles.naturalPersonFieldsVisible();
    }

    pub fn profileBusinessFieldsVisible(self: *const Model) bool {
        return self.taxProfiles.businessFieldsVisible();
    }

    pub fn profileRegistrationLoadFailureVisible(self: *const Model) bool {
        return !self.regLoaded or self.regLoadFailed;
    }

    pub fn profileEoptTierLabel(self: *const Model) []const u8 {
        if (!self.regLoaded or self.regLoadFailed) return "Not recorded";
        return self.regPage.eoptTierLabel();
    }

    fn profileEoptTierSelectionValid(self: *const Model) bool {
        const tier = self.regPage.eoptTier() orelse return false;
        return switch (tier) {
            .micro, .small, .medium, .large => true,
            .not_applicable => false,
        };
    }

    pub fn profileEoptTierMissing(self: *const Model) bool {
        return self.profileBusinessFieldsVisible() and
            !self.profileEoptTierSelectionValid();
    }

    pub fn profileEoptMicroSelected(self: *const Model) bool {
        return self.regPage.eoptTier() == .micro;
    }

    pub fn profileEoptSmallSelected(self: *const Model) bool {
        return self.regPage.eoptTier() == .small;
    }

    pub fn profileEoptMediumSelected(self: *const Model) bool {
        return self.regPage.eoptTier() == .medium;
    }

    pub fn profileEoptLargeSelected(self: *const Model) bool {
        return self.regPage.eoptTier() == .large;
    }

    pub fn profilePrimaryLineOfBusinessValue(self: *const Model) []const u8 {
        return self.profilePrimaryLineOfBusiness.text();
    }

    pub fn profilePrimaryLineOfBusinessDisplayValue(
        self: *const Model,
    ) []const u8 {
        const primary = self.regPage.primaryBusinessActivity() orelse
            return "Not recorded";
        return primary.line_of_business.asSlice();
    }

    pub fn profilePrimaryLineOfBusinessMissing(self: *const Model) bool {
        return self.profileBusinessFieldsVisible() and
            std.mem.trim(
                u8,
                self.profilePrimaryLineOfBusiness.text(),
                " \t\r\n",
            ).len == 0;
    }

    pub fn profilePersonalFieldsDisabled(self: *const Model) bool {
        return switch (self.taxProfiles.subject_kind) {
            .individual, .sole_proprietor => false,
            .corporation,
            .partnership,
            .cooperative,
            .estate,
            .trust,
            .other_legal_entity,
            => true,
        };
    }

    pub fn profileSourceManualSelected(self: *const Model) bool {
        return self.taxProfiles.source_kind == .manual_entry;
    }

    pub fn profileSourceImportedSelected(self: *const Model) bool {
        return self.taxProfiles.source_kind == .imported;
    }

    pub fn profileSourceMigratedSelected(self: *const Model) bool {
        return self.taxProfiles.source_kind == .migrated;
    }

    pub fn profileSourceReferenceDisabled(self: *const Model) bool {
        return self.taxProfiles.source_kind == .manual_entry;
    }

    pub fn profileGwaUnsetSelected(self: *const Model) bool {
        return self.taxProfiles.government_withholding_agent == .unset;
    }

    pub fn profileGwaNoSelected(self: *const Model) bool {
        return self.taxProfiles.government_withholding_agent == .no;
    }

    pub fn profileGwaYesSelected(self: *const Model) bool {
        return self.taxProfiles.government_withholding_agent == .yes;
    }

    pub fn profileTinValue(self: *const Model) []const u8 {
        return self.taxProfiles.tin.text();
    }

    pub fn profileRdoValue(self: *const Model) []const u8 {
        return self.taxProfiles.rdo.text();
    }

    pub fn profileTinSegmentOneValue(self: *const Model) []const u8 {
        return self.profileTinSegments[0].text();
    }

    pub fn profileTinSegmentTwoValue(self: *const Model) []const u8 {
        return self.profileTinSegments[1].text();
    }

    pub fn profileTinSegmentThreeValue(self: *const Model) []const u8 {
        return self.profileTinSegments[2].text();
    }

    pub fn profileTinSegmentBranchValue(self: *const Model) []const u8 {
        return self.profileTinSegments[3].text();
    }

    fn profileTinSegmentAutofocus(
        self: *const Model,
        segment: u8,
    ) bool {
        if (self.profileTinFocusActive) {
            return self.profileTinFocusSegment == segment;
        }
        return segment == 0 and self.profileCompletionTarget == .tin;
    }

    pub fn profileTinSegmentOneAutofocus(self: *const Model) bool {
        return self.profileTinSegmentAutofocus(0);
    }

    pub fn profileTinSegmentTwoAutofocus(self: *const Model) bool {
        return self.profileTinSegmentAutofocus(1);
    }

    pub fn profileTinSegmentThreeAutofocus(self: *const Model) bool {
        return self.profileTinSegmentAutofocus(2);
    }

    pub fn profileTinSegmentBranchAutofocus(self: *const Model) bool {
        return self.profileTinSegmentAutofocus(3);
    }

    pub fn profileRdoQueryValue(self: *const Model) []const u8 {
        return self.profileRdoQuery.text();
    }

    pub fn profileRdoPickerOpen(self: *const Model) bool {
        return self.profileRdoPickerVisible;
    }

    pub fn profileRdoSelectionMissing(self: *const Model) bool {
        return !self.profileTaxViewing() and
            rdo_reference.findByCode(self.taxProfiles.rdo.text()) == null;
    }

    pub fn profileRdoOptionRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileRdoOptionRow {
        const matches = rdo_reference.search(self.profileRdoQuery.text());
        const rows = arena.alloc(ProfileRdoOptionRow, matches.len) catch
            return &.{};
        for (matches.items(), 0..) |candidate, row_index| {
            var entry_index: usize = 0;
            for (&rdo_reference.entries, 0..) |*entry, index| {
                if (entry == candidate) {
                    entry_index = index;
                    break;
                }
            }
            rows[row_index] = .{
                .id = entry_index,
                .code = candidate.code,
                .name = candidate.name,
                .selected = std.mem.eql(
                    u8,
                    candidate.code,
                    self.taxProfiles.rdo.text(),
                ),
            };
        }
        return rows;
    }

    pub fn profileNameValue(self: *const Model) []const u8 {
        return self.taxProfiles.display_name.text();
    }

    pub fn profileTradeNameValue(self: *const Model) []const u8 {
        return self.taxProfiles.trade_name.text();
    }

    pub fn profileAddressValue(self: *const Model) []const u8 {
        return self.taxProfiles.registered_address.text();
    }

    pub fn profileZipValue(self: *const Model) []const u8 {
        return self.taxProfiles.zip_code.text();
    }

    pub fn profilePhoneValue(self: *const Model) []const u8 {
        return self.taxProfiles.phone.text();
    }

    pub fn profileEmailValue(self: *const Model) []const u8 {
        return self.taxProfiles.email.text();
    }

    pub fn profileBirthDateValue(self: *const Model) []const u8 {
        return self.taxProfiles.birth_date.text();
    }

    pub fn profileCitizenshipValue(self: *const Model) []const u8 {
        return self.taxProfiles.citizenship.text();
    }

    pub fn profileForeignTaxNumberValue(self: *const Model) []const u8 {
        return self.taxProfiles.foreign_tax_number.text();
    }

    pub fn profileBusinessLineValue(self: *const Model) []const u8 {
        return self.taxProfiles.business_line.text();
    }

    pub fn profileAtcValue(self: *const Model) []const u8 {
        return self.taxProfiles.atc.text();
    }

    pub fn profileTaxTypeValue(self: *const Model) []const u8 {
        return self.taxProfiles.tax_type.text();
    }

    pub fn profileSpecialRateBasisValue(self: *const Model) []const u8 {
        return self.taxProfiles.special_rate_basis.text();
    }

    pub fn profileEffectiveFromValue(self: *const Model) []const u8 {
        return self.taxProfiles.effective_from.text();
    }

    pub fn profileEffectiveUntilValue(self: *const Model) []const u8 {
        return self.taxProfiles.effective_until.text();
    }

    pub fn profileSourceReferenceValue(self: *const Model) []const u8 {
        return self.taxProfiles.source_reference.text();
    }

    pub fn profileTinDisplayValue(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const raw = std.mem.trim(u8, self.profileTinValue(), " \t\r\n");
        if (raw.len == 0) return "Not recorded";
        const tin = segmented_tin.SegmentedTin.fromText(raw);
        const output = arena.alloc(
            u8,
            segmented_tin.maximum_digit_count +
                segmented_tin.segment_count - 1,
        ) catch return raw;
        return tin.writeFormatted(output) catch raw;
    }

    pub fn profileRdoDisplayValue(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const raw = std.mem.trim(u8, self.profileRdoValue(), " \t\r\n");
        const entry = rdo_reference.findByCode(raw) orelse
            return recordedProfileValue(raw);
        return std.fmt.allocPrint(
            arena,
            "{s} - {s}",
            .{ entry.code, entry.name },
        ) catch entry.code;
    }

    pub fn profileNameDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileNameValue());
    }

    pub fn profileTradeNameDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileTradeNameValue());
    }

    pub fn profileAddressDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileAddressValue());
    }

    pub fn profileZipDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileZipValue());
    }

    pub fn profilePhoneDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profilePhoneValue());
    }

    pub fn profileEmailDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileEmailValue());
    }

    pub fn profileBirthDateDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileBirthDateValue());
    }

    pub fn profileCitizenshipDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileCitizenshipValue());
    }

    pub fn profileForeignTaxNumberDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileForeignTaxNumberValue());
    }

    pub fn profileBusinessLineDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileBusinessLineValue());
    }

    pub fn profileAtcDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileAtcValue());
    }

    pub fn profileTaxTypeDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileTaxTypeValue());
    }

    pub fn profileSpecialRateBasisDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileSpecialRateBasisValue());
    }

    pub fn profileGovernmentWithholdingDisplayValue(self: *const Model) []const u8 {
        return switch (self.taxProfiles.government_withholding_agent) {
            .unset => "Not recorded",
            .no => "No",
            .yes => "Yes",
        };
    }

    pub fn profileEffectiveFromDisplayValue(self: *const Model) []const u8 {
        return recordedProfileValue(self.profileEffectiveFromValue());
    }

    fn profileSetupTypedYear(self: *const Model) ?i32 {
        const query = self.profileSetupYearQuery.text();
        if (query.len != 4) return null;
        return std.fmt.parseInt(i32, query, 10) catch null;
    }

    fn profileSetupConfiguredCount(self: *const Model, year: i32) ?usize {
        for (self.taxProfiles.formSetSummaries()) |summary| {
            if (summary.tax_year == year) return summary.active_form_count;
        }
        return null;
    }

    pub fn profileSetupYearLabel(self: *const Model) []const u8 {
        return self.taxProfiles.tax_year.text();
    }

    pub fn profileSetupYearPickerOpen(self: *const Model) bool {
        return self.profileSetupYearPickerVisible;
    }

    pub fn profileSetupYearQueryValue(self: *const Model) []const u8 {
        return self.profileSetupYearQuery.text();
    }

    /// Rows for the yearly setup combobox: the current year first, then every
    /// other configured year and a short recent window, descending. Older
    /// years stay reachable by typing rather than filling the list with
    /// decades of empty history.
    pub fn profileSetupYearOptions(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileSetupYearOption {
        const maximum = self.taxProfiles.maximumSetupYear();
        var years: [max_setup_year_options]i32 = undefined;
        var count: usize = 0;

        insertYearDescending(&years, &count, maximum);
        for (self.taxProfiles.formSetSummaries()) |summary| {
            if (summary.tax_year > maximum) continue;
            insertYearDescending(&years, &count, summary.tax_year);
        }
        var recent = maximum - 1;
        while (recent >= maximum - setup_year_recent_window and
            recent >= profile_ui.minimum_setup_year) : (recent -= 1)
        {
            insertYearDescending(&years, &count, recent);
        }
        if (self.profileSetupTypedYear()) |typed| {
            if (typed >= profile_ui.minimum_setup_year and typed <= maximum) {
                insertYearDescending(&years, &count, typed);
            }
        }

        const query = self.profileSetupYearQuery.text();
        const selected = self.taxProfiles.workspaceYear();
        const rows = arena.alloc(ProfileSetupYearOption, count) catch return &.{};
        var emitted: usize = 0;
        for (years[0..count]) |year| {
            var text: [16]u8 = undefined;
            const rendered = std.fmt.bufPrint(&text, "{d}", .{year}) catch continue;
            if (query.len != 0 and
                !std.mem.startsWith(u8, rendered, query)) continue;
            const configured = self.profileSetupConfiguredCount(year);
            rows[emitted] = .{
                .id = @intCast(year),
                .year = year,
                .selected = selected != null and selected.? == year,
                .configured = configured != null,
                .active_form_count = configured orelse 0,
            };
            emitted += 1;
        }
        return rows[0..emitted];
    }

    pub fn profileSetupYearHelperVisible(self: *const Model) bool {
        const typed = self.profileSetupTypedYear() orelse return false;
        return typed > self.taxProfiles.maximumSetupYear() or
            typed < profile_ui.minimum_setup_year;
    }

    pub fn profileSetupYearHelperText(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const typed = self.profileSetupTypedYear() orelse return "";
        const maximum = self.taxProfiles.maximumSetupYear();
        if (typed > maximum) {
            return std.fmt.allocPrint(
                arena,
                "{d} hasn't started. You can set up years through {d}.",
                .{ typed, maximum },
            ) catch "That year has not started yet.";
        }
        return std.fmt.allocPrint(
            arena,
            "Years before {d} aren't supported.",
            .{profile_ui.minimum_setup_year},
        ) catch "That year is not supported.";
    }

    pub fn profileSetupDraftChoiceVisible(self: *const Model) bool {
        return self.taxProfiles.year_workspace == .draft_choice;
    }

    pub fn profileSetupDraftBannerVisible(self: *const Model) bool {
        return self.taxProfiles.year_workspace.isDraft();
    }

    pub fn profileSetupSeededVisible(self: *const Model) bool {
        return self.taxProfiles.year_workspace == .draft_seeded;
    }

    pub fn profileSetupManagerVisible(self: *const Model) bool {
        return self.taxProfiles.managing_forms and switch (self.taxProfiles.year_workspace) {
            .viewing, .draft_empty, .draft_seeded => true,
            .draft_choice, .conflict, .open_failed => false,
        };
    }

    /// A configured year opens as an ordinary library, never as an editor.
    /// The only transition into checkbox management is `profile_forms_manage`.
    pub fn profileSetupBrowseVisible(self: *const Model) bool {
        return self.taxProfiles.year_workspace == .viewing and
            !self.taxProfiles.managing_forms;
    }

    pub fn profileFormsCancelDisabled(self: *const Model) bool {
        // In Manage mode Cancel is also the explicit exit back to Browse.
        // It must remain available even when the staged set is still clean;
        // only Save is dirty-gated.
        return !self.taxProfiles.managing_forms;
    }

    pub fn profileSetupConflictVisible(self: *const Model) bool {
        return self.taxProfiles.year_workspace == .conflict;
    }

    pub fn profileSetupOpenFailedVisible(self: *const Model) bool {
        return self.taxProfiles.year_workspace == .open_failed;
    }

    pub fn profileSetupPendingSwitchVisible(self: *const Model) bool {
        return self.taxProfiles.pendingYearSwitch() != null;
    }

    pub fn profileSetupPendingSwitchTitle(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const year = self.taxProfiles.workspaceYear() orelse
            return "Unsaved changes";
        return std.fmt.allocPrint(
            arena,
            "Unsaved changes for {d}",
            .{year},
        ) catch "Unsaved changes";
    }

    pub fn profileSetupPendingSwitchBody(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "You have {d} unsaved changes. Switching years won't save them.",
            .{self.taxProfiles.changedFormCount()},
        ) catch "Switching years will not save your changes.";
    }

    pub fn profileSetupStatusLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const workspace = self.taxProfiles.year_workspace;
        const year = self.taxProfiles.workspaceYear();
        if (workspace == .open_failed) {
            if (year) |value| {
                return std.fmt.allocPrint(
                    arena,
                    "Couldn't open {d}. Nothing was changed.",
                    .{value},
                ) catch "That year could not be opened.";
            }
            return "That year could not be opened.";
        }
        const base: []const u8 = if (workspace.isDraft())
            "Not set up"
        else switch (self.taxProfiles.form_set_state) {
            .needs_configuration => "Not set up",
            .legacy_catalog_default => "Original catalog default",
            .active_empty => "Configured · no active forms",
            .active_nonempty => std.fmt.allocPrint(
                arena,
                "Configured · {s}",
                .{activeFormCountLabel(arena, self.taxProfiles.activeFormCount())},
            ) catch "Configured",
        };
        const changed = self.taxProfiles.changedFormCount();
        if (changed == 0) return base;
        return std.fmt.allocPrint(
            arena,
            "{s} · {d} unsaved changes",
            .{ base, changed },
        ) catch base;
    }

    pub fn profileSetupDraftTitle(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const year = self.taxProfiles.workspaceYear() orelse
            return "Nothing is saved yet";
        return std.fmt.allocPrint(
            arena,
            "Setting up {d} — nothing is saved yet",
            .{year},
        ) catch "Nothing is saved yet";
    }

    pub fn profileSetupSeedAvailable(self: *const Model) bool {
        return self.taxProfiles.recommendedSeedYear() != null;
    }

    pub fn profileSetupSeedLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const source = self.taxProfiles.recommendedSeedYear() orelse
            return "Use another year's setup";
        return std.fmt.allocPrint(
            arena,
            "Use setup from {d}",
            .{source},
        ) catch "Use another year's setup";
    }

    pub fn profileSetupSeedYear(self: *const Model) i32 {
        return self.taxProfiles.recommendedSeedYear() orelse 0;
    }

    pub fn profileSetupSourceLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const source = self.taxProfiles.draftSourceYear() orelse
            return "Starting from another year";
        return std.fmt.allocPrint(
            arena,
            "Starting from {d}",
            .{source},
        ) catch "Starting from another year";
    }

    pub fn profileSetupSourceSummary(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d} forms copied · you can change anything before saving",
            .{self.taxProfiles.stagedFormCount()},
        ) catch "Forms copied. You can change anything before saving.";
    }

    /// Explains that facts are referenced by date rather than duplicated,
    /// without exposing revision vocabulary.
    pub fn profileSetupInheritanceNote(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const year = self.taxProfiles.workspaceYear() orelse
            return "Your taxpayer details aren't copied between years.";
        return std.fmt.allocPrint(
            arena,
            "Your taxpayer details aren't copied — this year uses whatever was true during {d}.",
            .{year},
        ) catch "Your taxpayer details aren't copied between years.";
    }

    pub fn profileSetupSourcePickerOpen(self: *const Model) bool {
        return self.profileSetupSourcePickerVisible;
    }

    pub fn profileSetupSourceOptions(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileSetupSourceOption {
        const summaries = self.taxProfiles.formSetSummaries();
        const target = self.taxProfiles.workspaceYear();
        const rows = arena.alloc(ProfileSetupSourceOption, summaries.len) catch
            return &.{};
        var count: usize = 0;
        for (summaries) |summary| {
            if (target != null and summary.tax_year == target.?) continue;
            rows[count] = .{
                .id = @intCast(summary.tax_year),
                .year = summary.tax_year,
                .active_form_count = summary.active_form_count,
                .selected = self.taxProfiles.draftSourceYear() == summary.tax_year,
            };
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileSetupPrimaryLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.taxProfiles.applyScopeFromDate()) {
            const change_year = self.taxProfiles.workspaceYear() orelse
                return "Record mid-year change";
            return std.fmt.allocPrint(
                arena,
                "Record change for {d}",
                .{change_year},
            ) catch "Record mid-year change";
        }
        if (!self.taxProfiles.year_workspace.isDraft()) return "Save changes";
        const year = self.taxProfiles.workspaceYear() orelse return "Save setup";
        return std.fmt.allocPrint(
            arena,
            "Save setup for {d}",
            .{year},
        ) catch "Save setup";
    }

    pub fn profileSetupPrimaryDisabled(self: *const Model) bool {
        return switch (self.taxProfiles.year_workspace) {
            .draft_choice, .conflict, .open_failed => true,
            .draft_empty, .draft_seeded => false,
            // From-a-date deliberately ignores formsDirty: recording the
            // current membership taking effect on a date is a real event.
            .viewing => if (self.taxProfiles.applyScopeFromDate())
                self.taxProfiles.changeDateEmpty()
            else
                !self.taxProfiles.formsDirty(),
        };
    }

    /// Shown beside Save when a save would deliberately configure no forms, so
    /// an explicit empty year is never an accident. A recorded change has its
    /// own copy; this one talks about the year and would be wrong there.
    pub fn profileSetupZeroFormsHelperVisible(self: *const Model) bool {
        return self.profileSetupManagerVisible() and
            self.taxProfiles.stagedFormCount() == 0 and
            !self.taxProfiles.applyScopeFromDate() and
            !self.profileSetupPrimaryDisabled();
    }

    pub fn profileSetupZeroFormsHelperText(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const year = self.taxProfiles.workspaceYear() orelse
            return "Saving with no forms keeps this year configured but empty.";
        return std.fmt.allocPrint(
            arena,
            "Saving with no forms keeps {d} configured but empty — no forms in the library and no deadlines on the calendar.",
            .{year},
        ) catch "Saving with no forms keeps this year configured but empty.";
    }

    pub fn profileSetupDeactivationWarningVisible(
        self: *const Model,
    ) bool {
        if (!self.profileSetupManagerVisible()) return false;
        for (0..form_catalog.registry_count) |index| {
            if (self.taxProfiles.persistedFormSelected(index) and
                !self.taxProfiles.stagedFormSelected(index)) return true;
        }
        return false;
    }

    pub fn profileSetupDeactivationWarningText(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        var count: usize = 0;
        for (0..form_catalog.registry_count) |index| {
            if (self.taxProfiles.persistedFormSelected(index) and
                !self.taxProfiles.stagedFormSelected(index)) count += 1;
        }
        return std.fmt.allocPrint(
            arena,
            "Saving deactivates {d} {s} for this interval. New setup edits and new returns will be blocked; saved Tax Form Profile history and existing drafts are retained for review and later reactivation.",
            .{ count, if (count == 1) "form" else "forms" },
        ) catch "Deactivation blocks new setup and returns but retains saved history and drafts.";
    }

    pub fn profileSetupConflictTitle(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const year = self.taxProfiles.workspaceYear() orelse
            return "This year was set up in another window.";
        return std.fmt.allocPrint(
            arena,
            "{d} was set up in another window while you were working.",
            .{year},
        ) catch "This year was set up in another window.";
    }

    pub fn profileSetupConflictReviewLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const year = self.taxProfiles.workspaceYear() orelse
            return "Review the saved setup";
        return std.fmt.allocPrint(
            arena,
            "Review saved {d} setup",
            .{year},
        ) catch "Review the saved setup";
    }

    pub fn profileSetupYearsExpandedVisible(self: *const Model) bool {
        return self.profileSetupYearsExpanded;
    }

    /// The when-does-this-apply control belongs to a configured year only:
    /// a draft has no base setup for a recorded change to layer over.
    pub fn profileSetupScopeVisible(self: *const Model) bool {
        return self.profileSetupManagerVisible() and
            self.taxProfiles.year_workspace == .viewing;
    }

    pub fn profileSetupScopeWholeYearSelected(self: *const Model) bool {
        return !self.taxProfiles.applyScopeFromDate();
    }

    pub fn profileSetupScopeFromDateSelected(self: *const Model) bool {
        return self.taxProfiles.applyScopeFromDate();
    }

    pub fn profileSetupScopeDateVisible(self: *const Model) bool {
        return self.profileSetupScopeVisible() and
            self.taxProfiles.applyScopeFromDate();
    }

    pub fn profileSetupChangeDateValue(self: *const Model) []const u8 {
        return self.taxProfiles.changeDateText();
    }

    pub fn profileSetupChangesVisible(self: *const Model) bool {
        return self.profileSetupManagerVisible() and
            self.taxProfiles.year_workspace == .viewing and
            self.taxProfiles.formSetIntervals().len > 0;
    }

    pub fn profileSetupChangesDisclosureLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "Mid-year changes ({d})",
            .{self.taxProfiles.formSetIntervals().len},
        ) catch "Mid-year changes";
    }

    pub fn profileSetupChangesExpandedVisible(self: *const Model) bool {
        return self.profileSetupChangesExpanded;
    }

    pub fn profileSetupChangeRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileSetupChangeRow {
        const intervals = self.taxProfiles.formSetIntervals();
        const rows = arena.alloc(ProfileSetupChangeRow, intervals.len) catch
            return &.{};
        const today = self.taxProfiles.default_effective_from.text();
        for (intervals, 0..) |*interval, index| {
            // "Covers today" is a plain range check against the boot date,
            // not date-scoped resolution — nothing downstream reads it. An
            // open range ends with its own year, so the year must match too.
            const same_year = today.len == 10 and
                std.mem.eql(u8, today[0..4], interval.effective_from[0..4]);
            const started = same_year and
                std.mem.order(u8, today, &interval.effective_from) != .lt;
            const still_running = if (interval.effective_until) |*until|
                std.mem.order(u8, today, until) != .gt
            else
                true;
            rows[index] = .{
                .id = interval.sequence,
                .effective_from = interval.effective_from,
                .form_count = interval.form_count,
                .covers_today = started and still_running,
            };
        }
        return rows;
    }

    pub fn profileSetupYearsDisclosureLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "All configured years ({d})",
            .{self.taxProfiles.formSetSummaries().len},
        ) catch "All configured years";
    }

    pub fn profileSetupYearsDisclosureVisible(self: *const Model) bool {
        return self.taxProfiles.formSetSummaries().len != 0;
    }

    pub fn profileFactsSummaryVisible(self: *const Model) bool {
        return !self.taxProfiles.editing_new and
            self.taxProfiles.factsSummaryAvailable();
    }

    /// States which taxpayer details a year uses, in plain language. Carry
    /// forward is reported from the history itself, so an unchanged year never
    /// needs a duplicate record to look complete.
    pub fn profileFactsSummaryLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const year = self.taxProfiles.factsSummaryYear();
        if (self.taxProfiles.factsMissingForYear()) {
            return std.fmt.allocPrint(
                arena,
                "No taxpayer details exist for {d} yet.",
                .{year},
            ) catch "No taxpayer details exist for that year yet.";
        }
        if (self.taxProfiles.factsChangedDuringYear()) {
            return std.fmt.allocPrint(
                arena,
                "Details changed during {d}. Earlier filings keep the details they were prepared with.",
                .{year},
            ) catch "Details changed during this year.";
        }
        const effective = friendlyDateLabel(
            arena,
            self.taxProfiles.factsEffectiveFrom(),
        );
        if (self.taxProfiles.factsSameAsPriorYear()) {
            return std.fmt.allocPrint(
                arena,
                "Using details effective {s} · No changes from {d}",
                .{ effective, year - 1 },
            ) catch "No changes from the previous year.";
        }
        return std.fmt.allocPrint(
            arena,
            "Using details effective {s}",
            .{effective},
        ) catch "Using the details on file.";
    }

    pub fn profileFactsMissingVisible(self: *const Model) bool {
        return self.taxProfiles.factsMissingForYear();
    }

    pub fn profileChangeControlsVisible(self: *const Model) bool {
        return !self.taxProfiles.editing_new and
            self.taxProfiles.selectedProfileId() != null;
    }

    pub fn profileRecordChangeSelected(self: *const Model) bool {
        return self.taxProfiles.changeIntent() == .record_change;
    }

    pub fn profileFixMistakeSelected(self: *const Model) bool {
        return self.taxProfiles.changeIntent() == .fix_mistake;
    }

    pub fn profileEffectiveDateLabel(self: *const Model) []const u8 {
        return if (self.taxProfiles.changeIntent() == .fix_mistake)
            "Which period was recorded wrong?"
        else
            "When did this take effect?";
    }

    pub fn profileEffectiveDateHelp(self: *const Model) []const u8 {
        return if (self.taxProfiles.changeIntent() == .fix_mistake)
            "This replaces what's shown for that period. Forms you already prepared keep the values they were prepared with."
        else
            "Earlier periods keep their old details.";
    }

    pub fn profileAdvancedExpandedVisible(self: *const Model) bool {
        return self.profileAdvancedExpanded;
    }

    pub fn profileIdentityLockNote(self: *const Model) []const u8 {
        _ = self;
        return "Identity doesn't change with ordinary updates. A different kind of taxpayer needs its own profile.";
    }

    pub fn profileBranchMode(self: *const Model) bool {
        return self.taxProfiles.branchMode();
    }

    pub fn profileCanAddBranch(self: *const Model) bool {
        return self.taxProfiles.canAddBranch();
    }

    pub fn profileAddBranchLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (!self.taxProfiles.canAddBranch()) return "Add branch";
        return std.fmt.allocPrint(
            arena,
            "Add branch of {s}",
            .{self.taxProfiles.selectedName()},
        ) catch "Add branch";
    }

    pub fn profileBranchBannerTitle(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "New branch of {s}",
            .{self.taxProfiles.branchSourceName()},
        ) catch "New branch";
    }

    pub fn profileBranchBannerBody(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "Keep the nine-digit TIN {s} and add this branch's code. Its RDO, address, and registration details start blank because they often differ — review them before saving.",
            .{self.taxProfiles.branchSourceRoot()},
        ) catch "Keep the nine-digit TIN and add this branch's code.";
    }

    /// Active forms for the year on screen. A form the taxpayer does not file
    /// must never demand a detail, which is what kept the old surface from
    /// asking for all 16 canonical facts at once.
    fn activeFormRequiresKey(
        definition: *const form_catalog.FormDefinition,
        key: profile_fields.ReusableField,
    ) bool {
        for (definition.fields) |item| {
            const profile_key = item.profile_key orelse continue;
            if (item.profile_presence != .required) continue;
            const parsed = std.meta.stringToEnum(
                profile_fields.ReusableField,
                profile_key,
            ) orelse continue;
            if (parsed == key) return true;
        }
        return false;
    }

    fn activeFormsUsingKey(
        self: *const Model,
        arena: std.mem.Allocator,
        key: profile_fields.ReusableField,
    ) []const u8 {
        var list: std.ArrayList(u8) = .empty;
        for (&form_catalog.forms) |*definition| {
            if (!self.taxProfiles.formAvailable(
                self.calendar.selected_year,
                definition.code,
            )) continue;
            if (!activeFormRequiresKey(definition, key)) continue;
            if (list.items.len != 0) list.appendSlice(arena, ", ") catch break;
            list.appendSlice(arena, definition.code) catch break;
        }
        return list.items;
    }

    /// Every required detail an active form is missing, listed once with the
    /// forms that need it. The user fixes one shared editor rather than
    /// maintaining a taxpayer profile per form.
    pub fn profileMissingFactRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileMissingFactRow {
        if (self.taxProfiles.editing_new) return &.{};
        const keys = std.meta.tags(profile_fields.ReusableField);
        const rows = arena.alloc(ProfileMissingFactRow, keys.len) catch
            return &.{};
        var count: usize = 0;
        for (keys) |key| {
            if (self.taxProfiles.reusableValueText(key).len != 0) continue;
            const used_by = self.activeFormsUsingKey(arena, key);
            if (used_by.len == 0) continue;
            rows[count] = .{
                .id = count,
                .field_label = profile_ui.reusableFieldLabel(key),
                .used_by = used_by,
            };
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileMissingFactsVisible(
        self: *const Model,
        arena: std.mem.Allocator,
    ) bool {
        return self.profileMissingFactRows(arena).len != 0;
    }

    pub fn profileMissingFactsTitle(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const count = self.profileMissingFactRows(arena).len;
        if (count == 1) return "1 detail is missing for your active forms";
        return std.fmt.allocPrint(
            arena,
            "{d} details are missing for your active forms",
            .{count},
        ) catch "Details are missing for your active forms";
    }

    pub fn profileBranchCopyNote(self: *const Model) []const u8 {
        _ = self;
        return "Copied once: name, contact number, and email. Never copied: COR files, filings, drafts, payments, and email settings. Later head-office changes don't update this branch.";
    }

    pub fn profileFactsMissingHelpText(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "Record what was true in {d} — today's details won't be copied backward.",
            .{self.taxProfiles.factsSummaryYear()},
        ) catch "Record what was true then; today's details are not copied backward.";
    }

    pub fn profileFormSetRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileFormSetRow {
        const summaries = self.taxProfiles.formSetSummaries();
        const rows = arena.alloc(ProfileFormSetRow, summaries.len) catch
            return &.{};
        for (summaries, 0..) |summary, index| {
            rows[index] = .{
                .id = @intCast(summary.tax_year),
                .tax_year = summary.tax_year,
                .state = summary.state,
                .active_form_count = summary.active_form_count,
            };
        }
        return rows;
    }

    /// True only while a surface that hosts the yearly setup workspace is on
    /// screen. Since the calendar remediation, that is three places: the
    /// Profile Settings page's Registration & Forms section, the same
    /// section inside the taxpayer dashboard's inline Profile tab, and the
    /// dashboard's Forms tab, which its edit-year flow made a manager
    /// surface. The dashboard calendar tab stays browse-only; staged work is
    /// kept in state either way, so leaving and returning loses nothing.
    fn yearWorkspaceContextActive(self: *const Model) bool {
        if (self.page == .profile_setup) {
            return self.profileSetupSection == .tax_forms;
        }
        if (self.page != .taxpayer_dashboard) return false;
        return switch (self.dashboardSection) {
            .forms => true,
            .profile_settings => self.profileSetupSection == .tax_forms,
            .calendar => false,
        };
    }

    fn formsManageMode(self: *const Model) bool {
        return self.taxProfiles.managing_forms and
            self.yearWorkspaceContextActive();
    }

    pub fn managingProfileForms(self: *const Model) bool {
        return self.formsManageMode();
    }

    pub fn browsingProfileForms(self: *const Model) bool {
        return !self.formsManageMode();
    }

    pub fn profileFormsSearchValue(self: *const Model) []const u8 {
        return self.taxProfiles.formsQuery();
    }

    pub fn profileFormsCountLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.formsManageMode()) {
            return std.fmt.allocPrint(
                arena,
                "{d} selected · {d} unsaved changes",
                .{
                    self.taxProfiles.stagedFormCount(),
                    self.taxProfiles.changedFormCount(),
                },
            ) catch "Manage Forms";
        }
        var active_count: usize = 0;
        if (self.profileFormAvailabilityYear ==
            profileBrowseAvailabilityYear(self))
        {
            for (self.profileFormAnyPeriodActive) |active| {
                if (active) active_count += 1;
            }
        } else {
            active_count = self.taxProfiles.activeFormCount();
        }
        return std.fmt.allocPrint(
            arena,
            "{d} of {d} active",
            .{ active_count, form_catalog.registry_count },
        ) catch "Forms Set unavailable";
    }

    pub fn profileFormsYearLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.yearWorkspaceContextActive()) {
            return self.taxProfiles.tax_year.text();
        }
        return std.fmt.allocPrint(
            arena,
            "{d}",
            .{self.calendar.selected_year},
        ) catch "Tax year";
    }

    pub fn profileFormsChangedCountLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const changed = self.taxProfiles.changedFormCount();
        if (changed == 1) return "1 unsaved change";
        return std.fmt.allocPrint(
            arena,
            "{d} unsaved changes",
            .{changed},
        ) catch "Unsaved changes";
    }

    pub fn profileFormsHeading(self: *const Model) []const u8 {
        return if (self.formsManageMode())
            "Manage active forms"
        else
            "Tax Form Library";
    }

    pub fn profileFormsModeDescription(self: *const Model) []const u8 {
        return if (self.formsManageMode())
            "Choose which forms apply to this taxpayer. Changes stay staged until Save."
        else
            "Choose a month, quarter, annual return, or on-demand filing to open that exact workspace.";
    }

    pub fn profileCompletionVisible(self: *const Model) bool {
        return self.profileCompletionTarget != null;
    }

    pub fn profileCompletionMessage(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const field_label = if (self.profileCompletionTarget) |target|
            profileCompletionFieldLabel(target)
        else
            "the required profile data";
        const form_code = if (self.profileCompletionFormIndex) |index|
            if (index < form_catalog.registry_count)
                form_catalog.forms[index].code
            else
                "the selected form"
        else
            "the selected form";
        return std.fmt.allocPrint(
            arena,
            "Complete {s} in Tax Profile before opening BIR Form {s}.",
            .{ field_label, form_code },
        ) catch "Complete the missing Tax Profile data before opening the form.";
    }

    pub fn profileTinAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .tin;
    }

    pub fn profileRdoAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .rdo_code;
    }

    pub fn profileNameAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .taxpayer_name or
            self.profileCompletionTarget == .registered_name;
    }

    pub fn profileAddressAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .registered_address;
    }

    pub fn profileZipAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .zip_code;
    }

    pub fn profilePhoneAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .contact_number;
    }

    pub fn profileEmailAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .email_address;
    }

    pub fn profileBirthDateAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .date_of_birth;
    }

    pub fn profileCitizenshipAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .citizenship;
    }

    pub fn profileForeignTaxNumberAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .foreign_tax_number;
    }

    pub fn profileBusinessLineAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .line_of_business;
    }

    pub fn profileAtcAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .atc;
    }

    pub fn profileTaxTypeAutofocus(self: *const Model) bool {
        return self.profileCompletionTarget == .tax_type;
    }

    pub fn profileFormsLegacyResetVisible(self: *const Model) bool {
        return self.taxProfiles.legacy_form_set_reset_allowed;
    }

    pub fn profileFormsHeaderStacked(self: *const Model) bool {
        return self.constrainedLayout();
    }

    pub fn profileFormsIconAction(self: *const Model) bool {
        return self.viewportClass == .phone or
            self.viewportClass == .compact or
            self.viewportClass == .rail_narrow;
    }

    pub fn profileFormCardColumns(self: *const Model) u8 {
        // Match the original eBIRForms library proportions: desktop 3 cards,
        // tablet 2, and phone 1. The Native grid stretches each row
        // to its tallest card, so different title or capability text cannot
        // make neighboring cards jump in height.
        if (self.viewportWidth >= 1100) return 3;
        // Four 64 px filing-period tiles plus their gaps and card padding need
        // more than half of a 768 px window once the shell rail is present.
        // One honest full-width card is preferable to overlapping hit targets.
        if (self.viewportWidth >= 900) return 2;
        return 1;
    }

    fn profileFormInfoDefinition(
        self: *const Model,
    ) ?*const form_catalog.FormDefinition {
        const index = self.libraryFilter.info_index orelse return null;
        if (index >= form_catalog.forms.len) return null;
        return &form_catalog.forms[index];
    }

    pub fn profileFormInfoDialogOpen(self: *const Model) bool {
        return !self.formsManageMode() and
            self.profileFormInfoDefinition() != null;
    }

    pub fn profileFormInfoDialogWidth(self: *const Model) f32 {
        return @min(
            @as(f32, 520),
            @max(@as(f32, 320), self.viewportWidth - 32),
        );
    }

    pub fn profileFormInfoCode(self: *const Model) []const u8 {
        const definition = self.profileFormInfoDefinition() orelse return "";
        return definition.code;
    }

    pub fn profileFormInfoTitle(self: *const Model) []const u8 {
        const definition = self.profileFormInfoDefinition() orelse return "";
        return definition.display_title;
    }

    pub fn profileFormInfoCategory(self: *const Model) []const u8 {
        const definition = self.profileFormInfoDefinition() orelse return "";
        return taxCategoryLabel(definition.tax_category);
    }

    pub fn profileFormInfoCadence(self: *const Model) []const u8 {
        const definition = self.profileFormInfoDefinition() orelse return "";
        return switch (definition.cadence) {
            .monthly => "Monthly",
            .quarterly => "Quarterly",
            .annual => "Annual",
            .on_demand => "On-demand",
        };
    }

    pub fn profileFormInfoCapability(self: *const Model) []const u8 {
        const definition = self.profileFormInfoDefinition() orelse return "";
        return if (definition.status == .static_layout)
            "An in-app editor is available. Select a filing period to open or resume the form."
        else
            "Calendar only. This form can appear in deadlines and exports, but an in-app editor is not available.";
    }

    pub fn profileFormInfoRevision(self: *const Model) []const u8 {
        const definition = self.profileFormInfoDefinition() orelse return "";
        return definition.revision orelse "Not specified";
    }

    /// Makes the nested period-cell row type discoverable to the runtime
    /// markup interpreter. The actual rows are supplied by each form card's
    /// `periodCells` projection.
    pub fn profileFormPeriodCellTypeRows(
        self: *const Model,
    ) []const TaxFormLibraryPeriodCell {
        _ = self;
        return &.{};
    }

    pub fn profileFormsFilterPickerOpen(self: *const Model) bool {
        return self.libraryFilter.filter_picker_visible;
    }

    pub fn profileFormsPeriodFilterPickerOpen(self: *const Model) bool {
        return self.libraryFilter.period_picker_visible;
    }

    pub fn profileFormsPeriodFilterLabel(self: *const Model) []const u8 {
        return self.libraryFilter.period_filter.label();
    }

    pub fn profileFormsPeriodFilterAccessibleLabel(self: *const Model) []const u8 {
        _ = self;
        return "Filter filing periods";
    }

    fn currentProfileFormsCadenceMask(self: *const Model) u8 {
        return if (self.formsManageMode())
            self.libraryFilter.manage_cadence_mask
        else
            self.libraryFilter.browse_cadence_mask;
    }

    pub fn profileFormsCadenceMonthlySelected(self: *const Model) bool {
        return self.currentProfileFormsCadenceMask() & 0b0001 != 0;
    }

    pub fn profileFormsCadenceQuarterlySelected(self: *const Model) bool {
        return self.currentProfileFormsCadenceMask() & 0b0010 != 0;
    }

    pub fn profileFormsCadenceAnnualSelected(self: *const Model) bool {
        return self.currentProfileFormsCadenceMask() & 0b0100 != 0;
    }

    pub fn profileFormsCadenceOnDemandSelected(self: *const Model) bool {
        return self.currentProfileFormsCadenceMask() & 0b1000 != 0;
    }

    fn profileFormsCadenceLocked(self: *const Model, bit: u8) bool {
        return self.currentProfileFormsCadenceMask() == bit;
    }

    pub fn profileFormsCadenceMonthlyLocked(self: *const Model) bool {
        return self.profileFormsCadenceLocked(0b0001);
    }

    pub fn profileFormsCadenceQuarterlyLocked(self: *const Model) bool {
        return self.profileFormsCadenceLocked(0b0010);
    }

    pub fn profileFormsCadenceAnnualLocked(self: *const Model) bool {
        return self.profileFormsCadenceLocked(0b0100);
    }

    pub fn profileFormsCadenceOnDemandLocked(self: *const Model) bool {
        return self.profileFormsCadenceLocked(0b1000);
    }

    fn profileFormsAllMonthsSelected(self: *const Model) bool {
        return !self.formsManageMode() and
            self.profileFormsCadenceMonthlySelected() and
            self.libraryFilter.month_mask == 0;
    }

    fn profileFormsAllQuartersSelected(self: *const Model) bool {
        return !self.formsManageMode() and
            self.profileFormsCadenceQuarterlySelected() and
            self.libraryFilter.quarter_mask == 0;
    }

    fn profileFormsMonthSelected(self: *const Model, month: u8) bool {
        if (month < 1 or month > 12) return false;
        return self.libraryFilter.month_mask &
            (@as(u16, 1) << @intCast(month - 1)) != 0;
    }

    pub fn profileFormsJanuarySelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(1);
    }

    pub fn profileFormsFebruarySelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(2);
    }

    pub fn profileFormsMarchSelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(3);
    }

    pub fn profileFormsAprilSelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(4);
    }

    pub fn profileFormsMaySelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(5);
    }

    pub fn profileFormsJuneSelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(6);
    }

    pub fn profileFormsJulySelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(7);
    }

    pub fn profileFormsAugustSelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(8);
    }

    pub fn profileFormsSeptemberSelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(9);
    }

    pub fn profileFormsOctoberSelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(10);
    }

    pub fn profileFormsNovemberSelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(11);
    }

    pub fn profileFormsDecemberSelected(self: *const Model) bool {
        return self.profileFormsMonthSelected(12);
    }

    /// One row per month, carrying its own label, accessible name, and
    /// selected state. Twelve near-identical markup blocks and twenty-four
    /// accessors collapse into this.
    fn profileFormsPeriodButtonVariant(selected: bool) []const u8 {
        return if (selected) "primary" else "outline";
    }

    fn profileFormsQuarterSelected(self: *const Model, quarter: u8) bool {
        if (quarter < 1 or quarter > 4) return false;
        return self.libraryFilter.quarter_mask &
            (@as(u8, 1) << @intCast(quarter - 1)) != 0;
    }

    pub fn profileFormsMonthOptions(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const LibraryMonthFilterRow {
        const rows = arena.alloc(LibraryMonthFilterRow, 12) catch return &.{};
        for (0..12) |index| {
            const month: u8 = @intCast(index + 1);
            rows[index] = .{
                .id = index,
                .month = month,
                .selected = self.profileFormsMonthSelected(month),
            };
        }
        return rows;
    }

    pub fn profileFormsQuarterOneSelected(self: *const Model) bool {
        return self.profileFormsQuarterSelected(1);
    }

    pub fn profileFormsQuarterTwoSelected(self: *const Model) bool {
        return self.profileFormsQuarterSelected(2);
    }

    pub fn profileFormsQuarterThreeSelected(self: *const Model) bool {
        return self.profileFormsQuarterSelected(3);
    }

    pub fn profileFormsQuarterFourSelected(self: *const Model) bool {
        return self.profileFormsQuarterSelected(4);
    }

    pub fn profileFormsQuarter1Selected(self: *const Model) bool {
        return self.profileFormsQuarterOneSelected();
    }

    pub fn profileFormsQuarter2Selected(self: *const Model) bool {
        return self.profileFormsQuarterTwoSelected();
    }

    pub fn profileFormsQuarter3Selected(self: *const Model) bool {
        return self.profileFormsQuarterThreeSelected();
    }

    pub fn profileFormsQuarter4Selected(self: *const Model) bool {
        return self.profileFormsQuarterFourSelected();
    }

    pub fn profileFormsQuarter1Variant(self: *const Model) []const u8 {
        return profileFormsPeriodButtonVariant(self.profileFormsQuarter1Selected());
    }

    pub fn profileFormsQuarter2Variant(self: *const Model) []const u8 {
        return profileFormsPeriodButtonVariant(self.profileFormsQuarter2Selected());
    }

    pub fn profileFormsQuarter3Variant(self: *const Model) []const u8 {
        return profileFormsPeriodButtonVariant(self.profileFormsQuarter3Selected());
    }

    pub fn profileFormsQuarter4Variant(self: *const Model) []const u8 {
        return profileFormsPeriodButtonVariant(self.profileFormsQuarter4Selected());
    }

    fn profileFormsCategorySelected(
        self: *const Model,
        category: form_catalog.TaxCategory,
    ) bool {
        return self.libraryFilter.category_mask &
            (@as(u16, 1) << @intCast(@intFromEnum(category))) != 0;
    }

    /// One row per tax category, driven by the catalog enum rather than ten
    /// hand-written accessors and ten messages that had to stay in step with
    /// it. Adding a category to the catalog now adds its filter for free.
    pub fn profileFormsCategoryOptions(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const LibraryCategoryFilterRow {
        const categories = std.meta.tags(form_catalog.TaxCategory);
        const rows = arena.alloc(LibraryCategoryFilterRow, categories.len) catch
            return &.{};
        for (categories, 0..) |category, index| {
            rows[index] = .{
                .id = index,
                .label = taxCategoryLabel(category),
                .selected = self.profileFormsCategorySelected(category),
            };
        }
        return rows;
    }

    pub fn profileOnDemandFilterRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const LibraryOnDemandFilterRow {
        const rows = arena.alloc(
            LibraryOnDemandFilterRow,
            form_catalog.registry_count,
        ) catch return &.{};
        var count: usize = 0;
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (definition.cadence != .on_demand) continue;
            const browse_year = profileBrowseAvailabilityYear(self);
            const active = if (self.profileFormAvailabilityYear == browse_year)
                self.profileFormAnyPeriodActive[index]
            else if (self.yearWorkspaceContextActive())
                self.taxProfiles.persistedFormSelected(index)
            else
                self.taxProfiles.formAvailable(browse_year, definition.code);
            if (!active) continue;
            rows[count] = .{
                .id = index,
                .definition = definition,
                .selected = self.libraryFilter.on_demand_mask &
                    (@as(u64, 1) << @intCast(index)) != 0,
            };
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileFormsHasOnDemandFilters(self: *const Model) bool {
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (definition.cadence != .on_demand) continue;
            const browse_year = profileBrowseAvailabilityYear(self);
            if (self.profileFormAvailabilityYear == browse_year) {
                if (self.profileFormAnyPeriodActive[index]) return true;
            } else if (self.yearWorkspaceContextActive()) {
                if (self.taxProfiles.persistedFormSelected(index)) return true;
            } else if (self.taxProfiles.formAvailable(
                browse_year,
                definition.code,
            )) return true;
        }
        return false;
    }

    pub fn profileFormsFilterSummaryLabel(self: *const Model) []const u8 {
        if (!self.formsManageMode()) {
            if (self.libraryFilter.browse_cadence_mask == 0b1111 and
                self.libraryFilter.month_mask == 0 and
                self.libraryFilter.quarter_mask == 0 and
                self.libraryFilter.on_demand_mask == 0)
            {
                return "All active filings";
            }
            return "Browse filters applied";
        }
        return switch (self.taxProfiles.form_activity_filter) {
            .active => switch (self.taxProfiles.form_capability_filter) {
                .all => "Selected · Any capability",
                .editor => "Selected · Editor",
                .calendar_only => "Selected · Calendar only",
            },
            .inactive => switch (self.taxProfiles.form_capability_filter) {
                .all => "Not selected · Any capability",
                .editor => "Not selected · Editor",
                .calendar_only => "Not selected · Calendar only",
            },
            .all => switch (self.taxProfiles.form_capability_filter) {
                .all => "All forms",
                .editor => "All selections · Editor",
                .calendar_only => "All selections · Calendar only",
            },
        };
    }

    pub fn profileFormsFilterDisplayLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.formsManageMode()) {
            return self.profileFormsFilterSummaryLabel();
        }
        if (self.libraryFilter.browse_cadence_mask == 0b1111 and
            self.libraryFilter.month_mask == 0 and
            self.libraryFilter.quarter_mask == 0 and
            self.libraryFilter.on_demand_mask == 0)
        {
            return "All active filings";
        }

        var label: std.ArrayList(u8) = .empty;
        if (self.profileFormsCadenceMonthlySelected()) {
            const month_count: u8 = @intCast(@popCount(
                self.libraryFilter.month_mask,
            ));
            const part = if (month_count == 0)
                "All months"
            else if (month_count == 1)
                shortMonthName(firstSelectedMonth(self.libraryFilter.month_mask))
            else
                std.fmt.allocPrint(
                    arena,
                    "{d} months",
                    .{month_count},
                ) catch "Months";
            appendLibraryFilterLabelPart(&label, arena, part) catch
                return "Filing periods selected";
        }
        if (self.profileFormsCadenceQuarterlySelected()) {
            const quarter_count: u8 = @intCast(@popCount(
                self.libraryFilter.quarter_mask,
            ));
            const part = if (quarter_count == 0)
                "All quarters"
            else if (quarter_count == 1)
                shortQuarterName(firstSelectedQuarter(
                    self.libraryFilter.quarter_mask,
                ))
            else
                std.fmt.allocPrint(
                    arena,
                    "{d} quarters",
                    .{quarter_count},
                ) catch "Quarters";
            appendLibraryFilterLabelPart(&label, arena, part) catch
                return "Filing periods selected";
        }
        if (self.profileFormsCadenceAnnualSelected()) {
            appendLibraryFilterLabelPart(&label, arena, "Annual") catch
                return "Filing periods selected";
        }
        if (self.profileFormsCadenceOnDemandSelected()) {
            const selected_count: u8 = @intCast(@popCount(
                self.libraryFilter.on_demand_mask,
            ));
            const part = if (selected_count == 0)
                "On-demand"
            else if (selected_count == 1)
                "1 on-demand form"
            else
                std.fmt.allocPrint(
                    arena,
                    "{d} on-demand forms",
                    .{selected_count},
                ) catch "On-demand forms";
            appendLibraryFilterLabelPart(&label, arena, part) catch
                return "Filing periods selected";
        }
        return if (label.items.len == 0) "All active filings" else label.items;
    }

    pub fn profileFormsFilterAccessibleLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (!self.formsManageMode()) {
            if (self.libraryFilter.browse_cadence_mask == 0b1111 and
                self.libraryFilter.month_mask == 0 and
                self.libraryFilter.quarter_mask == 0 and
                self.libraryFilter.on_demand_mask == 0)
            {
                return "Filter active forms by cadence, month, or quarter";
            }
            return std.fmt.allocPrint(
                arena,
                "Filter active forms: {s}. Change cadence, month, or quarter",
                .{self.profileFormsFilterDisplayLabel(arena)},
            ) catch "Change active form filters";
        }
        return switch (self.taxProfiles.form_activity_filter) {
            .active => switch (self.taxProfiles.form_capability_filter) {
                .all => "Filter forms: selected, any capability",
                .editor => "Filter forms: selected, editor available",
                .calendar_only => "Filter forms: selected, calendar only",
            },
            .inactive => switch (self.taxProfiles.form_capability_filter) {
                .all => "Filter forms: not selected, any capability",
                .editor => "Filter forms: not selected, editor available",
                .calendar_only => "Filter forms: not selected, calendar only",
            },
            .all => switch (self.taxProfiles.form_capability_filter) {
                .all => "Filter forms: all forms",
                .editor => "Filter forms: all selections, editor available",
                .calendar_only => "Filter forms: all selections, calendar only",
            },
        };
    }

    pub fn profileFormsFilterActiveSelected(self: *const Model) bool {
        return self.taxProfiles.formFilterActiveSelected();
    }

    pub fn profileFormsFilterInactiveSelected(self: *const Model) bool {
        return self.taxProfiles.formFilterInactiveSelected();
    }

    pub fn profileFormsFilterEditorSelected(self: *const Model) bool {
        return self.taxProfiles.formFilterEditorSelected();
    }

    pub fn profileFormsFilterCalendarOnlySelected(self: *const Model) bool {
        return self.taxProfiles.formFilterCalendarOnlySelected();
    }

    pub fn profileFormsFilterActiveLocked(self: *const Model) bool {
        return self.taxProfiles.formFilterActiveLocked();
    }

    pub fn profileFormsFilterInactiveLocked(self: *const Model) bool {
        return self.taxProfiles.formFilterInactiveLocked();
    }

    pub fn profileFormsFilterEditorLocked(self: *const Model) bool {
        return self.taxProfiles.formFilterEditorLocked();
    }

    pub fn profileFormsFilterCalendarOnlyLocked(self: *const Model) bool {
        return self.taxProfiles.formFilterCalendarOnlyLocked();
    }

    fn libraryCadenceSelected(self: *const Model, cadence: form_catalog.FilingCadence) bool {
        const bit: u8 = switch (cadence) {
            .monthly => 0b0001,
            .quarterly => 0b0010,
            .annual => 0b0100,
            .on_demand => 0b1000,
        };
        return self.currentProfileFormsCadenceMask() & bit != 0;
    }

    fn libraryValidPeriodMask(
        definition: *const form_catalog.FormDefinition,
    ) u16 {
        const maximum: u8 = switch (definition.cadence) {
            .monthly => 12,
            .quarterly => 4,
            .annual, .on_demand => return 0,
        };
        const first = @min(definition.min_period orelse 1, maximum);
        const last = @min(definition.max_period orelse maximum, maximum);
        var mask: u16 = 0;
        var value = first;
        while (value <= last) : (value += 1) {
            mask |= @as(u16, 1) << @intCast(value - 1);
        }
        return mask;
    }

    fn libraryPeriodGridColumns(
        self: *const Model,
        definition: *const form_catalog.FormDefinition,
    ) u8 {
        _ = self;
        // Period tiles keep their cadence footprint regardless of the active
        // period filter. Monthly cards are always 4 columns x 3 rows and
        // quarterly cards are always 4 columns x 1 row; filtered-out slots
        // render as invisible placeholders instead of widening the survivors.
        return switch (definition.cadence) {
            .monthly, .quarterly => 4,
            .annual, .on_demand => 1,
        };
    }

    fn libraryFormMatchesSearch(
        self: *const Model,
        definition: *const form_catalog.FormDefinition,
    ) bool {
        const query = self.taxProfiles.formsQuery();
        if (query.len == 0) return true;
        return multi_select.containsAsciiInsensitive(definition.code, query) or
            multi_select.containsAsciiInsensitive(definition.display_title, query) or
            multi_select.containsAsciiInsensitive(
                taxCategoryLabel(definition.tax_category),
                query,
            );
    }

    fn browseFormMatches(
        self: *const Model,
        definition: *const form_catalog.FormDefinition,
        index: usize,
    ) bool {
        const browse_year = profileBrowseAvailabilityYear(self);
        const active = if (self.profileFormAvailabilityYear == browse_year)
            self.profileFormAnyPeriodActive[index]
        else if (self.yearWorkspaceContextActive())
            self.taxProfiles.persistedFormSelected(index)
        else
            self.taxProfiles.formAvailable(browse_year, definition.code);
        if (!active) return false;
        if (!self.libraryCadenceSelected(definition.cadence)) return false;
        switch (definition.cadence) {
            .monthly => if (self.libraryFilter.month_mask != 0 and
                self.libraryFilter.month_mask & libraryValidPeriodMask(definition) == 0)
                return false,
            .quarterly => if (self.libraryFilter.quarter_mask != 0 and
                @as(u16, self.libraryFilter.quarter_mask) &
                    libraryValidPeriodMask(definition) == 0)
                return false,
            .annual, .on_demand => {},
        }
        if (definition.cadence == .on_demand and
            self.libraryFilter.on_demand_mask != 0 and
            self.libraryFilter.on_demand_mask &
                (@as(u64, 1) << @intCast(index)) == 0) return false;
        return self.libraryFormMatchesSearch(definition);
    }

    fn manageFormMatches(
        self: *const Model,
        definition: *const form_catalog.FormDefinition,
        index: usize,
    ) bool {
        const selected = self.taxProfiles.stagedFormSelected(index);
        switch (self.taxProfiles.form_activity_filter) {
            .active => if (!selected) return false,
            .inactive => if (selected) return false,
            .all => {},
        }
        switch (self.taxProfiles.form_capability_filter) {
            .editor => if (definition.status != .static_layout) return false,
            .calendar_only => if (definition.status != .calendar_only) return false,
            .all => {},
        }
        if (!self.libraryCadenceSelected(definition.cadence)) return false;
        if (self.libraryFilter.category_mask != 0 and
            !self.profileFormsCategorySelected(definition.tax_category)) return false;
        return self.libraryFormMatchesSearch(definition);
    }

    pub fn profileBrowseFormRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const TaxFormLibraryRow {
        const rows = arena.alloc(
            TaxFormLibraryRow,
            form_catalog.registry_count,
        ) catch return &.{};
        var count: usize = 0;
        var matched: usize = 0;
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (!self.browseFormMatches(definition, index)) continue;
            if (matched < self.libraryFilter.page_offset) {
                matched += 1;
                continue;
            }
            if (count >= self.libraryFilter.visible_limit) break;
            const launch_assessment = if (self.profileFormLaunchAssessmentsReady)
                self.profileFormLaunchAssessments[index]
            else
                form_ui.LaunchAssessment{};
            const profile_state = if (self.taxFormProfileCardStatesReady)
                self.taxFormProfileCardStates[index]
            else
                TaxFormProfileCardState.error_loading;
            rows[count] = .{
                .id = index,
                .definition = definition,
                .active = true,
                .selected = true,
                .launch_assessment = launch_assessment,
                .launch_disabled = definition.status != .static_layout or
                    !launchActionEnabled(
                        launch_assessment.status,
                    ),
                .period_grid_columns = self.libraryPeriodGridColumns(definition),
                .tax_form_profile_status = profile_state.label(),
                .tax_form_profile_action = profile_state.actionLabel(),
                .tax_form_profile_action_visible = profile_state.actionVisible(),
                .tax_form_profile_action_disabled = !profile_state.actionVisible(),
                .activation_label = profileFormActivationLabel(
                    arena,
                    self.profileFormActiveSegments[index],
                ),
            };
            const browse_year = if (self.yearWorkspaceContextActive())
                self.taxProfiles.workspaceYear() orelse self.calendar.selected_year
            else
                self.calendar.selected_year;
            populateLibraryPeriodCells(
                &rows[count],
                self.taxProfiles.draftSummaries(),
                self.taxProfiles.draftSummariesTruncated(),
                definition.code,
                browse_year,
                arena,
                self.libraryFilter.month_mask,
                self.libraryFilter.quarter_mask,
                self.profilePeriodLaunchAssessments[index],
                self.profilePeriodLaunchAssessmentsReady[index],
                self.profilePeriodAvailability[index],
                self.profilePeriodAvailabilityReady[index],
            );
            count += 1;
            matched += 1;
        }
        return rows[0..count];
    }

    pub fn profileManageFormRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const TaxFormLibraryRow {
        const rows = arena.alloc(
            TaxFormLibraryRow,
            form_catalog.registry_count,
        ) catch return &.{};
        var count: usize = 0;
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (!self.manageFormMatches(definition, index)) continue;
            const active = self.taxProfiles.persistedFormSelected(index);
            const selected = self.taxProfiles.stagedFormSelected(index);
            const inactive_history = !active and
                self.taxFormProfileHistoryAvailable[index];
            rows[count] = .{
                .id = index,
                .definition = definition,
                .active = active,
                .selected = selected,
                .launch_disabled = true,
                .manage_status = self.taxProfiles.managedFormStatus(index) orelse
                    .inactive,
                .tax_form_profile_status = if (inactive_history)
                    "Saved Tax Form Profile history retained"
                else
                    "",
                // Deactivation hides setup access while retaining immutable
                // history. History becomes reachable again only after this
                // form is active for the selected tax year.
                .tax_form_profile_action = "",
                .tax_form_profile_action_visible = false,
                .tax_form_profile_action_disabled = true,
            };
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileFormRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const TaxFormLibraryRow {
        return if (self.formsManageMode())
            self.profileManageFormRows(arena)
        else
            self.profileBrowseFormRows(arena);
    }

    pub fn taxFormProfileCode(self: *const Model) []const u8 {
        const index = self.taxFormProfileFormIndex orelse return "Tax form";
        if (index >= form_catalog.registry_count) return "Tax form";
        return form_catalog.forms[index].code;
    }

    pub fn taxFormProfileBackLabel(self: *const Model) []const u8 {
        if (self.taxFormProfileReturnPage != .taxpayer_dashboard) return "Back";
        return switch (self.taxFormProfileReturnDashboardSection) {
            .calendar => "Back to Calendar",
            .forms => "Back to Tax Form Library",
            .profile_settings => switch (self.taxFormProfileReturnProfileSection) {
                .tax_profile => "Back to Tax Profile",
                .tax_forms => "Back to Registration & Forms",
                .email => "Back to Email Settings",
            },
        };
    }

    pub fn taxFormProfileTitle(self: *const Model) []const u8 {
        const index = self.taxFormProfileFormIndex orelse
            return "Tax Form Profile";
        if (index >= form_catalog.registry_count) return "Tax Form Profile";
        return form_catalog.forms[index].display_title;
    }

    pub fn taxFormProfileYear(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const identity = self.taxFormProfilePage.viewedIdentity() orelse
            return "unavailable";
        return std.fmt.allocPrint(
            arena,
            "{d}",
            .{identity.tax_year},
        ) catch "unavailable";
    }

    pub fn taxFormProfileRevision(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const identity = self.taxFormProfilePage.viewedIdentity() orelse
            return "unavailable";
        const revision = identity.formRevision() orelse
            return "unavailable";
        return std.fmt.allocPrint(arena, "{s}", .{revision}) catch
            "unavailable";
    }

    pub fn taxFormProfileStatus(self: *const Model) []const u8 {
        if (annualElectionPilotOpen(self)) {
            if (!self.taxFormProfileComposed.loaded) {
                return "Tax Profile status unavailable";
            }
            return switch (self.taxFormProfileComposed.readiness
                .base_tax_profile.status) {
                .ready, .locked, .not_applicable => "Tax Profile details ready",
                .unresolved => "Tax Profile incomplete",
                .reserved, .review_required, .invalid => "Tax Profile requires review",
            };
        }
        return switch (self.taxFormProfilePage.filingReadiness()) {
            .unavailable => "No Tax Form Profile is available for this form",
            .inactive => "Inactive for this tax year - saved history is read-only",
            .conflict => "A newer saved revision must be reviewed",
            .editing => "Editing Tax Form Profile",
            .missing_inherited_values => "Tax Profile incomplete",
            .missing_annual_setup => "Tax Form Profile setup is incomplete",
            .requires_review => "Saved setup requires review",
            .ready => "Profile setup ready",
        };
    }

    pub fn taxFormProfileStatusLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (annualElectionPilotOpen(self)) {
            if (!self.taxFormProfileComposed.loaded) {
                return "Tax Profile status unavailable";
            }
            const layer = self.taxFormProfileComposed.readiness
                .base_tax_profile;
            if (layer.status != .unresolved) return self.taxFormProfileStatus();
            const count = layer.missingKeys().len;
            if (count == 0) return "Not ready — inherited Tax Profile is invalid";
            return std.fmt.allocPrint(
                arena,
                "Not ready — {d} inherited Tax Profile field{s} missing",
                .{ count, if (count == 1) "" else "s" },
            ) catch "Not ready — inherited Tax Profile fields missing";
        }
        if (self.taxFormProfilePage.filingReadiness() !=
            .missing_inherited_values)
        {
            return self.taxFormProfileStatus();
        }
        const count = self.taxFormProfileMissingInheritedRows(arena).len;
        if (count == 0) return "Not ready — inherited Tax Profile is invalid";
        return std.fmt.allocPrint(
            arena,
            "Not ready — {d} inherited Tax Profile field{s} missing",
            .{ count, if (count == 1) "" else "s" },
        ) catch "Not ready — inherited Tax Profile fields missing";
    }

    pub fn taxFormProfileStatusTone(self: *const Model) []const u8 {
        if (annualElectionPilotOpen(self)) {
            if (!self.taxFormProfileComposed.loaded) return "destructive";
            return switch (self.taxFormProfileComposed.readiness
                .base_tax_profile.status) {
                .ready, .locked, .not_applicable => "primary",
                .unresolved,
                .reserved,
                .review_required,
                .invalid,
                => "destructive",
            };
        }
        return switch (self.taxFormProfilePage.filingReadiness()) {
            .ready => "primary",
            .editing => "secondary",
            .inactive, .unavailable => "secondary",
            .conflict,
            .missing_inherited_values,
            .missing_annual_setup,
            .requires_review,
            => "destructive",
        };
    }

    pub fn taxFormProfileDescription(self: *const Model) []const u8 {
        return switch (self.taxFormProfilePage.page() orelse
            .calendar_only_no_profile) {
            .calendar_only_no_profile => "This catalog entry is calendar-only and has no filing profile.",
            .inactive_history_only => "This form is not active in the selected year. Existing setup remains available as history and cannot be changed.",
            .inherited_only => "This form composes inherited Tax Profile details, filing context, and the saved annual income-tax-rate election. It has no duplicated annual form-specific setup.",
            .needs_setup => "Confirm only the form-specific roles or registrations that truthfully apply for this tax year.",
            .viewing_ready => "These form-specific selections are saved only for this taxpayer, tax year, form revision, and setup specification.",
            .editing => "Changes remain local until Save. Cancel restores the exact saved Tax Form Profile.",
        };
    }

    pub fn taxFormProfileEditing(self: *const Model) bool {
        return self.taxFormProfilePage.page() == .editing;
    }

    pub fn taxFormProfileSetupVisible(self: *const Model) bool {
        return self.taxFormProfilePage.setup_mode == .setup;
    }

    pub fn taxFormProfileInheritedOnlyVisible(self: *const Model) bool {
        return self.taxFormProfilePage.page() == .inherited_only;
    }

    pub fn taxFormProfileBaseRevision(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.taxFormProfileInherited.source_sequence == 0) {
            return "Source revision unavailable";
        }
        return std.fmt.allocPrint(
            arena,
            "Tax Profile revision {s} (sequence {d})",
            .{
                self.taxFormProfileInherited.source_revision_id.text(),
                self.taxFormProfileInherited.source_sequence,
            },
        ) catch "Source revision unavailable";
    }

    pub fn taxFormProfileInheritedTin(self: *const Model) []const u8 {
        return recordedProfileValue(self.taxFormProfileInherited.tin.text());
    }

    pub fn taxFormProfileInheritedRdo(self: *const Model) []const u8 {
        return recordedProfileValue(self.taxFormProfileInherited.rdo.text());
    }

    pub fn taxFormProfileInheritedSubjectKind(self: *const Model) []const u8 {
        return recordedProfileValue(
            self.taxFormProfileInherited.subject_kind.text(),
        );
    }

    pub fn taxFormProfileInheritedName(self: *const Model) []const u8 {
        return recordedProfileValue(self.taxFormProfileInherited.name.text());
    }

    pub fn taxFormProfileInheritedAddress(self: *const Model) []const u8 {
        return recordedProfileValue(
            self.taxFormProfileInherited.address.text(),
        );
    }

    pub fn taxFormProfileInheritedZip(self: *const Model) []const u8 {
        return recordedProfileValue(self.taxFormProfileInherited.zip.text());
    }

    pub fn taxFormProfileInheritedContact(self: *const Model) []const u8 {
        return recordedProfileValue(
            self.taxFormProfileInherited.contact.text(),
        );
    }

    pub fn taxFormProfileInheritedEmail(self: *const Model) []const u8 {
        return recordedProfileValue(self.taxFormProfileInherited.email.text());
    }

    fn taxFormProfileInheritedValue(
        self: *const Model,
        key: profile_fields.ReusableField,
    ) []const u8 {
        return switch (key) {
            .tin => self.taxFormProfileInherited.tin.text(),
            .rdo_code => self.taxFormProfileInherited.rdo.text(),
            .taxpayer_name, .registered_name => self.taxFormProfileInherited.name.text(),
            .registered_address => self.taxFormProfileInherited.address.text(),
            .zip_code => self.taxFormProfileInherited.zip.text(),
            .contact_number => self.taxFormProfileInherited.contact.text(),
            .email_address => self.taxFormProfileInherited.email.text(),
            .date_of_birth,
            .citizenship,
            .foreign_tax_number,
            .line_of_business,
            .atc,
            .tax_type,
            .government_withholding_agent,
            .special_rate_basis,
            => "",
        };
    }

    /// Annual income-tax elections and the shared Tax Profile are separate
    /// streams. Keep the exact missing inherited facts visible on this form
    /// page so a saved 8% election cannot be mistaken for a complete filer
    /// header.
    pub fn taxFormProfileMissingInheritedRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const TaxFormProfileInheritedRow {
        if (annualElectionPilotOpen(self)) {
            if (!self.taxFormProfileComposed.loaded) return &.{};
            const keys = self.taxFormProfileComposed.readiness
                .base_tax_profile.missingKeys();
            const rows = arena.alloc(
                TaxFormProfileInheritedRow,
                keys.len,
            ) catch return &.{};
            for (keys, 0..) |key, index| {
                rows[index] = .{
                    .id = index,
                    .label = profile_ui.reusableFieldLabel(key),
                    .value = "Required for this form",
                };
            }
            return rows;
        }
        const form_index = self.taxFormProfileFormIndex orelse return &.{};
        if (form_index >= form_catalog.registry_count) return &.{};
        const definition = &form_catalog.forms[form_index];
        const rows = arena.alloc(
            TaxFormProfileInheritedRow,
            definition.fields.len,
        ) catch return &.{};
        var count: usize = 0;
        for (definition.fields) |field_definition| {
            if (field_definition.provenance != .profile or
                field_definition.profile_presence != .required) continue;
            const profile_key = field_definition.profile_key orelse continue;
            const key = std.meta.stringToEnum(
                profile_fields.ReusableField,
                profile_key,
            ) orelse continue;
            if (self.taxFormProfileInheritedValue(key).len != 0) continue;
            rows[count] = .{
                .id = count,
                .label = profile_ui.reusableFieldLabel(key),
                .value = "Required for this form",
            };
            count += 1;
        }
        return rows[0..count];
    }

    pub fn taxFormProfileMissingInheritedVisible(
        self: *const Model,
    ) bool {
        if (annualElectionPilotOpen(self)) {
            if (!self.taxFormProfileComposed.loaded) return true;
            return switch (self.taxFormProfileComposed.readiness
                .base_tax_profile.status) {
                .ready, .locked, .not_applicable => false,
                .unresolved,
                .reserved,
                .review_required,
                .invalid,
                => true,
            };
        }
        return self.taxFormProfilePage.filingReadiness() ==
            .missing_inherited_values;
    }

    pub fn taxFormProfileMissingInheritedSummary(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const count = self.taxFormProfileMissingInheritedRows(arena).len;
        if (count == 0) {
            return "This form cannot be opened with the current Tax Profile. Review the shared profile details and Taxpayer Type.";
        }
        return std.fmt.allocPrint(
            arena,
            "This form still needs {d} inherited Tax Profile detail{s}. Add them once in Edit Tax Profile, then return here.",
            .{ count, if (count == 1) "" else "s" },
        ) catch "Complete the required Tax Profile details before opening this form.";
    }

    pub fn taxFormProfileMissingInheritedTitle(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (annualElectionPilotOpen(self)) {
            if (!self.taxFormProfileComposed.loaded) {
                return "Tax Profile status unavailable";
            }
            if (self.taxFormProfileComposed.readiness.base_tax_profile.status !=
                .unresolved)
            {
                return "Tax Profile details require review";
            }
        }
        const count = self.taxFormProfileMissingInheritedRows(arena).len;
        return std.fmt.allocPrint(
            arena,
            "Not ready — {d} inherited Tax Profile field{s} missing",
            .{ count, if (count == 1) "" else "s" },
        ) catch "Not ready — inherited Tax Profile fields missing";
    }

    pub fn taxFormProfileRegistrationRepairVisible(
        self: *const Model,
    ) bool {
        if (!annualElectionPilotOpen(self) or
            !self.taxFormProfileComposed.loaded) return false;
        return switch (self.taxFormProfileComposed.readiness
            .registration_bindings.status) {
            .ready, .locked, .not_applicable => false,
            .unresolved,
            .reserved,
            .review_required,
            .invalid,
            => true,
        };
    }

    pub fn taxFormProfileRegistrationRepairTitle(
        self: *const Model,
    ) []const u8 {
        return switch (self.taxFormProfileComposed.readiness
            .registration_bindings.status) {
            .unresolved, .reserved => "Registration details incomplete",
            .review_required, .invalid => "Registration details require review",
            .ready, .locked, .not_applicable => "Registration details ready",
        };
    }

    pub fn taxFormProfileRegistrationRepairAction(
        self: *const Model,
    ) []const u8 {
        return switch (self.taxFormProfileComposed.readiness
            .registration_bindings.status) {
            .unresolved, .reserved => "Complete Registration",
            .review_required, .invalid => "Review Registration",
            .ready, .locked, .not_applicable => "View Registration",
        };
    }

    pub fn taxFormProfileFilingContextVisible(self: *const Model) bool {
        return annualElectionPilotOpen(self) and
            self.taxFormProfileComposed.loaded;
    }

    pub fn taxFormProfileQuarterLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.taxFormProfileComposed.filing_context) |context| {
            const quarter = context.period.quarter() orelse
                return "Quarter unavailable";
            return std.fmt.allocPrint(
                arena,
                "Q{d}",
                .{quarter},
            ) catch "Quarter unavailable";
        }
        return std.fmt.allocPrint(
            arena,
            "Q{d}",
            .{self.annualIncomeTaxElection.filing_quarter},
        ) catch "Quarter unavailable";
    }

    pub fn taxFormProfileTaxablePeriodLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const context = self.taxFormProfileComposed.filing_context orelse
            return "Taxable period unavailable";
        const first = context.return_period_start orelse
            return "Taxable period unavailable";
        const last = context.return_period_end orelse
            return "Taxable period unavailable";
        return std.fmt.allocPrint(
            arena,
            "Calendar basis: {d:0>2}/01/{d:0>4} - {d:0>2}/{d:0>2}/{d:0>4}. Fiscal-year context is unavailable until it is recorded in the Tax Profile.",
            .{
                first.month,
                first.year,
                last.month,
                last.day,
                last.year,
            },
        ) catch "Taxable period unavailable";
    }

    pub fn taxFormProfileInheritedRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const TaxFormProfileInheritedRow {
        const labels = [_][]const u8{
            "Taxpayer Identification Number (TIN)",
            "Revenue District Office (RDO) code",
            "Taxpayer or registered name",
            "Registered address",
            "ZIP code",
            "Contact number",
            "Registered email address",
        };
        const values = [_][]const u8{
            self.taxFormProfileInheritedTin(),
            self.taxFormProfileInheritedRdo(),
            self.taxFormProfileInheritedName(),
            self.taxFormProfileInheritedAddress(),
            self.taxFormProfileInheritedZip(),
            self.taxFormProfileInheritedContact(),
            self.taxFormProfileInheritedEmail(),
        };
        const rows = arena.alloc(
            TaxFormProfileInheritedRow,
            labels.len,
        ) catch return &.{};
        for (labels, values, 0..) |label, value, index| {
            rows[index] = .{ .id = index, .label = label, .value = value };
        }
        return rows;
    }

    pub fn taxFormProfileEditVisible(self: *const Model) bool {
        return self.taxFormProfilePage.affordances().can_edit_tax_form_profile and
            !self.taxpayerYearEditing();
    }

    pub fn taxFormProfileEditTaxProfileVisible(self: *const Model) bool {
        return self.taxFormProfilePage.active and
            self.taxFormProfilePage.setup_mode != .calendar_only and
            !self.taxFormProfileEditing() and
            !self.taxpayerYearEditing();
    }

    pub fn taxFormProfileSaveDisabled(self: *const Model) bool {
        return !self.taxFormProfilePage.affordances().can_save;
    }

    pub fn taxFormProfileCancelDisabled(self: *const Model) bool {
        return !self.taxFormProfilePage.affordances().can_cancel;
    }

    pub fn taxFormProfileReviewVisible(self: *const Model) bool {
        return self.taxFormProfilePage.affordances().can_review_copy_or_reuse;
    }

    pub fn taxFormProfileReviewText(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const review = self.taxFormProfilePage.mappingReview() orelse
            return "Review copied or migrated selections before saving.";
        var summary: std.ArrayList(u8) = .empty;
        const mapped = std.fmt.allocPrint(
            arena,
            "Mapped {d} compatible value{s} from the prior form revision.",
            .{ review.mapped_count, if (review.mapped_count == 1) "" else "s" },
        ) catch return "Review the mapped prior setup before saving.";
        summary.appendSlice(arena, mapped) catch
            return "Review the mapped prior setup before saving.";
        for (review.issueSlice(), 0..) |issue, index| {
            summary.appendSlice(
                arena,
                if (index == 0) " Not carried forward: " else "; ",
            ) catch return "Review the mapped prior setup before saving.";
            summary.appendSlice(
                arena,
                taxFormProfileMappingFieldLabel(issue.role, issue.semantic_key),
            ) catch return "Review the mapped prior setup before saving.";
            summary.appendSlice(arena, switch (issue.reason) {
                .not_in_current_spec => " (not in the current form)",
                .value_type_changed => " (value type changed)",
                .evidence_gated => " (official evidence is still required)",
                .unsupported_ownership => " (cannot be reused by this form)",
            }) catch return "Review the mapped prior setup before saving.";
        }
        if (review.missing_required_count != 0) {
            const missing = std.fmt.allocPrint(
                arena,
                " {d} required current value{s} must still be selected.",
                .{
                    review.missing_required_count,
                    if (review.missing_required_count == 1) "" else "s",
                },
            ) catch return summary.items;
            summary.appendSlice(arena, missing) catch return summary.items;
        }
        summary.appendSlice(
            arena,
            " Confirm this review before saving.",
        ) catch return summary.items;
        return summary.items;
    }

    pub fn taxFormProfileConflictVisible(self: *const Model) bool {
        return self.taxFormProfilePage.conflict != null;
    }

    pub fn taxFormProfileConflictKeepDraftDisabled(
        self: *const Model,
    ) bool {
        return !self.taxFormProfilePage.affordances().can_rebase_conflict;
    }

    pub fn taxFormProfileConflictReloadDisabled(
        self: *const Model,
    ) bool {
        return !self.taxFormProfilePage.affordances().can_reload_conflict;
    }

    pub fn taxFormProfileActivationLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const period = self.taxFormProfilePage.activationPeriod() orelse
            return "Not active in this tax year; saved history is read-only.";
        var from_buffer: [10]u8 = undefined;
        const from = period.from.writeIso(&from_buffer);
        if (period.until) |until_date| {
            var until_buffer: [10]u8 = undefined;
            return std.fmt.allocPrint(
                arena,
                "Active {s} through {s}",
                .{ from, until_date.writeIso(&until_buffer) },
            ) catch "Active interval unavailable";
        }
        return std.fmt.allocPrint(
            arena,
            "Active from {s}",
            .{from},
        ) catch "Active interval unavailable";
    }

    pub fn taxFormProfileSegmentNavigationVisible(
        self: *const Model,
    ) bool {
        return self.taxFormProfilePreviousSegmentDate != null or
            self.taxFormProfileNextSegmentDate != null;
    }

    pub fn taxFormProfilePreviousSegmentDisabled(
        self: *const Model,
    ) bool {
        return self.taxFormProfilePreviousSegmentDate == null;
    }

    pub fn taxFormProfileNextSegmentDisabled(self: *const Model) bool {
        return self.taxFormProfileNextSegmentDate == null;
    }

    pub fn taxFormProfileCopyPriorYearVisible(self: *const Model) bool {
        const actions = self.taxFormProfilePage.affordances();
        return (actions.can_copy_prior_year or
            actions.can_review_compatibility) and
            !self.taxpayerYearEditing();
    }

    pub fn taxFormProfileReactivationReuseVisible(self: *const Model) bool {
        return self.taxFormProfilePage.affordances().can_reuse_after_reactivation and
            !self.taxpayerYearEditing();
    }

    pub fn taxFormProfileReactivationReuseLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const offer = self.taxFormProfilePage.copy_offer orelse
            return "Review saved setup for this interval";
        return std.fmt.allocPrint(
            arena,
            "Review and reuse revision {d}",
            .{offer.source.revision_sequence},
        ) catch "Review saved setup for this interval";
    }

    pub fn taxFormProfileCopyPriorYearLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const offer = self.taxFormProfilePage.copy_offer orelse
            return "Copy setup from prior year";
        if (offer.reason == .form_revision_mapping) {
            return std.fmt.allocPrint(
                arena,
                "Review {d} setup from form {s}",
                .{
                    offer.source.tax_year,
                    offer.source.form_revision.asSlice(),
                },
            ) catch "Review prior form setup";
        }
        return std.fmt.allocPrint(
            arena,
            "Copy setup from {d}",
            .{offer.source.tax_year},
        ) catch "Copy setup from prior year";
    }

    pub fn taxFormProfileHistoryVisible(self: *const Model) bool {
        return self.taxFormProfileHistoryRowCount != 0;
    }

    pub fn taxFormProfileHistoryRows(
        self: *const Model,
    ) []const TaxFormProfileHistoryRow {
        return self.taxFormProfileHistoryRowsCache[0..self.taxFormProfileHistoryRowCount];
    }

    pub fn taxFormProfileHistoryTruncatedVisible(self: *const Model) bool {
        return self.taxFormProfileHistoryTruncated;
    }

    pub fn taxFormProfileFieldRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const TaxFormProfileFieldRow {
        const form_index = self.taxFormProfileFormIndex orelse return &.{};
        if (form_index >= form_catalog.registry_count) return &.{};
        const definition = &form_catalog.forms[form_index];
        if (definition.tax_form_profile.mode != .setup) return &.{};
        const rows = arena.alloc(
            TaxFormProfileFieldRow,
            definition.tax_form_profile.values.len,
        ) catch return &.{};
        const values = if (self.taxFormProfileEditing())
            self.taxFormProfilePage.draftValues()
        else
            self.taxFormProfilePage.baselineValues();
        for (definition.tax_form_profile.values, 0..) |field, index| {
            const current = taxFormProfileSetupValue(
                values,
                field.role,
                field.semantic_key,
            );
            rows[index] = .{
                .id = index,
                .label = taxFormProfileFieldLabel(field),
                .value = taxFormProfileValueLabel(
                    self,
                    arena,
                    index,
                    current,
                ),
                .helper = taxFormProfileFieldHelper(field),
                .required = field.presence == .required,
                .evidence_required = field.availability == .evidence_required,
                .editable = self.taxFormProfileEditing() and
                    field.availability == .supported,
                .has_value = current != null,
                .picker_open = self.taxFormProfilePickerField == index,
            };
        }
        return rows;
    }

    pub fn taxFormProfileChoiceRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const TaxFormProfileChoiceRow {
        const field_index = self.taxFormProfilePickerField orelse return &.{};
        const rows = arena.alloc(
            TaxFormProfileChoiceRow,
            self.taxFormProfileChoiceCount,
        ) catch return &.{};
        var count: usize = 0;
        for (
            self.taxFormProfileChoices[0..self.taxFormProfileChoiceCount],
            0..,
        ) |*choice, choice_index| {
            if (choice.field_index != field_index) continue;
            rows[count] = .{
                .id = choice_index,
                .label = choice.label.text(),
                .selected = taxFormProfileChoiceSelected(
                    self,
                    field_index,
                    choice.stable_id.text(),
                ),
            };
            count += 1;
        }
        return rows[0..count];
    }

    pub fn taxFormProfileChoicesEmpty(self: *const Model) bool {
        const field_index = self.taxFormProfilePickerField orelse return true;
        for (self.taxFormProfileChoices[0..self.taxFormProfileChoiceCount]) |choice| {
            if (choice.field_index == field_index) return false;
        }
        return true;
    }

    pub fn taxFormProfileChoicesRegistrationRepairVisible(
        self: *const Model,
    ) bool {
        if (!self.taxFormProfileChoicesEmpty()) return false;
        const form_index = self.taxFormProfileFormIndex orelse return false;
        if (form_index >= form_catalog.registry_count) return false;
        const field_index = self.taxFormProfilePickerField orelse return false;
        const fields = form_catalog.forms[form_index].tax_form_profile.values;
        if (field_index >= fields.len) return false;
        return switch (fields[field_index].source_kind) {
            .business_activity_anchor,
            .registration_obligation_anchor,
            => true,
            .named_profile_role, .user_entry, .catalog_default => false,
        };
    }

    pub fn taxpayerYearSettingsVisible(self: *const Model) bool {
        const form_index = self.taxFormProfileFormIndex orelse return false;
        if (form_index >= form_catalog.registry_count) return false;
        for (form_catalog.forms[form_index].fields) |field| {
            if (field.provenance == .taxpayer_year) return true;
        }
        return false;
    }

    pub fn taxpayerYearStatus(self: *const Model) []const u8 {
        if (annualElectionPilotOpen(self)) {
            if (!self.taxFormProfileComposed.loaded) return "Unresolved";
            return switch (self.taxFormProfileComposed.readiness
                .annual_income_tax_election.status) {
                .not_applicable => "Not applicable",
                .unresolved => "Unresolved",
                .ready => "Ready",
                .reserved => "Reserved",
                .locked => "Locked",
                .review_required, .invalid => "Review required",
            };
        }
        return switch (self.taxpayerYearPage.readinessStatus()) {
            .unavailable => "Unavailable",
            .inactive => "Taxpayer is inactive",
            .no_consuming_forms => "No active form uses these settings",
            .conflict => "A newer revision must be reviewed",
            .editing => "Editing",
            .invalid_settings => "Choose a compatible yearly setting",
            .missing_required_settings => "Yearly setting required",
            .requires_review => "Review required",
            .ready => "Ready",
        };
    }

    pub fn taxpayerYearStatusTone(self: *const Model) []const u8 {
        if (annualElectionPilotOpen(self)) {
            if (!self.taxFormProfileComposed.loaded) return "destructive";
            return switch (self.taxFormProfileComposed.readiness
                .annual_income_tax_election.status) {
                .not_applicable, .ready, .locked => "primary",
                .reserved => "secondary",
                .unresolved, .review_required, .invalid => "destructive",
            };
        }
        return switch (self.taxpayerYearPage.readinessStatus()) {
            .ready => "primary",
            .editing, .inactive, .no_consuming_forms, .unavailable => "secondary",
            .conflict,
            .invalid_settings,
            .missing_required_settings,
            .requires_review,
            => "destructive",
        };
    }

    pub fn taxpayerYearEditing(self: *const Model) bool {
        return self.taxpayerYearPage.page() == .editing;
    }

    pub fn taxpayerYearEditVisible(self: *const Model) bool {
        if (annualElectionPilotOpen(self)) {
            return annualIncomeTaxElectionCandidateEditable(self) and
                self.taxpayerYearPage.affordances().can_edit and
                !self.taxFormProfileEditing();
        }
        return self.taxpayerYearPage.affordances().can_edit and
            !self.taxFormProfileEditing();
    }

    pub fn taxpayerYearSaveDisabled(self: *const Model) bool {
        if (annualElectionPilotOpen(self) and
            !annualIncomeTaxElectionCandidateEditable(self)) return true;
        return !self.taxpayerYearPage.affordances().can_save;
    }

    pub fn taxpayerYearCancelDisabled(self: *const Model) bool {
        return !self.taxpayerYearPage.affordances().can_cancel;
    }

    pub fn taxpayerYearReviewVisible(self: *const Model) bool {
        if (annualElectionPilotOpen(self)) return false;
        return self.taxpayerYearPage.affordances().can_acknowledge_review;
    }

    pub fn taxpayerYearCopyPriorYearVisible(self: *const Model) bool {
        if (annualElectionPilotOpen(self)) return false;
        return self.taxpayerYearPage.affordances().can_copy_prior_year and
            !self.taxFormProfileEditing();
    }

    pub fn taxpayerYearCopyPriorYearLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const offer = self.taxpayerYearPage.priorYearCopyOffer() orelse
            return "Copy prior-year settings";
        return std.fmt.allocPrint(
            arena,
            "Copy settings from {d}",
            .{offer.stream.tax_year},
        ) catch "Copy prior-year settings";
    }

    pub fn taxpayerYearConflictVisible(self: *const Model) bool {
        if (annualElectionPilotOpen(self)) return false;
        return self.taxpayerYearPage.pendingConflict() != null;
    }

    pub fn taxpayerYearConflictKeepDraftDisabled(self: *const Model) bool {
        return !self.taxpayerYearPage.affordances().can_rebase_conflict;
    }

    pub fn taxpayerYearConflictReloadDisabled(self: *const Model) bool {
        return !self.taxpayerYearPage.affordances().can_reload_conflict;
    }

    pub fn taxpayerYearGraduatedSelected(self: *const Model) bool {
        return taxpayerYearRateElection(self) == .graduated;
    }

    pub fn taxpayerYearEightPercentSelected(self: *const Model) bool {
        return taxpayerYearRateElection(self) == .eight_percent;
    }

    pub fn taxpayerYearRateLabel(self: *const Model) []const u8 {
        return switch (taxpayerYearRateElection(self) orelse
            return "Not selected") {
            .graduated => "Graduated income-tax rates",
            .eight_percent => "8% income-tax rate",
        };
    }

    pub fn taxpayerYearDeductionVisible(self: *const Model) bool {
        if (annualElectionPilotOpen(self)) return false;
        return self.taxpayerYearPage.consumption.deduction_method_when_graduated and
            taxpayerYearRateElection(self) == .graduated;
    }

    pub fn taxpayerYearItemizedSelected(self: *const Model) bool {
        return taxpayerYearDeductionMethod(self) == .itemized_deduction;
    }

    pub fn taxpayerYearOsdSelected(self: *const Model) bool {
        return taxpayerYearDeductionMethod(self) == .optional_standard_deduction;
    }

    pub fn taxpayerYearDeductionLabel(self: *const Model) []const u8 {
        return switch (taxpayerYearDeductionMethod(self) orelse
            return "Not selected") {
            .itemized_deduction => "Itemized deduction",
            .optional_standard_deduction => "Optional standard deduction",
        };
    }

    pub fn taxpayerYearEligibilityLabel(self: *const Model) []const u8 {
        if (!annualElectionPilotOpen(self)) return "Not applicable";
        return switch (self.annualIncomeTaxElection.eligibility) {
            .eligible => "Eligible individual percentage-tax taxpayer",
            .taxpayer_type_ineligible => "Only eligible individual business/professional taxpayers may elect this rate",
            .classification_unresolved => "Tax Classification must be confirmed first",
            .business_commencement_unresolved => "Business commencement is not confirmed in Registration",
            .percentage_tax_registration_missing => "A confirmed percentage-tax registration is required",
            .vat_registered => "VAT-registered taxpayers are not eligible for this election",
            .registration_requires_review => "Registration evidence requires review",
            .unresolved => "Eligibility has not been resolved",
            .load_failed => "Eligibility could not be loaded",
        };
    }

    pub fn taxpayerYearInitialQuarterLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const quarter = self.annualIncomeTaxElection.initial_applicable_quarter orelse
            return "Unresolved";
        return std.fmt.allocPrint(
            arena,
            "Q{d}",
            .{quarter},
        ) catch "Unresolved";
    }

    pub fn taxpayerYearSourceLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const current = self.annualIncomeTaxElection.current orelse
            return "No saved annual source";
        const source = switch (current.provenance.kind) {
            .statutory_default => "Statutory default",
            .form_1901 => "Form 1901 evidence",
            .form_1905 => "Form 1905 evidence",
            .form_1701q => "Form 1701Q",
            .form_2551q => "Form 2551Q",
            .migration => "Migrated evidence",
            .statutory_disqualification => "Statutory disqualification",
        };
        if (current.provenance.filing_quarter) |quarter| {
            return std.fmt.allocPrint(
                arena,
                "{s}, Q{d} (sequence {d})",
                .{ source, quarter, current.sequence },
            ) catch source;
        }
        return std.fmt.allocPrint(
            arena,
            "{s} (sequence {d})",
            .{ source, current.sequence },
        ) catch source;
    }

    pub fn taxpayerYearLockStateLabel(self: *const Model) []const u8 {
        const current = self.annualIncomeTaxElection.current orelse
            return "Unresolved - no annual choice saved";
        return switch (current.state) {
            .candidate => "Editable candidate; locks only at the filing boundary",
            .reserved => "Reserved by a queued initial-quarter filing",
            .confirmed => "Locked by a submitted filing or reviewed evidence",
            .review_required => "Historical evidence conflicts; review required",
        };
    }

    pub fn taxpayerYearBlockNoticeVisible(self: *const Model) bool {
        if (!annualElectionPilotOpen(self)) return false;
        if (self.annualIncomeTaxElection.load_failed) return true;
        if (self.annualIncomeTaxElection.eligibility != .eligible) return true;
        if (self.annualIncomeTaxElection.current) |current| {
            if (current.state == .review_required) return true;
        }
        const initial = self.annualIncomeTaxElection.initial_applicable_quarter orelse
            return true;
        if (self.annualIncomeTaxElection.filing_quarter == initial) return false;
        const current = self.annualIncomeTaxElection.current orelse return true;
        return current.state != .confirmed;
    }

    pub fn taxpayerYearBlockNotice(self: *const Model) []const u8 {
        if (self.annualIncomeTaxElection.load_failed) {
            return "The saved annual income tax rate could not be loaded.";
        }
        if (self.annualIncomeTaxElection.eligibility != .eligible) {
            return self.taxpayerYearEligibilityLabel();
        }
        if (self.annualIncomeTaxElection.current) |current| {
            if (current.state == .review_required) {
                return "Conflicting annual income-tax-rate evidence requires review before filing.";
            }
        }
        const initial = self.annualIncomeTaxElection.initial_applicable_quarter orelse
            return "Resolve the initial-quarter income tax rate first.";
        if (self.annualIncomeTaxElection.filing_quarter != initial) {
            return "Resolve the initial-quarter income tax rate first. A later quarter cannot establish the annual choice merely because it is filed first.";
        }
        return "Resolve the annual income-tax-rate election before filing.";
    }

    pub fn profileFormsShowMoreVisible(self: *const Model) bool {
        if (self.formsManageMode()) return false;
        var count: usize = 0;
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (self.browseFormMatches(definition, index)) count += 1;
        }
        return count > self.libraryFilter.page_offset + self.libraryFilter.visible_limit;
    }

    pub fn profileFormsHasMoreRows(self: *const Model) bool {
        return self.profileFormsShowMoreVisible();
    }

    pub fn profileFormsHasPreviousRows(self: *const Model) bool {
        return !self.formsManageMode() and
            self.libraryFilter.page_offset != 0;
    }

    pub fn profileFormsPreviousDisabled(self: *const Model) bool {
        return !self.profileFormsHasPreviousRows();
    }

    pub fn profileFormsNextDisabled(self: *const Model) bool {
        return !self.profileFormsHasMoreRows();
    }

    pub fn profileFormsPaginationVisible(self: *const Model) bool {
        return self.profileFormsHasPreviousRows() or
            self.profileFormsHasMoreRows();
    }

    pub fn profileFormsPageLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        var total: usize = 0;
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (self.browseFormMatches(definition, index)) total += 1;
        }
        if (total == 0) return "No forms";
        const first = @min(self.libraryFilter.page_offset + 1, total);
        const last = @min(
            self.libraryFilter.page_offset + self.libraryFilter.visible_limit,
            total,
        );
        return std.fmt.allocPrint(
            arena,
            "Forms {d}-{d} of {d}",
            .{ first, last, total },
        ) catch "Forms page";
    }

    pub fn profileFormRowsEmpty(
        self: *const Model,
        arena: std.mem.Allocator,
    ) bool {
        return self.profileFormRows(arena).len == 0;
    }

    pub fn profileBrowseActiveEmpty(self: *const Model) bool {
        if (self.formsManageMode()) return false;
        const browse_year = profileBrowseAvailabilityYear(self);
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (self.profileFormAvailabilityYear == browse_year) {
                if (self.profileFormAnyPeriodActive[index]) return false;
            } else if (self.yearWorkspaceContextActive()) {
                if (self.taxProfiles.persistedFormSelected(index)) return false;
            } else if (self.taxProfiles.formAvailable(browse_year, definition.code)) {
                return false;
            }
        }
        return true;
    }

    pub fn dashboardCalendarActive(self: *const Model) bool {
        return self.dashboardSection == .calendar;
    }

    pub fn dashboardFormsActive(self: *const Model) bool {
        return self.dashboardSection == .forms;
    }

    pub fn dashboardProfileSettingsActive(self: *const Model) bool {
        return self.dashboardSection == .profile_settings;
    }

    pub fn profileTaxActive(self: *const Model) bool {
        return self.profileSetupSection == .tax_profile;
    }

    pub fn profileTaxFormsActive(self: *const Model) bool {
        return self.profileSetupSection == .tax_forms;
    }

    pub fn regSectionVisible(self: *const Model) bool {
        return self.profileTaxFormsActive() and !self.editingNewProfile();
    }

    pub fn regLoadFail(self: *const Model) bool {
        return self.regSectionVisible() and self.regLoadFailed;
    }

    pub fn regContent(self: *const Model) bool {
        return self.regSectionVisible() and self.regLoaded and
            !self.regLoadFailed;
    }

    pub fn regEditing(self: *const Model) bool {
        return self.regPage.opened and
            self.regPage.page_state == .editing;
    }

    pub fn regEditVisible(self: *const Model) bool {
        return self.regPage.affordances().can_begin_edit;
    }

    pub fn regSaveDisabled(self: *const Model) bool {
        return !self.regPage.affordances().can_save;
    }

    pub fn regCancelDisabled(self: *const Model) bool {
        return !self.regPage.affordances().can_cancel;
    }

    pub fn regAddActDisabled(self: *const Model) bool {
        return !self.regPage.affordances().can_add_business_activity;
    }

    pub fn regAddObDisabled(self: *const Model) bool {
        return !self.regPage.affordances().can_add_registration_obligation;
    }

    pub fn regActVisible(self: *const Model) bool {
        return self.regPage.affordances().show_business_activity_section;
    }

    pub fn regObVisible(self: *const Model) bool {
        return self.regPage.affordances().show_registration_obligation_section;
    }

    pub fn regActEmpty(self: *const Model) bool {
        for (self.regPage.businessActivities()) |*activity| {
            if (!isPrimaryRegistrationActivity(activity)) return false;
        }
        return true;
    }

    pub fn regObEmpty(self: *const Model) bool {
        return self.regPage.registrationObligations().len == 0;
    }

    pub fn regReview(self: *const Model) bool {
        return self.regPage.reviewRequiredRows().len != 0;
    }

    pub fn regFactsVisible(self: *const Model) bool {
        for (self.regPage.confirmedReadOnlyFacts()) |fact| switch (fact) {
            .eopt_tier => {},
            else => return true,
        };
        return false;
    }

    pub fn regReviewLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const count = self.regPage.reviewRequiredRows().len;
        return std.fmt.allocPrint(
            arena,
            "{d} imported or migrated registration {s} require review before use.",
            .{ count, if (count == 1) "item" else "items" },
        ) catch "Registration items require review before use.";
    }

    pub fn regConflict(self: *const Model) bool {
        return self.regPage.conflict != null;
    }

    pub fn regDialog(self: *const Model) bool {
        return self.regDialogMode != .none;
    }

    pub fn regActivityDialog(self: *const Model) bool {
        return self.regDialogMode == .add_activity or
            self.regDialogMode == .edit_activity;
    }

    pub fn regDialogTitle(self: *const Model) []const u8 {
        return switch (self.regDialogMode) {
            .add_activity => "Add business activity",
            .edit_activity => "Edit business activity",
            .add_obligation => "Add registration obligation",
            .edit_obligation => "Edit registration obligation",
            .none => "Registration detail",
        };
    }

    pub fn regLine(self: *const Model) []const u8 {
        return self.regLineOfBusiness.text();
    }

    pub fn regAtcValue(self: *const Model) []const u8 {
        return self.regAtc.text();
    }

    pub fn regFrom(self: *const Model) []const u8 {
        return self.regEffectiveFrom.text();
    }

    pub fn regUntil(self: *const Model) []const u8 {
        return self.regEffectiveUntil.text();
    }

    pub fn regOtherValue(self: *const Model) []const u8 {
        return self.regOtherTaxType.text();
    }

    pub fn regOtherVisible(self: *const Model) bool {
        return self.regObligationDraftKind == .withholding_other;
    }

    pub fn regErrVisible(self: *const Model) bool {
        return self.regEditorError.text().len != 0;
    }

    pub fn regErrText(self: *const Model) []const u8 {
        return self.regEditorError.text();
    }

    pub fn regIncome(self: *const Model) bool {
        return self.regObligationDraftKind == .registered_income_tax;
    }

    pub fn regVat(self: *const Model) bool {
        return self.regObligationDraftKind == .vat;
    }

    pub fn regPct(self: *const Model) bool {
        return self.regObligationDraftKind == .percentage_tax;
    }

    pub fn regWhComp(self: *const Model) bool {
        return self.regObligationDraftKind == .withholding_compensation;
    }

    pub fn regWhExpanded(self: *const Model) bool {
        return self.regObligationDraftKind == .withholding_expanded;
    }

    pub fn regWhFinal(self: *const Model) bool {
        return self.regObligationDraftKind == .withholding_final;
    }

    pub fn regWhOther(self: *const Model) bool {
        return self.regObligationDraftKind == .withholding_other;
    }

    fn regEffectiveLabel(
        period: profile_registration.EffectivePeriod,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (period.until) |until| {
            return std.fmt.allocPrint(
                arena,
                "{d:0>4}-{d:0>2}-{d:0>2} to {d:0>4}-{d:0>2}-{d:0>2}",
                .{
                    period.from.year,
                    period.from.month,
                    period.from.day,
                    until.year,
                    until.month,
                    until.day,
                },
            ) catch "Effective period unavailable";
        }
        return std.fmt.allocPrint(
            arena,
            "From {d:0>4}-{d:0>2}-{d:0>2}",
            .{ period.from.year, period.from.month, period.from.day },
        ) catch "Effective period unavailable";
    }

    fn isPrimaryRegistrationActivity(
        activity: *const profile_registration_ui.BusinessActivityRow,
    ) bool {
        return std.mem.eql(
            u8,
            activity.anchor_id.asSlice(),
            profile_registration_ui.primary_business_activity_anchor,
        );
    }

    pub fn regActRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const RegistrationActivityView {
        const source = self.regPage.businessActivities();
        const rows = arena.alloc(RegistrationActivityView, source.len) catch
            return &.{};
        var row_count: usize = 0;
        for (source, 0..) |*activity, index| {
            if (isPrimaryRegistrationActivity(activity)) continue;
            rows[row_count] = .{
                .id = index,
                .line_of_business = activity.line_of_business.asSlice(),
                .atc = if (activity.atc) |*atc| atc.asSlice() else "Not recorded",
                .effective = regEffectiveLabel(
                    activity.effective,
                    arena,
                ),
            };
            row_count += 1;
        }
        return rows[0..row_count];
    }

    pub fn regObRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const RegistrationObligationView {
        const source = self.regPage.registrationObligations();
        const rows = arena.alloc(RegistrationObligationView, source.len) catch
            return &.{};
        for (source, 0..) |*obligation, index| {
            const label: []const u8 = switch (obligation.kind) {
                .registered_income_tax => "Income tax",
                .vat => "Value-added tax (VAT)",
                .percentage_tax => "Percentage tax",
                .withholding => |withholding| switch (withholding) {
                    .compensation => "Withholding - compensation",
                    .expanded => "Withholding - expanded",
                    .final => "Withholding - final",
                    .other => |value| std.fmt.allocPrint(
                        arena,
                        "Withholding - {s}",
                        .{value.asSlice()},
                    ) catch "Other withholding tax",
                    .unspecified_requires_review => "Withholding - review required",
                },
                .unknown_requires_review => "Registration type requires review",
            };
            rows[index] = .{
                .id = index,
                .kind = label,
                .effective = regEffectiveLabel(
                    obligation.effective,
                    arena,
                ),
            };
        }
        return rows;
    }

    pub fn regFactRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const RegistrationFactView {
        const source = self.regPage.confirmedReadOnlyFacts();
        const rows = arena.alloc(RegistrationFactView, source.len) catch
            return &.{};
        var row_count: usize = 0;
        for (source) |fact| {
            switch (fact) {
                .eopt_tier => continue,
                else => {},
            }
            const label: []const u8 = switch (fact) {
                .agent_designation => "Withholding-agent designation",
                .eopt_tier => unreachable,
                .registration_activity_status => "Registration status",
                .special_law_or_treaty_basis => "Special-law or treaty basis",
            };
            const value: []const u8 = switch (fact) {
                .agent_designation => |item| switch (item.value) {
                    .not_designated => "Not designated",
                    .government_withholding_agent => "Government withholding agent",
                    .top_withholding_agent => "Top withholding agent",
                    .government_and_top_withholding_agent => "Government and top withholding agent",
                    .unknown_requires_review => "Review required",
                },
                .eopt_tier => |item| switch (item.value) {
                    .not_applicable => "Not applicable",
                    .micro => "Micro",
                    .small => "Small",
                    .medium => "Medium",
                    .large => "Large",
                    .unknown_requires_review => "Review required",
                },
                .registration_activity_status => |item| switch (item.value) {
                    .active => "Active",
                    .inactive => "Inactive",
                    .unknown_requires_review => "Review required",
                },
                .special_law_or_treaty_basis => |item| switch (item.value) {
                    .special_law => |basis| std.fmt.allocPrint(
                        arena,
                        "Special law: {s}",
                        .{basis.asSlice()},
                    ) catch "Special law",
                    .treaty => |basis| std.fmt.allocPrint(
                        arena,
                        "Treaty: {s}",
                        .{basis.asSlice()},
                    ) catch "Treaty",
                    .unknown_requires_review => "Review required",
                },
            };
            const effective = switch (fact) {
                inline else => |item| regEffectiveLabel(
                    item.metadata.effective,
                    arena,
                ),
            };
            rows[row_count] = .{
                .id = row_count,
                .fact_label = label,
                .detail = std.fmt.allocPrint(
                    arena,
                    "{s} - {s}",
                    .{ value, effective },
                ) catch value,
            };
            row_count += 1;
        }
        return rows[0..row_count];
    }

    /// What the COR card says about the referenced document.
    ///
    /// The reference is re-checked when the taxpayer loads, so the card can
    /// report that the file moved or changed rather than showing a name that
    /// no longer stands for anything.
    pub fn profileCorStatusLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.taxProfiles.editing_new) {
            return "Save this taxpayer first, then attach its COR.";
        }
        const name = self.taxProfiles.corFileName();
        return switch (self.taxProfiles.corEvidenceState()) {
            .none => "No COR on file. Attach it to check your details against it.",
            .on_file => std.fmt.allocPrint(
                arena,
                "{s} · attached {s}",
                .{ name, friendlyUnixDateLabel(
                    arena,
                    self.taxProfiles.corAttachedAt(),
                ) },
            ) catch name,
            .moved => std.fmt.allocPrint(
                arena,
                "{s} was moved or deleted since you attached it.",
                .{name},
            ) catch "That document was moved or deleted.",
            .changed => std.fmt.allocPrint(
                arena,
                "{s} changed since you attached it.",
                .{name},
            ) catch "That document changed since you attached it.",
        };
    }

    pub fn profileCorActionLabel(self: *const Model) []const u8 {
        return if (self.taxProfiles.corEvidenceState() == .none)
            "Attach COR"
        else
            "Attach updated COR";
    }

    pub fn profileCorUploadDisabled(self: *const Model) bool {
        // A document belongs to a saved taxpayer.
        return self.taxProfiles.editing_new or
            self.taxProfiles.selectedProfileId() == null;
    }

    pub fn profileCorReviewAvailable(self: *const Model) bool {
        return !self.taxProfiles.corReviewOpen() and
            self.taxProfiles.corEvidenceState() != .none;
    }

    pub fn profileCorReviewOpen(self: *const Model) bool {
        return self.taxProfiles.corReviewOpen();
    }

    pub fn profileCorReviewTinValue(self: *const Model) []const u8 {
        return self.taxProfiles.cor_review_tin.text();
    }

    pub fn profileCorMismatchVisible(self: *const Model) bool {
        return self.taxProfiles.corReviewOpen() and
            self.taxProfiles.corReviewTinMatch() == .mismatched;
    }

    /// States whose COR this is, in masked form. A refusal has to be specific
    /// enough to act on without printing an identifier in full.
    pub fn profileCorMismatchLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        var stated_buffer: [24]u8 = undefined;
        var current_buffer: [24]u8 = undefined;
        const stated = profile_fields.Tin.parse(
            self.taxProfiles.cor_review_tin.text(),
        ) catch return "That TIN is not a valid taxpayer identification number.";
        const current = profile_fields.Tin.parse(
            self.taxProfiles.tin.text(),
        ) catch return "This COR belongs to a different taxpayer.";
        return std.fmt.allocPrint(
            arena,
            "This COR belongs to TIN {s}, not this taxpayer ({s}).",
            .{
                stated.writeMasked(&stated_buffer) catch "***",
                current.writeMasked(&current_buffer) catch "***",
            },
        ) catch "This COR belongs to a different taxpayer.";
    }

    /// Each reviewed detail names itself and what the taxpayer has on file,
    /// so the user can see what accepting it would change before they do.
    fn profileCorCandidateLabel(
        self: *const Model,
        arena: std.mem.Allocator,
        candidate: profile_ui.CorCandidateField,
    ) []const u8 {
        const key = candidate.reusable();
        const current = self.taxProfiles.reusableValueText(key);
        const name = profile_ui.reusableFieldLabel(key);
        if (current.len == 0) {
            return std.fmt.allocPrint(
                arena,
                "{s} - not recorded yet",
                .{name},
            ) catch name;
        }
        return std.fmt.allocPrint(
            arena,
            "{s} - on file: {s}",
            .{ name, current },
        ) catch name;
    }

    pub fn profileCorRdoLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.profileCorCandidateLabel(arena, .rdo_code);
    }

    pub fn profileCorRdoValue(self: *const Model) []const u8 {
        return self.taxProfiles.corReviewValue(
            @intFromEnum(profile_ui.CorCandidateField.rdo_code),
        );
    }

    pub fn profileCorRdoAccepted(self: *const Model) bool {
        return self.taxProfiles.corReviewAccepted(
            @intFromEnum(profile_ui.CorCandidateField.rdo_code),
        );
    }

    pub fn profileCorNameLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.profileCorCandidateLabel(arena, .taxpayer_name);
    }

    pub fn profileCorNameValue(self: *const Model) []const u8 {
        return self.taxProfiles.corReviewValue(
            @intFromEnum(profile_ui.CorCandidateField.taxpayer_name),
        );
    }

    pub fn profileCorNameAccepted(self: *const Model) bool {
        return self.taxProfiles.corReviewAccepted(
            @intFromEnum(profile_ui.CorCandidateField.taxpayer_name),
        );
    }

    pub fn profileCorAddressLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.profileCorCandidateLabel(arena, .registered_address);
    }

    pub fn profileCorAddressValue(self: *const Model) []const u8 {
        return self.taxProfiles.corReviewValue(
            @intFromEnum(profile_ui.CorCandidateField.registered_address),
        );
    }

    pub fn profileCorAddressAccepted(self: *const Model) bool {
        return self.taxProfiles.corReviewAccepted(
            @intFromEnum(profile_ui.CorCandidateField.registered_address),
        );
    }

    pub fn profileCorZipLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.profileCorCandidateLabel(arena, .zip_code);
    }

    pub fn profileCorZipValue(self: *const Model) []const u8 {
        return self.taxProfiles.corReviewValue(
            @intFromEnum(profile_ui.CorCandidateField.zip_code),
        );
    }

    pub fn profileCorZipAccepted(self: *const Model) bool {
        return self.taxProfiles.corReviewAccepted(
            @intFromEnum(profile_ui.CorCandidateField.zip_code),
        );
    }

    pub fn profileCorTaxTypeLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return self.profileCorCandidateLabel(arena, .tax_type);
    }

    pub fn profileCorTaxTypeValue(self: *const Model) []const u8 {
        return self.taxProfiles.corReviewValue(
            @intFromEnum(profile_ui.CorCandidateField.tax_type),
        );
    }

    pub fn profileCorTaxTypeAccepted(self: *const Model) bool {
        return self.taxProfiles.corReviewAccepted(
            @intFromEnum(profile_ui.CorCandidateField.tax_type),
        );
    }

    pub fn profileCorApplyFormsSelected(self: *const Model) bool {
        return self.taxProfiles.corReviewApplyForms();
    }

    pub fn profileCorApplyDisabled(self: *const Model) bool {
        return self.taxProfiles.corReviewApplyBlocked();
    }

    pub fn profileCorApplyLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const details = self.taxProfiles.corReviewAcceptedCount();
        const forms: usize = if (self.taxProfiles.corReviewApplyForms())
            self.taxProfiles.stagedFormCount()
        else
            0;
        return std.fmt.allocPrint(
            arena,
            "Apply {d} detail changes and {d} forms",
            .{ details, forms },
        ) catch "Apply";
    }

    pub fn profileCorApplyFormsLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const year = self.taxProfiles.workspaceYear() orelse
            return "Also apply the forms selected for this year";
        return std.fmt.allocPrint(
            arena,
            "Also apply the forms selected for {d}",
            .{year},
        ) catch "Also apply the selected forms";
    }

    pub fn profileEmailActive(self: *const Model) bool {
        return self.profileSetupSection == .email;
    }

    pub fn calendarRulesActive(self: *const Model) bool {
        return self.taxCalendarSection == .rules;
    }

    pub fn calendarOverridesActive(self: *const Model) bool {
        return self.taxCalendarSection == .overrides;
    }

    pub fn currentCalendarYear(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d}",
            .{self.calendar.selected_year},
        ) catch "";
    }

    pub fn profileCalendarYearLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.taxProfiles.formSetSummaries().len == 0) {
            return "No yearly form set";
        }
        return std.fmt.allocPrint(
            arena,
            "{d}",
            .{self.profileCalendar.selected_year},
        ) catch "Tax year";
    }

    pub fn profileCalendarYearPickerOpen(self: *const Model) bool {
        return self.profileCalendarYearPickerVisible;
    }

    pub fn profileCalendarYearPickerDisabled(self: *const Model) bool {
        return self.taxProfiles.formSetSummaries().len == 0;
    }

    pub fn profileCalendarPreviousMonthDisabled(self: *const Model) bool {
        return self.profileCalendar.selected_month <= 1;
    }

    pub fn profileCalendarNextMonthDisabled(self: *const Model) bool {
        return self.profileCalendar.selected_month >= 12;
    }

    pub fn profileCalendarYearQueryValue(self: *const Model) []const u8 {
        return self.profileCalendarYearQuery.text();
    }

    pub fn profileCalendarYearOptions(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileCalendarYearOption {
        const summaries = self.taxProfiles.formSetSummaries();
        const rows = arena.alloc(ProfileCalendarYearOption, summaries.len) catch
            return &.{};
        const query = self.profileCalendarYearQuery.text();
        var count: usize = 0;
        for (summaries) |summary| {
            if (summary.tax_year > self.calendarToday.year) continue;
            if (query.len == 0 and
                summary.tax_year < self.calendarToday.year -| 4 and
                summary.tax_year != self.profileCalendar.selected_year)
            {
                continue;
            }
            var year_text: [16]u8 = undefined;
            const rendered = std.fmt.bufPrint(
                &year_text,
                "{d}",
                .{summary.tax_year},
            ) catch continue;
            if (query.len != 0 and
                std.mem.indexOf(u8, rendered, query) == null)
            {
                continue;
            }
            rows[count] = .{
                .id = @intCast(summary.tax_year),
                .year = summary.tax_year,
                .selected = summary.tax_year == self.profileCalendar.selected_year,
            };
            count += 1;
        }
        return rows[0..count];
    }

    pub fn currentCalendarMonth(self: *const Model) []const u8 {
        return switch (self.calendar.selected_month) {
            1 => "January",
            2 => "February",
            3 => "March",
            4 => "April",
            5 => "May",
            6 => "June",
            7 => "July",
            8 => "August",
            9 => "September",
            10 => "October",
            11 => "November",
            12 => "December",
            else => "Unknown month",
        };
    }

    pub fn calendarRules(
        _: *const Model,
        arena: std.mem.Allocator,
    ) []const calendar_ui.RuleRow {
        return calendar_ui.ruleRows(arena);
    }

    pub fn calendarOverrides(self: *const Model) []const calendar_ui.OverrideRow {
        return self.calendar.overrides[0..self.calendar.override_count];
    }

    pub fn calendarOverridesEmpty(self: *const Model) bool {
        return self.calendar.override_count == 0;
    }

    pub fn calendarNonWorkingDays(
        self: *const Model,
    ) []const calendar_ui.NonWorkingDayRow {
        return self.calendar.non_working_days[0..self.calendar.non_working_day_count];
    }

    pub fn calendarNonWorkingDaysEmpty(self: *const Model) bool {
        return self.calendar.non_working_day_count == 0;
    }

    pub fn calendarNoticeVisible(self: *const Model) bool {
        return self.calendar.notice.len != 0;
    }

    pub fn calendarNotice(self: *const Model) []const u8 {
        return self.calendar.notice.text();
    }

    pub fn calendarNoticeTone(self: *const Model) []const u8 {
        return switch (self.calendar.notice_kind) {
            .neutral => "secondary",
            .success => "primary",
            .failure => "destructive",
        };
    }

    pub fn profileCalendarExportNoticeVisible(self: *const Model) bool {
        if (self.profileCalendarExportStatus == .idle) return false;
        const exported = self.calendarExportProfileRevision orelse
            return false;
        const selected = self.taxProfiles.selectedRevisionContext() orelse
            return false;
        return exported.eql(&selected);
    }

    pub fn profileCalendarExportBusy(self: *const Model) bool {
        return self.profileCalendarExportStatus == .writing or
            self.profileCalendarExportStatus == .opening;
    }

    pub fn profileCalendarExportNoticeSuccess(self: *const Model) bool {
        return self.profileCalendarExportStatus == .opened;
    }

    pub fn profileCalendarExportNoticeFailure(self: *const Model) bool {
        return switch (self.profileCalendarExportStatus) {
            .build_failed,
            .write_failed,
            .opener_unavailable,
            .unsupported_platform,
            .open_failed,
            => true,
            else => false,
        };
    }

    pub fn profileCalendarExportNoticeDismissible(
        self: *const Model,
    ) bool {
        return self.profileCalendarExportNoticeAutoDismissible();
    }

    fn profileCalendarExportNoticeAutoDismissible(
        self: *const Model,
    ) bool {
        return self.profileCalendarExportStatus != .idle and
            !self.profileCalendarExportBusy();
    }

    pub fn profileCalendarExportNotice(self: *const Model) []const u8 {
        return switch (self.profileCalendarExportStatus) {
            .idle => "",
            .wrong_context => "Calendar export must be started from the selected tax profile.",
            .no_profile => "Create or select a tax profile before exporting its calendar.",
            .unavailable => "Calendar handoff is unavailable until this profile's Forms Set can be loaded.",
            .nothing_to_add => "Nothing to add. This profile's Forms Set has no calendar deadline for this tax year.",
            .build_failed => "Could not prepare this profile's calendar handoff.",
            .writing => "Preparing this profile's calendar handoff file…",
            .opening => "Calendar file created. Opening the default calendar app…",
            .opened => "Opened this profile's calendar handoff. Choose the calendar account that should receive it.",
            .write_failed => "Could not write this profile's calendar handoff file.",
            .opener_unavailable => "The default-calendar opener is unavailable in this test context.",
            .unsupported_platform => "This platform has no configured default-calendar opener.",
            .open_failed => "The calendar file was created, but the default calendar app could not be opened.",
        };
    }

    pub fn overrideEditorTitle(self: *const Model) []const u8 {
        return if (self.calendar.editing_override_id == null)
            "Add deadline override"
        else
            "Edit deadline override";
    }

    pub fn overrideSaveLabel(self: *const Model) []const u8 {
        return if (self.calendar.editing_override_id == null)
            "Save override"
        else
            "Update override";
    }

    pub fn overrideTitleValue(self: *const Model) []const u8 {
        return self.calendar.override_title.text();
    }

    pub fn overrideFormsValue(self: *const Model) []const u8 {
        return self.calendar.override_forms.text();
    }

    pub fn overrideOriginalValue(self: *const Model) []const u8 {
        return self.calendar.override_original.text();
    }

    pub fn overrideAdjustedValue(self: *const Model) []const u8 {
        return self.calendar.override_adjusted.text();
    }

    pub fn overrideSourceValue(self: *const Model) []const u8 {
        return self.calendar.override_source.text();
    }

    pub fn overrideRegionsValue(self: *const Model) []const u8 {
        return self.calendar.override_regions.text();
    }

    pub fn overrideTaxpayerTypesValue(self: *const Model) []const u8 {
        return self.calendar.override_taxpayer_types.text();
    }

    pub fn overrideEffectiveFromValue(self: *const Model) []const u8 {
        return self.calendar.override_effective_from.text();
    }

    pub fn overrideEffectiveUntilValue(self: *const Model) []const u8 {
        return self.calendar.override_effective_until.text();
    }

    pub fn overrideExpiresAtValue(self: *const Model) []const u8 {
        return self.calendar.override_expires_at.text();
    }

    pub fn nonWorkingDayEditorTitle(self: *const Model) []const u8 {
        return if (self.calendar.editing_non_working_day_id == null)
            "Add non-working day"
        else
            "Edit non-working day";
    }

    pub fn nonWorkingDaySaveLabel(self: *const Model) []const u8 {
        return if (self.calendar.editing_non_working_day_id == null)
            "Save non-working day"
        else
            "Update non-working day";
    }

    pub fn nonWorkingDateValue(self: *const Model) []const u8 {
        return self.calendar.non_working_date.text();
    }

    pub fn nonWorkingNameValue(self: *const Model) []const u8 {
        return self.calendar.non_working_name.text();
    }

    pub fn nonWorkingKindValue(self: *const Model) []const u8 {
        return self.calendar.non_working_kind.text();
    }

    pub fn nonWorkingSourceValue(self: *const Model) []const u8 {
        return self.calendar.non_working_source.text();
    }

    pub fn nonWorkingRegionsValue(self: *const Model) []const u8 {
        return self.calendar.non_working_regions.text();
    }

    pub fn backgroundJobsActive(self: *const Model) bool {
        return self.backgroundTasksSection == .jobs;
    }

    pub fn backgroundLogsActive(self: *const Model) bool {
        return self.backgroundTasksSection == .logs;
    }

    pub fn globalCalendarFormPickerOpen(self: *const Model) bool {
        return self.globalDashboard.forms.isOpen();
    }

    pub fn globalCalendarFormSelectionText(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const count = self.globalDashboard.selectedFormCount();
        return std.fmt.allocPrint(
            arena,
            "{d} selected",
            .{count},
        ) catch "Selected forms";
    }

    pub fn globalCalendarFormQuery(self: *const Model) []const u8 {
        return self.globalDashboard.forms.query();
    }

    pub fn globalCalendarFormRowHeight(self: *const Model) f32 {
        return self.dashboardControlHeight();
    }

    pub fn globalCalendarFormPickerWidth(self: *const Model) f32 {
        if (self.constrainedLayout() or self.globalCalendarHeaderStacked()) {
            return self.globalCalendarLaneWidth();
        }
        return compact_global_form_picker_width;
    }

    pub fn globalCalendarFormOptionsHeight(self: *const Model) f32 {
        const filtered_count = self.filteredGlobalCalendarFormOptionCount();
        const visible_count = std.math.clamp(
            filtered_count,
            @as(usize, 1),
            max_visible_global_form_rows,
        );
        return self.globalCalendarFormRowHeight() *
            @as(f32, @floatFromInt(visible_count));
    }

    pub fn globalCalendarFormMenuHeight(self: *const Model) f32 {
        const row_height = self.globalCalendarFormRowHeight();
        // Search plus the pinned bulk-action row and two separators stay
        // outside the scrolling option region.
        const pinned_height = row_height * 2 + 2;
        return @min(
            @as(f32, 420),
            self.globalCalendarFormOptionsHeight() + pinned_height,
        );
    }

    pub fn visibleGlobalCalendarFormOptions(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const CalendarFormOptionRow {
        const visible_count = @min(
            self.filteredGlobalCalendarFormOptionCount(),
            max_rendered_form_options,
        );
        if (visible_count == 0) return &.{};

        const rows = arena.alloc(
            CalendarFormOptionRow,
            visible_count,
        ) catch return &.{};
        var output_index: usize = 0;
        for (calendar_form_codes, 0..) |code, index| {
            if (!self.globalDashboard.forms.matches(code)) continue;
            if (output_index == rows.len) break;

            rows[output_index] = .{
                .id = index,
                .label = code,
                .selected = self.globalDashboard.formIsSelected(index),
            };
            output_index += 1;
        }
        return rows[0..output_index];
    }

    pub fn globalCalendarAllFilteredSelected(self: *const Model) bool {
        var found_match = false;
        for (calendar_form_codes, 0..) |code, index| {
            if (!self.globalDashboard.forms.matches(code)) continue;
            found_match = true;
            if (!self.globalDashboard.formIsSelected(index)) return false;
        }
        return found_match;
    }

    pub fn globalCalendarAnyFormsSelected(self: *const Model) bool {
        return self.globalDashboard.hasSelectedForms();
    }

    pub fn globalCalendarFormPickerDisabled(self: *const Model) bool {
        _ = self;
        return false;
    }

    pub fn profileCalendarFormPickerOpen(self: *const Model) bool {
        return self.profileCalendarForms.isOpen();
    }

    pub fn profileCalendarFormSelectionText(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const count = self.profileCalendarSelectedActiveFormCount();
        return std.fmt.allocPrint(
            arena,
            "{d} {s}",
            .{ count, if (count == 1) "form" else "forms" },
        ) catch "Forms";
    }

    pub fn profileCalendarFormQuery(self: *const Model) []const u8 {
        return self.profileCalendarForms.query();
    }

    fn profileCalendarFormRowHeight(self: *const Model) f32 {
        _ = self;
        return 44;
    }

    pub fn profileCalendarFormPickerWidth(self: *const Model) f32 {
        const width = self.effectiveDashboardWidth();
        if (self.desktopLayout()) return @min(width, @as(f32, 260));
        if (self.phoneLayout()) return width;
        return @max(@as(f32, 160), (width - 60) / 2);
    }

    pub fn profileCalendarYearPickerWidth(self: *const Model) f32 {
        const width = self.effectiveDashboardWidth();
        if (self.desktopLayout()) return @min(width, @as(f32, 176));
        if (self.phoneLayout()) return @max(@as(f32, 120), width - 52);
        return @max(@as(f32, 120), (width - 60) / 2);
    }

    pub fn profileCalendarFormOptionsHeight(self: *const Model) f32 {
        const visible_count = std.math.clamp(
            self.filteredProfileCalendarFormOptionCount(),
            @as(usize, 1),
            max_visible_global_form_rows,
        );
        return self.profileCalendarFormRowHeight() *
            @as(f32, @floatFromInt(visible_count));
    }

    pub fn profileCalendarFormMenuHeight(self: *const Model) f32 {
        const pinned_height = self.profileCalendarFormRowHeight() * 2 + 2;
        return @min(
            @as(f32, 420),
            self.profileCalendarFormOptionsHeight() + pinned_height,
        );
    }

    pub fn visibleProfileCalendarFormOptions(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileCalendarFormOptionRow {
        const visible_count = self.filteredProfileCalendarFormOptionCount();
        if (visible_count == 0) return &.{};
        const rows = arena.alloc(
            ProfileCalendarFormOptionRow,
            visible_count,
        ) catch return &.{};
        var count: usize = 0;
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (!self.profileCalendarFormActive(index) or
                !self.profileCalendarFormMatches(definition)) continue;
            rows[count] = .{
                .id = index,
                .code = definition.code,
                .title = definition.display_title,
                .label = std.fmt.allocPrint(
                    arena,
                    "{s} - {s}",
                    .{ definition.code, definition.display_title },
                ) catch definition.code,
                .selected = self.profileCalendarForms.isSelected(index),
            };
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileCalendarAllFilteredSelected(self: *const Model) bool {
        var found = false;
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (!self.profileCalendarFormActive(index) or
                !self.profileCalendarFormMatches(definition)) continue;
            found = true;
            if (!self.profileCalendarForms.isSelected(index)) return false;
        }
        return found;
    }

    pub fn profileCalendarAnyFormsSelected(self: *const Model) bool {
        return self.profileCalendarSelectedActiveFormCount() != 0;
    }

    pub fn profileCalendarFormPickerDisabled(self: *const Model) bool {
        for (0..form_catalog.registry_count) |index| {
            if (self.profileCalendarFormActive(index)) return false;
        }
        return true;
    }

    fn profileCalendarSelectedActiveFormCount(self: *const Model) usize {
        var count: usize = 0;
        for (0..form_catalog.registry_count) |index| {
            if (self.profileCalendarFormActive(index) and
                self.profileCalendarForms.isSelected(index)) count += 1;
        }
        return count;
    }

    fn profileCalendarFormActive(self: *const Model, index: usize) bool {
        if (index >= form_catalog.registry_count or
            !self.hasSelectedTaxpayer()) return false;
        const form_code = form_catalog.forms[index].code;
        if (self.profileFormAvailabilityYear ==
            self.profileCalendar.selected_year and
            self.profileFormAnyPeriodActive[index]) return true;
        // The picker must describe the same effective set as the visible
        // calendar. A whole-year membership cache cannot answer this when a
        // From-date decision splits the year, so derive activity only from
        // deadlines that pass the canonical filing-date resolver.
        for (
            self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count],
        ) |*deadline| {
            const selection_code = if (formCodesEquivalent(deadline.form_code, "1604C") or
                formCodesEquivalent(deadline.form_code, "1604F"))
                "1604CF"
            else
                deadline.form_code;
            if (!formCodesEquivalent(selection_code, form_code) or
                !self.profileCalendarIncludesDeadline(deadline)) continue;
            return true;
        }
        return false;
    }

    fn profileCalendarFormMatches(
        self: *const Model,
        definition: *const form_catalog.FormDefinition,
    ) bool {
        const query = self.profileCalendarForms.query();
        return multi_select.containsAsciiInsensitive(definition.code, query) or
            multi_select.containsAsciiInsensitive(
                definition.display_title,
                query,
            );
    }

    fn filteredProfileCalendarFormOptionCount(self: *const Model) usize {
        var count: usize = 0;
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (self.profileCalendarFormActive(index) and
                self.profileCalendarFormMatches(definition)) count += 1;
        }
        return count;
    }

    fn setFilteredProfileCalendarForms(
        self: *Model,
        selected: bool,
    ) void {
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (!self.profileCalendarFormActive(index) or
                !self.profileCalendarFormMatches(definition)) continue;
            _ = self.profileCalendarForms.set(index, selected);
        }
    }

    pub fn globalCalendarMonth(self: *const Model) []const u8 {
        return fullMonthName(self.globalDashboard.calendar.selected_month);
    }

    pub fn globalCalendarYear(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d}",
            .{self.globalDashboard.calendar.selected_year},
        ) catch "";
    }

    pub fn globalCalendarDeadlineHeading(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.globalDashboard.selectedDay()) |day| {
            return std.fmt.allocPrint(
                arena,
                "Deadlines for {s} {d}, {d}",
                .{
                    fullMonthName(self.globalDashboard.calendar.selected_month),
                    day,
                    self.globalDashboard.calendar.selected_year,
                },
            ) catch "Deadlines";
        }
        return std.fmt.allocPrint(
            arena,
            "Deadlines for {s} {d}",
            .{
                fullMonthName(self.globalDashboard.calendar.selected_month),
                self.globalDashboard.calendar.selected_year,
            },
        ) catch "Deadlines";
    }

    pub fn importantNewsRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ImportantNewsRow {
        const notices = if (self.newsNotices) |*list|
            list.items
        else
            return &.{};
        const rows = arena.alloc(ImportantNewsRow, notices.len) catch
            return &.{};
        for (notices, 0..) |*notice, index| {
            rows[index] = .{ .id = index, .notice = notice };
        }
        return rows;
    }

    pub fn importantNewsRefreshing(self: *const Model) bool {
        return self.news.isRefreshing();
    }

    pub fn importantNewsRefreshDisabled(self: *const Model) bool {
        return self.importantNewsRefreshing();
    }

    pub fn importantNewsHasRows(self: *const Model) bool {
        return self.news.hasCachedNotices();
    }

    pub fn importantNewsLoadingEmpty(self: *const Model) bool {
        return self.news.isRefreshing() and !self.news.hasCachedNotices();
    }

    pub fn importantNewsEmpty(self: *const Model) bool {
        return self.news.phase == .empty;
    }

    pub fn importantNewsErrorVisible(self: *const Model) bool {
        return self.news.phase == .@"error";
    }

    pub fn importantNewsError(self: *const Model) []const u8 {
        return self.news.errorMessage();
    }

    /// The Global Dashboard is the complete resolved rules/override schedule.
    /// It never consults a selected tax profile's form choices.
    pub fn globalDeadlines(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const calendar_ui.DeadlineRow {
        const calendar = &self.globalDashboard.calendar;
        const all = calendar.deadlines[0..calendar.deadline_count];
        const rows = arena.alloc(
            calendar_ui.DeadlineRow,
            all.len,
        ) catch return &.{};
        var count: usize = 0;
        for (all) |row| {
            if (row.final_deadline.month !=
                calendar.selected_month) continue;
            if (row.final_deadline.year != calendar.selected_year) continue;
            if (self.globalDashboard.selectedDay()) |selected_day| {
                if (row.final_deadline.day != selected_day) continue;
            }
            if (!self.globalCalendarIncludesForm(row.form_code)) continue;
            rows[count] = row;
            count += 1;
        }
        return rows[0..count];
    }

    pub fn globalCalendarHasDeadlines(self: *const Model) bool {
        const calendar = &self.globalDashboard.calendar;
        for (calendar.deadlines[0..calendar.deadline_count]) |row| {
            if (row.final_deadline.year == calendar.selected_year and
                row.final_deadline.month == calendar.selected_month and
                (self.globalDashboard.selectedDay() == null or
                    row.final_deadline.day == self.globalDashboard.selectedDay().?) and
                self.globalCalendarIncludesForm(row.form_code))
            {
                return true;
            }
        }
        return false;
    }

    pub fn globalCalendarDeadlineCount(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const count = self.globalDeadlines(arena).len;
        const noun = deadlineNoun(count);
        return std.fmt.allocPrint(
            arena,
            "{d} {s}",
            .{ count, noun },
        ) catch "Deadlines";
    }

    pub fn globalCalendarDays(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileCalendarDayCell {
        const first = calendar_domain.Date.init(
            self.globalDashboard.calendar.selected_year,
            self.globalDashboard.calendar.selected_month,
            1,
        ) catch return &.{};
        const leading: usize = switch (first.weekday()) {
            .sunday => 0,
            .monday => 1,
            .tuesday => 2,
            .wednesday => 3,
            .thursday => 4,
            .friday => 5,
            .saturday => 6,
        };
        const days = calendar_domain.Date.daysInMonth(
            self.globalDashboard.calendar.selected_year,
            self.globalDashboard.calendar.selected_month,
        );
        const cells = arena.alloc(ProfileCalendarDayCell, 42) catch
            return &.{};
        for (cells, 0..) |*cell, index| {
            const day_index = index -| leading;
            const day: u8 = if (index >= leading and day_index < days)
                @intCast(day_index + 1)
            else
                0;
            const marker_tone = if (day == 0)
                CalendarMarkerTone.normal
            else
                self.globalCalendarMarkerToneForDay(day);
            cell.* = .{
                .id = index,
                .day = day,
                .deadline_count = if (day == 0)
                    0
                else
                    self.globalCalendarDeadlineCountForDay(day),
                .overdue_flag = marker_tone == .overdue,
                .due_soon_flag = marker_tone == .due_soon,
                .approaching_flag = marker_tone == .approaching,
                .selected_flag = day != 0 and
                    self.globalDashboard.isDaySelected(day),
            };
        }
        return cells;
    }

    fn profileDeadlineById(
        self: *const Model,
        id: u64,
    ) ?*const calendar_ui.DeadlineRow {
        for (
            self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count],
        ) |*deadline| {
            if (deadline.id == id) return deadline;
        }
        return null;
    }

    fn profileDeadlineDialogDateLabel(
        arena: std.mem.Allocator,
        date: calendar_domain.Date,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{s} {d}, {d}",
            .{ shortMonthName(date.month), date.day, date.year },
        ) catch "Date unavailable";
    }

    fn profileDeadlineAdjustmentDialogOpen(self: *const Model) bool {
        const id = self.profileDeadlineAdjustmentId orelse return false;
        const deadline = self.profileDeadlineById(id) orelse return false;
        return deadline.adjustmentVisible() or deadline.status == .extended;
    }

    fn profileDeadlineAdjustmentContext(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const id = self.profileDeadlineAdjustmentId orelse return "Deadline";
        const deadline = self.profileDeadlineById(id) orelse return "Deadline";
        const row = self.profileCalendarDeadlineRow(deadline.*);
        return std.fmt.allocPrint(
            arena,
            "{s} · {s}",
            .{ row.compactLabel(arena), deadline.form_name },
        ) catch deadline.display_form_no;
    }

    fn profileDeadlineAdjustmentSummary(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const id = self.profileDeadlineAdjustmentId orelse
            return "Deadline details are unavailable.";
        const deadline = self.profileDeadlineById(id) orelse
            return "Deadline details are unavailable.";
        if (deadline.adjustmentVisible()) {
            return std.fmt.allocPrint(
                arena,
                "This deadline was moved from {s} to {s}.",
                .{
                    profileDeadlineDialogDateLabel(
                        arena,
                        deadline.original_deadline,
                    ),
                    profileDeadlineDialogDateLabel(
                        arena,
                        deadline.final_deadline,
                    ),
                },
            ) catch "This deadline was adjusted.";
        }
        return if (deadline.status == .extended)
            "The filing deadline is marked as extended."
        else
            "This deadline has no recorded adjustment.";
    }

    fn profileDeadlineAdjustmentSourceVisible(
        self: *const Model,
    ) bool {
        const id = self.profileDeadlineAdjustmentId orelse return false;
        const deadline = self.profileDeadlineById(id) orelse return false;
        return deadline.sourceVisible();
    }

    fn profileDeadlineAdjustmentSource(self: *const Model) []const u8 {
        const id = self.profileDeadlineAdjustmentId orelse return "";
        const deadline = self.profileDeadlineById(id) orelse return "";
        return deadline.sourceLabel();
    }

    fn profileDeadlineStubDialogOpen(self: *const Model) bool {
        return self.profileDeadlineStubAction != .none and
            self.profileDeadlineStubDeadlineId != null;
    }

    fn profileDeadlineStubTitle(self: *const Model) []const u8 {
        return switch (self.profileDeadlineStubAction) {
            .submit => "Submission is not connected yet",
            .check_confirmation => "Confirmation check is not connected yet",
            .print => "Print preview is not available yet",
            .upload_receipt => "Receipt upload is not available yet",
            .pay_online => "Online payment is not available yet",
            else => "Action is not available yet",
        };
    }

    fn profileDeadlineStubContext(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const id = self.profileDeadlineStubDeadlineId orelse return "Filing";
        const deadline = self.profileDeadlineById(id) orelse return "Filing";
        const row = self.profileCalendarDeadlineRow(deadline.*);
        return std.fmt.allocPrint(
            arena,
            "{s} · {s}",
            .{ row.compactLabel(arena), row.filingStatus() },
        ) catch deadline.display_form_no;
    }

    fn profileDeadlineStubBody(self: *const Model) []const u8 {
        return switch (self.profileDeadlineStubAction) {
            .submit => "Filing transport is not connected in this build. Your draft remains unchanged.",
            .check_confirmation => "Automatic inbox checking is not connected in this build. The filing remains Sent.",
            .print => "A filing-specific print preview is still being connected. No document was generated.",
            .upload_receipt => "Receipt upload is still being connected. The filing remains Confirmed.",
            .pay_online => "No supported online payment provider is configured for this filing.",
            else => "This action is not available in the current build.",
        };
    }

    pub fn profileDeadlineDialogOpen(self: *const Model) bool {
        return self.profileDeadlineAdjustmentDialogOpen() or
            self.profileDeadlineStubDialogOpen();
    }

    pub fn profileDeadlineDialogTitle(self: *const Model) []const u8 {
        return if (self.profileDeadlineAdjustmentDialogOpen())
            "Deadline adjustment"
        else
            self.profileDeadlineStubTitle();
    }

    pub fn profileDeadlineDialogContext(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return if (self.profileDeadlineAdjustmentDialogOpen())
            self.profileDeadlineAdjustmentContext(arena)
        else
            self.profileDeadlineStubContext(arena);
    }

    pub fn profileDeadlineDialogBody(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return if (self.profileDeadlineAdjustmentDialogOpen())
            self.profileDeadlineAdjustmentSummary(arena)
        else
            self.profileDeadlineStubBody();
    }

    pub fn profileDeadlineDialogSourceVisible(self: *const Model) bool {
        return self.profileDeadlineAdjustmentDialogOpen() and
            self.profileDeadlineAdjustmentSourceVisible();
    }

    pub fn profileDeadlineDialogSource(self: *const Model) []const u8 {
        return if (self.profileDeadlineAdjustmentDialogOpen())
            self.profileDeadlineAdjustmentSource()
        else
            "";
    }

    pub fn profileCalendarDeadlineHeading(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.profileCalendarSelectedDay()) |day| {
            return std.fmt.allocPrint(
                arena,
                "Deadlines for {s} {d}, {d}",
                .{
                    fullMonthName(self.profileCalendar.selected_month),
                    day,
                    self.profileCalendar.selected_year,
                },
            ) catch "Deadlines";
        }
        return std.fmt.allocPrint(
            arena,
            "Deadlines for {s} {d}",
            .{
                fullMonthName(self.profileCalendar.selected_month),
                self.profileCalendar.selected_year,
            },
        ) catch "Deadlines";
    }

    fn profileCalendarDeadlineRowForLane(
        self: *const Model,
        deadline: calendar_ui.DeadlineRow,
        lane: ProfileDeadlineLane,
    ) ProfileCalendarDeadlineRow {
        var filing_state = ProfileFilingState.new;
        var draft_stage = ProfileDeadlineDraftStage.none;
        var paid_found = false;
        var matched_state: ?ProfileFilingState = null;
        var matched_stage = ProfileDeadlineDraftStage.none;
        var matched_draft_id: ?form_ids.DraftId = null;
        var matched_rank: u8 = 0;
        for (self.taxProfiles.draftSummaries()) |*draft| {
            if (!draftMatchesDeadline(draft, &deadline)) continue;
            const lifecycle = draft.lifecycleText();
            if (std.mem.eql(u8, lifecycle, "cancelled")) continue;
            if (std.mem.eql(u8, lifecycle, "paid")) {
                paid_found = true;
                continue;
            }
            const state: ProfileFilingState = if (std.mem.eql(u8, lifecycle, "editing") or
                std.mem.eql(u8, lifecycle, "prepared"))
                .draft
            else if (std.mem.eql(u8, lifecycle, "queued"))
                .queued
            else if (std.mem.eql(u8, lifecycle, "submitted"))
                .sent
            else if (std.mem.eql(u8, lifecycle, "confirmed"))
                .confirmed
            else
                .unknown;
            const stage: ProfileDeadlineDraftStage = if (std.mem.eql(
                u8,
                lifecycle,
                "editing",
            ))
                .editing
            else if (std.mem.eql(u8, lifecycle, "prepared"))
                .prepared
            else
                .none;
            const lifecycle_rank: u8 = if (std.mem.eql(u8, lifecycle, "editing"))
                5
            else if (std.mem.eql(u8, lifecycle, "prepared"))
                4
            else if (std.mem.eql(u8, lifecycle, "queued"))
                3
            else if (std.mem.eql(u8, lifecycle, "submitted"))
                2
            else if (std.mem.eql(u8, lifecycle, "confirmed"))
                1
            else
                0;
            const rank = lifecycle_rank +
                (if (std.mem.eql(u8, draft.intentText(), "amended"))
                    @as(u8, 10)
                else
                    0);
            if (matched_state == null or rank > matched_rank) {
                matched_state = state;
                matched_stage = stage;
                matched_draft_id = form_ids.DraftId.parse(
                    draft.draftId(),
                ) catch null;
                matched_rank = rank;
            }
        }
        if (matched_state) |state| {
            filing_state = state;
            draft_stage = matched_stage;
        } else if (paid_found) {
            filing_state = .paid;
        } else if (self.taxProfiles.draftSummariesTruncated()) {
            filing_state = .unknown;
        }

        var actions = profileDeadlineActionsFor(
            filing_state,
            draft_stage,
            false,
        );
        if (matched_state != null and matched_draft_id == null) actions = .{};
        if (profileFormRoute(deadline.form_code) == null) {
            filing_state = .calendar_only;
            draft_stage = .none;
            actions = .{};
        } else {
            const launch = self.profileDeadlineLaunchProjection(&deadline);
            if (launch.ready) {
                switch (launch.assessment.status) {
                    .needs_profile => {
                        actions = .{};
                        actions.add(.complete_profile);
                    },
                    .profile_not_eligible, .unavailable => actions = .{},
                    .ready_new, .ready_resume, .needs_activity_selection => {},
                }
            }
        }

        const timing: ProfileDeadlineTiming = if (filing_state == .paid)
            .closed
        else switch (calendar_domain.Date.compare(
            deadline.final_deadline,
            self.calendarToday,
        )) {
            .lt => .overdue,
            .eq => .due_today,
            .gt => .upcoming,
        };
        const menu_id = profileDeadlineMenuId(
            self.profileDeadlineProjectionGeneration,
            deadline.id,
            lane,
        );
        const action_menu_open = if (self.profileDeadlineActionMenuId) |open_id|
            actions.count > 1 and open_id == menu_id
        else
            false;
        return .{
            .id = deadline.id,
            .deadline = deadline,
            .projection_generation = self.profileDeadlineProjectionGeneration,
            .filing_state = filing_state,
            .timing = timing,
            .draft_stage = draft_stage,
            .draft_id = matched_draft_id,
            .actions = actions,
            .menu_id = menu_id,
            .action_menu_open = action_menu_open,
        };
    }

    fn profileCalendarDeadlineRow(
        self: *const Model,
        deadline: calendar_ui.DeadlineRow,
    ) ProfileCalendarDeadlineRow {
        return self.profileCalendarDeadlineRowForLane(deadline, .deadlines);
    }

    fn profileDeadlineLaunchProjection(
        self: *const Model,
        deadline: *const calendar_ui.DeadlineRow,
    ) ProfileDeadlineLaunchProjection {
        for (
            self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count],
            0..,
        ) |candidate, index| {
            if (candidate.id != deadline.id or
                !self.profileDeadlineLaunchAssessmentsReady[index]) continue;
            return .{
                .assessment = self.profileDeadlineLaunchAssessments[index],
                .ready = true,
            };
        }
        return .{};
    }

    pub fn profileMonthlyDeadlineRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileCalendarDeadlineRow {
        const all = self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count];
        const rows = arena.alloc(ProfileCalendarDeadlineRow, all.len) catch
            return &.{};
        var count: usize = 0;
        for (all) |deadline| {
            if (!self.profileDeadlineIsInSelectedMonth(&deadline))
                continue;
            if (self.profileCalendarSelectedDay()) |selected_day| {
                if (deadline.final_deadline.day != selected_day) continue;
            }
            rows[count] = self.profileCalendarDeadlineRowForLane(
                deadline,
                .deadlines,
            );
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileMonthlyHasDeadlines(
        self: *const Model,
        arena: std.mem.Allocator,
    ) bool {
        return self.profileMonthlyDeadlineRows(arena).len != 0;
    }

    fn profileDeadlineIsInSelectedMonth(
        self: *const Model,
        deadline: *const calendar_ui.DeadlineRow,
    ) bool {
        return deadline.final_deadline.year ==
            self.profileCalendar.selected_year and
            deadline.final_deadline.month ==
                self.profileCalendar.selected_month and
            self.profileCalendarViewIncludesDeadline(deadline);
    }

    fn profileMonthlyDeadlineCount(self: *const Model) usize {
        var count: usize = 0;
        for (
            self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count],
        ) |deadline| {
            if (self.profileDeadlineIsInSelectedMonth(&deadline))
                count += 1;
        }
        return count;
    }

    pub fn profileMonthlyDeadlineCountLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const count = self.profileMonthlyDeadlineCount();
        if (count == 1) return "1 deadline";
        return std.fmt.allocPrint(
            arena,
            "{d} deadlines",
            .{count},
        ) catch "Deadlines";
    }

    pub fn profileActionRequiredRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileCalendarDeadlineRow {
        const all = self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count];
        const rows = arena.alloc(ProfileCalendarDeadlineRow, all.len) catch
            return &.{};
        var count: usize = 0;
        for (all) |deadline| {
            if (!self.profileDeadlineIsInSelectedMonth(&deadline) or
                calendar_domain.Date.compare(
                    deadline.final_deadline,
                    self.calendarToday,
                ) == .lt) continue;
            const row = self.profileCalendarDeadlineRowForLane(
                deadline,
                .action_required,
            );
            if (!row.needsAction()) continue;
            rows[count] = row;
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileActionRequiredHasRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) bool {
        return self.profileActionRequiredRows(arena).len != 0;
    }

    pub fn profileActionRequiredCount(
        self: *const Model,
        arena: std.mem.Allocator,
    ) usize {
        return self.profileActionRequiredRows(arena).len;
    }

    pub fn profileOverdueDeadlineRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileCalendarDeadlineRow {
        const all = self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count];
        const rows = arena.alloc(ProfileCalendarDeadlineRow, all.len) catch
            return &.{};
        var count: usize = 0;
        for (all) |deadline| {
            if (deadline.final_deadline.year != self.profileCalendar.selected_year or
                !self.profileCalendarViewIncludesDeadline(&deadline) or
                calendar_domain.Date.compare(
                    deadline.final_deadline,
                    self.calendarToday,
                ) != .lt) continue;
            const row = self.profileCalendarDeadlineRowForLane(
                deadline,
                .overdue,
            );
            if (!row.needsAction()) continue;
            if (deadline.final_deadline.month != self.profileCalendar.selected_month and
                !row.filing_state.isSavedOpen()) continue;
            rows[count] = row;
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileOverdueHasDeadlines(
        self: *const Model,
        arena: std.mem.Allocator,
    ) bool {
        return self.profileOverdueDeadlineRows(arena).len != 0;
    }

    pub fn profileOverdueDeadlineCount(
        self: *const Model,
        arena: std.mem.Allocator,
    ) usize {
        return self.profileOverdueDeadlineRows(arena).len;
    }

    pub fn profileCalendarDays(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileCalendarDayCell {
        const first = calendar_domain.Date.init(
            self.profileCalendar.selected_year,
            self.profileCalendar.selected_month,
            1,
        ) catch return &.{};
        const leading: usize = switch (first.weekday()) {
            .sunday => 0,
            .monday => 1,
            .tuesday => 2,
            .wednesday => 3,
            .thursday => 4,
            .friday => 5,
            .saturday => 6,
        };
        const days = calendar_domain.Date.daysInMonth(
            self.profileCalendar.selected_year,
            self.profileCalendar.selected_month,
        );
        const cells = arena.alloc(ProfileCalendarDayCell, 42) catch
            return &.{};
        for (cells, 0..) |*cell, index| {
            const day_index = index -| leading;
            const day: u8 = if (index >= leading and day_index < days)
                @intCast(day_index + 1)
            else
                0;
            const marker_tone = if (day == 0)
                CalendarMarkerTone.normal
            else
                self.profileCalendarMarkerToneForDay(day);
            cell.* = .{
                .id = index,
                .day = day,
                .deadline_count = if (day == 0)
                    0
                else
                    self.profileCalendarDeadlineCountForDay(day),
                .closed_flag = marker_tone == .closed,
                .overdue_flag = marker_tone == .overdue,
                .due_soon_flag = marker_tone == .due_soon,
                .approaching_flag = marker_tone == .approaching,
                .selected_flag = day != 0 and
                    self.profileCalendarSelectedDay() == @as(?u8, day),
            };
        }
        return cells;
    }

    fn filteredGlobalCalendarFormOptionCount(self: *const Model) usize {
        var count: usize = 0;
        for (calendar_form_codes) |code| {
            if (self.globalDashboard.forms.matches(code)) count += 1;
        }
        return count;
    }

    fn setFilteredGlobalCalendarForms(
        self: *Model,
        selected: bool,
    ) void {
        for (calendar_form_codes, 0..) |code, index| {
            if (!self.globalDashboard.forms.matches(code)) continue;
            _ = self.globalDashboard.setForm(index, selected);
        }
    }

    fn globalCalendarDeadlineCountForDay(
        self: *const Model,
        day: u8,
    ) usize {
        var count: usize = 0;
        const calendar = &self.globalDashboard.calendar;
        for (calendar.deadlines[0..calendar.deadline_count]) |row| {
            if (row.final_deadline.year == calendar.selected_year and
                row.final_deadline.month == calendar.selected_month and
                row.final_deadline.day == day and
                self.globalCalendarIncludesForm(row.form_code)) count += 1;
        }
        return count;
    }

    fn globalCalendarMarkerToneForDay(
        self: *const Model,
        day: u8,
    ) CalendarMarkerTone {
        const calendar = &self.globalDashboard.calendar;
        const date = calendar_domain.Date.init(
            calendar.selected_year,
            calendar.selected_month,
            day,
        ) catch return .normal;
        for (calendar.deadlines[0..calendar.deadline_count]) |row| {
            if (calendar_domain.Date.compare(row.final_deadline, date) != .eq or
                !self.globalCalendarIncludesForm(row.form_code)) continue;
            return calendarMarkerTone(date, self.calendarToday);
        }
        return .normal;
    }

    fn globalCalendarIncludesForm(
        self: *const Model,
        deadline_form_code: []const u8,
    ) bool {
        const selection_code = if (std.ascii.eqlIgnoreCase(deadline_form_code, "1604C") or
            std.ascii.eqlIgnoreCase(deadline_form_code, "1604F")) "1604CF" else deadline_form_code;
        for (calendar_form_codes, 0..) |catalog_code, index| {
            if (!formCodesEquivalent(
                catalog_code,
                selection_code,
            )) continue;
            return self.globalDashboard.formIsSelected(index);
        }
        return false;
    }

    fn profileCalendarDeadlineCountForDay(
        self: *const Model,
        day: u8,
    ) usize {
        var count: usize = 0;
        for (self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count]) |row| {
            if (row.final_deadline.year != self.profileCalendar.selected_year or
                row.final_deadline.month != self.profileCalendar.selected_month or
                row.final_deadline.day != day or
                !self.profileCalendarViewIncludesDeadline(&row)) continue;
            count += 1;
        }
        return count;
    }

    fn profileCalendarMarkerToneForDay(
        self: *const Model,
        day: u8,
    ) CalendarMarkerTone {
        const date = calendar_domain.Date.init(
            self.profileCalendar.selected_year,
            self.profileCalendar.selected_month,
            day,
        ) catch return .normal;
        var found = false;
        var all_closed = true;
        var strongest = CalendarMarkerTone.normal;
        for (self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count]) |row| {
            if (calendar_domain.Date.compare(row.final_deadline, date) != .eq or
                !self.profileCalendarViewIncludesDeadline(&row)) continue;
            found = true;
            if (self.profileCalendarDeadlineRow(row).timing == .closed) continue;
            all_closed = false;
            const tone = calendarMarkerTone(date, self.calendarToday);
            const tone_rank: u8 = switch (tone) {
                .normal => 0,
                .approaching => 1,
                .due_soon => 2,
                .overdue => 3,
                .closed => unreachable,
            };
            const strongest_rank: u8 = switch (strongest) {
                .normal => 0,
                .approaching => 1,
                .due_soon => 2,
                .overdue => 3,
                .closed => unreachable,
            };
            if (tone_rank > strongest_rank) strongest = tone;
        }
        if (found and all_closed) return .closed;
        return strongest;
    }

    fn profileCalendarSelectedDay(self: *const Model) ?u8 {
        const selected = self.profileCalendarSelectedDate orelse return null;
        if (selected.year != self.profileCalendar.selected_year or
            selected.month != self.profileCalendar.selected_month)
        {
            return null;
        }
        return selected.day;
    }

    fn toggleProfileCalendarDay(self: *Model, day: u8) void {
        const selected = calendar_domain.Date.init(
            self.profileCalendar.selected_year,
            self.profileCalendar.selected_month,
            day,
        ) catch return;
        if (self.profileCalendarSelectedDate) |current| {
            if (calendar_domain.Date.compare(current, selected) == .eq) {
                self.profileCalendarSelectedDate = null;
                return;
            }
        }
        self.profileCalendarSelectedDate = selected;
    }

    fn profileDeadlineHasPaidDraft(
        self: *const Model,
        deadline: *const calendar_ui.DeadlineRow,
    ) bool {
        var paid_found = false;
        for (self.taxProfiles.draftSummaries()) |*draft| {
            if (!draftMatchesDeadline(draft, deadline)) continue;
            const lifecycle = draft.lifecycleText();
            if (std.mem.eql(u8, lifecycle, "cancelled")) continue;
            if (std.mem.eql(u8, lifecycle, "paid")) {
                paid_found = true;
            } else {
                // A paid original does not resolve an open amendment.
                return false;
            }
        }
        return paid_found;
    }

    fn profileDeadlineHasOpenDraft(
        self: *const Model,
        deadline: *const calendar_ui.DeadlineRow,
    ) bool {
        for (self.taxProfiles.draftSummaries()) |*draft| {
            if (std.mem.eql(u8, draft.lifecycleText(), "paid") or
                std.mem.eql(u8, draft.lifecycleText(), "cancelled")) continue;
            if (draftMatchesDeadline(draft, deadline)) return true;
        }
        return false;
    }

    fn profileCalendarViewIncludesDeadline(
        self: *const Model,
        deadline: *const calendar_ui.DeadlineRow,
    ) bool {
        if (!self.profileCalendarIncludesDeadline(deadline)) return false;
        const selection_code = if (formCodesEquivalent(deadline.form_code, "1604C") or
            formCodesEquivalent(deadline.form_code, "1604F"))
            "1604CF"
        else
            deadline.form_code;
        for (&form_catalog.forms, 0..) |*definition, index| {
            if (!formCodesEquivalent(definition.code, selection_code)) continue;
            return self.profileCalendarFormActive(index) and
                self.profileCalendarForms.isSelected(index);
        }
        return false;
    }

    fn profileCalendarIncludesDeadline(
        self: *const Model,
        deadline: *const calendar_ui.DeadlineRow,
    ) bool {
        const context = profileDeadlineAvailabilityContext(deadline) orelse
            return false;
        return formAvailableForFiling(
            self,
            context.definition,
            context.filing,
            context.occurrence_date,
        );
    }

    fn profileCalendarHasAnyIncludedDeadline(self: *const Model) bool {
        for (self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count]) |*deadline| {
            if (self.profileCalendarIncludesDeadline(deadline)) return true;
        }
        return false;
    }

    fn profileCalendarScopeAvailable(self: *const Model) bool {
        const year = self.profileCalendar.selected_year;
        return self.taxProfiles.hasExplicitFormSet(year);
    }

    fn profileCalendarIncludesForm(
        self: *const Model,
        deadline_form_code: []const u8,
    ) bool {
        for (
            self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count],
        ) |*deadline| {
            if (!formCodesEquivalent(deadline.form_code, deadline_form_code)) continue;
            if (self.profileCalendarIncludesDeadline(deadline)) return true;
        }
        return false;
    }

    fn profileCalendarIncludesFormForYear(
        self: *const Model,
        tax_year: i32,
        deadline_form_code: []const u8,
    ) bool {
        const wanted_code = if (formCodesEquivalent(deadline_form_code, "1604C") or
            formCodesEquivalent(deadline_form_code, "1604F"))
            "1604CF"
        else
            deadline_form_code;
        for (
            self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count],
        ) |*deadline| {
            const deadline_year = deadline.period.taxableYear() orelse
                deadline.original_deadline.year;
            const candidate_code = if (formCodesEquivalent(deadline.form_code, "1604C") or
                formCodesEquivalent(deadline.form_code, "1604F"))
                "1604CF"
            else
                deadline.form_code;
            if (deadline_year != tax_year or
                !formCodesEquivalent(candidate_code, wanted_code)) continue;
            if (self.profileCalendarIncludesDeadline(deadline)) return true;
        }
        return false;
    }

    /// The taxable years one export can touch. A January obligation belongs to
    /// the prior taxable year, so the export retains the adjacent-year union
    /// even though the on-screen calendar is scoped to its selected year.
    fn profileExportTaxYears(self: *const Model) [2]i32 {
        const year = self.profileCalendar.selected_year;
        return .{ year, if (year > 1) year - 1 else year };
    }

    /// A value copy of the on-screen profile calendar keeping only deadlines
    /// the selected taxpayer's Forms Set includes *for that deadline's own
    /// taxable year*, without mutating the global or on-screen projections.
    ///
    /// This is the authoritative filter, because it resolves each deadline
    /// against its own year. `profileExportFormScope` is a flat list and cannot
    /// express that, so it can only ever be a redundant second pass.
    fn profileCalendarForExport(self: *const Model) calendar_ui.State {
        var filtered = self.profileCalendar;
        filtered.deadline_count = 0;
        for (
            self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count],
        ) |deadline| {
            if (!self.profileCalendarIncludesDeadline(&deadline)) continue;
            filtered.deadlines[filtered.deadline_count] = deadline;
            filtered.deadline_count += 1;
        }
        return filtered;
    }

    /// The serializer receives an intentionally unrestricted second-pass
    /// scope. `profileCalendarForExport` already filters each deadline through
    /// the canonical date-effective resolver; a flat code list cannot preserve
    /// that interval semantics.
    fn profileExportFormScope(
        self: *const Model,
        arena: std.mem.Allocator,
    ) calendar_ui.ProfileFormScope {
        _ = self;
        _ = arena;
        // `profileCalendarForExport` has already applied the exact
        // filing-date resolver to every event. A flat list of form codes
        // cannot encode mid-year activation intervals, so applying one here
        // would be a weaker and potentially contradictory second authority.
        return .catalog_fallback;
    }
};

const LibraryDraftStatus = struct {
    label: []const u8,
    tone: []const u8,
};

fn onDemandDraftPeriodForSlot(
    drafts: []const profile_ui.DraftSummaryRow,
    form_code: []const u8,
    tax_year: u16,
    slot: usize,
) ?form_period.FilingPeriod {
    if (slot == 0) return null;
    var matched: usize = 0;
    for (drafts) |*draft| {
        if (!formCodesEquivalent(draft.formCode(), form_code)) continue;
        const period = form_period.FilingPeriod.parseKey(
            .on_demand,
            draft.periodKey(),
        ) catch continue;
        if (period.taxYear() != tax_year) continue;
        matched += 1;
        if (matched == slot) return period;
    }
    return null;
}

fn newOnDemandAssessmentPeriod(
    drafts: []const profile_ui.DraftSummaryRow,
    form_code: []const u8,
    tax_year: u16,
) ?form_period.FilingPeriod {
    var maximum: u32 = 0;
    for (drafts) |*draft| {
        if (!formCodesEquivalent(draft.formCode(), form_code)) continue;
        const period = form_period.FilingPeriod.parseKey(
            .on_demand,
            draft.periodKey(),
        ) catch continue;
        switch (period) {
            .on_demand => |value| {
                if (value.tax_year == tax_year) maximum = @max(
                    maximum,
                    value.occurrence,
                );
            },
            else => unreachable,
        }
    }
    if (maximum >= 999) return null;
    return .{ .on_demand = .{
        .tax_year = tax_year,
        .occurrence = maximum + 1,
    } };
}

fn libraryDraftStatus(
    drafts: []const profile_ui.DraftSummaryRow,
    drafts_truncated: bool,
    form_code: []const u8,
    period: form_period.FilingPeriod,
    arena: std.mem.Allocator,
) LibraryDraftStatus {
    var key_buffer: [32]u8 = undefined;
    const period_key = period.key(&key_buffer) catch "";
    for (drafts) |*draft| {
        if (!formCodesEquivalent(draft.formCode(), form_code)) continue;
        if (!std.mem.eql(u8, draft.periodKey(), period_key)) continue;
        return .{
            .label = filingLifecycleLabel(draft.lifecycleText()),
            .tone = filingLifecycleTone(draft.lifecycleText()),
        };
    }
    _ = arena;
    if (drafts_truncated) return .{
        .label = "Status unavailable",
        .tone = "secondary",
    };
    return .{ .label = "New", .tone = "outline" };
}

fn resetProfileFormsPage(model: *Model) void {
    model.libraryFilter.resetPage();
}

fn toggleCorAccepted(
    model: *Model,
    field_key: profile_ui.CorCandidateField,
) void {
    model.taxProfiles.toggleCorReviewAccepted(@intFromEnum(field_key));
}

fn applyCorValue(
    model: *Model,
    field_key: profile_ui.CorCandidateField,
    edit: canvas.TextInputEvent,
) void {
    model.taxProfiles.cor_review_values[@intFromEnum(field_key)].apply(edit);
}

/// Asks the platform for a document and attaches it as COR evidence.
///
/// The dialog is a synchronous platform service reached through the effects
/// channel's bound services, which is how a modal file picker works natively:
/// it blocks until the user chooses or cancels, and there is nothing to wait
/// for afterwards. Effects are absent in tests, where this is a no-op.
fn attachCorDocument(model: *Model, fx: ?*Effects) void {
    const effects = fx orelse return;
    const services = effects.services orelse {
        model.taxProfiles.reportFormLaunchFailure(
            "Choosing a file is not available on this system.",
        );
        return;
    };
    var paths: [native_sdk.platform.max_dialog_paths_bytes]u8 = undefined;
    const result = services.showOpenDialog(.{
        .title = "Choose your Certificate of Registration",
        .filters = &.{.{
            .name = "Certificate of Registration",
            .extensions = &.{ "pdf", "png", "jpg", "jpeg" },
        }},
    }, &paths) catch {
        model.taxProfiles.reportFormLaunchFailure(
            "The file chooser could not be opened.",
        );
        return;
    };
    // Cancelling is an ordinary outcome, not a failure to report.
    if (result.count == 0) return;
    // Multiple selection is off, so the result is one path; a newline would
    // only appear if that ever changed, and the first entry is still correct.
    const chosen = std.mem.sliceTo(result.paths, '\n');
    if (chosen.len == 0) return;
    _ = model.taxProfiles.attachCorDocument(chosen);
}

/// Groups registrations by their shared nine-digit TIN, head office before its
/// branches, then by branch code. Rows without a parsable TIN keep a stable
/// position at the end rather than interleaving unpredictably.
fn profileRowPrecedes(
    _: void,
    left: profile_ui.ProfileRow,
    right: profile_ui.ProfileRow,
) bool {
    const left_root = left.tinRoot();
    const right_root = right.tinRoot();
    if (left_root.len != right_root.len) return left_root.len > right_root.len;
    const root_order = std.mem.order(u8, left_root, right_root);
    if (root_order != .eq) return root_order == .lt;
    if (left.isBranch() != right.isBranch()) return !left.isBranch();
    const branch_order = std.mem.order(u8, left.branchCode(), right.branchCode());
    if (branch_order != .eq) return branch_order == .lt;
    return left.slot < right.slot;
}

const month_names = [_][]const u8{
    "January",   "February", "March",    "April",
    "May",       "June",     "July",     "August",
    "September", "October",  "November", "December",
};

/// Renders a Unix timestamp the way the interface speaks. Days are computed
/// from the epoch directly: the value is a recorded instant, not a date the
/// user typed, so there is nothing to parse.
fn friendlyUnixDateLabel(arena: std.mem.Allocator, unix_seconds: i64) []const u8 {
    if (unix_seconds <= 0) return "an unknown date";
    const days: i64 = @divFloor(unix_seconds, std.time.s_per_day);
    const epoch_day: std.time.epoch.EpochDay = .{ .day = @intCast(days) };
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const month_index = month_day.month.numeric() - 1;
    if (month_index >= month_names.len) return "an unknown date";
    return std.fmt.allocPrint(arena, "{s} {d}, {d}", .{
        month_names[month_index],
        month_day.day_index + 1,
        year_day.year,
    }) catch "an unknown date";
}

/// Renders an ISO date the way the interface speaks: "July 1, 2026". Falls
/// back to the stored text rather than inventing a date it cannot parse.
fn friendlyDateLabel(arena: std.mem.Allocator, iso: []const u8) []const u8 {
    if (iso.len != 10) return iso;
    const year = std.fmt.parseInt(u16, iso[0..4], 10) catch return iso;
    const month = std.fmt.parseInt(u8, iso[5..7], 10) catch return iso;
    const day = std.fmt.parseInt(u8, iso[8..10], 10) catch return iso;
    if (month < 1 or month > 12) return iso;
    return std.fmt.allocPrint(
        arena,
        "{s} {d}, {d}",
        .{ month_names[month - 1], day, year },
    ) catch iso;
}

fn recordedProfileValue(value: []const u8) []const u8 {
    return if (std.mem.trim(u8, value, " \t\r\n").len == 0)
        "Not recorded"
    else
        value;
}

/// Mirrors one text edit and then keeps only digits, so the year filter can
/// never hold arbitrary text no matter how the bytes arrived (typing, paste,
/// or an input method).
fn applyDigitsOnly(buffer: anytype, edit: canvas.TextInputEvent) void {
    buffer.apply(edit);
    const current = buffer.text();
    var digits: [8]u8 = undefined;
    var count: usize = 0;
    for (current) |byte| {
        if (!std.ascii.isDigit(byte)) continue;
        if (count == digits.len) break;
        digits[count] = byte;
        count += 1;
    }
    if (count != current.len) buffer.set(digits[0..count]);
}

fn syncProfileTinControl(model: *Model) void {
    const tin = segmented_tin.SegmentedTin.fromText(
        model.taxProfiles.tin.text(),
    );
    for (0..segmented_tin.segment_count) |index| {
        model.profileTinSegments[index].set(tin.segmentText(index).?);
    }
    model.profileTinFocusSegment = 0;
    model.profileTinFocusActive = false;
}

fn profileRdoLabel(entry: *const rdo_reference.Entry, output: []u8) []const u8 {
    return std.fmt.bufPrint(
        output,
        "{s} - {s}",
        .{ entry.code, entry.name },
    ) catch entry.code;
}

fn syncProfileRdoControl(model: *Model) void {
    model.profileRdoPickerVisible = false;
    const raw = std.mem.trim(u8, model.taxProfiles.rdo.text(), " \t\r\n");
    const entry = rdo_reference.findByCode(raw) orelse {
        model.profileRdoQuery.set(raw);
        return;
    };
    var buffer: [128]u8 = undefined;
    model.profileRdoQuery.set(profileRdoLabel(entry, &buffer));
}

fn syncProfileIdentityControls(model: *Model) void {
    syncProfileTinControl(model);
    syncProfileRdoControl(model);
}

fn applyProfileTinSegment(
    model: *Model,
    segment_index: usize,
    edit: canvas.TextInputEvent,
) void {
    if (segment_index >= segmented_tin.segment_count) return;
    const was_empty = model.profileTinSegments[segment_index].text().len == 0;
    model.profileTinSegments[segment_index].apply(edit);

    switch (edit) {
        .move_caret, .set_selection, .set_composition, .cancel_composition => return,
        .delete_backward => if (was_empty and segment_index != 0) {
            model.profileTinFocusSegment = @intCast(segment_index - 1);
            model.profileTinFocusActive = true;
            return;
        },
        else => {},
    }

    var tin = segmented_tin.SegmentedTin.fromText(
        model.taxProfiles.tin.text(),
    );
    const result = tin.replaceSegment(
        segment_index,
        model.profileTinSegments[segment_index].text(),
    ) orelse return;
    for (0..segmented_tin.segment_count) |index| {
        const normalized = tin.segmentText(index).?;
        if (!std.mem.eql(
            u8,
            model.profileTinSegments[index].text(),
            normalized,
        )) {
            model.profileTinSegments[index].set(normalized);
        }
    }
    var digits: [segmented_tin.maximum_digit_count]u8 = undefined;
    const canonical = tin.writeDigits(&digits) catch return;
    model.taxProfiles.tin.set(canonical);
    model.profileTinFocusSegment = @intCast(result.focus_segment);
    model.profileTinFocusActive = true;
}

fn applyProfileRdoQuery(
    model: *Model,
    edit: canvas.TextInputEvent,
) void {
    model.profileRdoQuery.apply(edit);
    model.profileRdoPickerVisible = true;
    const selected = rdo_reference.findByCode(
        model.taxProfiles.rdo.text(),
    ) orelse return;
    var buffer: [128]u8 = undefined;
    if (!std.mem.eql(
        u8,
        model.profileRdoQuery.text(),
        profileRdoLabel(selected, &buffer),
    )) {
        model.taxProfiles.rdo.clear();
    }
}

fn selectProfileRdo(model: *Model, entry_index: usize) void {
    if (entry_index >= rdo_reference.entries.len) return;
    model.taxProfiles.rdo.set(rdo_reference.entries[entry_index].code);
    syncProfileRdoControl(model);
}

fn resetRegistrationDialog(model: *Model) void {
    model.regDialogMode = .none;
    model.regSelectedIndex = null;
    model.regLineOfBusiness.clear();
    model.regAtc.clear();
    model.regEffectiveFrom.clear();
    model.regEffectiveUntil.clear();
    model.regOtherTaxType.clear();
    model.regEditorError.clear();
}

fn regSelectedTaxYear(model: *const Model) ?u16 {
    const year_value = model.taxProfiles.workspaceYear() orelse
        profileBrowseAvailabilityYear(model);
    if (year_value < 1 or year_value > 9999) return null;
    return @intCast(year_value);
}

fn regViewDate(model: *const Model) ?profile_model.Date {
    const tax_year = regSelectedTaxYear(model) orelse return null;
    return profile_model.Date.init(tax_year, 12, 31) catch null;
}

fn loadRegistrationPage(model: *Model) void {
    model.regLoaded = false;
    model.regLoadFailed = false;
    resetRegistrationDialog(model);
    const allocator = model.taxProfiles.allocator orelse {
        model.regLoadFailed = true;
        return;
    };
    const store = model.taxProfiles.store orelse {
        model.regLoadFailed = true;
        return;
    };
    const profile_id = model.taxProfiles.selectedProfileDomainId() orelse
        return;
    const viewed_on = regViewDate(model) orelse {
        model.regLoadFailed = true;
        return;
    };
    const tax_year = regSelectedTaxYear(model) orelse {
        model.regLoadFailed = true;
        return;
    };
    var owned = profile_persistence.loadRegistrationAggregateForYear(
        store,
        allocator,
        profile_id,
        tax_year,
    ) catch {
        model.regLoadFailed = true;
        return;
    };
    defer owned.deinit(allocator);
    model.regPage = profile_registration_ui.State.open(.{
        .aggregate = &owned.aggregate,
        .viewed_on = viewed_on,
        .selected_tax_year = tax_year,
        .subject_kind = model.taxProfiles.subjectKind(),
        .natural_person_classification = model.taxProfiles.naturalPersonClassification(),
        .expected_sequence = owned.stream_sequence,
    }) catch {
        model.regLoadFailed = true;
        return;
    };
    model.regLoaded = true;
    syncCompleteProfileRegistrationControls(model);
}

fn syncRegistrationTaxpayerContext(model: *Model) void {
    if (!model.regPage.opened) return;
    model.regPage.setTaxpayerContext(
        model.taxProfiles.subjectKind(),
        model.taxProfiles.naturalPersonClassification(),
    );
}

fn syncCompleteProfileRegistrationControls(model: *Model) void {
    model.profileClassificationPickerVisible = false;
    model.profileEoptPickerVisible = false;
    model.profilePrimaryLineOfBusiness.clear();
    const primary = model.regPage.primaryBusinessActivity() orelse return;
    model.profilePrimaryLineOfBusiness.set(
        primary.line_of_business.asSlice(),
    );
}

fn ensureCompleteProfileRegistrationLoaded(model: *Model) bool {
    if (model.taxProfiles.editing_new) return false;
    if (!model.regLoaded or model.regLoadFailed) {
        ensureYearWorkspaceOpen(model);
        if (!model.regLoaded or model.regLoadFailed) {
            loadRegistrationPage(model);
        }
    }
    if (!model.regLoaded or model.regLoadFailed) {
        model.taxProfiles.reportFormLaunchFailure(
            "Registration details could not be loaded. Retry before editing this Tax Profile.",
        );
        return false;
    }
    syncRegistrationTaxpayerContext(model);
    syncCompleteProfileRegistrationControls(model);
    return true;
}

fn initializeNewCompleteProfileRegistration(model: *Model) bool {
    const raw_year = std.mem.trim(
        u8,
        model.taxProfiles.tax_year.text(),
        " \t\r\n",
    );
    const tax_year = std.fmt.parseInt(u16, raw_year, 10) catch {
        model.regLoadFailed = true;
        return false;
    };
    const placeholder = profile_model.ProfileId.parse(
        "new-profile-placeholder",
    ) catch unreachable;
    const aggregate: profile_registration.RegistrationAggregate = .{
        .profile_id = placeholder,
    };
    const viewed_on = profile_model.Date.init(tax_year, 12, 31) catch {
        model.regLoadFailed = true;
        return false;
    };
    model.regPage = profile_registration_ui.State.open(.{
        .aggregate = &aggregate,
        .viewed_on = viewed_on,
        .selected_tax_year = tax_year,
        .subject_kind = model.taxProfiles.subjectKind(),
        .natural_person_classification = model.taxProfiles.naturalPersonClassification(),
        .expected_sequence = 0,
    }) catch {
        model.regLoadFailed = true;
        return false;
    };
    model.regPage.beginEdit() catch {
        model.regLoadFailed = true;
        return false;
    };
    model.regLoaded = true;
    model.regLoadFailed = false;
    syncCompleteProfileRegistrationControls(model);
    return true;
}

fn beginCompleteProfileEdit(model: *Model) void {
    if (!ensureCompleteProfileRegistrationLoaded(model)) return;
    model.regPage.beginEdit() catch return;
    model.taxProfiles.editSelected();
    if (!model.taxProfiles.profileEditing()) {
        loadRegistrationPage(model);
        return;
    }
    syncRegistrationTaxpayerContext(model);
    syncCompleteProfileRegistrationControls(model);
    syncProfileIdentityControls(model);
}

fn completeProfilePrimaryPeriod(
    model: *const Model,
) ?profile_registration.EffectivePeriod {
    if (model.regPage.primaryBusinessActivity()) |primary| {
        return primary.effective;
    }
    const tax_year = regSelectedTaxYear(model) orelse return null;
    const from = profile_model.Date.init(tax_year, 1, 1) catch return null;
    return profile_registration.EffectivePeriod.init(from, null) catch null;
}

fn applyCompleteProfilePrimaryLineOfBusiness(
    model: *Model,
    edit: canvas.TextInputEvent,
) void {
    if (!model.regEditing()) return;
    model.profilePrimaryLineOfBusiness.apply(edit);
    const value = std.mem.trim(
        u8,
        model.profilePrimaryLineOfBusiness.text(),
        " \t\r\n",
    );
    const existing = model.regPage.primaryBusinessActivity();
    if (value.len == 0) {
        if (existing != null) {
            model.regPage.removePrimaryBusinessActivity() catch {
                model.regEditorError.set(
                    "The primary Line of Business could not be cleared.",
                );
            };
        }
        return;
    }

    const effective = completeProfilePrimaryPeriod(model) orelse return;
    var atc_storage: [32]u8 = undefined;
    var atc: ?[]const u8 = null;
    if (existing) |primary| {
        if (primary.atc) |*code| {
            const source = code.asSlice();
            if (source.len <= atc_storage.len) {
                @memcpy(atc_storage[0..source.len], source);
                atc = atc_storage[0..source.len];
            }
        }
    }
    model.regPage.setPrimaryBusinessActivity(
        value,
        atc,
        effective,
    ) catch {
        model.regEditorError.set(
            "Enter a valid primary Line of Business.",
        );
    };
}

fn selectCompleteProfileEopt(
    model: *Model,
    tier: profile_registration_ui.EditableEoptTier,
) void {
    if (!model.regEditing()) return;
    const effective = model.regPage.eoptTierEffective() orelse blk: {
        const tax_year = regSelectedTaxYear(model) orelse return;
        const from = profile_model.Date.init(tax_year, 1, 1) catch return;
        break :blk profile_registration.EffectivePeriod.init(
            from,
            null,
        ) catch return;
    };
    model.regPage.setEoptTier(tier, effective) catch {
        model.regEditorError.set("The EOPT Tier could not be changed.");
        return;
    };
    model.profileEoptPickerVisible = false;
}

fn setRegistrationDateBuffers(
    model: *Model,
    period: profile_registration.EffectivePeriod,
) void {
    var from: [10]u8 = undefined;
    model.regEffectiveFrom.set(period.from.writeIso(&from));
    if (period.until) |until| {
        var until_buffer: [10]u8 = undefined;
        model.regEffectiveUntil.set(
            until.writeIso(&until_buffer),
        );
    } else {
        model.regEffectiveUntil.clear();
    }
}

fn defaultRegistrationPeriod(model: *Model) void {
    const viewed_on = regViewDate(model) orelse return;
    const from = profile_model.Date.init(viewed_on.year, 1, 1) catch return;
    setRegistrationDateBuffers(model, .{ .from = from, .until = null });
}

fn beginRegistrationActivityDialog(
    model: *Model,
    index: ?usize,
) void {
    resetRegistrationDialog(model);
    if (index) |selected| {
        const rows = model.regPage.businessActivities();
        if (selected >= rows.len) return;
        const row = &rows[selected];
        model.regDialogMode = .edit_activity;
        model.regSelectedIndex = selected;
        model.regLineOfBusiness.set(row.line_of_business.asSlice());
        if (row.atc) |*atc| model.regAtc.set(atc.asSlice());
        setRegistrationDateBuffers(model, row.effective);
    } else {
        model.regDialogMode = .add_activity;
        defaultRegistrationPeriod(model);
    }
}

fn setRegistrationObligationDraft(
    model: *Model,
    kind: profile_registration.RegistrationObligationKind,
) void {
    switch (kind) {
        .registered_income_tax => model.regObligationDraftKind =
            .registered_income_tax,
        .vat => model.regObligationDraftKind = .vat,
        .percentage_tax => model.regObligationDraftKind =
            .percentage_tax,
        .withholding => |withholding| switch (withholding) {
            .compensation => model.regObligationDraftKind =
                .withholding_compensation,
            .expanded => model.regObligationDraftKind =
                .withholding_expanded,
            .final => model.regObligationDraftKind =
                .withholding_final,
            .other => |value| {
                model.regObligationDraftKind = .withholding_other;
                model.regOtherTaxType.set(value.asSlice());
            },
            .unspecified_requires_review => {},
        },
        .unknown_requires_review => {},
    }
}

fn beginRegistrationObligationDialog(
    model: *Model,
    index: ?usize,
) void {
    resetRegistrationDialog(model);
    model.regObligationDraftKind = .registered_income_tax;
    if (index) |selected| {
        const rows = model.regPage.registrationObligations();
        if (selected >= rows.len) return;
        const row = &rows[selected];
        model.regDialogMode = .edit_obligation;
        model.regSelectedIndex = selected;
        setRegistrationObligationDraft(model, row.kind);
        setRegistrationDateBuffers(model, row.effective);
    } else {
        model.regDialogMode = .add_obligation;
        defaultRegistrationPeriod(model);
    }
}

fn regDraftPeriod(
    model: *Model,
) ?profile_registration.EffectivePeriod {
    const from = profile_model.Date.parseIso(
        model.regEffectiveFrom.text(),
    ) catch return null;
    const until = if (std.mem.trim(
        u8,
        model.regEffectiveUntil.text(),
        " \t\r\n",
    ).len == 0)
        null
    else
        profile_model.Date.parseIso(
            model.regEffectiveUntil.text(),
        ) catch return null;
    return profile_registration.EffectivePeriod.init(from, until) catch null;
}

fn regTypedObligation(
    model: *const Model,
) ?profile_registration_ui.TypedObligationInput {
    return switch (model.regObligationDraftKind) {
        .registered_income_tax => .registered_income_tax,
        .vat => .vat,
        .percentage_tax => .percentage_tax,
        .withholding_compensation => .withholding_compensation,
        .withholding_expanded => .withholding_expanded,
        .withholding_final => .withholding_final,
        .withholding_other => if (std.mem.trim(
            u8,
            model.regOtherTaxType.text(),
            " \t\r\n",
        ).len == 0)
            null
        else
            .{ .withholding_other = model.regOtherTaxType.text() },
    };
}

fn commitRegistrationDialog(model: *Model) void {
    model.regEditorError.clear();
    const period = regDraftPeriod(model) orelse {
        model.regEditorError.set(
            "Enter valid YYYY-MM-DD effectivity dates.",
        );
        return;
    };
    switch (model.regDialogMode) {
        .add_activity => {
            const store = model.taxProfiles.store orelse return;
            const generated = store.generateOpaqueId() catch return;
            const anchor = profile_registration.ActivityAnchorId.parse(
                &generated,
            ) catch return;
            model.regPage.addBusinessActivity(
                anchor,
                model.regLineOfBusiness.text(),
                model.regAtc.text(),
                period,
            ) catch {
                model.regEditorError.set(
                    "Enter a line of business and a valid optional ATC.",
                );
                return;
            };
        },
        .edit_activity => {
            const index = model.regSelectedIndex orelse return;
            const rows = model.regPage.businessActivities();
            if (index >= rows.len) return;
            model.regPage.updateBusinessActivity(
                rows[index].anchor_id,
                model.regLineOfBusiness.text(),
                model.regAtc.text(),
                period,
            ) catch {
                model.regEditorError.set(
                    "Enter a line of business and a valid optional ATC.",
                );
                return;
            };
        },
        .add_obligation => {
            const input = regTypedObligation(model) orelse {
                model.regEditorError.set(
                    "Enter the other withholding registration type.",
                );
                return;
            };
            const store = model.taxProfiles.store orelse return;
            const generated = store.generateOpaqueId() catch return;
            const anchor = profile_registration.ObligationAnchorId.parse(
                &generated,
            ) catch return;
            model.regPage.addRegistrationObligation(
                anchor,
                input,
                period,
            ) catch {
                model.regEditorError.set(
                    "This obligation conflicts with another active registration.",
                );
                return;
            };
        },
        .edit_obligation => {
            const index = model.regSelectedIndex orelse return;
            const rows = model.regPage.registrationObligations();
            if (index >= rows.len) return;
            const input = regTypedObligation(model) orelse {
                model.regEditorError.set(
                    "Enter the other withholding registration type.",
                );
                return;
            };
            model.regPage.updateRegistrationObligation(
                rows[index].anchor_id,
                input,
                period,
            ) catch {
                model.regEditorError.set(
                    "This obligation conflicts with another active registration.",
                );
                return;
            };
        },
        .none => return,
    }
    resetRegistrationDialog(model);
}

fn saveRegistrationPage(model: *Model) void {
    const intent = model.regPage.beginSave() catch return;
    const allocator = model.taxProfiles.allocator orelse {
        model.regPage.saveFailed() catch {};
        return;
    };
    const store = model.taxProfiles.store orelse {
        model.regPage.saveFailed() catch {};
        return;
    };
    const new_sequence = profile_persistence.saveRegistrationIntent(
        store,
        allocator,
        &intent,
    ) catch |err| {
        if (err == profile_store.Error.RegistrationStreamConflict) {
            const current = store.registrationStreamSequence(
                intent.profile_id.asSlice(),
            ) catch {
                model.regPage.saveFailed() catch {};
                return;
            };
            model.regPage.noteConflict(current) catch {};
        } else {
            model.regPage.saveFailed() catch {};
        }
        return;
    };
    model.regPage.saveSucceeded(new_sequence) catch return;
    loadRegistrationPage(model);
    refreshProfileFormLaunchAssessments(model);
    returnToTaxFormProfileAfterRegistration(model);
}

fn returnToTaxFormProfileAfterRegistration(model: *Model) void {
    if (!model.taxFormProfileRegistrationReturnPending) return;
    model.taxFormProfileRegistrationReturnPending = false;
    const picker_field = model.taxFormProfilePickerField;
    loadTaxFormProfileChoices(model);
    model.taxFormProfilePickerField = picker_field;
    refreshTaxFormProfileCardStates(model);
    refreshOpenedTaxFormProfileBindingReadiness(model);
    refreshOpenedRuntimeComposedSnapshot(model);
    navigate(model, .tax_form_profile);
}

fn openProfileSetupYear(model: *Model, year: i32) void {
    if (!model.taxProfiles.openYearWorkspace(year)) return;
    model.libraryFilter.filter_picker_visible = false;
    model.libraryFilter.period_picker_visible = false;
    model.libraryFilter.info_index = null;
    model.libraryFilter.manage_cadence_mask = 0b1111;
    model.libraryFilter.category_mask = 0;
    resetProfileFormsPage(model);
    refreshProfileFormLaunchAssessments(model);
    loadRegistrationPage(model);
}

fn openTaxFormProfileRegistrationRepair(model: *Model) void {
    if (!model.taxFormProfileChoicesRegistrationRepairVisible() and
        !model.taxFormProfileRegistrationRepairVisible()) return;
    const identity = model.taxFormProfilePage.viewedIdentity() orelse return;
    openProfileSetupYear(model, @intCast(identity.tax_year));
    if (model.taxProfiles.workspaceYear() != @as(i32, identity.tax_year) or
        !model.regLoaded)
    {
        return;
    }
    model.taxFormProfileRegistrationReturnPending = true;
    model.profileSetupSection = .tax_forms;
    model.dashboardSection = .profile_settings;
    navigate(model, .taxpayer_dashboard);
    model.regPage.beginEdit() catch {
        model.taxFormProfileRegistrationReturnPending = false;
    };
}

/// Opens the yearly setup workspace when its section becomes visible, so the
/// user always lands on a concrete year instead of an empty surface with no
/// visible next step.
fn ensureYearWorkspaceOpen(model: *Model) void {
    if (model.taxProfiles.editing_new) return;
    if (model.taxProfiles.selectedProfileId() == null) return;
    if (model.taxProfiles.managing_forms and
        model.taxProfiles.year_workspace != .open_failed) return;
    const maximum = model.taxProfiles.maximumSetupYear();
    const year = model.taxProfiles.workspaceYear() orelse maximum;
    openProfileSetupYear(model, if (year > maximum) maximum else year);
}

fn toggleLibraryCadence(model: *Model, bit: u8) void {
    model.libraryFilter.toggleCadence(bit, model.taxProfiles.managing_forms);
}

fn toggleLibraryMonth(model: *Model, month: u8) void {
    if (model.taxProfiles.managing_forms or month < 1 or month > 12) return;
    const bit = @as(u16, 1) << @intCast(month - 1);
    if (model.libraryFilter.month_mask & bit != 0) {
        const remaining = model.libraryFilter.month_mask & ~bit;
        model.libraryFilter.month_mask = remaining;
        if (remaining == 0 and
            model.libraryFilter.browse_cadence_mask != 0b0001)
        {
            model.libraryFilter.browse_cadence_mask &= ~@as(u8, 0b0001);
        }
    } else {
        model.libraryFilter.month_mask |= bit;
        if (model.libraryFilter.browse_cadence_mask == 0b1111) {
            model.libraryFilter.browse_cadence_mask = 0b0001;
        } else {
            model.libraryFilter.browse_cadence_mask |= 0b0001;
        }
    }
    resetProfileFormsPage(model);
}

fn toggleLibraryQuarter(model: *Model, quarter: u8) void {
    if (model.taxProfiles.managing_forms or quarter < 1 or quarter > 4) return;
    const bit = @as(u8, 1) << @intCast(quarter - 1);
    if (model.libraryFilter.quarter_mask & bit != 0) {
        const remaining = model.libraryFilter.quarter_mask & ~bit;
        model.libraryFilter.quarter_mask = remaining;
        if (remaining == 0 and
            model.libraryFilter.browse_cadence_mask != 0b0010)
        {
            model.libraryFilter.browse_cadence_mask &= ~@as(u8, 0b0010);
        }
    } else {
        model.libraryFilter.quarter_mask |= bit;
        if (model.libraryFilter.browse_cadence_mask == 0b1111) {
            model.libraryFilter.browse_cadence_mask = 0b0010;
        } else {
            model.libraryFilter.browse_cadence_mask |= 0b0010;
        }
    }
    resetProfileFormsPage(model);
}

/// Toggles the category at a row index. The index comes from the rendered
/// row list, so it is validated against the enum rather than cast blindly.
fn toggleLibraryCategoryAt(model: *Model, index: usize) void {
    const categories = std.meta.tags(form_catalog.TaxCategory);
    if (index >= categories.len) return;
    toggleLibraryCategory(model, categories[index]);
}

fn toggleLibraryCategory(
    model: *Model,
    category: form_catalog.TaxCategory,
) void {
    if (!model.taxProfiles.managing_forms) return;
    const bit = @as(u16, 1) << @intCast(@intFromEnum(category));
    model.libraryFilter.category_mask ^= bit;
}

fn toggleLibraryOnDemandForm(model: *Model, index: usize) void {
    if (model.taxProfiles.managing_forms or
        index >= form_catalog.registry_count) return;
    const definition = &form_catalog.forms[index];
    if (definition.cadence != .on_demand) return;
    const availability_year = profileBrowseAvailabilityYear(model);
    if (model.profileFormAvailabilityYear != availability_year or
        !model.profileFormAnyPeriodActive[index]) return;
    model.libraryFilter.on_demand_mask ^=
        @as(u64, 1) << @intCast(index);
    if (model.libraryFilter.on_demand_mask != 0) {
        if (model.libraryFilter.browse_cadence_mask == 0b1111) {
            model.libraryFilter.browse_cadence_mask = 0b1000;
        } else {
            model.libraryFilter.browse_cadence_mask |= 0b1000;
        }
    }
    resetProfileFormsPage(model);
}

fn resetProfileFormsBrowseFilters(model: *Model) void {
    model.libraryFilter.resetBrowseFilters();
}

fn setLibraryPeriodFilter(model: *Model, filter: LibraryPeriodFilter) void {
    model.libraryFilter.period_filter = filter;
    model.libraryFilter.period_picker_visible = false;
    switch (filter) {
        .all => resetProfileFormsBrowseFilters(model),
        .monthly => |month| {
            model.libraryFilter.month_mask =
                @as(u16, 1) << @intCast(month - 1);
            model.libraryFilter.quarter_mask = 0;
            model.libraryFilter.on_demand_mask = 0;
            model.libraryFilter.browse_cadence_mask = 0b0001;
        },
        .quarterly => |quarter| {
            model.libraryFilter.month_mask = 0;
            model.libraryFilter.quarter_mask =
                @as(u8, 1) << @intCast(quarter - 1);
            model.libraryFilter.browse_cadence_mask = 0b0010;
            model.libraryFilter.on_demand_mask = 0;
        },
        .annual => {
            model.libraryFilter.month_mask = 0;
            model.libraryFilter.quarter_mask = 0;
            model.libraryFilter.on_demand_mask = 0;
            model.libraryFilter.browse_cadence_mask = 0b0100;
        },
        .on_demand => {
            model.libraryFilter.month_mask = 0;
            model.libraryFilter.quarter_mask = 0;
            model.libraryFilter.on_demand_mask = 0;
            model.libraryFilter.browse_cadence_mask = 0b1000;
        },
    }
    refreshProfileFormLaunchAssessments(model);
}

fn libraryPeriodFilterAllowed(
    definition: *const form_catalog.FormDefinition,
    filter: LibraryPeriodFilter,
) bool {
    const slot: ?u8 = switch (filter) {
        .monthly => |month| month,
        .quarterly => |quarter| quarter,
        else => null,
    };
    if (slot) |value| {
        if (definition.min_period) |minimum| if (value < minimum) return false;
        if (definition.max_period) |maximum| if (value > maximum) return false;
    }
    return filter.matches(definition.cadence);
}

fn libraryPeriodForSlot(
    definition: *const form_catalog.FormDefinition,
    year: u16,
    slot: usize,
) ?form_period.FilingPeriod {
    return switch (definition.cadence) {
        .monthly => blk: {
            const minimum = definition.min_period orelse 1;
            const maximum = definition.max_period orelse 12;
            const value: usize = @as(usize, minimum) + slot;
            if (value > maximum or value > 12) break :blk null;
            break :blk .{ .monthly = .{
                .tax_year = year,
                .month = @intCast(value),
            } };
        },
        .quarterly => blk: {
            const minimum = definition.min_period orelse 1;
            const maximum = definition.max_period orelse 4;
            const value: usize = @as(usize, minimum) + slot;
            if (value > maximum or value > 4) break :blk null;
            break :blk .{ .quarterly = .{
                .tax_year = year,
                .quarter = @intCast(value),
            } };
        },
        .annual => if (slot == 0)
            .{ .annual = .{ .tax_year = year } }
        else
            null,
        .on_demand => if (slot == 0)
            .{ .on_demand = .{ .tax_year = year, .occurrence = 1 } }
        else
            null,
    };
}

fn periodLaunchNote(
    assessment: form_ui.LaunchAssessment,
    assessment_ready: bool,
) []const u8 {
    if (!assessment_ready) return "";
    return switch (assessment.status) {
        .ready_new, .ready_resume => "",
        .needs_profile => ", complete profile before opening",
        .needs_activity_selection => ", choose an activity before opening",
        .profile_not_eligible => ", profile is not eligible",
        .unavailable => ", unavailable",
    };
}

fn appendLibraryPeriodCell(
    row: *TaxFormLibraryRow,
    drafts: []const profile_ui.DraftSummaryRow,
    drafts_truncated: bool,
    form_code: []const u8,
    period: form_period.FilingPeriod,
    month_mask: u16,
    quarter_mask: u8,
    assessment: form_ui.LaunchAssessment,
    assessment_ready: bool,
    period_active: bool,
    availability_ready: bool,
    label_override: ?[]const u8,
    force_new_status: bool,
    arena: std.mem.Allocator,
) void {
    if (row.period_cell_count >= row.period_cells.len) return;
    const label = label_override orelse switch (period) {
        .monthly => |value| shortMonthName(value.month),
        .quarterly => |value| std.fmt.allocPrint(
            arena,
            "Q{d}",
            .{value.quarter},
        ) catch "Quarter",
        .annual => "File annual return",
        .on_demand => "Start new return",
    };
    const persisted_status = if (row.definition.status == .calendar_only)
        LibraryDraftStatus{ .label = "Deadline only", .tone = "outline" }
    else if (force_new_status)
        LibraryDraftStatus{ .label = "New", .tone = "outline" }
    else
        libraryDraftStatus(
            drafts,
            drafts_truncated,
            form_code,
            period,
            arena,
        );
    // Launch readiness is a separate concern from filing lifecycle. A form
    // can be New while profile data is incomplete; that must not leak as a
    // fake filing status such as "Profile" into the period tile.
    const status = if (availability_ready and !period_active)
        LibraryDraftStatus{ .label = "Inactive", .tone = "outline" }
    else
        persisted_status;
    const filtered_out = switch (period) {
        .monthly => |value| month_mask != 0 and
            month_mask & (@as(u16, 1) << @intCast(value.month - 1)) == 0,
        .quarterly => |value| quarter_mask != 0 and
            quarter_mask & (@as(u8, 1) << @intCast(value.quarter - 1)) == 0,
        .annual, .on_demand => false,
    };
    const selected = !filtered_out and switch (period) {
        .monthly => month_mask != 0,
        .quarterly => quarter_mask != 0,
        .annual, .on_demand => false,
    };
    const action_id = row.id * 16 + row.period_cell_count;
    const action_label = std.fmt.allocPrint(
        arena,
        "BIR Form {s}, {s}, tax year {d}, {s}{s}{s}",
        .{
            form_code,
            label,
            period.taxYear(),
            status.label,
            periodLaunchNote(assessment, assessment_ready),
            if (row.definition.status == .calendar_only)
                ", calendar only"
            else
                ", open exact filing period",
        },
    ) catch "Open filing period";
    const cell: TaxFormLibraryPeriodCell = .{
        .id = action_id,
        .action_id = action_id,
        .label = label,
        .status = status.label,
        .visual_status = compactPeriodStatus(status.label),
        .status_color = periodStatusColor(compactPeriodStatus(status.label)),
        .tile_width = switch (period) {
            .annual, .on_demand => 280,
            .monthly, .quarterly => 64,
        },
        .tone = status.tone,
        .selected = selected,
        .available = true,
        .visible = !filtered_out,
        .filtered_out = filtered_out,
        .actionable = row.definition.status == .static_layout and
            period_active and
            availability_ready and
            assessment_ready and
            launchActionEnabled(assessment.status),
        .calendar_only = row.definition.status == .calendar_only,
        .accessible_label = action_label,
    };
    row.setPeriodCell(row.period_cell_count, cell);
    row.period_cell_count += 1;
}

fn populateLibraryPeriodCells(
    row: *TaxFormLibraryRow,
    drafts: []const profile_ui.DraftSummaryRow,
    drafts_truncated: bool,
    form_code: []const u8,
    tax_year: i32,
    arena: std.mem.Allocator,
    month_mask: u16,
    quarter_mask: u8,
    assessments: [12]form_ui.LaunchAssessment,
    assessments_ready: [12]bool,
    availability: [12]bool,
    availability_ready: [12]bool,
) void {
    if (tax_year < 1 or tax_year > 9999) return;
    const year: u16 = @intCast(tax_year);
    if (row.definition.cadence == .on_demand) {
        const new_period = newOnDemandAssessmentPeriod(
            drafts,
            form_code,
            year,
        ) orelse form_period.FilingPeriod{ .on_demand = .{
            .tax_year = year,
            .occurrence = 999,
        } };
        appendLibraryPeriodCell(
            row,
            drafts,
            drafts_truncated,
            form_code,
            new_period,
            month_mask,
            quarter_mask,
            assessments[0],
            assessments_ready[0],
            availability[0],
            availability_ready[0],
            "Start new return",
            true,
            arena,
        );
        for (1..row.period_cells.len) |slot| {
            const period = onDemandDraftPeriodForSlot(
                drafts,
                form_code,
                year,
                slot,
            ) orelse break;
            const occurrence = switch (period) {
                .on_demand => |value| value.occurrence,
                else => unreachable,
            };
            const label = std.fmt.allocPrint(
                arena,
                "Saved return O{d:0>3}",
                .{occurrence},
            ) catch "Saved return";
            appendLibraryPeriodCell(
                row,
                drafts,
                drafts_truncated,
                form_code,
                period,
                month_mask,
                quarter_mask,
                assessments[slot],
                assessments_ready[slot],
                availability[slot],
                availability_ready[slot],
                label,
                false,
                arena,
            );
        }
    } else {
        for (0..row.period_cells.len) |slot| {
            const period = libraryPeriodForSlot(row.definition, year, slot) orelse
                break;
            appendLibraryPeriodCell(
                row,
                drafts,
                drafts_truncated,
                form_code,
                period,
                month_mask,
                quarter_mask,
                assessments[slot],
                assessments_ready[slot],
                availability[slot],
                availability_ready[slot],
                null,
                false,
                arena,
            );
        }
    }
    const summary_buffer = arena.alloc(u8, 768) catch return;
    var summary_len: usize = 0;
    for (row.periodCells(), 0..) |*cell, index| {
        const separator = if (index == 0) "" else "  ·  ";
        const written = std.fmt.bufPrint(
            summary_buffer[summary_len..],
            "{s}{s} {s}",
            .{ separator, cell.label, cell.status },
        ) catch break;
        summary_len += written.len;
    }
    row.period_summary = summary_buffer[0..summary_len];
}

fn formatNewsTimestamp(
    allocator: std.mem.Allocator,
    timestamp: i64,
) []const u8 {
    const date = utcCalendarTimeFromUnixSeconds(timestamp) orelse
        return "Unknown date";
    return std.fmt.allocPrint(
        allocator,
        "{s} {d}, {d}",
        .{ fullMonthName(date.month), date.day, date.year },
    ) catch "Unknown date";
}

fn compactNewsText(
    allocator: std.mem.Allocator,
    value: []const u8,
    maximum_bytes: usize,
) []const u8 {
    const ellipsis = "…";
    if (value.len <= maximum_bytes) return value;
    if (maximum_bytes < ellipsis.len) return "";
    if (maximum_bytes == ellipsis.len) return ellipsis;

    var end = maximum_bytes - ellipsis.len;
    while (end > 0 and (value[end] & 0b1100_0000) == 0b1000_0000) {
        end -= 1;
    }
    return std.fmt.allocPrint(
        allocator,
        "{s}{s}",
        .{ value[0..end], ellipsis },
    ) catch value[0..end];
}

fn profileDeadlineFilingPeriod(
    deadline: *const calendar_ui.DeadlineRow,
) ?form_period.FilingPeriod {
    const taxable_year = deadline.period.taxableYear() orelse return null;
    if (taxable_year < 1 or taxable_year > 9999) return null;
    const year: u16 = @intCast(taxable_year);
    const filing: form_period.FilingPeriod = switch (deadline.period) {
        .monthly => |period| .{ .monthly = .{
            .tax_year = year,
            .month = period.month,
        } },
        .quarterly => |period| .{ .quarterly = .{
            .tax_year = year,
            .quarter = period.quarter,
        } },
        .annual => .{ .annual = .{ .tax_year = year } },
        // Calendar event rules do not currently expose the occurrence needed
        // for a stable on-demand filing identity. Fail closed instead of
        // opening an arbitrary occurrence.
        .event_based => return null,
    };
    filing.validate() catch return null;
    return filing;
}

fn draftMatchesDeadline(
    draft: *const profile_ui.DraftSummaryRow,
    deadline: *const calendar_ui.DeadlineRow,
) bool {
    if (!formCodesEquivalent(draft.formCode(), deadline.form_code)) {
        return false;
    }
    const expected = profileDeadlineFilingPeriod(deadline) orelse return false;
    const cadence: form_catalog.FilingCadence = switch (deadline.period) {
        .monthly => .monthly,
        .quarterly => .quarterly,
        .annual => .annual,
        .event_based => return false,
    };
    const actual = form_period.FilingPeriod.parseKey(
        cadence,
        draft.periodKey(),
    ) catch return false;
    return actual.eql(expected);
}

pub const Msg = union(enum) {
    show_global_dashboard,
    show_taxpayer_dashboard,
    show_profile_setup,
    new_taxpayer_profile,
    show_import_data,
    show_background_tasks,
    show_tax_calendar,
    show_settings,
    show_screen_gallery,
    show_form_0605,
    show_form_0619_e,
    show_form_0619_f,
    show_form_1601_c,
    show_form_1701,
    show_form_1701q,
    show_form_1702_rt,
    show_form_1702_mx,
    show_form_2550q,
    show_form_2551q,
    select_form_activity: usize,
    select_form_spouse: usize,
    clear_form_spouse,
    save_recurring_form_draft,
    exact_1701q_open_original,
    exact_1701q_open_amended,
    exact_1701q_select_control: usize,
    exact_1701q_toggle_selected_reveal,
    exact_1701q_editor_input: canvas.TextInputEvent,
    exact_1701q_commit_selected,
    exact_1701q_toggle_selected_radio,
    exact_1701q_calculate,
    exact_1701q_validate_save,
    exact_1701q_generate_editable_candidate,
    exact_1701q_validate_full,
    exact_1701q_generate_final_candidate,
    exact_1701q_toggle_generated_reveal,
    exact_1701q_discard_workspace,
    income_tax_quarter_q1,
    income_tax_quarter_q2,
    income_tax_quarter_q3,
    income_tax_sheets_attached_input: canvas.TextInputEvent,
    income_tax_election_graduated,
    income_tax_election_eight_percent,
    income_tax_graduated_sales_input: canvas.TextInputEvent,
    income_tax_graduated_cost_input: canvas.TextInputEvent,
    income_tax_graduated_deductions_input: canvas.TextInputEvent,
    income_tax_graduated_taxable_income_input: canvas.TextInputEvent,
    income_tax_graduated_tax_due_input: canvas.TextInputEvent,
    income_tax_eight_gross_sales_input: canvas.TextInputEvent,
    income_tax_eight_non_operating_input: canvas.TextInputEvent,
    income_tax_eight_tax_due_input: canvas.TextInputEvent,
    income_tax_prior_payments_input: canvas.TextInputEvent,
    income_tax_withheld_2307_input: canvas.TextInputEvent,
    income_tax_other_credits_input: canvas.TextInputEvent,
    income_tax_payable_input: canvas.TextInputEvent,
    income_tax_surcharge_input: canvas.TextInputEvent,
    income_tax_interest_input: canvas.TextInputEvent,
    income_tax_compromise_input: canvas.TextInputEvent,
    income_tax_add_payment,
    income_tax_select_payment: usize,
    income_tax_remove_selected_payment,
    income_tax_payment_method_cash,
    income_tax_payment_method_check,
    income_tax_payment_method_tax_debit_memo,
    income_tax_payment_method_other,
    income_tax_payment_bank_input: canvas.TextInputEvent,
    income_tax_payment_reference_input: canvas.TextInputEvent,
    income_tax_payment_amount_input: canvas.TextInputEvent,
    percentage_tax_period_calendar,
    percentage_tax_period_fiscal,
    percentage_tax_year_end_month_input: canvas.TextInputEvent,
    percentage_tax_sheets_attached_input: canvas.TextInputEvent,
    percentage_tax_relief_none,
    percentage_tax_relief_specified,
    percentage_tax_relief_reference_input: canvas.TextInputEvent,
    percentage_tax_election_graduated,
    percentage_tax_election_eight_percent,
    percentage_tax_line_1_atc_input: canvas.TextInputEvent,
    percentage_tax_line_1_base_input: canvas.TextInputEvent,
    percentage_tax_line_1_rate_input: canvas.TextInputEvent,
    percentage_tax_line_2_atc_input: canvas.TextInputEvent,
    percentage_tax_line_2_base_input: canvas.TextInputEvent,
    percentage_tax_line_2_rate_input: canvas.TextInputEvent,
    percentage_tax_creditable_withheld_input: canvas.TextInputEvent,
    percentage_tax_paid_previous_input: canvas.TextInputEvent,
    percentage_tax_other_credit_input: canvas.TextInputEvent,
    percentage_tax_surcharge_input: canvas.TextInputEvent,
    percentage_tax_interest_input: canvas.TextInputEvent,
    percentage_tax_compromise_input: canvas.TextInputEvent,
    percentage_tax_disposition_not_applicable,
    percentage_tax_disposition_refund,
    percentage_tax_disposition_tax_credit,
    percentage_tax_disposition_carry_over,
    show_aux_lock_screen,
    show_aux_profile_auth_overlay,
    show_aux_admin_auth_overlay,
    show_aux_command_palette,
    show_aux_html_print_preview,
    show_aux_email_confirmation,
    show_aux_background_task_debug_log,
    select_taxpayer: usize,
    show_dashboard_calendar,
    show_dashboard_forms,
    show_dashboard_profile_settings,
    show_profile_tax,
    edit_tax_profile,
    show_profile_tax_forms,
    reg_retry,
    reg_edit,
    reg_cancel,
    reg_save,
    reg_add_act,
    reg_edit_act: usize,
    reg_remove_act: usize,
    reg_add_ob,
    reg_edit_ob: usize,
    reg_remove_ob: usize,
    reg_dialog_cancel,
    reg_dialog_save,
    reg_line_input: canvas.TextInputEvent,
    reg_atc_input: canvas.TextInputEvent,
    reg_from_input: canvas.TextInputEvent,
    reg_until_input: canvas.TextInputEvent,
    reg_other_input: canvas.TextInputEvent,
    reg_kind_income_tax,
    reg_kind_vat,
    reg_kind_percentage_tax,
    reg_kind_wh_comp,
    reg_kind_wh_expanded,
    reg_kind_wh_final,
    reg_kind_wh_other,
    reg_conflict_accept,
    reg_conflict_reload,
    profile_cor_upload,
    profile_cor_begin_review,
    profile_cor_cancel_review,
    profile_cor_tin_input: canvas.TextInputEvent,
    // on-input requires a bare TextInputEvent payload, so each reviewed
    // detail needs its own tag rather than one carrying an index.
    profile_cor_rdo_input: canvas.TextInputEvent,
    profile_cor_name_input: canvas.TextInputEvent,
    profile_cor_address_input: canvas.TextInputEvent,
    profile_cor_zip_input: canvas.TextInputEvent,
    profile_cor_tax_type_input: canvas.TextInputEvent,
    profile_cor_toggle_rdo,
    profile_cor_toggle_name,
    profile_cor_toggle_address,
    profile_cor_toggle_zip,
    profile_cor_toggle_tax_type,
    profile_cor_toggle_apply_forms,
    profile_cor_apply,
    form_filing_address_input: canvas.TextInputEvent,
    form_filing_zip_input: canvas.TextInputEvent,
    form_filing_contact_input: canvas.TextInputEvent,
    form_filing_email_input: canvas.TextInputEvent,
    form_filing_use_profile_contacts,
    show_profile_email,
    profile_subject_individual,
    profile_subject_corporation,
    profile_subject_partnership,
    profile_subject_cooperative,
    profile_subject_estate,
    profile_subject_trust,
    profile_subject_other_legal,
    profile_classification_pure_compensation,
    profile_classification_self_employed,
    profile_classification_mixed_income,
    toggle_profile_subject_picker,
    close_profile_subject_picker,
    toggle_profile_classification_picker,
    close_profile_classification_picker,
    toggle_profile_eopt_picker,
    close_profile_eopt_picker,
    profile_eopt_micro,
    profile_eopt_small,
    profile_eopt_medium,
    profile_eopt_large,
    profile_source_manual,
    profile_source_imported,
    profile_source_migrated,
    profile_gwa_unset,
    profile_gwa_no,
    profile_gwa_yes,
    profile_tin_segment_one_input: canvas.TextInputEvent,
    profile_tin_segment_two_input: canvas.TextInputEvent,
    profile_tin_segment_three_input: canvas.TextInputEvent,
    profile_tin_segment_branch_input: canvas.TextInputEvent,
    profile_rdo_toggle_picker,
    profile_rdo_close_picker,
    profile_rdo_query_input: canvas.TextInputEvent,
    profile_rdo_select: usize,
    profile_name_input: canvas.TextInputEvent,
    profile_trade_name_input: canvas.TextInputEvent,
    profile_address_input: canvas.TextInputEvent,
    profile_zip_input: canvas.TextInputEvent,
    profile_phone_input: canvas.TextInputEvent,
    profile_email_input: canvas.TextInputEvent,
    profile_birth_date_input: canvas.TextInputEvent,
    profile_citizenship_input: canvas.TextInputEvent,
    profile_foreign_tax_number_input: canvas.TextInputEvent,
    profile_primary_line_of_business_input: canvas.TextInputEvent,
    profile_business_line_input: canvas.TextInputEvent,
    profile_atc_input: canvas.TextInputEvent,
    profile_tax_type_input: canvas.TextInputEvent,
    profile_special_rate_basis_input: canvas.TextInputEvent,
    profile_effective_from_input: canvas.TextInputEvent,
    profile_effective_until_input: canvas.TextInputEvent,
    profile_source_reference_input: canvas.TextInputEvent,
    profile_setup_toggle_year_picker,
    profile_setup_close_year_picker,
    profile_setup_year_query: canvas.TextInputEvent,
    profile_setup_select_year: i32,
    profile_setup_retry_year,
    profile_setup_draft_empty,
    profile_setup_draft_seed: i32,
    profile_setup_toggle_source_picker,
    profile_setup_close_source_picker,
    profile_setup_save,
    profile_setup_conflict_review,
    profile_setup_conflict_discard,
    profile_setup_confirm_year_switch,
    profile_setup_cancel_year_switch,
    profile_setup_toggle_years_disclosure,
    profile_setup_apply_whole_year,
    profile_setup_apply_from_date,
    profile_setup_change_date_input: canvas.TextInputEvent,
    profile_setup_toggle_changes_disclosure,
    profile_record_change,
    profile_fix_mistake,
    profile_toggle_advanced,
    add_branch_profile,
    profile_forms_search_input: canvas.TextInputEvent,
    profile_forms_manage,
    toggle_profile_form: usize,
    profile_forms_select_all,
    profile_forms_clear_all,
    profile_forms_cancel,
    profile_forms_reset_legacy,
    profile_forms_toggle_filter_active,
    profile_forms_toggle_filter_inactive,
    profile_forms_toggle_filter_editor,
    profile_forms_toggle_filter_calendar_only,
    profile_forms_reset_filters,
    profile_forms_toggle_filter_picker,
    profile_forms_close_filter_picker,
    profile_forms_show_info: usize,
    profile_forms_close_info,
    profile_forms_toggle_cadence_monthly,
    profile_forms_toggle_cadence_quarterly,
    profile_forms_toggle_cadence_annual,
    profile_forms_toggle_cadence_on_demand,
    profile_forms_toggle_month: u8,
    profile_forms_toggle_quarter_1,
    profile_forms_toggle_quarter_2,
    profile_forms_toggle_quarter_3,
    profile_forms_toggle_quarter_4,
    profile_forms_toggle_category: usize,
    profile_forms_toggle_on_demand_form: usize,
    profile_forms_show_previous,
    profile_forms_show_more,
    profile_forms_toggle_period_picker,
    profile_forms_close_period_picker,
    profile_forms_period_all,
    profile_forms_period_january,
    profile_forms_period_february,
    profile_forms_period_march,
    profile_forms_period_april,
    profile_forms_period_may,
    profile_forms_period_june,
    profile_forms_period_july,
    profile_forms_period_august,
    profile_forms_period_september,
    profile_forms_period_october,
    profile_forms_period_november,
    profile_forms_period_december,
    profile_forms_period_quarter_one,
    profile_forms_period_quarter_two,
    profile_forms_period_quarter_three,
    profile_forms_period_quarter_four,
    profile_forms_period_annual,
    profile_forms_period_on_demand,
    open_library_form: usize,
    open_library_period: usize,
    open_tax_form_profile: usize,
    close_tax_form_profile,
    tax_form_profile_previous_segment,
    tax_form_profile_next_segment,
    tax_form_profile_keep_editing,
    tax_form_profile_discard_navigation,
    edit_tax_form_profile,
    cancel_tax_form_profile,
    save_tax_form_profile,
    tax_form_profile_toggle_picker: usize,
    tax_form_profile_select_choice: usize,
    tax_form_profile_clear_value: usize,
    tax_form_profile_close_picker,
    tax_form_profile_acknowledge_review,
    tax_form_profile_copy_prior_year,
    tax_form_profile_reuse_after_reactivation,
    tax_form_profile_keep_draft_after_conflict,
    tax_form_profile_reload_after_conflict,
    tax_form_profile_edit_tax_profile,
    tax_form_profile_edit_registration,
    taxpayer_year_edit,
    taxpayer_year_cancel,
    taxpayer_year_save,
    taxpayer_year_rate_graduated,
    taxpayer_year_rate_eight_percent,
    taxpayer_year_deduction_itemized,
    taxpayer_year_deduction_osd,
    taxpayer_year_acknowledge_review,
    taxpayer_year_copy_prior_year,
    taxpayer_year_keep_draft_after_conflict,
    taxpayer_year_reload_after_conflict,
    save_profile,
    cancel_profile_edit,
    profile_keep_editing,
    profile_discard_navigation,
    dismiss_profile_notice,
    profile_notice_timeout: native_sdk.EffectTimer,
    calendar_today_refresh: native_sdk.EffectTimer,
    show_calendar_rules,
    show_calendar_overrides,
    calendar_previous_month,
    calendar_next_month,
    profile_calendar_toggle_year_picker,
    profile_calendar_close_year_picker,
    profile_calendar_year_query: canvas.TextInputEvent,
    profile_calendar_select_year: i32,
    global_calendar_previous_month,
    global_calendar_next_month,
    global_calendar_select_day: u8,
    profile_calendar_select_day: u8,
    profile_deadline_toggle_actions: u64,
    profile_deadline_close_actions,
    profile_deadline_run_action: u64,
    profile_deadline_show_adjustment: u64,
    profile_deadline_close_dialog,
    calendar_refresh,
    refresh_important_news,
    important_news_response: native_sdk.EffectResponse,
    dismiss_important_news_error,
    profile_calendar_export,
    profile_calendar_export_written: native_sdk.EffectFileResult,
    profile_calendar_export_opened: native_sdk.EffectExit,
    dismiss_profile_calendar_export_notice,
    profile_calendar_export_notice_timeout: native_sdk.EffectTimer,
    calendar_override_title_input: canvas.TextInputEvent,
    calendar_override_forms_input: canvas.TextInputEvent,
    calendar_override_original_input: canvas.TextInputEvent,
    calendar_override_adjusted_input: canvas.TextInputEvent,
    calendar_override_source_input: canvas.TextInputEvent,
    calendar_override_regions_input: canvas.TextInputEvent,
    calendar_override_taxpayer_types_input: canvas.TextInputEvent,
    calendar_override_effective_from_input: canvas.TextInputEvent,
    calendar_override_effective_until_input: canvas.TextInputEvent,
    calendar_override_expires_at_input: canvas.TextInputEvent,
    calendar_save_override,
    calendar_cancel_override,
    calendar_edit_override: i64,
    calendar_delete_override: i64,
    calendar_non_working_date_input: canvas.TextInputEvent,
    calendar_non_working_name_input: canvas.TextInputEvent,
    calendar_non_working_kind_input: canvas.TextInputEvent,
    calendar_non_working_source_input: canvas.TextInputEvent,
    calendar_non_working_regions_input: canvas.TextInputEvent,
    calendar_save_non_working_day,
    calendar_cancel_non_working_day,
    calendar_edit_non_working_day: i64,
    calendar_delete_non_working_day: i64,
    show_background_jobs,
    show_background_logs,
    multi_select_open,
    multi_select_close,
    multi_select_query_changed: canvas.TextInputEvent,
    multi_select_toggle_option: usize,
    multi_select_select_all_filtered,
    multi_select_clear_all,
    profile_calendar_forms_open,
    profile_calendar_forms_close,
    profile_calendar_forms_query_changed: canvas.TextInputEvent,
    profile_calendar_forms_toggle_option: usize,
    profile_calendar_forms_select_all_filtered,
    profile_calendar_forms_clear_all,
    go_back,
    toggle_theme,
    set_theme_system,
    set_theme_light,
    set_theme_dark,
    expand_sidebar,
    collapse_sidebar,
    hide_sidebar,
    open_sidebar_overlay,
    close_sidebar_overlay,
    toggle_navigation,
    sidebar_profile_search_changed: canvas.TextInputEvent,
    viewport_class_changed: ViewportClass,
    viewport_width_changed: f32,
    appearance_changed: native_sdk.Appearance,

    // The host sends viewport/appearance changes. `hide_sidebar` remains a
    // model-level transition for tests and constrained-shell handoff, while
    // the visible desktop control now mirrors GPUI's single chevron toggle.
    pub const view_unbound = .{
        "appearance_changed",
        "viewport_class_changed",
        "viewport_width_changed",
        "hide_sidebar",
        "profile_calendar_export_written",
        "profile_calendar_export_opened",
        "profile_calendar_export_notice_timeout",
        "profile_notice_timeout",
        "calendar_today_refresh",
        "important_news_response",

        // Legacy single-period/card-level library actions remain available
        // to focused compatibility tests, but the Native UI dispatches only
        // grouped filter toggles and exact `open_library_period` tile IDs.
        "profile_forms_toggle_period_picker",
        "profile_forms_close_period_picker",
        "profile_forms_period_all",
        "profile_forms_period_january",
        "profile_forms_period_february",
        "profile_forms_period_march",
        "profile_forms_period_april",
        "profile_forms_period_may",
        "profile_forms_period_june",
        "profile_forms_period_july",
        "profile_forms_period_august",
        "profile_forms_period_september",
        "profile_forms_period_october",
        "profile_forms_period_november",
        "profile_forms_period_december",
        "profile_forms_period_quarter_one",
        "profile_forms_period_quarter_two",
        "profile_forms_period_quarter_three",
        "profile_forms_period_quarter_four",
        "profile_forms_period_annual",
        "profile_forms_period_on_demand",
        "open_library_form",

        // The coarse 1701Q editor remains compiled only for compatibility
        // and focused Zig tests. The Native 1701Q page is exclusively bound
        // to the exact adapter and must not dispatch these legacy actions.
        "income_tax_quarter_q1",
        "income_tax_quarter_q2",
        "income_tax_quarter_q3",
        "income_tax_sheets_attached_input",
        "income_tax_election_graduated",
        "income_tax_election_eight_percent",
        "income_tax_graduated_sales_input",
        "income_tax_graduated_cost_input",
        "income_tax_graduated_deductions_input",
        "income_tax_graduated_taxable_income_input",
        "income_tax_graduated_tax_due_input",
        "income_tax_eight_gross_sales_input",
        "income_tax_eight_non_operating_input",
        "income_tax_eight_tax_due_input",
        "income_tax_prior_payments_input",
        "income_tax_withheld_2307_input",
        "income_tax_other_credits_input",
        "income_tax_payable_input",
        "income_tax_surcharge_input",
        "income_tax_interest_input",
        "income_tax_compromise_input",
        "income_tax_add_payment",
        "income_tax_select_payment",
        "income_tax_remove_selected_payment",
        "income_tax_payment_method_cash",
        "income_tax_payment_method_check",
        "income_tax_payment_method_tax_debit_memo",
        "income_tax_payment_method_other",
        "income_tax_payment_bank_input",
        "income_tax_payment_reference_input",
        "income_tax_payment_amount_input",
    };
};

pub fn update(model: *Model, msg: Msg) void {
    updateCore(model, msg, null);
}

fn updateWithEffects(model: *Model, msg: Msg, fx: *Effects) void {
    const notice_epoch = model.taxProfiles.noticeEpoch();
    const export_status = model.profileCalendarExportStatus;
    updateCore(model, msg, fx);
    if (model.taxProfiles.noticeEpoch() != notice_epoch) {
        syncProfileNoticeTimer(model, fx);
    }
    if (model.profileCalendarExportStatus != export_status) {
        model.profileCalendarExportNoticeEpoch +%= 1;
        syncProfileCalendarExportNoticeTimer(model, fx);
    }
}

fn updateCore(model: *Model, msg: Msg, fx: ?*Effects) void {
    switch (msg) {
        .show_global_dashboard => navigate(model, .global_dashboard),
        .show_taxpayer_dashboard => {
            refreshSelectedProfileFormSet(model);
            navigate(model, .taxpayer_dashboard);
        },
        .show_profile_setup => {
            model.profileSetupSection = .tax_profile;
            model.pendingProfileFormLaunch = null;
            model.taxProfiles.cancelEdit();
            syncProfileIdentityControls(model);
            _ = ensureCompleteProfileRegistrationLoaded(model);
            openProfileEditor(model);
        },
        .new_taxpayer_profile => {
            if (rejectExact1701QContextChange(model)) {
                reconcileExact1701QTaxpayerSelection(model);
                navigate(model, .form_1701q);
                return;
            }
            if (deferTaxpayerContextMutation(model, .new_taxpayer)) return;
            model.profileSetupSection = .tax_profile;
            model.profileCompletionTarget = null;
            model.profileCompletionFormIndex = null;
            model.pendingProfileFormLaunch = null;
            model.libraryFilter.filter_picker_visible = false;
            model.libraryFilter.period_picker_visible = false;
            model.libraryFilter.info_index = null;
            model.libraryFilter.period_filter = .all;
            resetProfileFormsBrowseFilters(model);
            model.taxProfiles.startNew();
            _ = initializeNewCompleteProfileRegistration(model);
            syncProfileIdentityControls(model);
            openProfileEditor(model);
        },
        .show_import_data => {
            bumpSidebarActionEpoch(model);
            navigate(model, .import_data);
        },
        .show_background_tasks => {
            bumpSidebarActionEpoch(model);
            navigate(model, .background_tasks);
        },
        .show_tax_calendar => {
            bumpSidebarActionEpoch(model);
            navigate(model, .tax_calendar);
        },
        .show_settings => {
            bumpSidebarActionEpoch(model);
            navigate(model, .settings);
        },
        .show_screen_gallery => {
            bumpSidebarActionEpoch(model);
            navigate(model, .screen_gallery);
        },
        .show_form_0605 => openProfileBoundForm(model, .form_0605, "0605"),
        .show_form_0619_e => openProfileBoundForm(model, .form_0619_e, "0619E"),
        .show_form_0619_f => openProfileBoundForm(model, .form_0619_f, "0619F"),
        .show_form_1601_c => openProfileBoundForm(model, .form_1601_c, "1601C"),
        .show_form_1701 => openProfileBoundForm(model, .form_1701, "1701"),
        .show_form_1701q => openProfileBoundForm(model, .form_1701q, "1701Q"),
        .show_form_1702_rt => openProfileBoundForm(model, .form_1702_rt, "1702RT"),
        .show_form_1702_mx => openProfileBoundForm(model, .form_1702_mx, "1702MX"),
        .show_form_2550q => openProfileBoundForm(model, .form_2550q, "2550Q"),
        .show_form_2551q => openProfileBoundForm(model, .form_2551q, "2551Q"),
        .select_form_activity => |slot| {
            if (rejectExact1701QContextChange(model)) return;
            const amended = model.exact1701Q.amended();
            const candidates = model.formProfiles.activityCandidates(.filer);
            if (slot < candidates.len) {
                model.formProfiles.setBusinessActivity(
                    .filer,
                    candidates[slot].id,
                ) catch |err| {
                    model.exact1701Q.reportContextBindingFailure(err);
                    return;
                };
                refreshExact1701QFromCurrentProjection(model, amended);
            }
        },
        .select_form_spouse => |slot| {
            if (rejectExact1701QContextChange(model)) return;
            const amended = model.exact1701Q.amended();
            const candidates = model.formProfiles.spouseCandidates();
            if (slot < candidates.len) {
                model.formProfiles.setSpouseProfile(
                    candidates[slot].profile_id,
                ) catch |err| {
                    model.exact1701Q.reportContextBindingFailure(err);
                    return;
                };
                refreshExact1701QFromCurrentProjection(model, amended);
            }
        },
        .clear_form_spouse => {
            if (rejectExact1701QContextChange(model)) return;
            const amended = model.exact1701Q.amended();
            model.formProfiles.clearSpouseProfile() catch |err| {
                model.exact1701Q.reportContextBindingFailure(err);
                return;
            };
            refreshExact1701QFromCurrentProjection(model, amended);
        },
        .save_recurring_form_draft => saveRecurringFormDraft(model),
        .exact_1701q_open_original => {
            openExact1701QFilingKind(model, false);
        },
        .exact_1701q_open_amended => {
            openExact1701QFilingKind(model, true);
        },
        .exact_1701q_select_control => |slot| {
            model.exact1701Q.selectControl(slot);
        },
        .exact_1701q_toggle_selected_reveal => {
            model.exact1701Q.toggleSelectedReveal();
        },
        .exact_1701q_editor_input => |edit| {
            model.exact1701Q.applyEditorInput(edit);
        },
        .exact_1701q_commit_selected => {
            model.exact1701Q.commitSelected();
        },
        .exact_1701q_toggle_selected_radio => {
            model.exact1701Q.toggleSelectedRadio();
        },
        .exact_1701q_calculate => model.exact1701Q.calculate(),
        .exact_1701q_validate_save => {
            model.exact1701Q.validateSave();
        },
        .exact_1701q_generate_editable_candidate => {
            model.exact1701Q.generateEditableCandidate();
            persistExact1701QCandidate(model);
        },
        .exact_1701q_validate_full => {
            model.exact1701Q.validateFull();
        },
        .exact_1701q_generate_final_candidate => {
            model.exact1701Q.generateFinalCandidate();
            persistExact1701QCandidate(model);
        },
        .exact_1701q_toggle_generated_reveal => {
            model.exact1701Q.toggleGeneratedReveal();
        },
        .exact_1701q_discard_workspace => {
            model.exact1701Q.discardWorkspace();
            model.exact1701QFrozenProvenance = null;
            model.exact1701QHistoricalProfile = null;
        },
        .income_tax_quarter_q1 => reopenIncomeTaxQuarter(model, 1),
        .income_tax_quarter_q2 => reopenIncomeTaxQuarter(model, 2),
        .income_tax_quarter_q3 => reopenIncomeTaxQuarter(model, 3),
        .income_tax_sheets_attached_input => |edit| {
            model.incomeTax.applyInput(.sheets_attached, edit);
        },
        .income_tax_election_graduated => {
            model.incomeTax.setElection(.graduated) catch {};
        },
        .income_tax_election_eight_percent => {
            model.incomeTax.setElection(.eight_percent) catch {};
        },
        .income_tax_graduated_sales_input => |edit| {
            model.incomeTax.applyInput(
                .graduated_sales_revenues_receipts,
                edit,
            );
        },
        .income_tax_graduated_cost_input => |edit| {
            model.incomeTax.applyInput(
                .graduated_cost_of_sales_or_services,
                edit,
            );
        },
        .income_tax_graduated_deductions_input => |edit| {
            model.incomeTax.applyInput(
                .graduated_allowable_deductions,
                edit,
            );
        },
        .income_tax_graduated_taxable_income_input => |edit| {
            model.incomeTax.applyInput(.graduated_taxable_income, edit);
        },
        .income_tax_graduated_tax_due_input => |edit| {
            model.incomeTax.applyInput(.graduated_income_tax_due, edit);
        },
        .income_tax_eight_gross_sales_input => |edit| {
            model.incomeTax.applyInput(
                .eight_percent_gross_sales_or_receipts,
                edit,
            );
        },
        .income_tax_eight_non_operating_input => |edit| {
            model.incomeTax.applyInput(
                .eight_percent_non_operating_income,
                edit,
            );
        },
        .income_tax_eight_tax_due_input => |edit| {
            model.incomeTax.applyInput(.eight_percent_tax_due, edit);
        },
        .income_tax_prior_payments_input => |edit| {
            model.incomeTax.applyInput(
                .prior_quarter_income_tax_payments,
                edit,
            );
        },
        .income_tax_withheld_2307_input => |edit| {
            model.incomeTax.applyInput(
                .creditable_tax_withheld_2307,
                edit,
            );
        },
        .income_tax_other_credits_input => |edit| {
            model.incomeTax.applyInput(
                .other_tax_credits_or_payments,
                edit,
            );
        },
        .income_tax_payable_input => |edit| {
            model.incomeTax.applyInput(.tax_payable_or_overpayment, edit);
        },
        .income_tax_surcharge_input => |edit| {
            model.incomeTax.applyInput(.surcharge, edit);
        },
        .income_tax_interest_input => |edit| {
            model.incomeTax.applyInput(.interest, edit);
        },
        .income_tax_compromise_input => |edit| {
            model.incomeTax.applyInput(.compromise, edit);
        },
        .income_tax_add_payment => {
            _ = model.incomeTax.addPaymentRow() catch {};
        },
        .income_tax_select_payment => |slot| {
            model.incomeTax.selectPaymentRow(slot) catch {};
        },
        .income_tax_remove_selected_payment => {
            for (model.incomeTax.paymentRows()) |*row| {
                if (!row.selected()) continue;
                model.incomeTax.removePaymentRow(row.id()) catch {};
                break;
            }
        },
        .income_tax_payment_method_cash => {
            model.incomeTax.setSelectedPaymentMethod(.cash) catch {};
        },
        .income_tax_payment_method_check => {
            model.incomeTax.setSelectedPaymentMethod(.check) catch {};
        },
        .income_tax_payment_method_tax_debit_memo => {
            model.incomeTax.setSelectedPaymentMethod(
                .tax_debit_memo,
            ) catch {};
        },
        .income_tax_payment_method_other => {
            model.incomeTax.setSelectedPaymentMethod(.other) catch {};
        },
        .income_tax_payment_bank_input => |edit| {
            model.incomeTax.applyPaymentInput(.bank_or_agency, edit);
        },
        .income_tax_payment_reference_input => |edit| {
            model.incomeTax.applyPaymentInput(.reference, edit);
        },
        .income_tax_payment_amount_input => |edit| {
            model.incomeTax.applyPaymentInput(.amount, edit);
        },
        .percentage_tax_period_calendar => {
            model.percentageTax.setPeriodBasis(.calendar);
        },
        .percentage_tax_period_fiscal => {},
        .percentage_tax_year_end_month_input => |edit| {
            model.percentageTax.editYearEndMonth(edit);
        },
        .percentage_tax_sheets_attached_input => |edit| {
            model.percentageTax.editSheetsAttached(edit);
        },
        .percentage_tax_relief_none => {
            model.percentageTax.setTaxRelief(.none);
        },
        .percentage_tax_relief_specified => {
            model.percentageTax.setTaxRelief(.specified);
        },
        .percentage_tax_relief_reference_input => |edit| {
            model.percentageTax.editTaxReliefReference(edit);
        },
        .percentage_tax_election_graduated => {
            model.percentageTax.setIncomeTaxRateElection(.graduated);
        },
        .percentage_tax_election_eight_percent => {
            model.percentageTax.setIncomeTaxRateElection(.eight_percent);
        },
        .percentage_tax_line_1_atc_input => |edit| {
            model.percentageTax.editScheduleAtc(0, edit);
        },
        .percentage_tax_line_1_base_input => |edit| {
            model.percentageTax.editScheduleTaxBase(0, edit);
        },
        .percentage_tax_line_1_rate_input => |edit| {
            model.percentageTax.editScheduleRate(0, edit);
        },
        .percentage_tax_line_2_atc_input => |edit| {
            model.percentageTax.editScheduleAtc(1, edit);
        },
        .percentage_tax_line_2_base_input => |edit| {
            model.percentageTax.editScheduleTaxBase(1, edit);
        },
        .percentage_tax_line_2_rate_input => |edit| {
            model.percentageTax.editScheduleRate(1, edit);
        },
        .percentage_tax_creditable_withheld_input => |edit| {
            model.percentageTax.editCreditableWithheld(edit);
        },
        .percentage_tax_paid_previous_input => |edit| {
            model.percentageTax.editPaidInPreviousReturn(edit);
        },
        .percentage_tax_other_credit_input => |edit| {
            model.percentageTax.editOtherCredit(edit);
        },
        .percentage_tax_surcharge_input => |edit| {
            model.percentageTax.editSurcharge(edit);
        },
        .percentage_tax_interest_input => |edit| {
            model.percentageTax.editInterest(edit);
        },
        .percentage_tax_compromise_input => |edit| {
            model.percentageTax.editCompromise(edit);
        },
        .percentage_tax_disposition_not_applicable => {
            model.percentageTax.setOverpaymentDisposition(.not_applicable);
        },
        .percentage_tax_disposition_refund => {
            model.percentageTax.setOverpaymentDisposition(.refund);
        },
        .percentage_tax_disposition_tax_credit => {
            model.percentageTax.setOverpaymentDisposition(
                .tax_credit_certificate,
            );
        },
        .percentage_tax_disposition_carry_over => {
            model.percentageTax.setOverpaymentDisposition(.carry_over);
        },
        .show_aux_lock_screen => openTransient(model, .aux_lock_screen),
        .show_aux_profile_auth_overlay => openTransient(model, .aux_profile_auth),
        .show_aux_admin_auth_overlay => openTransient(model, .aux_admin_auth),
        .show_aux_command_palette => openTransient(model, .aux_command_palette),
        .show_aux_html_print_preview => openTransient(model, .aux_html_preview),
        .show_aux_email_confirmation => openTransient(model, .aux_email_confirmation),
        .show_aux_background_task_debug_log => openTransient(model, .aux_debug_log),
        .select_taxpayer => |slot| {
            const row = model.taxProfiles.rowAt(slot) orelse return;
            const changing_taxpayer = if (model.taxProfiles.selectedProfileId()) |selected|
                !std.mem.eql(u8, selected, row.idLabel())
            else
                true;
            if (changing_taxpayer and deferTaxpayerContextMutation(
                model,
                .{ .taxpayer_slot = slot },
            )) return;
            if (rejectExact1701QTaxpayerChange(
                model,
                row.idLabel(),
            )) {
                // Keep the sidebar selection and exact filer identity in
                // one visible context. A different taxpayer cannot become
                // selected behind a material exact workspace.
                reconcileExact1701QTaxpayerSelection(model);
                navigate(model, .form_1701q);
                return;
            }
            leaveInlineProfileSettings(model);
            model.taxProfiles.select(slot);
            if (!std.mem.eql(
                u8,
                model.taxProfiles.selectedProfileId() orelse return,
                row.idLabel(),
            )) return;
            syncProfileIdentityControls(model);
            model.regPage = .{};
            model.regLoaded = false;
            model.regLoadFailed = false;
            resetRegistrationDialog(model);
            model.profileCalendarSelectedDate = null;
            model.libraryFilter.filter_picker_visible = false;
            model.libraryFilter.period_picker_visible = false;
            model.libraryFilter.period_filter = .all;
            resetProfileFormsBrowseFilters(model);
            model.profileCompletionTarget = null;
            model.profileCompletionFormIndex = null;
            model.pendingProfileFormLaunch = null;
            refreshSelectedProfileFormSet(model);
            resetProfileCalendarExportNotice(model);
            model.dashboardSection = .calendar;
            navigate(model, .taxpayer_dashboard);
        },
        .show_dashboard_calendar => {
            if (model.dashboardSection != .calendar and
                deferProfileNavigation(
                    model,
                    .{ .dashboard_section = .calendar },
                )) return;
            leaveInlineProfileSettings(model);
            model.libraryFilter.filter_picker_visible = false;
            model.libraryFilter.period_picker_visible = false;
            model.libraryFilter.info_index = null;
            model.dashboardSection = .calendar;
        },
        .show_dashboard_forms => {
            if (model.dashboardSection != .forms and
                deferProfileNavigation(
                    model,
                    .{ .dashboard_section = .forms },
                )) return;
            leaveInlineProfileSettings(model);
            model.dashboardSection = .forms;
        },
        .show_dashboard_profile_settings => {
            if (model.dashboardSection == .profile_settings) return;
            model.profileCompletionTarget = null;
            model.profileCompletionFormIndex = null;
            model.pendingProfileFormLaunch = null;
            model.profileSetupSection = .tax_profile;
            model.taxProfiles.cancelEdit();
            syncProfileIdentityControls(model);
            _ = ensureCompleteProfileRegistrationLoaded(model);
            model.dashboardSection = .profile_settings;
        },
        .show_profile_tax => {
            if (model.regPage.dirty()) {
                model.regEditorError.set(
                    "Save or cancel registration edits before leaving this section.",
                );
                return;
            }
            if (model.profileSetupSection != .tax_profile and
                deferProfileNavigation(
                    model,
                    .{ .profile_section = .tax_profile },
                )) return;
            if (model.regEditing()) {
                loadRegistrationPage(model);
                syncCompleteProfileRegistrationControls(model);
            }
            model.profileSetupSection = .tax_profile;
        },
        .edit_tax_profile => {
            beginCompleteProfileEdit(model);
        },
        .show_profile_tax_forms => {
            if (model.profileSetupSection != .tax_forms and
                deferProfileNavigation(
                    model,
                    .{ .profile_section = .tax_forms },
                )) return;
            if (model.taxProfiles.profileEditing()) {
                model.taxProfiles.cancelEdit();
                syncProfileIdentityControls(model);
            }
            if (model.regEditing()) loadRegistrationPage(model);
            model.profileClassificationPickerVisible = false;
            model.profileEoptPickerVisible = false;
            model.profileSetupSection = .tax_forms;
            model.profileSetupYearPickerVisible = false;
            model.profileSetupSourcePickerVisible = false;
            model.profileSetupYearQuery.clear();
            ensureYearWorkspaceOpen(model);
        },
        .reg_retry => loadRegistrationPage(model),
        .reg_edit => model.regPage.beginEdit() catch {},
        .reg_cancel => {
            model.regPage.cancel() catch {};
            resetRegistrationDialog(model);
            returnToTaxFormProfileAfterRegistration(model);
        },
        .reg_save => saveRegistrationPage(model),
        .reg_add_act => beginRegistrationActivityDialog(
            model,
            null,
        ),
        .reg_edit_act => |index| {
            beginRegistrationActivityDialog(model, index);
        },
        .reg_remove_act => |index| {
            const rows = model.regPage.businessActivities();
            if (index < rows.len) {
                model.regPage.removeBusinessActivity(
                    rows[index].anchor_id,
                ) catch {};
            }
        },
        .reg_add_ob => beginRegistrationObligationDialog(
            model,
            null,
        ),
        .reg_edit_ob => |index| {
            beginRegistrationObligationDialog(model, index);
        },
        .reg_remove_ob => |index| {
            const rows = model.regPage.registrationObligations();
            if (index < rows.len) {
                model.regPage.removeRegistrationObligation(
                    rows[index].anchor_id,
                ) catch {};
            }
        },
        .reg_dialog_cancel => resetRegistrationDialog(model),
        .reg_dialog_save => commitRegistrationDialog(model),
        .reg_line_input => |edit| {
            model.regLineOfBusiness.apply(edit);
        },
        .reg_atc_input => |edit| model.regAtc.apply(edit),
        .reg_from_input => |edit| {
            model.regEffectiveFrom.apply(edit);
        },
        .reg_until_input => |edit| {
            model.regEffectiveUntil.apply(edit);
        },
        .reg_other_input => |edit| {
            model.regOtherTaxType.apply(edit);
        },
        .reg_kind_income_tax => {
            model.regObligationDraftKind = .registered_income_tax;
        },
        .reg_kind_vat => {
            model.regObligationDraftKind = .vat;
        },
        .reg_kind_percentage_tax => {
            model.regObligationDraftKind = .percentage_tax;
        },
        .reg_kind_wh_comp => {
            model.regObligationDraftKind = .withholding_compensation;
        },
        .reg_kind_wh_expanded => {
            model.regObligationDraftKind = .withholding_expanded;
        },
        .reg_kind_wh_final => {
            model.regObligationDraftKind = .withholding_final;
        },
        .reg_kind_wh_other => {
            model.regObligationDraftKind = .withholding_other;
        },
        .reg_conflict_accept => {
            if (model.regPage.conflict) |conflict| {
                model.regPage.acceptReviewedConflictBase(
                    conflict.current_sequence,
                ) catch {};
            }
        },
        .reg_conflict_reload => loadRegistrationPage(model),
        .profile_cor_upload => attachCorDocument(model, fx),
        .profile_cor_begin_review => _ = model.taxProfiles.beginCorReview(),
        .profile_cor_cancel_review => model.taxProfiles.cancelCorReview(),
        .profile_cor_tin_input => |edit| {
            model.taxProfiles.cor_review_tin.apply(edit);
        },
        .profile_cor_rdo_input => |edit| applyCorValue(model, .rdo_code, edit),
        .profile_cor_name_input => |edit| applyCorValue(model, .taxpayer_name, edit),
        .profile_cor_address_input => |edit| applyCorValue(model, .registered_address, edit),
        .profile_cor_zip_input => |edit| applyCorValue(model, .zip_code, edit),
        .profile_cor_tax_type_input => |edit| applyCorValue(model, .tax_type, edit),
        .profile_cor_toggle_rdo => toggleCorAccepted(model, .rdo_code),
        .profile_cor_toggle_name => toggleCorAccepted(model, .taxpayer_name),
        .profile_cor_toggle_address => toggleCorAccepted(model, .registered_address),
        .profile_cor_toggle_zip => toggleCorAccepted(model, .zip_code),
        .profile_cor_toggle_tax_type => toggleCorAccepted(model, .tax_type),
        .profile_cor_toggle_apply_forms => {
            model.taxProfiles.toggleCorReviewApplyForms();
        },
        .form_filing_address_input => |edit| {
            model.percentageTax.setContactOverride(.registered_address, edit);
        },
        .form_filing_zip_input => |edit| {
            model.percentageTax.setContactOverride(.zip_code, edit);
        },
        .form_filing_contact_input => |edit| {
            model.percentageTax.setContactOverride(.contact_number, edit);
        },
        .form_filing_email_input => |edit| {
            model.percentageTax.setContactOverride(.email_address, edit);
        },
        .form_filing_use_profile_contacts => {
            model.percentageTax.useProfileContactValues();
        },
        .profile_cor_apply => {
            if (model.taxProfiles.applyCorReview()) {
                resetProfileFormsPage(model);
                refreshSelectedProfileFormSet(model);
                refreshSelectedProfileCalendar(model);
            }
        },
        .show_profile_email => {
            if (model.regPage.dirty()) {
                model.regEditorError.set(
                    "Save or cancel registration edits before leaving this section.",
                );
                return;
            }
            if (model.profileSetupSection != .email and
                deferProfileNavigation(
                    model,
                    .{ .profile_section = .email },
                )) return;
            if (model.taxProfiles.profileEditing()) {
                model.taxProfiles.cancelEdit();
                syncProfileIdentityControls(model);
            }
            if (model.regEditing()) loadRegistrationPage(model);
            model.profileClassificationPickerVisible = false;
            model.profileEoptPickerVisible = false;
            model.profileSetupSection = .email;
        },
        .toggle_profile_subject_picker => {
            model.profileSubjectPickerVisible =
                !model.profileSubjectPickerVisible;
            model.profileClassificationPickerVisible = false;
            model.profileEoptPickerVisible = false;
        },
        .close_profile_subject_picker => {
            model.profileSubjectPickerVisible = false;
        },
        .toggle_profile_classification_picker => {
            model.profileClassificationPickerVisible =
                !model.profileClassificationPickerVisible;
            model.profileSubjectPickerVisible = false;
            model.profileEoptPickerVisible = false;
        },
        .close_profile_classification_picker => {
            model.profileClassificationPickerVisible = false;
        },
        .toggle_profile_eopt_picker => {
            model.profileEoptPickerVisible = !model.profileEoptPickerVisible;
            model.profileSubjectPickerVisible = false;
            model.profileClassificationPickerVisible = false;
        },
        .close_profile_eopt_picker => {
            model.profileEoptPickerVisible = false;
        },
        .profile_subject_individual => {
            model.taxProfiles.setSubjectKind(.individual);
            model.profileSubjectPickerVisible = false;
            syncRegistrationTaxpayerContext(model);
        },
        .profile_subject_corporation => {
            model.taxProfiles.setSubjectKind(.corporation);
            model.profileSubjectPickerVisible = false;
            syncRegistrationTaxpayerContext(model);
        },
        .profile_subject_partnership => {
            model.taxProfiles.setSubjectKind(.partnership);
            model.profileSubjectPickerVisible = false;
            syncRegistrationTaxpayerContext(model);
        },
        .profile_subject_cooperative => {
            model.taxProfiles.setSubjectKind(.cooperative);
            model.profileSubjectPickerVisible = false;
            syncRegistrationTaxpayerContext(model);
        },
        .profile_subject_estate => {
            model.taxProfiles.setSubjectKind(.estate);
            model.profileSubjectPickerVisible = false;
            syncRegistrationTaxpayerContext(model);
        },
        .profile_subject_trust => {
            model.taxProfiles.setSubjectKind(.trust);
            model.profileSubjectPickerVisible = false;
            syncRegistrationTaxpayerContext(model);
        },
        .profile_subject_other_legal => {
            model.taxProfiles.setSubjectKind(.other_legal_entity);
            model.profileSubjectPickerVisible = false;
            syncRegistrationTaxpayerContext(model);
        },
        .profile_classification_pure_compensation => {
            model.taxProfiles.setNaturalPersonClassification(
                .pure_compensation,
            );
            model.profileClassificationPickerVisible = false;
            syncRegistrationTaxpayerContext(model);
        },
        .profile_classification_self_employed => {
            model.taxProfiles.setNaturalPersonClassification(.self_employed);
            model.profileClassificationPickerVisible = false;
            syncRegistrationTaxpayerContext(model);
        },
        .profile_classification_mixed_income => {
            model.taxProfiles.setNaturalPersonClassification(.mixed_income);
            model.profileClassificationPickerVisible = false;
            syncRegistrationTaxpayerContext(model);
        },
        .profile_eopt_micro => selectCompleteProfileEopt(model, .micro),
        .profile_eopt_small => selectCompleteProfileEopt(model, .small),
        .profile_eopt_medium => selectCompleteProfileEopt(model, .medium),
        .profile_eopt_large => selectCompleteProfileEopt(model, .large),
        .profile_source_manual => {
            model.taxProfiles.setSourceKind(.manual_entry);
        },
        .profile_source_imported => {
            model.taxProfiles.setSourceKind(.imported);
        },
        .profile_source_migrated => {
            model.taxProfiles.setSourceKind(.migrated);
        },
        .profile_gwa_unset => {
            model.taxProfiles.setGovernmentWithholdingAgent(.unset);
        },
        .profile_gwa_no => {
            model.taxProfiles.setGovernmentWithholdingAgent(.no);
        },
        .profile_gwa_yes => {
            model.taxProfiles.setGovernmentWithholdingAgent(.yes);
        },
        .profile_setup_toggle_year_picker => {
            model.profileSetupYearPickerVisible =
                !model.profileSetupYearPickerVisible;
            model.profileSetupYearQuery.clear();
            model.profileSetupSourcePickerVisible = false;
        },
        .profile_setup_close_year_picker => {
            model.profileSetupYearPickerVisible = false;
            model.profileSetupYearQuery.clear();
        },
        .profile_setup_year_query => |edit| {
            applyDigitsOnly(&model.profileSetupYearQuery, edit);
        },
        .profile_setup_select_year => |year| {
            model.profileSetupYearPickerVisible = false;
            model.profileSetupYearQuery.clear();
            model.profileSetupSourcePickerVisible = false;
            if (model.regPage.dirty()) {
                model.regEditorError.set(
                    "Save or cancel registration edits before changing tax year.",
                );
                return;
            }
            openProfileSetupYear(model, year);
        },
        .profile_setup_retry_year => {
            const year = model.taxProfiles.workspaceYear() orelse
                model.taxProfiles.maximumSetupYear();
            openProfileSetupYear(model, year);
        },
        .profile_setup_draft_empty => {
            _ = model.taxProfiles.chooseDraftEmpty();
            resetProfileFormsPage(model);
        },
        .profile_setup_draft_seed => |source| {
            model.profileSetupSourcePickerVisible = false;
            _ = model.taxProfiles.chooseDraftSeed(source);
            resetProfileFormsPage(model);
        },
        .profile_setup_toggle_source_picker => {
            model.profileSetupSourcePickerVisible =
                !model.profileSetupSourcePickerVisible;
        },
        .profile_setup_close_source_picker => {
            model.profileSetupSourcePickerVisible = false;
        },
        .profile_setup_save => {
            const recorded_change = model.taxProfiles.applyScopeFromDate();
            if (model.taxProfiles.saveYearWorkspace()) {
                model.libraryFilter.filter_picker_visible = false;
                resetProfileFormsPage(model);
                refreshSelectedProfileFormSet(model);
                refreshSelectedProfileCalendar(model);
                refreshProfileFormLaunchAssessments(model);
                // A just-recorded change must be visible without a click, or
                // the catalog snapping back reads as a lost save.
                if (recorded_change) model.profileSetupChangesExpanded = true;
            }
        },
        .profile_setup_conflict_review => {
            _ = model.taxProfiles.reviewConflictingYear();
            resetProfileFormsPage(model);
        },
        .profile_setup_conflict_discard => {
            if (model.taxProfiles.discardConflictingDraft()) {
                resetProfileFormsPage(model);
                refreshSelectedProfileFormSet(model);
                refreshSelectedProfileCalendar(model);
            }
        },
        .profile_setup_confirm_year_switch => {
            _ = model.taxProfiles.confirmPendingYearSwitch();
            resetProfileFormsPage(model);
        },
        .profile_setup_cancel_year_switch => {
            model.taxProfiles.cancelPendingYearSwitch();
        },
        .profile_setup_toggle_years_disclosure => {
            model.profileSetupYearsExpanded = !model.profileSetupYearsExpanded;
        },
        .profile_setup_apply_whole_year => {
            model.taxProfiles.chooseApplyWholeYear();
        },
        .profile_setup_apply_from_date => {
            model.taxProfiles.chooseApplyFromDate();
        },
        .profile_setup_change_date_input => |edit| {
            model.taxProfiles.change_effective_from.apply(edit);
        },
        .profile_setup_toggle_changes_disclosure => {
            model.profileSetupChangesExpanded = !model.profileSetupChangesExpanded;
        },
        .add_branch_profile => {
            if (rejectExact1701QContextChange(model)) {
                reconcileExact1701QTaxpayerSelection(model);
                navigate(model, .form_1701q);
                return;
            }
            if (deferTaxpayerContextMutation(model, .add_branch)) return;
            if (!model.taxProfiles.beginAddBranch()) {
                syncProfileIdentityControls(model);
                openProfileEditor(model);
                return;
            }
            model.profileSetupSection = .tax_profile;
            model.profileCompletionTarget = null;
            model.profileCompletionFormIndex = null;
            model.pendingProfileFormLaunch = null;
            _ = initializeNewCompleteProfileRegistration(model);
            syncProfileIdentityControls(model);
            openProfileEditor(model);
        },
        .profile_record_change => model.taxProfiles.beginRecordChange(),
        .profile_fix_mistake => model.taxProfiles.beginFixMistake(),
        .profile_toggle_advanced => {
            model.profileAdvancedExpanded = !model.profileAdvancedExpanded;
        },
        .profile_forms_manage => {
            if (model.taxProfiles.beginManageForms()) {
                model.libraryFilter.filter_picker_visible = false;
                model.libraryFilter.period_picker_visible = false;
                model.libraryFilter.info_index = null;
                model.libraryFilter.manage_cadence_mask = 0b1111;
                model.libraryFilter.category_mask = 0;
                resetProfileFormsPage(model);
            }
        },
        .profile_forms_search_input => |edit| {
            model.taxProfiles.applyFormsQuery(edit);
            model.libraryFilter.info_index = null;
            resetProfileFormsPage(model);
        },
        .toggle_profile_form => |index| {
            model.taxProfiles.toggleStagedForm(index);
        },
        .profile_forms_select_all => model.taxProfiles.selectAllStagedForms(),
        .profile_forms_clear_all => model.taxProfiles.clearAllStagedForms(),
        .profile_forms_cancel => {
            const return_to_browse =
                model.taxProfiles.year_workspace == .viewing;
            model.taxProfiles.cancelYearWorkspaceEdits();
            if (return_to_browse) model.taxProfiles.cancelManageForms();
            model.libraryFilter.filter_picker_visible = false;
            resetProfileFormsPage(model);
            refreshProfileFormLaunchAssessments(model);
        },
        .profile_forms_reset_legacy => {
            if (model.taxProfiles.resetManagedFormsToLegacyDefault()) {
                model.libraryFilter.filter_picker_visible = false;
                refreshSelectedProfileFormSet(model);
                refreshSelectedProfileCalendar(model);
            }
        },
        .profile_forms_toggle_filter_active => {
            model.taxProfiles.toggleFormFilterActive();
        },
        .profile_forms_toggle_filter_inactive => {
            model.taxProfiles.toggleFormFilterInactive();
        },
        .profile_forms_toggle_filter_editor => {
            model.taxProfiles.toggleFormFilterEditor();
        },
        .profile_forms_toggle_filter_calendar_only => {
            model.taxProfiles.toggleFormFilterCalendarOnly();
        },
        .profile_forms_reset_filters => {
            model.libraryFilter.info_index = null;
            model.taxProfiles.applyFormsQuery(.clear);
            model.taxProfiles.resetFormFilters();
            if (model.taxProfiles.managing_forms) {
                model.libraryFilter.manage_cadence_mask = 0b1111;
                model.libraryFilter.category_mask = 0;
            } else {
                model.libraryFilter.browse_cadence_mask = 0b1111;
                model.libraryFilter.month_mask = 0;
                model.libraryFilter.quarter_mask = 0;
                model.libraryFilter.on_demand_mask = 0;
            }
            resetProfileFormsPage(model);
            model.libraryFilter.period_filter = .all;
            model.libraryFilter.period_picker_visible = false;
        },
        .profile_forms_toggle_filter_picker => {
            model.libraryFilter.period_picker_visible = false;
            model.libraryFilter.info_index = null;
            model.libraryFilter.filter_picker_visible =
                !model.libraryFilter.filter_picker_visible;
        },
        .profile_forms_close_filter_picker => {
            model.libraryFilter.filter_picker_visible = false;
        },
        .profile_forms_show_info => |index| {
            if (index >= form_catalog.forms.len or
                model.taxProfiles.managing_forms)
            {
                model.libraryFilter.info_index = null;
            } else if (model.libraryFilter.info_index == index) {
                model.libraryFilter.info_index = null;
            } else {
                model.libraryFilter.filter_picker_visible = false;
                model.libraryFilter.info_index = index;
            }
        },
        .profile_forms_close_info => {
            model.libraryFilter.info_index = null;
        },
        .profile_forms_toggle_cadence_monthly => toggleLibraryCadence(model, 0b0001),
        .profile_forms_toggle_cadence_quarterly => toggleLibraryCadence(model, 0b0010),
        .profile_forms_toggle_cadence_annual => toggleLibraryCadence(model, 0b0100),
        .profile_forms_toggle_cadence_on_demand => toggleLibraryCadence(model, 0b1000),
        .profile_forms_toggle_month => |month| toggleLibraryMonth(model, month),
        .profile_forms_toggle_quarter_1 => toggleLibraryQuarter(model, 1),
        .profile_forms_toggle_quarter_2 => toggleLibraryQuarter(model, 2),
        .profile_forms_toggle_quarter_3 => toggleLibraryQuarter(model, 3),
        .profile_forms_toggle_quarter_4 => toggleLibraryQuarter(model, 4),
        .profile_forms_toggle_category => |index| toggleLibraryCategoryAt(model, index),
        .profile_forms_toggle_on_demand_form => |index| toggleLibraryOnDemandForm(model, index),
        .profile_forms_show_previous => {
            model.libraryFilter.page_offset -|= model.libraryFilter.visible_limit;
        },
        .profile_forms_show_more => {
            if (model.profileFormsHasMoreRows()) {
                model.libraryFilter.page_offset += model.libraryFilter.visible_limit;
            }
        },
        .profile_forms_toggle_period_picker => {
            model.libraryFilter.filter_picker_visible = false;
            model.libraryFilter.period_picker_visible =
                !model.libraryFilter.period_picker_visible;
        },
        .profile_forms_close_period_picker => {
            model.libraryFilter.period_picker_visible = false;
        },
        .profile_forms_period_all => {
            setLibraryPeriodFilter(model, .all);
        },
        .profile_forms_period_january => setLibraryPeriodFilter(model, .{ .monthly = 1 }),
        .profile_forms_period_february => setLibraryPeriodFilter(model, .{ .monthly = 2 }),
        .profile_forms_period_march => setLibraryPeriodFilter(model, .{ .monthly = 3 }),
        .profile_forms_period_april => setLibraryPeriodFilter(model, .{ .monthly = 4 }),
        .profile_forms_period_may => setLibraryPeriodFilter(model, .{ .monthly = 5 }),
        .profile_forms_period_june => setLibraryPeriodFilter(model, .{ .monthly = 6 }),
        .profile_forms_period_july => setLibraryPeriodFilter(model, .{ .monthly = 7 }),
        .profile_forms_period_august => setLibraryPeriodFilter(model, .{ .monthly = 8 }),
        .profile_forms_period_september => setLibraryPeriodFilter(model, .{ .monthly = 9 }),
        .profile_forms_period_october => setLibraryPeriodFilter(model, .{ .monthly = 10 }),
        .profile_forms_period_november => setLibraryPeriodFilter(model, .{ .monthly = 11 }),
        .profile_forms_period_december => setLibraryPeriodFilter(model, .{ .monthly = 12 }),
        .profile_forms_period_quarter_one => setLibraryPeriodFilter(model, .{ .quarterly = 1 }),
        .profile_forms_period_quarter_two => setLibraryPeriodFilter(model, .{ .quarterly = 2 }),
        .profile_forms_period_quarter_three => setLibraryPeriodFilter(model, .{ .quarterly = 3 }),
        .profile_forms_period_quarter_four => setLibraryPeriodFilter(model, .{ .quarterly = 4 }),
        .profile_forms_period_annual => {
            setLibraryPeriodFilter(model, .annual);
        },
        .profile_forms_period_on_demand => {
            setLibraryPeriodFilter(model, .on_demand);
        },
        .open_library_form => |index| openLibraryForm(model, index),
        .open_library_period => |action_id| openLibraryPeriod(model, action_id),
        .open_tax_form_profile => |index| openTaxFormProfile(model, index),
        .close_tax_form_profile => closeTaxFormProfile(model),
        .tax_form_profile_previous_segment => requestTaxFormProfileSegment(
            model,
            model.taxFormProfilePreviousSegmentDate,
        ),
        .tax_form_profile_next_segment => requestTaxFormProfileSegment(
            model,
            model.taxFormProfileNextSegmentDate,
        ),
        .tax_form_profile_keep_editing => {
            model.taxFormProfilePendingNavigation = null;
            model.taxFormProfileDiscardPromptOpen = false;
        },
        .tax_form_profile_discard_navigation => {
            const pending = model.taxFormProfilePendingNavigation orelse
                PendingTaxFormProfileNavigation{
                    .return_context = {},
                };
            model.taxFormProfilePendingNavigation = null;
            model.taxFormProfileDiscardPromptOpen = false;
            model.taxFormProfilePage.reset();
            model.taxpayerYearPage.reset();
            model.annualIncomeTaxElection = .{};
            model.taxFormProfileComposed = .{};
            model.taxFormProfileFormIndex = null;
            model.taxFormProfileViewedDate = null;
            model.taxFormProfilePreviousSegmentDate = null;
            model.taxFormProfileNextSegmentDate = null;
            model.taxFormProfilePickerField = null;
            model.taxFormProfileChoiceCount = 0;
            model.taxFormProfileHistoryRowCount = 0;
            model.taxFormProfileHistoryTruncated = false;
            model.taxFormProfileInherited = .{};
            model.taxFormProfileRegistrationReturnPending = false;
            switch (pending) {
                .page => |page| navigate(model, page),
                .return_context => restoreTaxFormProfileReturnContext(model),
                .taxpayer_slot => |slot| updateCore(
                    model,
                    .{ .select_taxpayer = slot },
                    fx,
                ),
                .new_taxpayer => updateCore(model, .new_taxpayer_profile, fx),
                .add_branch => updateCore(model, .add_branch_profile, fx),
                .activation_segment => |target| openTaxFormProfileForYearAt(
                    model,
                    target.form_index,
                    target.tax_year,
                    target.viewed_on,
                    true,
                    target.filing,
                ),
            }
        },
        .edit_tax_form_profile => {
            model.taxFormProfilePage.beginEdit() catch {};
        },
        .cancel_tax_form_profile => {
            model.taxFormProfilePage.cancel() catch {};
            model.taxFormProfilePickerField = null;
        },
        .save_tax_form_profile => saveTaxFormProfile(model),
        .tax_form_profile_toggle_picker => |field_index| {
            if (model.taxFormProfilePage.page() != .editing) return;
            model.taxFormProfilePickerField =
                if (model.taxFormProfilePickerField == field_index)
                    null
                else
                    field_index;
        },
        .tax_form_profile_select_choice => |choice_index| {
            selectTaxFormProfileChoice(model, choice_index);
        },
        .tax_form_profile_clear_value => |field_index| {
            const form_index = model.taxFormProfileFormIndex orelse return;
            if (form_index >= form_catalog.registry_count) return;
            const definition = &form_catalog.forms[form_index];
            if (field_index >= definition.tax_form_profile.values.len) return;
            const field = definition.tax_form_profile.values[field_index];
            model.taxFormProfilePage.removeDraftValue(
                field.role,
                field.semantic_key,
            ) catch {};
            loadTaxFormProfileChoices(model);
        },
        .tax_form_profile_close_picker => {
            model.taxFormProfilePickerField = null;
        },
        .tax_form_profile_acknowledge_review => {
            model.taxFormProfilePage.acknowledgeReview() catch {};
        },
        .tax_form_profile_copy_prior_year => {
            const reason = if (model.taxFormProfilePage.copy_offer) |offer|
                offer.reason
            else
                return;
            if (reason != .prior_year and reason != .form_revision_mapping) {
                return;
            }
            stageTaxFormProfileOfferedReuse(model, reason);
        },
        .tax_form_profile_reuse_after_reactivation => {
            stageTaxFormProfileOfferedReuse(model, .reactivation);
        },
        .tax_form_profile_keep_draft_after_conflict => {
            acceptTaxFormProfileConflictBase(model);
        },
        .tax_form_profile_reload_after_conflict => {
            reloadTaxFormProfileAfterConflict(model);
        },
        .taxpayer_year_edit => {
            if (model.taxpayerYearEditVisible()) {
                model.taxpayerYearPage.beginEdit() catch {};
            }
        },
        .taxpayer_year_cancel => model.taxpayerYearPage.cancel() catch {},
        .taxpayer_year_save => saveTaxpayerYearSettings(model),
        .taxpayer_year_rate_graduated => {
            model.taxpayerYearPage.setDraftValue(.{
                .income_tax_rate_election = .graduated,
            }) catch {};
        },
        .taxpayer_year_rate_eight_percent => {
            model.taxpayerYearPage.setDraftValue(.{
                .income_tax_rate_election = .eight_percent,
            }) catch {};
            model.taxpayerYearPage.removeDraftSetting(.deduction_method) catch {};
        },
        .taxpayer_year_deduction_itemized => {
            model.taxpayerYearPage.setDraftValue(.{
                .deduction_method = .itemized_deduction,
            }) catch {};
        },
        .taxpayer_year_deduction_osd => {
            model.taxpayerYearPage.setDraftValue(.{
                .deduction_method = .optional_standard_deduction,
            }) catch {};
        },
        .taxpayer_year_acknowledge_review => {
            model.taxpayerYearPage.acknowledgeReview() catch {};
        },
        .taxpayer_year_copy_prior_year => {
            model.taxpayerYearPage.stagePriorYearCopy() catch {};
        },
        .taxpayer_year_keep_draft_after_conflict => {
            resolveTaxpayerYearConflict(model, true);
        },
        .taxpayer_year_reload_after_conflict => {
            resolveTaxpayerYearConflict(model, false);
        },
        .tax_form_profile_edit_tax_profile => {
            model.taxFormProfileRegistrationReturnPending = false;
            model.taxFormProfilePage.reset();
            model.taxpayerYearPage.reset();
            model.annualIncomeTaxElection = .{};
            model.taxFormProfileComposed = .{};
            model.taxFormProfileFormIndex = null;
            model.taxFormProfileViewedDate = null;
            model.taxFormProfilePreviousSegmentDate = null;
            model.taxFormProfileNextSegmentDate = null;
            model.taxFormProfilePickerField = null;
            model.taxFormProfileChoiceCount = 0;
            model.profileSetupSection = .tax_profile;
            model.dashboardSection = .profile_settings;
            navigate(model, .taxpayer_dashboard);
            beginCompleteProfileEdit(model);
        },
        .tax_form_profile_edit_registration => {
            openTaxFormProfileRegistrationRepair(model);
        },
        .profile_tin_segment_one_input => |edit| {
            applyProfileTinSegment(model, 0, edit);
        },
        .profile_tin_segment_two_input => |edit| {
            applyProfileTinSegment(model, 1, edit);
        },
        .profile_tin_segment_three_input => |edit| {
            applyProfileTinSegment(model, 2, edit);
        },
        .profile_tin_segment_branch_input => |edit| {
            applyProfileTinSegment(model, 3, edit);
        },
        .profile_rdo_toggle_picker => {
            if (model.profileRdoPickerVisible) {
                syncProfileRdoControl(model);
            } else {
                model.profileRdoQuery.clear();
                model.profileRdoPickerVisible = true;
            }
        },
        .profile_rdo_close_picker => syncProfileRdoControl(model),
        .profile_rdo_query_input => |edit| {
            applyProfileRdoQuery(model, edit);
        },
        .profile_rdo_select => |entry_index| {
            selectProfileRdo(model, entry_index);
        },
        .profile_name_input => |edit| {
            model.taxProfiles.display_name.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_trade_name_input => |edit| {
            model.taxProfiles.trade_name.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_address_input => |edit| {
            model.taxProfiles.registered_address.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_zip_input => |edit| {
            model.taxProfiles.zip_code.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_phone_input => |edit| {
            model.taxProfiles.phone.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_email_input => |edit| {
            model.taxProfiles.email.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_birth_date_input => |edit| {
            model.taxProfiles.birth_date.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_citizenship_input => |edit| {
            model.taxProfiles.citizenship.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_foreign_tax_number_input => |edit| {
            model.taxProfiles.foreign_tax_number.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_primary_line_of_business_input => |edit| {
            applyCompleteProfilePrimaryLineOfBusiness(model, edit);
        },
        .profile_business_line_input => |edit| {
            model.taxProfiles.business_line.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_atc_input => |edit| {
            model.taxProfiles.atc.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_tax_type_input => |edit| {
            model.taxProfiles.tax_type.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_special_rate_basis_input => |edit| {
            model.taxProfiles.special_rate_basis.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_effective_from_input => |edit| {
            model.taxProfiles.effective_from.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_effective_until_input => |edit| {
            model.taxProfiles.effective_until.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_source_reference_input => |edit| {
            model.taxProfiles.source_reference.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .save_profile => {
            if (model.profileSaveDisabled()) return;
            const inline_profile_settings =
                model.page == .taxpayer_dashboard and
                model.dashboardSection == .profile_settings;
            const exact_material =
                model.exact1701Q.ready() and
                model.exact1701Q.hasDirtyOrMaterialWork();
            const preserves_exact_filer =
                exact_material and
                !model.taxProfiles.editing_new and
                model.exact1701Q.filerProfileMatches(
                    model.taxProfiles.selectedProfileId() orelse "",
                );
            const pending_launch = model.pendingProfileFormLaunch;
            if (exact_material and !preserves_exact_filer) {
                model.exact1701Q.rejectContextChange();
                reconcileExact1701QTaxpayerSelection(model);
                navigate(model, .form_1701q);
                return;
            }
            const registration_dirty = model.regPage.dirty();
            var saved = false;
            if (registration_dirty) {
                const intent = model.regPage.beginSave() catch return;
                const new_sequence = model.taxProfiles.saveCompleteProfile(
                    &intent,
                ) orelse {
                    model.regPage.saveFailed() catch {};
                    return;
                };
                model.regPage.saveSucceeded(new_sequence) catch {
                    loadRegistrationPage(model);
                    return;
                };
                saved = true;
            } else {
                saved = model.taxProfiles.save();
            }
            if (saved) {
                syncProfileIdentityControls(model);
                loadRegistrationPage(model);
                syncCompleteProfileRegistrationControls(model);
                refreshSelectedProfileFormSet(model);
                refreshTaxFormProfileCardStates(model);
                resetProfileCalendarExportNotice(model);
                if (preserves_exact_filer) {
                    model.exact1701Q.reportNewerProfileRevision();
                    reconcileExact1701QTaxpayerSelection(model);
                }
                if (inline_profile_settings) {
                    model.profileCompletionTarget = null;
                    model.profileCompletionFormIndex = null;
                    model.pendingProfileFormLaunch = null;
                }
                if (pending_launch) |pending| {
                    if (pending.form_index >= form_catalog.forms.len) return;
                    const definition = &form_catalog.forms[pending.form_index];
                    const route = profileFormRoute(definition.code) orelse return;
                    _ = openProfileBoundFormForQuarter(
                        model,
                        route.page,
                        route.form_code,
                        pending.tax_year,
                        pending.quarter,
                        pending.period_month,
                        pending.spouse_profile_id,
                        pending.filing,
                    );
                } else if (inline_profile_settings) {
                    model.profileSetupSection = .tax_profile;
                    model.dashboardSection = .profile_settings;
                } else if (preserves_exact_filer) {
                    navigate(model, .form_1701q);
                } else {
                    model.profileSetupSection = .tax_profile;
                }
            }
        },
        .cancel_profile_edit => {
            const mode = model.taxProfiles.profileMode();
            // View mode has no Cancel action. Treat a stale/programmatic
            // dispatch as a no-op so Cancel can never become hidden Back
            // navigation again.
            if (mode == .viewing or model.profileCancelDisabled()) return;
            if (model.regPage.dirty()) {
                model.regPage.cancel() catch {};
            }
            model.taxProfiles.cancelEdit();
            if (mode == .creating) {
                model.regPage = .{};
                model.regLoaded = false;
                model.regLoadFailed = false;
                model.profilePrimaryLineOfBusiness.clear();
            } else {
                loadRegistrationPage(model);
                syncCompleteProfileRegistrationControls(model);
            }
            syncProfileIdentityControls(model);
            model.profileSubjectPickerVisible = false;
            model.profileClassificationPickerVisible = false;
            model.profileEoptPickerVisible = false;
            const inline_profile_settings =
                model.page == .taxpayer_dashboard and
                model.dashboardSection == .profile_settings;
            if (mode == .creating and
                model.taxProfiles.profileCreating())
            {
                closeProfileEditor(model);
            } else if (inline_profile_settings) {
                model.profileCompletionTarget = null;
                model.profileCompletionFormIndex = null;
                model.pendingProfileFormLaunch = null;
                model.profileSetupSection = .tax_profile;
                model.dashboardSection = .profile_settings;
            }
        },
        .profile_keep_editing => {
            model.pendingProfileNavigation = null;
        },
        .profile_discard_navigation => {
            const pending = model.pendingProfileNavigation orelse return;
            model.pendingProfileNavigation = null;
            const was_creating = model.taxProfiles.editing_new;
            if (model.regPage.dirty()) {
                model.regPage.cancel() catch {};
                resetRegistrationDialog(model);
            }
            model.taxProfiles.cancelEdit();
            if (was_creating) {
                model.regPage = .{};
                model.regLoaded = false;
                model.regLoadFailed = false;
                model.profilePrimaryLineOfBusiness.clear();
            } else if (model.regPage.opened) {
                loadRegistrationPage(model);
                syncCompleteProfileRegistrationControls(model);
            }
            syncProfileIdentityControls(model);
            switch (pending) {
                .page => |page| navigate(model, page),
                .profile_section => |section| switch (section) {
                    .tax_profile => updateCore(model, .show_profile_tax, fx),
                    .tax_forms => updateCore(model, .show_profile_tax_forms, fx),
                    .email => updateCore(model, .show_profile_email, fx),
                },
                .dashboard_section => |section| switch (section) {
                    .calendar => updateCore(model, .show_dashboard_calendar, fx),
                    .forms => updateCore(model, .show_dashboard_forms, fx),
                    .profile_settings => updateCore(
                        model,
                        .show_dashboard_profile_settings,
                        fx,
                    ),
                },
                .taxpayer_slot => |slot| updateCore(
                    model,
                    .{ .select_taxpayer = slot },
                    fx,
                ),
                .new_taxpayer => updateCore(model, .new_taxpayer_profile, fx),
                .add_branch => updateCore(model, .add_branch_profile, fx),
            }
        },
        .dismiss_profile_notice => model.taxProfiles.dismissNotice(),
        .profile_notice_timeout => |timer| {
            profileNoticeTimeout(model, timer);
        },
        .calendar_today_refresh => |timer| {
            refreshCalendarTodayFromClock(model, timer);
        },
        .show_calendar_rules => model.taxCalendarSection = .rules,
        .show_calendar_overrides => model.taxCalendarSection = .overrides,
        .calendar_previous_month => {
            if (model.taxProfiles.rejectIfFormsDirty()) return;
            if (model.calendar.selected_month <= 1) return;
            model.profileCalendarSelectedDate = null;
            model.calendar.previousMonth();
            syncSelectedProfileCalendar(model);
            refreshProfileFormLaunchAssessments(model);
        },
        .calendar_next_month => {
            if (model.taxProfiles.rejectIfFormsDirty()) return;
            if (model.calendar.selected_month >= 12) return;
            model.profileCalendarSelectedDate = null;
            model.calendar.nextMonth();
            syncSelectedProfileCalendar(model);
            refreshProfileFormLaunchAssessments(model);
        },
        .profile_calendar_toggle_year_picker => {
            model.profileCalendarForms.closePicker();
            model.profileCalendarYearQuery.clear();
            model.profileCalendarYearPickerVisible =
                !model.profileCalendarYearPickerVisible;
        },
        .profile_calendar_close_year_picker => {
            model.profileCalendarYearPickerVisible = false;
        },
        .profile_calendar_year_query => |edit| {
            model.profileCalendarYearQuery.apply(edit);
        },
        .profile_calendar_select_year => |year| {
            var configured = false;
            for (model.taxProfiles.formSetSummaries()) |summary| {
                if (summary.tax_year == year) {
                    configured = true;
                    break;
                }
            }
            if (!configured) return;
            model.profileCalendarYearPickerVisible = false;
            model.profileCalendarYearQuery.clear();
            model.profileCalendarSelectedDate = null;
            model.calendar.selected_year = year;
            refreshSelectedProfileFormSet(model);
        },
        .global_calendar_previous_month => {
            model.globalDashboard.previousMonth();
        },
        .global_calendar_next_month => {
            model.globalDashboard.nextMonth();
        },
        .global_calendar_select_day => |day| {
            _ = model.globalDashboard.toggleDay(day);
        },
        .profile_calendar_select_day => |day| {
            model.toggleProfileCalendarDay(day);
        },
        .profile_deadline_toggle_actions => |menu_id| {
            toggleProfileDeadlineActionMenu(model, menu_id);
        },
        .profile_deadline_close_actions => {
            model.profileDeadlineActionMenuId = null;
        },
        .profile_deadline_run_action => |dispatch_id| {
            runProfileDeadlineAction(model, dispatch_id);
        },
        .profile_deadline_show_adjustment => |id| {
            showProfileDeadlineAdjustment(model, id);
        },
        .profile_deadline_close_dialog => {
            model.profileDeadlineAdjustmentId = null;
            model.profileDeadlineStubAction = .none;
            model.profileDeadlineStubDeadlineId = null;
        },
        .calendar_refresh => {
            model.calendar.refresh();
            refreshGlobalCalendar(model);
            refreshSelectedProfileFormSet(model);
            refreshSelectedProfileCalendar(model);
        },
        .refresh_important_news => refreshImportantNews(model, fx),
        .important_news_response => |response| {
            receiveImportantNews(model, response);
        },
        .dismiss_important_news_error => model.news.dismissError(),
        .profile_calendar_export => exportProfileCalendar(model, fx),
        .profile_calendar_export_written => |result| profileCalendarExportWritten(model, result, fx),
        .profile_calendar_export_opened => |result| profileCalendarExportOpened(model, result),
        .dismiss_profile_calendar_export_notice => {
            dismissProfileCalendarExportNotice(model);
        },
        .profile_calendar_export_notice_timeout => |timer| {
            profileCalendarExportNoticeTimeout(model, timer);
        },
        .calendar_override_title_input => |edit| {
            model.calendar.override_title.apply(edit);
            model.calendar.captureOverrideInputTruncation();
        },
        .calendar_override_forms_input => |edit| {
            model.calendar.override_forms.apply(edit);
            model.calendar.captureOverrideInputTruncation();
        },
        .calendar_override_original_input => |edit| {
            model.calendar.override_original.apply(edit);
            model.calendar.captureOverrideInputTruncation();
        },
        .calendar_override_adjusted_input => |edit| {
            model.calendar.override_adjusted.apply(edit);
            model.calendar.captureOverrideInputTruncation();
        },
        .calendar_override_source_input => |edit| {
            model.calendar.override_source.apply(edit);
            model.calendar.captureOverrideInputTruncation();
        },
        .calendar_override_regions_input => |edit| {
            model.calendar.override_regions.apply(edit);
            model.calendar.captureOverrideInputTruncation();
        },
        .calendar_override_taxpayer_types_input => |edit| {
            model.calendar.override_taxpayer_types.apply(edit);
            model.calendar.captureOverrideInputTruncation();
        },
        .calendar_override_effective_from_input => |edit| {
            model.calendar.override_effective_from.apply(edit);
            model.calendar.captureOverrideInputTruncation();
        },
        .calendar_override_effective_until_input => |edit| {
            model.calendar.override_effective_until.apply(edit);
            model.calendar.captureOverrideInputTruncation();
        },
        .calendar_override_expires_at_input => |edit| {
            model.calendar.override_expires_at.apply(edit);
            model.calendar.captureOverrideInputTruncation();
        },
        .calendar_save_override => {
            model.calendar.saveOverride();
            refreshGlobalCalendar(model);
            refreshSelectedProfileCalendar(model);
        },
        .calendar_cancel_override => model.calendar.clearOverrideEditor(),
        .calendar_edit_override => |id| model.calendar.editOverride(id),
        .calendar_delete_override => |id| {
            model.calendar.deleteOverride(id);
            refreshGlobalCalendar(model);
            refreshSelectedProfileCalendar(model);
        },
        .calendar_non_working_date_input => |edit| {
            model.calendar.non_working_date.apply(edit);
            model.calendar.captureNonWorkingInputTruncation();
        },
        .calendar_non_working_name_input => |edit| {
            model.calendar.non_working_name.apply(edit);
            model.calendar.captureNonWorkingInputTruncation();
        },
        .calendar_non_working_kind_input => |edit| {
            model.calendar.non_working_kind.apply(edit);
            model.calendar.captureNonWorkingInputTruncation();
        },
        .calendar_non_working_source_input => |edit| {
            model.calendar.non_working_source.apply(edit);
            model.calendar.captureNonWorkingInputTruncation();
        },
        .calendar_non_working_regions_input => |edit| {
            model.calendar.non_working_regions.apply(edit);
            model.calendar.captureNonWorkingInputTruncation();
        },
        .calendar_save_non_working_day => {
            model.calendar.saveNonWorkingDay();
            refreshGlobalCalendar(model);
            refreshSelectedProfileCalendar(model);
        },
        .calendar_cancel_non_working_day => model.calendar.clearNonWorkingDayEditor(),
        .calendar_edit_non_working_day => |id| model.calendar.editNonWorkingDay(id),
        .calendar_delete_non_working_day => |id| {
            model.calendar.deleteNonWorkingDay(id);
            refreshGlobalCalendar(model);
            refreshSelectedProfileCalendar(model);
        },
        .show_background_jobs => model.backgroundTasksSection = .jobs,
        .show_background_logs => model.backgroundTasksSection = .logs,
        .multi_select_open => {
            model.globalDashboard.forms.openPicker();
        },
        .multi_select_close => model.globalDashboard.forms.closePicker(),
        .multi_select_query_changed => |edit| {
            model.globalDashboard.forms.applyQuery(edit);
        },
        .multi_select_toggle_option => |index| {
            _ = model.globalDashboard.toggleForm(index);
        },
        .multi_select_select_all_filtered => {
            model.setFilteredGlobalCalendarForms(true);
        },
        .multi_select_clear_all => {
            _ = model.globalDashboard.clearAllForms();
        },
        .profile_calendar_forms_open => {
            model.profileCalendarYearPickerVisible = false;
            model.profileCalendarYearQuery.clear();
            model.profileCalendarForms.openPicker();
        },
        .profile_calendar_forms_close => {
            model.profileCalendarForms.closePicker();
        },
        .profile_calendar_forms_query_changed => |edit| {
            model.profileCalendarForms.applyQuery(edit);
        },
        .profile_calendar_forms_toggle_option => |index| {
            if (model.profileCalendarFormActive(index)) {
                _ = model.profileCalendarForms.toggle(index);
            }
        },
        .profile_calendar_forms_select_all_filtered => {
            model.setFilteredProfileCalendarForms(true);
        },
        .profile_calendar_forms_clear_all => {
            _ = model.profileCalendarForms.clear();
        },
        .go_back => if (model.page == .profile_setup)
            closeProfileEditor(model)
        else
            closeTransient(model),
        .toggle_theme => {
            bumpSidebarActionEpoch(model);
            model.themePreference = if (effectiveColorScheme(model) == .dark) .light else .dark;
        },
        .set_theme_system => model.themePreference = .system,
        .set_theme_light => model.themePreference = .light,
        .set_theme_dark => model.themePreference = .dark,
        .expand_sidebar => {
            if (model.viewportClass == .desktop) {
                model.sidebarPreference = .expanded;
                model.sidebarOverlayOpen = false;
            } else {
                model.sidebarOverlayOpen = true;
            }
        },
        .collapse_sidebar => {
            model.sidebarPreference = .rail;
            model.sidebarOverlayOpen = false;
        },
        .hide_sidebar => {
            model.sidebarPreference = .hidden;
            model.sidebarOverlayOpen = false;
        },
        .open_sidebar_overlay => model.sidebarOverlayOpen = true,
        .close_sidebar_overlay => model.sidebarOverlayOpen = false,
        .toggle_navigation => {
            if (model.isConstrainedViewport()) {
                model.sidebarOverlayOpen = !model.sidebarOverlayOpen;
            } else if (model.sidebarPreference == .hidden) {
                model.sidebarPreference = if (model.viewportClass != .desktop)
                    .rail
                else
                    .expanded;
            } else {
                model.sidebarPreference = .hidden;
                model.sidebarOverlayOpen = false;
            }
        },
        .sidebar_profile_search_changed => |edit| {
            model.sidebarProfileSearchBuffer.apply(edit);
            // The store answers the search, so a taxpayer past the display
            // bound is still found by typing.
            model.taxProfiles.setSidebarQuery(
                model.sidebarProfileSearchBuffer.text(),
            );
        },
        .viewport_class_changed => |viewport_class| {
            const class_changed = model.viewportClass != viewport_class;
            model.viewportClass = viewport_class;
            model.viewportWidth = nominalWidthForClass(viewport_class);
            if (class_changed) model.libraryFilter.filter_picker_visible = false;
            if (!model.isConstrainedViewport()) {
                model.profileSubjectPickerVisible = false;
                model.profileClassificationPickerVisible = false;
                model.profileEoptPickerVisible = false;
            }
            if (viewport_class != .phone and viewport_class != .compact) {
                model.sidebarOverlayOpen = false;
            }
        },
        .viewport_width_changed => |width| {
            if (!std.math.isFinite(width) or width <= 0) return;
            model.viewportWidth = width;
            const viewport_class = viewportClassForWidth(width);
            const class_changed = model.viewportClass != viewport_class;
            model.viewportClass = viewport_class;
            if (class_changed) model.libraryFilter.filter_picker_visible = false;
            if (!model.isConstrainedViewport()) {
                model.profileSubjectPickerVisible = false;
                model.profileClassificationPickerVisible = false;
                model.profileEoptPickerVisible = false;
            }
            if (viewport_class != .phone and viewport_class != .compact) {
                model.sidebarOverlayOpen = false;
            }
        },
        .appearance_changed => |appearance| {
            model.systemColorScheme = appearance.color_scheme;
            model.reduceMotion = appearance.reduce_motion;
            model.highContrast = appearance.high_contrast;
        },
    }
}

fn refreshSelectedProfileFormSet(model: *Model) void {
    model.profileCalendarYearPickerVisible = false;
    model.profileCalendarYearQuery.clear();
    if (!model.taxProfiles.hasExplicitFormSet(model.calendar.selected_year)) {
        // The summaries are newest-first. When the current calendar year has
        // no yearly Forms Set, open on the latest configured year that is not
        // in the future instead of exposing a catalog fallback as active.
        for (model.taxProfiles.formSetSummaries()) |summary| {
            if (summary.tax_year <= model.calendarToday.year) {
                model.calendar.selected_year = summary.tax_year;
                break;
            }
        }
    }
    _ = model.taxProfiles.loadFormsForYear(model.calendar.selected_year);
    model.taxProfiles.refreshCalendarFormSet(
        model.calendar.selected_year,
    ) catch |err| model.calendar.setError(err);
    model.taxProfiles.refreshDraftSummariesForYear(
        model.calendar.selected_year,
    ) catch |err| model.calendar.setError(err);
    refreshProfileFormLaunchAssessments(model);
    syncSelectedProfileCalendar(model);
    reconcileProfileCalendarForms(model);
}

fn reconcileProfileCalendarForms(model: *Model) void {
    model.profileCalendarForms.closePicker();
    for (0..form_catalog.registry_count) |index| {
        _ = model.profileCalendarForms.set(
            index,
            model.profileCalendarFormActive(index),
        );
    }
}

fn catalogFormRevision(
    definition: *const form_catalog.FormDefinition,
) []const u8 {
    return definition.revision orelse forms_set_resolver.calendar_only_revision;
}

const ProfileDeadlineAvailabilityContext = struct {
    definition: *const form_catalog.FormDefinition,
    filing: form_period.FilingPeriod,
    occurrence_date: ?forms_set_resolver.Date = null,
};

fn catalogDefinitionForDeadline(
    form_code: []const u8,
) ?*const form_catalog.FormDefinition {
    const catalog_code = if (formCodesEquivalent(form_code, "1604C") or
        formCodesEquivalent(form_code, "1604F"))
        "1604CF"
    else
        form_code;
    for (&form_catalog.forms) |*definition| {
        if (formCodesEquivalent(definition.code, catalog_code)) {
            return definition;
        }
    }
    return null;
}

fn resolverDateFromCalendar(
    date: calendar_domain.Date,
) ?forms_set_resolver.Date {
    if (date.year < 1 or date.year > 9999) return null;
    return forms_set_resolver.Date.init(
        @intCast(date.year),
        date.month,
        date.day,
    ) catch null;
}

/// Converts a concrete calendar obligation into the exact filing key used by
/// Forms Set applicability. Event-based calendar rules do not currently retain
/// a separate triggering transaction date, so their original unadjusted date
/// is the stable occurrence date available to both on-screen and ICS paths.
fn profileDeadlineAvailabilityContext(
    deadline: *const calendar_ui.DeadlineRow,
) ?ProfileDeadlineAvailabilityContext {
    const definition = catalogDefinitionForDeadline(deadline.form_code) orelse
        return null;
    const filing: form_period.FilingPeriod = switch (deadline.period) {
        .monthly => |period| blk: {
            if (period.taxable_year < 1 or period.taxable_year > 9999) {
                return null;
            }
            break :blk .{ .monthly = .{
                .tax_year = @intCast(period.taxable_year),
                .month = period.month,
            } };
        },
        .quarterly => |period| blk: {
            if (period.taxable_year < 1 or period.taxable_year > 9999) {
                return null;
            }
            break :blk .{ .quarterly = .{
                .tax_year = @intCast(period.taxable_year),
                .quarter = period.quarter,
            } };
        },
        .annual => |period| blk: {
            if (period.taxable_year < 1 or period.taxable_year > 9999) {
                return null;
            }
            break :blk .{ .annual = .{
                .tax_year = @intCast(period.taxable_year),
            } };
        },
        .event_based => blk: {
            if (definition.cadence != .on_demand) return null;
            const occurrence = resolverDateFromCalendar(
                deadline.original_deadline,
            ) orelse return null;
            break :blk .{ .on_demand = .{
                .tax_year = occurrence.year,
                .occurrence = 1,
            } };
        },
    };
    return .{
        .definition = definition,
        .filing = filing,
        .occurrence_date = switch (filing) {
            .on_demand => resolverDateFromCalendar(deadline.original_deadline),
            .monthly, .quarterly, .annual => null,
        },
    };
}

fn currentOccurrenceDate(
    model: *const Model,
    tax_year: u16,
) ?forms_set_resolver.Date {
    if (model.calendarToday.year < 1 or
        model.calendarToday.year > 9999 or
        @as(u16, @intCast(model.calendarToday.year)) != tax_year) return null;
    return forms_set_resolver.Date.init(
        @intCast(model.calendarToday.year),
        model.calendarToday.month,
        model.calendarToday.day,
    ) catch null;
}

fn formAvailableForFiling(
    model: *const Model,
    definition: *const form_catalog.FormDefinition,
    filing: form_period.FilingPeriod,
    occurrence_date: ?forms_set_resolver.Date,
) bool {
    const query: forms_set_resolver.FilingQuery = .{
        .form = .{
            .form_code = definition.code,
            .form_revision = catalogFormRevision(definition),
        },
        .period = filing,
        .occurrence_date = occurrence_date,
    };
    const on = forms_set_resolver.applicabilityDate(query) catch return false;
    if (!model.taxProfiles.formAvailableOnDate(
        definition.code,
        catalogFormRevision(definition),
        on,
    )) return false;
    if (!std.mem.eql(u8, definition.code, "2551Q")) return true;
    const quarter = filing.quarter() orelse return true;
    const profile_id = model.taxProfiles.selectedProfileDomainId() orelse
        return false;
    const store = model.taxProfiles.store orelse return false;
    const stream: annual_income_tax_election.StreamKey = .{
        .profile_id = profile_id,
        .tax_year = filing.taxYear(),
    };
    const current = store.resolveAnnualIncomeTaxElection(stream) catch
        return false;
    return annual_income_tax_election.percentageTaxReturnRequired(
        if (current) |*event| event else null,
        quarter,
    ) catch false;
}

fn profileBrowseAvailabilityYear(model: *const Model) i32 {
    if (model.profileTaxFormsActive() and model.yearWorkspaceContextActive()) {
        return model.taxProfiles.workspaceYear() orelse
            model.calendar.selected_year;
    }
    return model.calendar.selected_year;
}

fn profileFormActivationLabel(
    arena: std.mem.Allocator,
    period: ?profile_model.EffectivePeriod,
) []const u8 {
    const active = period orelse return "Activation interval unavailable";
    var from_buffer: [10]u8 = undefined;
    const from = active.from.writeIso(&from_buffer);
    if (active.until) |until_date| {
        var until_buffer: [10]u8 = undefined;
        return std.fmt.allocPrint(
            arena,
            "Active {s} through {s}",
            .{ from, until_date.writeIso(&until_buffer) },
        ) catch "Activation interval unavailable";
    }
    return std.fmt.allocPrint(
        arena,
        "Active from {s}",
        .{from},
    ) catch "Activation interval unavailable";
}

fn taxFormProfileStream(
    profile_id: profile_model.ProfileId,
    definition: *const form_catalog.FormDefinition,
    tax_year: u16,
) ?tax_form_profile_domain.StreamKey {
    if (definition.tax_form_profile.mode != .setup) return null;
    const revision = definition.revision orelse return null;
    return .{
        .profile_id = profile_id,
        .tax_year = tax_year,
        .form_code = tax_form_profile_domain.FormCode.parse(
            definition.code,
        ) catch return null,
        .form_revision = tax_form_profile_domain.FormRevision.parse(
            revision,
        ) catch return null,
    };
}

fn composedFilingEffectiveOn(
    filing: form_period.FilingPeriod,
) !profile_model.Date {
    try filing.validate();
    return switch (filing) {
        .monthly => |period| monthEndDate(
            period.tax_year,
            period.month,
        ),
        .quarterly => |period| monthEndDate(
            period.tax_year,
            period.quarter * 3,
        ),
        .annual => |period| profile_model.Date.init(
            period.tax_year,
            12,
            31,
        ),
        // On-demand filings carry an occurrence ordinal rather than a
        // transaction date. The production pilot is quarterly 2551Q; callers
        // must not invent a date for another form at this boundary.
        .on_demand => error.FilingContextDateUnavailable,
    };
}

/// Loads every persistence owner needed by the composed read model, invokes
/// the pure composer while those owners are alive, then copies only fixed
/// storage into the returned runtime cache. No pointer in this result borrows
/// SQLite rows, allocator-owned arrays, or the transient composed view.
fn loadRuntimeComposedSnapshot(
    model: *Model,
    definition: *const form_catalog.FormDefinition,
    profile_id: profile_model.ProfileId,
    tax_year: u16,
    filing: form_period.FilingPeriod,
    tax_form_profile_state: ?*const tax_form_profile_ui.State,
) !RuntimeComposedSnapshot {
    if (filing.taxYear() != tax_year) return error.InvalidTaxYear;
    const effective_on = try composedFilingEffectiveOn(filing);
    const allocator = model.taxProfiles.allocator orelse
        return error.ProfileStoreUnavailable;
    const store = model.taxProfiles.store orelse
        return error.ProfileStoreUnavailable;

    var base = (try profile_persistence.loadEffectiveRevision(
        store,
        allocator,
        profile_id,
        effective_on,
    )) orelse return error.ProfileRevisionUnavailable;
    defer base.deinit(allocator);

    // The year projection retains earlier confirmed activities that ended
    // before the filing date. `compose` still resolves obligations and the
    // primary activity as of `effective_on`, while business commencement is
    // derived from the earliest confirmed historical activity.
    var normalized_registration = try profile_persistence
        .loadRegistrationAggregateForYear(
        store,
        allocator,
        profile_id,
        tax_year,
    );
    defer normalized_registration.deinit(allocator);

    var annual_history: ?profile_persistence
        .OwnedAnnualIncomeTaxElectionHistory = null;
    defer if (annual_history) |*owned| owned.deinit(allocator);
    if (form_catalog.consumesTaxpayerYearSetting(
        definition,
        .income_tax_rate_election,
    )) {
        annual_history = try profile_persistence
            .loadAnnualIncomeTaxElectionHistory(
            store,
            allocator,
            .{ .profile_id = profile_id, .tax_year = tax_year },
        );
    }

    const composed = try composed_tax_profile.compose(.{
        .profile_id = profile_id,
        .tax_year = tax_year,
        .form_code = definition.code,
        .form_revision = definition.revision,
        .base_revision = &base.revision,
        .registration_aggregate = &normalized_registration.aggregate,
        .annual_income_tax_election = if (annual_history) |*owned|
            &owned.history
        else
            null,
        .tax_form_profile_state = tax_form_profile_state,
        .filing_period = filing,
    });

    return .{
        .loaded = true,
        .readiness = composed.readiness,
        .current_annual = if (composed.annual_income_tax_election.current) |event|
            event.*
        else
            null,
        .filing_context = composed.filing_context,
        .ready_for_new_filing = composed.readyForNewFiling(),
    };
}

fn inheritedReadinessFromComposed(
    definition: *const form_catalog.FormDefinition,
    snapshot: *const RuntimeComposedSnapshot,
) tax_form_profile_ui.InheritedReadiness {
    var required_count: u16 = 0;
    for (definition.fields) |field_definition| {
        if (field_definition.provenance == .profile and
            field_definition.role == .filer and
            field_definition.profile_presence == .required)
        {
            required_count +|= 1;
        }
    }
    if (!snapshot.loaded) return .{
        .required_count = @max(required_count, 1),
        .invalid_count = 1,
    };
    const layer = snapshot.readiness.base_tax_profile;
    return switch (layer.status) {
        .ready, .locked, .not_applicable => .{
            .required_count = required_count,
        },
        .unresolved => .{
            .required_count = required_count,
            .missing_count = @intCast(@min(
                layer.missingKeys().len,
                required_count,
            )),
        },
        .reserved, .review_required, .invalid => .{
            .required_count = @max(required_count, 1),
            .invalid_count = 1,
        },
    };
}

fn taxFormProfileCardStateFromComposed(
    definition: *const form_catalog.FormDefinition,
    snapshot: *const RuntimeComposedSnapshot,
) TaxFormProfileCardState {
    if (!snapshot.loaded) return .error_loading;
    switch (snapshot.readiness.base_tax_profile.status) {
        .ready, .not_applicable, .locked => {},
        .unresolved => return .needs_tax_profile,
        .reserved, .review_required, .invalid => return .needs_tax_profile,
    }
    switch (snapshot.readiness.registration_bindings.status) {
        .ready, .not_applicable, .locked => {},
        .unresolved => return .needs_registration,
        .review_required, .invalid => return .requires_review,
        .reserved => return .needs_registration,
    }
    switch (snapshot.readiness.annual_income_tax_election.status) {
        .not_applicable, .locked => {},
        .ready => if (!snapshot.ready_for_new_filing) {
            return .needs_year_settings;
        },
        .unresolved => return .needs_year_settings,
        .reserved => return .year_settings_reserved,
        .review_required, .invalid => return .year_settings_require_review,
    }
    switch (snapshot.readiness.form_specific_values.status) {
        .ready, .not_applicable, .locked => {},
        .unresolved, .reserved => return .needs_setup,
        .review_required, .invalid => return .requires_review,
    }
    switch (snapshot.readiness.filing_context.status) {
        .ready, .not_applicable, .locked => {},
        .unresolved, .reserved => return .needs_filing_context,
        .review_required, .invalid => return .error_loading,
    }
    return if (definition.tax_form_profile.mode == .no_setup)
        .inherited_only_ready
    else
        .ready;
}

fn launchAssessmentForViewedDate(
    model: *const Model,
    definition: *const form_catalog.FormDefinition,
    index: usize,
    viewed_on: profile_model.Date,
) form_ui.LaunchAssessment {
    const slot: usize = switch (definition.cadence) {
        .monthly => viewed_on.month - 1,
        .quarterly => (viewed_on.month - 1) / 3,
        .annual, .on_demand => 0,
    };
    if (slot < model.profilePeriodLaunchAssessmentsReady[index].len and
        model.profilePeriodLaunchAssessmentsReady[index][slot] and
        model.profilePeriodAvailabilityReady[index][slot] and
        model.profilePeriodAvailability[index][slot])
    {
        return model.profilePeriodLaunchAssessments[index][slot];
    }

    // A date-effective Forms Set interval can begin or end inside a filing
    // period. Prefer the latest filing slot that the same availability cache
    // confirms rather than silently falling back to a different tax year or
    // an arbitrary catalog default.
    var candidate = model.profilePeriodLaunchAssessmentsReady[index].len;
    while (candidate > 0) {
        candidate -= 1;
        if (!model.profilePeriodLaunchAssessmentsReady[index][candidate] or
            !model.profilePeriodAvailabilityReady[index][candidate] or
            !model.profilePeriodAvailability[index][candidate]) continue;
        return model.profilePeriodLaunchAssessments[index][candidate];
    }
    return model.profileFormLaunchAssessments[index];
}

fn inheritedReadinessForForm(
    model: *const Model,
    definition: *const form_catalog.FormDefinition,
    index: usize,
    viewed_on: profile_model.Date,
) tax_form_profile_ui.InheritedReadiness {
    var required_count: u16 = 0;
    for (definition.fields) |field_definition| {
        if (field_definition.provenance == .profile and
            field_definition.profile_presence == .required)
        {
            required_count +|= 1;
        }
    }
    const assessment = launchAssessmentForViewedDate(
        model,
        definition,
        index,
        viewed_on,
    );
    return switch (assessment.status) {
        .needs_profile => .{
            .required_count = @max(required_count, assessment.issue_count),
            .missing_count = assessment.issue_count,
        },
        .profile_not_eligible, .unavailable => .{
            .required_count = @max(required_count, 1),
            .invalid_count = 1,
        },
        .ready_new, .ready_resume, .needs_activity_selection => .{
            .required_count = required_count,
        },
    };
}

const TaxpayerYearFormReadiness = enum {
    not_required,
    missing,
    requires_review,
    ready,
};

fn taxpayerYearReadinessForForm(
    definition: *const form_catalog.FormDefinition,
    revision: ?*const taxpayer_year_settings_domain.Revision,
) TaxpayerYearFormReadiness {
    const needs_rate = form_catalog.consumesTaxpayerYearSetting(
        definition,
        .income_tax_rate_election,
    );
    const needs_deduction = form_catalog.consumesTaxpayerYearSetting(
        definition,
        .deduction_method,
    );
    if (!needs_rate and !needs_deduction) return .not_required;
    const saved = revision orelse return .missing;
    if (saved.review_state != .confirmed) return .requires_review;
    const election_value = saved.find(.income_tax_rate_election) orelse
        return .missing;
    const election = switch (election_value.*) {
        .income_tax_rate_election => |value| value,
        .deduction_method => return .missing,
    };
    if (needs_deduction and election == .graduated and
        saved.find(.deduction_method) == null)
    {
        return .missing;
    }
    return .ready;
}

const LaunchTaxFormProfileBindings = struct {
    state: TaxFormProfileCardState = .ready,
    income_tax_rate_election: ?taxpayer_year_settings_domain.IncomeTaxRateElection = null,
    annual_election_event: ?annual_income_tax_election.Event = null,
    spouse_profile_id: ?profile_model.ProfileId = null,
    filer_activity_id: ?profile_model.BusinessActivityId = null,
    spouse_activity_id: ?profile_model.BusinessActivityId = null,
};

fn loadActivityIdForAnchor(
    model: *Model,
    profile_id: profile_model.ProfileId,
    anchor_id: []const u8,
    on: profile_model.Date,
) !?profile_model.BusinessActivityId {
    const allocator = model.taxProfiles.allocator orelse
        return error.ProfileStoreUnavailable;
    const store = model.taxProfiles.store orelse
        return error.ProfileStoreUnavailable;

    var registration = try profile_persistence.loadRegistrationAggregateOn(
        store,
        allocator,
        profile_id,
        on,
    );
    defer registration.deinit(allocator);
    var has_confirmed_registration_activity = false;
    for (registration.business_activities) |*activity| {
        if (!activity.metadata.review.isConfirmed() or
            !activity.metadata.isEffective(on))
        {
            continue;
        }
        has_confirmed_registration_activity = true;
        if (!std.mem.eql(
            u8,
            activity.anchor_id.asSlice(),
            anchor_id,
        )) continue;
        return try profile_model.BusinessActivityId.parse(
            activity.anchor_id.asSlice(),
        );
    }
    // Once v16 Registration has confirmed activities for this exact date it
    // owns the collection. A stale legacy anchor must not be revived from an
    // older Profile Revision merely because it has the same text identifier.
    if (has_confirmed_registration_activity) return null;

    var date_buffer: [10]u8 = undefined;
    var owned = (try store.getEffectiveRevision(
        allocator,
        profile_id.asSlice(),
        on.writeIso(&date_buffer),
    )) orelse return null;
    defer owned.deinit(allocator);
    for (owned.business_activities) |activity| {
        if (!std.mem.eql(u8, activity.anchor_id, anchor_id)) continue;
        const effective_from = try profile_model.Date.parseIso(
            activity.effective_from,
        );
        const effective_until = if (activity.effective_until) |until|
            try profile_model.Date.parseIso(until)
        else
            null;
        const effective = try profile_model.EffectivePeriod.init(
            effective_from,
            effective_until,
        );
        if (!effective.contains(on)) continue;
        return try profile_model.BusinessActivityId.parse(activity.id);
    }
    return null;
}

fn taxFormProfileLookupProfileSubjectKind(
    context: *anyopaque,
    profile_id: profile_model.ProfileId,
    on: profile_model.Date,
) !?profile_model.SubjectKind {
    const model: *Model = @ptrCast(@alignCast(context));
    const allocator = model.taxProfiles.allocator orelse
        return error.ProfileStoreUnavailable;
    const store = model.taxProfiles.store orelse
        return error.ProfileStoreUnavailable;
    var date_buffer: [10]u8 = undefined;
    var owned = (try store.getEffectiveRevision(
        allocator,
        profile_id.asSlice(),
        on.writeIso(&date_buffer),
    )) orelse return null;
    defer owned.deinit(allocator);
    return switch (owned.subject.kind()) {
        .individual => .individual,
        .sole_proprietor => .sole_proprietor,
        .corporation => .corporation,
        .partnership => .partnership,
        .cooperative => .cooperative,
        .estate => .estate,
        .trust => .trust,
        .other_legal_entity => .other_legal_entity,
    };
}

fn taxFormProfileLookupBusinessActivity(
    context: *anyopaque,
    owner_profile_id: profile_model.ProfileId,
    anchor_id: []const u8,
    on: profile_model.Date,
) !?profile_model.BusinessActivityId {
    const model: *Model = @ptrCast(@alignCast(context));
    return loadActivityIdForAnchor(model, owner_profile_id, anchor_id, on);
}

fn taxFormProfileLookupRegistrationObligation(
    context: *anyopaque,
    owner_profile_id: profile_model.ProfileId,
    semantic_key: form_catalog.TaxFormProfileSemanticKey,
    anchor_id: []const u8,
    on: profile_model.Date,
) !bool {
    const model: *Model = @ptrCast(@alignCast(context));
    const allocator = model.taxProfiles.allocator orelse
        return error.ProfileStoreUnavailable;
    const store = model.taxProfiles.store orelse
        return error.ProfileStoreUnavailable;
    if (semantic_key == .special_rate_obligation_anchor_id) {
        // This generated key is backed by the stable legacy special-rate
        // registration-fact anchor. The v16 normalized special-law/treaty
        // projection intentionally has no anchor and therefore cannot be
        // substituted for a different saved identifier.
        var date_buffer: [10]u8 = undefined;
        var owned = (try store.getEffectiveRevision(
            allocator,
            owner_profile_id.asSlice(),
            on.writeIso(&date_buffer),
        )) orelse return false;
        defer owned.deinit(allocator);
        for (owned.registration_facts) |fact| {
            if (!std.mem.eql(u8, fact.anchor_id, anchor_id)) continue;
            const effective = try profile_model.EffectivePeriod.init(
                try profile_model.Date.parseIso(fact.effective_from),
                if (fact.effective_until) |until|
                    try profile_model.Date.parseIso(until)
                else
                    null,
            );
            if (!effective.contains(on)) continue;
            switch (fact.value) {
                .special_rate_basis => return true,
                else => return false,
            }
        }
        return false;
    }

    var registration = try profile_persistence.loadRegistrationAggregateOn(
        store,
        allocator,
        owner_profile_id,
        on,
    );
    defer registration.deinit(allocator);
    const parsed = try profile_registration.ObligationAnchorId.parse(anchor_id);
    const resolved = registration.aggregate.resolveObligation(
        parsed,
        on,
    ) catch |err| switch (err) {
        error.MissingObligationAnchor => return false,
        else => return err,
    };
    return resolved.confirmed != null;
}

fn resolveTaxFormProfileBindings(
    model: *Model,
    definition: *const form_catalog.FormDefinition,
    profile_id: profile_model.ProfileId,
    on: profile_model.Date,
    saved_revision: ?*const tax_form_profile_domain.Revision,
    activity_selection_required: bool,
) !tax_form_profile_binding_resolver.Result {
    return tax_form_profile_binding_resolver.resolve(.{
        .form = definition,
        .filer_profile_id = profile_id,
        .on = on,
        .saved_revision = saved_revision,
        .activity_selection_required = activity_selection_required,
    }, .{
        .context = model,
        .profile_subject_kind_fn = taxFormProfileLookupProfileSubjectKind,
        .business_activity_fn = taxFormProfileLookupBusinessActivity,
        .registration_obligation_fn = taxFormProfileLookupRegistrationObligation,
    });
}

fn loadSavedTaxFormProfileBindings(
    model: *Model,
    definition: *const form_catalog.FormDefinition,
    profile_id: profile_model.ProfileId,
    tax_year: u16,
    on: profile_model.Date,
    activation_period: ?tax_form_profile_domain.EffectivePeriod,
    activity_selection_required: bool,
) !tax_form_profile_binding_resolver.Result {
    if (definition.tax_form_profile.mode != .setup) {
        return resolveTaxFormProfileBindings(
            model,
            definition,
            profile_id,
            on,
            null,
            activity_selection_required,
        );
    }
    const allocator = model.taxProfiles.allocator orelse
        return error.ProfileStoreUnavailable;
    const store = model.taxProfiles.store orelse
        return error.ProfileStoreUnavailable;
    const stream = taxFormProfileStream(
        profile_id,
        definition,
        tax_year,
    ) orelse return error.TaxFormProfileStreamUnavailable;
    var history = try profile_persistence.loadTaxFormProfileHistory(
        store,
        allocator,
        stream,
    );
    defer history.deinit(allocator);
    const expected_activation = activation_period orelse
        return error.TaxFormProfileActivationUnavailable;
    var saved_revision: ?*const tax_form_profile_domain.Revision = null;
    for (history.history.revisions) |*candidate| {
        if (!candidate.effective.eql(expected_activation) or
            !candidate.effectiveOn(on)) continue;
        if (saved_revision == null or
            candidate.sequence > saved_revision.?.sequence)
        {
            saved_revision = candidate;
        }
    }
    return resolveTaxFormProfileBindings(
        model,
        definition,
        profile_id,
        on,
        saved_revision,
        activity_selection_required,
    );
}

fn refreshOpenedTaxFormProfileBindingReadiness(model: *Model) void {
    if (!model.taxFormProfilePage.active) return;
    const identity = model.taxFormProfilePage.viewedIdentity() orelse return;
    const index = model.taxFormProfileFormIndex orelse return;
    if (index >= form_catalog.registry_count) return;
    const viewed_on = taxFormProfileViewedOn(model) orelse return;
    const definition = &form_catalog.forms[index];
    const launch = launchAssessmentForViewedDate(
        model,
        definition,
        index,
        viewed_on,
    );
    const bindings = loadSavedTaxFormProfileBindings(
        model,
        definition,
        identity.profile_id,
        identity.tax_year,
        viewed_on,
        model.taxFormProfilePage.activationPeriod(),
        launch.status == .needs_activity_selection,
    ) catch null;
    model.taxFormProfilePage.setSavedBindingsResolved(
        bindings != null and bindings.?.status == .ready,
    ) catch {};
}

fn loadLaunchTaxFormProfileBindings(
    model: *Model,
    definition: *const form_catalog.FormDefinition,
    form_index: usize,
    profile_id: profile_model.ProfileId,
    tax_year: u16,
    on: profile_model.Date,
    launch: form_ui.LaunchAssessment,
) LaunchTaxFormProfileBindings {
    const allocator = model.taxProfiles.allocator orelse
        return .{ .state = .error_loading };
    const store = model.taxProfiles.store orelse
        return .{ .state = .error_loading };
    var result: LaunchTaxFormProfileBindings = .{};

    if (std.mem.eql(u8, definition.code, "2551Q")) {
        const filing_quarter: u8 = @intCast((on.month - 1) / 3 + 1);
        const filing: form_period.FilingPeriod = .{ .quarterly = .{
            .tax_year = tax_year,
            .quarter = filing_quarter,
        } };
        const snapshot = loadRuntimeComposedSnapshot(
            model,
            definition,
            profile_id,
            tax_year,
            filing,
            null,
        ) catch return .{ .state = .error_loading };
        const composed_state = taxFormProfileCardStateFromComposed(
            definition,
            &snapshot,
        );
        switch (composed_state) {
            .ready, .inherited_only_ready => {},
            else => return .{ .state = composed_state },
        }
        const current = snapshot.current_annual orelse {
            // Item 13 is not applicable to a non-individual filer. The
            // composed annual layer is the authority for that distinction.
            if (snapshot.readiness.annual_income_tax_election.status ==
                .not_applicable) return result;
            return .{ .state = .needs_year_settings };
        };
        const item_13 = annual_income_tax_election.project2551qItem13(
            &current,
            tax_year,
            filing_quarter,
        ) catch |err| return switch (err) {
            error.ElectionUnresolved,
            error.ElectionNotConfirmedForLaterQuarter,
            => .{ .state = .needs_year_settings },
            error.ReviewRequired => .{
                .state = .year_settings_require_review,
            },
            error.FilingBeforeBusinessCommencement => .{
                .state = .unavailable,
            },
            else => .{ .state = .error_loading },
        };
        result.annual_election_event = current;
        // Item 13 belongs only to the initial applicable quarter. Later
        // quarters retain the confirmed annual event for UI/calculation
        // binding, while their official return transaction receives no
        // Item 13 value.
        if (item_13.included()) {
            result.income_tax_rate_election = switch (item_13.choice()) {
                .graduated => .graduated,
                .eight_percent => .eight_percent,
            };
        }
    } else if (taxpayerYearReadinessForForm(definition, null) != .not_required) {
        const stream: taxpayer_year_settings_domain.StreamKey = .{
            .profile_id = profile_id,
            .tax_year = tax_year,
        };
        var history = profile_persistence.loadTaxpayerYearHistory(
            store,
            allocator,
            stream,
        ) catch return .{ .state = .error_loading };
        defer history.deinit(allocator);
        const revision = history.history.effectiveOn(on) catch |err| {
            return .{ .state = if (err == error.NoEffectiveRevision)
                .needs_year_settings
            else
                .error_loading };
        };
        switch (taxpayerYearReadinessForForm(definition, revision)) {
            .not_required, .ready => {},
            .missing => return .{ .state = .needs_year_settings },
            .requires_review => return .{
                .state = .year_settings_require_review,
            },
        }
        if (revision.find(.income_tax_rate_election)) |setting| {
            result.income_tax_rate_election = switch (setting.*) {
                .income_tax_rate_election => |value| value,
                .deduction_method => return .{ .state = .error_loading },
            };
        }
    }

    const bindings = loadSavedTaxFormProfileBindings(
        model,
        definition,
        profile_id,
        tax_year,
        on,
        if (definition.tax_form_profile.mode == .setup) blk: {
            const activation = profileFormActivationContext(
                model,
                profile_id,
                definition,
                tax_year,
                on,
            ) orelse return .{ .state = .error_loading };
            break :blk activation.effective;
        } else null,
        launch.status == .needs_activity_selection,
    ) catch return .{ .state = .error_loading };
    switch (bindings.status) {
        .ready => {
            result.spouse_profile_id = bindings.spouse_profile_id;
            result.filer_activity_id = bindings.filer_activity_id;
            result.spouse_activity_id = bindings.spouse_activity_id;
        },
        .needs_setup => result.state = .needs_setup,
        .requires_review => result.state = .requires_review,
    }
    _ = form_index;
    return result;
}

fn refreshTaxFormProfileCardStates(model: *Model) void {
    model.taxFormProfileCardStatesReady = false;
    @memset(&model.taxFormProfileCardStates, .unavailable);
    @memset(&model.taxFormProfileHistoryAvailable, false);
    @memset(&model.profileFormActiveSegments, null);
    const allocator = model.taxProfiles.allocator orelse return;
    const store = model.taxProfiles.store orelse return;
    const profile_id = model.taxProfiles.selectedProfileDomainId() orelse
        return;
    const year_value = model.profileFormAvailabilityYear;
    if (year_value < 1 or year_value > 9999) return;
    const tax_year: u16 = @intCast(year_value);

    var taxpayer_year_load_failed = false;
    var taxpayer_year_history: ?profile_persistence.OwnedTaxpayerYearHistory = null;
    defer if (taxpayer_year_history) |*owned| owned.deinit(allocator);
    if (taxpayerYearConsumption(model).hasActiveConsumers()) {
        const stream: taxpayer_year_settings_domain.StreamKey = .{
            .profile_id = profile_id,
            .tax_year = tax_year,
        };
        taxpayer_year_history = profile_persistence.loadTaxpayerYearHistory(
            store,
            allocator,
            stream,
        ) catch blk: {
            taxpayer_year_load_failed = true;
            break :blk null;
        };
    }

    for (&form_catalog.forms, 0..) |*definition, index| {
        if (!model.profileFormAnyPeriodActive[index]) {
            if (definition.tax_form_profile.mode == .setup) {
                const stream = taxFormProfileStream(
                    profile_id,
                    definition,
                    tax_year,
                ) orelse continue;
                var history = profile_persistence.loadTaxFormProfileHistory(
                    store,
                    allocator,
                    stream,
                ) catch continue;
                defer history.deinit(allocator);
                model.taxFormProfileHistoryAvailable[index] =
                    history.history.revisions.len != 0;
            }
            continue;
        }
        const activation_context = profileFormActivationContext(
            model,
            profile_id,
            definition,
            tax_year,
            null,
        ) orelse {
            model.taxFormProfileCardStates[index] = .error_loading;
            continue;
        };
        model.profileFormActiveSegments[index] = activation_context.effective;
        if (definition.status == .calendar_only or
            definition.tax_form_profile.mode == .calendar_only)
        {
            model.taxFormProfileCardStates[index] = .calendar_only;
            continue;
        }
        if (std.mem.eql(u8, definition.code, "2551Q")) {
            const quarter = selectedFormQuarter(model, definition.code);
            const filing: form_period.FilingPeriod = .{ .quarterly = .{
                .tax_year = tax_year,
                .quarter = quarter,
            } };
            const snapshot = loadRuntimeComposedSnapshot(
                model,
                definition,
                profile_id,
                tax_year,
                filing,
                null,
            ) catch {
                model.taxFormProfileCardStates[index] = .error_loading;
                continue;
            };
            model.taxFormProfileCardStates[index] =
                taxFormProfileCardStateFromComposed(
                    definition,
                    &snapshot,
                );
            continue;
        }
        const inherited = inheritedReadinessForForm(
            model,
            definition,
            index,
            activation_context.viewed_on,
        );
        if (!inherited.ready()) {
            model.taxFormProfileCardStates[index] = .needs_tax_profile;
            continue;
        }
        if (taxpayer_year_load_failed and
            taxpayerYearReadinessForForm(definition, null) != .not_required)
        {
            model.taxFormProfileCardStates[index] = .error_loading;
            continue;
        }
        var taxpayer_year_revision: ?*const taxpayer_year_settings_domain.Revision = null;
        if (taxpayer_year_history) |*owned| {
            taxpayer_year_revision = owned.history.effectiveOn(
                activation_context.viewed_on,
            ) catch |err| blk: {
                if (err != error.NoEffectiveRevision) {
                    taxpayer_year_load_failed = true;
                }
                break :blk null;
            };
        }
        if (taxpayer_year_load_failed and
            taxpayerYearReadinessForForm(definition, null) != .not_required)
        {
            model.taxFormProfileCardStates[index] = .error_loading;
            continue;
        }
        switch (taxpayerYearReadinessForForm(
            definition,
            taxpayer_year_revision,
        )) {
            .not_required, .ready => {},
            .missing => {
                model.taxFormProfileCardStates[index] = .needs_year_settings;
                continue;
            },
            .requires_review => {
                model.taxFormProfileCardStates[index] =
                    .year_settings_require_review;
                continue;
            },
        }
        if (definition.tax_form_profile.mode == .no_setup) {
            model.taxFormProfileCardStates[index] = .inherited_only_ready;
            continue;
        }
        const stream = taxFormProfileStream(
            profile_id,
            definition,
            tax_year,
        ) orelse {
            model.taxFormProfileCardStates[index] = .error_loading;
            continue;
        };
        var history = profile_persistence.loadTaxFormProfileHistory(
            store,
            allocator,
            stream,
        ) catch {
            model.taxFormProfileCardStates[index] = .error_loading;
            continue;
        };
        defer history.deinit(allocator);
        model.taxFormProfileHistoryAvailable[index] =
            history.history.revisions.len != 0;
        var latest: ?*const tax_form_profile_domain.Revision = null;
        for (history.history.revisions) |*revision| {
            if (!revision.effective.eql(activation_context.effective) or
                !revision.effectiveOn(activation_context.viewed_on)) continue;
            if (latest == null or revision.sequence > latest.?.sequence) {
                latest = revision;
            }
        }
        const viewed_launch = launchAssessmentForViewedDate(
            model,
            definition,
            index,
            activation_context.viewed_on,
        );
        const bindings = resolveTaxFormProfileBindings(
            model,
            definition,
            profile_id,
            activation_context.viewed_on,
            latest,
            viewed_launch.status == .needs_activity_selection,
        ) catch {
            model.taxFormProfileCardStates[index] = .error_loading;
            continue;
        };
        model.taxFormProfileCardStates[index] = switch (bindings.status) {
            .ready => .ready,
            .needs_setup => .needs_setup,
            .requires_review => .requires_review,
        };
    }
    model.taxFormProfileCardStatesReady = true;
}

fn refreshProfileFormLaunchAssessments(model: *Model) void {
    model.profileFormLaunchAssessmentsReady = false;
    model.profileFormAvailabilityYear = 0;
    @memset(&model.profileFormAnyPeriodActive, false);
    @memset(&model.profileDeadlineLaunchAssessmentsReady, false);
    for (&model.profilePeriodLaunchAssessmentsReady) |*row| {
        row.* = [_]bool{false} ** 12;
    }
    for (&model.profilePeriodAvailability) |*row| {
        row.* = [_]bool{false} ** 12;
    }
    for (&model.profilePeriodAvailabilityReady) |*row| {
        row.* = [_]bool{false} ** 12;
    }
    _ = model.taxProfiles.selectedProfileDomainId() orelse return;
    const can_assess_launch = model.formProfiles.allocator != null and
        model.formProfiles.store != null;
    const year_value = profileBrowseAvailabilityYear(model);
    if (year_value < 1 or year_value > 9999) return;
    const year: u16 = @intCast(year_value);
    model.profileFormAvailabilityYear = year_value;
    for (&form_catalog.forms, 0..) |*definition, index| {
        model.profileFormLaunchAssessments[index] = .{};
        var captured_first_active_assessment = false;
        for (0..12) |slot| {
            const filing = if (definition.cadence == .on_demand)
                (if (slot == 0)
                    newOnDemandAssessmentPeriod(
                        model.taxProfiles.draftSummaries(),
                        definition.code,
                        year,
                    )
                else
                    onDemandDraftPeriodForSlot(
                        model.taxProfiles.draftSummaries(),
                        definition.code,
                        year,
                        slot,
                    )) orelse break
            else
                libraryPeriodForSlot(definition, year, slot) orelse break;
            const occurrence_date = switch (filing) {
                .on_demand => currentOccurrenceDate(model, year),
                .monthly, .quarterly, .annual => null,
            };
            const active = formAvailableForFiling(
                model,
                definition,
                filing,
                occurrence_date,
            );
            model.profilePeriodAvailability[index][slot] = active;
            model.profilePeriodAvailabilityReady[index][slot] = true;
            model.profileFormAnyPeriodActive[index] =
                model.profileFormAnyPeriodActive[index] or active;
            if (definition.status != .static_layout or
                !can_assess_launch) continue;
            if (!active) {
                model.profilePeriodLaunchAssessments[index][slot] = .{};
                model.profilePeriodLaunchAssessmentsReady[index][slot] = true;
                continue;
            }
            const quarter = filing.quarter() orelse switch (filing) {
                .annual => 4,
                .on_demand => selectedFormQuarter(model, definition.code),
                else => selectedFormQuarter(model, definition.code),
            };
            const assessment = assessProfileFormLaunch(
                model,
                definition.code,
                year_value,
                quarter,
                filing.month(),
                filing,
            );
            model.profilePeriodLaunchAssessments[index][slot] = assessment;
            model.profilePeriodLaunchAssessmentsReady[index][slot] = true;
            if (!captured_first_active_assessment) {
                model.profileFormLaunchAssessments[index] = assessment;
                captured_first_active_assessment = true;
            }
        }
    }
    model.profileFormLaunchAssessmentsReady = can_assess_launch;
    refreshTaxFormProfileCardStates(model);
    if (can_assess_launch) refreshProfileDeadlineLaunchAssessments(model);
}

/// Deadline actions use the same exact, cadence-aware assessment as the Tax
/// Form Library, but rendering only consumes this volatile cache. Keeping the
/// cache aligned with the resolved deadline array avoids persistence work in
/// Native view bindings and handles prior-tax-year obligations correctly.
fn refreshProfileDeadlineLaunchAssessments(model: *Model) void {
    @memset(&model.profileDeadlineLaunchAssessmentsReady, false);
    if (model.formProfiles.allocator == null or
        model.formProfiles.store == null) return;
    _ = model.taxProfiles.selectedProfileDomainId() orelse return;
    for (
        model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count],
        0..,
    ) |*deadline, index| {
        if (profileFormRoute(deadline.form_code) == null or
            !model.profileCalendarIncludesDeadline(deadline)) continue;
        const filing = profileDeadlineFilingPeriod(deadline) orelse continue;
        const tax_year: i32 = filing.taxYear();
        const quarter = filing.quarter() orelse switch (filing) {
            .annual => 4,
            .on_demand => continue,
            .monthly, .quarterly => unreachable,
        };
        model.profileDeadlineLaunchAssessments[index] =
            assessProfileFormLaunch(
                model,
                deadline.form_code,
                tax_year,
                quarter,
                filing.month(),
                filing,
            );
        model.profileDeadlineLaunchAssessmentsReady[index] = true;
    }
}

fn libraryFilingPeriod(
    model: *const Model,
    definition: *const form_catalog.FormDefinition,
    year: u16,
) form_period.FilingPeriod {
    return switch (definition.cadence) {
        .monthly => .{ .monthly = .{
            .tax_year = year,
            .month = switch (model.libraryFilter.period_filter) {
                .monthly => |month| month,
                else => @intCast(std.math.clamp(model.calendar.selected_month, 1, 12)),
            },
        } },
        .quarterly => .{ .quarterly = .{
            .tax_year = year,
            .quarter = switch (model.libraryFilter.period_filter) {
                .quarterly => |quarter| quarter,
                else => selectedFormQuarter(model, definition.code),
            },
        } },
        .annual => .{ .annual = .{ .tax_year = year } },
        .on_demand => .{ .on_demand = .{ .tax_year = year, .occurrence = 1 } },
    };
}

fn selectedTaxpayerCalendarContext(
    model: *const Model,
) calendar_ui.TaxpayerContext {
    const rdo = model.selectedTaxpayerRdo();
    const taxpayer_type = model.selectedTaxpayerKind();
    return .{
        .rdo = if (rdo.len == 0) null else rdo,
        .taxpayer_type = if (std.mem.eql(u8, taxpayer_type, "None"))
            null
        else
            taxpayer_type,
    };
}

fn invalidateProfileDeadlineProjection(model: *Model) void {
    model.profileDeadlineProjectionGeneration +%= 1;
    if (model.profileDeadlineProjectionGeneration == 0) {
        model.profileDeadlineProjectionGeneration = 1;
    }
    model.profileDeadlineActionMenuId = null;
    model.profileDeadlineAdjustmentId = null;
    model.profileDeadlineStubAction = .none;
    model.profileDeadlineStubDeadlineId = null;
}

fn syncSelectedProfileCalendar(model: *Model) void {
    invalidateProfileDeadlineProjection(model);
    model.profileCalendar.selected_year = model.calendar.selected_year;
    model.profileCalendar.selected_month = model.calendar.selected_month;
    if (model.hasSelectedTaxpayer()) {
        model.profileCalendar.recomputeForTaxpayer(
            selectedTaxpayerCalendarContext(model),
        ) catch |err| model.profileCalendar.setError(err);
    } else {
        model.profileCalendar.recompute() catch |err|
            model.profileCalendar.setError(err);
    }
    refreshProfileDeadlineLaunchAssessments(model);
}

fn refreshSelectedProfileCalendar(model: *Model) void {
    model.profileCalendar.reload() catch |err| {
        model.profileCalendar.setError(err);
        return;
    };
    syncSelectedProfileCalendar(model);
}

fn refreshGlobalCalendar(model: *Model) void {
    model.globalDashboard.calendar.refresh();
    _ = model.globalDashboard.reconcileSelectedDay();
}

fn attachImportantNews(
    model: *Model,
    allocator: std.mem.Allocator,
    store: *news_store.Store,
) !void {
    var cached = try store.listNewest(allocator);
    errdefer cached.deinit(allocator);
    model.newsStore = store;
    model.newsAllocator = allocator;
    model.newsNotices = cached;
    try model.news.loadCached(cached.items.len);
}

fn deinitImportantNews(model: *Model) void {
    model.news.cancelRefresh();
    if (model.newsNotices) |*notices| {
        if (model.newsAllocator) |allocator| notices.deinit(allocator);
    }
    model.newsNotices = null;
    model.newsStore = null;
    model.newsAllocator = null;
}

fn refreshImportantNews(model: *Model, maybe_fx: ?*Effects) void {
    const start = model.news.beginRefresh() catch return;
    const generation = switch (start) {
        .already_loading => return,
        .started => |value| value,
    };
    const fx = maybe_fx orelse {
        failImportantNews(model, generation, "News refresh is unavailable in this context.");
        return;
    };
    if (model.newsStore == null or model.newsAllocator == null) {
        failImportantNews(model, generation, "The news cache is unavailable.");
        return;
    }
    fx.fetch(.{
        .key = important_news_fetch_key,
        .url = important_news_feed_url,
        .timeout_ms = 15_000,
        .on_response = Effects.responseMsg(.important_news_response),
    });
}

fn receiveImportantNews(
    model: *Model,
    response: native_sdk.EffectResponse,
) void {
    if (response.key != important_news_fetch_key) return;
    const generation = model.news.active_request_generation orelse return;
    if (response.outcome != .ok) {
        failImportantNews(
            model,
            generation,
            importantNewsFetchFailure(response.outcome),
        );
        return;
    }
    if (response.status < 200 or response.status >= 300) {
        failImportantNews(model, generation, "The news provider returned an HTTP error.");
        return;
    }
    if (response.truncated) {
        failImportantNews(model, generation, "The news feed was larger than the safe response limit.");
        return;
    }
    const allocator = model.newsAllocator orelse {
        failImportantNews(model, generation, "The news cache is unavailable.");
        return;
    };
    const store = model.newsStore orelse {
        failImportantNews(model, generation, "The news cache is unavailable.");
        return;
    };
    var parsed = news_feed.parse(
        allocator,
        important_news_source,
        response.body,
        @intCast(c_time.time(null)),
    ) catch {
        failImportantNews(model, generation, "The news provider returned an invalid feed.");
        return;
    };
    defer parsed.deinit(allocator);
    store.upsertOwnedBatch(parsed.items) catch {
        failImportantNews(model, generation, "The refreshed news could not be saved.");
        return;
    };
    var newest = store.listNewest(allocator) catch {
        failImportantNews(model, generation, "The refreshed news cache could not be read.");
        return;
    };
    const applied = model.news.applySuccess(
        generation,
        newest.items.len,
    ) catch {
        newest.deinit(allocator);
        return;
    };
    if (applied == .stale) {
        newest.deinit(allocator);
        return;
    }
    if (model.newsNotices) |*old| old.deinit(allocator);
    model.newsNotices = newest;
}

fn failImportantNews(
    model: *Model,
    generation: u64,
    message: []const u8,
) void {
    _ = model.news.applyFailure(generation, message) catch {};
}

fn importantNewsFetchFailure(
    outcome: native_sdk.EffectFetchOutcome,
) []const u8 {
    return switch (outcome) {
        .ok => "The news provider returned an invalid response.",
        .rejected => "The news request could not be started.",
        .connect_failed => "Could not connect to the news provider.",
        .tls_failed => "The news provider's secure connection failed.",
        .protocol_failed => "The news connection ended unexpectedly.",
        .timed_out => "The news provider did not respond in time.",
        .cancelled => "The news refresh was cancelled.",
    };
}

fn resetProfileCalendarExportNotice(model: *Model) void {
    // A file write or native-calendar opener remains the active request even
    // if the user changes profiles or form choices. Retaining the busy state
    // prevents a second fixed-key export from racing the first one.
    if (model.profileCalendarExportBusy()) return;
    model.profileCalendarExportStatus = .idle;
    model.calendarExportProfileRevision = null;
}

fn saveRecurringFormDraft(model: *Model) void {
    const revision = model.formProfiles.formRevision() orelse return;
    if (std.mem.eql(u8, revision.code.asSlice(), "2551Q")) {
        const filer = model.formProfiles.roleBinding(.filer) orelse {
            model.percentageTax.blockForLoadFailure(
                error.ProfileProjectionUnavailable,
            );
            return;
        };
        const store = model.taxProfiles.store orelse {
            model.percentageTax.blockForLoadFailure(
                error.ProfileStoreUnavailable,
            );
            return;
        };
        const current = store.resolveAnnualIncomeTaxElection(.{
            .profile_id = filer.profile_id,
            .tax_year = model.formProfiles.taxYear(),
        }) catch |err| {
            model.percentageTax.blockForLoadFailure(err);
            return;
        };
        var values: percentage_tax_ui.DraftValueSet = .{};
        const writes = model.percentageTax.draftValueWritesForAnnualElection(
            &values,
            if (current) |*event| event else null,
        ) catch |err| {
            model.percentageTax.blockForLoadFailure(err);
            return;
        };
        _ = model.formProfiles.saveRecurringDraftWithValues(writes) catch
            return;
        model.taxProfiles.refreshDraftSummariesForYear(
            model.calendar.selected_year,
        ) catch |err| {
            model.calendar.setError(err);
        };
        return;
    }
    if (std.mem.eql(u8, revision.code.asSlice(), "1701Q")) {
        persistExact1701QCandidate(model);
        return;
    }
    _ = model.formProfiles.saveRecurringDraft() catch return;
    model.taxProfiles.refreshDraftSummariesForYear(
        model.calendar.selected_year,
    ) catch |err| {
        model.calendar.setError(err);
    };
}

fn persistExact1701QCandidate(model: *Model) void {
    const capability = model.exact1701QDevelopmentPlaintext orelse {
        model.exact1701Q.reportDevelopmentPersistenceFailure(
            "application_context",
            error.ExactDevelopmentPersistenceUnavailable,
        );
        return;
    };
    const store = model.taxProfiles.store orelse {
        model.exact1701Q.reportDevelopmentPersistenceFailure(
            "application_context",
            error.ExactDevelopmentPersistenceUnavailable,
        );
        return;
    };
    const frozen = if (model.exact1701QFrozenProvenance) |*value|
        value
    else {
        model.exact1701Q.reportDevelopmentPersistenceFailure(
            "frozen_provenance",
            error.MissingFrozenExactProvenance,
        );
        return;
    };
    const annual = frozen.annualFilerElection() catch |err| {
        model.exact1701Q.reportDevelopmentPersistenceFailure(
            "annual_filer_election",
            err,
        );
        return;
    };
    const expected_election = exact_1701q_ui.AnnualFilerElection
        .fromTaxpayerYear(annual.rate, annual.deduction) catch |err| {
        model.exact1701Q.reportDevelopmentPersistenceFailure(
            "annual_filer_election",
            err,
        );
        return;
    };
    _ = model.exact1701Q.applyOrValidateAnnualFilerElection(
        expected_election,
    ) catch |err| {
        model.exact1701Q.reportDevelopmentPersistenceFailure(
            "annual_filer_election",
            err,
        );
        return;
    };
    const historical_profile = if (model.exact1701QHistoricalProfile) |*value|
        value
    else {
        model.exact1701Q.reportDevelopmentPersistenceFailure(
            "historical_projection",
            error.HistoricalExactProjectionUnavailable,
        );
        return;
    };
    const exact = model.exact1701Q.exactPersistenceState() orelse {
        model.exact1701Q.reportDevelopmentPersistenceFailure(
            "exact_candidate",
            error.ExactWorkspaceUnavailable,
        );
        return;
    };
    switch (exact_1701q_runtime.persistCurrentCandidateDevelopmentPlaintext(
        capability,
        store,
        exact,
        historical_profile,
        frozen,
        @intCast(c_time.time(null)),
    )) {
        .saved => |receipt| model.exact1701Q.reportDevelopmentPersistenceSaved(
            receipt.revision.value,
            receipt.shape,
        ),
        .blocked => |failure| model.exact1701Q.reportDevelopmentPersistenceFailure(
            @tagName(failure.stage),
            failure.reason,
        ),
    }
}

fn editorRevision(form_code: []const u8) ?form_ids.FormRevision {
    for (form_ui.editor_revisions) |revision| {
        if (std.mem.eql(u8, revision.code.asSlice(), form_code)) {
            return revision;
        }
    }
    return null;
}

fn selectedCalendarQuarter(model: *const Model) u8 {
    const month = std.math.clamp(model.calendar.selected_month, 1, 12);
    return @intCast((month - 1) / 3 + 1);
}

fn selectedFormQuarter(model: *const Model, form_code: []const u8) u8 {
    const quarter = selectedCalendarQuarter(model);
    // 1701Q has Q1-Q3 filing periods. December remains a valid dashboard
    // context; use the last valid quarter until a specific quarter is chosen.
    if (std.mem.eql(u8, form_code, "1701Q") and quarter == 4) return 3;
    return quarter;
}

fn monthEndDate(year: u16, month: u8) profile_model.Date {
    const day: u8 = switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (year % 4 == 0 and
            (year % 100 != 0 or year % 400 == 0))
            29
        else
            28,
        else => unreachable,
    };
    return profile_model.Date.init(year, month, day) catch unreachable;
}

fn formatFilingDate(
    arena: std.mem.Allocator,
    date: profile_model.Date,
) []const u8 {
    return std.fmt.allocPrint(
        arena,
        "{d:0>2} / {d:0>2} / {d:0>4}",
        .{ date.month, date.day, date.year },
    ) catch "";
}

fn profileAsOfForForm(
    model: *const Model,
    form_code: []const u8,
    year: u16,
    quarter: u8,
    period_month: ?u8,
) profile_model.Date {
    if (std.mem.eql(u8, form_code, "1701") or
        std.mem.eql(u8, form_code, "1702RT") or
        std.mem.eql(u8, form_code, "1702MX"))
    {
        return profile_model.Date.init(year, 12, 31) catch unreachable;
    }
    if (std.mem.eql(u8, form_code, "1701Q") or
        std.mem.eql(u8, form_code, "2550Q") or
        std.mem.eql(u8, form_code, "2551Q"))
    {
        return monthEndDate(year, quarter * 3);
    }
    return monthEndDate(
        year,
        period_month orelse model.calendar.selected_month,
    );
}

fn openProfileBoundForm(
    model: *Model,
    page: Page,
    form_code: []const u8,
) void {
    if (model.exact1701Q.ready() and
        model.exact1701Q.hasDirtyOrMaterialWork())
    {
        if (!std.mem.eql(u8, form_code, "1701Q")) {
            model.exact1701Q.rejectContextChange();
        }
        navigate(model, .form_1701q);
        return;
    }
    if (std.mem.eql(u8, form_code, "1701Q") and
        selectedCalendarQuarter(model) == 4)
    {
        const definition = catalogDefinitionForDeadline(form_code) orelse
            return;
        if (model.calendar.selected_year < 1 or
            model.calendar.selected_year > 9999) return;
        const filing: form_period.FilingPeriod = .{ .quarterly = .{
            .tax_year = @intCast(model.calendar.selected_year),
            .quarter = 3,
        } };
        if (!formAvailableForFiling(model, definition, filing, null)) return;
        // Preserve the existing quarter-picker entry behavior: December has
        // no Q4 1701Q workspace, so show the page until the user chooses Q1-Q3.
        navigate(model, page);
        return;
    }
    _ = openProfileBoundFormForQuarter(
        model,
        page,
        form_code,
        model.calendar.selected_year,
        selectedCalendarQuarter(model),
        null,
        null,
        null,
    );
}

const ProfileFormRoute = struct {
    page: Page,
    form_code: []const u8,
};

fn profileFormRoute(form_code: []const u8) ?ProfileFormRoute {
    const routes = [_]ProfileFormRoute{
        .{ .page = .form_0605, .form_code = "0605" },
        .{ .page = .form_0619_e, .form_code = "0619E" },
        .{ .page = .form_0619_f, .form_code = "0619F" },
        .{ .page = .form_1601_c, .form_code = "1601C" },
        .{ .page = .form_1701, .form_code = "1701" },
        .{ .page = .form_1701q, .form_code = "1701Q" },
        .{ .page = .form_1702_rt, .form_code = "1702RT" },
        .{ .page = .form_1702_mx, .form_code = "1702MX" },
        .{ .page = .form_2550q, .form_code = "2550Q" },
        .{ .page = .form_2551q, .form_code = "2551Q" },
    };
    for (routes) |route| {
        if (formCodesEquivalent(route.form_code, form_code)) return route;
    }
    return null;
}

fn formCatalogIndex(form_code: []const u8) ?usize {
    for (form_catalog.forms, 0..) |form, index| {
        if (formCodesEquivalent(form.code, form_code)) return index;
    }
    return null;
}

fn taxFormProfileSetupValue(
    values: []const tax_form_profile_domain.SetupValue,
    role: form_catalog.Role,
    key: form_catalog.TaxFormProfileSemanticKey,
) ?*const tax_form_profile_domain.SetupValue {
    for (values) |*value| {
        if (value.role == role and value.semantic_key == key) return value;
    }
    return null;
}

fn taxFormProfileFieldLabel(
    definition: form_catalog.TaxFormProfileValueDefinition,
) []const u8 {
    return taxFormProfileMappingFieldLabel(
        definition.role,
        definition.semantic_key,
    );
}

fn taxFormProfileMappingFieldLabel(
    role: form_catalog.Role,
    semantic_key: form_catalog.TaxFormProfileSemanticKey,
) []const u8 {
    return switch (semantic_key) {
        .business_activity_anchor_id => if (role == .spouse)
            "Spouse business activity"
        else
            "Business activity",
        .spouse_profile_id => "Spouse taxpayer profile",
        .spouse_business_activity_anchor_id => "Spouse business activity",
        .special_rate_obligation_anchor_id => "Special-rate registration",
    };
}

fn taxFormProfileFieldHelper(
    definition: form_catalog.TaxFormProfileValueDefinition,
) []const u8 {
    if (definition.availability == .evidence_required) {
        return definition.evidence_gate orelse
            "This selection stays unavailable until its official-form evidence is confirmed.";
    }
    return switch (definition.source_kind) {
        .named_profile_role => "Choose another saved taxpayer profile only when that person is a filer on this form.",
        .business_activity_anchor => "Choose an activity saved under Registration and Forms for this tax year. Add another activity there to make a different selection.",
        .registration_obligation_anchor => "Choose a typed registration saved under Registration and Forms.",
        .user_entry => "Enter the value that applies for this form and tax year.",
        .catalog_default => "This value is supplied by the exact form revision.",
    };
}

fn taxFormProfileScalarStableId(
    value: *const tax_form_profile_domain.ScalarValue,
) ?[]const u8 {
    return switch (value.*) {
        .profile_id => |*item| item.asSlice(),
        .business_activity_anchor_id => |*item| item.asSlice(),
        .registration_obligation_anchor_id => |*item| item.asSlice(),
        .text => |*item| item.asSlice(),
        .choice => |*item| item.asSlice(),
        .boolean, .integer, .date, .year => null,
    };
}

fn taxFormProfileValueLabel(
    model: *const Model,
    arena: std.mem.Allocator,
    field_index: usize,
    setup_value: ?*const tax_form_profile_domain.SetupValue,
) []const u8 {
    const value = setup_value orelse return "Not selected";
    if (taxFormProfileScalarStableId(&value.value)) |stable_id| {
        for (model.taxFormProfileChoices[0..model.taxFormProfileChoiceCount]) |*choice| {
            if (choice.field_index == field_index and
                std.mem.eql(u8, choice.stable_id.text(), stable_id))
            {
                return choice.label.text();
            }
        }
    }
    return switch (value.value) {
        .profile_id => |*item| item.asSlice(),
        .business_activity_anchor_id => |*item| item.asSlice(),
        .registration_obligation_anchor_id => |*item| item.asSlice(),
        .text => |*item| item.asSlice(),
        .choice => |*item| item.asSlice(),
        .boolean => |item| if (item) "Yes" else "No",
        .integer => |item| std.fmt.allocPrint(
            arena,
            "{d}",
            .{item},
        ) catch "Value unavailable",
        .date => |item| std.fmt.allocPrint(
            arena,
            "{d:0>4}-{d:0>2}-{d:0>2}",
            .{ item.year, item.month, item.day },
        ) catch "Date unavailable",
        .year => |item| std.fmt.allocPrint(
            arena,
            "{d}",
            .{item},
        ) catch "Year unavailable",
    };
}

fn taxFormProfileChoiceSelected(
    model: *const Model,
    field_index: usize,
    stable_id: []const u8,
) bool {
    const form_index = model.taxFormProfileFormIndex orelse return false;
    if (form_index >= form_catalog.registry_count) return false;
    const definition = &form_catalog.forms[form_index];
    if (field_index >= definition.tax_form_profile.values.len) return false;
    const field = definition.tax_form_profile.values[field_index];
    const values = if (model.taxFormProfileEditing())
        model.taxFormProfilePage.draftValues()
    else
        model.taxFormProfilePage.baselineValues();
    const current = taxFormProfileSetupValue(
        values,
        field.role,
        field.semantic_key,
    ) orelse return false;
    const current_id = taxFormProfileScalarStableId(&current.value) orelse
        return false;
    return std.mem.eql(u8, current_id, stable_id);
}

fn taxpayerYearValues(
    model: *const Model,
) []const taxpayer_year_settings_domain.SettingValue {
    return if (model.taxpayerYearEditing())
        model.taxpayerYearPage.draftValues()
    else
        model.taxpayerYearPage.baselineValues();
}

fn annualIncomeTaxElectionCandidateEditable(model: *const Model) bool {
    if (!annualElectionPilotOpen(model) or
        model.annualIncomeTaxElection.load_failed or
        model.annualIncomeTaxElection.eligibility != .eligible)
    {
        return false;
    }
    const initial = model.annualIncomeTaxElection.initial_applicable_quarter orelse
        return false;
    if (model.annualIncomeTaxElection.filing_quarter != initial) return false;
    const current = model.annualIncomeTaxElection.current orelse return true;
    return current.state == .candidate;
}

fn taxpayerYearRateElection(
    model: *const Model,
) ?taxpayer_year_settings_domain.IncomeTaxRateElection {
    for (taxpayerYearValues(model)) |value| {
        switch (value) {
            .income_tax_rate_election => |election| return election,
            .deduction_method => {},
        }
    }
    return null;
}

fn taxpayerYearDeductionMethod(
    model: *const Model,
) ?taxpayer_year_settings_domain.DeductionMethod {
    for (taxpayerYearValues(model)) |value| {
        switch (value) {
            .deduction_method => |method| return method,
            .income_tax_rate_election => {},
        }
    }
    return null;
}

fn appendTaxFormProfileChoice(
    model: *Model,
    field_index: usize,
    stable_id: []const u8,
    label: []const u8,
) void {
    if (model.taxFormProfileChoiceCount == model.taxFormProfileChoices.len) {
        return;
    }
    var choice = TaxFormProfileChoiceCache{ .field_index = field_index };
    choice.stable_id.set(stable_id);
    choice.label.set(label);
    model.taxFormProfileChoices[model.taxFormProfileChoiceCount] = choice;
    model.taxFormProfileChoiceCount += 1;
}

fn taxFormProfileSelectedProfileId(
    state: *const tax_form_profile_ui.State,
) ?profile_model.ProfileId {
    for (state.draftValues()) |value| {
        if (value.semantic_key != .spouse_profile_id or
            value.role != .spouse) continue;
        return switch (value.value) {
            .profile_id => |profile_id| profile_id,
            else => null,
        };
    }
    return null;
}

fn taxFormProfileViewedOn(model: *const Model) ?profile_model.Date {
    const viewed = model.taxFormProfilePage.viewedIdentity() orelse return null;
    const date = model.taxFormProfileViewedDate orelse return null;
    return if (date.year == viewed.tax_year) date else null;
}

fn taxFormProfileRoleDefinition(
    definition: *const form_catalog.FormDefinition,
    role: form_catalog.Role,
) ?*const form_catalog.ProfileRoleDefinition {
    for (definition.profile_roles) |*candidate| {
        if (candidate.role == role) return candidate;
    }
    return null;
}

fn taxFormProfileCatalogSubjectKind(
    kind: profile_model.SubjectKind,
) form_catalog.ProfileSubjectKind {
    return switch (kind) {
        .individual => .individual,
        .sole_proprietor => .sole_proprietor,
        .corporation => .corporation,
        .partnership => .partnership,
        .cooperative => .cooperative,
        .estate => .estate,
        .trust => .trust,
        .other_legal_entity => .other_legal_entity,
    };
}

fn taxFormProfileRoleAllowsSubject(
    role: *const form_catalog.ProfileRoleDefinition,
    kind: profile_model.SubjectKind,
) bool {
    const catalog_kind = taxFormProfileCatalogSubjectKind(kind);
    for (role.allowed_subjects) |allowed| {
        if (allowed == catalog_kind) return true;
    }
    return false;
}

fn taxFormProfileBoundProfileId(
    model: *const Model,
    role: form_catalog.Role,
) ?profile_model.ProfileId {
    if (role == .filer) {
        return model.taxProfiles.selectedProfileDomainId();
    }
    for (model.taxFormProfilePage.draftValues()) |value| {
        if (value.role != role) continue;
        return switch (value.value) {
            .profile_id => |profile_id| profile_id,
            else => null,
        };
    }
    return null;
}

fn taxFormProfileNamedProfileChoiceAllowed(
    model: *const Model,
    definition: *const form_catalog.FormDefinition,
    role: form_catalog.Role,
    candidate: *const profile_ui.ProfileRow,
) bool {
    const policy = taxFormProfileRoleDefinition(definition, role) orelse
        return false;
    if (!taxFormProfileRoleAllowsSubject(policy, candidate.subject_kind)) {
        return false;
    }
    const candidate_id = profile_model.ProfileId.parse(
        candidate.idLabel(),
    ) catch return false;

    // Enforce the selected role's explicit constraints and their reverse
    // direction. The generated catalog currently declares spouse distinct
    // from filer, but the reverse pass keeps this correct if a later form
    // puts the constraint on the other role instead.
    for (policy.distinct_from) |other_role| {
        if (taxFormProfileBoundProfileId(model, other_role)) |bound| {
            if (candidate_id.eql(&bound)) return false;
        }
    }
    for (definition.profile_roles) |*other_policy| {
        if (other_policy.role == role) continue;
        const bound = taxFormProfileBoundProfileId(
            model,
            other_policy.role,
        ) orelse continue;
        for (other_policy.distinct_from) |distinct_role| {
            if (distinct_role == role and candidate_id.eql(&bound)) {
                return false;
            }
        }
    }
    return true;
}

fn loadTaxFormProfileActivityChoices(
    model: *Model,
    field_index: usize,
    profile_id: profile_model.ProfileId,
) void {
    const allocator = model.taxProfiles.allocator orelse return;
    const store = model.taxProfiles.store orelse return;
    const viewed_on = taxFormProfileViewedOn(model) orelse return;
    var owned = profile_persistence.loadRegistrationAggregateOn(
        store,
        allocator,
        profile_id,
        viewed_on,
    ) catch return;
    defer owned.deinit(allocator);
    for (owned.aggregate.business_activities) |*activity| {
        if (!activity.metadata.review.isConfirmed() or
            !activity.metadata.isEffective(viewed_on)) continue;
        var label_buffer: [220]u8 = undefined;
        const label = if (activity.atc) |*atc|
            std.fmt.bufPrint(
                &label_buffer,
                "{s} - ATC {s}",
                .{
                    activity.line_of_business.asSlice(),
                    atc.asSlice(),
                },
            ) catch activity.line_of_business.asSlice()
        else
            activity.line_of_business.asSlice();
        appendTaxFormProfileChoice(
            model,
            field_index,
            activity.anchor_id.asSlice(),
            label,
        );
    }
}

fn taxFormProfileObligationChoiceLabel(
    obligation: *const profile_registration.RegistrationObligation,
    buffer: []u8,
) []const u8 {
    return switch (obligation.kind) {
        .registered_income_tax => "Registered income tax",
        .vat => "Value-added tax (VAT)",
        .percentage_tax => "Percentage tax",
        .withholding => |withholding| switch (withholding) {
            .compensation => "Withholding tax - compensation",
            .expanded => "Withholding tax - expanded",
            .final => "Withholding tax - final",
            .other => |value| std.fmt.bufPrint(
                buffer,
                "Withholding tax - {s}",
                .{value.asSlice()},
            ) catch value.asSlice(),
            .unspecified_requires_review => "Withholding tax - review required",
        },
        .unknown_requires_review => |value| std.fmt.bufPrint(
            buffer,
            "Registration obligation - {s}",
            .{value.asSlice()},
        ) catch value.asSlice(),
    };
}

fn loadTaxFormProfileObligationChoices(
    model: *Model,
    field_index: usize,
    profile_id: profile_model.ProfileId,
) void {
    const allocator = model.taxProfiles.allocator orelse return;
    const store = model.taxProfiles.store orelse return;
    const viewed_on = taxFormProfileViewedOn(model) orelse return;
    var owned = profile_persistence.loadRegistrationAggregateOn(
        store,
        allocator,
        profile_id,
        viewed_on,
    ) catch return;
    defer owned.deinit(allocator);
    for (owned.aggregate.obligations) |*obligation| {
        if (!obligation.metadata.review.isConfirmed() or
            !obligation.metadata.isEffective(viewed_on)) continue;
        var label_buffer: [220]u8 = undefined;
        const label = taxFormProfileObligationChoiceLabel(
            obligation,
            &label_buffer,
        );
        appendTaxFormProfileChoice(
            model,
            field_index,
            obligation.anchor_id.asSlice(),
            label,
        );
    }
}

fn loadTaxFormProfileChoices(model: *Model) void {
    model.taxFormProfileChoiceCount = 0;
    model.taxFormProfilePickerField = null;
    const form_index = model.taxFormProfileFormIndex orelse return;
    if (form_index >= form_catalog.registry_count) return;
    const definition = &form_catalog.forms[form_index];
    const filer_id = model.taxProfiles.selectedProfileDomainId() orelse return;
    for (definition.tax_form_profile.values, 0..) |value_definition, field_index| {
        if (value_definition.availability != .supported) continue;
        switch (value_definition.source_kind) {
            .named_profile_role => {
                for (model.taxProfiles.rows()) |*row| {
                    if (!taxFormProfileNamedProfileChoiceAllowed(
                        model,
                        definition,
                        value_definition.role,
                        row,
                    )) continue;
                    appendTaxFormProfileChoice(
                        model,
                        field_index,
                        row.idLabel(),
                        row.nameLabel(),
                    );
                }
            },
            .business_activity_anchor => {
                const owner = if (value_definition.role == .spouse)
                    taxFormProfileSelectedProfileId(
                        &model.taxFormProfilePage,
                    ) orelse continue
                else
                    filer_id;
                loadTaxFormProfileActivityChoices(
                    model,
                    field_index,
                    owner,
                );
            },
            .registration_obligation_anchor => {
                loadTaxFormProfileObligationChoices(
                    model,
                    field_index,
                    filer_id,
                );
            },
            .user_entry, .catalog_default => {},
        }
    }
}

fn loadTaxFormProfileInherited(
    model: *Model,
    profile_id: profile_model.ProfileId,
    on: profile_model.Date,
) void {
    model.taxFormProfileInherited = .{};
    const allocator = model.taxProfiles.allocator orelse return;
    const store = model.taxProfiles.store orelse return;
    var owned = (profile_persistence.loadEffectiveRevision(
        store,
        allocator,
        profile_id,
        on,
    ) catch return) orelse return;
    defer owned.deinit(allocator);
    const revision = &owned.revision;
    model.taxFormProfileInherited.source_revision_id.set(
        revision.id.asSlice(),
    );
    model.taxFormProfileInherited.source_sequence = revision.sequence;
    model.taxFormProfileInherited.tin.set(revision.identity.tin.asDigits());
    model.taxFormProfileInherited.rdo.set(
        revision.identity.rdo_code.asSlice(),
    );
    model.taxFormProfileInherited.address.set(
        revision.contact.address.asSlice(),
    );
    if (revision.contact.zip_code) |*value| {
        model.taxFormProfileInherited.zip.set(value.asSlice());
    }
    if (revision.contact.contact_number) |*value| {
        model.taxFormProfileInherited.contact.set(value.asSlice());
    }
    if (revision.contact.email_address) |*value| {
        model.taxFormProfileInherited.email.set(value.asSlice());
    }
    switch (revision.subject) {
        .individual => |person| {
            model.taxFormProfileInherited.subject_kind.set("Individual");
            model.taxFormProfileInherited.name.set(person.name.asSlice());
        },
        .sole_proprietor => |proprietor| {
            model.taxFormProfileInherited.subject_kind.set("Sole proprietor");
            model.taxFormProfileInherited.name.set(
                proprietor.person.name.asSlice(),
            );
        },
        .legal_entity => |entity| {
            model.taxFormProfileInherited.subject_kind.set(switch (entity.kind) {
                .corporation => "Corporation",
                .partnership => "Partnership",
                .cooperative => "Cooperative",
                .estate => "Estate",
                .trust => "Trust",
                .other => "Other legal entity",
            });
            model.taxFormProfileInherited.name.set(
                entity.registered_name.asSlice(),
            );
        },
    }
}

fn taxpayerYearConsumption(model: *const Model) taxpayer_year_ui.Consumption {
    var result: taxpayer_year_ui.Consumption = .{};
    for (&form_catalog.forms, 0..) |*definition, index| {
        if (!model.profileFormAnyPeriodActive[index]) continue;
        const consumes_rate = form_catalog.consumesTaxpayerYearSetting(
            definition,
            .income_tax_rate_election,
        );
        const consumes_deduction = form_catalog.consumesTaxpayerYearSetting(
            definition,
            .deduction_method,
        );
        result.income_tax_rate_election =
            result.income_tax_rate_election or consumes_rate;
        result.deduction_method_when_graduated =
            result.deduction_method_when_graduated or consumes_deduction;
        if (consumes_rate or consumes_deduction) {
            result.active_form_count +|= 1;
        }
    }
    return result;
}

fn annualElectionPilotOpen(model: *const Model) bool {
    return std.mem.eql(u8, model.taxFormProfileCode(), "2551Q");
}

fn annualElectionQuarterEnd(tax_year: u16, quarter: u8) ?profile_model.Date {
    if (quarter < 1 or quarter > 4) return null;
    return monthEndDate(tax_year, quarter * 3);
}

fn resolveAnnualIncomeTaxEligibility(
    model: *Model,
    profile_id: profile_model.ProfileId,
    tax_year: u16,
    filing_quarter: u8,
) void {
    model.annualIncomeTaxElection.eligibility = .load_failed;
    model.annualIncomeTaxElection.commencement = .unknown;
    model.annualIncomeTaxElection.initial_applicable_quarter = null;

    const allocator = model.taxProfiles.allocator orelse return;
    const store = model.taxProfiles.store orelse return;
    const on = annualElectionQuarterEnd(tax_year, filing_quarter) orelse return;
    var date_buffer: [10]u8 = undefined;
    var owned_profile = (store.getEffectiveRevision(
        allocator,
        profile_id.asSlice(),
        on.writeIso(&date_buffer),
    ) catch return) orelse return;
    defer owned_profile.deinit(allocator);

    switch (owned_profile.subject) {
        .individual => |person| switch (person.classification) {
            .self_employed, .mixed_income => {},
            .classification_unknown => {
                model.annualIncomeTaxElection.eligibility =
                    .classification_unresolved;
                return;
            },
            .pure_compensation => {
                model.annualIncomeTaxElection.eligibility =
                    .taxpayer_type_ineligible;
                return;
            },
        },
        // Compatibility rows retain enough evidence to classify the natural
        // person as self-employed without manufacturing a legal-person type.
        .sole_proprietor => {},
        .legal_entity => {
            model.annualIncomeTaxElection.eligibility =
                .taxpayer_type_ineligible;
            return;
        },
    }

    var registration = profile_persistence.loadRegistrationAggregateOn(
        store,
        allocator,
        profile_id,
        on,
    ) catch return;
    defer registration.deinit(allocator);
    const summary = registration.aggregate.derivedSummary(on) catch return;
    if (summary.vat.confirmed_registered) {
        model.annualIncomeTaxElection.eligibility = .vat_registered;
        return;
    }
    if (!summary.percentage_tax.confirmed_registered) {
        model.annualIncomeTaxElection.eligibility =
            if (summary.percentage_tax.unreviewed_proposal_count != 0)
                .registration_requires_review
            else
                .percentage_tax_registration_missing;
        return;
    }

    var registration_year = profile_persistence.loadRegistrationAggregateForYear(
        store,
        allocator,
        profile_id,
        tax_year,
    ) catch return;
    defer registration_year.deinit(allocator);
    var commencement: ?profile_model.Date = null;
    var activity_requires_review = false;
    for (registration_year.aggregate.business_activities) |*activity| {
        if (!activity.metadata.review.isConfirmed()) {
            activity_requires_review = true;
            continue;
        }
        if (commencement == null or
            activity.metadata.effective.from.isBefore(commencement.?))
        {
            commencement = activity.metadata.effective.from;
        }
    }
    const commenced_on = commencement orelse {
        model.annualIncomeTaxElection.eligibility =
            if (activity_requires_review)
                .registration_requires_review
            else
                .business_commencement_unresolved;
        return;
    };
    model.annualIncomeTaxElection.commencement =
        if (commenced_on.year < tax_year)
            .existing_before_tax_year
        else
            .{ .commenced_on = commenced_on };
    const stream: annual_income_tax_election.StreamKey = .{
        .profile_id = profile_id,
        .tax_year = tax_year,
    };
    model.annualIncomeTaxElection.initial_applicable_quarter =
        annual_income_tax_election.initialApplicableQuarter(
            stream,
            model.annualIncomeTaxElection.commencement,
        ) catch {
            model.annualIncomeTaxElection.eligibility =
                .business_commencement_unresolved;
            return;
        };
    model.annualIncomeTaxElection.eligibility = .eligible;
}

fn openAnnualIncomeTaxElection(
    model: *Model,
    profile_id: profile_model.ProfileId,
    tax_year: u16,
    effective_on: taxpayer_year_settings_domain.Date,
) void {
    model.taxpayerYearPage.reset();
    const form_index = model.taxFormProfileFormIndex orelse return;
    if (form_index >= form_catalog.registry_count or
        !std.mem.eql(u8, form_catalog.forms[form_index].code, "2551Q") or
        effective_on.year != tax_year)
    {
        return;
    }
    const requested_quarter = model.annualIncomeTaxElection.filing_quarter;
    const filing_quarter = if (requested_quarter >= 1 and requested_quarter <= 4)
        requested_quarter
    else
        selectedFormQuarter(model, "2551Q");
    model.annualIncomeTaxElection = .{ .filing_quarter = filing_quarter };
    resolveAnnualIncomeTaxEligibility(
        model,
        profile_id,
        tax_year,
        filing_quarter,
    );

    const allocator = model.taxProfiles.allocator orelse {
        model.annualIncomeTaxElection.load_failed = true;
        return;
    };
    const store = model.taxProfiles.store orelse {
        model.annualIncomeTaxElection.load_failed = true;
        return;
    };
    const annual_stream: annual_income_tax_election.StreamKey = .{
        .profile_id = profile_id,
        .tax_year = tax_year,
    };
    var history = profile_persistence.loadAnnualIncomeTaxElectionHistory(
        store,
        allocator,
        annual_stream,
    ) catch {
        model.annualIncomeTaxElection.load_failed = true;
        return;
    };
    defer history.deinit(allocator);
    const current = history.history.current() catch {
        model.annualIncomeTaxElection.load_failed = true;
        return;
    };
    if (current) |event| {
        model.annualIncomeTaxElection.current = event.*;
        model.annualIncomeTaxElection.initial_applicable_quarter =
            event.initial_applicable_quarter;
    }

    var setting_values: [1]taxpayer_year_settings_domain.SettingValue =
        undefined;
    var projected_revision: ?taxpayer_year_settings_domain.Revision = null;
    if (current) |event| if (event.choice) |choice| {
        setting_values[0] = .{ .income_tax_rate_election = switch (choice) {
            .graduated => .graduated,
            .eight_percent => .eight_percent,
        } };
        projected_revision = .{
            .id = taxpayer_year_settings_domain.RevisionId.parse(
                "annual-election-ui",
            ) catch return,
            .stream = .{ .profile_id = profile_id, .tax_year = tax_year },
            .sequence = event.sequence,
            .effective = taxpayer_year_settings_domain.fullTaxYearPeriod(
                tax_year,
            ) catch return,
            // Lifecycle and lock state are rendered from the annual event.
            // `confirmed` here only lets the existing editor snapshot the
            // selected value; it never writes this compatibility projection.
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = event.occurred_at_unix_seconds,
            .source = .manual_entry,
            .values = &setting_values,
        };
    };
    model.taxpayerYearPage = taxpayer_year_ui.State.open(.{
        .profile_id = profile_id,
        .tax_year = tax_year,
        .effective_on = effective_on,
        .profile_active = true,
        .consumption = .{
            .active_form_count = 1,
            .income_tax_rate_election = true,
        },
        .history_exists = current != null,
        .saved_revision = if (projected_revision) |*revision| revision else null,
    }) catch .{};
}

fn openTaxpayerYearSettings(
    model: *Model,
    profile_id: profile_model.ProfileId,
    tax_year: u16,
    effective_on: taxpayer_year_settings_domain.Date,
) void {
    if (annualElectionPilotOpen(model)) {
        openAnnualIncomeTaxElection(
            model,
            profile_id,
            tax_year,
            effective_on,
        );
        return;
    }
    model.taxpayerYearPage.reset();
    if (effective_on.year != tax_year) return;
    const stream: taxpayer_year_settings_domain.StreamKey = .{
        .profile_id = profile_id,
        .tax_year = tax_year,
    };
    var history_exists = false;
    var saved_revision: ?*const taxpayer_year_settings_domain.Revision = null;
    var owned_history: ?profile_persistence.OwnedTaxpayerYearHistory = null;
    var prior_owned_history: ?profile_persistence.OwnedTaxpayerYearHistory = null;
    defer if (owned_history) |*owned| {
        if (model.taxProfiles.allocator) |allocator| owned.deinit(allocator);
    };
    defer if (prior_owned_history) |*owned| {
        if (model.taxProfiles.allocator) |allocator| owned.deinit(allocator);
    };
    if (model.taxProfiles.allocator) |allocator| {
        if (model.taxProfiles.store) |store| {
            owned_history = profile_persistence.loadTaxpayerYearHistory(
                store,
                allocator,
                stream,
            ) catch null;
            if (owned_history) |*owned| {
                history_exists = owned.history.revisions.len != 0;
                saved_revision = owned.history.effectiveOn(
                    effective_on,
                ) catch null;
            }
        }
    }
    var copy_offer: ?*const taxpayer_year_settings_domain.Revision = null;
    if (tax_year > 1) {
        if (model.taxProfiles.allocator) |allocator| {
            if (model.taxProfiles.store) |store| {
                prior_owned_history = profile_persistence.loadTaxpayerYearHistory(
                    store,
                    allocator,
                    .{
                        .profile_id = profile_id,
                        .tax_year = tax_year - 1,
                    },
                ) catch null;
                if (prior_owned_history) |*owned| {
                    for (owned.history.revisions) |*candidate| {
                        if (candidate.review_state != .confirmed) continue;
                        if (copy_offer == null or
                            candidate.sequence > copy_offer.?.sequence)
                        {
                            copy_offer = candidate;
                        }
                    }
                }
            }
        }
    }
    model.taxpayerYearPage = taxpayer_year_ui.State.open(.{
        .profile_id = profile_id,
        .tax_year = tax_year,
        .effective_on = effective_on,
        .profile_active = true,
        .consumption = taxpayerYearConsumption(model),
        .history_exists = history_exists,
        .saved_revision = saved_revision,
        .copy_offer = copy_offer,
    }) catch .{};
}

const ProfileFormActivationContext = struct {
    viewed_on: profile_model.Date,
    effective: tax_form_profile_domain.EffectivePeriod,
    previous_viewed_on: ?profile_model.Date = null,
    next_viewed_on: ?profile_model.Date = null,
};

fn profileFormActivationContext(
    model: *Model,
    profile_id: profile_model.ProfileId,
    definition: *const form_catalog.FormDefinition,
    tax_year: u16,
    requested: ?profile_model.Date,
) ?ProfileFormActivationContext {
    const allocator = model.taxProfiles.allocator orelse return null;
    const store = model.taxProfiles.store orelse return null;
    const stream: forms_set_history.StreamIdentity = .{
        .profile_id = profile_id,
        .tax_year = tax_year,
        .form = .{
            .code = definition.code,
            .revision = catalogFormRevision(definition),
        },
    };
    var owned = profile_persistence.loadFormSetDecisionHistory(
        store,
        allocator,
        stream,
    ) catch return null;
    defer owned.deinit(allocator);
    const preferred = requested orelse if (model.calendarToday.year == tax_year)
        profile_model.Date.init(
            tax_year,
            model.calendarToday.month,
            model.calendarToday.day,
        ) catch null
    else
        null;
    const window = (owned.history.activeSegmentWindow(
        stream,
        preferred,
    ) catch return null) orelse return null;
    if (requested) |date| {
        if (!window.selected.effective.contains(date)) return null;
    }
    return .{
        .viewed_on = window.selected.viewed_on,
        .effective = window.selected.effective,
        .previous_viewed_on = if (window.previous) |segment|
            segment.viewed_on
        else
            null,
        .next_viewed_on = if (window.next) |segment|
            segment.viewed_on
        else
            null,
    };
}

fn cacheTaxFormProfileHistory(
    model: *Model,
    revisions: []const tax_form_profile_domain.Revision,
    current_sequence: u32,
) void {
    model.taxFormProfileHistoryRowCount = 0;
    model.taxFormProfileHistoryTruncated =
        revisions.len > max_tax_form_profile_history_rows;
    var source_index = revisions.len;
    while (source_index > 0 and
        model.taxFormProfileHistoryRowCount <
            max_tax_form_profile_history_rows)
    {
        source_index -= 1;
        const revision = &revisions[source_index];
        const row_index = model.taxFormProfileHistoryRowCount;
        const row = &model.taxFormProfileHistoryRowsCache[row_index];
        row.* = .{
            .id = row_index,
            .sequence = revision.sequence,
            .current = revision.sequence == current_sequence,
        };

        var from_buffer: [10]u8 = undefined;
        const from = revision.effective.from.writeIso(&from_buffer);
        var effective_buffer: [32]u8 = undefined;
        const effective = if (revision.effective.until) |until_date| blk: {
            var until_buffer: [10]u8 = undefined;
            break :blk std.fmt.bufPrint(
                &effective_buffer,
                "{s} through {s}",
                .{ from, until_date.writeIso(&until_buffer) },
            ) catch "Effective interval unavailable";
        } else std.fmt.bufPrint(
            &effective_buffer,
            "From {s}",
            .{from},
        ) catch "Effective interval unavailable";
        row.effective.set(effective);

        var source_buffer: [128]u8 = undefined;
        const source = switch (revision.source) {
            .manual_entry => if (commonCopiedValueRevision(revision)) |source_id|
                std.fmt.bufPrint(
                    &source_buffer,
                    "Reviewed reuse from revision {s}",
                    .{source_id.asSlice()},
                ) catch "Reviewed saved setup reuse"
            else
                "Manual entry",
            .copied_from_prior_year => |*copy| std.fmt.bufPrint(
                &source_buffer,
                "Copied from {d} form {s}, revision {s}",
                .{
                    copy.source_tax_year,
                    copy.source_form_revision.asSlice(),
                    copy.source_revision_id.asSlice(),
                },
            ) catch "Copied from prior year",
            .migrated => |*value| std.fmt.bufPrint(
                &source_buffer,
                "Migrated from {s}",
                .{value.asSlice()},
            ) catch "Migrated setup",
        };
        row.source.set(source);
        model.taxFormProfileHistoryRowCount += 1;
    }
}

fn commonCopiedValueRevision(
    revision: *const tax_form_profile_domain.Revision,
) ?tax_form_profile_domain.RevisionId {
    var source: ?tax_form_profile_domain.RevisionId = null;
    for (revision.values) |value| switch (value.source) {
        .copied_from_revision => |revision_id| {
            if (source) |existing| {
                if (!existing.eql(&revision_id)) return null;
            } else {
                source = revision_id;
            }
        },
        .manual_confirmation, .migrated => return null,
    };
    return source;
}

fn priorYearTaxFormProfileOffer(
    model: *Model,
    profile_id: profile_model.ProfileId,
    definition: *const form_catalog.FormDefinition,
    tax_year: u16,
) ?tax_form_profile_ui.CopyOffer {
    if (tax_year <= 1 or definition.tax_form_profile.mode != .setup) {
        return null;
    }
    const allocator = model.taxProfiles.allocator orelse return null;
    const store = model.taxProfiles.store orelse return null;
    const form_code = tax_form_profile_domain.FormCode.parse(
        definition.code,
    ) catch return null;
    var candidates = profile_persistence.loadTaxFormProfileCandidatesForForm(
        store,
        allocator,
        profile_id,
        tax_year - 1,
        form_code,
    ) catch return null;
    defer candidates.deinit(allocator);
    var source: ?*const tax_form_profile_domain.Revision = null;
    for (candidates.revisions) |*candidate| {
        if (candidate.review_state != .confirmed) continue;
        if (source == null or taxFormProfileCandidateIsLater(
            candidate,
            source.?,
        )) {
            source = candidate;
        }
    }
    const revision = source orelse return null;
    const current_form_revision = definition.revision orelse return null;
    const current_spec_revision = definition.tax_form_profile.spec_revision orelse
        return null;
    const current_spec_hash = definition.tax_form_profile.spec_hash orelse
        return null;
    const compatibility: tax_form_profile_ui.CopyCompatibility =
        if (std.mem.eql(
            u8,
            revision.stream.form_revision.asSlice(),
            current_form_revision,
        ) and revision.spec_revision == current_spec_revision and
        std.mem.eql(
            u8,
            revision.spec_hash.asSlice(),
            current_spec_hash,
        ))
            .exact
        else
            .requires_mapping_review;
    return .{
        .source = tax_form_profile_ui.RevisionIdentity.fromRevision(revision),
        .compatibility = compatibility,
        .reason = if (compatibility == .exact)
            .prior_year
        else
            .form_revision_mapping,
    };
}

fn taxFormProfileCandidateIsLater(
    candidate: *const tax_form_profile_domain.Revision,
    current: *const tax_form_profile_domain.Revision,
) bool {
    const candidate_confirmed = candidate.confirmed_at_unix orelse
        std.math.minInt(i64);
    const current_confirmed = current.confirmed_at_unix orelse
        std.math.minInt(i64);
    if (candidate_confirmed != current_confirmed) {
        return candidate_confirmed > current_confirmed;
    }
    const revision_order = std.mem.order(
        u8,
        candidate.stream.form_revision.asSlice(),
        current.stream.form_revision.asSlice(),
    );
    if (revision_order != .eq) return revision_order == .gt;
    if (candidate.sequence != current.sequence) {
        return candidate.sequence > current.sequence;
    }
    return std.mem.order(
        u8,
        candidate.id.asSlice(),
        current.id.asSlice(),
    ) == .gt;
}

fn refreshOpenedTaxFormProfileHistory(model: *Model) void {
    model.taxFormProfileHistoryRowCount = 0;
    model.taxFormProfileHistoryTruncated = false;
    const identity = model.taxFormProfilePage.viewedIdentity() orelse return;
    const form_revision = identity.form_revision orelse return;
    const allocator = model.taxProfiles.allocator orelse return;
    const store = model.taxProfiles.store orelse return;
    const stream: tax_form_profile_domain.StreamKey = .{
        .profile_id = identity.profile_id,
        .tax_year = identity.tax_year,
        .form_code = identity.form_code,
        .form_revision = form_revision,
    };
    var history = profile_persistence.loadTaxFormProfileHistory(
        store,
        allocator,
        stream,
    ) catch return;
    defer history.deinit(allocator);
    cacheTaxFormProfileHistory(
        model,
        history.history.revisions,
        identity.annual_revision_sequence,
    );
}

fn stageTaxFormProfileOfferedReuse(
    model: *Model,
    expected_reason: tax_form_profile_ui.ReuseReason,
) void {
    const offer = model.taxFormProfilePage.copy_offer orelse return;
    if (offer.reason != expected_reason) return;
    const allocator = model.taxProfiles.allocator orelse return;
    const store = model.taxProfiles.store orelse return;
    if (expected_reason == .form_revision_mapping) {
        var candidates = profile_persistence.loadTaxFormProfileCandidatesForForm(
            store,
            allocator,
            offer.source.profile_id,
            offer.source.tax_year,
            offer.source.form_code,
        ) catch return;
        defer candidates.deinit(allocator);
        for (candidates.revisions) |*revision| {
            if (!taxFormProfileRevisionMatchesIdentity(
                revision,
                offer.source,
            )) continue;
            model.taxFormProfilePage.stageFormRevisionMapping(
                revision.values,
            ) catch return;
            model.taxFormProfilePickerField = null;
            loadTaxFormProfileChoices(model);
            return;
        }
        return;
    }
    const stream: tax_form_profile_domain.StreamKey = .{
        .profile_id = offer.source.profile_id,
        .tax_year = offer.source.tax_year,
        .form_code = offer.source.form_code,
        .form_revision = offer.source.form_revision,
    };
    var history = profile_persistence.loadTaxFormProfileHistory(
        store,
        allocator,
        stream,
    ) catch return;
    defer history.deinit(allocator);
    for (history.history.revisions) |*revision| {
        if (revision.sequence != offer.source.revision_sequence or
            !revision.id.eql(&offer.source.revision_id)) continue;
        switch (expected_reason) {
            .prior_year => model.taxFormProfilePage.stagePriorYearCopy(
                revision.values,
            ) catch return,
            .reactivation => model.taxFormProfilePage.stageReactivationReuse(
                revision.values,
            ) catch return,
            .form_revision_mapping => unreachable,
        }
        model.taxFormProfilePickerField = null;
        loadTaxFormProfileChoices(model);
        return;
    }
}

fn taxFormProfileRevisionMatchesIdentity(
    revision: *const tax_form_profile_domain.Revision,
    identity: tax_form_profile_ui.RevisionIdentity,
) bool {
    return revision.stream.profile_id.eql(&identity.profile_id) and
        revision.stream.tax_year == identity.tax_year and
        revision.stream.form_code.eql(&identity.form_code) and
        revision.stream.form_revision.eql(&identity.form_revision) and
        revision.spec_revision == identity.spec_revision and
        revision.spec_hash.eql(&identity.spec_hash) and
        revision.sequence == identity.revision_sequence and
        revision.id.eql(&identity.revision_id);
}

fn acceptTaxFormProfileConflictBase(model: *Model) void {
    const conflict = model.taxFormProfilePage.conflict orelse return;
    model.taxFormProfilePage.acceptReviewedConflictBase(
        conflict.current_sequence,
    ) catch return;
}

fn reloadTaxFormProfileAfterConflict(model: *Model) void {
    const conflict = model.taxFormProfilePage.conflict orelse return;
    const identity = model.taxFormProfilePage.viewedIdentity() orelse return;
    const form_revision = identity.form_revision orelse return;
    const allocator = model.taxProfiles.allocator orelse return;
    const store = model.taxProfiles.store orelse return;
    const stream: tax_form_profile_domain.StreamKey = .{
        .profile_id = identity.profile_id,
        .tax_year = identity.tax_year,
        .form_code = identity.form_code,
        .form_revision = form_revision,
    };
    var history = profile_persistence.loadTaxFormProfileHistory(
        store,
        allocator,
        stream,
    ) catch return;
    defer history.deinit(allocator);
    const activation = model.taxFormProfilePage.activationPeriod() orelse
        return;
    var selected_revision: ?*const tax_form_profile_domain.Revision = null;
    for (history.history.revisions) |*revision| {
        if (!revision.effective.eql(activation)) continue;
        if (selected_revision == null or
            revision.sequence > selected_revision.?.sequence)
        {
            selected_revision = revision;
        }
    }
    model.taxFormProfilePage.reloadAfterConflict(
        selected_revision,
        conflict.current_sequence,
    ) catch return;
    model.taxFormProfilePickerField = null;
    loadTaxFormProfileChoices(model);
    cacheTaxFormProfileHistory(
        model,
        history.history.revisions,
        if (selected_revision) |revision| revision.sequence else 0,
    );
    refreshOpenedTaxFormProfileBindingReadiness(model);
}

fn refreshOpenedRuntimeComposedSnapshot(model: *Model) void {
    model.taxFormProfileComposed = .{};
    const identity = model.taxFormProfilePage.viewedIdentity() orelse return;
    const index = model.taxFormProfileFormIndex orelse return;
    if (index >= form_catalog.registry_count) return;
    const definition = &form_catalog.forms[index];
    if (!std.mem.eql(u8, definition.code, "2551Q")) return;
    const quarter = model.annualIncomeTaxElection.filing_quarter;
    if (quarter < 1 or quarter > 4) return;
    const filing: form_period.FilingPeriod = .{ .quarterly = .{
        .tax_year = identity.tax_year,
        .quarter = quarter,
    } };
    model.taxFormProfileComposed = loadRuntimeComposedSnapshot(
        model,
        definition,
        identity.profile_id,
        identity.tax_year,
        filing,
        &model.taxFormProfilePage,
    ) catch return;
    // The annual UI cache retains eligibility/editing context; lifecycle and
    // provenance come from the same composed event used by readiness.
    model.annualIncomeTaxElection.current =
        model.taxFormProfileComposed.current_annual;
}

fn openTaxFormProfileForYearAt(
    model: *Model,
    index: usize,
    tax_year: u16,
    requested: ?profile_model.Date,
    preserve_return_page: bool,
    requested_filing: ?form_period.FilingPeriod,
) void {
    if (index >= form_catalog.registry_count) return;
    if (!model.taxFormProfileCardStatesReady) {
        refreshProfileFormLaunchAssessments(model);
    }
    const definition = &form_catalog.forms[index];
    if (definition.status == .calendar_only or
        definition.tax_form_profile.mode == .calendar_only) return;
    const profile_id = model.taxProfiles.selectedProfileDomainId() orelse
        return;
    const activation_context = profileFormActivationContext(
        model,
        profile_id,
        definition,
        tax_year,
        requested,
    );
    const viewed_on = if (activation_context) |context|
        context.viewed_on
    else
        tax_form_profile_domain.Date.init(tax_year, 12, 31) catch return;
    const activation_period = if (activation_context) |context|
        context.effective
    else
        null;
    const active = activation_period != null;
    var opening_composed: RuntimeComposedSnapshot = .{};
    var pilot_filing: ?form_period.FilingPeriod = null;
    const inherited = if (std.mem.eql(u8, definition.code, "2551Q")) blk: {
        const default_filing: form_period.FilingPeriod = .{ .quarterly = .{
            .tax_year = tax_year,
            .quarter = selectedFormQuarter(model, definition.code),
        } };
        const filing = if (requested_filing) |candidate| requested: {
            candidate.validate() catch break :requested default_filing;
            if (candidate.taxYear() != tax_year or
                candidate.cadence() != .quarterly)
            {
                break :requested default_filing;
            }
            break :requested candidate;
        } else default_filing;
        pilot_filing = filing;
        opening_composed = loadRuntimeComposedSnapshot(
            model,
            definition,
            profile_id,
            tax_year,
            filing,
            null,
        ) catch .{};
        break :blk inheritedReadinessFromComposed(
            definition,
            &opening_composed,
        );
    } else inheritedReadinessForForm(
        model,
        definition,
        index,
        viewed_on,
    );

    var history_exists = false;
    var stream_sequence: u32 = 0;
    var saved_revision: ?*const tax_form_profile_domain.Revision = null;
    var reactivation_offer: ?tax_form_profile_ui.CopyOffer = null;
    var owned_history: ?profile_persistence.OwnedTaxFormProfileHistory = null;
    defer if (owned_history) |*owned| {
        if (model.taxProfiles.allocator) |allocator| owned.deinit(allocator);
    };
    if (taxFormProfileStream(profile_id, definition, tax_year)) |stream| {
        const allocator = model.taxProfiles.allocator orelse return;
        const store = model.taxProfiles.store orelse return;
        owned_history = profile_persistence.loadTaxFormProfileHistory(
            store,
            allocator,
            stream,
        ) catch null;
        if (owned_history) |*owned| {
            history_exists = owned.history.revisions.len != 0;
            stream_sequence = owned.history.currentSequence();
            for (owned.history.revisions) |*revision| {
                if (!active or revision.effective.eql(activation_period.?)) {
                    if (saved_revision == null or
                        revision.sequence > saved_revision.?.sequence)
                    {
                        saved_revision = revision;
                    }
                    continue;
                }
                if (revision.review_state != .confirmed or
                    revision.spec_revision !=
                        (definition.tax_form_profile.spec_revision orelse continue) or
                    !std.mem.eql(
                        u8,
                        revision.spec_hash.asSlice(),
                        definition.tax_form_profile.spec_hash orelse continue,
                    )) continue;
                if (reactivation_offer == null or
                    revision.sequence >
                        reactivation_offer.?.source.revision_sequence)
                {
                    reactivation_offer = .{
                        .source = tax_form_profile_ui.RevisionIdentity.fromRevision(
                            revision,
                        ),
                        .compatibility = .exact,
                        .reason = .reactivation,
                    };
                }
            }
        }
    }
    const copy_offer = if (active and saved_revision == null)
        reactivation_offer orelse priorYearTaxFormProfileOffer(
            model,
            profile_id,
            definition,
            tax_year,
        )
    else
        null;
    const viewed_launch = launchAssessmentForViewedDate(
        model,
        definition,
        index,
        viewed_on,
    );
    model.taxFormProfilePage = tax_form_profile_ui.State.open(.{
        .profile_id = profile_id,
        .tax_year = tax_year,
        .form_code = definition.code,
        .active = active,
        .activation_period = activation_period,
        .history_exists = history_exists,
        .inherited = inherited,
        .annual_setup_required = viewed_launch.status == .needs_activity_selection,
        .saved_revision = saved_revision,
        .expected_current_sequence = stream_sequence,
        .copy_offer = copy_offer,
    }) catch return;
    if (active) {
        const bindings = resolveTaxFormProfileBindings(
            model,
            definition,
            profile_id,
            viewed_on,
            saved_revision,
            viewed_launch.status == .needs_activity_selection,
        ) catch null;
        model.taxFormProfilePage.setSavedBindingsResolved(
            bindings != null and bindings.?.status == .ready,
        ) catch return;
    }
    model.taxFormProfileFormIndex = index;
    model.taxFormProfileViewedDate = viewed_on;
    model.taxFormProfileComposed = opening_composed;
    if (pilot_filing) |filing| {
        model.annualIncomeTaxElection.filing_quarter = filing.quarter().?;
    }
    openTaxpayerYearSettings(model, profile_id, tax_year, viewed_on);
    refreshOpenedRuntimeComposedSnapshot(model);
    model.taxFormProfilePreviousSegmentDate = if (activation_context) |context|
        context.previous_viewed_on
    else
        null;
    model.taxFormProfileNextSegmentDate = if (activation_context) |context|
        context.next_viewed_on
    else
        null;
    if (!preserve_return_page) {
        model.taxFormProfileReturnPage = model.contentPage();
        model.taxFormProfileReturnDashboardSection = model.dashboardSection;
        model.taxFormProfileReturnProfileSection = model.profileSetupSection;
    }
    model.taxFormProfilePendingNavigation = null;
    model.taxFormProfileDiscardPromptOpen = false;
    model.taxFormProfileRegistrationReturnPending = false;
    const inherited_on = if (model.taxFormProfileComposed.filing_context) |context|
        context.effectiveOn()
    else
        viewed_on;
    loadTaxFormProfileInherited(model, profile_id, inherited_on);
    loadTaxFormProfileChoices(model);
    if (owned_history) |*owned| {
        cacheTaxFormProfileHistory(
            model,
            owned.history.revisions,
            model.taxFormProfilePage.viewedIdentity().?.annual_revision_sequence,
        );
    } else {
        model.taxFormProfileHistoryRowCount = 0;
        model.taxFormProfileHistoryTruncated = false;
    }
    navigate(model, .tax_form_profile);
}

fn openTaxFormProfileForYear(
    model: *Model,
    index: usize,
    tax_year: u16,
) void {
    openTaxFormProfileForYearAt(model, index, tax_year, null, false, null);
}

fn requestTaxFormProfileSegment(
    model: *Model,
    target: ?profile_model.Date,
) void {
    const viewed_on = target orelse return;
    const form_index = model.taxFormProfileFormIndex orelse return;
    const identity = model.taxFormProfilePage.viewedIdentity() orelse return;
    if (viewed_on.year != identity.tax_year) return;
    const filing = if (model.taxFormProfileComposed.filing_context) |context|
        context.period
    else
        null;
    if (model.taxFormProfilePage.dirty() or model.taxpayerYearPage.dirty()) {
        model.taxFormProfilePendingNavigation = .{
            .activation_segment = .{
                .form_index = form_index,
                .tax_year = identity.tax_year,
                .viewed_on = viewed_on,
                .filing = filing,
            },
        };
        model.taxFormProfileDiscardPromptOpen = true;
        return;
    }
    openTaxFormProfileForYearAt(
        model,
        form_index,
        identity.tax_year,
        viewed_on,
        true,
        filing,
    );
}

fn openTaxFormProfile(model: *Model, index: usize) void {
    const year_value = profileBrowseAvailabilityYear(model);
    if (year_value < 1 or year_value > 9999) return;
    openTaxFormProfileForYear(model, index, @intCast(year_value));
}

fn closeTaxFormProfile(model: *Model) void {
    if (model.taxFormProfilePage.dirty() or
        model.taxpayerYearPage.dirty())
    {
        model.taxFormProfilePendingNavigation = .{ .return_context = {} };
        model.taxFormProfileDiscardPromptOpen = true;
        return;
    }
    model.taxFormProfilePage.reset();
    model.taxpayerYearPage.reset();
    model.annualIncomeTaxElection = .{};
    model.taxFormProfileComposed = .{};
    model.taxFormProfileFormIndex = null;
    model.taxFormProfileViewedDate = null;
    model.taxFormProfilePreviousSegmentDate = null;
    model.taxFormProfileNextSegmentDate = null;
    model.taxFormProfilePendingNavigation = null;
    model.taxFormProfileDiscardPromptOpen = false;
    model.taxFormProfileRegistrationReturnPending = false;
    model.taxFormProfilePickerField = null;
    model.taxFormProfileChoiceCount = 0;
    model.taxFormProfileInherited = .{};
    model.taxFormProfileHistoryRowCount = 0;
    model.taxFormProfileHistoryTruncated = false;
    restoreTaxFormProfileReturnContext(model);
}

fn restoreTaxFormProfileReturnContext(model: *Model) void {
    const destination = model.taxFormProfileReturnPage;
    navigate(model, destination);
    if (destination != .taxpayer_dashboard) return;
    model.dashboardSection = model.taxFormProfileReturnDashboardSection;
    model.profileSetupSection = model.taxFormProfileReturnProfileSection;
}

fn selectTaxFormProfileChoice(model: *Model, choice_index: usize) void {
    if (choice_index >= model.taxFormProfileChoiceCount) return;
    const form_index = model.taxFormProfileFormIndex orelse return;
    if (form_index >= form_catalog.registry_count) return;
    const choice = &model.taxFormProfileChoices[choice_index];
    const definition = &form_catalog.forms[form_index];
    if (choice.field_index >= definition.tax_form_profile.values.len) return;
    const field_definition = definition.tax_form_profile.values[choice.field_index];
    const scalar: tax_form_profile_domain.ScalarValue = switch (field_definition.value_type) {
        .profile_id => .{
            .profile_id = profile_model.ProfileId.parse(
                choice.stable_id.text(),
            ) catch return,
        },
        .business_activity_anchor_id => .{
            .business_activity_anchor_id = tax_form_profile_domain.ComponentAnchorId.parse(
                choice.stable_id.text(),
            ) catch return,
        },
        .registration_obligation_anchor_id => .{
            .registration_obligation_anchor_id = tax_form_profile_domain.ComponentAnchorId.parse(
                choice.stable_id.text(),
            ) catch return,
        },
        .text,
        .boolean,
        .integer,
        .date,
        .year,
        .choice,
        => return,
    };
    model.taxFormProfilePage.setDraftValue(.{
        .semantic_key = field_definition.semantic_key,
        .role = field_definition.role,
        .value = scalar,
    }) catch return;
    loadTaxFormProfileChoices(model);
}

fn saveTaxFormProfile(model: *Model) void {
    const intent = model.taxFormProfilePage.beginSave() catch return;
    const allocator = model.taxProfiles.allocator orelse {
        _ = model.taxFormProfilePage.saveFailed() catch {};
        return;
    };
    const store = model.taxProfiles.store orelse {
        _ = model.taxFormProfilePage.saveFailed() catch {};
        return;
    };
    if (intent.expected_sequence == std.math.maxInt(u32)) {
        _ = model.taxFormProfilePage.saveFailed() catch {};
        return;
    }
    const generated_id = store.generateOpaqueId() catch {
        _ = model.taxFormProfilePage.saveFailed() catch {};
        return;
    };
    const copied_from = intent.copied_from;
    const revision: tax_form_profile_domain.Revision = .{
        .id = tax_form_profile_domain.RevisionId.parse(
            &generated_id,
        ) catch {
            _ = model.taxFormProfilePage.saveFailed() catch {};
            return;
        },
        .stream = .{
            .profile_id = intent.identity.profile_id,
            .tax_year = intent.identity.tax_year,
            .form_code = intent.identity.form_code,
            .form_revision = intent.identity.form_revision orelse {
                _ = model.taxFormProfilePage.saveFailed() catch {};
                return;
            },
        },
        .sequence = intent.expected_sequence + 1,
        .effective = intent.effective,
        .spec_revision = intent.identity.spec_revision orelse {
            _ = model.taxFormProfilePage.saveFailed() catch {};
            return;
        },
        .spec_hash = intent.identity.spec_hash orelse {
            _ = model.taxFormProfilePage.saveFailed() catch {};
            return;
        },
        .review_state = .confirmed,
        .confirmed_at_unix = @intCast(c_time.time(null)),
        .source = if (copied_from) |source| switch (intent.review_requirement) {
            .prior_year_copy, .form_revision_mapping => .{ .copied_from_prior_year = .{
                .source_tax_year = source.tax_year,
                .source_form_revision = source.form_revision,
                .source_spec_revision = source.spec_revision,
                .source_spec_hash = source.spec_hash,
                .source_revision_id = source.revision_id,
            } },
            // Same-year reactivation is a newly confirmed manual revision for
            // the new activation interval. Each reused value retains its exact
            // copied-from revision ID, so provenance is not mislabelled as a
            // prior-year copy.
            .reactivation => .manual_entry,
            .none, .persisted_unconfirmed_revision => .manual_entry,
        } else .manual_entry,
        .values = intent.values,
    };
    profile_persistence.appendTaxFormProfileRevision(
        store,
        allocator,
        intent.expected_sequence,
        &revision,
    ) catch |err| {
        if (err == profile_store.Error.RevisionConflict) {
            var history = profile_persistence.loadTaxFormProfileHistory(
                store,
                allocator,
                revision.stream,
            ) catch {
                _ = model.taxFormProfilePage.saveFailed() catch {};
                return;
            };
            defer history.deinit(allocator);
            var current_sequence: u32 = 0;
            for (history.history.revisions) |item| {
                current_sequence = @max(current_sequence, item.sequence);
            }
            model.taxFormProfilePage.noteConflict(current_sequence) catch {};
        } else {
            _ = model.taxFormProfilePage.saveFailed() catch {};
        }
        return;
    };
    model.taxFormProfilePage.saveSucceeded(&revision) catch return;
    model.taxFormProfilePickerField = null;
    refreshOpenedTaxFormProfileHistory(model);
    refreshTaxFormProfileCardStates(model);
    refreshOpenedTaxFormProfileBindingReadiness(model);
    refreshOpenedRuntimeComposedSnapshot(model);
}

fn saveTaxpayerYearSettings(model: *Model) void {
    if (annualElectionPilotOpen(model)) {
        saveAnnualIncomeTaxElectionCandidate(model);
        return;
    }
    const intent = model.taxpayerYearPage.beginSave() catch return;
    const allocator = model.taxProfiles.allocator orelse {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    };
    const store = model.taxProfiles.store orelse {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    };
    const generated_id = store.generateOpaqueId() catch {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    };
    const revision = intent.confirmedRevision(
        taxpayer_year_settings_domain.RevisionId.parse(
            &generated_id,
        ) catch {
            _ = model.taxpayerYearPage.saveFailed() catch {};
            return;
        },
        @intCast(c_time.time(null)),
    ) catch {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    };
    profile_persistence.appendTaxpayerYearRevision(
        store,
        allocator,
        intent.expected_sequence,
        &revision,
    ) catch |err| {
        if (err == profile_store.Error.RevisionConflict) {
            var history = profile_persistence.loadTaxpayerYearHistory(
                store,
                allocator,
                revision.stream,
            ) catch {
                _ = model.taxpayerYearPage.saveFailed() catch {};
                return;
            };
            defer history.deinit(allocator);
            model.taxpayerYearPage.noteConflict(
                history.history.currentSequence(),
            ) catch {};
        } else {
            _ = model.taxpayerYearPage.saveFailed() catch {};
        }
        return;
    };
    model.taxpayerYearPage.saveSucceeded(&revision) catch return;
    refreshTaxFormProfileCardStates(model);
}

fn saveAnnualIncomeTaxElectionCandidate(model: *Model) void {
    if (!annualIncomeTaxElectionCandidateEditable(model)) return;
    _ = model.taxpayerYearPage.beginSave() catch return;
    const identity = model.taxFormProfilePage.viewedIdentity() orelse {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    };
    const form_index = model.taxFormProfileFormIndex orelse {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    };
    if (form_index >= form_catalog.registry_count) {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    }
    const definition = &form_catalog.forms[form_index];
    const revision_text = definition.revision orelse {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    };
    const choice: annual_income_tax_election.Choice = switch (taxpayerYearRateElection(model) orelse {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    }) {
        .graduated => .graduated,
        .eight_percent => .eight_percent,
    };
    const store = model.taxProfiles.store orelse {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    };
    const result = profile_persistence.stageAnnualIncomeTaxElectionCandidate(
        store,
        .{
            .stream = .{
                .profile_id = identity.profile_id,
                .tax_year = identity.tax_year,
            },
            .expected_current_sequence = if (model.annualIncomeTaxElection.current) |event|
                event.sequence
            else
                0,
            .choice = choice,
            .commencement = model.annualIncomeTaxElection.commencement,
            .provenance = .{
                .kind = .form_2551q,
                .form_revision = annual_income_tax_election.FormRevision.parse(
                    revision_text,
                ) catch {
                    _ = model.taxpayerYearPage.saveFailed() catch {};
                    return;
                },
                .filing_quarter = model.annualIncomeTaxElection.filing_quarter,
            },
            .occurred_at_unix_seconds = @intCast(c_time.time(null)),
        },
    ) catch {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    };
    _ = result;
    const viewed_on = model.taxFormProfileViewedDate orelse {
        _ = model.taxpayerYearPage.saveFailed() catch {};
        return;
    };
    openAnnualIncomeTaxElection(
        model,
        identity.profile_id,
        identity.tax_year,
        viewed_on,
    );
    refreshOpenedRuntimeComposedSnapshot(model);
    refreshTaxFormProfileCardStates(model);
    refreshOpenedTaxFormProfileBindingReadiness(model);
}

fn resolveTaxpayerYearConflict(model: *Model, keep_draft: bool) void {
    const conflict = model.taxpayerYearPage.pendingConflict() orelse return;
    const identity = model.taxpayerYearPage.viewedIdentity() orelse return;
    const allocator = model.taxProfiles.allocator orelse return;
    const store = model.taxProfiles.store orelse return;
    var history = profile_persistence.loadTaxpayerYearHistory(
        store,
        allocator,
        identity.stream,
    ) catch return;
    defer history.deinit(allocator);
    for (history.history.revisions) |*revision| {
        if (revision.sequence != conflict.current_sequence) continue;
        if (keep_draft) {
            model.taxpayerYearPage.keepDraftAfterConflict(revision) catch
                return;
        } else {
            model.taxpayerYearPage.reloadSavedAfterConflict(revision) catch
                return;
        }
        return;
    }
}

fn openLibraryForm(model: *Model, index: usize) void {
    if (index >= form_catalog.forms.len) return;
    const definition = &form_catalog.forms[index];
    if (definition.status != .static_layout) return;
    const tax_year = profileBrowseAvailabilityYear(model);
    if (tax_year < 1 or tax_year > 9999) return;
    const year: u16 = @intCast(tax_year);
    const filing = libraryFilingPeriod(model, definition, year);
    const occurrence_date = switch (filing) {
        .on_demand => currentOccurrenceDate(model, year),
        .monthly, .quarterly, .annual => null,
    };
    if (!formAvailableForFiling(
        model,
        definition,
        filing,
        occurrence_date,
    )) return;
    const quarter = filing.quarter() orelse switch (filing) {
        .annual => 4,
        .on_demand => selectedFormQuarter(model, definition.code),
        else => selectedFormQuarter(model, definition.code),
    };
    const launch = assessProfileFormLaunch(
        model,
        definition.code,
        tax_year,
        quarter,
        filing.month(),
        filing,
    );
    switch (launch.status) {
        .needs_profile => {
            openProfileCompletion(model, index, launch, .{
                .form_index = index,
                .tax_year = tax_year,
                .quarter = quarter,
                .period_month = filing.month(),
                .spouse_profile_id = null,
                .filing = filing,
            });
            return;
        },
        .profile_not_eligible, .unavailable => return,
        .ready_new, .ready_resume, .needs_activity_selection => {},
    }
    const route = profileFormRoute(definition.code) orelse return;
    _ = openProfileBoundFormForQuarter(
        model,
        route.page,
        route.form_code,
        tax_year,
        quarter,
        filing.month(),
        null,
        filing,
    );
}

fn libraryPeriodMatchesBrowseFilters(
    model: *const Model,
    filing: form_period.FilingPeriod,
) bool {
    return switch (filing) {
        .monthly => |period| model.libraryFilter.month_mask == 0 or
            model.libraryFilter.month_mask &
                (@as(u16, 1) << @intCast(period.month - 1)) != 0,
        .quarterly => |period| model.libraryFilter.quarter_mask == 0 or
            model.libraryFilter.quarter_mask &
                (@as(u8, 1) << @intCast(period.quarter - 1)) != 0,
        .annual, .on_demand => true,
    };
}

/// Opens the exact period represented by one library tile. The primitive
/// action ID is decoded against generated catalog metadata and every
/// profile/year/capability guard is rechecked at dispatch time.
fn openLibraryPeriod(model: *Model, action_id: usize) void {
    if (model.taxProfiles.managing_forms) return;
    const index = action_id / 16;
    const slot = action_id % 16;
    if (index >= form_catalog.forms.len or slot >= 12) return;
    const definition = &form_catalog.forms[index];
    if (definition.status != .static_layout) return;
    if (!model.libraryCadenceSelected(definition.cadence)) return;
    const tax_year = profileBrowseAvailabilityYear(model);
    if (tax_year < 1 or tax_year > 9999) return;
    const year: u16 = @intCast(tax_year);
    var filing = if (definition.cadence == .on_demand)
        (if (slot == 0)
            newOnDemandAssessmentPeriod(
                model.taxProfiles.draftSummaries(),
                definition.code,
                year,
            )
        else
            onDemandDraftPeriodForSlot(
                model.taxProfiles.draftSummaries(),
                definition.code,
                year,
                slot,
            )) orelse return
    else
        libraryPeriodForSlot(definition, year, slot) orelse return;
    if (!libraryPeriodMatchesBrowseFilters(model, filing)) return;
    const occurrence_date = switch (filing) {
        .on_demand => currentOccurrenceDate(model, year),
        .monthly, .quarterly, .annual => null,
    };
    if (!formAvailableForFiling(
        model,
        definition,
        filing,
        occurrence_date,
    )) return;

    var quarter = filing.quarter() orelse switch (filing) {
        .annual => 4,
        .on_demand => selectedFormQuarter(model, definition.code),
        else => selectedFormQuarter(model, definition.code),
    };
    var launch = assessProfileFormLaunch(
        model,
        definition.code,
        tax_year,
        quarter,
        filing.month(),
        filing,
    );
    switch (launch.status) {
        .needs_profile => {
            openProfileCompletion(model, index, launch, .{
                .form_index = index,
                .tax_year = tax_year,
                .quarter = quarter,
                .period_month = filing.month(),
                .spouse_profile_id = null,
                .filing = filing,
            });
            return;
        },
        .profile_not_eligible, .unavailable => return,
        .ready_new, .ready_resume, .needs_activity_selection => {},
    }

    if (definition.cadence == .on_demand and slot == 0) {
        const store = model.formProfiles.store orelse {
            model.taxProfiles.reportFormLaunchFailure(
                "On-demand filing storage is unavailable.",
            );
            return;
        };
        const profile_id = model.taxProfiles.selectedProfileDomainId() orelse
            return;
        const revision = definition.revision orelse return;
        const owner_id = store.localOwnerId() catch {
            model.taxProfiles.reportFormLaunchFailure(
                "Could not verify the filing owner. Try again.",
            );
            return;
        };
        const occurrence = store.allocateOnDemandOccurrence(.{
            .owner_id = owner_id[0..],
            .profile_id = profile_id.asSlice(),
            .form_code = definition.code,
            .form_revision = revision,
            .tax_year = tax_year,
        }) catch {
            model.taxProfiles.reportFormLaunchFailure(
                "Could not reserve a new on-demand filing. Try again.",
            );
            return;
        };
        filing = .{ .on_demand = .{
            .tax_year = year,
            .occurrence = occurrence,
        } };
        quarter = selectedFormQuarter(model, definition.code);
        launch = assessProfileFormLaunch(
            model,
            definition.code,
            tax_year,
            quarter,
            null,
            filing,
        );
        switch (launch.status) {
            .profile_not_eligible, .unavailable => {
                model.taxProfiles.reportFormLaunchFailure(
                    "The new on-demand filing could not be opened.",
                );
                return;
            },
            .needs_profile => {
                openProfileCompletion(model, index, launch, .{
                    .form_index = index,
                    .tax_year = tax_year,
                    .quarter = quarter,
                    .period_month = filing.month(),
                    .spouse_profile_id = null,
                    .filing = filing,
                });
                return;
            },
            .ready_new, .ready_resume, .needs_activity_selection => {},
        }
    }

    const route = profileFormRoute(definition.code) orelse return;
    _ = openProfileBoundFormForQuarter(
        model,
        route.page,
        route.form_code,
        tax_year,
        quarter,
        filing.month(),
        null,
        filing,
    );
}

fn assessProfileFormLaunch(
    model: *const Model,
    form_code: []const u8,
    tax_year: i32,
    quarter: u8,
    period_month: ?u8,
    filing: ?form_period.FilingPeriod,
) form_ui.LaunchAssessment {
    const profile_id = model.taxProfiles.selectedProfileDomainId() orelse
        return .{};
    if (tax_year < 1 or tax_year > 9999) return .{};
    const revision = editorRevision(form_code) orelse return .{};
    const year: u16 = @intCast(tax_year);
    return model.formProfiles.assessLaunch(.{
        .form = revision,
        .filer_profile_id = profile_id,
        .tax_year = year,
        .quarter = quarter,
        .filing_period = filing,
        .profile_as_of = profileAsOfForForm(
            model,
            form_code,
            year,
            quarter,
            period_month,
        ),
    });
}

fn filingForProfileLaunch(
    model: *const Model,
    definition: *const form_catalog.FormDefinition,
    tax_year: u16,
    quarter: u8,
    period_month: ?u8,
    requested: ?form_period.FilingPeriod,
) ?form_period.FilingPeriod {
    if (requested) |filing| return filing;
    return switch (definition.cadence) {
        .monthly => blk: {
            const month = period_month orelse
                @as(u8, @intCast(std.math.clamp(
                    model.calendar.selected_month,
                    1,
                    12,
                )));
            if (month < 1 or month > 12) break :blk null;
            break :blk .{ .monthly = .{
                .tax_year = tax_year,
                .month = month,
            } };
        },
        .quarterly => if (quarter >= 1 and quarter <= 4)
            .{ .quarterly = .{
                .tax_year = tax_year,
                .quarter = quarter,
            } }
        else
            null,
        .annual => .{ .annual = .{ .tax_year = tax_year } },
        // A new on-demand filing must be allocated by the library path and an
        // existing one must carry its exact key. Never invent an occurrence
        // from a generic form shortcut.
        .on_demand => null,
    };
}

fn openProfileCompletion(
    model: *Model,
    form_index: usize,
    assessment: form_ui.LaunchAssessment,
    pending: PendingProfileFormLaunch,
) void {
    model.profileCompletionTarget = assessment.first_missing_field;
    model.profileCompletionFormIndex = form_index;
    model.pendingProfileFormLaunch = pending;
    model.profileSetupSection = .tax_profile;
    beginCompleteProfileEdit(model);
    model.dashboardSection = .profile_settings;
    navigate(model, .taxpayer_dashboard);
}

const ProfileDeadlineActionDispatch = struct {
    projection_generation: u32,
    deadline_id: u64,
    action: ProfileDeadlineAction,
};

fn decodeProfileDeadlineActionDispatch(
    dispatch_id: u64,
) ?ProfileDeadlineActionDispatch {
    const payload = dispatch_id & profile_deadline_dispatch_payload_mask;
    const raw_action = payload % profile_deadline_action_kind_count;
    const action: ProfileDeadlineAction = @enumFromInt(
        @as(u8, @intCast(raw_action)),
    );
    if (action == .none) return null;
    return .{
        .projection_generation = @intCast(
            dispatch_id >> profile_deadline_dispatch_payload_bits,
        ),
        .deadline_id = payload / profile_deadline_action_kind_count,
        .action = action,
    };
}

fn toggleProfileDeadlineActionMenu(model: *Model, menu_id: u64) void {
    var available = false;
    const lanes = [_]ProfileDeadlineLane{
        .deadlines,
        .action_required,
        .overdue,
    };
    for (
        model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count],
    ) |deadline| {
        if (!model.profileCalendarViewIncludesDeadline(&deadline)) continue;
        const row = model.profileCalendarDeadlineRow(deadline);
        if (!row.multipleActions()) continue;
        for (lanes) |lane| {
            if (profileDeadlineMenuId(
                model.profileDeadlineProjectionGeneration,
                deadline.id,
                lane,
            ) == menu_id) {
                available = true;
                break;
            }
        }
        if (available) break;
    }
    if (!available) return;
    model.profileDeadlineActionMenuId =
        if (model.profileDeadlineActionMenuId == menu_id)
            null
        else
            menu_id;
}

fn showProfileDeadlineAdjustment(model: *Model, dispatch_id: u64) void {
    const generation: u32 = @intCast(
        dispatch_id >> profile_deadline_dispatch_payload_bits,
    );
    if (generation != model.profileDeadlineProjectionGeneration) return;
    const id = dispatch_id & profile_deadline_dispatch_payload_mask;
    const deadline = model.profileDeadlineById(id) orelse return;
    if (!deadline.adjustmentVisible() and deadline.status != .extended) return;
    model.profileDeadlineActionMenuId = null;
    model.profileDeadlineStubAction = .none;
    model.profileDeadlineStubDeadlineId = null;
    model.profileDeadlineAdjustmentId = id;
}

fn showProfileDeadlineStub(
    model: *Model,
    id: u64,
    action: ProfileDeadlineAction,
) void {
    model.profileDeadlineActionMenuId = null;
    model.profileDeadlineAdjustmentId = null;
    model.profileDeadlineStubDeadlineId = id;
    model.profileDeadlineStubAction = action;
}

fn runProfileDeadlineAction(model: *Model, dispatch_id: u64) void {
    const dispatch = decodeProfileDeadlineActionDispatch(dispatch_id) orelse
        return;
    if (dispatch.projection_generation !=
        model.profileDeadlineProjectionGeneration) return;
    const deadline = model.profileDeadlineById(dispatch.deadline_id) orelse
        return;
    if (!model.profileCalendarViewIncludesDeadline(deadline)) return;
    const row = model.profileCalendarDeadlineRow(deadline.*);
    if (!row.actions.contains(dispatch.action)) return;
    model.profileDeadlineActionMenuId = null;
    switch (dispatch.action) {
        .start,
        .complete_profile,
        => openProfileDeadline(model, deadline, null),
        .continue_draft,
        .review_submission,
        => openProfileDeadline(model, deadline, row.draft_id),
        .submit,
        .check_confirmation,
        .print,
        .upload_receipt,
        .pay_online,
        => showProfileDeadlineStub(model, deadline.id, dispatch.action),
        .none => {},
    }
}

fn openProfileDeadline(
    model: *Model,
    deadline: *const calendar_ui.DeadlineRow,
    draft_id: ?form_ids.DraftId,
) void {
    if (!model.profileCalendarViewIncludesDeadline(deadline)) return;
    const route = profileFormRoute(deadline.form_code) orelse return;
    const filing = profileDeadlineFilingPeriod(deadline) orelse return;
    const tax_year: i32 = filing.taxYear();
    const quarter = filing.quarter() orelse switch (filing) {
        .annual => 4,
        .on_demand => return,
        .monthly, .quarterly => unreachable,
    };
    _ = openProfileBoundFormForQuarterDraft(
        model,
        route.page,
        route.form_code,
        tax_year,
        quarter,
        deadline.period.month(),
        null,
        filing,
        draft_id,
    );
}

fn openProfileBoundFormForQuarter(
    model: *Model,
    page: Page,
    form_code: []const u8,
    tax_year: i32,
    quarter: u8,
    period_month: ?u8,
    spouse_profile_id: ?profile_model.ProfileId,
    filing: ?form_period.FilingPeriod,
) bool {
    return openProfileBoundFormForQuarterDraft(
        model,
        page,
        form_code,
        tax_year,
        quarter,
        period_month,
        spouse_profile_id,
        filing,
        null,
    );
}

fn openProfileBoundFormForQuarterDraft(
    model: *Model,
    page: Page,
    form_code: []const u8,
    tax_year: i32,
    quarter: u8,
    period_month: ?u8,
    spouse_profile_id: ?profile_model.ProfileId,
    filing: ?form_period.FilingPeriod,
    draft_id: ?form_ids.DraftId,
) bool {
    if (std.mem.eql(u8, form_code, "1701Q") and
        rejectExact1701QContextChange(model))
    {
        return false;
    }
    const filer_id = model.taxProfiles.selectedProfileDomainId() orelse
        return false;
    const year_value = tax_year;
    if (year_value < 1 or year_value > 9999) return false;
    const year: u16 = @intCast(year_value);
    const definition = catalogDefinitionForDeadline(form_code) orelse
        return false;
    const resolved_filing = filingForProfileLaunch(
        model,
        definition,
        year,
        quarter,
        period_month,
        filing,
    ) orelse return false;
    const occurrence_date = switch (resolved_filing) {
        .on_demand => currentOccurrenceDate(model, year),
        .monthly, .quarterly, .annual => null,
    };
    if (!formAvailableForFiling(
        model,
        definition,
        resolved_filing,
        occurrence_date,
    )) return false;
    const revision = editorRevision(form_code) orelse return false;
    const form_index = formCatalogIndex(form_code) orelse return false;
    const launch = assessProfileFormLaunch(
        model,
        form_code,
        tax_year,
        quarter,
        period_month,
        resolved_filing,
    );
    switch (launch.status) {
        .needs_profile => {
            openProfileCompletion(model, form_index, launch, .{
                .form_index = form_index,
                .tax_year = tax_year,
                .quarter = quarter,
                .period_month = period_month,
                .spouse_profile_id = spouse_profile_id,
                .filing = resolved_filing,
            });
            return false;
        },
        .profile_not_eligible, .unavailable => return false,
        .ready_new, .ready_resume, .needs_activity_selection => {},
    }
    const profile_as_of = profileAsOfForForm(
        model,
        form_code,
        year,
        quarter,
        period_month,
    );
    const bindings = loadLaunchTaxFormProfileBindings(
        model,
        definition,
        form_index,
        filer_id,
        year,
        profile_as_of,
        launch,
    );
    switch (bindings.state) {
        .ready, .inherited_only_ready => {},
        .needs_registration,
        .needs_year_settings,
        .year_settings_reserved,
        .year_settings_require_review,
        .needs_setup,
        .requires_review,
        .needs_filing_context,
        => {
            openTaxFormProfileForYearAt(
                model,
                form_index,
                year,
                profile_as_of,
                false,
                resolved_filing,
            );
            return false;
        },
        .unavailable,
        .calendar_only,
        .needs_tax_profile,
        .error_loading,
        => return false,
    }
    // The annual Tax Form Profile is authoritative. Legacy callers may still
    // carry an old filing-time spouse parameter into the missing-profile
    // completion path above, but it must not override the saved,
    // tax-year-scoped binding used to open the form.
    const open_request: form_ui.OpenRequest = .{
        .form = revision,
        .filer_profile_id = filer_id,
        .spouse_profile_id = bindings.spouse_profile_id,
        .tax_year = year,
        .quarter = quarter,
        .filing_period = resolved_filing,
        .profile_as_of = profile_as_of,
    };
    const open_result = if (std.mem.eql(u8, form_code, "1701Q"))
        model.formProfiles.openExact1701QProjectionOnly(open_request)
    else if (draft_id) |selected_draft_id|
        model.formProfiles.openPersistedDraft(
            open_request,
            selected_draft_id,
        )
    else
        model.formProfiles.open(open_request);
    open_result catch |err| {
        model.percentageTax = .{};
        model.incomeTax = .{};
        if (std.mem.eql(u8, form_code, "1701Q")) {
            model.incomeTax.blockForLoadFailure(err);
            blockExact1701QOpen(model, err);
        } else {
            closeExact1701Q(model);
        }
        navigate(model, page);
        return false;
    };
    if (!model.formProfiles.profileSnapshotLocked()) {
        if (bindings.filer_activity_id) |activity_id| {
            model.formProfiles.setBusinessActivity(
                .filer,
                activity_id,
            ) catch return false;
        }
        if (bindings.spouse_activity_id) |activity_id| {
            model.formProfiles.setBusinessActivity(
                .spouse,
                activity_id,
            ) catch return false;
        }
    }
    if (std.mem.eql(u8, form_code, "2551Q")) {
        model.incomeTax = .{};
        model.percentageTax.reset(year, quarter) catch {
            model.percentageTax = .{};
        };
        const annual_event = if (bindings.annual_election_event) |*event|
            event
        else
            null;
        if (annual_event) |event| {
            const item_13 = annual_income_tax_election.project2551qItem13(
                event,
                year,
                quarter,
            ) catch |err| {
                model.percentageTax.blockForLoadFailure(err);
                navigate(model, page);
                return true;
            };
            model.percentageTax.bindIncomeTaxRateElection(switch (item_13.choice()) {
                .graduated => .graduated,
                .eight_percent => .eight_percent,
            });
        }
        const loaded_draft = model.formProfiles.loadPersistedDraft() catch |err| {
            model.percentageTax.blockForLoadFailure(err);
            navigate(model, page);
            return true;
        };
        if (loaded_draft) |loaded| {
            var draft = loaded;
            defer model.formProfiles.deinitLoadedDraft(&draft);
            model.percentageTax.loadFromDraftForAnnualElection(
                &draft,
                annual_event,
            ) catch |err| {
                model.percentageTax.blockForLoadFailure(err);
            };
        }
    } else if (std.mem.eql(u8, form_code, "1701Q")) {
        model.percentageTax = .{};
        // Keep the compiled coarse state empty for its historical unit tests;
        // it is neither hydrated nor used as the page/payload authority.
        model.incomeTax = .{};
        refreshExact1701QFromCurrentProjection(model, false);
    } else {
        model.percentageTax = .{};
        model.incomeTax = .{};
        closeExact1701Q(model);
    }
    navigate(model, page);
    return true;
}

fn openExact1701QFilingKind(model: *Model, amended: bool) void {
    if (rejectExact1701QContextChange(model)) return;
    refreshExact1701QFromCurrentProjection(model, amended);
}

fn closeExact1701Q(model: *Model) void {
    model.exact1701Q.close();
    model.exact1701QFrozenProvenance = null;
    model.exact1701QHistoricalProfile = null;
}

fn blockExact1701QOpen(model: *Model, err: anyerror) void {
    model.exact1701QFrozenProvenance = null;
    model.exact1701QHistoricalProfile = null;
    model.exact1701Q.blockOpen(err);
}

fn refreshExact1701QFromCurrentProjection(
    model: *Model,
    amended: bool,
) void {
    const revision = model.formProfiles.formRevision() orelse return;
    if (!std.mem.eql(u8, revision.code.asSlice(), "1701Q")) return;
    const snapshot = model.formProfiles.snapshot() orelse {
        blockExact1701QOpen(model, error.ProfileProjectionUnavailable);
        return;
    };
    const quarter: exact_1701q_ui.Quarter = switch (model.formProfiles.quarter()) {
        1 => .first,
        2 => .second,
        3 => .third,
        else => {
            blockExact1701QOpen(model, error.InvalidQuarter);
            return;
        },
    };
    const filing_context: exact_1701q_ui.FilingContext = .{
        .tax_year = model.formProfiles.taxYear(),
        .quarter = quarter,
        .amended = amended,
    };
    closeExact1701Q(model);
    if (model.exact1701QDevelopmentPlaintext) |capability| {
        if (model.taxProfiles.store) |store| {
            if (model.exact1701Q.exactPersistenceAllocator()) |allocator| {
                switch (exact_1701q_runtime.resumeUniqueDevelopmentPlaintext(
                    capability,
                    store,
                    allocator,
                    snapshot,
                    filing_context,
                    .editable_save,
                )) {
                    .opened => |reopened_value| {
                        var reopened = reopened_value;
                        defer reopened.deinit();
                        const exact = reopened.state.?;
                        const historical_profile = reopened.historicalProfile();
                        const frozen = if (reopened.frozenProvenance()) |value|
                            value.*
                        else
                            null;
                        model.exact1701Q.adoptReopenedDevelopmentPlaintext(
                            reopened.allocator,
                            exact,
                            historical_profile,
                        ) catch |err| {
                            model.exact1701Q.reportDevelopmentResumeFailure(
                                "adopt_reopened_state",
                                err,
                            );
                            return;
                        };
                        // Copy before releasing the runtime owner. This exact
                        // snapshot, not the mutable form-profile projection,
                        // remains the persistence authority for every later
                        // candidate revision in this workspace.
                        model.exact1701QHistoricalProfile = historical_profile.*;
                        reopened.state = null;
                        if (frozen) |value| {
                            const annual = value.annualFilerElection() catch |err| {
                                blockExact1701QOpen(model, err);
                                return;
                            };
                            const expected_election = exact_1701q_ui
                                .AnnualFilerElection.fromTaxpayerYear(
                                annual.rate,
                                annual.deduction,
                            ) catch |err| {
                                blockExact1701QOpen(model, err);
                                return;
                            };
                            _ = model.exact1701Q
                                .applyOrValidateAnnualFilerElection(
                                expected_election,
                            ) catch |err| {
                                blockExact1701QOpen(model, err);
                                return;
                            };
                            model.exact1701QFrozenProvenance = value;
                        } else {
                            // Legacy exact workspaces remain reopenable for
                            // inspection, but strict save stays unavailable
                            // because no v19 annual provenance exists.
                            model.exact1701QFrozenProvenance = null;
                        }
                        return;
                    },
                    .historical_projection_required => |frozen| {
                        // The persisted v19 sidecar is authoritative. Keep
                        // its fixed provenance available for a future
                        // historical-projection loader, but never substitute
                        // the mutable projection used only to locate this
                        // filing key.
                        model.exact1701QFrozenProvenance = frozen;
                        model.exact1701QHistoricalProfile = null;
                        model.exact1701Q.reportDevelopmentResumeFailure(
                            "historical_projection",
                            error.HistoricalExactProjectionUnavailable,
                        );
                        return;
                    },
                    .not_found => model.exact1701Q.reportDevelopmentResumeNotFound(),
                    .blocked => |failure| {
                        model.exact1701Q.reportDevelopmentResumeFailure(
                            @tagName(failure.stage),
                            failure.reason,
                        );
                        return;
                    },
                }
            }
        }
    }
    const allocator = model.taxProfiles.allocator orelse {
        blockExact1701QOpen(model, error.NotAttached);
        return;
    };
    const store = model.taxProfiles.store orelse {
        blockExact1701QOpen(model, error.NotAttached);
        return;
    };
    const definition = form_catalog.findForm("1701Q") orelse {
        blockExact1701QOpen(model, error.UnknownForm);
        return;
    };
    const filing_period = model.formProfiles.filingPeriod() orelse {
        blockExact1701QOpen(model, error.FilingPeriodUnavailable);
        return;
    };
    var prepared = draft_provenance_runtime.prepare(
        allocator,
        store,
        &model.formProfiles,
        definition,
        filing_period,
        null,
    ) catch |err| {
        blockExact1701QOpen(model, err);
        return;
    };
    defer prepared.deinit();
    const frozen = exact_1701q_runtime.FrozenExactProvenance.capture(
        &prepared,
    ) catch |err| {
        blockExact1701QOpen(model, err);
        return;
    };
    const annual = frozen.annualFilerElection() catch |err| {
        blockExact1701QOpen(model, err);
        return;
    };
    const expected_election = exact_1701q_ui.AnnualFilerElection
        .fromTaxpayerYear(annual.rate, annual.deduction) catch |err| {
        blockExact1701QOpen(model, err);
        return;
    };
    const workspace_id =
        model.formProfiles.generateExactWorkspaceId() catch |err| {
            blockExact1701QOpen(model, err);
            return;
        };
    _ = model.exact1701Q.open(workspace_id, snapshot, filing_context) catch |err| {
        blockExact1701QOpen(model, err);
        return;
    };
    _ = model.exact1701Q.applyOrValidateAnnualFilerElection(
        expected_election,
    ) catch |err| {
        blockExact1701QOpen(model, err);
        return;
    };
    model.exact1701QHistoricalProfile = snapshot.*;
    model.exact1701QFrozenProvenance = frozen;
}

fn rejectExact1701QContextChange(model: *Model) bool {
    if (!model.exact1701Q.ready() or
        !model.exact1701Q.hasDirtyOrMaterialWork())
    {
        return false;
    }
    model.exact1701Q.rejectContextChange();
    return true;
}

fn rejectExact1701QTaxpayerChange(
    model: *Model,
    candidate_profile_id: []const u8,
) bool {
    if (!model.exact1701Q.ready() or
        !model.exact1701Q.hasDirtyOrMaterialWork())
    {
        return false;
    }
    if (model.exact1701Q.filerProfileMatches(candidate_profile_id)) {
        return false;
    }
    model.exact1701Q.rejectContextChange();
    return true;
}

fn reconcileExact1701QTaxpayerSelection(model: *Model) void {
    const filer_profile_id =
        model.exact1701Q.filerProfileId() orelse return;
    if (model.exact1701Q.filerProfileMatches(
        model.taxProfiles.selectedProfileId() orelse "",
    )) {
        model.taxProfiles.reconcileSelectedRow();
        return;
    }
    for (model.taxProfiles.rows(), 0..) |*row, slot| {
        if (!std.mem.eql(
            u8,
            row.idLabel(),
            filer_profile_id,
        )) continue;

        // Restore only the sidebar profile state. The form projection and
        // exact workspace remain untouched and retain their immutable
        // revision binding, edits, candidates, and workflow history.
        model.taxProfiles.select(slot);
        return;
    }
}

fn reopenIncomeTaxQuarter(model: *Model, quarter: u8) void {
    if (quarter < 1 or quarter > 3) return;
    if (rejectExact1701QContextChange(model)) return;
    var spouse_profile_id: ?profile_model.ProfileId = null;
    if (model.formProfiles.formRevision()) |revision| {
        if (std.mem.eql(u8, revision.code.asSlice(), "1701Q")) {
            if (model.formProfiles.roleBinding(.spouse)) |binding| {
                spouse_profile_id = binding.profile_id;
            }
        }
    }
    if (openProfileBoundFormForQuarter(
        model,
        .form_1701q,
        "1701Q",
        model.calendar.selected_year,
        quarter,
        null,
        spouse_profile_id,
        null,
    )) {
        model.calendar.selected_month = quarter * 3;
        model.profileCalendarSelectedDate = null;
        syncSelectedProfileCalendar(model);
    }
}

fn profileNavigationRequiresDiscard(model: *const Model) bool {
    const profile_surface = model.page == .profile_setup or
        (model.page == .taxpayer_dashboard and
            model.dashboardSection == .profile_settings);
    if (!profile_surface) return false;
    return model.regPage.dirty() or
        (!model.taxProfiles.profileViewing() and
            model.taxProfiles.profileDirty());
}

fn deferProfileNavigation(
    model: *Model,
    target: PendingProfileNavigation,
) bool {
    if (!profileNavigationRequiresDiscard(model)) return false;
    model.pendingProfileNavigation = target;
    return true;
}

/// Taxpayer-context actions must be rejected or deferred before they mutate
/// the selected profile, Registration editor, Forms Set workspace, or annual
/// Tax Form Profile. This ordering keeps every dirty editor under the same
/// taxpayer shell until the user explicitly discards it.
fn deferTaxpayerContextMutation(
    model: *Model,
    target: TaxpayerContextMutation,
) bool {
    if (model.page == .tax_form_profile and
        (model.taxFormProfilePage.dirty() or
            model.taxpayerYearPage.dirty()))
    {
        model.taxFormProfilePendingNavigation = switch (target) {
            .taxpayer_slot => |slot| .{ .taxpayer_slot = slot },
            .new_taxpayer => .new_taxpayer,
            .add_branch => .add_branch,
        };
        model.taxFormProfileDiscardPromptOpen = true;
        return true;
    }
    if (profileNavigationRequiresDiscard(model)) {
        model.pendingProfileNavigation = switch (target) {
            .taxpayer_slot => |slot| .{ .taxpayer_slot = slot },
            .new_taxpayer => .new_taxpayer,
            .add_branch => .add_branch,
        };
        return true;
    }
    return model.taxProfiles.rejectIfFormsDirty();
}

fn navigate(model: *Model, page: Page) void {
    if (model.page == .tax_form_profile and
        page != .tax_form_profile and
        !isAuxiliaryPage(page) and
        (model.taxFormProfilePage.dirty() or
            model.taxpayerYearPage.dirty()))
    {
        model.taxFormProfilePendingNavigation = .{ .page = page };
        model.taxFormProfileDiscardPromptOpen = true;
        return;
    }
    if (page != model.page and
        !isAuxiliaryPage(page) and
        deferProfileNavigation(model, .{ .page = page }))
    {
        return;
    }
    if (model.page == .taxpayer_dashboard and
        model.dashboardSection == .profile_settings and
        page != .taxpayer_dashboard and
        !isAuxiliaryPage(page))
    {
        leaveInlineProfileSettings(model);
        model.dashboardSection = .calendar;
    }
    if (model.page == .taxpayer_dashboard and page != .taxpayer_dashboard) {
        model.taxProfiles.resetFormFilters();
    }
    model.page = page;
    model.sidebarOverlayOpen = false;
    model.profileSubjectPickerVisible = false;
    model.profileClassificationPickerVisible = false;
    model.profileEoptPickerVisible = false;
    model.libraryFilter.filter_picker_visible = false;
    model.libraryFilter.period_picker_visible = false;
    model.libraryFilter.info_index = null;
    if (page != .taxpayer_dashboard) {
        model.libraryFilter.period_filter = .all;
        resetProfileFormsBrowseFilters(model);
    }
}

fn bumpSidebarActionEpoch(model: *Model) void {
    model.sidebarActionEpoch +%= 1;
}

fn openTransient(model: *Model, page: Page) void {
    if (model.page != page) model.overlayReturnPage = model.contentPage();
    navigate(model, page);
}

fn closeTransient(model: *Model) void {
    const destination = model.overlayReturnPage;
    model.overlayReturnPage = .global_dashboard;
    navigate(model, destination);
}

fn openProfileEditor(model: *Model) void {
    if (model.page != .profile_setup) {
        model.profileEditorOrigin = model.contentPage();
    }
    navigate(model, .profile_setup);
}

fn leaveInlineProfileSettings(model: *Model) void {
    if (model.page != .taxpayer_dashboard or
        model.dashboardSection != .profile_settings)
    {
        return;
    }
    model.taxProfiles.cancelEdit();
    if (model.regEditing() and !model.regPage.dirty()) {
        loadRegistrationPage(model);
        syncCompleteProfileRegistrationControls(model);
    }
    syncProfileIdentityControls(model);
    model.profileCompletionTarget = null;
    model.profileCompletionFormIndex = null;
    model.pendingProfileFormLaunch = null;
    model.profileSetupSection = .tax_profile;
}

fn closeProfileEditor(model: *Model) void {
    const destination = model.profileEditorOrigin;
    // Back is navigation, not the editor's Cancel action. A dirty editor must
    // stay intact until the user confirms the shared discard prompt; a clean
    // editor can safely restore view mode before leaving the page.
    if (deferProfileNavigation(model, .{ .page = destination })) return;
    model.taxProfiles.cancelEdit();
    if (model.regEditing() and !model.regPage.dirty()) {
        loadRegistrationPage(model);
        syncCompleteProfileRegistrationControls(model);
    }
    syncProfileIdentityControls(model);
    model.profileCompletionTarget = null;
    model.profileCompletionFormIndex = null;
    model.pendingProfileFormLaunch = null;
    navigate(model, destination);
    // A dirty navigation guard deliberately keeps the editor open. Preserve
    // its origin until the deferred discard completes so Back still has a
    // truthful destination.
    if (model.page != .profile_setup) {
        model.profileEditorOrigin = .global_dashboard;
    }
}

fn launchActionEnabled(status: form_ui.LaunchStatus) bool {
    return switch (status) {
        .ready_new,
        .ready_resume,
        .needs_profile,
        .needs_activity_selection,
        => true,
        .profile_not_eligible,
        .unavailable,
        => false,
    };
}

fn profileCompletionFieldLabel(
    reusable_field: profile_fields.ReusableField,
) []const u8 {
    return switch (reusable_field) {
        .tin => "the Taxpayer Identification Number (TIN)",
        .rdo_code => "the Revenue District Office (RDO) code",
        .taxpayer_name,
        .registered_name,
        => "the registered taxpayer name",
        .registered_address => "the registered address",
        .zip_code => "the ZIP code",
        .contact_number => "the contact number",
        .email_address => "the registered email address",
        .date_of_birth => "the date of birth",
        .citizenship => "the citizenship",
        .foreign_tax_number => "the foreign tax number",
        .line_of_business => "the line of business",
        .atc => "the alphanumeric tax code",
        .tax_type => "the registered tax type",
        .government_withholding_agent => "the government withholding-agent choice",
        .special_rate_basis => "the special-rate basis",
    };
}

fn isAuxiliaryPage(page: Page) bool {
    return switch (page) {
        .aux_lock_screen,
        .aux_profile_auth,
        .aux_admin_auth,
        .aux_command_palette,
        .aux_html_preview,
        .aux_email_confirmation,
        .aux_debug_log,
        => true,
        else => false,
    };
}

fn effectiveColorScheme(model: *const Model) canvas.ColorScheme {
    return switch (model.themePreference) {
        .system => switch (model.systemColorScheme) {
            .light => .light,
            .dark => .dark,
        },
        .light => .light,
        .dark => .dark,
    };
}

fn appTokens(model: *const Model) canvas.DesignTokens {
    return canvas.DesignTokens.themeWithOverrides(
        .{
            .pack = .geist,
            .color_scheme = effectiveColorScheme(model),
            .contrast = if (model.highContrast) .high else .standard,
            .reduce_motion = model.reduceMotion,
        },
        .{
            // GPUI's sidebar uses 20 px glyphs and true 48 px circles.
            // Geist defaults to 16 px glyphs and a 12 px xl radius.
            .metrics = .{ .icon_text_step = 6 },
            .radius = .{ .xl = 24 },
        },
    );
}

fn appearanceMessage(appearance: native_sdk.Appearance) ?Msg {
    return .{ .appearance_changed = appearance };
}

fn frameMessage(model: *const Model, frame: native_sdk.GpuFrame) ?Msg {
    if (@abs(model.viewportWidth - frame.size.width) < 0.5) return null;
    return .{ .viewport_width_changed = frame.size.width };
}

fn viewportClassForWidth(width: f32) ViewportClass {
    if (width < phone_breakpoint) return .phone;
    if (width < compact_shell_breakpoint) return .compact;
    if (width < 900) return .rail_narrow;
    if (width < rail_shell_breakpoint) return .rail_regular;
    return .desktop;
}

fn taxpayerDashboardLaneModeForWidth(
    effective_width: f32,
) TaxpayerDashboardLaneMode {
    if (effective_width >= taxpayer_three_lane_min_width) {
        return .three_columns;
    }
    if (effective_width >= taxpayer_two_lane_min_width) {
        return .two_columns;
    }
    return .stacked;
}

fn calendarDayHeight(calendar_width: f32, maximum: f32) f32 {
    const ideal = (calendar_width - calendar_grid_gutters) / 7;
    return std.math.clamp(
        ideal,
        calendar_day_min_height,
        maximum,
    );
}

fn deadlineNoun(count: usize) []const u8 {
    return if (count == 1) "deadline" else "deadlines";
}

fn nominalWidthForClass(viewport_class: ViewportClass) f32 {
    return switch (viewport_class) {
        .phone => 390,
        .compact => 700,
        .rail_narrow => 820,
        .rail_regular => 1000,
        .desktop => rail_shell_breakpoint,
    };
}

const Effects = native_sdk.Effects(Msg);
const important_news_fetch_key: u64 = 20_260_000;
const important_news_feed_url = "https://www.officialgazette.gov.ph/feed/";
const important_news_source = "Official Gazette";
const calendar_export_file_key: u64 = 20_260_001;
const calendar_open_file_key: u64 = 20_260_002;
const profile_notice_timer_key_base: u64 = 20_260_100;
const profile_notice_duration_ms: u64 = 5_000;
const profile_calendar_export_timer_key_base: u64 = 20_260_200;
const profile_calendar_export_notice_duration_ms: u64 = 6_000;
const calendar_today_refresh_timer_key: u64 = 20_260_300;
const calendar_today_refresh_interval_ms: u64 = 60_000;

fn startCalendarTodayRefreshTimer(fx: *Effects) void {
    fx.startTimer(.{
        .key = calendar_today_refresh_timer_key,
        .interval_ms = calendar_today_refresh_interval_ms,
        .mode = .repeating,
        .on_fire = Effects.timerMsg(.calendar_today_refresh),
    });
}

fn updateCalendarToday(
    model: *Model,
    current_date: calendar_domain.Date,
) bool {
    if (calendar_domain.Date.compare(model.calendarToday, current_date) == .eq) {
        return false;
    }
    model.calendarToday = current_date;
    return true;
}

fn refreshCalendarTodayFromClock(
    model: *Model,
    timer: native_sdk.EffectTimer,
) void {
    if (timer.key != calendar_today_refresh_timer_key or
        timer.outcome != .fired) return;
    const raw_seconds: i64 = @intCast(c_time.time(null));
    const current_date = localCalendarDateFromUnixSeconds(raw_seconds) orelse
        return;
    _ = updateCalendarToday(model, current_date);
}

fn profileNoticeTimerKey(epoch: u64) u64 {
    const key = profile_notice_timer_key_base +% epoch;
    return if (key == 0) profile_notice_timer_key_base else key;
}

fn syncProfileNoticeTimer(model: *Model, fx: *Effects) void {
    if (model.profileNoticeTimerKey != 0) {
        fx.cancelTimer(model.profileNoticeTimerKey);
        model.profileNoticeTimerKey = 0;
    }
    if (!model.taxProfiles.noticeAutoDismissible()) return;

    const key = profileNoticeTimerKey(model.taxProfiles.noticeEpoch());
    model.profileNoticeTimerKey = key;
    fx.startTimer(.{
        .key = key,
        .interval_ms = profile_notice_duration_ms,
        .mode = .one_shot,
        .on_fire = Effects.timerMsg(.profile_notice_timeout),
    });
}

fn profileNoticeTimeout(
    model: *Model,
    timer: native_sdk.EffectTimer,
) void {
    if (timer.key != model.profileNoticeTimerKey) return;
    model.profileNoticeTimerKey = 0;
    switch (timer.outcome) {
        .fired => {
            if (model.taxProfiles.noticeAutoDismissible()) {
                model.taxProfiles.dismissNotice();
            }
        },
        .rejected => {},
    }
}

fn profileCalendarExportTimerKey(epoch: u64) u64 {
    const key = profile_calendar_export_timer_key_base +% epoch;
    return if (key == 0) profile_calendar_export_timer_key_base else key;
}

fn syncProfileCalendarExportNoticeTimer(
    model: *Model,
    fx: *Effects,
) void {
    if (model.profileCalendarExportTimerKey != 0) {
        fx.cancelTimer(model.profileCalendarExportTimerKey);
        model.profileCalendarExportTimerKey = 0;
    }
    if (!model.profileCalendarExportNoticeAutoDismissible()) return;

    const key = profileCalendarExportTimerKey(
        model.profileCalendarExportNoticeEpoch,
    );
    model.profileCalendarExportTimerKey = key;
    fx.startTimer(.{
        .key = key,
        .interval_ms = profile_calendar_export_notice_duration_ms,
        .mode = .one_shot,
        .on_fire = Effects.timerMsg(
            .profile_calendar_export_notice_timeout,
        ),
    });
}

fn dismissProfileCalendarExportNotice(model: *Model) void {
    if (model.profileCalendarExportBusy()) return;
    model.profileCalendarExportStatus = .idle;
    model.calendarExportProfileRevision = null;
}

fn profileCalendarExportNoticeTimeout(
    model: *Model,
    timer: native_sdk.EffectTimer,
) void {
    if (timer.key != model.profileCalendarExportTimerKey) return;
    model.profileCalendarExportTimerKey = 0;
    switch (timer.outcome) {
        .fired => {
            if (model.profileCalendarExportNoticeAutoDismissible()) {
                dismissProfileCalendarExportNotice(model);
            }
        },
        .rejected => {},
    }
}

fn exportProfileCalendar(model: *Model, maybe_fx: ?*Effects) void {
    if (model.profileCalendarExportBusy()) return;
    model.calendarExportProfileRevision =
        model.taxProfiles.selectedRevisionContext();
    if (model.contentPage() != .taxpayer_dashboard) {
        model.profileCalendarExportStatus = .wrong_context;
        return;
    }
    if (!model.hasSelectedTaxpayer()) {
        model.profileCalendarExportStatus = .no_profile;
        return;
    }
    if (!model.profileCalendarScopeAvailable()) {
        model.profileCalendarExportStatus = .unavailable;
        return;
    }
    if (!model.profileCalendarHasAnyIncludedDeadline()) {
        model.profileCalendarExportStatus = .nothing_to_add;
        return;
    }
    const fx = maybe_fx orelse {
        model.profileCalendarExportStatus = .unavailable;
        return;
    };
    const allocator = model.profileCalendar.allocator orelse {
        model.profileCalendar.setError(error.NotAttached);
        model.profileCalendarExportStatus = .build_failed;
        return;
    };
    var export_stamp: [16]u8 = undefined;
    const now: i64 = @intCast(c_time.time(null));
    if (utcCalendarTimeFromUnixSeconds(now)) |current| {
        export_stamp = current.stamp;
    } else {
        const fallback = model.profileCalendar.exportTimestamp();
        if (fallback.len != export_stamp.len) {
            model.profileCalendar.setError(error.InvalidTimestamp);
            model.profileCalendarExportStatus = .build_failed;
            return;
        }
        @memcpy(&export_stamp, fallback);
    }
    // Form availability is year-specific, so the calendar is filtered against
    // each deadline's own taxable year before serialization.
    const export_calendar = model.profileCalendarForExport();
    // The serializer applies the profile's registered form scope as well. It
    // is deliberately redundant with the filter above: a future caller that
    // forgets to pre-filter still cannot export a form the taxpayer has not
    // registered for.
    var scope_arena = std.heap.ArenaAllocator.init(allocator);
    defer scope_arena.deinit();
    const bytes = export_calendar.buildProfileIcs(
        allocator,
        &export_stamp,
        .{
            .key = model.selectedTaxpayerCalendarKey(),
            .name = model.selectedTaxpayerName(),
            .form_scope = model.profileExportFormScope(scope_arena.allocator()),
        },
    ) catch |err| {
        if (err == error.NoCalendarEvents) {
            model.profileCalendarExportStatus = .nothing_to_add;
            return;
        }
        model.profileCalendar.setError(err);
        model.profileCalendarExportStatus = .build_failed;
        return;
    };
    defer allocator.free(bytes);

    model.profileCalendarExportStatus = .writing;
    fx.writeFile(.{
        .key = calendar_export_file_key,
        .path = model.profileCalendar.exportPath(),
        .bytes = bytes,
        .on_result = Effects.fileMsg(.profile_calendar_export_written),
    });
}

fn profileCalendarExportWritten(
    model: *Model,
    result: native_sdk.EffectFileResult,
    maybe_fx: ?*Effects,
) void {
    if (result.key != calendar_export_file_key or
        result.op != .write or
        model.profileCalendarExportStatus != .writing) return;
    if (result.outcome != .ok) {
        model.profileCalendarExportStatus = .write_failed;
        return;
    }
    const fx = maybe_fx orelse {
        model.profileCalendarExportStatus = .opener_unavailable;
        return;
    };

    model.profileCalendarExportStatus = .opening;
    const path = model.profileCalendar.exportPath();
    switch (native_sdk.app_dirs.currentPlatform()) {
        .macos => fx.spawn(.{
            .key = calendar_open_file_key,
            .argv = &.{ "open", path },
            .on_exit = Effects.exitMsg(.profile_calendar_export_opened),
        }),
        .windows => fx.spawn(.{
            .key = calendar_open_file_key,
            .argv = &.{ "cmd.exe", "/D", "/C", "start", "", path },
            .on_exit = Effects.exitMsg(.profile_calendar_export_opened),
        }),
        .linux => fx.spawn(.{
            .key = calendar_open_file_key,
            .argv = &.{ "xdg-open", path },
            .on_exit = Effects.exitMsg(.profile_calendar_export_opened),
        }),
        else => model.profileCalendarExportStatus = .unsupported_platform,
    }
}

fn profileCalendarExportOpened(
    model: *Model,
    result: native_sdk.EffectExit,
) void {
    if (result.key != calendar_open_file_key or
        model.profileCalendarExportStatus != .opening) return;
    if (result.reason == .exited and result.code == 0) {
        model.profileCalendarExportStatus = .opened;
    } else {
        model.profileCalendarExportStatus = .open_failed;
    }
}

fn registerBootImages(model: *Model, fx: *Effects) void {
    fx.loadImage(.{ .id = 1, .path = "assets/brand/ebirforms.png" });
    fx.loadImage(.{ .id = 2, .path = "assets/brand/bagong-pilipinas.png" });
    fx.loadImage(.{ .id = 3, .path = "assets/brand/bir-new-logo.png" });
    fx.loadImage(.{ .id = 4, .path = "assets/brand/goldcoders-logo.png" });
    fx.loadImage(.{ .id = 6, .path = "assets/icon.png" });
    startCalendarTodayRefreshTimer(fx);
    syncProfileNoticeTimer(model, fx);
    refreshImportantNews(model, fx);
}

const EbirFormsApp = native_sdk.UiApp(Model, Msg);
pub const app_markup = @embedFile("app.native");
const multi_select_component_markup = @embedFile("components/multi-select-combobox.native");
const multi_select_component_fixture = multi_select_component_markup ++
    \\
    \\<column>
    \\  <use
    \\    template="multi-select-combobox"
    \\    placeholder="Search form codes..."
    \\    label="Choose profile calendar forms"/>
    \\</column>
;

const BootCalendarTime = struct {
    year: i32,
    month: u8,
    day: u8,
    stamp: [16]u8,
};

fn bootCalendarTime(io: std.Io) BootCalendarTime {
    const raw_seconds = std.Io.Clock.real.now(io).toSeconds();
    const utc = utcCalendarTimeFromUnixSeconds(raw_seconds) orelse return .{
        .year = 2026,
        .month = 1,
        .day = 1,
        .stamp = "20260101T000000Z".*,
    };
    const local_date = localCalendarDateFromUnixSeconds(raw_seconds) orelse
        calendar_domain.Date{
            .year = utc.year,
            .month = utc.month,
            .day = utc.day,
        };
    return .{
        .year = local_date.year,
        .month = local_date.month,
        .day = local_date.day,
        .stamp = utc.stamp,
    };
}

fn utcCalendarTimeFromUnixSeconds(raw_seconds: i64) ?BootCalendarTime {
    if (raw_seconds < 0) return null;
    const epoch_seconds = std.time.epoch.EpochSeconds{
        .secs = @intCast(raw_seconds),
    };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const year: u16 = year_day.year;
    if (year == 0 or year > 9999) return null;
    const month: u8 = @intCast(month_day.month.numeric());
    const day: u8 = @intCast(month_day.day_index + 1);
    const hour: u8 = @intCast(day_seconds.getHoursIntoDay());
    const minute: u8 = @intCast(day_seconds.getMinutesIntoHour());
    const second: u8 = @intCast(day_seconds.getSecondsIntoMinute());

    var stamp: [16]u8 = undefined;
    writeFourDigits(stamp[0..4], year);
    writeTwoDigits(stamp[4..6], month);
    writeTwoDigits(stamp[6..8], day);
    stamp[8] = 'T';
    writeTwoDigits(stamp[9..11], hour);
    writeTwoDigits(stamp[11..13], minute);
    writeTwoDigits(stamp[13..15], second);
    stamp[15] = 'Z';
    return .{
        .year = year,
        .month = month,
        .day = day,
        .stamp = stamp,
    };
}

fn localCalendarDateFromUnixSeconds(
    raw_seconds: i64,
) ?calendar_domain.Date {
    const utc = utcCalendarTimeFromUnixSeconds(raw_seconds) orelse return null;
    var local_seconds: c_time.time_t = @intCast(raw_seconds);
    var local: c_time.struct_tm = undefined;
    // MinGW declares `localtime_s` with an asm alias to `_localtime64_s`.
    // Zig's translated declaration can lose that alias and emit an unresolved
    // `localtime_s` reference for Windows ARM64, so prefer the exported CRT
    // symbol directly when it is available.
    const local_ok = if (@hasDecl(c_time, "_localtime64_s"))
        c_time._localtime64_s(&local, &local_seconds) == 0
    else if (@hasDecl(c_time, "localtime_r"))
        c_time.localtime_r(&local_seconds, &local) != null
    else if (@hasDecl(c_time, "localtime_s"))
        c_time.localtime_s(&local, &local_seconds) == 0
    else
        false;
    const year: i32 = if (local_ok) local.tm_year + 1900 else utc.year;
    const month: i32 = if (local_ok) local.tm_mon + 1 else utc.month;
    const day: i32 = if (local_ok) local.tm_mday else utc.day;
    return calendar_domain.Date.init(
        year,
        std.math.cast(u8, month) orelse return null,
        std.math.cast(u8, day) orelse return null,
    ) catch null;
}

fn writeFourDigits(output: []u8, value: u16) void {
    output[0] = @intCast('0' + (value / 1000) % 10);
    output[1] = @intCast('0' + (value / 100) % 10);
    output[2] = @intCast('0' + (value / 10) % 10);
    output[3] = @intCast('0' + value % 10);
}

fn writeTwoDigits(output: []u8, value: u8) void {
    output[0] = @intCast('0' + (value / 10) % 10);
    output[1] = @intCast('0' + value % 10);
}

fn macBundleResourcesPath(
    executable_path: []const u8,
    output: []u8,
) error{PathTooLong}!?[]const u8 {
    const marker = "/Contents/MacOS/";
    const marker_index = std.mem.lastIndexOf(
        u8,
        executable_path,
        marker,
    ) orelse return null;
    const bundle_path = executable_path[0..marker_index];
    const executable_name = executable_path[marker_index + marker.len ..];
    if (!std.mem.endsWith(u8, bundle_path, ".app") or
        executable_name.len == 0 or
        std.mem.indexOfScalar(u8, executable_name, '/') != null)
    {
        return null;
    }

    const suffix = "/Contents/Resources";
    const required_len = bundle_path.len + suffix.len;
    if (required_len > output.len) return error.PathTooLong;
    @memcpy(output[0..bundle_path.len], bundle_path);
    @memcpy(output[bundle_path.len..required_len], suffix);
    return output[0..required_len];
}

fn usePackagedMacResources(io: std.Io) !void {
    if (comptime builtin.os.tag != .macos) return;

    var executable_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const executable_len = try std.process.executablePath(
        io,
        &executable_buffer,
    );
    var resources_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const resources_path = try macBundleResourcesPath(
        executable_buffer[0..executable_len],
        &resources_buffer,
    ) orelse return;

    var resources = std.Io.Dir.openDirAbsolute(
        io,
        resources_path,
        .{},
    ) catch |err| {
        std.log.err(
            "packaged eBIRForms resources are missing at {s}: {s}",
            .{ resources_path, @errorName(err) },
        );
        return err;
    };
    defer resources.close(io);
    var brand_asset = resources.openFile(
        io,
        "assets/brand/ebirforms.png",
        .{ .allow_directory = false },
    ) catch |err| {
        std.log.err(
            "packaged eBIRForms brand asset is missing: {s}",
            .{@errorName(err)},
        );
        return err;
    };
    brand_asset.close(io);
    try std.process.setCurrentPath(io, resources_path);
}

test "macOS bundle resources path recognizes only an exact app executable" {
    var output: [256]u8 = undefined;
    const resources = (try macBundleResourcesPath(
        "/Applications/eBIRForms.app/Contents/MacOS/eBIRForms",
        &output,
    )).?;
    try std.testing.expectEqualStrings(
        "/Applications/eBIRForms.app/Contents/Resources",
        resources,
    );

    const ordinary = try macBundleResourcesPath(
        "/Volumes/work/zig-out/bin/ebirforms",
        &output,
    );
    try std.testing.expect(ordinary == null);
    const near_match = try macBundleResourcesPath(
        "/Applications/eBIRForms.appish/Contents/MacOS/eBIRForms",
        &output,
    );
    try std.testing.expect(near_match == null);
    const nested_executable = try macBundleResourcesPath(
        "/Applications/eBIRForms.app/Contents/MacOS/bin/eBIRForms",
        &output,
    );
    try std.testing.expect(nested_executable == null);
}

test "macOS bundle resources path rejects truncation" {
    var output: [8]u8 = undefined;
    try std.testing.expectError(
        error.PathTooLong,
        macBundleResourcesPath(
            "/Applications/eBIRForms.app/Contents/MacOS/eBIRForms",
            &output,
        ),
    );
}

pub fn main(init: std.process.Init) !void {
    // This source-selected bootstrap must precede environment inspection,
    // repository path resolution, directory creation, and every storage I/O.
    // It has no runtime selector and current source can mint development
    // plaintext authority only.
    const artifact_storage = key_custody.bootstrapCurrentArtifactStorage();
    const development_plaintext = artifact_storage.development_plaintext;

    canvas.icons.registerAppIcons(&app_icons);
    defer canvas.icons.registerAppIcons(&.{});

    // Message handlers need an I/O handle to hash an attached COR; this is
    // the only place one exists.
    profile_ui.publishIo(init.io);

    const app_dirs = native_sdk.app_dirs;
    const platform = app_dirs.currentPlatform();
    const environment = native_sdk.debug.envFromMap(init.environ_map);
    var data_dir_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const configured_data_dir = init.environ_map.get("EBIRFORMS_DATA_DIR") orelse
        try app_dirs.resolveOne(
            .{ .name = "ebirforms-zero" },
            platform,
            environment,
            .data,
            &data_dir_buffer,
        );
    try std.Io.Dir.cwd().createDirPath(init.io, configured_data_dir);
    var data_directory = try std.Io.Dir.cwd().openDir(
        init.io,
        configured_data_dir,
        .{},
    );
    defer data_directory.close(init.io);
    var absolute_data_dir_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const absolute_data_dir_len = try data_directory.realPath(
        init.io,
        &absolute_data_dir_buffer,
    );
    const data_dir = absolute_data_dir_buffer[0..absolute_data_dir_len];

    var database_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const database_path = try app_dirs.join(
        platform,
        &database_path_buffer,
        &.{ data_dir, "calendar.sqlite3" },
    );
    var news_database_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const news_database_path = try app_dirs.join(
        platform,
        &news_database_path_buffer,
        &.{ data_dir, news_store.default_filename },
    );
    var export_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const export_path = try app_dirs.join(
        platform,
        &export_path_buffer,
        &.{ data_dir, "ebirforms-tax-calendar.ics" },
    );

    var calendar_store =
        try calendar_ui.persistence.Store.openDevelopmentPlaintext(
            development_plaintext,
            init.gpa,
            database_path,
        );
    defer calendar_store.close();
    var tax_profile_store = try profile_store.Store.openDevelopmentPlaintext(
        development_plaintext,
        init.gpa,
        database_path,
    );
    defer tax_profile_store.close();
    var important_news_store = try news_store.Store.openRecoverableCache(
        init.gpa,
        news_database_path,
    );
    defer important_news_store.close();
    const boot_time = bootCalendarTime(init.io);
    var boot_date: [10]u8 = undefined;
    @memcpy(boot_date[0..4], boot_time.stamp[0..4]);
    boot_date[4] = '-';
    @memcpy(boot_date[5..7], boot_time.stamp[4..6]);
    boot_date[7] = '-';
    @memcpy(boot_date[8..10], boot_time.stamp[6..8]);

    // Native image paths are relative. Packaged macOS launches start beside
    // the executable, so switch only the exact .app layout to Resources after
    // all data paths have been resolved. Development launches retain their
    // caller-selected working directory.
    try usePackagedMacResources(init.io);

    const app_state = try EbirFormsApp.create(std.heap.page_allocator, .{
        .name = "ebirforms-zero",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = updateWithEffects,
        .init_fx = registerBootImages,
        .on_appearance = appearanceMessage,
        .on_frame = frameMessage,
        .tokens_fn = appTokens,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = .{};
    app_state.model.calendarToday = try calendar_domain.Date.init(
        boot_time.year,
        boot_time.month,
        boot_time.day,
    );
    try app_state.model.calendar.attach(
        init.gpa,
        &calendar_store,
        export_path,
        &boot_time.stamp,
        boot_time.year,
        boot_time.month,
    );
    try app_state.model.globalDashboard.calendar.attach(
        init.gpa,
        &calendar_store,
        export_path,
        &boot_time.stamp,
        boot_time.year,
        boot_time.month,
    );
    try app_state.model.profileCalendar.attach(
        init.gpa,
        &calendar_store,
        export_path,
        &boot_time.stamp,
        boot_time.year,
        boot_time.month,
    );
    try attachImportantNews(
        &app_state.model,
        init.gpa,
        &important_news_store,
    );
    defer deinitImportantNews(&app_state.model);
    try app_state.model.taxProfiles.attach(
        init.gpa,
        &tax_profile_store,
        &boot_date,
        boot_time.year,
    );
    refreshSelectedProfileFormSet(&app_state.model);
    app_state.model.formProfiles.attach(
        init.gpa,
        &tax_profile_store,
    );
    refreshProfileFormLaunchAssessments(&app_state.model);
    defer app_state.model.formProfiles.deinit();
    app_state.model.exact1701Q.attach(
        init.gpa,
        .{
            .current_year = boot_time.year,
            .schedule_date = .{
                .current_date = .{
                    .year = boot_time.year,
                    .month = boot_time.month,
                    .day = boot_time.day,
                },
                // Both legacy date defaults are grounded to the same captured
                // boot date, so the second is not later than the first.
                .empty_default_input_was_later = false,
            },
        },
    );
    app_state.model.exact1701QDevelopmentPlaintext = development_plaintext;
    defer app_state.model.exact1701Q.deinit();

    try runner.runWithOptions(app_state.app(), .{
        .app_name = "ebirforms-zero",
        .window_title = "eBIRForms",
        .bundle_id = "dev.goldcoders.ebirforms",
        .icon_path = "assets/icon.png",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .restore_state = false,
        .js_window_api = false,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } },
        },
    }, init);
}

fn addTestProfile(
    store: *profile_store.Store,
    id: []const u8,
    name: []const u8,
    tin: []const u8,
    subject_kind: profile_model.SubjectKind,
) !void {
    return addTestProfileWithRdo(
        store,
        id,
        name,
        tin,
        subject_kind,
        "040",
    );
}

fn addTestProfileWithRdo(
    store: *profile_store.Store,
    id: []const u8,
    name: []const u8,
    tin: []const u8,
    subject_kind: profile_model.SubjectKind,
    rdo_code: []const u8,
) !void {
    try addTestProfileWithRdoWithoutYearSettings(
        store,
        id,
        name,
        tin,
        subject_kind,
        rdo_code,
    );
    for ([_]u16{ 2025, 2026, 2027 }) |tax_year| {
        try addTestTaxpayerYearSettings(store, id, tax_year);
        try addTestAnnualIncomeTaxElection(store, id, tax_year);
    }
}

fn addTestProfileWithoutYearSettings(
    store: *profile_store.Store,
    id: []const u8,
    name: []const u8,
    tin: []const u8,
    subject_kind: profile_model.SubjectKind,
) !void {
    return addTestProfileWithRdoWithoutYearSettings(
        store,
        id,
        name,
        tin,
        subject_kind,
        "040",
    );
}

fn addTestTaxpayerYearSettings(
    store: *profile_store.Store,
    raw_profile_id: []const u8,
    tax_year: u16,
) !void {
    const values = [_]taxpayer_year_settings_domain.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .itemized_deduction },
    };
    const generated_id = try store.generateOpaqueId();
    const revision: taxpayer_year_settings_domain.Revision = .{
        .id = try taxpayer_year_settings_domain.RevisionId.parse(
            &generated_id,
        ),
        .stream = .{
            .profile_id = try profile_model.ProfileId.parse(raw_profile_id),
            .tax_year = tax_year,
        },
        .sequence = 1,
        .effective = try taxpayer_year_settings_domain.fullTaxYearPeriod(
            tax_year,
        ),
        .review_state = .confirmed,
        .confirmed_at_unix_seconds = 1,
        .source = .manual_entry,
        .values = &values,
    };
    try profile_persistence.appendTaxpayerYearRevision(
        store,
        std.testing.allocator,
        0,
        &revision,
    );
}

fn addTestAnnualIncomeTaxElection(
    store: *profile_store.Store,
    raw_profile_id: []const u8,
    tax_year: u16,
) !void {
    _ = try profile_persistence.confirmAnnualIncomeTaxElectionEvidence(
        store,
        .{
            .stream = .{
                .profile_id = try profile_model.ProfileId.parse(raw_profile_id),
                .tax_year = tax_year,
            },
            .expected_current_sequence = 0,
            .choice = .graduated,
            .initial_applicable_quarter = 1,
            .provenance = .{ .kind = .statutory_default },
            .occurred_at_unix_seconds = 1,
        },
    );
}

/// Seeds the normalized Registration facts that make a self-employed fixture
/// complete for the 2551Q pilot and for the unified complete-profile editor.
/// Base-profile helpers intentionally do not do this automatically: tests that
/// exercise missing Registration must remain able to fail closed.
fn addTestCompleteBusinessRegistration(
    store: *profile_store.Store,
    raw_profile_id: []const u8,
    effective_from: [10]u8,
) !void {
    const activity_revision_id = try store.generateOpaqueId();
    const obligation_revision_id = try store.generateOpaqueId();
    const eopt_revision_id = try store.generateOpaqueId();
    const activities = [_]profile_store.RegistrationActivityRevisionWrite{.{
        .anchor_id = composed_tax_profile.primary_business_activity_anchor,
        .metadata = .{
            .id = activity_revision_id[0..],
            .expected_component_sequence = 0,
            .effective = .{ .from = effective_from },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .line_of_business = "Professional services",
        .atc = "PT010",
    }};
    const obligations = [_]profile_store.RegistrationObligationRevisionWrite{.{
        .anchor_id = "percentage-tax",
        .metadata = .{
            .id = obligation_revision_id[0..],
            .expected_component_sequence = 0,
            .effective = .{ .from = effective_from },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 2,
        },
        .kind = .percentage_tax,
    }};
    const eopt_tiers = [_]profile_store.RegistrationEoptTierRevisionWrite{.{
        .metadata = .{
            .id = eopt_revision_id[0..],
            .expected_component_sequence = 0,
            .effective = .{ .from = effective_from },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 3,
        },
        .value = .micro,
    }};
    _ = try store.appendRegistrationCommit(.{
        .profile_id = raw_profile_id,
        .expected_current_sequence = 0,
        .activities = &activities,
        .obligations = &obligations,
        .eopt_tiers = &eopt_tiers,
    });
}

fn addTestProfileWithRdoWithoutYearSettings(
    store: *profile_store.Store,
    id: []const u8,
    name: []const u8,
    tin: []const u8,
    subject_kind: profile_model.SubjectKind,
    rdo_code: []const u8,
) !void {
    var revision_id_buffer: [64]u8 = undefined;
    const revision_id = try std.fmt.bufPrint(
        &revision_id_buffer,
        "rev-{s}",
        .{id},
    );
    const base: profile_editor.Base = .{
        .profile_id = try profile_model.ProfileId.parse(id),
        .revision_id = try profile_model.RevisionId.parse(revision_id),
        .sequence = 1,
        .effective = try profile_model.EffectivePeriod.init(
            try profile_model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try profile_fields.Tin.parse(tin),
            .rdo_code = try profile_fields.RdoCode.parse(rdo_code),
        },
        .contact = .{
            .address = try profile_fields.RegisteredAddress.parse(
                "Quezon City",
            ),
            .zip_code = try profile_fields.ZipCode.parse("1100"),
            .contact_number = try profile_fields.ContactNumber.parse(
                "09171234567",
            ),
            .email_address = try profile_fields.EmailAddress.parse(
                "fixture@example.ph",
            ),
        },
    };
    const ready = switch (subject_kind) {
        .individual => profile_editor.begin(base).individual(.{
            .name = try profile_fields.TaxpayerName.parse(name),
            .classification = .self_employed,
            .date_of_birth = try profile_model.Date.parseIso("1990-01-01"),
            .citizenship = try profile_fields.Citizenship.parse("Filipino"),
        }),
        .sole_proprietor => profile_editor.begin(base).soleProprietor(.{
            .person = .{
                .name = try profile_fields.TaxpayerName.parse(name),
                .date_of_birth = try profile_model.Date.parseIso("1990-01-01"),
                .citizenship = try profile_fields.Citizenship.parse(
                    "Filipino",
                ),
            },
        }),
        .corporation,
        .partnership,
        .cooperative,
        .estate,
        .trust,
        .other_legal_entity,
        => profile_editor.begin(base).legalEntity(.{
            .registered_name = try profile_fields.RegisteredName.parse(name),
            .kind = switch (subject_kind) {
                .corporation => .corporation,
                .partnership => .partnership,
                .cooperative => .cooperative,
                .estate => .estate,
                .trust => .trust,
                .other_legal_entity => .other,
                .individual, .sole_proprietor => unreachable,
            },
        }),
    };
    const revision = try ready.build();
    try profile_persistence.createProfileWithRevision(
        store,
        std.testing.allocator,
        .active,
        &revision,
    );
    var forms: [form_catalog.registry_count]profile_store.FormRegistrationWrite =
        undefined;
    for (&form_catalog.forms, 0..) |*form, index| {
        forms[index] = .{
            .form_code = form.code,
            .form_revision = form.revision orelse "calendar-only",
        };
    }
    for ([_]i32{ 2025, 2026, 2027 }) |year| {
        try store.replaceFormSet(id, year, &forms);
    }
}

fn persistTestSoleProprietorRevision(
    store: *profile_store.Store,
    profile_id: []const u8,
    revision_id: []const u8,
    sequence: u32,
    effective_on: []const u8,
    name: []const u8,
    tin: []const u8,
    activities: []const profile_model.BusinessActivity,
) !void {
    const base: profile_editor.Base = .{
        .profile_id = try profile_model.ProfileId.parse(profile_id),
        .revision_id = try profile_model.RevisionId.parse(revision_id),
        .sequence = sequence,
        .effective = try profile_model.EffectivePeriod.init(
            try profile_model.Date.parseIso(effective_on),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try profile_fields.Tin.parse(tin),
            .rdo_code = try profile_fields.RdoCode.parse("040"),
        },
        .contact = .{
            .address = try profile_fields.RegisteredAddress.parse(
                "Quezon City",
            ),
            .zip_code = try profile_fields.ZipCode.parse("1100"),
            .contact_number = try profile_fields.ContactNumber.parse(
                "09171234567",
            ),
            .email_address = try profile_fields.EmailAddress.parse(
                "fixture@example.ph",
            ),
        },
    };
    const revision = try profile_editor.begin(base)
        .soleProprietor(.{
            .person = .{
                .name = try profile_fields.TaxpayerName.parse(name),
                .date_of_birth = try profile_model.Date.parseIso(
                    "1990-01-01",
                ),
                .citizenship = try profile_fields.Citizenship.parse(
                    "Filipino",
                ),
            },
        })
        .withBusinessActivities(activities)
        .build();
    if (sequence == 1) {
        try profile_persistence.createProfileWithRevision(
            store,
            std.testing.allocator,
            .active,
            &revision,
        );
        var forms: [form_catalog.registry_count]profile_store.FormRegistrationWrite =
            undefined;
        for (&form_catalog.forms, 0..) |*form, index| {
            forms[index] = .{
                .form_code = form.code,
                .form_revision = form.revision orelse "calendar-only",
            };
        }
        for ([_]i32{ 2025, 2026, 2027 }) |year| {
            try store.replaceFormSet(profile_id, year, &forms);
        }
        for ([_]u16{ 2025, 2026, 2027 }) |tax_year| {
            try addTestTaxpayerYearSettings(store, profile_id, tax_year);
        }
    } else {
        try profile_persistence.appendRevision(
            store,
            std.testing.allocator,
            &revision,
            sequence - 1,
        );
    }
}

fn addThreeTestProfiles(store: *profile_store.Store) !void {
    try addTestProfile(
        store,
        "11111111111111111111111111111111",
        "Juan Dela Cruz",
        "000-000-000-000",
        .individual,
    );
    try addTestProfile(
        store,
        "22222222222222222222222222222222",
        "Demo Corporation",
        "111-111-111-000",
        .corporation,
    );
    try addTestProfile(
        store,
        "33333333333333333333333333333333",
        "Sample Partnership",
        "222-222-222-000",
        .partnership,
    );
}

test "Registration and Forms cancels exact repeatable draft, guards year switch, and persists v16 anchors" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    const profile_id_text = "registration-page-owner";
    try addTestProfile(
        &store,
        profile_id_text,
        "Registration Page Owner",
        "987-654-321-000",
        .sole_proprietor,
    );
    const baseline_activities = [_]profile_store.RegistrationActivityRevisionWrite{.{
        .anchor_id = "baseline-consulting",
        .metadata = .{
            .id = "baseline-consulting-r1",
            .expected_component_sequence = 0,
            .effective = .{ .from = "2026-01-01".* },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .line_of_business = "Consulting",
        .atc = "PT010",
    }};
    const baseline_obligations = [_]profile_store.RegistrationObligationRevisionWrite{.{
        .anchor_id = "baseline-income-tax",
        .metadata = .{
            .id = "baseline-income-tax-r1",
            .expected_component_sequence = 0,
            .effective = .{ .from = "2026-01-01".* },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 2,
        },
        .kind = .registered_income_tax,
    }};
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.appendRegistrationCommit(.{
            .profile_id = profile_id_text,
            .expected_current_sequence = 0,
            .activities = &baseline_activities,
            .obligations = &baseline_obligations,
        }),
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .profile_settings,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    refreshSelectedProfileFormSet(&model);

    update(&model, .show_profile_tax_forms);
    update(&model, .{ .profile_setup_select_year = 2026 });
    try std.testing.expect(model.profileTaxFormsActive());
    try std.testing.expect(model.regLoaded);
    try std.testing.expectEqual(
        profile_registration_ui.PageState.viewing,
        model.regPage.page_state,
    );
    try std.testing.expectEqual(@as(i32, 2026), model.taxProfiles.workspaceYear().?);
    try std.testing.expectEqual(@as(usize, 1), model.regPage.businessActivities().len);
    try std.testing.expectEqual(
        @as(usize, 1),
        model.regPage.registrationObligations().len,
    );
    try expectAppMarkupBuilds(&model);
    const baseline_activity = model.regPage.businessActivities()[0];
    const baseline_obligation = model.regPage.registrationObligations()[0];

    update(&model, .reg_edit);
    try std.testing.expectEqual(
        profile_registration_ui.PageState.editing,
        model.regPage.page_state,
    );
    try std.testing.expect(!model.regPage.dirty());
    try std.testing.expect(model.regSaveDisabled());
    try std.testing.expect(model.regCancelDisabled());

    update(&model, .reg_add_act);
    try expectAppMarkupBuilds(&model);
    update(&model, .reg_dialog_cancel);
    try std.testing.expect(!model.regDialog());
    try expectAppMarkupBuilds(&model);
    update(&model, .reg_add_act);
    update(&model, .{
        .reg_line_input = .{ .insert_text = "Retail trade" },
    });
    update(&model, .{ .reg_atc_input = .{ .insert_text = "PT020" } });
    update(&model, .{ .reg_from_input = .clear });
    update(&model, .{
        .reg_from_input = .{ .insert_text = "2026-02-15" },
    });
    update(&model, .{
        .reg_until_input = .{ .insert_text = "2026-12-31" },
    });
    try expectAppMarkupBuilds(&model);
    update(&model, .reg_dialog_save);
    try expectAppMarkupBuilds(&model);

    update(&model, .reg_add_ob);
    update(&model, .reg_kind_vat);
    update(&model, .{ .reg_from_input = .clear });
    update(&model, .{
        .reg_from_input = .{ .insert_text = "2026-03-01" },
    });
    update(&model, .reg_dialog_save);
    try std.testing.expect(model.regPage.dirty());
    try std.testing.expect(!model.regSaveDisabled());
    try std.testing.expect(!model.regCancelDisabled());
    try std.testing.expectEqual(@as(usize, 2), model.regPage.businessActivities().len);
    try std.testing.expectEqual(
        @as(usize, 2),
        model.regPage.registrationObligations().len,
    );
    try expectAppMarkupBuilds(&model);

    // Main dashboard navigation is guarded too; it cannot silently reload
    // and discard a dirty Registration draft.
    update(&model, .show_dashboard_calendar);
    try std.testing.expectEqual(
        DashboardSection.profile_settings,
        model.dashboardSection,
    );
    try std.testing.expect(model.regPage.dirty());
    try std.testing.expect(model.profileDirtyNavigationVisible());
    try std.testing.expectEqualStrings(
        "Discard unsaved Registration changes?",
        model.profileDirtyNavigationTitle(),
    );
    update(&model, .profile_keep_editing);
    try std.testing.expect(!model.profileDirtyNavigationVisible());
    try std.testing.expect(model.regPage.dirty());

    update(&model, .{ .profile_setup_select_year = 2027 });
    try std.testing.expectEqual(@as(i32, 2026), model.taxProfiles.workspaceYear().?);
    try std.testing.expectEqualStrings(
        "Save or cancel registration edits before changing tax year.",
        model.regErrText(),
    );

    update(&model, .reg_cancel);
    try std.testing.expect(model.profileTaxFormsActive());
    try std.testing.expectEqual(
        profile_registration_ui.PageState.viewing,
        model.regPage.page_state,
    );
    try std.testing.expect(!model.regPage.dirty());
    try std.testing.expectEqual(@as(usize, 1), model.regPage.businessActivities().len);
    try std.testing.expectEqual(
        @as(usize, 1),
        model.regPage.registrationObligations().len,
    );
    const restored_activity = &model.regPage.businessActivities()[0];
    try std.testing.expect(restored_activity.anchor_id.eql(
        &baseline_activity.anchor_id,
    ));
    try std.testing.expectEqualStrings(
        baseline_activity.line_of_business.asSlice(),
        restored_activity.line_of_business.asSlice(),
    );
    try std.testing.expectEqualStrings(
        baseline_activity.atc.?.asSlice(),
        restored_activity.atc.?.asSlice(),
    );
    try std.testing.expect(restored_activity.effective.eql(
        baseline_activity.effective,
    ));
    try std.testing.expect(restored_activity.origin.?.revision_id.eql(
        &baseline_activity.origin.?.revision_id,
    ));
    try std.testing.expectEqual(
        baseline_activity.origin.?.sequence,
        restored_activity.origin.?.sequence,
    );
    const restored_obligation = &model.regPage.registrationObligations()[0];
    try std.testing.expect(restored_obligation.anchor_id.eql(
        &baseline_obligation.anchor_id,
    ));
    try std.testing.expect(restored_obligation.effective.eql(
        baseline_obligation.effective,
    ));
    try std.testing.expect(restored_obligation.origin.?.revision_id.eql(
        &baseline_obligation.origin.?.revision_id,
    ));
    try std.testing.expectEqual(
        baseline_obligation.origin.?.sequence,
        restored_obligation.origin.?.sequence,
    );
    switch (restored_obligation.kind) {
        .registered_income_tax => {},
        else => return error.TestUnexpectedResult,
    }

    update(&model, .reg_edit);
    update(&model, .reg_add_act);
    update(&model, .{
        .reg_line_input = .{ .insert_text = "Retail trade" },
    });
    update(&model, .{ .reg_atc_input = .{ .insert_text = "PT020" } });
    update(&model, .{ .reg_from_input = .clear });
    update(&model, .{
        .reg_from_input = .{ .insert_text = "2026-02-15" },
    });
    update(&model, .{
        .reg_until_input = .{ .insert_text = "2026-12-31" },
    });
    update(&model, .reg_dialog_save);
    const saved_activity_anchor = model.regPage.businessActivities()[1].anchor_id;

    update(&model, .reg_add_ob);
    update(&model, .reg_kind_vat);
    update(&model, .{ .reg_from_input = .clear });
    update(&model, .{
        .reg_from_input = .{ .insert_text = "2026-03-01" },
    });
    update(&model, .reg_dialog_save);
    const saved_obligation_anchor = model.regPage.registrationObligations()[1].anchor_id;
    update(&model, .reg_save);

    try std.testing.expectEqual(
        profile_registration_ui.PageState.viewing,
        model.regPage.page_state,
    );
    try std.testing.expect(!model.regPage.dirty());
    try std.testing.expectEqual(@as(u32, 2), model.regPage.expected_sequence);

    const profile_id = try profile_model.ProfileId.parse(profile_id_text);
    const viewed_on = try profile_model.Date.parseIso("2026-12-31");
    var persisted = try profile_persistence.loadRegistrationAggregateOn(
        &store,
        allocator,
        profile_id,
        viewed_on,
    );
    defer persisted.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 2), persisted.stream_sequence);
    try std.testing.expectEqual(@as(usize, 2), persisted.activity_anchors.len);
    try std.testing.expectEqual(@as(usize, 2), persisted.obligation_anchors.len);

    const persisted_activity = (try persisted.aggregate.resolveActivity(
        saved_activity_anchor,
        viewed_on,
    )).confirmed orelse return error.TestUnexpectedResult;
    try std.testing.expect(persisted_activity.anchor_id.eql(
        &saved_activity_anchor,
    ));
    try std.testing.expectEqualStrings(
        "Retail trade",
        persisted_activity.line_of_business.asSlice(),
    );
    try std.testing.expectEqualStrings("PT020", persisted_activity.atc.?.asSlice());
    try std.testing.expect(persisted_activity.metadata.effective.from.eql(
        try profile_model.Date.parseIso("2026-02-15"),
    ));
    try std.testing.expect(persisted_activity.metadata.effective.until.?.eql(
        try profile_model.Date.parseIso("2026-12-31"),
    ));

    const persisted_obligation = (try persisted.aggregate.resolveObligation(
        saved_obligation_anchor,
        viewed_on,
    )).confirmed orelse return error.TestUnexpectedResult;
    try std.testing.expect(persisted_obligation.anchor_id.eql(
        &saved_obligation_anchor,
    ));
    try std.testing.expect(persisted_obligation.metadata.effective.from.eql(
        try profile_model.Date.parseIso("2026-03-01"),
    ));
    try std.testing.expect(persisted_obligation.metadata.effective.until == null);
    switch (persisted_obligation.kind) {
        .vat => {},
        else => return error.TestUnexpectedResult,
    }

    // Discard is explicit and restores the saved Registration baseline before
    // the deferred dashboard navigation is allowed to run.
    update(&model, .reg_edit);
    update(&model, .{ .reg_remove_act = 1 });
    try std.testing.expect(model.regPage.dirty());
    update(&model, .show_dashboard_calendar);
    try std.testing.expect(model.profileDirtyNavigationVisible());
    update(&model, .profile_discard_navigation);
    try std.testing.expectEqual(DashboardSection.calendar, model.dashboardSection);
    try std.testing.expect(!model.regPage.dirty());
    update(&model, .show_dashboard_profile_settings);
    update(&model, .show_profile_tax_forms);
    try std.testing.expectEqual(
        @as(usize, 2),
        model.regPage.businessActivities().len,
    );
}

test "Registration and Forms keeps a Jan-Jun component visible and editable for its year" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    const profile_id_text = "part-year-registration-owner";
    try addTestProfile(
        &store,
        profile_id_text,
        "Part-year Registration Owner",
        "753-159-486-000",
        .sole_proprietor,
    );
    const activities = [_]profile_store.RegistrationActivityRevisionWrite{.{
        .anchor_id = "part-year-consulting",
        .metadata = .{
            .id = "part-year-consulting-r1",
            .expected_component_sequence = 0,
            .effective = .{
                .from = "2026-01-01".*,
                .until = "2026-06-30".*,
            },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .line_of_business = "Seasonal consulting",
        .atc = "PT010",
    }};
    const obligations = [_]profile_store.RegistrationObligationRevisionWrite{.{
        .anchor_id = "part-year-percentage-tax",
        .metadata = .{
            .id = "part-year-percentage-tax-r1",
            .expected_component_sequence = 0,
            .effective = .{
                .from = "2026-01-01".*,
                .until = "2026-06-30".*,
            },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 2,
        },
        .kind = .percentage_tax,
    }};
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.appendRegistrationCommit(.{
            .profile_id = profile_id_text,
            .expected_current_sequence = 0,
            .activities = &activities,
            .obligations = &obligations,
        }),
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .profile_settings,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    refreshSelectedProfileFormSet(&model);

    update(&model, .show_profile_tax_forms);
    update(&model, .{ .profile_setup_select_year = 2026 });
    try std.testing.expect(model.regLoaded);
    try std.testing.expectEqual(@as(?u16, 2026), model.regPage.selected_tax_year);
    try std.testing.expectEqual(@as(usize, 1), model.regPage.businessActivities().len);
    try std.testing.expectEqual(
        @as(usize, 1),
        model.regPage.registrationObligations().len,
    );
    const original_anchor = model.regPage.businessActivities()[0].anchor_id;
    const original_period = model.regPage.businessActivities()[0].effective;
    try std.testing.expectEqualStrings(
        "part-year-consulting",
        original_anchor.asSlice(),
    );
    try std.testing.expect(original_period.eql(
        try profile_registration.EffectivePeriod.init(
            try profile_model.Date.parseIso("2026-01-01"),
            try profile_model.Date.parseIso("2026-06-30"),
        ),
    ));

    update(&model, .reg_edit);
    update(&model, .{ .reg_edit_act = 0 });
    try std.testing.expectEqualStrings("2026-01-01", model.regFrom());
    try std.testing.expectEqualStrings("2026-06-30", model.regUntil());
    update(&model, .{ .reg_line_input = .clear });
    update(&model, .{
        .reg_line_input = .{ .insert_text = "Seasonal advisory" },
    });
    update(&model, .{ .reg_atc_input = .clear });
    update(&model, .{
        .reg_atc_input = .{ .insert_text = "PT011" },
    });
    update(&model, .reg_dialog_save);
    update(&model, .reg_save);

    try std.testing.expect(model.regLoaded);
    try std.testing.expectEqual(@as(usize, 1), model.regPage.businessActivities().len);
    const reloaded = &model.regPage.businessActivities()[0];
    try std.testing.expect(reloaded.anchor_id.eql(&original_anchor));
    try std.testing.expect(reloaded.effective.eql(original_period));
    try std.testing.expectEqualStrings(
        "Seasonal advisory",
        reloaded.line_of_business.asSlice(),
    );
    try std.testing.expectEqualStrings("PT011", reloaded.atc.?.asSlice());
    try std.testing.expect(model.regPage.registrationObligations()[0].effective.eql(
        original_period,
    ));

    const profile_id = try profile_model.ProfileId.parse(profile_id_text);
    var persisted = try profile_persistence.loadRegistrationAggregateForYear(
        &store,
        allocator,
        profile_id,
        2026,
    );
    defer persisted.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 2), persisted.stream_sequence);
    try std.testing.expect(persisted.business_activities[0].anchor_id.eql(
        &original_anchor,
    ));
    try std.testing.expect(persisted.business_activities[0].metadata.effective.eql(
        original_period,
    ));
}

test "Tax Form Profile page saves exact annual activity and dirty Cancel stays" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    try persistTestSoleProprietorRevision(
        &store,
        "tax-form-profile-owner",
        "tax-form-profile-owner-r1",
        1,
        "2026-01-01",
        "Annual Setup Taxpayer",
        "321-654-987-000",
        &.{},
    );
    try addTestProfile(
        &store,
        "tax-form-profile-other-owner",
        "Other Annual Setup Taxpayer",
        "321-654-988-000",
        .corporation,
    );
    const registration_activities = [_]profile_store.RegistrationActivityRevisionWrite{.{
        .anchor_id = "tax-form-profile-consulting",
        .metadata = .{
            .id = "tax-form-profile-consulting-v16-r1",
            .expected_component_sequence = 0,
            .effective = .{ .from = "2026-01-01".* },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .line_of_business = "Professional consulting",
        .atc = "PT010",
    }};
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.appendRegistrationCommit(.{
            .profile_id = "tax-form-profile-owner",
            .expected_current_sequence = 0,
            .activities = &registration_activities,
        }),
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    refreshSelectedProfileFormSet(&model);

    const index = formCatalogIndex("1601C").?;
    update(&model, .{ .open_tax_form_profile = index });
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expectEqualStrings("1601C", model.taxFormProfileCode());
    try std.testing.expectEqual(
        tax_form_profile_ui.PageState.needs_setup,
        model.taxFormProfilePage.page().?,
    );
    try std.testing.expectEqual(
        tax_form_profile_ui.FilingReadiness.ready,
        model.taxFormProfilePage.filingReadiness(),
    );
    try std.testing.expectEqualStrings(
        "primary",
        model.taxFormProfileStatusTone(),
    );
    try expectAppMarkupBuilds(&model);

    // Back restores the exact dashboard surface that opened the annual
    // setup instead of falling through to Calendar.
    try std.testing.expectEqualStrings(
        "Back to Tax Form Library",
        model.taxFormProfileBackLabel(),
    );
    update(&model, .close_tax_form_profile);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expectEqual(DashboardSection.forms, model.dashboardSection);

    model.dashboardSection = .profile_settings;
    model.profileSetupSection = .tax_forms;
    update(&model, .{ .open_tax_form_profile = index });
    try std.testing.expectEqualStrings(
        "Back to Registration & Forms",
        model.taxFormProfileBackLabel(),
    );
    update(&model, .close_tax_form_profile);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expectEqual(
        DashboardSection.profile_settings,
        model.dashboardSection,
    );
    try std.testing.expectEqual(
        ProfileSetupSection.tax_forms,
        model.profileSetupSection,
    );

    update(&model, .{ .open_tax_form_profile = index });
    try std.testing.expectEqual(Page.tax_form_profile, model.page);

    update(&model, .edit_tax_form_profile);
    try expectAppMarkupBuilds(&model);
    try std.testing.expect(model.taxFormProfileEditing());
    try std.testing.expect(model.taxFormProfileSaveDisabled());
    try std.testing.expect(model.taxFormProfileCancelDisabled());
    try std.testing.expectEqual(@as(usize, 1), model.taxFormProfileChoiceCount);

    update(&model, .{ .tax_form_profile_toggle_picker = 0 });
    try expectAppMarkupBuilds(&model);
    update(&model, .{ .tax_form_profile_select_choice = 0 });
    try std.testing.expect(model.taxFormProfilePage.dirty());
    try std.testing.expect(!model.taxFormProfileSaveDisabled());
    try std.testing.expect(!model.taxFormProfileCancelDisabled());
    update(&model, .close_tax_form_profile);
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expect(model.taxFormProfileDiscardPromptOpen);
    update(&model, .tax_form_profile_keep_editing);

    // Every taxpayer-context mutation is deferred before it can change the
    // sidebar/profile shell behind this dirty annual setup.
    const other_profile_slot = profileSlotNamed(
        &model,
        "Other Annual Setup Taxpayer",
    ).?;
    update(&model, .{ .select_taxpayer = other_profile_slot });
    try std.testing.expectEqualStrings(
        "tax-form-profile-owner",
        model.taxProfiles.selectedProfileId().?,
    );
    try std.testing.expect(model.taxFormProfileDiscardPromptOpen);
    update(&model, .tax_form_profile_keep_editing);
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    update(&model, .new_taxpayer_profile);
    try std.testing.expectEqualStrings(
        "tax-form-profile-owner",
        model.taxProfiles.selectedProfileId().?,
    );
    try std.testing.expect(model.taxFormProfileDiscardPromptOpen);
    update(&model, .tax_form_profile_keep_editing);
    update(&model, .add_branch_profile);
    try std.testing.expectEqualStrings(
        "tax-form-profile-owner",
        model.taxProfiles.selectedProfileId().?,
    );
    try std.testing.expect(model.taxFormProfileDiscardPromptOpen);
    update(&model, .tax_form_profile_keep_editing);
    update(&model, .cancel_tax_form_profile);
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expect(!model.taxFormProfilePage.dirty());
    try std.testing.expectEqual(@as(usize, 0), model.taxFormProfilePage.draftValues().len);

    update(&model, .edit_tax_form_profile);
    update(&model, .{ .tax_form_profile_select_choice = 0 });
    update(&model, .save_tax_form_profile);
    try std.testing.expectEqual(
        tax_form_profile_ui.PageState.viewing_ready,
        model.taxFormProfilePage.page().?,
    );
    try std.testing.expect(!model.taxFormProfilePage.dirty());
    try std.testing.expectEqual(
        TaxFormProfileCardState.ready,
        model.taxFormProfileCardStates[index],
    );
    const saved_bindings = loadLaunchTaxFormProfileBindings(
        &model,
        &form_catalog.forms[index],
        index,
        model.taxProfiles.selectedProfileDomainId().?,
        2026,
        model.taxFormProfileViewedDate.?,
        launchAssessmentForViewedDate(
            &model,
            &form_catalog.forms[index],
            index,
            model.taxFormProfileViewedDate.?,
        ),
    );
    try std.testing.expectEqual(TaxFormProfileCardState.ready, saved_bindings.state);
    try std.testing.expectEqualStrings(
        "tax-form-profile-consulting",
        saved_bindings.filer_activity_id.?.asSlice(),
    );

    const profile_id = model.taxProfiles.selectedProfileDomainId().?;
    const stream = taxFormProfileStream(
        profile_id,
        &form_catalog.forms[index],
        2026,
    ).?;
    var history = try profile_persistence.loadTaxFormProfileHistory(
        &store,
        allocator,
        stream,
    );
    defer history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), history.history.revisions.len);
    try std.testing.expectEqual(@as(usize, 1), history.history.revisions[0].values.len);

    // The saved annual setup points at a v16-only stable anchor: the base Tax
    // Profile intentionally has no legacy business_activity row. The real
    // launch path must resolve that Registration anchor, project its LOB, and
    // mount the editor instead of bouncing back to setup.
    const filing: form_period.FilingPeriod = .{ .monthly = .{
        .tax_year = 2026,
        .month = 8,
    } };
    try std.testing.expect(openProfileBoundFormForQuarter(
        &model,
        .form_1601_c,
        "1601C",
        2026,
        3,
        8,
        null,
        filing,
    ));
    try std.testing.expectEqual(Page.form_1601_c, model.page);
    try std.testing.expect(model.formProfiles.projectionAccepted());
    try std.testing.expectEqualStrings(
        "Professional consulting",
        model.formProfiles.filerText(.line_of_business),
    );
    try expectAppMarkupBuilds(&model);

    openTaxFormProfileForYear(&model, index, 2027);
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expect(model.taxFormProfileCopyPriorYearVisible());
    update(&model, .tax_form_profile_copy_prior_year);
    try std.testing.expect(model.taxFormProfileEditing());
    try std.testing.expect(model.taxFormProfilePage.dirty());
    try std.testing.expect(model.taxFormProfileReviewVisible());
    try std.testing.expect(model.taxFormProfileSaveDisabled());
    update(&model, .tax_form_profile_acknowledge_review);
    try std.testing.expect(!model.taxFormProfileSaveDisabled());
    update(&model, .save_tax_form_profile);

    const stream_2027 = taxFormProfileStream(
        profile_id,
        &form_catalog.forms[index],
        2027,
    ).?;
    var copied_history = try profile_persistence.loadTaxFormProfileHistory(
        &store,
        allocator,
        stream_2027,
    );
    defer copied_history.deinit(allocator);
    try std.testing.expectEqual(
        @as(usize, 1),
        copied_history.history.revisions.len,
    );
    const copied = &copied_history.history.revisions[0];
    try std.testing.expectEqual(
        tax_form_profile_domain.ReviewState.confirmed,
        copied.review_state,
    );
    try std.testing.expectEqual(
        @as(u16, 2026),
        copied.source.copied_from_prior_year.source_tax_year,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.taxFormProfileHistoryRowCount,
    );

    // A saved optional activity can be explicitly cleared. The clear is an
    // append-only revision (not a silent deletion), so its Save affordance
    // must remain enabled even though the editable value set is now empty.
    openTaxFormProfileForYear(&model, index, 2026);
    update(&model, .edit_tax_form_profile);
    update(&model, .{ .tax_form_profile_clear_value = 0 });
    try std.testing.expect(model.taxFormProfilePage.dirty());
    try std.testing.expect(!model.taxFormProfileSaveDisabled());
    update(&model, .save_tax_form_profile);
    try std.testing.expectEqual(
        tax_form_profile_ui.PageState.viewing_ready,
        model.taxFormProfilePage.page().?,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        model.taxFormProfilePage.baselineValues().len,
    );
    var cleared_history = try profile_persistence.loadTaxFormProfileHistory(
        &store,
        allocator,
        stream,
    );
    defer cleared_history.deinit(allocator);
    try std.testing.expectEqual(
        @as(usize, 2),
        cleared_history.history.revisions.len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        cleared_history.history.revisions[1].values.len,
    );

    // The only saved Registration activity is a valid choice, but selecting
    // it again against the cleared revision is now a real change and enables
    // Save. This distinguishes one eligible Registration activity from a
    // hard-coded form-profile option.
    update(&model, .edit_tax_form_profile);
    update(&model, .{ .tax_form_profile_toggle_picker = 0 });
    update(&model, .{ .tax_form_profile_select_choice = 0 });
    try std.testing.expect(model.taxFormProfilePage.dirty());
    try std.testing.expect(!model.taxFormProfileSaveDisabled());

    // Discarding a later dirty edit now performs the deferred taxpayer change
    // only after the old annual setup has been reset.
    update(&model, .{ .select_taxpayer = other_profile_slot });
    try std.testing.expectEqualStrings(
        "tax-form-profile-owner",
        model.taxProfiles.selectedProfileId().?,
    );
    update(&model, .tax_form_profile_discard_navigation);
    try std.testing.expectEqualStrings(
        "tax-form-profile-other-owner",
        model.taxProfiles.selectedProfileId().?,
    );
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
}

test "Tax Form Profile reviews and saves a prior catalog form revision" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    try persistTestSoleProprietorRevision(
        &store,
        "cross-revision-ui-owner",
        "cross-revision-ui-owner-r1",
        1,
        "2025-01-01",
        "Cross Revision UI Taxpayer",
        "654-321-987-000",
        &.{},
    );
    const registration_activities = [_]profile_store.RegistrationActivityRevisionWrite{.{
        .anchor_id = "cross-revision-ui-activity",
        .metadata = .{
            .id = "cross-revision-ui-activity-r1",
            .expected_component_sequence = 0,
            .effective = .{ .from = "2025-01-01".* },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .line_of_business = "Professional services",
        .atc = "PT010",
    }};
    _ = try store.appendRegistrationCommit(.{
        .profile_id = "cross-revision-ui-owner",
        .expected_current_sequence = 0,
        .activities = &registration_activities,
    });

    const definition = form_catalog.findForm("1601C").?;
    try store.replaceFormSet("cross-revision-ui-owner", 2025, &.{.{
        .form_code = definition.code,
        .form_revision = "2017-OLD",
    }});
    try store.replaceFormSet("cross-revision-ui-owner", 2026, &.{.{
        .form_code = definition.code,
        .form_revision = definition.revision.?,
    }});
    try profile_store.testing.execHistoricalFixture(&store,
        \\INSERT INTO tax_profile_form_profile_revisions (
        \\    profile_id, tax_year, form_code, form_revision, id,
        \\    sequence, effective_from, spec_revision, spec_hash,
        \\    review_state, confirmed_at_unix_seconds, source_tag
        \\) VALUES (
        \\    'cross-revision-ui-owner', 2025, '1601C', '2017-OLD',
        \\    'cross-revision-ui-source', 1, '2025-01-01', 7,
        \\    'old-generated-spec-hash', 'confirmed', 1735689600,
        \\    'manual_entry'
        \\);
        \\INSERT INTO tax_profile_form_profile_values (
        \\    profile_id, tax_year, form_code, form_revision,
        \\    revision_id, revision_sequence, semantic_key, role,
        \\    value_type, anchor_value, source_tag
        \\) VALUES (
        \\    'cross-revision-ui-owner', 2025, '1601C', '2017-OLD',
        \\    'cross-revision-ui-source', 1,
        \\    'business_activity_anchor_id', 'filer',
        \\    'business_activity_anchor_id', 'cross-revision-ui-activity',
        \\    'manual_confirmation'
        \\);
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    refreshSelectedProfileFormSet(&model);

    const index = formCatalogIndex("1601C").?;
    openTaxFormProfileForYear(&model, index, 2026);
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expect(model.taxFormProfileCopyPriorYearVisible());
    try std.testing.expectEqual(
        tax_form_profile_ui.ReuseReason.form_revision_mapping,
        model.taxFormProfilePage.copy_offer.?.reason,
    );
    update(&model, .tax_form_profile_copy_prior_year);
    try std.testing.expect(model.taxFormProfileEditing());
    const review = model.taxFormProfilePage.mappingReview().?;
    try std.testing.expectEqual(@as(u16, 1), review.mapped_count);
    try std.testing.expectEqual(@as(usize, 0), review.issue_count);
    var review_arena = std.heap.ArenaAllocator.init(allocator);
    defer review_arena.deinit();
    try std.testing.expect(std.mem.indexOf(
        u8,
        model.taxFormProfileReviewText(review_arena.allocator()),
        "Mapped 1 compatible value",
    ) != null);
    update(&model, .tax_form_profile_acknowledge_review);
    update(&model, .save_tax_form_profile);

    const stream = taxFormProfileStream(
        model.taxProfiles.selectedProfileDomainId().?,
        definition,
        2026,
    ).?;
    var history = try profile_persistence.loadTaxFormProfileHistory(
        &store,
        allocator,
        stream,
    );
    defer history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), history.history.revisions.len);
    const copy = history.history.revisions[0].source.copied_from_prior_year;
    try std.testing.expectEqualStrings(
        "2017-OLD",
        copy.source_form_revision.asSlice(),
    );
    try std.testing.expectEqual(@as(u32, 7), copy.source_spec_revision);
    try std.testing.expectEqualStrings(
        "cross-revision-ui-source",
        copy.source_revision_id.asSlice(),
    );
}

test "retired Tax Form Profile anchors make card page and launch need setup" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    try addTestProfile(
        &store,
        "retired-binding-owner",
        "Retired Binding Owner",
        "741-852-963-000",
        .sole_proprietor,
    );
    const activity_rows = [_]profile_store.RegistrationActivityRevisionWrite{
        .{
            .anchor_id = "retired-binding-activity",
            .metadata = .{
                .id = "retired-binding-activity-r1",
                .expected_component_sequence = 0,
                .effective = .{
                    .from = "2026-01-01".*,
                    .until = "2026-06-30".*,
                },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 1,
            },
            .line_of_business = "Retired consulting activity",
            .atc = "PT010",
        },
        .{
            // Keeps the base/profile projection complete on the viewed date
            // while proving that the separately saved old anchor is stale.
            .anchor_id = "current-binding-activity",
            .metadata = .{
                .id = "current-binding-activity-r1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-07-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 2,
            },
            .line_of_business = "Current consulting activity",
            .atc = "PT011",
        },
    };
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.appendRegistrationCommit(.{
            .profile_id = "retired-binding-owner",
            .expected_current_sequence = 0,
            .activities = &activity_rows,
        }),
    );

    const definition = form_catalog.findForm("1601C").?;
    const profile_id = try profile_model.ProfileId.parse(
        "retired-binding-owner",
    );
    const setup_values = [_]tax_form_profile_domain.SetupValue{.{
        .semantic_key = .business_activity_anchor_id,
        .role = .filer,
        .value = .{
            .business_activity_anchor_id = try tax_form_profile_domain
                .ComponentAnchorId.parse("retired-binding-activity"),
        },
    }};
    const setup_revision: tax_form_profile_domain.Revision = .{
        .id = try tax_form_profile_domain.RevisionId.parse(
            "retired-binding-setup-r1",
        ),
        .stream = taxFormProfileStream(
            profile_id,
            definition,
            2026,
        ).?,
        .sequence = 1,
        .effective = try tax_form_profile_domain.EffectivePeriod.init(
            try profile_model.Date.parseIso("2026-01-01"),
            try profile_model.Date.parseIso("2026-12-31"),
        ),
        .spec_revision = definition.tax_form_profile.spec_revision.?,
        .spec_hash = try tax_form_profile_domain.SpecHash.parse(
            definition.tax_form_profile.spec_hash.?,
        ),
        .review_state = .confirmed,
        .confirmed_at_unix = 1,
        .source = .manual_entry,
        .values = &setup_values,
    };
    try profile_persistence.appendTaxFormProfileRevision(
        &store,
        allocator,
        0,
        &setup_revision,
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    refreshSelectedProfileFormSet(&model);

    const index = formCatalogIndex("1601C").?;
    try std.testing.expectEqual(
        TaxFormProfileCardState.needs_setup,
        model.taxFormProfileCardStates[index],
    );
    openTaxFormProfileForYear(&model, index, 2026);
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expectEqual(
        tax_form_profile_ui.PageState.needs_setup,
        model.taxFormProfilePage.page().?,
    );
    try std.testing.expectEqual(
        tax_form_profile_ui.FilingReadiness.missing_annual_setup,
        model.taxFormProfilePage.filingReadiness(),
    );

    const launch = launchAssessmentForViewedDate(
        &model,
        definition,
        index,
        model.taxFormProfileViewedDate.?,
    );
    const bindings = loadLaunchTaxFormProfileBindings(
        &model,
        definition,
        index,
        profile_id,
        2026,
        model.taxFormProfileViewedDate.?,
        launch,
    );
    try std.testing.expectEqual(
        TaxFormProfileCardState.needs_setup,
        bindings.state,
    );
    try std.testing.expect(bindings.filer_activity_id == null);
    try std.testing.expect(!openProfileBoundFormForQuarter(
        &model,
        .form_1601_c,
        "1601C",
        2026,
        3,
        8,
        null,
        .{ .monthly = .{ .tax_year = 2026, .month = 8 } },
    ));
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
}

test "empty Tax Form Profile activity picker repairs Registration and returns to the same year" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    try persistTestSoleProprietorRevision(
        &store,
        "tax-form-profile-repair-owner",
        "tax-form-profile-repair-r1",
        1,
        "2026-01-01",
        "Registration Repair Taxpayer",
        "654-321-987-000",
        &.{},
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    refreshSelectedProfileFormSet(&model);

    const index = formCatalogIndex("1601C").?;
    update(&model, .{ .open_tax_form_profile = index });
    update(&model, .edit_tax_form_profile);
    update(&model, .{ .tax_form_profile_toggle_picker = 0 });
    try std.testing.expect(model.taxFormProfileChoicesEmpty());
    try std.testing.expect(
        model.taxFormProfileChoicesRegistrationRepairVisible(),
    );

    update(&model, .tax_form_profile_edit_registration);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.profileTaxFormsActive());
    try std.testing.expect(model.taxFormProfileRegistrationReturnPending);
    try std.testing.expectEqual(
        profile_registration_ui.PageState.editing,
        model.regPage.page_state,
    );

    update(&model, .reg_add_act);
    update(&model, .{
        .reg_line_input = .{ .insert_text = "Professional services" },
    });
    update(&model, .{ .reg_atc_input = .{ .insert_text = "PT010" } });
    update(&model, .reg_dialog_save);
    update(&model, .reg_save);

    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expect(!model.taxFormProfileRegistrationReturnPending);
    try std.testing.expect(model.taxFormProfileEditing());
    try std.testing.expectEqualStrings("1601C", model.taxFormProfileCode());
    try std.testing.expectEqual(
        @as(u16, 2026),
        model.taxFormProfilePage.viewedIdentity().?.tax_year,
    );
    try std.testing.expectEqual(@as(?usize, 0), model.taxFormProfilePickerField);
    try std.testing.expectEqual(@as(usize, 1), model.taxFormProfileChoiceCount);
    try std.testing.expect(!model.taxFormProfileChoicesEmpty());

    update(&model, .{ .tax_form_profile_select_choice = 0 });
    update(&model, .save_tax_form_profile);
    try std.testing.expectEqual(
        tax_form_profile_ui.PageState.viewing_ready,
        model.taxFormProfilePage.page().?,
    );
}

test "Tax Form Profile opens the exact confirmed active segment, not silent year end" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "midyear-profile-owner",
        "Midyear Profile Owner",
        "159-753-486-000",
        .sole_proprietor,
    );

    const activity_rows = [_]profile_store.RegistrationActivityRevisionWrite{.{
        .anchor_id = "midyear-consulting",
        .metadata = .{
            .id = "midyear-consulting-r1",
            .expected_component_sequence = 0,
            .effective = .{
                .from = "2026-01-01".*,
                .until = "2026-06-30".*,
            },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .line_of_business = "Midyear consulting",
        .atc = "PT010",
    }};
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.appendRegistrationCommit(.{
            .profile_id = "midyear-profile-owner",
            .expected_current_sequence = 0,
            .activities = &activity_rows,
        }),
    );
    const interval_id = try store.generateOpaqueId();
    try store.createFormSetInterval(.{
        .id = &interval_id,
        .profile_id = "midyear-profile-owner",
        .tax_year = 2026,
        .effective_from = "2026-07-01",
        .forms = &.{},
    });

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    refreshSelectedProfileFormSet(&model);

    const index = formCatalogIndex("1601C").?;
    try std.testing.expect(model.profileFormAnyPeriodActive[index]);
    openTaxFormProfileForYear(&model, index, 2026);
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expect(model.taxFormProfilePage.active);
    try std.testing.expect(
        model.taxFormProfileViewedDate.?.eql(
            try profile_model.Date.parseIso("2026-06-30"),
        ),
    );
    const activation = model.taxFormProfilePage.activationPeriod().?;
    try std.testing.expect(
        activation.from.eql(try profile_model.Date.parseIso("2026-01-01")),
    );
    try std.testing.expect(
        activation.until.?.eql(
            try profile_model.Date.parseIso("2026-06-30"),
        ),
    );
    update(&model, .edit_tax_form_profile);
    try std.testing.expectEqual(
        @as(usize, 1),
        model.taxFormProfileChoiceCount,
    );
    try std.testing.expectEqualStrings(
        "midyear-consulting",
        model.taxFormProfileChoices[0].stable_id.text(),
    );
}

test "Tax Form Profile navigates disjoint activation intervals and saves older corrections at the stream head" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "segmented-profile-owner",
        "Segmented Profile Owner",
        "951-753-852-000",
        .sole_proprietor,
    );

    const activity_rows = [_]profile_store.RegistrationActivityRevisionWrite{
        .{
            .anchor_id = "segmented-consulting",
            .metadata = .{
                .id = "segmented-consulting-r1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-01-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 1,
            },
            .line_of_business = "Segmented consulting",
            .atc = "PT010",
        },
        .{
            .anchor_id = "segmented-training",
            .metadata = .{
                .id = "segmented-training-r1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-01-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 1,
            },
            .line_of_business = "Segmented training",
            .atc = "PT011",
        },
    };
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.appendRegistrationCommit(.{
            .profile_id = "segmented-profile-owner",
            .expected_current_sequence = 0,
            .activities = &activity_rows,
        }),
    );
    try store.createFormSetInterval(.{
        .id = "segmented-profile-q3-inactive",
        .profile_id = "segmented-profile-owner",
        .tax_year = 2026,
        .effective_from = "2026-07-01",
        .effective_until = "2026-09-30",
        .forms = &.{},
    });

    const definition = form_catalog.findForm("1601C").?;
    const profile_id = try profile_model.ProfileId.parse(
        "segmented-profile-owner",
    );
    const stream = taxFormProfileStream(profile_id, definition, 2026).?;
    const first_period = try tax_form_profile_domain.EffectivePeriod.init(
        try profile_model.Date.parseIso("2026-01-01"),
        try profile_model.Date.parseIso("2026-06-30"),
    );
    const second_period = try tax_form_profile_domain.EffectivePeriod.init(
        try profile_model.Date.parseIso("2026-10-01"),
        try profile_model.Date.parseIso("2026-12-31"),
    );
    const first_values = [_]tax_form_profile_domain.SetupValue{.{
        .semantic_key = .business_activity_anchor_id,
        .role = .filer,
        .value = .{
            .business_activity_anchor_id = try tax_form_profile_domain
                .ComponentAnchorId.parse("segmented-consulting"),
        },
    }};
    const second_values = [_]tax_form_profile_domain.SetupValue{.{
        .semantic_key = .business_activity_anchor_id,
        .role = .filer,
        .value = .{
            .business_activity_anchor_id = try tax_form_profile_domain
                .ComponentAnchorId.parse("segmented-training"),
        },
    }};
    const first_revision: tax_form_profile_domain.Revision = .{
        .id = try tax_form_profile_domain.RevisionId.parse(
            "segmented-profile-first-r1",
        ),
        .stream = stream,
        .sequence = 1,
        .effective = first_period,
        .spec_revision = definition.tax_form_profile.spec_revision.?,
        .spec_hash = try tax_form_profile_domain.SpecHash.parse(
            definition.tax_form_profile.spec_hash.?,
        ),
        .review_state = .confirmed,
        .confirmed_at_unix = 1,
        .source = .manual_entry,
        .values = &first_values,
    };
    try profile_persistence.appendTaxFormProfileRevision(
        &store,
        allocator,
        0,
        &first_revision,
    );
    const second_revision: tax_form_profile_domain.Revision = .{
        .id = try tax_form_profile_domain.RevisionId.parse(
            "segmented-profile-second-r1",
        ),
        .stream = stream,
        .sequence = 2,
        .effective = second_period,
        .spec_revision = definition.tax_form_profile.spec_revision.?,
        .spec_hash = try tax_form_profile_domain.SpecHash.parse(
            definition.tax_form_profile.spec_hash.?,
        ),
        .review_state = .confirmed,
        .confirmed_at_unix = 2,
        .source = .manual_entry,
        .values = &second_values,
    };
    try profile_persistence.appendTaxFormProfileRevision(
        &store,
        allocator,
        1,
        &second_revision,
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    refreshSelectedProfileFormSet(&model);

    const index = formCatalogIndex("1601C").?;
    openTaxFormProfileForYear(&model, index, 2026);
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expect(model.taxFormProfilePage.activationPeriod().?.eql(
        second_period,
    ));
    try std.testing.expectEqual(
        @as(u32, 2),
        model.taxFormProfilePage.viewedIdentity().?.annual_revision_sequence,
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        model.taxFormProfilePage.expected_sequence,
    );
    try std.testing.expect(!model.taxFormProfilePreviousSegmentDisabled());
    try std.testing.expect(model.taxFormProfileNextSegmentDisabled());

    update(&model, .tax_form_profile_previous_segment);
    try std.testing.expect(model.taxFormProfilePage.activationPeriod().?.eql(
        first_period,
    ));
    try std.testing.expectEqual(
        @as(u32, 1),
        model.taxFormProfilePage.viewedIdentity().?.annual_revision_sequence,
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        model.taxFormProfilePage.expected_sequence,
    );
    try std.testing.expect(model.taxFormProfilePreviousSegmentDisabled());
    try std.testing.expect(!model.taxFormProfileNextSegmentDisabled());

    try model.taxFormProfilePage.beginEdit();
    try model.taxFormProfilePage.setDraftValue(second_values[0]);
    update(&model, .tax_form_profile_next_segment);
    try std.testing.expect(model.taxFormProfileDiscardPromptOpen);
    try std.testing.expect(model.taxFormProfilePage.activationPeriod().?.eql(
        first_period,
    ));
    update(&model, .tax_form_profile_keep_editing);
    try std.testing.expect(model.taxFormProfilePage.dirty());
    update(&model, .tax_form_profile_next_segment);
    update(&model, .tax_form_profile_discard_navigation);
    try std.testing.expect(!model.taxFormProfileDiscardPromptOpen);
    try std.testing.expect(model.taxFormProfilePage.activationPeriod().?.eql(
        second_period,
    ));

    update(&model, .tax_form_profile_previous_segment);
    try model.taxFormProfilePage.beginEdit();
    try model.taxFormProfilePage.setDraftValue(second_values[0]);
    update(&model, .save_tax_form_profile);
    try std.testing.expectEqual(
        tax_form_profile_ui.PageState.viewing_ready,
        model.taxFormProfilePage.page().?,
    );
    try std.testing.expectEqual(
        @as(u32, 3),
        model.taxFormProfilePage.viewedIdentity().?.annual_revision_sequence,
    );
    try std.testing.expect(model.taxFormProfilePage.activationPeriod().?.eql(
        first_period,
    ));

    update(&model, .tax_form_profile_next_segment);
    try std.testing.expect(model.taxFormProfilePage.activationPeriod().?.eql(
        second_period,
    ));
    try std.testing.expectEqual(
        @as(u32, 2),
        model.taxFormProfilePage.viewedIdentity().?.annual_revision_sequence,
    );
    try std.testing.expectEqual(
        @as(u32, 3),
        model.taxFormProfilePage.expected_sequence,
    );

    var history = try profile_persistence.loadTaxFormProfileHistory(
        &store,
        allocator,
        stream,
    );
    defer history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), history.history.revisions.len);
    try std.testing.expect(history.history.revisions[2].effective.eql(
        first_period,
    ));
    try std.testing.expectEqualStrings(
        "segmented-training",
        history.history.revisions[2]
            .values[0]
            .value
            .business_activity_anchor_id
            .asSlice(),
    );
}

fn taxFormProfileChoiceContains(
    model: *const Model,
    field_index: usize,
    stable_id: []const u8,
) bool {
    for (model.taxFormProfileChoices[0..model.taxFormProfileChoiceCount]) |*choice| {
        if (choice.field_index == field_index and
            std.mem.eql(u8, choice.stable_id.text(), stable_id))
        {
            return true;
        }
    }
    return false;
}

test "Tax Form Profile pickers use confirmed date-effective registration and role policy" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    try addTestProfile(
        &store,
        "picker-filer",
        "Picker Filer",
        "101-101-101-000",
        .individual,
    );
    try addTestProfile(
        &store,
        "picker-individual",
        "Eligible Individual",
        "202-202-202-000",
        .individual,
    );
    try addTestProfile(
        &store,
        "picker-sole",
        "Eligible Sole Proprietor",
        "303-303-303-000",
        .sole_proprietor,
    );
    try addTestProfile(
        &store,
        "picker-corporation",
        "Ineligible Corporation",
        "404-404-404-000",
        .corporation,
    );
    try addTestProfile(
        &store,
        "picker-partnership",
        "Ineligible Partnership",
        "505-505-505-000",
        .partnership,
    );
    try addTestProfile(
        &store,
        "picker-estate",
        "Ineligible Estate",
        "606-606-606-000",
        .estate,
    );

    const registration_activities = [_]profile_store.RegistrationActivityRevisionWrite{
        .{
            .anchor_id = "expired-activity",
            .metadata = .{
                .id = "expired-activity-r1",
                .expected_component_sequence = 0,
                .effective = .{
                    .from = "2026-01-01".*,
                    .until = "2026-06-30".*,
                },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 1,
            },
            .line_of_business = "Expired activity",
        },
        .{
            .anchor_id = "confirmed-activity",
            .metadata = .{
                .id = "confirmed-activity-r1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-07-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 2,
            },
            .line_of_business = "Confirmed activity",
            .atc = "PT010",
        },
        .{
            .anchor_id = "proposal-activity",
            .metadata = .{
                .id = "proposal-activity-r1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-01-01".* },
                .source = .manual_entry,
                .review_state = .requires_review,
                .review_reason = .manual_proposal,
            },
            .line_of_business = "Unreviewed activity",
        },
        .{
            .anchor_id = "future-activity",
            .metadata = .{
                .id = "future-activity-r1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2027-01-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 3,
            },
            .line_of_business = "Future activity",
        },
    };
    const registration_obligations = [_]profile_store.RegistrationObligationRevisionWrite{
        .{
            .anchor_id = "expired-obligation",
            .metadata = .{
                .id = "expired-obligation-r1",
                .expected_component_sequence = 0,
                .effective = .{
                    .from = "2026-01-01".*,
                    .until = "2026-06-30".*,
                },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 4,
            },
            .kind = .registered_income_tax,
        },
        .{
            .anchor_id = "confirmed-obligation",
            .metadata = .{
                .id = "confirmed-obligation-r1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-07-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 5,
            },
            .kind = .withholding_expanded,
        },
        .{
            .anchor_id = "proposal-obligation",
            .metadata = .{
                .id = "proposal-obligation-r1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-01-01".* },
                .source = .manual_entry,
                .review_state = .requires_review,
                .review_reason = .specificity_unknown,
            },
            .kind = .unknown_requires_review,
            .value_text = "Needs review",
        },
        .{
            .anchor_id = "future-obligation",
            .metadata = .{
                .id = "future-obligation-r1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2027-01-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 6,
            },
            .kind = .vat,
        },
    };
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.appendRegistrationCommit(.{
            .profile_id = "picker-filer",
            .expected_current_sequence = 0,
            .activities = &registration_activities,
            .obligations = &registration_obligations,
        }),
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    model.taxProfiles.select(profileSlotNamed(&model, "Picker Filer").?);
    refreshSelectedProfileFormSet(&model);

    const form_index = formCatalogIndex("1701Q").?;
    openTaxFormProfileForYear(&model, form_index, 2026);
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    const definition = &form_catalog.forms[form_index];
    var spouse_field_index: ?usize = null;
    var activity_field_index: ?usize = null;
    for (definition.tax_form_profile.values, 0..) |value, index| {
        if (value.source_kind == .named_profile_role) {
            spouse_field_index = index;
        }
        if (value.source_kind == .business_activity_anchor and
            value.role == .filer and value.availability == .supported)
        {
            activity_field_index = index;
        }
    }
    const spouse_field = spouse_field_index.?;
    const activity_field = activity_field_index.?;

    // The generated spouse role accepts only individual/sole-proprietor
    // profiles and declares it distinct from the filer.
    try std.testing.expect(taxFormProfileChoiceContains(
        &model,
        spouse_field,
        "picker-individual",
    ));
    try std.testing.expect(taxFormProfileChoiceContains(
        &model,
        spouse_field,
        "picker-sole",
    ));
    for ([_][]const u8{
        "picker-filer",
        "picker-corporation",
        "picker-partnership",
        "picker-estate",
    }) |excluded| {
        try std.testing.expect(!taxFormProfileChoiceContains(
            &model,
            spouse_field,
            excluded,
        ));
    }

    // At the page's exact 2026-08-04 viewed date, only the confirmed active
    // v16 component is selectable. Expired, future, and review-required rows
    // remain in history but cannot be bound to an annual form profile.
    try std.testing.expect(taxFormProfileChoiceContains(
        &model,
        activity_field,
        "confirmed-activity",
    ));
    for ([_][]const u8{
        "expired-activity",
        "proposal-activity",
        "future-activity",
    }) |excluded| {
        try std.testing.expect(!taxFormProfileChoiceContains(
            &model,
            activity_field,
            excluded,
        ));
    }

    const obligation_field: usize = 97;
    loadTaxFormProfileObligationChoices(
        &model,
        obligation_field,
        try profile_model.ProfileId.parse("picker-filer"),
    );
    try std.testing.expect(taxFormProfileChoiceContains(
        &model,
        obligation_field,
        "confirmed-obligation",
    ));
    for ([_][]const u8{
        "expired-obligation",
        "proposal-obligation",
        "future-obligation",
    }) |excluded| {
        try std.testing.expect(!taxFormProfileChoiceContains(
            &model,
            obligation_field,
            excluded,
        ));
    }
}

test "2551Q Tax Form Profile stays no-setup while taxpayer-year revisions are isolated" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfileWithoutYearSettings(
        &store,
        "taxpayer-year-owner",
        "Taxpayer Year Owner",
        "741-852-963-000",
        .individual,
    );
    const activities = [_]profile_store.RegistrationActivityRevisionWrite{.{
        .anchor_id = "taxpayer-year-business",
        .metadata = .{
            .id = "taxpayer-year-business-r1",
            .expected_component_sequence = 0,
            .effective = .{ .from = "2026-01-01".* },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .line_of_business = "Professional services",
    }};
    const obligations = [_]profile_store.RegistrationObligationRevisionWrite{.{
        .anchor_id = "taxpayer-year-percentage-tax",
        .metadata = .{
            .id = "taxpayer-year-percentage-tax-r1",
            .expected_component_sequence = 0,
            .effective = .{ .from = "2026-01-01".* },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .kind = .percentage_tax,
    }};
    _ = try store.appendRegistrationCommit(.{
        .profile_id = "taxpayer-year-owner",
        .expected_current_sequence = 0,
        .activities = &activities,
        .obligations = &obligations,
    });

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    refreshSelectedProfileFormSet(&model);

    const index = formCatalogIndex("2551Q").?;
    update(&model, .{ .open_tax_form_profile = index });
    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expectEqual(
        tax_form_profile_ui.PageState.inherited_only,
        model.taxFormProfilePage.page().?,
    );
    try std.testing.expectError(
        error.SetupNotSupported,
        model.taxFormProfilePage.beginEdit(),
    );
    try std.testing.expect(model.taxpayerYearSettingsVisible());
    try std.testing.expectEqualStrings("Unresolved", model.taxpayerYearStatus());
    try std.testing.expectEqualStrings(
        "destructive",
        model.taxpayerYearStatusTone(),
    );
    try expectAppMarkupBuilds(&model);

    update(&model, .taxpayer_year_edit);
    try std.testing.expect(model.taxpayerYearEditing());
    try std.testing.expect(model.taxpayerYearSaveDisabled());
    update(&model, .taxpayer_year_rate_eight_percent);
    try std.testing.expect(!model.taxpayerYearSaveDisabled());
    update(&model, .taxpayer_year_save);
    try std.testing.expectEqualStrings("Ready", model.taxpayerYearStatus());
    try std.testing.expectEqualStrings(
        "primary",
        model.taxpayerYearStatusTone(),
    );
    try expectAppMarkupBuilds(&model);

    const profile_id = model.taxProfiles.selectedProfileDomainId().?;
    var history_2026 = try profile_persistence.loadAnnualIncomeTaxElectionHistory(
        &store,
        allocator,
        .{ .profile_id = profile_id, .tax_year = 2026 },
    );
    defer history_2026.deinit(allocator);
    const resolved = (try history_2026.history.current()).?;
    try std.testing.expectEqual(@as(u32, 1), resolved.sequence);
    try std.testing.expectEqual(
        annual_income_tax_election.State.candidate,
        resolved.state,
    );
    try std.testing.expectEqual(
        annual_income_tax_election.Choice.eight_percent,
        resolved.choice.?,
    );

    var history_2025 = try profile_persistence.loadAnnualIncomeTaxElectionHistory(
        &store,
        allocator,
        .{ .profile_id = profile_id, .tax_year = 2025 },
    );
    defer history_2025.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), history_2025.history.events.len);
}

test "2551Q runtime composition refreshes base and separates annual lifecycle" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    const raw_profile_id = "composed-runtime-2551q";
    try addTestProfileWithoutYearSettings(
        &store,
        raw_profile_id,
        "Composed Runtime Taxpayer",
        "741-852-963-000",
        .individual,
    );
    const profile_id = try profile_model.ProfileId.parse(raw_profile_id);

    // Highest effective sequence intentionally lacks the exact three 2551Q
    // inherited contact facts. The older complete revision must not mask it.
    var current = (try profile_persistence.loadCurrentRevision(
        &store,
        allocator,
        profile_id,
    )).?;
    defer current.deinit(allocator);
    var incomplete = current.revision;
    incomplete.id = try profile_model.RevisionId.parse(
        "composed-runtime-incomplete",
    );
    incomplete.sequence = 2;
    incomplete.contact.zip_code = null;
    incomplete.contact.contact_number = null;
    incomplete.contact.email_address = null;
    try profile_persistence.appendRevision(
        &store,
        allocator,
        &incomplete,
        1,
    );

    const activities = [_]profile_store.RegistrationActivityRevisionWrite{.{
        .anchor_id = "primary",
        .metadata = .{
            .id = "composed-runtime-primary-r1",
            .expected_component_sequence = 0,
            .effective = .{ .from = "2026-01-01".* },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .line_of_business = "Professional services",
    }};
    const obligations = [_]profile_store.RegistrationObligationRevisionWrite{.{
        .anchor_id = "composed-runtime-percentage-tax",
        .metadata = .{
            .id = "composed-runtime-percentage-tax-r1",
            .expected_component_sequence = 0,
            .effective = .{ .from = "2026-01-01".* },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .kind = .percentage_tax,
    }};
    _ = try store.appendRegistrationCommit(.{
        .profile_id = raw_profile_id,
        .expected_current_sequence = 0,
        .activities = &activities,
        .obligations = &obligations,
    });
    _ = try profile_persistence.stageAnnualIncomeTaxElectionCandidate(
        &store,
        .{
            .stream = .{ .profile_id = profile_id, .tax_year = 2026 },
            .expected_current_sequence = 0,
            .choice = .eight_percent,
            .commencement = .existing_before_tax_year,
            .provenance = .{
                .kind = .form_2551q,
                .form_revision = try annual_income_tax_election.FormRevision.parse(
                    "2018-01-ENCS",
                ),
                .filing_quarter = 1,
            },
            .occurred_at_unix_seconds = 2,
        },
    );

    var model = Model{};
    try model.taxProfiles.attach(allocator, &store, "2026-03-31", 2026);
    const definition = &form_catalog.forms[formCatalogIndex("2551Q").?];
    const q1: form_period.FilingPeriod = .{ .quarterly = .{
        .tax_year = 2026,
        .quarter = 1,
    } };
    const before = try loadRuntimeComposedSnapshot(
        &model,
        definition,
        profile_id,
        2026,
        q1,
        null,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        before.readiness.base_tax_profile.missingKeys().len,
    );
    try std.testing.expect(
        before.readiness.base_tax_profile.contains(.zip_code),
    );
    try std.testing.expect(
        before.readiness.base_tax_profile.contains(.contact_number),
    );
    try std.testing.expect(
        before.readiness.base_tax_profile.contains(.email_address),
    );
    try std.testing.expectEqual(
        composed_tax_profile.LayerStatus.ready,
        before.readiness.annual_income_tax_election.status,
    );

    var corrected = incomplete;
    corrected.id = try profile_model.RevisionId.parse(
        "composed-runtime-corrected",
    );
    corrected.sequence = 3;
    corrected.contact.zip_code = try profile_fields.ZipCode.parse("1100");
    corrected.contact.contact_number = try profile_fields.ContactNumber.parse(
        "09171234567",
    );
    corrected.contact.email_address = try profile_fields.EmailAddress.parse(
        "runtime@example.ph",
    );
    try profile_persistence.appendRevision(
        &store,
        allocator,
        &corrected,
        2,
    );
    const after = try loadRuntimeComposedSnapshot(
        &model,
        definition,
        profile_id,
        2026,
        q1,
        null,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        after.readiness.base_tax_profile.missingKeys().len,
    );
    try std.testing.expect(after.ready_for_new_filing);

    const q2: form_period.FilingPeriod = .{ .quarterly = .{
        .tax_year = 2026,
        .quarter = 2,
    } };
    const candidate_q2 = try loadRuntimeComposedSnapshot(
        &model,
        definition,
        profile_id,
        2026,
        q2,
        null,
    );
    try std.testing.expect(!candidate_q2.ready_for_new_filing);
    try std.testing.expectEqual(
        TaxFormProfileCardState.needs_year_settings,
        taxFormProfileCardStateFromComposed(definition, &candidate_q2),
    );

    _ = try profile_persistence.confirmAnnualIncomeTaxElectionEvidence(
        &store,
        .{
            .stream = .{ .profile_id = profile_id, .tax_year = 2026 },
            .expected_current_sequence = 1,
            .choice = .eight_percent,
            .initial_applicable_quarter = 1,
            .provenance = .{ .kind = .statutory_default },
            .occurred_at_unix_seconds = 3,
        },
    );
    const confirmed_q2 = try loadRuntimeComposedSnapshot(
        &model,
        definition,
        profile_id,
        2026,
        q2,
        null,
    );
    try std.testing.expectEqual(
        composed_tax_profile.LayerStatus.locked,
        confirmed_q2.readiness.annual_income_tax_election.status,
    );
    try std.testing.expect(confirmed_q2.ready_for_new_filing);
    try std.testing.expectEqual(
        TaxFormProfileCardState.inherited_only_ready,
        taxFormProfileCardStateFromComposed(definition, &confirmed_q2),
    );

    var reserved = confirmed_q2;
    reserved.readiness.annual_income_tax_election.status = .reserved;
    reserved.ready_for_new_filing = false;
    try std.testing.expectEqual(
        TaxFormProfileCardState.year_settings_reserved,
        taxFormProfileCardStateFromComposed(definition, &reserved),
    );
}

fn profileSlotNamed(model: *const Model, name: []const u8) ?usize {
    for (model.profileRows()) |row| {
        if (std.mem.eql(u8, row.nameLabel(), name)) return row.slot;
    }
    return null;
}

test "app calendar and filing action icons register for markup" {
    canvas.icons.registerAppIcons(&app_icons);
    try std.testing.expect(canvas.icons.resolve("app:calendar") != null);
    try std.testing.expect(canvas.icons.resolve("app:mail-check") != null);
    try std.testing.expect(canvas.icons.resolve("app:printer") != null);
    try std.testing.expect(canvas.icons.resolve("app:upload-receipt") != null);
}

test "tax-profile domain modules remain in the repository test root" {
    _ = @import("domain/date.zig");
    _ = @import("domain/money.zig");
    _ = @import("tax_profile/field.zig");
    _ = @import("tax_profile/model.zig");
    _ = @import("tax_profile/capability.zig");
    _ = @import("tax_profile/projection.zig");
    _ = @import("tax_profile/editor.zig");
    _ = @import("tax_profile/evolution.zig");
    _ = @import("tax_profile/persistence_adapter.zig");
    _ = @import("forms/id.zig");
    _ = @import("forms/spec.zig");
    _ = @import("forms/compose.zig");
    _ = @import("forms/lifecycle.zig");
    _ = @import("forms/form_2551q.zig");
    _ = @import("forms/form_1701q.zig");
    _ = @import("forms/runtime.zig");
    _ = @import("forms/catalog_projection.zig");
    _ = @import("forms/persistence_adapter.zig");
    _ = @import("forms/ui_state.zig");
    _ = @import("forms/income_tax_ui_state.zig");
    _ = @import("forms/percentage_tax_ui_state.zig");
    _ = @import("form_engine/root.zig");
    _ = @import("container_codec/legacy.zig");
    _ = @import("artifact_lab/session.zig");
}

test "theme preference overrides and restores the system scheme" {
    var model = Model{ .systemColorScheme = .dark };
    try std.testing.expect(model.darkThemeActive());

    update(&model, .set_theme_light);
    try std.testing.expect(model.lightThemeActive());

    update(&model, .set_theme_system);
    try std.testing.expect(model.darkThemeActive());
}

test "theme toggle changes the effective scheme" {
    var model = Model{};
    update(&model, .toggle_theme);
    try std.testing.expect(model.darkThemeActive());
    update(&model, .toggle_theme);
    try std.testing.expect(model.lightThemeActive());
}

test "sidebar derives full rail and floating modes from viewport width" {
    var model = Model{};
    try std.testing.expect(!model.sidebarExpandedVisible());
    try std.testing.expect(model.sidebarRailVisible());

    update(&model, .{ .viewport_width_changed = 1920 });
    try std.testing.expect(model.sidebarExpandedVisible());
    try std.testing.expect(!model.sidebarRailVisible());

    update(&model, .{ .viewport_class_changed = viewportClassForWidth(900) });
    try std.testing.expect(!model.sidebarExpandedVisible());
    try std.testing.expect(model.sidebarRailVisible());
    update(&model, .expand_sidebar);
    try std.testing.expect(model.sidebarOverlayVisible());
    update(&model, .close_sidebar_overlay);

    update(&model, .{ .viewport_class_changed = viewportClassForWidth(700) });
    try std.testing.expect(!model.sidebarRailVisible());
    try std.testing.expect(model.sidebarLauncherVisible());
    update(&model, .open_sidebar_overlay);
    try std.testing.expect(model.sidebarOverlayVisible());

    update(&model, .show_settings);
    try std.testing.expect(!model.sidebarOverlayVisible());
    try std.testing.expectEqual(Page.settings, model.page);
}

test "tax form library uses icon actions through narrow tablet widths" {
    var model = Model{};

    update(&model, .{ .viewport_width_changed = 408 });
    try std.testing.expect(model.profileFormsIconAction());

    update(&model, .{ .viewport_width_changed = 768 });
    try std.testing.expect(model.profileFormsIconAction());

    update(&model, .{ .viewport_width_changed = 900 });
    try std.testing.expect(!model.profileFormsIconAction());
}

test "tax form library grouped filters summarize and stay open while toggling" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};

    try std.testing.expectEqualStrings(
        "All active filings",
        model.profileFormsFilterSummaryLabel(),
    );
    try std.testing.expectEqualStrings(
        "All active filings",
        model.profileFormsFilterDisplayLabel(arena),
    );
    try std.testing.expectEqualStrings(
        "Filter active forms by cadence, month, or quarter",
        model.profileFormsFilterAccessibleLabel(arena),
    );
    try std.testing.expect(model.profileFormsAllMonthsSelected());
    try std.testing.expect(model.profileFormsAllQuartersSelected());

    update(&model, .profile_forms_toggle_filter_picker);
    try std.testing.expect(model.profileFormsFilterPickerOpen());

    update(&model, .{ .profile_forms_toggle_month = 1 });
    try std.testing.expect(model.profileFormsFilterPickerOpen());
    try std.testing.expect(model.profileFormsJanuarySelected());
    try std.testing.expect(model.profileFormsCadenceMonthlySelected());
    try std.testing.expect(!model.profileFormsCadenceQuarterlySelected());
    try std.testing.expect(!model.profileFormsAllMonthsSelected());
    try std.testing.expectEqualStrings(
        "Browse filters applied",
        model.profileFormsFilterSummaryLabel(),
    );
    try std.testing.expectEqualStrings(
        "Jan",
        model.profileFormsFilterDisplayLabel(arena),
    );

    update(&model, .profile_forms_toggle_quarter_2);
    try std.testing.expect(model.profileFormsJanuarySelected());
    try std.testing.expect(model.profileFormsQuarter2Selected());
    try std.testing.expect(model.profileFormsCadenceMonthlySelected());
    try std.testing.expect(model.profileFormsCadenceQuarterlySelected());
    try std.testing.expectEqualStrings(
        "Jan · Q2",
        model.profileFormsFilterDisplayLabel(arena),
    );

    update(&model, .profile_forms_toggle_cadence_monthly);
    try std.testing.expect(!model.profileFormsCadenceMonthlySelected());
    try std.testing.expect(!model.profileFormsJanuarySelected());

    update(&model, .profile_forms_close_filter_picker);
    try std.testing.expect(!model.profileFormsFilterPickerOpen());

    model.libraryFilter.on_demand_mask = 1;
    model.taxProfiles.applyFormsQuery(.{ .insert_text = "2551Q" });
    try std.testing.expectEqualStrings("2551Q", model.taxProfiles.formsQuery());
    update(&model, .profile_forms_reset_filters);
    try std.testing.expectEqualStrings(
        "All active filings",
        model.profileFormsFilterSummaryLabel(),
    );
    try std.testing.expect(!model.profileFormsJanuarySelected());
    try std.testing.expect(!model.profileFormsQuarter2Selected());
    try std.testing.expectEqual(@as(u64, 0), model.libraryFilter.on_demand_mask);
    try std.testing.expectEqualStrings("", model.taxProfiles.formsQuery());
}

test "tax form library last period selection never widens another cadence" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};

    update(&model, .{ .profile_forms_toggle_month = 1 });
    try std.testing.expect(model.profileFormsCadenceMonthlyLocked());
    update(&model, .{ .profile_forms_toggle_month = 1 });
    try std.testing.expect(model.profileFormsAllMonthsSelected());
    try std.testing.expectEqualStrings(
        "All months",
        model.profileFormsFilterDisplayLabel(arena),
    );

    update(&model, .{ .profile_forms_toggle_month = 1 });
    update(&model, .profile_forms_toggle_quarter_2);
    try std.testing.expect(!model.profileFormsCadenceMonthlyLocked());
    try std.testing.expect(!model.profileFormsCadenceQuarterlyLocked());
    update(&model, .{ .profile_forms_toggle_month = 1 });
    try std.testing.expect(!model.profileFormsCadenceMonthlySelected());
    try std.testing.expect(model.profileFormsCadenceQuarterlySelected());
    try std.testing.expect(model.profileFormsQuarter2Selected());
    try std.testing.expectEqualStrings(
        "Q2",
        model.profileFormsFilterDisplayLabel(arena),
    );

    update(&model, .profile_forms_toggle_quarter_2);
    try std.testing.expect(model.profileFormsAllQuartersSelected());
    try std.testing.expectEqualStrings(
        "All quarters",
        model.profileFormsFilterDisplayLabel(arena),
    );
}

test "tax form library period tiles keep a fixed cadence grid" {
    const quarterly = &form_catalog.forms[formCatalogIndex("2551Q").?];
    var model = Model{
        .viewportClass = .phone,
        .viewportWidth = 408,
    };
    try std.testing.expectEqual(
        @as(u8, 4),
        model.libraryPeriodGridColumns(quarterly),
    );
    model.libraryFilter.quarter_mask = 0b0011;
    try std.testing.expectEqual(
        @as(u8, 4),
        model.libraryPeriodGridColumns(quarterly),
    );
    model.libraryFilter.quarter_mask = 0;

    model.viewportClass = .desktop;
    model.viewportWidth = 1_320;
    try std.testing.expectEqual(
        @as(u8, 4),
        model.libraryPeriodGridColumns(quarterly),
    );

    model.viewportWidth = 1_800;
    try std.testing.expectEqual(
        @as(u8, 4),
        model.libraryPeriodGridColumns(quarterly),
    );

    model.viewportWidth = 2_400;
    try std.testing.expectEqual(
        @as(u8, 4),
        model.libraryPeriodGridColumns(quarterly),
    );

    model.libraryFilter.quarter_mask = 0b0001;
    try std.testing.expectEqual(
        @as(u8, 4),
        model.libraryPeriodGridColumns(quarterly),
    );

    const monthly = &form_catalog.forms[formCatalogIndex("1601C").?];
    model.viewportClass = .phone;
    model.libraryFilter.month_mask = 0b0000_0000_0000_0011;
    try std.testing.expectEqual(
        @as(u8, 4),
        model.libraryPeriodGridColumns(monthly),
    );
}

test "tax form library card columns follow desktop tablet phone density" {
    var model = Model{};
    model.viewportWidth = 1_440;
    try std.testing.expectEqual(@as(u8, 3), model.profileFormCardColumns());
    model.viewportWidth = 768;
    try std.testing.expectEqual(@as(u8, 1), model.profileFormCardColumns());
    model.viewportWidth = 408;
    try std.testing.expectEqual(@as(u8, 1), model.profileFormCardColumns());
}

test "tax form library progress counts filed lifecycle states only" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var row = TaxFormLibraryRow{
        .id = 0,
        .definition = &form_catalog.forms[formCatalogIndex("2551Q").?],
        .active = true,
        .selected = true,
        .launch_disabled = false,
    };
    row.setPeriodCell(0, .{ .status = "Draft" });
    row.setPeriodCell(1, .{ .status = "Sent" });
    row.setPeriodCell(2, .{ .status = "Confirmed" });
    row.setPeriodCell(3, .{ .status = "New" });
    row.period_cell_count = 4;
    try std.testing.expectEqualStrings(
        "2/4 filed",
        row.filingProgress(arena_state.allocator()),
    );
}

test "tax form library information uses a dismissible dialog at every width" {
    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
        .viewportWidth = 768,
    };
    const index = formCatalogIndex("2551Q").?;
    update(&model, .{ .profile_forms_show_info = index });
    try std.testing.expect(model.profileFormInfoDialogOpen());
    try std.testing.expectEqualStrings("2551Q", model.profileFormInfoCode());
    model.viewportWidth = 1_440;
    try std.testing.expect(model.profileFormInfoDialogOpen());
    try std.testing.expect(model.profileFormInfoDialogWidth() >= 480);
    model.viewportWidth = 408;
    try std.testing.expect(model.profileFormInfoDialogWidth() <= 408);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
    var ui = canvas.Ui(Msg).init(arena);
    const tree = try ui.finalize(try view.build(&ui, &model));
    const dialog = findWidgetByKind(tree.root, .dialog).?;
    update(&model, tree.msgForDismiss(dialog.id).?);
    try std.testing.expect(model.libraryFilter.info_index == null);
}

test "tax form library capability checkboxes partition the catalog" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};
    model.taxProfiles.managing_forms = true;
    model.taxProfiles.form_activity_filter = .all;

    update(&model, .profile_forms_toggle_filter_calendar_only);
    const editor_rows = model.profileManageFormRows(arena);
    try std.testing.expectEqual(form_catalog.editor_count, editor_rows.len);

    update(&model, .profile_forms_reset_filters);
    model.taxProfiles.form_activity_filter = .all;
    update(&model, .profile_forms_toggle_filter_editor);
    const calendar_rows = model.profileManageFormRows(arena);
    try std.testing.expectEqual(
        form_catalog.calendar_only_count,
        calendar_rows.len,
    );

    update(&model, .profile_forms_reset_filters);
    // Rows are ordered by the catalog enum, so income tax is at its index.
    const income_index = std.mem.indexOfScalar(
        form_catalog.TaxCategory,
        std.meta.tags(form_catalog.TaxCategory),
        .income_tax,
    ).?;
    update(&model, .{ .profile_forms_toggle_category = income_index });
    const income_rows = model.profileManageFormRows(arena);
    try std.testing.expect(income_rows.len > 0);
    for (income_rows) |*row| {
        try std.testing.expectEqual(
            form_catalog.TaxCategory.income_tax,
            row.definition.tax_category,
        );
    }
}

test "inactive manage rows retain Tax Form Profile history without setup access" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{};
    model.taxProfiles.managing_forms = true;
    model.taxProfiles.form_activity_filter = .all;
    const index = formCatalogIndex("2551Q").?;
    model.taxFormProfileHistoryAvailable[index] = true;

    const rows = model.profileManageFormRows(arena);
    var matched = false;
    for (rows) |row| {
        if (row.id != index) continue;
        matched = true;
        try std.testing.expect(!row.active);
        try std.testing.expectEqualStrings(
            "Saved Tax Form Profile history retained",
            row.tax_form_profile_status,
        );
        try std.testing.expectEqualStrings("", row.tax_form_profile_action);
        try std.testing.expect(!row.tax_form_profile_action_visible);
        try std.testing.expect(row.tax_form_profile_action_disabled);
    }
    try std.testing.expect(matched);
}

test "tax form library cadence and period filters are immediate and bounded" {
    var model = Model{};
    try std.testing.expect(model.profileFormsCadenceMonthlySelected());
    try std.testing.expect(model.profileFormsCadenceQuarterlySelected());
    try std.testing.expectEqualStrings(
        "All filing periods",
        model.profileFormsPeriodFilterLabel(),
    );

    update(&model, .profile_forms_toggle_cadence_monthly);
    try std.testing.expect(!model.profileFormsCadenceMonthlySelected());
    try std.testing.expect(model.profileFormsCadenceQuarterlySelected());

    update(&model, .profile_forms_period_march);
    switch (model.libraryFilter.period_filter) {
        .monthly => |month| try std.testing.expectEqual(@as(u8, 3), month),
        else => try std.testing.expect(false),
    }
    try std.testing.expectEqualStrings(
        "March",
        model.profileFormsPeriodFilterLabel(),
    );

    update(&model, .profile_forms_reset_filters);
    try std.testing.expectEqualStrings(
        "All filing periods",
        model.profileFormsPeriodFilterLabel(),
    );
}

test "catalog cadence projects canonical monthly quarterly annual and on-demand slots" {
    const year: u16 = 2026;
    const monthly = &form_catalog.forms[formCatalogIndex("1601C").?];
    try std.testing.expectEqual(@as(?u8, 1), libraryPeriodForSlot(monthly, year, 0).?.month());
    try std.testing.expectEqual(@as(?u8, 12), libraryPeriodForSlot(monthly, year, 11).?.month());
    try std.testing.expect(libraryPeriodForSlot(monthly, year, 12) == null);

    const quarterly = &form_catalog.forms[formCatalogIndex("1701Q").?];
    try std.testing.expectEqual(@as(?u8, 3), libraryPeriodForSlot(quarterly, year, 2).?.quarter());
    try std.testing.expect(libraryPeriodForSlot(quarterly, year, 3) == null);

    const annual = &form_catalog.forms[formCatalogIndex("1701").?];
    try std.testing.expectEqual(
        form_catalog.FilingCadence.annual,
        libraryPeriodForSlot(annual, year, 0).?.cadence(),
    );
    try std.testing.expect(libraryPeriodForSlot(annual, year, 1) == null);

    const on_demand = &form_catalog.forms[formCatalogIndex("0605").?];
    try std.testing.expectEqual(
        form_catalog.FilingCadence.on_demand,
        libraryPeriodForSlot(on_demand, year, 0).?.cadence(),
    );
}

test "month and quarter filters project only selected filing buttons" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const assessments = [_]form_ui.LaunchAssessment{
        .{ .status = .ready_new },
    } ** 12;
    const assessments_ready = [_]bool{true} ** 12;
    const availability = [_]bool{true} ** 12;
    const availability_ready = [_]bool{true} ** 12;

    var monthly = TaxFormLibraryRow{
        .id = formCatalogIndex("1601C").?,
        .definition = &form_catalog.forms[formCatalogIndex("1601C").?],
        .active = true,
        .selected = true,
        .launch_disabled = false,
    };
    populateLibraryPeriodCells(
        &monthly,
        &.{},
        false,
        "1601C",
        2026,
        arena,
        0b0000_0000_0000_0101,
        0,
        assessments,
        assessments_ready,
        availability,
        availability_ready,
    );
    var visible_months: usize = 0;
    for (monthly.periodCells()) |cell| {
        if (cell.visible) visible_months += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), visible_months);
    try std.testing.expect(monthly.period1.visible);
    try std.testing.expect(!monthly.period2.visible);
    try std.testing.expect(monthly.period3.visible);

    var quarterly = TaxFormLibraryRow{
        .id = formCatalogIndex("2551Q").?,
        .definition = &form_catalog.forms[formCatalogIndex("2551Q").?],
        .active = true,
        .selected = true,
        .launch_disabled = false,
    };
    populateLibraryPeriodCells(
        &quarterly,
        &.{},
        false,
        "2551Q",
        2026,
        arena,
        0,
        0b0011,
        assessments,
        assessments_ready,
        availability,
        availability_ready,
    );
    var visible_quarters: usize = 0;
    for (quarterly.periodCells()) |cell| {
        if (cell.visible) visible_quarters += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), visible_quarters);
    try std.testing.expect(quarterly.period1.visible);
    try std.testing.expect(quarterly.period2.visible);
    try std.testing.expect(!quarterly.period3.visible);
}

test "on-demand cards expose start-new and saved occurrence actions" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var drafts = [_]profile_ui.DraftSummaryRow{
        .{ .slot = 0 },
        .{ .slot = 1 },
    };
    try drafts[0].form_code.set("0605");
    try drafts[0].period_key.set("2026-O001");
    try drafts[0].lifecycle.set("editing");
    try drafts[1].form_code.set("0605");
    try drafts[1].period_key.set("2026-O002");
    try drafts[1].lifecycle.set("submitted");

    var assessments = [_]form_ui.LaunchAssessment{
        .{ .status = .ready_resume },
    } ** 12;
    assessments[0].status = .ready_new;
    const assessments_ready = [_]bool{true} ** 12;
    const availability = [_]bool{true} ** 12;
    const availability_ready = [_]bool{true} ** 12;
    var row = TaxFormLibraryRow{
        .id = formCatalogIndex("0605").?,
        .definition = &form_catalog.forms[formCatalogIndex("0605").?],
        .active = true,
        .selected = true,
        .launch_disabled = false,
        .period_grid_columns = 1,
    };
    populateLibraryPeriodCells(
        &row,
        &drafts,
        false,
        "0605",
        2026,
        arena,
        0,
        0,
        assessments,
        assessments_ready,
        availability,
        availability_ready,
    );
    try std.testing.expectEqual(@as(usize, 3), row.periodCells().len);
    try std.testing.expectEqualStrings("Start new return", row.period1.label);
    try std.testing.expectEqualStrings("New", row.period1.status);
    try std.testing.expectEqualStrings("Saved return O001", row.period2.label);
    try std.testing.expectEqualStrings("Draft", row.period2.status);
    try std.testing.expectEqualStrings("Saved return O002", row.period3.label);
    try std.testing.expectEqualStrings("Sent", row.period3.status);
}

test "tax form library composes status type and search over staged forms" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "11111111111111111111111111111111",
        "Juan Dela Cruz",
        "123-456-789-000",
        .individual,
    );
    var model = Model{};
    model.calendar.selected_year = 2026;
    try model.taxProfiles.attach(allocator, &store, "2026-08-02", 2026);
    const profile_id = model.taxProfiles.selectedProfileId().?;
    try store.replaceFormSet(profile_id, 2026, &.{
        .{ .form_code = "2551Q", .form_revision = "2018-01-ENCS" },
        .{ .form_code = "1905", .form_revision = "calendar-only" },
    });
    try std.testing.expect(model.taxProfiles.loadFormsForYear(2026));
    refreshSelectedProfileFormSet(&model);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try std.testing.expectEqual(@as(usize, 2), model.profileFormRows(arena).len);
    const initial_rows = model.profileFormRows(arena);
    var initial_quarterly: ?*const TaxFormLibraryRow = null;
    for (initial_rows) |*row| {
        if (std.mem.eql(u8, row.code(), "2551Q")) initial_quarterly = row;
    }
    try std.testing.expect(initial_quarterly != null);
    try std.testing.expectEqual(@as(usize, 4), initial_quarterly.?.periodCells().len);
    try std.testing.expectEqualStrings("Q1 New", initial_quarterly.?.periodSummary()[0..6]);

    // Capability filters belong to Manage mode and cannot hide active filing
    // cards while the user is browsing exact periods.
    update(&model, .profile_forms_toggle_filter_calendar_only);
    try std.testing.expectEqual(@as(usize, 2), model.profileFormRows(arena).len);

    update(&model, .profile_forms_reset_filters);
    update(&model, .{
        .profile_forms_search_input = .{ .insert_text = "2551q" },
    });
    const search_rows = model.profileFormRows(arena);
    try std.testing.expectEqual(@as(usize, 1), search_rows.len);
    try std.testing.expectEqualStrings("2551Q", search_rows[0].code());

    update(&model, .{ .profile_forms_search_input = .clear });
    update(&model, .{
        .profile_forms_search_input = .{
            .insert_text = "Quarterly Percentage Tax Return",
        },
    });
    const title_rows = model.profileFormRows(arena);
    try std.testing.expectEqual(@as(usize, 1), title_rows.len);
    try std.testing.expectEqualStrings("2551Q", title_rows[0].code());

    update(&model, .{ .profile_forms_search_input = .clear });
    update(&model, .{
        .profile_forms_search_input = .{ .insert_text = "Percentage tax" },
    });
    const category_rows = model.profileFormRows(arena);
    try std.testing.expectEqual(@as(usize, 1), category_rows.len);
    try std.testing.expectEqualStrings("2551Q", category_rows[0].code());

    update(&model, .profile_forms_reset_filters);
    update(&model, .{ .profile_forms_search_input = .clear });
    update(&model, .profile_forms_period_quarter_two);
    const quarter_rows = model.profileFormRows(arena);
    try std.testing.expectEqual(@as(usize, 1), quarter_rows.len);
    try std.testing.expectEqualStrings("2551Q", quarter_rows[0].code());
    try std.testing.expectEqualStrings("Quarter 2", model.profileFormsPeriodFilterLabel());

    update(&model, .profile_forms_period_all);
    model.page = .profile_setup;
    update(&model, .show_profile_tax_forms);
    update(&model, .{ .profile_setup_select_year = 2026 });
    resetProfileFormsPage(&model);
    try std.testing.expect(!model.taxProfiles.managing_forms);
    try std.testing.expectEqual(@as(usize, 2), model.profileFormRows(arena).len);

    update(&model, .profile_forms_manage);
    try std.testing.expect(model.taxProfiles.managing_forms);
    // A clean manager cannot Save, but Cancel is its explicit exit back to
    // Browse and must never be disabled.
    try std.testing.expect(model.profileSetupPrimaryDisabled());
    try std.testing.expect(!model.profileFormsCancelDisabled());
    try std.testing.expectEqual(
        form_catalog.registry_count,
        model.profileFormRows(arena).len,
    );

    update(&model, .profile_forms_toggle_filter_inactive);
    try std.testing.expectEqual(@as(usize, 2), model.profileFormRows(arena).len);

    var editor_index: ?usize = null;
    for (form_catalog.forms, 0..) |form, index| {
        if (std.mem.eql(u8, form.code, "2551Q")) {
            editor_index = index;
            break;
        }
    }
    update(&model, .{ .toggle_profile_form = editor_index.? });
    const staged_rows = model.profileFormRows(arena);
    try std.testing.expectEqual(@as(usize, 1), staged_rows.len);
    try std.testing.expectEqualStrings("1905", staged_rows[0].code());

    // Sidebar context creation must not clear a dirty staged Forms Set.
    update(&model, .new_taxpayer_profile);
    try std.testing.expectEqualStrings(
        "11111111111111111111111111111111",
        model.taxProfiles.selectedProfileId().?,
    );
    try std.testing.expect(model.taxProfiles.managing_forms);
    try std.testing.expect(model.taxProfiles.formsDirty());
    update(&model, .add_branch_profile);
    try std.testing.expectEqualStrings(
        "11111111111111111111111111111111",
        model.taxProfiles.selectedProfileId().?,
    );
    try std.testing.expect(model.taxProfiles.managing_forms);
    try std.testing.expect(model.taxProfiles.formsDirty());

    // Cancel reverts the staged change and visibly returns to browse mode on
    // the same year with the persisted membership restored.
    update(&model, .profile_forms_cancel);
    try std.testing.expect(!model.taxProfiles.managing_forms);
    try std.testing.expect(!model.taxProfiles.formsDirty());
    try std.testing.expectEqual(
        @as(usize, 2),
        model.taxProfiles.activeFormCount(),
    );
    try std.testing.expectEqual(@as(usize, 2), model.profileFormRows(arena).len);
}

test "tax form filter picker closes when its dashboard context changes" {
    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };

    update(&model, .profile_forms_toggle_filter_picker);
    try std.testing.expect(model.profileFormsFilterPickerOpen());

    update(&model, .show_dashboard_calendar);
    try std.testing.expect(!model.profileFormsFilterPickerOpen());

    update(&model, .show_dashboard_forms);
    update(&model, .profile_forms_toggle_filter_picker);
    try std.testing.expect(model.profileFormsFilterPickerOpen());
    update(&model, .{ .profile_forms_toggle_month = 1 });
    try std.testing.expectEqualStrings(
        "Browse filters applied",
        model.profileFormsFilterSummaryLabel(),
    );

    navigate(&model, .settings);
    try std.testing.expect(!model.profileFormsFilterPickerOpen());
    try std.testing.expectEqualStrings(
        "All active filings",
        model.profileFormsFilterSummaryLabel(),
    );

    navigate(&model, .taxpayer_dashboard);
    update(&model, .profile_forms_toggle_filter_picker);
    try std.testing.expect(model.profileFormsFilterPickerOpen());
    update(&model, .{ .viewport_width_changed = 408 });
    try std.testing.expect(!model.profileFormsFilterPickerOpen());
}

test "sidebar can be collapsed hidden and restored without losing its route" {
    var model = Model{
        .page = .tax_calendar,
        .viewportClass = .desktop,
        .viewportWidth = 1920,
    };
    update(&model, .collapse_sidebar);
    try std.testing.expect(model.sidebarRailVisible());

    update(&model, .hide_sidebar);
    try std.testing.expect(!model.sidebarExpandedVisible());
    try std.testing.expect(!model.sidebarRailVisible());
    try std.testing.expect(model.sidebarLauncherVisible());

    update(&model, .toggle_navigation);
    try std.testing.expect(model.sidebarExpandedVisible());
    try std.testing.expectEqual(Page.tax_calendar, model.page);
}

test "taxpayer selection and local page tabs are model owned" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    var calendar_store = try calendar_ui.persistence.Store.openMemory(allocator);
    defer calendar_store.close();
    try addThreeTestProfiles(&store);

    var model = Model{};
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);
    try std.testing.expectEqual(@as(usize, 3), model.profileRows().len);

    const partnership_slot = profileSlotNamed(
        &model,
        "Sample Partnership",
    ).?;
    update(&model, .{ .select_taxpayer = partnership_slot });
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expectEqualStrings(
        "Sample Partnership",
        model.selectedTaxpayerName(),
    );
    try std.testing.expect(model.profileRows()[partnership_slot].active);

    update(&model, .show_dashboard_forms);
    try std.testing.expect(model.dashboardFormsActive());
    update(&model, .show_dashboard_calendar);
    try std.testing.expect(model.dashboardCalendarActive());

    update(&model, .show_profile_setup);
    try std.testing.expect(!model.taxProfiles.editing_new);
    update(&model, .show_profile_email);
    try std.testing.expect(model.profileEmailActive());

    update(&model, .show_screen_gallery);
    try std.testing.expectEqualStrings(
        "Sample Partnership",
        model.selectedTaxpayerName(),
    );
}

test "calendar export is bound to the selected tax profile context" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    try addThreeTestProfiles(&store);

    var model = Model{};
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-profile-export-test.ics",
        "20260729T010203Z",
        2026,
        7,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-profile-export-test.ics",
        "20260729T010203Z",
        2026,
        7,
    );
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);
    refreshSelectedProfileFormSet(&model);
    update(&model, .profile_calendar_export);
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.wrong_context,
        model.profileCalendarExportStatus,
    );

    model.page = .taxpayer_dashboard;
    const exported_revision = model.taxProfiles.selectedRevisionContext().?;
    update(&model, .profile_calendar_export);
    try std.testing.expect(
        exported_revision.eql(&model.calendarExportProfileRevision.?),
    );
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.unavailable,
        model.profileCalendarExportStatus,
    );
    try std.testing.expect(model.profileCalendarExportNoticeVisible());

    try store.replaceFormSet(
        model.taxProfiles.selectedProfileId().?,
        2026,
        &.{},
    );
    try store.replaceFormSet(
        model.taxProfiles.selectedProfileId().?,
        2025,
        &.{},
    );
    refreshSelectedProfileFormSet(&model);
    update(&model, .profile_calendar_export);
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.nothing_to_add,
        model.profileCalendarExportStatus,
    );
    try std.testing.expectEqualStrings(
        "Nothing to add. This profile's Forms Set has no calendar deadline for this tax year.",
        model.profileCalendarExportNotice(),
    );

    update(&model, .{
        .select_taxpayer = profileSlotNamed(&model, "Juan Dela Cruz").?,
    });
    try std.testing.expect(!model.profileCalendarExportNoticeVisible());
}

test "profile ICS uses current and prior taxable-year Forms Sets" {
    const allocator = std.testing.allocator;
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    var profile_fixture = try profile_store.Store.openMemory(allocator);
    defer profile_fixture.close();

    const profile_id = "ics-two-year-profile";
    try addTestProfile(
        &profile_fixture,
        profile_id,
        "Two Year Calendar",
        "321-654-987-000",
        .individual,
    );
    try profile_fixture.replaceFormSet(profile_id, 2026, &.{.{
        .form_code = "1701Q",
        .form_revision = "2018-01-ENCS",
    }});
    try profile_fixture.replaceFormSet(profile_id, 2025, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});

    var model = Model{};
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-two-year-export-test.ics",
        "20260729T010203Z",
        2026,
        1,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-two-year-export-test.ics",
        "20260729T010203Z",
        2026,
        1,
    );
    try model.taxProfiles.attach(
        allocator,
        &profile_fixture,
        "2026-01-10",
        2026,
    );
    refreshSelectedProfileFormSet(&model);

    // Exercise the same filter and scope the export effect uses, so this test
    // cannot pass against a path production does not take.
    const export_calendar = model.profileCalendarForExport();
    var scope_arena = std.heap.ArenaAllocator.init(allocator);
    defer scope_arena.deinit();
    const bytes = try export_calendar.buildProfileIcs(
        allocator,
        "20260729T010203Z",
        .{
            .key = model.selectedTaxpayerCalendarKey(),
            .name = model.selectedTaxpayerName(),
            .form_scope = model.profileExportFormScope(scope_arena.allocator()),
        },
    );
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "X-EBIRFORMS-OBLIGATION-KEY:2025:2551Q:q4",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "X-EBIRFORMS-OBLIGATION-KEY:2026:1701Q:q1",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "X-EBIRFORMS-OBLIGATION-KEY:2026:2551Q:q1",
    ) == null);
}

test "profile ICS date-aware projection excludes unregistered forms" {
    const allocator = std.testing.allocator;
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    var profile_fixture = try profile_store.Store.openMemory(allocator);
    defer profile_fixture.close();

    const profile_id = "ics-scope-barrier-profile";
    try addTestProfile(
        &profile_fixture,
        profile_id,
        "Scope Barrier",
        "321-654-987-000",
        .individual,
    );
    try profile_fixture.replaceFormSet(profile_id, 2026, &.{.{
        .form_code = "1701Q",
        .form_revision = "2018-01-ENCS",
    }});
    try profile_fixture.replaceFormSet(profile_id, 2025, &.{.{
        .form_code = "1701Q",
        .form_revision = "2018-01-ENCS",
    }});

    var model = Model{};
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-scope-barrier-test.ics",
        "20260729T010203Z",
        2026,
        1,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-scope-barrier-test.ics",
        "20260729T010203Z",
        2026,
        1,
    );
    try model.taxProfiles.attach(
        allocator,
        &profile_fixture,
        "2026-01-10",
        2026,
    );
    refreshSelectedProfileFormSet(&model);

    // Precondition: the unfiltered projection really does carry the
    // unregistered form, so the assertion below cannot pass vacuously.
    var unregistered_present = false;
    for (
        model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count],
    ) |*row| {
        if (std.mem.eql(u8, row.form_code, "2550Q")) unregistered_present = true;
    }
    try std.testing.expect(unregistered_present);

    var scope_arena = std.heap.ArenaAllocator.init(allocator);
    defer scope_arena.deinit();
    const filtered = model.profileCalendarForExport();
    const bytes = try filtered.buildProfileIcs(
        allocator,
        "20260729T010203Z",
        .{
            .key = model.selectedTaxpayerCalendarKey(),
            .name = model.selectedTaxpayerName(),
            .form_scope = model.profileExportFormScope(scope_arena.allocator()),
        },
    );
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "1701Q") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "2550Q") == null);
}

test "profile export projection spans current and prior taxable years" {
    // A January obligation belongs to the prior taxable year. The filtered
    // projection must retain each deadline while resolving it against its own
    // filing period instead of flattening both years into one code list.
    const allocator = std.testing.allocator;
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    var profile_fixture = try profile_store.Store.openMemory(allocator);
    defer profile_fixture.close();

    const profile_id = "ics-partial-year-profile";
    try addTestProfile(
        &profile_fixture,
        profile_id,
        "Partial Year",
        "321-654-987-000",
        .individual,
    );
    // Disjoint sets, so each year's contribution is individually visible.
    try profile_fixture.replaceFormSet(profile_id, 2026, &.{.{
        .form_code = "1701Q",
        .form_revision = "2018-01-ENCS",
    }});
    try profile_fixture.replaceFormSet(profile_id, 2025, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});

    var model = Model{};
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-partial-year-test.ics",
        "20260729T010203Z",
        2026,
        1,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-partial-year-test.ics",
        "20260729T010203Z",
        2026,
        1,
    );
    try model.taxProfiles.attach(
        allocator,
        &profile_fixture,
        "2026-01-10",
        2026,
    );
    refreshSelectedProfileFormSet(&model);

    var scope_arena = std.heap.ArenaAllocator.init(allocator);
    defer scope_arena.deinit();
    switch (model.profileExportFormScope(scope_arena.allocator())) {
        .catalog_fallback => {},
        .registered => return error.TestUnexpectedResult,
    }
    const filtered = model.profileCalendarForExport();
    var has_current = false;
    var has_prior = false;
    for (filtered.deadlines[0..filtered.deadline_count]) |deadline| {
        if (deadline.period.taxableYear() == 2026 and
            formCodesEquivalent(deadline.form_code, "1701Q"))
        {
            has_current = true;
        }
        if (deadline.period.taxableYear() == 2025 and
            formCodesEquivalent(deadline.form_code, "2551Q"))
        {
            has_prior = true;
        }
    }
    try std.testing.expect(has_current);
    try std.testing.expect(has_prior);
}

test "profile export projection is authoritative-empty for an empty Forms Set" {
    const allocator = std.testing.allocator;
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    var profile_fixture = try profile_store.Store.openMemory(allocator);
    defer profile_fixture.close();

    const profile_id = "ics-empty-set-profile";
    try addTestProfile(
        &profile_fixture,
        profile_id,
        "Empty Forms Set",
        "321-654-987-000",
        .individual,
    );
    try profile_fixture.replaceFormSet(profile_id, 2026, &.{});
    try profile_fixture.replaceFormSet(profile_id, 2025, &.{});

    var model = Model{};
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-empty-set-test.ics",
        "20260729T010203Z",
        2026,
        1,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-empty-set-test.ics",
        "20260729T010203Z",
        2026,
        1,
    );
    try model.taxProfiles.attach(
        allocator,
        &profile_fixture,
        "2026-01-10",
        2026,
    );
    refreshSelectedProfileFormSet(&model);

    var scope_arena = std.heap.ArenaAllocator.init(allocator);
    defer scope_arena.deinit();
    const scope = model.profileExportFormScope(scope_arena.allocator());
    switch (scope) {
        .catalog_fallback => {},
        .registered => return error.TestUnexpectedResult,
    }
    const filtered = model.profileCalendarForExport();
    try std.testing.expectEqual(@as(usize, 0), filtered.deadline_count);

    try std.testing.expectError(
        error.NoCalendarEvents,
        filtered.buildProfileIcs(
            allocator,
            "20260729T010203Z",
            .{
                .key = model.selectedTaxpayerCalendarKey(),
                .name = model.selectedTaxpayerName(),
                .form_scope = scope,
            },
        ),
    );
}

test "profile calendar export remains correlated while preferences change" {
    var model = Model{
        .profileCalendarExportStatus = .writing,
    };

    update(&model, .multi_select_clear_all);
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.writing,
        model.profileCalendarExportStatus,
    );

    profileCalendarExportWritten(
        &model,
        .{ .key = calendar_export_file_key + 1, .op = .write },
        null,
    );
    profileCalendarExportOpened(
        &model,
        .{ .key = calendar_open_file_key, .code = 0 },
    );
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.writing,
        model.profileCalendarExportStatus,
    );

    profileCalendarExportWritten(
        &model,
        .{
            .key = calendar_export_file_key,
            .op = .write,
            .outcome = .io_failed,
        },
        null,
    );
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.write_failed,
        model.profileCalendarExportStatus,
    );

    model.profileCalendarExportStatus = .opening;
    profileCalendarExportOpened(
        &model,
        .{ .key = calendar_open_file_key + 1, .code = 0 },
    );
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.opening,
        model.profileCalendarExportStatus,
    );
    profileCalendarExportOpened(
        &model,
        .{ .key = calendar_open_file_key, .code = 0 },
    );
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.opened,
        model.profileCalendarExportStatus,
    );
}

test "persisted tax profiles have unique opaque calendar identities" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addThreeTestProfiles(&store);

    var model = Model{};
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);
    const rows = model.profileRows();
    const corporation_key = rows[0].idLabel();
    const juan_key = rows[1].idLabel();
    const partnership_key = rows[2].idLabel();

    try std.testing.expect(!std.mem.eql(u8, juan_key, corporation_key));
    try std.testing.expect(!std.mem.eql(u8, juan_key, partnership_key));
    try std.testing.expect(!std.mem.eql(u8, corporation_key, partnership_key));
    try std.testing.expect(std.mem.indexOf(u8, juan_key, "000-000") == null);
    try std.testing.expect(std.mem.indexOf(u8, corporation_key, "Demo") == null);
    try std.testing.expect(std.mem.indexOf(u8, partnership_key, "Partnership") == null);
}

test "Forms Set explicit empty disables editors while fallback enables them" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "11111111111111111111111111111111",
        "Juan Dela Cruz",
        "123-456-789-000",
        .individual,
    );
    var model = Model{};
    model.calendar.selected_year = 2026;
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);
    const profile_id = model.taxProfiles.selectedProfileId().?;

    try store.replaceFormSet(profile_id, 2026, &.{});
    refreshSelectedProfileFormSet(&model);
    try std.testing.expect(model.profileBrowseActiveEmpty());
    try std.testing.expect(model.taxpayerForm0605Disabled());
    try std.testing.expect(model.taxpayerForm1701QDisabled());
    try std.testing.expect(model.taxpayerForm2551QDisabled());
    model.page = .taxpayer_dashboard;
    update(&model, .show_form_2551q);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);

    model.calendar.selected_year = 2027;
    refreshSelectedProfileFormSet(&model);
    try std.testing.expect(!model.profileBrowseActiveEmpty());
    try std.testing.expect(!model.taxpayerForm0605Disabled());
    try std.testing.expect(!model.taxpayerForm1701QDisabled());
    try std.testing.expect(!model.taxpayerForm2551QDisabled());

    try store.replaceFormSet(profile_id, 2027, &.{
        .{
            .form_code = "2551Q",
            .form_revision = "2018-01-ENCS",
        },
    });
    refreshSelectedProfileFormSet(&model);
    try std.testing.expect(model.taxpayerForm0605Disabled());
    try std.testing.expect(model.taxpayerForm1701QDisabled());
    try std.testing.expect(!model.taxpayerForm2551QDisabled());
}

test "library launch assessment routes incomplete profile to completion" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    try addTestProfile(
        &store,
        "11111111111111111111111111111111",
        "Juan Dela Cruz",
        "123-456-789-000",
        .individual,
    );
    try addTestCompleteBusinessRegistration(
        &store,
        "11111111111111111111111111111111",
        "2026-01-01".*,
    );

    var model = Model{};
    model.calendar.selected_year = 2026;
    model.calendar.selected_month = 3;
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-incomplete-profile-calendar-test.ics",
        "20260301T010203Z",
        2026,
        3,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-incomplete-profile-calendar-test.ics",
        "20260301T010203Z",
        2026,
        3,
    );
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();

    const profile_id = model.taxProfiles.selectedProfileDomainId().?;
    try store.replaceFormSet(profile_id.asSlice(), 2026, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});
    model.taxProfiles.editSelected();
    model.taxProfiles.phone.clear();
    model.taxProfiles.email.clear();
    try std.testing.expect(model.taxProfiles.save());
    refreshSelectedProfileFormSet(&model);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const rows = model.profileFormRows(arena.allocator());
    var found = false;
    var action_id: ?usize = null;
    for (rows) |*row| {
        if (!std.mem.eql(u8, row.code(), "2551Q")) continue;
        found = true;
        try std.testing.expectEqual(
            form_ui.LaunchStatus.needs_profile,
            row.launch_assessment.status,
        );
        try std.testing.expectEqualStrings("Complete profile", row.launchLabel());
        try std.testing.expect(!row.launchDisabled());
        try std.testing.expectEqualStrings("New", row.period1.status);
        try std.testing.expectEqualStrings("outline", row.period1.tone);
        try std.testing.expect(
            std.mem.indexOf(u8, row.period1.accessibleLabel(), "complete profile") != null,
        );
        action_id = row.period1.actionId();
    }
    try std.testing.expect(found);

    var calendar_action_found = false;
    for (
        model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count],
    ) |deadline| {
        if (!formCodesEquivalent(deadline.form_code, "2551Q")) continue;
        const projected = model.profileCalendarDeadlineRow(deadline);
        try std.testing.expectEqual(
            ProfileDeadlineAction.complete_profile,
            projected.actions.at(0),
        );
        try std.testing.expectEqualStrings(
            "Complete Profile",
            projected.primaryActionLabel(),
        );
        try std.testing.expectEqualStrings("edit", projected.primaryActionIcon());
        calendar_action_found = true;
        break;
    }
    try std.testing.expect(calendar_action_found);

    update(&model, .{ .open_library_period = action_id.? });
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expectEqual(
        profile_fields.ReusableField.contact_number,
        model.profileCompletionTarget.?,
    );
    try std.testing.expect(model.pendingProfileFormLaunch != null);

    model.taxProfiles.phone.set("+63 917 123 4567");
    model.taxProfiles.email.set("juan@example.test");
    update(&model, .save_profile);
    try std.testing.expectEqual(Page.form_2551q, model.page);
    try std.testing.expect(model.profileCompletionTarget == null);
    try std.testing.expect(model.pendingProfileFormLaunch == null);
}

test "library period tile opens the exact quarterly filing identity" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "11111111111111111111111111111111",
        "Juan Dela Cruz",
        "123-456-789-000",
        .individual,
    );
    try addTestCompleteBusinessRegistration(
        &store,
        "11111111111111111111111111111111",
        "2026-01-01".*,
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendar.selected_year = 2026;
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    const profile_id = model.taxProfiles.selectedProfileDomainId().?;
    try store.replaceFormSet(profile_id.asSlice(), 2026, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});
    refreshSelectedProfileFormSet(&model);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const rows = model.profileFormRows(arena_state.allocator());
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqualStrings("2551Q", rows[0].code());
    try std.testing.expectEqual(@as(usize, 4), rows[0].periodCells().len);
    try std.testing.expectEqualStrings("Q2", rows[0].period2.label);

    // A global month/filter context cannot rewrite this tile's exact Q2
    // identity: the action payload is derived from the tile itself.
    model.calendar.selected_month = 1;
    update(&model, .{ .open_library_period = rows[0].period2.actionId() });
    try std.testing.expectEqual(Page.form_2551q, model.page);
    const filing = model.formProfiles.filingPeriod().?;
    try std.testing.expectEqual(form_catalog.FilingCadence.quarterly, filing.cadence());
    try std.testing.expectEqual(@as(?u8, 2), filing.quarter());
    try std.testing.expectEqual(@as(u16, 2026), filing.taxYear());
}

test "2551Q setup diversion preserves the clicked quarterly filing context" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "2551q-context-diversion-owner",
        "Context Diversion Taxpayer",
        "852-741-963-000",
        .individual,
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendar.selected_year = 2026;
    model.calendar.selected_month = 1;
    try model.taxProfiles.attach(allocator, &store, "2026-01-15", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    const profile_id = model.taxProfiles.selectedProfileDomainId().?;
    try store.replaceFormSet(profile_id.asSlice(), 2026, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});
    refreshSelectedProfileFormSet(&model);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const rows = model.profileFormRows(arena);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    update(&model, .{ .open_library_period = rows[0].period2.actionId() });

    try std.testing.expectEqual(Page.tax_form_profile, model.page);
    try std.testing.expect(model.taxFormProfileRegistrationRepairVisible());
    try std.testing.expectEqualStrings(
        "Q2",
        model.taxFormProfileQuarterLabel(arena),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        model.taxFormProfileTaxablePeriodLabel(arena),
        "04/01/2026 - 06/30/2026",
    ) != null);
}

test "month navigation stays inside the selected Forms Set year" {
    const allocator = std.testing.allocator;
    var profile_store_instance = try profile_store.Store.openMemory(allocator);
    defer profile_store_instance.close();
    try addTestProfile(
        &profile_store_instance,
        "11111111111111111111111111111111",
        "Juan Dela Cruz",
        "123-456-789-000",
        .individual,
    );
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();

    var model = Model{};
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-year-boundary-test.ics",
        "20261231T010203Z",
        2026,
        12,
    );
    try model.taxProfiles.attach(
        allocator,
        &profile_store_instance,
        "2026-12-31",
        2026,
    );
    const profile_id = model.taxProfiles.selectedProfileId().?;
    try profile_store_instance.replaceFormSet(profile_id, 2027, &.{
        .{
            .form_code = "2551Q",
            .form_revision = "2018-01-ENCS",
        },
    });
    refreshSelectedProfileFormSet(&model);
    try std.testing.expect(!model.taxpayerForm0605Disabled());

    model.libraryFilter.page_offset = 12;
    model.libraryFilter.month_mask = 1;
    model.libraryFilter.on_demand_mask = 1;

    update(&model, .calendar_next_month);
    try std.testing.expectEqual(@as(i32, 2026), model.calendar.selected_year);
    try std.testing.expectEqual(@as(u8, 12), model.calendar.selected_month);
    try std.testing.expect(!model.taxpayerForm0605Disabled());
    try std.testing.expect(!model.taxpayerForm2551QDisabled());
    try std.testing.expectEqual(@as(usize, 12), model.libraryFilter.page_offset);
    try std.testing.expectEqual(@as(u16, 1), model.libraryFilter.month_mask);
    try std.testing.expectEqual(@as(u64, 1), model.libraryFilter.on_demand_mask);
    try std.testing.expect(model.profileCalendarNextMonthDisabled());

    model.calendar.selected_month = 1;
    syncSelectedProfileCalendar(&model);
    update(&model, .calendar_previous_month);
    try std.testing.expectEqual(@as(i32, 2026), model.calendar.selected_year);
    try std.testing.expectEqual(@as(u8, 1), model.calendar.selected_month);
    try std.testing.expect(!model.taxpayerForm0605Disabled());
    try std.testing.expect(model.profileCalendarPreviousMonthDisabled());
}

test "2551Q app wiring saves and resumes exact profile and transaction data" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "11111111111111111111111111111111",
        "Juan Dela Cruz",
        "123-456-789-000",
        .individual,
    );
    try addTestCompleteBusinessRegistration(
        &store,
        "11111111111111111111111111111111",
        "2026-01-01".*,
    );

    var model = Model{};
    model.calendar.selected_year = 2026;
    model.calendar.selected_month = 3;
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();

    update(&model, .show_form_2551q);
    try std.testing.expectEqual(Page.form_2551q, model.page);
    try std.testing.expect(model.formProfiles.projectionAccepted());
    try std.testing.expectEqual(
        @as(usize, 7),
        model.formProfiles.snapshot().?.slice().len,
    );
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    try std.testing.expectEqualStrings(
        "2026 Q1",
        model.formFilingPeriodLabel(arena_state.allocator()),
    );
    try std.testing.expectEqualStrings(
        "2026",
        model.formFilingYear(arena_state.allocator()),
    );
    try std.testing.expectEqualStrings(
        "01 / 01 / 2026",
        model.formFilingPeriodStart(arena_state.allocator()),
    );
    try std.testing.expectEqualStrings(
        "03 / 31 / 2026",
        model.formFilingPeriodEnd(arena_state.allocator()),
    );
    try std.testing.expectEqualStrings(
        "123-456-789-000",
        model.formFilerTin(arena_state.allocator()),
    );

    update(&model, .percentage_tax_period_fiscal);
    try std.testing.expectEqualStrings(
        "",
        model.percentageTaxPeriodBasis(),
    );
    update(&model, .percentage_tax_period_calendar);
    update(&model, .{
        .percentage_tax_year_end_month_input = .{
            .insert_text = "12",
        },
    });
    update(&model, .percentage_tax_election_graduated);
    update(&model, .{
        .percentage_tax_line_1_atc_input = .{ .insert_text = "PT010" },
    });
    update(&model, .{
        .percentage_tax_line_1_base_input = .{
            .insert_text = "1000.00",
        },
    });
    update(&model, .{
        .percentage_tax_line_1_rate_input = .{ .insert_text = "3.00" },
    });
    update(&model, .{
        .percentage_tax_line_2_atc_input = .{ .insert_text = "PT020" },
    });
    update(&model, .{
        .percentage_tax_line_2_base_input = .{
            .insert_text = "2000.00",
        },
    });
    update(&model, .{
        .percentage_tax_line_2_rate_input = .{ .insert_text = "1.00" },
    });
    try std.testing.expect(model.formProfileCanSaveDraft());
    try std.testing.expectEqualStrings(
        "50.00",
        model.percentageTaxTotalDue(),
    );

    update(&model, .save_recurring_form_draft);
    const saved_id = model.formProfiles.draftId().?;
    var draft = (try store.getDraft(
        allocator,
        saved_id.asSlice(),
    )).?;
    defer draft.deinit(allocator);
    // Transaction fields only: this filing states no contact detail of its own.
    try std.testing.expectEqual(
        @as(usize, percentage_tax_ui.max_draft_values -
            percentage_tax_ui.filing_contact_field_count),
        draft.values.len,
    );
    var found_external_rate = false;
    var found_derived_total = false;
    for (draft.values) |*value| {
        if (std.mem.eql(
            u8,
            value.field_id,
            "2551Q.2018-01-ENCS.schedule.line-1.rate",
        )) {
            found_external_rate = true;
            try std.testing.expectEqualStrings(
                "external_policy",
                value.provenance,
            );
        }
        if (std.mem.eql(
            u8,
            value.field_id,
            percentage_tax_ui.PersistedField
                .total_percentage_tax_due.id(),
        )) {
            found_derived_total = true;
            try std.testing.expectEqualStrings("50.00", value.value_text);
            try std.testing.expectEqualStrings(
                "derived",
                value.provenance,
            );
        }
    }
    try std.testing.expect(found_external_rate);
    try std.testing.expect(found_derived_total);

    model.percentageTax = .{};
    update(&model, .show_form_2551q);
    try std.testing.expectEqualStrings(
        "PT010",
        model.percentageTaxLine1Atc(),
    );
    try std.testing.expectEqualStrings(
        "PT020",
        model.percentageTaxLine2Atc(),
    );
    try std.testing.expectEqualStrings(
        "50.00",
        model.percentageTaxTotalDue(),
    );
    try std.testing.expectEqualStrings(
        saved_id.asSlice(),
        model.formProfiles.draftId().?.asSlice(),
    );
}

test "1701Q opens exact state and coarse draft persistence stays disabled" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "11111111111111111111111111111111",
        "Juan Dela Cruz",
        "123-456-789-000",
        .individual,
    );
    try addTestProfile(
        &store,
        "22222222222222222222222222222222",
        "Maria Dela Cruz",
        "987-654-321-000",
        .individual,
    );

    var model = Model{};
    model.calendar.selected_year = 2026;
    model.calendar.selected_month = 12;
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);
    model.taxProfiles.select(profileSlotNamed(&model, "Juan Dela Cruz").?);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    model.exact1701Q.attach(allocator, .{
        .current_year = 2026,
        .schedule_date = .{
            .current_date = .{ .year = 2026, .month = 7, .day = 30 },
            .empty_default_input_was_later = false,
        },
    });
    defer model.exact1701Q.deinit();

    update(&model, .show_form_1701q);
    try std.testing.expectEqual(Page.form_1701q, model.page);
    try std.testing.expect(model.incomeTaxSaveDisabled());
    try std.testing.expect(model.formProfiles.formRevision() == null);
    // 1701Q covers quarters one to three, so a December context opens no
    // projection and the header has nothing truthful to show.
    try std.testing.expectEqualStrings("", model.formFilerRdo());

    update(&model, .income_tax_quarter_q2);
    try std.testing.expectEqual(@as(u8, 6), model.calendar.selected_month);
    try std.testing.expectEqual(@as(u8, 2), model.formProfiles.quarter());
    try std.testing.expect(model.incomeTax.quarter() == null);
    try std.testing.expect(model.formProfiles.projectionAccepted());
    try std.testing.expect(model.exact1701Q.ready());
    try std.testing.expectEqual(
        exact_1701q_ui.control_count,
        model.exact1701Q.rows().len,
    );
    try std.testing.expect(!model.formProfileCanSaveDraft());

    // With a projection open the header shows the taxpayer's own details,
    // which is what the bound inputs render.
    {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        try std.testing.expectEqualStrings("040", model.formFilerRdo());
        try std.testing.expectEqualStrings(
            "Juan Dela Cruz",
            model.formFilerTaxpayerName(),
        );
        try std.testing.expectEqualStrings(
            "123-456-789-000",
            model.formFilerTin(arena),
        );
        try std.testing.expectEqualStrings(
            "Quezon City",
            model.formFilerRegisteredAddress(),
        );
    }

    const filer_id = model.taxProfiles.selectedProfileDomainId().?;
    var spouse_slot: ?usize = null;
    for (model.formProfiles.spouseCandidates(), 0..) |*candidate, index| {
        if (!candidate.profile_id.eql(&filer_id)) {
            spouse_slot = index;
            break;
        }
    }
    update(&model, .{ .select_form_spouse = spouse_slot.? });
    try std.testing.expectEqualStrings(
        "Maria Dela Cruz",
        model.formSpouseName(),
    );
    try std.testing.expect(model.exact1701Q.ready());

    // No hidden coarse editor is allowed to become a parallel authority.
    try std.testing.expect(model.incomeTaxSaveDisabled());

    update(&model, .save_recurring_form_draft);
    try std.testing.expect(model.formProfiles.draftId() == null);
    try std.testing.expectEqual(
        @as(usize, 0),
        std.mem.count(u8, app_markup, "on-input=\"income_tax_"),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "exact_1701q_generate_editable_candidate",
    ) != null);
}

test "exact 1701Q survives navigation and only explicit discard permits replacement" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "33333333333333333333333333333333",
        "Navigation Filer",
        "321-654-987-000",
        .individual,
    );
    try addTestCompleteBusinessRegistration(
        &store,
        "33333333333333333333333333333333",
        "2026-01-01".*,
    );

    var model = Model{};
    model.calendar.selected_year = 2026;
    model.calendar.selected_month = 6;
    try model.taxProfiles.attach(
        allocator,
        &store,
        "2026-07-29",
        2026,
    );
    model.taxProfiles.select(
        profileSlotNamed(&model, "Navigation Filer").?,
    );
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    model.exact1701Q.attach(allocator, .{
        .current_year = 2026,
        .schedule_date = .{
            .current_date = .{ .year = 2026, .month = 7, .day = 30 },
            .empty_default_input_was_later = false,
        },
    });
    defer model.exact1701Q.deinit();

    update(&model, .show_form_1701q);
    update(&model, .income_tax_quarter_q2);
    try std.testing.expect(model.exact1701Q.ready());
    model.exact1701Q.calculate();
    model.exact1701Q.validateSave();
    try std.testing.expect(
        model.exact1701Q.canGenerateEditableCandidate(),
    );
    model.exact1701Q.generateEditableCandidate();
    try std.testing.expect(model.exact1701Q.candidateVisible());
    const exact_before_coarse_dispatch =
        try model.exact1701Q.exact.?.candidateSummary();
    try model.incomeTax.reset(2026, 2);
    update(&model, .{
        .income_tax_sheets_attached_input = .{
            .insert_text = "9",
        },
    });
    const exact_after_coarse_dispatch =
        try model.exact1701Q.exact.?.candidateSummary();
    try std.testing.expectEqualSlices(
        u8,
        &exact_before_coarse_dispatch.sha256,
        &exact_after_coarse_dispatch.sha256,
    );
    try std.testing.expect(model.exact1701Q.candidateVisible());
    update(&model, .income_tax_quarter_q3);
    try std.testing.expectEqual(@as(u8, 2), model.formProfiles.quarter());
    try std.testing.expect(model.exact1701Q.candidateVisible());
    try std.testing.expectEqualStrings(
        "destructive",
        model.exact1701Q.noticeTone(),
    );

    var lob_slot: ?usize = null;
    for (model.exact1701Q.rows(), 0..) |*row, slot| {
        if (std.mem.eql(
            u8,
            row.idLabel(),
            "frm1701q:txtLOB",
        )) {
            lob_slot = slot;
            break;
        }
    }
    update(&model, .{ .exact_1701q_select_control = lob_slot.? });
    update(&model, .exact_1701q_toggle_selected_reveal);
    update(&model, .{
        .exact_1701q_editor_input = .{
            .insert_text = "navigation edit",
        },
    });
    try std.testing.expect(
        model.exact1701Q.hasDirtyOrMaterialWork(),
    );
    try std.testing.expect(!model.exact1701Q.candidateVisible());

    // Revising the bound taxpayer inline keeps the exact workspace open but
    // must still surface the immutable-revision warning.
    update(&model, .show_taxpayer_dashboard);
    update(&model, .show_dashboard_profile_settings);
    update(&model, .edit_tax_profile);
    model.taxProfiles.display_name.set("Navigation Filer Revised");
    update(&model, .save_profile);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expect(model.exact1701Q.ready());
    try std.testing.expect(std.mem.indexOf(
        u8,
        model.exact1701Q.noticeText(),
        "newer tax-profile revision",
    ) != null);

    update(&model, .show_global_dashboard);
    try std.testing.expectEqual(Page.global_dashboard, model.page);
    try std.testing.expect(model.exact1701Q.ready());
    try std.testing.expectEqualStrings(
        "navigation edit",
        model.exact1701Q.selectedEditorText(),
    );

    update(&model, .show_form_1701q);
    try std.testing.expectEqual(Page.form_1701q, model.page);
    try std.testing.expectEqualStrings(
        "navigation edit",
        model.exact1701Q.selectedEditorText(),
    );
    update(&model, .exact_1701q_toggle_selected_reveal);
    try std.testing.expect(model.exact1701Q.candidateVisible());

    update(&model, .show_form_2551q);
    try std.testing.expectEqual(Page.form_1701q, model.page);
    try std.testing.expect(model.exact1701Q.ready());
    try std.testing.expect(model.exact1701Q.candidateVisible());
    try std.testing.expectEqualStrings(
        "destructive",
        model.exact1701Q.noticeTone(),
    );

    update(&model, .exact_1701q_discard_workspace);
    try std.testing.expect(!model.exact1701Q.ready());
    try std.testing.expect(std.mem.indexOf(
        u8,
        model.exact1701Q.noticeText(),
        "explicitly discarded",
    ) != null);
    update(&model, .show_form_2551q);
    try std.testing.expectEqual(Page.form_2551q, model.page);
    try std.testing.expect(!model.exact1701Q.ready());
}

test "material exact 1701Q blocks a different sidebar taxpayer selection" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addThreeTestProfiles(&store);

    var model = Model{};
    model.calendar.selected_year = 2026;
    model.calendar.selected_month = 6;
    try model.taxProfiles.attach(
        allocator,
        &store,
        "2026-07-29",
        2026,
    );
    const filer_slot = profileSlotNamed(&model, "Juan Dela Cruz").?;
    const other_slot = profileSlotNamed(
        &model,
        "Sample Partnership",
    ).?;
    model.taxProfiles.select(filer_slot);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    model.exact1701Q.attach(allocator, .{
        .current_year = 2026,
        .schedule_date = .{
            .current_date = .{ .year = 2026, .month = 7, .day = 30 },
            .empty_default_input_was_later = false,
        },
    });
    defer model.exact1701Q.deinit();

    update(&model, .show_form_1701q);
    try std.testing.expect(model.exact1701Q.ready());
    model.exact1701Q.calculate();
    try std.testing.expect(
        model.exact1701Q.hasDirtyOrMaterialWork(),
    );
    const exact_workspace = model.exact1701Q.workspaceId().?;
    try std.testing.expectEqualStrings(
        model.taxProfiles.rowAt(filer_slot).?.idLabel(),
        model.exact1701Q.filerProfileId().?,
    );

    // Simulate stale presentation state from the pre-guard defect. The
    // security decision must use the exact workspace's immutable filer
    // binding, never the sidebar row's visual `active` flag.
    model.taxProfiles.profiles[filer_slot].active = false;
    model.taxProfiles.profiles[other_slot].active = true;

    update(&model, .show_global_dashboard);
    update(&model, .{
        .select_taxpayer = model.profileRows().len,
    });
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        model.selectedTaxpayerName(),
    );
    try std.testing.expectEqual(Page.global_dashboard, model.page);
    try std.testing.expect(
        model.exact1701Q.hasDirtyOrMaterialWork(),
    );
    try std.testing.expect(
        exact_workspace.eql(&model.exact1701Q.workspaceId().?),
    );
    try expectAppMarkupBuilds(&model);

    update(&model, .{ .select_taxpayer = other_slot });
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        model.selectedTaxpayerName(),
    );
    try std.testing.expectEqual(Page.form_1701q, model.page);
    try std.testing.expect(model.exact1701Q.ready());
    try std.testing.expectEqualStrings(
        "destructive",
        model.exact1701Q.noticeTone(),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        model.exact1701Q.noticeText(),
        "was not changed",
    ) != null);
    try std.testing.expect(
        exact_workspace.eql(&model.exact1701Q.workspaceId().?),
    );
    try std.testing.expectEqualStrings(
        model.taxProfiles.rowAt(filer_slot).?.idLabel(),
        model.exact1701Q.filerProfileId().?,
    );
    try std.testing.expect(
        model.taxProfiles.rowAt(filer_slot).?.active,
    );
    try std.testing.expect(
        !model.taxProfiles.rowAt(other_slot).?.active,
    );
    try expectAppMarkupBuilds(&model);

    // Selecting the already-bound taxpayer is navigation, not a context
    // change, and remains available without discarding exact work even when
    // that row's stale visual flag says it is inactive.
    model.taxProfiles.profiles[filer_slot].active = false;
    model.taxProfiles.profiles[other_slot].active = true;
    update(&model, .{ .select_taxpayer = filer_slot });
    try std.testing.expectEqualStrings(
        "Juan Dela Cruz",
        model.selectedTaxpayerName(),
    );
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.exact1701Q.ready());
    try std.testing.expect(
        exact_workspace.eql(&model.exact1701Q.workspaceId().?),
    );
    try std.testing.expect(
        model.taxProfiles.rowAt(filer_slot).?.active,
    );
    try std.testing.expect(
        !model.taxProfiles.rowAt(other_slot).?.active,
    );
}

test "material exact 1701Q guards profile creation and retains its immutable revision" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addThreeTestProfiles(&store);
    try addTestCompleteBusinessRegistration(
        &store,
        "11111111111111111111111111111111",
        "2026-01-01".*,
    );

    var model = Model{};
    model.calendar.selected_year = 2026;
    model.calendar.selected_month = 6;
    try model.taxProfiles.attach(
        allocator,
        &store,
        "2026-07-29",
        2026,
    );
    const filer_slot = profileSlotNamed(&model, "Juan Dela Cruz").?;
    model.taxProfiles.select(filer_slot);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    model.exact1701Q.attach(allocator, .{
        .current_year = 2026,
        .schedule_date = .{
            .current_date = .{ .year = 2026, .month = 7, .day = 30 },
            .empty_default_input_was_later = false,
        },
    });
    defer model.exact1701Q.deinit();

    update(&model, .show_form_1701q);
    model.exact1701Q.calculate();
    model.exact1701Q.validateSave();
    try std.testing.expect(
        model.exact1701Q.canGenerateEditableCandidate(),
    );
    model.exact1701Q.generateEditableCandidate();
    try std.testing.expect(model.exact1701Q.candidateVisible());

    const exact_workspace = model.exact1701Q.workspaceId().?;
    const exact_revision_sequence =
        model.exact1701Q.filerRevisionSequence().?;
    const candidate_before =
        try model.exact1701Q.exact.?.candidateSummary();
    const initial_profile_count = model.profileRows().len;
    const selected_revision_before =
        model.taxProfiles.selectedRevisionContext().?;
    try std.testing.expectEqual(
        selected_revision_before.sequence,
        exact_revision_sequence,
    );

    // Creating another profile is an unavoidable filer-context change and is
    // blocked before the profile editor can replace any selection. Existing
    // same-profile editor bytes are not reloaded or discarded by rejection.
    update(&model, .show_profile_setup);
    update(&model, .edit_tax_profile);
    model.taxProfiles.display_name.set("Unsaved Same Profile Edit");
    try expectAppMarkupBuilds(&model);
    update(&model, .new_taxpayer_profile);
    // The exact workspace rejects the filer change, while the Tax Profile's
    // own dirty-navigation guard keeps its draft visible until the user
    // explicitly stays or discards it.
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expect(model.profileDirtyNavigationVisible());
    try std.testing.expect(!model.taxProfiles.editing_new);
    try std.testing.expectEqualStrings(
        "Unsaved Same Profile Edit",
        model.taxProfiles.display_name.text(),
    );
    try std.testing.expectEqual(
        initial_profile_count,
        model.profileRows().len,
    );
    try std.testing.expect(
        exact_workspace.eql(&model.exact1701Q.workspaceId().?),
    );
    try std.testing.expectEqualStrings(
        "destructive",
        model.exact1701Q.noticeTone(),
    );
    try expectAppMarkupBuilds(&model);

    // Appending a revision to the same stable filer is safe: the selected
    // profile advances, while the material exact workspace and its candidate
    // retain the immutable revision captured at open.
    update(&model, .profile_keep_editing);
    // Give the save an actual change to record: a revision logs a real event,
    // not a visit.
    model.taxProfiles.display_name.set("Exact Filer Renamed");
    update(&model, .save_profile);

    try std.testing.expectEqual(Page.form_1701q, model.page);
    const selected_revision_after =
        model.taxProfiles.selectedRevisionContext().?;
    try std.testing.expectEqual(
        selected_revision_before.sequence + 1,
        selected_revision_after.sequence,
    );
    try std.testing.expectEqual(
        exact_revision_sequence,
        model.exact1701Q.filerRevisionSequence().?,
    );
    try std.testing.expect(
        exact_workspace.eql(&model.exact1701Q.workspaceId().?),
    );
    const candidate_after_revision =
        try model.exact1701Q.exact.?.candidateSummary();
    try std.testing.expectEqualSlices(
        u8,
        &candidate_before.sha256,
        &candidate_after_revision.sha256,
    );
    try std.testing.expect(model.exact1701Q.candidateVisible());
    try std.testing.expectEqualStrings(
        "secondary",
        model.exact1701Q.noticeTone(),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        model.exact1701Q.noticeText(),
        "remains bound to the immutable profile revision",
    ) != null);
    try expectAppMarkupBuilds(&model);

    // Defend the save boundary too, even if an in-progress new-profile editor
    // was reached through stale pre-guard state. Rejection preserves both the
    // exact candidate and the unpersisted editor bytes.
    model.taxProfiles.startNew();
    model.taxProfiles.display_name.set("Blocked New Profile");
    model.taxProfiles.tin.set("444-555-666-00000");
    model.taxProfiles.rdo.set("040");
    model.taxProfiles.registered_address.set("Quezon City");
    model.taxProfiles.effective_from.set("2026-01-01");
    model.taxProfiles.setNaturalPersonClassification(.pure_compensation);
    openProfileEditor(&model);
    try std.testing.expect(model.taxProfiles.editing_new);
    try expectAppMarkupBuilds(&model);
    update(&model, .save_profile);
    // The save is rejected, and the attempted return to the exact workspace
    // is itself guarded because the new-profile draft is dirty. Nothing is
    // hidden or discarded until the user explicitly chooses.
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expect(model.profileDirtyNavigationVisible());
    try std.testing.expect(model.taxProfiles.editing_new);
    try std.testing.expectEqualStrings(
        "Blocked New Profile",
        model.taxProfiles.display_name.text(),
    );
    try std.testing.expectEqual(
        initial_profile_count,
        model.profileRows().len,
    );
    const candidate_after_block =
        try model.exact1701Q.exact.?.candidateSummary();
    try std.testing.expectEqualSlices(
        u8,
        &candidate_before.sha256,
        &candidate_after_block.sha256,
    );
    try std.testing.expectEqualStrings(
        "destructive",
        model.exact1701Q.noticeTone(),
    );
    try expectAppMarkupBuilds(&model);

    // Explicit discard removes the guard. Profile creation then follows the
    // ordinary editor/save path and may select the newly created taxpayer.
    update(&model, .exact_1701q_discard_workspace);
    try std.testing.expect(!model.exact1701Q.ready());
    update(&model, .profile_keep_editing);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expect(model.taxProfiles.editing_new);
    model.taxProfiles.display_name.set("Permitted New Profile");
    try expectAppMarkupBuilds(&model);
    update(&model, .save_profile);
    try std.testing.expectEqual(
        initial_profile_count + 1,
        model.profileRows().len,
    );
    try std.testing.expectEqualStrings(
        "Permitted New Profile",
        model.selectedTaxpayerName(),
    );
    try std.testing.expect(!model.exact1701Q.ready());
    try expectAppMarkupBuilds(&model);
}

test "exact 1701Q Original and Amended actions mint guarded filing workspaces" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "34343434343434343434343434343434",
        "Filing Kind Filer",
        "321-765-489-000",
        .individual,
    );

    var model = Model{};
    model.calendar.selected_year = 2026;
    model.calendar.selected_month = 6;
    try model.taxProfiles.attach(
        allocator,
        &store,
        "2026-07-29",
        2026,
    );
    model.taxProfiles.select(
        profileSlotNamed(&model, "Filing Kind Filer").?,
    );
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    model.exact1701Q.attach(allocator, .{
        .current_year = 2026,
        .schedule_date = .{
            .current_date = .{ .year = 2026, .month = 7, .day = 30 },
            .empty_default_input_was_later = false,
        },
    });
    defer model.exact1701Q.deinit();

    update(&model, .show_form_1701q);
    update(&model, .income_tax_quarter_q2);
    try std.testing.expect(model.exact1701Q.ready());
    try std.testing.expect(!model.exact1701Q.amended());
    const original_workspace = model.exact1701Q.workspaceId().?;

    update(&model, .exact_1701q_open_amended);
    try std.testing.expect(model.exact1701Q.ready());
    try std.testing.expect(model.exact1701Q.amended());
    try std.testing.expect(
        model.exact1701Q.exact.?.filingContext().amended,
    );
    const pristine_amended_workspace =
        model.exact1701Q.workspaceId().?;
    try std.testing.expect(
        !original_workspace.eql(&pristine_amended_workspace),
    );

    model.exact1701Q.calculate();
    try std.testing.expect(
        model.exact1701Q.hasDirtyOrMaterialWork(),
    );
    update(&model, .exact_1701q_open_original);
    try std.testing.expect(model.exact1701Q.amended());
    const blocked_workspace = model.exact1701Q.workspaceId().?;
    try std.testing.expect(
        blocked_workspace.eql(&pristine_amended_workspace),
    );
    try std.testing.expectEqualStrings(
        "destructive",
        model.exact1701Q.noticeTone(),
    );

    update(&model, .exact_1701q_discard_workspace);
    try std.testing.expect(!model.exact1701Q.ready());
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "on-press=\"exact_1701q_open_original\"",
    ) != null);
    const amended_action_position = std.mem.indexOf(
        u8,
        app_markup,
        "on-press=\"exact_1701q_open_amended\"",
    ).?;
    const ready_branch_position = std.mem.indexOf(
        u8,
        app_markup,
        "<if test=\"{exact1701QReady}\">",
    ).?;
    try std.testing.expect(
        amended_action_position < ready_branch_position,
    );

    update(&model, .exact_1701q_open_amended);
    try std.testing.expect(model.exact1701Q.ready());
    try std.testing.expect(model.exact1701Q.amended());
    const reopened_amended_workspace =
        model.exact1701Q.workspaceId().?;
    try std.testing.expect(
        !reopened_amended_workspace.eql(&blocked_workspace),
    );

    model.exact1701Q.calculate();
    model.exact1701Q.validateSave();
    try std.testing.expect(
        model.exact1701Q.canGenerateEditableCandidate(),
    );
    model.exact1701Q.generateEditableCandidate();
    try std.testing.expect(model.exact1701Q.candidateVisible());
    const candidate_before =
        try model.exact1701Q.exact.?.candidateSummary();
    try std.testing.expectError(
        error.FilingContextLocked,
        model.exact1701Q.exact.?.setRadio(
            "frm1701q:AmendedRtn_2",
            true,
        ),
    );
    const candidate_after =
        try model.exact1701Q.exact.?.candidateSummary();
    try std.testing.expectEqualSlices(
        u8,
        &candidate_before.sha256,
        &candidate_after.sha256,
    );
    try std.testing.expect(
        model.exact1701Q.exact.?.filingContext().amended,
    );
}

test "exact 1701Q projection-only open isolates an older coarse draft" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    const old_effective = try profile_model.EffectivePeriod.init(
        try profile_model.Date.parseIso("2026-01-01"),
        null,
    );
    const old_activities = [_]profile_model.BusinessActivity{.{
        .id = try profile_model.BusinessActivityId.parse(
            "legacy-draft-activity",
        ),
        .line_of_business = try profile_fields.LineOfBusiness.parse(
            "Legacy consulting",
        ),
        .atc = try profile_fields.Atc.parse("PT010"),
        .effective = old_effective,
    }};
    try persistTestSoleProprietorRevision(
        &store,
        "projection-only-filer",
        "projection-only-filer-r1",
        1,
        "2026-01-01",
        "LEGACY PROFILE NAME",
        "123-456-789-000",
        &old_activities,
    );
    try addTestProfile(
        &store,
        "projection-only-spouse",
        "CURRENT SPOUSE",
        "987-654-321-000",
        .individual,
    );

    const filer_id = try profile_model.ProfileId.parse(
        "projection-only-filer",
    );
    const spouse_id = try profile_model.ProfileId.parse(
        "projection-only-spouse",
    );
    const legacy_period: form_runtime.RecurringQuarter = .{
        .form = editorRevision("1701Q").?,
        .tax_year = 2026,
        .quarter = 2,
    };
    const legacy_draft_id = try form_persistence.originalDraftId(
        filer_id,
        legacy_period,
    );
    var legacy_period_buffer: [form_persistence.canonical_period_key_len]u8 = undefined;
    const legacy_period_key = try form_persistence.canonicalPeriodKey(
        legacy_period,
        &legacy_period_buffer,
    );
    const legacy_bindings = [_]profile_store.RoleBindingWrite{
        .{
            .role = "filer",
            .profile_id = filer_id.asSlice(),
            .profile_revision_id = "projection-only-filer-r1",
            .profile_revision_sequence = 1,
            .business_activity_id = old_activities[0].id.asSlice(),
        },
        .{
            .role = "spouse",
            .profile_id = spouse_id.asSlice(),
            .profile_revision_id = "rev-projection-only-spouse",
            .profile_revision_sequence = 1,
        },
    };
    const legacy_values = [_]profile_store.DraftValueWrite{.{
        .field_id = "legacy.coarse.marker",
        .value_text = "must-remain-unchanged",
        .provenance = "transaction",
    }};
    try store.createDraft(
        .{
            .id = legacy_draft_id.asSlice(),
            .form_code = legacy_period.form.code.asSlice(),
            .form_revision = legacy_period.form.revision.asSlice(),
            .period_key = legacy_period_key,
            .profile_as_of = "2026-06-30".*,
            .mapping_revision = form_persistence.mapping_revision_v1,
        },
        &legacy_bindings,
        &.{},
        &legacy_values,
    );

    const current_effective = try profile_model.EffectivePeriod.init(
        try profile_model.Date.parseIso("2026-04-01"),
        null,
    );
    const current_activities = [_]profile_model.BusinessActivity{
        .{
            .id = try profile_model.BusinessActivityId.parse(
                "current-retail-activity",
            ),
            .line_of_business = try profile_fields.LineOfBusiness.parse(
                "Current retail",
            ),
            .atc = try profile_fields.Atc.parse("PT020"),
            .effective = current_effective,
        },
        .{
            .id = try profile_model.BusinessActivityId.parse(
                "current-service-activity",
            ),
            .line_of_business = try profile_fields.LineOfBusiness.parse(
                "Current services",
            ),
            .atc = try profile_fields.Atc.parse("PT030"),
            .effective = current_effective,
        },
    };
    try persistTestSoleProprietorRevision(
        &store,
        "projection-only-filer",
        "projection-only-filer-r2",
        2,
        "2026-04-01",
        "CURRENT PROFILE NAME",
        "123-456-789-000",
        &current_activities,
    );

    var model = Model{};
    model.calendar.selected_year = 2026;
    model.calendar.selected_month = 6;
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);
    model.taxProfiles.select(
        // Sidebar identity follows the current registered name now that the
        // app-only Profile Label has been removed.
        profileSlotNamed(&model, "CURRENT PROFILE NAME").?,
    );
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    model.exact1701Q.attach(allocator, .{
        .current_year = 2026,
        .schedule_date = .{
            .current_date = .{ .year = 2026, .month = 7, .day = 30 },
            .empty_default_input_was_later = false,
        },
    });
    defer model.exact1701Q.deinit();

    update(&model, .show_form_1701q);
    try std.testing.expectEqual(Page.form_1701q, model.page);
    try std.testing.expect(model.formProfiles.projectionAccepted());
    try std.testing.expect(model.exact1701Q.ready());
    // This catches runtime-only binding/option failures that the strict
    // markup checker and state-transition tests cannot observe.
    try expectAppMarkupBuilds(&model);
    try std.testing.expect(model.formProfiles.draftId() == null);
    try std.testing.expect(!model.formProfiles.profileSnapshotLocked());
    try std.testing.expect(model.formProfiles.saveDisabled());
    try std.testing.expect(!model.formProfileCanSaveDraft());
    try std.testing.expectEqual(
        @as(u32, 2),
        model.formProfiles.roleBinding(.filer).?.revision_sequence,
    );
    try std.testing.expectEqualStrings(
        "CURRENT PROFILE NAME",
        model.formProfiles.filerText(.taxpayer_name),
    );
    try std.testing.expect(
        model.formProfiles.roleBinding(.spouse) == null,
    );

    var exact_name_slot: ?usize = null;
    for (model.exact1701Q.rows(), 0..) |*row, slot| {
        if (std.mem.eql(
            u8,
            row.idLabel(),
            "frm1701q:txtTaxpayerName",
        )) {
            exact_name_slot = slot;
            break;
        }
    }
    model.exact1701Q.selectControl(exact_name_slot.?);
    model.exact1701Q.toggleSelectedReveal();
    try std.testing.expectEqualStrings(
        "CURRENT PROFILE NAME",
        model.exact1701Q.selectedEditorText(),
    );

    const activity_candidates =
        model.formProfiles.activityCandidates(.filer);
    try std.testing.expectEqual(
        @as(usize, current_activities.len),
        activity_candidates.len,
    );
    for (activity_candidates) |*candidate| {
        try std.testing.expect(!candidate.selected);
        try std.testing.expect(!candidate.id.eql(&old_activities[0].id));
    }
    var current_activity_slot: ?usize = null;
    for (activity_candidates, 0..) |*candidate, slot| {
        if (candidate.id.eql(&current_activities[1].id)) {
            current_activity_slot = slot;
            break;
        }
    }
    update(&model, .{
        .select_form_activity = current_activity_slot.?,
    });
    try std.testing.expect(
        model.formProfiles.roleBinding(.filer).?
            .business_activity_id.?.eql(&current_activities[1].id),
    );
    try std.testing.expect(model.exact1701Q.ready());

    var current_spouse_slot: ?usize = null;
    for (model.formProfiles.spouseCandidates(), 0..) |*candidate, slot| {
        try std.testing.expect(!candidate.selected);
        if (candidate.profile_id.eql(&spouse_id)) {
            current_spouse_slot = slot;
        }
    }
    update(&model, .{ .select_form_spouse = current_spouse_slot.? });
    try std.testing.expect(
        model.formProfiles.roleBinding(.spouse).?.profile_id.eql(
            &spouse_id,
        ),
    );
    try std.testing.expect(model.exact1701Q.ready());

    try std.testing.expectError(
        error.DraftPersistenceDisabled,
        model.formProfiles.saveRecurringDraft(),
    );
    update(&model, .save_recurring_form_draft);
    try std.testing.expect(model.formProfiles.draftId() == null);

    var unchanged = (try store.getDraft(
        allocator,
        legacy_draft_id.asSlice(),
    )).?;
    defer unchanged.deinit(allocator);
    try std.testing.expectEqualStrings("editing", unchanged.lifecycle);
    try std.testing.expectEqualStrings("2026-06-30", unchanged.profile_as_of);
    try std.testing.expectEqual(@as(usize, 2), unchanged.bindings.len);
    try std.testing.expectEqual(@as(usize, 1), unchanged.values.len);
    try std.testing.expectEqualStrings(
        "legacy.coarse.marker",
        unchanged.values[0].field_id,
    );
    try std.testing.expectEqualStrings(
        "must-remain-unchanged",
        unchanged.values[0].value_text,
    );

    var found_legacy_filer_binding = false;
    var found_legacy_spouse_binding = false;
    for (unchanged.bindings) |*binding| {
        if (std.mem.eql(u8, binding.role, "filer")) {
            found_legacy_filer_binding = true;
            try std.testing.expectEqual(
                @as(u32, 1),
                binding.profile_revision_sequence,
            );
            try std.testing.expectEqualStrings(
                old_activities[0].id.asSlice(),
                binding.business_activity_id.?,
            );
        } else if (std.mem.eql(u8, binding.role, "spouse")) {
            found_legacy_spouse_binding = true;
            try std.testing.expectEqual(
                @as(u32, 1),
                binding.profile_revision_sequence,
            );
        }
    }
    try std.testing.expect(found_legacy_filer_binding);
    try std.testing.expect(found_legacy_spouse_binding);
    try std.testing.expectEqual(@as(usize, 0), unchanged.snapshots.len);
    try std.testing.expectEqualStrings(
        form_persistence.mapping_revision_v1,
        unchanged.mapping_revision,
    );
}

test "calendar handoff markup is exposed only as a profile action" {
    try std.testing.expectEqual(
        @as(usize, 3),
        std.mem.count(u8, app_markup, "on-press=\"profile_calendar_export\""),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        std.mem.count(u8, app_markup, "on-press=\"calendar_export\""),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "Native/default calendar handoff",
    ) == null);
}

test "compact profile subject picker selects and dismisses predictably" {
    var model = Model{
        .page = .profile_setup,
        .viewportClass = .phone,
        .viewportWidth = 390,
    };
    try std.testing.expectEqualStrings("Individual", model.profileSubjectKindLabel());
    try std.testing.expect(!model.profileSubjectPickerOpen());

    update(&model, .toggle_profile_subject_picker);
    try std.testing.expect(model.profileSubjectPickerOpen());
    update(&model, .profile_subject_corporation);
    try std.testing.expect(!model.profileSubjectPickerOpen());
    try std.testing.expectEqualStrings("Corporation", model.profileSubjectKindLabel());

    update(&model, .toggle_profile_subject_picker);
    update(&model, .close_profile_subject_picker);
    try std.testing.expect(!model.profileSubjectPickerOpen());
}

test "compact profile settings tab opens inline" {
    var model = Model{
        .page = .taxpayer_dashboard,
        .viewportClass = .compact,
        .viewportWidth = 700,
    };
    update(&model, .show_dashboard_profile_settings);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expect(!model.profileInlineBackVisible());
}

test "transient pages return to their exact origin" {
    var model = Model{ .page = .form_1701q };
    update(&model, .show_aux_html_print_preview);
    try std.testing.expectEqual(Page.aux_html_preview, model.page);
    try std.testing.expectEqual(Page.form_1701q, model.overlayReturnPage);
    try std.testing.expectEqual(Page.form_1701q, model.contentPage());

    update(&model, .go_back);
    try std.testing.expectEqual(Page.form_1701q, model.page);
    try std.testing.expectEqual(
        Page.global_dashboard,
        model.overlayReturnPage,
    );
}

test "profile view cancel stays put and Back returns to its opening page" {
    var model = Model{
        .page = .taxpayer_dashboard,
        .profileSetupSection = .email,
    };
    model.taxProfiles.profile_mode = .viewing;
    model.taxProfiles.editing_new = false;
    update(&model, .show_profile_setup);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expect(model.profileTaxActive());
    try std.testing.expectEqual(
        Page.taxpayer_dashboard,
        model.profileEditorOrigin,
    );
    try std.testing.expectEqualStrings(
        "Back to tax profile",
        model.profileBackLabel(),
    );

    update(&model, .cancel_profile_edit);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expect(model.profileTaxViewing());

    update(&model, .go_back);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expectEqual(
        Page.global_dashboard,
        model.profileEditorOrigin,
    );
}

test "profile editor Back exits clean edits and guards dirty edits" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "profile-editor-back",
        "Back Navigation Taxpayer",
        "123-456-789-000",
        .individual,
    );

    var model = Model{ .page = .taxpayer_dashboard };
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.taxProfiles.select(
        profileSlotNamed(&model, "Back Navigation Taxpayer").?,
    );
    update(&model, .show_profile_setup);
    update(&model, .edit_tax_profile);

    try std.testing.expect(model.taxProfiles.profileEditing());
    try std.testing.expect(model.profileSaveDisabled());
    try std.testing.expect(model.profileCancelDisabled());
    try std.testing.expect(!model.profileInlineBackDisabled());

    update(&model, .go_back);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.profileTaxViewing());
    try std.testing.expectEqualStrings(
        "Back Navigation Taxpayer",
        model.taxProfiles.display_name.text(),
    );

    update(&model, .show_profile_setup);
    update(&model, .edit_tax_profile);
    model.taxProfiles.display_name.set("Unsaved Back Navigation");
    try std.testing.expect(!model.profileCancelDisabled());

    update(&model, .go_back);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expect(model.taxProfiles.profileEditing());
    try std.testing.expect(model.profileDirtyNavigationVisible());
    try std.testing.expectEqualStrings(
        "Unsaved Back Navigation",
        model.taxProfiles.display_name.text(),
    );

    update(&model, .profile_keep_editing);
    try std.testing.expect(!model.profileDirtyNavigationVisible());
    update(&model, .cancel_profile_edit);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expect(model.profileTaxViewing());
    try std.testing.expectEqualStrings(
        "Back Navigation Taxpayer",
        model.taxProfiles.display_name.text(),
    );

    update(&model, .edit_tax_profile);
    model.taxProfiles.display_name.set("Discarded Back Navigation");
    update(&model, .go_back);
    update(&model, .profile_discard_navigation);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.profileTaxViewing());
    try std.testing.expectEqualStrings(
        "Back Navigation Taxpayer",
        model.taxProfiles.display_name.text(),
    );
}

test "Tax Form Profile repair route opens the complete atomic profile editor" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "tax-form-profile-complete-repair",
        "Complete Repair Taxpayer",
        "123-456-789-000",
        .individual,
    );

    var model = Model{ .page = .tax_form_profile };
    try model.taxProfiles.attach(allocator, &store, "2026-08-05", 2026);
    model.taxProfiles.select(
        profileSlotNamed(&model, "Complete Repair Taxpayer").?,
    );

    update(&model, .tax_form_profile_edit_tax_profile);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expect(model.profileTaxActive());
    try std.testing.expect(model.taxProfiles.profileEditing());
    try std.testing.expect(model.regLoaded);
    try std.testing.expect(model.regEditing());
    try std.testing.expect(model.profileSaveDisabled());
    try std.testing.expect(model.profileCancelDisabled());

    update(&model, .profile_subject_corporation);
    update(&model, .profile_eopt_micro);
    update(&model, .{ .profile_primary_line_of_business_input = .{
        .insert_text = "Professional services",
    } });
    try std.testing.expectEqual(
        profile_registration_ui.EditableEoptTier.micro,
        model.regPage.eoptTier().?,
    );
    try std.testing.expectEqual(
        profile_model.Date{ .year = 2026, .month = 1, .day = 1 },
        model.regPage.eoptTierEffective().?.from,
    );
    try std.testing.expectEqualStrings(
        "Professional services",
        model.regPage.primaryBusinessActivity().?.line_of_business.asSlice(),
    );
    try std.testing.expect(!model.profileSaveDisabled());
    try std.testing.expect(!model.profileCancelDisabled());

    update(&model, .cancel_profile_edit);
    try std.testing.expect(model.profileTaxViewing());
    try std.testing.expect(!model.regEditing());
    try std.testing.expect(model.regPage.eoptTier() == null);
    try std.testing.expect(model.regPage.primaryBusinessActivity() == null);
}

test "inline profile settings discard staged edits when cancelled or left" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addTestProfile(
        &store,
        "inline-profile-settings",
        "Original Taxpayer Name",
        "321-654-987-000",
        .individual,
    );
    try addTestProfile(
        &store,
        "inline-profile-settings-second",
        "Second Taxpayer Name",
        "321-654-988-000",
        .individual,
    );
    try addTestCompleteBusinessRegistration(
        &store,
        "inline-profile-settings",
        "2026-01-01".*,
    );

    var model = Model{ .page = .taxpayer_dashboard };
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    model.taxProfiles.select(
        profileSlotNamed(&model, "Original Taxpayer Name").?,
    );
    update(&model, .show_dashboard_profile_settings);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expect(model.profileTaxViewing());
    update(&model, .edit_tax_profile);
    model.taxProfiles.display_name.set("Unsaved Tab Switch");
    update(&model, .show_dashboard_forms);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expect(model.profileDirtyNavigationVisible());
    try std.testing.expectEqualStrings(
        "Unsaved Tab Switch",
        model.taxProfiles.display_name.text(),
    );
    update(&model, .profile_discard_navigation);
    try std.testing.expect(model.dashboardFormsActive());
    try std.testing.expectEqualStrings(
        "Original Taxpayer Name",
        model.selectedTaxpayerName(),
    );

    update(&model, .show_dashboard_profile_settings);
    update(&model, .edit_tax_profile);
    model.taxProfiles.display_name.set("Unsaved Cancel");
    update(&model, .cancel_profile_edit);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expect(model.profileTaxViewing());
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expectEqualStrings(
        "Original Taxpayer Name",
        model.selectedTaxpayerName(),
    );

    update(&model, .edit_tax_profile);
    model.taxProfiles.display_name.set("Saved Inline Revision");
    update(&model, .save_profile);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expect(model.profileTaxViewing());
    try std.testing.expectEqualStrings(
        "Saved Inline Revision",
        model.selectedTaxpayerName(),
    );
    try std.testing.expectEqualStrings(
        "Saved Inline Revision",
        model.taxProfiles.display_name.text(),
    );

    update(&model, .edit_tax_profile);
    model.taxProfiles.display_name.set("Transient Edit Preserved");
    update(&model, .show_aux_command_palette);
    try std.testing.expectEqual(Page.aux_command_palette, model.page);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expectEqualStrings(
        "Transient Edit Preserved",
        model.taxProfiles.display_name.text(),
    );
    update(&model, .go_back);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expectEqualStrings(
        "Transient Edit Preserved",
        model.taxProfiles.display_name.text(),
    );

    model.taxProfiles.display_name.set("Unsaved Sidebar Exit");
    model.profileCompletionTarget = .contact_number;
    model.profileCompletionFormIndex = 0;
    model.pendingProfileFormLaunch = .{
        .form_index = 0,
        .tax_year = 2026,
        .quarter = 1,
        .period_month = null,
        .spouse_profile_id = null,
        .filing = null,
    };
    update(&model, .show_global_dashboard);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expect(model.dashboardProfileSettingsActive());
    try std.testing.expect(model.profileDirtyNavigationVisible());
    try std.testing.expectEqualStrings(
        "Unsaved Sidebar Exit",
        model.taxProfiles.display_name.text(),
    );
    update(&model, .profile_discard_navigation);
    try std.testing.expectEqual(Page.global_dashboard, model.page);
    try std.testing.expect(model.dashboardCalendarActive());
    try std.testing.expect(model.profileCompletionTarget == null);
    try std.testing.expect(model.profileCompletionFormIndex == null);
    try std.testing.expect(model.pendingProfileFormLaunch == null);
    try std.testing.expectEqualStrings(
        "Saved Inline Revision",
        model.selectedTaxpayerName(),
    );

    update(&model, .show_taxpayer_dashboard);
    update(&model, .show_dashboard_profile_settings);
    update(&model, .edit_tax_profile);
    model.taxProfiles.display_name.set("Unsaved Taxpayer Switch");
    model.pendingProfileFormLaunch = .{
        .form_index = 0,
        .tax_year = 2026,
        .quarter = 1,
        .period_month = null,
        .spouse_profile_id = null,
        .filing = null,
    };
    update(&model, .{
        .select_taxpayer = profileSlotNamed(
            &model,
            "Second Taxpayer Name",
        ).?,
    });
    try std.testing.expectEqualStrings(
        "Saved Inline Revision",
        model.selectedTaxpayerName(),
    );
    try std.testing.expect(model.profileDirtyNavigationVisible());
    update(&model, .profile_discard_navigation);
    try std.testing.expectEqualStrings(
        "Second Taxpayer Name",
        model.selectedTaxpayerName(),
    );
    try std.testing.expect(model.dashboardCalendarActive());
    try std.testing.expect(model.pendingProfileFormLaunch == null);

    update(&model, .show_dashboard_forms);
    update(&model, .{ .profile_setup_select_year = 2026 });
    update(&model, .profile_forms_manage);
    update(&model, .{
        .toggle_profile_form = formCatalogIndex("2551Q").?,
    });
    try std.testing.expect(model.taxProfiles.changedFormCount() != 0);
    update(&model, .{
        .select_taxpayer = profileSlotNamed(
            &model,
            "Saved Inline Revision",
        ).?,
    });
    try std.testing.expectEqualStrings(
        "Second Taxpayer Name",
        model.selectedTaxpayerName(),
    );
    try std.testing.expect(model.dashboardFormsActive());
    try std.testing.expect(model.managingProfileForms());
    update(&model, .profile_forms_cancel);
}

test "profile and transient return origins remain independent" {
    var model = Model{ .page = .taxpayer_dashboard };
    model.taxProfiles.profile_mode = .viewing;
    model.taxProfiles.editing_new = false;
    update(&model, .show_profile_setup);
    update(&model, .show_aux_command_palette);

    try std.testing.expectEqual(Page.aux_command_palette, model.page);
    try std.testing.expectEqual(Page.profile_setup, model.overlayReturnPage);
    try std.testing.expectEqual(
        Page.taxpayer_dashboard,
        model.profileEditorOrigin,
    );

    update(&model, .go_back);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expectEqual(
        Page.taxpayer_dashboard,
        model.profileEditorOrigin,
    );

    update(&model, .cancel_profile_edit);
    try std.testing.expectEqual(Page.profile_setup, model.page);

    update(&model, .go_back);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
}

test "transient switches preserve one bounded underlying origin" {
    var model = Model{ .page = .form_1701q };
    update(&model, .show_aux_html_print_preview);
    update(&model, .show_aux_command_palette);

    try std.testing.expectEqual(Page.aux_command_palette, model.page);
    try std.testing.expectEqual(Page.form_1701q, model.overlayReturnPage);

    update(&model, .go_back);
    try std.testing.expectEqual(Page.form_1701q, model.page);
}

test "successful profile save returns to Tax Profile view" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    var model = Model{ .page = .taxpayer_dashboard };
    try model.taxProfiles.attach(
        allocator,
        &store,
        "2026-07-31",
        2026,
    );
    update(&model, .new_taxpayer_profile);
    model.taxProfiles.tin.set("123-456-789-00000");
    model.taxProfiles.rdo.set("040");
    model.taxProfiles.natural_person_classification = .pure_compensation;
    model.taxProfiles.display_name.set("Navigation Test Taxpayer");
    model.taxProfiles.registered_address.set("Quezon City");
    model.taxProfiles.effective_from.set("2026-01-01");

    update(&model, .save_profile);

    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expect(model.profileTaxViewing());
    try std.testing.expectEqual(
        Page.taxpayer_dashboard,
        model.profileEditorOrigin,
    );
    try std.testing.expectEqualStrings(
        "Navigation Test Taxpayer",
        model.selectedTaxpayerName(),
    );
}

test "profile editor has one responsive back control per shell mode" {
    try std.testing.expectEqual(
        @as(usize, 2),
        std.mem.count(u8, app_markup, "label=\"{profileBackLabel}\""),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "<if test=\"{profileInlineBackVisible}\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "<if test=\"{page == 'profile_setup'}\">",
    ) != null);
}

test "profile notice toast supports manual and timed dismissal" {
    const allocator = std.testing.allocator;
    const fx = try allocator.create(Effects);
    defer allocator.destroy(fx);
    fx.* = .{
        .allocator = allocator,
        .executor = .fake,
    };
    defer fx.deinit();

    var model = Model{};
    model.taxProfiles.startNew();
    syncProfileNoticeTimer(&model, fx);

    try std.testing.expect(model.profileNoticeVisible());
    try std.testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    const first_request = fx.pendingTimerAt(0).?;
    try std.testing.expectEqual(
        profile_notice_duration_ms,
        first_request.interval_ms,
    );
    try std.testing.expectEqual(
        native_sdk.TimerMode.one_shot,
        first_request.mode,
    );

    updateWithEffects(&model, .dismiss_profile_notice, fx);
    try std.testing.expect(!model.profileNoticeVisible());
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());

    model.taxProfiles.startNew();
    syncProfileNoticeTimer(&model, fx);
    const fired_key = model.profileNoticeTimerKey;
    try fx.fireTimer(fired_key);
    updateWithEffects(&model, fx.takeMsg().?, fx);
    try std.testing.expect(!model.profileNoticeVisible());
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());

    model.taxProfiles.startNew();
    syncProfileNoticeTimer(&model, fx);
    const rejected_key = model.profileNoticeTimerKey;
    fx.cancelTimer(rejected_key);
    updateWithEffects(&model, .{ .profile_notice_timeout = .{
        .key = rejected_key,
        .outcome = .rejected,
    } }, fx);
    try std.testing.expect(model.profileNoticeVisible());
    try std.testing.expectEqual(@as(u64, 0), model.profileNoticeTimerKey);

    updateWithEffects(&model, .save_profile, fx);
    try std.testing.expect(model.profileNoticeVisible());
    // Blank creation is invalid and Save is disabled, so a programmatic stale
    // dispatch is a no-op and cannot replace the existing neutral notice with
    // an invented failure.
    try std.testing.expect(model.taxProfiles.noticeAutoDismissible());
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
}

test "calendar export toast is safe while busy and dismisses when terminal" {
    const allocator = std.testing.allocator;
    const fx = try allocator.create(Effects);
    defer allocator.destroy(fx);
    fx.* = .{
        .allocator = allocator,
        .executor = .fake,
    };
    defer fx.deinit();

    var model = Model{
        .profileCalendarExportStatus = .writing,
    };
    syncProfileCalendarExportNoticeTimer(&model, fx);
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
    updateWithEffects(
        &model,
        .dismiss_profile_calendar_export_notice,
        fx,
    );
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.writing,
        model.profileCalendarExportStatus,
    );

    model.profileCalendarExportStatus = .opened;
    model.profileCalendarExportNoticeEpoch +%= 1;
    syncProfileCalendarExportNoticeTimer(&model, fx);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    try std.testing.expectEqual(
        profile_calendar_export_notice_duration_ms,
        fx.pendingTimerAt(0).?.interval_ms,
    );

    const timer_key = model.profileCalendarExportTimerKey;
    try fx.fireTimer(timer_key);
    updateWithEffects(&model, fx.takeMsg().?, fx);
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.idle,
        model.profileCalendarExportStatus,
    );
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());

    model.profileCalendarExportStatus = .write_failed;
    model.profileCalendarExportNoticeEpoch +%= 1;
    syncProfileCalendarExportNoticeTimer(&model, fx);
    updateWithEffects(
        &model,
        .dismiss_profile_calendar_export_notice,
        fx,
    );
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.idle,
        model.profileCalendarExportStatus,
    );
    try std.testing.expectEqual(@as(usize, 0), fx.pendingTimerCount());
}

test "important news refresh persists RSS and retains cache on failure" {
    const allocator = std.testing.allocator;
    var store = try news_store.Store.openMemory(allocator);
    defer store.close();

    var model = Model{};
    try attachImportantNews(&model, allocator, &store);
    defer deinitImportantNews(&model);

    const fx = try allocator.create(Effects);
    defer allocator.destroy(fx);
    fx.* = .{ .allocator = allocator, .executor = .fake };
    defer fx.deinit();

    updateWithEffects(&model, .refresh_important_news, fx);
    try std.testing.expect(model.importantNewsRefreshing());
    try std.testing.expectEqual(@as(usize, 1), fx.pendingFetchCount());
    try std.testing.expectEqualStrings(
        important_news_feed_url,
        fx.pendingFetchAt(0).?.url,
    );

    const rss =
        \\<?xml version="1.0"?>
        \\<rss version="2.0"><channel><item>
        \\<guid>notice-1382</guid>
        \\<title>Proclamation No. 1382, s. 2026</title>
        \\<description>Public holiday announcement.</description>
        \\<link>https://www.officialgazette.gov.ph/example/</link>
        \\<pubDate>Thu, 30 Jul 2026 02:11:31 +0000</pubDate>
        \\</item></channel></rss>
    ;
    try fx.feedResponse(important_news_fetch_key, 200, rss);
    updateWithEffects(&model, fx.takeMsg().?, fx);
    try std.testing.expect(!model.importantNewsRefreshing());
    try std.testing.expect(model.importantNewsHasRows());
    try std.testing.expectEqual(@as(usize, 1), try store.count());
    try std.testing.expectEqualStrings(
        "Proclamation No. 1382, s. 2026",
        model.newsNotices.?.items[0].title,
    );

    updateWithEffects(&model, .refresh_important_news, fx);
    try fx.feedResponse(important_news_fetch_key, 200, "not a feed");
    updateWithEffects(&model, fx.takeMsg().?, fx);
    try std.testing.expect(model.importantNewsErrorVisible());
    try std.testing.expect(model.importantNewsHasRows());
    try std.testing.expectEqual(@as(usize, 1), try store.count());
    update(&model, .dismiss_important_news_error);
    try std.testing.expect(!model.importantNewsErrorVisible());
}

test "important news display text is compact and UTF-8 safe" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try std.testing.expectEqualStrings(
        "Short notice",
        compactNewsText(arena, "Short notice", 150),
    );
    try std.testing.expectEqualStrings(
        "ab…",
        compactNewsText(arena, "abcdef", 5),
    );
    const unicode = compactNewsText(arena, "éééé", 5);
    try std.testing.expectEqualStrings("é…", unicode);
    try std.testing.expect(std.unicode.utf8ValidateSlice(unicode));
}

test "settings visibly binds the source-selected storage classification" {
    const model: Model = .{};
    try std.testing.expectEqualStrings(
        "development_only_plaintext_not_production",
        model.artifactStorageClassification(),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "{artifactStorageClassification}",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "Storage: {artifactStorageClassification}",
    ) == null);
}

test "compact header keeps navigation leftmost without duplicate branding" {
    const shell_source = @embedFile("components/shell.native");
    const header_start = std.mem.indexOf(
        u8,
        shell_source,
        "<template name=\"app-mobile-header\">",
    ).?;
    const header_tail = shell_source[header_start..];
    const header_end = std.mem.indexOf(u8, header_tail, "</template>").?;
    const header = header_tail[0 .. header_end + "</template>".len];

    try std.testing.expect(
        std.mem.indexOf(u8, header, "app_icon") == null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, header, "<image") == null,
    );
    const title_position = std.mem.indexOf(
        u8,
        header,
        "{currentPageTitle}",
    ).?;
    try std.testing.expect(
        std.mem.indexOf(u8, header, "icon=\"chevron-left\"").? <
            title_position,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, header, "icon=\"menu\"").? <
            title_position,
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "<image image=\"{app_icon}\" width=\"48\" height=\"48\"",
    ) != null);
}

test "profile setup uses flat field groups and native tabs with shell toasts" {
    const shell_source = @embedFile("components/shell.native");

    try std.testing.expectEqual(
        @as(usize, 1),
        std.mem.count(
            u8,
            app_markup,
            "label=\"Profile setup sections\"",
        ),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "<tabs label=\"Profile setup sections\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "<column gap=\"4\" label=\"Profile setup sections\">",
    ) == null);
    try std.testing.expectEqual(
        @as(usize, 0),
        std.mem.count(u8, app_markup, "<card size=\"sm\">"),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        std.mem.count(
            u8,
            app_markup,
            "<if test=\"{profileNoticeVisible}\">",
        ),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        shell_source,
        "<template name=\"profile-notice-toast\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "label=\"Dismiss tax profile notification\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        shell_source,
        "<template name=\"profile-calendar-export-toast\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "label=\"Dismiss calendar export notification\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "<badge variant=\"{profileNoticeTone}\">",
    ) == null);
    const notice_conditions = [_][]const u8{
        "<if test=\"{calendarNoticeVisible}\">",
    };
    for (notice_conditions) |condition| {
        const block_start = std.mem.indexOf(u8, app_markup, condition).?;
        const block_tail = app_markup[block_start..];
        const block_end = std.mem.indexOf(u8, block_tail, "</if>").?;
        const block = block_tail[0 .. block_end + "</if>".len];
        try std.testing.expect(
            std.mem.indexOf(u8, block, "<row cross=\"center\"") != null,
        );
    }
}

test "viewport classes cover phone compact tablet and desktop breakpoints" {
    try std.testing.expectEqual(ViewportClass.phone, viewportClassForWidth(390));
    try std.testing.expectEqual(ViewportClass.compact, viewportClassForWidth(767));
    try std.testing.expectEqual(ViewportClass.rail_narrow, viewportClassForWidth(768));
    try std.testing.expectEqual(ViewportClass.rail_narrow, viewportClassForWidth(899));
    try std.testing.expectEqual(ViewportClass.rail_regular, viewportClassForWidth(900));
    try std.testing.expectEqual(ViewportClass.rail_regular, viewportClassForWidth(1099));
    try std.testing.expectEqual(ViewportClass.rail_regular, viewportClassForWidth(1100));
    try std.testing.expectEqual(ViewportClass.rail_regular, viewportClassForWidth(1225));
    try std.testing.expectEqual(ViewportClass.rail_regular, viewportClassForWidth(1319));
    try std.testing.expectEqual(ViewportClass.desktop, viewportClassForWidth(1320));
    try std.testing.expectEqual(ViewportClass.desktop, viewportClassForWidth(1920));
}

test "effective dashboard width is monotonic across shell boundaries" {
    const widths = [_]f32{
        390,
        599,
        600,
        700,
        767,
        768,
        899,
        900,
        1099,
        1100,
        1225,
        1319,
        1320,
        1920,
    };
    var model = Model{};
    var previous: f32 = 0;
    for (widths) |width| {
        update(&model, .{ .viewport_width_changed = width });
        const current = model.effectiveDashboardWidth();
        try std.testing.expect(current >= previous);
        previous = current;
    }

    update(&model, .{ .viewport_width_changed = 767 });
    try std.testing.expect(@abs(model.effectiveDashboardWidth() - 648) < 0.01);
    update(&model, .{ .viewport_width_changed = 768 });
    try std.testing.expect(@abs(model.effectiveDashboardWidth() - 648) < 0.01);
    update(&model, .{ .viewport_width_changed = 1319 });
    try std.testing.expect(@abs(model.effectiveDashboardWidth() - 976) < 0.01);
    update(&model, .{ .viewport_width_changed = 1320 });
    try std.testing.expect(@abs(model.effectiveDashboardWidth() - 976) < 0.01);
}

test "taxpayer dashboard lane modes use effective width thresholds" {
    try std.testing.expectEqual(
        TaxpayerDashboardLaneMode.stacked,
        taxpayerDashboardLaneModeForWidth(739),
    );
    try std.testing.expectEqual(
        TaxpayerDashboardLaneMode.two_columns,
        taxpayerDashboardLaneModeForWidth(740),
    );
    try std.testing.expectEqual(
        TaxpayerDashboardLaneMode.two_columns,
        taxpayerDashboardLaneModeForWidth(973),
    );
    try std.testing.expectEqual(
        TaxpayerDashboardLaneMode.three_columns,
        taxpayerDashboardLaneModeForWidth(974),
    );

    var compact = Model{ .viewportClass = .compact, .viewportWidth = 700 };
    try std.testing.expect(compact.dashboardStackedLayout());
    update(&compact, .{ .viewport_width_changed = 900 });
    try std.testing.expect(compact.dashboardTwoColumnLayout());
    update(&compact, .{ .viewport_width_changed = 1225 });
    try std.testing.expect(compact.dashboardThreeColumnLayout());
}

test "dashboard calendar geometry stays bounded at representative widths" {
    var model = Model{};

    update(&model, .{ .viewport_width_changed = 390 });
    try std.testing.expect(model.globalCalendarHeaderStacked());
    try std.testing.expect(@abs(model.globalCalendarLaneWidth() - 358) < 0.01);
    try std.testing.expect(@abs(model.dashboardControlHeight() - 44) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormPickerWidth() - 358) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormOptionsHeight() - 352) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormMenuHeight() - 420) < 0.01);
    try std.testing.expect(@abs(model.profileCalendarFormPickerWidth() - 358) < 0.01);
    try std.testing.expect(@abs(model.profileCalendarYearPickerWidth() - 306) < 0.01);
    try std.testing.expect(!model.profileDeadlineTableLayout());
    try std.testing.expectEqual(@as(u16, 16), model.taxpayerDashboardPagePadding());

    update(&model, .{ .viewport_width_changed = 700 });
    try std.testing.expect(model.globalCalendarHeaderStacked());
    try std.testing.expect(@abs(model.globalCalendarLaneWidth() - 560) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormPickerWidth() - 560) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarDayHeight() - 56) < 0.01);
    try std.testing.expect(model.profileCalendarDayHeight() >= 44);
    try std.testing.expect(model.profileCalendarDayHeight() <= 72);
    try std.testing.expect(@abs(model.profileCalendarFormPickerWidth() - 294) < 0.01);
    try std.testing.expect(@abs(model.profileCalendarYearPickerWidth() - 294) < 0.01);
    try std.testing.expect(model.profileDeadlineTableLayout());
    try std.testing.expectEqual(@as(u16, 24), model.taxpayerDashboardPagePadding());

    update(&model, .{ .viewport_width_changed = 1225 });
    try std.testing.expect(@abs(model.effectiveDashboardWidth() - 976) < 0.01);
    try std.testing.expect(model.globalCalendarLaneWidth() >= 320);
    try std.testing.expect(model.globalCalendarLaneWidth() <= 560);
    try std.testing.expect(@abs(model.globalCalendarFormPickerWidth() - 180) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormRowHeight() - 36) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormOptionsHeight() - 288) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormMenuHeight() - 362) < 0.01);
    try std.testing.expect(@abs(model.profileCalendarFormPickerWidth() - 458) < 0.01);
    try std.testing.expect(@abs(model.profileCalendarYearPickerWidth() - 458) < 0.01);
    try std.testing.expect(!model.profileDeadlineTableLayout());

    update(&model, .{ .viewport_width_changed = 1920 });
    try std.testing.expect(@abs(model.globalCalendarLaneWidth() - 560) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarDayHeight() - 64) < 0.01);
    try std.testing.expect(@abs(model.profileCalendarLaneWidth() - 500) < 0.01);
    try std.testing.expect(model.profileDeadlineTableLayout());
    try std.testing.expect(model.profileCalendarDayHeight() >= 44);
    try std.testing.expect(model.profileCalendarDayHeight() <= 72);
    try std.testing.expect(@abs(model.profileCalendarFormPickerWidth() - 260) < 0.01);
    try std.testing.expect(@abs(model.profileCalendarYearPickerWidth() - 176) < 0.01);
    try std.testing.expectEqual(@as(u16, 32), model.taxpayerDashboardPagePadding());
}

test "taxpayer navigation selection is hidden on global routes" {
    var model = Model{};
    const global_pages = [_]Page{
        .global_dashboard,
        .tax_calendar,
        .settings,
        .import_data,
        .background_tasks,
        .screen_gallery,
    };
    for (global_pages) |page| {
        model.page = page;
        try std.testing.expect(!model.taxpayerNavigationSelectionVisible());
    }

    model.page = .taxpayer_dashboard;
    try std.testing.expect(model.taxpayerNavigationSelectionVisible());
    model.page = .form_1701q;
    try std.testing.expect(model.taxpayerNavigationSelectionVisible());
    model.page = .profile_setup;
    model.taxProfiles.editing_new = true;
    try std.testing.expect(!model.taxpayerNavigationSelectionVisible());
    model.taxProfiles.editing_new = false;
    try std.testing.expect(model.taxpayerNavigationSelectionVisible());
}

test "deadline count labels use singular only for one" {
    try std.testing.expectEqualStrings("deadlines", deadlineNoun(0));
    try std.testing.expectEqualStrings("deadline", deadlineNoun(1));
    try std.testing.expectEqualStrings("deadlines", deadlineNoun(2));
}

test "deadline marker tones follow the captured current date" {
    const today = try calendar_domain.Date.init(2026, 8, 1);

    try std.testing.expectEqual(
        CalendarMarkerTone.overdue,
        calendarMarkerTone(try today.addDays(-1), today),
    );
    try std.testing.expectEqual(
        CalendarMarkerTone.due_soon,
        calendarMarkerTone(today, today),
    );
    try std.testing.expectEqual(
        CalendarMarkerTone.due_soon,
        calendarMarkerTone(try today.addDays(1), today),
    );
    try std.testing.expectEqual(
        CalendarMarkerTone.approaching,
        calendarMarkerTone(try today.addDays(2), today),
    );
    try std.testing.expectEqual(
        CalendarMarkerTone.approaching,
        calendarMarkerTone(try today.addDays(7), today),
    );
    try std.testing.expectEqual(
        CalendarMarkerTone.normal,
        calendarMarkerTone(try today.addDays(8), today),
    );

    // Verify that the rule is based on civil-day distance, not day-of-month.
    const year_end = try calendar_domain.Date.init(2026, 12, 31);
    try std.testing.expectEqual(
        CalendarMarkerTone.due_soon,
        calendarMarkerTone(
            try calendar_domain.Date.init(2027, 1, 1),
            year_end,
        ),
    );
}

test "calendar today refresh timer keeps the captured date live" {
    const allocator = std.testing.allocator;
    const fx = try allocator.create(Effects);
    defer allocator.destroy(fx);
    fx.* = .{
        .allocator = allocator,
        .executor = .fake,
    };
    defer fx.deinit();

    startCalendarTodayRefreshTimer(fx);
    try std.testing.expectEqual(@as(usize, 1), fx.pendingTimerCount());
    const request = fx.pendingTimerAt(0).?;
    try std.testing.expectEqual(calendar_today_refresh_timer_key, request.key);
    try std.testing.expectEqual(
        calendar_today_refresh_interval_ms,
        request.interval_ms,
    );
    try std.testing.expectEqual(native_sdk.TimerMode.repeating, request.mode);

    var model = Model{
        .calendarToday = try calendar_domain.Date.init(2026, 12, 31),
    };
    const next_day = try calendar_domain.Date.init(2027, 1, 1);
    try std.testing.expect(updateCalendarToday(&model, next_day));
    try std.testing.expectEqual(next_day, model.calendarToday);
    try std.testing.expect(!updateCalendarToday(&model, next_day));
}

fn expectCalendarCellTone(
    cells: []const ProfileCalendarDayCell,
    day: u8,
    expected: CalendarMarkerTone,
) !void {
    for (cells) |cell| {
        if (cell.day != day) continue;
        try std.testing.expectEqual(expected == .closed, cell.closed());
        try std.testing.expectEqual(expected == .overdue, cell.overdue());
        try std.testing.expectEqual(expected == .due_soon, cell.dueSoon());
        try std.testing.expectEqual(
            expected == .approaching,
            cell.approaching(),
        );
        return;
    }
    return error.TestUnexpectedResult;
}

test "launch assessment refresh clears deadline readiness before guards" {
    var model = Model{};
    @memset(&model.profileDeadlineLaunchAssessmentsReady, true);

    refreshProfileFormLaunchAssessments(&model);

    for (model.profileDeadlineLaunchAssessmentsReady) |ready| {
        try std.testing.expect(!ready);
    }
}

test "global and taxpayer calendars project the same marker tone" {
    const allocator = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    var profile_fixture = try profile_store.Store.openMemory(allocator);
    defer profile_fixture.close();
    try addTestProfile(
        &profile_fixture,
        "marker-tone-profile",
        "Marker Tone Taxpayer",
        "123-456-789-000",
        .individual,
    );

    var model = Model{};
    try model.globalDashboard.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-marker-tone-test.ics",
        "20260801T010203Z",
        2026,
        8,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-marker-tone-test.ics",
        "20260801T010203Z",
        2026,
        8,
    );
    try model.taxProfiles.attach(
        allocator,
        &profile_fixture,
        "2026-08-01",
        2026,
    );

    var target: ?calendar_domain.Date = null;
    var target_form_code: ?[]const u8 = null;
    for (model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count]) |*deadline| {
        if (!model.profileCalendarIncludesDeadline(deadline)) continue;
        const form_index = formCatalogIndex(deadline.form_code) orelse continue;
        target = deadline.final_deadline;
        target_form_code = form_catalog.forms[form_index].code;
        break;
    }
    const deadline = target orelse return error.TestUnexpectedResult;
    const profile_id = model.taxProfiles.selectedProfileDomainId().?;
    try profile_fixture.replaceFormSet(profile_id.asSlice(), deadline.year, &.{.{
        .form_code = target_form_code.?,
        .form_revision = "calendar-test",
    }});
    model.calendar.selected_year = deadline.year;
    model.calendar.selected_month = deadline.month;
    refreshSelectedProfileFormSet(&model);
    model.globalDashboard.calendar.selected_year = deadline.year;
    model.globalDashboard.calendar.selected_month = deadline.month;
    model.profileCalendar.selected_year = deadline.year;
    model.profileCalendar.selected_month = deadline.month;
    const expectations = [_]struct {
        today_offset: i32,
        tone: CalendarMarkerTone,
    }{
        .{ .today_offset = 1, .tone = .overdue },
        .{ .today_offset = 0, .tone = .due_soon },
        .{ .today_offset = -3, .tone = .approaching },
        .{ .today_offset = -8, .tone = .normal },
    };
    for (expectations) |expectation| {
        model.calendarToday = try deadline.addDays(expectation.today_offset);
        try std.testing.expectEqual(
            expectation.tone,
            model.globalCalendarMarkerToneForDay(deadline.day),
        );
        try std.testing.expectEqual(
            expectation.tone,
            model.profileCalendarMarkerToneForDay(deadline.day),
        );
        try expectCalendarCellTone(
            model.globalCalendarDays(arena),
            deadline.day,
            expectation.tone,
        );
        try expectCalendarCellTone(
            model.profileCalendarDays(arena),
            deadline.day,
            expectation.tone,
        );
    }

    model.calendarToday = try deadline.addDays(-3);
    update(&model, .multi_select_clear_all);
    try std.testing.expectEqual(
        CalendarMarkerTone.normal,
        model.globalCalendarMarkerToneForDay(deadline.day),
    );
    try std.testing.expectEqual(
        CalendarMarkerTone.approaching,
        model.profileCalendarMarkerToneForDay(deadline.day),
    );
}

fn findWidgetByKind(widget: canvas.Widget, kind: canvas.WidgetKind) ?canvas.Widget {
    if (widget.kind == kind) return widget;
    for (widget.children) |child| {
        if (findWidgetByKind(child, kind)) |found| return found;
    }
    return null;
}

fn findWidgetByText(
    widget: canvas.Widget,
    kind: canvas.WidgetKind,
    text: []const u8,
) ?canvas.Widget {
    if (widget.kind == kind and std.mem.eql(u8, widget.text, text)) return widget;
    for (widget.children) |child| {
        if (findWidgetByText(child, kind, text)) |found| return found;
    }
    return null;
}

fn findWidgetBySemanticsLabel(
    widget: canvas.Widget,
    label: []const u8,
) ?canvas.Widget {
    if (std.mem.eql(u8, widget.semantics.label, label)) return widget;
    for (widget.children) |child| {
        if (findWidgetBySemanticsLabel(child, label)) |found| return found;
    }
    return null;
}

fn findWidgetBySemanticsPrefix(
    widget: canvas.Widget,
    prefix: []const u8,
) ?canvas.Widget {
    if (std.mem.startsWith(u8, widget.semantics.label, prefix)) return widget;
    for (widget.children) |child| {
        if (findWidgetBySemanticsPrefix(child, prefix)) |found| return found;
    }
    return null;
}

fn countWidgetTree(widget: canvas.Widget) usize {
    var count: usize = 1;
    for (widget.children) |child| count += countWidgetTree(child);
    return count;
}

fn writeReferenceProofShot(
    model: *const Model,
    width: usize,
    height: usize,
    path: []const u8,
) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
    var ui = canvas.Ui(Msg).init(arena);
    const tree = try ui.finalize(try view.build(&ui, model));
    const tokens = canvas.DesignTokens.theme(.{ .color_scheme = .light });
    const layout_nodes = try arena.alloc(canvas.WidgetLayoutNode, 8192);
    const bounds = geometry.RectF.init(
        0,
        0,
        @floatFromInt(width),
        @floatFromInt(height),
    );
    const layout = try canvas.layoutWidgetTreeWithTokens(
        tree.root,
        bounds,
        tokens,
        layout_nodes,
    );

    const commands = try arena.alloc(canvas.CanvasCommand, 65536);
    var builder = canvas.Builder.init(commands);
    try layout.emitDisplayList(&builder, tokens);
    const display_list = builder.displayList();
    const render_commands = try arena.alloc(canvas.RenderCommand, 65536);
    const plan = try (canvas.DisplayList{
        .commands = display_list.commands,
    }).renderPlan(render_commands);

    const pixels = try arena.alloc(u8, width * height * 4);
    @memset(pixels, 0);
    const surface = try canvas.ReferenceRenderSurface.init(width, height, pixels);
    try surface.renderPass(.{
        .commands = plan.commands,
        .surface_size = geometry.SizeF.init(
            @floatFromInt(width),
            @floatFromInt(height),
        ),
        .full_repaint = true,
    }, tokens.colors.background);

    const io = std.testing.io;
    try std.Io.Dir.cwd().createDirPath(
        io,
        std.fs.path.dirname(path) orelse ".",
    );
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var write_buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &write_buffer);
    try canvas.png.writeRgba8(
        &writer.interface,
        width,
        height,
        pixels,
    );
    try writer.interface.flush();
}

fn writeFormActivationProofShots(
    model: *Model,
    stage: []const u8,
) !void {
    const shots = [_]struct {
        name: []const u8,
        width: usize,
        height: usize,
    }{
        .{ .name = "desktop", .width = 1176, .height = 768 },
        .{ .name = "tablet", .width = 768, .height = 768 },
        .{ .name = "phone", .width = 408, .height = 800 },
    };
    for (shots) |shot| {
        update(model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        var path_buffer: [192]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-form-activation-shots/{s}-{s}.png",
            .{ stage, shot.name },
        );
        try writeReferenceProofShot(model, shot.width, shot.height, path);
    }
}

/// The states of the taxpayer setup workspace worth proving at every width.
const SetupWorkspaceStage = enum {
    profile,
    forms_configured,
    forms_year_open,
    forms_draft_choice,
    forms_draft_seeded,
    branch,
};

const setup_workspace_widths = [_]struct {
    name: []const u8,
    width: usize,
    height: usize,
}{
    .{ .name = "desktop", .width = 1400, .height = 900 },
    .{ .name = "tablet", .width = 768, .height = 900 },
    .{ .name = "phone", .width = 408, .height = 900 },
};

/// A taxpayer with one configured year and one that still needs setting up,
/// so both halves of the year workspace are reachable.
fn attachSetupWorkspaceFixture(
    model: *Model,
    allocator: std.mem.Allocator,
    store: *profile_store.Store,
) !void {
    const profile_id = "77777777777777777777777777777777";
    try addTestProfile(
        store,
        profile_id,
        "Maria Santos",
        "123-456-789-000",
        .sole_proprietor,
    );
    // The fixture seeds 2025-2027; leave 2025 unset so both a configured year
    // and a year that still needs setup are reachable.
    _ = try store.clearFormSet(profile_id, 2025);
    _ = try store.clearFormSet(profile_id, 2027);
    try store.replaceFormSet(profile_id, 2026, &.{
        .{ .form_code = "2551Q", .form_revision = "2018-01-ENCS" },
        .{ .form_code = "1701Q", .form_revision = "2018-01-ENCS" },
    });

    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    model.calendar.selected_year = 2026;
    try model.taxProfiles.attach(allocator, store, "2026-08-04", 2026);
    model.formProfiles.attach(allocator, store);
    canvas.icons.registerAppIcons(&app_icons);
    update(model, .{ .select_taxpayer = 0 });
    model.page = .profile_setup;
    model.taxProfiles.dismissNotice();
}

fn driveSetupWorkspaceStage(model: *Model, stage: SetupWorkspaceStage) void {
    switch (stage) {
        .profile => update(model, .show_profile_tax),
        .forms_configured => {
            update(model, .show_profile_tax_forms);
            update(model, .{ .profile_setup_select_year = 2026 });
        },
        .forms_year_open => {
            update(model, .show_profile_tax_forms);
            update(model, .profile_setup_toggle_year_picker);
        },
        .forms_draft_choice => {
            update(model, .profile_setup_close_year_picker);
            update(model, .{ .profile_setup_select_year = 2025 });
        },
        .forms_draft_seeded => {
            update(model, .{ .profile_setup_draft_seed = 2026 });
        },
        .branch => {
            // Leave the seeded draft behind first: an unsaved year
            // legitimately blocks leaving, which the previous stage
            // already demonstrates.
            update(model, .profile_setup_cancel_year_switch);
            update(model, .profile_forms_cancel);
            update(model, .{ .profile_setup_select_year = 2026 });
            update(model, .add_branch_profile);
        },
    }
}

/// Lays the current model out at one size and runs the SDK's layout audit.
///
/// The audit reports text painted past its frame, widgets escaping their clip
/// scope, overlapping siblings, and undersized hit targets — the defect
/// classes that only rendering used to catch. It reads geometry, so layout
/// must actually run: a finalized tree carries no frames.
fn expectSetupWorkspaceLayoutClean(
    model: *const Model,
    width: usize,
    height: usize,
    label: []const u8,
) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
    var ui = canvas.Ui(Msg).init(arena);
    const tree = try ui.finalize(try view.build(&ui, model));
    const tokens = canvas.DesignTokens.theme(.{ .color_scheme = .light });
    const nodes = try arena.alloc(
        canvas.WidgetLayoutNode,
        canvas.max_layout_audit_nodes,
    );
    const bounds = geometry.RectF.init(
        0,
        0,
        @floatFromInt(width),
        @floatFromInt(height),
    );
    const layout = canvas.layoutWidgetTreeWithTokens(
        tree.root,
        bounds,
        tokens,
        nodes,
    ) catch |err| {
        std.debug.print(
            "layout audit: {s} failed to lay out at {d}x{d}: {s}\n",
            .{ label, width, height, @errorName(err) },
        );
        return err;
    };
    // The audit only inspects the first `max_layout_audit_nodes`. A tree that
    // outgrows the buffer would be audited in part while reporting clean, so
    // fail loudly instead of quietly covering less.
    if (layout.nodes.len >= canvas.max_layout_audit_nodes) {
        std.debug.print(
            "layout audit: {s} at {d}x{d} has {d} nodes, at or past the {d} the audit can inspect\n",
            .{ label, width, height, layout.nodes.len, canvas.max_layout_audit_nodes },
        );
        return error.LayoutAuditTreeTooLarge;
    }

    var storage: [canvas.max_layout_audit_findings]canvas.LayoutAuditFinding =
        undefined;
    const issues = canvas.auditWidgetLayout(layout, bounds, tokens, &storage);
    if (issues.total == 0) return;

    std.debug.print(
        "layout audit: {d} finding(s) for {s} at {d}x{d}\n",
        .{ issues.total, label, width, height },
    );
    for (issues.findings) |finding| {
        var buffer: [1024]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        canvas.formatLayoutAuditFinding(layout, finding, &writer) catch {};
        std.debug.print("  - {s}\n", .{writer.buffered()});
    }
    return error.LayoutAuditFindings;
}

test "taxpayer setup workspace lays out cleanly at every width" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    var model = Model{ .page = .profile_setup };
    try attachSetupWorkspaceFixture(&model, allocator, &store);
    defer model.formProfiles.deinit();

    for (setup_workspace_widths) |viewport| {
        for (std.meta.tags(SetupWorkspaceStage)) |stage| {
            update(&model, .{
                .viewport_width_changed = @floatFromInt(viewport.width),
            });
            driveSetupWorkspaceStage(&model, stage);
            update(&model, .{
                .viewport_width_changed = @floatFromInt(viewport.width),
            });
            model.taxProfiles.dismissNotice();

            var label_buffer: [96]u8 = undefined;
            const label = try std.fmt.bufPrint(
                &label_buffer,
                "{s}/{s}",
                .{ @tagName(stage), viewport.name },
            );
            try expectSetupWorkspaceLayoutClean(
                &model,
                viewport.width,
                viewport.height,
                label,
            );
        }
        // Return to a saved taxpayer before the next width sweep.
        model.taxProfiles.cancelAddBranch();
        update(&model, .{ .select_taxpayer = 0 });
        model.page = .profile_setup;
    }
}

test "render taxpayer setup workspace proof shots when requested" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    if (std.c.getenv("SETUP_WORKSPACE_SHOTS") == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    var model = Model{ .page = .profile_setup };
    try attachSetupWorkspaceFixture(&model, allocator, &store);
    defer model.formProfiles.deinit();

    for (setup_workspace_widths) |shot| {
        for (std.meta.tags(SetupWorkspaceStage)) |stage| {
            update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
            driveSetupWorkspaceStage(&model, stage);
            update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
            model.taxProfiles.dismissNotice();
            var path_buffer: [192]u8 = undefined;
            const path = try std.fmt.bufPrint(
                &path_buffer,
                "/tmp/ebirforms-setup-shots/{s}-{s}.png",
                .{ @tagName(stage), shot.name },
            );
            try writeReferenceProofShot(&model, shot.width, shot.height, path);
        }
        // Return to a saved taxpayer before the next width sweep.
        model.taxProfiles.cancelAddBranch();
        update(&model, .{ .select_taxpayer = 0 });
        model.page = .profile_setup;
    }
}

test "render tax form filter menu proof shots when requested" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    if (std.c.getenv("FILTER_MENU_SHOTS") == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addThreeTestProfiles(&store);

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    try model.taxProfiles.attach(allocator, &store, "2026-08-02", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    update(&model, .{ .select_taxpayer = 0 });
    model.dashboardSection = .forms;
    model.taxProfiles.dismissNotice();
    canvas.icons.registerAppIcons(&app_icons);

    const shots = [_]struct {
        name: []const u8,
        width: usize,
        height: usize,
    }{
        .{ .name = "phone", .width = 408, .height = 800 },
        .{ .name = "tablet", .width = 768, .height = 768 },
        .{ .name = "desktop", .width = 1176, .height = 768 },
        .{ .name = "desktop-short", .width = 1176, .height = 500 },
    };
    for (shots) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        model.libraryFilter.filter_picker_visible = false;
        var path_buffer: [160]u8 = undefined;
        const closed_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-filter-menu-shots/{s}-closed.png",
            .{shot.name},
        );
        try writeReferenceProofShot(
            &model,
            shot.width,
            shot.height,
            closed_path,
        );

        model.libraryFilter.filter_picker_visible = true;
        const open_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-filter-menu-shots/{s}-open.png",
            .{shot.name},
        );
        try writeReferenceProofShot(
            &model,
            shot.width,
            shot.height,
            open_path,
        );
    }

    // Capture a single-month selection first, then a multi-month selection.
    // The period tiles are the interaction itself, so these renders make the
    // selected-state and the compact closed summary auditable at each step.
    update(&model, .{ .profile_forms_toggle_month = 1 });
    model.libraryFilter.filter_picker_visible = true;
    for (shots[0..3]) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        model.libraryFilter.filter_picker_visible = true;
        var path_buffer: [160]u8 = undefined;
        const selected_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-filter-menu-shots/{s}-jan-open.png",
            .{shot.name},
        );
        try writeReferenceProofShot(
            &model,
            shot.width,
            shot.height,
            selected_path,
        );
    }
    update(&model, .{ .profile_forms_toggle_month = 2 });
    update(&model, .{ .profile_forms_toggle_month = 3 });
    model.libraryFilter.filter_picker_visible = true;
    for (shots[0..3]) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        model.libraryFilter.filter_picker_visible = true;
        var path_buffer: [160]u8 = undefined;
        const selected_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-filter-menu-shots/{s}-jan-feb-mar-open.png",
            .{shot.name},
        );
        try writeReferenceProofShot(
            &model,
            shot.width,
            shot.height,
            selected_path,
        );
    }

    update(&model, .profile_forms_reset_filters);
    update(&model, .{ .profile_forms_toggle_month = 1 });
    update(&model, .profile_forms_toggle_quarter_2);
    model.libraryFilter.filter_picker_visible = true;
    for (shots[0..3]) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        model.libraryFilter.filter_picker_visible = true;
        var path_buffer: [160]u8 = undefined;
        const selected_open_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-filter-menu-shots/{s}-selected-open.png",
            .{shot.name},
        );
        try writeReferenceProofShot(
            &model,
            shot.width,
            shot.height,
            selected_open_path,
        );
    }
    model.libraryFilter.filter_picker_visible = false;
    for (shots[0..3]) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        var path_buffer: [160]u8 = undefined;
        const filtered_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-filter-menu-shots/{s}-jan-q2.png",
            .{shot.name},
        );
        try writeReferenceProofShot(
            &model,
            shot.width,
            shot.height,
            filtered_path,
        );
    }

    update(&model, .profile_forms_reset_filters);
    update(&model, .profile_forms_toggle_quarter_1);
    update(&model, .profile_forms_toggle_quarter_2);
    update(&model, .{
        .profile_forms_search_input = .{ .insert_text = "2551Q" },
    });
    for (shots[0..3]) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        var path_buffer: [160]u8 = undefined;
        const filtered_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-filter-menu-shots/{s}-q1-q2.png",
            .{shot.name},
        );
        try writeReferenceProofShot(
            &model,
            shot.width,
            shot.height,
            filtered_path,
        );
    }

    update(&model, .{ .profile_forms_search_input = .clear });
    update(&model, .{
        .profile_forms_search_input = .{ .insert_text = "no-such-form" },
    });
    for (shots[0..3]) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        var path_buffer: [160]u8 = undefined;
        const empty_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-filter-menu-shots/{s}-empty.png",
            .{shot.name},
        );
        try writeReferenceProofShot(
            &model,
            shot.width,
            shot.height,
            empty_path,
        );
    }

    // Period-card geometry proof set. These captures deliberately focus on
    // one monthly form and one quarterly form so every filtered cardinality
    // can be inspected without other cards masking the grid footprint.
    const period_shots = [_]struct {
        name: []const u8,
        width: usize,
        height: usize,
    }{
        // Keep the requested desktop/tablet/phone widths, with a taller
        // canvas so all twelve monthly slots remain visible in one proof.
        .{ .name = "desktop-full", .width = 1176, .height = 1120 },
        .{ .name = "tablet-full", .width = 768, .height = 1120 },
        .{ .name = "phone-full", .width = 408, .height = 1120 },
    };
    update(&model, .profile_forms_reset_filters);
    update(&model, .{
        .profile_forms_search_input = .{ .insert_text = "1601C" },
    });
    model.libraryFilter.filter_picker_visible = false;
    for (period_shots) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        model.libraryFilter.filter_picker_visible = false;
        var path_buffer: [192]u8 = undefined;
        const all_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-period-card-shots/monthly-all-{s}.png",
            .{shot.name},
        );
        try writeReferenceProofShot(&model, shot.width, shot.height, all_path);
    }

    var month_index: u8 = 1;
    while (month_index <= 12) : (month_index += 1) {
        // The message carries the month, so no tag-per-month mapping is needed.
        update(&model, .{ .profile_forms_toggle_month = month_index });
        for (period_shots) |shot| {
            update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
            model.libraryFilter.filter_picker_visible = false;
            var path_buffer: [192]u8 = undefined;
            const filtered_path = try std.fmt.bufPrint(
                &path_buffer,
                "/tmp/ebirforms-period-card-shots/monthly-{d:0>2}-{s}.png",
                .{ month_index, shot.name },
            );
            try writeReferenceProofShot(
                &model,
                shot.width,
                shot.height,
                filtered_path,
            );
        }
    }

    update(&model, .profile_forms_reset_filters);
    update(&model, .{ .profile_forms_search_input = .clear });
    update(&model, .{
        .profile_forms_search_input = .{ .insert_text = "2551Q" },
    });
    for (period_shots) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        model.libraryFilter.filter_picker_visible = false;
        var path_buffer: [192]u8 = undefined;
        const all_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-period-card-shots/quarterly-all-{s}.png",
            .{shot.name},
        );
        try writeReferenceProofShot(&model, shot.width, shot.height, all_path);
    }

    var quarter_index: u8 = 1;
    while (quarter_index <= 4) : (quarter_index += 1) {
        const toggle: Msg = switch (quarter_index) {
            1 => .profile_forms_toggle_quarter_1,
            2 => .profile_forms_toggle_quarter_2,
            3 => .profile_forms_toggle_quarter_3,
            4 => .profile_forms_toggle_quarter_4,
            else => unreachable,
        };
        update(&model, toggle);
        for (period_shots) |shot| {
            update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
            model.libraryFilter.filter_picker_visible = false;
            var path_buffer: [192]u8 = undefined;
            const filtered_path = try std.fmt.bufPrint(
                &path_buffer,
                "/tmp/ebirforms-period-card-shots/quarterly-{d:0>2}-{s}.png",
                .{ quarter_index, shot.name },
            );
            try writeReferenceProofShot(
                &model,
                shot.width,
                shot.height,
                filtered_path,
            );
        }
    }

    // Annual cards have one full-width filing action rather than a period
    // matrix. Keep a dedicated visual proof beside the monthly/quarterly
    // fixtures so the card contract is reviewable at every breakpoint.
    update(&model, .profile_forms_reset_filters);
    update(&model, .{ .profile_forms_search_input = .clear });
    update(&model, .{
        .profile_forms_search_input = .{ .insert_text = "1702RT" },
    });
    for (period_shots) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        model.libraryFilter.filter_picker_visible = false;
        var path_buffer: [192]u8 = undefined;
        const annual_path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-period-card-shots/annual-all-{s}.png",
            .{shot.name},
        );
        try writeReferenceProofShot(&model, shot.width, shot.height, annual_path);
    }
}

test "render opened form workspace proof shots when requested" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    if (std.c.getenv("FORM_WORKSPACE_SHOTS") == null) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    const effective = try profile_model.EffectivePeriod.init(
        try profile_model.Date.parseIso("2026-01-01"),
        null,
    );
    const activities = [_]profile_model.BusinessActivity{.{
        .id = try profile_model.BusinessActivityId.parse("activity-retail"),
        .line_of_business = try profile_fields.LineOfBusiness.parse("Retail"),
        .atc = try profile_fields.Atc.parse("PT010"),
        .effective = effective,
    }};
    try persistTestSoleProprietorRevision(
        &store,
        "44444444444444444444444444444444",
        "open-form-filer-r1",
        1,
        "2026-01-01",
        "Open Form Fixture",
        "444-444-444-000",
        &activities,
    );

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    try model.taxProfiles.attach(allocator, &store, "2026-08-02", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();

    const profile_id = model.taxProfiles.selectedProfileId().?;
    try store.replaceFormSet(profile_id, 2026, &.{
        .{ .form_code = "2551Q", .form_revision = "2018-01-ENCS" },
        .{ .form_code = "1601C", .form_revision = "2018-01-ENCS" },
    });
    try std.testing.expect(model.taxProfiles.loadFormsForYear(2026));
    refreshSelectedProfileFormSet(&model);

    const form_index = formCatalogIndex("2551Q").?;
    try std.testing.expectEqual(
        form_ui.LaunchStatus.ready_new,
        model.profileFormLaunchAssessments[form_index].status,
    );

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
    var library_ui = canvas.Ui(Msg).init(arena);
    const library_tree = try library_ui.finalize(
        try view.build(&library_ui, &model),
    );
    const quarter_one = findWidgetBySemanticsPrefix(
        library_tree.root,
        "BIR Form 2551Q, Q1, tax year 2026",
    ).?;
    update(&model, library_tree.msgForPointer(quarter_one.id, .up).?);
    try std.testing.expectEqual(Page.form_2551q, model.page);
    model.taxProfiles.dismissNotice();

    const shots = [_]struct {
        name: []const u8,
        width: usize,
        height: usize,
    }{
        .{ .name = "desktop", .width = 1176, .height = 768 },
        .{ .name = "phone", .width = 408, .height = 800 },
    };
    for (shots) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        var path_buffer: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-open-form-shots/2551q-{s}.png",
            .{shot.name},
        );
        try writeReferenceProofShot(&model, shot.width, shot.height, path);
    }

    // Re-enter the library and open a monthly tile. This is the companion
    // proof that the selected month is passed into the editor as its filing
    // period, rather than being inferred from the global calendar context.
    navigate(&model, .taxpayer_dashboard);
    model.dashboardSection = .forms;
    model.taxProfiles.dismissNotice();
    var monthly_arena_state = std.heap.ArenaAllocator.init(allocator);
    defer monthly_arena_state.deinit();
    const monthly_arena = monthly_arena_state.allocator();
    var monthly_view = try canvas.MarkupView(Model, Msg).init(
        monthly_arena,
        app_markup,
    );
    var monthly_ui = canvas.Ui(Msg).init(monthly_arena);
    const monthly_tree = try monthly_ui.finalize(
        try monthly_view.build(&monthly_ui, &model),
    );
    const january = findWidgetBySemanticsPrefix(
        monthly_tree.root,
        "BIR Form 1601C, Jan, tax year 2026",
    ).?;
    update(&model, monthly_tree.msgForPointer(january.id, .up).?);
    try std.testing.expectEqual(Page.form_1601_c, model.page);
    model.taxProfiles.dismissNotice();
    for (shots) |shot| {
        update(&model, .{ .viewport_width_changed = @floatFromInt(shot.width) });
        var path_buffer: [160]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &path_buffer,
            "/tmp/ebirforms-open-form-shots/1601c-jan-{s}.png",
            .{shot.name},
        );
        try writeReferenceProofShot(&model, shot.width, shot.height, path);
    }
}

test "render form activation flow proof shots when requested" {
    if (comptime !@import("builtin").link_libc) return error.SkipZigTest;
    if (std.c.getenv("FORM_ACTIVATION_SHOTS") == null) {
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addThreeTestProfiles(&store);

    // Start from an explicitly empty Forms Set so the screenshots show the
    // real distinction between inactive, staged, and saved active forms.
    for ([_][]const u8{
        "11111111111111111111111111111111",
        "22222222222222222222222222222222",
        "33333333333333333333333333333333",
    }) |profile_id| {
        try store.replaceFormSet(profile_id, 2026, &.{});
    }

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    try model.taxProfiles.attach(allocator, &store, "2026-08-02", 2026);
    model.formProfiles.attach(allocator, &store);
    defer model.formProfiles.deinit();
    update(&model, .{ .select_taxpayer = 0 });
    model.dashboardSection = .forms;
    model.taxProfiles.dismissNotice();
    canvas.icons.registerAppIcons(&app_icons);

    try writeFormActivationProofShots(&model, "01-before");
    update(&model, .{ .viewport_width_changed = 1176 });

    // Enter the yearly Forms Set editor through Profile Settings → Tax Forms.
    update(&model, .show_profile_setup);
    update(&model, .show_profile_tax_forms);
    update(&model, .{ .profile_setup_select_year = 2026 });
    model.taxProfiles.applyFormsQuery(.{ .insert_text = "2551Q" });
    try writeFormActivationProofShots(&model, "02-manage");
    update(&model, .{ .viewport_width_changed = 1176 });

    // Select 2551Q, but do not save it yet. The staged state is intentionally
    // visible before the authoritative Forms Set changes.
    {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
        var ui = canvas.Ui(Msg).init(arena);
        const tree = try ui.finalize(try view.build(&ui, &model));
        const form_checkbox = findWidgetBySemanticsLabel(
            tree.root,
            "Select BIR Form 2551Q",
        ).?;
        update(&model, tree.msgFor(form_checkbox.id, .change).?);
    }
    try writeFormActivationProofShots(&model, "03-activate-staged");
    update(&model, .{ .viewport_width_changed = 1176 });

    // Save commits the staged selection and makes 2551Q active for 2026.
    {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
        var ui = canvas.Ui(Msg).init(arena);
        const tree = try ui.finalize(try view.build(&ui, &model));
        const save = findWidgetByText(tree.root, .button, "Save").?;
        update(&model, tree.msgForPointer(save.id, .up).?);
    }
    model.taxProfiles.dismissNotice();
    try writeFormActivationProofShots(&model, "04-active-saved");
    update(&model, .{ .viewport_width_changed = 1176 });

    // Stage the reverse operation from the active library.
    {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
        var ui = canvas.Ui(Msg).init(arena);
        const tree = try ui.finalize(try view.build(&ui, &model));
        const manage = findWidgetByText(tree.root, .button, "Manage Forms").?;
        update(&model, tree.msgForPointer(manage.id, .up).?);
    }
    model.taxProfiles.applyFormsQuery(.{ .insert_text = "2551Q" });
    update(&model, .{ .viewport_width_changed = 1176 });
    {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
        var ui = canvas.Ui(Msg).init(arena);
        const tree = try ui.finalize(try view.build(&ui, &model));
        const form_checkbox = findWidgetBySemanticsLabel(
            tree.root,
            "Deselect BIR Form 2551Q",
        ).?;
        update(&model, tree.msgFor(form_checkbox.id, .change).?);
    }
    try writeFormActivationProofShots(&model, "05-inactivate-staged");
    update(&model, .{ .viewport_width_changed = 1176 });

    {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
        var ui = canvas.Ui(Msg).init(arena);
        const tree = try ui.finalize(try view.build(&ui, &model));
        const save = findWidgetByText(tree.root, .button, "Save").?;
        update(&model, tree.msgForPointer(save.id, .up).?);
    }
    model.taxProfiles.dismissNotice();
    try writeFormActivationProofShots(&model, "06-inactive-saved");
}

test "tax form library filter dispatches through compiled markup" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addThreeTestProfiles(&store);

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
        .viewportClass = .phone,
        .viewportWidth = 408,
    };
    try model.taxProfiles.attach(allocator, &store, "2026-08-02", 2026);
    update(&model, .{ .select_taxpayer = 0 });
    model.dashboardSection = .forms;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);

    var closed_ui = canvas.Ui(Msg).init(arena);
    const closed_root = view.build(&closed_ui, &model) catch |err| {
        std.debug.print(
            "library markup build failed at {s}:{d}:{d}: {s}\n",
            .{
                view.diagnostic.path,
                view.diagnostic.line,
                view.diagnostic.column,
                view.diagnostic.message,
            },
        );
        return err;
    };
    const closed_tree = try closed_ui.finalize(closed_root);
    const closed_trigger = findWidgetBySemanticsLabel(
        closed_tree.root,
        "Filter active forms by cadence, month, or quarter",
    ).?;
    try std.testing.expectEqual(canvas.WidgetKind.select, closed_trigger.kind);
    try std.testing.expectEqualStrings("All active filings", closed_trigger.text);

    update(&model, closed_tree.msgForPointer(closed_trigger.id, .up).?);
    try std.testing.expect(model.profileFormsFilterPickerOpen());

    var open_ui = canvas.Ui(Msg).init(arena);
    const open_tree = try open_ui.finalize(try view.build(&open_ui, &model));
    const january = findWidgetBySemanticsLabel(open_tree.root, "January").?;
    const quarter_two = findWidgetBySemanticsLabel(open_tree.root, "Quarter 2").?;
    try std.testing.expectEqual(canvas.WidgetKind.button, january.kind);
    try std.testing.expectEqual(canvas.WidgetKind.button, quarter_two.kind);
    try std.testing.expect(
        findWidgetBySemanticsLabel(open_tree.root, "All months") == null,
    );
    try std.testing.expect(
        findWidgetByText(open_tree.root, .button, "Reset filters") != null,
    );
    try std.testing.expect(
        findWidgetByText(open_tree.root, .button, "Done") == null,
    );
    try std.testing.expect(
        findWidgetByText(open_tree.root, .checkbox, "Selected") == null,
    );
    try std.testing.expect(!january.state.selected);
    try std.testing.expect(!quarter_two.state.selected);

    update(&model, open_tree.msgForPointer(january.id, .up).?);
    try std.testing.expect(model.profileFormsFilterPickerOpen());

    var toggled_ui = canvas.Ui(Msg).init(arena);
    const toggled_tree = try toggled_ui.finalize(try view.build(&toggled_ui, &model));
    const toggled_trigger = findWidgetBySemanticsLabel(
        toggled_tree.root,
        "Filter active forms: Jan. Change cadence, month, or quarter",
    ).?;
    try std.testing.expectEqualStrings("Jan", toggled_trigger.text);
    try std.testing.expect(
        findWidgetBySemanticsLabel(toggled_tree.root, "January").?.state.selected,
    );
    try std.testing.expect(model.profileFormsCadenceMonthlySelected());

    const toggled_quarter_two = findWidgetBySemanticsLabel(
        toggled_tree.root,
        "Quarter 2",
    ).?;
    update(
        &model,
        toggled_tree.msgForPointer(toggled_quarter_two.id, .up).?,
    );
    var combined_ui = canvas.Ui(Msg).init(arena);
    const combined_tree = try combined_ui.finalize(
        try view.build(&combined_ui, &model),
    );
    try std.testing.expect(
        findWidgetBySemanticsLabel(combined_tree.root, "January").?.state.selected,
    );
    try std.testing.expect(
        findWidgetBySemanticsLabel(combined_tree.root, "Quarter 2").?.state.selected,
    );
    try std.testing.expect(model.profileFormsCadenceMonthlySelected());
    try std.testing.expect(model.profileFormsCadenceQuarterlySelected());
    const combined_trigger = findWidgetBySemanticsLabel(
        combined_tree.root,
        "Filter active forms: Jan · Q2. Change cadence, month, or quarter",
    ).?;
    try std.testing.expectEqualStrings("Jan · Q2", combined_trigger.text);

    const menu = findWidgetByKind(combined_tree.root, .dropdown_menu).?;
    update(&model, combined_tree.msgForDismiss(menu.id).?);
    try std.testing.expect(!model.profileFormsFilterPickerOpen());

    update(&model, .{
        .profile_forms_search_input = .{ .insert_text = "no-such-form" },
    });
    var empty_ui = canvas.Ui(Msg).init(arena);
    const empty_tree = try empty_ui.finalize(try view.build(&empty_ui, &model));
    try std.testing.expect(
        findWidgetByText(
            empty_tree.root,
            .text,
            "No forms match these filters",
        ) != null,
    );
    const reset = findWidgetByText(empty_tree.root, .button, "Reset filters").?;
    update(&model, empty_tree.msgForPointer(reset.id, .up).?);
    try std.testing.expectEqualStrings("", model.taxProfiles.formsQuery());
    try std.testing.expect(!model.profileFormRowsEmpty(arena));
}

test "tax form library keeps browse and manage trees within widget budget" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addThreeTestProfiles(&store);

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
        .viewportWidth = 1176,
    };
    try model.taxProfiles.attach(allocator, &store, "2026-08-02", 2026);
    update(&model, .{ .select_taxpayer = 0 });
    model.dashboardSection = .forms;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);

    var browse_ui = canvas.Ui(Msg).init(arena);
    const browse_tree = try browse_ui.finalize(try view.build(&browse_ui, &model));
    try std.testing.expect(countWidgetTree(browse_tree.root) < 1024);
    try std.testing.expect(
        findWidgetByText(browse_tree.root, .button, "Open Form") == null,
    );
    const next = findWidgetBySemanticsLabel(browse_tree.root, "Next forms").?;
    update(&model, browse_tree.msgForPointer(next.id, .up).?);
    try std.testing.expectEqual(@as(usize, 12), model.libraryFilter.page_offset);

    var second_page_ui = canvas.Ui(Msg).init(arena);
    const second_page_tree = try second_page_ui.finalize(
        try view.build(&second_page_ui, &model),
    );
    try std.testing.expect(countWidgetTree(second_page_tree.root) < 1024);
    try std.testing.expect(
        !findWidgetBySemanticsLabel(
            second_page_tree.root,
            "Previous forms",
        ).?.state.disabled,
    );

    model.page = .profile_setup;
    update(&model, .show_profile_tax_forms);
    update(&model, .{ .profile_setup_select_year = 2026 });
    resetProfileFormsPage(&model);
    update(&model, .profile_forms_manage);
    var manage_ui = canvas.Ui(Msg).init(arena);
    const manage_tree = try manage_ui.finalize(try view.build(&manage_ui, &model));
    try std.testing.expect(countWidgetTree(manage_tree.root) < 1024);
    try std.testing.expect(
        findWidgetByText(manage_tree.root, .button, "Open Form") == null,
    );
    try std.testing.expect(
        findWidgetBySemanticsPrefix(
            manage_tree.root,
            "BIR Form 0605,",
        ) == null,
    );

    // Individual form toggles must use the Native checkbox toggle event. A
    // checkbox's visual state can change without updating the model when it
    // is bound to the generic input-change event, which leaves Save disabled.
    try std.testing.expectEqual(
        @as(usize, 1),
        std.mem.count(u8, app_markup, "on-toggle=\"toggle_profile_form:{form.id}\""),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        std.mem.count(u8, app_markup, "on-change=\"toggle_profile_form:{form.id}\""),
    );
    const form_checkbox = findWidgetBySemanticsPrefix(
        manage_tree.root,
        "Select BIR Form 0605",
    ) orelse findWidgetBySemanticsPrefix(
        manage_tree.root,
        "Deselect BIR Form 0605",
    ) orelse return error.TestUnexpectedResult;
    const staged_before_toggle = model.taxProfiles.stagedFormCount();
    update(&model, manage_tree.msgForPointer(form_checkbox.id, .up).?);
    try std.testing.expect(
        model.taxProfiles.stagedFormCount() != staged_before_toggle,
    );
}

test "global calendar picker dispatches open search toggle and dismiss interactions" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{};
    var view = try canvas.MarkupView(Model, Msg).init(
        arena,
        multi_select_component_fixture,
    );

    var closed_ui = canvas.Ui(Msg).init(arena);
    const closed_tree = try closed_ui.finalize(try view.build(&closed_ui, &model));
    const closed_trigger = findWidgetByKind(closed_tree.root, .select).?;
    try std.testing.expectEqualStrings("54 selected", closed_trigger.text);

    const open_message = closed_tree.msgForPointer(closed_trigger.id, .up).?;
    update(&model, open_message);
    update(&model, open_message);
    try std.testing.expect(model.globalDashboard.forms.isOpen());

    var open_ui = canvas.Ui(Msg).init(arena);
    const open_tree = try open_ui.finalize(try view.build(&open_ui, &model));
    const open_trigger = findWidgetByKind(open_tree.root, .select).?;
    const open_search = findWidgetByKind(open_tree.root, .search_field).?;
    const first_option = findWidgetByText(open_tree.root, .menu_item, "0605").?;
    const second_option = findWidgetByText(open_tree.root, .menu_item, "1905").?;
    try std.testing.expectEqualStrings("54 selected", open_trigger.text);
    try std.testing.expectEqualStrings("", open_search.text);
    try std.testing.expect(open_search.autofocus);
    try std.testing.expect(first_option.state.selected);
    try std.testing.expect(second_option.state.selected);

    update(&model, open_tree.msgForPointer(first_option.id, .up).?);
    var partial_ui = canvas.Ui(Msg).init(arena);
    const partial_tree = try partial_ui.finalize(try view.build(&partial_ui, &model));
    try std.testing.expect(
        !findWidgetByText(partial_tree.root, .menu_item, "0605").?.state.selected,
    );
    try std.testing.expect(
        findWidgetByText(partial_tree.root, .menu_item, "1905").?.state.selected,
    );

    update(
        &model,
        partial_tree.msgForPointer(
            findWidgetByText(partial_tree.root, .menu_item, "0605").?.id,
            .up,
        ).?,
    );
    try std.testing.expectEqual(
        @as(usize, calendar_form_codes.len),
        model.globalDashboard.forms.selectedCount(),
    );

    update(
        &model,
        open_tree.msgForTextEdit(
            open_search.id,
            .{ .insert_text = "0619E" },
        ).?,
    );

    var filtered_ui = canvas.Ui(Msg).init(arena);
    const filtered_tree = try filtered_ui.finalize(try view.build(&filtered_ui, &model));
    const matching_option = findWidgetByText(
        filtered_tree.root,
        .menu_item,
        "0619E",
    ).?;
    try std.testing.expect(matching_option.state.selected);
    update(
        &model,
        filtered_tree.msgForPointer(matching_option.id, .up).?,
    );
    try std.testing.expectEqual(
        @as(usize, calendar_form_codes.len - 1),
        model.globalDashboard.forms.selectedCount(),
    );

    var toggled_ui = canvas.Ui(Msg).init(arena);
    const toggled_tree = try toggled_ui.finalize(try view.build(&toggled_ui, &model));
    const toggled_option = findWidgetByText(
        toggled_tree.root,
        .menu_item,
        "0619E",
    ).?;
    try std.testing.expect(!toggled_option.state.selected);
    try std.testing.expect(
        findWidgetByText(
            toggled_tree.root,
            .button,
            "Select All",
        ) != null,
    );
    try std.testing.expect(
        findWidgetByText(
            toggled_tree.root,
            .button,
            "Clear All",
        ) != null,
    );

    const menu = findWidgetByKind(toggled_tree.root, .dropdown_menu).?;
    update(&model, toggled_tree.msgForDismiss(menu.id).?);
    try std.testing.expect(!model.globalDashboard.forms.isOpen());

    var dismissed_ui = canvas.Ui(Msg).init(arena);
    const dismissed_tree = try dismissed_ui.finalize(try view.build(&dismissed_ui, &model));
    const dismissed_trigger = findWidgetByKind(dismissed_tree.root, .select).?;
    try std.testing.expectEqualStrings("53 selected", dismissed_trigger.text);
}

test "global calendar picker supports an explicit empty selection" {
    var model = Model{};
    update(&model, .multi_select_open);
    update(&model, .multi_select_clear_all);
    try std.testing.expect(!model.globalCalendarFormPickerDisabled());
    try std.testing.expect(model.globalCalendarFormPickerOpen());
    try std.testing.expectEqual(
        @as(usize, 0),
        model.globalDashboard.forms.selectedCount(),
    );
}

test "global form selection filters dashboard deadlines and markers only" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        std.testing.allocator,
    );
    defer calendar_store.close();
    var model = Model{};
    try model.calendar.attach(
        std.testing.allocator,
        &calendar_store,
        "/tmp/ebirforms-profile-filter-test.ics",
        "20260729T010203Z",
        2026,
        7,
    );
    try model.globalDashboard.calendar.attach(
        std.testing.allocator,
        &calendar_store,
        "/tmp/ebirforms-profile-filter-test.ics",
        "20260729T010203Z",
        2026,
        7,
    );
    var global_tax_calendar_count: usize = 0;
    for (model.calendar.deadlines[0..model.calendar.deadline_count]) |row| {
        if (row.final_deadline.year == model.calendar.selected_year and
            row.final_deadline.month == model.calendar.selected_month)
        {
            global_tax_calendar_count += 1;
        }
    }
    const global_dashboard_count = model.globalDeadlines(arena).len;
    try std.testing.expectEqual(
        global_tax_calendar_count,
        global_dashboard_count,
    );
    update(&model, .multi_select_clear_all);

    try std.testing.expectEqual(
        @as(usize, 0),
        model.globalDashboard.forms.selectedCount(),
    );
    try std.testing.expect(!model.globalCalendarHasDeadlines());
    try std.testing.expectEqual(
        @as(usize, 0),
        model.globalDeadlines(arena).len,
    );
    try std.testing.expectEqual(
        global_tax_calendar_count,
        global_tax_calendar_count,
    );
    update(&model, .multi_select_open);
    update(
        &model,
        .{ .multi_select_query_changed = .{ .insert_text = "2551Q" } },
    );
    update(&model, .multi_select_select_all_filtered);

    const deadlines = model.globalDeadlines(arena);
    try std.testing.expectEqual(
        @as(usize, 1),
        model.globalDashboard.forms.selectedCount(),
    );
    try std.testing.expect(deadlines.len > 0);
    for (deadlines) |deadline| {
        try std.testing.expectEqualStrings("2551Q", deadline.form_code);
    }
    const deadline_day = deadlines[0].final_deadline.day;
    var found_marker = false;
    for (model.globalCalendarDays(arena)) |cell| {
        if (cell.day != deadline_day) continue;
        try std.testing.expect(cell.hasDeadlines());
        found_marker = true;
        break;
    }
    try std.testing.expect(found_marker);
}

test "profile RDO and taxpayer type scope never changes global deadlines" {
    const allocator = std.testing.allocator;
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    _ = try calendar_store.putOverride(.{
        .title = "RDO 040 individual extension",
        .source = "Official scoped fixture",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-06-15",
        .affected_form_codes = &.{"1701Q"},
        .regions = &.{"040"},
        .taxpayer_types = &.{"individual"},
    });

    var profile_fixture = try profile_store.Store.openMemory(allocator);
    defer profile_fixture.close();
    try addTestProfileWithRdo(
        &profile_fixture,
        "scope-alpha",
        "Alpha Individual",
        "111-222-333-000",
        .individual,
        "040",
    );
    try addTestProfileWithRdo(
        &profile_fixture,
        "scope-beta",
        "Beta Corporation",
        "444-555-666-000",
        .corporation,
        "041",
    );

    var model = Model{};
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-scope-wiring-test.ics",
        "20260729T010203Z",
        2026,
        5,
    );
    try model.globalDashboard.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-scope-wiring-test.ics",
        "20260729T010203Z",
        2026,
        5,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-scope-wiring-test.ics",
        "20260729T010203Z",
        2026,
        5,
    );
    try model.taxProfiles.attach(
        allocator,
        &profile_fixture,
        "2026-05-01",
        2026,
    );

    const original = try calendar_domain.Date.init(2026, 5, 15);
    const adjusted = try calendar_domain.Date.init(2026, 6, 15);
    var global_date: ?calendar_domain.Date = null;
    for (model.globalDashboard.calendar.deadlines[0..model.globalDashboard.calendar.deadline_count]) |row| {
        if (std.mem.eql(u8, row.form_code, "1701Q") and
            calendar_domain.Date.compare(row.original_deadline, original) == .eq)
        {
            global_date = row.final_deadline;
            break;
        }
    }
    try std.testing.expectEqual(original, global_date.?);

    update(&model, .{
        .select_taxpayer = profileSlotNamed(&model, "Alpha Individual").?,
    });
    var alpha_date: ?calendar_domain.Date = null;
    for (model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count]) |row| {
        if (std.mem.eql(u8, row.form_code, "1701Q") and
            calendar_domain.Date.compare(row.original_deadline, original) == .eq)
        {
            alpha_date = row.final_deadline;
            break;
        }
    }
    try std.testing.expectEqual(adjusted, alpha_date.?);
    const scoped_ics = try model.profileCalendar.buildProfileIcs(
        allocator,
        "20260729T010203Z",
        .{
            .key = model.selectedTaxpayerCalendarKey(),
            .name = model.selectedTaxpayerName(),
            .form_scope = .catalog_fallback,
        },
    );
    defer allocator.free(scoped_ics);
    try std.testing.expect(std.mem.indexOf(
        u8,
        scoped_ics,
        "DTSTART;VALUE=DATE:20260615",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        scoped_ics,
        "Source: Official scoped fixture",
    ) != null);

    update(&model, .{
        .select_taxpayer = profileSlotNamed(&model, "Beta Corporation").?,
    });
    var beta_date: ?calendar_domain.Date = null;
    for (model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count]) |row| {
        if (std.mem.eql(u8, row.form_code, "1701Q") and
            calendar_domain.Date.compare(row.original_deadline, original) == .eq)
        {
            beta_date = row.final_deadline;
            break;
        }
    }
    try std.testing.expectEqual(original, beta_date.?);

    // Profile selection is a projection only; the global schedule remains
    // unaffected before and after both scoped recomputations.
    for (model.globalDashboard.calendar.deadlines[0..model.globalDashboard.calendar.deadline_count]) |row| {
        if (std.mem.eql(u8, row.form_code, "1701Q") and
            calendar_domain.Date.compare(row.original_deadline, original) == .eq)
        {
            try std.testing.expectEqual(original, row.final_deadline);
            return;
        }
    }
    return error.TestUnexpectedResult;
}

test "global calendar day widget toggles exact-date rows and heading" {
    const allocator = std.testing.allocator;
    var store = try calendar_ui.persistence.Store.openMemory(allocator);
    defer store.close();

    var model = Model{ .page = .global_dashboard };
    try model.globalDashboard.calendar.attach(
        allocator,
        &store,
        "/tmp/ebirforms-global-day-widget-test.ics",
        "20260729T010203Z",
        2026,
        7,
    );

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const month_rows = model.globalDeadlines(arena);
    try std.testing.expect(month_rows.len > 0);
    const selected_date = month_rows[0].final_deadline;

    var day_label: ?[]const u8 = null;
    for (model.globalCalendarDays(arena)) |cell| {
        if (cell.day != selected_date.day) continue;
        day_label = cell.actionLabel(arena);
        break;
    }
    const action_label = day_label orelse return error.TestUnexpectedResult;
    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
    var initial_ui = canvas.Ui(Msg).init(arena);
    const initial_tree = try initial_ui.finalize(
        try view.build(&initial_ui, &model),
    );
    const day_widget = findWidgetBySemanticsLabel(
        initial_tree.root,
        action_label,
    ).?;
    update(&model, initial_tree.msgForPointer(day_widget.id, .up).?);

    try std.testing.expectEqual(selected_date.day, model.globalDashboard.selectedDay().?);
    const exact_rows = model.globalDeadlines(arena);
    try std.testing.expect(exact_rows.len > 0);
    for (exact_rows) |row| {
        try std.testing.expect(std.meta.eql(row.final_deadline, selected_date));
    }
    var day_number_buffer: [4]u8 = undefined;
    const day_number = try std.fmt.bufPrint(
        &day_number_buffer,
        "{d}",
        .{selected_date.day},
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        model.globalCalendarDeadlineHeading(arena),
        day_number,
    ) != null);

    var selected_ui = canvas.Ui(Msg).init(arena);
    const selected_tree = try selected_ui.finalize(
        try view.build(&selected_ui, &model),
    );
    const selected_widget = findWidgetBySemanticsLabel(
        selected_tree.root,
        action_label,
    ).?;
    try std.testing.expect(selected_widget.state.selected);
    update(&model, selected_tree.msgForPointer(selected_widget.id, .up).?);
    try std.testing.expect(model.globalDashboard.selectedDay() == null);
}

test "the sidebar keeps a taxpayer's registrations together, head office first" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    // Deliberately created out of order, and named so that sorting by name
    // alone would interleave the two taxpayers.
    try addTestProfile(
        &store,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "Zeta Branch Two",
        "123-456-789-002",
        .individual,
    );
    try addTestProfile(
        &store,
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "Alpha Other Taxpayer",
        "987-654-321-000",
        .individual,
    );
    try addTestProfile(
        &store,
        "cccccccccccccccccccccccccccccccc",
        "Mid Head Office",
        "123-456-789-000",
        .individual,
    );

    var model = Model{};
    try model.taxProfiles.attach(allocator, &store, "2026-01-01", 2026);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const rows = model.visibleProfileRows(arena);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    // One taxpayer's registrations are adjacent with the head office leading,
    // and the unrelated taxpayer does not land between them.
    try std.testing.expectEqualStrings("Mid Head Office", rows[0].nameLabel());
    try std.testing.expectEqualStrings("Zeta Branch Two", rows[1].nameLabel());
    try std.testing.expectEqualStrings("Alpha Other Taxpayer", rows[2].nameLabel());
    try std.testing.expect(!rows[0].isBranch());
    try std.testing.expect(rows[1].isBranch());

    // Ordering is presentation only: each row still selects its own taxpayer.
    for (rows) |row| {
        const source = model.taxProfiles.rowAt(row.slot).?;
        try std.testing.expectEqualStrings(source.idLabel(), row.idLabel());
    }
}

test "missing taxpayer details are listed once with the forms that need them" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();

    var model = Model{};
    model.calendar.selected_year = 2026;
    try model.taxProfiles.attach(allocator, &store, "2026-01-01", 2026);
    model.taxProfiles.tin.set("123-456-789-00000");
    model.taxProfiles.rdo.set("040");
    model.taxProfiles.natural_person_classification = .pure_compensation;
    model.taxProfiles.display_name.set("Missing Details Taxpayer");
    model.taxProfiles.registered_address.set("Quezon City");
    model.taxProfiles.effective_from.set("2026-01-01");
    try std.testing.expect(model.taxProfiles.save());

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Nothing is active yet, so nothing may be demanded.
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileMissingFactRows(arena).len,
    );

    // 2551Q requires ZIP code, contact number, and email address.
    try store.replaceFormSet(
        model.taxProfiles.selectedProfileId().?,
        2026,
        &.{.{ .form_code = "2551Q", .form_revision = "2018-01-ENCS" }},
    );
    try model.taxProfiles.refreshCalendarFormSet(2026);

    const rows = model.profileMissingFactRows(arena);
    try std.testing.expect(rows.len >= 3);
    var saw_email = false;
    for (rows) |row| {
        // Every listed detail names at least one active form that needs it,
        // so the user can see the fix is shared rather than per-form.
        try std.testing.expect(row.usedByLabel().len != 0);
        if (std.mem.eql(u8, row.fieldLabel(), "Registered email address")) {
            saw_email = true;
            try std.testing.expectEqualStrings("2551Q", row.usedByLabel());
        }
    }
    try std.testing.expect(saw_email);

    // Filling the shared editor once clears it for every form that uses it.
    model.taxProfiles.email.set("taxpayer@example.ph");
    for (model.profileMissingFactRows(arena)) |row| {
        try std.testing.expect(
            !std.mem.eql(u8, row.fieldLabel(), "Registered email address"),
        );
    }
}

test "profile calendar year picker is configured and future bounded" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    const profile_id = "55555555555555555555555555555555";
    try addTestProfile(
        &store,
        profile_id,
        "Year Picker Taxpayer",
        "555-555-555-000",
        .individual,
    );
    try store.replaceFormSet(profile_id, 2020, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});

    var model = Model{ .page = .taxpayer_dashboard };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(
        allocator,
        &store,
        "2026-08-04",
        2026,
    );
    update(&model, .{ .select_taxpayer = 0 });
    model.profileCalendar.selected_year = 2026;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const recent = model.profileCalendarYearOptions(arena);
    try std.testing.expectEqual(@as(usize, 2), recent.len);
    try std.testing.expectEqual(@as(i32, 2026), recent[0].year);
    try std.testing.expectEqual(@as(i32, 2025), recent[1].year);

    update(&model, .{
        .profile_calendar_year_query = .{ .insert_text = "2020" },
    });
    const filtered = model.profileCalendarYearOptions(arena);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqual(@as(i32, 2020), filtered[0].year);

    // The yearly setup combobox opens on the current year, distinguishes
    // configured years from ones that still need setup, and never lists a year
    // that has not started.
    const setup_options = model.profileSetupYearOptions(arena);
    try std.testing.expect(setup_options.len >= 3);
    try std.testing.expectEqual(@as(i32, 2026), setup_options[0].year);
    try std.testing.expect(setup_options[0].configured);
    var saw_unconfigured_2024 = false;
    var saw_configured_2020 = false;
    for (setup_options) |option| {
        try std.testing.expect(option.year <= 2026);
        try std.testing.expect(option.year >= profile_ui.minimum_setup_year);
        if (option.year == 2024) {
            saw_unconfigured_2024 = true;
            try std.testing.expect(option.missing());
        }
        if (option.year == 2020) {
            saw_configured_2020 = true;
            try std.testing.expect(option.configured);
        }
    }
    try std.testing.expect(saw_unconfigured_2024);
    try std.testing.expect(saw_configured_2020);

    // A future year is explained rather than offered, so no create action for
    // it can exist anywhere in the list.
    update(&model, .{
        .profile_setup_year_query = .{ .insert_text = "2027" },
    });
    try std.testing.expect(model.profileSetupYearHelperVisible());
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileSetupYearOptions(arena).len,
    );

    // The filter holds digits only, however the bytes arrived.
    update(&model, .profile_setup_close_year_picker);
    update(&model, .{
        .profile_setup_year_query = .{ .insert_text = "20a4" },
    });
    try std.testing.expectEqualStrings(
        "204",
        model.profileSetupYearQueryValue(),
    );
}

test "profile calendar form picker searches only active forms and stays session local" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    const profile_id = "profile-calendar-picker";
    try addTestProfile(
        &store,
        profile_id,
        "Picker Taxpayer",
        "456-123-789-000",
        .individual,
    );
    try store.replaceFormSet(profile_id, 2026, &.{
        .{
            .form_code = "2551Q",
            .form_revision = "2018-01-ENCS",
        },
        .{
            .form_code = "1905",
            .form_revision = "calendar-only",
        },
    });
    try store.replaceFormSet(profile_id, 2025, &.{.{
        .form_code = "1701Q",
        .form_revision = "2018-01-ENCS",
    }});

    var model = Model{};
    model.calendar.selected_year = 2026;
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.taxProfiles.attach(allocator, &store, "2026-08-04", 2026);
    refreshSelectedProfileFormSet(&model);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings(
        "2 forms",
        model.profileCalendarFormSelectionText(arena),
    );
    const options = model.visibleProfileCalendarFormOptions(arena);
    try std.testing.expectEqual(@as(usize, 2), options.len);
    for (options) |option| try std.testing.expect(option.selected);

    const global_selection_count =
        model.globalDashboard.forms.selectedCount();
    update(&model, .profile_calendar_forms_clear_all);
    try std.testing.expectEqualStrings(
        "0 forms",
        model.profileCalendarFormSelectionText(arena),
    );
    update(&model, .{
        .profile_calendar_forms_query_changed = .{
            .insert_text = "quarterly percentage",
        },
    });
    const filtered = model.visibleProfileCalendarFormOptions(arena);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("2551Q", filtered[0].code);
    update(&model, .profile_calendar_forms_select_all_filtered);
    try std.testing.expectEqualStrings(
        "1 form",
        model.profileCalendarFormSelectionText(arena),
    );
    try std.testing.expect(
        model.profileCalendarForms.isSelected(formCatalogIndex("2551Q").?),
    );
    try std.testing.expect(
        !model.profileCalendarForms.isSelected(formCatalogIndex("1905").?),
    );

    // View filtering does not rewrite the persisted Forms Set or the global
    // calendar's independent selection state.
    try std.testing.expect(model.taxProfiles.formAvailable(2026, "2551Q"));
    try std.testing.expect(model.taxProfiles.formAvailable(2026, "1905"));
    try std.testing.expectEqual(
        global_selection_count,
        model.globalDashboard.forms.selectedCount(),
    );
    update(&model, .profile_calendar_forms_close);
    try std.testing.expectEqualStrings("", model.profileCalendarFormQuery());

    update(&model, .profile_calendar_forms_open);
    try std.testing.expect(model.profileCalendarFormPickerOpen());
    update(&model, .profile_calendar_toggle_year_picker);
    try std.testing.expect(!model.profileCalendarFormPickerOpen());
    try std.testing.expect(model.profileCalendarYearPickerOpen());
    update(&model, .profile_calendar_forms_open);
    try std.testing.expect(model.profileCalendarFormPickerOpen());
    try std.testing.expect(!model.profileCalendarYearPickerOpen());
    update(&model, .profile_calendar_forms_close);

    update(&model, .{ .profile_calendar_select_year = 2025 });
    try std.testing.expectEqualStrings(
        "1 form",
        model.profileCalendarFormSelectionText(arena),
    );
    try std.testing.expect(
        model.profileCalendarForms.isSelected(formCatalogIndex("1701Q").?),
    );
    try std.testing.expect(
        !model.profileCalendarForms.isSelected(formCatalogIndex("2551Q").?),
    );
    update(&model, .profile_calendar_forms_clear_all);
    update(&model, .calendar_next_month);
    update(&model, .{ .profile_calendar_select_day = 1 });
    try std.testing.expectEqualStrings(
        "0 forms",
        model.profileCalendarFormSelectionText(arena),
    );

    update(&model, .{ .profile_calendar_select_year = 2026 });
    try std.testing.expectEqualStrings(
        "2 forms",
        model.profileCalendarFormSelectionText(arena),
    );
}

test "midyear Forms Set interval agrees across cards launch calendar and export" {
    const allocator = std.testing.allocator;
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    var profile_fixture = try profile_store.Store.openMemory(allocator);
    defer profile_fixture.close();

    const profile_id = "midyear-availability-profile";
    try addTestProfile(
        &profile_fixture,
        profile_id,
        "Midyear Percentage Taxpayer",
        "654-321-987-000",
        .individual,
    );
    try addTestCompleteBusinessRegistration(
        &profile_fixture,
        profile_id,
        "2026-01-01".*,
    );
    // The saved whole-year decision is explicitly empty. 2551Q becomes
    // active only for filing periods ending on or after July 1.
    try profile_fixture.replaceFormSet(profile_id, 2026, &.{});
    try profile_fixture.createFormSetInterval(.{
        .id = "midyear-2551q-from-july",
        .profile_id = profile_id,
        .tax_year = 2026,
        .effective_from = "2026-07-01",
        .forms = &.{.{
            .form_code = "2551Q",
            .form_revision = "2018-01-ENCS",
        }},
    });

    var model = Model{
        .page = .taxpayer_dashboard,
        .dashboardSection = .forms,
    };
    model.calendarToday = try calendar_domain.Date.init(2026, 8, 4);
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-midyear-availability.ics",
        "20260804T010203Z",
        2026,
        8,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-midyear-availability.ics",
        "20260804T010203Z",
        2026,
        8,
    );
    try model.taxProfiles.attach(
        allocator,
        &profile_fixture,
        "2026-08-04",
        2026,
    );
    model.formProfiles.attach(allocator, &profile_fixture);
    defer model.formProfiles.deinit();
    refreshSelectedProfileFormSet(&model);

    const index = formCatalogIndex("2551Q").?;
    try std.testing.expectEqual(@as(i32, 2026), model.profileFormAvailabilityYear);
    try std.testing.expect(!model.profilePeriodAvailability[index][0]);
    try std.testing.expect(!model.profilePeriodAvailability[index][1]);
    try std.testing.expect(model.profilePeriodAvailability[index][2]);
    try std.testing.expect(model.profilePeriodAvailability[index][3]);
    try std.testing.expect(model.profileFormAnyPeriodActive[index]);

    // Dispatch rechecks the same persisted resolver. Q2 stays on the library;
    // Q3 opens the editor because its quarter-end is inside the active range.
    update(&model, .{ .open_library_period = index * 16 + 1 });
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    update(&model, .{ .open_library_period = index * 16 + 2 });
    try std.testing.expectEqual(Page.form_2551q, model.page);

    var calendar_included = [_]bool{false} ** 4;
    for (
        model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count],
    ) |*deadline| {
        if (!formCodesEquivalent(deadline.form_code, "2551Q")) continue;
        const period = switch (deadline.period) {
            .quarterly => |value| value,
            else => continue,
        };
        if (period.taxable_year != 2026) continue;
        if (model.profileCalendarIncludesDeadline(deadline)) {
            calendar_included[period.quarter - 1] = true;
        }
    }
    // This calendar instance is scoped to deadlines occurring in calendar
    // year 2026. The 2026 Q4 return is active (asserted above), but its filing
    // deadline occurs in January 2027 and therefore belongs to the next
    // calendar view. Of the deadlines present here, only Q3 is in the
    // midyear-active interval.
    try std.testing.expectEqualSlices(
        bool,
        &[_]bool{ false, false, true, false },
        &calendar_included,
    );

    const filtered = model.profileCalendarForExport();
    var export_included = [_]bool{false} ** 4;
    for (filtered.deadlines[0..filtered.deadline_count]) |deadline| {
        if (!formCodesEquivalent(deadline.form_code, "2551Q")) continue;
        const period = switch (deadline.period) {
            .quarterly => |value| value,
            else => continue,
        };
        if (period.taxable_year != 2026) continue;
        export_included[period.quarter - 1] = true;
    }
    try std.testing.expectEqualSlices(
        bool,
        &calendar_included,
        &export_included,
    );
}

test "profile calendar keeps prior taxable year obligations visible" {
    const allocator = std.testing.allocator;
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    var profile_store_fixture = try profile_store.Store.openMemory(allocator);
    defer profile_store_fixture.close();

    const profile_id = "prior-year-calendar-profile";
    try addTestProfile(
        &profile_store_fixture,
        profile_id,
        "Prior Year Taxpayer",
        "654-321-987-000",
        .individual,
    );
    try profile_store_fixture.replaceFormSet(profile_id, 2026, &.{});
    try profile_store_fixture.replaceFormSet(profile_id, 2025, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});

    var model = Model{};
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-prior-year-calendar-test.ics",
        "20260101T010203Z",
        2026,
        1,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-prior-year-calendar-test.ics",
        "20260101T010203Z",
        2026,
        1,
    );
    try model.taxProfiles.attach(
        allocator,
        &profile_store_fixture,
        "2026-01-01",
        2026,
    );
    refreshSelectedProfileFormSet(&model);

    var prior_deadline: ?calendar_ui.DeadlineRow = null;
    for (
        model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count],
    ) |deadline| {
        if (!formCodesEquivalent(deadline.form_code, "2551Q") or
            deadline.final_deadline.year != 2026 or
            deadline.period.taxableYear() != @as(?i32, 2025)) continue;
        prior_deadline = deadline;
        break;
    }
    try std.testing.expect(prior_deadline != null);
    const form_index = formCatalogIndex("2551Q").?;
    try std.testing.expect(model.profileCalendarFormActive(form_index));
    try std.testing.expect(model.profileCalendarForms.isSelected(form_index));
    try std.testing.expect(model.profileCalendarViewIncludesDeadline(
        &prior_deadline.?,
    ));
    model.calendar.selected_month = prior_deadline.?.final_deadline.month;
    model.profileCalendar.selected_month = prior_deadline.?.final_deadline.month;
    model.calendarToday = try prior_deadline.?.final_deadline.addDays(-1);
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    try std.testing.expect(model.profileMonthlyDeadlineRows(
        arena_state.allocator(),
    ).len != 0);
}

test "profile deadline identity accepts canonical and legacy typed periods" {
    const due = try calendar_domain.Date.init(2026, 2, 10);
    var deadline = calendar_ui.DeadlineRow{
        .id = 1,
        .rule_id = "monthly-test",
        .form_code = "0619-E",
        .display_form_no = "0619-E",
        .form_name = "Monthly Withholding Tax Remittance",
        .description = "",
        .period = .{ .monthly = .{ .taxable_year = 2026, .month = 1 } },
        .original_deadline = due,
        .final_deadline = due,
        .status = .normal,
    };
    var draft = profile_ui.DraftSummaryRow{ .slot = 0 };
    try draft.form_code.set("0619E");
    try draft.period_key.set("2026-M01");
    try std.testing.expect(formCodesEquivalent(
        draft.formCode(),
        deadline.form_code,
    ));
    const expected_month = profileDeadlineFilingPeriod(&deadline).?;
    const canonical_month = try form_period.FilingPeriod.parseKey(
        .monthly,
        draft.periodKey(),
    );
    try std.testing.expect(canonical_month.eql(expected_month));
    try std.testing.expect(draftMatchesDeadline(&draft, &deadline));
    try draft.period_key.set("2026-01");
    try std.testing.expect(draftMatchesDeadline(&draft, &deadline));
    try draft.period_key.set("2026-02");
    try std.testing.expect(!draftMatchesDeadline(&draft, &deadline));

    deadline.form_code = "2551Q";
    deadline.display_form_no = "2551Q";
    deadline.period = .{ .quarterly = .{ .taxable_year = 2026, .quarter = 1 } };
    try draft.form_code.set("2551Q");
    try draft.period_key.set("2026-Q1");
    try std.testing.expect(draftMatchesDeadline(&draft, &deadline));

    deadline.form_code = "1701";
    deadline.display_form_no = "1701";
    deadline.period = .{ .annual = .{ .taxable_year = 2026 } };
    try draft.form_code.set("1701");
    try draft.period_key.set("2026-A");
    try std.testing.expect(draftMatchesDeadline(&draft, &deadline));
}

test "profile deadline compact labels and independent statuses are stable" {
    const due = try calendar_domain.Date.init(2026, 7, 27);
    const deadline = calendar_ui.DeadlineRow{
        .id = 1,
        .rule_id = "quarterly-test",
        .form_code = "2551Q",
        .display_form_no = "2551Q",
        .form_name = "Quarterly Percentage Tax Return",
        .description = "",
        .period = .{ .quarterly = .{ .taxable_year = 2026, .quarter = 2 } },
        .original_deadline = try calendar_domain.Date.init(2026, 7, 25),
        .final_deadline = due,
        .status = .weekend_adjusted,
    };
    const row = ProfileCalendarDeadlineRow{
        .id = deadline.id,
        .deadline = deadline,
        .filing_state = .sent,
        .timing = .overdue,
        .actions = profileDeadlineActionsFor(.sent, .none, false),
    };
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("2551Q Q2", row.compactLabel(arena));
    try std.testing.expectEqualStrings("Due Jul 27, 2026", row.dueLabel(arena));
    try std.testing.expect(row.adjustmentVisible());
    try std.testing.expectEqualStrings(
        "View deadline adjustment details",
        row.adjustmentActionLabel(),
    );
    try std.testing.expectEqualStrings("Sent", row.filingStatus());
    try std.testing.expectEqualStrings("Overdue", row.timingLabel());
    try std.testing.expect(row.timingVisible());
    try std.testing.expectEqualStrings(
        "Check Confirmation",
        row.primaryActionLabel(),
    );
    try std.testing.expect(row.multipleActions());
    try std.testing.expectEqualStrings(
        "Print Form",
        row.secondaryActionOneLabel(),
    );
}

test "profile deadline action matrix is lifecycle and capability derived" {
    const new_actions = profileDeadlineActionsFor(.new, .none, false);
    try std.testing.expectEqual(@as(u8, 1), new_actions.count);
    try std.testing.expectEqual(ProfileDeadlineAction.start, new_actions.at(0));

    const editing_actions = profileDeadlineActionsFor(.draft, .editing, false);
    try std.testing.expectEqual(
        ProfileDeadlineAction.continue_draft,
        editing_actions.at(0),
    );
    const prepared_actions = profileDeadlineActionsFor(.draft, .prepared, false);
    try std.testing.expectEqual(ProfileDeadlineAction.submit, prepared_actions.at(0));

    const queued_actions = profileDeadlineActionsFor(.queued, .none, false);
    try std.testing.expectEqual(@as(u8, 2), queued_actions.count);
    try std.testing.expectEqual(
        ProfileDeadlineAction.review_submission,
        queued_actions.at(0),
    );
    try std.testing.expectEqual(ProfileDeadlineAction.print, queued_actions.at(1));

    const sent_actions = profileDeadlineActionsFor(.sent, .none, false);
    try std.testing.expectEqual(
        ProfileDeadlineAction.check_confirmation,
        sent_actions.at(0),
    );
    try std.testing.expectEqual(ProfileDeadlineAction.print, sent_actions.at(1));

    const confirmed_actions = profileDeadlineActionsFor(.confirmed, .none, false);
    try std.testing.expectEqual(
        ProfileDeadlineAction.upload_receipt,
        confirmed_actions.at(0),
    );
    try std.testing.expectEqual(ProfileDeadlineAction.print, confirmed_actions.at(1));
    const provider_actions = profileDeadlineActionsFor(.confirmed, .none, true);
    try std.testing.expectEqual(ProfileDeadlineAction.pay_online, provider_actions.at(0));
    try std.testing.expectEqual(ProfileDeadlineAction.print, provider_actions.at(1));

    const paid_actions = profileDeadlineActionsFor(.paid, .none, false);
    try std.testing.expectEqual(@as(u8, 1), paid_actions.count);
    try std.testing.expectEqual(ProfileDeadlineAction.print, paid_actions.at(0));
    try std.testing.expectEqual(
        @as(u8, 0),
        profileDeadlineActionsFor(.calendar_only, .none, false).count,
    );
    try std.testing.expectEqual(
        @as(u8, 0),
        profileDeadlineActionsFor(.unknown, .none, false).count,
    );
    try std.testing.expect(ProfileFilingState.new.needsAction());
    try std.testing.expect(ProfileFilingState.draft.needsAction());
    try std.testing.expect(ProfileFilingState.queued.needsAction());
    try std.testing.expect(ProfileFilingState.sent.needsAction());
    try std.testing.expect(ProfileFilingState.confirmed.needsAction());
    try std.testing.expect(!ProfileFilingState.paid.needsAction());
    try std.testing.expect(!ProfileFilingState.calendar_only.needsAction());
    try std.testing.expect(!ProfileFilingState.unknown.needsAction());

    for (std.meta.tags(ProfileDeadlineAction)) |action| {
        if (action == .none) continue;
        const dispatch_id = profileDeadlineActionDispatchId(91, 37, action);
        const decoded = decodeProfileDeadlineActionDispatch(dispatch_id).?;
        try std.testing.expectEqual(@as(u32, 91), decoded.projection_generation);
        try std.testing.expectEqual(@as(u64, 37), decoded.deadline_id);
        try std.testing.expectEqual(action, decoded.action);
    }
    try std.testing.expect(
        profileDeadlineMenuId(91, 37, .deadlines) !=
            profileDeadlineMenuId(91, 37, .action_required),
    );
    try std.testing.expect(
        profileDeadlineMenuId(91, 37, .action_required) !=
            profileDeadlineMenuId(91, 37, .overdue),
    );
}

test "profile deadline adjustment dialog explains original and final dates" {
    var model = Model{};
    const deadline = calendar_ui.DeadlineRow{
        .id = 9,
        .rule_id = "adjusted-dialog-test",
        .form_code = "2551Q",
        .display_form_no = "2551Q",
        .form_name = "Quarterly Percentage Tax Return",
        .description = "",
        .period = .{ .quarterly = .{ .taxable_year = 2026, .quarter = 2 } },
        .original_deadline = try calendar_domain.Date.init(2026, 7, 25),
        .final_deadline = try calendar_domain.Date.init(2026, 7, 27),
        .status = .weekend_adjusted,
    };
    model.profileCalendar.deadlines[0] = deadline;
    model.profileCalendar.deadline_count = 1;
    showProfileDeadlineAdjustment(&model, deadline.id);
    try std.testing.expect(model.profileDeadlineDialogOpen());
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const summary = model.profileDeadlineDialogBody(arena_state.allocator());
    try std.testing.expect(std.mem.indexOf(u8, summary, "Jul 25, 2026") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "Jul 27, 2026") != null);
    update(&model, .profile_deadline_close_dialog);
    try std.testing.expect(!model.profileDeadlineDialogOpen());
}

test "profile calendar lanes use injected date and persisted filer lifecycle" {
    const allocator = std.testing.allocator;
    var calendar_store = try calendar_ui.persistence.Store.openMemory(
        allocator,
    );
    defer calendar_store.close();
    var profile_store_fixture = try profile_store.Store.openMemory(allocator);
    defer profile_store_fixture.close();

    const profile_id = "lane-calendar-profile";
    try addTestProfile(
        &profile_store_fixture,
        profile_id,
        "Lane Calendar Taxpayer",
        "456-789-123-000",
        .individual,
    );
    try addTestCompleteBusinessRegistration(
        &profile_store_fixture,
        profile_id,
        "2026-01-01".*,
    );
    var model = Model{};
    try model.calendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-profile-lanes-test.ics",
        "20260729T010203Z",
        2026,
        7,
    );
    try model.profileCalendar.attach(
        allocator,
        &calendar_store,
        "/tmp/ebirforms-profile-lanes-test.ics",
        "20260729T010203Z",
        2026,
        7,
    );
    try model.taxProfiles.attach(
        allocator,
        &profile_store_fixture,
        "2026-07-01",
        2026,
    );
    model.formProfiles.attach(allocator, &profile_store_fixture);
    defer model.formProfiles.deinit();
    try std.testing.expect(model.profileCalendarIncludesForm("1701Q"));
    try profile_store_fixture.replaceFormSet(profile_id, 2026, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});
    try profile_store_fixture.replaceFormSet(profile_id, 2025, &.{});
    refreshSelectedProfileFormSet(&model);
    try std.testing.expect(model.profileCalendarIncludesForm("2551Q"));
    try std.testing.expect(!model.profileCalendarIncludesForm("1701Q"));

    var matching_deadline: ?calendar_ui.DeadlineRow = null;
    for (model.calendar.deadlines[0..model.calendar.deadline_count]) |row| {
        if (!std.mem.eql(u8, row.form_code, "2551Q")) continue;
        switch (row.period) {
            .quarterly => |period| if (period.taxable_year == 2026 and
                period.quarter == 2)
            {
                matching_deadline = row;
                break;
            },
            else => {},
        }
    }
    model.calendar.selected_month = matching_deadline.?.final_deadline.month;
    model.profileCalendar.selected_year =
        matching_deadline.?.final_deadline.year;
    model.profileCalendar.selected_month =
        matching_deadline.?.final_deadline.month;
    model.calendarToday = matching_deadline.?.final_deadline;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // A New obligation belongs to exactly one workflow lane: Action Required
    // through its due date, then Overdue. The monthly schedule remains visible
    // independently, and an unsaved New item does not become cross-month
    // backlog.
    try std.testing.expectEqual(
        @as(usize, 0),
        model.taxProfiles.draftSummaries().len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileMonthlyDeadlineRows(arena).len,
    );
    const new_action_rows = model.profileActionRequiredRows(arena);
    try std.testing.expectEqual(@as(usize, 1), new_action_rows.len);
    try std.testing.expectEqualStrings("New", new_action_rows[0].filingStatus());
    try std.testing.expect(new_action_rows[0].primaryActionVisible());
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileOverdueDeadlineRows(arena).len,
    );
    model.calendarToday = try matching_deadline.?.final_deadline.addDays(1);
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileActionRequiredRows(arena).len,
    );
    const new_overdue_rows = model.profileOverdueDeadlineRows(arena);
    try std.testing.expectEqual(@as(usize, 1), new_overdue_rows.len);
    try std.testing.expectEqualStrings("New", new_overdue_rows[0].filingStatus());
    const selected_month = model.profileCalendar.selected_month;
    model.profileCalendar.selected_month = if (selected_month == 1) 2 else 1;
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileOverdueDeadlineRows(arena).len,
    );
    model.profileCalendar.selected_month = selected_month;
    model.calendarToday = matching_deadline.?.final_deadline;

    try model.formProfiles.open(.{
        .form = editorRevision("2551Q").?,
        .filer_profile_id = model.taxProfiles.selectedProfileDomainId().?,
        .tax_year = 2026,
        .quarter = 2,
        .filing_period = .{ .quarterly = .{
            .tax_year = 2026,
            .quarter = 2,
        } },
    });
    const original_draft_id =
        (try model.formProfiles.saveRecurringDraft()).id;
    try model.taxProfiles.refreshDraftSummaries();
    try std.testing.expectEqual(
        @as(usize, 1),
        model.taxProfiles.draftSummaries().len,
    );
    try std.testing.expect(model.profileCalendarIncludesForm(
        matching_deadline.?.form_code,
    ));
    try std.testing.expectEqualStrings(
        "2551Q",
        model.taxProfiles.draftSummaries()[0].formCode(),
    );
    try std.testing.expectEqualStrings(
        "2026-Q2",
        model.taxProfiles.draftSummaries()[0].periodKey(),
    );
    try std.testing.expectEqualStrings(
        "2551Q",
        matching_deadline.?.form_code,
    );
    switch (matching_deadline.?.period) {
        .quarterly => |period| {
            var period_buffer: [16]u8 = undefined;
            const rendered = try std.fmt.bufPrint(
                &period_buffer,
                "{d}-Q{d}",
                .{ period.taxable_year, period.quarter },
            );
            try std.testing.expectEqualStrings("2026-Q2", rendered);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(draftMatchesDeadline(
        &model.taxProfiles.draftSummaries()[0],
        &matching_deadline.?,
    ));
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileMonthlyDeadlineRows(arena).len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileMonthlyDeadlineCount(),
    );
    try std.testing.expectEqualStrings(
        "1 deadline",
        model.profileMonthlyDeadlineCountLabel(arena),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileActionRequiredRows(arena).len,
    );
    const action_row = model.profileActionRequiredRows(arena)[0];
    update(&model, .{
        .profile_deadline_run_action = action_row.primaryActionDispatchId(),
    });
    try std.testing.expectEqual(Page.form_2551q, model.page);
    try std.testing.expectEqual(
        @as(?u8, 2),
        model.formProfiles.filingPeriod().?.quarter(),
    );
    navigate(&model, .taxpayer_dashboard);

    // A clicked day narrows the month schedule only. It cannot hide a saved draft from
    // Action Required or move a deadline into Overdue.
    const other_day: u8 = if (matching_deadline.?.final_deadline.day == 1)
        2
    else
        1;
    model.profileCalendarSelectedDate = try calendar_domain.Date.init(
        matching_deadline.?.final_deadline.year,
        matching_deadline.?.final_deadline.month,
        other_day,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileMonthlyDeadlineRows(arena).len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileMonthlyDeadlineCount(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileActionRequiredRows(arena).len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileOverdueDeadlineRows(arena).len,
    );

    model.calendarToday = try matching_deadline.?.final_deadline.addDays(1);
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileMonthlyDeadlineCount(),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileActionRequiredRows(arena).len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileOverdueDeadlineRows(arena).len,
    );

    // The profile form picker is a session-only view filter. It hides every
    // lane and marker without changing the Forms Set or export projection.
    const form_index = formCatalogIndex("2551Q").?;
    const export_count = model.profileCalendarForExport().deadline_count;
    update(&model, .{
        .profile_calendar_forms_toggle_option = form_index,
    });
    try std.testing.expectEqualStrings(
        "0 forms",
        model.profileCalendarFormSelectionText(arena),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileOverdueDeadlineRows(arena).len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileCalendarDeadlineCountForDay(
            matching_deadline.?.final_deadline.day,
        ),
    );
    try std.testing.expect(model.taxProfiles.formAvailable(2026, "2551Q"));
    try std.testing.expectEqual(
        export_count,
        model.profileCalendarForExport().deadline_count,
    );
    update(&model, .{
        .profile_calendar_forms_toggle_option = form_index,
    });
    try std.testing.expectEqualStrings(
        "1 form",
        model.profileCalendarFormSelectionText(arena),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileOverdueDeadlineRows(arena).len,
    );

    // Open draft backlog remains visible outside its deadline month; the
    // selected-day state remains irrelevant to the overdue classification.
    model.profileCalendar.selected_month =
        if (matching_deadline.?.final_deadline.month == 1) 2 else 1;
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileOverdueDeadlineRows(arena).len,
    );
    model.profileCalendar.selected_month =
        matching_deadline.?.final_deadline.month;

    model.calendarToday = matching_deadline.?.final_deadline;
    try profile_store_fixture.transitionDraft(
        original_draft_id.asSlice(),
        "editing",
        "prepared",
    );
    try model.taxProfiles.refreshDraftSummaries();
    var lifecycle_rows = model.profileActionRequiredRows(arena);
    try std.testing.expectEqual(@as(usize, 1), lifecycle_rows.len);
    try std.testing.expectEqualStrings("Draft", lifecycle_rows[0].filingStatus());
    try std.testing.expectEqualStrings("Submit Form", lifecycle_rows[0].primaryActionLabel());
    const stale_submit_dispatch = lifecycle_rows[0].primaryActionDispatchId();
    invalidateProfileDeadlineProjection(&model);
    update(&model, .{
        .profile_deadline_run_action = stale_submit_dispatch,
    });
    try std.testing.expect(!model.profileDeadlineStubDialogOpen());
    lifecycle_rows = model.profileActionRequiredRows(arena);
    update(&model, .{
        .profile_deadline_run_action = lifecycle_rows[0].primaryActionDispatchId(),
    });
    try std.testing.expect(model.profileDeadlineStubDialogOpen());
    {
        var persisted = (try profile_store_fixture.getDraft(
            allocator,
            original_draft_id.asSlice(),
        )).?;
        defer persisted.deinit(allocator);
        try std.testing.expectEqualStrings("prepared", persisted.lifecycle);
    }
    update(&model, .profile_deadline_close_dialog);

    try profile_store_fixture.transitionDraft(
        original_draft_id.asSlice(),
        "prepared",
        "queued",
    );
    try model.taxProfiles.refreshDraftSummaries();
    lifecycle_rows = model.profileActionRequiredRows(arena);
    try std.testing.expectEqual(@as(usize, 1), lifecycle_rows.len);
    try std.testing.expectEqualStrings("Queued", lifecycle_rows[0].filingStatus());
    try std.testing.expectEqualStrings("Review Submission", lifecycle_rows[0].primaryActionLabel());
    try std.testing.expectEqualStrings("Print Form", lifecycle_rows[0].secondaryActionOneLabel());
    model.profileCalendarSelectedDate = null;
    update(&model, .{
        .profile_deadline_toggle_actions = lifecycle_rows[0].actionMenuId(),
    });
    try std.testing.expect(
        model.profileActionRequiredRows(arena)[0].actionMenuOpen(),
    );
    try std.testing.expect(
        !model.profileMonthlyDeadlineRows(arena)[0].actionMenuOpen(),
    );
    update(&model, .profile_deadline_close_actions);

    try profile_store_fixture.transitionDraft(
        original_draft_id.asSlice(),
        "queued",
        "submitted",
    );
    try model.taxProfiles.refreshDraftSummaries();
    lifecycle_rows = model.profileActionRequiredRows(arena);
    try std.testing.expectEqual(@as(usize, 1), lifecycle_rows.len);
    try std.testing.expectEqualStrings("Sent", lifecycle_rows[0].filingStatus());
    try std.testing.expectEqualStrings("Check Confirmation", lifecycle_rows[0].primaryActionLabel());
    try std.testing.expectEqualStrings("Print Form", lifecycle_rows[0].secondaryActionOneLabel());
    update(&model, .{
        .profile_deadline_run_action = lifecycle_rows[0].primaryActionDispatchId(),
    });
    try std.testing.expect(model.profileDeadlineStubDialogOpen());
    {
        var persisted = (try profile_store_fixture.getDraft(
            allocator,
            original_draft_id.asSlice(),
        )).?;
        defer persisted.deinit(allocator);
        try std.testing.expectEqualStrings("submitted", persisted.lifecycle);
    }
    update(&model, .profile_deadline_close_dialog);

    try profile_store_fixture.transitionDraft(
        original_draft_id.asSlice(),
        "submitted",
        "confirmed",
    );
    try model.taxProfiles.refreshDraftSummaries();
    lifecycle_rows = model.profileActionRequiredRows(arena);
    try std.testing.expectEqual(@as(usize, 1), lifecycle_rows.len);
    try std.testing.expectEqualStrings("Confirmed", lifecycle_rows[0].filingStatus());
    try std.testing.expectEqualStrings("Upload Receipt", lifecycle_rows[0].primaryActionLabel());
    try std.testing.expectEqualStrings("Print Form", lifecycle_rows[0].secondaryActionOneLabel());
    update(&model, .{
        .profile_deadline_run_action = lifecycle_rows[0].primaryActionDispatchId(),
    });
    try std.testing.expect(model.profileDeadlineStubDialogOpen());
    {
        var persisted = (try profile_store_fixture.getDraft(
            allocator,
            original_draft_id.asSlice(),
        )).?;
        defer persisted.deinit(allocator);
        try std.testing.expectEqualStrings("confirmed", persisted.lifecycle);
    }
    update(&model, .profile_deadline_close_dialog);

    model.calendarToday = try matching_deadline.?.final_deadline.addDays(1);
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileActionRequiredRows(arena).len,
    );
    const confirmed_overdue_rows = model.profileOverdueDeadlineRows(arena);
    try std.testing.expectEqual(@as(usize, 1), confirmed_overdue_rows.len);
    try std.testing.expectEqualStrings(
        "Confirmed",
        confirmed_overdue_rows[0].filingStatus(),
    );
    try std.testing.expectEqual(
        ProfileDeadlineTiming.overdue,
        confirmed_overdue_rows[0].timing,
    );
    try std.testing.expectEqual(
        CalendarMarkerTone.overdue,
        model.profileCalendarMarkerToneForDay(
            matching_deadline.?.final_deadline.day,
        ),
    );

    try profile_store_fixture.transitionDraft(
        original_draft_id.asSlice(),
        "confirmed",
        "paid",
    );
    try model.taxProfiles.refreshDraftSummaries();
    model.profileCalendarSelectedDate = null;
    const paid_month_rows = model.profileMonthlyDeadlineRows(arena);
    try std.testing.expectEqual(@as(usize, 1), paid_month_rows.len);
    try std.testing.expectEqualStrings("Paid", paid_month_rows[0].filingStatus());
    try std.testing.expectEqualStrings("Print Form", paid_month_rows[0].primaryActionLabel());
    update(&model, .{
        .profile_deadline_run_action = paid_month_rows[0].primaryActionDispatchId(),
    });
    try std.testing.expect(model.profileDeadlineStubDialogOpen());
    {
        var persisted = (try profile_store_fixture.getDraft(
            allocator,
            original_draft_id.asSlice(),
        )).?;
        defer persisted.deinit(allocator);
        try std.testing.expectEqualStrings("paid", persisted.lifecycle);
    }
    update(&model, .profile_deadline_close_dialog);
    try std.testing.expectEqual(ProfileDeadlineTiming.closed, paid_month_rows[0].timing);
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileMonthlyDeadlineCount(),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileActionRequiredRows(arena).len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileOverdueDeadlineRows(arena).len,
    );
    try std.testing.expectEqual(
        CalendarMarkerTone.closed,
        model.profileCalendarMarkerToneForDay(
            matching_deadline.?.final_deadline.day,
        ),
    );

    // A paid original remains resolved until an open amendment exists. The
    // amendment then owns the actionable lifecycle instead of rendering a
    // contradictory Paid row.
    const amendment_id = try form_ids.DraftId.parse(
        "lane-calendar-2551q-q2-amended",
    );
    {
        var original = (try profile_store_fixture.getDraft(
            allocator,
            original_draft_id.asSlice(),
        )).?;
        defer original.deinit(allocator);
        const rehydrated = try form_persistence.rehydrate(&original);
        var amendment = try form_persistence.createOrLoad(
            allocator,
            &profile_store_fixture,
            .{
                .mode = .{ .amendment = .{
                    .caller_supplied_id = amendment_id,
                    .amendment_of = original_draft_id,
                } },
                .period = .{
                    .form = rehydrated.form,
                    .tax_year = rehydrated.period.taxYear(),
                    .quarter = rehydrated.period.quarter().?,
                },
                .filing_period = rehydrated.period,
                .role_bindings = &rehydrated.role_bindings,
                .snapshot = &rehydrated.snapshot,
            },
        );
        amendment.deinit(allocator);
    }
    try model.taxProfiles.refreshDraftSummaries();
    model.calendarToday = matching_deadline.?.final_deadline;
    try std.testing.expect(!model.profileDeadlineHasPaidDraft(
        &matching_deadline.?,
    ));
    const amended_rows = model.profileActionRequiredRows(arena);
    try std.testing.expectEqual(@as(usize, 1), amended_rows.len);
    try std.testing.expectEqualStrings(
        "Draft",
        amended_rows[0].filingStatus(),
    );
    try std.testing.expectEqualStrings(
        "Continue Draft",
        amended_rows[0].primaryActionLabel(),
    );
    update(&model, .{
        .profile_deadline_run_action = amended_rows[0].primaryActionDispatchId(),
    });
    try std.testing.expectEqual(Page.form_2551q, model.page);
    try std.testing.expectEqualStrings(
        amendment_id.asSlice(),
        model.formProfiles.draftId().?.asSlice(),
    );
    navigate(&model, .taxpayer_dashboard);

    try profile_store_fixture.replaceFormSet(profile_id, 2026, &.{});
    refreshSelectedProfileFormSet(&model);
    try std.testing.expect(!model.profileCalendarIncludesForm("2551Q"));
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileMonthlyDeadlineRows(arena).len,
    );
}

test "global calendar form choices do not change with taxpayer selection" {
    const allocator = std.testing.allocator;
    var store = try profile_store.Store.openMemory(allocator);
    defer store.close();
    try addThreeTestProfiles(&store);

    var model = Model{};
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);

    const juan_slot = profileSlotNamed(&model, "Juan Dela Cruz").?;
    const corporation_slot = profileSlotNamed(
        &model,
        "Demo Corporation",
    ).?;

    update(&model, .multi_select_clear_all);
    update(
        &model,
        .{ .multi_select_toggle_option = calendarFormIndex("2551Q") },
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.globalDashboard.forms.selectedCount(),
    );

    update(&model, .{ .select_taxpayer = juan_slot });
    try std.testing.expectEqual(
        @as(usize, 1),
        model.globalDashboard.forms.selectedCount(),
    );
    update(&model, .{ .select_taxpayer = corporation_slot });
    try std.testing.expect(
        model.globalDashboard.forms.isSelected(calendarFormIndex("2551Q")),
    );

    try std.testing.expectEqual(
        @as(usize, 1),
        model.globalDashboard.forms.selectedCount(),
    );
    try std.testing.expect(
        try store.getCalendarFormSelection(
            allocator,
            model.taxProfiles.selectedProfileId().?,
        ) == null,
    );
    const fresh = Model{};
    try std.testing.expectEqual(
        @as(usize, calendar_form_codes.len),
        fresh.globalDashboard.forms.selectedCount(),
    );
}

test "profile dashboard markup builds with the three calendar lanes" {
    const model = Model{ .page = .taxpayer_dashboard };
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
    var ui = canvas.Ui(Msg).init(arena);
    const tree = try ui.finalize(try view.build(&ui, &model));
    try std.testing.expect(
        findWidgetByText(tree.root, .text, "Deadlines") != null,
    );
    try std.testing.expect(
        findWidgetByText(tree.root, .text, "Action Required") != null,
    );
    try std.testing.expect(
        findWidgetByText(tree.root, .text, "Overdue") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, app_markup, "profile_deadline_run_action") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, app_markup, "profile_deadline_show_adjustment") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, app_markup, "open_profile_deadline") == null,
    );
    const profile_source = @embedFile("pages/taxpayer-dashboard.native");
    try std.testing.expectEqual(
        @as(usize, 2),
        std.mem.count(u8, profile_source, "<use template=\"t-l\""),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        std.mem.count(u8, profile_source, "@include-template d-s"),
    );
}

test "global and profile form pickers remain separately scoped" {
    const profile_source = @embedFile("pages/taxpayer-dashboard.native");
    const profile_page_source = @embedFile(
        "pages/taxpayer-dashboard-page.native",
    );
    const global_source = @embedFile("pages/global-dashboard.fragment");
    const calendar_source = @embedFile("pages/tax-calendar.native");
    try std.testing.expectEqual(
        @as(usize, 3),
        std.mem.count(
            u8,
            profile_source,
            "@include-template profile-calendar-multi-select-combobox",
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        std.mem.count(
            u8,
            profile_source,
            "@include-template multi-select-combobox",
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        std.mem.count(
            u8,
            global_source,
            "@include-template multi-select-combobox",
        ),
    );
    try std.testing.expect(
        std.mem.indexOf(u8, calendar_source, "multi-select-combobox") == null,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        std.mem.count(
            u8,
            profile_page_source,
            "on-press=\"show_dashboard_profile_settings\"",
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        std.mem.count(u8, profile_page_source, "show_profile_setup"),
    );
}

fn expectAppMarkupBuilds(model: *const Model) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
    var ui = canvas.Ui(Msg).init(arena);
    const root = view.build(&ui, model) catch |err| {
        if (err == error.MarkupBuild) {
            std.debug.print(
                "app markup failed at {s}:{d}:{d}: {s}\n",
                .{
                    view.diagnostic.path,
                    view.diagnostic.line,
                    view.diagnostic.column,
                    view.diagnostic.message,
                },
            );
        }
        return err;
    };
    _ = try ui.finalize(root);
}
