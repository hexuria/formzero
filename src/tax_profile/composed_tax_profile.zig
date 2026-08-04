//! Pure composed Tax Profile read model and layered readiness.
//!
//! Persistence ownership stays explicit: the returned view retains the
//! effective base revision, normalized Registration aggregate, annual
//! income-tax election event, Tax Form Profile values, and derived filing
//! context as separate members.  Readiness is recomputed from those owners on
//! every `compose` call; no layer can hide or overwrite another layer's
//! missing facts.

const std = @import("std");
const catalog = @import("../forms/generated/catalog.zig");
const filing_period = @import("../forms/filing_period.zig");
const field = @import("field.zig");
const model = @import("model.zig");
const capability = @import("capability.zig");
const registration = @import("registration.zig");
const annual_election = @import("annual_income_tax_election.zig");
const tax_form_profile = @import("tax_form_profile.zig");
const tax_form_profile_ui = @import("tax_form_profile_ui.zig");

/// Stable Registration identity for the one business activity surfaced by
/// the complete Base Tax Profile editor. Additional activities remain owned
/// by Registration & Forms and must never make the primary value ambiguous.
pub const primary_business_activity_anchor = "primary";

pub const Error = error{
    InvalidTaxYear,
    UnknownForm,
    WrongFormRevision,
    WrongBaseProfileOwner,
    WrongRegistrationOwner,
    WrongAnnualElectionOwner,
    WrongAnnualElectionTaxYear,
    WrongTaxFormProfileOwner,
    WrongTaxFormProfileTaxYear,
    WrongTaxFormProfileForm,
};

/// One vocabulary is sufficient for every layer while preserving the
/// distinctions that matter to users. `reserved` and `locked` are successful
/// annual lifecycle states, not aliases for generic readiness.
pub const LayerStatus = enum {
    not_applicable,
    unresolved,
    ready,
    reserved,
    locked,
    review_required,
    invalid,
};

fn ReadinessLayer(comptime Key: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        status: LayerStatus = .not_applicable,
        missing: [capacity]Key = undefined,
        missing_count: usize = 0,

        pub fn missingKeys(self: *const Self) []const Key {
            return self.missing[0..self.missing_count];
        }

        pub fn contains(self: *const Self, key: Key) bool {
            for (self.missingKeys()) |existing| {
                if (std.meta.eql(existing, key)) return true;
            }
            return false;
        }

        fn addMissing(self: *Self, key: Key) void {
            if (self.contains(key)) return;
            if (self.missing_count == self.missing.len) return;
            self.missing[self.missing_count] = key;
            self.missing_count += 1;
        }

        fn finishMissing(self: *Self) void {
            if (self.status == .invalid or self.status == .review_required or
                self.status == .reserved or self.status == .locked)
            {
                return;
            }
            self.status = if (self.missing_count == 0) .ready else .unresolved;
        }

        pub fn satisfied(self: *const Self) bool {
            return self.status == .ready or self.status == .not_applicable or
                self.status == .locked;
        }
    };
}

/// Profile keys are the canonical reusable-field vocabulary already used by
/// exact form specs and projections.
pub const BaseTaxProfileReadiness = ReadinessLayer(field.ReusableField, 32);

pub const FormSpecificSemanticKey = struct {
    role: catalog.Role,
    semantic_key: catalog.TaxFormProfileSemanticKey,
};

pub const RegistrationSemanticKey = union(enum) {
    primary_business_activity,
    percentage_tax_registration,
    not_vat_registered,
    eopt_tier,
    form_binding: FormSpecificSemanticKey,
};

pub const RegistrationReadiness = ReadinessLayer(
    RegistrationSemanticKey,
    32,
);

pub const AnnualSemanticKey = enum {
    eligibility,
    income_tax_rate_election,
    initial_applicable_quarter,
};

pub const AnnualElectionReadiness = ReadinessLayer(AnnualSemanticKey, 8);
pub const FormSpecificReadiness = ReadinessLayer(
    FormSpecificSemanticKey,
    32,
);

pub const FilingContextSemanticKey = enum {
    tax_year,
    filing_period,
    quarter,
    return_period_start,
    return_period_end,
};

pub const FilingContextReadiness = ReadinessLayer(
    FilingContextSemanticKey,
    8,
);

