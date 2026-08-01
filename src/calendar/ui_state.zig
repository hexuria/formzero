//! Application-facing calendar state.
//!
//! The pure rule resolver stays in `domain.zig`; SQLite-shaped records stay
//! in `store.zig`. This module is the bounded conversion layer used by the
//! Native SDK model and by the `.native` calendar screen.

const std = @import("std");
const native_sdk = @import("native_sdk");

pub const domain = @import("domain.zig");
pub const ics = @import("ics.zig");
pub const persistence = @import("store.zig");

const canvas = native_sdk.canvas;

pub const max_deadlines = 256;
pub const max_overrides = 64;
pub const max_non_working_days = 128;
pub const max_forms_per_override = 32;
pub const max_scopes_per_record = 16;
pub const max_scope_text_bytes = 128;
const max_joined_forms_bytes = max_forms_per_override * 34;
const max_joined_scopes_bytes =
    max_scopes_per_record * (max_scope_text_bytes + 2);

pub const StateError = error{
    NotAttached,
    TooManyDeadlines,
    TooManyOverrides,
    TooManyNonWorkingDays,
    TooManyForms,
    TooManyScopes,
    FieldTooLong,
    InvalidFormCode,
    InvalidKind,
    InvalidMonth,
    IncompleteProjection,
};

fn FixedText(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        storage: [capacity]u8 = undefined,
        len: usize = 0,

        fn set(self: *Self, value: []const u8) StateError!void {
            if (value.len > capacity) return error.FieldTooLong;
            @memcpy(self.storage[0..value.len], value);
            self.len = value.len;
        }

        fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn text(self: *const Self) []const u8 {
            return self.storage[0..self.len];
        }
    };
}

const ShortText = FixedText(32);
const MediumText = FixedText(96);
const LongText = FixedText(256);
const ScopeText = FixedText(max_scope_text_bytes);

pub const DeadlineRow = struct {
    id: u64,
    rule_id: []const u8,
    form_code: []const u8,
    display_form_no: []const u8,
    form_name: []const u8,
    description: []const u8,
    period: domain.Period,
    original_deadline: domain.Date,
    final_deadline: domain.Date,
    status: domain.DeadlineStatus,
    source: LongText = .{},

    pub fn key(self: *const DeadlineRow) canvas.UiKey {
        return canvas.uiKey(self.id);
    }

    pub fn dateLabel(self: *const DeadlineRow, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(
            arena,
            "{s} {d}",
            .{ monthAbbreviation(self.final_deadline.month), self.final_deadline.day },
        ) catch "";
    }

    pub fn yearLabel(self: *const DeadlineRow, arena: std.mem.Allocator) []const u8 {
        return std.fmt.allocPrint(arena, "{d}", .{self.final_deadline.year}) catch "";
    }

    pub fn periodLabel(self: *const DeadlineRow, arena: std.mem.Allocator) []const u8 {
        return formatPeriod(arena, self.period);
    }

    pub fn statusLabel(self: *const DeadlineRow) []const u8 {
        return self.status.label();
    }

    pub fn tone(self: *const DeadlineRow) []const u8 {
        return switch (self.status) {
            .extended => "primary",
            .normal => "secondary",
            .weekend_adjusted,
            .holiday_adjusted,
            .non_working_day_adjusted,
            => "outline",
            .event_based => "secondary",
        };
    }

    pub fn adjustmentVisible(self: *const DeadlineRow) bool {
        return domain.Date.compare(self.original_deadline, self.final_deadline) != .eq;
    }

    pub fn adjustmentLabel(self: *const DeadlineRow, arena: std.mem.Allocator) []const u8 {
        var original: [10]u8 = undefined;
        var final: [10]u8 = undefined;
        return std.fmt.allocPrint(
            arena,
            "Statutory {s} → final {s}",
            .{
                self.original_deadline.writeIso(&original),
                self.final_deadline.writeIso(&final),
            },
        ) catch "";
    }

    pub fn sourceVisible(self: *const DeadlineRow) bool {
        return self.source.len != 0;
    }

    pub fn sourceLabel(self: *const DeadlineRow) []const u8 {
        return self.source.text();
    }

    fn obligationKey(self: *const DeadlineRow, output: []u8) ![]const u8 {
        // Preserve the established human-readable identities for the distinct
        // 1604-C and 1604-F returns even though storage uses normalized codes.
        const identity_form_code = if (std.mem.eql(u8, self.display_form_no, "1604-C") or
            std.mem.eql(u8, self.display_form_no, "1604-F"))
            self.display_form_no
        else
            self.form_code;
        return switch (self.period) {
            .monthly => |period| std.fmt.bufPrint(
                output,
                "{d}:{s}:m{d:0>2}",
                .{ period.taxable_year, identity_form_code, period.month },
            ),
            .quarterly => |period| std.fmt.bufPrint(
                output,
                "{d}:{s}:q{d}",
                .{ period.taxable_year, identity_form_code, period.quarter },
            ),
            .annual => |period| if (std.mem.eql(u8, self.form_code, "2316"))
                // Form 2316 has two annual duties with different recipients
                // and deadlines. Rule identity prevents calendar clients from
                // collapsing them while remaining stable across date changes.
                std.fmt.bufPrint(
                    output,
                    "{d}:{s}:annual:{s}",
                    .{
                        period.taxable_year,
                        identity_form_code,
                        if (std.mem.eql(
                            u8,
                            self.rule_id,
                            "2316-employee-furnishing-january-31",
                        ))
                            "employee-copy"
                        else if (std.mem.eql(
                            u8,
                            self.rule_id,
                            "2316-bir-submission-february-28",
                        ))
                            "bir-copy"
                        else
                            self.rule_id,
                    },
                )
            else
                std.fmt.bufPrint(
                    output,
                    "{d}:{s}:annual",
                    .{ period.taxable_year, identity_form_code },
                ),
            .event_based => error.InvalidFormCode,
        };
    }
};

pub const RuleRow = struct {
    id: u64,
    form_codes: []const u8,
    form_name: []const u8,
    frequency: []const u8,
    description: []const u8,

    pub fn key(self: *const RuleRow) canvas.UiKey {
        return canvas.uiKey(self.id);
    }
};

pub const OverrideRow = struct {
    id: i64,
    title: MediumText = .{},
    source: LongText = .{},
    original_deadline: domain.Date,
    adjusted_deadline: domain.Date,
    effective_from: ?domain.Date = null,
    effective_until: ?domain.Date = null,
    expires_at: ?domain.Date = null,
    form_codes: [max_forms_per_override]ShortText = undefined,
    form_count: usize = 0,
    regions: [max_scopes_per_record]ScopeText = undefined,
    region_count: usize = 0,
    taxpayer_types: [max_scopes_per_record]ScopeText = undefined,
    taxpayer_type_count: usize = 0,

    pub fn key(self: *const OverrideRow) canvas.UiKey {
        return canvas.uiKey(@as(u64, @intCast(self.id)));
    }

    pub fn titleLabel(self: *const OverrideRow) []const u8 {
        return self.title.text();
    }

    pub fn sourceLabel(self: *const OverrideRow) []const u8 {
        return self.source.text();
    }

    pub fn formsLabel(self: *const OverrideRow, arena: std.mem.Allocator) []const u8 {
        return joinFixedTexts(
            arena,
            self.form_codes[0..self.form_count],
            ", ",
        );
    }

    pub fn datesLabel(self: *const OverrideRow, arena: std.mem.Allocator) []const u8 {
        var original: [10]u8 = undefined;
        var adjusted: [10]u8 = undefined;
        return std.fmt.allocPrint(
            arena,
            "{s} → {s}",
            .{
                self.original_deadline.writeIso(&original),
                self.adjusted_deadline.writeIso(&adjusted),
            },
        ) catch "";
    }

    pub fn scopeLabel(self: *const OverrideRow, arena: std.mem.Allocator) []const u8 {
        const region = if (self.region_count == 0)
            "All RDOs"
        else
            joinFixedTexts(arena, self.regions[0..self.region_count], ", ");
        const taxpayer = if (self.taxpayer_type_count == 0)
            "All taxpayer types"
        else
            joinFixedTexts(
                arena,
                self.taxpayer_types[0..self.taxpayer_type_count],
                ", ",
            );
        return std.fmt.allocPrint(arena, "{s} · {s}", .{ region, taxpayer }) catch "";
    }

    pub fn effectiveLabel(self: *const OverrideRow, arena: std.mem.Allocator) []const u8 {
        if (self.effective_from == null and
            self.effective_until == null and
            self.expires_at == null)
        {
            return "No effective-date or expiry metadata";
        }
        var from_buffer: [10]u8 = undefined;
        var until_buffer: [10]u8 = undefined;
        var expires_buffer: [10]u8 = undefined;
        const from = if (self.effective_from) |date|
            date.writeIso(&from_buffer)
        else
            "open";
        const until = if (self.effective_until) |date|
            date.writeIso(&until_buffer)
        else
            "open";
        const expires = if (self.expires_at) |date|
            date.writeIso(&expires_buffer)
        else
            "none";
        return std.fmt.allocPrint(
            arena,
            "Effective {s} to {s} · expires {s}",
            .{ from, until, expires },
        ) catch "";
    }
};

