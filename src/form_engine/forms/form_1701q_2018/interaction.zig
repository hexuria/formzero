//! Pure Desktop interaction/mutation model for the frozen 1701Q form.
//!
//! The module models HTML radio activation, declaration/init disabled state,
//! and the grounded click/blur call chains. A multi-control mutation is
//! applied to a complete copy of `transaction.State`; failure wipes that copy
//! and leaves the caller's state and runtime flags unchanged. Success wipes
//! the displaced state before installing the replacement.
//!
//! Profile-produced semantic values remain immutable. The evidenced global
//! uppercase handler may normalize their form-owned rendered bytes while
//! retaining profile origin, provenance, and digest. The legacy estate/trust
//! branch attempted to clear spouse identity controls; this model permits that
//! branch only when the qualified profile has no spouse, in which case those
//! projected values are already empty. A populated spouse profile blocks
//! atomically.

const std = @import("std");
const calculations = @import("calculations.zig");
const control_contract = @import("control_contract.zig");
const event_contract = @import("event_contract.zig");
const occurrences = @import("occurrences.zig");
const transaction = @import("transaction.zig");
const validation = @import("validation.zig");
const sensitive_memory = @import("../../../security/sensitive_memory.zig");

pub const control_count = occurrences.control_seeds.len;

pub const Error =
    transaction.Error ||
    calculations.CalculationError ||
    error{
        ControlDisabled,
        InvalidCurrentYear,
        ImmutableSpouseProfileConflict,
        NotRadioControl,
        NoBlurBinding,
        UnsupportedClickBinding,
        UnsupportedBlurBinding,
        PreBlurMoneyGrammarUnqualified,
        PreBlurYearGrammarUnqualified,
    };

pub const Person = enum {
    filer,
    spouse,
};

pub const Context = struct {
    /// True only when the frozen profile projection bound a spouse instance.
    spouse_profile_present: bool,
};

pub const BlurContext = struct {
    current_year: i32,
    schedule_date: validation.ScheduleDateContext,
};

pub const MutationSummary = struct {
    fact: ?event_contract.HandlerFact,
    recalculated: bool,
};

pub const BlurMutation = enum {
    unchanged,
    uppercased,
    cleared,
    reset_to_zero,
    canonical_money,
};

pub const BlurSummary = struct {
    fact: event_contract.HandlerFact,
    mutation: BlurMutation,
    alert: ?[]const u8 = null,
    focus: bool = false,
    legacy_return_is_valid: ?bool = null,
    recalculated: bool = false,
};

const filer_types = [_][]const u8{
    "frm1701q:optType_1",
    "frm1701q:optType_2",
    "frm1701q:optType_3",
    "frm1701q:optType_4",
};
const filer_atcs = [_][]const u8{
    "frm1701q:optATC_1",
    "frm1701q:optATC_2",
    "frm1701q:optATC_3",
    "frm1701q:optATC_4",
    "frm1701q:optATC_5",
    "frm1701q:optATC_6",
};
const filer_rates = [_][]const u8{
    "frm1701q:optTaxRate_1",
    "frm1701q:optTaxRate_2",
};
const filer_methods = [_][]const u8{
    "frm1701q:optMethodOfDeduction:_1",
    "frm1701q:optMethodOfDeduction:_2",
};
const spouse_types = [_][]const u8{
    "frm1701q:optSpouseType_1",
    "frm1701q:optSpouseType_2",
    "frm1701q:optSpouseType_3",
};
const spouse_atcs = [_][]const u8{
    "frm1701q:optSpouseATC_1",
    "frm1701q:optSpouseATC_2",
    "frm1701q:optSpouseATC_3",
    "frm1701q:optSpouseATC_4",
    "frm1701q:optSpouseATC_5",
    "frm1701q:optSpouseATC_6",
    "frm1701q:optSpouseATC_7",
};
const spouse_rates = [_][]const u8{
    "frm1701q:optSpouseTaxRate_1",
    "frm1701q:optSpouseTaxRate_2",
};
const spouse_methods = [_][]const u8{
    "frm1701q:optSpouseMethod:_1",
    "frm1701q:optSpouseMethod:_2",
};

const schedule1_filer_inputs = [_][]const u8{
    "frm1701q:txt36A",
    "frm1701q:txt37A",
    "frm1701q:txt39A",
    "frm1701q:txt42A",
    "frm1701q:txt43A",
    "frm1701q:txt44A",
};
const schedule1_spouse_inputs = [_][]const u8{
    "frm1701q:txt36B",
    "frm1701q:txt37B",
    "frm1701q:txt39B",
    "frm1701q:txt42B",
    "frm1701q:txt43B",
    "frm1701q:txt44B",
};
const schedule2_filer_inputs = [_][]const u8{
    "frm1701q:txt47A",
    "frm1701q:txt48A",
    "frm1701q:txt50A",
    "frm1701q:txt52A",
};
const schedule2_spouse_inputs = [_][]const u8{
    "frm1701q:txt47B",
    "frm1701q:txt48B",
    "frm1701q:txt50B",
    "frm1701q:txt52B",
};
const payment_filer_inputs = [_][]const u8{
    "frm1701q:txt55A",
    "frm1701q:txt56A",
    "frm1701q:txt57A",
    "frm1701q:txt58A",
    "frm1701q:txt59A",
    "frm1701q:txt60A",
    "frm1701q:txt61A",
    "frm1701q:txt64A",
    "frm1701q:txt65A",
    "frm1701q:txt66A",
};
const payment_spouse_inputs = [_][]const u8{
    "frm1701q:txt55B",
    "frm1701q:txt56B",
    "frm1701q:txt57B",
    "frm1701q:txt58B",
    "frm1701q:txt59B",
    "frm1701q:txt60B",
    "frm1701q:txt61B",
    "frm1701q:txt64B",
    "frm1701q:txt65B",
    "frm1701q:txt66B",
};