pub const ComposedReadiness = struct {
    base_tax_profile: BaseTaxProfileReadiness = .{},
    registration_bindings: RegistrationReadiness = .{},
    annual_income_tax_election: AnnualElectionReadiness = .{},
    form_specific_values: FormSpecificReadiness = .{},
    filing_context: FilingContextReadiness = .{},

    /// Whether a new filing may proceed. A reserved election belongs to an
    /// already queued filing and therefore does not authorize another one.
    pub fn readyForNewFiling(self: *const ComposedReadiness) bool {
        return self.base_tax_profile.satisfied() and
            self.registration_bindings.satisfied() and
            self.form_specific_values.satisfied() and
            self.filing_context.satisfied() and
            (self.annual_income_tax_election.status == .not_applicable or
                self.annual_income_tax_election.status == .ready or
                self.annual_income_tax_election.status == .locked);
    }
};

/// Filing identity plus calendar-period dates derived at the composition
/// boundary. On-demand occurrences intentionally have no invented start/end
/// dates.
pub const DerivedFilingContext = struct {
    period: filing_period.FilingPeriod,
    return_period_start: ?model.Date,
    return_period_end: ?model.Date,

    pub fn effectiveOn(self: DerivedFilingContext) model.Date {
        return self.return_period_end orelse switch (self.period) {
            .on_demand => |value| model.Date.init(
                value.tax_year,
                1,
                1,
            ) catch unreachable,
            else => unreachable,
        };
    }
};

pub const BaseTaxProfileView = struct {
    revision: ?*const model.ProfileRevision,
};

pub const RegistrationView = struct {
    aggregate: ?*const registration.RegistrationAggregate,
    summary: ?registration.RegistrationSummary = null,
    primary_business_activity: ?*const registration.BusinessActivity = null,
    business_commencement: ?model.Date = null,
    eopt_tier: ?*const registration.EoptTierRevision = null,
};

pub const AnnualElectionView = struct {
    history: ?*const annual_election.History,
    current: ?*const annual_election.Event,
};

pub const FormSpecificView = struct {
    state: ?*const tax_form_profile_ui.State,
    values: []const tax_form_profile.SetupValue,
};

pub const ComposedTaxProfile = struct {
    form: *const catalog.FormDefinition,
    profile_id: model.ProfileId,
    tax_year: u16,
    base_tax_profile: BaseTaxProfileView,
    registration: RegistrationView,
    annual_income_tax_election: AnnualElectionView,
    form_specific: FormSpecificView,
    filing_context: ?DerivedFilingContext,
    readiness: ComposedReadiness,

    /// A candidate is usable only in the initial applicable quarter. Later
    /// periods require the shared election to have reached its immutable lock.
    pub fn readyForNewFiling(self: *const ComposedTaxProfile) bool {
        if (!self.readiness.readyForNewFiling()) return false;
        const current = self.annual_income_tax_election.current orelse
            return self.readiness.annual_income_tax_election.status ==
                .not_applicable;
        if (current.state != .candidate) return current.state == .confirmed;
        const context = self.filing_context orelse return false;
        const quarter = context.period.quarter() orelse return false;
        return quarter == current.initial_applicable_quarter;
    }
};

pub const ComposeInput = struct {
    profile_id: model.ProfileId,
    tax_year: u16,
    form_code: []const u8,
    form_revision: ?[]const u8 = null,
    base_revision: ?*const model.ProfileRevision = null,
    registration_aggregate: ?*const registration.RegistrationAggregate = null,
    annual_income_tax_election: ?*const annual_election.History = null,
    tax_form_profile_state: ?*const tax_form_profile_ui.State = null,
    filing_period: ?filing_period.FilingPeriod = null,
};

