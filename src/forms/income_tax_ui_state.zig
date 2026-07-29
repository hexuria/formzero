//! Controlled filing-input state for BIR Form 1701Q (January 2018 ENCS).
//!
//! Profile facts remain owned by `forms/ui_state.zig`. This module owns only
//! filing-context and transaction values. Monetary results that depend on tax
//! policy are explicit inputs: this adapter parses and preserves them, but
//! never selects a rate or calculates income tax due.

const std = @import("std");
const native_sdk = @import("native_sdk");
const Money = @import("../domain/money.zig").Money;
const form = @import("form_1701q.zig");
const store_module = @import("../tax_profile/store.zig");

const canvas = native_sdk.canvas;

pub const max_payment_rows = 4;
pub const max_payment_row_id_len = 32;
pub const max_draft_values = 17 + (max_payment_rows * 4);
pub const max_input_len = 160;
pub const max_notice_len = 255;
const input_count = std.meta.fields(Input).len;

pub const NoticeKind = enum {
    neutral,
    success,
    failure,
};

pub const Election = enum {
    none,
    graduated,
    eight_percent,
};

pub const PaymentMethodChoice = enum {
    none,
    cash,
    check,
    tax_debit_memo,
    other,
};

/// Text inputs have one stable key so `main.zig` can route Native
/// `canvas.TextInputEvent` payloads without reaching into this state.
pub const Input = enum {
    tax_year,
    sheets_attached,
    graduated_sales_revenues_receipts,
    graduated_cost_of_sales_or_services,
    graduated_allowable_deductions,
    graduated_taxable_income,
    graduated_income_tax_due,
    eight_percent_gross_sales_or_receipts,
    eight_percent_non_operating_income,
    eight_percent_tax_due,
    prior_quarter_income_tax_payments,
    creditable_tax_withheld_2307,
    other_tax_credits_or_payments,
    tax_payable_or_overpayment,
    surcharge,
    interest,
    compromise,
};

pub const PaymentInput = enum {
    bank_or_agency,
    reference,
    amount,
};

pub const Error = error{
    DuplicateDraftField,
    DraftInputsLocked,
    ElectionRequired,
    FieldTooLong,
    IncompletePayment,
    InputWasTruncated,
    InvalidBoolean,
    InvalidDraftIntent,
    InvalidPaymentFieldId,
    InvalidQuarter,
    InvalidSheetsAttached,
    InvalidTaxYear,
    MissingValue,
    NegativeAmountNotAllowed,
    TooManyDraftValues,
    TooManyPaymentRows,
    UnknownDraftField,
    UnexpectedDraftProvenance,
    WrongFormRevision,
    WrongPeriodContext,
};