const spouse_profile_controls = [_][]const u8{
    "frm1701q:txtSpouseTIN1",
    "frm1701q:txtSpouseTIN2",
    "frm1701q:txtSpouseTIN3",
    "frm1701q:txtSpouseBranchCode",
    "frm1701q:txtSpouseRDOCode",
    "frm1701q:txtSpouseName",
    "frm1701q:txtSpouseCitizenship",
    "frm1701q:txtSpouseForeignTaxNum",
};

pub const Runtime = struct {
    const Self = @This();

    disabled_flags: [control_count]bool,
    /// The markup initializes each independent spouse-type radio to
    /// `waschecked="true"`.
    spouse_was_checked: [3]bool = .{ true, true, true },

    pub fn fromMarkup() Self {
        var result: Self = undefined;
        for (control_contract.contracts, 0..) |contract, index| {
            result.disabled_flags[index] = contract.disabled_in_markup;
        }
        result.spouse_was_checked = .{ true, true, true };
        return result;
    }

    pub fn isDisabled(
        self: *const Self,
        control_id: []const u8,
    ) transaction.Error!bool {
        return self.disabled_flags[
            controlIndex(control_id) orelse
                return error.UnknownControl
        ];
    }

    /// Applies the eligible-control portion of source `init()`:
    /// current year/current page values, enabling the amended radios, and the
    /// initial `processAmend()` call. The caller passes a transaction state
    /// already seeded with markup radio/default values.
    pub fn applyInit(
        self: *Self,
        state: *transaction.State,
        current_year: i32,
        context: Context,
    ) Error!void {
        if (current_year < 0 or current_year > 9999) {
            return error.InvalidCurrentYear;
        }
        var next_state = state.*;
        defer next_state.deinit();
        var next_runtime = self.*;

        var year_buffer: [4]u8 = undefined;
        defer sensitive_memory.wipeValue([4]u8, &year_buffer);
        const year: u16 = @intCast(current_year);
        year_buffer[0] = @intCast('0' + (year / 1000) % 10);
        year_buffer[1] = @intCast('0' + (year / 100) % 10);
        year_buffer[2] = @intCast('0' + (year / 10) % 10);
        year_buffer[3] = @intCast('0' + year % 10);
        try setText(&next_state, "frm1701q:txtYear", &year_buffer);
        try setText(&next_state, "frm1701q:txtCurrentPage", "1");
        try next_runtime.setDisabled("frm1701q:AmendedRtn_1", false);
        try next_runtime.setDisabled("frm1701q:AmendedRtn_2", false);
        try next_runtime.processAmend(&next_state, context);

        state.deinit();
        state.* = next_state;
        self.* = next_runtime;
    }

    /// Models browser radio activation followed by the exact inline click
    /// pipeline. Controls without an inline `onclick` still receive native
    /// radio-group activation.
    pub fn click(
        self: *Self,
        state: *transaction.State,
        control_id: []const u8,
        context: Context,
    ) Error!MutationSummary {
        if (try self.isDisabled(control_id)) return error.ControlDisabled;
        const declaration = control_contract.find(control_id) orelse
            return error.UnknownControl;
        if (declaration.kind != .radio) return error.NotRadioControl;

        var next_state = state.*;
        defer next_state.deinit();
        var next_runtime = self.*;
        try nativeRadioActivate(&next_state, control_id);

        const binding = event_contract.find(control_id, .click);
        var recalculate = false;
        if (binding) |event| {
            switch (event.fact) {
                .empty_attribute => {},
                .click_process_amend => {
                    try next_runtime.processAmend(&next_state, context);
                },
                .click_process_tax_type_filer => {
                    try next_runtime.processTaxType(
                        &next_state,
                        .filer,
                        context,
                    );
                    recalculate = true;
                },
                .click_spouse_type_1_clear_then_process,
                .click_spouse_type_2_clear_then_process,
                .click_spouse_type_3_clear_then_process,
                => {
                    try next_runtime.clearCheck(&next_state, control_id);
                    try next_runtime.processTaxType(
                        &next_state,
                        .spouse,
                        context,
                    );
                    recalculate = true;
                },
                .click_process_atc_filer => {
                    try next_runtime.processAtc(&next_state, .filer);
                    recalculate = true;
                },
                .click_process_atc_spouse => {
                    try next_runtime.processAtc(&next_state, .spouse);
                    recalculate = true;
                },
                .click_enable_schedule1_then_itemized_filer => {
                    try next_runtime.enableSchedule1(&next_state, .filer);
                    try next_runtime.itemized(&next_state, .filer);
                    recalculate = true;
                },
                .click_enable_schedule1_then_itemized_spouse => {
                    try next_runtime.enableSchedule1(&next_state, .spouse);
                    try next_runtime.itemized(&next_state, .spouse);
                    recalculate = true;
                },
                .click_enable_schedule2_filer => {
                    try next_runtime.enableSchedule2(&next_state, .filer);
                    recalculate = true;
                },
                .click_enable_schedule2_spouse => {
                    try next_runtime.enableSchedule2(&next_state, .spouse);
                    recalculate = true;
                },
                .click_itemized_filer => {
                    try next_runtime.itemized(&next_state, .filer);
                    recalculate = true;
                },
                .click_itemized_spouse => {
                    try next_runtime.itemized(&next_state, .spouse);
                    recalculate = true;
                },
                .click_optional_filer => {
                    try next_runtime.optional(&next_state, .filer);
                    recalculate = true;
                },
                .click_optional_spouse => {
                    try next_runtime.optional(&next_state, .spouse);
                    recalculate = true;
                },
                else => return error.UnsupportedClickBinding,
            }
        }
        if (recalculate) try recalculateState(&next_state);

        state.deinit();
        state.* = next_state;
        self.* = next_runtime;
        return .{
            .fact = if (binding) |event| event.fact else null,
            .recalculated = recalculate,
        };
    }

    /// Applies qualified blur behavior. Arbitrary legacy numeric lexemes are
    /// not guessed: money must already be in canonical transaction grammar,
    /// and year text must already be four decimal digits.
    pub fn blur(
        self: *Self,
        state: *transaction.State,
        control_id: []const u8,
        context: BlurContext,
    ) Error!BlurSummary {
        _ = self;
        const binding = event_contract.find(control_id, .blur) orelse
            return error.NoBlurBinding;
        var next_state = state.*;
        defer next_state.deinit();
        var summary: BlurSummary = .{
            .fact = binding.fact,
            .mutation = .unchanged,
        };

        switch (binding.fact) {
            .empty_attribute => {},
            .blur_global_uppercase => {
                const changed = try uppercaseAllText(&next_state);
                if (changed) summary.mutation = .uppercased;
            },
            .blur_year_normalize_compute46_validate_compute46 => {
                const raw = try getText(&next_state, control_id);
                if (!isCanonicalYear(raw)) {
                    return error.PreBlurYearGrammarUnqualified;
                }
                switch (validation.validateYearOnBlur(
                    raw,
                    context.current_year,
                )) {
                    .unchanged => {
                        try recalculateState(&next_state);
                        summary.recalculated = true;
                    },
                    .rejected => |rejected| {
                        if (rejected.clear_value) {
                            try setText(&next_state, control_id, "");
                            summary.mutation = .cleared;
                        }
                        summary.alert = rejected.alert;
                        summary.focus = rejected.focus;
                    },
                }
            },
            .blur_validate_date => {
                const raw = try getText(&next_state, control_id);
                const result = validation.validateScheduleDateOnBlur(
                    raw,
                    context.schedule_date,
                );
                if (result.clear_value) {
                    try setText(&next_state, control_id, "");
                    summary.mutation = .cleared;
                }
                summary.alert = result.alert;
                summary.focus = result.focus;
                summary.legacy_return_is_valid =
                    result.legacy_return_is_valid;
            },
            .blur_round,
            .blur_round_compute38_filer,
            .blur_round_compute38_compute40_filer,
            .blur_round_compute38_spouse,
            .blur_round_compute38_compute40_spouse,
            .blur_round_compute41_filer,
            .blur_round_compute41_spouse,
            .blur_round_compute45_filer,
            .blur_round_compute45_spouse,
            .blur_round_compute49_filer,
            .blur_round_compute49_spouse,
            .blur_round_compute51_filer,
            .blur_round_compute51_spouse,
            .blur_round_compute62_filer,
            .blur_round_compute62_spouse,
            .blur_round_compute67_filer,
            .blur_round_compute67_spouse,
            .blur_round_validate_item52_compute53_filer,
            .blur_round_validate_item52_compute53_spouse,
            => {
                const raw = try getText(&next_state, control_id);
                const parsed = transaction.parseMoney(raw) catch
                    return error.PreBlurMoneyGrammarUnqualified;
                summary.mutation = .canonical_money;

                if (binding.fact ==
                    .blur_round_validate_item52_compute53_filer or
                    binding.fact ==
                        .blur_round_validate_item52_compute53_spouse)
                {
                    const item52 =
                        validation.validateItem52OnBlur(parsed.centavos);
                    if (item52.value_centavos != parsed.centavos) {
                        try setText(&next_state, control_id, "0.00");
                        summary.mutation = .reset_to_zero;
                    }
                    summary.alert = item52.alert;
                }

                if (binding.fact != .blur_round) {
                    try recalculateState(&next_state);
                    summary.recalculated = true;
                }
            },
            else => return error.UnsupportedBlurBinding,
        }

        state.deinit();
        state.* = next_state;
        return summary;
    }

    fn setDisabled(
        self: *Self,
        control_id: []const u8,
        disabled: bool,
    ) transaction.Error!void {
        self.disabled_flags[
            controlIndex(control_id) orelse
                return error.UnknownControl
        ] = disabled;
    }

    fn clearCheck(
        self: *Self,
        state: *transaction.State,
        control_id: []const u8,
    ) Error!void {
        const index = spouseTypeIndex(control_id) orelse
            return error.UnknownControl;
        if (self.spouse_was_checked[index]) {
            try setChecked(state, control_id, false);
            self.spouse_was_checked[index] = false;
        } else {
            self.spouse_was_checked[index] = true;
        }
    }

    fn processAmend(
        self: *Self,
        state: *const transaction.State,
        context: Context,
    ) Error!void {
        if (try getChecked(state, "frm1701q:AmendedRtn_1")) {
            try self.setDisabled("frm1701q:txt59A", false);
            try self.setDisabled(
                "frm1701q:txt59B",
                !context.spouse_profile_present,
            );
        } else {
            try self.setDisabled("frm1701q:txt59A", true);
            try self.setDisabled("frm1701q:txt59B", true);
        }
    }

    fn processTaxType(
        self: *Self,
        state: *transaction.State,
        person: Person,
        context: Context,
    ) Error!void {
        switch (person) {
            .filer => {
                try setAllChecked(state, &filer_atcs, false);
                try setAllChecked(state, &filer_rates, false);
                try setAllChecked(state, &filer_methods, false);
                try self.setAllDisabled(&filer_methods, false);
                try self.setDisabled("frm1701q:txt37A", true);
                try self.setDisabled("frm1701q:txt39A", true);
                try setText(state, "frm1701q:txt37A", "0.00");
                try setText(state, "frm1701q:txt39A", "0.00");

                const individual =
                    try getChecked(state, filer_types[0]) or
                    try getChecked(state, filer_types[1]);
                const estate_or_trust =
                    try getChecked(state, filer_types[2]) or
                    try getChecked(state, filer_types[3]);
                if (individual) {
                    try self.setAllDisabled(filer_atcs[1..], false);
                    try self.setDisabled(filer_rates[1], false);
                    try self.disableSchedule1(state, .filer);
                    try self.disableSchedule2(state, .filer);
                    try self.enableSpouse();
                } else if (estate_or_trust) {
                    if (context.spouse_profile_present) {
                        return error.ImmutableSpouseProfileConflict;
                    }
                    try setChecked(state, filer_atcs[0], true);
                    try self.setAllDisabled(filer_atcs[1..], true);
                    try self.setDisabled(filer_rates[0], false);
                    try setChecked(state, filer_rates[0], true);
                    try self.setDisabled(filer_rates[1], true);
                    try self.enableSchedule1(state, .filer);
                    try self.disableSpouse(state);
                }
            },
            .spouse => {
                try setAllChecked(state, &spouse_atcs, false);
                try self.setAllDisabled(&spouse_atcs, false);
                try setAllChecked(state, &spouse_rates, false);
                try setAllChecked(state, &spouse_methods, false);
                try self.setAllDisabled(&spouse_rates, false);
                try self.setAllDisabled(&spouse_methods, false);
                try self.setDisabled("frm1701q:txt37B", true);
                try self.setDisabled("frm1701q:txt39B", true);
                try setText(state, "frm1701q:txt37B", "0.00");
                try setText(state, "frm1701q:txt39B", "0.00");
                try self.disableSchedule1(state, .spouse);
                try self.disableSchedule2(state, .spouse);
                try self.enableSpousePayments(state, context);

                if (try getChecked(state, spouse_types[2])) {
                    try setChecked(state, spouse_atcs[3], true);
                    for (spouse_atcs, 0..) |id, index| {
                        if (index != 3) try self.setDisabled(id, true);
                    }
                    try setAllChecked(state, &spouse_rates, false);
                    try setAllChecked(state, &spouse_methods, false);
                    try self.setAllDisabled(&spouse_rates, true);
                    try self.setAllDisabled(&spouse_methods, true);
                    try self.clearAndDisablePayments(state, .spouse);
                }

                var selected_type_count: usize = 0;
                for (spouse_types) |id| {
                    if (try getChecked(state, id)) {
                        selected_type_count += 1;
                    }
                }
                if (selected_type_count > 1) {
                    try self.setDisabled(spouse_atcs[2], false);
                    try self.setDisabled(spouse_atcs[6], false);
                    try self.setAllDisabled(&spouse_rates, false);
                }
            },
        }
    }

    fn processAtc(
        self: *Self,
        state: *transaction.State,
        person: Person,
    ) Error!void {
        switch (person) {
            .filer => {
                if (try anyChecked(state, filer_atcs[0..3])) {
                    try self.setDisabled(filer_rates[0], false);
                    try setChecked(state, filer_rates[0], true);
                    try self.setDisabled(filer_rates[1], true);
                    try self.setAllDisabled(&filer_methods, false);
                    try self.enableSchedule1(state, .filer);
                } else {
                    try self.setDisabled(filer_rates[1], false);
                    try setChecked(state, filer_rates[1], true);
                    try self.setDisabled(filer_rates[0], true);
                    try setAllChecked(state, &filer_methods, false);
                    try self.setAllDisabled(&filer_methods, true);
                    try self.enableSchedule2(state, .filer);
                }
            },
            .spouse => {
                if (try anyChecked(state, spouse_atcs[0..3])) {
                    try self.setDisabled(spouse_rates[0], false);
                    try setChecked(state, spouse_rates[0], true);
                    try self.setDisabled(spouse_rates[1], true);
                    try self.setAllDisabled(&spouse_methods, false);
                    try self.enableSchedule1(state, .spouse);
                    try self.enableSpousePayments(
                        state,
                        .{ .spouse_profile_present = true },
                    );
                } else if (try anyChecked(state, spouse_atcs[4..7])) {
                    try self.setDisabled(spouse_rates[1], false);
                    try setChecked(state, spouse_rates[1], true);
                    try self.setDisabled(spouse_rates[0], true);
                    try setAllChecked(state, &spouse_methods, false);
                    try self.setAllDisabled(&spouse_methods, true);
                    try self.enableSchedule2(state, .spouse);
                    try self.enableSpousePayments(
                        state,
                        .{ .spouse_profile_present = true },
                    );
                } else {
                    try setAllChecked(state, &spouse_rates, false);
                    try self.setAllDisabled(&spouse_rates, true);
                    try self.setAllDisabled(&spouse_methods, true);
                    try self.disableSchedule1(state, .spouse);
                    try self.disableSchedule2(state, .spouse);
                    try self.clearAndDisablePayments(state, .spouse);
                }
            },
        }
    }

    fn enableSchedule1(
        self: *Self,
        state: *transaction.State,
        person: Person,
    ) Error!void {
        try self.setDisabled("frm1701q:txt43Desc", false);
        const methods = methodsFor(person);
        try setAllChecked(state, methods, false);
        try self.setAllDisabled(methods, false);

        const inputs = schedule1Inputs(person);
        try self.setAllDisabled(inputs, false);
        // The spouse branch contains a grounded cross-person typo: it checks
        // the filer's itemized radio, not the spouse's. Both spouse methods
        // were just cleared, so the filer election alone decides whether
        // spouse Items 37/39 remain enabled.
        const itemized_gate = try getChecked(state, filer_methods[0]);
        if (!itemized_gate) {
            try self.setDisabled(input37(person), true);
            try self.setDisabled(input39(person), true);
        }
        try self.disableSchedule2(state, person);
    }

    fn disableSchedule1(
        self: *Self,
        state: *transaction.State,
        person: Person,
    ) Error!void {
        const inputs = schedule1Inputs(person);
        for (inputs) |id| {
            try self.setDisabled(id, true);
            try setText(state, id, "0.00");
        }
        try self.setDisabled("frm1701q:txt43Desc", true);
        try setText(state, "frm1701q:txt43Desc", "");
    }

    fn enableSchedule2(
        self: *Self,
        state: *transaction.State,
        person: Person,
    ) Error!void {
        try self.setDisabled("frm1701q:txt48Desc", false);
        const methods = methodsFor(person);
        try setAllChecked(state, methods, false);
        try self.setAllDisabled(methods, true);
        try self.setAllDisabled(schedule2Inputs(person), false);

        switch (person) {
            .filer => {
                if (try getChecked(state, filer_atcs[5])) {
                    try setText(state, "frm1701q:txt52A", "0.00");
                    try self.setDisabled("frm1701q:txt52A", true);
                }
            },
            .spouse => {
                if (try getChecked(state, spouse_atcs[6]) and
                    !try getChecked(state, spouse_types[2]))
                {
                    try setText(state, "frm1701q:txt52B", "0.00");
                    try self.setDisabled("frm1701q:txt52B", true);
                }
            },
        }
        try self.disableSchedule1(state, person);
    }

    fn disableSchedule2(
        self: *Self,
        state: *transaction.State,
        person: Person,
    ) Error!void {
        const inputs = schedule2Inputs(person);
        for (inputs) |id| {
            try self.setDisabled(id, true);
            try setText(state, id, "0.00");
        }
        try self.setDisabled("frm1701q:txt48Desc", true);
        try setText(state, "frm1701q:txt48Desc", "");
    }

    fn itemized(
        self: *Self,
        state: *transaction.State,
        person: Person,
    ) Error!void {
        if (try getChecked(state, methodsFor(person)[0]) and
            try getChecked(state, ratesFor(person)[0]))
        {
            try self.setDisabled(input37(person), false);
            try self.setDisabled(input39(person), false);
        }
    }

    fn optional(
        self: *Self,
        state: *transaction.State,
        person: Person,
    ) Error!void {
        if (!try getChecked(state, methodsFor(person)[1])) return;
        try self.setDisabled(input37(person), true);
        try self.setDisabled(input39(person), true);
        try setText(state, input37(person), "0.00");
        try setText(state, input39(person), "0.00");
    }

    fn enableSpouse(self: *Self) Error!void {
        for (spouse_profile_controls) |id| {
            // Preserve the source typo: enableSpouse toggles the filer foreign
            // tax number, not txtSpouseForeignTaxNum.
            if (std.mem.eql(u8, id, "frm1701q:txtSpouseForeignTaxNum")) {
                continue;
            }
            try self.setDisabled(id, false);
        }
        try self.setDisabled("frm1701q:txtForeignTaxNumber", false);
        try self.setDisabled(
            "frm1701q:optSpouseForeignTaxCred_1",
            false,
        );
        try self.setDisabled(
            "frm1701q:optSpouseForeignTaxCred_2",
            false,
        );
        try self.setAllDisabled(&spouse_types, false);
        try self.setAllDisabled(&spouse_atcs, false);
        try self.setAllDisabled(&spouse_rates, false);
        try self.setAllDisabled(&spouse_methods, false);
    }

    fn disableSpouse(
        self: *Self,
        state: *transaction.State,
    ) Error!void {
        try self.setAllDisabled(&spouse_profile_controls, true);
        try self.setDisabled(
            "frm1701q:optSpouseForeignTaxCred_1",
            true,
        );
        try self.setDisabled(
            "frm1701q:optSpouseForeignTaxCred_2",
            true,
        );
        try setChecked(
            state,
            "frm1701q:optSpouseForeignTaxCred_1",
            false,
        );
        try setChecked(
            state,
            "frm1701q:optSpouseForeignTaxCred_2",
            false,
        );
        try setAllChecked(state, &spouse_types, false);
        try self.setAllDisabled(&spouse_types, true);
        try setAllChecked(state, &spouse_atcs, false);
        try self.setAllDisabled(&spouse_atcs, true);
        try setAllChecked(state, &spouse_rates, false);
        try self.setAllDisabled(&spouse_rates, true);
        try setAllChecked(state, &spouse_methods, false);
        try self.setAllDisabled(&spouse_methods, true);
    }

    fn enableSpousePayments(
        self: *Self,
        state: *const transaction.State,
        context: Context,
    ) Error!void {
        _ = context;
        for (payment_spouse_inputs) |id| {
            if (std.mem.eql(u8, id, "frm1701q:txt59B")) {
                try self.setDisabled(
                    id,
                    !try getChecked(
                        state,
                        "frm1701q:AmendedRtn_1",
                    ),
                );
            } else {
                try self.setDisabled(id, false);
            }
        }
    }

    fn clearAndDisablePayments(
        self: *Self,
        state: *transaction.State,
        person: Person,
    ) Error!void {
        const inputs: []const []const u8 = switch (person) {
            .filer => &payment_filer_inputs,
            .spouse => &payment_spouse_inputs,
        };
        for (inputs) |id| {
            try setText(state, id, "0.00");
            try self.setDisabled(id, true);
        }
    }

    fn setAllDisabled(
        self: *Self,
        control_ids: []const []const u8,
        disabled: bool,
    ) Error!void {
        for (control_ids) |id| try self.setDisabled(id, disabled);
    }
};

