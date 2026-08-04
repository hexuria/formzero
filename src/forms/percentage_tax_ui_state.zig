//! Controlled filing-input state for BIR Form 2551Q.
//!
//! Profile-prefilled header fields stay in `forms/ui_state.zig`. This module
//! owns only filing/transaction inputs and their derived presentation values.
//! In particular, a percentage-tax rate is always an explicit external-policy
//! input: there is no embedded or fallback rate.

const std = @import("std");
const native_sdk = @import("native_sdk");
const form_2551q = @import("form_2551q.zig");
const field = @import("../tax_profile/field.zig");
const store_module = @import("../tax_profile/store.zig");
const Money = @import("../domain/money.zig").Money;

const canvas = native_sdk.canvas;

pub const max_schedule_rows = 2;
/// The contact details a single filing may state differently from the
/// taxpayer's profile.
///
/// Only contact details: the TIN, RDO, and registered name identify the
/// taxpayer, and a filing that disagreed with the profile about those would be
/// claiming to be a different taxpayer rather than reaching them differently.
pub const FilingContactField = enum {
    registered_address,
    zip_code,
    contact_number,
    email_address,

    pub fn reusable(self: FilingContactField) field.ReusableField {
        return switch (self) {
            .registered_address => .registered_address,
            .zip_code => .zip_code,
            .contact_number => .contact_number,
            .email_address => .email_address,
        };
    }

    /// The stable target this override replaces on the printed form.
    pub fn target(self: FilingContactField) []const u8 {
        return switch (self) {
            .registered_address => "2551Q.2018-01-ENCS.input.registered_address",
            .zip_code => "2551Q.2018-01-ENCS.input.zip_code",
            .contact_number => "2551Q.2018-01-ENCS.input.contact_number",
            .email_address => "2551Q.2018-01-ENCS.input.email_address",
        };
    }
};

pub const filing_contact_field_count = std.meta.tags(FilingContactField).len;

/// Marks a stored value as belonging to this filing rather than to the
/// taxpayer, so provenance survives save and resume.
pub const filing_override_provenance = "filing_override";

fn resolveContactTarget(field_id: []const u8) ?FilingContactField {
    for (std.meta.tags(FilingContactField)) |contact_field| {
        if (std.mem.eql(u8, contact_field.target(), field_id)) {
            return contact_field;
        }
    }
    return null;
}

pub const max_draft_values = 28 + filing_contact_field_count;
pub const max_persisted_value_len = 192;
pub const max_persisted_field_id_len = 96;

pub const Error = error{
    DivisionByZero,
    DuplicateDraftField,
    Empty,
    FieldTooLong,
    InputTruncated,
    InvalidDraftDerivedValue,
    InvalidDraftIntent,
    InvalidDraftLifecycle,
    InvalidDraftProvenance,
    InvalidDraftValue,
    InvalidFormat,
    InvalidMoneySign,
    InvalidOverpaymentDisposition,
    InvalidPeriodContext,
    InvalidStoredForm,
    InvalidTaxRate,
    InvalidYearEndMonth,
    MissingExternalRate,
    MissingIncomeTaxRateElection,
    MissingPeriodBasis,
    MissingScheduleAtc,
    MissingScheduleLine,
    MissingScheduleTaxBase,
    MissingTaxReliefReference,
    NoSpaceLeft,
    OutputTooSmall,
    Overflow,
    TaxReliefReferenceNotApplicable,
    TooManyFractionDigits,
    UnsupportedFiscalPeriod,
};

pub const TaxReliefChoice = enum {
    none,
    specified,
};

/// Stable identities for the bounded Schedule 1 editor. These identities,
/// rather than the packed transaction-line index, choose persisted field IDs.
pub const ScheduleRowId = enum {
    line_1,
    line_2,

    pub fn ordinal(self: ScheduleRowId) u8 {
        return switch (self) {
            .line_1 => 1,
            .line_2 => 2,
        };
    }

    pub fn index(self: ScheduleRowId) usize {
        return switch (self) {
            .line_1 => 0,
            .line_2 => 1,
        };
    }

    pub fn stableKey(self: ScheduleRowId) []const u8 {
        return switch (self) {
            .line_1 => "line-1",
            .line_2 => "line-2",
        };
    }
};

pub const PersistedField = enum {
    period_basis,
    year_end_month,
    taxable_quarter,
    taxable_year,
    sheets_attached,
    return_option,
    amended_return,
    tax_relief,
    tax_relief_reference,
    income_tax_rate_election,
    total_percentage_tax_due,
    creditable_percentage_tax_withheld,
    paid_in_previous_return,
    other_credit_or_payment,
    total_tax_credits_or_payments,
    tax_payable_or_overpayment,
    surcharge,
    interest,
    compromise,
    overpayment_disposition,

    pub fn id(self: PersistedField) []const u8 {
        return switch (self) {
            .period_basis => "2551Q.2018-01-ENCS.input.taxable_period_basis",
            .year_end_month => "2551Q.2018-01-ENCS.input.year_end_month",
            .taxable_quarter => "2551Q.2018-01-ENCS.input.taxable_quarter",
            .taxable_year => "2551Q.2018-01-ENCS.input.taxable_year",
            .sheets_attached => "2551Q.2018-01-ENCS.input.number_of_sheets_attached",
            .return_option => "2551Q.2018-01-ENCS.input.return_options",
            .amended_return => "2551Q.2018-01-ENCS.input.amended_return",
            .tax_relief => "2551Q.2018-01-ENCS.input.tax_relief",
            .tax_relief_reference => "2551Q.2018-01-ENCS.input.tax_relief_specification",
            .income_tax_rate_election => "2551Q.2018-01-ENCS.input.income_tax_rate_election",
            .total_percentage_tax_due => "2551Q.2018-01-ENCS.input.total_percentage_tax_due",
            .creditable_percentage_tax_withheld => "2551Q.2018-01-ENCS.input.creditable_percentage_tax_withheld",
            .paid_in_previous_return => "2551Q.2018-01-ENCS.input.tax_paid_in_previous_return",
            .other_credit_or_payment => "2551Q.2018-01-ENCS.input.other_tax_credit_payment",
            .total_tax_credits_or_payments => "2551Q.2018-01-ENCS.input.total_tax_credits_payments",
            .tax_payable_or_overpayment => "2551Q.2018-01-ENCS.input.tax_payable_overpayment",
            .surcharge => "2551Q.2018-01-ENCS.input.surcharge_manual",
            .interest => "2551Q.2018-01-ENCS.input.interest_manual",
            .compromise => "2551Q.2018-01-ENCS.input.compromise_manual",
            .overpayment_disposition => "2551Q.2018-01-ENCS.input.overpayment_disposition",
        };
    }

    pub fn provenance(self: PersistedField) []const u8 {
        return switch (self) {
            .period_basis,
            .year_end_month,
            .taxable_quarter,
            .taxable_year,
            .sheets_attached,
            .amended_return,
            => "filing_context",
            .creditable_percentage_tax_withheld,
            .paid_in_previous_return,
            => "external_evidence",
            .income_tax_rate_election => "taxpayer_year",
            .total_percentage_tax_due,
            .total_tax_credits_or_payments,
            .tax_payable_or_overpayment,
            => "derived",
            else => "transaction",
        };
    }

    pub fn derived(self: PersistedField) bool {
        return std.mem.eql(u8, self.provenance(), "derived");
    }
};

pub const ScheduleField = enum {
    atc,
    tax_base,
    rate,
    due,

    pub fn segment(self: ScheduleField) []const u8 {
        return switch (self) {
            .atc => "atc",
            .tax_base => "tax_base",
            .rate => "rate",
            .due => "due",
        };
    }

    pub fn provenance(self: ScheduleField) []const u8 {
        return switch (self) {
            .rate => "external_policy",
            .due => "derived",
            .atc, .tax_base => "transaction",
        };
    }

    pub fn derived(self: ScheduleField) bool {
        return self == .due;
    }
};

const ScheduleFieldRef = struct {
    row_id: ScheduleRowId,
    schedule_field: ScheduleField,
};