const NoticeText = struct {
    bytes: [max_notice_len]u8 = undefined,
    len: u8 = 0,

    fn set(self: *NoticeText, value_text: []const u8) void {
        const length = @min(value_text.len, self.bytes.len);
        @memcpy(self.bytes[0..length], value_text[0..length]);
        self.len = @intCast(length);
    }

    fn text(self: *const NoticeText) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const PaymentRowId = struct {
    bytes: [max_payment_row_id_len]u8 = undefined,
    len: u8 = 0,

    pub fn parse(raw: []const u8) Error!PaymentRowId {
        const value_text = std.mem.trim(u8, raw, " \t\r\n");
        if (value_text.len == 0 or
            value_text.len > max_payment_row_id_len)
        {
            return error.FieldTooLong;
        }
        for (value_text) |byte| {
            if (!std.ascii.isAlphanumeric(byte) and
                byte != '-' and byte != '_')
            {
                return error.FieldTooLong;
            }
        }
        var result: PaymentRowId = .{};
        @memcpy(result.bytes[0..value_text.len], value_text);
        result.len = @intCast(value_text.len);
        return result;
    }

    pub fn asSlice(self: *const PaymentRowId) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(self: *const PaymentRowId, other: *const PaymentRowId) bool {
        return std.mem.eql(u8, self.asSlice(), other.asSlice());
    }
};

pub const PaymentRow = struct {
    slot: usize,
    stable_id: PaymentRowId,
    method: PaymentMethodChoice = .none,
    bank_or_agency: canvas.TextBuffer(max_input_len) = .{},
    reference: canvas.TextBuffer(max_input_len) = .{},
    amount: canvas.TextBuffer(max_input_len) = .{},
    active: bool = false,

    pub fn idLabel(self: *const PaymentRow) []const u8 {
        return self.stable_id.asSlice();
    }

    pub fn id(self: *const PaymentRow) usize {
        return self.slot;
    }

    pub fn name(self: *const PaymentRow) []const u8 {
        return switch (self.method) {
            .none => "Incomplete payment",
            .cash => "Cash",
            .check => "Check",
            .tax_debit_memo => "Tax Debit Memo",
            .other => "Other",
        };
    }

    pub fn selected(self: *const PaymentRow) bool {
        return self.active;
    }

    pub fn bankOrAgencyText(self: *const PaymentRow) []const u8 {
        return self.bank_or_agency.text();
    }

    pub fn referenceText(self: *const PaymentRow) []const u8 {
        return self.reference.text();
    }

    pub fn amountText(self: *const PaymentRow) []const u8 {
        return self.amount.text();
    }
};

const Parsed = struct {
    period: form.FilingQuarter,
    sheets_attached: u16,
    computation: form.IncomeComputation,
    credits: form.Credits,
    tax_payable_or_overpayment: Money,
    additions: form.Additions,
};

pub const State = struct {
    inputs: [input_count]canvas.TextBuffer(max_input_len) =
        [_]canvas.TextBuffer(max_input_len){.{}} ** input_count,
    selected_quarter: ?u8 = null,
    selected_election: Election = .none,
    amended_return: bool = false,
    inputs_locked: bool = false,
    input_was_truncated: bool = false,

    payment_rows: [max_payment_rows]PaymentRow = undefined,
    payment_row_count: u8 = 0,
    selected_payment_row: ?u8 = null,
    next_payment_row_sequence: u32 = 1,
    payment_storage: [max_payment_rows]form.Payment = undefined,
    draft_writes: [max_draft_values]store_module.DraftValueWrite = undefined,
    draft_field_id_buffers: [max_draft_values][96]u8 = undefined,
    draft_value_buffers: [max_draft_values][max_input_len]u8 = undefined,
    draft_write_len: u8 = 0,

    notice: NoticeText = .{},
    notice_kind: NoticeKind = .neutral,

    pub fn reset(self: *State, tax_year: u16, quarter_number: u8) !void {
        if (tax_year == 0) return error.InvalidTaxYear;
        _ = form.FilingQuarter.init(tax_year, quarter_number) catch
            return error.InvalidQuarter;
        self.* = .{};
        var year_buffer: [4]u8 = undefined;
        const year_text = std.fmt.bufPrint(
            &year_buffer,
            "{d:0>4}",
            .{tax_year},
        ) catch unreachable;
        self.inputs[@intFromEnum(Input.tax_year)].set(year_text);
        self.selected_quarter = quarter_number;
        self.refreshValidationNotice();
    }

    pub fn applyInput(
        self: *State,
        input: Input,
        event: canvas.TextInputEvent,
    ) void {
        if (self.inputs_locked) {
            self.setNotice(
                .failure,
                "This persisted draft is no longer editable.",
            );
            return;
        }
        if (input == .tax_year) {
            self.setNotice(
                .failure,
                "Tax year is fixed by the opened filing context.",
            );
            return;
        }
        const buffer = &self.inputs[@intFromEnum(input)];
        buffer.apply(event);
        self.refreshInputTruncation();
        self.refreshValidationNotice();
    }

    /// Programmatic setter used by persistence hydration and focused tests.
    pub fn setInput(
        self: *State,
        input: Input,
        text: []const u8,
    ) Error!void {
        if (self.inputs_locked) return error.DraftInputsLocked;
        if (input == .tax_year) {
            const opened_year = parseTaxYear(self.value(.tax_year)) catch
                return error.WrongPeriodContext;
            const requested_year = parseTaxYear(text) catch
                return error.InvalidTaxYear;
            if (requested_year != opened_year) {
                return error.WrongPeriodContext;
            }
        }
        try self.setInputRaw(input, text);
        self.refreshValidationNotice();
    }

    pub fn value(self: *const State, input: Input) []const u8 {
        return self.inputs[@intFromEnum(input)].text();
    }

    pub fn setQuarter(self: *State, quarter_number: u8) Error!void {
        if (self.inputs_locked) return error.DraftInputsLocked;
        if (quarter_number < 1 or quarter_number > 3) {
            return error.InvalidQuarter;
        }
        const opened_quarter = self.selected_quarter orelse
            return error.WrongPeriodContext;
        if (quarter_number != opened_quarter) {
            return error.WrongPeriodContext;
        }
        self.refreshValidationNotice();
    }

    pub fn quarter(self: *const State) ?u8 {
        return self.selected_quarter;
    }

    pub fn quarterValue(self: *const State) []const u8 {
        return switch (self.selected_quarter orelse return "Select Q1-Q3") {
            1 => "Q1",
            2 => "Q2",
            3 => "Q3",
            else => unreachable,
        };
    }

    pub fn quarterSelected(self: *const State, wanted: u8) bool {
        return self.selected_quarter == wanted;
    }

    pub fn setElection(self: *State, wanted: Election) Error!void {
        if (self.inputs_locked) return error.DraftInputsLocked;
        self.selected_election = wanted;
        self.refreshValidationNotice();
    }

    pub fn selectedElection(self: *const State) Election {
        return self.selected_election;
    }

    pub fn electionValue(self: *const State) []const u8 {
        return switch (self.selected_election) {
            .none => "Select graduated or 8 percent",
            .graduated => "Graduated income-tax rate",
            .eight_percent => "8 percent income-tax rate",
        };
    }

    pub fn electionSelected(
        self: *const State,
        wanted: Election,
    ) bool {
        return self.selected_election == wanted;
    }

    pub fn graduatedInputsDisabled(self: *const State) bool {
        return self.inputs_locked or self.selected_election != .graduated;
    }

    pub fn eightPercentInputsDisabled(self: *const State) bool {
        return self.inputs_locked or self.selected_election != .eight_percent;
    }

    pub fn paymentRows(self: *const State) []const PaymentRow {
        return self.payment_rows[0..self.payment_row_count];
    }

    pub fn paymentRowsFull(self: *const State) bool {
        return self.payment_row_count == max_payment_rows;
    }

    pub fn paymentAddDisabled(self: *const State) bool {
        return self.inputs_locked or self.paymentRowsFull();
    }

    pub fn paymentRemoveDisabled(self: *const State) bool {
        return self.inputs_locked or self.selected_payment_row == null;
    }

    pub fn paymentEditorVisible(self: *const State) bool {
        return self.selected_payment_row != null;
    }

    pub fn addPaymentRow(self: *State) Error!PaymentRowId {
        if (self.inputs_locked) return error.DraftInputsLocked;
        if (self.payment_row_count == max_payment_rows) {
            return error.TooManyPaymentRows;
        }
        var id_buffer: [max_payment_row_id_len]u8 = undefined;
        while (true) {
            const id_text = std.fmt.bufPrint(
                &id_buffer,
                "payment-{d}",
                .{self.next_payment_row_sequence},
            ) catch return error.FieldTooLong;
            self.next_payment_row_sequence +%= 1;
            if (self.next_payment_row_sequence == 0) {
                self.next_payment_row_sequence = 1;
            }
            const candidate = try PaymentRowId.parse(id_text);
            if (self.paymentRowIndex(candidate) == null) {
                try self.addPaymentRowWithId(candidate);
                self.refreshValidationNotice();
                return candidate;
            }
        }
    }

    pub fn selectPaymentRow(self: *State, slot: usize) Error!void {
        if (self.inputs_locked) return error.DraftInputsLocked;
        if (slot >= self.payment_row_count) return error.IncompletePayment;
        self.selected_payment_row = @intCast(slot);
        self.markSelectedPaymentRow();
    }

    pub fn removePaymentRow(self: *State, slot: usize) Error!void {
        if (self.inputs_locked) return error.DraftInputsLocked;
        if (slot >= self.payment_row_count) return error.IncompletePayment;
        var index = slot;
        while (index + 1 < self.payment_row_count) : (index += 1) {
            self.payment_rows[index] = self.payment_rows[index + 1];
            self.payment_rows[index].slot = index;
        }
        self.payment_row_count -= 1;
        if (self.payment_row_count == 0) {
            self.selected_payment_row = null;
        } else {
            self.selected_payment_row = @intCast(
                @min(slot, self.payment_row_count - 1),
            );
        }
        self.markSelectedPaymentRow();
        self.refreshPaymentInputTruncation();
        self.refreshValidationNotice();
    }

    pub fn applyPaymentInput(
        self: *State,
        input: PaymentInput,
        event: canvas.TextInputEvent,
    ) void {
        if (self.inputs_locked) {
            self.setNotice(
                .failure,
                "This persisted draft is no longer editable.",
            );
            return;
        }
        const row = self.selectedPaymentRowMut() orelse {
            self.setValidationError(error.IncompletePayment);
            return;
        };
        paymentBuffer(row, input).apply(event);
        self.refreshPaymentInputTruncation();
        self.refreshValidationNotice();
    }

    pub fn setPaymentInput(
        self: *State,
        input: PaymentInput,
        value_text: []const u8,
    ) Error!void {
        if (self.inputs_locked) return error.DraftInputsLocked;
        const row = self.selectedPaymentRowMut() orelse
            return error.IncompletePayment;
        if (value_text.len > max_input_len) return error.FieldTooLong;
        const buffer = paymentBuffer(row, input);
        buffer.set(value_text);
        buffer.truncated = false;
        self.refreshPaymentInputTruncation();
        self.refreshValidationNotice();
    }

    pub fn paymentValue(
        self: *const State,
        input: PaymentInput,
    ) []const u8 {
        const row = self.selectedPaymentRowConst() orelse return "";
        return paymentBufferConst(row, input).text();
    }

    pub fn setSelectedPaymentMethod(
        self: *State,
        method: PaymentMethodChoice,
    ) Error!void {
        if (self.inputs_locked) return error.DraftInputsLocked;
        const row = self.selectedPaymentRowMut() orelse
            return error.IncompletePayment;
        row.method = method;
        self.refreshValidationNotice();
    }

    pub fn paymentMethodSelected(
        self: *const State,
        method: PaymentMethodChoice,
    ) bool {
        const row = self.selectedPaymentRowConst() orelse return false;
        return row.method == method;
    }

    pub fn paymentMethodValue(self: *const State) []const u8 {
        const row = self.selectedPaymentRowConst() orelse
            return "No payment row selected";
        return row.name();
    }

    pub fn amendedReturnValue(self: *const State) []const u8 {
        return if (self.amended_return) "Yes" else "No";
    }

    pub fn inputsDisabled(self: *const State) bool {
        return self.inputs_locked;
    }

    /// Fail closed when a persisted nonempty value set cannot be hydrated.
    /// The caller may retain this state for diagnostics, but it cannot be
    /// edited or saved until an explicit reset or successful load.
    pub fn blockForLoadFailure(self: *State, load_error: anyerror) void {
        self.inputs_locked = true;
        self.setNoticeFmt(
            .failure,
            "Persisted 1701Q filing values could not be loaded: {s}.",
            .{@errorName(load_error)},
        );
    }

    pub fn noticeVisible(self: *const State) bool {
        return self.notice.len != 0;
    }

    pub fn noticeText(self: *const State) []const u8 {
        return self.notice.text();
    }

    pub fn noticeTone(self: *const State) []const u8 {
        return switch (self.notice_kind) {
            .neutral => "secondary",
            .success => "primary",
            .failure => "destructive",
        };
    }

    pub fn saveDisabled(self: *const State) bool {
        if (self.inputs_locked) return true;
        _ = self.parse() catch return true;
        self.validatePaymentRows() catch return true;
        return false;
    }

    pub fn validate(self: *State) !void {
        _ = self.parse() catch |err| {
            self.setValidationError(err);
            return err;
        };
        self.validatePaymentRows() catch |err| {
            self.setValidationError(err);
            return err;
        };
        self.setNotice(
            .success,
            "1701Q filing inputs are valid. No tax rate or policy was inferred.",
        );
    }

    pub fn buildTransaction(self: *State) !form.Transaction {
        const parsed = self.parse() catch |err| {
            self.setValidationError(err);
            return err;
        };
        for (self.paymentRows(), 0..) |*row, index| {
            self.payment_storage[index] = self.parsePaymentRow(row) catch |err| {
                self.setValidationError(err);
                return err;
            };
        }
        self.setNotice(
            .success,
            "1701Q transaction built from explicit filing inputs.",
        );
        return .{
            .period = parsed.period,
            .sheets_attached = parsed.sheets_attached,
            .computation = parsed.computation,
            .credits = parsed.credits,
            .tax_payable_or_overpayment = parsed.tax_payable_or_overpayment,
            .additions = parsed.additions,
            .payments = self.payment_storage[0..self.payment_row_count],
        };
    }

    /// Returns canonical, state-owned writes. The slice remains valid until
    /// the next call that mutates this state.
    pub fn draftValueWrites(
        self: *State,
    ) ![]const store_module.DraftValueWrite {
        if (self.inputs_locked) return error.DraftInputsLocked;
        const transaction = try self.buildTransaction();
        self.draft_write_len = 0;

        try self.appendInteger(
            field_id.taxable_year,
            transaction.period.year,
            provenance.filing_context,
        );
        try self.appendInteger(
            field_id.quarter,
            transaction.period.number,
            provenance.filing_context,
        );
        try self.appendText(
            field_id.amended_return,
            if (self.amended_return) "true" else "false",
            provenance.filing_context,
        );
        try self.appendInteger(
            field_id.sheets_attached,
            transaction.sheets_attached,
            provenance.filing_context,
        );

        switch (transaction.computation) {
            .graduated => |computation| {
                try self.appendText(
                    field_id.income_tax_rate_election,
                    "graduated",
                    provenance.transaction,
                );
                try self.appendMoney(
                    field_id.sales_revenues_receipts,
                    computation.sales_revenues_receipts,
                    provenance.transaction,
                );
                try self.appendMoney(
                    field_id.cost_of_sales_or_services,
                    computation.cost_of_sales_or_services,
                    provenance.transaction,
                );
                try self.appendMoney(
                    field_id.allowable_deductions,
                    computation.allowable_deductions,
                    provenance.transaction,
                );
                try self.appendMoney(
                    field_id.taxable_income,
                    computation.taxable_income,
                    provenance.external_policy_result,
                );
                try self.appendMoney(
                    field_id.income_tax_due,
                    computation.income_tax_due,
                    provenance.external_policy_result,
                );
            },
            .eight_percent => |computation| {
                try self.appendText(
                    field_id.income_tax_rate_election,
                    "eight_percent",
                    provenance.transaction,
                );
                try self.appendMoney(
                    field_id.gross_sales_or_receipts,
                    computation.gross_sales_or_receipts,
                    provenance.transaction,
                );
                try self.appendMoney(
                    field_id.non_operating_income,
                    computation.non_operating_income,
                    provenance.transaction,
                );
                try self.appendMoney(
                    field_id.eight_percent_tax_due,
                    computation.tax_due,
                    provenance.external_policy_result,
                );
            },
        }

        try self.appendMoney(
            field_id.prior_quarter_payments,
            transaction.credits.prior_quarter_income_tax_payments,
            provenance.external_evidence,
        );
        try self.appendMoney(
            field_id.creditable_tax_withheld_2307,
            transaction.credits.creditable_tax_withheld_2307,
            provenance.external_evidence,
        );
        try self.appendMoney(
            field_id.other_tax_credits,
            transaction.credits.other_tax_credits_or_payments,
            provenance.transaction,
        );
        try self.appendMoney(
            field_id.tax_payable_or_overpayment,
            transaction.tax_payable_or_overpayment,
            provenance.external_policy_result,
        );
        try self.appendMoney(
            field_id.surcharge,
            transaction.additions.surcharge,
            provenance.external_policy_result,
        );
        try self.appendMoney(
            field_id.interest,
            transaction.additions.interest,
            provenance.external_policy_result,
        );
        try self.appendMoney(
            field_id.compromise,
            transaction.additions.compromise,
            provenance.external_policy_result,
        );

        for (transaction.payments, 0..) |payment, index| {
            const row_id = self.payment_rows[index].stable_id;
            try self.appendPaymentText(
                row_id,
                "method",
                @tagName(payment.method),
                provenance.external_payment,
            );
            try self.appendPaymentText(
                row_id,
                "bank_or_agency",
                payment.bank_or_agency.asSlice(),
                provenance.external_payment,
            );
            try self.appendPaymentText(
                row_id,
                "reference",
                payment.reference.asSlice(),
                provenance.external_payment,
            );
            try self.appendPaymentMoney(
                row_id,
                "amount",
                payment.amount,
                provenance.external_payment,
            );
        }
        return self.draft_writes[0..self.draft_write_len];
    }

    /// Hydrates only filing/transaction values. Profile snapshots and named
    /// bindings remain authoritative in `forms/ui_state.zig`.
    pub fn loadFromDraft(
        self: *State,
        draft: *const store_module.OwnedDraft,
    ) !void {
        if (!std.mem.eql(u8, draft.form_code, form.revision.code.asSlice()) or
            !std.mem.eql(
                u8,
                draft.form_revision,
                form.revision.revision.asSlice(),
            ))
        {
            return error.WrongFormRevision;
        }
        const period = try parsePeriodKey(draft.period_key);
        try self.reset(period.year, period.number);
        self.amended_return = if (std.mem.eql(u8, draft.intent, "original"))
            false
        else if (std.mem.eql(u8, draft.intent, "amended"))
            true
        else
            return error.InvalidDraftIntent;
        self.inputs_locked = if (std.mem.eql(u8, draft.lifecycle, "editing"))
            false
        else if (std.mem.eql(u8, draft.lifecycle, "prepared") or
            std.mem.eql(u8, draft.lifecycle, "queued") or
            std.mem.eql(u8, draft.lifecycle, "submitted") or
            std.mem.eql(u8, draft.lifecycle, "confirmed") or
            std.mem.eql(u8, draft.lifecycle, "paid") or
            std.mem.eql(u8, draft.lifecycle, "cancelled"))
            true
        else
            return error.InvalidDraftIntent;

        if (draft.values.len == 0) {
            self.setNotice(
                .neutral,
                "This legacy draft has no 1701Q filing values yet.",
            );
            return;
        }

        for (draft.values) |*stored| {
            const parsed_field = (try parsePaymentFieldId(stored.field_id)) orelse
                continue;
            if (self.paymentRowIndex(parsed_field.row_id) == null) {
                try self.addPaymentRowWithId(parsed_field.row_id);
            }
        }

        var seen_inputs = [_]bool{false} ** input_count;
        var seen_quarter = false;
        var seen_amended = false;
        var seen_election = false;
        var seen_payment_fields =
            [_][4]bool{[_]bool{false} ** 4} ** max_payment_rows;

        for (draft.values) |*stored| {
            if (try parsePaymentFieldId(stored.field_id)) |parsed_field| {
                const row_index = self.paymentRowIndex(
                    parsed_field.row_id,
                ).?;
                const field_index = @intFromEnum(parsed_field.kind);
                if (seen_payment_fields[row_index][field_index]) {
                    return error.DuplicateDraftField;
                }
                seen_payment_fields[row_index][field_index] = true;
                try expectProvenance(
                    provenance.external_payment,
                    stored.provenance,
                );
                const row = &self.payment_rows[row_index];
                switch (parsed_field.kind) {
                    .method => row.method =
                        parsePaymentMethod(stored.value_text) orelse
                        return error.IncompletePayment,
                    .bank_or_agency => try setPaymentBufferRaw(
                        &row.bank_or_agency,
                        stored.value_text,
                    ),
                    .reference => try setPaymentBufferRaw(
                        &row.reference,
                        stored.value_text,
                    ),
                    .amount => try setPaymentBufferRaw(
                        &row.amount,
                        stored.value_text,
                    ),
                }
                continue;
            }
            if (inputForFieldId(stored.field_id)) |input| {
                const index = @intFromEnum(input);
                if (seen_inputs[index]) return error.DuplicateDraftField;
                seen_inputs[index] = true;
                try expectProvenance(inputProvenance(input), stored.provenance);
                try self.setInputRaw(input, stored.value_text);
                continue;
            }
            if (std.mem.eql(u8, stored.field_id, field_id.quarter)) {
                if (seen_quarter) return error.DuplicateDraftField;
                seen_quarter = true;
                try expectProvenance(
                    provenance.filing_context,
                    stored.provenance,
                );
                const quarter_number = try parseQuarter(stored.value_text);
                if (quarter_number != period.number) {
                    return error.WrongPeriodContext;
                }
                self.selected_quarter = quarter_number;
                continue;
            }
            if (std.mem.eql(u8, stored.field_id, field_id.amended_return)) {
                if (seen_amended) return error.DuplicateDraftField;
                seen_amended = true;
                try expectProvenance(
                    provenance.filing_context,
                    stored.provenance,
                );
                const amended = try parseBoolean(stored.value_text);
                if (amended != self.amended_return) {
                    return error.InvalidDraftIntent;
                }
                continue;
            }
            if (std.mem.eql(
                u8,
                stored.field_id,
                field_id.income_tax_rate_election,
            )) {
                if (seen_election) return error.DuplicateDraftField;
                seen_election = true;
                try expectProvenance(
                    provenance.transaction,
                    stored.provenance,
                );
                self.selected_election = parseElection(stored.value_text) orelse
                    return error.ElectionRequired;
                continue;
            }
            return error.UnknownDraftField;
        }

        if (!seen_quarter or !seen_amended or !seen_election) {
            return error.MissingValue;
        }
        const always_required = [_]Input{
            .tax_year,
            .sheets_attached,
            .prior_quarter_income_tax_payments,
            .creditable_tax_withheld_2307,
            .other_tax_credits_or_payments,
            .tax_payable_or_overpayment,
            .surcharge,
            .interest,
            .compromise,
        };
        for (always_required) |input| {
            if (!seen_inputs[@intFromEnum(input)]) return error.MissingValue;
        }
        switch (self.selected_election) {
            .none => return error.ElectionRequired,
            .graduated => {
                const required = [_]Input{
                    .graduated_sales_revenues_receipts,
                    .graduated_cost_of_sales_or_services,
                    .graduated_allowable_deductions,
                    .graduated_taxable_income,
                    .graduated_income_tax_due,
                };
                for (required) |input| {
                    if (!seen_inputs[@intFromEnum(input)]) {
                        return error.MissingValue;
                    }
                }
                const forbidden = [_]Input{
                    .eight_percent_gross_sales_or_receipts,
                    .eight_percent_non_operating_income,
                    .eight_percent_tax_due,
                };
                for (forbidden) |input| {
                    if (seen_inputs[@intFromEnum(input)]) {
                        return error.UnknownDraftField;
                    }
                }
            },
            .eight_percent => {
                const required = [_]Input{
                    .eight_percent_gross_sales_or_receipts,
                    .eight_percent_non_operating_income,
                    .eight_percent_tax_due,
                };
                for (required) |input| {
                    if (!seen_inputs[@intFromEnum(input)]) {
                        return error.MissingValue;
                    }
                }
                const forbidden = [_]Input{
                    .graduated_sales_revenues_receipts,
                    .graduated_cost_of_sales_or_services,
                    .graduated_allowable_deductions,
                    .graduated_taxable_income,
                    .graduated_income_tax_due,
                };
                for (forbidden) |input| {
                    if (seen_inputs[@intFromEnum(input)]) {
                        return error.UnknownDraftField;
                    }
                }
            },
        }
        var payment_index: usize = 0;
        while (payment_index < self.payment_row_count) : (payment_index += 1) {
            for (seen_payment_fields[payment_index]) |was_seen| {
                if (!was_seen) return error.MissingValue;
            }
        }

        const loaded_year = try parseTaxYear(self.value(.tax_year));
        if (loaded_year != period.year) return error.WrongPeriodContext;
        if (self.payment_row_count != 0) {
            self.selected_payment_row = 0;
            self.markSelectedPaymentRow();
        }
        self.refreshPaymentInputTruncation();
        try self.validate();
        self.setNotice(
            .success,
            "Persisted 1701Q filing inputs loaded without recalculation.",
        );
    }

    pub fn totalTaxPayable(self: *const State) !Money {
        var total = try parseMoney(
            self.value(.tax_payable_or_overpayment),
        );
        total = try total.checkedAdd(try parseMoney(self.value(.surcharge)));
        total = try total.checkedAdd(try parseMoney(self.value(.interest)));
        return total.checkedAdd(try parseMoney(self.value(.compromise)));
    }

    pub fn totalTaxPayableText(
        self: *const State,
        arena: std.mem.Allocator,
    ) []const u8 {
        const total = self.totalTaxPayable() catch return "PHP —";
        var amount_buffer: [32]u8 = undefined;
        const amount = total.write(&amount_buffer) catch return "PHP —";
        return std.fmt.allocPrint(arena, "PHP {s}", .{amount}) catch "PHP —";
    }

    fn parse(self: *const State) !Parsed {
        if (self.input_was_truncated) return error.InputWasTruncated;
        const year = try parseTaxYear(self.value(.tax_year));
        const quarter_number = self.selected_quarter orelse
            return error.InvalidQuarter;
        const period = form.FilingQuarter.init(year, quarter_number) catch
            return error.InvalidQuarter;
        const sheets = parseUnsigned(
            u16,
            self.value(.sheets_attached),
        ) catch return error.InvalidSheetsAttached;

        const computation: form.IncomeComputation =
            switch (self.selected_election) {
                .none => return error.ElectionRequired,
                .graduated => .{ .graduated = .{
                    .sales_revenues_receipts = try parseNonNegativeMoney(
                        self.value(.graduated_sales_revenues_receipts),
                    ),
                    .cost_of_sales_or_services = try parseNonNegativeMoney(
                        self.value(.graduated_cost_of_sales_or_services),
                    ),
                    .allowable_deductions = try parseNonNegativeMoney(
                        self.value(.graduated_allowable_deductions),
                    ),
                    .taxable_income = try parseNonNegativeMoney(
                        self.value(.graduated_taxable_income),
                    ),
                    .income_tax_due = try parseNonNegativeMoney(
                        self.value(.graduated_income_tax_due),
                    ),
                } },
                .eight_percent => .{ .eight_percent = .{
                    .gross_sales_or_receipts = try parseNonNegativeMoney(
                        self.value(.eight_percent_gross_sales_or_receipts),
                    ),
                    .non_operating_income = try parseNonNegativeMoney(
                        self.value(.eight_percent_non_operating_income),
                    ),
                    .tax_due = try parseNonNegativeMoney(
                        self.value(.eight_percent_tax_due),
                    ),
                } },
            };

        return .{
            .period = period,
            .sheets_attached = sheets,
            .computation = computation,
            .credits = .{
                .prior_quarter_income_tax_payments = try parseNonNegativeMoney(
                    self.value(.prior_quarter_income_tax_payments),
                ),
                .creditable_tax_withheld_2307 = try parseNonNegativeMoney(
                    self.value(.creditable_tax_withheld_2307),
                ),
                .other_tax_credits_or_payments = try parseNonNegativeMoney(
                    self.value(.other_tax_credits_or_payments),
                ),
            },
            .tax_payable_or_overpayment = try parseMoney(
                self.value(.tax_payable_or_overpayment),
            ),
            .additions = .{
                .surcharge = try parseNonNegativeMoney(
                    self.value(.surcharge),
                ),
                .interest = try parseNonNegativeMoney(
                    self.value(.interest),
                ),
                .compromise = try parseNonNegativeMoney(
                    self.value(.compromise),
                ),
            },
        };
    }

    fn parsePaymentRow(
        self: *const State,
        row: *const PaymentRow,
    ) !form.Payment {
        _ = self;
        const bank = std.mem.trim(u8, row.bank_or_agency.text(), " \t\r\n");
        const reference = std.mem.trim(u8, row.reference.text(), " \t\r\n");
        const amount = std.mem.trim(u8, row.amount.text(), " \t\r\n");
        if (row.method == .none or
            bank.len == 0 or reference.len == 0 or amount.len == 0)
        {
            return error.IncompletePayment;
        }
        return .{
            .method = switch (row.method) {
                .none => unreachable,
                .cash => .cash,
                .check => .check,
                .tax_debit_memo => .tax_debit_memo,
                .other => .other,
            },
            .bank_or_agency = try @import("../tax_profile/field.zig")
                .SourceReference.parse(bank),
            .reference = try @import("../tax_profile/field.zig")
                .SourceReference.parse(reference),
            .amount = try parseNonNegativeMoney(amount),
        };
    }

    fn validatePaymentRows(self: *const State) !void {
        for (self.paymentRows()) |*row| {
            _ = try self.parsePaymentRow(row);
        }
    }

    fn paymentRowIndex(
        self: *const State,
        row_id: PaymentRowId,
    ) ?usize {
        for (self.paymentRows(), 0..) |*row, index| {
            if (row.stable_id.eql(&row_id)) return index;
        }
        return null;
    }

    fn addPaymentRowWithId(
        self: *State,
        row_id: PaymentRowId,
    ) Error!void {
        if (self.payment_row_count == max_payment_rows) {
            return error.TooManyPaymentRows;
        }
        if (self.paymentRowIndex(row_id) != null) {
            return error.DuplicateDraftField;
        }
        const slot: usize = self.payment_row_count;
        self.payment_rows[slot] = .{
            .slot = slot,
            .stable_id = row_id,
            .active = true,
        };
        self.payment_row_count += 1;
        self.selected_payment_row = @intCast(slot);
        self.markSelectedPaymentRow();
    }

    fn markSelectedPaymentRow(self: *State) void {
        for (self.payment_rows[0..self.payment_row_count], 0..) |
            *row,
            index,
        | {
            row.active = self.selected_payment_row ==
                @as(u8, @intCast(index));
        }
    }

    fn selectedPaymentRowMut(self: *State) ?*PaymentRow {
        const selected = self.selected_payment_row orelse return null;
        if (selected >= self.payment_row_count) return null;
        return &self.payment_rows[selected];
    }

    fn selectedPaymentRowConst(self: *const State) ?*const PaymentRow {
        const selected = self.selected_payment_row orelse return null;
        if (selected >= self.payment_row_count) return null;
        return &self.payment_rows[selected];
    }

    fn setInputRaw(
        self: *State,
        input: Input,
        text: []const u8,
    ) Error!void {
        if (text.len > max_input_len) return error.FieldTooLong;
        const buffer = &self.inputs[@intFromEnum(input)];
        buffer.set(text);
        buffer.truncated = false;
        self.refreshInputTruncation();
    }

    fn refreshValidationNotice(self: *State) void {
        _ = self.parse() catch |err| {
            self.setValidationError(err);
            return;
        };
        self.validatePaymentRows() catch |err| {
            self.setValidationError(err);
            return;
        };
        self.setNotice(
            .success,
            "1701Q filing inputs are valid. No tax rate or policy was inferred.",
        );
    }

    fn refreshInputTruncation(self: *State) void {
        self.input_was_truncated = false;
        for (&self.inputs) |*buffer| {
            if (buffer.truncated) {
                self.input_was_truncated = true;
                return;
            }
        }
        for (self.payment_rows[0..self.payment_row_count]) |*row| {
            if (row.bank_or_agency.truncated or
                row.reference.truncated or
                row.amount.truncated)
            {
                self.input_was_truncated = true;
                return;
            }
        }
    }

    fn refreshPaymentInputTruncation(self: *State) void {
        self.refreshInputTruncation();
    }

    fn setValidationError(self: *State, err: anyerror) void {
        self.setNoticeFmt(
            .failure,
            "Complete the explicit 1701Q filing inputs: {s}.",
            .{@errorName(err)},
        );
    }

    fn setNotice(
        self: *State,
        kind: NoticeKind,
        text: []const u8,
    ) void {
        self.notice_kind = kind;
        self.notice.set(text);
    }

    fn setNoticeFmt(
        self: *State,
        kind: NoticeKind,
        comptime format: []const u8,
        args: anytype,
    ) void {
        var buffer: [max_notice_len]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, format, args) catch {
            self.setNotice(kind, "1701Q filing input validation failed.");
            return;
        };
        self.setNotice(kind, text);
    }

    fn appendInteger(
        self: *State,
        id: []const u8,
        value_to_write: anytype,
        value_provenance: []const u8,
    ) !void {
        const index = try self.reserveDraftValue();
        const text = std.fmt.bufPrint(
            &self.draft_value_buffers[index],
            "{d}",
            .{value_to_write},
        ) catch return error.FieldTooLong;
        self.draft_writes[index] = .{
            .field_id = id,
            .value_text = text,
            .provenance = value_provenance,
        };
    }

    fn appendMoney(
        self: *State,
        id: []const u8,
        value_to_write: Money,
        value_provenance: []const u8,
    ) !void {
        const index = try self.reserveDraftValue();
        const text = value_to_write.write(
            &self.draft_value_buffers[index],
        ) catch return error.FieldTooLong;
        self.draft_writes[index] = .{
            .field_id = id,
            .value_text = text,
            .provenance = value_provenance,
        };
    }

    fn appendText(
        self: *State,
        id: []const u8,
        text: []const u8,
        value_provenance: []const u8,
    ) !void {
        if (text.len > max_input_len) return error.FieldTooLong;
        const index = try self.reserveDraftValue();
        @memcpy(
            self.draft_value_buffers[index][0..text.len],
            text,
        );
        self.draft_writes[index] = .{
            .field_id = id,
            .value_text = self.draft_value_buffers[index][0..text.len],
            .provenance = value_provenance,
        };
    }

    fn appendPaymentText(
        self: *State,
        row_id: PaymentRowId,
        component: []const u8,
        text: []const u8,
        value_provenance: []const u8,
    ) !void {
        if (text.len > max_input_len) return error.FieldTooLong;
        const index = try self.reserveDraftValue();
        const id = std.fmt.bufPrint(
            &self.draft_field_id_buffers[index],
            "{s}{s}/{s}",
            .{ payment_field_prefix, row_id.asSlice(), component },
        ) catch return error.FieldTooLong;
        @memcpy(self.draft_value_buffers[index][0..text.len], text);
        self.draft_writes[index] = .{
            .field_id = id,
            .value_text = self.draft_value_buffers[index][0..text.len],
            .provenance = value_provenance,
        };
    }

    fn appendPaymentMoney(
        self: *State,
        row_id: PaymentRowId,
        component: []const u8,
        value_to_write: Money,
        value_provenance: []const u8,
    ) !void {
        const index = try self.reserveDraftValue();
        const id = std.fmt.bufPrint(
            &self.draft_field_id_buffers[index],
            "{s}{s}/{s}",
            .{ payment_field_prefix, row_id.asSlice(), component },
        ) catch return error.FieldTooLong;
        const text = value_to_write.write(
            &self.draft_value_buffers[index],
        ) catch return error.FieldTooLong;
        self.draft_writes[index] = .{
            .field_id = id,
            .value_text = text,
            .provenance = value_provenance,
        };
    }

    fn reserveDraftValue(self: *State) Error!usize {
        if (self.draft_write_len == self.draft_writes.len) {
            return error.TooManyDraftValues;
        }
        const index = self.draft_write_len;
        self.draft_write_len += 1;
        return index;
    }
};

