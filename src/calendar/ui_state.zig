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
        return switch (self.period) {
            .monthly => |period| std.fmt.bufPrint(
                output,
                "{d}:{s}:m{d:0>2}",
                .{ period.taxable_year, self.form_code, period.month },
            ),
            .quarterly => |period| std.fmt.bufPrint(
                output,
                "{d}:{s}:q{d}",
                .{ period.taxable_year, self.form_code, period.quarter },
            ),
            .annual => |period| std.fmt.bufPrint(
                output,
                "{d}:{s}:annual",
                .{ period.taxable_year, self.form_code },
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
    expires_on: ?domain.Date = null,
    form_codes: [max_forms_per_override]ShortText = undefined,
    form_count: usize = 0,
    regions: [max_scopes_per_record]ShortText = undefined,
    region_count: usize = 0,
    taxpayer_types: [max_scopes_per_record]ShortText = undefined,
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
            "All regions"
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
        if (self.effective_from == null and self.expires_on == null) return "No effective-date limit";
        var from_buffer: [10]u8 = undefined;
        var until_buffer: [10]u8 = undefined;
        const from = if (self.effective_from) |date|
            date.writeIso(&from_buffer)
        else
            "open";
        const until = if (self.expires_on) |date|
            date.writeIso(&until_buffer)
        else
            "open";
        return std.fmt.allocPrint(arena, "Effective {s} to {s}", .{ from, until }) catch "";
    }
};

pub const NonWorkingDayRow = struct {
    id: i64,
    date: domain.Date,
    name: MediumText = .{},
    kind: ShortText = .{},
    source: LongText = .{},
    regions: [max_scopes_per_record]ShortText = undefined,
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
        if (self.region_count == 0) return "Nationwide";
        return joinFixedTexts(arena, self.regions[0..self.region_count], ", ");
    }
};