pub fn compose(input: ComposeInput) Error!ComposedTaxProfile {
    if (input.tax_year == 0 or input.tax_year > 9999) {
        return error.InvalidTaxYear;
    }
    const form = catalog.findForm(input.form_code) orelse
        return error.UnknownForm;
    if (input.form_revision) |wanted| {
        const actual = form.revision orelse return error.WrongFormRevision;
        if (!std.mem.eql(u8, wanted, actual)) return error.WrongFormRevision;
    }
    if (input.base_revision) |revision| {
        if (!revision.profile_id.eql(&input.profile_id)) {
            return error.WrongBaseProfileOwner;
        }
    }
    if (input.registration_aggregate) |aggregate| {
        if (!aggregate.profile_id.eql(&input.profile_id)) {
            return error.WrongRegistrationOwner;
        }
    }
    if (input.annual_income_tax_election) |history| {
        if (!history.stream.profile_id.eql(&input.profile_id)) {
            return error.WrongAnnualElectionOwner;
        }
        if (history.stream.tax_year != input.tax_year) {
            return error.WrongAnnualElectionTaxYear;
        }
    }
    try validateTaxFormProfileOwner(form, input);

    var readiness: ComposedReadiness = .{};
    const context = deriveFilingContext(form, input, &readiness.filing_context);
    const effective_on = if (context) |value|
        value.effectiveOn()
    else
        model.Date.init(input.tax_year, 1, 1) catch unreachable;

    composeBaseReadiness(
        form,
        input.base_revision,
        effective_on,
        &readiness.base_tax_profile,
    );

    const form_values = currentFormSpecificValues(input.tax_form_profile_state);
    composeFormSpecificReadiness(
        form,
        input.tax_form_profile_state,
        form_values,
        &readiness.form_specific_values,
    );

    var registration_view = RegistrationView{
        .aggregate = input.registration_aggregate,
    };
    composeRegistrationReadiness(
        form,
        input.base_revision,
        input.registration_aggregate,
        form_values,
        effective_on,
        &registration_view,
        &readiness.registration_bindings,
    );

    var current_annual: ?*const annual_election.Event = null;
    composeAnnualReadiness(
        form,
        input.base_revision,
        input.annual_income_tax_election,
        registration_view.business_commencement,
        &current_annual,
        &readiness.annual_income_tax_election,
    );

    return .{
        .form = form,
        .profile_id = input.profile_id,
        .tax_year = input.tax_year,
        .base_tax_profile = .{ .revision = input.base_revision },
        .registration = registration_view,
        .annual_income_tax_election = .{
            .history = input.annual_income_tax_election,
            .current = current_annual,
        },
        .form_specific = .{
            .state = input.tax_form_profile_state,
            .values = form_values,
        },
        .filing_context = context,
        .readiness = readiness,
    };
}

fn validateTaxFormProfileOwner(
    form: *const catalog.FormDefinition,
    input: ComposeInput,
) Error!void {
    const state = input.tax_form_profile_state orelse return;
    const identity = state.viewedIdentity() orelse return;
    if (!identity.profile_id.eql(&input.profile_id)) {
        return error.WrongTaxFormProfileOwner;
    }
    if (identity.tax_year != input.tax_year) {
        return error.WrongTaxFormProfileTaxYear;
    }
    if (!std.mem.eql(u8, identity.formCode(), form.code)) {
        return error.WrongTaxFormProfileForm;
    }
}

fn composeBaseReadiness(
    form: *const catalog.FormDefinition,
    revision: ?*const model.ProfileRevision,
    effective_on: model.Date,
    result: *BaseTaxProfileReadiness,
) void {
    result.* = .{ .status = .ready };
    const provided = if (revision) |value| blk: {
        value.validate() catch {
            result.status = .invalid;
            return;
        };
        if (!value.isEffective(effective_on)) {
            result.status = .invalid;
            return;
        }
        break :blk capability.provided(value);
    } else field.FieldSet.empty;

    for (form.fields) |definition| {
        if (definition.provenance != .profile or
            definition.role != .filer or
            definition.profile_presence != .required)
        {
            continue;
        }
        const raw_key = definition.profile_key orelse continue;
        const key = std.meta.stringToEnum(
            field.ReusableField,
            raw_key,
        ) orelse continue;
        if (!provided.contains(key)) result.addMissing(key);
    }
    result.finishMissing();
}

fn currentFormSpecificValues(
    state: ?*const tax_form_profile_ui.State,
) []const tax_form_profile.SetupValue {
    const value = state orelse return &.{};
    return if (value.page() == .editing)
        value.draftValues()
    else
        value.baselineValues();
}

fn composeFormSpecificReadiness(
    form: *const catalog.FormDefinition,
    state: ?*const tax_form_profile_ui.State,
    values: []const tax_form_profile.SetupValue,
    result: *FormSpecificReadiness,
) void {
    result.* = .{};
    if (form.tax_form_profile.mode != .setup) return;
    result.status = .ready;
    if (state != null and state.?.page() == null) {
        result.status = .invalid;
        return;
    }
    const runtime_requires_conditional = if (state) |value|
        value.annual_setup_required
    else
        false;
    for (form.tax_form_profile.values) |definition| {
        if (definition.availability != .supported) continue;
        const required = definition.presence == .required or
            (definition.presence == .conditional and
                runtime_requires_conditional);
        if (!required) continue;
        if (tax_form_profile.findValue(
            values,
            definition.role,
            definition.semantic_key,
        ) == null) {
            result.addMissing(.{
                .role = definition.role,
                .semantic_key = definition.semantic_key,
            });
        }
    }
    if (state) |value| {
        if (value.conflict != null) {
            result.status = .invalid;
            return;
        }
        if (value.annualReadiness().review_required) {
            result.status = .review_required;
            return;
        }
    }
    result.finishMissing();
}