fn parseMoney(raw: []const u8) !Money {
    if (std.mem.trim(u8, raw, " \t\r\n").len == 0) {
        return error.MissingValue;
    }
    return Money.parse(raw);
}

fn parseNonNegativeMoney(raw: []const u8) !Money {
    const value = try parseMoney(raw);
    if (value.centavos < 0) return error.NegativeAmountNotAllowed;
    return value;
}

fn paymentBuffer(
    row: *PaymentRow,
    input: PaymentInput,
) *canvas.TextBuffer(max_input_len) {
    return switch (input) {
        .bank_or_agency => &row.bank_or_agency,
        .reference => &row.reference,
        .amount => &row.amount,
    };
}

fn paymentBufferConst(
    row: *const PaymentRow,
    input: PaymentInput,
) *const canvas.TextBuffer(max_input_len) {
    return switch (input) {
        .bank_or_agency => &row.bank_or_agency,
        .reference => &row.reference,
        .amount => &row.amount,
    };
}

fn setPaymentBufferRaw(
    buffer: *canvas.TextBuffer(max_input_len),
    text: []const u8,
) Error!void {
    if (text.len > max_input_len) return error.FieldTooLong;
    buffer.set(text);
    buffer.truncated = false;
}

const PaymentFieldKind = enum {
    method,
    bank_or_agency,
    reference,
    amount,
};