fn controlIndex(control_id: []const u8) ?usize {
    for (occurrences.control_seeds, 0..) |seed, index| {
        if (std.mem.eql(u8, seed.id, control_id)) return index;
    }
    return null;
}

fn spouseTypeIndex(control_id: []const u8) ?usize {
    for (spouse_types, 0..) |id, index| {
        if (std.mem.eql(u8, id, control_id)) return index;
    }
    return null;
}

fn setText(
    state: *transaction.State,
    control_id: []const u8,
    raw: []const u8,
) transaction.Error!void {
    const origin = try state.originFor(control_id);
    try state.setText(origin, control_id, raw);
}

fn getText(
    state: *const transaction.State,
    control_id: []const u8,
) transaction.Error![]const u8 {
    const origin = try state.originFor(control_id);
    return state.text(origin, control_id);
}

fn setChecked(
    state: *transaction.State,
    control_id: []const u8,
    value: bool,
) transaction.Error!void {
    const origin = try state.originFor(control_id);
    try state.setChecked(origin, control_id, value);
}

fn getChecked(
    state: *const transaction.State,
    control_id: []const u8,
) transaction.Error!bool {
    const origin = try state.originFor(control_id);
    return state.checked(origin, control_id);
}

fn setAllChecked(
    state: *transaction.State,
    control_ids: []const []const u8,
    value: bool,
) transaction.Error!void {
    for (control_ids) |id| try setChecked(state, id, value);
}