const ResolvedPersistedField = union(enum) {
    scalar: PersistedField,
    schedule: ScheduleFieldRef,

    fn ordinal(self: ResolvedPersistedField) usize {
        return switch (self) {
            .scalar => |value| @intFromEnum(value),
            .schedule => |value| std.meta.fields(PersistedField).len +
                value.row_id.index() *
                    std.meta.fields(ScheduleField).len +
                @intFromEnum(value.schedule_field),
        };
    }

    fn provenance(self: ResolvedPersistedField) []const u8 {
        return switch (self) {
            .scalar => |value| value.provenance(),
            .schedule => |value| value.schedule_field.provenance(),
        };
    }

    fn derived(self: ResolvedPersistedField) bool {
        return switch (self) {
            .scalar => |value| value.derived(),
            .schedule => |value| value.schedule_field.derived(),
        };
    }
};

comptime {
    if (std.meta.fields(PersistedField).len +
        max_schedule_rows * std.meta.fields(ScheduleField).len +
        filing_contact_field_count !=
        max_draft_values)
    {
        @compileError(
            "max_draft_values must cover scalar, repeated, and filing-specific 2551Q fields",
        );
    }
}

pub fn writeScheduleFieldId(
    row_id: ScheduleRowId,
    schedule_field: ScheduleField,
    output: []u8,
) error{NoSpaceLeft}![]const u8 {
    return std.fmt.bufPrint(
        output,
        "2551Q.2018-01-ENCS.schedule.{s}.{s}",
        .{ row_id.stableKey(), schedule_field.segment() },
    );
}

fn DisplayText(comptime capacity: usize) type {
    return struct {
        storage: [capacity]u8 = undefined,
        len: usize = 0,

        fn clear(self: *@This()) void {
            self.len = 0;
        }

        fn set(self: *@This(), value: []const u8) void {
            const count = @min(value.len, capacity);
            @memcpy(self.storage[0..count], value[0..count]);
            self.len = count;
        }

        pub fn text(self: *const @This()) []const u8 {
            return self.storage[0..self.len];
        }
    };
}

pub const ScheduleRowState = struct {
    id: ScheduleRowId,
    atc: canvas.TextBuffer(16) = .{},
    tax_base: canvas.TextBuffer(32) = .{},
    rate: canvas.TextBuffer(8) = .{},
    due_display: DisplayText(40) = .{},

    pub fn isEmpty(self: *const ScheduleRowState) bool {
        return trimmed(self.atc.text()).len == 0 and
            trimmed(self.tax_base.text()).len == 0 and
            trimmed(self.rate.text()).len == 0;
    }
};

const default_schedule_rows = [max_schedule_rows]ScheduleRowState{
    .{ .id = .line_1 },
    .{ .id = .line_2 },
};

pub const DraftValueSet = struct {
    writes: [max_draft_values]store_module.DraftValueWrite = undefined,
    field_id_storage: [max_draft_values][max_persisted_field_id_len]u8 = undefined,
    value_storage: [max_draft_values][max_persisted_value_len]u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const DraftValueSet) []const store_module.DraftValueWrite {
        return self.writes[0..self.len];
    }

    fn reset(self: *DraftValueSet) void {
        self.len = 0;
    }

    fn append(
        self: *DraftValueSet,
        persisted_field: PersistedField,
        value: []const u8,
    ) Error!void {
        return self.appendRaw(
            persisted_field.id(),
            value,
            persisted_field.provenance(),
        );
    }

    fn appendSchedule(
        self: *DraftValueSet,
        row_id: ScheduleRowId,
        schedule_field: ScheduleField,
        value: []const u8,
    ) Error!void {
        var field_id: [max_persisted_field_id_len]u8 = undefined;
        return self.appendRaw(
            try writeScheduleFieldId(row_id, schedule_field, &field_id),
            value,
            schedule_field.provenance(),
        );
    }

    fn appendRaw(
        self: *DraftValueSet,
        field_id: []const u8,
        value: []const u8,
        provenance: []const u8,
    ) Error!void {
        if (self.len >= self.writes.len) return error.OutputTooSmall;
        if (field_id.len > max_persisted_field_id_len) {
            return error.FieldTooLong;
        }
        if (value.len > max_persisted_value_len) return error.FieldTooLong;
        const index = self.len;
        @memcpy(
            self.field_id_storage[index][0..field_id.len],
            field_id,
        );
        @memcpy(self.value_storage[index][0..value.len], value);
        self.writes[index] = .{
            .field_id = self.field_id_storage[index][0..field_id.len],
            .value_text = self.value_storage[index][0..value.len],
            .provenance = provenance,
        };
        self.len += 1;
    }
};

pub const Calculation = struct {
    schedule_line_due: [max_schedule_rows]Money,
    total_percentage_tax_due: Money,
    total_credits: Money,
    tax_payable_or_overpayment: Money,
    total_additions: Money,
    total_amount_payable: Money,
};

