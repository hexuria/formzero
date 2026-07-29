//! Static eBIRForms application state and Native SDK wiring.
//!
//! The screens remain declarative `.native` templates. Zig owns the small
//! amount of real application state required by the prototype: page
//! selection, appearance preference, and the live system accessibility
//! settings used to resolve design tokens.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const multi_select = @import("components/multi_select.zig");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const canvas_label = "main-canvas";
const window_width: f32 = 1225;
const window_height: f32 = 768;
const phone_breakpoint: f32 = 600;
const compact_shell_breakpoint: f32 = 768;
const rail_shell_breakpoint: f32 = 1100;

const app_permissions = [_][]const u8{
    native_sdk.security.permission_command,
    native_sdk.security.permission_view,
};
const shell_views = [_]native_sdk.ShellView{
    .{
        .label = canvas_label,
        .kind = .gpu_surface,
        .fill = true,
        .role = "eBIRForms application",
        .accessibility_label = "eBIRForms",
        .gpu_backend = .metal,
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

pub const TaxpayerProfile = enum {
    juan_dela_cruz,
    demo_corporation,
    sample_partnership,
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

const form_filter_codes = [_][]const u8{
    // This is the current 51-form registry represented by the reference
    // dashboard. Keep the order stable so menu identity remains stable.
    "0605",
    "1905",
    "1600",
    "1600PT",
    "1600VT",
    "1600WP",
    "1601C",
    "1601E",
    "1601F",
    "0619F",
    "1601FQ",
    "1602",
    "1602Q",
    "1603",
    "1603Q",
    "1604CF",
    "1604E",
    "0620",
    "2316",
    "1700",
    "1701Q",
    "1701",
    "1701A",
    "1702Q",
    "1702",
    "1702RT",
    "1702EX",
    "1702MX",
    "1704",
    "2550M",
    "2550Q",
    "2551Q",
    "2551M",
    "2552",
    "2553",
    "2000",
    "2000OT",
    "2200A",
    "2200AN",
    "2200M",
    "2200P",
    "2200T",
    "2200C",
    "2200S",
    "0619E",
    "1601EQ",
    "1701MS",
    "1706",
    "1707A",
    "1800",
    "1801",
};
const max_rendered_form_options: usize = 9;
const FormFilterState = multi_select.State(form_filter_codes.len, 64);

pub const FormFilterRow = struct {
    id: usize,
    label: []const u8,
    selected: bool,
};

pub const GlobalDeadline = struct {
    id: usize,
    day: u8,
    form_index: usize,
    form: []const u8,
    title: []const u8,
    detail: []const u8,
    openable: bool,
    target: Page,
};

fn formIndex(comptime wanted: []const u8) usize {
    inline for (form_filter_codes, 0..) |code, index| {
        if (std.mem.eql(u8, code, wanted)) return index;
    }
    @compileError("global deadline references an unknown form code: " ++ wanted);
}

const global_deadlines = [_]GlobalDeadline{
    .{
        .id = 1,
        .day = 10,
        .form_index = formIndex("0619E"),
        .form = "0619-E",
        .title = "Withholding Tax Remittance",
        .detail = "Juan Dela Cruz",
        .openable = true,
        .target = .form_0619_e,
    },
    .{
        .id = 2,
        .day = 10,
        .form_index = formIndex("0619F"),
        .form = "0619-F",
        .title = "Final Income Tax Remittance",
        .detail = "Juan Dela Cruz",
        .openable = true,
        .target = .form_0619_f,
    },
    .{
        .id = 3,
        .day = 10,
        .form_index = formIndex("1601C"),
        .form = "1601-C",
        .title = "Compensation Withholding Remittance",
        .detail = "2 taxpayer profiles have this deadline",
        .openable = true,
        .target = .form_1601_c,
    },
    .{
        .id = 4,
        .day = 10,
        .form_index = formIndex("1601E"),
        .form = "1601-E",
        .title = "Expanded Withholding Tax Return",
        .detail = "Juan Dela Cruz",
        .openable = false,
        .target = .global_dashboard,
    },
    .{
        .id = 5,
        .day = 10,
        .form_index = formIndex("1601F"),
        .form = "1601-F",
        .title = "Final Withholding Tax Return",
        .detail = "Juan Dela Cruz",
        .openable = false,
        .target = .global_dashboard,
    },
    .{
        .id = 6,
        .day = 15,
        .form_index = formIndex("1601EQ"),
        .form = "1601-EQ",
        .title = "Quarterly Expanded Withholding Return",
        .detail = "2 taxpayer profiles have this deadline",
        .openable = false,
        .target = .global_dashboard,
    },
    .{
        .id = 7,
        .day = 27,
        .form_index = formIndex("1701Q"),
        .form = "1701Q",
        .title = "Quarterly Income Tax Return",
        .detail = "Juan Dela Cruz",
        .openable = true,
        .target = .form_1701q,
    },
    .{
        .id = 8,
        .day = 27,
        .form_index = formIndex("2550Q"),
        .form = "2550Q",
        .title = "Quarterly VAT Return",
        .detail = "2 taxpayer profiles have this deadline",
        .openable = true,
        .target = .form_2550q,
    },
    .{
        .id = 9,
        .day = 31,
        .form_index = formIndex("2551Q"),
        .form = "2551Q",
        .title = "Quarterly Percentage Tax Return",
        .detail = "2 taxpayer profiles have this deadline",
        .openable = true,
        .target = .form_2551q,
    },
    .{
        .id = 10,
        .day = 31,
        .form_index = formIndex("1601FQ"),
        .form = "1601-FQ",
        .title = "Quarterly Final Withholding Return",
        .detail = "Juan Dela Cruz",
        .openable = false,
        .target = .global_dashboard,
    },
    .{
        .id = 11,
        .day = 31,
        .form_index = formIndex("1702Q"),
        .form = "1702Q",
        .title = "Quarterly Corporate Income Tax Return",
        .detail = "Demo Corporation",
        .openable = false,
        .target = .global_dashboard,
    },
    .{
        .id = 12,
        .day = 31,
        .form_index = formIndex("1603"),
        .form = "1603",
        .title = "Final Income Tax Withheld Return",
        .detail = "Juan Dela Cruz",
        .openable = false,
        .target = .global_dashboard,
    },
};

pub const Model = struct {
    page: Page = .global_dashboard,
    returnPage: Page = .global_dashboard,
    selectedTaxpayer: TaxpayerProfile = .juan_dela_cruz,
    dashboardSection: DashboardSection = .calendar,
    profileSetupSection: ProfileSetupSection = .tax_profile,
    taxCalendarSection: TaxCalendarSection = .deadlines,
    backgroundTasksSection: BackgroundTasksSection = .jobs,
    formFilter: FormFilterState = FormFilterState.allSelected(),
    themePreference: ThemePreference = .system,
    sidebarPreference: SidebarPreference = .expanded,
    sidebarOverlayOpen: bool = false,
    // Native list items retain pointer-selected state internally. Changing
    // this sibling-scoped key after a dock action remounts those rows so
    // their gray surface remains a hover affordance, never a selection.
    sidebarActionEpoch: u64 = 0,
    viewportClass: ViewportClass = .desktop,
    systemColorScheme: native_sdk.ColorScheme = .light,
    reduceMotion: bool = false,
    highContrast: bool = false,

    // These values drive Zig-owned tokens rather than markup bindings.
    pub const view_unbound = .{
        "sidebarPreference",
        "sidebarOverlayOpen",
        "viewportClass",
        "returnPage",
        "selectedTaxpayer",
        "dashboardSection",
        "profileSetupSection",
        "taxCalendarSection",
        "backgroundTasksSection",
        "formFilter",
        "systemColorScheme",
        "reduceMotion",
        "highContrast",
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

    /// Auxiliary surfaces sit above the shell while the page that opened
    /// them remains visible underneath.
    pub fn contentPage(self: *const Model) Page {
        return if (isAuxiliaryPage(self.page)) self.returnPage else self.page;
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

    pub fn selectedTaxpayerName(self: *const Model) []const u8 {
        return switch (self.selectedTaxpayer) {
            .juan_dela_cruz => "Juan Dela Cruz",
            .demo_corporation => "Demo Corporation",
            .sample_partnership => "Sample Partnership",
        };
    }

    pub fn selectedTaxpayerTin(self: *const Model) []const u8 {
        return switch (self.selectedTaxpayer) {
            .juan_dela_cruz => "000-000-000-00000",
            .demo_corporation => "111-111-111-00000",
            .sample_partnership => "222-222-222-00000",
        };
    }

    pub fn selectedTaxpayerKind(self: *const Model) []const u8 {
        return switch (self.selectedTaxpayer) {
            .juan_dela_cruz => "Individual",
            .demo_corporation => "Corporation",
            .sample_partnership => "Partnership",
        };
    }

    pub fn selectedTaxpayerInitials(self: *const Model) []const u8 {
        return switch (self.selectedTaxpayer) {
            .juan_dela_cruz => "JD",
            .demo_corporation => "DC",
            .sample_partnership => "SP",
        };
    }

    pub fn juanProfileActive(self: *const Model) bool {
        return self.selectedTaxpayer == .juan_dela_cruz;
    }

    pub fn demoProfileActive(self: *const Model) bool {
        return self.selectedTaxpayer == .demo_corporation;
    }

    pub fn partnershipProfileActive(self: *const Model) bool {
        return self.selectedTaxpayer == .sample_partnership;
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

    pub fn backgroundJobsActive(self: *const Model) bool {
        return self.backgroundTasksSection == .jobs;
    }

    pub fn backgroundLogsActive(self: *const Model) bool {
        return self.backgroundTasksSection == .logs;
    }

    pub fn formFilterOpen(self: *const Model) bool {
        return self.formFilter.isOpen();
    }

    /// The closed face summarizes selection; the open face is the live query.
    pub fn formFilterText(self: *const Model, arena: std.mem.Allocator) []const u8 {
        if (self.formFilter.isOpen()) return self.formFilter.query();

        const count = self.formFilter.selectedCount();
        if (count == 0) return "Select forms...";
        return std.fmt.allocPrint(arena, "{d} selected", .{count}) catch "Selected forms";
    }

    /// The anchored menu stays bounded; typing exposes matches beyond this
    /// first view-sized page without mounting all registry rows at once.
    pub fn visibleFormOptions(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const FormFilterRow {
        const visible_count = @min(self.filteredFormOptionCount(), max_rendered_form_options);
        if (visible_count == 0) return &.{};

        const rows = arena.alloc(FormFilterRow, visible_count) catch return &.{};
        var output_index: usize = 0;
        for (form_filter_codes, 0..) |code, index| {
            if (!self.formFilter.matches(code)) continue;
            if (output_index == rows.len) break;

            rows[output_index] = .{
                .id = index,
                .label = code,
                .selected = self.formFilter.isSelected(index),
            };
            output_index += 1;
        }
        return rows[0..output_index];
    }

    pub fn formFilterAllFilteredSelected(self: *const Model) bool {
        var found_match = false;
        for (form_filter_codes, 0..) |code, index| {
            if (!self.formFilter.matches(code)) continue;
            found_match = true;
            if (!self.formFilter.isSelected(index)) return false;
        }
        return found_match;
    }

    pub fn formFilterHiddenCount(self: *const Model) usize {
        return self.filteredFormOptionCount() -| max_rendered_form_options;
    }

    /// Deadline rows are derived from the selection on every rebuild. No
    /// secondary cache or selection callback can leave calendar content stale.
    pub fn visibleGlobalDeadlines(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const GlobalDeadline {
        const rows = arena.alloc(GlobalDeadline, global_deadlines.len) catch return &.{};
        var count: usize = 0;
        for (global_deadlines) |deadline| {
            if (!self.formFilter.isSelected(deadline.form_index)) continue;
            rows[count] = deadline;
            count += 1;
        }
        return rows[0..count];
    }

    pub fn hasVisibleGlobalDeadlines(self: *const Model) bool {
        for (global_deadlines) |deadline| {
            if (self.formFilter.isSelected(deadline.form_index)) return true;
        }
        return false;
    }

    pub fn calendarDay10Marker(self: *const Model) []const u8 {
        return self.deadlineMarkerForDay(10);
    }

    pub fn calendarDay15Marker(self: *const Model) []const u8 {
        return self.deadlineMarkerForDay(15);
    }

    pub fn calendarDay27Marker(self: *const Model) []const u8 {
        return self.deadlineMarkerForDay(27);
    }

    pub fn calendarDay31Marker(self: *const Model) []const u8 {
        return self.deadlineMarkerForDay(31);
    }

    fn filteredFormOptionCount(self: *const Model) usize {
        var count: usize = 0;
        for (form_filter_codes) |code| {
            if (self.formFilter.matches(code)) count += 1;
        }
        return count;
    }

    fn setFilteredFormOptions(self: *Model, selected: bool) void {
        for (form_filter_codes, 0..) |code, index| {
            if (!self.formFilter.matches(code)) continue;
            _ = self.formFilter.set(index, selected);
        }
    }

    fn deadlineMarkerForDay(self: *const Model, day: u8) []const u8 {
        var count: usize = 0;
        for (global_deadlines) |deadline| {
            if (deadline.day == day and self.formFilter.isSelected(deadline.form_index)) {
                count += 1;
            }
        }

        return switch (count) {
            0 => "",
            1 => "•",
            2 => "••",
            3 => "•••",
            4 => "••••",
            else => "•••• +",
        };
    }
};

pub const Msg = union(enum) {
    show_global_dashboard,
    show_taxpayer_dashboard,
    show_profile_setup,
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
    show_aux_lock_screen,
    show_aux_profile_auth_overlay,
    show_aux_admin_auth_overlay,
    show_aux_command_palette,
    show_aux_html_print_preview,
    show_aux_email_confirmation,
    show_aux_background_task_debug_log,
    select_taxpayer: TaxpayerProfile,
    show_dashboard_calendar,
    show_dashboard_forms,
    show_profile_tax,
    show_profile_certificate,
    show_profile_email,
    show_calendar_deadlines,
    show_calendar_rules,
    show_calendar_overrides,
    show_background_jobs,
    show_background_logs,
    multi_select_toggle,
    multi_select_close,
    multi_select_query_changed: canvas.TextInputEvent,
    multi_select_toggle_option: usize,
    multi_select_select_all_filtered,
    multi_select_clear_all,
    show_deadline_form: Page,
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
    viewport_class_changed: ViewportClass,
    appearance_changed: native_sdk.Appearance,

    // The host sends viewport/appearance changes. `hide_sidebar` remains a
    // model-level transition for tests and constrained-shell handoff, while
    // the visible desktop control now mirrors GPUI's single chevron toggle.
    pub const view_unbound = .{
        "appearance_changed",
        "viewport_class_changed",
        "hide_sidebar",
    };
};

pub fn update(model: *Model, msg: Msg) void {
    switch (msg) {
        .show_global_dashboard => navigate(model, .global_dashboard),
        .show_taxpayer_dashboard => navigate(model, .taxpayer_dashboard),
        .show_profile_setup => openReturnablePage(model, .profile_setup),
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
        .show_form_0605 => navigate(model, .form_0605),
        .show_form_0619_e => navigate(model, .form_0619_e),
        .show_form_0619_f => navigate(model, .form_0619_f),
        .show_form_1601_c => navigate(model, .form_1601_c),
        .show_form_1701 => navigate(model, .form_1701),
        .show_form_1701q => navigate(model, .form_1701q),
        .show_form_1702_rt => navigate(model, .form_1702_rt),
        .show_form_1702_mx => navigate(model, .form_1702_mx),
        .show_form_2550q => navigate(model, .form_2550q),
        .show_form_2551q => navigate(model, .form_2551q),
        .show_aux_lock_screen => openTransient(model, .aux_lock_screen),
        .show_aux_profile_auth_overlay => openTransient(model, .aux_profile_auth),
        .show_aux_admin_auth_overlay => openTransient(model, .aux_admin_auth),
        .show_aux_command_palette => openTransient(model, .aux_command_palette),
        .show_aux_html_print_preview => openTransient(model, .aux_html_preview),
        .show_aux_email_confirmation => openTransient(model, .aux_email_confirmation),
        .show_aux_background_task_debug_log => openTransient(model, .aux_debug_log),
        .select_taxpayer => |profile| {
            model.selectedTaxpayer = profile;
            model.dashboardSection = .calendar;
            navigate(model, .taxpayer_dashboard);
        },
        .show_dashboard_calendar => model.dashboardSection = .calendar,
        .show_dashboard_forms => model.dashboardSection = .forms,
        .show_profile_tax => model.profileSetupSection = .tax_profile,
        .show_profile_certificate => model.profileSetupSection = .certificate,
        .show_profile_email => model.profileSetupSection = .email,
        .show_calendar_deadlines => model.taxCalendarSection = .deadlines,
        .show_calendar_rules => model.taxCalendarSection = .rules,
        .show_calendar_overrides => model.taxCalendarSection = .overrides,
        .show_background_jobs => model.backgroundTasksSection = .jobs,
        .show_background_logs => model.backgroundTasksSection = .logs,
        .multi_select_toggle => model.formFilter.togglePicker(),
        .multi_select_close => model.formFilter.closePicker(),
        .multi_select_query_changed => |edit| model.formFilter.applyQuery(edit),
        .multi_select_toggle_option => |index| {
            _ = model.formFilter.toggle(index);
        },
        .multi_select_select_all_filtered => model.setFilteredFormOptions(true),
        .multi_select_clear_all => {
            _ = model.formFilter.clear();
        },
        .show_deadline_form => |page| navigate(model, page),
        .go_back => {
            const destination = model.returnPage;
            model.returnPage = .global_dashboard;
            navigate(model, destination);
        },
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
        .viewport_class_changed => |viewport_class| {
            model.viewportClass = viewport_class;
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

fn navigate(model: *Model, page: Page) void {
    model.page = page;
    model.sidebarOverlayOpen = false;
}

fn bumpSidebarActionEpoch(model: *Model) void {
    model.sidebarActionEpoch +%= 1;
}

fn openTransient(model: *Model, page: Page) void {
    if (model.page != page) model.returnPage = model.page;
    navigate(model, page);
}

fn openReturnablePage(model: *Model, page: Page) void {
    if (model.page != page) model.returnPage = model.page;
    navigate(model, page);
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
    const viewport_class = viewportClassForWidth(frame.size.width);
    if (model.viewportClass == viewport_class) return null;
    return .{ .viewport_class_changed = viewport_class };
}

fn viewportClassForWidth(width: f32) ViewportClass {
    if (width < phone_breakpoint) return .phone;
    if (width < compact_shell_breakpoint) return .compact;
    if (width < 900) return .rail_narrow;
    if (width < rail_shell_breakpoint) return .rail_regular;
    return .desktop;
}

const Effects = native_sdk.Effects(Msg);

fn registerBootImages(_: *Model, fx: *Effects) void {
    fx.loadImage(.{ .id = 1, .path = "assets/brand/ebirforms.png" });
    fx.loadImage(.{ .id = 2, .path = "assets/brand/bagong-pilipinas.png" });
    fx.loadImage(.{ .id = 3, .path = "assets/brand/bir-new-logo.png" });
    fx.loadImage(.{ .id = 4, .path = "assets/brand/goldcoders-logo.png" });
    fx.loadImage(.{ .id = 6, .path = "assets/icon.png" });
}

const EbirFormsApp = native_sdk.UiApp(Model, Msg);
pub const app_markup = @embedFile("app.native");
const multi_select_component_markup = @embedFile("components/multi-select-combobox.native");
const multi_select_component_fixture = multi_select_component_markup ++
    \\
    \\<column>
    \\  <use
    \\    template="multi-select-combobox"
    \\    value="{formFilterText}"
    \\    open="{formFilterOpen}"
    \\    options="{visibleFormOptions}"
    \\    allselected="{formFilterAllFilteredSelected}"
    \\    hiddencount="{formFilterHiddenCount}"
    \\    width="240"
    \\    menuheight="420"
    \\    placeholder="Search form codes..."
    \\    label="Filter compliance calendar forms"/>
    \\</column>
;

pub fn main(init: std.process.Init) !void {
    const app_state = try EbirFormsApp.create(std.heap.page_allocator, .{
        .name = "ebirforms-zero",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update = update,
        .init_fx = registerBootImages,
        .on_appearance = appearanceMessage,
        .on_frame = frameMessage,
        .tokens_fn = appTokens,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = .{};

    try runner.runWithOptions(app_state.app(), .{
        .app_name = "ebirforms-zero",
        .window_title = "eBIRForms",
        .bundle_id = "dev.goldcoders.ebirforms.static",
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

test "sidebar can be collapsed hidden and restored without losing its route" {
    var model = Model{ .page = .tax_calendar };
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
    var model = Model{};
    try std.testing.expect(model.juanProfileActive());
    try std.testing.expect(!model.demoProfileActive());
    try std.testing.expect(!model.partnershipProfileActive());

    update(&model, .{ .select_taxpayer = .demo_corporation });
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expectEqual(TaxpayerProfile.demo_corporation, model.selectedTaxpayer);
    try std.testing.expectEqualStrings("Demo Corporation", model.selectedTaxpayerName());
    try std.testing.expect(!model.juanProfileActive());
    try std.testing.expect(model.demoProfileActive());
    try std.testing.expect(!model.partnershipProfileActive());

    update(&model, .show_dashboard_forms);
    try std.testing.expect(model.dashboardFormsActive());
    update(&model, .show_dashboard_calendar);
    try std.testing.expect(model.dashboardCalendarActive());

    update(&model, .show_profile_setup);
    update(&model, .show_profile_email);
    try std.testing.expect(model.profileEmailActive());

    update(&model, .show_screen_gallery);
    try std.testing.expect(model.demoProfileActive());
}

test "transient pages return to their exact origin" {
    var model = Model{ .page = .form_1701q };
    update(&model, .show_aux_html_print_preview);
    try std.testing.expectEqual(Page.aux_html_preview, model.page);
    try std.testing.expectEqual(Page.form_1701q, model.returnPage);
    try std.testing.expectEqual(Page.form_1701q, model.contentPage());

    update(&model, .go_back);
    try std.testing.expectEqual(Page.form_1701q, model.page);
    try std.testing.expectEqual(Page.global_dashboard, model.returnPage);
}

test "profile setup cancel returns to its opening page" {
    var model = Model{ .page = .taxpayer_dashboard };
    update(&model, .show_profile_setup);
    try std.testing.expectEqual(Page.profile_setup, model.page);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.returnPage);

    update(&model, .go_back);
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
}

test "viewport classes cover phone compact tablet and desktop breakpoints" {
    try std.testing.expectEqual(ViewportClass.phone, viewportClassForWidth(390));
    try std.testing.expectEqual(ViewportClass.compact, viewportClassForWidth(620));
    try std.testing.expectEqual(ViewportClass.rail_narrow, viewportClassForWidth(800));
    try std.testing.expectEqual(ViewportClass.rail_regular, viewportClassForWidth(1024));
    try std.testing.expectEqual(ViewportClass.desktop, viewportClassForWidth(1225));
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

test "multi-select component dispatches open search toggle and dismiss interactions" {
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
    const closed_combobox = findWidgetByKind(closed_tree.root, .combobox).?;
    try std.testing.expectEqualStrings("51 selected", closed_combobox.text);

    update(&model, closed_tree.msgForPointer(closed_combobox.id, .up).?);
    try std.testing.expect(model.formFilter.isOpen());

    var open_ui = canvas.Ui(Msg).init(arena);
    const open_tree = try open_ui.finalize(try view.build(&open_ui, &model));
    const open_combobox = findWidgetByKind(open_tree.root, .combobox).?;
    const first_option = findWidgetByText(open_tree.root, .menu_item, "0605").?;
    try std.testing.expectEqualStrings("", open_combobox.text);
    try std.testing.expect(first_option.state.selected);

    update(
        &model,
        open_tree.msgForTextEdit(
            open_combobox.id,
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
    try std.testing.expectEqualStrings("•••• +", model.calendarDay10Marker());

    update(
        &model,
        filtered_tree.msgForPointer(matching_option.id, .up).?,
    );
    try std.testing.expectEqual(@as(usize, 50), model.formFilter.selectedCount());
    try std.testing.expectEqualStrings("••••", model.calendarDay10Marker());

    var toggled_ui = canvas.Ui(Msg).init(arena);
    const toggled_tree = try toggled_ui.finalize(try view.build(&toggled_ui, &model));
    const toggled_option = findWidgetByText(
        toggled_tree.root,
        .menu_item,
        "0619E",
    ).?;
    try std.testing.expect(!toggled_option.state.selected);

    const menu = findWidgetByKind(toggled_tree.root, .dropdown_menu).?;
    update(&model, toggled_tree.msgForDismiss(menu.id).?);
    try std.testing.expect(!model.formFilter.isOpen());

    var dismissed_ui = canvas.Ui(Msg).init(arena);
    const dismissed_tree = try dismissed_ui.finalize(try view.build(&dismissed_ui, &model));
    const dismissed_combobox = findWidgetByKind(dismissed_tree.root, .combobox).?;
    try std.testing.expectEqualStrings("50 selected", dismissed_combobox.text);
}

test "form selection directly derives deadline rows and calendar markers" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var model = Model{};
    update(&model, .multi_select_clear_all);

    try std.testing.expectEqual(@as(usize, 0), model.formFilter.selectedCount());
    try std.testing.expect(!model.hasVisibleGlobalDeadlines());
    try std.testing.expectEqual(@as(usize, 0), model.visibleGlobalDeadlines(arena).len);
    try std.testing.expectEqualStrings("", model.calendarDay10Marker());
    try std.testing.expectEqualStrings("", model.calendarDay15Marker());
    try std.testing.expectEqualStrings("", model.calendarDay27Marker());
    try std.testing.expectEqualStrings("", model.calendarDay31Marker());

    update(&model, .multi_select_toggle);
    update(
        &model,
        .{ .multi_select_query_changed = .{ .insert_text = "2551Q" } },
    );
    update(&model, .multi_select_select_all_filtered);

    const deadlines = model.visibleGlobalDeadlines(arena);
    try std.testing.expectEqual(@as(usize, 1), model.formFilter.selectedCount());
    try std.testing.expectEqual(@as(usize, 1), deadlines.len);
    try std.testing.expectEqualStrings("2551Q", deadlines[0].form);
    try std.testing.expectEqualStrings("•", model.calendarDay31Marker());
}
