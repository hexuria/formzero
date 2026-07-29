//! Static eBIRForms application state and Native SDK wiring.
//!
//! The screens remain declarative `.native` templates. Zig owns the small
//! amount of real application state required by the prototype: page
//! selection, appearance preference, and the live system accessibility
//! settings used to resolve design tokens.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");

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

pub const Model = struct {
    page: Page = .global_dashboard,
    returnPage: Page = .global_dashboard,
    selectedTaxpayer: TaxpayerProfile = .juan_dela_cruz,
    dashboardSection: DashboardSection = .calendar,
    profileSetupSection: ProfileSetupSection = .tax_profile,
    taxCalendarSection: TaxCalendarSection = .deadlines,
    backgroundTasksSection: BackgroundTasksSection = .jobs,
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
        return self.page == .taxpayer_dashboard and
            self.selectedTaxpayer == .juan_dela_cruz;
    }

    pub fn demoProfileActive(self: *const Model) bool {
        return self.page == .taxpayer_dashboard and
            self.selectedTaxpayer == .demo_corporation;
    }

    pub fn partnershipProfileActive(self: *const Model) bool {
        return self.page == .taxpayer_dashboard and
            self.selectedTaxpayer == .sample_partnership;
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
    update(&model, .{ .select_taxpayer = .demo_corporation });
    try std.testing.expectEqual(Page.taxpayer_dashboard, model.page);
    try std.testing.expectEqual(TaxpayerProfile.demo_corporation, model.selectedTaxpayer);
    try std.testing.expectEqualStrings("Demo Corporation", model.selectedTaxpayerName());

    update(&model, .show_dashboard_forms);
    try std.testing.expect(model.dashboardFormsActive());
    update(&model, .show_dashboard_calendar);
    try std.testing.expect(model.dashboardCalendarActive());

    update(&model, .show_profile_setup);
    update(&model, .show_profile_email);
    try std.testing.expect(model.profileEmailActive());
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