fn composeRegistrationReadiness(
    form: *const catalog.FormDefinition,
    base_revision: ?*const model.ProfileRevision,
    aggregate: ?*const registration.RegistrationAggregate,
    form_values: []const tax_form_profile.SetupValue,
    effective_on: model.Date,
    view: *RegistrationView,
    result: *RegistrationReadiness,
) void {
    result.* = .{ .status = .ready };
    const normalized = aggregate orelse {
        addRegistrationRequirementsWithoutAggregate(form, base_revision, result);
        for (form_values) |value| {
            if (isRegistrationBinding(form, value)) {
                result.addMissing(.{ .form_binding = .{
                    .role = value.role,
                    .semantic_key = value.semantic_key,
                } });
            }
        }
        result.finishMissing();
        return;
    };
    normalized.validate() catch {
        result.status = .invalid;
        return;
    };

    view.summary = normalized.derivedSummary(effective_on) catch {
        result.status = .invalid;
        return;
    };
    const eopt = normalized.resolveEoptTier(effective_on) catch {
        result.status = .invalid;
        return;
    };
    view.eopt_tier = eopt.confirmed;
    resolvePrimaryBusinessActivity(normalized, effective_on, view, result);

    if (std.mem.eql(u8, form.code, "2551Q")) {
        if (view.primary_business_activity == null) {
            result.addMissing(.primary_business_activity);
        }
        const summary = view.summary.?;
        if (!summary.percentage_tax.confirmed_registered) {
            result.addMissing(.percentage_tax_registration);
        }
        if (summary.vat.confirmed_registered) {
            result.status = .invalid;
            return;
        }
    }

    resolveFormRegistrationBindings(
        form,
        normalized,
        form_values,
        effective_on,
        result,
    );
    if (result.status != .invalid) result.finishMissing();
}

fn addRegistrationRequirementsWithoutAggregate(
    form: *const catalog.FormDefinition,
    base_revision: ?*const model.ProfileRevision,
    result: *RegistrationReadiness,
) void {
    _ = base_revision;
    if (std.mem.eql(u8, form.code, "2551Q")) {
        result.addMissing(.primary_business_activity);
        result.addMissing(.percentage_tax_registration);
    }
}

fn resolvePrimaryBusinessActivity(
    aggregate: *const registration.RegistrationAggregate,
    effective_on: model.Date,
    view: *RegistrationView,
    result: *RegistrationReadiness,
) void {
    var earliest: ?model.Date = null;
    for (aggregate.business_activities) |*activity| {
        if (!activity.metadata.review.isConfirmed()) continue;
        if (earliest == null or
            activity.metadata.effective.from.isBefore(earliest.?))
        {
            earliest = activity.metadata.effective.from;
        }
        if (!activity.metadata.isEffective(effective_on)) continue;
        if (std.mem.eql(
            u8,
            activity.anchor_id.asSlice(),
            primary_business_activity_anchor,
        )) {
            view.primary_business_activity = activity;
        }
    }
    view.business_commencement = earliest;
    _ = result;
}

fn isRegistrationBinding(
    form: *const catalog.FormDefinition,
    value: tax_form_profile.SetupValue,
) bool {
    for (form.tax_form_profile.values) |definition| {
        if (definition.role != value.role or
            definition.semantic_key != value.semantic_key)
        {
            continue;
        }
        return definition.source_kind == .business_activity_anchor or
            definition.source_kind == .registration_obligation_anchor;
    }
    return false;
}