pub const NonWorkingDayRow = struct {
    id: i64,
    date: domain.Date,
    name: MediumText = .{},
    kind: ShortText = .{},
    source: LongText = .{},
    regions: [max_scopes_per_record]ScopeText = undefined,
    region_count: usize = 0,

    pub fn key(self: *const NonWorkingDayRow) canvas.UiKey {
        return canvas.uiKey(@as(u64, @intCast(self.id)));
    }

    pub fn dateLabel(self: *const NonWorkingDayRow, arena: std.mem.Allocator) []const u8 {
        var buffer: [10]u8 = undefined;
        return std.fmt.allocPrint(arena, "{s}", .{self.date.writeIso(&buffer)}) catch "";
    }

    pub fn nameLabel(self: *const NonWorkingDayRow) []const u8 {
        return self.name.text();
    }

    pub fn kindLabel(self: *const NonWorkingDayRow) []const u8 {
        return self.kind.text();
    }

    pub fn sourceLabel(self: *const NonWorkingDayRow) []const u8 {
        return self.source.text();
    }

    pub fn regionsLabel(self: *const NonWorkingDayRow, arena: std.mem.Allocator) []const u8 {
        if (self.region_count == 0) return "All RDOs";
        const codes = joinFixedTexts(
            arena,
            self.regions[0..self.region_count],
            ", ",
        );
        return std.fmt.allocPrint(arena, "RDOs: {s}", .{codes}) catch codes;
    }
};

pub const NoticeKind = enum {
    neutral,
    success,
    failure,
};

pub const ProfileFormScope = union(enum) {
    /// Temporary shipping mode when no profile-level calendar preference is
    /// available and the caller intentionally chooses the full catalog.
    catalog_fallback,
    /// Effective canonical form codes selected for this profile's calendar.
    /// An empty configured selection intentionally exports no deadlines.
    registered: []const []const u8,
};

pub const ProfileExport = struct {
    /// Stable opaque profile identity. This must not be a name or TIN.
    key: []const u8,
    name: []const u8,
    form_scope: ProfileFormScope,
};

/// Taxpayer attributes used to project the already-loaded global calendar
/// policy for one profile. Region-scoped records may name either a geographic
/// region or an RDO, so both values participate in the same scope match.
pub const TaxpayerContext = struct {
    region: ?[]const u8 = null,
    rdo: ?[]const u8 = null,
    taxpayer_type: ?[]const u8 = null,
};

