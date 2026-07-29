//! Persistence-agnostic application layer for profile-bound recurring drafts.
//!
//! Form specifications qualify runtime-loaded profile revisions and project
//! reusable values into an owned `projection.Snapshot`. This module adds the
//! application-level identity around that snapshot:
//!
//! - one stable recurring-period key,
//! - owned named-role/revision bindings, and
//! - the existing coarse filing lifecycle.
//!
//! Transaction slices remain governed by their form payload types. Profile
//! values and provenance never borrow the source revision.

const std = @import("std");
const money = @import("../domain/money.zig");
const ids = @import("id.zig");
const compose = @import("compose.zig");
const lifecycle = @import("lifecycle.zig");
const form_1701q = @import("form_1701q.zig");
const form_2551q = @import("form_2551q.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");
const projection = @import("../tax_profile/projection.zig");

pub const Money = money.Money;

/// Stable identity for one occurrence of a recurring quarterly form.
///
/// `profile_as_of` is intentionally not part of this key. It is captured by
/// the projection snapshot and can differ from the period identity for fiscal
/// taxpayers or form-specific policy.
pub const RecurringQuarter = struct {
    form: ids.FormRevision,
    tax_year: u16,
    quarter: u8,

    pub fn for2551Q(period: field.Quarter) RecurringQuarter {
        return .{
            .form = form_2551q.revision,
            .tax_year = period.year,
            .quarter = period.number,
        };
    }

    pub fn for1701Q(period: form_1701q.FilingQuarter) RecurringQuarter {
        return .{
            .form = form_1701q.revision,
            .tax_year = period.year,
            .quarter = period.number,
        };
    }

    pub fn eql(self: *const RecurringQuarter, other: *const RecurringQuarter) bool {
        return self.form.eql(&other.form) and
            self.tax_year == other.tax_year and
            self.quarter == other.quarter;
    }
};

/// An owned record of which immutable profile revision filled a named role.
pub const RoleRevisionBinding = struct {
    role: ids.Role,
    profile_id: model.ProfileId,
    revision_id: model.RevisionId,
    revision_sequence: u32,
    revision_source: model.RevisionSource,
    business_activity_id: ?model.BusinessActivityId,

    fn capture(binding: projection.Binding) RoleRevisionBinding {
        return .{
            .role = binding.role,
            .profile_id = binding.revision.profile_id,
            .revision_id = binding.revision.id,
            .revision_sequence = binding.revision.sequence,
            .revision_source = binding.revision.source,
            .business_activity_id = binding.selection.business_activity_id,
        };
    }
};

pub const max_role_bindings = 4;

pub const RoleBindingError = error{
    DuplicateRoleBinding,
    TooManyRoleBindings,
};

pub const RoleBindings = struct {
    entries: [max_role_bindings]RoleRevisionBinding = undefined,
    len: u8 = 0,

    pub fn from(
        bindings: []const projection.Binding,
    ) RoleBindingError!RoleBindings {
        var result: RoleBindings = .{};
        for (bindings) |binding| {
            if (result.get(binding.role) != null) {
                return error.DuplicateRoleBinding;
            }
            if (result.len == result.entries.len) {
                return error.TooManyRoleBindings;
            }
            result.entries[result.len] = RoleRevisionBinding.capture(binding);
            result.len += 1;
        }
        return result;
    }

    pub fn slice(self: *const RoleBindings) []const RoleRevisionBinding {
        return self.entries[0..self.len];
    }

    pub fn get(
        self: *const RoleBindings,
        role: ids.Role,
    ) ?*const RoleRevisionBinding {
        for (self.slice()) |*binding| {
            if (binding.role == role) return binding;
        }
        return null;
    }
};

pub const Error = compose.Error || RoleBindingError || error{
    WrongFormRevision,
    InvalidTransaction,
};

/// Wraps the existing lifecycle state without dropping the recurring identity
/// or the immutable role bindings during a state transition.
pub fn EditingDraft(comptime Payload: type) type {
    return struct {
        const Self = @This();

        period: RecurringQuarter,
        role_bindings: RoleBindings,
        state: lifecycle.Editing(Payload),

        pub fn snapshot(self: *const Self) *const projection.Snapshot {
            return &self.state.snapshot;
        }

        pub fn prepare(
            self: Self,
            evidence: lifecycle.ValidationEvidence,
        ) PreparedDraft(Payload) {
            return .{
                .period = self.period,
                .role_bindings = self.role_bindings,
                .state = self.state.prepare(evidence),
            };
        }
    };
}