pub const State = struct {
    context: ?field.Quarter = null,
    editable: bool = true,
    period_basis: ?form_2551q.TaxablePeriodBasis = null,
    tax_relief: TaxReliefChoice = .none,
    income_tax_rate_election: ?form_2551q.IncomeTaxRateElection = null,
    overpayment_disposition: form_2551q.OverpaymentDisposition =
        .not_applicable,

    year_end_month: canvas.TextBuffer(2) = .{},
    sheets_attached: canvas.TextBuffer(5) = .{},
    tax_relief_reference: canvas.TextBuffer(160) = .{},
    schedule_rows: [max_schedule_rows]ScheduleRowState =
        default_schedule_rows,
    creditable_percentage_tax_withheld: canvas.TextBuffer(32) = .{},
    paid_in_previous_return: canvas.TextBuffer(32) = .{},
    other_credit_or_payment: canvas.TextBuffer(32) = .{},
    surcharge: canvas.TextBuffer(32) = .{},
    interest: canvas.TextBuffer(32) = .{},
    compromise: canvas.TextBuffer(32) = .{},

    /// Contact details this filing states differently from the taxpayer's
    /// profile. They belong to the filing, so they persist with the draft's
    /// transaction values and never touch the immutable snapshot the draft was
    /// composed from - which is exactly what lets the profile value be
    /// restored later.
    contact_overrides: [filing_contact_field_count]canvas.TextBuffer(255) =
        [_]canvas.TextBuffer(255){.{}} ** filing_contact_field_count,
    contact_overridden: [filing_contact_field_count]bool =
        [_]bool{false} ** filing_contact_field_count,

    total_due_display: DisplayText(40) = .{},
    total_credits_display: DisplayText(40) = .{},
    net_tax_display: DisplayText(40) = .{},
    total_amount_payable_display: DisplayText(40) = .{},
    validation_display: DisplayText(192) = .{},
    input_was_truncated: bool = false,

    pub fn reset(self: *State, tax_year: u16, quarter: u8) Error!void {
        const filing_quarter = field.Quarter.init(tax_year, quarter) catch
            return error.InvalidPeriodContext;
        self.* = .{ .context = filing_quarter };
        self.refresh();
    }

    pub fn loadFromDraft(
        self: *State,
        draft: *const store_module.OwnedDraft,
    ) Error!void {
        if (!std.mem.eql(
            u8,
            draft.form_code,
            form_2551q.revision.code.asSlice(),
        ) or !std.mem.eql(
            u8,
            draft.form_revision,
            form_2551q.revision.revision.asSlice(),
        )) {
            return error.InvalidStoredForm;
        }
        if (!std.mem.eql(u8, draft.intent, "original") or
            draft.amendment_of != null)
        {
            return error.InvalidDraftIntent;
        }
        const period = try parsePeriodKey(draft.period_key);
        try self.reset(period.year, period.number);
        if (!validDraftLifecycle(draft.lifecycle)) {
            return error.InvalidDraftLifecycle;
        }
        self.editable = std.mem.eql(u8, draft.lifecycle, "editing");

        var seen: u32 = 0;
        self.useProfileContactValues();
        for (draft.values) |*stored| {
            // A filing-specific contact value is not one of the transaction
            // fields; its provenance says so, and it is restored to the
            // override it was rather than to the taxpayer's own details.
            if (std.mem.eql(u8, stored.provenance, filing_override_provenance)) {
                const contact_field = resolveContactTarget(stored.field_id) orelse
                    return error.InvalidDraftValue;
                const index = @intFromEnum(contact_field);
                if (self.contact_overridden[index]) {
                    return error.DuplicateDraftField;
                }
                self.contact_overrides[index].set(stored.value_text);
                self.contact_overridden[index] = true;
                continue;
            }
            const persisted_field = resolveFieldId(stored.field_id) orelse
                return error.InvalidDraftValue;
            const mask = @as(u32, 1) <<
                @as(u5, @intCast(persisted_field.ordinal()));
            if (seen & mask != 0) return error.DuplicateDraftField;
            seen |= mask;
            if (!std.mem.eql(
                u8,
                stored.provenance,
                persisted_field.provenance(),
            )) {
                return error.InvalidDraftProvenance;
            }
            switch (persisted_field) {
                .scalar => |value| try self.loadValue(
                    value,
                    stored.value_text,
                ),
                .schedule => |value| try self.loadScheduleValue(
                    value,
                    stored.value_text,
                ),
            }
        }
        self.refresh();

        if (draft.values.len == 0) {
            // Profile-only drafts created before filing-input persistence
            // remain resumable with empty controlled filing values.
            return;
        }

        var canonical: DraftValueSet = .{};
        const expected = try self.draftValueWrites(&canonical);
        if (draft.values.len != expected.len) {
            return error.InvalidDraftValue;
        }
        for (expected) |*expected_value| {
            const stored = findStoredValue(
                draft.values,
                expected_value.field_id,
            ) orelse return error.InvalidDraftValue;
            if (!std.mem.eql(
                u8,
                stored.value_text,
                expected_value.value_text,
            )) {
                const persisted_field =
                    resolveFieldId(expected_value.field_id) orelse
                    unreachable;
                return if (persisted_field.derived())
                    error.InvalidDraftDerivedValue
                else
                    error.InvalidDraftValue;
            }
        }
    }

    /// Clears any partially hydrated values and makes a failed resume
    /// visibly non-editable. Callers must not fall back to a fresh state for
    /// a malformed nonempty persisted draft.
    pub fn blockForLoadFailure(self: *State, load_error: anyerror) void {
        self.* = .{ .editable = false };
        self.validation_display.set(switch (load_error) {
            error.InvalidDraftDerivedValue,
            error.InvalidDraftIntent,
            error.InvalidDraftLifecycle,
            error.InvalidDraftProvenance,
            error.InvalidDraftValue,
            error.DuplicateDraftField,
            => "Stored 2551Q filing values failed integrity checks. Saving is blocked; repair or discard the persisted draft.",
            error.InvalidStoredForm,
            error.InvalidPeriodContext,
            => "The stored draft does not belong to this 2551Q filing period. Saving is blocked.",
            else => "The 2551Q filing values could not be resumed safely. Saving is blocked.",
        });
    }

    pub fn setPeriodBasis(
        self: *State,
        value: form_2551q.TaxablePeriodBasis,
    ) void {
        if (!self.editable) return;
        self.period_basis = value;
        self.refresh();
    }

    pub fn setTaxRelief(self: *State, value: TaxReliefChoice) void {
        if (!self.editable) return;
        self.tax_relief = value;
        if (value == .none) {
            self.tax_relief_reference.clear();
            self.tax_relief_reference.truncated = false;
        }
        self.refresh();
    }

    pub fn setIncomeTaxRateElection(
        self: *State,
        value: form_2551q.IncomeTaxRateElection,
    ) void {
        if (!self.editable) return;
        self.income_tax_rate_election = value;
        self.refresh();
    }

    /// Annual election is owned by the confirmed taxpayer-year revision.
    /// Filing screens may display it, but may not choose a different value.
    pub fn bindIncomeTaxRateElection(
        self: *State,
        value: form_2551q.IncomeTaxRateElection,
    ) void {
        self.income_tax_rate_election = value;
        self.refresh();
    }

    pub fn setOverpaymentDisposition(
        self: *State,
        value: form_2551q.OverpaymentDisposition,
    ) void {
        if (!self.editable) return;
        self.overpayment_disposition = value;
        self.refresh();
    }

    pub fn editYearEndMonth(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        self.year_end_month.apply(edit);
        self.afterEdit(self.year_end_month.truncated);
    }

    pub fn editSheetsAttached(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        self.sheets_attached.apply(edit);
        self.afterEdit(self.sheets_attached.truncated);
    }

    pub fn editTaxReliefReference(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        self.tax_relief_reference.apply(edit);
        self.afterEdit(self.tax_relief_reference.truncated);
    }

    pub fn editScheduleAtc(
        self: *State,
        row_index: usize,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        const row = self.scheduleRow(row_index) orelse return;
        row.atc.apply(edit);
        self.afterEdit(row.atc.truncated);
    }

    pub fn editScheduleTaxBase(
        self: *State,
        row_index: usize,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        const row = self.scheduleRow(row_index) orelse return;
        row.tax_base.apply(edit);
        self.afterEdit(row.tax_base.truncated);
    }

    pub fn editScheduleRate(
        self: *State,
        row_index: usize,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        const row = self.scheduleRow(row_index) orelse return;
        row.rate.apply(edit);
        self.afterEdit(row.rate.truncated);
    }

    pub fn editCreditableWithheld(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        self.creditable_percentage_tax_withheld.apply(edit);
        self.afterEdit(self.creditable_percentage_tax_withheld.truncated);
    }

    pub fn editPaidInPreviousReturn(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        self.paid_in_previous_return.apply(edit);
        self.afterEdit(self.paid_in_previous_return.truncated);
    }

    pub fn editOtherCredit(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        self.other_credit_or_payment.apply(edit);
        self.afterEdit(self.other_credit_or_payment.truncated);
    }

    pub fn editSurcharge(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        self.surcharge.apply(edit);
        self.afterEdit(self.surcharge.truncated);
    }

    pub fn editInterest(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        self.interest.apply(edit);
        self.afterEdit(self.interest.truncated);
    }

    pub fn editCompromise(
        self: *State,
        edit: canvas.TextInputEvent,
    ) void {
        if (!self.editable) return;
        self.compromise.apply(edit);
        self.afterEdit(self.compromise.truncated);
    }

    pub fn buildTransaction(
        self: *const State,
        schedule_storage: *[max_schedule_rows]form_2551q.ScheduleLine,
    ) Error!form_2551q.Transaction {
        if (self.input_was_truncated) return error.InputTruncated;
        const quarter = self.context orelse return error.InvalidPeriodContext;
        const period_basis = self.period_basis orelse
            return error.MissingPeriodBasis;
        if (period_basis == .fiscal) {
            return error.UnsupportedFiscalPeriod;
        }
        const year_end_month = try parseRequiredInt(
            u8,
            self.year_end_month.text(),
        );
        if (year_end_month < 1 or year_end_month > 12) {
            return error.InvalidYearEndMonth;
        }
        const sheets_attached = try parseOptionalInt(
            u16,
            self.sheets_attached.text(),
        );
        const tax_relief_value: form_2551q.TaxRelief = switch (self.tax_relief) {
            .none => blk: {
                if (trimmed(self.tax_relief_reference.text()).len != 0) {
                    return error.TaxReliefReferenceNotApplicable;
                }
                break :blk .none;
            },
            .specified => .{
                .specified = field.SourceReference.parse(
                    self.tax_relief_reference.text(),
                ) catch return error.MissingTaxReliefReference,
            },
        };
        const election = self.income_tax_rate_election orelse
            return error.MissingIncomeTaxRateElection;
        const calculation = try self.calculate();
        var schedule_len: usize = 0;
        for (&self.schedule_rows, 0..) |*row, row_index| {
            if (row.isEmpty()) continue;
            schedule_storage[schedule_len] = .{
                .atc = field.Atc.parse(row.atc.text()) catch
                    return error.MissingScheduleAtc,
                .tax_base = try parseRequiredNonNegativeMoney(
                    row.tax_base.text(),
                    error.MissingScheduleTaxBase,
                ),
                .rate = try parseRate(row.rate.text()),
                .percentage_tax_due = calculation.schedule_line_due[row_index],
            };
            schedule_len += 1;
        }
        if (schedule_len == 0) return error.MissingScheduleLine;

        const transaction: form_2551q.Transaction = .{
            .period_basis = period_basis,
            .year_end_month = year_end_month,
            .quarter = quarter,
            .sheets_attached = sheets_attached,
            .tax_relief = tax_relief_value,
            .income_tax_rate_election = election,
            .schedule_lines = schedule_storage[0..schedule_len],
            .total_percentage_tax_due = calculation.total_percentage_tax_due,
            .credits = .{
                .creditable_percentage_tax_withheld = try parseOptionalNonNegativeMoney(
                    self.creditable_percentage_tax_withheld.text(),
                ),
                .paid_in_previous_return = try parseOptionalNonNegativeMoney(
                    self.paid_in_previous_return.text(),
                ),
                .other_credit_or_payment = try parseOptionalNonNegativeMoney(
                    self.other_credit_or_payment.text(),
                ),
            },
            .tax_payable_or_overpayment = calculation.tax_payable_or_overpayment,
            .additions = .{
                .surcharge = try parseOptionalNonNegativeMoney(
                    self.surcharge.text(),
                ),
                .interest = try parseOptionalNonNegativeMoney(
                    self.interest.text(),
                ),
                .compromise = try parseOptionalNonNegativeMoney(
                    self.compromise.text(),
                ),
            },
            .overpayment_disposition = self.overpayment_disposition,
        };
        try transaction.validate();
        return transaction;
    }

    pub fn contactOverridden(
        self: *const State,
        contact_field: FilingContactField,
    ) bool {
        return self.contact_overridden[@intFromEnum(contact_field)];
    }

    pub fn contactOverrideText(
        self: *const State,
        contact_field: FilingContactField,
    ) []const u8 {
        return self.contact_overrides[@intFromEnum(contact_field)].text();
    }

    pub fn overriddenContactCount(self: *const State) usize {
        var count: usize = 0;
        for (self.contact_overridden) |overridden| {
            if (overridden) count += 1;
        }
        return count;
    }

    /// Records a value that applies to this filing only.
    pub fn setContactOverride(
        self: *State,
        contact_field: FilingContactField,
        edit: canvas.TextInputEvent,
    ) void {
        const index = @intFromEnum(contact_field);
        self.contact_overrides[index].apply(edit);
        self.contact_overridden[index] =
            self.contact_overrides[index].text().len != 0;
    }

    /// Drops every filing-specific value, so the form shows what the taxpayer
    /// profile said when this filing was started. The restored value comes
    /// from the draft's own snapshot, never from the live profile, so a
    /// profile revised since then cannot leak into a filing already under way.
    pub fn useProfileContactValues(self: *State) void {
        for (&self.contact_overrides) |*value| value.clear();
        self.contact_overridden = [_]bool{false} ** filing_contact_field_count;
    }

    pub fn draftValueWrites(
        self: *const State,
        output: *DraftValueSet,
    ) Error![]const store_module.DraftValueWrite {
        var schedule: [max_schedule_rows]form_2551q.ScheduleLine = undefined;
        const transaction = try self.buildTransaction(&schedule);
        const calculation = try self.calculate();
        output.reset();

        var small: [32]u8 = undefined;
        try output.append(.period_basis, @tagName(transaction.period_basis));
        try output.append(
            .year_end_month,
            try std.fmt.bufPrint(&small, "{d}", .{transaction.year_end_month}),
        );
        try output.append(
            .taxable_quarter,
            try std.fmt.bufPrint(
                &small,
                "{d}",
                .{transaction.quarter.number},
            ),
        );
        try output.append(
            .taxable_year,
            try std.fmt.bufPrint(&small, "{d}", .{transaction.quarter.year}),
        );
        try output.append(
            .sheets_attached,
            try std.fmt.bufPrint(
                &small,
                "{d}",
                .{transaction.sheets_attached},
            ),
        );
        try output.append(.return_option, "original");
        try output.append(.amended_return, "false");
        try output.append(.tax_relief, @tagName(transaction.tax_relief));
        try output.append(
            .tax_relief_reference,
            switch (transaction.tax_relief) {
                .none => "",
                .specified => |reference| reference.asSlice(),
            },
        );
        try output.append(
            .income_tax_rate_election,
            @tagName(transaction.income_tax_rate_election),
        );
        var packed_line_index: usize = 0;
        for (&self.schedule_rows) |*row| {
            if (row.isEmpty()) continue;
            const line = transaction.schedule_lines[packed_line_index];
            try output.appendSchedule(
                row.id,
                .atc,
                line.atc.asSlice(),
            );
            try appendScheduleMoney(
                output,
                row.id,
                .tax_base,
                line.tax_base,
            );
            try output.appendSchedule(
                row.id,
                .rate,
                try writeRate(line.rate, &small),
            );
            try appendScheduleMoney(
                output,
                row.id,
                .due,
                line.percentage_tax_due,
            );
            packed_line_index += 1;
        }
        try appendMoney(
            output,
            .total_percentage_tax_due,
            transaction.total_percentage_tax_due,
        );
        try appendMoney(
            output,
            .creditable_percentage_tax_withheld,
            transaction.credits.creditable_percentage_tax_withheld,
        );
        try appendMoney(
            output,
            .paid_in_previous_return,
            transaction.credits.paid_in_previous_return,
        );
        try appendMoney(
            output,
            .other_credit_or_payment,
            transaction.credits.other_credit_or_payment,
        );
        try appendMoney(
            output,
            .total_tax_credits_or_payments,
            calculation.total_credits,
        );
        try appendMoney(
            output,
            .tax_payable_or_overpayment,
            transaction.tax_payable_or_overpayment,
        );
        try appendMoney(output, .surcharge, transaction.additions.surcharge);
        try appendMoney(output, .interest, transaction.additions.interest);
        try appendMoney(output, .compromise, transaction.additions.compromise);
        try output.append(
            .overpayment_disposition,
            @tagName(transaction.overpayment_disposition),
        );
        // Filing-specific contact values ride with the draft's transaction
        // values and carry their own provenance, so resuming knows they came
        // from this filing rather than from the taxpayer.
        for (std.meta.tags(FilingContactField)) |contact_field| {
            const index = @intFromEnum(contact_field);
            if (!self.contact_overridden[index]) continue;
            const value = self.contact_overrides[index].text();
            if (value.len == 0) continue;
            try output.appendRaw(
                contact_field.target(),
                value,
                filing_override_provenance,
            );
        }
        return output.slice();
    }

    pub fn canBuild(self: *const State) bool {
        var schedule: [max_schedule_rows]form_2551q.ScheduleLine = undefined;
        _ = self.buildTransaction(&schedule) catch return false;
        return self.editable;
    }

    pub fn periodBasisText(self: *const State) []const u8 {
        return if (self.period_basis) |value| switch (value) {
            .calendar => "Calendar",
            .fiscal => "Fiscal",
        } else "";
    }

    pub fn periodCalendarSelected(self: *const State) bool {
        return self.period_basis == .calendar;
    }

    pub fn periodFiscalSelected(self: *const State) bool {
        return self.period_basis == .fiscal;
    }

    pub fn quarterText(
        self: *const State,
        arena: std.mem.Allocator,
    ) []const u8 {
        const quarter = self.context orelse return "";
        return std.fmt.allocPrint(arena, "Q{d}", .{quarter.number}) catch "";
    }

    pub fn yearText(
        self: *const State,
        arena: std.mem.Allocator,
    ) []const u8 {
        const quarter = self.context orelse return "";
        return std.fmt.allocPrint(arena, "{d}", .{quarter.year}) catch "";
    }

    pub fn returnOptionText(_: *const State) []const u8 {
        return "Original";
    }

    pub fn amendedReturnText(_: *const State) []const u8 {
        return "No";
    }

    pub fn taxReliefText(self: *const State) []const u8 {
        return switch (self.tax_relief) {
            .none => "No",
            .specified => "Specified",
        };
    }

    pub fn taxReliefNoneSelected(self: *const State) bool {
        return self.tax_relief == .none;
    }

    pub fn taxReliefSpecifiedSelected(self: *const State) bool {
        return self.tax_relief == .specified;
    }

    pub fn incomeTaxRateElectionText(self: *const State) []const u8 {
        return if (self.income_tax_rate_election) |value| switch (value) {
            .graduated => "Graduated",
            .eight_percent => "8 percent",
        } else "";
    }

    pub fn graduatedElectionSelected(self: *const State) bool {
        return self.income_tax_rate_election == .graduated;
    }

    pub fn eightPercentElectionSelected(self: *const State) bool {
        return self.income_tax_rate_election == .eight_percent;
    }

    pub fn dispositionText(self: *const State) []const u8 {
        return switch (self.overpayment_disposition) {
            .not_applicable => "Not applicable",
            .refund => "Refund",
            .tax_credit_certificate => "Tax credit certificate",
            .carry_over => "Carry over",
        };
    }

    pub fn dispositionSelected(
        self: *const State,
        value: form_2551q.OverpaymentDisposition,
    ) bool {
        return self.overpayment_disposition == value;
    }

    pub fn scheduleRowId(self: *const State, row_index: usize) ?ScheduleRowId {
        if (row_index >= self.schedule_rows.len) return null;
        return self.schedule_rows[row_index].id;
    }

    pub fn scheduleAtcText(
        self: *const State,
        row_index: usize,
    ) []const u8 {
        if (row_index >= self.schedule_rows.len) return "";
        return self.schedule_rows[row_index].atc.text();
    }

    pub fn scheduleTaxBaseText(
        self: *const State,
        row_index: usize,
    ) []const u8 {
        if (row_index >= self.schedule_rows.len) return "";
        return self.schedule_rows[row_index].tax_base.text();
    }

    pub fn scheduleRateText(
        self: *const State,
        row_index: usize,
    ) []const u8 {
        if (row_index >= self.schedule_rows.len) return "";
        return self.schedule_rows[row_index].rate.text();
    }

    pub fn scheduleDueText(
        self: *const State,
        row_index: usize,
    ) []const u8 {
        if (row_index >= self.schedule_rows.len) return "";
        return self.schedule_rows[row_index].due_display.text();
    }

    pub fn lineDueText(self: *const State) []const u8 {
        return self.scheduleDueText(0);
    }

    pub fn totalDueText(self: *const State) []const u8 {
        return self.total_due_display.text();
    }

    pub fn totalCreditsText(self: *const State) []const u8 {
        return self.total_credits_display.text();
    }

    pub fn netTaxText(self: *const State) []const u8 {
        return self.net_tax_display.text();
    }

    pub fn totalAmountPayableText(self: *const State) []const u8 {
        return self.total_amount_payable_display.text();
    }

    pub fn validationText(self: *const State) []const u8 {
        return self.validation_display.text();
    }

    fn scheduleRow(
        self: *State,
        row_index: usize,
    ) ?*ScheduleRowState {
        if (row_index >= self.schedule_rows.len) return null;
        return &self.schedule_rows[row_index];
    }

    fn afterEdit(self: *State, truncated_input: bool) void {
        _ = truncated_input;
        self.refresh();
    }

    fn refresh(self: *State) void {
        self.recomputeInputTruncation();
        for (&self.schedule_rows) |*row| row.due_display.clear();
        self.total_due_display.clear();
        self.total_credits_display.clear();
        self.net_tax_display.clear();
        self.total_amount_payable_display.clear();

        if (self.calculate()) |calculation| {
            for (&self.schedule_rows, 0..) |*row, row_index| {
                if (row.isEmpty()) continue;
                setMoneyDisplay(
                    &row.due_display,
                    calculation.schedule_line_due[row_index],
                );
            }
            setMoneyDisplay(
                &self.total_due_display,
                calculation.total_percentage_tax_due,
            );
            setMoneyDisplay(
                &self.total_credits_display,
                calculation.total_credits,
            );
            setMoneyDisplay(
                &self.net_tax_display,
                calculation.tax_payable_or_overpayment,
            );
            setMoneyDisplay(
                &self.total_amount_payable_display,
                calculation.total_amount_payable,
            );
        } else |_| {}

        var schedule: [max_schedule_rows]form_2551q.ScheduleLine = undefined;
        if (self.buildTransaction(&schedule)) |_| {
            self.validation_display.set(
                if (self.editable)
                    "Filing inputs are valid. Save will persist their typed values and provenance."
                else
                    "This persisted draft is read-only at its current lifecycle stage.",
            );
        } else |err| {
            self.validation_display.set(validationMessage(err));
        }
    }

    fn recomputeInputTruncation(self: *State) void {
        var truncated_input =
            self.year_end_month.truncated or
            self.sheets_attached.truncated or
            self.tax_relief_reference.truncated or
            self.creditable_percentage_tax_withheld.truncated or
            self.paid_in_previous_return.truncated or
            self.other_credit_or_payment.truncated or
            self.surcharge.truncated or
            self.interest.truncated or
            self.compromise.truncated;
        for (&self.schedule_rows) |*row| {
            truncated_input = truncated_input or
                row.atc.truncated or
                row.tax_base.truncated or
                row.rate.truncated;
        }
        self.input_was_truncated = truncated_input;
    }

    fn calculate(self: *const State) Error!Calculation {
        var line_due = [_]Money{Money.zero} ** max_schedule_rows;
        var total_due = Money.zero;
        var schedule_len: usize = 0;
        for (&self.schedule_rows, 0..) |*row, row_index| {
            if (row.isEmpty()) continue;
            const tax_base = try parseRequiredNonNegativeMoney(
                row.tax_base.text(),
                error.MissingScheduleTaxBase,
            );
            const rate = try parseRate(row.rate.text());
            line_due[row_index] = try tax_base.checkedRatio(
                rate.basis_points,
                10_000,
            );
            total_due = try total_due.checkedAdd(line_due[row_index]);
            schedule_len += 1;
        }
        if (schedule_len == 0) return error.MissingScheduleLine;
        const creditable = try parseOptionalNonNegativeMoney(
            self.creditable_percentage_tax_withheld.text(),
        );
        const previous = try parseOptionalNonNegativeMoney(
            self.paid_in_previous_return.text(),
        );
        const other_credit = try parseOptionalNonNegativeMoney(
            self.other_credit_or_payment.text(),
        );
        const total_credits = try (try creditable.checkedAdd(previous))
            .checkedAdd(other_credit);
        const net = try total_due.checkedSub(total_credits);
        const surcharge_value = try parseOptionalNonNegativeMoney(
            self.surcharge.text(),
        );
        const interest_value = try parseOptionalNonNegativeMoney(
            self.interest.text(),
        );
        const compromise_value = try parseOptionalNonNegativeMoney(
            self.compromise.text(),
        );
        const additions = try (try surcharge_value.checkedAdd(interest_value))
            .checkedAdd(compromise_value);
        return .{
            .schedule_line_due = line_due,
            .total_percentage_tax_due = total_due,
            .total_credits = total_credits,
            .tax_payable_or_overpayment = net,
            .total_additions = additions,
            .total_amount_payable = try net.checkedAdd(additions),
        };
    }

    fn loadValue(
        self: *State,
        persisted_field: PersistedField,
        raw: []const u8,
    ) Error!void {
        switch (persisted_field) {
            .period_basis => self.period_basis =
                std.meta.stringToEnum(
                    form_2551q.TaxablePeriodBasis,
                    raw,
                ) orelse return error.InvalidDraftValue,
            .year_end_month => try setBuffer(&self.year_end_month, raw),
            .taxable_quarter => {
                const context = self.context orelse
                    return error.InvalidPeriodContext;
                if ((std.fmt.parseInt(u8, raw, 10) catch
                    return error.InvalidDraftValue) != context.number)
                {
                    return error.InvalidPeriodContext;
                }
            },
            .taxable_year => {
                const context = self.context orelse
                    return error.InvalidPeriodContext;
                if ((std.fmt.parseInt(u16, raw, 10) catch
                    return error.InvalidDraftValue) != context.year)
                {
                    return error.InvalidPeriodContext;
                }
            },
            .sheets_attached => try setBuffer(&self.sheets_attached, raw),
            .return_option => if (!std.mem.eql(u8, raw, "original"))
                return error.InvalidDraftValue,
            .amended_return => if (!std.mem.eql(u8, raw, "false"))
                return error.InvalidDraftValue,
            .tax_relief => self.tax_relief =
                std.meta.stringToEnum(TaxReliefChoice, raw) orelse
                return error.InvalidDraftValue,
            .tax_relief_reference => try setBuffer(
                &self.tax_relief_reference,
                raw,
            ),
            .income_tax_rate_election => self.income_tax_rate_election =
                std.meta.stringToEnum(
                    form_2551q.IncomeTaxRateElection,
                    raw,
                ) orelse return error.InvalidDraftValue,
            .creditable_percentage_tax_withheld => try setBuffer(
                &self.creditable_percentage_tax_withheld,
                raw,
            ),
            .paid_in_previous_return => try setBuffer(
                &self.paid_in_previous_return,
                raw,
            ),
            .other_credit_or_payment => try setBuffer(
                &self.other_credit_or_payment,
                raw,
            ),
            .surcharge => try setBuffer(&self.surcharge, raw),
            .interest => try setBuffer(&self.interest, raw),
            .compromise => try setBuffer(&self.compromise, raw),
            .overpayment_disposition => self.overpayment_disposition =
                std.meta.stringToEnum(
                    form_2551q.OverpaymentDisposition,
                    raw,
                ) orelse return error.InvalidDraftValue,
            .total_percentage_tax_due,
            .total_tax_credits_or_payments,
            .tax_payable_or_overpayment,
            => {},
        }
    }

    fn loadScheduleValue(
        self: *State,
        persisted: ScheduleFieldRef,
        raw: []const u8,
    ) Error!void {
        const row = &self.schedule_rows[persisted.row_id.index()];
        switch (persisted.schedule_field) {
            .atc => try setBuffer(&row.atc, raw),
            .tax_base => try setBuffer(&row.tax_base, raw),
            .rate => try setBuffer(&row.rate, raw),
            .due => {},
        }
    }
};