fn anyChecked(
    state: *const transaction.State,
    control_ids: []const []const u8,
) transaction.Error!bool {
    for (control_ids) |id| {
        if (try getChecked(state, id)) return true;
    }
    return false;
}

fn nativeRadioActivate(
    state: *transaction.State,
    control_id: []const u8,
) transaction.Error!void {
    const declaration = control_contract.find(control_id) orelse
        return error.UnknownControl;
    const radio = declaration.radio_declaration orelse
        return error.KindMismatch;
    for (control_contract.contracts) |candidate| {
        const candidate_radio = candidate.radio_declaration orelse continue;
        if (std.mem.eql(u8, candidate_radio.name, radio.name)) {
            try setChecked(state, candidate.id, false);
        }
    }
    try setChecked(state, control_id, true);
}

fn schedule1Inputs(person: Person) []const []const u8 {
    return switch (person) {
        .filer => &schedule1_filer_inputs,
        .spouse => &schedule1_spouse_inputs,
    };
}

fn schedule2Inputs(person: Person) []const []const u8 {
    return switch (person) {
        .filer => &schedule2_filer_inputs,
        .spouse => &schedule2_spouse_inputs,
    };
}

fn methodsFor(person: Person) []const []const u8 {
    return switch (person) {
        .filer => &filer_methods,
        .spouse => &spouse_methods,
    };
}

