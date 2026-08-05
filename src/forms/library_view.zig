//! Presentation types and label helpers for the tax form library.
//!
//! These carry no application state: rows and cells are built per frame from
//! the catalog, the profile's managed-form status, and launch assessments.
//! Keeping them out of `main.zig` lets the library's vocabulary be read, and
//! tested, without the surrounding application model.

const std = @import("std");
const native_sdk = @import("native_sdk");
const canvas = native_sdk.canvas;
const form_catalog = @import("generated/catalog.zig");
const form_period = @import("filing_period.zig");
const form_ui = @import("ui_state.zig");
const profile_ui = @import("../tax_profile/ui_state.zig");

pub const LibraryPeriodFilter = union(enum) {
    all,
    monthly: u8,
    quarterly: u8,
    annual,
    on_demand,

    pub fn label(self: LibraryPeriodFilter) []const u8 {
        return switch (self) {
            .all => "All filing periods",
            .monthly => |month| form_period.monthName(month),
            .quarterly => |quarter| switch (quarter) {
                1 => "Quarter 1",
                2 => "Quarter 2",
                3 => "Quarter 3",
                4 => "Quarter 4",
                else => "Quarter",
            },
            .annual => "Annual",
            .on_demand => "On-demand",
        };
    }

    pub fn summary(self: LibraryPeriodFilter) []const u8 {
        return switch (self) {
            .all => "All periods",
            .monthly => |month| form_period.monthName(month),
            .quarterly => |quarter| switch (quarter) {
                1 => "Q1",
                2 => "Q2",
                3 => "Q3",
                4 => "Q4",
                else => "Quarter",
            },
            .annual => "Annual",
            .on_demand => "On-demand",
        };
    }

    pub fn matches(self: LibraryPeriodFilter, cadence: form_catalog.FilingCadence) bool {
        return switch (self) {
            .all => true,
            .monthly => cadence == .monthly,
            .quarterly => cadence == .quarterly,
            .annual => cadence == .annual,
            .on_demand => cadence == .on_demand,
        };
    }
};

pub fn taxCategoryLabel(category: form_catalog.TaxCategory) []const u8 {
    return switch (category) {
        .payment => "Payment",
        .registration => "Registration",
        .withholding_tax => "Withholding tax",
        .income_tax => "Income tax",
        .value_added_tax => "Value-added tax",
        .percentage_tax => "Percentage tax",
        .documentary_stamp_tax => "Documentary stamp tax",
        .excise_tax => "Excise tax",
        .capital_gains_tax => "Capital gains tax",
        .estate_and_donors_tax => "Estate and donor's tax",
    };
}