fn parsePeriodKey(raw: []const u8) Error!field.Quarter {
    if (raw.len != 7 or raw[4] != '-' or raw[5] != 'Q') {
        return error.InvalidPeriodContext;
    }
    const year = std.fmt.parseInt(u16, raw[0..4], 10) catch
        return error.InvalidPeriodContext;
    const quarter = std.fmt.parseInt(u8, raw[6..7], 10) catch
        return error.InvalidPeriodContext;
    return field.Quarter.init(year, quarter) catch
        return error.InvalidPeriodContext;
}

fn fieldFromId(raw: []const u8) ?PersistedField {
    inline for (std.meta.fields(PersistedField)) |enum_field| {
        const value: PersistedField = @enumFromInt(enum_field.value);
        if (std.mem.eql(u8, raw, value.id())) return value;
    }
    return null;
}

fn resolveFieldId(raw: []const u8) ?ResolvedPersistedField {
    if (fieldFromId(raw)) |persisted_field| {
        return .{ .scalar = persisted_field };
    }
    inline for (std.meta.fields(ScheduleRowId)) |row_enum_field| {
        const row_id: ScheduleRowId =
            @enumFromInt(row_enum_field.value);
        inline for (std.meta.fields(ScheduleField)) |schedule_enum_field| {
            const schedule_field: ScheduleField =
                @enumFromInt(schedule_enum_field.value);
            var expected: [max_persisted_field_id_len]u8 = undefined;
            const expected_id = writeScheduleFieldId(
                row_id,
                schedule_field,
                &expected,
            ) catch unreachable;
            if (std.mem.eql(u8, raw, expected_id)) {
                return .{ .schedule = .{
                    .row_id = row_id,
                    .schedule_field = schedule_field,
                } };
            }
        }
    }
    return null;
}

