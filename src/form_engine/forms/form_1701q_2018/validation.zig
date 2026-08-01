//! Ordered validation core for BIR Form 1701Q January 2018 ENCS.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1701Qv2018.hta`
//! - SHA-256:
//!   `5f164dde6154b96f28e23656ed2ef29406010ee3f94333e88ea6eb107fe589a0`
//! - Full `validate()` lines 3327-3448.
//! - Schedule-date `validateDate()` lines 3235-3300.
//! - Item 52/year edit validators lines 3302-3325.
//! - Birth helper `validateMonthDayYearDate()` lines 4589-4635.
//! - Save gate `initialValidateBeforeSave()` lines 4637-4655.
//! - TIN message adapter: `js/string-util.js` SHA-256
//!   `bc7f86f70bf993389a3a0135dcbd76c3e370c49d2eb95e2fc66ff318a2ebe43c`,
//!   `getTinChkCode`/`getChkTinErrDesc` lines 74-105.
//! - Legacy checksum process binding: `js/eBIRTools.vbs` SHA-256
//!   `7d0ceb5aad2c0eb90aeca189d6104ff05163ecd1820379f456125634ff7460f7`,
//!   `ValidateTinWChkDgt` lines 111-124.
//! - That binding delegates to unsigned 32-bit `chkt.exe`, SHA-256
//!   `c00bd4131a725af53f48c6385d3332c4b789e15441bf52bbac73117c96c1b0ac`.
//!   No qualified local replacement or approved oracle corpus is currently
//!   available, so application callers must retain `.not_evaluated`; the
//!   legacy executable is evidence-only and is never invoked by this module.
//!
//! The audit CSV reports 28 lexical `alert(` matches for `validate()`. Two are
//! inside the block comment at HTA lines 3367-3374. The executable pipeline is
//! therefore exactly 25 ordered failures plus one terminal success alert.

const std = @import("std");

pub const manifest_lexical_alert_count: u8 = 28;
pub const commented_alert_count: u8 = 2;
pub const active_failure_count: u8 = 25;
pub const active_success_alert_count: u8 = 1;

pub const LegacyReturn = enum {
    undefined,
    boolean_true,
    boolean_false,
};

pub const FullRuleId = enum(u8) {
    year_required = 1,
    year_not_future = 2,
    year_not_before_1900 = 3,
    quarter_required = 4,
    taxpayer_tin_required = 5,
    taxpayer_tin_segment_lengths = 6,
    taxpayer_rdo_required = 7,
    taxpayer_name_required = 8,
    taxpayer_address_required = 9,
    taxpayer_birth_date_format = 10,
    taxpayer_birth_date_required = 11,
    taxpayer_birth_year_not_future = 12,
    taxpayer_zip_required = 13,
    spouse_tin_shape = 14,
    spouse_tin_checksum = 15,
    spouse_rdo_required = 16,
    spouse_name_required = 17,
    spouse_atc_required_with_tin = 18,
    taxpayer_type_required = 19,
    taxpayer_atc_required = 20,
    taxpayer_tax_rate_required = 21,
    taxpayer_deduction_method_required = 22,
    spouse_type_required_with_name = 23,
    spouse_atc_required_with_name = 24,
    spouse_tax_rate_required = 25,
};

pub const FullRule = struct {
    id: FullRuleId,
    source_order: u8,
    source_line: u16,
    alert: []const u8,
    legacy_return: LegacyReturn = .undefined,
    explicit_focus: bool = false,
};