fn ratesFor(person: Person) []const []const u8 {
    return switch (person) {
        .filer => &filer_rates,
        .spouse => &spouse_rates,
    };
}

fn input37(person: Person) []const u8 {
    return switch (person) {
        .filer => "frm1701q:txt37A",
        .spouse => "frm1701q:txt37B",
    };
}

fn input39(person: Person) []const u8 {
    return switch (person) {
        .filer => "frm1701q:txt39A",
        .spouse => "frm1701q:txt39B",
    };
}

fn recalculateState(state: *transaction.State) Error!void {
    var calculated = try state.recalculateAndApply();
    defer sensitive_memory.wipeValue(
        calculations.FormState,
        &calculated,
    );
}

fn isCanonicalYear(raw: []const u8) bool {
    if (raw.len != 4) return false;
    for (raw) |byte| {
        if (!std.ascii.isDigit(byte)) return false;
    }
    return true;
}

/// The later duplicate `capital()` declaration in string-util.js is the
/// effective handler: it uppercases every `type=text` control except txtEmail.
fn uppercaseAllText(state: *transaction.State) Error!bool {
    return state.applyLegacyCapital();
}

fn seedTestState() !transaction.State {
    var state = try transaction.State.init();
    errdefer state.deinit();

    for (control_contract.contracts) |contract| {
        const origin = try state.originFor(contract.id);
        switch (contract.kind) {
            .radio => {
                if (origin != .profile and origin != .derived) {
                    try state.setChecked(
                        origin,
                        contract.id,
                        contract.radio_declaration.?.checked,
                    );
                }
            },
            .text, .select_one => {
                if (origin == .profile or origin == .derived or
                    origin == .preparer)
                {
                    continue;
                }
                try state.setText(
                    origin,
                    contract.id,
                    contract.declared_value,
                );
            },
        }
    }
    try setChecked(&state, "frm1701q:DateQuarter_1", true);
    try setText(&state, "frm1701q:txtYear", "2026");
    try recalculateState(&state);
    return state;
}