pub const TaxFormLibraryPeriodCell = struct {
    id: usize = 0,
    action_id: usize = 0,
    label: []const u8 = "",
    status: []const u8 = "",
    visual_status: []const u8 = "",
    status_color: []const u8 = "muted",
    tile_width: u16 = 64,
    tone: []const u8 = "outline",
    selected: bool = false,
    available: bool = false,
    visible: bool = false,
    filtered_out: bool = false,
    actionable: bool = false,
    calendar_only: bool = false,
    accessible_label: []const u8 = "Filing period",

    pub fn key(self: *const TaxFormLibraryPeriodCell) canvas.UiKey {
        return canvas.uiKey(self.id);
    }

    pub fn actionId(self: *const TaxFormLibraryPeriodCell) usize {
        return self.action_id;
    }

    pub fn filteredOut(self: *const TaxFormLibraryPeriodCell) bool {
        return self.filtered_out;
    }

    pub fn launchDisabled(self: *const TaxFormLibraryPeriodCell) bool {
        return !self.actionable or self.filtered_out;
    }

    pub fn disabled(self: *const TaxFormLibraryPeriodCell) bool {
        return self.launchDisabled();
    }

    pub fn editorAction(self: *const TaxFormLibraryPeriodCell) bool {
        return !self.calendar_only;
    }

    pub fn calendarOnly(self: *const TaxFormLibraryPeriodCell) bool {
        return self.calendar_only;
    }

    pub fn accessibleLabel(self: *const TaxFormLibraryPeriodCell) []const u8 {
        return self.accessible_label;
    }

    pub fn actionLabel(self: *const TaxFormLibraryPeriodCell) []const u8 {
        return self.accessible_label;
    }

    pub fn visualStatus(self: *const TaxFormLibraryPeriodCell) []const u8 {
        return if (self.visual_status.len == 0) self.status else self.visual_status;
    }

    pub fn statusColor(self: *const TaxFormLibraryPeriodCell) []const u8 {
        return self.status_color;
    }

    pub fn tileWidth(self: *const TaxFormLibraryPeriodCell) u16 {
        return self.tile_width;
    }

    pub fn statusWarning(self: *const TaxFormLibraryPeriodCell) bool {
        const status = self.visualStatus();
        return std.mem.eql(u8, status, "Draft") or
            std.mem.eql(u8, status, "Queued") or
            std.mem.eql(u8, status, "Due") or
            std.mem.eql(u8, status, "Unknown");
    }

    pub fn statusInfo(self: *const TaxFormLibraryPeriodCell) bool {
        return std.mem.eql(u8, self.visualStatus(), "Sent");
    }

    pub fn statusSuccess(self: *const TaxFormLibraryPeriodCell) bool {
        const status = self.visualStatus();
        return std.mem.eql(u8, status, "Confirmed") or
            std.mem.eql(u8, status, "Paid");
    }

    pub fn statusDestructive(self: *const TaxFormLibraryPeriodCell) bool {
        return std.mem.eql(u8, self.visualStatus(), "Cancelled");
    }

    pub fn statusNeutral(self: *const TaxFormLibraryPeriodCell) bool {
        return !self.statusWarning() and
            !self.statusInfo() and
            !self.statusSuccess() and
            !self.statusDestructive();
    }
};