const ParsedPaymentField = struct {
    row_id: PaymentRowId,
    kind: PaymentFieldKind,
};

const payment_field_prefix = "1701Q.2018-01-ENCS.table.payment/";

fn parsePaymentFieldId(raw: []const u8) Error!?ParsedPaymentField {
    if (!std.mem.startsWith(u8, raw, payment_field_prefix)) return null;
    const rest = raw[payment_field_prefix.len..];
    const separator = std.mem.lastIndexOfScalar(u8, rest, '/') orelse
        return error.InvalidPaymentFieldId;
    if (separator == 0 or separator + 1 == rest.len) {
        return error.InvalidPaymentFieldId;
    }
    const row_id = PaymentRowId.parse(rest[0..separator]) catch
        return error.InvalidPaymentFieldId;
    const component = rest[separator + 1 ..];
    const kind: PaymentFieldKind =
        if (std.mem.eql(u8, component, "method"))
            .method
        else if (std.mem.eql(u8, component, "bank_or_agency"))
            .bank_or_agency
        else if (std.mem.eql(u8, component, "reference"))
            .reference
        else if (std.mem.eql(u8, component, "amount"))
            .amount
        else
            return error.InvalidPaymentFieldId;
    return .{ .row_id = row_id, .kind = kind };
}

fn parseTaxYear(raw: []const u8) Error!u16 {
    const text = std.mem.trim(u8, raw, " \t\r\n");
    if (text.len != 4) return error.InvalidTaxYear;
    const year = std.fmt.parseInt(u16, text, 10) catch
        return error.InvalidTaxYear;
    if (year == 0) return error.InvalidTaxYear;
    return year;
}