pub const State = struct {
    allocator: ?std.mem.Allocator = null,
    store: ?*persistence.Store = null,
    selected_year: i32 = 2026,
    selected_month: u8 = 1,
    export_path: FixedText(1024) = .{},
    export_timestamp: FixedText(16) = .{},

    deadlines: [max_deadlines]DeadlineRow = undefined,
    deadline_count: usize = 0,
    overrides: [max_overrides]OverrideRow = undefined,
    override_count: usize = 0,
    override_records_truncated: bool = false,
    non_working_days: [max_non_working_days]NonWorkingDayRow = undefined,
    non_working_day_count: usize = 0,
    non_working_day_records_truncated: bool = false,

    editing_override_id: ?i64 = null,
    pending_delete_override_id: ?i64 = null,
    pending_delete_non_working_day_id: ?i64 = null,
    editing_non_working_day_id: ?i64 = null,
    override_title: canvas.TextBuffer(96) = .{},
    override_forms: canvas.TextBuffer(max_joined_forms_bytes) = .{},
    override_original: canvas.TextBuffer(10) = .{},
    override_adjusted: canvas.TextBuffer(10) = .{},
    override_source: canvas.TextBuffer(256) = .{},
    override_regions: canvas.TextBuffer(max_joined_scopes_bytes) = .{},
    override_taxpayer_types: canvas.TextBuffer(max_joined_scopes_bytes) = .{},
    override_effective_from: canvas.TextBuffer(10) = .{},
    override_effective_until: canvas.TextBuffer(10) = .{},
    override_expires_at: canvas.TextBuffer(10) = .{},

    non_working_date: canvas.TextBuffer(10) = .{},
    non_working_name: canvas.TextBuffer(96) = .{},
    non_working_kind: canvas.TextBuffer(32) = .{},
    non_working_source: canvas.TextBuffer(256) = .{},
    non_working_regions: canvas.TextBuffer(max_joined_scopes_bytes) = .{},
    override_input_was_truncated: bool = false,
    non_working_input_was_truncated: bool = false,

    notice: LongText = .{},
    notice_kind: NoticeKind = .neutral,

    pub fn attach(
        self: *State,
        allocator: std.mem.Allocator,
        store: *persistence.Store,
        export_path: []const u8,
        export_timestamp: []const u8,
        selected_year: i32,
        selected_month: u8,
    ) !void {
        if (selected_month < 1 or selected_month > 12) {
            return error.InvalidMonth;
        }
        self.allocator = allocator;
        self.store = store;
        self.selected_year = selected_year;
        self.selected_month = selected_month;
        try self.export_path.set(export_path);
        try self.export_timestamp.set(export_timestamp);
        try self.reload();
        self.setReloadNotice("Calendar rules and SQLite overrides loaded.");
    }

    pub fn exportPath(self: *const State) []const u8 {
        return self.export_path.text();
    }

    pub fn exportTimestamp(self: *const State) []const u8 {
        return self.export_timestamp.text();
    }

    pub fn reload(self: *State) !void {
        const allocator = self.allocator orelse return error.NotAttached;
        const store = self.store orelse return error.NotAttached;

        var overrides = try store.listOverrides(allocator);
        defer overrides.deinit(allocator);
        self.override_records_truncated = overrides.items.len > max_overrides;
        self.override_count = 0;
        for (overrides.items[0..@min(overrides.items.len, max_overrides)]) |item| {
            try self.copyOverride(item);
        }

        var days = try store.listNonWorkingDays(allocator);
        defer days.deinit(allocator);
        self.non_working_day_records_truncated =
            days.items.len > max_non_working_days;
        self.non_working_day_count = 0;
        for (days.items[0..@min(days.items.len, max_non_working_days)]) |item| {
            try self.copyNonWorkingDay(item);
        }

        try self.recompute();
    }

    pub fn recompute(self: *State) !void {
        try self.recomputeProjection(null);
    }

    /// Rebuilds the selected calendar year for one taxpayer without reading
    /// SQLite. The caller must first load records through `attach`/`reload`, or
    /// otherwise populate the in-memory rows (as deterministic tests do).
    pub fn recomputeForTaxpayer(
        self: *State,
        context: TaxpayerContext,
    ) !void {
        try self.recomputeProjection(context);
    }

    fn recomputeProjection(
        self: *State,
        taxpayer_context: ?TaxpayerContext,
    ) !void {
        const allocator = self.allocator orelse return error.NotAttached;

        var override_form_slices: [max_overrides][max_forms_per_override][]const u8 = undefined;
        var override_region_slices: [max_overrides][max_scopes_per_record][]const u8 = undefined;
        var override_taxpayer_slices: [max_overrides][max_scopes_per_record][]const u8 = undefined;
        var override_id_buffers: [max_overrides][24]u8 = undefined;
        var domain_overrides: [max_overrides]domain.DeadlineOverride = undefined;
        var domain_override_count: usize = 0;

        for (self.overrides[0..self.override_count]) |*row| {
            // The explorer/export is a global projection with no taxpayer
            // profile or region. Keep scoped policy visible and editable,
            // but never leak it into the nationwide schedule.
            if (!overrideAppliesToContext(row, taxpayer_context)) continue;
            const index = domain_override_count;
            for (row.form_codes[0..row.form_count], 0..) |*code, code_index| {
                override_form_slices[index][code_index] = code.text();
            }
            for (row.regions[0..row.region_count], 0..) |*region, scope_index| {
                override_region_slices[index][scope_index] = region.text();
            }
            for (
                row.taxpayer_types[0..row.taxpayer_type_count],
                0..,
            ) |*taxpayer_type, scope_index| {
                override_taxpayer_slices[index][scope_index] = taxpayer_type.text();
            }
            const stable_id = try std.fmt.bufPrint(
                &override_id_buffers[index],
                "sqlite:{d}",
                .{row.id},
            );
            domain_overrides[index] = .{
                .id = stable_id,
                .title = row.title.text(),
                .source_reference = row.source.text(),
                .affected_form_codes = override_form_slices[index][0..row.form_count],
                .original_deadline = row.original_deadline,
                .adjusted_deadline = row.adjusted_deadline,
                .affected_regions = override_region_slices[index][0..row.region_count],
                .affected_taxpayer_types = override_taxpayer_slices[index][0..row.taxpayer_type_count],
                .effective_from = row.effective_from,
                .effective_until = row.effective_until,
                .expires_at = row.expires_at,
            };
            domain_override_count += 1;
        }

        var day_region_slices: [max_non_working_days][max_scopes_per_record][]const u8 = undefined;
        var domain_days: [max_non_working_days]domain.NonWorkingDay = undefined;
        var domain_day_count: usize = 0;
        for (self.non_working_days[0..self.non_working_day_count]) |*row| {
            const kind = try parseNonWorkingKind(row.kind.text());
            // The global explorer has no region context. Only nationwide
            // closures can adjust its single authoritative projection. A
            // legacy local-holiday row with no region is invalid and remains
            // visible for cleanup, but must never become nationwide.
            if (!nonWorkingDayAppliesToContext(row, kind, taxpayer_context)) {
                continue;
            }
            const index = domain_day_count;
            for (row.regions[0..row.region_count], 0..) |*region, scope_index| {
                day_region_slices[index][scope_index] = region.text();
            }
            domain_days[index] = .{
                .date = row.date,
                .name = row.name.text(),
                .kind = kind,
                .regions = day_region_slices[index][0..row.region_count],
                .source_reference = row.source.text(),
            };
            domain_day_count += 1;
        }

        const resolved = try domain.resolveCalendarYear(
            allocator,
            self.selected_year,
            .{
                .calendar = .{
                    .non_working_days = domain_days[0..domain_day_count],
                },
                .overrides = domain_overrides[0..domain_override_count],
            },
        );
        defer allocator.free(resolved);
        if (resolved.len > max_deadlines) return error.TooManyDeadlines;

        self.deadline_count = 0;
        for (resolved, 0..) |deadline, index| {
            const original = deadline.originalDeadlineDate() orelse continue;
            const final = deadline.finalDeadlineDate() orelse continue;
            var row = DeadlineRow{
                .id = @intCast(index + 1),
                .rule_id = deadline.rule_id,
                .form_code = deadline.form_code,
                .display_form_no = deadline.display_form_no,
                .form_name = deadline.form_name,
                .description = deadline.description,
                .period = deadline.period,
                .original_deadline = original,
                .final_deadline = final,
                .status = deadline.status,
            };
            if (deadline.source_reference) |source| try row.source.set(source);
            self.deadlines[self.deadline_count] = row;
            self.deadline_count += 1;
        }
    }

    pub fn previousYear(self: *State) void {
        if (self.selected_year <= 2) return;
        self.selected_year -= 1;
        self.recompute() catch |err| {
            self.selected_year += 1;
            return self.setError(err);
        };
        self.setReloadNotice("Calendar year updated.");
    }

    pub fn nextYear(self: *State) void {
        if (self.selected_year >= 9997) return;
        self.selected_year += 1;
        self.recompute() catch |err| {
            self.selected_year -= 1;
            return self.setError(err);
        };
        self.setReloadNotice("Calendar year updated.");
    }

    pub fn previousMonth(self: *State) void {
        if (self.selected_month > 1) {
            self.selected_month -= 1;
            self.setReloadNotice("Calendar month updated.");
            return;
        }
        if (self.selected_year <= 2) return;

        self.selected_year -= 1;
        self.selected_month = 12;
        self.recompute() catch |err| {
            self.selected_year += 1;
            self.selected_month = 1;
            return self.setError(err);
        };
        self.setReloadNotice("Calendar month updated.");
    }

    pub fn nextMonth(self: *State) void {
        if (self.selected_month < 12) {
            self.selected_month += 1;
            self.setReloadNotice("Calendar month updated.");
            return;
        }
        if (self.selected_year >= 9997) return;

        self.selected_year += 1;
        self.selected_month = 1;
        self.recompute() catch |err| {
            self.selected_year -= 1;
            self.selected_month = 12;
            return self.setError(err);
        };
        self.setReloadNotice("Calendar month updated.");
    }

    pub fn refresh(self: *State) void {
        self.reload() catch |err| return self.setError(err);
        self.setReloadNotice(
            "Rules, overrides, and non-working days refreshed from SQLite.",
        );
    }

    pub fn saveOverride(self: *State) void {
        const store = self.store orelse return self.setError(error.NotAttached);
        if (self.override_input_was_truncated or self.overrideInputsTruncated()) {
            return self.setError(error.FieldTooLong);
        }
        if (self.editing_override_id == null and
            self.override_count >= max_overrides)
        {
            return self.setError(error.TooManyOverrides);
        }

        var forms: [max_forms_per_override][]const u8 = undefined;
        const form_count = parseCanonicalForms(
            self.override_forms.text(),
            &forms,
        ) catch |err| return self.setError(err);
        var regions: [max_scopes_per_record][]const u8 = undefined;
        const region_count = parseList(
            self.override_regions.text(),
            &regions,
        ) catch |err| return self.setError(err);
        var taxpayer_types: [max_scopes_per_record][]const u8 = undefined;
        const taxpayer_type_count = parseList(
            self.override_taxpayer_types.text(),
            &taxpayer_types,
        ) catch |err| return self.setError(err);
        ensureEntryLengths(regions[0..region_count], max_scope_text_bytes) catch |err|
            return self.setError(err);
        ensureEntryLengths(
            taxpayer_types[0..taxpayer_type_count],
            max_scope_text_bytes,
        ) catch |err| return self.setError(err);

        const effective_from = optionalTrimmed(
            self.override_effective_from.text(),
        );
        const effective_until = optionalTrimmed(
            self.override_effective_until.text(),
        );
        const expires_at = optionalTrimmed(self.override_expires_at.text());

        _ = store.putOverride(.{
            .id = self.editing_override_id,
            .title = trimmed(self.override_title.text()),
            .source = trimmed(self.override_source.text()),
            .original_deadline = trimmed(self.override_original.text()),
            .adjusted_deadline = trimmed(self.override_adjusted.text()),
            .effective_from = effective_from,
            .effective_until = effective_until,
            .expires_at = expires_at,
            .affected_form_codes = forms[0..form_count],
            .regions = regions[0..region_count],
            .taxpayer_types = taxpayer_types[0..taxpayer_type_count],
        }) catch |err| return self.setError(err);

        const was_editing = self.editing_override_id != null;
        self.clearOverrideEditor();
        self.reload() catch |err| return self.setError(err);
        self.setReloadNotice(
            if (was_editing) "Deadline override updated." else "Deadline override saved.",
        );
    }

    pub fn editOverride(self: *State, id: i64) void {
        const row = self.findOverride(id) orelse
            return self.setError(error.InvalidFormCode);
        self.editing_override_id = id;
        self.pending_delete_override_id = null;
        setEditorBuffer(&self.override_title, row.title.text());
        setEditorBuffer(&self.override_source, row.source.text());
        setDateBuffer(&self.override_original, row.original_deadline);
        setDateBuffer(&self.override_adjusted, row.adjusted_deadline);
        setOptionalDateBuffer(&self.override_effective_from, row.effective_from);
        setOptionalDateBuffer(
            &self.override_effective_until,
            row.effective_until,
        );
        setOptionalDateBuffer(&self.override_expires_at, row.expires_at);
        setJoinedBuffer(
            &self.override_forms,
            row.form_codes[0..row.form_count],
        );
        setJoinedBuffer(
            &self.override_regions,
            row.regions[0..row.region_count],
        );
        setJoinedBuffer(
            &self.override_taxpayer_types,
            row.taxpayer_types[0..row.taxpayer_type_count],
        );
        self.override_input_was_truncated = false;
        self.setNotice(.neutral, "Editing deadline override.");
    }

    pub fn deleteOverride(self: *State, id: i64) void {
        if (self.pending_delete_override_id != id) {
            self.pending_delete_override_id = id;
            self.setNotice(
                .neutral,
                "Press Delete on this override again to confirm permanent removal.",
            );
            return;
        }
        const store = self.store orelse return self.setError(error.NotAttached);
        const deleted = store.deleteOverride(id) catch |err| return self.setError(err);
        if (!deleted) return self.setError(error.InvalidFormCode);
        self.pending_delete_override_id = null;
        if (self.editing_override_id == id) self.clearOverrideEditor();
        self.reload() catch |err| return self.setError(err);
        self.setReloadNotice("Deadline override deleted.");
    }

    pub fn clearOverrideEditor(self: *State) void {
        self.editing_override_id = null;
        self.pending_delete_override_id = null;
        clearEditorBuffer(&self.override_title);
        clearEditorBuffer(&self.override_forms);
        clearEditorBuffer(&self.override_original);
        clearEditorBuffer(&self.override_adjusted);
        clearEditorBuffer(&self.override_source);
        clearEditorBuffer(&self.override_regions);
        clearEditorBuffer(&self.override_taxpayer_types);
        clearEditorBuffer(&self.override_effective_from);
        clearEditorBuffer(&self.override_effective_until);
        clearEditorBuffer(&self.override_expires_at);
        self.override_input_was_truncated = false;
    }

    pub fn saveNonWorkingDay(self: *State) void {
        const store = self.store orelse return self.setError(error.NotAttached);
        if (self.non_working_input_was_truncated or
            self.nonWorkingInputsTruncated())
        {
            return self.setError(error.FieldTooLong);
        }
        if (self.editing_non_working_day_id == null and
            self.non_working_day_count >= max_non_working_days)
        {
            return self.setError(error.TooManyNonWorkingDays);
        }
        const parsed_kind = parseNonWorkingKind(
            trimmed(self.non_working_kind.text()),
        ) catch |err|
            return self.setError(err);
        var regions: [max_scopes_per_record][]const u8 = undefined;
        const region_count = parseList(
            self.non_working_regions.text(),
            &regions,
        ) catch |err| return self.setError(err);
        ensureEntryLengths(regions[0..region_count], max_scope_text_bytes) catch |err|
            return self.setError(err);
        if (parsed_kind == .local_holiday and region_count == 0) {
            return self.setError(persistence.Error.InvalidValue);
        }

        _ = store.putNonWorkingDay(.{
            .id = self.editing_non_working_day_id,
            .day = trimmed(self.non_working_date.text()),
            .name = trimmed(self.non_working_name.text()),
            .kind = trimmed(self.non_working_kind.text()),
            .source = trimmed(self.non_working_source.text()),
            .regions = regions[0..region_count],
        }) catch |err| return self.setError(err);

        const was_editing = self.editing_non_working_day_id != null;
        self.clearNonWorkingDayEditor();
        self.reload() catch |err| return self.setError(err);
        self.setReloadNotice(
            if (was_editing) "Non-working day updated." else "Non-working day saved.",
        );
    }

    pub fn editNonWorkingDay(self: *State, id: i64) void {
        const row = self.findNonWorkingDay(id) orelse
            return self.setError(error.InvalidKind);
        self.editing_non_working_day_id = id;
        self.pending_delete_non_working_day_id = null;
        setDateBuffer(&self.non_working_date, row.date);
        setEditorBuffer(&self.non_working_name, row.name.text());
        setEditorBuffer(&self.non_working_kind, row.kind.text());
        setEditorBuffer(&self.non_working_source, row.source.text());
        setJoinedBuffer(
            &self.non_working_regions,
            row.regions[0..row.region_count],
        );
        self.non_working_input_was_truncated = false;
        self.setNotice(.neutral, "Editing non-working day.");
    }

    pub fn deleteNonWorkingDay(self: *State, id: i64) void {
        if (self.pending_delete_non_working_day_id != id) {
            self.pending_delete_non_working_day_id = id;
            self.setNotice(
                .neutral,
                "Press Delete on this non-working day again to confirm permanent removal.",
            );
            return;
        }
        const store = self.store orelse return self.setError(error.NotAttached);
        const deleted = store.deleteNonWorkingDay(id) catch |err|
            return self.setError(err);
        if (!deleted) return self.setError(error.InvalidKind);
        self.pending_delete_non_working_day_id = null;
        if (self.editing_non_working_day_id == id) {
            self.clearNonWorkingDayEditor();
        }
        self.reload() catch |err| return self.setError(err);
        self.setReloadNotice("Non-working day deleted.");
    }

    pub fn clearNonWorkingDayEditor(self: *State) void {
        self.editing_non_working_day_id = null;
        self.pending_delete_non_working_day_id = null;
        clearEditorBuffer(&self.non_working_date);
        clearEditorBuffer(&self.non_working_name);
        clearEditorBuffer(&self.non_working_kind);
        clearEditorBuffer(&self.non_working_source);
        clearEditorBuffer(&self.non_working_regions);
        self.non_working_input_was_truncated = false;
    }

    pub fn buildProfileIcs(
        self: *const State,
        allocator: std.mem.Allocator,
        dtstamp_utc: []const u8,
        profile: ProfileExport,
    ) ![]u8 {
        if (self.override_records_truncated or
            self.non_working_day_records_truncated)
        {
            return error.IncompleteProjection;
        }
        if (profile.key.len == 0 or profile.name.len == 0) {
            return error.InvalidProfile;
        }
        var events: [max_deadlines]ics.Event = undefined;
        var keys: [max_deadlines][80]u8 = undefined;
        var periods: [max_deadlines][64]u8 = undefined;
        var summaries: [max_deadlines][320]u8 = undefined;
        var descriptions: [max_deadlines][640]u8 = undefined;
        var calendar_name_buffer: [320]u8 = undefined;
        const calendar_name = try std.fmt.bufPrint(
            &calendar_name_buffer,
            "{s} — eBIRForms Tax Deadlines",
            .{profile.name},
        );

        var event_count: usize = 0;
        for (self.deadlines[0..self.deadline_count]) |*row| {
            if (!profileIncludesForm(profile.form_scope, row.form_code)) continue;

            const key = try row.obligationKey(&keys[event_count]);
            const period = formatPeriodInto(&periods[event_count], row.period);
            const summary = try std.fmt.bufPrint(
                &summaries[event_count],
                "[BIR] {s} — {s} — {s}",
                .{ profile.name, row.display_form_no, period },
            );
            var original: [10]u8 = undefined;
            var final: [10]u8 = undefined;
            const description = try std.fmt.bufPrint(
                &descriptions[event_count],
                "Tax profile: {s}\n{s}\nTaxable period: {s}\nStatutory deadline: {s}\nFinal deadline: {s}\nStatus: {s}{s}{s}",
                .{
                    profile.name,
                    row.form_name,
                    period,
                    row.original_deadline.writeIso(&original),
                    row.final_deadline.writeIso(&final),
                    row.status.label(),
                    if (row.source.len == 0) "" else "\nSource: ",
                    row.source.text(),
                },
            );
            events[event_count] = .{
                .obligation_key = key,
                .date = .{
                    .year = row.final_deadline.year,
                    .month = row.final_deadline.month,
                    .day = row.final_deadline.day,
                },
                .summary = summary,
                .description = description,
            };
            event_count += 1;
        }

        if (event_count == 0) return error.NoCalendarEvents;

        // The caller supplies the profile's persisted calendar selection.
        // When Forms Sets become the authoritative profile-form source, pass
        // the intersection here together with region, taxpayer type, fiscal
        // year, and eFPS group before treating this as a filing plan.
        return ics.generate(
            allocator,
            events[0..event_count],
            .{
                .calendar_name = calendar_name,
                .uid_namespace = profile.key,
                .dtstamp_utc = dtstamp_utc,
            },
        );
    }

    pub fn setError(self: *State, err: anyerror) void {
        var buffer: [220]u8 = undefined;
        const text = std.fmt.bufPrint(
            &buffer,
            "Calendar operation failed: {s}",
            .{@errorName(err)},
        ) catch "Calendar operation failed.";
        self.setNotice(.failure, text);
    }

    pub fn setNotice(
        self: *State,
        kind: NoticeKind,
        message: []const u8,
    ) void {
        self.notice.set(message) catch {
            self.notice.clear();
            self.notice.set("Calendar status message was too long.") catch {};
            self.notice_kind = .failure;
            return;
        };
        self.notice_kind = kind;
    }

    pub fn captureOverrideInputTruncation(self: *State) void {
        self.override_input_was_truncated =
            self.override_input_was_truncated or self.overrideInputsTruncated();
    }

    pub fn captureNonWorkingInputTruncation(self: *State) void {
        self.non_working_input_was_truncated =
            self.non_working_input_was_truncated or
            self.nonWorkingInputsTruncated();
    }

    fn overrideInputsTruncated(self: *const State) bool {
        return self.override_title.truncated or
            self.override_forms.truncated or
            self.override_original.truncated or
            self.override_adjusted.truncated or
            self.override_source.truncated or
            self.override_regions.truncated or
            self.override_taxpayer_types.truncated or
            self.override_effective_from.truncated or
            self.override_effective_until.truncated or
            self.override_expires_at.truncated;
    }

    fn nonWorkingInputsTruncated(self: *const State) bool {
        return self.non_working_date.truncated or
            self.non_working_name.truncated or
            self.non_working_kind.truncated or
            self.non_working_source.truncated or
            self.non_working_regions.truncated;
    }

    fn setReloadNotice(self: *State, success_message: []const u8) void {
        if (self.override_records_truncated or
            self.non_working_day_records_truncated)
        {
            self.setNotice(
                .failure,
                "SQLite exceeds the safe editor page size. The first records are shown; remove records to reveal and recover the remaining rows.",
            );
            return;
        }
        self.setNotice(.success, success_message);
    }

    fn copyOverride(self: *State, item: persistence.OwnedOverride) !void {
        if (self.override_count >= max_overrides) return error.TooManyOverrides;
        if (item.affected_form_codes.len > max_forms_per_override) {
            return error.TooManyForms;
        }
        if (item.regions.len > max_scopes_per_record or
            item.taxpayer_types.len > max_scopes_per_record)
        {
            return error.TooManyScopes;
        }

        var row = OverrideRow{
            .id = item.id,
            .original_deadline = try domain.Date.parseIso(item.original_deadline),
            .adjusted_deadline = try domain.Date.parseIso(item.adjusted_deadline),
            .effective_from = if (item.effective_from) |date|
                try domain.Date.parseIso(date)
            else
                null,
            .effective_until = if (item.effective_until) |date|
                try domain.Date.parseIso(date)
            else
                null,
            .expires_at = if (item.expires_at) |date|
                try domain.Date.parseIso(date)
            else
                null,
        };
        try row.title.set(item.title);
        try row.source.set(item.source);
        for (item.affected_form_codes, 0..) |form_code, index| {
            const canonical = domain.canonicalFormCode(form_code);
            if (std.mem.eql(u8, canonical, domain.unknown_form_code)) {
                return error.InvalidFormCode;
            }
            try row.form_codes[index].set(canonical);
        }
        row.form_count = item.affected_form_codes.len;
        for (item.regions, 0..) |region, index| {
            try row.regions[index].set(region);
        }
        row.region_count = item.regions.len;
        for (item.taxpayer_types, 0..) |taxpayer_type, index| {
            try row.taxpayer_types[index].set(taxpayer_type);
        }
        row.taxpayer_type_count = item.taxpayer_types.len;

        self.overrides[self.override_count] = row;
        self.override_count += 1;
    }

    fn copyNonWorkingDay(
        self: *State,
        item: persistence.OwnedNonWorkingDay,
    ) !void {
        if (self.non_working_day_count >= max_non_working_days) {
            return error.TooManyNonWorkingDays;
        }
        if (item.regions.len > max_scopes_per_record) return error.TooManyScopes;
        _ = try parseNonWorkingKind(item.kind);

        var row = NonWorkingDayRow{
            .id = item.id,
            .date = try domain.Date.parseIso(item.day),
        };
        try row.name.set(item.name);
        try row.kind.set(item.kind);
        try row.source.set(item.source);
        for (item.regions, 0..) |region, index| {
            try row.regions[index].set(region);
        }
        row.region_count = item.regions.len;

        self.non_working_days[self.non_working_day_count] = row;
        self.non_working_day_count += 1;
    }

    fn findOverride(self: *const State, id: i64) ?*const OverrideRow {
        for (self.overrides[0..self.override_count]) |*row| {
            if (row.id == id) return row;
        }
        return null;
    }

    fn findNonWorkingDay(self: *const State, id: i64) ?*const NonWorkingDayRow {
        for (self.non_working_days[0..self.non_working_day_count]) |*row| {
            if (row.id == id) return row;
        }
        return null;
    }
};