fn resolveFormRegistrationBindings(
    form: *const catalog.FormDefinition,
    aggregate: *const registration.RegistrationAggregate,
    values: []const tax_form_profile.SetupValue,
    effective_on: model.Date,
    result: *RegistrationReadiness,
) void {
    for (values) |value| {
        if (value.role != .filer) continue;
        const definition = findFormSpecificDefinition(form, value) orelse
            continue;
        const resolved = switch (definition.source_kind) {
            .business_activity_anchor => blk: {
                const id = switch (value.value) {
                    .business_activity_anchor_id => |anchor| anchor,
                    else => {
                        result.status = .invalid;
                        return;
                    },
                };
                const registration_id = registration.ActivityAnchorId.parse(
                    id.asSlice(),
                ) catch {
                    result.status = .invalid;
                    return;
                };
                const resolution = aggregate.resolveActivity(
                    registration_id,
                    effective_on,
                ) catch {
                    result.status = .invalid;
                    return;
                };
                break :blk resolution.confirmed != null;
            },
            .registration_obligation_anchor => blk: {
                const id = switch (value.value) {
                    .registration_obligation_anchor_id => |anchor| anchor,
                    else => {
                        result.status = .invalid;
                        return;
                    },
                };
                const registration_id = registration.ObligationAnchorId.parse(
                    id.asSlice(),
                ) catch {
                    result.status = .invalid;
                    return;
                };
                const resolution = aggregate.resolveObligation(
                    registration_id,
                    effective_on,
                ) catch {
                    result.status = .invalid;
                    return;
                };
                break :blk resolution.confirmed != null;
            },
            else => continue,
        };
        if (!resolved) result.addMissing(.{ .form_binding = .{
            .role = value.role,
            .semantic_key = value.semantic_key,
        } });
    }
}

fn findFormSpecificDefinition(
    form: *const catalog.FormDefinition,
    value: tax_form_profile.SetupValue,
) ?*const catalog.TaxFormProfileValueDefinition {
    for (form.tax_form_profile.values) |*definition| {
        if (definition.role == value.role and
            definition.semantic_key == value.semantic_key)
        {
            return definition;
        }
    }
    return null;
}

fn composeAnnualReadiness(
    form: *const catalog.FormDefinition,
    revision: ?*const model.ProfileRevision,
    history: ?*const annual_election.History,
    business_commencement: ?model.Date,
    current: *?*const annual_election.Event,
    result: *AnnualElectionReadiness,
) void {
    result.* = .{};
    if (!catalog.consumesTaxpayerYearSetting(
        form,
        .income_tax_rate_election,
    )) return;

    if (history) |events| {
        events.validate() catch {
            result.status = .invalid;
            return;
        };
        if (events.events.len != 0) {
            current.* = &events.events[events.events.len - 1];
            result.status = switch (current.*.?.state) {
                .candidate => .ready,
                .reserved => .reserved,
                .confirmed => .locked,
                .review_required => .review_required,
            };
            if (current.*.?.choice == null) {
                result.addMissing(.income_tax_rate_election);
            }
            return;
        }
    }

    switch (annualEligibility(revision)) {
        .not_applicable => result.status = .not_applicable,
        .requires_review => {
            result.status = .review_required;
            result.addMissing(.eligibility);
        },
        .applicable => {
            result.status = .unresolved;
            result.addMissing(.income_tax_rate_election);
            if (business_commencement == null) {
                result.addMissing(.initial_applicable_quarter);
            }
        },
    }
}

const AnnualEligibility = enum {
    not_applicable,
    applicable,
    requires_review,
};

fn annualEligibility(
    revision: ?*const model.ProfileRevision,
) AnnualEligibility {
    const value = revision orelse return .requires_review;
    return switch (value.subject) {
        .sole_proprietor => .applicable,
        .individual => |person| switch (person.classification) {
            .self_employed, .mixed_income => .applicable,
            .pure_compensation => .not_applicable,
            .classification_unknown => .requires_review,
        },
        .legal_entity => .not_applicable,
    };
}

fn deriveFilingContext(
    form: *const catalog.FormDefinition,
    input: ComposeInput,
    result: *FilingContextReadiness,
) ?DerivedFilingContext {
    result.* = .{ .status = .ready };
    const period = input.filing_period orelse {
        result.addMissing(.tax_year);
        result.addMissing(.filing_period);
        if (form.cadence == .quarterly) {
            result.addMissing(.quarter);
            result.addMissing(.return_period_start);
            result.addMissing(.return_period_end);
        }
        result.finishMissing();
        return null;
    };
    period.validate() catch {
        result.status = .invalid;
        return null;
    };
    if (period.taxYear() != input.tax_year or
        !period.matchesCadence(form.cadence))
    {
        result.status = .invalid;
        return null;
    }

    const dates = datesForPeriod(period) catch {
        result.status = .invalid;
        return null;
    };
    return .{
        .period = period,
        .return_period_start = dates.start,
        .return_period_end = dates.end,
    };
}