fn initTest(
    spouse_present: bool,
) !struct { state: transaction.State, runtime: Runtime } {
    var state = try seedTestState();
    errdefer state.deinit();
    var runtime = Runtime.fromMarkup();
    try runtime.applyInit(
        &state,
        2026,
        .{ .spouse_profile_present = spouse_present },
    );
    return .{ .state = state, .runtime = runtime };
}

fn expectChecked(
    state: *const transaction.State,
    id: []const u8,
    expected: bool,
) !void {
    try std.testing.expectEqual(expected, try getChecked(state, id));
}

fn expectText(
    state: *const transaction.State,
    id: []const u8,
    expected: []const u8,
) !void {
    try std.testing.expectEqualStrings(expected, try getText(state, id));
}

test "markup and init disabled layers are exact for eligible controls" {
    var fixture = try initTest(false);
    defer fixture.state.deinit();

    var markup_disabled: usize = 0;
    var runtime_disabled: usize = 0;
    for (control_contract.contracts) |contract| {
        if (contract.disabled_in_markup) markup_disabled += 1;
        if (try fixture.runtime.isDisabled(contract.id)) {
            runtime_disabled += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 89), markup_disabled);
    // Two amended radios become enabled; txt59A/B become disabled by the
    // declared "No" amended selection.
    try std.testing.expectEqual(@as(usize, 89), runtime_disabled);
    try std.testing.expect(
        !try fixture.runtime.isDisabled("frm1701q:AmendedRtn_1"),
    );
    try std.testing.expect(
        try fixture.runtime.isDisabled("frm1701q:txt59A"),
    );
    try expectText(&fixture.state, "frm1701q:txtYear", "2026");
    try expectText(&fixture.state, "frm1701q:txtCurrentPage", "1");
}

test "processAmend covers amended and spouse-presence branches" {
    inline for (.{ false, true }) |spouse_present| {
        var fixture = try initTest(spouse_present);
        defer fixture.state.deinit();
        _ = try fixture.runtime.click(
            &fixture.state,
            "frm1701q:AmendedRtn_1",
            .{ .spouse_profile_present = spouse_present },
        );
        try std.testing.expect(
            !try fixture.runtime.isDisabled("frm1701q:txt59A"),
        );
        try std.testing.expectEqual(
            !spouse_present,
            try fixture.runtime.isDisabled("frm1701q:txt59B"),
        );
        _ = try fixture.runtime.click(
            &fixture.state,
            "frm1701q:AmendedRtn_2",
            .{ .spouse_profile_present = spouse_present },
        );
        try std.testing.expect(
            try fixture.runtime.isDisabled("frm1701q:txt59A"),
        );
        try std.testing.expect(
            try fixture.runtime.isDisabled("frm1701q:txt59B"),
        );
    }
}