fn overrideAppliesToContext(
    row: *const OverrideRow,
    taxpayer_context: ?TaxpayerContext,
) bool {
    const context = taxpayer_context orelse
        return row.region_count == 0 and row.taxpayer_type_count == 0;

    if (row.region_count != 0 and
        !scopeMatchesRegionOrRdo(row.regions[0..row.region_count], context))
    {
        return false;
    }
    if (row.taxpayer_type_count != 0 and
        !scopeMatchesValue(
            row.taxpayer_types[0..row.taxpayer_type_count],
            context.taxpayer_type,
        ))
    {
        return false;
    }
    return true;
}

fn nonWorkingDayAppliesToContext(
    row: *const NonWorkingDayRow,
    kind: domain.NonWorkingDayKind,
    taxpayer_context: ?TaxpayerContext,
) bool {
    const context = taxpayer_context orelse
        return row.region_count == 0 and kind != .local_holiday;

    // A local holiday is meaningful only with an explicit stored scope and a
    // matching taxpayer region/RDO. This also quarantines legacy unscoped
    // local rows that predate the store validation.
    if (kind == .local_holiday and row.region_count == 0) return false;
    if (row.region_count == 0) return true;
    return scopeMatchesRegionOrRdo(
        row.regions[0..row.region_count],
        context,
    );
}