const PeriodDates = struct {
    start: ?model.Date,
    end: ?model.Date,
};

fn datesForPeriod(period: filing_period.FilingPeriod) !PeriodDates {
    return switch (period) {
        .monthly => |value| .{
            .start = try model.Date.init(value.tax_year, value.month, 1),
            .end = try model.Date.init(
                value.tax_year,
                value.month,
                lastDayOfMonth(value.tax_year, value.month),
            ),
        },
        .quarterly => |value| blk: {
            const first_month: u8 = (value.quarter - 1) * 3 + 1;
            const last_month = first_month + 2;
            break :blk .{
                .start = try model.Date.init(value.tax_year, first_month, 1),
                .end = try model.Date.init(
                    value.tax_year,
                    last_month,
                    lastDayOfMonth(value.tax_year, last_month),
                ),
            };
        },
        .annual => |value| .{
            .start = try model.Date.init(value.tax_year, 1, 1),
            .end = try model.Date.init(value.tax_year, 12, 31),
        },
        .on_demand => .{ .start = null, .end = null },
    };
}

fn lastDayOfMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (year % 4 == 0 and
            (year % 100 != 0 or year % 400 == 0)) 29 else 28,
        else => 0,
    };
}

fn testProfile(
    profile_id: model.ProfileId,
    include_contact: bool,
) !model.ProfileRevision {
    return .{
        .profile_id = profile_id,
        .id = try model.RevisionId.parse("revision-composed-1"),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-00000"),
            .rdo_code = try field.RdoCode.parse("040"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("Quezon City"),
            .zip_code = if (include_contact)
                try field.ZipCode.parse("1100")
            else
                null,
            .contact_number = if (include_contact)
                try field.ContactNumber.parse("09171234567")
            else
                null,
            .email_address = if (include_contact)
                try field.EmailAddress.parse("taxpayer@example.ph")
            else
                null,
        },
        .subject = .{ .individual = .{
            .name = try field.TaxpayerName.parse("COMPOSED TAXPAYER"),
            .classification = .self_employed,
        } },
    };
}

const RegistrationFixture = struct {
    activity_anchors: [1]registration.ActivityAnchor,
    obligation_anchors: [1]registration.ObligationAnchor,
    activities: [1]registration.BusinessActivity,
    obligations: [1]registration.RegistrationObligation,

    fn aggregate(self: *const RegistrationFixture, profile_id: model.ProfileId) registration.RegistrationAggregate {
        return .{
            .profile_id = profile_id,
            .activity_anchors = &self.activity_anchors,
            .obligation_anchors = &self.obligation_anchors,
            .business_activities = &self.activities,
            .obligations = &self.obligations,
        };
    }
};

fn testRegistration(profile_id: model.ProfileId) !RegistrationFixture {
    const activity_anchor = try registration.ActivityAnchorId.parse(
        primary_business_activity_anchor,
    );
    const obligation_anchor = try registration.ObligationAnchorId.parse(
        "obligation-percentage",
    );
    const effective = try model.EffectivePeriod.init(
        try model.Date.parseIso("2025-05-01"),
        null,
    );
    return .{
        .activity_anchors = .{.{
            .owner_profile_id = profile_id,
            .id = activity_anchor,
        }},
        .obligation_anchors = .{.{
            .owner_profile_id = profile_id,
            .id = obligation_anchor,
        }},
        .activities = .{.{
            .anchor_id = activity_anchor,
            .metadata = .{
                .owner_profile_id = profile_id,
                .revision_id = try registration.ComponentRevisionId.parse(
                    "activity-revision-1",
                ),
                .sequence = 1,
                .effective = effective,
                .source = .manual_entry,
                .review = .{ .confirmed = .{
                    .confirmed_at_unix_seconds = 1_760_000_000,
                } },
            },
            .line_of_business = try field.LineOfBusiness.parse(
                "Professional services",
            ),
        }},
        .obligations = .{.{
            .anchor_id = obligation_anchor,
            .metadata = .{
                .owner_profile_id = profile_id,
                .revision_id = try registration.ComponentRevisionId.parse(
                    "obligation-revision-1",
                ),
                .sequence = 1,
                .effective = effective,
                .source = .manual_entry,
                .review = .{ .confirmed = .{
                    .confirmed_at_unix_seconds = 1_760_000_000,
                } },
            },
            .kind = .{ .percentage_tax = {} },
        }},
    };
}