pub const full_rules = [_]FullRule{
    .{ .id = .year_required, .source_order = 1, .source_line = 3330, .alert = "Please enter a valid year in Item 1." },
    .{ .id = .year_not_future, .source_order = 2, .source_line = 3334, .alert = "Invalid date entry on Item no.1. Entry should not be later than Current Date." },
    .{ .id = .year_not_before_1900, .source_order = 3, .source_line = 3338, .alert = "Invalid date entry on Item no.1. Entry should not be lower than 1900." },
    .{ .id = .quarter_required, .source_order = 4, .source_line = 3342, .alert = "Please select quarter in Item 2." },
    .{ .id = .taxpayer_tin_required, .source_order = 5, .source_line = 3347, .alert = "Please enter a valid TIN number on Item 5." },
    .{ .id = .taxpayer_tin_segment_lengths, .source_order = 6, .source_line = 3352, .alert = "Please enter a valid TIN number on Item 5." },
    .{ .id = .taxpayer_rdo_required, .source_order = 7, .source_line = 3356, .alert = "Please enter a valid RDO Code on Item 6." },
    .{ .id = .taxpayer_name_required, .source_order = 8, .source_line = 3360, .alert = "Please enter a valid Taxpayer Name on Item 9." },
    .{ .id = .taxpayer_address_required, .source_order = 9, .source_line = 3364, .alert = "Please enter Taxpayer's Registered Address on Item 10." },
    .{ .id = .taxpayer_birth_date_format, .source_order = 10, .source_line = 3377, .alert = "Invalid birth date on item 11 of Taxpayer.  Please check date format.", .legacy_return = .boolean_true },
    .{ .id = .taxpayer_birth_date_required, .source_order = 11, .source_line = 3381, .alert = "Please indicate Birth Date of Taxpayer on item 11.", .legacy_return = .boolean_true },
    .{ .id = .taxpayer_birth_year_not_future, .source_order = 12, .source_line = 3385, .alert = "Birth Year on Item 11 should not be later than current year.", .legacy_return = .boolean_false },
    .{ .id = .taxpayer_zip_required, .source_order = 13, .source_line = 3389, .alert = "Please enter Zip Code on Item 10A." },
    .{ .id = .spouse_tin_shape, .source_order = 14, .source_line = 3396, .alert = "Please enter a valid TIN number on Item 17." },
    .{ .id = .spouse_tin_checksum, .source_order = 15, .source_line = 3401, .alert = "You have entered an incorrect TIN on Item 17." },
    .{ .id = .spouse_rdo_required, .source_order = 16, .source_line = 3405, .alert = "Please enter a valid RDO Code on Item 18." },
    .{ .id = .spouse_name_required, .source_order = 17, .source_line = 3409, .alert = "Please enter Spouse Name on Item 21." },
    .{ .id = .spouse_atc_required_with_tin, .source_order = 18, .source_line = 3413, .alert = "Please select an option for Item 20." },
    .{ .id = .taxpayer_type_required, .source_order = 19, .source_line = 3420, .alert = "Please select an option for Item 7." },
    .{ .id = .taxpayer_atc_required, .source_order = 20, .source_line = 3423, .alert = "Please select an option for Item 8." },
    .{ .id = .taxpayer_tax_rate_required, .source_order = 21, .source_line = 3426, .alert = "Please select an option for Item 16." },
    .{ .id = .taxpayer_deduction_method_required, .source_order = 22, .source_line = 3429, .alert = "Please select an option for Item 16A." },
    .{ .id = .spouse_type_required_with_name, .source_order = 23, .source_line = 3433, .alert = "Please select an option for Item 19." },
    .{ .id = .spouse_atc_required_with_name, .source_order = 24, .source_line = 3436, .alert = "Please select an option for Item 20." },
    .{ .id = .spouse_tax_rate_required, .source_order = 25, .source_line = 3440, .alert = "Please select an option for Item 25." },
};

pub const FullFailure = struct {
    rule: FullRule,
};

pub const FullSuccess = struct {
    source_line: u16 = 3446,
    alert: []const u8 =
        "Validation successful. Click on Edit if you wish to modify your entries.",
    disables_all_controls_before_alert: bool = true,
};

pub const ValidationBlock = enum {
    /// The exact spouse checksum is supplied by the `chkt.exe` adapter in the
    /// legacy runtime. Unknown status must not be silently treated as valid.
    spouse_tin_checksum_not_evaluated,
};

pub const FullValidationResult = union(enum) {
    failure: FullFailure,
    blocked: ValidationBlock,
    success: FullSuccess,
};

pub const TinChecksumStatus = enum {
    not_evaluated,
    valid,
    invalid,
};

pub const FormValidationInput = struct {
    current_year: i32,
    year: []const u8 = "",
    quarter_checked: [3]bool = .{ false, false, false },

    taxpayer_tin: [3][]const u8 = .{ "", "", "" },
    taxpayer_branch_code: []const u8 = "",
    taxpayer_rdo_selected_index: usize = 0,
    taxpayer_rdo_value: []const u8 = "000",
    taxpayer_name: []const u8 = "",
    taxpayer_address: []const u8 = "",
    taxpayer_birth_month: []const u8 = "",
    taxpayer_birth_day: []const u8 = "",
    taxpayer_birth_year: []const u8 = "",
    taxpayer_zip: []const u8 = "",

    spouse_tin: [3][]const u8 = .{ "", "", "" },
    spouse_branch_code: []const u8 = "",
    spouse_tin_checksum: TinChecksumStatus = .not_evaluated,
    spouse_rdo_selected_index: usize = 0,
    spouse_name: []const u8 = "",

    taxpayer_type_checked: [4]bool = .{ false, false, false, false },
    taxpayer_atc_checked: [6]bool = .{ false, false, false, false, false, false },
    taxpayer_tax_rate_checked: [2]bool = .{ false, false },
    taxpayer_deduction_method_checked: [2]bool = .{ false, false },
    spouse_type_checked: [3]bool = .{ false, false, false },
    spouse_atc_checked: [7]bool = .{ false, false, false, false, false, false, false },
    spouse_tax_rate_checked: [2]bool = .{ false, false },
};