pub fn PreparedDraft(comptime Payload: type) type {
    return struct {
        const Self = @This();

        period: RecurringQuarter,
        role_bindings: RoleBindings,
        state: lifecycle.Prepared(Payload),

        pub fn queue(
            self: Self,
            evidence: lifecycle.QueueEvidence,
        ) QueuedDraft(Payload) {
            return .{
                .period = self.period,
                .role_bindings = self.role_bindings,
                .state = self.state.queue(evidence),
            };
        }
    };
}

pub fn QueuedDraft(comptime Payload: type) type {
    return struct {
        const Self = @This();

        period: RecurringQuarter,
        role_bindings: RoleBindings,
        state: lifecycle.Queued(Payload),

        pub fn acknowledge(
            self: Self,
            outcome: lifecycle.Outcome,
        ) AcknowledgedDraft(Payload) {
            return .{
                .period = self.period,
                .role_bindings = self.role_bindings,
                .state = self.state.acknowledge(outcome),
            };
        }
    };
}

pub fn AcknowledgedDraft(comptime Payload: type) type {
    return struct {
        period: RecurringQuarter,
        role_bindings: RoleBindings,
        state: lifecycle.Acknowledged(Payload),
    };
}

pub fn CreationResult(comptime Payload: type) type {
    return union(enum) {
        accepted: EditingDraft(Payload),
        rejected: compose.Rejection,
    };
}

pub const Create2551QResult = CreationResult(form_2551q.Transaction);
pub const Create1701QResult = CreationResult(form_1701q.Transaction);

/// Qualifies and snapshots the exact 2551Q reusable filer header.
///
/// ATC and percentage rates live only in `transaction.schedule_lines`.
pub fn create2551Q(
    draft_id: ids.DraftId,
    intent: lifecycle.Intent,
    filer: *const model.ProfileRevision,
    profile_as_of: model.Date,
    transaction: form_2551q.Transaction,
) Error!Create2551QResult {
    const bindings = [_]projection.Binding{
        .{ .role = .filer, .revision = filer },
    };
    const result = try form_2551q.composeProfiles(&bindings, profile_as_of);
    return switch (result) {
        .rejected => |rejection| .{ .rejected = rejection },
        .accepted => |snapshot| .{ .accepted = .{
            .period = RecurringQuarter.for2551Q(transaction.quarter),
            .role_bindings = try RoleBindings.from(&bindings),
            .state = try form_2551q.beginEditing(
                draft_id,
                intent,
                snapshot,
                transaction,
            ),
        } },
    };
}

/// Qualifies and snapshots the required filer plus an optional named spouse.
///
/// The form composer enforces that the two named roles cannot use the same
/// profile, even if they point at different revision values in memory.
pub fn create1701Q(
    draft_id: ids.DraftId,
    intent: lifecycle.Intent,
    filer: *const model.ProfileRevision,
    spouse: ?*const model.ProfileRevision,
    profile_as_of: model.Date,
    transaction: form_1701q.Transaction,
) Error!Create1701QResult {
    var binding_storage: [2]projection.Binding = undefined;
    binding_storage[0] = .{ .role = .filer, .revision = filer };
    var binding_len: usize = 1;
    if (spouse) |revision| {
        binding_storage[1] = .{ .role = .spouse, .revision = revision };
        binding_len = 2;
    }
    const bindings = binding_storage[0..binding_len];

    const result = try form_1701q.composeProfiles(bindings, profile_as_of);
    return switch (result) {
        .rejected => |rejection| .{ .rejected = rejection },
        .accepted => |snapshot| .{ .accepted = .{
            .period = RecurringQuarter.for1701Q(transaction.period),
            .role_bindings = try RoleBindings.from(bindings),
            .state = try form_1701q.beginEditing(
                draft_id,
                intent,
                snapshot,
                transaction,
            ),
        } },
    };
}

/// Applies an explicitly supplied policy rate. The denominator converts basis
/// points to a ratio; no tax-policy rate is embedded in the runtime.
pub fn calculate2551QPercentageTax(
    tax_base: Money,
    rate: form_2551q.TaxRate,
) money.Error!Money {
    return tax_base.checkedRatio(@intCast(rate.basis_points), 10_000);
}

pub fn make2551QScheduleLine(
    atc: field.Atc,
    tax_base: Money,
    rate: form_2551q.TaxRate,
) money.Error!form_2551q.ScheduleLine {
    return .{
        .atc = atc,
        .tax_base = tax_base,
        .rate = rate,
        .percentage_tax_due = try calculate2551QPercentageTax(
            tax_base,
            rate,
        ),
    };
}