fn parseUnsigned(comptime T: type, raw: []const u8) !T {
    const text = std.mem.trim(u8, raw, " \t\r\n");
    if (text.len == 0) return error.MissingValue;
    return std.fmt.parseInt(T, text, 10);
}

fn parsePeriodKey(raw: []const u8) Error!form.FilingQuarter {
    if (raw.len != 7 or raw[4] != '-' or raw[5] != 'Q') {
        return error.WrongPeriodContext;
    }
    const year = parseTaxYear(raw[0..4]) catch
        return error.WrongPeriodContext;
    const quarter = parseQuarter(raw[5..]) catch
        return error.WrongPeriodContext;
    return form.FilingQuarter.init(year, quarter) catch
        return error.WrongPeriodContext;
}

fn parseQuarter(raw: []const u8) Error!u8 {
    const text = std.mem.trim(u8, raw, " \t\r\n");
    const digits = if (text.len == 2 and
        (text[0] == 'Q' or text[0] == 'q'))
        text[1..]
    else
        text;
    const quarter = std.fmt.parseInt(u8, digits, 10) catch
        return error.InvalidQuarter;
    if (quarter < 1 or quarter > 3) return error.InvalidQuarter;
    return quarter;
}

fn parseBoolean(raw: []const u8) Error!bool {
    if (std.ascii.eqlIgnoreCase(raw, "true") or
        std.ascii.eqlIgnoreCase(raw, "yes"))
    {
        return true;
    }
    if (std.ascii.eqlIgnoreCase(raw, "false") or
        std.ascii.eqlIgnoreCase(raw, "no"))
    {
        return false;
    }
    return error.InvalidBoolean;
}