/// Exact executable order of `validate()`, including duplicate messages,
/// conditional spouse branches, and inconsistent legacy return values.
pub fn validateFull(input: FormValidationInput) FullValidationResult {
    if (input.year.len == 0) return fail(.year_required);
    if (legacyGreaterThan(input.year, input.current_year)) {
        return fail(.year_not_future);
    }
    if (legacyLessThan(input.year, 1900)) {
        return fail(.year_not_before_1900);
    }
    if (!anyChecked(&input.quarter_checked)) return fail(.quarter_required);

    if (input.taxpayer_tin[0].len == 0 or
        input.taxpayer_tin[1].len == 0 or
        input.taxpayer_tin[2].len == 0 or
        input.taxpayer_branch_code.len == 0)
    {
        return fail(.taxpayer_tin_required);
    }
    if (input.taxpayer_tin[0].len != 3 or
        input.taxpayer_tin[1].len != 3 or
        input.taxpayer_tin[2].len != 3 or
        input.taxpayer_branch_code.len < 3)
    {
        return fail(.taxpayer_tin_segment_lengths);
    }
    if (input.taxpayer_rdo_selected_index == 0) {
        return fail(.taxpayer_rdo_required);
    }
    if (input.taxpayer_name.len == 0) return fail(.taxpayer_name_required);
    if (input.taxpayer_address.len == 0) {
        return fail(.taxpayer_address_required);
    }

    const any_birth_part = input.taxpayer_birth_month.len != 0 or
        input.taxpayer_birth_day.len != 0 or
        input.taxpayer_birth_year.len != 0;
    if (any_birth_part) {
        if (legacyBirthDateInvalid(
            input.taxpayer_birth_month,
            input.taxpayer_birth_day,
            input.taxpayer_birth_year,
        )) {
            return fail(.taxpayer_birth_date_format);
        }
    } else {
        return fail(.taxpayer_birth_date_required);
    }
    if (legacyGreaterThan(input.taxpayer_birth_year, input.current_year)) {
        return fail(.taxpayer_birth_year_not_future);
    }
    if (input.taxpayer_zip.len == 0) return fail(.taxpayer_zip_required);

    const any_spouse_tin = input.spouse_tin[0].len != 0 or
        input.spouse_tin[1].len != 0 or
        input.spouse_tin[2].len != 0;
    if (any_spouse_tin) {
        if (input.spouse_tin[0].len != 3 or
            input.spouse_tin[1].len != 3 or
            input.spouse_tin[2].len != 3 or
            input.spouse_branch_code.len > 5)
        {
            return fail(.spouse_tin_shape);
        }
        switch (input.spouse_tin_checksum) {
            .not_evaluated => return .{
                .blocked = .spouse_tin_checksum_not_evaluated,
            },
            .invalid => return fail(.spouse_tin_checksum),
            .valid => {},
        }
        if (input.spouse_rdo_selected_index == 0) {
            return fail(.spouse_rdo_required);
        }
        if (input.spouse_name.len == 0) return fail(.spouse_name_required);
        if (!anyChecked(&input.spouse_atc_checked)) {
            return fail(.spouse_atc_required_with_tin);
        }
    }

    if (!anyChecked(&input.taxpayer_type_checked)) {
        return fail(.taxpayer_type_required);
    }
    if (!anyChecked(&input.taxpayer_atc_checked)) {
        return fail(.taxpayer_atc_required);
    }
    if (!anyChecked(&input.taxpayer_tax_rate_checked)) {
        return fail(.taxpayer_tax_rate_required);
    }
    if (input.taxpayer_tax_rate_checked[0] and
        !anyChecked(&input.taxpayer_deduction_method_checked))
    {
        return fail(.taxpayer_deduction_method_required);
    }

    if (input.spouse_name.len != 0) {
        if (!anyChecked(&input.spouse_type_checked)) {
            return fail(.spouse_type_required_with_name);
        }
        if (!anyChecked(&input.spouse_atc_checked)) {
            return fail(.spouse_atc_required_with_name);
        }
        if (!anyChecked(&input.spouse_tax_rate_checked) and
            !input.spouse_type_checked[2])
        {
            return fail(.spouse_tax_rate_required);
        }
    }

    return .{ .success = .{} };
}

fn fail(id: FullRuleId) FullValidationResult {
    for (full_rules) |rule| {
        if (rule.id == id) return .{ .failure = .{ .rule = rule } };
    }
    unreachable;
}

fn anyChecked(values: []const bool) bool {
    for (values) |checked| {
        if (checked) return true;
    }
    return false;
}

/// Models numeric comparisons made with JavaScript `value * 1` for the
/// digit-only, four-character fields exposed by this HTA. Nonnumeric text is
/// `null` (NaN), and all ordered comparisons with it are false.
fn legacyWholeNumber(raw: []const u8) ?i64 {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return 0;
    return std.fmt.parseInt(i64, trimmed, 10) catch null;
}