fn scopeMatchesRegionOrRdo(
    scopes: []const ScopeText,
    context: TaxpayerContext,
) bool {
    return scopeMatchesValue(scopes, context.region) or
        scopeMatchesValue(scopes, context.rdo);
}

fn scopeMatchesValue(
    scopes: []const ScopeText,
    candidate: ?[]const u8,
) bool {
    const raw_value = candidate orelse return false;
    const value = trimmed(raw_value);
    if (value.len == 0) return false;
    for (scopes) |*scope| {
        if (std.ascii.eqlIgnoreCase(scope.text(), value)) return true;
    }
    return false;
}

fn profileIncludesForm(scope: ProfileFormScope, form_code: []const u8) bool {
    return switch (scope) {
        .catalog_fallback => true,
        .registered => |registered| for (registered) |candidate| {
            if (std.mem.eql(u8, candidate, form_code) or
                (std.mem.eql(u8, candidate, "1604CF") and
                    (std.mem.eql(u8, form_code, "1604C") or
                        std.mem.eql(u8, form_code, "1604F")))) break true;
        } else false,
    };
}

pub fn ruleRows(arena: std.mem.Allocator) []const RuleRow {
    const rows = arena.alloc(RuleRow, domain.OFFICIAL_RULES.len) catch return &.{};
    for (domain.OFFICIAL_RULES, 0..) |rule, index| {
        var joined: std.ArrayList(u8) = .empty;
        for (rule.form_nos, 0..) |form_no, form_index| {
            if (form_index != 0) joined.appendSlice(arena, ", ") catch break;
            joined.appendSlice(arena, form_no) catch break;
        }
        rows[index] = .{
            .id = index + 1,
            .form_codes = joined.items,
            .form_name = rule.form_name,
            .frequency = frequencyLabel(rule.frequency),
            .description = rule.description,
        };
    }
    return rows;
}

fn frequencyLabel(frequency: domain.Frequency) []const u8 {
    return switch (frequency) {
        .monthly => "Monthly",
        .quarterly => "Quarterly",
        .annual => "Annual",
        .as_needed => "Event-based",
    };
}

fn parseCanonicalForms(
    value: []const u8,
    output: *[max_forms_per_override][]const u8,
) !usize {
    var raw: [max_forms_per_override][]const u8 = undefined;
    const count = try parseList(value, &raw);
    if (count == 0) return persistence.Error.AffectedFormRequired;

    var output_count: usize = 0;
    for (raw[0..count]) |form_code| {
        const canonical = domain.canonicalFormCode(form_code);
        if (std.mem.eql(u8, canonical, domain.unknown_form_code)) {
            return error.InvalidFormCode;
        }
        if (containsIgnoreCase(output[0..output_count], canonical)) continue;
        output[output_count] = canonical;
        output_count += 1;
    }
    return output_count;
}

fn parseList(value: []const u8, output: anytype) !usize {
    // Scope names commonly contain spaces ("Region IV-A", "mixed income
    // earner"). Only explicit separators split entries.
    var iterator = std.mem.tokenizeAny(u8, value, ",;\r\n");
    var count: usize = 0;
    while (iterator.next()) |raw_entry| {
        const entry = trimmed(raw_entry);
        if (entry.len == 0) continue;
        if (count >= output.len) return error.TooManyScopes;
        if (containsIgnoreCase(output[0..count], entry)) continue;
        output[count] = entry;
        count += 1;
    }
    return count;
}

fn containsIgnoreCase(values: []const []const u8, wanted: []const u8) bool {
    for (values) |value| {
        if (std.ascii.eqlIgnoreCase(value, wanted)) return true;
    }
    return false;
}