fn parseElection(raw: []const u8) ?Election {
    if (std.mem.eql(u8, raw, "graduated")) return .graduated;
    if (std.mem.eql(u8, raw, "eight_percent")) return .eight_percent;
    return null;
}

fn parsePaymentMethod(raw: []const u8) ?PaymentMethodChoice {
    if (std.mem.eql(u8, raw, "cash")) return .cash;
    if (std.mem.eql(u8, raw, "check")) return .check;
    if (std.mem.eql(u8, raw, "tax_debit_memo")) return .tax_debit_memo;
    if (std.mem.eql(u8, raw, "other")) return .other;
    return null;
}

fn expectProvenance(expected: []const u8, actual: []const u8) Error!void {
    if (!std.mem.eql(u8, expected, actual)) {
        return error.UnexpectedDraftProvenance;
    }
}

fn inputForFieldId(id: []const u8) ?Input {
    inline for (std.meta.tags(Input)) |input| {
        if (std.mem.eql(u8, id, inputFieldId(input))) return input;
    }
    return null;
}

fn inputFieldId(input: Input) []const u8 {
    return switch (input) {
        .tax_year => field_id.taxable_year,
        .sheets_attached => field_id.sheets_attached,
        .graduated_sales_revenues_receipts => field_id.sales_revenues_receipts,
        .graduated_cost_of_sales_or_services => field_id.cost_of_sales_or_services,
        .graduated_allowable_deductions => field_id.allowable_deductions,
        .graduated_taxable_income => field_id.taxable_income,
        .graduated_income_tax_due => field_id.income_tax_due,
        .eight_percent_gross_sales_or_receipts => field_id.gross_sales_or_receipts,
        .eight_percent_non_operating_income => field_id.non_operating_income,
        .eight_percent_tax_due => field_id.eight_percent_tax_due,
        .prior_quarter_income_tax_payments => field_id.prior_quarter_payments,
        .creditable_tax_withheld_2307 => field_id.creditable_tax_withheld_2307,
        .other_tax_credits_or_payments => field_id.other_tax_credits,
        .tax_payable_or_overpayment => field_id.tax_payable_or_overpayment,
        .surcharge => field_id.surcharge,
        .interest => field_id.interest,
        .compromise => field_id.compromise,
    };
}

fn inputProvenance(input: Input) []const u8 {
    return switch (input) {
        .tax_year,
        .sheets_attached,
        => provenance.filing_context,
        .graduated_sales_revenues_receipts,
        .graduated_cost_of_sales_or_services,
        .graduated_allowable_deductions,
        .eight_percent_gross_sales_or_receipts,
        .eight_percent_non_operating_income,
        .other_tax_credits_or_payments,
        => provenance.transaction,
        .prior_quarter_income_tax_payments,
        .creditable_tax_withheld_2307,
        => provenance.external_evidence,
        .graduated_taxable_income,
        .graduated_income_tax_due,
        .eight_percent_tax_due,
        .tax_payable_or_overpayment,
        .surcharge,
        .interest,
        .compromise,
        => provenance.external_policy_result,
    };
}

const provenance = struct {
    const filing_context = "filing_context";
    const transaction = "transaction";
    const external_evidence = "external_evidence";
    const external_policy_result = "external_policy_result";
    const external_payment = "external_payment";
};

const field_id = struct {
    const taxable_year = "1701Q.2018-01-ENCS.input.taxable_year";
    const quarter = "1701Q.2018-01-ENCS.input.quarter";
    const amended_return = "1701Q.2018-01-ENCS.input.amended_return";
    const sheets_attached =
        "1701Q.2018-01-ENCS.input.number_of_sheets_attached";
    const income_tax_rate_election =
        "1701Q.2018-01-ENCS.input.income_tax_rate_election";
    const sales_revenues_receipts =
        "1701Q.2018-01-ENCS.input.sales_revenues_receipts";
    const cost_of_sales_or_services =
        "1701Q.2018-01-ENCS.input.cost_of_sales_services";
    const allowable_deductions =
        "1701Q.2018-01-ENCS.input.allowable_deductions";
    const taxable_income = "1701Q.2018-01-ENCS.input.taxable_income";
    const income_tax_due = "1701Q.2018-01-ENCS.input.income_tax_due";
    const gross_sales_or_receipts =
        "1701Q.2018-01-ENCS.input.gross_sales_receipts";
    const non_operating_income =
        "1701Q.2018-01-ENCS.input.less_non_operating_income";
    const eight_percent_tax_due =
        "1701Q.2018-01-ENCS.input.tax_due_at_8_percent";
    const prior_quarter_payments =
        "1701Q.2018-01-ENCS.input.prior_quarter_income_tax_payments";
    const creditable_tax_withheld_2307 =
        "1701Q.2018-01-ENCS.input.creditable_tax_withheld_bir_form_2307";
    const other_tax_credits =
        "1701Q.2018-01-ENCS.input.other_tax_credits_payments";
    const tax_payable_or_overpayment =
        "1701Q.2018-01-ENCS.input.tax_payable_overpayment";
    const surcharge = "1701Q.2018-01-ENCS.input.surcharge";
    const interest = "1701Q.2018-01-ENCS.input.interest";
    const compromise = "1701Q.2018-01-ENCS.input.compromise";
};