fn testCandidate(
    profile_id: model.ProfileId,
) !annual_election.Event {
    const stream: annual_election.StreamKey = .{
        .profile_id = profile_id,
        .tax_year = 2026,
    };
    const transition = try annual_election.stageCandidate(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .eight_percent,
        .commencement = .existing_before_tax_year,
        .provenance = .{
            .kind = .form_2551q,
            .form_revision = try annual_election.FormRevision.parse(
                "2018-01-ENCS",
            ),
            .filing_quarter = 1,
        },
        .occurred_at_unix_seconds = 1_760_000_001,
    });
    return transition.append;
}

test "2551Q reports inherited profile gaps independently from annual state" {
    const profile_id = try model.ProfileId.parse("profile-composed");
    const profile = try testProfile(profile_id, false);
    const registration_fixture = try testRegistration(profile_id);
    const aggregate = registration_fixture.aggregate(profile_id);
    const stream: annual_election.StreamKey = .{
        .profile_id = profile_id,
        .tax_year = 2026,
    };
    const empty_history: annual_election.History = .{
        .stream = stream,
        .events = &.{},
    };

    const composed = try compose(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .form_revision = "2018-01-ENCS",
        .base_revision = &profile,
        .registration_aggregate = &aggregate,
        .annual_income_tax_election = &empty_history,
        .filing_period = .{ .quarterly = .{
            .tax_year = 2026,
            .quarter = 1,
        } },
    });

    try std.testing.expectEqual(
        LayerStatus.unresolved,
        composed.readiness.base_tax_profile.status,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        composed.readiness.base_tax_profile.missingKeys().len,
    );
    try std.testing.expect(
        composed.readiness.base_tax_profile.contains(.zip_code),
    );
    try std.testing.expect(
        composed.readiness.base_tax_profile.contains(.contact_number),
    );
    try std.testing.expect(
        composed.readiness.base_tax_profile.contains(.email_address),
    );
    try std.testing.expectEqual(
        LayerStatus.unresolved,
        composed.readiness.annual_income_tax_election.status,
    );
    try std.testing.expect(
        composed.readiness.annual_income_tax_election.contains(
            .income_tax_rate_election,
        ),
    );
    try std.testing.expectEqual(
        LayerStatus.ready,
        composed.readiness.registration_bindings.status,
    );
    try std.testing.expectEqual(
        LayerStatus.not_applicable,
        composed.readiness.form_specific_values.status,
    );
    try std.testing.expectEqual(
        LayerStatus.ready,
        composed.readiness.filing_context.status,
    );
}

test "candidate election becomes ready without masking inherited gaps" {
    const profile_id = try model.ProfileId.parse("profile-candidate");
    const profile = try testProfile(profile_id, false);
    const registration_fixture = try testRegistration(profile_id);
    const aggregate = registration_fixture.aggregate(profile_id);
    const candidate = try testCandidate(profile_id);
    const events = [_]annual_election.Event{candidate};
    const history: annual_election.History = .{
        .stream = candidate.stream,
        .events = &events,
    };

    const composed = try compose(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .base_revision = &profile,
        .registration_aggregate = &aggregate,
        .annual_income_tax_election = &history,
        .filing_period = .{ .quarterly = .{
            .tax_year = 2026,
            .quarter = 1,
        } },
    });

    try std.testing.expectEqual(
        LayerStatus.ready,
        composed.readiness.annual_income_tax_election.status,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        composed.readiness.base_tax_profile.missingKeys().len,
    );
    try std.testing.expect(!composed.readyForNewFiling());
}

test "composition boundary immediately observes a corrected base revision" {
    const profile_id = try model.ProfileId.parse("profile-refresh");
    var profile = try testProfile(profile_id, false);
    const registration_fixture = try testRegistration(profile_id);
    const aggregate = registration_fixture.aggregate(profile_id);
    const candidate = try testCandidate(profile_id);
    const events = [_]annual_election.Event{candidate};
    const history: annual_election.History = .{
        .stream = candidate.stream,
        .events = &events,
    };
    const input: ComposeInput = .{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .base_revision = &profile,
        .registration_aggregate = &aggregate,
        .annual_income_tax_election = &history,
        .filing_period = .{ .quarterly = .{
            .tax_year = 2026,
            .quarter = 1,
        } },
    };

    const before = try compose(input);
    try std.testing.expectEqual(
        @as(usize, 3),
        before.readiness.base_tax_profile.missingKeys().len,
    );

    profile.contact.zip_code = try field.ZipCode.parse("1100");
    profile.contact.contact_number = try field.ContactNumber.parse(
        "09171234567",
    );
    profile.contact.email_address = try field.EmailAddress.parse(
        "taxpayer@example.ph",
    );

    const after = try compose(input);
    try std.testing.expectEqual(
        LayerStatus.ready,
        after.readiness.base_tax_profile.status,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        after.readiness.base_tax_profile.missingKeys().len,
    );
    try std.testing.expect(after.readyForNewFiling());
    try std.testing.expectEqual(
        try model.Date.parseIso("2026-01-01"),
        after.filing_context.?.return_period_start.?,
    );
    try std.testing.expectEqual(
        try model.Date.parseIso("2026-03-31"),
        after.filing_context.?.return_period_end.?,
    );
}