const ExampleRevisionOptions = struct {
    profile_id: []const u8,
    revision_id: []const u8,
    sequence: u32,
    effective_from: []const u8,
    effective_until: ?[]const u8 = null,
    tin: []const u8,
    name: []const u8,
    email: ?[]const u8 = "person@example.ph",
};

fn exampleIndividualRevision(
    options: ExampleRevisionOptions,
) !model.ProfileRevision {
    return .{
        .profile_id = try model.ProfileId.parse(options.profile_id),
        .id = try model.RevisionId.parse(options.revision_id),
        .sequence = options.sequence,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso(options.effective_from),
            if (options.effective_until) |until|
                try model.Date.parseIso(until)
            else
                null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse(options.tin),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("1 Taxpayer Street"),
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = if (options.email) |email|
                try field.EmailAddress.parse(email)
            else
                null,
        },
        .subject = .{ .individual = .{
            .name = try field.TaxpayerName.parse(options.name),
            .date_of_birth = try model.Date.parseIso("1995-06-01"),
            .citizenship = try field.Citizenship.parse("Filipino"),
        } },
    };
}

fn transaction2551Q(
    lines: []const form_2551q.ScheduleLine,
    year: u16,
    quarter: u8,
) !form_2551q.Transaction {
    var total = Money.zero;
    for (lines) |line| {
        total = try total.checkedAdd(line.percentage_tax_due);
    }
    return .{
        .period_basis = .calendar,
        .year_end_month = 12,
        .quarter = try field.Quarter.init(year, quarter),
        .sheets_attached = 0,
        .tax_relief = .none,
        .income_tax_rate_election = .graduated,
        .schedule_lines = lines,
        .total_percentage_tax_due = total,
        .credits = .{
            .creditable_percentage_tax_withheld = .zero,
            .paid_in_previous_return = .zero,
            .other_credit_or_payment = .zero,
        },
        .tax_payable_or_overpayment = total,
        .additions = .{
            .surcharge = .zero,
            .interest = .zero,
            .compromise = .zero,
        },
        .overpayment_disposition = .not_applicable,
    };
}

fn transaction1701Q(
    year: u16,
    quarter: u8,
) !form_1701q.Transaction {
    return .{
        .period = try form_1701q.FilingQuarter.init(year, quarter),
        .sheets_attached = 0,
        .computation = .{ .graduated = .{
            .sales_revenues_receipts = Money.fromCentavos(10_000_000),
            .cost_of_sales_or_services = Money.zero,
            .allowable_deductions = Money.zero,
            .taxable_income = Money.fromCentavos(10_000_000),
            .income_tax_due = Money.fromCentavos(500_000),
        } },
        .credits = .{
            .prior_quarter_income_tax_payments = Money.zero,
            .creditable_tax_withheld_2307 = Money.zero,
            .other_tax_credits_or_payments = Money.zero,
        },
        .tax_payable_or_overpayment = Money.fromCentavos(500_000),
        .additions = .{
            .surcharge = Money.zero,
            .interest = Money.zero,
            .compromise = Money.zero,
        },
    };
}

test "2551Q draft owns exactly seven filer facts and revision provenance" {
    var revision = try exampleIndividualRevision(.{
        .profile_id = "profile-filer",
        .revision_id = "revision-1",
        .sequence = 1,
        .effective_from = "2026-01-01",
        .tin = "123-456-789-000",
        .name = "JUAN DELA CRUZ",
    });
    const line = try make2551QScheduleLine(
        try field.Atc.parse("PT010"),
        Money.fromCentavos(45_000_000),
        try form_2551q.TaxRate.init(300),
    );
    const lines = [_]form_2551q.ScheduleLine{line};
    const result = try create2551Q(
        try ids.DraftId.parse("draft-2551q-2026-q1"),
        .original,
        &revision,
        try model.Date.parseIso("2026-03-31"),
        try transaction2551Q(&lines, 2026, 1),
    );
    const draft = result.accepted;

    try std.testing.expectEqual(@as(u8, 7), draft.snapshot().len);
    try std.testing.expectEqual(@as(u8, 1), draft.role_bindings.len);
    try std.testing.expectEqual(ids.Role.filer, draft.role_bindings.slice()[0].role);
    try std.testing.expectEqual(@as(u16, 2026), draft.period.tax_year);
    try std.testing.expectEqual(@as(u8, 1), draft.period.quarter);

    for (draft.snapshot().slice()) |entry| {
        try std.testing.expectEqual(ids.Role.filer, entry.role);
        try std.testing.expect(entry.value.field() != .atc);
        try std.testing.expectEqualStrings(
            "revision-1",
            entry.provenance.revision_id.asSlice(),
        );
    }
    try std.testing.expectEqualStrings(
        "PT010",
        draft.state.payload.schedule_lines[0].atc.asSlice(),
    );
}