pub const NoticeKind = enum {
    neutral,
    success,
    failure,
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
    non_working_days: [max_non_working_days]NonWorkingDayRow = undefined,
    non_working_day_count: usize = 0,

    editing_override_id: ?i64 = null,
    editing_non_working_day_id: ?i64 = null,
    override_title: canvas.TextBuffer(96) = .{},
    override_forms: canvas.TextBuffer(256) = .{},
    override_original: canvas.TextBuffer(10) = .{},
    override_adjusted: canvas.TextBuffer(10) = .{},
    override_source: canvas.TextBuffer(256) = .{},
    override_regions: canvas.TextBuffer(192) = .{},
    override_taxpayer_types: canvas.TextBuffer(192) = .{},
    override_effective_from: canvas.TextBuffer(10) = .{},
    override_expires_on: canvas.TextBuffer(10) = .{},

    non_working_date: canvas.TextBuffer(10) = .{},
    non_working_name: canvas.TextBuffer(96) = .{},
    non_working_kind: canvas.TextBuffer(32) = .{},
    non_working_source: canvas.TextBuffer(256) = .{},
    non_working_regions: canvas.TextBuffer(192) = .{},

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
        self.setNotice(.success, "Calendar rules and SQLite overrides loaded.");
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
        if (overrides.items.len > max_overrides) return error.TooManyOverrides;
        self.override_count = 0;
        for (overrides.items) |item| {
            try self.copyOverride(item);
        }

        var days = try store.listNonWorkingDays(allocator);
        defer days.deinit(allocator);
        if (days.items.len > max_non_working_days) {
            return error.TooManyNonWorkingDays;
        }
        self.non_working_day_count = 0;
        for (days.items) |item| {
            try self.copyNonWorkingDay(item);
        }

        try self.recompute();
    }

    pub fn recompute(self: *State) !void {
        const allocator = self.allocator orelse return error.NotAttached;

        var override_form_slices: [max_overrides][max_forms_per_override][]const u8 = undefined;
        var override_region_slices: [max_overrides][max_scopes_per_record][]const u8 = undefined;
        var override_taxpayer_slices: [max_overrides][max_scopes_per_record][]const u8 = undefined;
        var domain_overrides: [max_overrides]domain.DeadlineOverride = undefined;

        for (self.overrides[0..self.override_count], 0..) |*row, index| {
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
            domain_overrides[index] = .{
                .id = row.title.text(),
                .title = row.title.text(),
                .source_reference = row.source.text(),
                .affected_form_codes = override_form_slices[index][0..row.form_count],
                .original_deadline = row.original_deadline,
                .adjusted_deadline = row.adjusted_deadline,
                .affected_regions = override_region_slices[index][0..row.region_count],
                .affected_taxpayer_types = override_taxpayer_slices[index][0..row.taxpayer_type_count],
                .effective_from = row.effective_from,
                .expires_at = row.expires_on,
            };
        }

        var day_region_slices: [max_non_working_days][max_scopes_per_record][]const u8 = undefined;
        var domain_days: [max_non_working_days]domain.NonWorkingDay = undefined;
        var domain_day_count: usize = 0;
        for (self.non_working_days[0..self.non_working_day_count]) |*row| {
            // The global explorer has no region context. Only nationwide
            // closures can adjust its single authoritative projection.
            if (row.region_count != 0) continue;
            const index = domain_day_count;
            for (row.regions[0..row.region_count], 0..) |*region, scope_index| {
                day_region_slices[index][scope_index] = region.text();
            }
            domain_days[index] = .{
                .date = row.date,
                .name = row.name.text(),
                .kind = try parseNonWorkingKind(row.kind.text()),
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
                .overrides = domain_overrides[0..self.override_count],
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
        self.setNotice(.success, "Calendar year updated.");
    }

    pub fn nextYear(self: *State) void {
        if (self.selected_year >= 9997) return;
        self.selected_year += 1;
        self.recompute() catch |err| {
            self.selected_year -= 1;
            return self.setError(err);
        };
        self.setNotice(.success, "Calendar year updated.");
    }

    pub fn previousMonth(self: *State) void {
        if (self.selected_month > 1) {
            self.selected_month -= 1;
            self.setNotice(.success, "Calendar month updated.");
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
        self.setNotice(.success, "Calendar month updated.");
    }

    pub fn nextMonth(self: *State) void {
        if (self.selected_month < 12) {
            self.selected_month += 1;
            self.setNotice(.success, "Calendar month updated.");
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
        self.setNotice(.success, "Calendar month updated.");
    }

    pub fn refresh(self: *State) void {
        self.reload() catch |err| return self.setError(err);
        self.setNotice(.success, "Rules, overrides, and non-working days refreshed from SQLite.");
    }

    pub fn saveOverride(self: *State) void {
        const store = self.store orelse return self.setError(error.NotAttached);

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

        const effective_from = optionalTrimmed(
            self.override_effective_from.text(),
        );
        const expires_on = optionalTrimmed(self.override_expires_on.text());

        _ = store.putOverride(.{
            .id = self.editing_override_id,
            .title = trimmed(self.override_title.text()),
            .source = trimmed(self.override_source.text()),
            .original_deadline = trimmed(self.override_original.text()),
            .adjusted_deadline = trimmed(self.override_adjusted.text()),
            .effective_from = effective_from,
            .expires_on = expires_on,
            .affected_form_codes = forms[0..form_count],
            .regions = regions[0..region_count],
            .taxpayer_types = taxpayer_types[0..taxpayer_type_count],
        }) catch |err| return self.setError(err);

        const was_editing = self.editing_override_id != null;
        self.clearOverrideEditor();
        self.reload() catch |err| return self.setError(err);
        self.setNotice(
            .success,
            if (was_editing) "Deadline override updated." else "Deadline override saved.",
        );
    }

    pub fn editOverride(self: *State, id: i64) void {
        const row = self.findOverride(id) orelse
            return self.setError(error.InvalidFormCode);
        self.editing_override_id = id;
        self.override_title.set(row.title.text());
        self.override_source.set(row.source.text());
        setDateBuffer(&self.override_original, row.original_deadline);
        setDateBuffer(&self.override_adjusted, row.adjusted_deadline);
        setOptionalDateBuffer(&self.override_effective_from, row.effective_from);
        setOptionalDateBuffer(&self.override_expires_on, row.expires_on);
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
        self.setNotice(.neutral, "Editing deadline override.");
    }

    pub fn deleteOverride(self: *State, id: i64) void {
        const store = self.store orelse return self.setError(error.NotAttached);
        const deleted = store.deleteOverride(id) catch |err| return self.setError(err);
        if (!deleted) return self.setError(error.InvalidFormCode);
        if (self.editing_override_id == id) self.clearOverrideEditor();
        self.reload() catch |err| return self.setError(err);
        self.setNotice(.success, "Deadline override deleted.");
    }

    pub fn clearOverrideEditor(self: *State) void {
        self.editing_override_id = null;
        self.override_title.clear();
        self.override_forms.clear();
        self.override_original.clear();
        self.override_adjusted.clear();
        self.override_source.clear();
        self.override_regions.clear();
        self.override_taxpayer_types.clear();
        self.override_effective_from.clear();
        self.override_expires_on.clear();
    }

    pub fn saveNonWorkingDay(self: *State) void {
        const store = self.store orelse return self.setError(error.NotAttached);
        _ = parseNonWorkingKind(trimmed(self.non_working_kind.text())) catch |err|
            return self.setError(err);
        var regions: [max_scopes_per_record][]const u8 = undefined;
        const region_count = parseList(
            self.non_working_regions.text(),
            &regions,
        ) catch |err| return self.setError(err);

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
        self.setNotice(
            .success,
            if (was_editing) "Non-working day updated." else "Non-working day saved.",
        );
    }

    pub fn editNonWorkingDay(self: *State, id: i64) void {
        const row = self.findNonWorkingDay(id) orelse
            return self.setError(error.InvalidKind);
        self.editing_non_working_day_id = id;
        setDateBuffer(&self.non_working_date, row.date);
        self.non_working_name.set(row.name.text());
        self.non_working_kind.set(row.kind.text());
        self.non_working_source.set(row.source.text());
        setJoinedBuffer(
            &self.non_working_regions,
            row.regions[0..row.region_count],
        );
        self.setNotice(.neutral, "Editing non-working day.");
    }

    pub fn deleteNonWorkingDay(self: *State, id: i64) void {
        const store = self.store orelse return self.setError(error.NotAttached);
        const deleted = store.deleteNonWorkingDay(id) catch |err|
            return self.setError(err);
        if (!deleted) return self.setError(error.InvalidKind);
        if (self.editing_non_working_day_id == id) {
            self.clearNonWorkingDayEditor();
        }
        self.reload() catch |err| return self.setError(err);
        self.setNotice(.success, "Non-working day deleted.");
    }

    pub fn clearNonWorkingDayEditor(self: *State) void {
        self.editing_non_working_day_id = null;
        self.non_working_date.clear();
        self.non_working_name.clear();
        self.non_working_kind.clear();
        self.non_working_source.clear();
        self.non_working_regions.clear();
    }

    pub fn buildIcs(
        self: *const State,
        allocator: std.mem.Allocator,
        dtstamp_utc: []const u8,
    ) ![]u8 {
        var events: [max_deadlines]ics.Event = undefined;
        var keys: [max_deadlines][80]u8 = undefined;
        var periods: [max_deadlines][64]u8 = undefined;
        var summaries: [max_deadlines][192]u8 = undefined;
        var descriptions: [max_deadlines][512]u8 = undefined;

        for (self.deadlines[0..self.deadline_count], 0..) |*row, index| {
            const key = try row.obligationKey(&keys[index]);
            const period = formatPeriodInto(&periods[index], row.period);
            const summary = try std.fmt.bufPrint(
                &summaries[index],
                "[BIR] {s} — {s}",
                .{ row.display_form_no, period },
            );
            var original: [10]u8 = undefined;
            var final: [10]u8 = undefined;
            const description = try std.fmt.bufPrint(
                &descriptions[index],
                "{s}\nTaxable period: {s}\nStatutory deadline: {s}\nFinal deadline: {s}\nStatus: {s}{s}{s}",
                .{
                    row.form_name,
                    period,
                    row.original_deadline.writeIso(&original),
                    row.final_deadline.writeIso(&final),
                    row.status.label(),
                    if (row.source.len == 0) "" else "\nSource: ",
                    row.source.text(),
                },
            );
            events[index] = .{
                .obligation_key = key,
                .date = .{
                    .year = row.final_deadline.year,
                    .month = row.final_deadline.month,
                    .day = row.final_deadline.day,
                },
                .summary = summary,
                .description = description,
                .sequence = if (row.status == .extended) 1 else 0,
            };
        }

        return ics.generate(
            allocator,
            events[0..self.deadline_count],
            .{ .dtstamp_utc = dtstamp_utc },
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
            .expires_on = if (item.expires_on) |date|
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
    var iterator = std.mem.tokenizeAny(u8, value, ",; \t\r\n");
    var count: usize = 0;
    while (iterator.next()) |entry| {
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
    values: []const ShortText,
    separator: []const u8,
) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (values, 0..) |*value, index| {
        if (index != 0) out.appendSlice(arena, separator) catch return "";
        out.appendSlice(arena, value.text()) catch return "";
    }
    return out.items;
}

fn setJoinedBuffer(buffer: anytype, values: []const ShortText) void {
    var scratch: [512]u8 = undefined;
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
    buffer.set(scratch[0..length]);
}

fn setDateBuffer(buffer: anytype, date: domain.Date) void {
    var value: [10]u8 = undefined;
    buffer.set(date.writeIso(&value));
}

fn setOptionalDateBuffer(buffer: anytype, date: ?domain.Date) void {
    if (date) |value| {
        setDateBuffer(buffer, value);
    } else {
        buffer.clear();
    }
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
    const bytes = try state.buildIcs(allocator, "20260729T010203Z");
    defer allocator.free(bytes);

    try std.testing.expectEqual(
        state.deadline_count,
        std.mem.count(u8, bytes, "BEGIN:VEVENT"),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        bytes,
        "UID:2026:1701Q:q1@ebirforms.local",
    ) != null);
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
