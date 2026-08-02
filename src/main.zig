//! eBIRForms application state and Native SDK wiring.
//!
//! The screens remain declarative `.native` templates. Zig owns the small
//! application state: navigation, appearance and accessibility preferences,
//! plus the tested calendar resolver, SQLite policy store, and native
//! calendar-handoff effects.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const multi_select = @import("components/multi_select.zig");
const calendar_domain = @import("calendar/domain.zig");
const calendar_ui = @import("calendar/ui_state.zig");
const global_dashboard_ui = @import("global_dashboard/ui_state.zig");
const news_domain = @import("news/domain.zig");
const news_feed = @import("news/feed.zig");
const news_store = @import("news/store.zig");
const news_ui = @import("news/ui_state.zig");
const profile_ui = @import("tax_profile/ui_state.zig");
const profile_store = @import("tax_profile/store.zig");
const profile_persistence = @import("tax_profile/persistence_adapter.zig");
const profile_editor = @import("tax_profile/editor.zig");
const profile_fields = @import("tax_profile/field.zig");
const profile_model = @import("tax_profile/model.zig");
const form_ui = @import("forms/ui_state.zig");
const form_ids = @import("forms/id.zig");
const form_persistence = @import("forms/persistence_adapter.zig");
const form_runtime = @import("forms/runtime.zig");
const form_catalog = @import("forms/generated/catalog.zig");
const income_tax_ui = @import("forms/income_tax_ui_state.zig");
const key_custody = @import("security/key_custody.zig");
const exact_1701q_native = @import(
    "forms/form_1701q_exact_native_state.zig",
);
const exact_1701q_ui = @import(
    "forms/form_1701q_exact_ui_state.zig",
);
const percentage_tax_ui = @import("forms/percentage_tax_ui_state.zig");
const c_time = @cImport({
    @cInclude("time.h");
});

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const calendar_icon = canvas.svg_icon.parseComptime(
    @embedFile("icons/calendar.svg"),
);
pub const app_icons = [_]canvas.icons.Entry{
    .{ .name = "calendar", .icon = &calendar_icon },
};

const canvas_label = "main-canvas";
const window_width: f32 = 1225;
const window_height: f32 = 768;
const phone_breakpoint: f32 = 600;
const compact_shell_breakpoint: f32 = 768;
const rail_shell_breakpoint: f32 = 1320;
const taxpayer_two_lane_min_width: f32 = 740;
const taxpayer_three_lane_min_width: f32 = 974;
const global_calendar_lane_min_width: f32 = 320;
const global_calendar_lane_max_width: f32 = 560;
const profile_calendar_lane_max_width: f32 = 500;
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
};

pub const ProfileSetupSection = enum {
    tax_profile,
    certificate,
    email,
};

pub const TaxCalendarSection = enum {
    deadlines,
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

pub const CalendarFormOptionRow = struct {
    id: usize,
    label: []const u8,
    selected: bool,
};

pub const ProfileCalendarDayCell = struct {
    id: usize,
    day: u8,
    deadline_count: usize,
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

pub const ProfileActionRequiredRow = struct {
    id: usize,
    draft_id: []const u8,
    form_code: []const u8,
    form_name: []const u8,
    period_key: []const u8,
    lifecycle: []const u8,
    due_date: calendar_domain.Date,

    pub fn key(self: *const ProfileActionRequiredRow) canvas.UiKey {
        return canvas.uiKey(self.id);
    }

    pub fn dateLabel(
        self: *const ProfileActionRequiredRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{s} {d}",
            .{ shortMonthName(self.due_date.month), self.due_date.day },
        ) catch "";
    }

    pub fn yearLabel(
        self: *const ProfileActionRequiredRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(arena, "{d}", .{self.due_date.year}) catch "";
    }

    pub fn statusLabel(
        self: *const ProfileActionRequiredRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.lifecycle.len == 0) return "Pending";
        const output = arena.dupe(u8, self.lifecycle) catch return self.lifecycle;
        output[0] = std.ascii.toUpper(output[0]);
        return output;
    }

    pub fn tone(self: *const ProfileActionRequiredRow) []const u8 {
        if (std.mem.eql(u8, self.lifecycle, "queued") or
            std.mem.eql(u8, self.lifecycle, "submitted") or
            std.mem.eql(u8, self.lifecycle, "confirmed"))
        {
            return "outline";
        }
        return "secondary";
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

pub const TaxFormLibraryRow = struct {
    id: usize,
    definition: *const form_catalog.FormDefinition,
    active: bool,
    selected: bool,
    launch_disabled: bool,
    launch_assessment: form_ui.LaunchAssessment = .{},

    pub fn key(self: *const TaxFormLibraryRow) canvas.UiKey {
        return canvas.uiKey(self.id);
    }

    pub fn code(self: *const TaxFormLibraryRow) []const u8 {
        return self.definition.code;
    }

    pub fn title(
        self: *const TaxFormLibraryRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "BIR Form {s}",
            .{self.definition.code},
        ) catch self.definition.code;
    }

    pub fn capability(self: *const TaxFormLibraryRow) []const u8 {
        return if (self.definition.status == .static_layout)
            "Editor available"
        else
            "Calendar only";
    }

    pub fn activeLabel(self: *const TaxFormLibraryRow) []const u8 {
        return if (self.active) "Active" else "Inactive";
    }

    pub fn editorAvailable(self: *const TaxFormLibraryRow) bool {
        return self.definition.status == .static_layout;
    }

    pub fn selectionLabel(
        self: *const TaxFormLibraryRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{s} BIR Form {s}",
            .{
                if (self.selected) "Deselect" else "Select",
                self.definition.code,
            },
        ) catch "Toggle form selection";
    }

    pub fn launchLabel(self: *const TaxFormLibraryRow) []const u8 {
        if (!self.active) return "Inactive";
        if (!self.editorAvailable()) return "Calendar only";
        return switch (self.launch_assessment.status) {
            .ready_new => "Open Form",
            .ready_resume => "Resume Draft",
            .needs_profile => "Complete profile",
            .needs_activity_selection => "Choose activity",
            .profile_not_eligible => "Profile not eligible",
            .unavailable => "Unavailable",
        };
    }

    pub fn launchStatus(self: *const TaxFormLibraryRow) []const u8 {
        if (!self.active) return "Inactive";
        if (!self.editorAvailable()) return "Calendar only";
        return switch (self.launch_assessment.status) {
            .ready_new => "Ready",
            .ready_resume => "Draft available",
            .needs_profile => "Needs profile",
            .needs_activity_selection => "Choose activity",
            .profile_not_eligible => "Not eligible",
            .unavailable => "Launch blocked",
        };
    }

    pub fn launchActionVisible(self: *const TaxFormLibraryRow) bool {
        return self.active and self.editorAvailable();
    }

    pub fn launchDisabled(self: *const TaxFormLibraryRow) bool {
        return self.launch_disabled;
    }
};