test "later profile revisions cannot mutate an existing recurring draft" {
    var first = try exampleIndividualRevision(.{
        .profile_id = "profile-filer",
        .revision_id = "revision-1",
        .sequence = 1,
        .effective_from = "2026-01-01",
        .effective_until = "2026-03-31",
        .tin = "123-456-789-000",
        .name = "JUAN DELA CRUZ",
    });
    const line = try make2551QScheduleLine(
        try field.Atc.parse("PT010"),
        Money.fromCentavos(10_000_000),
        try form_2551q.TaxRate.init(300),
    );
    const lines = [_]form_2551q.ScheduleLine{line};
    const first_result = try create2551Q(
        try ids.DraftId.parse("draft-2551q-2026-q1"),
        .original,
        &first,
        try model.Date.parseIso("2026-03-31"),
        try transaction2551Q(&lines, 2026, 1),
    );
    const first_draft = first_result.accepted;

    var later = try exampleIndividualRevision(.{
        .profile_id = "profile-filer",
        .revision_id = "revision-2",
        .sequence = 2,
        .effective_from = "2026-04-01",
        .tin = "123-456-789-000",
        .name = "JUAN DELA CRUZ UPDATED",
    });
    const later_result = try create2551Q(
        try ids.DraftId.parse("draft-2551q-2026-q2"),
        .original,
        &later,
        try model.Date.parseIso("2026-06-30"),
        try transaction2551Q(&lines, 2026, 2),
    );
    const later_draft = later_result.accepted;

    const target = ids.FieldId.initComptime(
        "2551Q.2018-01-ENCS.input.taxpayers_name",
    );
    try std.testing.expectEqualStrings(
        "JUAN DELA CRUZ",
        first_draft.snapshot().get(target).?.value.taxpayer_name.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "revision-1",
        first_draft.snapshot().get(target).?.provenance.revision_id.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "JUAN DELA CRUZ UPDATED",
        later_draft.snapshot().get(target).?.value.taxpayer_name.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "revision-2",
        later_draft.snapshot().get(target).?.provenance.revision_id.asSlice(),
    );
}

test "2551Q rejects a profile missing a required reusable capability" {
    var incomplete = try exampleIndividualRevision(.{
        .profile_id = "profile-incomplete",
        .revision_id = "revision-1",
        .sequence = 1,
        .effective_from = "2026-01-01",
        .tin = "123-456-789-000",
        .name = "INCOMPLETE FILER",
        .email = null,
    });
    const line = try make2551QScheduleLine(
        try field.Atc.parse("PT010"),
        Money.fromCentavos(10_000_000),
        try form_2551q.TaxRate.init(300),
    );
    const lines = [_]form_2551q.ScheduleLine{line};
    const result = try create2551Q(
        try ids.DraftId.parse("draft-incomplete"),
        .original,
        &incomplete,
        try model.Date.parseIso("2026-03-31"),
        try transaction2551Q(&lines, 2026, 1),
    );
    const rejection = result.rejected;

    try std.testing.expectEqual(@as(u8, 1), rejection.len);
    const issue = rejection.slice()[0].qualification;
    try std.testing.expectEqual(
        field.ReusableField.email_address,
        issue.missing_required_field.reusable_field,
    );
}

