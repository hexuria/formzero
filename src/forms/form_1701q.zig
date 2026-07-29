//! BIR Form 1701Q, January 2018 (ENCS).
//!
//! It binds an exact-one `filer` profile and an optional separately named
//! `spouse` profile. Spouse facts are not mirrored into filer marital state.

const ids = @import("id.zig");
const spec = @import("spec.zig");
const compose = @import("compose.zig");
const lifecycle = @import("lifecycle.zig");
const projection = @import("../tax_profile/projection.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");
const Money = @import("../domain/money.zig").Money;

pub const revision = ids.FormRevision.initComptime(
    "1701Q",
    "2018-01-ENCS",
);

pub const filer_requirements = [_]spec.Requirement{
    .{
        .source = .tin,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.tin",
        ),
    },
    .{
        .source = .rdo_code,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.rdo_code",
        ),
    },
    .{
        .source = .taxpayer_name,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.taxpayer_filer_name",
        ),
    },
    .{
        .source = .registered_address,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.registered_address",
        ),
    },
    .{
        .source = .date_of_birth,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.date_of_birth",
        ),
        // Not applicable to estate/trust filers named by this form revision.
        .presence = .optional,
    },
    .{
        .source = .email_address,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.email_address",
        ),
    },
    .{
        .source = .citizenship,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.citizenship",
        ),
        // Not applicable to estate/trust filers.
        .presence = .optional,
    },
    .{
        .source = .foreign_tax_number,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.foreign_tax_number",
        ),
        .presence = .optional,
    },
};

pub const spouse_requirements = [_]spec.Requirement{
    .{
        .source = .tin,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.spouse_tin",
        ),
    },
    .{
        .source = .rdo_code,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.spouse_rdo_code",
        ),
    },
    .{
        .source = .taxpayer_name,
        .target = ids.FieldId.initComptime(
            "1701Q.2018-01-ENCS.input.spouse_name",
        ),
    },
};

pub const roles = [_]spec.RoleSpec{
    .{
        .role = .filer,
        .cardinality = .exactly_one,
        .allowed_subjects = model.SubjectKindSet.initMany(&.{
            .individual,
            .sole_proprietor,
            .estate,
            .trust,
        }),
        .requirements = &filer_requirements,
    },
    .{
        .role = .spouse,
        .cardinality = .zero_or_one,
        .allowed_subjects = model.SubjectKindSet.initMany(&.{
            .individual,
            .sole_proprietor,
        }),
        .requirements = &spouse_requirements,
    },
};

pub const profile_spec: spec.FormSpec = .{
    .revision = revision,
    .roles = &roles,
    .distinct_profile_roles = &.{.{
        .left = .filer,
        .right = .spouse,
    }},
};

comptime {
    spec.validate(profile_spec);
}

pub const FilingQuarter = struct {
    year: u16,
    number: u8,

    pub fn init(year: u16, number: u8) error{InvalidFilingQuarter}!FilingQuarter {
        // 1701Q is filed for the first three quarters; the annual return
        // covers the fourth-quarter/year-end obligation.
        if (year == 0 or number < 1 or number > 3) {
            return error.InvalidFilingQuarter;
        }
        return .{ .year = year, .number = number };
    }
};

pub const GraduatedComputation = struct {
    sales_revenues_receipts: Money,
    cost_of_sales_or_services: Money,
    allowable_deductions: Money,
    taxable_income: Money,
    income_tax_due: Money,
};

pub const EightPercentComputation = struct {
    gross_sales_or_receipts: Money,
    non_operating_income: Money,
    tax_due: Money,
};

/// The union keeps the chosen rate election synchronized with the inputs that
/// are meaningful for that election.
pub const IncomeComputation = union(enum) {
    graduated: GraduatedComputation,
    eight_percent: EightPercentComputation,
};

pub const Credits = struct {
    prior_quarter_income_tax_payments: Money,
    creditable_tax_withheld_2307: Money,
    other_tax_credits_or_payments: Money,
};

pub const Additions = struct {
    surcharge: Money,
    interest: Money,
    compromise: Money,
};

pub const PaymentMethod = enum {
    cash,
    check,
    tax_debit_memo,
    other,
};

pub const Payment = struct {
    method: PaymentMethod,
    bank_or_agency: field.SourceReference,
    reference: field.SourceReference,
    amount: Money,
};

/// Filing-period facts and policy-produced monetary results. This type does
/// not contain tax tables or infer a rate.
pub const Transaction = struct {
    period: FilingQuarter,
    sheets_attached: u16,
    computation: IncomeComputation,
    credits: Credits,
    tax_payable_or_overpayment: Money,
    additions: Additions,
    payments: []const Payment = &.{},
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
) error{WrongFormRevision}!lifecycle.Editing(Transaction) {
    if (!snapshot.form.eql(&revision)) return error.WrongFormRevision;
    return .{
        .draft_id = draft_id,
        .intent = intent,
        .snapshot = snapshot,
        .payload = transaction,
    };
}

test "1701Q has a required filer and optional named spouse role" {
    const std = @import("std");
    try std.testing.expectEqual(
        spec.Cardinality.exactly_one,
        profile_spec.role(.filer).?.cardinality,
    );
    try std.testing.expectEqual(
        spec.Cardinality.zero_or_one,
        profile_spec.role(.spouse).?.cardinality,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        profile_spec.role(.spouse).?.requirements.len,
    );
}

test "1701Q computation union cannot disagree with its rate election" {
    const std = @import("std");
    const transaction: Transaction = .{
        .period = try FilingQuarter.init(2026, 1),
        .sheets_attached = 0,
        .computation = .{ .eight_percent = .{
            .gross_sales_or_receipts = Money.fromCentavos(10_000_000),
            .non_operating_income = .zero,
            .tax_due = Money.fromCentavos(800_000),
        } },
        .credits = .{
            .prior_quarter_income_tax_payments = .zero,
            .creditable_tax_withheld_2307 = .zero,
            .other_tax_credits_or_payments = .zero,
        },
        .tax_payable_or_overpayment = Money.fromCentavos(800_000),
        .additions = .{
            .surcharge = .zero,
            .interest = .zero,
            .compromise = .zero,
        },
    };
    try std.testing.expectEqual(
        @as(i64, 800_000),
        transaction.computation.eight_percent.tax_due.centavos,
    );
    try std.testing.expectError(
        error.InvalidFilingQuarter,
        FilingQuarter.init(2026, 4),
    );
}
