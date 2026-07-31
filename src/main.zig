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
const calendar_ui = @import("calendar/ui_state.zig");
const profile_ui = @import("tax_profile/ui_state.zig");
const profile_store = @import("tax_profile/store.zig");
const profile_persistence = @import("tax_profile/persistence_adapter.zig");
const profile_editor = @import("tax_profile/editor.zig");
const profile_fields = @import("tax_profile/field.zig");
const profile_model = @import("tax_profile/model.zig");
const form_ui = @import("forms/ui_state.zig");
const form_ids = @import("forms/id.zig");
const form_catalog = @import("forms/generated/catalog.zig");
const income_tax_ui = @import("forms/income_tax_ui_state.zig");
const percentage_tax_ui = @import("forms/percentage_tax_ui_state.zig");
const c_time = @cImport({
    @cInclude("time.h");
});

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

const ProfileCalendarExportStatus = enum {
    idle,
    wrong_context,
    no_profile,
    unavailable,
    build_failed,
    writing,
    opening,
    opened,
    write_failed,
    opener_unavailable,
    unsupported_platform,
    open_failed,
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

pub const FormProfileChoiceRow = struct {
    id: usize,
    stable_id: []const u8,
    name: []const u8,
    selected: bool,

    pub fn idLabel(self: *const FormProfileChoiceRow) []const u8 {
        return self.stable_id;
    }
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
    profileEditorOrigin: Page = .global_dashboard,
    overlayReturnPage: Page = .global_dashboard,
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
    calendar: calendar_ui.State = .{},
    taxProfiles: profile_ui.State = .{},
    formProfiles: form_ui.State = .{},
    incomeTax: income_tax_ui.State = .{},
    percentageTax: percentage_tax_ui.State = .{},
    calendarExportProfileRevision: ?profile_ui.RevisionContext = null,
    profileCalendarExportStatus: ProfileCalendarExportStatus = .idle,
    profileActionsOpen: bool = false,
    profileNoticeTimerKey: u64 = 0,

    // These values drive Zig-owned tokens rather than markup bindings.
    pub const view_unbound = .{
        "sidebarPreference",
        "sidebarOverlayOpen",
        "viewportClass",
        "profileEditorOrigin",
        "overlayReturnPage",
        "profileSetupSection",
        "taxCalendarSection",
        "backgroundTasksSection",
        "formFilter",
        "systemColorScheme",
        "reduceMotion",
        "highContrast",
        "calendar",
        "taxProfiles",
        "formProfiles",
        "incomeTax",
        "percentageTax",
        "calendarExportProfileRevision",
        "profileCalendarExportStatus",
        "profileNoticeTimerKey",
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
        return if (isAuxiliaryPage(self.page))
            self.overlayReturnPage
        else
            self.page;
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

    pub fn profileRows(self: *const Model) []const profile_ui.ProfileRow {
        return self.taxProfiles.rows();
    }

    pub fn profileRowsEmpty(self: *const Model) bool {
        return self.taxProfiles.rowsEmpty();
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
        if (!self.hasSelectedTaxpayer()) return true;
        return !self.taxProfiles.formAvailable(
            self.calendar.selected_year,
            form_code,
        );
    }

    pub fn taxpayerForm0605Disabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("0605");
    }

    pub fn taxpayerForm0619EDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("0619E");
    }

    pub fn taxpayerForm0619FDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("0619F");
    }

    pub fn taxpayerForm1601CDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("1601C");
    }

    pub fn taxpayerForm1701Disabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("1701");
    }

    pub fn taxpayerForm1701QDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("1701Q");
    }

    pub fn taxpayerForm1702RTDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("1702RT");
    }

    pub fn taxpayerForm1702MXDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("1702MX");
    }

    pub fn taxpayerForm2550QDisabled(self: *const Model) bool {
        return self.taxpayerFormDisabled("2550Q");
    }

    pub fn taxpayerForm2551QDisabled(self: *const Model) bool {
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
            return !self.incomeTax.saveDisabled();
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

    pub fn profileFormsSetFallbackSelected(self: *const Model) bool {
        return !self.taxProfiles.forms_set_configured;
    }

    pub fn profileFormsSetRegisteredSelected(self: *const Model) bool {
        return self.taxProfiles.forms_set_configured;
    }

    pub fn profileFormsSetInputDisabled(self: *const Model) bool {
        return !self.taxProfiles.forms_set_configured;
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
        return std.fmt.allocPrint(
            arena,
            "{d} scheduled deadlines",
            .{self.calendar.deadline_count},
        ) catch "";
    }

    pub fn calendarVisibleDeadlineCount(
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const u8 {
        var count: usize = 0;
        for (self.calendar.deadlines[0..self.calendar.deadline_count]) |row| {
            if (row.final_deadline.month == self.calendar.selected_month) count += 1;
        }
        return std.fmt.allocPrint(arena, "{d} deadlines this month", .{count}) catch "";
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
        self: *const Model,
        arena: std.mem.Allocator,
    ) []const calendar_ui.RuleRow {
        _ = self;
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
        // Successful reloads and edits are already reflected by the calendar
        // content itself. Keep the inline notice for actionable failures only;
        // a permanent "loaded" badge wastes scarce calendar-screen space.
        return self.calendar.notice.len != 0 and
            self.calendar.notice_kind == .failure;
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

    pub fn profileCalendarExportNotice(self: *const Model) []const u8 {
        return switch (self.profileCalendarExportStatus) {
            .idle => "",
            .wrong_context => "Calendar export must be started from the selected tax profile.",
            .no_profile => "Create or select a tax profile before exporting its calendar.",
            .unavailable => "Calendar export is unavailable in this test context.",
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

    pub fn profileCalendarExportNoticeTone(self: *const Model) []const u8 {
        return switch (self.profileCalendarExportStatus) {
            .opened => "primary",
            .wrong_context,
            .no_profile,
            .unavailable,
            .build_failed,
            .write_failed,
            .opener_unavailable,
            .unsupported_platform,
            .open_failed,
            => "destructive",
            .idle,
            .writing,
            .opening,
            => "secondary",
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

    pub fn formFilterOpen(self: *const Model) bool {
        return self.formFilter.isOpen();
    }

    pub fn formFilterText(self: *const Model, arena: std.mem.Allocator) []const u8 {
        const count = self.formFilter.selectedCount();
        if (count == 0) return "Select forms...";
        return std.fmt.allocPrint(arena, "{d} selected", .{count}) catch "Selected forms";
    }

    pub fn formFilterQuery(self: *const Model) []const u8 {
        return self.formFilter.query();
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
    profile_source_manual,
    profile_source_imported,
    profile_source_migrated,
    profile_gwa_unset,
    profile_gwa_no,
    profile_gwa_yes,
    profile_forms_set_fallback,
    profile_forms_set_registered,
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
    profile_forms_set_input: canvas.TextInputEvent,
    save_profile,
    cancel_profile_edit,
    dismiss_profile_notice,
    profile_notice_timeout: native_sdk.EffectTimer,
    toggle_profile_actions,
    close_profile_actions,
    show_calendar_deadlines,
    show_calendar_rules,
    show_calendar_overrides,
    calendar_previous_year,
    calendar_next_year,
    calendar_previous_month,
    calendar_next_month,
    calendar_refresh,
    profile_calendar_export,
    profile_calendar_export_written: native_sdk.EffectFileResult,
    profile_calendar_export_opened: native_sdk.EffectExit,
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
    viewport_class_changed: ViewportClass,
    appearance_changed: native_sdk.Appearance,

    // The host sends viewport/appearance changes. `hide_sidebar` remains a
    // model-level transition for tests and constrained-shell handoff, while
    // the visible desktop control now mirrors GPUI's single chevron toggle.
    pub const view_unbound = .{
        "appearance_changed",
        "viewport_class_changed",
        "hide_sidebar",
        "profile_calendar_export_written",
        "profile_calendar_export_opened",
        "profile_notice_timeout",
    };
};

pub fn update(model: *Model, msg: Msg) void {
    updateCore(model, msg, null);
}

fn updateWithEffects(model: *Model, msg: Msg, fx: *Effects) void {
    const notice_epoch = model.taxProfiles.noticeEpoch();
    updateCore(model, msg, fx);
    if (notice_epoch != model.taxProfiles.noticeEpoch()) {
        syncProfileNoticeTimer(model, fx);
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
            model.profileSetupSection = .tax_profile;
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
            const candidates = model.formProfiles.activityCandidates(.filer);
            if (slot < candidates.len) {
                model.formProfiles.setBusinessActivity(
                    .filer,
                    candidates[slot].id,
                ) catch {};
            }
        },
        .select_form_spouse => |slot| {
            const candidates = model.formProfiles.spouseCandidates();
            if (slot < candidates.len) {
                model.formProfiles.setSpouseProfile(
                    candidates[slot].profile_id,
                ) catch {};
            }
        },
        .clear_form_spouse => {
            model.formProfiles.clearSpouseProfile() catch {};
        },
        .save_recurring_form_draft => saveRecurringFormDraft(model),
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
            model.taxProfiles.select(slot);
            refreshSelectedProfileFormSet(model);
            navigate(model, .taxpayer_dashboard);
        },
        .show_profile_tax => model.profileSetupSection = .tax_profile,
        .show_profile_certificate => model.profileSetupSection = .certificate,
        .show_profile_email => model.profileSetupSection = .email,
        .profile_subject_individual => {
            model.taxProfiles.setSubjectKind(.individual);
        },
        .profile_subject_sole_proprietor => {
            model.taxProfiles.setSubjectKind(.sole_proprietor);
        },
        .profile_subject_corporation => {
            model.taxProfiles.setSubjectKind(.corporation);
        },
        .profile_subject_partnership => {
            model.taxProfiles.setSubjectKind(.partnership);
        },
        .profile_subject_estate => {
            model.taxProfiles.setSubjectKind(.estate);
        },
        .profile_subject_trust => {
            model.taxProfiles.setSubjectKind(.trust);
        },
        .profile_subject_other_legal => {
            model.taxProfiles.setSubjectKind(.other_legal_entity);
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
        .profile_forms_set_fallback => {
            model.taxProfiles.setFormsSetConfigured(false);
        },
        .profile_forms_set_registered => {
            model.taxProfiles.setFormsSetConfigured(true);
        },
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
        .profile_forms_set_input => |edit| {
            model.taxProfiles.forms_set.apply(edit);
            model.taxProfiles.captureInputTruncation();
        },
        .save_profile => {
            if (model.taxProfiles.save()) {
                refreshSelectedProfileFormSet(model);
                closeProfileEditor(model);
            }
        },
        .cancel_profile_edit => {
            model.taxProfiles.cancelEdit();
            closeProfileEditor(model);
        },
        .dismiss_profile_notice => model.taxProfiles.dismissNotice(),
        .profile_notice_timeout => |timer| profileNoticeTimeout(model, timer),
        .toggle_profile_actions => model.profileActionsOpen = !model.profileActionsOpen,
        .close_profile_actions => model.profileActionsOpen = false,
        .show_calendar_deadlines => model.taxCalendarSection = .deadlines,
        .show_calendar_rules => model.taxCalendarSection = .rules,
        .show_calendar_overrides => model.taxCalendarSection = .overrides,
        .calendar_previous_year => {
            model.calendar.previousYear();
            refreshSelectedProfileFormSet(model);
        },
        .calendar_next_year => {
            model.calendar.nextYear();
            refreshSelectedProfileFormSet(model);
        },
        .calendar_previous_month => model.calendar.previousMonth(),
        .calendar_next_month => model.calendar.nextMonth(),
        .calendar_refresh => {
            model.calendar.refresh();
            refreshSelectedProfileFormSet(model);
        },
        .profile_calendar_export => exportProfileCalendar(model, fx),
        .profile_calendar_export_written => |result| profileCalendarExportWritten(model, result, fx),
        .profile_calendar_export_opened => |result| profileCalendarExportOpened(model, result),
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
        .calendar_save_override => model.calendar.saveOverride(),
        .calendar_cancel_override => model.calendar.clearOverrideEditor(),
        .calendar_edit_override => |id| model.calendar.editOverride(id),
        .calendar_delete_override => |id| model.calendar.deleteOverride(id),
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
        .calendar_save_non_working_day => model.calendar.saveNonWorkingDay(),
        .calendar_cancel_non_working_day => model.calendar.clearNonWorkingDayEditor(),
        .calendar_edit_non_working_day => |id| model.calendar.editNonWorkingDay(id),
        .calendar_delete_non_working_day => |id| model.calendar.deleteNonWorkingDay(id),
        .show_background_jobs => model.backgroundTasksSection = .jobs,
        .show_background_logs => model.backgroundTasksSection = .logs,
        .multi_select_open => model.formFilter.openPicker(),
        .multi_select_close => model.formFilter.closePicker(),
        .multi_select_query_changed => |edit| model.formFilter.applyQuery(edit),
        .multi_select_toggle_option => |index| {
            _ = model.formFilter.toggle(index);
        },
        .multi_select_select_all_filtered => model.setFilteredFormOptions(true),
        .multi_select_clear_all => {
            _ = model.formFilter.clear();
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
        .viewport_class_changed => |viewport_class| {
            model.viewportClass = viewport_class;
            if (viewport_class != .phone) model.profileActionsOpen = false;
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
}

fn saveRecurringFormDraft(model: *Model) void {
    const revision = model.formProfiles.formRevision() orelse return;
    if (std.mem.eql(u8, revision.code.asSlice(), "2551Q")) {
        var values: percentage_tax_ui.DraftValueSet = .{};
        const writes = model.percentageTax.draftValueWrites(&values) catch
            return;
        _ = model.formProfiles.saveRecurringDraftWithValues(writes) catch {};
        return;
    }
    if (std.mem.eql(u8, revision.code.asSlice(), "1701Q")) {
        const writes = model.incomeTax.draftValueWrites() catch return;
        _ = model.formProfiles.saveRecurringDraftWithValues(writes) catch {};
        return;
    }
    _ = model.formProfiles.saveRecurringDraft() catch {};
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
    return monthEndDate(year, model.calendar.selected_month);
}

fn openProfileBoundForm(
    model: *Model,
    page: Page,
    form_code: []const u8,
) void {
    _ = openProfileBoundFormForQuarter(
        model,
        page,
        form_code,
        selectedCalendarQuarter(model),
        null,
    );
}

fn openProfileBoundFormForQuarter(
    model: *Model,
    page: Page,
    form_code: []const u8,
    quarter: u8,
    spouse_profile_id: ?profile_model.ProfileId,
) bool {
    const filer_id = model.taxProfiles.selectedProfileDomainId() orelse
        return false;
    if (model.taxpayerFormDisabled(form_code)) return false;
    const year_value = model.calendar.selected_year;
    if (year_value < 1 or year_value > 9999) return false;
    const year: u16 = @intCast(year_value);
    const revision = editorRevision(form_code) orelse return false;
    const profile_as_of = profileAsOfForForm(
        model,
        form_code,
        year,
        quarter,
    );
    model.formProfiles.open(.{
        .form = revision,
        .filer_profile_id = filer_id,
        .spouse_profile_id = spouse_profile_id,
        .tax_year = year,
        .quarter = quarter,
        .profile_as_of = profile_as_of,
    }) catch |err| {
        model.percentageTax = .{};
        model.incomeTax = .{};
        if (std.mem.eql(u8, form_code, "1701Q")) {
            model.incomeTax.blockForLoadFailure(err);
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
        model.incomeTax.reset(year, quarter) catch |err| {
            model.incomeTax = .{};
            model.incomeTax.blockForLoadFailure(err);
        };
        const loaded_draft = model.formProfiles.loadPersistedDraft() catch |err| {
            model.incomeTax.blockForLoadFailure(err);
            navigate(model, page);
            return true;
        };
        if (loaded_draft) |loaded| {
            var draft = loaded;
            defer model.formProfiles.deinitLoadedDraft(&draft);
            model.incomeTax.loadFromDraft(&draft) catch |err| {
                model.incomeTax.blockForLoadFailure(err);
            };
        }
    } else {
        model.percentageTax = .{};
        model.incomeTax = .{};
    }
    navigate(model, page);
    return true;
}

fn reopenIncomeTaxQuarter(model: *Model, quarter: u8) void {
    if (quarter < 1 or quarter > 3) return;
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
        quarter,
        spouse_profile_id,
    )) {
        model.calendar.selected_month = quarter * 3;
    }
}

fn navigate(model: *Model, page: Page) void {
    model.page = page;
    model.sidebarOverlayOpen = false;
    model.profileActionsOpen = false;
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
    navigate(model, destination);
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
const calendar_export_file_key: u64 = 20_260_001;
const calendar_open_file_key: u64 = 20_260_002;
const profile_notice_timer_key_base: u64 = 20_260_100;
const profile_notice_duration_ms: u64 = 5_000;

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
    const fx = maybe_fx orelse {
        model.profileCalendarExportStatus = .unavailable;
        return;
    };
    const allocator = model.calendar.allocator orelse {
        model.calendar.setError(error.NotAttached);
        model.profileCalendarExportStatus = .build_failed;
        return;
    };
    var export_stamp: [16]u8 = undefined;
    const now: i64 = @intCast(c_time.time(null));
    if (utcCalendarTimeFromUnixSeconds(now)) |current| {
        export_stamp = current.stamp;
    } else {
        const fallback = model.calendar.exportTimestamp();
        if (fallback.len != export_stamp.len) {
            model.calendar.setError(error.InvalidTimestamp);
            model.profileCalendarExportStatus = .build_failed;
            return;
        }
        @memcpy(&export_stamp, fallback);
    }
    const bytes = model.calendar.buildProfileIcs(
        allocator,
        &export_stamp,
        .{
            .key = model.selectedTaxpayerCalendarKey(),
            .name = model.selectedTaxpayerName(),
            // Calendar rules and overrides are global policy. Until the
            // profile Forms Set is a product-level filter, every profile's
            // handoff uses the complete shared catalog.
            .form_scope = calendar_ui.ProfileFormScope.catalog_fallback,
        },
    ) catch |err| {
        model.calendar.setError(err);
        model.profileCalendarExportStatus = .build_failed;
        return;
    };
    defer allocator.free(bytes);

    model.profileCalendarExportStatus = .writing;
    fx.writeFile(.{
        .key = calendar_export_file_key,
        .path = model.calendar.exportPath(),
        .bytes = bytes,
        .on_result = Effects.fileMsg(.profile_calendar_export_written),
    });
}

fn profileCalendarExportWritten(
    model: *Model,
    result: native_sdk.EffectFileResult,
    maybe_fx: ?*Effects,
) void {
    if (result.outcome != .ok) {
        model.profileCalendarExportStatus = .write_failed;
        return;
    }
    const fx = maybe_fx orelse {
        model.profileCalendarExportStatus = .opener_unavailable;
        return;
    };

    model.profileCalendarExportStatus = .opening;
    const path = model.calendar.exportPath();
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
    syncProfileNoticeTimer(model, fx);
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
    \\    query="{formFilterQuery}"
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

const BootCalendarTime = struct {
    year: i32,
    month: u8,
    stamp: [16]u8,
};

fn bootCalendarTime(io: std.Io) BootCalendarTime {
    const raw_seconds = std.Io.Clock.real.now(io).toSeconds();
    const utc = utcCalendarTimeFromUnixSeconds(raw_seconds) orelse return .{
        .year = 2026,
        .month = 1,
        .stamp = "20260101T000000Z".*,
    };

    var local_seconds: c_time.time_t = @intCast(raw_seconds);
    var local: c_time.struct_tm = undefined;
    const local_result = c_time.localtime_r(&local_seconds, &local);
    const local_year: i32 = if (local_result != null)
        local.tm_year + 1900
    else
        utc.year;
    const local_month: i32 = if (local_result != null)
        local.tm_mon + 1
    else
        utc.month;
    if (local_year < 1 or local_year > 9999 or
        local_month < 1 or local_month > 12)
    {
        return utc;
    }
    return .{
        .year = local_year,
        .month = @intCast(local_month),
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
        .stamp = stamp,
    };
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
    var export_path_buffer: [1024]u8 = undefined;
    const export_path = try app_dirs.join(
        platform,
        &export_path_buffer,
        &.{ data_dir, "ebirforms-tax-calendar.ics" },
    );

    var calendar_store = try calendar_ui.persistence.Store.open(
        init.gpa,
        database_path,
    );
    defer calendar_store.close();
    var tax_profile_store = try profile_store.Store.open(
        init.gpa,
        database_path,
    );
    defer tax_profile_store.close();
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
    try app_state.model.calendar.attach(
        init.gpa,
        &calendar_store,
        export_path,
        &boot_time.stamp,
        boot_time.year,
        boot_time.month,
    );
    try app_state.model.taxProfiles.attach(
        init.gpa,
        &tax_profile_store,
        &boot_date,
        boot_time.year,
    );
    app_state.model.formProfiles.attach(
        init.gpa,
        &tax_profile_store,
    );
    defer app_state.model.formProfiles.deinit();

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

test "tax-profile domain modules remain in the repository test root" {
    _ = @import("domain/date.zig");
    _ = @import("domain/money.zig");
    _ = @import("tax_profile/field.zig");
    _ = @import("tax_profile/model.zig");
    _ = @import("tax_profile/capability.zig");
    _ = @import("tax_profile/projection.zig");
    _ = @import("tax_profile/editor.zig");
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
    var model = Model{ .page = .settings };
    update(&model, .collapse_sidebar);
    try std.testing.expect(model.sidebarRailVisible());

    update(&model, .hide_sidebar);
    try std.testing.expect(!model.sidebarExpandedVisible());
    try std.testing.expect(!model.sidebarRailVisible());
    try std.testing.expect(model.sidebarLauncherVisible());

    update(&model, .toggle_navigation);
    try std.testing.expect(model.sidebarExpandedVisible());
    try std.testing.expectEqual(Page.settings, model.page);
}

test "taxpayer selection and profile navigation are model owned" {
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
    try addThreeTestProfiles(&store);

    var model = Model{};
    try model.taxProfiles.attach(allocator, &store, "2026-07-29", 2026);
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

    model.taxProfiles.select(profileSlotNamed(&model, "Juan Dela Cruz").?);
    try std.testing.expect(!model.profileCalendarExportNoticeVisible());
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

test "global calendar policy is shared across profile exports" {
    const allocator = std.testing.allocator;
    var profile_store_state = try profile_store.Store.openMemory(allocator);
    defer profile_store_state.close();
    try addTestProfile(
        &profile_store_state,
        "11111111111111111111111111111111",
        "Juan Dela Cruz",
        "123-456-789-000",
        .individual,
    );

    var calendar_store_state =
        try calendar_ui.persistence.Store.openMemory(allocator);
    defer calendar_store_state.close();

    var model = Model{ .page = .taxpayer_dashboard };
    try model.taxProfiles.attach(
        allocator,
        &profile_store_state,
        "2026-07-29",
        2026,
    );
    try model.calendar.attach(
        allocator,
        &calendar_store_state,
        "profile-calendar.ics",
        "20260731T000000Z",
        2026,
        7,
    );
    try std.testing.expect(!model.calendarNoticeVisible());
    model.calendar.setError(error.NotAttached);
    try std.testing.expect(model.calendarNoticeVisible());
    model.calendar.refresh();
    try std.testing.expect(!model.calendarNoticeVisible());
    _ = try calendar_store_state.putOverride(.{
        .title = "Quarterly indirect tax extension",
        .source = "Official projection fixture",
        .original_deadline = "2026-07-25",
        .adjusted_deadline = "2026-07-27",
        .affected_form_codes = &.{ "2550Q", "2551Q" },
    });
    model.calendar.refresh();

    var empty_arena = std.heap.ArenaAllocator.init(allocator);
    defer empty_arena.deinit();
    const deadlines = model.calendarDeadlines(empty_arena.allocator());
    try std.testing.expect(deadlines.len > 0);
    var found_2550q = false;
    var found_2551q = false;
    for (deadlines) |deadline| {
        found_2550q = found_2550q or std.mem.eql(u8, deadline.form_code, "2550Q");
        found_2551q = found_2551q or std.mem.eql(u8, deadline.form_code, "2551Q");
    }
    try std.testing.expect(found_2550q);
    try std.testing.expect(found_2551q);

    const rules = model.calendarRules(empty_arena.allocator());
    var found_indirect_rule = false;
    for (rules) |rule| {
        if (!std.mem.eql(
            u8,
            rule.form_name,
            "Quarterly Percentage/Value-Added Tax",
        )) continue;
        found_indirect_rule = true;
        try std.testing.expect(std.mem.indexOf(u8, rule.form_codes, "2550Q") != null);
        try std.testing.expect(std.mem.indexOf(u8, rule.form_codes, "2551Q") != null);
    }
    try std.testing.expect(found_indirect_rule);

    const overrides = model.calendarOverrides();
    try std.testing.expectEqual(@as(usize, 1), overrides.len);
    const forms_label = overrides[0].formsLabel(empty_arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, forms_label, "2550Q") != null);
    try std.testing.expect(std.mem.indexOf(u8, forms_label, "2551Q") != null);

    // A profile Forms Set does not own or filter the global catalog yet.
    const profile_id = model.taxProfiles.selectedProfileId().?;
    try profile_store_state.replaceFormSet(profile_id, 2026, &.{.{
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
    }});
    refreshSelectedProfileFormSet(&model);
    var after_profile_arena = std.heap.ArenaAllocator.init(allocator);
    defer after_profile_arena.deinit();
    const after_profile_deadlines = model.calendarDeadlines(after_profile_arena.allocator());
    var still_has_2550q = false;
    for (after_profile_deadlines) |deadline| {
        still_has_2550q = still_has_2550q or std.mem.eql(u8, deadline.form_code, "2550Q");
    }
    try std.testing.expect(still_has_2550q);

    const fx = try allocator.create(Effects);
    defer allocator.destroy(fx);
    fx.* = .{
        .allocator = allocator,
        .executor = .fake,
    };
    defer fx.deinit();
    updateWithEffects(&model, .profile_calendar_export, fx);
    try std.testing.expectEqual(
        ProfileCalendarExportStatus.writing,
        model.profileCalendarExportStatus,
    );
    const request = fx.pendingFileAt(0).?;
    try std.testing.expect(std.mem.indexOf(u8, request.bytes, "2550Q") != null);
    try std.testing.expect(std.mem.indexOf(u8, request.bytes, "2551Q") != null);
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

test "1701Q quarter reopening keeps profile period and transaction aligned" {
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

    update(&model, .show_form_1701q);
    try std.testing.expectEqual(Page.form_1701q, model.page);
    try std.testing.expect(model.incomeTaxSaveDisabled());
    try std.testing.expect(model.formProfiles.formRevision() == null);

    update(&model, .income_tax_quarter_q2);
    try std.testing.expectEqual(@as(u8, 6), model.calendar.selected_month);
    try std.testing.expectEqual(@as(u8, 2), model.formProfiles.quarter());
    try std.testing.expectEqual(@as(?u8, 2), model.incomeTax.quarter());
    try std.testing.expect(model.formProfiles.projectionAccepted());

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

    update(&model, .{
        .income_tax_sheets_attached_input = .{ .insert_text = "0" },
    });
    update(&model, .income_tax_election_graduated);
    update(&model, .{
        .income_tax_graduated_sales_input = .{
            .insert_text = "100000.00",
        },
    });
    update(&model, .{
        .income_tax_graduated_cost_input = .{
            .insert_text = "20000.00",
        },
    });
    update(&model, .{
        .income_tax_graduated_deductions_input = .{
            .insert_text = "10000.00",
        },
    });
    update(&model, .{
        .income_tax_graduated_taxable_income_input = .{
            .insert_text = "70000.00",
        },
    });
    update(&model, .{
        .income_tax_graduated_tax_due_input = .{
            .insert_text = "5000.00",
        },
    });
    update(&model, .{
        .income_tax_prior_payments_input = .{
            .insert_text = "1000.00",
        },
    });
    update(&model, .{
        .income_tax_withheld_2307_input = .{
            .insert_text = "500.00",
        },
    });
    update(&model, .{
        .income_tax_other_credits_input = .{
            .insert_text = "100.00",
        },
    });
    update(&model, .{
        .income_tax_payable_input = .{ .insert_text = "3400.00" },
    });
    update(&model, .{
        .income_tax_surcharge_input = .{ .insert_text = "50.00" },
    });
    update(&model, .{
        .income_tax_interest_input = .{ .insert_text = "25.00" },
    });
    update(&model, .{
        .income_tax_compromise_input = .{ .insert_text = "0.00" },
    });
    update(&model, .income_tax_add_payment);
    update(&model, .income_tax_payment_method_check);
    update(&model, .{
        .income_tax_payment_bank_input = .{ .insert_text = "DBP" },
    });
    update(&model, .{
        .income_tax_payment_reference_input = .{
            .insert_text = "CHK-2026-Q2",
        },
    });
    update(&model, .{
        .income_tax_payment_amount_input = .{
            .insert_text = "3475.00",
        },
    });
    try std.testing.expect(!model.incomeTaxSaveDisabled());

    update(&model, .save_recurring_form_draft);
    const q2_draft_id = model.formProfiles.draftId().?;
    try std.testing.expectEqual(@as(usize, 10), model.formProfiles
        .snapshot().?.slice().len);

    update(&model, .income_tax_quarter_q1);
    try std.testing.expectEqual(@as(u8, 1), model.formProfiles.quarter());
    try std.testing.expectEqual(
        income_tax_ui.Election.none,
        model.incomeTax.selectedElection(),
    );
    try std.testing.expect(model.formProfiles.draftId() == null);
    try std.testing.expectEqualStrings(
        "Maria Dela Cruz",
        model.formSpouseName(),
    );

    update(&model, .income_tax_quarter_q2);
    try std.testing.expectEqualStrings(
        q2_draft_id.asSlice(),
        model.formProfiles.draftId().?.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "100000.00",
        model.incomeTaxGraduatedSales(),
    );
    try std.testing.expectEqualStrings(
        "CHK-2026-Q2",
        model.incomeTaxPaymentReference(),
    );
    try std.testing.expectEqual(@as(usize, 1), model.incomeTaxPaymentRows().len);
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

test "phone profile actions close after navigation and viewport expansion" {
    var model = Model{
        .page = .taxpayer_dashboard,
        .viewportClass = .phone,
    };
    update(&model, .toggle_profile_actions);
    try std.testing.expect(model.profileActionsOpen);

    update(&model, .show_profile_setup);
    try std.testing.expect(!model.profileActionsOpen);

    model.page = .taxpayer_dashboard;
    update(&model, .toggle_profile_actions);
    try std.testing.expect(model.profileActionsOpen);
    update(&model, .{ .viewport_class_changed = .desktop });
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
}

test "profile setup uses compact cards and native tabs with a shell toast" {
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
    try std.testing.expect(
        std.mem.count(u8, app_markup, "<card size=\"sm\">") >= 6,
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
        "<template name=\"profile-notice-toast\" args=\"width=320\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "label=\"Dismiss tax profile notification\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "width=\"44\"\nheight=\"44\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "<column grow=\"1\" padding=\"16\" main=\"end\" cross=\"center\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "<badge variant=\"{profileNoticeTone}\">",
    ) == null);
}

test "calendar explorer is global and profile actions only hand off" {
    try std.testing.expectEqual(
        @as(usize, 2),
        std.mem.count(u8, app_markup, "on-press=\"show_tax_calendar\""),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "contentPage == 'tax_calendar'",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "<template name=\"tax-calendar-page\">",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "Profile-specific deadlines will appear",
    ) == null);
    try std.testing.expectEqual(
        @as(usize, 1),
        std.mem.count(
            u8,
            app_markup,
            "<use template=\"tax-calendar-deadlines-section\"/>",
        ),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "label=\"Tax profile calendar sections\"",
    ) == null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        app_markup,
        "label=\"Dashboard view\"",
    ) == null);
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
    const closed_trigger = findWidgetByKind(closed_tree.root, .select).?;
    try std.testing.expectEqualStrings("51 selected", closed_trigger.text);

    const open_message = closed_tree.msgForPointer(closed_trigger.id, .up).?;
    update(&model, open_message);
    update(&model, open_message);
    try std.testing.expect(model.formFilter.isOpen());

    var open_ui = canvas.Ui(Msg).init(arena);
    const open_tree = try open_ui.finalize(try view.build(&open_ui, &model));
    const open_trigger = findWidgetByKind(open_tree.root, .select).?;
    const open_search = findWidgetByKind(open_tree.root, .input).?;
    const first_option = findWidgetByText(open_tree.root, .menu_item, "0605").?;
    const second_option = findWidgetByText(open_tree.root, .menu_item, "1905").?;
    try std.testing.expectEqualStrings("51 selected", open_trigger.text);
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
    try std.testing.expectEqual(@as(usize, 51), model.formFilter.selectedCount());

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
    const dismissed_trigger = findWidgetByKind(dismissed_tree.root, .select).?;
    try std.testing.expectEqualStrings("50 selected", dismissed_trigger.text);
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

    update(&model, .multi_select_open);
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

test "global dashboard markup builds with the reusable form filter mounted" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const model = Model{};
    var view = try canvas.MarkupView(Model, Msg).init(arena, app_markup);
    var ui = canvas.Ui(Msg).init(arena);
    _ = try ui.finalize(try view.build(&ui, &model));
}