test "all four filer types cover individual and estate-trust branches" {
    for (filer_types, 0..) |type_id, index| {
        var fixture = try initTest(false);
        defer fixture.state.deinit();
        const result = try fixture.runtime.click(
            &fixture.state,
            type_id,
            .{ .spouse_profile_present = false },
        );
        try std.testing.expect(result.recalculated);
        if (index < 2) {
            try expectChecked(&fixture.state, filer_atcs[0], false);
            try std.testing.expect(
                !try fixture.runtime.isDisabled(filer_rates[1]),
            );
            try std.testing.expect(
                !try fixture.runtime.isDisabled(spouse_types[0]),
            );
        } else {
            try expectChecked(&fixture.state, filer_atcs[0], true);
            try expectChecked(&fixture.state, filer_rates[0], true);
            try std.testing.expect(
                try fixture.runtime.isDisabled(spouse_types[0]),
            );
        }
    }
}

test "estate-trust spouse-profile conflict is atomic" {
    var fixture = try initTest(true);
    defer fixture.state.deinit();
    try setText(&fixture.state, "frm1701q:txt37A", "123.00");
    const before_flags = fixture.runtime.disabled_flags;
    try std.testing.expectError(
        error.ImmutableSpouseProfileConflict,
        fixture.runtime.click(
            &fixture.state,
            filer_types[2],
            .{ .spouse_profile_present = true },
        ),
    );
    try expectText(&fixture.state, "frm1701q:txt37A", "123.00");
    try expectChecked(&fixture.state, filer_types[2], false);
    try std.testing.expectEqualSlices(
        bool,
        &before_flags,
        &fixture.runtime.disabled_flags,
    );
}

test "spouse clearCheck waschecked quirk allows independent combinations" {
    var fixture = try initTest(true);
    defer fixture.state.deinit();

    // Browser checks it, then the initial waschecked=true clears it.
    _ = try fixture.runtime.click(
        &fixture.state,
        spouse_types[0],
        .{ .spouse_profile_present = true },
    );
    try expectChecked(&fixture.state, spouse_types[0], false);
    // Second click checks it and flips waschecked back to true.
    _ = try fixture.runtime.click(
        &fixture.state,
        spouse_types[0],
        .{ .spouse_profile_present = true },
    );
    try expectChecked(&fixture.state, spouse_types[0], true);

    _ = try fixture.runtime.click(
        &fixture.state,
        spouse_types[1],
        .{ .spouse_profile_present = true },
    );
    _ = try fixture.runtime.click(
        &fixture.state,
        spouse_types[1],
        .{ .spouse_profile_present = true },
    );
    try expectChecked(&fixture.state, spouse_types[0], true);
    try expectChecked(&fixture.state, spouse_types[1], true);
    try std.testing.expect(
        !try fixture.runtime.isDisabled(spouse_atcs[2]),
    );
    try std.testing.expect(
        !try fixture.runtime.isDisabled(spouse_atcs[6]),
    );
}

test "compensation spouse branch fixes ATC 4 and clears payments" {
    var fixture = try initTest(true);
    defer fixture.state.deinit();
    try setText(&fixture.state, payment_spouse_inputs[0], "500.00");
    _ = try fixture.runtime.click(
        &fixture.state,
        spouse_types[2],
        .{ .spouse_profile_present = true },
    );
    _ = try fixture.runtime.click(
        &fixture.state,
        spouse_types[2],
        .{ .spouse_profile_present = true },
    );
    try expectChecked(&fixture.state, spouse_atcs[3], true);
    for (spouse_atcs, 0..) |id, index| {
        if (index != 3) {
            try std.testing.expect(try fixture.runtime.isDisabled(id));
        }
    }
    try expectText(&fixture.state, payment_spouse_inputs[0], "0.00");
    try std.testing.expect(
        try fixture.runtime.isDisabled(payment_spouse_inputs[0]),
    );
}

test "all filer ATCs select their grounded rate and schedule branch" {
    for (filer_atcs, 0..) |atc_id, index| {
        var fixture = try initTest(false);
        defer fixture.state.deinit();
        _ = try fixture.runtime.click(
            &fixture.state,
            filer_types[0],
            .{ .spouse_profile_present = false },
        );
        _ = try fixture.runtime.click(
            &fixture.state,
            atc_id,
            .{ .spouse_profile_present = false },
        );
        if (index < 3) {
            try expectChecked(&fixture.state, filer_rates[0], true);
            try std.testing.expect(
                !try fixture.runtime.isDisabled(
                    schedule1_filer_inputs[0],
                ),
            );
        } else {
            try expectChecked(&fixture.state, filer_rates[1], true);
            try std.testing.expect(
                !try fixture.runtime.isDisabled(
                    schedule2_filer_inputs[0],
                ),
            );
        }
    }
}

test "all spouse ATCs cover graduated percentage and compensation branches" {
    for (spouse_atcs, 0..) |atc_id, index| {
        var fixture = try initTest(true);
        defer fixture.state.deinit();
        _ = try fixture.runtime.click(
            &fixture.state,
            atc_id,
            .{ .spouse_profile_present = true },
        );
        if (index < 3) {
            try expectChecked(&fixture.state, spouse_rates[0], true);
        } else if (index >= 4) {
            try expectChecked(&fixture.state, spouse_rates[1], true);
        } else {
            try expectChecked(&fixture.state, spouse_rates[0], false);
            try expectChecked(&fixture.state, spouse_rates[1], false);
            try std.testing.expect(
                try fixture.runtime.isDisabled(
                    payment_spouse_inputs[0],
                ),
            );
        }
    }
}