fn findWrite(
    writes: []const store_module.DraftValueWrite,
    field_id: []const u8,
) ?*const store_module.DraftValueWrite {
    for (writes) |*write| {
        if (std.mem.eql(u8, write.field_id, field_id)) return write;
    }
    return null;
}

fn findStoredValue(
    values: []const store_module.OwnedDraftValue,
    field_id: []const u8,
) ?*const store_module.OwnedDraftValue {
    for (values) |*value| {
        if (std.mem.eql(u8, value.field_id, field_id)) return value;
    }
    return null;
}

fn validDraftLifecycle(value: []const u8) bool {
    const allowed = [_][]const u8{
        "editing",
        "prepared",
        "queued",
        "submitted",
        "confirmed",
        "paid",
        "cancelled",
    };
    for (allowed) |candidate| {
        if (std.mem.eql(u8, value, candidate)) return true;
    }
    return false;
}

fn appendMoney(
    output: *DraftValueSet,
    persisted_field: PersistedField,
    value: Money,
) Error!void {
    var buffer: [32]u8 = undefined;
    try output.append(
        persisted_field,
        value.write(&buffer) catch return error.OutputTooSmall,
    );
}

fn appendScheduleMoney(
    output: *DraftValueSet,
    row_id: ScheduleRowId,
    schedule_field: ScheduleField,
    value: Money,
) Error!void {
    var buffer: [32]u8 = undefined;
    try output.appendSchedule(
        row_id,
        schedule_field,
        value.write(&buffer) catch return error.OutputTooSmall,
    );
}