pub const TaxFormLibraryRow = struct {
    id: usize,
    definition: *const form_catalog.FormDefinition,
    active: bool,
    selected: bool,
    launch_disabled: bool,
    launch_assessment: form_ui.LaunchAssessment = .{},
    period_cells: [12]TaxFormLibraryPeriodCell =
        [_]TaxFormLibraryPeriodCell{.{}} ** 12,
    period_cell_count: u8 = 0,
    period1: TaxFormLibraryPeriodCell = .{},
    period2: TaxFormLibraryPeriodCell = .{},
    period3: TaxFormLibraryPeriodCell = .{},
    period4: TaxFormLibraryPeriodCell = .{},
    period5: TaxFormLibraryPeriodCell = .{},
    period6: TaxFormLibraryPeriodCell = .{},
    period7: TaxFormLibraryPeriodCell = .{},
    period8: TaxFormLibraryPeriodCell = .{},
    period9: TaxFormLibraryPeriodCell = .{},
    period10: TaxFormLibraryPeriodCell = .{},
    period11: TaxFormLibraryPeriodCell = .{},
    period12: TaxFormLibraryPeriodCell = .{},
    period_summary: []const u8 = "",
    period_grid_columns: u8 = 4,
    manage_status: profile_ui.ManagedFormStatus = .inactive,
    tax_form_profile_status: []const u8 = "",
    tax_form_profile_action: []const u8 = "",
    tax_form_profile_action_visible: bool = false,
    tax_form_profile_action_disabled: bool = true,
    activation_label: []const u8 = "Active in selected tax year",

    pub fn key(self: *const TaxFormLibraryRow) canvas.UiKey {
        return canvas.uiKey(self.id);
    }

    pub fn code(self: *const TaxFormLibraryRow) []const u8 {
        return self.definition.code;
    }

    pub fn title(
        self: *const TaxFormLibraryRow,
    ) []const u8 {
        return self.definition.display_title;
    }

    pub fn taxCategory(self: *const TaxFormLibraryRow) []const u8 {
        return taxCategoryLabel(self.definition.tax_category);
    }

    pub fn categoryLabel(self: *const TaxFormLibraryRow) []const u8 {
        return self.taxCategory();
    }

    pub fn capability(self: *const TaxFormLibraryRow) []const u8 {
        return if (self.definition.status == .static_layout)
            "Editor available"
        else
            "Calendar only";
    }

    /// Editor availability is deliberately independent from artifact
    /// qualification. A form can open in the app without its official print,
    /// validation, submission, or filing gates having passed.
    pub fn fileability(self: *const TaxFormLibraryRow) []const u8 {
        return if (self.definition.status == .static_layout)
            "Not qualified"
        else
            "No artifact";
    }

    pub fn cadenceLabel(self: *const TaxFormLibraryRow) []const u8 {
        return switch (self.definition.cadence) {
            .monthly => "Monthly",
            .quarterly => "Quarterly",
            .annual => "Annual",
            .on_demand => "On-demand",
        };
    }

    pub fn periodCells(self: *const TaxFormLibraryRow) []const TaxFormLibraryPeriodCell {
        return self.period_cells[0..self.period_cell_count];
    }

    pub fn setPeriodCell(
        self: *TaxFormLibraryRow,
        slot: usize,
        cell: TaxFormLibraryPeriodCell,
    ) void {
        if (slot >= self.period_cells.len) return;
        self.period_cells[slot] = cell;
        switch (slot) {
            0 => self.period1 = cell,
            1 => self.period2 = cell,
            2 => self.period3 = cell,
            3 => self.period4 = cell,
            4 => self.period5 = cell,
            5 => self.period6 = cell,
            6 => self.period7 = cell,
            7 => self.period8 = cell,
            8 => self.period9 = cell,
            9 => self.period10 = cell,
            10 => self.period11 = cell,
            11 => self.period12 = cell,
            else => unreachable,
        }
    }

    pub fn hasPeriodCells(self: *const TaxFormLibraryRow) bool {
        return self.period_cell_count != 0;
    }

    pub fn periodSummary(self: *const TaxFormLibraryRow) []const u8 {
        return self.period_summary;
    }

    pub fn periodGridColumns(self: *const TaxFormLibraryRow) u8 {
        return self.period_grid_columns;
    }

    pub fn filingProgress(
        self: *const TaxFormLibraryRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        var filed: usize = 0;
        for (self.periodCells()) |cell| {
            if (std.mem.eql(u8, cell.status, "Sent") or
                std.mem.eql(u8, cell.status, "Confirmed") or
                std.mem.eql(u8, cell.status, "Paid"))
            {
                filed += 1;
            }
        }
        return std.fmt.allocPrint(
            arena,
            "{d}/{d} filed",
            .{ filed, self.period_cell_count },
        ) catch "Filing progress";
    }

    pub fn infoLabel(
        self: *const TaxFormLibraryRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "About BIR Form {s}",
            .{self.definition.code},
        ) catch "About this form";
    }

    pub fn activeLabel(self: *const TaxFormLibraryRow) []const u8 {
        return if (self.active) "Active" else "Inactive";
    }

    pub fn activationLabel(self: *const TaxFormLibraryRow) []const u8 {
        return self.activation_label;
    }

    pub fn editorAvailable(self: *const TaxFormLibraryRow) bool {
        return self.definition.status == .static_layout;
    }

    pub fn calendarOnly(self: *const TaxFormLibraryRow) bool {
        return self.definition.status == .calendar_only;
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

    pub fn manageStatusLabel(self: *const TaxFormLibraryRow) []const u8 {
        return self.manage_status.label();
    }

    pub fn manageStatusTone(self: *const TaxFormLibraryRow) []const u8 {
        return switch (self.manage_status) {
            .active => "secondary",
            .inactive => "outline",
            .will_activate => "secondary",
            .will_deactivate => "destructive",
        };
    }

    pub fn selectedCard(self: *const TaxFormLibraryRow) bool {
        return self.selected;
    }

    pub fn launchLabel(self: *const TaxFormLibraryRow) []const u8 {
        if (!self.active) return "Inactive";
        if (!self.editorAvailable()) return "Calendar only";
        return switch (self.launch_assessment.status) {
            .inactive => "Inactive",
            .missing_base_profile => "Complete Tax Profile",
            .missing_tax_form_profile => "Complete Tax Form Profile",
            .unsupported_period => "Unavailable",
            .ready_new => "Open Form",
            .ready_resume => "Resume Draft",
        };
    }

    pub fn launchStatus(self: *const TaxFormLibraryRow) []const u8 {
        if (!self.active) return "Inactive";
        if (!self.editorAvailable()) return "Calendar only";
        return switch (self.launch_assessment.status) {
            .inactive => "Inactive",
            .missing_base_profile => "Tax Profile incomplete",
            .missing_tax_form_profile => "Tax Form Profile incomplete",
            .unsupported_period => "Filing period unavailable",
            .ready_new => "Ready",
            .ready_resume => "Draft available",
        };
    }

    pub fn launchActionVisible(self: *const TaxFormLibraryRow) bool {
        return self.active and self.editorAvailable();
    }

    pub fn launchDisabled(self: *const TaxFormLibraryRow) bool {
        return self.launch_disabled;
    }

    pub fn taxFormProfileStatus(self: *const TaxFormLibraryRow) []const u8 {
        return self.tax_form_profile_status;
    }

    pub fn taxFormProfileAction(self: *const TaxFormLibraryRow) []const u8 {
        return self.tax_form_profile_action;
    }

    pub fn taxFormProfileActionVisible(self: *const TaxFormLibraryRow) bool {
        return self.active and self.tax_form_profile_action_visible;
    }

    pub fn taxFormProfileActionDisabled(self: *const TaxFormLibraryRow) bool {
        return !self.active or self.tax_form_profile_action_disabled;
    }
};