test "1701Q accepts an omitted spouse and captures an optional named spouse" {
    var filer = try exampleIndividualRevision(.{
        .profile_id = "profile-filer",
        .revision_id = "revision-filer",
        .sequence = 1,
        .effective_from = "2026-01-01",
        .tin = "123-456-789-000",
        .name = "JUAN DELA CRUZ",
    });
    const no_spouse_result = try create1701Q(
        try ids.DraftId.parse("draft-1701q-no-spouse"),
        .original,
        &filer,
        null,
        try model.Date.parseIso("2026-03-31"),
        try transaction1701Q(2026, 1),
    );
    const no_spouse = no_spouse_result.accepted;
    try std.testing.expectEqual(@as(u8, 1), no_spouse.role_bindings.len);
    try std.testing.expect(no_spouse.role_bindings.get(.spouse) == null);
    try std.testing.expectEqual(@as(u8, 7), no_spouse.snapshot().len);

    var spouse = try exampleIndividualRevision(.{
        .profile_id = "profile-spouse",
        .revision_id = "revision-spouse",
        .sequence = 1,
        .effective_from = "2026-01-01",
        .tin = "987-654-321-000",
        .name = "ANA DELA CRUZ",
    });
    const with_spouse_result = try create1701Q(
        try ids.DraftId.parse("draft-1701q-with-spouse"),
        .original,
        &filer,
        &spouse,
        try model.Date.parseIso("2026-03-31"),
        try transaction1701Q(2026, 1),
    );
    const with_spouse = with_spouse_result.accepted;
    try std.testing.expectEqual(@as(u8, 2), with_spouse.role_bindings.len);
    try std.testing.expect(with_spouse.role_bindings.get(.spouse) != null);
    try std.testing.expectEqual(@as(u8, 10), with_spouse.snapshot().len);
}

test "1701Q rejects the same profile in filer and spouse roles" {
    var filer = try exampleIndividualRevision(.{
        .profile_id = "profile-filer",
        .revision_id = "revision-filer",
        .sequence = 1,
        .effective_from = "2026-01-01",
        .tin = "123-456-789-000",
        .name = "JUAN DELA CRUZ",
    });
    const result = try create1701Q(
        try ids.DraftId.parse("draft-1701q-duplicate"),
        .original,
        &filer,
        &filer,
        try model.Date.parseIso("2026-03-31"),
        try transaction1701Q(2026, 1),
    );
    const rejection = result.rejected;

    try std.testing.expectEqual(@as(u8, 1), rejection.len);
    try std.testing.expectEqual(
        compose.Issue.same_profile_in_distinct_roles,
        std.meta.activeTag(rejection.slice()[0]),
    );
}

test "externally supplied 2551Q rates change the computed amount" {
    const tax_base = Money.fromCentavos(45_000_000);
    const atc = try field.Atc.parse("PT010");
    const three_percent = try make2551QScheduleLine(
        atc,
        tax_base,
        try form_2551q.TaxRate.init(300),
    );
    const five_percent = try make2551QScheduleLine(
        atc,
        tax_base,
        try form_2551q.TaxRate.init(500),
    );

    try std.testing.expectEqual(
        @as(i64, 1_350_000),
        three_percent.percentage_tax_due.centavos,
    );
    try std.testing.expectEqual(
        @as(i64, 2_250_000),
        five_percent.percentage_tax_due.centavos,
    );
    try std.testing.expect(
        three_percent.percentage_tax_due.centavos !=
            five_percent.percentage_tax_due.centavos,
    );
}

test "runtime wrapper preserves bindings through coarse lifecycle states" {
    var filer = try exampleIndividualRevision(.{
        .profile_id = "profile-filer",
        .revision_id = "revision-filer",
        .sequence = 1,
        .effective_from = "2026-01-01",
        .tin = "123-456-789-000",
        .name = "JUAN DELA CRUZ",
    });
    const result = try create1701Q(
        try ids.DraftId.parse("draft-1701q-lifecycle"),
        .original,
        &filer,
        null,
        try model.Date.parseIso("2026-03-31"),
        try transaction1701Q(2026, 1),
    );
    const prepared = result.accepted.prepare(.{
        .validated_on = try model.Date.parseIso("2026-04-24"),
        .policy_revision = ids.RevisionLabel.initComptime("rules-2026-q1"),
    });
    const queued = prepared.queue(.{
        .queued_on = try model.Date.parseIso("2026-04-25"),
        .queue_reference = try ids.FilingId.parse("queue-1701q-q1"),
    });
    const acknowledged = queued.acknowledge(.{ .accepted = .{
        .acknowledged_on = try model.Date.parseIso("2026-04-25"),
        .acknowledgement_reference = try ids.FilingId.parse("ack-1701q-q1"),
    } });

    try std.testing.expectEqual(@as(u8, 1), acknowledged.role_bindings.len);
    try std.testing.expectEqual(@as(u16, 2026), acknowledged.period.tax_year);
    try std.testing.expectEqualStrings(
        "revision-filer",
        acknowledged.state.snapshot.slice()[0]
            .provenance.revision_id.asSlice(),
    );
}
