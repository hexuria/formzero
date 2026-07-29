//! BIR Form 2551Q, January 2018 (ENCS).
//!
//! The profile projection mirrors the reusable controls that actually exist
//! in `src/pages/forms/2551q.native`. Filing-period choices, monetary lines,
//! credits, additions, and disposition remain transaction data.

const ids = @import("id.zig");
const spec = @import("spec.zig");
const compose = @import("compose.zig");
const lifecycle = @import("lifecycle.zig");
const projection = @import("../tax_profile/projection.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");
const Money = @import("../domain/money.zig").Money;

pub const revision = ids.FormRevision.initComptime(
    "2551Q",
    "2018-01-ENCS",
);

pub const filer_requirements = [_]spec.Requirement{
    .{
        .source = .tin,
        .target = ids.FieldId.initComptime(
            "2551Q.2018-01-ENCS.input.tin",
        ),
    },
    .{
        .source = .rdo_code,
        .target = ids.FieldId.initComptime(
            "2551Q.2018-01-ENCS.input.rdo_code",
        ),
    },
    .{
        .source = .taxpayer_name,
        .target = ids.FieldId.initComptime(
            "2551Q.2018-01-ENCS.input.taxpayers_name",
        ),
    },
    .{
        .source = .registered_address,
        .target = ids.FieldId.initComptime(
            "2551Q.2018-01-ENCS.input.registered_address",
        ),
    },
    .{
        .source = .zip_code,
        .target = ids.FieldId.initComptime(
            "2551Q.2018-01-ENCS.input.zip_code",
        ),
    },
    .{
        .source = .contact_number,
        .target = ids.FieldId.initComptime(
            "2551Q.2018-01-ENCS.input.contact_number",
        ),
    },
    .{
        .source = .email_address,
        .target = ids.FieldId.initComptime(
            "2551Q.2018-01-ENCS.input.email_address",
        ),
    },
};

pub const roles = [_]spec.RoleSpec{.{
    .role = .filer,
    .cardinality = .exactly_one,
    .allowed_subjects = model.SubjectKindSet.full,
    .requirements = &filer_requirements,
}};

pub const profile_spec: spec.FormSpec = .{
    .revision = revision,
    .roles = &roles,
};

comptime {
    spec.validate(profile_spec);
}

pub const TaxablePeriodBasis = enum {
    calendar,
    fiscal,
};

pub const TaxRelief = union(enum) {
    none,
    specified: field.SourceReference,
};

pub const IncomeTaxRateElection = enum {
    graduated,
    eight_percent,
};

pub const TaxRate = struct {
    /// One basis point is 0.01%. The value is supplied by external tax policy.
    basis_points: u16,

    pub fn init(basis_points: u16) error{InvalidTaxRate}!TaxRate {
        if (basis_points > 10_000) return error.InvalidTaxRate;
        return .{ .basis_points = basis_points };
    }
};

pub const ScheduleLine = struct {
    /// Repeated schedule-row selection for this filing, not a singleton
    /// taxpayer-header projection.
    atc: field.Atc,
    tax_base: Money,
    rate: TaxRate,
    percentage_tax_due: Money,
};

pub const Credits = struct {
    creditable_percentage_tax_withheld: Money,
    paid_in_previous_return: Money,
    other_credit_or_payment: Money,
};

pub const Additions = struct {
    surcharge: Money,
    interest: Money,
    compromise: Money,
};

pub const OverpaymentDisposition = enum {
    not_applicable,
    refund,
    tax_credit_certificate,
    carry_over,
};

/// Filing-specific values. No rate or due is derived here: authoritative tax
/// policy must supply the schedule line calculations before preparation.
pub const Transaction = struct {
    period_basis: TaxablePeriodBasis,
    year_end_month: u8,
    quarter: field.Quarter,
    sheets_attached: u16,
    tax_relief: TaxRelief,
    income_tax_rate_election: IncomeTaxRateElection,
    schedule_lines: []const ScheduleLine,
    total_percentage_tax_due: Money,
    credits: Credits,
    tax_payable_or_overpayment: Money,
    additions: Additions,
    overpayment_disposition: OverpaymentDisposition,

    pub fn validate(self: Transaction) error{
        InvalidYearEndMonth,
        MissingScheduleLine,
        InvalidOverpaymentDisposition,
    }!void {
        if (self.year_end_month < 1 or self.year_end_month > 12) {
            return error.InvalidYearEndMonth;
        }
        if (self.schedule_lines.len == 0) return error.MissingScheduleLine;
        if (self.tax_payable_or_overpayment.centavos < 0 and
            self.overpayment_disposition == .not_applicable)
        {
            return error.InvalidOverpaymentDisposition;
        }
        if (self.tax_payable_or_overpayment.centavos >= 0 and
            self.overpayment_disposition != .not_applicable)
        {
            return error.InvalidOverpaymentDisposition;
        }
    }
};

pub fn composeProfiles(
    bindings: []const projection.Binding,
    effective_on: model.Date,
) compose.Error!compose.Result {
    return compose.compose(profile_spec, bindings, effective_on);
}

pub fn beginEditing(
    draft_id: ids.DraftId,
    intent: lifecycle.Intent,
    snapshot: projection.Snapshot,
    transaction: Transaction,
) error{ WrongFormRevision, InvalidTransaction }!lifecycle.Editing(Transaction) {
    if (!snapshot.form.eql(&revision)) return error.WrongFormRevision;
    transaction.validate() catch return error.InvalidTransaction;
    return .{
        .draft_id = draft_id,
        .intent = intent,
        .snapshot = snapshot,
        .payload = transaction,
    };
}

test "2551Q spec contains the exact reusable taxpayer header" {
    const role = profile_spec.role(.filer).?;
    try @import("std").testing.expectEqual(@as(usize, 7), role.requirements.len);
    try @import("std").testing.expect(role.requiredFields().contains(.tin));
    try @import("std").testing.expect(!role.requiredFields().contains(.atc));
    try @import("std").testing.expect(
        !role.requiredFields().contains(.line_of_business),
    );
}

test "2551Q transaction accepts policy-supplied rates without embedding one" {
    const std = @import("std");
    const lines = [_]ScheduleLine{.{
        .atc = try field.Atc.parse("PT010"),
        .tax_base = Money.fromCentavos(45_000_000),
        .rate = try TaxRate.init(300),
        .percentage_tax_due = Money.fromCentavos(1_350_000),
    }};
    const transaction: Transaction = .{
        .period_basis = .calendar,
        .year_end_month = 12,
        .quarter = try field.Quarter.init(2026, 1),
        .sheets_attached = 0,
        .tax_relief = .none,
        .income_tax_rate_election = .graduated,
        .schedule_lines = &lines,
        .total_percentage_tax_due = Money.fromCentavos(1_350_000),
        .credits = .{
            .creditable_percentage_tax_withheld = .zero,
            .paid_in_previous_return = .zero,
            .other_credit_or_payment = .zero,
        },
        .tax_payable_or_overpayment = Money.fromCentavos(1_350_000),
        .additions = .{
            .surcharge = .zero,
            .interest = .zero,
            .compromise = .zero,
        },
        .overpayment_disposition = .not_applicable,
    };
    try transaction.validate();
    try std.testing.expectEqual(
        @as(u16, 300),
        transaction.schedule_lines[0].rate.basis_points,
    );
}