/// One month filter choice: its short button text, its spoken name, and
/// whether it is selected. Months are regular, so they are generated rather
/// than written out twelve times.
pub const LibraryMonthFilterRow = struct {
    id: usize,
    month: u8,
    selected: bool,

    const short_names = [_][]const u8{
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };
    const full_names = [_][]const u8{
        "January",   "February", "March",    "April",
        "May",       "June",     "July",     "August",
        "September", "October",  "November", "December",
    };

    pub fn key(self: *const LibraryMonthFilterRow) canvas.UiKey {
        return canvas.uiKey(self.id);
    }

    pub fn text(self: *const LibraryMonthFilterRow) []const u8 {
        if (self.month < 1 or self.month > 12) return "";
        return short_names[self.month - 1];
    }

    pub fn label(self: *const LibraryMonthFilterRow) []const u8 {
        if (self.month < 1 or self.month > 12) return "";
        return full_names[self.month - 1];
    }

    pub fn variant(self: *const LibraryMonthFilterRow) []const u8 {
        return if (self.selected) "primary" else "outline";
    }
};

/// One tax-category filter choice. Rows come from the catalog enum, so the
/// filter list cannot fall out of step with the categories that exist.
pub const LibraryCategoryFilterRow = struct {
    id: usize,
    label: []const u8,
    selected: bool,

    pub fn key(self: *const LibraryCategoryFilterRow) canvas.UiKey {
        return canvas.uiKey(self.id);
    }

    pub fn text(self: *const LibraryCategoryFilterRow) []const u8 {
        return self.label;
    }
};

pub const LibraryOnDemandFilterRow = struct {
    id: usize,
    definition: *const form_catalog.FormDefinition,
    selected: bool,

    pub fn key(self: *const LibraryOnDemandFilterRow) canvas.UiKey {
        return canvas.uiKey(self.id);
    }

    pub fn code(self: *const LibraryOnDemandFilterRow) []const u8 {
        return self.definition.code;
    }

    pub fn title(self: *const LibraryOnDemandFilterRow) []const u8 {
        return self.definition.display_title;
    }

    pub fn label(
        self: *const LibraryOnDemandFilterRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{s} - {s}",
            .{ self.definition.code, self.definition.display_title },
        ) catch self.definition.code;
    }

    pub fn selectionLabel(
        self: *const LibraryOnDemandFilterRow,
        arena: std.mem.Allocator,
    ) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "Filter on-demand filings by BIR Form {s}, {s}",
            .{ self.definition.code, self.definition.display_title },
        ) catch "Filter on-demand form";
    }
};