fn fillCommonRequiredInputs(state: *State) !void {
    try state.setInput(.sheets_attached, "0");
    try state.setInput(.prior_quarter_income_tax_payments, "0.00");
    try state.setInput(.creditable_tax_withheld_2307, "0.00");
    try state.setInput(.other_tax_credits_or_payments, "0.00");
    try state.setInput(.tax_payable_or_overpayment, "900.00");
    try state.setInput(.surcharge, "10.00");
    try state.setInput(.interest, "5.00");
    try state.setInput(.compromise, "0.00");
}

fn fillGraduatedInputs(state: *State) !void {
    try state.setElection(.graduated);
    try state.setInput(
        .graduated_sales_revenues_receipts,
        "10000.00",
    );
    try state.setInput(
        .graduated_cost_of_sales_or_services,
        "2000.00",
    );
    try state.setInput(.graduated_allowable_deductions, "1000.00");
    try state.setInput(.graduated_taxable_income, "7000.00");
    try state.setInput(.graduated_income_tax_due, "900.00");
}

test "graduated transaction uses explicit values and omits inactive branch" {
    var state: State = .{};
    try state.reset(2026, 1);
    try fillCommonRequiredInputs(&state);
    try fillGraduatedInputs(&state);

    const transaction = try state.buildTransaction();
    try std.testing.expectEqual(@as(u16, 2026), transaction.period.year);
    try std.testing.expectEqual(@as(u8, 1), transaction.period.number);
    try std.testing.expectEqual(
        @as(i64, 900_00),
        transaction.computation.graduated.income_tax_due.centavos,
    );
    try std.testing.expectEqual(@as(usize, 0), transaction.payments.len);
    try std.testing.expectEqual(
        @as(i64, 915_00),
        (try state.totalTaxPayable()).centavos,
    );

    const writes = try state.draftValueWrites();
    try std.testing.expectEqual(@as(usize, 17), writes.len);
    try std.testing.expect(
        findWrite(writes, field_id.gross_sales_or_receipts) == null,
    );
    try std.testing.expectEqualStrings(
        provenance.external_policy_result,
        findWrite(writes, field_id.income_tax_due).?.provenance,
    );
}

test "eight-percent branch and optional payment round trip from draft values" {
    var source: State = .{};
    try source.reset(2026, 2);
    try fillCommonRequiredInputs(&source);
    try source.setElection(.eight_percent);
    try source.setInput(
        .eight_percent_gross_sales_or_receipts,
        "20000.00",
    );
    try source.setInput(.eight_percent_non_operating_income, "500.00");
    try source.setInput(.eight_percent_tax_due, "1560.00");
    _ = try source.addPaymentRow();
    try source.setSelectedPaymentMethod(.check);
    try source.setPaymentInput(.bank_or_agency, "Authorized Bank");
    try source.setPaymentInput(.reference, "CHECK-123");
    try source.setPaymentInput(.amount, "915.00");

    const writes = try source.draftValueWrites();
    try std.testing.expectEqual(@as(usize, 19), writes.len);
    var owned_values: [max_draft_values]store_module.OwnedDraftValue =
        undefined;
    for (writes, 0..) |write, index| {
        owned_values[index] = .{
            .field_id = @constCast(write.field_id),
            .value_text = @constCast(write.value_text),
            .provenance = @constCast(write.provenance),
        };
    }
    const draft: store_module.OwnedDraft = .{
        .id = @constCast("draft-1701q"),
        .form_code = @constCast("1701Q"),
        .form_revision = @constCast("2018-01-ENCS"),
        .period_key = @constCast("2026-Q2"),
        .profile_as_of = @constCast("2026-06-30"),
        .lifecycle = @constCast("editing"),
        .intent = @constCast("original"),
        .mapping_revision = @constCast("test-mapping"),
        .amendment_of = null,
        .bindings = &.{},
        .snapshots = &.{},
        .values = owned_values[0..writes.len],
    };

    var loaded: State = .{};
    try loaded.loadFromDraft(&draft);
    const transaction = try loaded.buildTransaction();
    try std.testing.expectEqual(
        @as(i64, 1_560_00),
        transaction.computation.eight_percent.tax_due.centavos,
    );
    try std.testing.expectEqual(@as(usize, 1), transaction.payments.len);
    try std.testing.expectEqual(
        form.PaymentMethod.check,
        transaction.payments[0].method,
    );
    try std.testing.expectEqualStrings(
        "CHECK-123",
        loaded.paymentValue(.reference),
    );
}

test "validation rejects missing election malformed inputs and partial payment" {
    var state: State = .{};
    try state.reset(2026, 3);
    try fillCommonRequiredInputs(&state);
    try std.testing.expect(state.saveDisabled());
    try std.testing.expectError(
        error.ElectionRequired,
        state.buildTransaction(),
    );

    try fillGraduatedInputs(&state);
    try state.setInput(.graduated_income_tax_due, "calculated later");
    try std.testing.expect(state.saveDisabled());
    try state.setInput(.graduated_income_tax_due, "900.00");
    try std.testing.expect(!state.saveDisabled());

    _ = try state.addPaymentRow();
    try state.setSelectedPaymentMethod(.cash);
    try std.testing.expectError(
        error.IncompletePayment,
        state.buildTransaction(),
    );
    try std.testing.expectError(
        error.WrongPeriodContext,
        state.setQuarter(2),
    );
    try std.testing.expectError(
        error.WrongPeriodContext,
        state.setInput(.tax_year, "2025"),
    );
    try std.testing.expectError(error.InvalidQuarter, state.setQuarter(4));
}

test "multiple payment rows keep stable generic persistence identities" {
    var source: State = .{};
    try source.reset(2026, 1);
    try fillCommonRequiredInputs(&source);
    try fillGraduatedInputs(&source);

    const first_id = try source.addPaymentRow();
    try source.setSelectedPaymentMethod(.cash);
    try source.setPaymentInput(.bank_or_agency, "RCO Manila");
    try source.setPaymentInput(.reference, "CASH-001");
    try source.setPaymentInput(.amount, "100.00");

    const second_id = try source.addPaymentRow();
    try source.setSelectedPaymentMethod(.tax_debit_memo);
    try source.setPaymentInput(.bank_or_agency, "BIR");
    try source.setPaymentInput(.reference, "TDM-002");
    try source.setPaymentInput(.amount, "815.00");

    try std.testing.expect(!first_id.eql(&second_id));
    const writes = try source.draftValueWrites();
    try std.testing.expectEqual(@as(usize, 25), writes.len);
    var first_prefix_buffer: [96]u8 = undefined;
    const first_prefix = try std.fmt.bufPrint(
        &first_prefix_buffer,
        "{s}{s}/",
        .{ payment_field_prefix, first_id.asSlice() },
    );
    var second_prefix_buffer: [96]u8 = undefined;
    const second_prefix = try std.fmt.bufPrint(
        &second_prefix_buffer,
        "{s}{s}/",
        .{ payment_field_prefix, second_id.asSlice() },
    );
    var first_fields: usize = 0;
    var second_fields: usize = 0;
    for (writes) |write| {
        if (std.mem.startsWith(u8, write.field_id, first_prefix)) {
            first_fields += 1;
        }
        if (std.mem.startsWith(u8, write.field_id, second_prefix)) {
            second_fields += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 4), first_fields);
    try std.testing.expectEqual(@as(usize, 4), second_fields);

    var owned_values: [max_draft_values]store_module.OwnedDraftValue =
        undefined;
    ownTestWrites(writes, owned_values[0..writes.len]);
    var draft = testDraft(
        owned_values[0..writes.len],
        "2026-Q1",
        "editing",
    );
    var loaded: State = .{};
    try loaded.loadFromDraft(&draft);
    try std.testing.expectEqual(@as(usize, 2), loaded.paymentRows().len);
    const transaction = try loaded.buildTransaction();
    try std.testing.expectEqual(@as(usize, 2), transaction.payments.len);
    try std.testing.expectEqual(
        @as(i64, 815_00),
        transaction.payments[1].amount.centavos,
    );
}