test "schedule and deduction clicks clear displaced transaction inputs" {
    var fixture = try initTest(false);
    defer fixture.state.deinit();
    _ = try fixture.runtime.click(
        &fixture.state,
        filer_types[0],
        .{ .spouse_profile_present = false },
    );
    _ = try fixture.runtime.click(
        &fixture.state,
        filer_atcs[0],
        .{ .spouse_profile_present = false },
    );
    _ = try fixture.runtime.click(
        &fixture.state,
        filer_methods[0],
        .{ .spouse_profile_present = false },
    );
    try std.testing.expect(
        !try fixture.runtime.isDisabled("frm1701q:txt37A"),
    );
    try setText(&fixture.state, "frm1701q:txt37A", "123.00");
    try setText(&fixture.state, "frm1701q:txt39A", "456.00");
    _ = try fixture.runtime.click(
        &fixture.state,
        filer_methods[1],
        .{ .spouse_profile_present = false },
    );
    try expectText(&fixture.state, "frm1701q:txt37A", "0.00");
    try expectText(&fixture.state, "frm1701q:txt39A", "0.00");

    _ = try fixture.runtime.click(
        &fixture.state,
        filer_atcs[5],
        .{ .spouse_profile_present = false },
    );
    try std.testing.expect(
        try fixture.runtime.isDisabled("frm1701q:txt52A"),
    );
    try expectText(&fixture.state, "frm1701q:txt52A", "0.00");
}

test "spouse Schedule 1 preserves the grounded filer-itemized gate typo" {
    var fixture = try initTest(true);
    defer fixture.state.deinit();
    _ = try fixture.runtime.click(
        &fixture.state,
        filer_types[0],
        .{ .spouse_profile_present = true },
    );
    _ = try fixture.runtime.click(
        &fixture.state,
        filer_atcs[0],
        .{ .spouse_profile_present = true },
    );
    _ = try fixture.runtime.click(
        &fixture.state,
        filer_methods[0],
        .{ .spouse_profile_present = true },
    );
    try expectChecked(&fixture.state, filer_methods[0], true);

    _ = try fixture.runtime.click(
        &fixture.state,
        spouse_rates[0],
        .{ .spouse_profile_present = true },
    );
    try std.testing.expect(
        !try fixture.runtime.isDisabled("frm1701q:txt37B"),
    );
    try std.testing.expect(
        !try fixture.runtime.isDisabled("frm1701q:txt39B"),
    );
    try expectChecked(&fixture.state, spouse_methods[0], false);
}

test "qualified blur behavior covers uppercase year date money and item52" {
    var fixture = try initTest(false);
    defer fixture.state.deinit();
    try setText(&fixture.state, "frm1701q:txtLOB", "small shop");
    try setText(&fixture.state, "frm1701q:txt43Desc", "other cost");
    const upper = try fixture.runtime.blur(
        &fixture.state,
        "frm1701q:txtLOB",
        .{
            .current_year = 2026,
            .schedule_date = .{
                .current_date = .{
                    .year = 2026,
                    .month = 7,
                    .day = 30,
                },
                .empty_default_input_was_later = false,
            },
        },
    );
    try std.testing.expectEqual(BlurMutation.uppercased, upper.mutation);
    try expectText(&fixture.state, "frm1701q:txtLOB", "SMALL SHOP");
    try expectText(&fixture.state, "frm1701q:txt43Desc", "OTHER COST");

    try setText(&fixture.state, "frm1701q:txtYear", "2027");
    const year = try fixture.runtime.blur(
        &fixture.state,
        "frm1701q:txtYear",
        .{
            .current_year = 2026,
            .schedule_date = .{
                .current_date = .{
                    .year = 2026,
                    .month = 7,
                    .day = 30,
                },
                .empty_default_input_was_later = false,
            },
        },
    );
    try std.testing.expectEqual(BlurMutation.cleared, year.mutation);
    try expectText(&fixture.state, "frm1701q:txtYear", "");
    try setText(&fixture.state, "frm1701q:txtYear", "2026");

    try setText(&fixture.state, "frm1701q:txtDate32", "07/31/2026");
    const date = try fixture.runtime.blur(
        &fixture.state,
        "frm1701q:txtDate32",
        .{
            .current_year = 2026,
            .schedule_date = .{
                .current_date = .{
                    .year = 2026,
                    .month = 7,
                    .day = 30,
                },
                .empty_default_input_was_later = false,
            },
        },
    );
    try std.testing.expectEqual(BlurMutation.cleared, date.mutation);
    try std.testing.expect(date.alert != null);

    try setText(&fixture.state, "frm1701q:txt52A", "250,000.01");
    const item52 = try fixture.runtime.blur(
        &fixture.state,
        "frm1701q:txt52A",
        .{
            .current_year = 2026,
            .schedule_date = .{
                .current_date = .{
                    .year = 2026,
                    .month = 7,
                    .day = 30,
                },
                .empty_default_input_was_later = false,
            },
        },
    );
    try std.testing.expectEqual(
        BlurMutation.reset_to_zero,
        item52.mutation,
    );
    try expectText(&fixture.state, "frm1701q:txt52A", "0.00");
}

test "unqualified pre-blur grammars reject atomically" {
    var fixture = try initTest(false);
    defer fixture.state.deinit();
    try setText(&fixture.state, "frm1701q:txt36A", "1234.56");
    try std.testing.expectError(
        error.PreBlurMoneyGrammarUnqualified,
        fixture.runtime.blur(
            &fixture.state,
            "frm1701q:txt36A",
            .{
                .current_year = 2026,
                .schedule_date = .{
                    .current_date = .{
                        .year = 2026,
                        .month = 7,
                        .day = 30,
                    },
                    .empty_default_input_was_later = false,
                },
            },
        ),
    );
    try expectText(&fixture.state, "frm1701q:txt36A", "1234.56");

    try setText(&fixture.state, "frm1701q:txtYear", "26.0");
    try std.testing.expectError(
        error.PreBlurYearGrammarUnqualified,
        fixture.runtime.blur(
            &fixture.state,
            "frm1701q:txtYear",
            .{
                .current_year = 2026,
                .schedule_date = .{
                    .current_date = .{
                        .year = 2026,
                        .month = 7,
                        .day = 30,
                    },
                    .empty_default_input_was_later = false,
                },
            },
        ),
    );
    try expectText(&fixture.state, "frm1701q:txtYear", "26.0");
}