pub fn filingLifecycleLabel(lifecycle: []const u8) []const u8 {
    if (std.mem.eql(u8, lifecycle, "editing") or
        std.mem.eql(u8, lifecycle, "prepared")) return "Draft";
    if (std.mem.eql(u8, lifecycle, "queued")) return "Queued";
    if (std.mem.eql(u8, lifecycle, "submitted")) return "Sent";
    if (std.mem.eql(u8, lifecycle, "confirmed")) return "Confirmed";
    if (std.mem.eql(u8, lifecycle, "paid")) return "Paid";
    if (std.mem.eql(u8, lifecycle, "cancelled")) return "Cancelled";
    return "New";
}

pub fn filingLifecycleTone(lifecycle: []const u8) []const u8 {
    if (std.mem.eql(u8, lifecycle, "submitted")) return "secondary";
    if (std.mem.eql(u8, lifecycle, "confirmed") or
        std.mem.eql(u8, lifecycle, "paid")) return "primary";
    if (std.mem.eql(u8, lifecycle, "cancelled")) return "destructive";
    if (std.mem.eql(u8, lifecycle, "editing") or
        std.mem.eql(u8, lifecycle, "prepared") or
        std.mem.eql(u8, lifecycle, "queued")) return "secondary";
    return "outline";
}

pub fn compactPeriodStatus(label: []const u8) []const u8 {
    // Period tiles are intentionally compact (four columns even on a phone),
    // so keep their visual status to a short token while the full status
    // remains in the accessible action label and the card capability copy.
    if (std.mem.eql(u8, label, "Deadline only")) return "Due";
    if (std.mem.eql(u8, label, "Status unavailable")) return "Unknown";
    return label;
}

pub fn periodStatusColor(label: []const u8) []const u8 {
    if (std.mem.eql(u8, label, "Sent")) return "info";
    if (std.mem.eql(u8, label, "Confirmed") or std.mem.eql(u8, label, "Paid")) {
        return "success";
    }
    if (std.mem.eql(u8, label, "Cancelled")) return "destructive";
    if (std.mem.eql(u8, label, "Draft") or
        std.mem.eql(u8, label, "Queued") or
        std.mem.eql(u8, label, "Due") or
        std.mem.eql(u8, label, "Unknown"))
    {
        return "warning";
    }
    // A real token name, so markup can bind `foreground` directly instead of
    // branching over every possible colour to reach the same text element.
    return "text_muted";
}

pub fn firstSelectedMonth(mask: u16) u8 {
    for (1..13) |month| {
        if (mask & (@as(u16, 1) << @intCast(month - 1)) != 0) {
            return @intCast(month);
        }
    }
    return 0;
}

pub fn firstSelectedQuarter(mask: u8) u8 {
    for (1..5) |quarter| {
        if (mask & (@as(u8, 1) << @intCast(quarter - 1)) != 0) {
            return @intCast(quarter);
        }
    }
    return 0;
}

pub fn appendLibraryFilterLabelPart(
    label: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    part: []const u8,
) !void {
    if (label.items.len != 0) try label.appendSlice(allocator, " · ");
    try label.appendSlice(allocator, part);
}

/// Filter and paging state for the tax form library.
///
/// This lived as twelve loose fields on the application model. It is one
/// value here because the fields are only ever meaningful together: clearing a
/// cadence clears its dependent month, quarter, or on-demand selection, and
/// every filter change resets paging.
///
/// Markup binds to the model's accessor methods rather than these fields, so
/// the model keeps its published surface while owning one field instead of
/// twelve.
pub const FilterState = struct {
    filter_picker_visible: bool = false,
    browse_cadence_mask: u8 = 0b1111,
    manage_cadence_mask: u8 = 0b1111,
    month_mask: u16 = 0,
    quarter_mask: u8 = 0,
    on_demand_mask: u64 = 0,
    category_mask: u16 = 0,
    visible_limit: usize = 12,
    page_offset: usize = 0,
    info_index: ?usize = null,
    period_filter: LibraryPeriodFilter = .all,
    period_picker_visible: bool = false,

    /// Any filter change returns the list to its first page. A narrowed filter
    /// can otherwise leave the view scrolled past the end of the new results.
    pub fn resetPage(self: *FilterState) void {
        self.visible_limit = 12;
        self.page_offset = 0;
    }

    pub fn resetBrowseFilters(self: *FilterState) void {
        self.browse_cadence_mask = 0b1111;
        self.month_mask = 0;
        self.quarter_mask = 0;
        self.on_demand_mask = 0;
        self.resetPage();
    }

    /// `managing` selects the manage-mode mask instead of the browse-mode one.
    /// The caller supplies it rather than this type reaching for profile state.
    ///
    /// Turning a cadence off also clears the selection it scopes, so a hidden
    /// month or quarter cannot keep filtering results the user can no longer
    /// see. The last enabled cadence is not clearable: an empty cadence mask
    /// would show nothing with no visible way back.
    pub fn toggleCadence(self: *FilterState, bit: u8, managing: bool) void {
        const mask = if (managing)
            &self.manage_cadence_mask
        else
            &self.browse_cadence_mask;
        if (mask.* & bit != 0) {
            if (mask.* == bit) return;
            mask.* &= ~bit;
            if (!managing) {
                switch (bit) {
                    0b0001 => self.month_mask = 0,
                    0b0010 => self.quarter_mask = 0,
                    0b1000 => self.on_demand_mask = 0,
                    else => {},
                }
            }
        } else {
            mask.* |= bit;
        }
        self.resetPage();
    }
};