fn legacyGreaterThan(raw: []const u8, bound: i64) bool {
    const value = legacyWholeNumber(raw) orelse return false;
    return value > bound;
}

fn legacyLessThan(raw: []const u8, bound: i64) bool {
    const value = legacyWholeNumber(raw) orelse return false;
    return value < bound;
}

/// Exact source-reachable semantics of `validateMonthDayYearDate()`. Notable
/// legacy quirks retained here: month `00` is accepted, only the first truthy
/// date segment is tested by `isNaN`, and the year is checked for length but
/// not independently for digits.
pub fn legacyBirthDateInvalid(
    month: []const u8,
    day: []const u8,
    year: []const u8,
) bool {
    const first_truthy = if (month.len != 0)
        month
    else if (day.len != 0)
        day
    else
        year;
    if (first_truthy.len != 0 and legacyWholeNumber(first_truthy) == null) {
        return true;
    }

    if (month.len != 2 or
        legacyGreaterThan(month, 12) or
        legacyLessThan(month, 0))
    {
        return true;
    }
    if (day.len != 2 or
        legacyGreaterThan(day, 31) or
        legacyLessThan(day, 1))
    {
        return true;
    }
    if (year.len != 4) return true;

    const month_number = legacyWholeNumber(month);
    const day_number = legacyWholeNumber(day);
    if (month_number != null and month_number.? == 2) {
        const leap = legacyJsLeapYear(year);
        if (!leap and day_number != null and day_number.? == 29) return true;
        if (!leap and day_number != null and day_number.? > 29) return true;
        if (leap and day_number != null and day_number.? > 29) return true;
    } else if (isExactMonth(month, &.{ "01", "03", "05", "07", "08", "10", "12" })) {
        if (day_number != null and day_number.? > 31) return true;
    } else if (isExactMonth(month, &.{ "04", "06", "09", "11" })) {
        if (day_number != null and day_number.? > 30) return true;
    }
    return false;
}

fn isExactMonth(value: []const u8, candidates: []const []const u8) bool {
    for (candidates) |candidate| {
        if (std.mem.eql(u8, value, candidate)) return true;
    }
    return false;
}