fn writeRate(
    rate: form_2551q.TaxRate,
    output: []u8,
) error{NoSpaceLeft}![]const u8 {
    return std.fmt.bufPrint(
        output,
        "{d}.{d:0>2}",
        .{ rate.basis_points / 100, rate.basis_points % 100 },
    );
}

fn parseRate(raw: []const u8) Error!form_2551q.TaxRate {
    var value = trimmed(raw);
    if (value.len == 0) return error.MissingExternalRate;
    if (value[value.len - 1] == '%') {
        value = trimmed(value[0 .. value.len - 1]);
    }
    if (value.len == 0 or value[0] == '-' or value[0] == '+') {
        return error.InvalidTaxRate;
    }

    const decimal = std.mem.indexOfScalar(u8, value, '.');
    const whole_text = if (decimal) |index| value[0..index] else value;
    const fraction_text = if (decimal) |index| value[index + 1 ..] else "";
    if (whole_text.len == 0 or fraction_text.len > 2) {
        return error.InvalidTaxRate;
    }
    const whole = std.fmt.parseInt(u16, whole_text, 10) catch
        return error.InvalidTaxRate;
    var fraction: u16 = 0;
    if (fraction_text.len != 0) {
        fraction = std.fmt.parseInt(u16, fraction_text, 10) catch
            return error.InvalidTaxRate;
        if (fraction_text.len == 1) fraction *= 10;
    }
    const basis_points = std.math.mul(u16, whole, 100) catch
        return error.InvalidTaxRate;
    return form_2551q.TaxRate.init(
        std.math.add(u16, basis_points, fraction) catch
            return error.InvalidTaxRate,
    );
}

fn parseRequiredInt(
    comptime T: type,
    raw: []const u8,
) Error!T {
    const value = trimmed(raw);
    if (value.len == 0) return error.InvalidDraftValue;
    return std.fmt.parseInt(T, value, 10) catch error.InvalidDraftValue;
}

fn parseOptionalInt(
    comptime T: type,
    raw: []const u8,
) Error!T {
    const value = trimmed(raw);
    if (value.len == 0) return 0;
    return std.fmt.parseInt(T, value, 10) catch error.InvalidDraftValue;
}

fn parseRequiredNonNegativeMoney(
    raw: []const u8,
    missing: Error,
) Error!Money {
    if (trimmed(raw).len == 0) return missing;
    const value = try Money.parse(raw);
    if (value.centavos < 0) return error.InvalidMoneySign;
    return value;
}

fn parseOptionalNonNegativeMoney(raw: []const u8) Error!Money {
    if (trimmed(raw).len == 0) return .zero;
    const value = try Money.parse(raw);
    if (value.centavos < 0) return error.InvalidMoneySign;
    return value;
}

fn setBuffer(buffer: anytype, value: []const u8) Error!void {
    if (value.len > buffer.storage.len) return error.FieldTooLong;
    buffer.set(value);
    buffer.truncated = false;
}

fn setMoneyDisplay(display: anytype, value: Money) void {
    var buffer: [40]u8 = undefined;
    display.set(value.write(&buffer) catch "");
}

fn trimmed(raw: []const u8) []const u8 {
    return std.mem.trim(u8, raw, " \t\r\n");
}