test "clearing a cadence clears the selection it scopes" {
    var state: FilterState = .{ .month_mask = 0b101, .page_offset = 4 };
    state.toggleCadence(0b0001, false);
    try std.testing.expectEqual(@as(u16, 0), state.month_mask);
    try std.testing.expectEqual(@as(usize, 0), state.page_offset);
}

test "the last enabled cadence cannot be cleared" {
    var state: FilterState = .{ .browse_cadence_mask = 0b0010 };
    state.toggleCadence(0b0010, false);
    try std.testing.expectEqual(@as(u8, 0b0010), state.browse_cadence_mask);
}

test "manage mode uses its own mask and leaves browse selections alone" {
    var state: FilterState = .{ .month_mask = 0b11 };
    state.toggleCadence(0b0001, true);
    try std.testing.expectEqual(@as(u8, 0b1110), state.manage_cadence_mask);
    try std.testing.expectEqual(@as(u8, 0b1111), state.browse_cadence_mask);
    try std.testing.expectEqual(@as(u16, 0b11), state.month_mask);
}

test "editor capability never implies filing qualification" {
    const editor = form_catalog.findForm("2551Q") orelse return error.TestUnexpectedResult;
    const row: TaxFormLibraryRow = .{
        .id = 0,
        .definition = editor,
        .active = true,
        .selected = false,
        .launch_disabled = false,
    };
    try std.testing.expectEqualStrings("Editor available", row.capability());
    try std.testing.expectEqualStrings(
        "Not qualified",
        row.fileability(),
    );

    const calendar = form_catalog.findForm("1905") orelse
        return error.TestUnexpectedResult;
    const calendar_row: TaxFormLibraryRow = .{
        .id = 1,
        .definition = calendar,
        .active = true,
        .selected = false,
        .launch_disabled = true,
    };
    try std.testing.expectEqualStrings("Calendar only", calendar_row.capability());
    try std.testing.expectEqualStrings("No artifact", calendar_row.fileability());
}

test "library launch labels use only canonical readiness layers" {
    const definition = form_catalog.findForm("2551Q") orelse
        return error.TestUnexpectedResult;
    var row: TaxFormLibraryRow = .{
        .id = 0,
        .definition = definition,
        .active = true,
        .selected = false,
        .launch_disabled = true,
    };

    row.launch_assessment.status = .missing_base_profile;
    try std.testing.expectEqualStrings("Complete Tax Profile", row.launchLabel());
    try std.testing.expectEqualStrings("Tax Profile incomplete", row.launchStatus());

    row.launch_assessment.status = .missing_tax_form_profile;
    try std.testing.expectEqualStrings(
        "Complete Tax Form Profile",
        row.launchLabel(),
    );
    try std.testing.expectEqualStrings(
        "Tax Form Profile incomplete",
        row.launchStatus(),
    );

    row.launch_assessment.status = .unsupported_period;
    try std.testing.expectEqualStrings("Unavailable", row.launchLabel());
    try std.testing.expectEqualStrings(
        "Filing period unavailable",
        row.launchStatus(),
    );
}