fn ensureEntryLengths(values: []const []const u8, max: usize) StateError!void {
    for (values) |value| {
        if (value.len > max) return error.FieldTooLong;
    }
}

fn optionalTrimmed(value: []const u8) ?[]const u8 {
    const normalized = trimmed(value);
    return if (normalized.len == 0) null else normalized;
}

fn trimmed(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn parseNonWorkingKind(value: []const u8) StateError!domain.NonWorkingDayKind {
    if (std.ascii.eqlIgnoreCase(value, "regular") or
        std.ascii.eqlIgnoreCase(value, "regular_holiday"))
    {
        return .regular_holiday;
    }
    if (std.ascii.eqlIgnoreCase(value, "local") or
        std.ascii.eqlIgnoreCase(value, "local_holiday"))
    {
        return .local_holiday;
    }
    if (std.ascii.eqlIgnoreCase(value, "special") or
        std.ascii.eqlIgnoreCase(value, "special_non_working_day"))
    {
        return .special_non_working_day;
    }
    if (std.ascii.eqlIgnoreCase(value, "closure") or
        std.ascii.eqlIgnoreCase(value, "other_closure"))
    {
        return .other_closure;
    }
    return error.InvalidKind;
}

fn formatPeriod(arena: std.mem.Allocator, period: domain.Period) []const u8 {
    return switch (period) {
        .monthly => |value| std.fmt.allocPrint(
            arena,
            "{s} {d}",
            .{ monthName(value.month), value.taxable_year },
        ) catch "",
        .quarterly => |value| std.fmt.allocPrint(
            arena,
            "Q{d} {d}",
            .{ value.quarter, value.taxable_year },
        ) catch "",
        .annual => |value| std.fmt.allocPrint(
            arena,
            "Taxable year {d}",
            .{value.taxable_year},
        ) catch "",
        .event_based => "Event-based",
    };
}

fn formatPeriodInto(output: []u8, period: domain.Period) []const u8 {
    return switch (period) {
        .monthly => |value| std.fmt.bufPrint(
            output,
            "{s} {d}",
            .{ monthName(value.month), value.taxable_year },
        ) catch "",
        .quarterly => |value| std.fmt.bufPrint(
            output,
            "Q{d} {d}",
            .{ value.quarter, value.taxable_year },
        ) catch "",
        .annual => |value| std.fmt.bufPrint(
            output,
            "Taxable year {d}",
            .{value.taxable_year},
        ) catch "",
        .event_based => "Event-based",
    };
}

fn monthName(month: u8) []const u8 {
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
        else => "Invalid month",
    };
}

fn monthAbbreviation(month: u8) []const u8 {
    return switch (month) {
        1 => "JAN",
        2 => "FEB",
        3 => "MAR",
        4 => "APR",
        5 => "MAY",
        6 => "JUN",
        7 => "JUL",
        8 => "AUG",
        9 => "SEP",
        10 => "OCT",
        11 => "NOV",
        12 => "DEC",
        else => "???",
    };
}

fn joinFixedTexts(
    arena: std.mem.Allocator,
    values: anytype,
    separator: []const u8,
) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (values, 0..) |*value, index| {
        if (index != 0) out.appendSlice(arena, separator) catch return "";
        out.appendSlice(arena, value.text()) catch return "";
    }
    return out.items;
}

fn setJoinedBuffer(buffer: anytype, values: anytype) void {
    var scratch: [max_joined_scopes_bytes]u8 = undefined;
    var length: usize = 0;
    for (values, 0..) |*value, index| {
        if (index != 0) {
            if (length + 2 > scratch.len) break;
            scratch[length] = ',';
            scratch[length + 1] = ' ';
            length += 2;
        }
        const text = value.text();
        if (length + text.len > scratch.len) break;
        @memcpy(scratch[length..][0..text.len], text);
        length += text.len;
    }
    setEditorBuffer(buffer, scratch[0..length]);
}

fn setEditorBuffer(buffer: anytype, value: []const u8) void {
    buffer.set(value);
    // `TextBuffer.set` is intentionally clamping and does not update this
    // seam. Capacities above cover every normalized SQLite record.
    buffer.truncated = value.len > buffer.storage.len;
}

fn clearEditorBuffer(buffer: anytype) void {
    buffer.clear();
    buffer.truncated = false;
}

fn setDateBuffer(buffer: anytype, date: domain.Date) void {
    var value: [10]u8 = undefined;
    setEditorBuffer(buffer, date.writeIso(&value));
}

fn setOptionalDateBuffer(buffer: anytype, date: ?domain.Date) void {
    if (date) |value| {
        setDateBuffer(buffer, value);
    } else {
        clearEditorBuffer(buffer);
    }
}

fn testOverrideRow(
    id: i64,
    adjusted_deadline: domain.Date,
    regions: []const []const u8,
    taxpayer_types: []const []const u8,
) !OverrideRow {
    var row = OverrideRow{
        .id = id,
        .original_deadline = try domain.Date.init(2026, 5, 15),
        .adjusted_deadline = adjusted_deadline,
    };
    try row.title.set("Scoped override fixture");
    try row.source.set("Official test source");
    try row.form_codes[0].set("1701Q");
    row.form_count = 1;
    for (regions, 0..) |region, index| try row.regions[index].set(region);
    row.region_count = regions.len;
    for (taxpayer_types, 0..) |taxpayer_type, index| {
        try row.taxpayer_types[index].set(taxpayer_type);
    }
    row.taxpayer_type_count = taxpayer_types.len;
    return row;
}

fn testNonWorkingDayRow(
    id: i64,
    date: domain.Date,
    kind: []const u8,
    regions: []const []const u8,
) !NonWorkingDayRow {
    var row = NonWorkingDayRow{ .id = id, .date = date };
    try row.name.set("Scoped non-working day fixture");
    try row.kind.set(kind);
    try row.source.set("Official test source");
    for (regions, 0..) |region, index| try row.regions[index].set(region);
    row.region_count = regions.len;
    return row;
}

fn findDatedDeadline(
    state: *const State,
    form_code: []const u8,
    original_deadline: domain.Date,
) ?*const DeadlineRow {
    for (state.deadlines[0..state.deadline_count]) |*row| {
        if (std.mem.eql(u8, row.form_code, form_code) and
            domain.Date.compare(row.original_deadline, original_deadline) == .eq)
        {
            return row;
        }
    }
    return null;
}

test "state persists overrides and recomputes the calendar" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        7,
    );
    const original_count = state.deadline_count;
    try std.testing.expect(original_count > 100);

    state.override_title.set("Q1 extension");
    state.override_forms.set("1701Q");
    state.override_original.set("2026-05-15");
    state.override_adjusted.set("2026-06-15");
    state.override_source.set("BIR test issuance");
    state.saveOverride();

    try std.testing.expectEqual(@as(usize, 1), state.override_count);
    try std.testing.expectEqual(NoticeKind.success, state.notice_kind);
    var found = false;
    for (state.deadlines[0..state.deadline_count]) |row| {
        if (std.mem.eql(u8, row.form_code, "1701Q") and
            domain.Date.compare(
                row.original_deadline,
                try domain.Date.init(2026, 5, 15),
            ) == .eq)
        {
            found = true;
            try std.testing.expectEqual(
                try domain.Date.init(2026, 6, 15),
                row.final_deadline,
            );
            try std.testing.expectEqual(domain.DeadlineStatus.extended, row.status);
        }
    }
    try std.testing.expect(found);
}

test "nationwide non-working days adjust while regional days remain scoped" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const nationwide_id = try store.putNonWorkingDay(.{
        .day = "2026-05-15",
        .name = "Nationwide test holiday",
        .kind = "regular",
        .source = "Official test source",
    });
    _ = nationwide_id;
    _ = try store.putNonWorkingDay(.{
        .day = "2026-04-15",
        .name = "Regional test holiday",
        .kind = "local",
        .source = "Official test source",
        .regions = &.{"NCR"},
    });

    var state = State{};
    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        7,
    );

    var quarterly_shifted = false;
    var annual_unshifted = false;
    for (state.deadlines[0..state.deadline_count]) |row| {
        if (std.mem.eql(u8, row.form_code, "1701Q") and
            domain.Date.compare(
                row.original_deadline,
                try domain.Date.init(2026, 5, 15),
            ) == .eq)
        {
            quarterly_shifted =
                domain.Date.compare(
                    row.final_deadline,
                    try domain.Date.init(2026, 5, 18),
                ) == .eq;
        }
        if (std.mem.eql(u8, row.form_code, "1701") and
            domain.Date.compare(
                row.original_deadline,
                try domain.Date.init(2026, 4, 15),
            ) == .eq)
        {
            annual_unshifted =
                domain.Date.compare(row.final_deadline, row.original_deadline) == .eq;
        }
    }
    try std.testing.expect(quarterly_shifted);
    try std.testing.expect(annual_unshifted);
}