test "annual reserved and confirmed states stay distinct" {
    const profile_id = try model.ProfileId.parse("profile-lock-state");
    const profile = try testProfile(profile_id, true);
    const registration_fixture = try testRegistration(profile_id);
    const aggregate = registration_fixture.aggregate(profile_id);
    const stream: annual_election.StreamKey = .{
        .profile_id = profile_id,
        .tax_year = 2026,
    };
    const draft_id = try annual_election.DraftId.parse("draft-q1");
    const reserved_transition = try annual_election.reserve(null, .{
        .stream = stream,
        .expected_current_sequence = 0,
        .choice = .graduated,
        .commencement = .existing_before_tax_year,
        .provenance = .{
            .kind = .form_2551q,
            .form_revision = try annual_election.FormRevision.parse(
                "2018-01-ENCS",
            ),
            .filing_quarter = 1,
            .draft_id = draft_id,
        },
        .occurred_at_unix_seconds = 1_760_000_010,
    });
    const reserved = reserved_transition.append;
    const reserved_events = [_]annual_election.Event{reserved};
    const reserved_history: annual_election.History = .{
        .stream = stream,
        .events = &reserved_events,
    };

    const common: ComposeInput = .{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "2551Q",
        .base_revision = &profile,
        .registration_aggregate = &aggregate,
        .annual_income_tax_election = &reserved_history,
        .filing_period = .{ .quarterly = .{
            .tax_year = 2026,
            .quarter = 1,
        } },
    };
    const reserved_view = try compose(common);
    try std.testing.expectEqual(
        LayerStatus.reserved,
        reserved_view.readiness.annual_income_tax_election.status,
    );
    try std.testing.expect(!reserved_view.readyForNewFiling());

    const confirmed_transition = try annual_election.confirmReservation(
        &reserved,
        .{
            .stream = stream,
            .expected_current_sequence = 1,
            .draft_id = draft_id,
            .occurred_at_unix_seconds = 1_760_000_011,
        },
    );
    const confirmed_events = [_]annual_election.Event{
        reserved,
        confirmed_transition.append,
    };
    const confirmed_history: annual_election.History = .{
        .stream = stream,
        .events = &confirmed_events,
    };
    var confirmed_input = common;
    confirmed_input.annual_income_tax_election = &confirmed_history;
    const locked_view = try compose(confirmed_input);
    try std.testing.expectEqual(
        LayerStatus.locked,
        locked_view.readiness.annual_income_tax_election.status,
    );
    try std.testing.expect(locked_view.readyForNewFiling());
}

test "runtime-required form-specific binding has its own semantic key" {
    const profile_id = try model.ProfileId.parse("profile-form-value");
    const profile = try testProfile(profile_id, true);
    const state = try tax_form_profile_ui.State.open(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "1601C",
        .active = true,
        .activation_period = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            try model.Date.parseIso("2026-12-31"),
        ),
        .annual_setup_required = true,
    });
    const composed = try compose(.{
        .profile_id = profile_id,
        .tax_year = 2026,
        .form_code = "1601C",
        .base_revision = &profile,
        .tax_form_profile_state = &state,
        .filing_period = .{ .monthly = .{
            .tax_year = 2026,
            .month = 1,
        } },
    });

    const key: FormSpecificSemanticKey = .{
        .role = .filer,
        .semantic_key = .business_activity_anchor_id,
    };
    try std.testing.expectEqual(
        LayerStatus.unresolved,
        composed.readiness.form_specific_values.status,
    );
    try std.testing.expect(
        composed.readiness.form_specific_values.contains(key),
    );
    try std.testing.expectEqual(
        LayerStatus.ready,
        composed.readiness.registration_bindings.status,
    );
}