fn legacyJsLeapYear(raw: []const u8) bool {
    var year = legacyWholeNumber(raw) orelse return false;
    // ECMAScript's multi-argument Date constructor maps years 0-99 to
    // 1900-1999 before the February-29 normalization used by the HTA.
    if (year >= 0 and year <= 99) year += 1900;
    return @mod(year, 4) == 0 and
        (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

pub const SaveRuleId = enum(u8) {
    quarter_required = 1,
    taxpayer_tin_required = 2,
    taxpayer_rdo_required = 3,
    taxpayer_name_required = 4,
};

pub const SaveRule = struct {
    id: SaveRuleId,
    source_order: u8,
    source_line: u16,
    alert: []const u8,
};

pub const save_rules = [_]SaveRule{
    .{ .id = .quarter_required, .source_order = 1, .source_line = 4639, .alert = "Please select quarter in Item 2." },
    .{ .id = .taxpayer_tin_required, .source_order = 2, .source_line = 4643, .alert = "Please enter a valid TIN number on Item 5." },
    .{ .id = .taxpayer_rdo_required, .source_order = 3, .source_line = 4647, .alert = "Please enter a valid RDO Code on Item 6." },
    .{ .id = .taxpayer_name_required, .source_order = 4, .source_line = 4651, .alert = "Please enter a valid Taxpayer Name on Item 9." },
};

pub const SaveValidationResult = union(enum) {
    failure: SaveRule,
    success,
};

/// Exact four-rule `initialValidateBeforeSave()` gate. It intentionally checks
/// the RDO value for `"000"` while full validation checks `selectedIndex == 0`.
pub fn validateBeforeSave(input: FormValidationInput) SaveValidationResult {
    if (!anyChecked(&input.quarter_checked)) {
        return saveFail(.quarter_required);
    }
    if (input.taxpayer_tin[0].len == 0 or
        input.taxpayer_tin[1].len == 0 or
        input.taxpayer_tin[2].len == 0 or
        input.taxpayer_branch_code.len == 0)
    {
        return saveFail(.taxpayer_tin_required);
    }
    if (std.mem.eql(u8, input.taxpayer_rdo_value, "000")) {
        return saveFail(.taxpayer_rdo_required);
    }
    if (input.taxpayer_name.len == 0) {
        return saveFail(.taxpayer_name_required);
    }
    return .success;
}

fn saveFail(id: SaveRuleId) SaveValidationResult {
    for (save_rules) |rule| {
        if (rule.id == id) return .{ .failure = rule };
    }
    unreachable;
}

pub const ArtifactIntent = enum {
    editable_save,
    final_copy,
};

pub const TransitionDenial = enum {
    save_gate_failed,
    full_validation_missing,
    full_validation_not_successful,
};

pub const ArtifactTransition = union(enum) {
    allowed,
    denied: TransitionDenial,
};

/// State-machine boundary that fixes the documented Desktop bypass: legacy
/// `saveXML()` falls through to `return true` even when its initial gate fails.
/// Rule semantics stay unchanged, but serialization is never authorized from a
/// failed gate. Final Copy additionally requires terminal full-validation
/// success; UI button enablement alone is not trusted.
pub fn authorizeArtifactTransition(
    intent: ArtifactIntent,
    save_result: SaveValidationResult,
    full_result: ?FullValidationResult,
) ArtifactTransition {
    switch (save_result) {
        .failure => return .{ .denied = .save_gate_failed },
        .success => {},
    }
    if (intent == .editable_save) return .allowed;

    const full = full_result orelse
        return .{ .denied = .full_validation_missing };
    return switch (full) {
        .success => .allowed,
        .failure, .blocked => .{
            .denied = .full_validation_not_successful,
        },
    };
}

pub const EditValidation = union(enum) {
    unchanged,
    rejected: struct {
        alert: []const u8,
        clear_value: bool,
        focus: bool,
    },
};

/// `validateYear()` lines 3317-3325. The alert says "greater than or equal",
/// but the executable predicate is strictly greater; that mismatch is
/// preserved.
pub fn validateYearOnBlur(
    year: []const u8,
    current_year: i32,
) EditValidation {
    if (!legacyGreaterThan(year, current_year)) return .unchanged;
    return .{ .rejected = .{
        .alert = "Year (Item 1) cannot be greater than or equal to current year.",
        .clear_value = true,
        .focus = false,
    } };
}

pub const Item52EditResult = struct {
    value_centavos: i64,
    alert: ?[]const u8,
};

/// `item52Validate()` lines 3302-3316. The spouse branch repeats "52A" in the
/// alert; the same literal is therefore used for both persons.
pub fn validateItem52OnBlur(value_centavos: i64) Item52EditResult {
    if (value_centavos <= 250_000 * 100) {
        return .{ .value_centavos = value_centavos, .alert = null };
    }
    return .{
        .value_centavos = 0,
        .alert = "Item 52A cannot be more than P250,000.",
    };
}

pub const CalendarDate = struct {
    year: i32,
    month: u8,
    day: u8,
};

pub const ScheduleDateEditResult = struct {
    /// Mirrors the function's returned `isValid`. A future date still returns
    /// true in the Desktop source even though it is cleared and focused.
    legacy_return_is_valid: bool,
    alert: ?[]const u8,
    clear_value: bool,
    focus: bool,
};

/// `validateDate()` creates `currentDate` and then a second default
/// `inputDate`. For an empty control, whether the latter is greater depends on
/// the two wall-clock reads. The caller must supply that observed relation so
/// the core does not invent deterministic behavior for a nondeterministic
/// legacy edge.
pub const ScheduleDateContext = struct {
    current_date: CalendarDate,
    empty_default_input_was_later: bool,
};

/// `validateDate()` lines 3235-3300, used by Schedule I Items 32-35.
pub fn validateScheduleDateOnBlur(
    raw: []const u8,
    context: ScheduleDateContext,
) ScheduleDateEditResult {
    if (raw.len == 0) {
        if (context.empty_default_input_was_later) {
            return .{
                .legacy_return_is_valid = true,
                .alert = "This date cannot be a future date.",
                .clear_value = true,
                .focus = true,
            };
        }
        return .{
            .legacy_return_is_valid = true,
            .alert = null,
            .clear_value = false,
            .focus = false,
        };
    }

    var parts = std.mem.splitScalar(u8, raw, '/');
    const month = parts.next() orelse "";
    const day = parts.next() orelse "";
    const year = parts.next() orelse "";
    const exactly_three = parts.next() == null;
    if (!exactly_three or legacyScheduleDatePartsInvalid(month, day, year)) {
        return .{
            .legacy_return_is_valid = false,
            .alert = "Please provide a valid date. (MM/DD/YYYY format)",
            .clear_value = true,
            .focus = true,
        };
    }

    const parsed_month = legacyWholeNumber(month);
    const parsed_day = legacyWholeNumber(day);
    const parsed_year = legacyWholeNumber(year);
    if (parsed_month != null and parsed_day != null and parsed_year != null) {
        var normalized_year = parsed_year.?;
        if (normalized_year >= 0 and normalized_year <= 99) {
            normalized_year += 1900;
        }
        const entered: CalendarDate = .{
            .year = std.math.cast(i32, normalized_year) orelse
                return .{
                    .legacy_return_is_valid = true,
                    .alert = null,
                    .clear_value = false,
                    .focus = false,
                },
            .month = std.math.cast(u8, parsed_month.?).?,
            .day = std.math.cast(u8, parsed_day.?).?,
        };
        if (calendarDateAfter(entered, context.current_date)) {
            return .{
                .legacy_return_is_valid = true,
                .alert = "This date cannot be a future date.",
                .clear_value = true,
                .focus = true,
            };
        }
    }

    return .{
        .legacy_return_is_valid = true,
        .alert = null,
        .clear_value = false,
        .focus = false,
    };
}

fn legacyScheduleDatePartsInvalid(
    month: []const u8,
    day: []const u8,
    year: []const u8,
) bool {
    const first_truthy = if (month.len != 0)
        month
    else if (day.len != 0)
        day
    else
        year;
    if (first_truthy.len != 0 and legacyWholeNumber(first_truthy) == null) {
        return true;
    }
    if (month.len != 2 or
        legacyGreaterThan(month, 12) or
        legacyLessThan(month, 1))
    {
        return true;
    }
    if (day.len != 2 or
        legacyGreaterThan(day, 31) or
        legacyLessThan(day, 1))
    {
        return true;
    }
    if (year.len != 4) return true;

    const month_number = legacyWholeNumber(month);
    const day_number = legacyWholeNumber(day);
    if (month_number != null and month_number.? == 2) {
        const leap = legacyJsLeapYear(year);
        if (!leap and day_number != null and day_number.? == 29) return true;
        if (!leap and day_number != null and day_number.? > 29) return true;
        if (leap and day_number != null and day_number.? > 29) return true;
    } else if (isExactMonth(month, &.{ "04", "06", "09", "11" })) {
        if (day_number != null and day_number.? > 30) return true;
    }
    return false;
}

fn calendarDateAfter(left: CalendarDate, right: CalendarDate) bool {
    if (left.year != right.year) return left.year > right.year;
    if (left.month != right.month) return left.month > right.month;
    return left.day > right.day;
}

fn validFixture() FormValidationInput {
    return .{
        .current_year = 2026,
        .year = "2020",
        .quarter_checked = .{ true, false, false },
        .taxpayer_tin = .{ "111", "222", "333" },
        .taxpayer_branch_code = "000",
        .taxpayer_rdo_selected_index = 1,
        .taxpayer_rdo_value = "001",
        .taxpayer_name = "SYNTHETIC",
        .taxpayer_address = "SYNTHETIC",
        .taxpayer_birth_month = "01",
        .taxpayer_birth_day = "01",
        .taxpayer_birth_year = "1990",
        .taxpayer_zip = "0000",
        .taxpayer_type_checked = .{ true, false, false, false },
        .taxpayer_atc_checked = .{ true, false, false, false, false, false },
        .taxpayer_tax_rate_checked = .{ true, false },
        .taxpayer_deduction_method_checked = .{ true, false },
    };
}

fn enableValidSpouseTin(input: *FormValidationInput) void {
    input.spouse_tin = .{ "444", "555", "666" };
    input.spouse_branch_code = "000";
    input.spouse_tin_checksum = .valid;
    input.spouse_rdo_selected_index = 1;
    input.spouse_name = "SYNTHETIC SPOUSE";
    input.spouse_type_checked = .{ true, false, false };
    input.spouse_atc_checked = .{ true, false, false, false, false, false, false };
    input.spouse_tax_rate_checked = .{ true, false };
}

fn expectFullRule(
    input: FormValidationInput,
    expected: FullRuleId,
) !void {
    switch (validateFull(input)) {
        .failure => |failure| try std.testing.expectEqual(expected, failure.rule.id),
        .blocked, .success => return error.TestUnexpectedResult,
    }
}

test "all 25 executable full-validation alerts are first-error reachable in source order" {
    for (full_rules) |expected| {
        var input = validFixture();
        switch (expected.id) {
            .year_required => input.year = "",
            .year_not_future => input.year = "2027",
            .year_not_before_1900 => input.year = "1899",
            .quarter_required => input.quarter_checked = .{ false, false, false },
            .taxpayer_tin_required => input.taxpayer_tin[0] = "",
            .taxpayer_tin_segment_lengths => input.taxpayer_tin[0] = "11",
            .taxpayer_rdo_required => input.taxpayer_rdo_selected_index = 0,
            .taxpayer_name_required => input.taxpayer_name = "",
            .taxpayer_address_required => input.taxpayer_address = "",
            .taxpayer_birth_date_format => input.taxpayer_birth_day = "32",
            .taxpayer_birth_date_required => {
                input.taxpayer_birth_month = "";
                input.taxpayer_birth_day = "";
                input.taxpayer_birth_year = "";
            },
            .taxpayer_birth_year_not_future => input.taxpayer_birth_year = "2027",
            .taxpayer_zip_required => input.taxpayer_zip = "",
            .spouse_tin_shape => {
                enableValidSpouseTin(&input);
                input.spouse_tin[0] = "44";
            },
            .spouse_tin_checksum => {
                enableValidSpouseTin(&input);
                input.spouse_tin_checksum = .invalid;
            },
            .spouse_rdo_required => {
                enableValidSpouseTin(&input);
                input.spouse_rdo_selected_index = 0;
            },
            .spouse_name_required => {
                enableValidSpouseTin(&input);
                input.spouse_name = "";
            },
            .spouse_atc_required_with_tin => {
                enableValidSpouseTin(&input);
                input.spouse_atc_checked =
                    .{ false, false, false, false, false, false, false };
            },
            .taxpayer_type_required => {
                input.taxpayer_type_checked = .{ false, false, false, false };
            },
            .taxpayer_atc_required => {
                input.taxpayer_atc_checked =
                    .{ false, false, false, false, false, false };
            },
            .taxpayer_tax_rate_required => {
                input.taxpayer_tax_rate_checked = .{ false, false };
            },
            .taxpayer_deduction_method_required => {
                input.taxpayer_deduction_method_checked = .{ false, false };
            },
            .spouse_type_required_with_name => {
                input.spouse_name = "SYNTHETIC SPOUSE";
            },
            .spouse_atc_required_with_name => {
                input.spouse_name = "SYNTHETIC SPOUSE";
                input.spouse_type_checked = .{ true, false, false };
            },
            .spouse_tax_rate_required => {
                input.spouse_name = "SYNTHETIC SPOUSE";
                input.spouse_type_checked = .{ true, false, false };
                input.spouse_atc_checked =
                    .{ true, false, false, false, false, false, false };
            },
        }
        try expectFullRule(input, expected.id);
    }
}

test "commented lexical alerts cannot become executable validation rules" {
    try std.testing.expectEqual(@as(usize, active_failure_count), full_rules.len);
    try std.testing.expectEqual(
        manifest_lexical_alert_count,
        active_failure_count + active_success_alert_count + commented_alert_count,
    );
    for (full_rules, 0..) |rule, index| {
        try std.testing.expectEqual(
            @as(u8, @intCast(index + 1)),
            rule.source_order,
        );
        try std.testing.expectEqual(
            rule.source_order,
            @intFromEnum(rule.id),
        );
        try std.testing.expect(rule.source_line != 3368);
        try std.testing.expect(rule.source_line != 3372);
        try std.testing.expect(!rule.explicit_focus);
    }

    var input = validFixture();
    input.taxpayer_birth_month = "";
    input.taxpayer_birth_day = "";
    input.taxpayer_birth_year = "";
    try expectFullRule(input, .taxpayer_birth_date_required);
}

test "full-validation return quirks and terminal success are preserved" {
    try std.testing.expectEqual(
        LegacyReturn.boolean_true,
        full_rules[9].legacy_return,
    );
    try std.testing.expectEqual(
        LegacyReturn.boolean_true,
        full_rules[10].legacy_return,
    );
    try std.testing.expectEqual(
        LegacyReturn.boolean_false,
        full_rules[11].legacy_return,
    );
    for (full_rules, 0..) |rule, index| {
        if (index < 9 or index > 11) {
            try std.testing.expectEqual(LegacyReturn.undefined, rule.legacy_return);
        }
    }

    switch (validateFull(validFixture())) {
        .success => |success| {
            try std.testing.expect(success.disables_all_controls_before_alert);
            try std.testing.expectEqual(@as(u16, 3446), success.source_line);
        },
        .failure, .blocked => return error.TestUnexpectedResult,
    }
}

test "spouse checksum is externally injected and unknown status blocks closed" {
    var input = validFixture();
    enableValidSpouseTin(&input);
    input.spouse_tin_checksum = .not_evaluated;
    switch (validateFull(input)) {
        .blocked => |reason| try std.testing.expectEqual(
            ValidationBlock.spouse_tin_checksum_not_evaluated,
            reason,
        ),
        .failure, .success => return error.TestUnexpectedResult,
    }
}

test "birth helper preserves grounded legacy edge behavior" {
    try std.testing.expect(!legacyBirthDateInvalid("02", "29", "2000"));
    try std.testing.expect(legacyBirthDateInvalid("02", "29", "1900"));
    try std.testing.expect(legacyBirthDateInvalid("04", "31", "2000"));
    try std.testing.expect(!legacyBirthDateInvalid("00", "31", "2000"));
    // Only the first truthy segment is tested by the source's `isNaN(a||b||c)`.
    try std.testing.expect(!legacyBirthDateInvalid("01", "xx", "2000"));
    // JavaScript Date maps year 00 to 1900 for this leap check.
    try std.testing.expect(legacyBirthDateInvalid("02", "29", "0000"));
}

test "all four save-gate failures are first-error reachable" {
    for (save_rules, 0..) |expected, index| {
        try std.testing.expectEqual(
            @as(u8, @intCast(index + 1)),
            expected.source_order,
        );
        try std.testing.expectEqual(
            expected.source_order,
            @intFromEnum(expected.id),
        );
        var input = validFixture();
        switch (expected.id) {
            .quarter_required => input.quarter_checked =
                .{ false, false, false },
            .taxpayer_tin_required => input.taxpayer_branch_code = "",
            .taxpayer_rdo_required => input.taxpayer_rdo_value = "000",
            .taxpayer_name_required => input.taxpayer_name = "",
        }
        switch (validateBeforeSave(input)) {
            .failure => |rule| try std.testing.expectEqual(expected.id, rule.id),
            .success => return error.TestUnexpectedResult,
        }
    }
    switch (validateBeforeSave(validFixture())) {
        .success => {},
        .failure => return error.TestUnexpectedResult,
    }
}

test "full and save RDO predicates remain distinct" {
    var input = validFixture();
    input.taxpayer_rdo_selected_index = 1;
    input.taxpayer_rdo_value = "000";
    switch (validateFull(input)) {
        .success => {},
        .failure, .blocked => return error.TestUnexpectedResult,
    }
    switch (validateBeforeSave(input)) {
        .failure => |rule| try std.testing.expectEqual(
            SaveRuleId.taxpayer_rdo_required,
            rule.id,
        ),
        .success => return error.TestUnexpectedResult,
    }
}

test "artifact transition rejects the legacy save fallthrough bypass" {
    var invalid = validFixture();
    invalid.quarter_checked = .{ false, false, false };
    const failed_save = validateBeforeSave(invalid);
    const successful_full = validateFull(validFixture());

    switch (authorizeArtifactTransition(
        .editable_save,
        failed_save,
        null,
    )) {
        .denied => |reason| try std.testing.expectEqual(
            TransitionDenial.save_gate_failed,
            reason,
        ),
        .allowed => return error.TestUnexpectedResult,
    }
    switch (authorizeArtifactTransition(
        .final_copy,
        validateBeforeSave(validFixture()),
        successful_full,
    )) {
        .allowed => {},
        .denied => return error.TestUnexpectedResult,
    }
    switch (authorizeArtifactTransition(
        .final_copy,
        validateBeforeSave(validFixture()),
        null,
    )) {
        .denied => |reason| try std.testing.expectEqual(
            TransitionDenial.full_validation_missing,
            reason,
        ),
        .allowed => return error.TestUnexpectedResult,
    }
}

test "edit validations retain predicate, mutation, and message quirks" {
    switch (validateYearOnBlur("2026", 2026)) {
        .unchanged => {},
        .rejected => return error.TestUnexpectedResult,
    }
    switch (validateYearOnBlur("2027", 2026)) {
        .rejected => |rejected| {
            try std.testing.expect(rejected.clear_value);
            try std.testing.expect(!rejected.focus);
        },
        .unchanged => return error.TestUnexpectedResult,
    }

    const accepted = validateItem52OnBlur(250_000 * 100);
    try std.testing.expectEqual(@as(i64, 25_000_000), accepted.value_centavos);
    try std.testing.expect(accepted.alert == null);
    const rejected = validateItem52OnBlur(250_000 * 100 + 1);
    try std.testing.expectEqual(@as(i64, 0), rejected.value_centavos);
    try std.testing.expectEqualStrings(
        "Item 52A cannot be more than P250,000.",
        rejected.alert.?,
    );
}

test "schedule-date edit validation preserves format, future, and return quirks" {
    const context: ScheduleDateContext = .{
        .current_date = .{ .year = 2026, .month = 7, .day = 30 },
        .empty_default_input_was_later = false,
    };
    const valid = validateScheduleDateOnBlur("07/30/2026", context);
    try std.testing.expect(valid.legacy_return_is_valid);
    try std.testing.expect(valid.alert == null);

    const malformed = validateScheduleDateOnBlur("02/29/2025", context);
    try std.testing.expect(!malformed.legacy_return_is_valid);
    try std.testing.expect(malformed.clear_value);
    try std.testing.expect(malformed.focus);
    try std.testing.expectEqualStrings(
        "Please provide a valid date. (MM/DD/YYYY format)",
        malformed.alert.?,
    );

    const future = validateScheduleDateOnBlur("07/31/2026", context);
    try std.testing.expect(future.legacy_return_is_valid);
    try std.testing.expect(future.clear_value);
    try std.testing.expectEqualStrings(
        "This date cannot be a future date.",
        future.alert.?,
    );

    const empty_future = validateScheduleDateOnBlur("", .{
        .current_date = context.current_date,
        .empty_default_input_was_later = true,
    });
    try std.testing.expect(empty_future.legacy_return_is_valid);
    try std.testing.expect(empty_future.alert != null);
}