fn validationMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidPeriodContext => "Open a valid 2551Q filing quarter.",
        error.MissingPeriodBasis => "Choose Calendar taxable-period basis.",
        error.UnsupportedFiscalPeriod => "Fiscal-quarter profile dates are not supported yet. Choose Calendar so the tax-profile snapshot uses the correct effective date.",
        error.InvalidYearEndMonth, error.InvalidDraftValue => "Enter a valid year-end month and whole-number sheet count.",
        error.MissingIncomeTaxRateElection => "Choose the income-tax-rate election for this filing.",
        error.MissingScheduleAtc => "Enter at least one valid Schedule 1 percentage-tax code.",
        error.MissingScheduleTaxBase => "Enter the Schedule 1 tax base.",
        error.MissingExternalRate => "Enter a current policy-supplied Schedule 1 rate. No rate is assumed.",
        error.InvalidTaxRate => "The policy-supplied rate must be from 0.00 through 100.00 percent.",
        error.MissingTaxReliefReference => "Specified tax relief requires its legal or source reference.",
        error.TaxReliefReferenceNotApplicable => "Clear the tax-relief reference or choose Specified.",
        error.InvalidMoneySign => "Tax base, credits, and additions cannot be negative.",
        error.InvalidOverpaymentDisposition => "Choose a disposition only for an overpayment, and choose one when an overpayment exists.",
        error.InputTruncated, error.FieldTooLong => "One or more filing values exceed the supported length.",
        else => "Review the 2551Q filing values before saving.",
    };
}

fn configuredState() !State {
    var state: State = .{};
    try state.reset(2026, 1);
    state.setPeriodBasis(.calendar);
    state.setIncomeTaxRateElection(.graduated);
    state.year_end_month.set("12");
    state.sheets_attached.set("0");
    state.schedule_rows[0].atc.set("PT010");
    state.schedule_rows[0].tax_base.set("450000.00");
    state.schedule_rows[0].rate.set("3.00");
    state.refresh();
    return state;
}

test "2551Q refuses to invent a percentage-tax rate" {
    var state = try configuredState();
    state.schedule_rows[0].rate.clear();
    state.refresh();
    var schedule: [max_schedule_rows]form_2551q.ScheduleLine = undefined;
    try std.testing.expectError(
        error.MissingExternalRate,
        state.buildTransaction(&schedule),
    );
    try std.testing.expect(!state.canBuild());
}

test "2551Q fails closed for fiscal periods until profile dates support them" {
    var state = try configuredState();
    state.setPeriodBasis(.fiscal);
    var schedule: [max_schedule_rows]form_2551q.ScheduleLine = undefined;
    try std.testing.expectError(
        error.UnsupportedFiscalPeriod,
        state.buildTransaction(&schedule),
    );
    try std.testing.expect(!state.canBuild());
}

test "2551Q over-capacity input can be corrected without reopening" {
    var state = try configuredState();
    state.editScheduleRate(0, .{
        .set_selection = .{ .anchor = 0, .focus = 4 },
    });
    state.editScheduleRate(0, .{
        .insert_text = "12345678901234567890",
    });
    try std.testing.expect(state.input_was_truncated);
    try std.testing.expect(!state.canBuild());

    state.editScheduleRate(0, .{
        .set_selection = .{ .anchor = 0, .focus = 8 },
    });
    state.editScheduleRate(0, .{ .insert_text = "3.00" });
    try std.testing.expect(!state.input_was_truncated);
    try std.testing.expect(state.canBuild());
}

test "2551Q read-only resumed state ignores programmatic mutations" {
    var state = try configuredState();
    state.editable = false;
    state.setPeriodBasis(.fiscal);
    state.editScheduleAtc(0, .clear);
    state.editCreditableWithheld(.{ .insert_text = "500.00" });

    try std.testing.expectEqual(
        form_2551q.TaxablePeriodBasis.calendar,
        state.period_basis.?,
    );
    try std.testing.expectEqualStrings("PT010", state.scheduleAtcText(0));
    try std.testing.expectEqualStrings(
        "",
        state.creditable_percentage_tax_withheld.text(),
    );
    try std.testing.expect(!state.canBuild());
}

test "2551Q load failure clears partial state and blocks saving" {
    var state = try configuredState();
    state.blockForLoadFailure(error.InvalidDraftProvenance);
    state.editScheduleAtc(0, .{ .insert_text = "PT999" });

    try std.testing.expect(!state.editable);
    try std.testing.expectEqualStrings("", state.scheduleAtcText(0));
    try std.testing.expect(!state.canBuild());
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            state.validationText(),
            "Saving is blocked",
        ) != null,
    );
}

test "2551Q builds repeated typed lines and computes due credits and payable" {
    var state = try configuredState();
    state.schedule_rows[1].atc.set("PT020");
    state.schedule_rows[1].tax_base.set("100000.00");
    state.schedule_rows[1].rate.set("1.00");
    state.creditable_percentage_tax_withheld.set("500.00");
    state.paid_in_previous_return.set("250.00");
    state.other_credit_or_payment.set("100.00");
    state.surcharge.set("50.00");
    state.interest.set("25.00");
    state.refresh();

    var schedule: [max_schedule_rows]form_2551q.ScheduleLine = undefined;
    const transaction = try state.buildTransaction(&schedule);
    try std.testing.expectEqual(@as(usize, 2), transaction.schedule_lines.len);
    try std.testing.expectEqualStrings(
        "PT010",
        transaction.schedule_lines[0].atc.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "PT020",
        transaction.schedule_lines[1].atc.asSlice(),
    );
    try std.testing.expectEqual(@as(u16, 300), schedule[0].rate.basis_points);
    try std.testing.expectEqual(@as(u16, 100), schedule[1].rate.basis_points);
    try std.testing.expectEqual(
        @as(i64, 1_350_000),
        schedule[0].percentage_tax_due.centavos,
    );
    try std.testing.expectEqual(
        @as(i64, 1_365_000),
        transaction.tax_payable_or_overpayment.centavos,
    );
    try std.testing.expectEqualStrings("13500.00", state.lineDueText());
    try std.testing.expectEqualStrings("1000.00", state.scheduleDueText(1));
    try std.testing.expectEqualStrings(
        "13650.00",
        state.netTaxText(),
    );
    try std.testing.expectEqualStrings(
        "13725.00",
        state.totalAmountPayableText(),
    );
}

test "2551Q overpayment requires an applicable disposition" {
    var state = try configuredState();
    state.creditable_percentage_tax_withheld.set("14000.00");
    state.refresh();
    var schedule: [max_schedule_rows]form_2551q.ScheduleLine = undefined;
    try std.testing.expectError(
        error.InvalidOverpaymentDisposition,
        state.buildTransaction(&schedule),
    );

    state.setOverpaymentDisposition(.refund);
    const transaction = try state.buildTransaction(&schedule);
    try std.testing.expectEqual(
        form_2551q.OverpaymentDisposition.refund,
        transaction.overpayment_disposition,
    );
    try std.testing.expectEqual(
        @as(i64, -50_000),
        transaction.tax_payable_or_overpayment.centavos,
    );
}

test "draft writes preserve source categories and resume all source values" {
    var source = try configuredState();
    source.setTaxRelief(.specified);
    source.tax_relief_reference.set("RA-TEST-2026");
    source.creditable_percentage_tax_withheld.set("500.00");
    source.surcharge.set("25.00");
    source.schedule_rows[1].atc.set("PT020");
    source.schedule_rows[1].tax_base.set("100000.00");
    source.schedule_rows[1].rate.set("1.00");
    source.refresh();

    var persisted: DraftValueSet = .{};
    const writes = try source.draftValueWrites(&persisted);
    // Every transaction field is written; the filing-specific contact slots
    // stay empty until this filing actually states one.
    try std.testing.expectEqual(
        @as(usize, max_draft_values - filing_contact_field_count),
        writes.len,
    );
    var line_2_rate_id: [max_persisted_field_id_len]u8 = undefined;
    var line_2_due_id: [max_persisted_field_id_len]u8 = undefined;
    try std.testing.expectEqualStrings(
        "external_policy",
        findWrite(
            writes,
            try writeScheduleFieldId(.line_2, .rate, &line_2_rate_id),
        ).?.provenance,
    );
    try std.testing.expectEqualStrings(
        "derived",
        findWrite(
            writes,
            try writeScheduleFieldId(.line_2, .due, &line_2_due_id),
        ).?.provenance,
    );

    var owned_values: [max_draft_values]store_module.OwnedDraftValue =
        undefined;
    for (writes, 0..) |write, index| {
        owned_values[index] = .{
            .field_id = @constCast(write.field_id),
            .value_text = @constCast(write.value_text),
            .provenance = @constCast(write.provenance),
        };
    }
    var empty_bindings: [0]store_module.OwnedRoleBinding = .{};
    var empty_snapshots: [0]store_module.OwnedSnapshotField = .{};
    var draft: store_module.OwnedDraft = .{
        .id = @constCast("draft-resume"),
        .form_code = @constCast("2551Q"),
        .form_revision = @constCast("2018-01-ENCS"),
        .period_key = @constCast("2026-Q1"),
        .profile_as_of = @constCast("2026-03-31"),
        .lifecycle = @constCast("editing"),
        .intent = @constCast("original"),
        .mapping_revision = @constCast("tax-profile-snapshot-v1"),
        .amendment_of = null,
        .bindings = &empty_bindings,
        .snapshots = &empty_snapshots,
        // Only the entries actually written: the array is sized for the
        // maximum, which now includes filing-specific slots this draft has none of.
        .values = owned_values[0..writes.len],
    };

    var resumed: State = .{};
    try resumed.loadFromDraft(&draft);
    try std.testing.expectEqualStrings(
        "RA-TEST-2026",
        resumed.tax_relief_reference.text(),
    );
    try std.testing.expectEqualStrings(
        "500.00",
        resumed.creditable_percentage_tax_withheld.text(),
    );
    try std.testing.expectEqual(
        ScheduleRowId.line_1,
        resumed.scheduleRowId(0).?,
    );
    try std.testing.expectEqual(
        ScheduleRowId.line_2,
        resumed.scheduleRowId(1).?,
    );
    try std.testing.expectEqualStrings(
        "PT010",
        resumed.scheduleAtcText(0),
    );
    try std.testing.expectEqualStrings(
        "PT020",
        resumed.scheduleAtcText(1),
    );
    try std.testing.expectEqualStrings(
        "1.00",
        resumed.scheduleRateText(1),
    );
    try std.testing.expectEqualStrings(
        source.totalAmountPayableText(),
        resumed.totalAmountPayableText(),
    );
}