test "legacy unscoped local holiday never becomes nationwide" {
    var state = State{
        .allocator = std.testing.allocator,
        .selected_year = 2026,
        .selected_month = 5,
    };
    var legacy = NonWorkingDayRow{
        .id = 1,
        .date = try domain.Date.init(2026, 5, 15),
    };
    try legacy.name.set("Legacy local row");
    try legacy.kind.set("local");
    try legacy.source.set("Legacy SQLite fixture");
    state.non_working_days[0] = legacy;
    state.non_working_day_count = 1;

    try state.recompute();
    for (state.deadlines[0..state.deadline_count]) |row| {
        if (std.mem.eql(u8, row.form_code, "1701Q") and
            domain.Date.compare(
                row.original_deadline,
                try domain.Date.init(2026, 5, 15),
            ) == .eq)
        {
            try std.testing.expectEqual(row.original_deadline, row.final_deadline);
            try std.testing.expectEqual(domain.DeadlineStatus.normal, row.status);
            return;
        }
    }
    return error.TestExpectedEqual;
}

test "taxpayer recompute applies loaded override scopes case-insensitively" {
    var state = State{
        .allocator = std.testing.allocator,
        .selected_year = 2026,
        .selected_month = 5,
    };
    state.overrides[0] = try testOverrideRow(
        1,
        try domain.Date.init(2026, 5, 20),
        &.{},
        &.{},
    );
    state.overrides[1] = try testOverrideRow(
        2,
        try domain.Date.init(2026, 6, 15),
        &.{"NCR"},
        &.{},
    );
    state.overrides[2] = try testOverrideRow(
        3,
        try domain.Date.init(2026, 7, 15),
        &.{},
        &.{"Corporation"},
    );
    state.overrides[3] = try testOverrideRow(
        4,
        try domain.Date.init(2026, 8, 14),
        &.{"NCR"},
        &.{"Corporation"},
    );
    state.override_count = 4;
    const original = try domain.Date.init(2026, 5, 15);

    // The existing global projection still admits only the unscoped record.
    try state.recompute();
    try std.testing.expectEqual(
        try domain.Date.init(2026, 5, 20),
        findDatedDeadline(&state, "1701Q", original).?.final_deadline,
    );

    // A mismatched taxpayer still receives the unscoped policy.
    try state.recomputeForTaxpayer(.{
        .region = "Region VII",
        .taxpayer_type = "Individual",
    });
    try std.testing.expectEqual(
        try domain.Date.init(2026, 5, 20),
        findDatedDeadline(&state, "1701Q", original).?.final_deadline,
    );

    // RDO and taxpayer-type scopes are both ASCII case-insensitive.
    try state.recomputeForTaxpayer(.{
        .rdo = "ncr",
        .taxpayer_type = "Individual",
    });
    try std.testing.expectEqual(
        try domain.Date.init(2026, 6, 15),
        findDatedDeadline(&state, "1701Q", original).?.final_deadline,
    );
    try state.recomputeForTaxpayer(.{
        .region = "Region VII",
        .taxpayer_type = "CORPORATION",
    });
    try std.testing.expectEqual(
        try domain.Date.init(2026, 7, 15),
        findDatedDeadline(&state, "1701Q", original).?.final_deadline,
    );

    // A record carrying both scopes requires both to match. The later matching
    // record wins using the same deterministic precedence as global reloads.
    try state.recomputeForTaxpayer(.{
        .region = "nCr",
        .taxpayer_type = "corporation",
    });
    try std.testing.expectEqual(
        try domain.Date.init(2026, 8, 14),
        findDatedDeadline(&state, "1701Q", original).?.final_deadline,
    );
}

test "taxpayer recompute applies scoped days and quarantines unscoped local holidays" {
    var state = State{
        .allocator = std.testing.allocator,
        .selected_year = 2026,
        .selected_month = 5,
    };
    state.non_working_days[0] = try testNonWorkingDayRow(
        1,
        try domain.Date.init(2026, 4, 15),
        "regular",
        &.{},
    );
    state.non_working_days[1] = try testNonWorkingDayRow(
        2,
        try domain.Date.init(2026, 5, 15),
        "special",
        &.{"NCR"},
    );
    state.non_working_days[2] = try testNonWorkingDayRow(
        3,
        try domain.Date.init(2026, 6, 10),
        "local",
        &.{"NCR"},
    );
    state.non_working_days[3] = try testNonWorkingDayRow(
        4,
        try domain.Date.init(2026, 7, 10),
        "local",
        &.{},
    );
    state.non_working_day_count = 4;

    try state.recomputeForTaxpayer(.{
        .region = "Region VII",
        .taxpayer_type = "Individual",
    });
    try std.testing.expectEqual(
        try domain.Date.init(2026, 4, 16),
        findDatedDeadline(
            &state,
            "1701",
            try domain.Date.init(2026, 4, 15),
        ).?.final_deadline,
    );
    try std.testing.expectEqual(
        try domain.Date.init(2026, 5, 15),
        findDatedDeadline(
            &state,
            "1701Q",
            try domain.Date.init(2026, 5, 15),
        ).?.final_deadline,
    );
    try std.testing.expectEqual(
        try domain.Date.init(2026, 6, 10),
        findDatedDeadline(
            &state,
            "0619E",
            try domain.Date.init(2026, 6, 10),
        ).?.final_deadline,
    );

    try state.recomputeForTaxpayer(.{ .region = "ncr" });
    try std.testing.expectEqual(
        try domain.Date.init(2026, 5, 18),
        findDatedDeadline(
            &state,
            "1701Q",
            try domain.Date.init(2026, 5, 15),
        ).?.final_deadline,
    );
    try std.testing.expectEqual(
        try domain.Date.init(2026, 6, 11),
        findDatedDeadline(
            &state,
            "0619E",
            try domain.Date.init(2026, 6, 10),
        ).?.final_deadline,
    );
    try std.testing.expectEqual(
        try domain.Date.init(2026, 7, 10),
        findDatedDeadline(
            &state,
            "1600VT",
            try domain.Date.init(2026, 7, 10),
        ).?.final_deadline,
    );

    const first_count = state.deadline_count;
    var first_projection: [max_deadlines]DeadlineRow = undefined;
    @memcpy(
        first_projection[0..first_count],
        state.deadlines[0..first_count],
    );
    try state.recomputeForTaxpayer(.{ .region = "Region VII" });
    try state.recomputeForTaxpayer(.{ .rdo = "NCR" });
    try std.testing.expectEqual(first_count, state.deadline_count);
    for (
        first_projection[0..first_count],
        state.deadlines[0..state.deadline_count],
    ) |expected, actual| {
        try std.testing.expectEqual(expected.id, actual.id);
        try std.testing.expectEqualStrings(expected.rule_id, actual.rule_id);
        try std.testing.expectEqualStrings(expected.form_code, actual.form_code);
        try std.testing.expectEqual(expected.original_deadline, actual.original_deadline);
        try std.testing.expectEqual(expected.final_deadline, actual.final_deadline);
        try std.testing.expectEqual(expected.status, actual.status);
        try std.testing.expectEqualStrings(expected.sourceLabel(), actual.sourceLabel());
    }
}

test "ICS export contains the complete selected calendar year" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        7,
    );
    const bytes = try state.buildProfileIcs(
        allocator,
        "20260729T010203Z",
        .{
            .key = "profile-alpha",
            .name = "Alpha Profile",
            .form_scope = .catalog_fallback,
        },
    );
    defer allocator.free(bytes);

    try std.testing.expectEqual(
        state.deadline_count,
        std.mem.count(u8, bytes, "BEGIN:VEVENT"),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "UID:profile-alpha:2026:1701Q:q1@ebirforms.goldcoders.dev",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "UID:profile-alpha:2025:1604-C:annual@ebirforms.goldcoders.dev",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "UID:profile-alpha:2025:1604-F:annual@ebirforms.goldcoders.dev",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "UID:profile-alpha:2025:2316:annual:employee-copy@ebirforms.goldcoders.dev",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "UID:profile-alpha:2025:2316:annual:bir-copy@ebirforms.goldcoders.dev",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "X-WR-CALNAME:Alpha Profile — eBIRForms Tax Deadlines",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "X-EBIRFORMS-OBLIGATION-KEY:2026:1701Q:q1",
    ) != null);

    var unique_uids = std.StringHashMap(void).init(allocator);
    defer unique_uids.deinit();
    var lines = std.mem.splitSequence(u8, bytes, "\r\n");
    var uid_count: usize = 0;
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "UID:")) continue;
        const inserted = try unique_uids.getOrPut(line[4..]);
        try std.testing.expect(!inserted.found_existing);
        uid_count += 1;
    }
    try std.testing.expectEqual(state.deadline_count, uid_count);
    try std.testing.expectEqual(uid_count, unique_uids.count());
}