test "legacy empty draft resumes blank and editable" {
    var no_values: [0]store_module.OwnedDraftValue = .{};
    var draft = testDraft(no_values[0..], "2026-Q2", "editing");
    var state: State = .{};
    try state.loadFromDraft(&draft);

    try std.testing.expect(!state.inputsDisabled());
    try std.testing.expect(state.saveDisabled());
    try std.testing.expectEqualStrings("", state.value(.sheets_attached));
    try std.testing.expectEqualStrings("secondary", state.noticeTone());
    try std.testing.expectEqualStrings(
        "This legacy draft has no 1701Q filing values yet.",
        state.noticeText(),
    );
}

test "persisted nonediting draft locks every mutation boundary" {
    var source: State = .{};
    try source.reset(2026, 3);
    try fillCommonRequiredInputs(&source);
    try fillGraduatedInputs(&source);
    const writes = try source.draftValueWrites();
    var owned_values: [max_draft_values]store_module.OwnedDraftValue =
        undefined;
    ownTestWrites(writes, owned_values[0..writes.len]);
    var draft = testDraft(
        owned_values[0..writes.len],
        "2026-Q3",
        "prepared",
    );

    var loaded: State = .{};
    try loaded.loadFromDraft(&draft);
    try std.testing.expect(loaded.inputsDisabled());
    try std.testing.expect(loaded.saveDisabled());
    try std.testing.expectError(
        error.DraftInputsLocked,
        loaded.setInput(.sheets_attached, "2"),
    );
    try std.testing.expectError(
        error.DraftInputsLocked,
        loaded.setQuarter(2),
    );
    try std.testing.expectError(
        error.DraftInputsLocked,
        loaded.setElection(.eight_percent),
    );
    try std.testing.expectError(
        error.DraftInputsLocked,
        loaded.addPaymentRow(),
    );
    try std.testing.expectError(
        error.DraftInputsLocked,
        loaded.draftValueWrites(),
    );
}

test "nonnegative money is enforced except signed payable or overpayment" {
    var graduated: State = .{};
    try graduated.reset(2026, 1);
    try fillCommonRequiredInputs(&graduated);
    try fillGraduatedInputs(&graduated);
    const graduated_nonnegative = [_]Input{
        .graduated_sales_revenues_receipts,
        .graduated_cost_of_sales_or_services,
        .graduated_allowable_deductions,
        .graduated_taxable_income,
        .graduated_income_tax_due,
        .prior_quarter_income_tax_payments,
        .creditable_tax_withheld_2307,
        .other_tax_credits_or_payments,
        .surcharge,
        .interest,
        .compromise,
    };
    for (graduated_nonnegative) |input| {
        try graduated.setInput(input, "-0.01");
        try std.testing.expectError(
            error.NegativeAmountNotAllowed,
            graduated.buildTransaction(),
        );
        try graduated.setInput(input, "0.00");
    }
    try graduated.setInput(.tax_payable_or_overpayment, "-100.00");
    _ = try graduated.buildTransaction();

    var eight_percent: State = .{};
    try eight_percent.reset(2026, 2);
    try fillCommonRequiredInputs(&eight_percent);
    try eight_percent.setElection(.eight_percent);
    try eight_percent.setInput(
        .eight_percent_gross_sales_or_receipts,
        "100.00",
    );
    try eight_percent.setInput(.eight_percent_non_operating_income, "0.00");
    try eight_percent.setInput(.eight_percent_tax_due, "8.00");
    const eight_nonnegative = [_]Input{
        .eight_percent_gross_sales_or_receipts,
        .eight_percent_non_operating_income,
        .eight_percent_tax_due,
    };
    for (eight_nonnegative) |input| {
        try eight_percent.setInput(input, "-0.01");
        try std.testing.expectError(
            error.NegativeAmountNotAllowed,
            eight_percent.buildTransaction(),
        );
        try eight_percent.setInput(input, "0.00");
    }
    _ = try eight_percent.addPaymentRow();
    try eight_percent.setSelectedPaymentMethod(.check);
    try eight_percent.setPaymentInput(.bank_or_agency, "Bank");
    try eight_percent.setPaymentInput(.reference, "REF");
    try eight_percent.setPaymentInput(.amount, "-0.01");
    try std.testing.expectError(
        error.NegativeAmountNotAllowed,
        eight_percent.buildTransaction(),
    );
}

test "correcting a truncated common or payment buffer clears the guard" {
    var state: State = .{};
    try state.reset(2026, 1);
    try fillCommonRequiredInputs(&state);
    try fillGraduatedInputs(&state);
    state.inputs[@intFromEnum(Input.surcharge)].truncated = true;
    state.refreshInputTruncation();
    try std.testing.expect(state.saveDisabled());
    try state.setInput(.surcharge, "0.00");
    try std.testing.expect(!state.input_was_truncated);

    _ = try state.addPaymentRow();
    try state.setSelectedPaymentMethod(.cash);
    try state.setPaymentInput(.bank_or_agency, "RCO");
    try state.setPaymentInput(.reference, "REF");
    try state.setPaymentInput(.amount, "1.00");
    state.selectedPaymentRowMut().?.amount.truncated = true;
    state.refreshPaymentInputTruncation();
    try std.testing.expect(state.saveDisabled());
    try state.setPaymentInput(.amount, "1.00");
    try std.testing.expect(!state.input_was_truncated);
    try std.testing.expect(!state.saveDisabled());
}

test "nonempty partial or unknown drafts reject and can be failed closed" {
    var values = [_]store_module.OwnedDraftValue{.{
        .field_id = @constCast(field_id.taxable_year),
        .value_text = @constCast("2026"),
        .provenance = @constCast(provenance.filing_context),
    }};
    var partial = testDraft(values[0..], "2026-Q1", "editing");
    var state: State = .{};
    try std.testing.expectError(
        error.MissingValue,
        state.loadFromDraft(&partial),
    );
    state.blockForLoadFailure(error.MissingValue);
    try std.testing.expect(state.inputsDisabled());
    try std.testing.expect(state.saveDisabled());
    try std.testing.expect(
        std.mem.indexOf(u8, state.noticeText(), "MissingValue") != null,
    );

    values[0].field_id = @constCast("1701Q.2018-01-ENCS.input.unknown");
    var unknown = testDraft(values[0..], "2026-Q1", "editing");
    var other: State = .{};
    try std.testing.expectError(
        error.UnknownDraftField,
        other.loadFromDraft(&unknown),
    );
}

test "nonempty draft rejects fields from the inactive computation branch" {
    var source: State = .{};
    try source.reset(2026, 1);
    try fillCommonRequiredInputs(&source);
    try fillGraduatedInputs(&source);
    const writes = try source.draftValueWrites();
    var owned_values: [max_draft_values]store_module.OwnedDraftValue =
        undefined;
    ownTestWrites(writes, owned_values[0..writes.len]);
    owned_values[writes.len] = .{
        .field_id = @constCast(field_id.gross_sales_or_receipts),
        .value_text = @constCast("1.00"),
        .provenance = @constCast(provenance.transaction),
    };
    var draft = testDraft(
        owned_values[0 .. writes.len + 1],
        "2026-Q1",
        "editing",
    );
    var loaded: State = .{};
    try std.testing.expectError(
        error.UnknownDraftField,
        loaded.loadFromDraft(&draft),
    );
}

fn ownTestWrites(
    writes: []const store_module.DraftValueWrite,
    destination: []store_module.OwnedDraftValue,
) void {
    std.debug.assert(writes.len == destination.len);
    for (writes, destination) |write, *owned| {
        owned.* = .{
            .field_id = @constCast(write.field_id),
            .value_text = @constCast(write.value_text),
            .provenance = @constCast(write.provenance),
        };
    }
}

fn testDraft(
    values: []store_module.OwnedDraftValue,
    period_key: []const u8,
    lifecycle: []const u8,
) store_module.OwnedDraft {
    return .{
        .id = @constCast("draft-1701q"),
        .form_code = @constCast("1701Q"),
        .form_revision = @constCast("2018-01-ENCS"),
        .period_key = @constCast(period_key),
        .profile_as_of = @constCast("2026-06-30"),
        .lifecycle = @constCast(lifecycle),
        .intent = @constCast("original"),
        .mapping_revision = @constCast("test-mapping"),
        .amendment_of = null,
        .bindings = &.{},
        .snapshots = &.{},
        .values = values,
    };
}

fn findWrite(
    writes: []const store_module.DraftValueWrite,
    id: []const u8,
) ?*const store_module.DraftValueWrite {
    for (writes) |*write| {
        if (std.mem.eql(u8, write.field_id, id)) return write;
    }
    return null;
}