test "resume rejects a false provenance claim" {
    var rate_id: [max_persisted_field_id_len]u8 = undefined;
    var value: [1]store_module.OwnedDraftValue = .{.{
        .field_id = @constCast(
            try writeScheduleFieldId(.line_1, .rate, &rate_id),
        ),
        .value_text = @constCast("3.00"),
        .provenance = @constCast("transaction"),
    }};
    var empty_bindings: [0]store_module.OwnedRoleBinding = .{};
    var empty_snapshots: [0]store_module.OwnedSnapshotField = .{};
    var draft: store_module.OwnedDraft = .{
        .id = @constCast("draft-invalid-provenance"),
        .form_code = @constCast("2551Q"),
        .form_revision = @constCast("2018-01-ENCS"),
        .period_key = @constCast("2026-Q1"),
        .profile_as_of = @constCast("2026-03-31"),
        .lifecycle = @constCast("editing"),
        .intent = @constCast("original"),
        .mapping_revision = @constCast("tax-profile-snapshot-v1"),
        .amendment_of = null,
        .bindings = &empty_bindings,
        .snapshots = &empty_snapshots,
        .values = &value,
    };

    var state: State = .{};
    try std.testing.expectError(
        error.InvalidDraftProvenance,
        state.loadFromDraft(&draft),
    );
}

test "resume rejects partial nonempty values and unknown lifecycle" {
    var partial_values: [1]store_module.OwnedDraftValue = .{.{
        .field_id = @constCast(PersistedField.period_basis.id()),
        .value_text = @constCast("calendar"),
        .provenance = @constCast("filing_context"),
    }};
    var empty_bindings: [0]store_module.OwnedRoleBinding = .{};
    var empty_snapshots: [0]store_module.OwnedSnapshotField = .{};
    var partial_draft: store_module.OwnedDraft = .{
        .id = @constCast("draft-partial-values"),
        .form_code = @constCast("2551Q"),
        .form_revision = @constCast("2018-01-ENCS"),
        .period_key = @constCast("2026-Q1"),
        .profile_as_of = @constCast("2026-03-31"),
        .lifecycle = @constCast("editing"),
        .intent = @constCast("original"),
        .mapping_revision = @constCast("tax-profile-snapshot-v1"),
        .amendment_of = null,
        .bindings = &empty_bindings,
        .snapshots = &empty_snapshots,
        .values = &partial_values,
    };
    var state: State = .{};
    try std.testing.expectError(
        error.InvalidDraftValue,
        state.loadFromDraft(&partial_draft),
    );

    var empty_values: [0]store_module.OwnedDraftValue = .{};
    var invalid_lifecycle_draft = partial_draft;
    invalid_lifecycle_draft.id = @constCast("draft-invalid-lifecycle");
    invalid_lifecycle_draft.lifecycle = @constCast("preapred");
    invalid_lifecycle_draft.values = &empty_values;
    try std.testing.expectError(
        error.InvalidDraftLifecycle,
        state.loadFromDraft(&invalid_lifecycle_draft),
    );

    var amended_draft = partial_draft;
    amended_draft.id = @constCast("draft-amendment");
    amended_draft.lifecycle = @constCast("editing");
    amended_draft.intent = @constCast("amendment");
    amended_draft.values = &empty_values;
    try std.testing.expectError(
        error.InvalidDraftIntent,
        state.loadFromDraft(&amended_draft),
    );

    amended_draft.intent = @constCast("original");
    amended_draft.amendment_of = @constCast("prior-draft");
    try std.testing.expectError(
        error.InvalidDraftIntent,
        state.loadFromDraft(&amended_draft),
    );
}

test "a contact value changed for one filing survives resume and can be undone" {
    var state = try configuredState();
    state.refresh();

    var clean: DraftValueSet = .{};
    const baseline = try state.draftValueWrites(&clean);
    try std.testing.expectEqual(@as(usize, 0), state.overriddenContactCount());

    // This filing states a different contact number.
    state.setContactOverride(.contact_number, .{ .insert_text = "+639170000000" });
    try std.testing.expect(state.contactOverridden(.contact_number));
    try std.testing.expectEqualStrings(
        "+639170000000",
        state.contactOverrideText(.contact_number),
    );

    var persisted: DraftValueSet = .{};
    const writes = try state.draftValueWrites(&persisted);
    try std.testing.expectEqual(baseline.len + 1, writes.len);
    const stored = findWrite(
        writes,
        FilingContactField.contact_number.target(),
    ).?;
    // The stored value says it belongs to the filing, not to the taxpayer.
    try std.testing.expectEqualStrings(filing_override_provenance, stored.provenance);
    try std.testing.expectEqualStrings("+639170000000", stored.value_text);

    var owned: [max_draft_values]store_module.OwnedDraftValue = undefined;
    for (writes, 0..) |write, index| {
        owned[index] = .{
            .field_id = @constCast(write.field_id),
            .value_text = @constCast(write.value_text),
            .provenance = @constCast(write.provenance),
        };
    }
    var empty_bindings: [0]store_module.OwnedRoleBinding = .{};
    var empty_snapshots: [0]store_module.OwnedSnapshotField = .{};
    var draft: store_module.OwnedDraft = .{
        .id = @constCast("draft-filing-contact"),
        .form_code = @constCast("2551Q"),
        .form_revision = @constCast("2018-01-ENCS"),
        .period_key = @constCast("2026-Q1"),
        .profile_as_of = @constCast("2026-03-31"),
        .lifecycle = @constCast("editing"),
        .intent = @constCast("original"),
        .mapping_revision = @constCast("tax-profile-snapshot-v1"),
        .amendment_of = null,
        .bindings = &empty_bindings,
        .snapshots = &empty_snapshots,
        .values = owned[0..writes.len],
    };

    var resumed: State = .{};
    try resumed.loadFromDraft(&draft);
    try std.testing.expect(resumed.contactOverridden(.contact_number));
    try std.testing.expectEqualStrings(
        "+639170000000",
        resumed.contactOverrideText(.contact_number),
    );
    // Only the detail this filing stated is its own; the rest stay the
    // taxpayer's.
    try std.testing.expectEqual(@as(usize, 1), resumed.overriddenContactCount());
    try std.testing.expect(!resumed.contactOverridden(.registered_address));

    // Undoing it leaves nothing filing-specific behind, so the form falls back
    // to the details the draft was composed from.
    resumed.useProfileContactValues();
    try std.testing.expectEqual(@as(usize, 0), resumed.overriddenContactCount());
    var after: DraftValueSet = .{};
    const restored = try resumed.draftValueWrites(&after);
    try std.testing.expectEqual(baseline.len, restored.len);
}