test "profile calendar selection filters canonical forms and grouped codes" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        7,
    );

    const vat_forms = [_][]const u8{"2550Q"};
    const vat_bytes = try state.buildProfileIcs(
        allocator,
        "20260729T010203Z",
        .{
            .key = "profile-vat",
            .name = "VAT Profile",
            .form_scope = .{ .registered = &vat_forms },
        },
    );
    defer allocator.free(vat_bytes);
    try std.testing.expect(std.mem.count(u8, vat_bytes, "BEGIN:VEVENT") > 0);
    try std.testing.expect(std.mem.indexOf(u8, vat_bytes, ":2550Q:") != null);
    try std.testing.expect(std.mem.indexOf(u8, vat_bytes, ":1701Q:") == null);

    const withholding_forms = [_][]const u8{"1604CF"};
    const withholding_bytes = try state.buildProfileIcs(
        allocator,
        "20260729T010203Z",
        .{
            .key = "profile-withholding",
            .name = "Withholding Profile",
            .form_scope = .{ .registered = &withholding_forms },
        },
    );
    defer allocator.free(withholding_bytes);
    try std.testing.expect(
        std.mem.indexOf(u8, withholding_bytes, ":1604-C:") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, withholding_bytes, ":1604-F:") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, withholding_bytes, ":1621:") == null,
    );

    const no_forms = [_][]const u8{};
    try std.testing.expectError(
        error.NoCalendarEvents,
        state.buildProfileIcs(
            allocator,
            "20260729T010203Z",
            .{
                .key = "profile-empty",
                .name = "Empty Forms Set",
                .form_scope = .{ .registered = &no_forms },
            },
        ),
    );
}

test "attach validates and records the selected month" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try std.testing.expectError(error.InvalidMonth, state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        0,
    ));
    try std.testing.expect(state.allocator == null);
    try std.testing.expect(state.store == null);

    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        12,
    );
    try std.testing.expectEqual(@as(u8, 12), state.selected_month);
}

test "month navigation recomputes only when crossing a year boundary" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        6,
    );

    // A same-year month move does not rebuild the already-resolved annual
    // schedule. The zero count acts as an observable recomputation sentinel.
    state.deadline_count = 0;
    state.previousMonth();
    try std.testing.expectEqual(@as(i32, 2026), state.selected_year);
    try std.testing.expectEqual(@as(u8, 5), state.selected_month);
    try std.testing.expectEqual(@as(usize, 0), state.deadline_count);
    state.nextMonth();
    try std.testing.expectEqual(@as(u8, 6), state.selected_month);
    try std.testing.expectEqual(@as(usize, 0), state.deadline_count);

    state.selected_month = 12;
    state.nextMonth();
    try std.testing.expectEqual(@as(i32, 2027), state.selected_year);
    try std.testing.expectEqual(@as(u8, 1), state.selected_month);
    try std.testing.expect(state.deadline_count > 100);

    state.deadline_count = 0;
    state.previousMonth();
    try std.testing.expectEqual(@as(i32, 2026), state.selected_year);
    try std.testing.expectEqual(@as(u8, 12), state.selected_month);
    try std.testing.expect(state.deadline_count > 100);
}

test "SQLite insertion order preserves later override precedence" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const forms = [_][]const u8{"1701Q"};
    _ = try store.putOverride(.{
        .title = "First extension",
        .source = "First official source",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-06-15",
        .affected_form_codes = &forms,
    });
    _ = try store.putOverride(.{
        .title = "Later correction",
        .source = "Later official source",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-06-10",
        .affected_form_codes = &forms,
    });

    var state = State{};
    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        5,
    );

    for (state.deadlines[0..state.deadline_count]) |row| {
        if (std.mem.eql(u8, row.form_code, "1701Q") and
            domain.Date.compare(
                row.original_deadline,
                try domain.Date.init(2026, 5, 15),
            ) == .eq)
        {
            try std.testing.expectEqual(
                try domain.Date.init(2026, 6, 10),
                row.final_deadline,
            );
            try std.testing.expectEqualStrings(
                "Later official source",
                row.sourceLabel(),
            );
            return;
        }
    }
    return error.TestExpectedEqual;
}

test "scoped overrides remain stored but do not leak into global projection" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    _ = try store.putOverride(.{
        .title = "NCR-only extension",
        .source = "Official regional fixture",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-06-15",
        .affected_form_codes = &.{"1701Q"},
        .regions = &.{"NCR"},
    });

    var state = State{};
    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        5,
    );
    try std.testing.expectEqual(@as(usize, 1), state.override_count);
    for (state.deadlines[0..state.deadline_count]) |row| {
        if (std.mem.eql(u8, row.form_code, "1701Q") and
            domain.Date.compare(
                row.original_deadline,
                try domain.Date.init(2026, 5, 15),
            ) == .eq)
        {
            try std.testing.expectEqual(row.original_deadline, row.final_deadline);
            try std.testing.expectEqual(domain.DeadlineStatus.normal, row.status);
            return;
        }
    }
    return error.TestExpectedEqual;
}

test "override temporal metadata and multi-word scopes round trip" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var state = State{};
    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        5,
    );
    state.override_title.set("Scoped fixture");
    state.override_forms.set("1701Q");
    state.override_original.set("2026-05-15");
    state.override_adjusted.set("2026-05-22");
    state.override_source.set("Official fixture");
    state.override_regions.set("Region IV-A; NCR");
    state.override_taxpayer_types.set("Mixed income earner");
    state.override_effective_from.set("2026-05-01");
    state.override_effective_until.set("2026-05-31");
    state.override_expires_at.set("2027-05-31");
    state.saveOverride();

    try std.testing.expectEqual(NoticeKind.success, state.notice_kind);
    try std.testing.expectEqual(@as(usize, 1), state.override_count);
    const row = state.overrides[0];
    try std.testing.expectEqual(@as(usize, 2), row.region_count);
    try std.testing.expect(
        std.mem.eql(u8, row.regions[0].text(), "Region IV-A") or
            std.mem.eql(u8, row.regions[1].text(), "Region IV-A"),
    );
    try std.testing.expectEqualStrings(
        "Mixed income earner",
        row.taxpayer_types[0].text(),
    );
    try std.testing.expectEqual(
        try domain.Date.init(2026, 5, 31),
        row.effective_until.?,
    );
    try std.testing.expectEqual(
        try domain.Date.init(2027, 5, 31),
        row.expires_at.?,
    );
}

test "delete requires a repeated explicit confirmation" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    const id = try store.putOverride(.{
        .title = "Delete fixture",
        .source = "Official fixture",
        .original_deadline = "2026-05-15",
        .adjusted_deadline = "2026-05-22",
        .affected_form_codes = &.{"1701Q"},
    });

    var state = State{};
    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        5,
    );
    state.deleteOverride(id);
    var still_present = try store.getOverride(allocator, id);
    try std.testing.expect(still_present != null);
    if (still_present) |*item| item.deinit(allocator);

    state.deleteOverride(id);
    try std.testing.expect((try store.getOverride(allocator, id)) == null);
}

test "overflow stays recoverable and blocks incomplete export" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    var title: [32]u8 = undefined;
    for (0..max_overrides + 1) |index| {
        const rendered = try std.fmt.bufPrint(&title, "Override {d}", .{index});
        _ = try store.putOverride(.{
            .title = rendered,
            .source = "Official fixture",
            .original_deadline = "2026-05-15",
            .adjusted_deadline = "2026-05-22",
            .affected_form_codes = &.{"1701Q"},
        });
    }

    var state = State{};
    try state.attach(
        allocator,
        &store,
        "/tmp/ebirforms-tax-calendar.ics",
        "20260729T010203Z",
        2026,
        5,
    );
    try std.testing.expect(state.override_records_truncated);
    try std.testing.expectEqual(max_overrides, state.override_count);
    try std.testing.expectEqual(NoticeKind.failure, state.notice_kind);
    try std.testing.expectError(
        error.IncompleteProjection,
        state.buildProfileIcs(
            allocator,
            "20260729T010203Z",
            .{
                .key = "profile-overflow",
                .name = "Overflow Profile",
                .form_scope = .catalog_fallback,
            },
        ),
    );
}