pub const Model = struct {
    page: Page = .global_dashboard,
    profileEditorOrigin: Page = .global_dashboard,
    overlayReturnPage: Page = .global_dashboard,
    dashboardSection: DashboardSection = .calendar,
    profileSetupSection: ProfileSetupSection = .tax_profile,
    taxCalendarSection: TaxCalendarSection = .deadlines,
    backgroundTasksSection: BackgroundTasksSection = .jobs,
    globalDashboard: GlobalDashboardState = .{},
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
    formProfiles: form_ui.State = .{},
    incomeTax: income_tax_ui.State = .{},
    exact1701Q: exact_1701q_native.State = .{},
    percentageTax: percentage_tax_ui.State = .{},
    calendarExportProfileRevision: ?profile_ui.RevisionContext = null,
    profileCalendarExportStatus: ProfileCalendarExportStatus = .idle,
    profileCalendarExportNoticeEpoch: u64 = 0,
    profileCalendarExportTimerKey: u64 = 0,
    profileActionsOpen: bool = false,
    profileSubjectPickerVisible: bool = false,
    profileCompletionTarget: ?profile_fields.ReusableField = null,
    profileCompletionFormIndex: ?usize = null,
    profileFormLaunchAssessments: [form_catalog.registry_count]form_ui.LaunchAssessment = undefined,
    profileFormLaunchAssessmentsReady: bool = false,
    profileFormsFilterPickerVisible: bool = false,
    profileCalendarSelectedDate: ?calendar_domain.Date = null,
    profileNoticeTimerKey: u64 = 0,
    calendarToday: calendar_domain.Date = .{
        .year = 2026,
        .month = 1,
        .day = 1,
    },

    // These values drive Zig-owned tokens rather than markup bindings.
    pub const view_unbound = .{
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
        "profileCompletionTarget",
        "profileCompletionFormIndex",
        "profileFormLaunchAssessments",
        "profileFormLaunchAssessmentsReady",
        "profileFormsFilterPickerVisible",
        "profileCalendarDeadlines",
        "profileCalendarHasDeadlines",
        "profileCalendarDeadlineCount",
        "profileCalendarEmptyTitle",
        "profileCalendarEmptyMessage",
        "taxProfiles",
        "formProfiles",
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

    pub fn visibleProfileRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const profile_ui.ProfileRow {
        const all = self.taxProfiles.rows();
        const query = self.sidebarProfileSearchBuffer.text();
        if (query.len == 0) return all;

        const rows = arena.alloc(profile_ui.ProfileRow, all.len) catch return &.{};
        var count: usize = 0;
        for (all) |row| {
            if (!multi_select.containsAsciiInsensitive(row.nameLabel(), query) and
                !multi_select.containsAsciiInsensitive(row.tinLabel(arena), query))
            {
                continue;
            }
            rows[count] = row;
            count += 1;
        }
        return rows[0..count];
    }

    pub fn visibleProfileRowsEmpty(
        self: *const Model,
        arena: std.mem.Allocator,
    ) bool {
        return self.visibleProfileRows(arena).len == 0;
    }

    pub fn profileRowsEmptyTitle(self: *const Model) []const u8 {
        if (self.taxProfiles.rowsEmpty()) return "No tax profiles yet";
        return "No matching profiles";
    }

    pub fn profileRowsEmptyMessage(self: *const Model) []const u8 {
        if (self.taxProfiles.rowsEmpty()) {
            return "Add a profile once, then reuse its qualified fields on recurring forms.";
        }
        return "Try a taxpayer name or TIN, or clear the search field.";
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
        return self.formProfiles.filerText(.registered_address);
    }

    pub fn formFilerZipCode(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.zip_code);
    }

    pub fn formFilerContactNumber(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.contact_number);
    }

    pub fn formFilerEmailAddress(self: *const Model) []const u8 {
        return self.formProfiles.filerText(.email_address);
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
        return if (self.taxProfiles.editing_new)
            "Create Taxpayer Profile"
        else
            "Revise Taxpayer Profile";
    }

    pub fn editingNewProfile(self: *const Model) bool {
        return self.taxProfiles.editing_new;
    }

    pub fn profileInlineBackVisible(self: *const Model) bool {
        return self.page == .profile_setup and
            !self.sidebarLauncherVisible();
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
            "Save New Revision";
    }

    pub fn profileSaveDisabled(self: *const Model) bool {
        return self.taxProfiles.saveDisabled();
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

    pub fn profileSubjectKindLabel(self: *const Model) []const u8 {
        return switch (self.taxProfiles.subject_kind) {
            .individual => "Individual",
            .sole_proprietor => "Sole proprietor",
            .corporation => "Corporation",
            .partnership => "Partnership",
            .estate => "Estate",
            .trust => "Trust",
            .other_legal_entity => "Other legal entity",
        };
    }

    pub fn profileIndividualSelected(self: *const Model) bool {
        return self.taxProfiles.subject_kind == .individual;
    }

    pub fn profileSoleProprietorSelected(self: *const Model) bool {
        return self.taxProfiles.subject_kind == .sole_proprietor;
    }

    pub fn profileCorporationSelected(self: *const Model) bool {
        return self.taxProfiles.subject_kind == .corporation;
    }

    pub fn profilePartnershipSelected(self: *const Model) bool {
        return self.taxProfiles.subject_kind == .partnership;
    }

    pub fn profileEstateSelected(self: *const Model) bool {
        return self.taxProfiles.subject_kind == .estate;
    }

    pub fn profileTrustSelected(self: *const Model) bool {
        return self.taxProfiles.subject_kind == .trust;
    }

    pub fn profileOtherLegalSelected(self: *const Model) bool {
        return self.taxProfiles.subject_kind == .other_legal_entity;
    }

    pub fn profileTradeNameVisible(self: *const Model) bool {
        return self.taxProfiles.subject_kind == .sole_proprietor;
    }

    pub fn profilePersonalFieldsDisabled(self: *const Model) bool {
        return switch (self.taxProfiles.subject_kind) {
            .individual, .sole_proprietor => false,
            .corporation,
            .partnership,
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

    pub fn profileTaxYearValue(self: *const Model) []const u8 {
        return self.taxProfiles.tax_year.text();
    }

    pub fn profileFormsSetValue(self: *const Model) []const u8 {
        return self.taxProfiles.forms_set.text();
    }

    pub fn managingProfileForms(self: *const Model) bool {
        return self.taxProfiles.managing_forms;
    }

    pub fn profileFormsSaveDisabled(self: *const Model) bool {
        return !self.taxProfiles.formsDirty();
    }

    pub fn profileFormsSearchValue(self: *const Model) []const u8 {
        return self.taxProfiles.formsQuery();
    }

    pub fn profileFormsCountLabel(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d} of {d} active",
            .{ self.taxProfiles.activeFormCount(), form_catalog.registry_count },
        ) catch "Forms Set unavailable";
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

    pub fn profileFormsFilterPickerOpen(self: *const Model) bool {
        return self.profileFormsFilterPickerVisible;
    }

    pub fn profileFormsFilterSummaryLabel(self: *const Model) []const u8 {
        return switch (self.taxProfiles.form_activity_filter) {
            .active => switch (self.taxProfiles.form_capability_filter) {
                .all => "Active · Any type",
                .editor => "Active · Editor",
                .calendar_only => "Active · Calendar only",
            },
            .inactive => switch (self.taxProfiles.form_capability_filter) {
                .all => "Inactive · Any type",
                .editor => "Inactive · Editor",
                .calendar_only => "Inactive · Calendar only",
            },
            .all => switch (self.taxProfiles.form_capability_filter) {
                .all => "All forms",
                .editor => "All statuses · Editor",
                .calendar_only => "All statuses · Calendar only",
            },
        };
    }

    pub fn profileFormsFilterAccessibleLabel(self: *const Model) []const u8 {
        return switch (self.taxProfiles.form_activity_filter) {
            .active => switch (self.taxProfiles.form_capability_filter) {
                .all => "Filter forms: active, any form type",
                .editor => "Filter forms: active, editor available",
                .calendar_only => "Filter forms: active, calendar only",
            },
            .inactive => switch (self.taxProfiles.form_capability_filter) {
                .all => "Filter forms: inactive, any form type",
                .editor => "Filter forms: inactive, editor available",
                .calendar_only => "Filter forms: inactive, calendar only",
            },
            .all => switch (self.taxProfiles.form_capability_filter) {
                .all => "Filter forms: all forms",
                .editor => "Filter forms: all statuses, editor available",
                .calendar_only => "Filter forms: all statuses, calendar only",
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

    pub fn profileFormRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const TaxFormLibraryRow {
        const rows = arena.alloc(
            TaxFormLibraryRow,
            form_catalog.registry_count,
        ) catch return &.{};
        var count: usize = 0;
        for (&form_catalog.forms, 0..) |*definition, index| {
            const active = self.taxProfiles.formAvailable(
                self.calendar.selected_year,
                definition.code,
            );
            const selected = self.taxProfiles.displayedFormSelected(index);
            const filter_selected = if (self.taxProfiles.managing_forms)
                selected
            else
                active;
            switch (self.taxProfiles.form_activity_filter) {
                .active => if (!filter_selected) continue,
                .inactive => if (filter_selected) continue,
                .all => {},
            }
            switch (self.taxProfiles.form_capability_filter) {
                .editor => if (definition.status != .static_layout) continue,
                .calendar_only => if (definition.status != .calendar_only) continue,
                .all => {},
            }
            if (!multi_select.containsAsciiInsensitive(
                definition.code,
                self.taxProfiles.formsQuery(),
            )) continue;
            const launch_assessment = if (self.profileFormLaunchAssessmentsReady)
                self.profileFormLaunchAssessments[index]
            else
                form_ui.LaunchAssessment{};
            rows[count] = .{
                .id = index,
                .definition = definition,
                .active = active,
                .selected = selected,
                .launch_assessment = launch_assessment,
                .launch_disabled = definition.status != .static_layout or
                    !active or
                    !launchActionEnabled(
                        launch_assessment.status,
                    ),
            };
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileFormRowsEmpty(
        self: *const Model,
        arena: std.mem.Allocator,
    ) bool {
        return self.profileFormRows(arena).len == 0;
    }

    pub fn dashboardCalendarActive(self: *const Model) bool {
        return self.dashboardSection == .calendar;
    }

    pub fn dashboardFormsActive(self: *const Model) bool {
        return self.dashboardSection == .forms;
    }

    pub fn profileTaxActive(self: *const Model) bool {
        return self.profileSetupSection == .tax_profile;
    }

    pub fn profileCertificateActive(self: *const Model) bool {
        return self.profileSetupSection == .certificate;
    }

    pub fn profileEmailActive(self: *const Model) bool {
        return self.profileSetupSection == .email;
    }

    pub fn calendarDeadlinesActive(self: *const Model) bool {
        return self.taxCalendarSection == .deadlines;
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

    pub fn calendarDeadlineCount(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const noun = deadlineNoun(self.calendar.deadline_count);
        return std.fmt.allocPrint(
            arena,
            "{d} scheduled {s}",
            .{ self.calendar.deadline_count, noun },
        ) catch "";
    }

    pub fn calendarVisibleDeadlineCount(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        var count: usize = 0;
        for (self.calendar.deadlines[0..self.calendar.deadline_count]) |row| {
            if (row.final_deadline.month == self.calendar.selected_month) {
                count += 1;
            }
        }
        const noun = deadlineNoun(count);
        return std.fmt.allocPrint(
            arena,
            "{d} {s} this month",
            .{ count, noun },
        ) catch "";
    }

    pub fn calendarDeadlines(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const calendar_ui.DeadlineRow {
        const all = self.calendar.deadlines[0..self.calendar.deadline_count];
        const visible = arena.alloc(calendar_ui.DeadlineRow, all.len) catch return &.{};
        var count: usize = 0;
        for (all) |row| {
            if (row.final_deadline.month != self.calendar.selected_month) continue;
            visible[count] = row;
            count += 1;
        }
        return visible[0..count];
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
        const filtered_count = self.filteredProfileCalendarFormOptionCount();
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
            self.filteredProfileCalendarFormOptionCount(),
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

    /// Profile deadline rows follow the selected taxpayer's registered Forms
    /// Set. An unconfigured tax year intentionally uses the catalog fallback.
    pub fn profileCalendarDeadlines(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const calendar_ui.DeadlineRow {
        const all = self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count];
        const rows = arena.alloc(
            calendar_ui.DeadlineRow,
            all.len,
        ) catch return &.{};
        var count: usize = 0;
        for (all) |row| {
            if (row.final_deadline.month !=
                self.profileCalendar.selected_month) continue;
            if (self.profileCalendarSelectedDay()) |selected_day| {
                if (row.final_deadline.day != selected_day) continue;
            }
            if (!self.profileCalendarIncludesDeadline(&row)) continue;
            rows[count] = row;
            count += 1;
        }
        return rows[0..count];
    }

    /// Deadlines in the visible month that have not passed and have not been
    /// satisfied by a paid filing for the selected taxpayer.
    pub fn profileUpcomingDeadlines(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const calendar_ui.DeadlineRow {
        const all = self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count];
        const rows = arena.alloc(
            calendar_ui.DeadlineRow,
            all.len,
        ) catch return &.{};
        var count: usize = 0;
        for (all) |row| {
            if (row.final_deadline.month != self.profileCalendar.selected_month or
                !self.profileCalendarDayVisible(row.final_deadline.day) or
                !self.profileCalendarIncludesDeadline(&row) or
                calendar_domain.Date.compare(
                    row.final_deadline,
                    self.calendarToday,
                ) == .lt or
                self.profileDeadlineHasPaidDraft(&row))
            {
                continue;
            }
            rows[count] = row;
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileUpcomingHasDeadlines(self: *const Model) bool {
        for (self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count]) |*row| {
            if (row.final_deadline.month == self.profileCalendar.selected_month and
                self.profileCalendarDayVisible(row.final_deadline.day) and
                self.profileCalendarIncludesDeadline(row) and
                calendar_domain.Date.compare(
                    row.final_deadline,
                    self.calendarToday,
                ) != .lt and
                !self.profileDeadlineHasPaidDraft(row))
            {
                return true;
            }
        }
        return false;
    }

    pub fn profileUpcomingDeadlineCount(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d}",
            .{self.profileUpcomingDeadlines(arena).len},
        ) catch "0";
    }

    /// Persisted, non-paid filing work whose matching deadline is still open
    /// in the visible month. The dashboard never manufactures a draft from a
    /// deadline: an Action Required row exists only after a real SQLite draft
    /// has been created for this filer and period.
    pub fn profileActionRequiredRows(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const ProfileActionRequiredRow {
        const drafts = self.taxProfiles.draftSummaries();
        const rows = arena.alloc(
            ProfileActionRequiredRow,
            drafts.len,
        ) catch return &.{};
        var count: usize = 0;
        for (drafts) |*draft| {
            if (std.mem.eql(u8, draft.lifecycleText(), "paid") or
                std.mem.eql(u8, draft.lifecycleText(), "cancelled"))
            {
                continue;
            }
            for (self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count]) |*deadline| {
                if (!self.profileCalendarIncludesDeadline(deadline) or
                    deadline.final_deadline.month != self.profileCalendar.selected_month or
                    !self.profileCalendarDayVisible(deadline.final_deadline.day) or
                    calendar_domain.Date.compare(
                        deadline.final_deadline,
                        self.calendarToday,
                    ) == .lt or
                    !draftMatchesDeadline(draft, deadline))
                {
                    continue;
                }
                rows[count] = .{
                    .id = draft.slot,
                    .draft_id = draft.draftId(),
                    .form_code = deadline.display_form_no,
                    .form_name = deadline.form_name,
                    .period_key = draft.periodKey(),
                    .lifecycle = draft.lifecycleText(),
                    .due_date = deadline.final_deadline,
                };
                count += 1;
                break;
            }
        }
        return rows[0..count];
    }

    pub fn profileActionRequiredHasRows(self: *const Model) bool {
        for (self.taxProfiles.draftSummaries()) |*draft| {
            if (std.mem.eql(u8, draft.lifecycleText(), "paid") or
                std.mem.eql(u8, draft.lifecycleText(), "cancelled"))
            {
                continue;
            }
            for (self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count]) |*deadline| {
                if (self.profileCalendarIncludesDeadline(deadline) and
                    deadline.final_deadline.month == self.profileCalendar.selected_month and
                    self.profileCalendarDayVisible(deadline.final_deadline.day) and
                    calendar_domain.Date.compare(
                        deadline.final_deadline,
                        self.calendarToday,
                    ) != .lt and
                    draftMatchesDeadline(draft, deadline))
                {
                    return true;
                }
            }
        }
        return false;
    }

    pub fn profileActionRequiredCount(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d}",
            .{self.profileActionRequiredRows(arena).len},
        ) catch "0";
    }

    pub fn profileOverdueDeadlines(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const calendar_ui.DeadlineRow {
        const all = self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count];
        const rows = arena.alloc(
            calendar_ui.DeadlineRow,
            all.len,
        ) catch return &.{};
        var count: usize = 0;
        for (all) |row| {
            if (!self.profileCalendarIncludesDeadline(&row) or
                calendar_domain.Date.compare(
                    row.final_deadline,
                    self.calendarToday,
                ) != .lt or
                self.profileDeadlineHasPaidDraft(&row))
            {
                continue;
            }
            const visible_period = row.final_deadline.month ==
                self.profileCalendar.selected_month and
                self.profileCalendarDayVisible(row.final_deadline.day);
            if (!visible_period and !self.profileDeadlineHasOpenDraft(&row)) {
                continue;
            }
            rows[count] = row;
            count += 1;
        }
        return rows[0..count];
    }

    pub fn profileOverdueHasDeadlines(self: *const Model) bool {
        for (self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count]) |*row| {
            if (self.profileCalendarIncludesDeadline(row) and
                calendar_domain.Date.compare(
                    row.final_deadline,
                    self.calendarToday,
                ) == .lt and
                !self.profileDeadlineHasPaidDraft(row) and
                ((row.final_deadline.month == self.profileCalendar.selected_month and
                    self.profileCalendarDayVisible(row.final_deadline.day)) or
                    self.profileDeadlineHasOpenDraft(row)))
            {
                return true;
            }
        }
        return false;
    }

    pub fn profileOverdueDeadlineCount(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{d}",
            .{self.profileOverdueDeadlines(arena).len},
        ) catch "0";
    }

    pub fn profileCalendarHasDeadlines(self: *const Model) bool {
        for (self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count]) |row| {
            if (row.final_deadline.month != self.profileCalendar.selected_month) continue;
            if (self.profileCalendarSelectedDay()) |selected_day| {
                if (row.final_deadline.day != selected_day) continue;
            }
            if (self.profileCalendarIncludesDeadline(&row)) return true;
        }
        return false;
    }

    pub fn profileCalendarDeadlineCount(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        const count = self.profileCalendarDeadlines(arena).len;
        const noun = deadlineNoun(count);
        return std.fmt.allocPrint(
            arena,
            "{d} {s}",
            .{ count, noun },
        ) catch "Deadlines";
    }

    pub fn profileCalendarEmptyTitle(self: *const Model) []const u8 {
        _ = self;
        return "No deadlines this month";
    }

    pub fn profileCalendarEmptyMessage(self: *const Model) []const u8 {
        _ = self;
        return "This profile's Forms Set has no deadlines in this month.";
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
                .overdue_flag = marker_tone == .overdue,
                .due_soon_flag = marker_tone == .due_soon,
                .approaching_flag = marker_tone == .approaching,
                .selected_flag = day != 0 and
                    self.profileCalendarSelectedDay() == @as(?u8, day),
            };
        }
        return cells;
    }

    fn filteredProfileCalendarFormOptionCount(self: *const Model) usize {
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
            if (row.final_deadline.month != self.profileCalendar.selected_month or
                row.final_deadline.day != day or
                !self.profileCalendarIncludesDeadline(&row)) continue;
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
        for (self.profileCalendar.deadlines[0..self.profileCalendar.deadline_count]) |row| {
            if (calendar_domain.Date.compare(row.final_deadline, date) != .eq or
                !self.profileCalendarIncludesDeadline(&row)) continue;
            return calendarMarkerTone(date, self.calendarToday);
        }
        return .normal;
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

    fn profileCalendarDayVisible(self: *const Model, day: u8) bool {
        return if (self.profileCalendarSelectedDay()) |selected|
            selected == day
        else
            true;
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
        for (self.taxProfiles.draftSummaries()) |*draft| {
            if (!std.mem.eql(u8, draft.lifecycleText(), "paid")) continue;
            if (draftMatchesDeadline(draft, deadline)) return true;
        }
        return false;
    }

    fn profileDeadlineHasOpenDraft(
        self: *const Model,
        deadline: *const calendar_ui.DeadlineRow,
    ) bool {
        for (self.taxProfiles.draftSummaries()) |*draft| {
            if (std.mem.eql(u8, draft.lifecycleText(), "paid") or
                std.mem.eql(u8, draft.lifecycleText(), "cancelled"))
            {
                continue;
            }
            if (draftMatchesDeadline(draft, deadline)) return true;
        }
        return false;
    }

    fn profileCalendarIncludesDeadline(
        self: *const Model,
        deadline: *const calendar_ui.DeadlineRow,
    ) bool {
        const tax_year = deadline.period.taxableYear() orelse
            deadline.final_deadline.year;
        return self.profileCalendarIncludesFormForYear(
            tax_year,
            deadline.form_code,
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
        return self.taxProfiles.calendarFormSetAvailable(year) and
            (year == 1 or self.taxProfiles.calendarFormSetAvailable(year - 1));
    }

    fn profileCalendarIncludesForm(
        self: *const Model,
        deadline_form_code: []const u8,
    ) bool {
        return self.profileCalendarIncludesFormForYear(
            self.profileCalendar.selected_year,
            deadline_form_code,
        );
    }

    fn profileCalendarIncludesFormForYear(
        self: *const Model,
        tax_year: i32,
        deadline_form_code: []const u8,
    ) bool {
        if (!self.hasSelectedTaxpayer()) return false;
        const selection_code = if (formCodesEquivalent(deadline_form_code, "1604C") or
            formCodesEquivalent(deadline_form_code, "1604F")) "1604CF" else deadline_form_code;
        for (calendar_form_codes) |catalog_code| {
            if (!formCodesEquivalent(catalog_code, selection_code)) continue;
            return self.taxProfiles.formAvailable(
                tax_year,
                catalog_code,
            );
        }
        return false;
    }

    fn selectedProfileCalendarFormCodes(
        self: *const Model,
        arena: std.mem.Allocator,
    ) ![]const []const u8 {
        if (!self.taxProfiles.calendarFormSetConfigured(
            self.calendar.selected_year,
        )) {
            return calendar_form_codes[0..];
        }
        return self.taxProfiles.calendarFormCodes(
            arena,
            self.calendar.selected_year,
        );
    }

    fn selectedProfileCalendarHasForms(self: *const Model) bool {
        if (!self.taxProfiles.calendarFormSetConfigured(
            self.calendar.selected_year,
        )) return true;
        for (calendar_form_codes) |form_code| {
            if (self.taxProfiles.formAvailable(
                self.calendar.selected_year,
                form_code,
            )) return true;
        }
        return false;
    }
};

fn deadlineMarker(count: usize) []const u8 {
    return switch (count) {
        0 => "",
        1 => "•",
        2 => "••",
        3 => "•••",
        4 => "••••",
        else => "•••• +",
    };
}

const CalendarMarkerTone = enum {
    normal,
    approaching,
    due_soon,
    overdue,
};

/// Calendar deadlines currently resolve to a civil date, not a clock time.
/// Treat today and tomorrow as the date-level approximation of "within 24
/// hours", then keep the inclusive seven-day window green.
fn calendarMarkerTone(
    deadline: calendar_domain.Date,
    today: calendar_domain.Date,
) CalendarMarkerTone {
    if (calendar_domain.Date.compare(deadline, today) == .lt) {
        return .overdue;
    }
    const due_soon_through = today.addDays(1) catch today;
    if (calendar_domain.Date.compare(deadline, due_soon_through) != .gt) {
        return .due_soon;
    }
    const approaching_through = today.addDays(7) catch due_soon_through;
    if (calendar_domain.Date.compare(deadline, approaching_through) != .gt) {
        return .approaching;
    }
    return .normal;
}

fn fullMonthName(month: u8) []const u8 {
    return switch (month) {
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

fn shortMonthName(month: u8) []const u8 {
    return switch (month) {
        1 => "Jan",
        2 => "Feb",
        3 => "Mar",
        4 => "Apr",
        5 => "May",
        6 => "Jun",
        7 => "Jul",
        8 => "Aug",
        9 => "Sep",
        10 => "Oct",
        11 => "Nov",
        12 => "Dec",
        else => "",
    };
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

fn draftMatchesDeadline(
    draft: *const profile_ui.DraftSummaryRow,
    deadline: *const calendar_ui.DeadlineRow,
) bool {
    if (!std.ascii.eqlIgnoreCase(draft.formCode(), deadline.form_code)) {
        return false;
    }
    const key = draft.periodKey();
    const taxable_year = deadline.period.taxableYear() orelse return false;
    if (key.len < 4) return false;
    const key_year = std.fmt.parseInt(i32, key[0..4], 10) catch return false;
    if (key_year != taxable_year) return false;
    return switch (deadline.period) {
        .monthly => |period| blk: {
            if (key.len < 6 or key[4] != '-' or
                key[5] == 'Q' or key[5] == 'q') break :blk false;
            const month = std.fmt.parseInt(u8, key[5..], 10) catch
                break :blk false;
            break :blk month == period.month;
        },
        .quarterly => |period| key.len == 7 and key[4] == '-' and
            (key[5] == 'Q' or key[5] == 'q') and
            key[6] == '0' + period.quarter,
        .annual => true,
        .event_based => false,
    };
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
    show_profile_tax,
    show_profile_certificate,
    show_profile_email,
    profile_subject_individual,
    profile_subject_sole_proprietor,
    profile_subject_corporation,
    profile_subject_partnership,
    profile_subject_estate,
    profile_subject_trust,
    profile_subject_other_legal,
    toggle_profile_subject_picker,
    close_profile_subject_picker,
    profile_source_manual,
    profile_source_imported,
    profile_source_migrated,
    profile_gwa_unset,
    profile_gwa_no,
    profile_gwa_yes,
    profile_tin_input: canvas.TextInputEvent,
    profile_rdo_input: canvas.TextInputEvent,
    profile_name_input: canvas.TextInputEvent,
    profile_trade_name_input: canvas.TextInputEvent,
    profile_address_input: canvas.TextInputEvent,
    profile_zip_input: canvas.TextInputEvent,
    profile_phone_input: canvas.TextInputEvent,
    profile_email_input: canvas.TextInputEvent,
    profile_birth_date_input: canvas.TextInputEvent,
    profile_citizenship_input: canvas.TextInputEvent,
    profile_foreign_tax_number_input: canvas.TextInputEvent,
    profile_business_line_input: canvas.TextInputEvent,
    profile_atc_input: canvas.TextInputEvent,
    profile_tax_type_input: canvas.TextInputEvent,
    profile_special_rate_basis_input: canvas.TextInputEvent,
    profile_effective_from_input: canvas.TextInputEvent,
    profile_effective_until_input: canvas.TextInputEvent,
    profile_source_reference_input: canvas.TextInputEvent,
    profile_tax_year_input: canvas.TextInputEvent,
    manage_profile_forms,
    profile_forms_search_input: canvas.TextInputEvent,
    toggle_profile_form: usize,
    profile_forms_select_all,
    profile_forms_clear_all,
    profile_forms_save,
    profile_forms_cancel,
    profile_forms_reset_legacy,
    profile_forms_toggle_filter_active,
    profile_forms_toggle_filter_inactive,
    profile_forms_toggle_filter_editor,
    profile_forms_toggle_filter_calendar_only,
    profile_forms_reset_filters,
    profile_forms_toggle_filter_picker,
    profile_forms_close_filter_picker,
    open_library_form: usize,
    save_profile,
    cancel_profile_edit,
    dismiss_profile_notice,
    profile_notice_timeout: native_sdk.EffectTimer,
    calendar_today_refresh: native_sdk.EffectTimer,
    toggle_profile_actions,
    close_profile_actions,
    show_calendar_deadlines,
    show_calendar_rules,
    show_calendar_overrides,
    calendar_previous_year,
    calendar_next_year,
    calendar_previous_month,
    calendar_next_month,
    global_calendar_previous_month,
    global_calendar_next_month,
    global_calendar_select_day: u8,
    profile_calendar_select_day: u8,
    open_profile_deadline: u64,
    open_profile_action_required: usize,
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
            model.taxProfiles.editSelected();
            openProfileEditor(model);
        },
        .new_taxpayer_profile => {
            if (rejectExact1701QContextChange(model)) {
                reconcileExact1701QTaxpayerSelection(model);
                navigate(model, .form_1701q);
                return;
            }
            model.profileSetupSection = .tax_profile;
            model.profileCompletionTarget = null;
            model.profileCompletionFormIndex = null;
            model.profileFormsFilterPickerVisible = false;
            model.taxProfiles.startNew();
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
        },
        .exact_1701q_validate_full => {
            model.exact1701Q.validateFull();
        },
        .exact_1701q_generate_final_candidate => {
            model.exact1701Q.generateFinalCandidate();
        },
        .exact_1701q_toggle_generated_reveal => {
            model.exact1701Q.toggleGeneratedReveal();
        },
        .exact_1701q_discard_workspace => {
            model.exact1701Q.discardWorkspace();
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
            model.taxProfiles.select(slot);
            model.profileCalendarSelectedDate = null;
            model.profileFormsFilterPickerVisible = false;
            model.profileCompletionTarget = null;
            model.profileCompletionFormIndex = null;
            refreshSelectedProfileFormSet(model);
            resetProfileCalendarExportNotice(model);
            model.dashboardSection = .calendar;
            navigate(model, .taxpayer_dashboard);
        },
        .show_dashboard_calendar => {
            model.profileFormsFilterPickerVisible = false;
            model.dashboardSection = .calendar;
        },
        .show_dashboard_forms => model.dashboardSection = .forms,
        .show_profile_tax => model.profileSetupSection = .tax_profile,
        .show_profile_certificate => model.profileSetupSection = .certificate,
        .show_profile_email => model.profileSetupSection = .email,
        .toggle_profile_subject_picker => {
            model.profileSubjectPickerVisible =
                !model.profileSubjectPickerVisible;
        },
        .close_profile_subject_picker => {
            model.profileSubjectPickerVisible = false;
        },
        .profile_subject_individual => {
            model.taxProfiles.setSubjectKind(.individual);
            model.profileSubjectPickerVisible = false;
        },
        .profile_subject_sole_proprietor => {
            model.taxProfiles.setSubjectKind(.sole_proprietor);
            model.profileSubjectPickerVisible = false;
        },
        .profile_subject_corporation => {
            model.taxProfiles.setSubjectKind(.corporation);
            model.profileSubjectPickerVisible = false;
        },
        .profile_subject_partnership => {
            model.taxProfiles.setSubjectKind(.partnership);
            model.profileSubjectPickerVisible = false;
        },
        .profile_subject_estate => {
            model.taxProfiles.setSubjectKind(.estate);
            model.profileSubjectPickerVisible = false;
        },
        .profile_subject_trust => {
            model.taxProfiles.setSubjectKind(.trust);
            model.profileSubjectPickerVisible = false;
        },
        .profile_subject_other_legal => {
            model.taxProfiles.setSubjectKind(.other_legal_entity);
            model.profileSubjectPickerVisible = false;
        },
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
        .manage_profile_forms => {
            if (!model.taxProfiles.beginManageForms()) return;
            model.profileFormsFilterPickerVisible = false;
            model.dashboardSection = .forms;
            model.profileActionsOpen = false;
            navigate(model, .taxpayer_dashboard);
        },
        .profile_forms_search_input => |edit| {
            model.taxProfiles.applyFormsQuery(edit);
        },
        .toggle_profile_form => |index| {
            model.taxProfiles.toggleStagedForm(index);
        },
        .profile_forms_select_all => model.taxProfiles.selectAllStagedForms(),
        .profile_forms_clear_all => model.taxProfiles.clearAllStagedForms(),
        .profile_forms_save => {
            if (model.taxProfiles.saveManagedForms()) {
                model.profileFormsFilterPickerVisible = false;
                refreshSelectedProfileFormSet(model);
                refreshSelectedProfileCalendar(model);
            }
        },
        .profile_forms_cancel => {
            model.taxProfiles.cancelManageForms();
            model.profileFormsFilterPickerVisible = false;
        },
        .profile_forms_reset_legacy => {
            if (model.taxProfiles.resetManagedFormsToLegacyDefault()) {
                model.profileFormsFilterPickerVisible = false;
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
            model.taxProfiles.resetFormFilters();
        },
        .profile_forms_toggle_filter_picker => {
            model.profileFormsFilterPickerVisible =
                !model.profileFormsFilterPickerVisible;
        },
        .profile_forms_close_filter_picker => {
            model.profileFormsFilterPickerVisible = false;
        },
        .open_library_form => |index| openLibraryForm(model, index),
        .profile_tin_input => |edit| {
            model.taxProfiles.tin.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .profile_rdo_input => |edit| {
            model.taxProfiles.rdo.apply(edit);
            model.taxProfiles.captureInputTruncation();
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
        .profile_tax_year_input => |edit| {
            model.taxProfiles.tax_year.apply(edit);
            model.taxProfiles.captureInputTruncation();
            model.taxProfiles.taxYearInputChanged();
        },
        .save_profile => {
            const exact_material =
                model.exact1701Q.ready() and
                model.exact1701Q.hasDirtyOrMaterialWork();
            const preserves_exact_filer =
                exact_material and
                !model.taxProfiles.editing_new and
                model.exact1701Q.filerProfileMatches(
                    model.taxProfiles.selectedProfileId() orelse "",
                );
            if (exact_material and !preserves_exact_filer) {
                model.exact1701Q.rejectContextChange();
                reconcileExact1701QTaxpayerSelection(model);
                navigate(model, .form_1701q);
                return;
            }
            if (model.taxProfiles.save()) {
                refreshSelectedProfileFormSet(model);
                resetProfileCalendarExportNotice(model);
                closeProfileEditor(model);
                if (preserves_exact_filer) {
                    model.exact1701Q.reportNewerProfileRevision();
                    reconcileExact1701QTaxpayerSelection(model);
                    navigate(model, .form_1701q);
                }
            }
        },
        .cancel_profile_edit => {
            model.taxProfiles.cancelEdit();
            closeProfileEditor(model);
        },
        .dismiss_profile_notice => model.taxProfiles.dismissNotice(),
        .profile_notice_timeout => |timer| {
            profileNoticeTimeout(model, timer);
        },
        .calendar_today_refresh => |timer| {
            refreshCalendarTodayFromClock(model, timer);
        },
        .toggle_profile_actions => model.profileActionsOpen = !model.profileActionsOpen,
        .close_profile_actions => model.profileActionsOpen = false,
        .show_calendar_deadlines => model.taxCalendarSection = .deadlines,
        .show_calendar_rules => model.taxCalendarSection = .rules,
        .show_calendar_overrides => model.taxCalendarSection = .overrides,
        .calendar_previous_year => {
            if (model.taxProfiles.rejectIfFormsDirty()) return;
            model.profileFormsFilterPickerVisible = false;
            model.profileCalendarSelectedDate = null;
            model.calendar.previousYear();
            _ = model.taxProfiles.loadFormsForYear(model.calendar.selected_year);
            refreshSelectedProfileFormSet(model);
        },
        .calendar_next_year => {
            if (model.taxProfiles.rejectIfFormsDirty()) return;
            model.profileFormsFilterPickerVisible = false;
            model.profileCalendarSelectedDate = null;
            model.calendar.nextYear();
            _ = model.taxProfiles.loadFormsForYear(model.calendar.selected_year);
            refreshSelectedProfileFormSet(model);
        },
        .calendar_previous_month => {
            if (model.taxProfiles.rejectIfFormsDirty()) return;
            model.profileCalendarSelectedDate = null;
            const previous_year = model.calendar.selected_year;
            model.calendar.previousMonth();
            if (model.calendar.selected_year != previous_year) {
                model.profileFormsFilterPickerVisible = false;
                _ = model.taxProfiles.loadFormsForYear(model.calendar.selected_year);
                refreshSelectedProfileFormSet(model);
            } else {
                syncSelectedProfileCalendar(model);
                refreshProfileFormLaunchAssessments(model);
            }
        },
        .calendar_next_month => {
            if (model.taxProfiles.rejectIfFormsDirty()) return;
            model.profileCalendarSelectedDate = null;
            const previous_year = model.calendar.selected_year;
            model.calendar.nextMonth();
            if (model.calendar.selected_year != previous_year) {
                model.profileFormsFilterPickerVisible = false;
                _ = model.taxProfiles.loadFormsForYear(model.calendar.selected_year);
                refreshSelectedProfileFormSet(model);
            } else {
                syncSelectedProfileCalendar(model);
                refreshProfileFormLaunchAssessments(model);
            }
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
        .open_profile_deadline => |id| {
            openProfileDeadlineById(model, id);
        },
        .open_profile_action_required => |slot| {
            openProfileActionRequired(model, slot);
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
        .go_back => closeTransient(model),
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
        },
        .viewport_class_changed => |viewport_class| {
            const class_changed = model.viewportClass != viewport_class;
            model.viewportClass = viewport_class;
            model.viewportWidth = nominalWidthForClass(viewport_class);
            if (class_changed) model.profileFormsFilterPickerVisible = false;
            if (!model.isConstrainedViewport()) model.profileActionsOpen = false;
            if (!model.isConstrainedViewport()) {
                model.profileSubjectPickerVisible = false;
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
            if (class_changed) model.profileFormsFilterPickerVisible = false;
            if (!model.isConstrainedViewport()) model.profileActionsOpen = false;
            if (!model.isConstrainedViewport()) {
                model.profileSubjectPickerVisible = false;
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
    model.taxProfiles.refreshCalendarFormSet(
        model.calendar.selected_year,
    ) catch |err| model.calendar.setError(err);
    model.taxProfiles.refreshDraftSummariesForYear(
        model.calendar.selected_year,
    ) catch |err| model.calendar.setError(err);
    refreshProfileFormLaunchAssessments(model);
    syncSelectedProfileCalendar(model);
}

fn refreshProfileFormLaunchAssessments(model: *Model) void {
    model.profileFormLaunchAssessmentsReady = false;
    if (model.formProfiles.allocator == null or
        model.formProfiles.store == null) return;
    const profile_id = model.taxProfiles.selectedProfileDomainId() orelse return;
    const year_value = model.calendar.selected_year;
    if (year_value < 1 or year_value > 9999) return;
    const year: u16 = @intCast(year_value);
    for (&form_catalog.forms, 0..) |*definition, index| {
        model.profileFormLaunchAssessments[index] = .{};
        if (definition.status != .static_layout) continue;
        if (!model.taxProfiles.formAvailable(year_value, definition.code)) {
            continue;
        }
        const revision = editorRevision(definition.code) orelse continue;
        const quarter = selectedFormQuarter(model, definition.code);
        const request: form_ui.OpenRequest = .{
            .form = revision,
            .filer_profile_id = profile_id,
            .tax_year = year,
            .quarter = quarter,
            .profile_as_of = profileAsOfForForm(
                model,
                definition.code,
                year,
                quarter,
                null,
            ),
        };
        model.profileFormLaunchAssessments[index] =
            model.formProfiles.assessLaunch(request);
    }
    model.profileFormLaunchAssessmentsReady = true;
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

fn syncSelectedProfileCalendar(model: *Model) void {
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
        var values: percentage_tax_ui.DraftValueSet = .{};
        const writes = model.percentageTax.draftValueWrites(&values) catch
            return;
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
        // Exact 1701Q persistence remains unavailable until its occurrence
        // adapter and local key-custody policy are connected.
        return;
    }
    _ = model.formProfiles.saveRecurringDraft() catch return;
    model.taxProfiles.refreshDraftSummariesForYear(
        model.calendar.selected_year,
    ) catch |err| {
        model.calendar.setError(err);
    };
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
    if (model.taxpayerFormDisabled(form_code)) return;
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

fn openLibraryForm(model: *Model, index: usize) void {
    if (index >= form_catalog.forms.len) return;
    const definition = &form_catalog.forms[index];
    if (definition.status != .static_layout) return;
    if (!model.taxProfiles.formAvailable(
        model.calendar.selected_year,
        definition.code,
    )) return;
    const launch = assessProfileFormLaunch(
        model,
        definition.code,
        model.calendar.selected_year,
        selectedFormQuarter(model, definition.code),
        null,
    );
    switch (launch.status) {
        .needs_profile => {
            openProfileCompletion(model, index, launch);
            return;
        },
        .profile_not_eligible, .unavailable => return,
        .ready_new, .ready_resume, .needs_activity_selection => {},
    }
    const route = profileFormRoute(definition.code) orelse return;
    openProfileBoundForm(model, route.page, route.form_code);
}

fn assessProfileFormLaunch(
    model: *const Model,
    form_code: []const u8,
    tax_year: i32,
    quarter: u8,
    period_month: ?u8,
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
        .profile_as_of = profileAsOfForForm(
            model,
            form_code,
            year,
            quarter,
            period_month,
        ),
    });
}

fn openProfileCompletion(
    model: *Model,
    form_index: usize,
    assessment: form_ui.LaunchAssessment,
) void {
    model.profileCompletionTarget = assessment.first_missing_field;
    model.profileCompletionFormIndex = form_index;
    model.profileSetupSection = .tax_profile;
    model.taxProfiles.editSelected();
    openProfileEditor(model);
}

fn openProfileDeadlineById(model: *Model, id: u64) void {
    for (model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count]) |*deadline| {
        if (deadline.id != id) continue;
        openProfileDeadline(model, deadline);
        return;
    }
}

fn openProfileActionRequired(model: *Model, slot: usize) void {
    const drafts = model.taxProfiles.draftSummaries();
    if (slot >= drafts.len) return;
    const draft = &drafts[slot];
    for (model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count]) |*deadline| {
        if (!draftMatchesDeadline(draft, deadline)) continue;
        openProfileDeadline(model, deadline);
        return;
    }
}

fn openProfileDeadline(
    model: *Model,
    deadline: *const calendar_ui.DeadlineRow,
) void {
    if (!model.profileCalendarIncludesDeadline(deadline)) return;
    const route = profileFormRoute(deadline.form_code) orelse return;
    const tax_year = deadline.period.taxableYear() orelse
        deadline.final_deadline.year;
    const quarter = deadline.period.quarter() orelse
        @as(u8, 1);
    _ = openProfileBoundFormForQuarter(
        model,
        route.page,
        route.form_code,
        tax_year,
        quarter,
        deadline.period.month(),
        null,
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
) bool {
    if (std.mem.eql(u8, form_code, "1701Q") and
        rejectExact1701QContextChange(model))
    {
        return false;
    }
    const filer_id = model.taxProfiles.selectedProfileDomainId() orelse
        return false;
    if (model.taxpayerFormDisabledForYear(tax_year, form_code)) return false;
    const year_value = tax_year;
    if (year_value < 1 or year_value > 9999) return false;
    const year: u16 = @intCast(year_value);
    const revision = editorRevision(form_code) orelse return false;
    const launch = assessProfileFormLaunch(
        model,
        form_code,
        tax_year,
        quarter,
        period_month,
    );
    switch (launch.status) {
        .needs_profile => {
            const form_index = formCatalogIndex(form_code) orelse return false;
            openProfileCompletion(model, form_index, launch);
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
    const open_request: form_ui.OpenRequest = .{
        .form = revision,
        .filer_profile_id = filer_id,
        .spouse_profile_id = spouse_profile_id,
        .tax_year = year,
        .quarter = quarter,
        .profile_as_of = profile_as_of,
    };
    const open_result = if (std.mem.eql(u8, form_code, "1701Q"))
        model.formProfiles.openExact1701QProjectionOnly(open_request)
    else
        model.formProfiles.open(open_request);
    open_result catch |err| {
        model.percentageTax = .{};
        model.incomeTax = .{};
        if (std.mem.eql(u8, form_code, "1701Q")) {
            model.incomeTax.blockForLoadFailure(err);
            model.exact1701Q.blockOpen(err);
        } else {
            model.exact1701Q.close();
        }
        navigate(model, page);
        return false;
    };
    if (std.mem.eql(u8, form_code, "2551Q")) {
        model.incomeTax = .{};
        model.percentageTax.reset(year, quarter) catch {
            model.percentageTax = .{};
        };
        const loaded_draft = model.formProfiles.loadPersistedDraft() catch |err| {
            model.percentageTax.blockForLoadFailure(err);
            navigate(model, page);
            return true;
        };
        if (loaded_draft) |loaded| {
            var draft = loaded;
            defer model.formProfiles.deinitLoadedDraft(&draft);
            model.percentageTax.loadFromDraft(&draft) catch |err| {
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
        model.exact1701Q.close();
    }
    navigate(model, page);
    return true;
}

fn openExact1701QFilingKind(model: *Model, amended: bool) void {
    if (rejectExact1701QContextChange(model)) return;
    refreshExact1701QFromCurrentProjection(model, amended);
}

fn refreshExact1701QFromCurrentProjection(
    model: *Model,
    amended: bool,
) void {
    const revision = model.formProfiles.formRevision() orelse return;
    if (!std.mem.eql(u8, revision.code.asSlice(), "1701Q")) return;
    const snapshot = model.formProfiles.snapshot() orelse {
        model.exact1701Q.blockOpen(error.ProfileProjectionUnavailable);
        return;
    };
    const quarter: exact_1701q_ui.Quarter = switch (model.formProfiles.quarter()) {
        1 => .first,
        2 => .second,
        3 => .third,
        else => {
            model.exact1701Q.blockOpen(error.InvalidQuarter);
            return;
        },
    };
    const workspace_id =
        model.formProfiles.generateExactWorkspaceId() catch |err| {
            model.exact1701Q.blockOpen(err);
            return;
        };
    _ = model.exact1701Q.open(workspace_id, snapshot, .{
        .tax_year = model.formProfiles.taxYear(),
        .quarter = quarter,
        .amended = amended,
    }) catch |err| {
        model.exact1701Q.blockOpen(err);
        return;
    };
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
    )) {
        model.calendar.selected_month = quarter * 3;
        model.profileCalendarSelectedDate = null;
        syncSelectedProfileCalendar(model);
    }
}

fn navigate(model: *Model, page: Page) void {
    if (model.page == .taxpayer_dashboard and page != .taxpayer_dashboard) {
        model.taxProfiles.resetFormFilters();
    }
    model.page = page;
    model.sidebarOverlayOpen = false;
    model.profileActionsOpen = false;
    model.profileSubjectPickerVisible = false;
    model.profileFormsFilterPickerVisible = false;
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

fn closeProfileEditor(model: *Model) void {
    const destination = model.profileEditorOrigin;
    model.profileEditorOrigin = .global_dashboard;
    model.profileCompletionTarget = null;
    model.profileCompletionFormIndex = null;
    navigate(model, destination);
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
    model.profileActionsOpen = false;
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
    // Form availability is year-specific. Compact a value copy of the
    // already profile-context-resolved calendar before handing it to the ICS
    // serializer, so January obligations use the prior taxable year's Forms
    // Set without mutating either the global or on-screen projections.
    var export_calendar = model.profileCalendar;
    export_calendar.deadline_count = 0;
    for (model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count]) |deadline| {
        if (!model.profileCalendarIncludesDeadline(&deadline)) continue;
        export_calendar.deadlines[export_calendar.deadline_count] = deadline;
        export_calendar.deadline_count += 1;
    }
    const bytes = export_calendar.buildProfileIcs(
        allocator,
        &export_stamp,
        .{
            .key = model.selectedTaxpayerCalendarKey(),
            .name = model.selectedTaxpayerName(),
            .form_scope = .catalog_fallback,
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

pub fn main(init: std.process.Init) !void {
    // This source-selected bootstrap must precede environment inspection,
    // repository path resolution, directory creation, and every storage I/O.
    // It has no runtime selector and current source can mint development
    // plaintext authority only.
    const artifact_storage = key_custody.bootstrapCurrentArtifactStorage();
    const development_plaintext = artifact_storage.development_plaintext;

    canvas.icons.registerAppIcons(&app_icons);
    defer canvas.icons.registerAppIcons(&.{});

    const app_dirs = native_sdk.app_dirs;
    const platform = app_dirs.currentPlatform();
    const environment = native_sdk.debug.envFromMap(init.environ_map);
    var data_dir_buffer: [1024]u8 = undefined;
    const data_dir = init.environ_map.get("EBIRFORMS_DATA_DIR") orelse
        try app_dirs.resolveOne(
            .{ .name = "ebirforms-zero" },
            platform,
            environment,
            .data,
            &data_dir_buffer,
        );
    try std.Io.Dir.cwd().createDirPath(init.io, data_dir);

    var database_path_buffer: [1024]u8 = undefined;
    const database_path = try app_dirs.join(
        platform,
        &database_path_buffer,
        &.{ data_dir, "calendar.sqlite3" },
    );
    var news_database_path_buffer: [1024]u8 = undefined;
    const news_database_path = try app_dirs.join(
        platform,
        &news_database_path_buffer,
        &.{ data_dir, news_store.default_filename },
    );
    var export_path_buffer: [1024]u8 = undefined;
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
        .estate,
        .trust,
        .other_legal_entity,
        => profile_editor.begin(base).legalEntity(.{
            .registered_name = try profile_fields.RegisteredName.parse(name),
            .kind = switch (subject_kind) {
                .corporation => .corporation,
                .partnership => .partnership,
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

fn profileSlotNamed(model: *const Model, name: []const u8) ?usize {
    for (model.profileRows()) |row| {
        if (std.mem.eql(u8, row.nameLabel(), name)) return row.slot;
    }
    return null;
}

test "app calendar icon registers for direct markup tests" {
    canvas.icons.registerAppIcons(&app_icons);
    try std.testing.expect(canvas.icons.resolve("app:calendar") != null);
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
    var model = Model{};

    try std.testing.expectEqualStrings(
        "Active · Any type",
        model.profileFormsFilterSummaryLabel(),
    );
    try std.testing.expectEqualStrings(
        "Filter forms: active, any form type",
        model.profileFormsFilterAccessibleLabel(),
    );
    try std.testing.expect(model.profileFormsFilterActiveSelected());
    try std.testing.expect(!model.profileFormsFilterInactiveSelected());
    try std.testing.expect(model.profileFormsFilterEditorSelected());
    try std.testing.expect(model.profileFormsFilterCalendarOnlySelected());

    update(&model, .profile_forms_toggle_filter_picker);
    try std.testing.expect(model.profileFormsFilterPickerOpen());

    update(&model, .profile_forms_toggle_filter_inactive);
    try std.testing.expect(model.profileFormsFilterPickerOpen());
    try std.testing.expectEqualStrings(
        "All forms",
        model.profileFormsFilterSummaryLabel(),
    );

    update(&model, .profile_forms_toggle_filter_calendar_only);
    try std.testing.expectEqualStrings(
        "All statuses · Editor",
        model.profileFormsFilterSummaryLabel(),
    );
    try std.testing.expectEqualStrings(
        "Filter forms: all statuses, editor available",
        model.profileFormsFilterAccessibleLabel(),
    );

    update(&model, .profile_forms_close_filter_picker);
    try std.testing.expect(!model.profileFormsFilterPickerOpen());

    update(&model, .profile_forms_reset_filters);
    try std.testing.expectEqualStrings(
        "Active · Any type",
        model.profileFormsFilterSummaryLabel(),
    );
}

test "tax form library capability checkboxes partition the catalog" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var model = Model{};
    model.taxProfiles.form_activity_filter = .all;

    update(&model, .profile_forms_toggle_filter_calendar_only);
    const editor_rows = model.profileFormRows(arena);
    try std.testing.expectEqual(form_catalog.editor_count, editor_rows.len);

    update(&model, .profile_forms_reset_filters);
    model.taxProfiles.form_activity_filter = .all;
    update(&model, .profile_forms_toggle_filter_editor);
    const calendar_rows = model.profileFormRows(arena);
    try std.testing.expectEqual(
        form_catalog.calendar_only_count,
        calendar_rows.len,
    );
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

    update(&model, .profile_forms_toggle_filter_calendar_only);
    const editor_rows = model.profileFormRows(arena);
    try std.testing.expectEqual(@as(usize, 1), editor_rows.len);
    try std.testing.expectEqualStrings("2551Q", editor_rows[0].code());

    update(&model, .profile_forms_reset_filters);
    update(&model, .{
        .profile_forms_search_input = .{ .insert_text = "2551q" },
    });
    const search_rows = model.profileFormRows(arena);
    try std.testing.expectEqual(@as(usize, 1), search_rows.len);
    try std.testing.expectEqualStrings("2551Q", search_rows[0].code());

    update(&model, .manage_profile_forms);
    try std.testing.expect(model.taxProfiles.managing_forms);
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

    update(&model, .profile_forms_cancel);
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
    update(&model, .profile_forms_toggle_filter_inactive);
    try std.testing.expectEqualStrings(
        "All forms",
        model.profileFormsFilterSummaryLabel(),
    );

    navigate(&model, .settings);
    try std.testing.expect(!model.profileFormsFilterPickerOpen());
    try std.testing.expectEqualStrings(
        "Active · Any type",
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

    var export_calendar = model.profileCalendar;
    export_calendar.deadline_count = 0;
    for (model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count]) |deadline| {
        if (!model.profileCalendarIncludesDeadline(&deadline)) continue;
        export_calendar.deadlines[export_calendar.deadline_count] = deadline;
        export_calendar.deadline_count += 1;
    }
    const bytes = try export_calendar.buildProfileIcs(
        allocator,
        "20260729T010203Z",
        .{
            .key = model.selectedTaxpayerCalendarKey(),
            .name = model.selectedTaxpayerName(),
            .form_scope = .catalog_fallback,
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
    try std.testing.expect(model.taxpayerForm0605Disabled());
    try std.testing.expect(model.taxpayerForm1701QDisabled());
    try std.testing.expect(model.taxpayerForm2551QDisabled());
    model.page = .taxpayer_dashboard;
    update(&model, .show_form_2551q);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);

    model.calendar.selected_year = 2027;
    refreshSelectedProfileFormSet(&model);
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
    try addTestProfile(
        &store,
        "11111111111111111111111111111111",
        "Juan Dela Cruz",
        "123-456-789-000",
        .individual,
    );

    var model = Model{};
    model.calendar.selected_year = 2026;
    model.calendar.selected_month = 3;
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
    for (rows) |*row| {
        if (!std.mem.eql(u8, row.code(), "2551Q")) continue;
        found = true;
        try std.testing.expectEqual(
            form_ui.LaunchStatus.needs_profile,
            row.launch_assessment.status,
        );
        try std.testing.expectEqualStrings("Complete profile", row.launchLabel());
        try std.testing.expect(!row.launchDisabled());
    }
    try std.testing.expect(found);

    update(&model, .show_form_2551q);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expectEqual(
        profile_fields.ReusableField.contact_number,
        model.profileCompletionTarget.?,
    );
}

test "month navigation refreshes the Forms Set across a year boundary" {
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

    update(&model, .calendar_next_month);
    try std.testing.expectEqual(@as(i32, 2027), model.calendar.selected_year);
    try std.testing.expectEqual(@as(u8, 1), model.calendar.selected_month);
    try std.testing.expect(model.taxpayerForm0605Disabled());
    try std.testing.expect(!model.taxpayerForm2551QDisabled());

    update(&model, .calendar_previous_month);
    try std.testing.expectEqual(@as(i32, 2026), model.calendar.selected_year);
    try std.testing.expectEqual(@as(u8, 12), model.calendar.selected_month);
    try std.testing.expect(!model.taxpayerForm0605Disabled());
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
    try std.testing.expectEqual(
        @as(usize, percentage_tax_ui.max_draft_values),
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
    model.taxProfiles.display_name.set("Unsaved Same Profile Edit");
    try expectAppMarkupBuilds(&model);
    update(&model, .new_taxpayer_profile);
    try std.testing.expectEqual(Page.form_1701q, model.page);
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
    update(&model, .show_profile_setup);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expect(!model.taxProfiles.editing_new);
    try expectAppMarkupBuilds(&model);
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
    openProfileEditor(&model);
    try std.testing.expect(model.taxProfiles.editing_new);
    update(&model, .save_profile);
    try std.testing.expectEqual(Page.form_1701q, model.page);
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
    update(&model, .new_taxpayer_profile);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expect(model.taxProfiles.editing_new);
    model.taxProfiles.tin.set("444-555-666-000");
    model.taxProfiles.rdo.set("040");
    model.taxProfiles.display_name.set("Permitted New Profile");
    model.taxProfiles.registered_address.set("Quezon City");
    model.taxProfiles.effective_from.set("2026-01-01");
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
        @as(usize, 2),
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

test "compact profile actions close after navigation and viewport expansion" {
    var model = Model{
        .page = .taxpayer_dashboard,
        .viewportClass = .phone,
    };
    update(&model, .toggle_profile_actions);
    try std.testing.expect(model.profileActionsOpen);

    update(&model, .show_profile_setup);
    try std.testing.expect(!model.profileActionsOpen);

    model.page = .taxpayer_dashboard;
    update(&model, .{ .viewport_class_changed = .compact });
    update(&model, .toggle_profile_actions);
    try std.testing.expect(model.profileActionsOpen);
    update(&model, .{ .viewport_class_changed = .desktop });
    try std.testing.expect(!model.profileActionsOpen);
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

test "compact wrench dispatches profile settings from its menu" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{
        .page = .taxpayer_dashboard,
        .viewportClass = .compact,
        .viewportWidth = 700,
    };
    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
    var closed_ui = canvas.Ui(Msg).init(arena);
    const closed_tree = try closed_ui.finalize(
        try view.build(&closed_ui, &model),
    );
    const wrench = findWidgetBySemanticsLabel(
        closed_tree.root,
        "Profile actions",
    ).?;
    update(&model, closed_tree.msgForPointer(wrench.id, .up).?);
    try std.testing.expect(model.profileActionsOpen);

    var open_ui = canvas.Ui(Msg).init(arena);
    const open_tree = try open_ui.finalize(try view.build(&open_ui, &model));
    const settings = findWidgetByText(
        open_tree.root,
        .menu_item,
        "Profile Settings",
    ).?;
    try std.testing.expect(
        findWidgetByText(open_tree.root, .menu_item, "Add to Calendar") != null,
    );
    update(&model, open_tree.msgForPointer(settings.id, .up).?);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.profileEditorOrigin);
    try std.testing.expect(!model.profileActionsOpen);
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

test "profile setup cancel returns to its opening page" {
    var model = Model{
        .page = .taxpayer_dashboard,
        .profileSetupSection = .email,
    };
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
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expectEqual(
        Page.global_dashboard,
        model.profileEditorOrigin,
    );
}

test "profile and transient return origins remain independent" {
    var model = Model{ .page = .taxpayer_dashboard };
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

test "successful profile save returns to the tax profile" {
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
    model.taxProfiles.tin.set("123-456-789-000");
    model.taxProfiles.rdo.set("040");
    model.taxProfiles.display_name.set("Navigation Test Taxpayer");
    model.taxProfiles.registered_address.set("Quezon City");
    model.taxProfiles.effective_from.set("2026-01-01");

    update(&model, .save_profile);

    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expectEqual(
        Page.global_dashboard,
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
    try std.testing.expect(!model.taxProfiles.noticeAutoDismissible());
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
    const header_start = std.mem.indexOf(
        u8,
        app_markup,
        "<template name=\"app-mobile-header\">",
    ).?;
    const header_tail = app_markup[header_start..];
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
        app_markup,
        "<template name=\"profile-notice-toast\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "label=\"Dismiss tax profile notification\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
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

    update(&model, .{ .viewport_width_changed = 700 });
    try std.testing.expect(model.globalCalendarHeaderStacked());
    try std.testing.expect(@abs(model.globalCalendarLaneWidth() - 560) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormPickerWidth() - 560) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarDayHeight() - 56) < 0.01);
    try std.testing.expect(model.profileCalendarDayHeight() >= 44);
    try std.testing.expect(model.profileCalendarDayHeight() <= 72);

    update(&model, .{ .viewport_width_changed = 1225 });
    try std.testing.expect(@abs(model.effectiveDashboardWidth() - 976) < 0.01);
    try std.testing.expect(model.globalCalendarLaneWidth() >= 320);
    try std.testing.expect(model.globalCalendarLaneWidth() <= 560);
    try std.testing.expect(@abs(model.globalCalendarFormPickerWidth() - 180) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormRowHeight() - 36) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormOptionsHeight() - 288) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarFormMenuHeight() - 362) < 0.01);

    update(&model, .{ .viewport_width_changed = 1920 });
    try std.testing.expect(@abs(model.globalCalendarLaneWidth() - 560) < 0.01);
    try std.testing.expect(@abs(model.globalCalendarDayHeight() - 64) < 0.01);
    try std.testing.expect(@abs(model.profileCalendarLaneWidth() - 500) < 0.01);
    try std.testing.expect(model.profileCalendarDayHeight() >= 44);
    try std.testing.expect(model.profileCalendarDayHeight() <= 72);
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
    for (model.profileCalendar.deadlines[0..model.profileCalendar.deadline_count]) |*deadline| {
        if (!model.profileCalendarIncludesDeadline(deadline)) continue;
        target = deadline.final_deadline;
        break;
    }
    const deadline = target orelse return error.TestUnexpectedResult;
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
        model.profileFormsFilterPickerVisible = false;
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

        model.profileFormsFilterPickerVisible = true;
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
    const open_button = findWidgetByText(
        library_tree.root,
        .button,
        "Open Form",
    ).?;
    update(&model, library_tree.msgForPointer(open_button.id, .up).?);
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
    // On a phone, Manage Forms is intentionally in the compact profile
    // actions menu rather than consuming header width.
    update(&model, .{ .viewport_width_changed = 408 });
    {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
        var ui = canvas.Ui(Msg).init(arena);
        const closed_tree = try ui.finalize(try view.build(&ui, &model));
        const trigger = findWidgetBySemanticsLabel(
            closed_tree.root,
            "Profile actions",
        ).?;
        update(&model, closed_tree.msgForPointer(trigger.id, .up).?);
    }
    try writeReferenceProofShot(
        &model,
        408,
        800,
        "/tmp/ebirforms-form-activation-shots/01b-actions-phone.png",
    );
    model.profileActionsOpen = false;
    update(&model, .{ .viewport_width_changed = 1176 });

    // Enter the real Manage Forms interaction from the compiled markup.
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
    const closed_tree = try closed_ui.finalize(try view.build(&closed_ui, &model));
    const closed_trigger = findWidgetBySemanticsLabel(
        closed_tree.root,
        "Filter forms: active, any form type",
    ).?;
    try std.testing.expectEqual(canvas.WidgetKind.select, closed_trigger.kind);
    try std.testing.expectEqualStrings("Active · Any type", closed_trigger.text);

    update(&model, closed_tree.msgForPointer(closed_trigger.id, .up).?);
    try std.testing.expect(model.profileFormsFilterPickerOpen());

    var open_ui = canvas.Ui(Msg).init(arena);
    const open_tree = try open_ui.finalize(try view.build(&open_ui, &model));
    const active = findWidgetByText(open_tree.root, .checkbox, "Active").?;
    const inactive = findWidgetByText(open_tree.root, .checkbox, "Inactive").?;
    try std.testing.expect(
        findWidgetByText(open_tree.root, .button, "Reset filters") != null,
    );
    try std.testing.expect(
        findWidgetByText(open_tree.root, .button, "Done") == null,
    );
    try std.testing.expect(active.state.selected);
    try std.testing.expect(active.state.disabled);
    try std.testing.expect(!inactive.state.selected);

    update(&model, open_tree.msgForPointer(inactive.id, .up).?);
    try std.testing.expect(model.profileFormsFilterPickerOpen());

    var toggled_ui = canvas.Ui(Msg).init(arena);
    const toggled_tree = try toggled_ui.finalize(try view.build(&toggled_ui, &model));
    const toggled_trigger = findWidgetBySemanticsLabel(
        toggled_tree.root,
        "Filter forms: all forms",
    ).?;
    try std.testing.expectEqualStrings("All forms", toggled_trigger.text);
    try std.testing.expect(
        findWidgetByText(toggled_tree.root, .checkbox, "Active").?.state.selected,
    );
    try std.testing.expect(
        findWidgetByText(toggled_tree.root, .checkbox, "Inactive").?.state.selected,
    );

    const menu = findWidgetByKind(toggled_tree.root, .dropdown_menu).?;
    update(&model, toggled_tree.msgForDismiss(menu.id).?);
    try std.testing.expect(!model.profileFormsFilterPickerOpen());
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
    const global_tax_calendar_count = model.calendarDeadlines(arena).len;
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
        model.calendarDeadlines(arena).len,
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
    try profile_store_fixture.createDraft(
        .{
            .id = "lane-calendar-2551q-q2",
            .form_code = "2551Q",
            .form_revision = "2018-01-ENCS",
            .period_key = "2026-Q2",
            .profile_as_of = "2026-06-30".*,
            .mapping_revision = form_persistence.mapping_revision_v1,
        },
        &.{.{
            .role = "filer",
            .profile_id = profile_id,
            .profile_revision_id = "rev-lane-calendar-profile",
            .profile_revision_sequence = 1,
        }},
        &.{},
        &.{},
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
    model.calendarToday = matching_deadline.?.final_deadline;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
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
        model.profileActionRequiredRows(arena).len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileCalendarDeadlines(arena).len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.profileUpcomingDeadlines(arena).len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileOverdueDeadlines(arena).len,
    );

    const after_due = try matching_deadline.?.final_deadline.addDays(40);
    model.profileCalendar.selected_month = after_due.month;
    model.calendarToday = after_due;
    var found_overdue_draft = false;
    for (model.profileOverdueDeadlines(arena)) |row| {
        if (draftMatchesDeadline(
            &model.taxProfiles.draftSummaries()[0],
            &row,
        )) {
            found_overdue_draft = true;
            break;
        }
    }
    try std.testing.expect(found_overdue_draft);
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileActionRequiredRows(arena).len,
    );
    model.profileCalendar.selected_month =
        matching_deadline.?.final_deadline.month;
    model.calendarToday = matching_deadline.?.final_deadline;

    try profile_store_fixture.transitionDraft(
        "lane-calendar-2551q-q2",
        "editing",
        "prepared",
    );
    try profile_store_fixture.transitionDraft(
        "lane-calendar-2551q-q2",
        "prepared",
        "queued",
    );
    try profile_store_fixture.transitionDraft(
        "lane-calendar-2551q-q2",
        "queued",
        "submitted",
    );
    try profile_store_fixture.transitionDraft(
        "lane-calendar-2551q-q2",
        "submitted",
        "confirmed",
    );
    try profile_store_fixture.transitionDraft(
        "lane-calendar-2551q-q2",
        "confirmed",
        "paid",
    );
    try model.taxProfiles.refreshDraftSummaries();
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileActionRequiredRows(arena).len,
    );
    for (model.profileUpcomingDeadlines(arena)) |row| {
        if (!std.mem.eql(u8, row.form_code, "2551Q")) continue;
        switch (row.period) {
            .quarterly => |period| try std.testing.expect(
                period.quarter != 2,
            ),
            else => {},
        }
    }

    try profile_store_fixture.replaceFormSet(profile_id, 2026, &.{});
    refreshSelectedProfileFormSet(&model);
    try std.testing.expect(!model.profileCalendarIncludesForm("2551Q"));
    try std.testing.expectEqual(
        @as(usize, 0),
        model.profileCalendarDeadlines(arena).len,
    );
}

test "profile calendar lanes are three columns only on wide layouts" {
    var model = Model{
        .viewportClass = .desktop,
        .viewportWidth = 1_800,
    };
    try std.testing.expect(model.dashboardThreeColumnLayout());
    update(&model, .{ .viewport_class_changed = .rail_regular });
    try std.testing.expect(!model.dashboardThreeColumnLayout());
    update(&model, .{ .viewport_class_changed = .rail_narrow });
    try std.testing.expect(!model.dashboardThreeColumnLayout());
    update(&model, .{ .viewport_class_changed = .phone });
    try std.testing.expect(!model.dashboardThreeColumnLayout());
    try expectAppMarkupBuilds(&model);
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
    const model = Model{};
    try expectAppMarkupBuilds(&model);
}

test "form picker source is scoped only to the global dashboard" {
    const profile_source = @embedFile("pages/taxpayer-dashboard.native");
    const global_source = @embedFile("pages/global-dashboard.fragment");
    const calendar_source = @embedFile("pages/tax-calendar.native");
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
